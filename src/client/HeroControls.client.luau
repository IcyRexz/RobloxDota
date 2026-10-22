--!strict
-- Hero input on this player's device:
--  * shooting (owner 2026-10-20): left mouse (or the HUD's Attack slot; holding
--    repeats at the cooldown) fires the basic attack straight ahead along the
--    crosshair, up to Pulse.Range. Out of range = a miss. Your hero never walks
--    on its own. The swing plays at once on this device, so it feels instant.
--  * red marker = "a click hits this" (owner 2026-10-21). Every frame this
--    device runs the server's own shot rule (Targeting.castShot) along the
--    crosshair; if that would hit an enemy, the marker goes on it and the
--    click fires straight along the crosshair. Only when the straight shot
--    would miss does the aim assist below look for a target.
--  * aim assist (owner 2026-10-20): when an enemy is within shot range (measured
--    exactly like the server's shot: straight-line distance from your head, so
--    an outlined enemy is always reachable; owner 2026-10-21), in
--    line of sight and close to the crosshair (within ASSIST_DEGREES of its
--    body), it gets the red marker (ring + outline) and your shot is aimed
--    straight at it. Move the crosshair away and the marker and the assist
--    turn off. Nearest-to-crosshair wins; the current one is kept a little
--    longer (ASSIST_KEEP_DEGREES) so it does not flicker between two.
-- Aim assist only changes the direction this device sends; the server still
-- casts the shot itself from your hero's head and checks the cooldown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GroundRing = require(ReplicatedStorage.Shared.GroundRing)
local MageAbilities = require(ReplicatedStorage.Shared.MageAbilities)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Pulse = Config.Hero.Pulse
local SWING_ANIMATION = "rbxassetid://522635514" -- Roblox default R15 "tool slash"
local RESEND_SECONDS = 0.15 -- ask the server again at most this often
local ASSIST_DEGREES = 3 -- crosshair this close to an enemy's body turns the assist on
local ASSIST_KEEP_DEGREES = 5 -- ...and it stays on that enemy until this far off
local UNIT_RADIUS = 1.5 -- studs: rough body half-width used for the angle test
local MARKER_COLOR = UiTheme.Enemy -- an enemy you can hit (UI design system)
local ALLY_MARKER_COLOR = UiTheme.Ally -- an ally under the crosshair (owner 2026-10-23)
local MARKER_DASHES = 12
local MARKER_SPIN = math.rad(90) -- degrees per second
-- Players are always on our side; used until the server sets the attribute.
local DEFAULT_TEAM = Config.Teams.Defenders

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local actionEvent = ReplicatedStorage:WaitForChild("HeroAction") :: RemoteEvent

-- The enemy under the red marker, or else the ally under the crosshair
-- (owner 2026-10-23: hover allies to see their health), shared with other
-- scripts on this device (TargetInfo.client shows its face, name and health).
-- Made here, on this device only: it is never sent to or trusted by the server.
local aimValue = Instance.new("ObjectValue")
aimValue.Name = "AimTarget"
aimValue.Parent = player

local function localTeam(): string
	local team = player:GetAttribute("Team")
	return if type(team) == "string" then team else DEFAULT_TEAM
end

-- Assist target -----------------------------------------------------------------

local function isAlive(target: Instance): boolean
	local health = target:GetAttribute("Health")
	return target:IsDescendantOf(Workspace) and type(health) == "number" and health > 0
end

-- Same objective-order lock as the server (shared rule in Targeting).
local function isLocked(target: Instance): boolean
	return Targeting.isLocked(target, isAlive)
end

local function isEnemy(character: Model, target: Instance): boolean
	if target == character or not Targeting.TargetKinds[target:GetAttribute("Kind")] then
		return false
	end
	local team = target:GetAttribute("Team")
	return type(team) == "string" and team ~= localTeam() and isAlive(target) and not isLocked(target)
end

