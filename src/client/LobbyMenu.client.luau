--!strict
-- The lobby menu (plan slice 2, docs/15_LOBBY_MATCHMAKING_PLAN.md; owner
-- 2026-10-23): everything the lobby offers without walking anywhere, in the
-- UI design system (docs/11_UI_DESIGN.md). Lobby only (GameContext).
--   * a menu bar down the left edge: Play, Classes, Stats, Equipment, Upgrades,
--     Shop, Settings. Play is green; the open panel's button is gold.
--     Clicking the open panel's button again closes it.
--   * one window in the middle (MenuKit.window: gold rim, blue body, title,
--     red X) showing one panel at a time; PanelRouter decides which.
-- Panels:
--   Play       only for picking (owner 2026-10-23): Create lobby: the map
--              on top (Config.Lobby.Maps), then how many players (1 to
--              Config.Lobby.MaxBattlePlayers), then Create lobby, which closes
--              the panel; the countdown shows on that dais's notice board
--              (Lobby.client). E on a dais with no room open opens it for that
--              dais; from the menu the server takes the first idle dais.
--              With nothing to create (already in a room, or every dais
--              busy) it only says to use a dais (E joins and leaves).
--              Requests go through LobbyRequest (Match.luau).
--   Classes    Mage (the only class so far, selected); Archer and Warrior
--              shown locked until they are built (T18).
--   Stats      your saved stats (PlayerData.server) and whether they are saved.
--   Equipment, Upgrades, Shop, Settings: not designed yet (OPEN); each says so.
-- Top right: short server messages (LobbyNotice) that fade after a few seconds.
-- Buttons are large for touch (48+ px at 1x, drawn at UiTheme.Scale).
-- Updates run only while their panel is open (Play's clock) or on change.
-- (Lobby parties with invites were built and then removed, owner 2026-10-23.)

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GameContext = require(ReplicatedStorage.Shared.GameContext)
local MenuKit = require(ReplicatedStorage.Shared.MenuKit)
local PanelRouter = require(ReplicatedStorage.Shared.PanelRouter)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local LobbyConfig = Config.Lobby
local Font = UiTheme.Font
local Size = UiTheme.TextSize
local Strength = UiTheme.Strength
local space = UiTheme.space

local NAV_WIDTH = 150
local NAV_BUTTON = 52 -- height
local ICON = 32
local WINDOW_WIDTH = 620
local WINDOW_HEIGHT = 420
local ACTION_WIDTH = 210
local ACTION_HEIGHT = 56
local CARD_HEIGHT = 56
local COUNT_BUTTON = 64 -- the 1-4 player buttons, square-ish

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local requestEvent = ReplicatedStorage:WaitForChild("LobbyRequest") :: RemoteEvent
local noticeEvent = ReplicatedStorage:WaitForChild("LobbyNotice") :: RemoteEvent
local lobby = Workspace:WaitForChild("Lobby")

-- The queue daises (Lobby.luau), each with its own lobby room (Match.luau).
local daises: { BasePart } = {}
for index in LobbyConfig.Pads do
	daises[index] = lobby:WaitForChild(`QueueDais{index}`) :: BasePart
end

-- A dais's room is "Idle" (nothing open) | "Open" | "Waiting".
local function isIdle(dais: Instance): boolean
	local value = dais:GetAttribute("RoomState")
	return value == nil or value == "Idle"
end

local function anyIdle(): boolean
	for _, dais in daises do
		if isIdle(dais) then
			return true
		end
	end
	return false
end

-- In one of the rooms (Match.luau's InRoom: the room's pad number).
local function inRoom(): boolean
	return player:GetAttribute("InRoom") ~= nil
end

-- The pad whose E opened the Create lobby panel (nil: opened from the menu,
-- the server then takes the first idle pad).
local createPad: number? = nil

local screen = Instance.new("ScreenGui")
screen.Name = "LobbyMenu"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 20
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui
GameContext.showIn(screen, "Lobby") -- lobby UI: hidden in the battle

-- Window ---------------------------------------------------------------------------------

local frame = MenuKit.window(screen, WINDOW_WIDTH, WINDOW_HEIGHT, "")
frame.window.Visible = false
frame.closeButton.Activated:Connect(PanelRouter.close)

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.fromScale(1, 1)
content.BackgroundTransparency = 1
content.Parent = frame.body
local contentPad = Instance.new("UIPadding")
contentPad.PaddingTop = UDim.new(0, MenuKit.PAD_TOP)
contentPad.PaddingBottom = UDim.new(0, MenuKit.PAD_BOTTOM)
contentPad.PaddingLeft = UDim.new(0, MenuKit.PAD)
contentPad.PaddingRight = UDim.new(0, MenuKit.PAD)
contentPad.Parent = content

-- A vertical list: a page inside the window (shown while its panel is open),
-- or a section of one.
local function list(parent: Instance, name: string, gap: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	return holder
end

local function page(name: string): Frame
	local holder = list(content, name, space(3))
	holder.Visible = false
	return holder
end

-- A line of text in a list that wraps and grows to fit (MenuKit flow rule).
local function line(parent: Instance, order: number, size: number, font: Font, strength: number?): TextLabel
	local label = UiTheme.text(parent, size, font, strength)
	label.LayoutOrder = order
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.None
	return label
end

-- A horizontal row of buttons in a list.
local function buttonRow(parent: Instance, order: number, height: number): Frame
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, height + space(2)) -- room for the hover growth
	row.BackgroundTransparency = 1
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, space(3))
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	return row
end

