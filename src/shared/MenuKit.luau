--!strict
-- The one layout every full menu uses (owner 2026-10-21: the Base Upgrades
-- page must look and be organised like the Character Menu; blocky restyle
-- owner 2026-10-22), built from UiTheme values (docs/11_UI_DESIGN.md). Both
-- CharacterMenu.client and BaseUpgradeMenu.client build their window from
-- these pieces only. The top of the left column comes in two kinds;
-- everything else is shared:
--
--   Title (on the gold rim, flush left)                                 [X]
--   left column (34%)                    right column (66%)
--   profile top:        picker top:       Heading [chip]              # # # #
--   +----------------+  CAPTION           +-- grid panel ---------------+
--   |[LV] Title      |  [icon Name  2/6]  | [tile] [tile] [tile]        |
--   |     subtitle   |  [icon Name  Lv2]  | [tile] [tile] [tile]        |
--   |     ==== XP ===|  [icon Name  0/6]  +-----------------------------+
--   +----------------+                    +-- info area ----------------+
--   CAPTION                               | Title              [button] |
--   +-- stat rows ---+                    | Improves: ...      [button] |
--   | label   value  |                    | body text                   |
--   +----------------+                    +-----------------------------+
--   CAPTION (profile only)                                    "X to close"
--   [slot][slot][slot][slot][slot]
--
-- Profile top (Character Menu): level ring, name, class, XP bar, then the
-- ABILITIES slot row under the stats. Picker top (Base Upgrades): full-width
-- cards to choose what the rest of the menu shows, and no slot row.
-- Tiles show only a name and an orange "Improves: ..." line (owner
-- 2026-10-22); the full text, the price and the buy / pick button are in the
-- info area under the grid. Hovering a slot, card or tile fills the info
-- area; there are no floating tooltips.
-- Text that can run to two lines (owner 2026-10-22: wrapped lines pushed things
-- out of place) is made with flow(): it grows to fit its lines inside a
-- UIListLayout, so a second line moves what follows down instead of
-- overlapping it or being cut off. The info area scrolls when its text is
-- longer than the space; text is never shrunk to fit.

local Workspace = game:GetService("Workspace")

local UiTheme = require(script.Parent.UiTheme)

local Font = UiTheme.Font
local Size = UiTheme.TextSize
local Strength = UiTheme.Strength
local space = UiTheme.space

local MenuKit = {}

-- A label in a vertical UIListLayout that wraps and grows to fit its lines.
local function flow(label: TextLabel, order: number): TextLabel
	label.LayoutOrder = order
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.None
	label.TextYAlignment = Enum.TextYAlignment.Top
	return label
end

-- A vertical stack for flow() labels.
local function stack(parent: Instance, gap: number)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
end

MenuKit.WIDTH = 900
MenuKit.HEIGHT = 600
MenuKit.LEFT_SHARE = 0.34
MenuKit.RIM = 6 -- the gold rim around the blue body
MenuKit.PAD = space(6) -- 24, column sides
MenuKit.PAD_TOP = space(9) -- 36, room under the title on the rim
MenuKit.PAD_BOTTOM = space(5) -- 20
MenuKit.ROW_HEIGHT = space(8) -- 32
MenuKit.STAT_ROWS = 5
MenuKit.SLOT_SIZE = 44
MenuKit.RING_SIZE = 56
MenuKit.PROFILE_HEIGHT = 80
MenuKit.CARD_HEIGHT = 56
MenuKit.GRID_TOP = space(12) -- 48, under the heading
MenuKit.GRID_PAD = space(2) + 2 -- 10, inside the grid panel
MenuKit.TILE_HEIGHT = 84
MenuKit.BUTTON_TILE_HEIGHT = 108 -- tiles with a price button at the bottom (Base Upgrades)
MenuKit.TILE_BUTTON_HEIGHT = 28
MenuKit.TILE_GAP = space(2) + 2 -- 10
MenuKit.COLUMNS = 3
MenuKit.INFO_BUTTON_WIDTH = 150

local CLOSE_HINT_SPACE = 22 -- kept free at the bottom of the right column
local CAPTION_HEIGHT = 18

local GOLD_HEX = UiTheme.Gold:ToHex()
MenuKit.GOLD_HEX = GOLD_HEX

