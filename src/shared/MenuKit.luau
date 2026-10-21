--!strict
-- The one layout every full menu uses (owner 2026-10-21: the Base Upgrades
-- page must look and be organised like the Character Menu), built from
-- UiTheme values (docs/11_UI_DESIGN.md). Both CharacterMenu.client and
-- BaseUpgradeMenu.client build their window from these pieces only. The top of
-- the left column comes in two kinds; everything else is shared:
--
--   left column (34%)                    right column (66%)
--   profile top:        picker top:       Heading                     o o o o o
--   [ring] Title        CAPTION           subtitle (gold when actionable)
--          subtitle     [icon Name  2/6]  [tile] [tile] [tile]
--   ==== gold bar ====  [icon Name  Lv2]  [tile] [tile] [tile]
--   bar label           [icon Name  0/6]  [tile] [tile] [tile]
--   CAPTION
--   label ............ value  x5
--   CAPTION (profile only)                                        "X to close"
--   [slot][slot][slot][slot][slot]
--   +-- info area -----------------+
--   | Title                         |
--   | Improves: ...   (orange)      |
--   | body text                     |
--   +-------------------------------+
--
-- Profile top (Character Menu): level ring, name, class, XP bar, then the
-- ABILITIES slot row under the stats. Picker top (Base Upgrades, owner
-- 2026-10-21: bigger building icons, less repetition): full-width cards to
-- choose what the rest of the menu shows, and no slot row.
-- Tiles: name, an orange "Improves: ..." line, short text, and a corner line
-- (TAKEN / OWNED / a price). Hovering a slot, card or tile fills the info
-- area; there are no floating tooltips.
-- Text that can run to two lines (owner 2026-10-22: wrapped lines pushed things
-- out of place) is made with flow(): it grows to fit its lines inside a
-- UIListLayout, so a second line moves what follows down instead of
-- overlapping it or being cut off. The info area scrolls when its text is
-- longer than the space; text is never shrunk to fit.
-- Options for the Base Upgrades menu (owner 2026-10-21): infoUnderGrid moves
-- the info area under the grid on the right; largeText makes cards, tiles,
-- stat rows and the info area bigger.

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
MenuKit.HEIGHT = 560
MenuKit.LEFT_SHARE = 0.34
MenuKit.PAD = space(6) -- 24
MenuKit.ROW_HEIGHT = space(8) -- 32
MenuKit.STAT_ROWS = 5
MenuKit.SLOT_SIZE = 40
MenuKit.RING_SIZE = 48
MenuKit.CARD_HEIGHT = 52
MenuKit.GRID_TOP = space(15)
MenuKit.TILE_HEIGHT = 116
MenuKit.TILE_GAP = space(3)
MenuKit.COLUMNS = 3
-- Large text (Base Upgrades, owner 2026-10-21: building and upgrade text was
-- too small): taller cards and tiles to hold it.
MenuKit.LARGE_CARD_HEIGHT = 60
MenuKit.LARGE_TILE_HEIGHT = 128
MenuKit.LARGE_ROW_HEIGHT = space(9) -- 36

local CLOSE_HINT_SPACE = 24 -- kept free at the bottom of the right column

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
	local title = UiTheme.text(parent, Size.Caption, Font.Bold, Strength.Faint)
	title.Position = UDim2.fromOffset(0, y)
	title.Size = UDim2.new(1, 0, 0, 14)
	title.Text = label
	return title
end

-- 60 -> "60", 202.5 -> "202.5", 1.3333 -> "1.33"
function MenuKit.formatNumber(value: number): string
	if math.abs(value - math.round(value)) < 0.005 then
		return tostring(math.round(value))
	end
	local trimmed = string.format("%.2f", value):gsub("0+$", "")
	return trimmed
end