local function actionButton(row: Frame, order: number, fill: UiTheme.FillName, text: string): (TextButton, TextLabel)
	local button, label = MenuKit.button(row, fill, text)
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(ACTION_WIDTH, ACTION_HEIGHT)
	return button, label
end

-- A full-width card: an icon, a name and a short detail on the right. It
-- grows only a little on hover so it stays inside the window.
local function card(parent: Instance, order: number, icon: string, name: string): (TextButton, TextLabel, TextLabel)
	local button, nameLabel = MenuKit.button(parent, "Blue", name, Size.Title + 1, true)
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
	nameLabel.Position = UDim2.fromOffset(space(3) + ICON + space(3), 0)
	nameLabel.Size = UDim2.new(1, -(space(6) + ICON + 140), 1, 0)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	local iconLabel = UiTheme.text(button, 28, Font.Bold)
	iconLabel.Position = UDim2.fromOffset(space(3), 0)
	iconLabel.Size = UDim2.new(0, ICON, 1, 0)
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	iconLabel.Text = icon
	local detail = UiTheme.text(button, Size.Value + 1, Font.Bold)
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.new(1, -space(4), 0, 0)
	detail.Size = UDim2.new(0, 130, 1, 0)
	detail.TextXAlignment = Enum.TextXAlignment.Right
	return button, nameLabel, detail
end

local function request(action: string, ...: any)
	requestEvent:FireServer(action, ...)
end

-- Registers a panel whose page shows in the window under `title`.
-- `onShow` may return a cleanup run when the panel closes.
local function addPanel(name: string, title: string, holder: GuiObject, onShow: (() -> (() -> ())?)?)
	local cleanup: (() -> ())? = nil
	PanelRouter.register(name, {
		show = function()
			frame.titleLabel.Text = title
			holder.Visible = true
			frame.fitToScreen()
			frame.window.Visible = true
			cleanup = if onShow then onShow() else nil
		end,
		hide = function()
			holder.Visible = false
			frame.window.Visible = false
			if cleanup then
				local stop = cleanup
				cleanup = nil
				stop()
			end
		end,
	})
end

-- Play ------------------------------------------------------------------------------------

local playPage = page("Play")

-- Create lobby: the map on top, then how many players (owner 2026-10-23).
local createView = list(playPage, "Create", space(2))
createView.LayoutOrder = 1
local selectedMap = LobbyConfig.Maps[1].Id
local selectedCount = LobbyConfig.MaxBattlePlayers
line(createView, 1, Size.Small, Font.Bold).Text = "MAP"
type MapCard = { id: string, button: TextButton, detail: TextLabel }
local mapCards: { MapCard } = {}
local countButtons: { [number]: TextButton } = {}

local function refreshChoices()
	for _, entry in mapCards do
		local selected = entry.id == selectedMap
		UiTheme.setFill(entry.button, if selected then "Gold" else "Blue")
		entry.detail.Text = if selected then "Selected" else ""
	end
	for count, button in countButtons do
		UiTheme.setFill(button, if count == selectedCount then "Gold" else "Blue")
	end
end

for index, map in LobbyConfig.Maps do
	local button, _, detail = card(createView, 1 + index, "🗺️", map.Name)
	table.insert(mapCards, { id = map.Id, button = button, detail = detail })
	button.Activated:Connect(function()
		selectedMap = map.Id
		refreshChoices()
	end)
