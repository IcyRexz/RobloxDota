--!strict
-- Party list and Tab scoreboard (owner 2026-10-21, Dota-like), top left, in the
-- game's UI design system (docs/11_UI_DESIGN.md, values from UiTheme).
--  * Always on: every player in the match stacked vertically, you first: a
--    round portrait, the level in a small gold-rimmed circle under it, and a
--    thin health bar (green). While down (owner 2026-10-23) the portrait greys
--    out under a dark wedge that shrinks with the respawn countdown, with the
--    seconds left on it; while an ally revives them the ring turns green and
--    the wedge shows the revive filling instead.
--  * Hold Tab: the scoreboard replaces it: one row per player with portrait,
--    name and class, level, kills, masteries picked (one chip per mastery
--    level: initials in gold once picked, faint while still open). No Gold
--    column (owner 2026-10-23: the Gold counter shows your own).
--    Your own row is lit. Release Tab to go back.
-- Roblox's own player list (also on Tab) is turned off. Reads only replicated
-- attributes (Player: Level, Kills, Mastery<id>, InParty; character: Health,
-- MaxHealth, HeroName, DownedAt, RespawnAt, ReviveStartedAt). Display only.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameContext = require(ReplicatedStorage.Shared.GameContext)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Font = UiTheme.Font
local Size = UiTheme.TextSize
local Strength = UiTheme.Strength
local space = UiTheme.space
local Hero = Config.Hero

local PORTRAIT = 44
local BADGE = 18
local PARTY_ITEM_HEIGHT = PORTRAIT + BADGE // 2 + space(2) + UiTheme.Bar.Unit
local HEADER_HEIGHT = 18
local ROW_HEIGHT = 40
local ROW_PORTRAIT = 30
local CHIP = 22
local CHIP_GAP = 6
local REFRESH_SECONDS = 0.2
local BOARD_PAD = space(4) -- panel edge to rows
local ROW_INSET = space(3) -- row edge to its first and last column
local COLUMN_GAP = space(6) -- even space between columns
local SCREEN_MARGIN = space(3) -- the board never comes closer to the screen edge

-- Scoreboard columns, left to right: x offset and width (pixels before scaling).
type Column = { x: number, width: number }
local function columns(widths: { number }): { Column }
	local list: { Column } = {}
	local x = ROW_INSET
	for _, width in widths do
		table.insert(list, { x = x, width = width })
		x += width + COLUMN_GAP
	end
	return list
end
local MASTERY_WIDTH = #Hero.MasteryLevels * (CHIP + CHIP_GAP) - CHIP_GAP
local layout = columns({ 200, 36, 52, MASTERY_WIDTH })
local COLUMNS = {
	player = layout[1],
	level = layout[2],
	kills = layout[3],
	masteries = layout[4],
}
local ROW_WIDTH = COLUMNS.masteries.x + COLUMNS.masteries.width + ROW_INSET
local BOARD_WIDTH = ROW_WIDTH + BOARD_PAD * 2

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

-- Helpers ---------------------------------------------------------------------------

local function readNumber(target: Instance, name: string): number
	local value = target:GetAttribute(name)
	return if type(value) == "number" and value == value then value else 0
end