export type Slot = { button: TextButton, label: TextLabel, line: UIStroke }
export type Card = { button: TextButton, line: UIStroke, icon: TextLabel, name: TextLabel, detail: TextLabel, hover: boolean }
export type Tile = {
	button: TextButton,
	line: UIStroke,
	name: TextLabel,
	improves: TextLabel,
	text: TextLabel,
	corner: TextLabel,
	hover: boolean,
}
export type Options = {
	statsCaption: string,
	closeText: string,
	-- Profile top: the caption over the slot row (e.g. ABILITIES).
	slotsCaption: string?,
	-- Picker top instead: the caption over the cards and how many there are.
	pickerCaption: string?,
	pickerCount: number?,
	-- Stat rows in the left column (default STAT_ROWS).
	statRows: number?,
	-- Info area under the grid in the right column (holding this many grid
	-- rows) instead of at the bottom of the left column.
	infoUnderGrid: number?,
	-- Bigger text on cards, tiles and stat rows.
	largeText: boolean?,
}
export type Menu = {
	screen: ScreenGui,
	window: Frame,
	left: Frame,
	right: Frame,
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
	infoScroll: ScrollingFrame,
	infoTitle: TextLabel,
	infoImproves: TextLabel,
	infoBody: TextLabel,
	-- right column
	heading: TextLabel,
	headingSub: TextLabel,
	pipRow: Frame,
	grid: Frame,
	closeHint: TextLabel,
	fitToScreen: () -> (),
	largeText: boolean,
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

	local window = UiTheme.panel(screen, UiTheme.MenuTransparency, UiTheme.RadiusLarge)
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(MenuKit.WIDTH, MenuKit.HEIGHT)
	local fit = Instance.new("UIScale")
	fit.Parent = window

	local function column(columnName: string, x: number, width: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = columnName
		frame.Position = UDim2.fromScale(x, 0)
		frame.Size = UDim2.fromScale(width, 1)
		frame.BackgroundTransparency = 1
		frame.Parent = window
		padding(frame, MenuKit.PAD, MenuKit.PAD, MenuKit.PAD)
		return frame
	end
	local left = column("Left", 0, MenuKit.LEFT_SHARE)
	local right = column("Right", MenuKit.LEFT_SHARE, 1 - MenuKit.LEFT_SHARE)

	local divider = Instance.new("Frame")
	divider.Position = UDim2.new(MenuKit.LEFT_SHARE, 0, 0, MenuKit.PAD)
	divider.Size = UDim2.new(0, 1, 1, -MenuKit.PAD * 2)
	divider.BackgroundColor3 = UiTheme.Raised
	divider.BackgroundTransparency = 0.88
	divider.BorderSizePixel = 0
	divider.Parent = window

	-- Where the left column's sections go, by kind of top.
	local RING = MenuKit.RING_SIZE
	local large = options.largeText == true
	local cardHeight = if large then MenuKit.LARGE_CARD_HEIGHT else MenuKit.CARD_HEIGHT
	local rowHeight = if large then MenuKit.LARGE_ROW_HEIGHT else MenuKit.ROW_HEIGHT
	local statText = if large then Size.Value else Size.Value - 1
	local pickerCount = options.pickerCount or 0
	local isPicker = options.pickerCaption ~= nil
	local statsTop = if isPicker
		then space(5) + pickerCount * cardHeight + (pickerCount - 1) * space(2) + space(4)
		else RING + space(11)
	local statRows = options.statRows or MenuKit.STAT_ROWS
	local statsEnd = statsTop + space(5) + statRows * rowHeight + space(4)
	local slotsTop = statsEnd + space(5)
	local infoTop = if isPicker then statsEnd else slotsTop + MenuKit.SLOT_SIZE + space(4)

	-- Profile top: ring, title, subtitle, thin gold bar and its label.
	local header = Instance.new("Frame")
	header.Name = "Profile"
	header.Size = UDim2.new(1, 0, 0, statsTop)
	header.BackgroundTransparency = 1
	header.Visible = not isPicker
	header.Parent = left
	local ring = Instance.new("Frame")
	ring.Size = UDim2.fromOffset(RING, RING)
	ring.BackgroundTransparency = 1
	ring.Parent = header
	UiTheme.corner(ring, RING // 2)
	local ringStroke = Instance.new("UIStroke")
	ringStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ringStroke.Color = UiTheme.Gold
	ringStroke.Thickness = 2
	ringStroke.Parent = ring
	local ringCaption = UiTheme.text(ring, 9, Font.Bold, Strength.Label)
	ringCaption.Position = UDim2.fromOffset(0, 8)
	ringCaption.Size = UDim2.new(1, 0, 0, 10)
	ringCaption.TextXAlignment = Enum.TextXAlignment.Center
	local ringValue = UiTheme.text(ring, Size.Title, Font.Heavy)
	ringValue.Position = UDim2.fromOffset(0, 18)
	ringValue.Size = UDim2.new(1, 0, 0, 20)
	ringValue.TextXAlignment = Enum.TextXAlignment.Center
	local title = UiTheme.text(header, Size.Title, Font.Heavy)
	title.Position = UDim2.fromOffset(RING + space(3), 4)
	title.Size = UDim2.new(1, -(RING + space(3)), 0, 22)
	local subtitle = UiTheme.text(header, Size.Small + 1, Font.Medium, Strength.Label)
	subtitle.Position = UDim2.fromOffset(RING + space(3), 26)
	subtitle.Size = UDim2.new(1, -(RING + space(3)), 0, 16)
	local bar = UiTheme.bar(header, UiTheme.Bar.Xp, UiTheme.Gold)
	bar.track.Position = UDim2.fromOffset(0, RING + space(3))
	bar.track.BackgroundColor3 = UiTheme.Raised
	bar.track.BackgroundTransparency = 0.88
	local barLabel = UiTheme.text(header, Size.Small, Font.Medium, Strength.Faint)
	barLabel.Position = UDim2.fromOffset(0, RING + space(3) + UiTheme.Bar.Xp + space(1))
	barLabel.Size = UDim2.new(1, 0, 0, 14)

	-- Picker top: a caption and full-width cards (MenuKit.card).
	local pickerList = Instance.new("Frame")
	pickerList.Name = "Picker"
	pickerList.Position = UDim2.fromOffset(0, space(5))
	pickerList.Size = UDim2.new(1, 0, 0, statsTop - space(5))
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

	-- Stat rows (label left, value right).
	local statsCaption = caption(left, options.statsCaption, statsTop)
	local statLabels: { TextLabel } = {}
	local statValues: { TextLabel } = {}
	for index = 1, statRows do
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(0, statsTop + space(5) + (index - 1) * rowHeight)
		row.Size = UDim2.new(1, 0, 0, rowHeight)
		row.BackgroundTransparency = 1
		row.Parent = left
		local label = UiTheme.text(row, statText, Font.Medium, Strength.Label)
		label.Size = UDim2.fromScale(0.62, 1)
		local value = UiTheme.text(row, statText, Font.Bold)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.fromScale(1, 0)
		value.Size = UDim2.fromScale(0.38, 1)
		value.TextXAlignment = Enum.TextXAlignment.Right
		table.insert(statLabels, label)
		table.insert(statValues, value)
	end

	-- Profile top only: the slot row under the stats.
	if not isPicker then
		caption(left, options.slotsCaption or "", statsEnd)
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
	slotLayout.Padding = UDim.new(0, space(2))
	slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotLayout.Parent = slotRow

	-- Info area (what the mouse is over): the rest of the left column, or the
	-- space between the grid and the close hint on the right.
	local tileHeight = if large then MenuKit.LARGE_TILE_HEIGHT else MenuKit.TILE_HEIGHT
	local gridRows = options.infoUnderGrid
	local gridHeight = if gridRows then gridRows * (tileHeight + MenuKit.TILE_GAP) - MenuKit.TILE_GAP else nil
	local info = Instance.new("Frame")
	info.Name = "Info"
	if gridHeight then
		local top = MenuKit.GRID_TOP + gridHeight + space(4)
		info.Position = UDim2.fromOffset(0, top)
		info.Size = UDim2.new(1, 0, 1, -(top + CLOSE_HINT_SPACE))
		info.Parent = right
	else
		info.Position = UDim2.fromOffset(0, infoTop)
		info.Size = UDim2.new(1, 0, 1, -infoTop)
		info.Parent = left
	end
	info.BackgroundColor3 = UiTheme.Raised
	info.BackgroundTransparency = UiTheme.RaisedTransparency
	info.BorderSizePixel = 0
	info.ClipsDescendants = true
	UiTheme.corner(info, 10)
	-- Title, "Improves" line and body stack and wrap (flow); if together they
	-- are taller than the area, it scrolls (mouse wheel) instead of cutting
	-- off the last lines. Sizes are never smaller than the tile text on the
	-- right (owner 2026-10-21: the info area was unreadable).
	local infoScroll = Instance.new("ScrollingFrame")
	infoScroll.Name = "Content"
	infoScroll.Size = UDim2.fromScale(1, 1)
	infoScroll.BackgroundTransparency = 1
	infoScroll.BorderSizePixel = 0
	infoScroll.CanvasSize = UDim2.new()
	infoScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	infoScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	infoScroll.ScrollBarThickness = UiTheme.ScrollBar
	infoScroll.ScrollBarImageColor3 = UiTheme.Text
	infoScroll.ScrollBarImageTransparency = Strength.Faint
	infoScroll.Parent = info
	padding(infoScroll, space(3), space(3), space(3))
	stack(infoScroll, space(1))
	local infoTitle = flow(UiTheme.text(infoScroll, Size.Title, Font.Heavy), 1)
	local infoImproves = flow(UiTheme.text(infoScroll, if large then Size.Value else Size.Body, Font.Bold), 2)
	infoImproves.TextColor3 = UiTheme.Improves
	local infoBody = flow(UiTheme.text(infoScroll, if large then Size.Value else Size.Body, Font.Regular, Strength.Label), 3)
	infoBody.RichText = true

	-- Right: heading, sub line, pips, grid, close hint.
	local heading = UiTheme.text(right, Size.Heading, Font.Heavy)
	heading.Size = UDim2.new(1, -170, 0, 28)
	local headingSub = UiTheme.text(right, Size.Small + 1, Font.Bold)
	headingSub.Position = UDim2.fromOffset(0, 28)
	headingSub.Size = UDim2.new(1, 0, 0, 16)
	local pipRow = Instance.new("Frame")
	pipRow.Name = "Pips"
	pipRow.AnchorPoint = Vector2.new(1, 0)
	pipRow.Position = UDim2.new(1, 0, 0, 10)
	pipRow.Size = UDim2.fromOffset(160, 8)
	pipRow.BackgroundTransparency = 1
	pipRow.Parent = right

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(0, MenuKit.GRID_TOP)
	grid.Size = if gridHeight
		then UDim2.new(1, 0, 0, gridHeight)
		else UDim2.new(1, 0, 1, -(MenuKit.GRID_TOP + CLOSE_HINT_SPACE))
	grid.BackgroundTransparency = 1
	grid.Parent = right

	local closeHint = UiTheme.text(right, Size.Small, Font.Medium, Strength.Faint)
	closeHint.AnchorPoint = Vector2.new(1, 1)
	closeHint.Position = UDim2.fromScale(1, 1)
	closeHint.Size = UDim2.fromOffset(160, 16)
	closeHint.TextXAlignment = Enum.TextXAlignment.Right
	closeHint.Text = options.closeText

	local function fitToScreen()
		local viewport = Workspace.CurrentCamera.ViewportSize
		fit.Scale = math.min(UiTheme.MenuScale, (viewport.X - 32) / MenuKit.WIDTH, (viewport.Y - 32) / MenuKit.HEIGHT)
	end

	return {
		screen = screen,
		window = window,
		left = left,
		right = right,
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
		infoScroll = infoScroll,
		infoTitle = infoTitle,
		infoImproves = infoImproves,
		infoBody = infoBody,
		heading = heading,
		headingSub = headingSub,
		pipRow = pipRow,
		grid = grid,
		closeHint = closeHint,
		fitToScreen = fitToScreen,
		largeText = large,
	}
end

-- A full-width picker card: a big icon, a name and a short detail on the right
-- ("2/6", "Lv 2"). Style it with MenuKit.styleCard.
function MenuKit.card(menu: Menu, icon: string, name: string, order: number): Card
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	local large = menu.largeText
	button.Size = UDim2.new(1, 0, 0, if large then MenuKit.LARGE_CARD_HEIGHT else MenuKit.CARD_HEIGHT)
	button.BackgroundColor3 = UiTheme.Raised
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = menu.pickerList
	UiTheme.corner(button, 10)
	local line = Instance.new("UIStroke")
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Color = UiTheme.Gold
	line.Thickness = 1
	line.Parent = button
	local ICON = if large then 36 else 32
	local iconLabel = UiTheme.text(button, if large then 30 else 26, Font.Bold)
	iconLabel.Position = UDim2.fromOffset(space(3), 0)
	iconLabel.Size = UDim2.new(0, ICON, 1, 0)
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	iconLabel.Text = icon
	local nameLabel = UiTheme.text(button, if large then Size.Title else Size.Value, Font.Heavy)
	nameLabel.Position = UDim2.fromOffset(space(3) + ICON + space(3), 0)
	nameLabel.Size = UDim2.new(1, -(space(6) + ICON + space(3) + 50), 1, 0)
	nameLabel.Text = name
	if large then
		-- Long names shrink a little rather than run into the detail.
		nameLabel.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = Size.Title
		limit.MinTextSize = Size.Body
		limit.Parent = nameLabel
	end
	local detail = UiTheme.text(button, if large then Size.Value else Size.Small + 1, Font.Bold, Strength.Label)
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.new(1, -space(3), 0, 0)
	detail.Size = UDim2.new(0, 50, 1, 0)
	detail.TextXAlignment = Enum.TextXAlignment.Right
	return { button = button, line = line, icon = iconLabel, name = nameLabel, detail = detail, hover = false }
end

-- Card looks: selected = lit with a solid gold line; hover = lit with a faint one.
function MenuKit.styleCard(card: Card, selected: boolean)
	card.button.BackgroundTransparency = if selected or card.hover
		then UiTheme.RaisedHoverTransparency
		else UiTheme.RaisedTransparency
	card.line.Transparency = if selected then 0 elseif card.hover then 0.6 else 1
	card.detail.TextColor3 = if selected then UiTheme.Gold else UiTheme.Text
	card.detail.TextTransparency = if selected then 0 else Strength.Label
end

-- Fills the stat rows: { label, value, improved } (improved values in gold).
-- Rows past the end of `lines` are left empty.
function MenuKit.setStats(menu: Menu, lines: { { any } })
	for index, label in menu.statLabels do
		local line = lines[index]
		local value = menu.statValues[index]
		label.Text = if line then tostring(line[1]) else ""
		value.Text = if line then tostring(line[2]) else ""
		value.TextColor3 = if line and line[3] then UiTheme.Gold else UiTheme.Text
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

-- A slot in the left column's slot row (a short tag, or an icon).
function MenuKit.slot(menu: Menu, tag: string, order: number): Slot
	local button = Instance.new("TextButton")
	button.Name = tag
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(MenuKit.SLOT_SIZE, MenuKit.SLOT_SIZE)
	button.BackgroundColor3 = UiTheme.Raised
	button.BackgroundTransparency = UiTheme.RaisedHoverTransparency
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = menu.slotRow
	UiTheme.corner(button)
	local line = Instance.new("UIStroke")
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Color = UiTheme.Gold
	line.Thickness = 1
	line.Transparency = 1
	line.Parent = button
	local label = UiTheme.text(button, Size.Caption, Font.Heavy)
	label.Position = UDim2.fromOffset(2, 0)
	label.Size = UDim2.new(1, -4, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextScaled = true -- long names shrink to fit
	label.Text = tag
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 20
	limit.Parent = label
	return { button = button, label = label, line = line }
end

-- One dot per step on the right of the heading. Returns them in order.
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
		local pip = Instance.new("Frame")
		pip.LayoutOrder = index
		pip.Size = UDim2.fromOffset(8, 8)
		pip.BorderSizePixel = 0
		pip.Parent = menu.pipRow
		UiTheme.corner(pip, 4)
		table.insert(pips, pip)
	end
	return pips
end

-- A pip: "done" gold, "open" half gold, otherwise faint.
function MenuKit.setPip(pip: Frame, state: string)
	pip.BackgroundColor3 = if state == "done" or state == "open" then UiTheme.Gold else UiTheme.Text
	pip.BackgroundTransparency = if state == "done" then 0 elseif state == "open" then 0.5 else 0.85
end

-- A grid tile at position `index` (left to right, top to bottom, 3 across).
function MenuKit.tile(menu: Menu, index: number): Tile
	local column = (index - 1) % MenuKit.COLUMNS
	local row = (index - 1) // MenuKit.COLUMNS
	local columns = MenuKit.COLUMNS
	local gap = MenuKit.TILE_GAP
	local large = menu.largeText
	local height = if large then MenuKit.LARGE_TILE_HEIGHT else MenuKit.TILE_HEIGHT
	local button = Instance.new("TextButton")
	button.Name = `Tile{index}`
	button.Position = UDim2.new(column / columns, column * gap / columns, 0, row * (height + gap))
	button.Size = UDim2.new(1 / columns, -gap * (columns - 1) / columns, 0, height)
	button.BackgroundColor3 = UiTheme.Raised
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = menu.grid
	UiTheme.corner(button, 10)
	padding(button, space(3), space(3), space(3))
	local line = Instance.new("UIStroke")
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Color = UiTheme.Gold
	line.Thickness = 1
	line.Parent = button

	-- Text sizes: name, improves line, text, corner line.
	local nameSize, improvesSize, textSize, cornerSize = Size.Body, Size.Small - 1, Size.Small, Size.Small
	local cornerHeight = 14
	if large then
		nameSize, improvesSize, textSize, cornerSize = Size.Value, Size.Small, Size.Body - 1, Size.Body
		cornerHeight = 16
	end
	-- Name, improves line and text stack (flow), so a two-line name or
	-- improves line moves the text down; the stack stops above the corner line.
	local body = Instance.new("Frame")
	body.Name = "Text"
	body.Size = UDim2.new(1, 0, 1, -(cornerHeight + 2))
	body.BackgroundTransparency = 1
	body.ClipsDescendants = true
	body.Parent = button
	stack(body, space(1))
	local name = flow(UiTheme.text(body, nameSize, Font.Heavy), 1)
	local improves = flow(UiTheme.text(body, improvesSize, Font.Bold), 2)
	improves.TextColor3 = UiTheme.Improves
	local text = flow(UiTheme.text(body, textSize, Font.Regular), 3)
	local corner = UiTheme.text(button, cornerSize, Font.Heavy)
	corner.AnchorPoint = Vector2.new(0, 1)
	corner.Position = UDim2.fromScale(0, 1)
	corner.Size = UDim2.new(1, 0, 0, cornerHeight)

	local tile: Tile = { button = button, line = line, name = name, improves = improves, text = text, corner = corner, hover = false }
	return tile
end

-- Tile looks: "taken" (lit, gold rim, gold name), "open" (can be picked or
-- bought; gold rim and name on hover) or "locked" (greyed, not clickable).
-- `cornerText` / `cornerColor` set the bottom line (TAKEN, OWNED, a price).
function MenuKit.styleTile(tile: Tile, state: string, cornerText: string, cornerColor: Color3?)
	tile.button.Active = state == "open"
	tile.corner.Text = cornerText
	tile.corner.TextColor3 = cornerColor or UiTheme.Gold
	if state == "taken" then
		tile.button.BackgroundTransparency = UiTheme.RaisedHoverTransparency
		tile.line.Transparency = 0
		tile.name.TextColor3 = UiTheme.Gold
		tile.name.TextTransparency = 0
		tile.improves.TextTransparency = 0
		tile.text.TextTransparency = Strength.Label
		tile.corner.TextTransparency = 0
	elseif state == "open" then
		tile.button.BackgroundTransparency = if tile.hover then UiTheme.RaisedHoverTransparency else UiTheme.RaisedTransparency
		tile.line.Transparency = if tile.hover then 0.4 else 1
		tile.name.TextColor3 = if tile.hover then UiTheme.Gold else UiTheme.Text
		tile.name.TextTransparency = 0
		tile.improves.TextTransparency = 0
		tile.text.TextTransparency = Strength.Label
		tile.corner.TextTransparency = 0
	else
		tile.button.BackgroundTransparency = UiTheme.DisabledTransparency
		tile.line.Transparency = 1
		tile.name.TextColor3 = UiTheme.Text
		tile.name.TextTransparency = Strength.Faint
		tile.improves.TextTransparency = 0.5
		tile.text.TextTransparency = Strength.Faint
		tile.corner.TextTransparency = Strength.Faint
	end
end

return MenuKit
