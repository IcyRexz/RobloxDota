--!strict
-- Announcement banner just left of the core strip (CoreStrip.client), its
-- top level with the strip's, growing leftward toward the party portraits
-- (owner 2026-10-23: at the top middle it covered the target panel; option A
-- of five). In the game's UI design system (docs/11_UI_DESIGN.md): a block
-- with a white headline and a dimmer subline, centred in it (owner
-- 2026-10-23). It is as wide as its text, but never wider than the gap between
-- the portraits and the strip: longer lines wrap. E.g.
--   Zombies lost a core
--   Enemy core destroyed
-- No team colours. Banners queue, so two quick events show one after another.
-- Battlefield events and arrivals use a red block (owner 2026-10-23); every
-- other banner stays navy.
-- Also small popups on the right (owner 2026-10-23) when a player falls or is
-- revived ("Bob has fallen", "Zac revived Bob") or picks a mastery ("Zac took
-- Chain Bolt", gold dot), or one of our buildings is under attack ("Base Core
-- under attack", red dot; owner 2026-10-23: at most once per building every
-- Config.Display.UnderAttackCooldown seconds), stacked, each fading after a
-- few seconds; the revived player also gets a "YOU HAVE BEEN REVIVED" banner.
-- Display only: the server decides when a structure is destroyed, who falls
-- and who is revived (HeroDowned, from Heroes.server).

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GameContext = require(ReplicatedStorage.Shared.GameContext)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local space = UiTheme.space
local SHOW_SECONDS = 3
local FADE_SECONDS = 0.25
local POPUP_SECONDS = 4
local POPUP_MAX = 4 -- older popups are dropped beyond this
local POPUP_DOT = 10
local BANNER_PAD_X = space(6) -- each side, at 1x
local BANNER_MIN_WIDTH = 160 -- at 1x; on a very narrow window it may reach the portraits
local HEADLINE_SIZE = 22
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
screen.IgnoreGuiInset = true -- measured from the very top, like the core strip
screen.Parent = player:WaitForChild("PlayerGui")
GameContext.showIn(screen, "Battle") -- battle UI: hidden in the lobby

local banner = UiTheme.panel(screen, nil, UiTheme.RadiusLarge)
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(1, 0)
banner.Size = UDim2.fromOffset(BANNER_MIN_WIDTH, 0)
banner.AutomaticSize = Enum.AutomaticSize.Y
banner.Visible = false
UiTheme.applyScale(banner)
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, space(3))
pad.PaddingBottom = UDim.new(0, space(3))
pad.PaddingLeft = UDim.new(0, BANNER_PAD_X)
pad.PaddingRight = UDim.new(0, BANNER_PAD_X)
pad.Parent = banner
local layout = Instance.new("UIListLayout")
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 2)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = banner

local function line(order: number, size: number, weight: Font, strength: number): TextLabel
	local label = UiTheme.text(banner, size, weight, strength)
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, size + 4)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.None
	label.TextXAlignment = Enum.TextXAlignment.Center
	return label
end
local headline = line(1, HEADLINE_SIZE, UiTheme.Font.Heavy, UiTheme.Strength.Value)
local subline = line(2, UiTheme.TextSize.Body, UiTheme.Font.Medium, UiTheme.Strength.Label)

-- One line's width at 1x, unwrapped (0 if it cannot be measured).
local function textWidth(text: string, font: Font, size: number): number
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = font
	params.Size = size
	params.Width = math.huge
	local ok, bounds = pcall(function(): Vector2
		return TextService:GetTextBoundsAsync(params)
	end)
	return if ok then math.ceil(bounds.X) + 4 else 0 -- + the text outline
end

-- The text width the current banner wants at 1x (measured once per banner).
local wantedWidth = BANNER_MIN_WIDTH

-- Places the banner left of the core strip and sizes it to its text, capped
-- at the room left between the party portraits and the strip.
local function layoutBanner()
	local camera = Workspace.CurrentCamera
	local screenWidth = if camera then camera.ViewportSize.X else 0
	local factor = UiTheme.Scale * UiTheme.screenFactor()
	local stripLeft = screenWidth / 2 - UiTheme.CoreStripWidth / 2 * factor
	local partyRight = space(3) + UiTheme.PartyColumnWidth * factor
	local room = (stripLeft - space(3) - partyRight - space(3)) / factor
	local width = math.max(math.min(wantedWidth, room), BANNER_MIN_WIDTH)
	banner.Position = UDim2.new(0.5, -(UiTheme.CoreStripWidth / 2 * factor + space(3)), 0, space(3))
	banner.Size = UDim2.fromOffset(width, 0)
end
UiTheme.onScreenResize(layoutBanner)

local function fadeTo(visible: boolean)
	local info = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(banner, info, {
		BackgroundTransparency = if visible then UiTheme.SurfaceTransparency else 1,
	}):Play()
	TweenService:Create(headline, info, { TextTransparency = if visible then UiTheme.Strength.Value else 1 }):Play()
	TweenService:Create(subline, info, { TextTransparency = if visible then UiTheme.Strength.Label else 1 }):Play()
end

-- Queue ----------------------------------------------------------------------------

type Message = { headline: string, subline: string, fill: UiTheme.FillName? }
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
	wantedWidth = math.max(
		textWidth(message.headline, UiTheme.Font.Heavy, HEADLINE_SIZE),
		textWidth(message.subline, UiTheme.Font.Medium, UiTheme.TextSize.Body)
	) + BANNER_PAD_X * 2
	layoutBanner()
	UiTheme.setFill(banner, message.fill or "Navy")
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
				then { headline = string.upper(info.name), subline = info.text, fill = "Red" }
				else { headline = `{info.name} is over`, subline = "Zombies are back to normal", fill = "Red" })
			return
		end
	end
	for _, arrival in Config.Events.Arrivals do
		if arrival.id == id and phase == "Start" then
			announce({ headline = string.upper(arrival.name), subline = arrival.text, fill = "Red" })
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

-- Under attack: one of our buildings losing health (its Health attribute
-- going down) shows a popup, at most once per building per cooldown.
local UNDER_ATTACK_NAMES: { [string]: string } = { Core = "Base Core", Barracks = "Barracks", Tower = "Tower" }
local lastAlertAt: { [Instance]: number } = {}
local function watchBuilding(item: Instance)
	local kind = item:GetAttribute("Kind")
	if not (item:IsA("BasePart") and type(kind) == "string" and UNDER_ATTACK_NAMES[kind] and item:GetAttribute("Team") == DEFENDERS) then
		return
	end
	local function health(): number
		local value = item:GetAttribute("Health")
		return if type(value) == "number" then value else 0
	end
	local last = health()
	item:GetAttributeChangedSignal("Health"):Connect(function()
		local now = health()
		local hit = now < last
		last = now
		if not hit or now <= 0 or Workspace:GetAttribute("MatchResult") ~= nil then
			return
		end
		local clock = os.clock()
		if clock - (lastAlertAt[item] or -math.huge) >= Config.Display.UnderAttackCooldown then
			lastAlertAt[item] = clock
			popup(`{UNDER_ATTACK_NAMES[kind]} under attack`, UiTheme.Enemy)
		end
	end)
	item.Destroying:Connect(function()
		lastAlertAt[item] = nil
	end)
end
local arena = Workspace:WaitForChild("Arena")
for _, item in arena:GetDescendants() do
	watchBuilding(item)
end
-- Buildings put back by the battlefield reset (T15) arrive as new parts.
arena.DescendantAdded:Connect(watchBuilding)