-- The point to aim at: a unit's centre, or the point of a structure's box
-- nearest to where the crosshair line passes it.
local function aimPointFor(target: Instance, eye: Vector3, look: Vector3): Vector3?
	if target:IsA("BasePart") then
		local centre, half = target.Position, target.Size / 2
		local onLine = eye + look * math.max((centre - eye):Dot(look), 0)
		return Vector3.new(
			math.clamp(onLine.X, centre.X - half.X, centre.X + half.X),
			math.clamp(onLine.Y, centre.Y - half.Y, centre.Y + half.Y),
			math.clamp(onLine.Z, centre.Z - half.Z, centre.Z + half.Z)
		)
	end
	local root = Targeting.rootOf(target)
	return if root then root.Position else nil
end

-- Degrees between the crosshair and the target's edge (0 when the crosshair is on it).
local function offAngle(eye: Vector3, look: Vector3, point: Vector3, radius: number): number
	local toPoint = point - eye
	local distance = toPoint.Magnitude
	if distance < 0.01 then
		return 0
	end
	local angle = math.deg(math.acos(math.clamp(look:Dot(toPoint / distance), -1, 1)))
	return math.max(angle - math.deg(math.atan(radius / distance)), 0)
end

type Candidate = { target: Instance, point: Vector3, angle: number }

local assistTarget: Instance? = nil -- the enemy with the red marker
local assistPoint: Vector3? = nil -- where to aim; nil = straight along the crosshair

-- The enemy a shot of `range` studs would go for, and where to aim (nil =
-- straight along the crosshair). `keep` is held a little longer so the choice
-- does not flicker. Used by the basic attack (Pulse.Range).
local function findTarget(character: Model, root: BasePart, range: number, keep: Instance?): (Instance?, Vector3?)
	local camera = Workspace.CurrentCamera
	local eye, look = camera.CFrame.Position, camera.CFrame.LookVector
	-- 1. What a shot straight along the crosshair would hit (the server's rule).
	local direct = Targeting.castShot(character, localTeam(), look, range, function(target)
		return isEnemy(character, target)
	end)
	if direct then
		return direct, nil
	end
	-- 2. Otherwise, aim assist: an enemy near the crosshair. The server casts
	-- from the head, `range` studs long.
	local head = character:FindFirstChild("Head")
	local shotFrom = if head and head:IsA("BasePart") then head.Position else root.Position
	local candidates: { Candidate } = {}
	for _, group in Targeting.candidateGroups() do
		for _, target in group do
			if isEnemy(character, target) then
				local point = aimPointFor(target, eye, look)
				if point and (point - shotFrom).Magnitude <= range then
					local radius = if target:IsA("BasePart") then 0 else UNIT_RADIUS
					local angle = offAngle(eye, look, point, radius)
					local limit = if target == keep then ASSIST_KEEP_DEGREES else ASSIST_DEGREES
					if angle <= limit then
						table.insert(candidates, { target = target, point = point, angle = angle })
					end
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.angle < b.angle
	end)
	-- Line-of-sight checks (raycasts) only for the few that passed, best first.
	for _, candidate in candidates do
		if Targeting.hasLineOfSight(candidate.target, eye, candidate.point) then
			return candidate.target, candidate.point
		end
	end
	return nil, nil
end

-- The basic attack's marker target, refreshed every frame.
local function updateAssist(character: Model, root: BasePart)
	assistTarget, assistPoint = findTarget(character, root, Pulse.Range, assistTarget)
end

