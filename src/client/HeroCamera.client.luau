--!strict
-- Fixed MOBA camera (Mobile Legends style): high, tilted, never rotates, and
-- follows your hero smoothly. It looks down the lane toward the enemy base, so
-- "up" on the screen (W / thumbstick up) is always toward the enemy.
-- The same camera is used on desktop and phones; shift lock is switched off in
-- the project file (StarterPlayer.EnableMouseLockOption).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PITCH = math.rad(55) -- how steeply the camera looks down
local DISTANCE = 70 -- studs from the hero
local FIELD_OF_VIEW = 40
local FOLLOW_SHARPNESS = 10 -- higher = follows more tightly
local FOCUS_AHEAD = 4 -- studs the view leans toward the enemy, so you see more of what is ahead
-- Until match teams exist (task T05), everyone is treated as Blue.
local DEFAULT_TEAM = "Blue"
-- Direction from each team's base toward the enemy (the lane runs along X).
local FORWARD: { [string]: Vector3 } = {
	Blue = Vector3.new(1, 0, 0),
	Red = Vector3.new(-1, 0, 0),
}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local focus: Vector3? = nil

local function forward(): Vector3
	local team = player:GetAttribute("Team")
	return FORWARD[if type(team) == "string" then team else DEFAULT_TEAM] or FORWARD[DEFAULT_TEAM]
end

local function heroPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

RunService:BindToRenderStep("MobaCamera", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
	camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FIELD_OF_VIEW

	local ahead = forward()
	local target = heroPosition()
	if target then
		target += ahead * FOCUS_AHEAD
		-- Smooth follow that behaves the same at any frame rate.
		local alpha = 1 - math.exp(-FOLLOW_SHARPNESS * deltaTime)
		focus = if focus then focus:Lerp(target, alpha) else target
	end
	if not focus then
		return -- no hero yet; leave the camera where it is
	end

	local offset = -ahead * math.cos(PITCH) * DISTANCE + Vector3.yAxis * math.sin(PITCH) * DISTANCE
	camera.CFrame = CFrame.lookAt(focus + offset, focus)
end)

-- Snap straight to the new hero after a respawn instead of gliding across the map.
player.CharacterAdded:Connect(function()
	focus = nil
end)
