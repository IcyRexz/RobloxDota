--!strict
-- What you see while your hero is down (owner 2026-10-23; rules in
-- Heroes.server and Config.Hero.Death):
--  * the world turns grey (a local ColorCorrectionEffect);
--  * the camera leaves first person and orbits your body where it fell:
--    move the mouse to look around, wheel to zoom; you cannot move;
--  * a panel in the UI design system (docs/11_UI_DESIGN.md): "YOU DIED", the
--    respawn countdown, whether an ally can still revive you, and while one
--    holds F, "<name> is reviving you" with a green progress bar.
-- Your body's own animations stop while it lies there. Sets this device's
-- "Down" attribute on the local player (never sent to the server) so other
-- scripts (Crosshair.client) can hide. Display only: the server decides death,
-- revive and respawn (character attributes Health, DownedAt, RespawnAt,
-- ReviverName, ReviveStartedAt; player attribute ReviveUsed).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Font = UiTheme.Font
local Size = UiTheme.TextSize
local Strength = UiTheme.Strength
local space = UiTheme.space
local Death = Config.Hero.Death

local PANEL_WIDTH = 340
local FADE = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Orbit camera around the body.
local ORBIT_DISTANCE = 14 -- studs, at the start
local ORBIT_MIN, ORBIT_MAX = 6, 30
local ORBIT_ZOOM_STEP = 2
local ORBIT_SENSITIVITY = 0.004 -- radians per pixel of mouse movement
local ORBIT_PITCH_MIN, ORBIT_PITCH_MAX = math.rad(-75), math.rad(-5)
local ORBIT_LOOK_HEIGHT = 1 -- studs above the body the camera looks at
local CAMERA_STEP = "DeathOrbitCamera"

local player = Players.LocalPlayer

-- Grey world ----------------------------------------------------------------------

local grey = Instance.new("ColorCorrectionEffect")
grey.Name = "DeathGrey"
grey.Saturation = 0
grey.Brightness = 0
grey.Contrast = 0
grey.Enabled = false
grey.Parent = Lighting

-- Panel ---------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "DeathScreen"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 5
screen.Enabled = false
screen.Parent = player:WaitForChild("PlayerGui")

local panel = UiTheme.panel(screen, nil, UiTheme.RadiusLarge)
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.fromScale(0.5, 0.18)
panel.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
UiTheme.applyScale(panel)
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, space(4))
pad.PaddingBottom = UDim.new(0, space(4))
pad.PaddingLeft = UDim.new(0, space(5))
pad.PaddingRight = UDim.new(0, space(5))
pad.Parent = panel
local list = Instance.new("UIListLayout")
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Padding = UDim.new(0, space(2))
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = panel

local function line(order: number, size: number, weight: Font, strength: number?): TextLabel
	local label = UiTheme.text(panel, size, weight, strength)
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, size + 6)
	label.TextXAlignment = Enum.TextXAlignment.Center
	return label
end

local title = line(1, Size.Display, Font.Heavy)
title.Text = "YOU DIED"
title.TextColor3 = UiTheme.Enemy
local countdown = line(2, Size.Title, Font.Bold)
countdown.TextColor3 = UiTheme.Gold
local hint = line(3, Size.Body, Font.Medium, Strength.Label)
hint.TextWrapped = true
hint.TextTruncate = Enum.TextTruncate.None
hint.Size = UDim2.fromScale(1, 0)
hint.AutomaticSize = Enum.AutomaticSize.Y

local reviveRow = Instance.new("Frame")
reviveRow.Name = "Revive"
reviveRow.LayoutOrder = 4
reviveRow.BackgroundTransparency = 1
reviveRow.Size = UDim2.new(1, 0, 0, Size.Body + 6 + space(1) + UiTheme.Bar.Health)
reviveRow.Visible = false
reviveRow.Parent = panel
local reviverText = UiTheme.text(reviveRow, Size.Body, Font.Bold)
reviverText.Size = UDim2.new(1, 0, 0, Size.Body + 6)
reviverText.TextXAlignment = Enum.TextXAlignment.Center
local reviveBar = UiTheme.bar(reviveRow, UiTheme.Bar.Health, UiTheme.Ally)
reviveBar.track.Position = UDim2.fromOffset(0, Size.Body + 6 + space(1))

