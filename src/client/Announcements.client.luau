--!strict
-- Announcement banner near the top of the screen, in the game's UI design
-- system (docs/11_UI_DESIGN.md): a surface pill with a white headline and a
-- dimmer subline, e.g.
--   Zombies lost a core
--   Enemy core destroyed
-- No team colours. Banners queue, so two quick events show one after another.
-- Also small popups on the right (owner 2026-10-23) when a player falls or is
-- revived ("Bob has fallen", "Zac revived Bob") or picks a mastery ("Zac took
-- Chain Bolt", gold dot), stacked, each fading after a
-- few seconds; the revived player also gets a "YOU HAVE BEEN REVIVED" banner.
-- Display only: the server decides when a structure is destroyed, who falls
-- and who is revived (HeroDowned, from Heroes.server).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local space = UiTheme.space
local SHOW_SECONDS = 3
local FADE_SECONDS = 0.25
local POPUP_SECONDS = 4
local POPUP_MAX = 4 -- older popups are dropped beyond this
local POPUP_DOT = 10
local DEFENDERS = Config.Teams.Defenders
local DISPLAY_NAMES: { [string]: string } = { Tower = "tower", Barracks = "barracks", Core = "core", Nest = "nest" }
-- How each side is named on banners.
local TEAM_LABELS: { [string]: string } = { [DEFENDERS] = "We", [Config.Teams.Zombies] = "Zombies" }
-- Players are always on our side; used until the server sets the attribute.
local DEFAULT_TEAM = DEFENDERS

local player = Players.LocalPlayer
local destroyedEvent = ReplicatedStorage:WaitForChild("StructureDestroyed") :: RemoteEvent
local zombieEvent = ReplicatedStorage:WaitForChild("ZombieEvent") :: RemoteEvent
local downedEvent = ReplicatedStorage:WaitForChild("HeroDowned") :: RemoteEvent
local pickedEvent = ReplicatedStorage:WaitForChild("MasteryPicked") :: RemoteEvent

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
	-- A fallen barracks only stops its own soldiers (owner 2026-10-23).
	local detail = if kind == "Barracks" and ours
		then "No more soldiers from that side"
		elseif ours then `Your {name} has fallen`
		else `Enemy {name} destroyed`
	announce({
		headline = `{TEAM_LABELS[team]} lost a {name}`,
		subline = detail,
	})
end)

-- Battlefield events (ZombieEvents.luau) --------------------------------------------

zombieEvent.OnClientEvent:Connect(function(id: unknown, phase: unknown)
	if type(id) ~= "string" or (phase ~= "Start" and phase ~= "End") then
		return
	end
	for _, info in Config.Events.List do
		if info.id == id then
			announce(if phase == "Start"
				then { headline = string.upper(info.name), subline = info.text }
				else { headline = `{info.name} is over`, subline = "Zombies are back to normal" })
			return
		end
	end
	for _, arrival in Config.Events.Arrivals do
		if arrival.id == id and phase == "Start" then
			announce({ headline = string.upper(arrival.name), subline = arrival.text })
			return
		end
	end
end)

-- Popups: a player fell or was revived ----------------------------------------------

local popups = Instance.new("Frame")
popups.Name = "Popups"
popups.AnchorPoint = Vector2.new(1, 0)
popups.Position = UDim2.new(1, -space(3), 0.4, 0)
popups.Size = UDim2.fromOffset(0, 0)
popups.AutomaticSize = Enum.AutomaticSize.XY
popups.BackgroundTransparency = 1
popups.Parent = screen
UiTheme.applyScale(popups)
local popupList = Instance.new("UIListLayout")
popupList.HorizontalAlignment = Enum.HorizontalAlignment.Right
popupList.Padding = UDim.new(0, space(1))
popupList.SortOrder = Enum.SortOrder.LayoutOrder
popupList.Parent = popups

local popupOrder = 0
local function popup(text: string, color: Color3)
	popupOrder += 1
	local pill = UiTheme.panel(popups, nil, UiTheme.Radius)
	pill.LayoutOrder = popupOrder
	pill.Size = UDim2.fromOffset(0, space(7))
	pill.AutomaticSize = Enum.AutomaticSize.X
	local inner = Instance.new("UIPadding")
	inner.PaddingLeft = UDim.new(0, space(3))
	inner.PaddingRight = UDim.new(0, space(3))
	inner.Parent = pill
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, space(2))
	row.Parent = pill
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(POPUP_DOT, POPUP_DOT)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.Parent = pill
	UiTheme.corner(dot, POPUP_DOT // 2)
	local label = UiTheme.text(pill, UiTheme.TextSize.Body, UiTheme.Font.Bold)
	label.Size = UDim2.fromOffset(0, space(7))
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextTruncate = Enum.TextTruncate.None
	label.Text = text

	local shown = {}
	for _, child in popups:GetChildren() do
		if child:IsA("Frame") then
			table.insert(shown, child)
		end
	end
	table.sort(shown, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 1, #shown - POPUP_MAX do
		shown[index]:Destroy()
	end

	task.delay(POPUP_SECONDS, function()
		if not pill.Parent then
			return
		end
		local info = TweenInfo.new(FADE_SECONDS)
		TweenService:Create(pill, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(dot, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		task.delay(FADE_SECONDS, function()
			pill:Destroy()
		end)
	end)
end

local function nameOf(who: Player): string
	return if who == player then "You" else who.DisplayName
end

downedEvent.OnClientEvent:Connect(function(kind: unknown, first: unknown, second: unknown)
	if kind == "Fallen" and typeof(first) == "Instance" and first:IsA("Player") then
		popup(if first == player then "You have fallen" else `{first.DisplayName} has fallen`, UiTheme.Enemy)
	elseif
		kind == "Revived"
		and typeof(first) == "Instance"
		and first:IsA("Player")
		and typeof(second) == "Instance"
		and second:IsA("Player")
	then
		local revived = if second == player then "you" else second.DisplayName
		popup(`{nameOf(first)} revived {revived}`, UiTheme.Ally)
		if second == player then
			announce({ headline = "YOU HAVE BEEN REVIVED", subline = `{first.DisplayName} brought you back` })
		end
	end
end)

pickedEvent.OnClientEvent:Connect(function(who: unknown, id: unknown)
	if not (typeof(who) == "Instance" and who:IsA("Player") and type(id) == "string") then
		return
	end
	for _, info in Config.Hero.Masteries do
		if info.id == id then
			popup(`{nameOf(who)} took {info.name}`, UiTheme.Gold)
			return
		end
	end
end)
