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
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Pulse = Config.Hero.Pulse
local SWING_ANIMATION = "rbxassetid://522635514" -- Roblox default R15 "tool slash"
local RESEND_SECONDS = 0.15 -- ask the server again at most this often
local ASSIST_DEGREES = 3 -- crosshair this close to an enemy's body turns the assist on
local ASSIST_KEEP_DEGREES = 5 -- ...and it stays on that enemy until this far off
local UNIT_RADIUS = 1.5 -- studs: rough body half-width used for the angle test
local MARKER_COLOR = UiTheme.Enemy -- an enemy you can hit (UI design system)
local MARKER_DASHES = 12
local MARKER_SPIN = math.rad(90) -- degrees per second
-- Players are always on our side; used until the server sets the attribute.
local DEFAULT_TEAM = Config.Teams.Defenders

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local actionEvent = ReplicatedStorage:WaitForChild("HeroAction") :: RemoteEvent

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

-- Picks the enemy nearest to the crosshair, if any is close enough.
local function updateAssist(character: Model, root: BasePart)
	local camera = Workspace.CurrentCamera
	local eye, look = camera.CFrame.Position, camera.CFrame.LookVector
	-- 1. What a click straight along the crosshair would hit (the server's rule).
	local direct = Targeting.castShot(character, localTeam(), look, Pulse.Range, function(target)
		return isEnemy(character, target)
	end)
	if direct then
		assistTarget, assistPoint = direct, nil
		return
	end
	-- 2. Otherwise, aim assist: an enemy near the crosshair. The server casts the
	-- shot from the head, Pulse.Range studs long.
	local head = character:FindFirstChild("Head")
	local shotFrom = if head and head:IsA("BasePart") then head.Position else root.Position
	local candidates: { Candidate } = {}
	for _, group in Targeting.candidateGroups() do
		for _, target in group do
			if isEnemy(character, target) then
				local point = aimPointFor(target, eye, look)
				if point and (point - shotFrom).Magnitude <= Pulse.Range then
					local radius = if target:IsA("BasePart") then 0 else UNIT_RADIUS
					local angle = offAngle(eye, look, point, radius)
					local limit = if target == assistTarget then ASSIST_KEEP_DEGREES else ASSIST_DEGREES
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
			assistTarget, assistPoint = candidate.target, candidate.point
			return
		end
	end
	assistTarget, assistPoint = nil, nil
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

local function markerRadius(target: Instance): number
	if target:IsA("BasePart") then
		return math.max(target.Size.X, target.Size.Z) / 2 + 1.5
	end
	return 2.2
end

local spin = 0
local function drawMarker(target: Instance?, deltaTime: number)
	local targetRoot = if target and target:IsA("BasePart") then target elseif target then Targeting.rootOf(target) else nil
	if not (target and targetRoot) then
		marker.Parent = nil
		highlight.Parent = nil
		return
	end
	local centre = targetRoot.Position
	local radius = markerRadius(target)
	-- Ring at the target's feet (or the structure's base), so it sits on hills too.
	local groundY = if target:IsA("BasePart") then centre.Y - target.Size.Y / 2 else centre.Y - 3
	spin += MARKER_SPIN * deltaTime
	local dashLength = 2 * math.pi * radius / MARKER_DASHES * 0.6
	for i, dash in dashes do
		local angle = spin + (i / MARKER_DASHES) * 2 * math.pi
		local position = Vector3.new(centre.X + math.cos(angle) * radius, groundY + 0.1, centre.Z + math.sin(angle) * radius)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		dash.Size = Vector3.new(0.35, 0.05, dashLength)
		dash.CFrame = CFrame.lookAt(position, position + tangent)
	end
	marker.Parent = Workspace
	highlight.Adornee = target
	highlight.Parent = playerGui
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
	if not (character and humanoid and root and humanoid.Health > 0) then
		assistTarget, assistPoint = nil, nil
		drawMarker(nil, deltaTime)
		if player:GetAttribute("AimTarget") then
			player:SetAttribute("AimTarget", false)
		end
		return
	end
	updateAssist(character, root)
	drawMarker(assistTarget, deltaTime)
	-- Tells the crosshair (Crosshair.client) to turn red while the marker is on.
	-- A client-set attribute: it stays on this device and is never trusted by the server.
	local aiming = assistTarget ~= nil
	if player:GetAttribute("AimTarget") ~= aiming then
		player:SetAttribute("AimTarget", aiming)
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
	if not gameProcessed and input.UserInputType == Enum.UserInputType.MouseButton1 then
		press()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and holding > 0 then
		release()
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