local function padding(parent: Instance, top: number, side: number, bottom: number)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, top)
	pad.PaddingBottom = UDim.new(0, bottom)
	pad.PaddingLeft = UDim.new(0, side)
	pad.PaddingRight = UDim.new(0, side)
	pad.Parent = parent
end

local function caption(parent: Instance, label: string, y: number): TextLabel
	local title = UiTheme.text(parent, Size.Small, Font.Bold)
	title.Position = UDim2.fromOffset(0, y)
	title.Size = UDim2.new(1, 0, 0, CAPTION_HEIGHT)
	title.Text = label
	return title
end

-- A button made into a block, with no text of its own.
local function blockButton(parent: Instance, fill: UiTheme.FillName, radius: number?, thickness: number?): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundTransparency = 0
	button.Parent = parent
	UiTheme.styleBlock(button, fill, radius, thickness)
	return button
end

-- 60 -> "60", 202.5 -> "202.5", 1.3333 -> "1.33"
function MenuKit.formatNumber(value: number): string
	if math.abs(value - math.round(value)) < 0.005 then
		return tostring(math.round(value))
	end
	local trimmed = string.format("%.2f", value):gsub("0+$", "")
	return trimmed
end

export type Slot = { button: TextButton, label: TextLabel, selected: boolean }
export type Card = { button: TextButton, icon: TextLabel, name: TextLabel, detail: TextLabel, hover: boolean }
export type Tile = {
	button: TextButton,
	name: TextLabel,
	improves: TextLabel,
	check: Frame,
	price: TextButton, -- the small buy button (tileButtons menus only; hidden otherwise)
	priceText: TextLabel,
	hover: boolean,
	selected: boolean,
}
export type Options = {
	title: string, -- on the rim, top left
	statsCaption: string,
	closeText: string,
	-- Grid rows the info area sits under.
	gridRows: number,
	-- Tiles get a small price button at the bottom (Base Upgrades).
	tileButtons: boolean?,
	-- Profile top: the caption over the slot row (e.g. ABILITIES).
	slotsCaption: string?,
	-- Picker top instead: the caption over the cards and how many there are.
	pickerCaption: string?,
	pickerCount: number?,
	-- Stat rows in the left column (default STAT_ROWS).
	statRows: number?,
}
export type Menu = {
	screen: ScreenGui,
	window: Frame,
	left: Frame,
	right: Frame,
	titleLabel: TextLabel,
	closeButton: TextButton,
	-- left column, profile top (hidden with a picker top)
	ringCaption: TextLabel, -- small text above the ring's value ("LV"; "" for none)
	ringValue: TextLabel,
	title: TextLabel,
	subtitle: TextLabel,
	bar: UiTheme.Bar,
	barLabel: TextLabel,
	slotRow: Frame,
	-- left column, picker top
	pickerList: Frame,
	-- left column, shared
	statsCaption: TextLabel,
	statLabels: { TextLabel },
	statValues: { TextLabel },
	-- right column
	heading: TextLabel,
	headingChip: Frame,
	headingSub: TextLabel,
	pipRow: Frame,
	grid: Frame,
	infoScroll: ScrollingFrame,
	infoTitle: TextLabel,
	infoImproves: TextLabel,
	infoBody: TextLabel,
	infoButton: TextButton,
	infoButtonText: TextLabel,
	infoAction: (() -> ())?,
	closeHint: TextLabel,
	tileHeight: number,
	tileButtons: boolean,
	fitToScreen: () -> (),
}

