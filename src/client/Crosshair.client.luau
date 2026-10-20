--!strict
-- Crosshair in the centre of the screen for the first-person camera
-- (StarterPlayer.CameraMode = LockFirstPerson in default.project.json).
-- Four short lines with a gap and a centre dot. It turns red while it points at
-- an enemy the basic attack can hit (Targeting.TargetKinds, other team), white
-- otherwise. Roblox's own mouse icon is hidden so only this shows.
-- Display only: what the attack hits is still decided by the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Targeting = require(ReplicatedStorage.Shared.Targeting)

local LINE_LENGTH = 8
local LINE_THICKNESS = 2
local GAP = 5 -- pixels from the centre to where each line starts
local DOT_SIZE = 3
local AIM_DISTANCE = 300 -- studs the enemy check looks ahead
local NORMAL_COLOR = Color3.new(1, 1, 1)
local ENEMY_COLOR = Color3.fromRGB(255, 60, 50)
-- Players are always on our side; used until the server sets the attribute.
local DEFAULT_TEAM = Config.Teams.Defenders

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

UserInputService.MouseIconEnabled = false

local screen = Instance.new("ScreenGui")
screen.Name = "Crosshair"
screen.IgnoreGuiInset = true -- centre of the whole window, where the camera ray goes
screen.ResetOnSpawn = false
screen.Parent = playerGui

local centre = Instance.new("Frame")
centre.Name = "Centre"
centre.AnchorPoint = Vector2.new(0.5, 0.5)
centre.Position = UDim2.fromScale(0.5, 0.5)
centre.Size = UDim2.fromOffset(0, 0)
centre.BackgroundTransparency = 1
centre.Parent = screen

local pieces: { Frame } = {}

local function addPiece(x: number, y: number, width: number, height: number)
	local piece = Instance.new("Frame")
	piece.AnchorPoint = Vector2.new(0.5, 0.5)
	piece.Position = UDim2.fromOffset(x, y)
	piece.Size = UDim2.fromOffset(width, height)
	piece.BackgroundColor3 = NORMAL_COLOR
	piece.BorderSizePixel = 0
	piece.Parent = centre
	-- Thin dark outline so it reads on bright ground and sky.
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.4
	stroke.Thickness = 1
	stroke.Parent = piece
	table.insert(pieces, piece)
end

local offset = GAP + LINE_LENGTH / 2
addPiece(0, -offset, LINE_THICKNESS, LINE_LENGTH) -- up
addPiece(0, offset, LINE_THICKNESS, LINE_LENGTH) -- down
addPiece(-offset, 0, LINE_LENGTH, LINE_THICKNESS) -- left
addPiece(offset, 0, LINE_LENGTH, LINE_THICKNESS) -- right
addPiece(0, 0, DOT_SIZE, DOT_SIZE) -- centre dot

local function localTeam(): string
	local team = player:GetAttribute("Team")
	return if type(team) == "string" then team else DEFAULT_TEAM
end

-- The attackable enemy (unit model or structure part) owning a hit part, if any.
local function enemyOf(hitPart: Instance): Instance?
	local instance: Instance? = hitPart
	while instance and instance ~= Workspace do
		if Targeting.TargetKinds[instance:GetAttribute("Kind")] then
			local team = instance:GetAttribute("Team")
			return if type(team) == "string" and team ~= localTeam() then instance else nil
		end
		instance = instance.Parent
	end
	return nil
end

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local currentColor = NORMAL_COLOR
RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	local character = player.Character
	-- Fences and hills don't stop the crosshair, same as attacks.
	local ignore = Targeting.seeThrough()
	if character then
		table.insert(ignore, character)
	end
	aimParams.FilterDescendantsInstances = ignore
	local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * AIM_DISTANCE, aimParams)
	local color = if hit and enemyOf(hit.Instance) then ENEMY_COLOR else NORMAL_COLOR
	if color ~= currentColor then
		currentColor = color
		for _, piece in pieces do
			piece.BackgroundColor3 = color
		end
	end
end)
