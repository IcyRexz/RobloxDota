--!strict
-- Character Menu (owner spec 2026-10-20), in the game's UI design system
-- (docs/11_UI_DESIGN.md, values from UiTheme). U opens and closes it; clicking
-- the level ring also opens it. One menu surface, two columns:
--  * left (~38%): level ring, player name, hero name, gold XP bar, then
--    ATTRIBUTES (Health, Damage, Move Speed, Attack Speed, Range, read from the
--    server's Stat* Player attributes), ABILITIES (the hero's skill slots) and
--    TALENTS (talents taken, with a gold count). Hovering an ability or a talent
--    shows its details.
--  * right (~62%): when a level-up pick is waiting, "Choose a talent" with three
--    cards (stat tag, name, description, before -> after with the new value in
--    gold); click one or press 1/2/3. Picking closes the menu. Otherwise a note
--    with the next pick's level.
-- The game keeps running while it is open (multiplayer): you can still walk,
-- but the mouse is freed (a Modal button) so you can click, and you cannot shoot.
-- Display only: the server (HeroProgress) checks and applies every pick.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Font = UiTheme.Font
local Size = UiTheme.TextSize
local Strength = UiTheme.Strength
local space = UiTheme.space

-- Layout (pixels before scaling) --------------------------------------------------------
local WINDOW_WIDTH = 860
local WINDOW_HEIGHT = 560
-- Drawn at UiTheme.MenuScale (owner 2026-10-21: looked too small), shrunk
-- only when the screen is too small for that.
local MENU_SCALE = UiTheme.MenuScale
local LEFT_SHARE = 0.38
local PAD = space(6) -- 24
local ROW_HEIGHT = space(8) -- 32
local SLOT_SIZE = 40
local RING_SIZE = 48
local TOOLTIP_WIDTH = 250

-- Attributes on the left, in order: label, server attribute, short tag, unit.
type StatInfo = { label: string, attribute: string, tag: string, unit: string }
local STATS: { StatInfo } = {
	{ label = "Health", attribute = "StatMaxHealth", tag = "HP", unit = "" },
	{ label = "Damage", attribute = "StatAttackDamage", tag = "DMG", unit = "" },
	{ label = "Move Speed", attribute = "StatMoveSpeed", tag = "SPD", unit = "" },
	{ label = "Attack Speed", attribute = "StatAttackSpeed", tag = "AS", unit = " /s" },
	{ label = "Range", attribute = "StatAttackRange", tag = "RNG", unit = "" },
}

-- Talent cards: id (Config.Hero.Upgrades), name, description, which stat it changes.
type CardInfo = { id: string, name: string, effect: string, stat: StatInfo }
local CARDS: { CardInfo } = {
	{ id = "Attack", name = "Damage", effect = "Your attacks hit harder.", stat = STATS[2] },
	{ id = "MoveSpeed", name = "Move Speed", effect = "You move faster.", stat = STATS[3] },
	{ id = "Health", name = "Health", effect = "More max health, healed at once.", stat = STATS[1] },
}

-- The hero's ability slots, matching the HUD's slot row. Only the basic attack
-- exists so far; the other three are locked until talents can unlock abilities.
type SkillInfo = { key: string, name: string, tag: string, locked: boolean }
local SKILLS: { SkillInfo } = {
	{ key = "LMB", name = "Lightning Bolt", tag = "BOLT", locked = false },
	{ key = "1", name = "Ability 1", tag = "1", locked = true },
	{ key = "2", name = "Ability 2", tag = "2", locked = true },
	{ key = "3", name = "Ultimate", tag = "3", locked = true },
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local chooseEvent = ReplicatedStorage:WaitForChild("ChooseUpgrade") :: RemoteEvent
local upgradeFactors = Config.Hero.Upgrades :: { [string]: number }

-- Helpers ---------------------------------------------------------------------------

local function readNumber(name: string): number?
	local value = player:GetAttribute(name)
	if type(value) ~= "number" or value ~= value or math.abs(value) > 1e9 then
		return nil
	end
	return value
end

local function pending(): number
	return math.floor(readNumber("UpgradesPending") or 0)
end

-- 60 -> "60", 202.5 -> "202.5", 1.3333 -> "1.33"
local function formatNumber(value: number): string
	if math.abs(value - math.round(value)) < 0.005 then
		return tostring(math.round(value))
	end
	local trimmed = string.format("%.2f", value):gsub("0+$", "")
	return trimmed
end

local function statText(attribute: string): string
	local value = readNumber(attribute)
	return if value then formatNumber(value) else "-"
end

local function padding(parent: Instance, top: number, side: number, bottom: number)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, top)
	pad.PaddingBottom = UDim.new(0, bottom)
	pad.PaddingLeft = UDim.new(0, side)
	pad.PaddingRight = UDim.new(0, side)
	pad.Parent = parent