-- Builds the window (hidden).
function MenuKit.new(name: string, parent: Instance, options: Options): Menu
	local screen = Instance.new("ScreenGui")
	screen.Name = name
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 20
	screen.Enabled = false
	screen.Parent = parent

	-- Scrim: a Modal button, so the first-person mouse lock is released while open.
	local scrim = Instance.new("TextButton")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = UiTheme.Scrim
	scrim.BackgroundTransparency = UiTheme.ScrimTransparency
	scrim.AutoButtonColor = false
	scrim.Text = ""
	scrim.Modal = true
	scrim.Parent = screen

	-- The window is the gold rim; the blue body sits inside it.
	local window = UiTheme.block(screen, "Gold", UiTheme.RadiusLarge)
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(MenuKit.WIDTH, MenuKit.HEIGHT)
	local fit = Instance.new("UIScale")
	fit.Parent = window
	local body = UiTheme.block(window, "Blue", UiTheme.RadiusLarge - MenuKit.RIM // 2, 2)
	body.Name = "Body"
	body.Position = UDim2.fromOffset(MenuKit.RIM, MenuKit.RIM)
	body.Size = UDim2.new(1, -MenuKit.RIM * 2, 1, -MenuKit.RIM * 2)
	UiTheme.setOutline(body, Color3.fromRGB(26, 111, 192), 2)

	-- Title on the rim, flush left (owner 2026-10-22: no icon), and the close button.
	local titleLabel = UiTheme.text(window, Size.Display, Font.Heavy)
	titleLabel.Name = "Title"
	titleLabel.AnchorPoint = Vector2.new(0, 0.5)
	titleLabel.Position = UDim2.fromOffset(MenuKit.PAD, 4)
	titleLabel.Size = UDim2.fromOffset(0, 40)
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.TextTruncate = Enum.TextTruncate.None
	titleLabel.ZIndex = 5
	titleLabel.Text = options.title


	local closeButton = blockButton(window, "Red", UiTheme.Radius)
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, space(3), 0, -space(4))
	closeButton.Size = UDim2.fromOffset(48, 44)
	closeButton.ZIndex = 5
	UiTheme.pressable(closeButton)
	local closeX = UiTheme.text(closeButton, Size.Heading, Font.Heavy)
	closeX.Size = UDim2.fromScale(1, 1)
	closeX.TextXAlignment = Enum.TextXAlignment.Center
	closeX.ZIndex = 6
	closeX.Text = "X"

	local function column(columnName: string, x: number, width: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = columnName
		frame.Position = UDim2.fromScale(x, 0)
		frame.Size = UDim2.fromScale(width, 1)
		frame.BackgroundTransparency = 1
		frame.Parent = body
		padding(frame, MenuKit.PAD_TOP, MenuKit.PAD, MenuKit.PAD_BOTTOM)
		return frame
	end
	local left = column("Left", 0, MenuKit.LEFT_SHARE)
	local right = column("Right", MenuKit.LEFT_SHARE, 1 - MenuKit.LEFT_SHARE)
	-- The columns meet in the middle with one PAD between them, not two.
	local leftPad = left:FindFirstChildOfClass("UIPadding")
	if leftPad then
		leftPad.PaddingRight = UDim.new(0, MenuKit.PAD // 2)
	end
	local rightPad = right:FindFirstChildOfClass("UIPadding")
	if rightPad then
		rightPad.PaddingLeft = UDim.new(0, MenuKit.PAD // 2)
	end

	-- Where the left column's sections go, by kind of top.
	local RING = MenuKit.RING_SIZE
	local rowHeight = MenuKit.ROW_HEIGHT
	local pickerCount = options.pickerCount or 0
	local isPicker = options.pickerCaption ~= nil
	local statsTop = if isPicker
		then CAPTION_HEIGHT + space(1) + pickerCount * MenuKit.CARD_HEIGHT + (pickerCount - 1) * space(2) + space(3)
		else MenuKit.PROFILE_HEIGHT + space(3)
	local statRows = options.statRows or MenuKit.STAT_ROWS
	local statsBlockTop = statsTop + CAPTION_HEIGHT + space(1)
	local statsEnd = statsBlockTop + statRows * rowHeight + space(3)
	local slotsTop = statsEnd + space(3) + CAPTION_HEIGHT + space(1)

	-- Profile top: a navy block with the ring, title, subtitle, XP bar and its label.
	local header = UiTheme.block(left, "Navy", UiTheme.Radius)
	header.Name = "Profile"
	header.Size = UDim2.new(1, 0, 0, MenuKit.PROFILE_HEIGHT)
	header.Visible = not isPicker
	local ring = UiTheme.block(header, "Gold", RING // 2)
	ring.Position = UDim2.fromOffset(space(3), (MenuKit.PROFILE_HEIGHT - RING) // 2)
	ring.Size = UDim2.fromOffset(RING, RING)
	local ringCaption = UiTheme.text(ring, Size.Caption, Font.Bold)
	ringCaption.Position = UDim2.fromOffset(0, 8)
	ringCaption.Size = UDim2.new(1, 0, 0, 12)
	ringCaption.TextXAlignment = Enum.TextXAlignment.Center
	local ringValue = UiTheme.text(ring, Size.Heading, Font.Heavy)
	ringValue.Position = UDim2.fromOffset(0, 20)
	ringValue.Size = UDim2.new(1, 0, 0, 28)
	ringValue.TextXAlignment = Enum.TextXAlignment.Center
	local textX = space(3) + RING + space(3)
	local title = UiTheme.text(header, Size.Title + 3, Font.Heavy)
	title.Position = UDim2.fromOffset(textX, 10)
	title.Size = UDim2.new(1, -(textX + space(3)), 0, 24)
	local subtitle = UiTheme.text(header, Size.Body, Font.Bold)
	subtitle.Position = UDim2.fromOffset(textX, 32)
	subtitle.Size = UDim2.new(1, -(textX + space(3)), 0, 16)
	subtitle.TextColor3 = UiTheme.Gold
	local bar = UiTheme.bar(header, UiTheme.Bar.Xp + 2, UiTheme.Gold)
	bar.track.Position = UDim2.fromOffset(textX, 52)
	bar.track.Size = UDim2.new(1, -(textX + space(3)), 0, UiTheme.Bar.Xp + 2)
	local barLabel = UiTheme.text(header, Size.Caption, Font.Bold, Strength.Label)
	barLabel.Position = UDim2.fromOffset(textX, 63)
	barLabel.Size = UDim2.new(1, -(textX + space(3)), 0, 14)

	-- Picker top: a caption and full-width cards (MenuKit.card).
	local pickerList = Instance.new("Frame")
	pickerList.Name = "Picker"
	pickerList.Position = UDim2.fromOffset(0, CAPTION_HEIGHT + space(1))
	pickerList.Size = UDim2.new(1, 0, 0, statsTop - CAPTION_HEIGHT)
	pickerList.BackgroundTransparency = 1
	pickerList.Visible = isPicker
	pickerList.Parent = left
	local pickerLayout = Instance.new("UIListLayout")
	pickerLayout.Padding = UDim.new(0, space(2))
	pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pickerLayout.Parent = pickerList
	if isPicker then
		caption(left, options.pickerCaption or "", 0)
	end

	-- Stat rows (ink label left, outlined value right) on a light block.
	local statsCaption = caption(left, options.statsCaption, statsTop)
	local statsBlock = UiTheme.block(left, "Light", UiTheme.Radius)
	statsBlock.Name = "Stats"
	statsBlock.Position = UDim2.fromOffset(0, statsBlockTop)
	statsBlock.Size = UDim2.new(1, 0, 0, statRows * rowHeight + space(3))
	UiTheme.setOutline(statsBlock, UiTheme.Ink, UiTheme.OutlineThin)
	local statLabels: { TextLabel } = {}
	local statValues: { TextLabel } = {}
	for index = 1, statRows do
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(space(3), space(1) + 2 + (index - 1) * rowHeight)
		row.Size = UDim2.new(1, -space(6), 0, rowHeight)
		row.BackgroundTransparency = 1
		row.Parent = statsBlock
		local label = UiTheme.text(row, Size.Value, Font.Medium)
		label.Size = UDim2.fromScale(0.62, 1)
		UiTheme.inkText(label)
		local value = UiTheme.text(row, Size.Value + 1, Font.Bold)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.fromScale(1, 0)
		value.Size = UDim2.fromScale(0.38, 1)
		value.TextXAlignment = Enum.TextXAlignment.Right
		table.insert(statLabels, label)
		table.insert(statValues, value)
		if index < statRows then
			local rule = Instance.new("Frame")
			rule.AnchorPoint = Vector2.new(0, 1)
			rule.Position = UDim2.fromScale(0, 1)
			rule.Size = UDim2.new(1, 0, 0, 1)
			rule.BackgroundColor3 = UiTheme.Ink
			rule.BackgroundTransparency = 0.8
			rule.BorderSizePixel = 0
			rule.Parent = row
		end
	end

	-- Profile top only: the slot row under the stats.
	if not isPicker then
		caption(left, options.slotsCaption or "", statsEnd + space(3))
	end
	local slotRow = Instance.new("Frame")
	slotRow.Name = "Slots"
	slotRow.Position = UDim2.fromOffset(0, slotsTop)
	slotRow.Size = UDim2.new(1, 0, 0, MenuKit.SLOT_SIZE)
	slotRow.BackgroundTransparency = 1
	slotRow.Visible = not isPicker
	slotRow.Parent = left
	local slotLayout = Instance.new("UIListLayout")
	slotLayout.FillDirection = Enum.FillDirection.Horizontal
	slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	slotLayout.Padding = UDim.new(0, space(1) + 2)
	slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotLayout.Parent = slotRow

	-- Right: heading with its chip, pips, the grid panel, info area, close hint.
	local headRow = Instance.new("Frame")
	headRow.Name = "Head"
	headRow.Size = UDim2.new(1, -150, 0, 36)
	headRow.BackgroundTransparency = 1
	headRow.Parent = right
	local headLayout = Instance.new("UIListLayout")
	headLayout.FillDirection = Enum.FillDirection.Horizontal
	headLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	headLayout.Padding = UDim.new(0, space(3))
	headLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headLayout.Parent = headRow
	local heading = UiTheme.text(headRow, Size.Heading + 4, Font.Heavy)
	heading.LayoutOrder = 1
	heading.Size = UDim2.fromOffset(0, 36)
	heading.AutomaticSize = Enum.AutomaticSize.X
	heading.TextTruncate = Enum.TextTruncate.None

	-- The chip next to the heading: Gold, a waiting pick, or a server reply.
	local headingChip = UiTheme.block(headRow, "Green", UiTheme.Radius, UiTheme.OutlineThin)
	headingChip.LayoutOrder = 2
	headingChip.Size = UDim2.fromOffset(0, 30)
	headingChip.AutomaticSize = Enum.AutomaticSize.X
	padding(headingChip, 0, space(3), 0)
	local headingSub = UiTheme.text(headingChip, Size.Value, Font.Bold)
	headingSub.Size = UDim2.fromOffset(0, 30)
	headingSub.AutomaticSize = Enum.AutomaticSize.X
	headingSub.TextTruncate = Enum.TextTruncate.None

	local pipRow = Instance.new("Frame")
	pipRow.Name = "Pips"
	pipRow.AnchorPoint = Vector2.new(1, 0)
	pipRow.Position = UDim2.new(1, 0, 0, 9)
	pipRow.Size = UDim2.fromOffset(150, 18)
	pipRow.BackgroundTransparency = 1
	pipRow.Parent = right

	local gridRows = options.gridRows
	local GRID_PAD = MenuKit.GRID_PAD
	local tileButtons = options.tileButtons == true
	local tileHeight = if tileButtons then MenuKit.BUTTON_TILE_HEIGHT else MenuKit.TILE_HEIGHT
	local gridHeight = gridRows * (tileHeight + MenuKit.TILE_GAP) - MenuKit.TILE_GAP
	local gridPanel = UiTheme.block(right, "Sky", UiTheme.RadiusLarge)
	gridPanel.Name = "GridPanel"
	gridPanel.Position = UDim2.fromOffset(0, MenuKit.GRID_TOP)
	gridPanel.Size = UDim2.new(1, 0, 0, gridHeight + GRID_PAD * 2)
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(GRID_PAD, GRID_PAD)
	grid.Size = UDim2.new(1, -GRID_PAD * 2, 0, gridHeight)
	grid.BackgroundTransparency = 1
	grid.Parent = gridPanel

	-- Info area (what the mouse is over) under the grid, with a button on the
	-- right (buy / pick) when the shown thing can be acted on.
	local infoTop = MenuKit.GRID_TOP + gridHeight + GRID_PAD * 2 + space(3)
	local info = UiTheme.block(right, "Light", UiTheme.Radius)
	info.Name = "Info"
	info.Position = UDim2.fromOffset(0, infoTop)
	info.Size = UDim2.new(1, 0, 1, -(infoTop + CLOSE_HINT_SPACE))
	info.ClipsDescendants = true
	-- Title, "Improves" line and body stack and wrap (flow); if together they
	-- are taller than the area, it scrolls (mouse wheel) instead of cutting
	-- off the last lines (owner 2026-10-21: the info area was unreadable).
	local infoScroll = Instance.new("ScrollingFrame")
	infoScroll.Name = "Content"
	infoScroll.Size = UDim2.fromScale(1, 1)
	infoScroll.BackgroundTransparency = 1
	infoScroll.BorderSizePixel = 0
	infoScroll.CanvasSize = UDim2.new()
	infoScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	infoScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	infoScroll.ScrollBarThickness = UiTheme.ScrollBar
	infoScroll.ScrollBarImageColor3 = UiTheme.Ink
	infoScroll.ScrollBarImageTransparency = 0.5
	infoScroll.Parent = info
	padding(infoScroll, space(3), space(4), space(3))
	stack(infoScroll, space(1))
	local infoTitle = flow(UiTheme.text(infoScroll, Size.Title + 3, Font.Heavy), 1)
	local infoImproves = flow(UiTheme.text(infoScroll, Size.Value, Font.Medium), 2)
	UiTheme.inkText(infoImproves)
	infoImproves.TextColor3 = UiTheme.Improves
	local infoBody = flow(UiTheme.text(infoScroll, Size.Value, Font.Regular), 3)
	UiTheme.inkText(infoBody)
	infoBody.RichText = true

	local infoButton = blockButton(info, "Green", UiTheme.Radius)
	infoButton.Name = "Action"
	infoButton.AnchorPoint = Vector2.new(1, 1) -- bottom right (owner 2026-10-22)
	infoButton.Position = UDim2.new(1, -space(4), 1, -space(4))
	infoButton.Size = UDim2.fromOffset(MenuKit.INFO_BUTTON_WIDTH, 52)
	infoButton.Visible = false
	UiTheme.pressable(infoButton)
	local infoButtonText = UiTheme.text(infoButton, Size.Heading, Font.Heavy)
	infoButtonText.Size = UDim2.fromScale(1, 1)
	infoButtonText.TextXAlignment = Enum.TextXAlignment.Center


	local closeHint = UiTheme.text(right, Size.Small, Font.Bold, Strength.Label)
	closeHint.AnchorPoint = Vector2.new(1, 1)
	closeHint.Position = UDim2.fromScale(1, 1)
	closeHint.Size = UDim2.fromOffset(160, 16)
	closeHint.TextXAlignment = Enum.TextXAlignment.Right
	closeHint.Text = options.closeText

	local function fitToScreen()
		local viewport = Workspace.CurrentCamera.ViewportSize
		fit.Scale = math.min(UiTheme.MenuScale, (viewport.X - 48) / MenuKit.WIDTH, (viewport.Y - 64) / MenuKit.HEIGHT)
	end

	local menu: Menu = {
		screen = screen,
		window = window,
		left = left,
		right = right,
		titleLabel = titleLabel,
		closeButton = closeButton,
		ringCaption = ringCaption,
		ringValue = ringValue,
		title = title,
		subtitle = subtitle,
		bar = bar,
		barLabel = barLabel,
		slotRow = slotRow,
		pickerList = pickerList,
		statsCaption = statsCaption,
		statLabels = statLabels,
		statValues = statValues,
		heading = heading,
		headingChip = headingChip,
		headingSub = headingSub,
		pipRow = pipRow,
		grid = grid,
		infoScroll = infoScroll,
		infoTitle = infoTitle,
		infoImproves = infoImproves,
		infoBody = infoBody,
		infoButton = infoButton,
		infoButtonText = infoButtonText,
		infoAction = nil,
		closeHint = closeHint,
		tileHeight = tileHeight,
		tileButtons = tileButtons,
		fitToScreen = fitToScreen,
	}
	infoButton.Activated:Connect(function()
		local action = menu.infoAction
		if action then
			action()
		end
	end)
	return menu
end

-- The chip next to the heading: text on a coloured block (Green = Gold,
-- Gold = something to do, Red = a warning, Navy = plain information).
function MenuKit.setSub(menu: Menu, text: string, fill: UiTheme.FillName)
	menu.headingSub.Text = text
	UiTheme.setFill(menu.headingChip, fill)
end

-- A full-width picker card: a big icon, a name and a short detail on the right
-- ("2/6", "Lv 2"). Style it with MenuKit.styleCard.
function MenuKit.card(menu: Menu, icon: string, name: string, order: number): Card
	local button = blockButton(menu.pickerList, "Blue", UiTheme.Radius)
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, MenuKit.CARD_HEIGHT)
	UiTheme.pressable(button)
	local ICON = 36
	local iconLabel = UiTheme.text(button, 30, Font.Bold)
	iconLabel.Position = UDim2.fromOffset(space(3), 0)
	iconLabel.Size = UDim2.new(0, ICON, 1, 0)
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	iconLabel.Text = icon
	local nameLabel = UiTheme.text(button, Size.Title + 1, Font.Heavy)
	nameLabel.Position = UDim2.fromOffset(space(3) + ICON + space(3), 0)
	nameLabel.Size = UDim2.new(1, -(space(6) + ICON + space(3) + 50), 1, 0)
	nameLabel.Text = name
	local detail = UiTheme.text(button, Size.Value + 1, Font.Bold)
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.new(1, -space(3), 0, 0)
	detail.Size = UDim2.new(0, 50, 1, 0)
	detail.TextXAlignment = Enum.TextXAlignment.Right
	return { button = button, icon = iconLabel, name = nameLabel, detail = detail, hover = false }
end

-- Card looks: selected = gold; hover = a white outline.
function MenuKit.styleCard(card: Card, selected: boolean)
	UiTheme.setFill(card.button, if selected then "Gold" else "Blue")
	UiTheme.setOutline(card.button, if card.hover and not selected then UiTheme.Text else UiTheme.Ink)
end

-- Fills the stat rows: { label, value, improved }. Values are always white
-- (owner 2026-10-22: no gold for improved numbers); `improved` is ignored.
-- Rows past the end of `lines` are left empty.
function MenuKit.setStats(menu: Menu, lines: { { any } })
	for index, label in menu.statLabels do
		local line = lines[index]
		local value = menu.statValues[index]
		label.Text = if line then tostring(line[1]) else ""
		value.Text = if line then tostring(line[2]) else ""
	end
end

-- Shows something in the info area. `improves` nil hides that line.
function MenuKit.showInfo(menu: Menu, title: string, improves: string?, body: string)
	if menu.infoTitle.Text ~= title then
		menu.infoScroll.CanvasPosition = Vector2.zero -- something new: back to the top
	end
	menu.infoTitle.Text = title
	menu.infoImproves.Visible = improves ~= nil
	menu.infoImproves.Text = if improves then `Improves: {improves}` else ""
	menu.infoBody.Text = body
end

-- The info area's button: `text` nil hides it. `action` runs on click.
function MenuKit.setInfoButton(menu: Menu, text: string?, fill: UiTheme.FillName, action: (() -> ())?)
	local shown = text ~= nil
	menu.infoButton.Visible = shown
	menu.infoButtonText.Text = text or ""
	UiTheme.setFill(menu.infoButton, fill)
	menu.infoAction = action
	-- The text makes room for the button.
	local room = if shown then MenuKit.INFO_BUTTON_WIDTH + space(4) else 0
	menu.infoScroll.Size = UDim2.new(1, -room, 1, 0)
end

-- A slot in the left column's slot row (a short tag, or an icon).
function MenuKit.slot(menu: Menu, tag: string, order: number): Slot
	local button = blockButton(menu.slotRow, "Deep", UiTheme.Radius, UiTheme.OutlineThin)
	button.Name = tag
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(MenuKit.SLOT_SIZE, MenuKit.SLOT_SIZE)
	UiTheme.pressable(button)
	local label = UiTheme.text(button, Size.Caption, Font.Heavy)
	label.Position = UDim2.fromOffset(2, 0)
	label.Size = UDim2.new(1, -4, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextScaled = true -- long names shrink to fit
	label.Text = tag
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 14
	limit.Parent = label
	return { button = button, label = label, selected = false }
end

-- Slot looks: the one shown in the info area is gold.
function MenuKit.styleSlot(slot: Slot)
	UiTheme.setFill(slot.button, if slot.selected then "Gold" else "Deep")
end

-- One square per step on the right of the heading. Returns them in order.
function MenuKit.pips(menu: Menu, count: number): { Frame }
	menu.pipRow:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, space(1) + 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = menu.pipRow
	local pips: { Frame } = {}
	for index = 1, count do
		local pip = UiTheme.block(menu.pipRow, "Navy", 5, UiTheme.OutlineThin)
		pip.LayoutOrder = index
		pip.Size = UDim2.fromOffset(18, 18)
		table.insert(pips, pip)
	end
	return pips
end

-- A pip: "done" gold, "open" (waiting) green, otherwise navy.
function MenuKit.setPip(pip: Frame, state: string)
	UiTheme.setFill(pip, if state == "done" then "Gold" elseif state == "open" then "Green" else "Navy")
end

-- A grid tile at position `index` (left to right, top to bottom, 3 across):
-- a name and an orange "Improves: ..." line only.
function MenuKit.tile(menu: Menu, index: number): Tile
	local column = (index - 1) % MenuKit.COLUMNS
	local row = (index - 1) // MenuKit.COLUMNS
	local columns = MenuKit.COLUMNS
	local gap = MenuKit.TILE_GAP
	local height = menu.tileHeight
	local button = blockButton(menu.grid, "Light", UiTheme.Radius)
	button.Name = `Tile{index}`
	button.Position = UDim2.new(column / columns, column * gap / columns, 0, row * (height + gap))
	button.Size = UDim2.new(1 / columns, -gap * (columns - 1) / columns, 0, height)

	-- Name and improves line stack (flow), so a two-line name moves the
	-- improves line down; the stack is clipped at the tile's edge.
	local body = Instance.new("Frame")
	body.Name = "Text"
	local buttonRoom = if menu.tileButtons then MenuKit.TILE_BUTTON_HEIGHT + space(2) else 0
	body.Size = UDim2.new(1, 0, 1, -buttonRoom)
	body.BackgroundTransparency = 1
	body.ClipsDescendants = true
	body.Parent = button
	padding(body, space(2) + 2, space(3), space(2))
	stack(body, space(1))
	local name = flow(UiTheme.text(body, Size.Value + 1, Font.Heavy), 1)
	local improves = flow(UiTheme.text(body, Size.Small + 1, Font.Medium), 2)
	UiTheme.inkText(improves)
	improves.TextColor3 = UiTheme.Improves

	-- A green check in the corner when owned or taken.
	local check = UiTheme.block(button, "Green", 13, UiTheme.OutlineThin)
	check.Name = "Check"
	check.AnchorPoint = Vector2.new(0.5, 0.5)
	check.Position = UDim2.new(1, -4, 0, 4)
	check.Size = UDim2.fromOffset(26, 26)
	check.ZIndex = 3
	check.Visible = false
	local tick = UiTheme.text(check, Size.Value, Font.Heavy)
	tick.Size = UDim2.fromScale(1, 1)
	tick.TextXAlignment = Enum.TextXAlignment.Center
	tick.ZIndex = 4
	tick.Text = "✓"

	-- The small price button at the bottom left (shown with setTileButton).
	local price = blockButton(button, "Green", UiTheme.Radius - 2, UiTheme.OutlineThin)
	price.Name = "Price"
	price.AnchorPoint = Vector2.new(0, 1)
	price.Position = UDim2.new(0, space(3), 1, -space(2) - 2)
	price.Size = UDim2.fromOffset(0, MenuKit.TILE_BUTTON_HEIGHT)
	price.AutomaticSize = Enum.AutomaticSize.X
	price.Visible = false
	price.ZIndex = 2
	UiTheme.pressable(price)
	padding(price, 0, space(3), 0)
	local priceText = UiTheme.text(price, Size.Value, Font.Bold)
	priceText.Size = UDim2.fromOffset(0, MenuKit.TILE_BUTTON_HEIGHT)
	priceText.AutomaticSize = Enum.AutomaticSize.X
	priceText.TextTruncate = Enum.TextTruncate.None
	priceText.ZIndex = 3

	return {
		button = button,
		name = name,
		improves = improves,
		check = check,
		price = price,
		priceText = priceText,
		hover = false,
		selected = false,
	}
end

-- A tile's small price button: `text` nil hides it.
function MenuKit.setTileButton(tile: Tile, text: string?, fill: UiTheme.FillName)
	tile.price.Visible = text ~= nil
	tile.priceText.Text = text or ""
	UiTheme.setFill(tile.price, fill)
end

-- Tile looks: "taken" (green with a check), "open" (light; gold on hover or
-- while shown in the info area) or "locked" (grey, faint, not clickable).
-- The tile shown in the info area also gets a white outline.
function MenuKit.styleTile(tile: Tile, state: string)
	tile.button.Active = state ~= "locked"
	tile.check.Visible = state == "taken"
	local lit = tile.hover or tile.selected
	local fill: UiTheme.FillName = if state == "taken"
		then "Green"
		elseif state == "locked" then "Grey"
		elseif lit then "Gold"
		else "Light"
	UiTheme.setFill(tile.button, fill)
	UiTheme.setOutline(tile.button, if tile.selected then UiTheme.Text else UiTheme.Ink)
	local faint = if state == "locked" then Strength.Faint else 0
	tile.name.TextTransparency = faint
	tile.improves.TextTransparency = faint
end

return MenuKit
