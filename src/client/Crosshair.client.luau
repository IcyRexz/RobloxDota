--!strict
-- Crosshair in the centre of the screen for the first-person camera
-- (StarterPlayer.CameraMode = LockFirstPerson in default.project.json).
-- Four short lines with a gap and a centre dot, in the UI design system. It
-- turns red exactly when the red target marker is on, i.e. when a click would
-- hit an enemy (straight along the crosshair or through aim assist). That
-- decision is made by HeroControls.client, which sets this device's own
-- "AimTarget" attribute on the local player (not sent to the server).
-- Roblox's own mouse icon is hidden so only this shows.
-- Display only: what the attack hits is still decided by the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameContext = require(ReplicatedStorage.Shared.GameContext)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local LINE_LENGTH = 8
local LINE_THICKNESS = 2
local GAP = 5 -- pixels from the centre to where each line starts
local DOT_SIZE = 3
local NORMAL_COLOR = UiTheme.Text
local ENEMY_COLOR = UiTheme.Enemy

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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
UiTheme.applyScale(centre, 1.2) -- a little larger, but a crosshair should stay fine

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
	stroke.Color = UiTheme.Surface
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

local function refresh()
	local color = if player:GetAttribute("AimTarget") == true then ENEMY_COLOR else NORMAL_COLOR
	for _, piece in pieces do
		piece.BackgroundColor3 = color
	end
end
refresh()
player:GetAttributeChangedSignal("AimTarget"):Connect(refresh)

-- Battle only, and hidden while your hero is down (DeathScreen.client sets
-- this device's "Down"). The mouse icon is hidden by ContextCamera.client.
local function updateShown()
	screen.Enabled = GameContext.is("Battle") and player:GetAttribute("Down") ~= true
end
updateShown()
player:GetAttributeChangedSignal("Down"):Connect(updateShown)
GameContext.changed:Connect(updateShown)