-- "Chain Bolt" -> "CB", "Vitality" -> "VI".
local function initials(name: string): string
	local letters = ""
	for word in name:gmatch("%a+") do
		letters ..= word:sub(1, 1)
	end
	return string.upper(if #letters >= 2 then letters:sub(1, 2) else name:sub(1, 2))
end

-- Masteries a player has picked, in grid order.
local function picked(owner: Player): { Config.MasteryInfo }
	local list: { Config.MasteryInfo } = {}
	for _, info in Hero.Masteries do
		if owner:GetAttribute("Mastery" .. info.id) == true then
			table.insert(list, info)
		end
	end
	return list
end

-- A round portrait: the player's headshot, or their initial until it loads
-- (or if it cannot load, e.g. test players in Studio).
local portraitCache: { [number]: string } = {}
local function portrait(parent: Instance, owner: Player, size: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromOffset(size, size)
	image.BackgroundColor3 = UiTheme.Surface
	image.BackgroundTransparency = UiTheme.SurfaceTransparency
	image.BorderSizePixel = 0
	image.Parent = parent
	UiTheme.corner(image, size // 2)
	local ring = Instance.new("UIStroke")
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Color = UiTheme.Text
	ring.Transparency = 0.75
	ring.Thickness = 1.5
	ring.Parent = image
	local letter = UiTheme.text(image, math.floor(size * 0.45), Font.Heavy, Strength.Label)
	letter.Size = UDim2.fromScale(1, 1)
	letter.TextXAlignment = Enum.TextXAlignment.Center
	letter.Text = string.upper(owner.DisplayName:sub(1, 1))
	task.spawn(function()
		local content = portraitCache[owner.UserId]
		if not content and owner.UserId > 0 then
			local ok, result = pcall(function()
				return Players:GetUserThumbnailAsync(owner.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok then
				content = result
				portraitCache[owner.UserId] = result
			end
		end
		if content and image.Parent then
			image.Image = content
			letter.Visible = false
		end
	end)
	return image
end

local screen = Instance.new("ScreenGui")
screen.Name = "Scoreboard"
screen.ResetOnSpawn = false
screen.DisplayOrder = 5
screen.Parent = playerGui
GameContext.showIn(screen, "Battle") -- battle UI: hidden in the lobby

-- Party list (always on) --------------------------------------------------------------

local party = Instance.new("Frame")
party.Name = "Party"
party.Position = UDim2.fromOffset(space(3), space(3))
party.Size = UDim2.fromOffset(PORTRAIT + 8, 0)
party.AutomaticSize = Enum.AutomaticSize.Y
party.BackgroundTransparency = 1
party.Parent = screen
UiTheme.applyScale(party)
local partyLayout = Instance.new("UIListLayout")
partyLayout.Padding = UDim.new(0, space(3))
partyLayout.SortOrder = Enum.SortOrder.LayoutOrder
partyLayout.Parent = party

-- Scoreboard (hold Tab) ---------------------------------------------------------------

local board = UiTheme.panel(screen, UiTheme.MenuTransparency, UiTheme.RadiusLarge)
board.Name = "Board"
board.Position = UDim2.fromOffset(space(3), space(3))
board.Size = UDim2.fromOffset(BOARD_WIDTH, 0)
board.AutomaticSize = Enum.AutomaticSize.Y
board.Visible = false
local boardScale = UiTheme.applyScale(board)
local boardPad = Instance.new("UIPadding")
boardPad.PaddingTop = UDim.new(0, BOARD_PAD)
boardPad.PaddingBottom = UDim.new(0, BOARD_PAD)
boardPad.PaddingLeft = UDim.new(0, BOARD_PAD)
boardPad.PaddingRight = UDim.new(0, BOARD_PAD)
boardPad.Parent = board
local boardLayout = Instance.new("UIListLayout")
boardLayout.Padding = UDim.new(0, space(1))
boardLayout.SortOrder = Enum.SortOrder.LayoutOrder
boardLayout.Parent = board

-- Full size (UiTheme.Scale) when the screen has room, smaller on narrow or
-- short screens so the whole board stays on screen.
local function fitBoard()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local rows = 0
	for _, owner in Players:GetPlayers() do
		if owner:GetAttribute("InParty") == true then
			rows += 1
		end
	end
	local height = BOARD_PAD * 2 + HEADER_HEIGHT + rows * (ROW_HEIGHT + space(1))
	boardScale.Scale = math.min(
		UiTheme.Scale * UiTheme.screenFactor(),
		(viewport.X - SCREEN_MARGIN * 2) / BOARD_WIDTH,
		(viewport.Y - SCREEN_MARGIN * 2) / height
	)
end

local function cell(parent: Instance, column: Column, size: number, weight: Font, strength: number?): TextLabel
	local label = UiTheme.text(parent, size, weight, strength)
	label.Position = UDim2.fromOffset(column.x, 0)
	label.Size = UDim2.new(0, column.width, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center
	return label
end

-- Header captions.
local header = Instance.new("Frame")
header.Name = "Header"
header.LayoutOrder = 0
header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
header.BackgroundTransparency = 1
header.Parent = board
local playerCaption = cell(header, COLUMNS.player, Size.Caption, Font.Bold, Strength.Faint)
playerCaption.TextXAlignment = Enum.TextXAlignment.Left
playerCaption.Text = "PLAYER"
cell(header, COLUMNS.level, Size.Caption, Font.Bold, Strength.Faint).Text = "LV"
cell(header, COLUMNS.kills, Size.Caption, Font.Bold, Strength.Faint).Text = "KILLS"
cell(header, COLUMNS.masteries, Size.Caption, Font.Bold, Strength.Faint).Text = "MASTERIES"

board.Parent = screen

-- Entries ---------------------------------------------------------------------------

type Entry = {
	owner: Player,
	partyItem: Frame,
	partyPortrait: ImageLabel,
	partyCover: (number, string) -> (),
	partyLevel: TextLabel,
	partyHealth: UiTheme.Bar,
	row: Frame,
	name: TextLabel,
	class: TextLabel,
	level: TextLabel,
	kills: TextLabel,
	chips: { TextLabel },
}
local entries: { [Player]: Entry } = {}

local function addEntry(owner: Player)
	if entries[owner] then
		return
	end
	local order = if owner == player then 0 else 1

	-- Party item: portrait, level circle on its lower edge, health bar.
	local item = Instance.new("Frame")
	item.Name = owner.Name
	item.LayoutOrder = order
	item.Size = UDim2.fromOffset(PORTRAIT + 8, PARTY_ITEM_HEIGHT)
	item.BackgroundTransparency = 1
	item.Parent = party
	local partyPortrait = portrait(item, owner, PORTRAIT)
	partyPortrait.Position = UDim2.fromOffset(4, 0)
	local partyCover = UiTheme.radialCover(partyPortrait, PORTRAIT // 2, Size.Title)
	partyCover(0, "")
	local badge = UiTheme.panel(item, 0.1, BADGE // 2)
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromOffset(4 + PORTRAIT / 2, PORTRAIT)
	badge.Size = UDim2.fromOffset(BADGE, BADGE)
	badge.ZIndex = 3
	local badgeRing = Instance.new("UIStroke")
	badgeRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	badgeRing.Color = UiTheme.Gold
	badgeRing.Thickness = 1.5
	badgeRing.Parent = badge
	local partyLevel = UiTheme.text(badge, Size.Caption, Font.Heavy)
	partyLevel.Size = UDim2.fromScale(1, 1)
	partyLevel.TextXAlignment = Enum.TextXAlignment.Center
	partyLevel.ZIndex = 4
	local partyHealth = UiTheme.bar(item, UiTheme.Bar.Unit, UiTheme.Ally)
	partyHealth.track.Position = UDim2.fromOffset(4, PORTRAIT + BADGE // 2 + space(2))
	partyHealth.track.Size = UDim2.fromOffset(PORTRAIT, UiTheme.Bar.Unit)

	-- Scoreboard row.
	local row = Instance.new("Frame")
	row.Name = owner.Name
	row.LayoutOrder = order + 1
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = UiTheme.Raised
	row.BackgroundTransparency = if owner == player then UiTheme.RaisedHoverTransparency else 1
	row.BorderSizePixel = 0
	row.Parent = board
	UiTheme.corner(row)
	local rowPortrait = portrait(row, owner, ROW_PORTRAIT)
	rowPortrait.Position = UDim2.fromOffset(COLUMNS.player.x, (ROW_HEIGHT - ROW_PORTRAIT) // 2)
	local textX = COLUMNS.player.x + ROW_PORTRAIT + space(2)
	local textWidth = COLUMNS.player.x + COLUMNS.player.width - textX
	local name = UiTheme.text(row, Size.Body, Font.Heavy)
	name.Position = UDim2.fromOffset(textX, 4)
	name.Size = UDim2.fromOffset(textWidth, 18)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = owner.DisplayName
	local class = UiTheme.text(row, Size.Small, Font.Medium, Strength.Label)
	class.Position = UDim2.fromOffset(textX, 21)
	class.Size = UDim2.fromOffset(textWidth, 14)
	local level = cell(row, COLUMNS.level, Size.Value, Font.Heavy)
	level.TextColor3 = UiTheme.Gold
	local kills = cell(row, COLUMNS.kills, Size.Value, Font.Bold)
	local chips: { TextLabel } = {}
	for index = 1, #Hero.MasteryLevels do
		local chip = UiTheme.text(row, Size.Caption - 1, Font.Heavy)
		chip.Position = UDim2.fromOffset(COLUMNS.masteries.x + (index - 1) * (CHIP + CHIP_GAP), (ROW_HEIGHT - CHIP) // 2)
		chip.Size = UDim2.fromOffset(CHIP, CHIP)
		chip.TextXAlignment = Enum.TextXAlignment.Center
		chip.BackgroundColor3 = UiTheme.Raised
		chip.BorderSizePixel = 0
		UiTheme.corner(chip, 6)
		local chipLine = Instance.new("UIStroke")
		chipLine.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		chipLine.Thickness = 1
		chipLine.Parent = chip
		table.insert(chips, chip)
	end

	entries[owner] = {
		owner = owner,
		partyItem = item,
		partyPortrait = partyPortrait,
		partyCover = partyCover,
		partyLevel = partyLevel,
		partyHealth = partyHealth,
		row = row,
		name = name,
		class = class,
		level = level,
		kills = kills,
		chips = chips,
	}
end

local function removeEntry(owner: Player)
	local entry = entries[owner]
	if entry then
		entry.partyItem:Destroy()
		entry.row:Destroy()
		entries[owner] = nil
	end
end

local function refreshEntry(entry: Entry)
	local owner = entry.owner
	-- Only the players in this battle (not those waiting in the lobby).
	local inBattle = owner:GetAttribute("InParty") == true
	entry.partyItem.Visible = inBattle
	entry.row.Visible = inBattle
	if not inBattle then
		return
	end
	local character = owner.Character
	local level = math.max(math.floor(readNumber(owner, "Level")), 1)
	local health = if character then readNumber(character, "Health") else 0
	local maxHealth = if character then readNumber(character, "MaxHealth") else 0
	local share = if maxHealth > 0 then math.clamp(health / maxHealth, 0, 1) else 0
	local alive = share > 0

	entry.partyLevel.Text = tostring(level)
	entry.partyHealth.fill.Size = UDim2.fromScale(share, 1)
	entry.partyPortrait.ImageTransparency = if alive then 0 else 0.6
	entry.partyPortrait.ImageColor3 = if alive then Color3.new(1, 1, 1) else Color3.fromRGB(120, 120, 120)
	-- Down: countdown wedge and seconds; being revived: green ring, revive wedge.
	local now = Workspace:GetServerTimeNow()
	local downedAt = if character and not alive then readNumber(character, "DownedAt") else 0
	local respawnAt = if character then readNumber(character, "RespawnAt") else 0
	local reviveStartedAt = if character and not alive then readNumber(character, "ReviveStartedAt") else 0
	local ring = entry.partyPortrait:FindFirstChildOfClass("UIStroke")
	if downedAt > 0 and respawnAt > downedAt then
		local left = math.max(respawnAt - now, 0)
		local wedge = if reviveStartedAt > 0
			then 1 - math.clamp((now - reviveStartedAt) / Hero.Death.ReviveHold, 0, 1)
			else left / (respawnAt - downedAt)
		entry.partyCover(wedge, if left > 0 then tostring(math.ceil(left)) else "")
	else
		entry.partyCover(0, "")
	end
	if ring then
		local reviving = reviveStartedAt > 0
		ring.Color = if reviving then UiTheme.Ally else UiTheme.Text
		ring.Transparency = if reviving then 0 else 0.75
		ring.Thickness = if reviving then 2.5 else 1.5
	end

	if not board.Visible then
		return
	end
	local heroName = if character then character:GetAttribute("HeroName") else nil
	entry.class.Text = if type(heroName) == "string" then heroName else Hero.Name
	entry.level.Text = tostring(level)
	entry.kills.Text = tostring(math.floor(readNumber(owner, "Kills")))
	local taken = picked(owner)
	for index, chip in entry.chips do
		local info = taken[index]
		chip.Text = if info then initials(info.name) else ""
		chip.TextColor3 = UiTheme.Gold
		chip.BackgroundTransparency = if info then UiTheme.RaisedHoverTransparency else UiTheme.DisabledTransparency
		-- Picked: gold outline. Open: a faint empty slot.
		local line = chip:FindFirstChildOfClass("UIStroke")
		if line then
			line.Color = if info then UiTheme.Gold else UiTheme.Text
			line.Transparency = if info then 0.3 else 0.82
		end
	end
end

local function refreshAll()
	for _, entry in entries do
		refreshEntry(entry)
	end
end

for _, owner in Players:GetPlayers() do
	addEntry(owner)
end
Players.PlayerAdded:Connect(addEntry)
Players.PlayerRemoving:Connect(removeEntry)

-- Hold Tab ----------------------------------------------------------------------------

local function setBoard(open: boolean)
	board.Visible = open
	party.Visible = not open
	refreshAll()
	if open then
		fitBoard()
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Tab and not gameProcessed and GameContext.is("Battle") then
		setBoard(true)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Tab then
		setBoard(false)
	end
end)

GameContext.every("Battle", REFRESH_SECONDS, refreshAll)
-- Back in the lobby: close the board (Tab may still be held).
GameContext.during("Battle", function()
	return function()
		setBoard(false)
	end
end)