end
local afterMaps = 2 + #LobbyConfig.Maps
line(createView, afterMaps, Size.Small, Font.Bold).Text = "PLAYERS"
local countRow = buttonRow(createView, afterMaps + 1, ACTION_HEIGHT)
for count = 1, LobbyConfig.MaxBattlePlayers do
	local button = MenuKit.button(countRow, "Blue", tostring(count), Size.Heading)
	button.LayoutOrder = count
	button.Size = UDim2.fromOffset(COUNT_BUTTON, ACTION_HEIGHT)
	countButtons[count] = button
	button.Activated:Connect(function()
		selectedCount = count
		refreshChoices()
	end)
end
local createRow = buttonRow(createView, afterMaps + 2, ACTION_HEIGHT)
local createButton = actionButton(createRow, 1, "Green", "Create lobby")
createButton.Activated:Connect(function()
	request("Create", createPad, selectedMap, selectedCount)
	-- The panel only picks (owner 2026-10-23): it closes, and the countdown
	-- shows on that pad's notice board (Lobby.client).
	PanelRouter.close()
end)
refreshChoices()

-- While a room is open there is nothing to pick: the dais joins and leaves.
local openNote = line(playPage, 2, Size.Title, Font.Bold, Strength.Label)

local function refreshPlay()
	local pad = createPad
	local canCreate = not inRoom() and (if pad then isIdle(daises[pad]) else anyIdle())
	createView.Visible = canCreate
	openNote.Visible = not canCreate
	openNote.Text = if inRoom()
		then "You are in a lobby. Press E on its stone dais to leave it."
		elseif pad then "A lobby is already open on this dais. Press E to join it."
		else "Every dais has a lobby open. Press E on one to join it."
end

addPanel("Play", "Play", playPage, function()
	refreshPlay()
	-- Rooms open, fill and close while the panel may be open.
	local connections = { player:GetAttributeChangedSignal("InRoom"):Connect(refreshPlay) }
	for _, dais in daises do
		table.insert(connections, dais:GetAttributeChangedSignal("RoomState"):Connect(refreshPlay))
	end
	return function()
		createPad = nil -- the next time it opens from the menu, any pad
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end)

-- Classes -----------------------------------------------------------------------------------

type ClassInfo = { id: string, icon: string, name: string, playable: boolean, text: string }
-- Only the Mage is built (T18); how classes are chosen and unlocked is OPEN.
local CLASSES: { ClassInfo } = {
	{
		id = "Mage",
		icon = "⚡",
		name = "Mage",
		playable = true,
		text = "Ranged caster with the lowest health. Lightning Bolt (left click), Lightning Strike (Q), Teleport (E); Storm Banner makes our soldiers hit harder.",
	},
	{ id = "Archer", icon = "🏹", name = "Archer", playable = false, text = "Ranged and mobile. Not playable yet." },
	{ id = "Warrior", icon = "⚔️", name = "Warrior", playable = false, text = "Melee front line with the most health. Not playable yet." },
}