end

-- A white-6% rounded square with a short tag: ability and talent slots.
local function slot(parent: Instance, tag: string, size: number, locked: boolean?): Frame
	local box = Instance.new("Frame")
	box.Size = UDim2.fromOffset(size, size)
	box.BackgroundColor3 = UiTheme.Raised
	box.BackgroundTransparency = if locked then UiTheme.DisabledTransparency else UiTheme.RaisedHoverTransparency
	box.BorderSizePixel = 0
	box.Parent = parent
	UiTheme.corner(box)
	local label = UiTheme.text(box, Size.Caption, Font.Heavy, if locked then Strength.Faint else Strength.Value)
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = tag
	return box
end

local function caption(parent: Instance, label: string, y: number)
	local title = UiTheme.text(parent, Size.Caption, Font.Bold, Strength.Faint)
	title.Position = UDim2.fromOffset(0, y)
	title.Size = UDim2.new(1, 0, 0, 14)
	title.Text = label
end

-- Window ----------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "CharacterMenu"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 20
screen.Enabled = false
screen.Parent = playerGui

-- Scrim. It is a Modal button: while the menu is open the first-person mouse
-- lock is released so the cards can be clicked.
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
window.Size = UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT)
local fit = Instance.new("UIScale")
fit.Parent = window

local function column(name: string, x: number, width: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = UDim2.fromScale(x, 0)
	frame.Size = UDim2.fromScale(width, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = window
	padding(frame, PAD, PAD, PAD)
	return frame
end

local left = column("Character", 0, LEFT_SHARE)
local right = column("Talents", LEFT_SHARE, 1 - LEFT_SHARE)

-- Left column: header ---------------------------------------------------------------

local ring = Instance.new("Frame")
ring.Size = UDim2.fromOffset(RING_SIZE, RING_SIZE)
ring.BackgroundTransparency = 1
ring.Parent = left
UiTheme.corner(ring, RING_SIZE // 2)
local ringStroke = Instance.new("UIStroke")
ringStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
ringStroke.Color = UiTheme.Gold
ringStroke.Thickness = 2
ringStroke.Parent = ring
local ringCaption = UiTheme.text(ring, 9, Font.Bold, Strength.Label)
ringCaption.Position = UDim2.fromOffset(0, 8)
ringCaption.Size = UDim2.new(1, 0, 0, 10)
ringCaption.TextXAlignment = Enum.TextXAlignment.Center
ringCaption.Text = "LV"
local levelLabel = UiTheme.text(ring, Size.Title, Font.Heavy)
levelLabel.Position = UDim2.fromOffset(0, 18)
levelLabel.Size = UDim2.new(1, 0, 0, 20)
levelLabel.TextXAlignment = Enum.TextXAlignment.Center

local playerName = UiTheme.text(left, Size.Title, Font.Heavy)
playerName.Position = UDim2.fromOffset(RING_SIZE + space(3), 4)
playerName.Size = UDim2.new(1, -(RING_SIZE + space(3)), 0, 22)
playerName.Text = player.DisplayName

local heroName = UiTheme.text(left, Size.Small + 1, Font.Medium, Strength.Label)
heroName.Position = UDim2.fromOffset(RING_SIZE + space(3), 26)
heroName.Size = UDim2.new(1, -(RING_SIZE + space(3)), 0, 16)

local xpBar = UiTheme.bar(left, UiTheme.Bar.Xp, UiTheme.Gold)
xpBar.track.Position = UDim2.fromOffset(0, RING_SIZE + space(3))
xpBar.track.BackgroundColor3 = UiTheme.Raised
xpBar.track.BackgroundTransparency = 0.88

local xpLabel = UiTheme.text(left, Size.Small, Font.Medium, Strength.Faint)
xpLabel.Position = UDim2.fromOffset(0, RING_SIZE + space(3) + UiTheme.Bar.Xp + space(1))
xpLabel.Size = UDim2.new(1, 0, 0, 14)

-- Left column: attributes -----------------------------------------------------------

local ATTRIBUTES_TOP = RING_SIZE + space(11)
caption(left, "ATTRIBUTES", ATTRIBUTES_TOP)
local statValues: { [string]: TextLabel } = {}
for index, info in STATS do
	local row = Instance.new("Frame")
	row.Name = info.attribute
	row.Position = UDim2.fromOffset(0, ATTRIBUTES_TOP + space(5) + (index - 1) * ROW_HEIGHT)
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.Parent = left
	local name = UiTheme.text(row, Size.Value - 1, Font.Medium, Strength.Label)
	name.Size = UDim2.fromScale(0.65, 1)
	name.Text = info.label
	local value = UiTheme.text(row, Size.Value - 1, Font.Bold)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	value.Size = UDim2.fromScale(0.35, 1)
	value.TextXAlignment = Enum.TextXAlignment.Right
	statValues[info.attribute] = value
end

-- Tooltip ---------------------------------------------------------------------------
-- One box, shown next to the mouse while it is over an ability or talent slot.

local tooltip = UiTheme.panel(screen, 0.08)
tooltip.Name = "Tooltip"
tooltip.Size = UDim2.fromOffset(TOOLTIP_WIDTH, 0)
tooltip.AutomaticSize = Enum.AutomaticSize.Y
tooltip.Visible = false
tooltip.ZIndex = 50
local tooltipScale = UiTheme.applyScale(tooltip) -- kept equal to the menu's scale (fitToScreen)
padding(tooltip, space(3), space(3), space(3))
local tipLayout = Instance.new("UIListLayout")
tipLayout.Padding = UDim.new(0, space(1))
tipLayout.SortOrder = Enum.SortOrder.LayoutOrder
tipLayout.Parent = tooltip
local tipTitle = UiTheme.text(tooltip, Size.Value, Font.Heavy)
tipTitle.LayoutOrder = 1
tipTitle.Size = UDim2.new(1, 0, 0, 20)
tipTitle.ZIndex = 51
local tipBody = UiTheme.text(tooltip, Size.Body - 1, Font.Regular, Strength.Label)
tipBody.LayoutOrder = 2
tipBody.Size = UDim2.fromScale(1, 0)
tipBody.AutomaticSize = Enum.AutomaticSize.Y
tipBody.TextWrapped = true
tipBody.TextTruncate = Enum.TextTruncate.None
tipBody.RichText = true
tipBody.ZIndex = 51

local GOLD_HEX = UiTheme.Gold:ToHex()
local hovered: GuiObject? = nil
local describe: { [GuiObject]: () -> (string, string) } = {}

local function placeTooltip()
	local mouse = UserInputService:GetMouseLocation()
	local viewport = Workspace.CurrentCamera.ViewportSize
	local size = tooltip.AbsoluteSize
	-- Right of and below the cursor, flipped if it would leave the screen.
	local x = if mouse.X + 16 + size.X > viewport.X then mouse.X - 16 - size.X else mouse.X + 16
	local y = math.min(mouse.Y + 16, viewport.Y - size.Y - 8)
	tooltip.Position = UDim2.fromOffset(x, y)
end

local function showTooltip(target: GuiObject)
	local describeFn = describe[target]
	if not describeFn then
		return
	end
	local title, body = describeFn()
	tipTitle.Text = title
	tipBody.Text = body
	tooltip.Visible = true
	placeTooltip()
end

-- Makes a slot show a tooltip; describeFn returns (title, body) when hovered,
-- so the details are always current.
local function addTooltip(target: GuiObject, describeFn: () -> (string, string))
	describe[target] = describeFn
	target.MouseEnter:Connect(function()
		hovered = target
		showTooltip(target)
	end)
	target.MouseLeave:Connect(function()
		if hovered == target then
			hovered = nil
			tooltip.Visible = false
		end
	end)
end

UserInputService.InputChanged:Connect(function(input)
	if tooltip.Visible and input.UserInputType == Enum.UserInputType.MouseMovement then
		placeTooltip()
	end
end)

-- Left column: abilities and talents ---------------------------------------------------

local function slotRow(y: number): Frame
	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(0, y)
	row.Size = UDim2.new(1, 0, 0, SLOT_SIZE)
	row.BackgroundTransparency = 1
	row.Parent = left
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, space(2))
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	return row
end

local ABILITIES_TOP = ATTRIBUTES_TOP + space(5) + #STATS * ROW_HEIGHT + space(4)
caption(left, "ABILITIES", ABILITIES_TOP)
local abilityRow = slotRow(ABILITIES_TOP + space(5))
for index, skill in SKILLS do
	local box = slot(abilityRow, skill.tag, SLOT_SIZE, skill.locked)
	box.Name = skill.name
	box.LayoutOrder = index
	addTooltip(box, function()
		if skill.locked then
			return `{skill.name}  [{skill.key}]`, "Locked. Talents will unlock abilities later."
		end
		return `{skill.name}  [{skill.key}]`,
			"Fire a bolt where you aim. It hits the first enemy in line; out of range is a miss. "
				.. "Aim assist locks on when the crosshair is right next to an enemy.\n\n"
				.. `Damage <b>{statText("StatAttackDamage")}</b>   Range <b>{statText("StatAttackRange")}</b>\n`
				.. `Cooldown <b>{formatNumber(Config.Hero.Pulse.Cooldown)}</b> s  ({statText("StatAttackSpeed")} per second)`
	end)
end

local TALENTS_TOP = ABILITIES_TOP + space(5) + SLOT_SIZE + space(4)
caption(left, "TALENTS", TALENTS_TOP)
local talentRow = slotRow(TALENTS_TOP + space(5))
local noTalents = UiTheme.text(talentRow, Size.Small + 1, Font.Medium, Strength.Faint)
noTalents.LayoutOrder = 0
noTalents.Size = UDim2.fromScale(1, 1)
noTalents.Text = "None yet"

-- One slot per talent, shown once taken, with a gold count chip.
type TalentView = { box: Frame, count: TextLabel }
local talentViews: { [string]: TalentView } = {}
for index, card in CARDS do
	local box = slot(talentRow, card.stat.tag, SLOT_SIZE)
	box.Name = card.id
	box.LayoutOrder = index
	box.Visible = false
	local chip = Instance.new("Frame")
	chip.AnchorPoint = Vector2.new(1, 1)
	chip.Position = UDim2.new(1, 4, 1, 4)
	chip.Size = UDim2.fromOffset(18, 14)
	chip.BackgroundColor3 = UiTheme.Gold
	chip.BorderSizePixel = 0
	chip.ZIndex = 3
	chip.Parent = box
	UiTheme.corner(chip, 4)
	local count = UiTheme.text(chip, 10, Font.Heavy)
	count.Size = UDim2.fromScale(1, 1)
	count.TextXAlignment = Enum.TextXAlignment.Center
	count.TextColor3 = UiTheme.OnGold
	count.ZIndex = 4
	talentViews[card.id] = { box = box, count = count }
	addTooltip(box, function()
		local taken = math.floor(readNumber(card.id .. "Picks") or 0)
		local factor = upgradeFactors[card.id] or 1
		return `{card.name}  x{taken}`,
			`{card.effect}\nEach pick: x{formatNumber(factor)} {string.lower(card.stat.label)}.\n\n`
				.. `Total <b>x{formatNumber(factor ^ taken)}</b>   Now <b>{statText(card.stat.attribute)}{card.stat.unit}</b>`
	end)
end

-- Divider between the columns.
local divider = Instance.new("Frame")
divider.Position = UDim2.new(LEFT_SHARE, 0, 0, PAD)
divider.Size = UDim2.new(0, 1, 1, -PAD * 2)
divider.BackgroundColor3 = UiTheme.Raised
divider.BackgroundTransparency = 0.88
divider.BorderSizePixel = 0
divider.Parent = window

-- Right column ---------------------------------------------------------------------

local rightTitle = UiTheme.text(right, Size.Heading, Font.Heavy)
rightTitle.Size = UDim2.new(1, 0, 0, 28)

local rightSub = UiTheme.text(right, Size.Small + 1, Font.Bold)
rightSub.Position = UDim2.fromOffset(0, 28)
rightSub.Size = UDim2.new(1, 0, 0, 16)
rightSub.TextColor3 = UiTheme.Gold

local CARDS_TOP = space(15)

local cardRow = Instance.new("Frame")
cardRow.Name = "Cards"
cardRow.Position = UDim2.fromOffset(0, CARDS_TOP)
cardRow.Size = UDim2.new(1, 0, 0, 220)
cardRow.BackgroundTransparency = 1
cardRow.Parent = right
local cardLayout = Instance.new("UIListLayout")
cardLayout.FillDirection = Enum.FillDirection.Horizontal
cardLayout.Padding = UDim.new(0, space(3))
cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardLayout.Parent = cardRow

local setOpen: (boolean) -> () -- defined below

-- Sends the pick and closes the menu (owner 2026-10-20); the ring's gold "U"
-- pill stays if more picks are waiting, so the player can reopen it.
local function choose(id: string)
	if pending() > 0 then
		chooseEvent:FireServer(id)
	end
	setOpen(false)
end

type CardView = { info: CardInfo, preview: TextLabel }
local cardViews: { CardView } = {}

for index, info in CARDS do
	local card = Instance.new("TextButton")
	card.Name = info.id
	card.LayoutOrder = index
	card.Size = UDim2.new(1 / 3, -space(2), 1, 0)
	card.BackgroundColor3 = UiTheme.Raised
	card.BackgroundTransparency = UiTheme.RaisedTransparency
	card.AutoButtonColor = false
	card.Text = ""
	card.Parent = cardRow
	UiTheme.corner(card, 10)
	padding(card, space(4), space(3), space(4))
	local line = Instance.new("UIStroke")
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Color = UiTheme.Gold
	line.Thickness = 1
	line.Transparency = 1 -- shown on hover
	line.Parent = card

	local tag = UiTheme.text(card, Size.Small, Font.Heavy, Strength.Label)
	tag.Size = UDim2.new(1, -20, 0, 16)
	tag.Text = info.stat.tag
	local key = UiTheme.text(card, Size.Caption, Font.Bold, Strength.Faint)
	key.AnchorPoint = Vector2.new(1, 0)
	key.Position = UDim2.fromScale(1, 0)
	key.Size = UDim2.fromOffset(20, 16)
	key.TextXAlignment = Enum.TextXAlignment.Right
	key.Text = tostring(index)

	local name = UiTheme.text(card, Size.Value + 2, Font.Heavy)
	name.Position = UDim2.fromOffset(0, space(7))
	name.Size = UDim2.new(1, 0, 0, 22)
	name.Text = info.name

	local effect = UiTheme.text(card, Size.Body - 1, Font.Regular, Strength.Label)
	effect.Position = UDim2.fromOffset(0, space(13))
	effect.Size = UDim2.new(1, 0, 0, 56)
	effect.TextWrapped = true
	effect.TextTruncate = Enum.TextTruncate.None
	effect.TextYAlignment = Enum.TextYAlignment.Top
	effect.Text = `{info.effect} x{formatNumber(upgradeFactors[info.id] or 1)}.`

	local preview = UiTheme.text(card, Size.Value, Font.Bold)
	preview.AnchorPoint = Vector2.new(0, 1)
	preview.Position = UDim2.fromScale(0, 1)
	preview.Size = UDim2.new(1, 0, 0, 20)
	preview.RichText = true

	card.MouseEnter:Connect(function()
		card.BackgroundTransparency = UiTheme.RaisedHoverTransparency
		line.Transparency = 0.4
		tag.TextColor3 = UiTheme.Gold
		tag.TextTransparency = 0
	end)
	card.MouseLeave:Connect(function()
		card.BackgroundTransparency = UiTheme.RaisedTransparency
		line.Transparency = 1
		tag.TextColor3 = UiTheme.Text
		tag.TextTransparency = Strength.Label
	end)
	card.Activated:Connect(function()
		choose(info.id)
	end)
	table.insert(cardViews, { info = info, preview = preview })
end

-- No-pick note (shown when nothing is waiting).
local note = Instance.new("Frame")
note.Name = "Note"
note.Position = UDim2.fromOffset(0, CARDS_TOP)
note.Size = UDim2.new(1, 0, 0, 120)
note.BackgroundTransparency = 1
note.Parent = right
local noteNext = UiTheme.text(note, Size.Value + 2, Font.Heavy)
noteNext.Size = UDim2.new(1, 0, 0, 24)
local noteHint = UiTheme.text(note, Size.Body, Font.Regular, Strength.Label)
noteHint.Position = UDim2.fromOffset(0, space(8))
noteHint.Size = UDim2.new(1, 0, 0, 60)
noteHint.TextWrapped = true
noteHint.TextTruncate = Enum.TextTruncate.None
noteHint.TextYAlignment = Enum.TextYAlignment.Top
noteHint.Text = "Every zombie that falls gives you XP. Talents you take appear on the left; hover them for details."

local closeHint = UiTheme.text(right, Size.Small, Font.Medium, Strength.Faint)
closeHint.AnchorPoint = Vector2.new(1, 1)
closeHint.Position = UDim2.fromScale(1, 1)
closeHint.Size = UDim2.fromOffset(120, 16)
closeHint.TextXAlignment = Enum.TextXAlignment.Right
closeHint.Text = "U to close"

-- Refresh -------------------------------------------------------------------------

local function refresh()
	local character = player.Character
	local hero = character and character:GetAttribute("HeroName")
	heroName.Text = if type(hero) == "string" then hero else Config.Hero.Name

	local level = math.max(math.floor(readNumber("Level") or 1), 1)
	local xp = math.floor(readNumber("Xp") or 0)
	local toNext = math.floor(readNumber("XpToNext") or 0)
	levelLabel.Text = tostring(level)
	xpBar.fill.Size = UDim2.fromScale(if toNext > 0 then math.clamp(xp / toNext, 0, 1) else 0, 1)
	xpLabel.Text = if toNext > 0 then `{xp} / {toNext} XP` else `{xp} XP`

	for _, info in STATS do
		local value = readNumber(info.attribute)
		statValues[info.attribute].Text = if value then formatNumber(value) .. info.unit else "-"
	end

	local picks = pending()
	cardRow.Visible = picks > 0
	note.Visible = picks <= 0
	if picks > 0 then
		rightTitle.Text = "Choose a talent"
		rightSub.Text = if picks > 1 then `Level up  ·  {picks} picks left` else "Level up"
		for _, view in cardViews do
			local current = readNumber(view.info.stat.attribute)
			local factor = upgradeFactors[view.info.id] or 1
			view.preview.Text = if current
				then `{formatNumber(current)}  <font transparency="0.6">-&gt;</font>  <font color="#{GOLD_HEX}">{formatNumber(current * factor)}</font>`
				else ""
		end
	else
		rightTitle.Text = "Talents"
		rightSub.Text = "Level up to earn a pick"
		noteNext.Text = if toNext > 0 then `Next pick at level {level + 1}  ({toNext - xp} XP to go)` else ""
	end

	local anyTaken = false
	for id, view in talentViews do
		local count = math.floor(readNumber(id .. "Picks") or 0)
		view.box.Visible = count > 0
		view.count.Text = tostring(count)
		anyTaken = anyTaken or count > 0
	end
	noTalents.Visible = not anyTaken

	-- Keep an open tooltip's numbers current (e.g. right after a pick).
	if hovered and tooltip.Visible then
		showTooltip(hovered)
	end
end

-- Open / close -----------------------------------------------------------------------

local function fitToScreen()
	local viewport = Workspace.CurrentCamera.ViewportSize
	fit.Scale = math.min(MENU_SCALE, (viewport.X - 32) / WINDOW_WIDTH, (viewport.Y - 32) / WINDOW_HEIGHT)
	tooltipScale.Scale = fit.Scale
end

function setOpen(open: boolean)
	if screen.Enabled == open then
		return
	end
	if open then
		fitToScreen()
		refresh()
	else
		hovered = nil
		tooltip.Visible = false
	end
	screen.Enabled = open
	-- The crosshair script hides the mouse icon; show it while the menu is open.
	UserInputService.MouseIconEnabled = open
end

player.AttributeChanged:Connect(function()
	if screen.Enabled then
		refresh()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.U then
		setOpen(not screen.Enabled)
	elseif screen.Enabled and pending() > 0 then
		local index = if input.KeyCode == Enum.KeyCode.One
			then 1
			elseif input.KeyCode == Enum.KeyCode.Two then 2
			elseif input.KeyCode == Enum.KeyCode.Three then 3
			else nil
		if index then
			choose(CARDS[index].id)
		end
	end
end)

-- The HUD's level ring (built by HeroHud.client) opens the menu too.
task.spawn(function()
	local hud = playerGui:WaitForChild("HeroHud")
	local button = hud:WaitForChild("Panel"):WaitForChild("LevelBadge"):WaitForChild("OpenUpgrades")
	if button:IsA("GuiButton") then
		button.Activated:Connect(function()
			setOpen(true)
		end)
	end
end)
