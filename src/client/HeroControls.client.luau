--!strict
-- Hero input on this player's device, Mobile Legends style:
--  * a target marker (ring + outline) sits on the enemy your basic attack will
--    go for: the nearest enemy hero, else minion, else attackable structure,
--    within AcquireRange and line of sight. It stays on that target while it
--    remains valid. Red = in attack range, orange = you will walk to it.
--  * picking a target yourself: click (or tap) an enemy within AcquireRange to
--    lock onto it, or press Tab to cycle through enemies in range, nearest
--    first. A locked target shows a solid, still ring. The lock ends when the
--    target dies or leaves AcquireRange, or when you click empty ground.
--  * pressing attack (left mouse / the HUD's Attack slot; holding repeats):
--    if the target is out of range, your hero walks toward it, then attacks.
--    Moving yourself (WASD / thumbstick) cancels the walk.
--  * when an attack is sent your hero turns to the target and swings at once
--    on this device, so it feels instant.
-- The server still decides everything: it re-checks the target, range, line of
-- sight and cooldown, and may pick a different target or refuse.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Targeting = require(ReplicatedStorage.Shared.Targeting)

local Pulse = Config.Hero.Pulse
local SWING_ANIMATION = "rbxassetid://522635514" -- Roblox default R15 "tool slash"
local RESEND_SECONDS = 0.15 -- ask the server again at most this often
local TAP_MEMORY = 0.8 -- a single tap keeps trying (walking in) this long
local IN_RANGE_COLOR = Color3.fromRGB(255, 60, 50)
local CHASE_COLOR = Color3.fromRGB(255, 170, 40)
local MARKER_DASHES = 12
local MARKER_SPIN = math.rad(90) -- degrees per second
local RETARGET_SECONDS = 0.1 -- how often the marker's target is re-chosen
-- Until match teams exist (task T05), everyone is treated as Blue.
local DEFAULT_TEAM = "Blue"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local actionEvent = ReplicatedStorage:WaitForChild("HeroAction") :: RemoteEvent

-- Roblox's own movement controls, to tell when the player steers by hand.
local controls = (require :: any)(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()

local function localTeam(): string
	local team = player:GetAttribute("Team")
	return if type(team) == "string" then team else DEFAULT_TEAM
end

-- Target prediction ------------------------------------------------------------

local function isAlive(target: Instance): boolean
	local health = target:GetAttribute("Health")
	return target:IsDescendantOf(Workspace) and type(health) == "number" and health > 0
end

-- Same objective-order lock as the server (shared rule in Targeting).
local function isLocked(target: Instance): boolean
	return Targeting.isLocked(target, isAlive)
end

-- Distance to the target if it is a valid enemy in AcquireRange with line of sight.
local function reach(character: Model, root: BasePart, target: Instance): number?
	if target == character or not Targeting.TargetKinds[target:GetAttribute("Kind")] then
		return nil
	end
	local team = target:GetAttribute("Team")
	if type(team) ~= "string" or team == localTeam() or not isAlive(target) or isLocked(target) then
		return nil
	end
	local point = Targeting.aimPointOf(target, root.Position)
	if not point then
		return nil
	end
	local distance = Targeting.planarDistance(point, root.Position)
	if distance > Pulse.AcquireRange or not Targeting.hasLineOfSight(target, root.Position, point) then
		return nil
	end
	return distance
end

local current: Instance? = nil
local locked: Instance? = nil -- chosen by the player (click/tap/Tab)

-- A locked target wins while it stays valid. Otherwise the highest-priority
-- group with any valid target wins; within it the nearest. The current target
-- is kept while it is valid and in that same group.
local function updateTarget(character: Model, root: BasePart)
	if locked then
		if reach(character, root, locked) then
			current = locked
			return
		end
		locked = nil
	end
	for _, group in Targeting.candidateGroups() do
		local best: Instance? = nil
		local bestDistance = math.huge
		local keepCurrent = false
		for _, target in group do
			local distance = reach(character, root, target)
			if distance then
				if target == current then
					keepCurrent = true
				end
				if distance < bestDistance then
					best, bestDistance = target, distance
				end
			end
		end
		if best then
			current = if keepCurrent then current else best
			return
		end
	end
	current = nil
end

-- Marker -----------------------------------------------------------------------

local highlight = Instance.new("Highlight")
highlight.FillTransparency = 1
highlight.OutlineTransparency = 0
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

local marker = Instance.new("Model")
marker.Name = "TargetMarker"
local dashes: { Part } = {}
for i = 1, MARKER_DASHES do
	local dash = Instance.new("Part")
	dash.Name = "Dash" .. i
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
	return if target:GetAttribute("Kind") == "Hero" then 3 else 2.2
end

local spin = 0
local function drawMarker(target: Instance?, inRange: boolean, deltaTime: number)
	local lockedOn = target ~= nil and target == locked
	local targetRoot = if target and target:IsA("BasePart") then target elseif target then Targeting.rootOf(target) else nil
	if not (target and targetRoot) then
		marker.Parent = nil
		highlight.Parent = nil
		return
	end
	local centre = targetRoot.Position
	local radius = markerRadius(target)
	local color = if inRange then IN_RANGE_COLOR else CHASE_COLOR
	-- Auto target: spinning dashes. Locked target: a still, almost solid ring.
	if not lockedOn then
		spin += MARKER_SPIN * deltaTime
	end
	local dashLength = 2 * math.pi * radius / MARKER_DASHES * (if lockedOn then 0.95 else 0.6)
	for i, dash in dashes do
		local angle = spin + (i / MARKER_DASHES) * 2 * math.pi
		local position = Vector3.new(centre.X + math.cos(angle) * radius, 0.1, centre.Z + math.sin(angle) * radius)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		dash.Size = Vector3.new(if lockedOn then 0.55 else 0.35, 0.05, dashLength)
		dash.CFrame = CFrame.lookAt(position, position + tangent)
		dash.Color = color
	end
	marker.Parent = Workspace
	highlight.OutlineColor = color
	highlight.Adornee = target
	highlight.Parent = playerGui
end

-- Attacking --------------------------------------------------------------------

local sinceRetarget = math.huge
local holding = 0 -- inputs currently holding attack (mouse, Attack slot)
local tappedAt = -math.huge
local lastSentAt = -math.huge
local chasing = false
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

local function wantsAttack(): boolean
	return holding > 0 or os.clock() - tappedAt < TAP_MEMORY
end

local function readyToAttack(character: Model): boolean
	local readyAt = character:GetAttribute("PulseReadyAt")
	return not (type(readyAt) == "number" and Workspace:GetServerTimeNow() < readyAt)
end

local function stopChasing(humanoid: Humanoid, root: BasePart)
	if chasing then
		chasing = false
		humanoid:MoveTo(root.Position)
	end
end

RunService.Heartbeat:Connect(function(deltaTime)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and Targeting.rootOf(character)
	if not (character and humanoid and root and humanoid.Health > 0) then
		current = nil
		drawMarker(nil, false, deltaTime)
		return
	end

	sinceRetarget += deltaTime
	if sinceRetarget >= RETARGET_SECONDS or (current and not isAlive(current)) then
		sinceRetarget = 0
		updateTarget(character, root)
	end
	local target = current
	local point = if target then Targeting.aimPointOf(target, root.Position) else nil
	local distance = if point then Targeting.planarDistance(point, root.Position) else math.huge
	local inRange = distance <= Pulse.Range - 0.5 -- small margin: the server checks a moment later
	drawMarker(target, inRange, deltaTime)

	-- Steering by hand cancels any walk-to-target and any remembered tap.
	if controls:GetMoveVector().Magnitude > 0.1 then
		tappedAt = -math.huge
		chasing = false
		return
	end

	if not (wantsAttack() and target and point) then
		stopChasing(humanoid, root)
		return
	end
	if not inRange then
		chasing = true
		humanoid:MoveTo(point)
		return
	end
	stopChasing(humanoid, root)

	local time = os.clock()
	if time - lastSentAt >= RESEND_SECONDS and readyToAttack(character) then
		lastSentAt = time
		tappedAt = -math.huge -- a tap is used up by one attack
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(point.X, root.Position.Y, point.Z))
		if swingTrack then
			swingTrack:Play(0.05)
		end
		actionEvent:FireServer("Pulse", target)
	end
end)

-- Picking a target ---------------------------------------------------------------

-- The enemy unit under a screen point (mouse or touch), if any.
local function unitAt(screenPoint: Vector2): Instance?
	local camera = Workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local include: { Instance } = {}
	for _, group in Targeting.candidateGroups() do
		for _, unit in group do
			if unit ~= player.Character then
				table.insert(include, unit)
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	local instance: Instance? = if hit then hit.Instance else nil
	while instance and instance ~= Workspace do
		if Targeting.TargetKinds[instance:GetAttribute("Kind")] then
			return instance
		end
		instance = instance.Parent
	end
	return nil
end

-- Locks onto the enemy under the pointer if it is a valid target; clicking
-- anything else (ground, allies, units out of range) clears the lock.
local function pickAt(screenPoint: Vector2)
	local character = player.Character
	local root = character and Targeting.rootOf(character)
	local unit = unitAt(screenPoint)
	if character and root and unit and reach(character, root, unit) then
		locked = unit
		current = unit
		sinceRetarget = 0
	else
		locked = nil
	end
end

-- Tab: lock onto the next enemy in range, nearest first, wrapping around.
local function cycleTarget()
	local character = player.Character
	local root = character and Targeting.rootOf(character)
	if not (character and root) then
		return
	end
	type Option = { unit: Instance, distance: number }
	local options: { Option } = {}
	for _, group in Targeting.candidateGroups() do
		for _, unit in group do
			local distance = reach(character, root, unit)
			if distance then
				table.insert(options, { unit = unit, distance = distance })
			end
		end
	end
	if #options == 0 then
		return
	end
	table.sort(options, function(a, b)
		return a.distance < b.distance
	end)
	local nextIndex = 1
	for i, option in options do
		if option.unit == current then
			nextIndex = i % #options + 1
		end
	end
	locked = options[nextIndex].unit
	current = locked
	sinceRetarget = 0
end

-- Input --------------------------------------------------------------------------

local function press()
	holding += 1
	tappedAt = os.clock()
end

local function release()
	holding = math.max(holding - 1, 0)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		pickAt(UserInputService:GetMouseLocation())
		press()
	elseif input.UserInputType == Enum.UserInputType.Touch then
		-- Phones: tapping an enemy in the world only picks it; attacking is the button.
		pickAt(Vector2.new(input.Position.X, input.Position.Y))
	elseif input.KeyCode == Enum.KeyCode.Tab then
		cycleTarget()
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