-- The ally (unit, hero or building) straight under the crosshair within
-- HealthBarRange of the camera's focus, for the target panel. It gets a green
-- ring (no outline).
local function allyUnderCrosshair(character: Model): Instance?
	local camera = Workspace.CurrentCamera
	local eye, look = camera.CFrame.Position, camera.CFrame.LookVector
	local reach = (camera.Focus.Position - eye).Magnitude + Config.Display.HealthBarRange
	local ignore = Targeting.seeThrough()
	table.insert(ignore, character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local result = Workspace:Spherecast(eye, Targeting.ShotRadius, look * reach, params)
	local owner = result and Targeting.ownerOf(result.Instance)
	if
		owner
		and Targeting.TargetKinds[owner:GetAttribute("Kind")]
		and owner:GetAttribute("Team") == localTeam()
		and isAlive(owner)
	then
		return owner
	end
	return nil
end

-- Marker -----------------------------------------------------------------------

local highlight = Instance.new("Highlight")
highlight.FillTransparency = 1
highlight.OutlineTransparency = 0
highlight.OutlineColor = MARKER_COLOR
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

local marker = Instance.new("Model")
marker.Name = "TargetMarker"
local dashes: { Part } = {}
for i = 1, MARKER_DASHES do
	local dash = Instance.new("Part")
	dash.Name = "Dash" .. i
	dash.Color = MARKER_COLOR
	dash.Material = Enum.Material.Neon
	dash.Anchored = true
	dash.CanCollide = false
	dash.CanQuery = false
	dash.CanTouch = false
	dash.CastShadow = false
	dash.Parent = marker
	table.insert(dashes, dash)
end

local function markerRadius(target: Instance, root: BasePart): number
	if target:IsA("BasePart") then
		return math.max(target.Size.X, target.Size.Z) / 2 + 1.5
	end
	return 2.2 * root.Size.X / 2 -- wider round bigger bodies (a Brute's root is 1.5x)
end

-- Height of a unit's feet: below its root by half the root plus the hip
-- height, both of which grow with the body (so a Brute's ring is on the
-- ground too, not at its waist).
local function feetY(target: Instance, root: BasePart): number
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight else 2
	return root.Position.Y - root.Size.Y / 2 - hip
end

local spin = 0
-- `ally` draws the ring green and without the red outline.
local function drawMarker(target: Instance?, ally: boolean, deltaTime: number)
	local targetRoot = if target and target:IsA("BasePart") then target elseif target then Targeting.rootOf(target) else nil
	if not (target and targetRoot) then
		marker.Parent = nil
		highlight.Parent = nil
		return
	end
	local centre = targetRoot.Position
	local radius = markerRadius(target, targetRoot)
	-- Ring at the target's feet (or the structure's base), so it sits on hills too.
	local groundY = if target:IsA("BasePart") then centre.Y - target.Size.Y / 2 else feetY(target, targetRoot)
	spin += MARKER_SPIN * deltaTime
	local dashLength = 2 * math.pi * radius / MARKER_DASHES * 0.6
	local color = if ally then ALLY_MARKER_COLOR else MARKER_COLOR
	for i, dash in dashes do
		dash.Color = color
		local angle = spin + (i / MARKER_DASHES) * 2 * math.pi
		local position = Vector3.new(centre.X + math.cos(angle) * radius, groundY + 0.1, centre.Z + math.sin(angle) * radius)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		dash.Size = Vector3.new(0.35, 0.05, dashLength)
		dash.CFrame = CFrame.lookAt(position, position + tangent)
	end
	marker.Parent = Workspace
	highlight.Adornee = if ally then nil else target
	highlight.Parent = if ally then nil else playerGui
end

-- Abilities (owner 2026-10-21) -------------------------------------------------------
--  Q Lightning Strike: hold Q to show the area on the ground where you aim
--    (clamped to its range), release to cast there.
--  E Teleport: hold E to show the landing spot where you aim (clamped to its
--    range), release to teleport. The server checks the spot and moves you.
-- Each must be off cooldown (<Ability>ReadyAt on the character). Ability keys do
-- nothing while a menu is open. The Strike area's size includes the
-- Empowered Lightning mastery (MageAbilities, read from this player's
-- Mastery<id> attributes; display only).

local Skills = Config.Hero.Skills
local STRIKE_COLOR = Color3.fromRGB(150, 210, 255) -- the lightning's colour (a world effect)
local LANDING_RADIUS = 2.5 -- studs: the teleport landing marker
local LOCAL_GUARD = 0.3 -- seconds a key ignores repeats until the server's cooldown arrives

type SkillKey = { id: string, range: number }
local SKILL_KEYS: { [Enum.KeyCode]: SkillKey } = {
	[Enum.KeyCode.Q] = { id = "Strike", range = Skills.Strike.Range },
	[Enum.KeyCode.E] = { id = "Teleport", range = Skills.Teleport.Range },
}

local lastCast: { [string]: number } = {}
local aiming: string? = nil -- the ability whose key is held (its marker shows)

local function hasMastery(id: string): boolean
	return player:GetAttribute("Mastery" .. id) == true
end

local function skillReady(character: Model, id: string): boolean
	local readyAt = character:GetAttribute(id .. "ReadyAt")
	if type(readyAt) == "number" and Workspace:GetServerTimeNow() < readyAt then
		return false
	end
	return os.clock() - (lastCast[id] or -math.huge) >= LOCAL_GUARD
end

-- The Character Menu or the Base Upgrades menu is open.
local function menuOpen(): boolean
	for _, name in { "CharacterMenu", "BaseUpgrades" } do
		local menu = playerGui:FindFirstChild(name)
		if menu and menu:IsA("ScreenGui") and menu.Enabled then
			return true
		end
	end
	return false
end

-- Markers: a dashed rim with a faint fill lying on the ground (GroundRing
-- follows hills and the base floor).
local strikeArea = GroundRing.new(STRIKE_COLOR, Skills.Strike.Radius, 0.1, 0.55)
local landingArea = GroundRing.new(STRIKE_COLOR, LANDING_RADIUS, 0.1, 0.4)

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- Where the crosshair meets the ground, pulled back to `range` (flat) from the
-- hero, then dropped onto the ground just below (so not onto a tree top).
local function aimedGroundPoint(character: Model, root: BasePart, range: number): Vector3
	local ignore: { Instance } = { character, strikeArea.model, landingArea.model }
	local minions = Workspace:FindFirstChild("Minions")
	if minions then
		table.insert(ignore, minions)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	groundParams.FilterDescendantsInstances = ignore
	local camera = Workspace.CurrentCamera
	local eye, look = camera.CFrame.Position, camera.CFrame.LookVector
	local hit = Workspace:Raycast(eye, look * (range * 3), groundParams)
	local point = if hit then hit.Position else eye + look * range
	local flat = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
	if flat.Magnitude > range then
		point = root.Position + flat.Unit * range
	end
	local from = Vector3.new(point.X, math.max(point.Y, root.Position.Y) + 8, point.Z)
	local down = Workspace:Raycast(from, Vector3.new(0, -80, 0), groundParams)
	return if down then down.Position else Vector3.new(point.X, root.Position.Y - 3, point.Z)
end

local function drawAreas(character: Model?, root: BasePart?)
	if aiming == "Strike" and character and root then
		strikeArea:place(aimedGroundPoint(character, root, Skills.Strike.Range), MageAbilities.strikeRadius(hasMastery))
	else
		strikeArea:hide()
	end
	if aiming == "Teleport" and character and root then
		landingArea:place(aimedGroundPoint(character, root, Skills.Teleport.Range))
	else
		landingArea:hide()
	end
end

local function cast(character: Model, skill: SkillKey)
	local root = Targeting.rootOf(character)
	if not root or not skillReady(character, skill.id) then
		return
	end
	lastCast[skill.id] = os.clock()
	actionEvent:FireServer(skill.id, aimedGroundPoint(character, root, skill.range))
end

-- Attacking --------------------------------------------------------------------

local holding = 0 -- inputs currently holding attack (mouse, Attack slot)
local lastSentAt = -math.huge
local swingTrack: AnimationTrack? = nil

local function loadSwing(character: Model)
	swingTrack = nil
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if animator and animator:IsA("Animator") then
		local animation = Instance.new("Animation")
		animation.AnimationId = SWING_ANIMATION
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		swingTrack = track
	end
end
player.CharacterAdded:Connect(loadSwing)
if player.Character then
	task.spawn(loadSwing, player.Character)
end

local function readyToAttack(character: Model): boolean
	local readyAt = character:GetAttribute("PulseReadyAt")
	return not (type(readyAt) == "number" and Workspace:GetServerTimeNow() < readyAt)
end

-- Fires along the crosshair, or straight at the assist target when there is one.
-- The server casts from the head, so an assisted shot is aimed from there too.
local function shoot(character: Model)
	local time = os.clock()
	if time - lastSentAt < RESEND_SECONDS or not readyToAttack(character) then
		return
	end
	lastSentAt = time
	local direction = Workspace.CurrentCamera.CFrame.LookVector
	local head = character:FindFirstChild("Head")
	if assistPoint and head and head:IsA("BasePart") then
		local toTarget = assistPoint - head.Position
		if toTarget.Magnitude > 0.1 then
			direction = toTarget.Unit
		end
	end
	if swingTrack then
		swingTrack:Play(0.05)
	end
	actionEvent:FireServer("Pulse", direction)
end

RunService.RenderStepped:Connect(function(deltaTime)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and Targeting.rootOf(character)
	-- Down heroes (Health attribute 0) keep a living Humanoid, so the attribute decides.
	if not (character and humanoid and root and isAlive(character)) then
		assistTarget, assistPoint = nil, nil
		aiming = nil
		drawMarker(nil, false, deltaTime)
		drawAreas(nil, nil)
		if player:GetAttribute("AimTarget") then
			player:SetAttribute("AimTarget", false)
		end
		aimValue.Value = nil
		return
	end
	updateAssist(character, root)
	local hoveredAlly = if assistTarget then nil else allyUnderCrosshair(character)
	drawMarker(assistTarget or hoveredAlly, hoveredAlly ~= nil, deltaTime)
	drawAreas(character, root)
	-- Tells the crosshair (Crosshair.client) to turn red while the marker is on.
	-- A client-set attribute: it stays on this device and is never trusted by the server.
	local marked = assistTarget ~= nil
	if player:GetAttribute("AimTarget") ~= marked then
		player:SetAttribute("AimTarget", marked)
	end
	local shown = assistTarget or hoveredAlly
	if aimValue.Value ~= shown then
		aimValue.Value = shown
	end
	if holding > 0 then
		shoot(character)
	end
end)

-- Input --------------------------------------------------------------------------

local function press()
	holding += 1
	local character = player.Character
	if character then
		shoot(character) -- fire on the click itself, not a frame later
	end
end

local function release()
	holding = math.max(holding - 1, 0)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		press()
		return
	end
	local character = player.Character
	if not character or menuOpen() then
		return
	end
	local skill = SKILL_KEYS[input.KeyCode]
	if skill then
		aiming = skill.id -- shows the marker; the cast happens on release
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and holding > 0 then
		release()
		return
	end
	local skill = SKILL_KEYS[input.KeyCode]
	if skill and aiming == skill.id then
		aiming = nil
		local character = player.Character
		if character and not menuOpen() then
			cast(character, skill)
		end
	end
end)

-- The HUD's Attack slot (built by HeroHud.client).
task.spawn(function()
	local hud = playerGui:WaitForChild("HeroHud")
	local slot = hud:WaitForChild("Panel"):WaitForChild("Skills"):WaitForChild("Attack")
	if slot:IsA("GuiButton") then
		slot.MouseButton1Down:Connect(press)
		slot.MouseButton1Up:Connect(release)
		slot.MouseLeave:Connect(function()
			holding = 0
		end)
	end
end)
