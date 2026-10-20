--!strict
-- Announcement banner near the top of the screen, in the game's UI design
-- system (docs/11_UI_DESIGN.md): a surface pill with a white headline and a
-- dimmer subline, e.g.
--   Zombies lost a core
--   Enemy core destroyed
-- No team colours. Banners queue, so two quick events show one after another.
-- Display only: the server decides when a structure is destroyed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local space = UiTheme.space
local SHOW_SECONDS = 3
local FADE_SECONDS = 0.25
local DEFENDERS = Config.Teams.Defenders
-- The map calls it Barracks; players know it as the inhibitor.
local DISPLAY_NAMES: { [string]: string } = { Tower = "tower", Barracks = "inhibitor", Core = "core" }
-- How each side is named on banners.
local TEAM_LABELS: { [string]: string } = { [DEFENDERS] = "We", [Config.Teams.Zombies] = "Zombies" }
local UNIT_LABELS: { [string]: string } = { [DEFENDERS] = "Our minions", [Config.Teams.Zombies] = "Zombies" }
-- Players are always on our side; used until the server sets the attribute.
local DEFAULT_TEAM = DEFENDERS

local player = Players.LocalPlayer
local destroyedEvent = ReplicatedStorage:WaitForChild("StructureDestroyed") :: RemoteEvent

local function localTeam(): string
	local team = player:GetAttribute("Team")
	return if type(team) == "string" then team else DEFAULT_TEAM
end

-- Banner ---------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "Announcements"
screen.ResetOnSpawn = false
screen.DisplayOrder = 10
screen.Parent = player:WaitForChild("PlayerGui")

local banner = UiTheme.panel(screen, nil, UiTheme.RadiusLarge)
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, space(16))
banner.Size = UDim2.fromOffset(0, 0)
banner.AutomaticSize = Enum.AutomaticSize.XY
banner.Visible = false
UiTheme.applyScale(banner)
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, space(3))
pad.PaddingBottom = UDim.new(0, space(3))
pad.PaddingLeft = UDim.new(0, space(6))
pad.PaddingRight = UDim.new(0, space(6))
pad.Parent = banner
local layout = Instance.new("UIListLayout")
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 2)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = banner

local function line(order: number, size: number, weight: Font, strength: number): TextLabel
	local label = UiTheme.text(banner, size, weight, strength)
	label.LayoutOrder = order
	label.Size = UDim2.fromOffset(0, size + 4)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextTruncate = Enum.TextTruncate.None
	label.TextXAlignment = Enum.TextXAlignment.Center
	return label
end
local headline = line(1, 22, UiTheme.Font.Heavy, UiTheme.Strength.Value)
local subline = line(2, UiTheme.TextSize.Body, UiTheme.Font.Medium, UiTheme.Strength.Label)

local function fadeTo(visible: boolean)
	local info = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(banner, info, {
		BackgroundTransparency = if visible then UiTheme.SurfaceTransparency else 1,
	}):Play()
	TweenService:Create(headline, info, { TextTransparency = if visible then UiTheme.Strength.Value else 1 }):Play()
	TweenService:Create(subline, info, { TextTransparency = if visible then UiTheme.Strength.Label else 1 }):Play()
end

-- Queue ----------------------------------------------------------------------------

type Message = { headline: string, subline: string }
local queue: { Message } = {}
local showing = false

local function showNext()
	local message = table.remove(queue, 1)
	if not message then
		showing = false
		banner.Visible = false
		return
	end
	showing = true
	headline.Text = message.headline
	subline.Text = message.subline
	banner.BackgroundTransparency = 1
	headline.TextTransparency = 1
	subline.TextTransparency = 1
	banner.Visible = true
	fadeTo(true)
	task.delay(SHOW_SECONDS, function()
		fadeTo(false)
		task.delay(FADE_SECONDS, showNext)
	end)
end

local function announce(message: Message)
	table.insert(queue, message)
	if not showing then
		showNext()
	end
end

-- Structure destroyed --------------------------------------------------------------

destroyedEvent.OnClientEvent:Connect(function(kind: unknown, team: unknown, killerTeam: unknown)
	if type(kind) ~= "string" or type(team) ~= "string" or type(killerTeam) ~= "string" then
		return
	end
	local name = DISPLAY_NAMES[kind]
	if not (name and TEAM_LABELS[team]) then
		return
	end
	local ours = team == localTeam()
	local detail = if kind == "Barracks" and UNIT_LABELS[killerTeam]
		then `{UNIT_LABELS[killerTeam]} are now stronger`
		elseif ours then `Your {name} has fallen`
		else `Enemy {name} destroyed`
	announce({
		headline = `{TEAM_LABELS[team]} lost a {name}`,
		subline = detail,
	})
end)