-- Orbit camera ----------------------------------------------------------------------

local yaw, pitch, distance = 0, math.rad(-30), ORBIT_DISTANCE
local lastFocus: Vector3? = nil

local function cameraParams(): RaycastParams
	local ignore: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local minions = Workspace:FindFirstChild("Minions")
	if minions then
		table.insert(ignore, minions)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return params
end

local function updateCamera(_deltaTime: number)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		lastFocus = root.Position + Vector3.new(0, ORBIT_LOOK_HEIGHT, 0)
	end
	local focus = lastFocus
	if not focus then
		return
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	local delta = UserInputService:GetMouseDelta()
	yaw -= delta.X * ORBIT_SENSITIVITY
	pitch = math.clamp(pitch - delta.Y * ORBIT_SENSITIVITY, ORBIT_PITCH_MIN, ORBIT_PITCH_MAX)
	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local offset = rotation:VectorToWorldSpace(Vector3.new(0, 0, distance))
	-- Pull in in front of walls and hills between the body and the camera.
	local hit = Workspace:Raycast(focus, offset, cameraParams())
	local reach = if hit then math.max((hit.Position - focus).Magnitude - 0.5, 1) else distance
	camera.CFrame = CFrame.lookAt(focus + offset.Unit * reach, focus)
end

UserInputService.InputChanged:Connect(function(input: InputObject)
	if screen.Enabled and input.UserInputType == Enum.UserInputType.MouseWheel then
		distance = math.clamp(distance - input.Position.Z * ORBIT_ZOOM_STEP, ORBIT_MIN, ORBIT_MAX)
	end
end)

-- Down / up -------------------------------------------------------------------------

local down = false

local function setAnimations(character: Model, playing: boolean)
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = playing
	end
	if not playing then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				track:Stop(0.2)
			end
		end
	end
end

local function setDown(isDown: boolean, character: Model?)
	if isDown == down then
		return
	end
	down = isDown
	player:SetAttribute("Down", isDown)
	local camera = Workspace.CurrentCamera
	if isDown then
		-- Start the orbit behind where the camera was looking.
		local look = camera.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
		pitch, distance, lastFocus = math.rad(-30), ORBIT_DISTANCE, nil
		camera.CameraType = Enum.CameraType.Scriptable
		-- (The server holds the body still: anchored, no walk speed or jump.)
		RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Camera.Value + 1, updateCamera)
		if character then
			setAnimations(character, false)
		end
		grey.Enabled = true
		TweenService:Create(grey, FADE, { Saturation = -1, Brightness = -0.05, Contrast = 0.1 }):Play()
		screen.Enabled = true
	else
		RunService:UnbindFromRenderStep(CAMERA_STEP)
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		if character then
			setAnimations(character, true)
		end
		grey.Enabled = false
		grey.Saturation, grey.Brightness, grey.Contrast = 0, 0, 0
		screen.Enabled = false
	end
end

local function readNumber(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else nil
end

RunService.RenderStepped:Connect(function()
	local character = player.Character
	local health = character and readNumber(character, "Health")
	local downedAt = character and readNumber(character, "DownedAt")
	setDown(character ~= nil and health ~= nil and health <= 0 and downedAt ~= nil, character)
	if not (down and character) then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local respawnAt = readNumber(character, "RespawnAt") or now
	-- Counts down to 1, then shows nothing while the new character loads
	-- (owner 2026-10-23: no "Respawn in 0" / "-0"; math.ceil of a small
	-- negative number is -0).
	local left = respawnAt - now
	countdown.Text = if left > 0 then `Respawn in {math.ceil(left)}` else ""
	local canBeRevived = player:GetAttribute("ReviveUsed") ~= true
	hint.Text = if canBeRevived
		then "An ally can revive you: they hold F by your body"
		else "You were already revived this match"
	local reviver = character:GetAttribute("ReviverName")
	local startedAt = readNumber(character, "ReviveStartedAt")
	reviveRow.Visible = type(reviver) == "string" and startedAt ~= nil
	if type(reviver) == "string" and startedAt then
		reviverText.Text = `{reviver} is reviving you`
		reviveBar.fill.Size = UDim2.fromScale(math.clamp((now - startedAt) / Death.ReviveHold, 0, 1), 1)
	end
end)