local classesPage = page("Classes")
local classInfo = line(classesPage, #CLASSES + 1, Size.Value, Font.Regular, Strength.Label)
local selectedClass = "Mage"
local shownClass = "Mage"
type ClassCard = { info: ClassInfo, button: TextButton, detail: TextLabel }
local classCards: { ClassCard } = {}

local function refreshClasses()
	for _, entry in classCards do
		local selected = entry.info.id == selectedClass
		UiTheme.setFill(entry.button, if selected then "Gold" elseif entry.info.playable then "Blue" else "Grey")
		UiTheme.setOutline(entry.button, if entry.info.id == shownClass and not selected then UiTheme.Text else UiTheme.Ink)
		entry.detail.Text = if selected then "Selected" elseif entry.info.playable then "" else "Coming later"
		if entry.info.id == shownClass then
			classInfo.Text = entry.info.text
		end
	end
end

for index, info in CLASSES do
	local button, nameLabel, detail = card(classesPage, index, info.icon, info.name)
	nameLabel.TextTransparency = if info.playable then Strength.Value else Strength.Faint
	table.insert(classCards, { info = info, button = button, detail = detail })
	button.Activated:Connect(function()
		shownClass = info.id
		if info.playable then
			selectedClass = info.id -- only the Mage so far; picking with the server comes with T18
		end
		refreshClasses()
	end)
end
refreshClasses()

addPanel("Classes", "Classes", classesPage)

-- Stats --------------------------------------------------------------------------------------

-- Saved per player by PlayerData.server (Record<...> attributes, DataStatus).
local STAT_ROW_HEIGHT = 32
local STAT_ROWS: { { label: string, attribute: string, time: boolean? } } = {
	{ label = "Battles played", attribute = "RecordGames" },
	{ label = "Wins", attribute = "RecordWins" },
	{ label = "Losses", attribute = "RecordLosses" },
	{ label = "Zombies killed", attribute = "RecordKills" },
	{ label = "Zombie Cores earned", attribute = "RecordZombieCores" },
	{ label = "Best level", attribute = "RecordBestLevel" },
	{ label = "Time in battle", attribute = "RecordBattleSeconds", time = true },
}
local STATUS_TEXT: { [string]: string } = {
	Loading = "Loading your stats…",
	Saved = "Saved to your account.",
	Unsaved = "Not being saved right now (saving is unavailable); battles still count while you stay.",
}

local statsPage = page("Stats")
-- A light block with one row per stat: the label in ink, the value outlined.
local statsBlock = UiTheme.block(statsPage, "Light", UiTheme.Radius)
statsBlock.LayoutOrder = 1
statsBlock.Size = UDim2.new(1, 0, 0, #STAT_ROWS * STAT_ROW_HEIGHT + space(3))
UiTheme.setOutline(statsBlock, UiTheme.Ink, UiTheme.OutlineThin)
local statValues: { TextLabel } = {}
for index, entry in STAT_ROWS do
	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(space(3), space(1) + 2 + (index - 1) * STAT_ROW_HEIGHT)
	row.Size = UDim2.new(1, -space(6), 0, STAT_ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.Parent = statsBlock
	local label = UiTheme.text(row, Size.Value, Font.Medium)
	label.Size = UDim2.fromScale(0.65, 1)
	label.Text = entry.label
	UiTheme.inkText(label)
	local value = UiTheme.text(row, Size.Value + 1, Font.Bold)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	value.Size = UDim2.fromScale(0.35, 1)
	value.TextXAlignment = Enum.TextXAlignment.Right
	statValues[index] = value
end
local statsStatus = line(statsPage, 2, Size.Small, Font.Medium, Strength.Label)

-- 3725 seconds -> "1h 2m"; 95 -> "1m".
local function duration(seconds: number): string
	local minutes = math.floor(seconds / 60)
	return if minutes >= 60 then `{minutes // 60}h {minutes % 60}m` else `{minutes}m`
end

local function refreshStats()
	for index, entry in STAT_ROWS do
		local value = player:GetAttribute(entry.attribute)
		local number = if type(value) == "number" and value == value then value else 0
		statValues[index].Text = if entry.time then duration(number) else MenuKit.formatNumber(number)
	end
	local status = player:GetAttribute("DataStatus")
	statsStatus.Text = if type(status) == "string" then STATUS_TEXT[status] or "" else STATUS_TEXT.Loading
end

addPanel("Stats", "Stats", statsPage, function()
	refreshStats()
	local connection = player.AttributeChanged:Connect(function(name: string)
		if name == "DataStatus" or string.sub(name, 1, 6) == "Record" then
			refreshStats()
		end
	end)
	return function()
		connection:Disconnect()
	end
end)

-- Not designed yet --------------------------------------------------------------------------

local function notYet(name: string, text: string)
	local holder = page(name)
	local label = line(holder, 1, Size.Title, Font.Bold, Strength.Label)
	label.Text = text
	addPanel(name, name, holder)
end
-- Catalogues, prices and settings are OPEN (docs/01_BRIEF.md).
notYet("Equipment", "Weapons and gear for your class will be equipped here. There is no gear yet.")
notYet("Upgrades", "Permanent upgrades for your heroes will be bought here. None are available yet.")
notYet("Shop", "Gear will be bought here with the rewards you earn in battle. The shop is not open yet.")
notYet("Settings", "No settings yet.")

-- Messages (top right) -----------------------------------------------------------------------

local NOTICE_WIDTH = 320
local NOTICE_SECONDS = 3
local MAX_TOASTS = 3

local notices = Instance.new("Frame")
notices.Name = "Notices"
notices.AnchorPoint = Vector2.new(1, 0)
notices.Position = UDim2.new(1, -space(4), 0, space(4))
notices.Size = UDim2.fromOffset(NOTICE_WIDTH, 0)
notices.AutomaticSize = Enum.AutomaticSize.Y
notices.BackgroundTransparency = 1
notices.ZIndex = 3 -- above the window and the menu bar
notices.Parent = screen
UiTheme.applyScale(notices)
local noticeLayout = Instance.new("UIListLayout")
noticeLayout.Padding = UDim.new(0, space(2))
noticeLayout.SortOrder = Enum.SortOrder.LayoutOrder
noticeLayout.Parent = notices

local noticeOrder = 0
local toasts: { Frame } = {}

local function toast(text: string)
	noticeOrder += 1
	local block = UiTheme.panel(notices)
	block.LayoutOrder = noticeOrder
	block.Size = UDim2.fromScale(1, 0)
	block.AutomaticSize = Enum.AutomaticSize.Y
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, space(2))
	pad.PaddingBottom = UDim.new(0, space(2))
	pad.PaddingLeft = UDim.new(0, space(3))
	pad.PaddingRight = UDim.new(0, space(3))
	pad.Parent = block
	local label = UiTheme.text(block, Size.Body, Font.Bold)
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.None
	label.Text = text
	table.insert(toasts, block)
	if #toasts > MAX_TOASTS then
		local oldest = table.remove(toasts, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(NOTICE_SECONDS, function()
		local index = table.find(toasts, block)
		if index then
			table.remove(toasts, index)
			block:Destroy()
		end
	end)
end

noticeEvent.OnClientEvent:Connect(function(text: unknown)
	if type(text) == "string" and GameContext.is("Lobby") then
		toast(text)
	end
end)

-- Going into a battle drops the messages.
GameContext.during("Lobby", function()
	return function()
		for _, block in toasts do
			block:Destroy()
		end
		table.clear(toasts)
	end
end)

-- Menu bar ------------------------------------------------------------------------------------

type NavEntry = { id: string, icon: string, idle: UiTheme.FillName }
local NAV: { NavEntry } = {
	{ id = "Play", icon = "⚔️", idle = "Green" },
	{ id = "Classes", icon = "🧙", idle = "Blue" },
	{ id = "Stats", icon = "📊", idle = "Blue" },
	{ id = "Equipment", icon = "🛡️", idle = "Blue" },
	{ id = "Upgrades", icon = "⭐", idle = "Blue" },
	{ id = "Shop", icon = "🛒", idle = "Blue" },
	{ id = "Settings", icon = "⚙️", idle = "Blue" },
}

local nav = Instance.new("Frame")
nav.Name = "Nav"
nav.AnchorPoint = Vector2.new(0, 0.5)
nav.Position = UDim2.new(0, space(4), 0.5, 0)
nav.Size = UDim2.fromOffset(NAV_WIDTH, #NAV * NAV_BUTTON + (#NAV - 1) * space(2))
nav.BackgroundTransparency = 1
nav.ZIndex = 2 -- above the window where they overlap on a small screen
nav.Parent = screen
UiTheme.applyScale(nav)
local navLayout = Instance.new("UIListLayout")
navLayout.Padding = UDim.new(0, space(2))
navLayout.SortOrder = Enum.SortOrder.LayoutOrder
navLayout.Parent = nav

local navButtons: { [string]: { button: TextButton, entry: NavEntry } } = {}
for index, entry in NAV do
	local button, label = MenuKit.button(nav, entry.idle, entry.id, Size.Title)
	button.LayoutOrder = index
	button.Size = UDim2.new(1, 0, 0, NAV_BUTTON)
	label.Position = UDim2.fromOffset(space(2) + ICON + space(1), 0)
	label.Size = UDim2.new(1, -(space(3) + ICON + space(1)), 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	local icon = UiTheme.text(button, 22, Font.Bold)
	icon.Position = UDim2.fromOffset(space(2), 0)
	icon.Size = UDim2.new(0, ICON, 1, 0)
	icon.TextXAlignment = Enum.TextXAlignment.Center
	icon.Text = entry.icon
	button.Activated:Connect(function()
		PanelRouter.toggle(entry.id)
	end)
	navButtons[entry.id] = { button = button, entry = entry }
end

PanelRouter.changed:Connect(function(open: string?)
	for id, item in navButtons do
		UiTheme.setFill(item.button, if id == open then "Gold" else item.entry.idle)
	end
end)

-- E on a dais with no room open shows the same Play panel (one code path)
-- to create one there; with a room open the server joins or leaves it
-- (Match.toggleRoom) and no panel opens (owner 2026-10-23).
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
	local dais = prompt.Parent
	local pad = if dais then dais:GetAttribute("Pad") else nil
	if prompt:IsDescendantOf(lobby) and prompt.Name == "QueuePrompt" and dais and type(pad) == "number" and isIdle(dais) and not inRoom() then
		PanelRouter.close() -- reopen for this pad even if Play was open for another
		createPad = pad
		PanelRouter.open("Play")
	end
end)

UiTheme.onScreenResize(function()
	if frame.window.Visible then
		frame.fitToScreen()
	end
end)
