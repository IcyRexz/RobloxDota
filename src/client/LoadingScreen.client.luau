--!strict
-- The loading screen between the lobby and a battle (owner 2026-10-23,
-- following games like Survive The Swarm), in the UI design system
-- (docs/11_UI_DESIGN.md). Shown while the server says this player is on the
-- way (GameContext "Loading", Match.luau): going into a battle ("Preparing
-- battle", the map's name) or back to the lobby ("Returning to the lobby").
-- It covers the whole window over everything else, fades in quickly and
-- out a little slower; three dots pulse while it shows. Display only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GameContext = require(ReplicatedStorage.Shared.GameContext)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Font = UiTheme.Font
local Size = UiTheme.TextSize
local Strength = UiTheme.Strength
local space = UiTheme.space

local FADE_IN = TweenInfo.new(0.15)
local FADE_OUT = TweenInfo.new(0.4)
local DOT_SECONDS = 0.35

local player = Players.LocalPlayer

local screen = Instance.new("ScreenGui")
screen.Name = "LoadingScreen"
screen.ResetOnSpawn = false -- it must stay up while the character is replaced
screen.IgnoreGuiInset = true
screen.DisplayOrder = 100 -- over every other screen
screen.Enabled = false
screen.Parent = player:WaitForChild("PlayerGui")

local cover = Instance.new("CanvasGroup")
cover.Name = "Cover"
cover.Size = UDim2.fromScale(1, 1)
cover.BackgroundColor3 = UiTheme.Surface
cover.BorderSizePixel = 0
cover.GroupTransparency = 1
cover.Parent = screen
local gradient = Instance.new("UIGradient")
gradient.Rotation = 90
gradient.Color = ColorSequence.new(UiTheme.Fill.Navy[1], UiTheme.Fill.Navy[2])
gradient.Parent = cover

local column = Instance.new("Frame")
column.AnchorPoint = Vector2.new(0.5, 0.5)
column.Position = UDim2.fromScale(0.5, 0.5)
column.Size = UDim2.fromOffset(560, 0)
column.AutomaticSize = Enum.AutomaticSize.Y
column.BackgroundTransparency = 1
column.Parent = cover
UiTheme.applyScale(column)
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, space(2))
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = column

local function centred(order: number, size: number, font: Font, strength: number?): TextLabel
	local label = UiTheme.text(column, size, font, strength)
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, size + 10)
	label.TextXAlignment = Enum.TextXAlignment.Center
	return label
end
local title = centred(1, Size.Display + 6, Font.Heavy)
local detail = centred(2, Size.Title, Font.Bold, Strength.Label)
detail.TextColor3 = UiTheme.Gold
local dots = centred(3, Size.Heading, Font.Heavy, Strength.Label)

local function mapName(): string
	local id = Workspace:GetAttribute("BattleMap")
	for _, map in Config.Lobby.Maps do
		if map.Id == id then
			return map.Name
		end
	end
	return ""
end

local showToken = 0

local function show()
	showToken += 1
	local token = showToken
	local goingIn = player:GetAttribute("InParty") == true
	title.Text = if goingIn then "Preparing battle" else "Returning to the lobby"
	detail.Text = if goingIn then mapName() else ""
	detail.Visible = detail.Text ~= ""
	screen.Enabled = true
	TweenService:Create(cover, FADE_IN, { GroupTransparency = 0 }):Play()
	task.spawn(function()
		local count = 0
		while showToken == token do
			count = count % 3 + 1
			dots.Text = string.rep("•  ", count)
			task.wait(DOT_SECONDS)
		end
	end)
end

local function hide()
	showToken += 1
	local token = showToken
	local fade = TweenService:Create(cover, FADE_OUT, { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Once(function()
		if showToken == token then
			screen.Enabled = false
		end
	end)
end

GameContext.during("Loading", function()
	show()
	return hide
end)
