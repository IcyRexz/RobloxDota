--!strict
-- Hero HUD on each player's own screen, in the game's UI design system
-- (docs/11_UI_DESIGN.md, values from UiTheme; blocky restyle owner 2026-10-22):
--  * bottom centre, your own hero, with no box around it (owner 2026-10-22):
--    a level ring, a chunky health bar with "current / max" inside it, a gold
--    XP bar with "xp / next XP" beside it, and the Mage's slots: Bolt, Strike
--    on Q and Teleport on E (no passive or base buff slot, owner 2026-10-22),
--    with circular cooldown sweeps. Pips along the bottom of the Bolt slot fill
--    towards the next Arcane Resonance (the character's Resonance attribute)
--    and the slot turns gold when the next hit triggers it.
--    Level and XP follow the server's Level / Xp / XpToNext Player attributes.
--    The ring is navy normally and turns gold with a soft pulsing glow only
--    while a mastery pick is waiting (MasteryPoints > 0), with a gold
--    "MASTERY" pill above it; clicking the ring (or pressing U) opens the
--    Character Menu (CharacterMenu.client).
--  * over every other hero's head: their name above a health bar (green
--    your side, red the enemy). Your own has none: the camera is first person.
-- The health bars show a pale "recent damage" chunk that drains shortly after a hit.
-- Display only: the server owns hero health (the Health/MaxHealth attributes).
-- Desktop layout for now; the phone layout is decided when touch controls are built.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MageAbilities = require(ReplicatedStorage.Shared.MageAbilities)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Font = UiTheme.Font
local Size = UiTheme.TextSize
local Strength = UiTheme.Strength
local space = UiTheme.space

local CHIP_DELAY = 0.35 -- seconds before the recent-damage chunk drains
local CHIP_DRAIN = 0.3
local CHIP_TRANSPARENCY = 0.5 -- the chunk is white at 50%
local RING_SIZE = 72
local BLOCK_WIDTH = 340
local SLOT_SIZE = 56
local HEALTH_HEIGHT = 22 -- the HUD's own bar: bigger than UiTheme.Bar.Health, numbers inside
local XP_HEIGHT = 10
-- Players are always on our side; used until the server sets the attribute.
local DEFAULT_TEAM = Config.Teams.Defenders

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Roblox's own health bar is replaced by ours.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local function localTeam(): string
	local team = player:GetAttribute("Team")
	return if type(team) == "string" then team else DEFAULT_TEAM
end

local function readHealth(character: Model): (number, number)
	local health = character:GetAttribute("Health")
	local maxHealth = character:GetAttribute("MaxHealth")
	local max = if type(maxHealth) == "number" and maxHealth > 0 then maxHealth else 1
	local current = if type(health) == "number" then math.clamp(health, 0, max) else max
	return current, max
end

local function readWholeNumber(name: string): number?
	local value = player:GetAttribute(name)
	if type(value) ~= "number" or value ~= value or value < 0 or value > 1e9 then
		return nil
	end
	return math.floor(value)
end

-- A health bar with the pale recent-damage chunk behind its fill.
type HealthBar = { track: Frame, chip: Frame, fill: Frame }

local function healthBar(parent: Instance, height: number): HealthBar
	local bar = UiTheme.bar(parent, height, UiTheme.Ally)
	local chip = Instance.new("Frame")
	chip.Name = "DamageChip"
	chip.Size = UDim2.fromScale(1, 1)
	chip.BackgroundColor3 = UiTheme.Text
	chip.BackgroundTransparency = CHIP_TRANSPARENCY
	chip.BorderSizePixel = 0
	chip.ZIndex = 1
	chip.Parent = bar.track
	UiTheme.corner(chip, math.ceil(height / 2))
	bar.fill.ZIndex = 2 -- the fill draws over the chunk
	return { track = bar.track, chip = chip, fill = bar.fill }
end

-- Moves the fill at once and lets the damage chip catch up after a moment.
local function setHealth(bar: HealthBar, current: number, max: number, color: Color3)
	local share = current / max
	bar.fill.BackgroundColor3 = color
	bar.fill.Size = UDim2.fromScale(share, 1)
	if share >= bar.chip.Size.X.Scale then
		bar.chip.Size = UDim2.fromScale(share, 1) -- healed: no chip
	else
		TweenService:Create(
			bar.chip,
			TweenInfo.new(CHIP_DRAIN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, CHIP_DELAY),
			{ Size = UDim2.fromScale(share, 1) }
		):Play()
	end
end

-- Bottom HUD ---------------------------------------------------------------------------
--  (MASTERY)
--  ( LV )  [######## 600 / 600 ########]     health (22 px, numbers inside)
--  ( 12 )  [=====-----------]   12 / 30 XP   xp (10 px, gold)
--          [BOLT] [ Q ] [ E ]                 slots

local screen = Instance.new("ScreenGui")
screen.Name = "HeroHud"
screen.ResetOnSpawn = false
screen.Parent = playerGui

local BLOCK_X = RING_SIZE + space(4)
local XP_Y = HEALTH_HEIGHT + space(2)
local SLOTS_Y = XP_Y + XP_HEIGHT + space(4) -- room for the key chips above the slots
local PANEL_HEIGHT = SLOTS_Y + SLOT_SIZE
local XP_TEXT_WIDTH = 84 -- room right of the XP bar for "xp / next XP"
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -space(4))
panel.Size = UDim2.fromOffset(BLOCK_X + BLOCK_WIDTH, PANEL_HEIGHT)
panel.BackgroundTransparency = 1
panel.Parent = screen
UiTheme.applyScale(panel)

-- Level ring (the badge). Named LevelBadge / OpenUpgrades for CharacterMenu.client.
-- Soft gold glow behind the ring, shown (pulsing) only while a pick is waiting.
local RING_Y = PANEL_HEIGHT - RING_SIZE
local GLOW_SIZE = RING_SIZE + space(4)
local glow = Instance.new("Frame")
glow.Name = "Glow"
glow.AnchorPoint = Vector2.new(0.5, 0.5)
glow.Position = UDim2.fromOffset(RING_SIZE / 2, RING_Y + RING_SIZE / 2)
glow.Size = UDim2.fromOffset(GLOW_SIZE, GLOW_SIZE)
glow.BackgroundColor3 = UiTheme.Gold
glow.BackgroundTransparency = 0.6
glow.BorderSizePixel = 0
glow.Visible = false
glow.Parent = panel
UiTheme.corner(glow, GLOW_SIZE // 2)
local glowPulse = TweenService:Create(
	glow,
	TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ BackgroundTransparency = 0.9, Size = UDim2.fromOffset(GLOW_SIZE + space(3), GLOW_SIZE + space(3)) }
)

local badge = UiTheme.block(panel, "Navy", RING_SIZE // 2)
badge.Name = "LevelBadge"
badge.Position = UDim2.fromOffset(0, RING_Y)
badge.Size = UDim2.fromOffset(RING_SIZE, RING_SIZE)
badge.ZIndex = 2

-- Navy normally; gold and glowing while a pick is waiting.
local function setPickWaiting(waiting: boolean)
	UiTheme.setFill(badge, if waiting then "Gold" else "Navy")
	glow.Visible = waiting
	if waiting then
		glowPulse:Play()
	else
		glowPulse:Cancel()
	end
end
setPickWaiting(false)
local levelCaption = UiTheme.text(badge, Size.Small, Font.Bold)
levelCaption.Position = UDim2.fromOffset(0, 11)
levelCaption.Size = UDim2.new(1, 0, 0, 14)
levelCaption.TextXAlignment = Enum.TextXAlignment.Center
levelCaption.ZIndex = 2
levelCaption.Text = "LV"
local levelText = UiTheme.text(badge, 32, Font.Heavy)
levelText.Position = UDim2.fromOffset(0, 24)
levelText.Size = UDim2.new(1, 0, 0, 34)
levelText.TextXAlignment = Enum.TextXAlignment.Center
levelText.ZIndex = 2
levelText.Text = "1"

local badgeButton = Instance.new("TextButton")
badgeButton.Name = "OpenUpgrades"
badgeButton.BackgroundTransparency = 1
badgeButton.Text = ""
badgeButton.Size = UDim2.fromScale(1, 1)
badgeButton.ZIndex = 3
badgeButton.Parent = badge

-- "MASTERY" pill above the ring while a mastery pick is waiting: a gold block
-- with a navy key chip showing U (opens the Character Menu), and "x2" when
-- several picks are queued. It bobs gently so it is noticed without shouting.
local PILL_Y = RING_Y - space(2)
local pickHint = UiTheme.block(panel, "Gold", UiTheme.Radius, UiTheme.OutlineThin)
pickHint.Name = "PickHint"
pickHint.AnchorPoint = Vector2.new(0.5, 1)
pickHint.Position = UDim2.fromOffset(RING_SIZE / 2, PILL_Y)
pickHint.Size = UDim2.fromOffset(0, 28)
pickHint.AutomaticSize = Enum.AutomaticSize.X
pickHint.Visible = false
pickHint.ZIndex = 4
local pickPad = Instance.new("UIPadding")
pickPad.PaddingLeft = UDim.new(0, space(1))
pickPad.PaddingRight = UDim.new(0, space(2))
pickPad.Parent = pickHint
local pickLayout = Instance.new("UIListLayout")
pickLayout.FillDirection = Enum.FillDirection.Horizontal
pickLayout.VerticalAlignment = Enum.VerticalAlignment.Center
pickLayout.Padding = UDim.new(0, space(1) + 2)
pickLayout.SortOrder = Enum.SortOrder.LayoutOrder
pickLayout.Parent = pickHint
local keyChip = UiTheme.block(pickHint, "Navy", 6, UiTheme.OutlineThin)
keyChip.LayoutOrder = 1
keyChip.Size = UDim2.fromOffset(20, 20)
keyChip.ZIndex = 5
local keyChipText = UiTheme.text(keyChip, Size.Small, Font.Heavy)
keyChipText.Size = UDim2.fromScale(1, 1)
keyChipText.TextXAlignment = Enum.TextXAlignment.Center
keyChipText.ZIndex = 6
keyChipText.Text = "U"
local pickHintText = UiTheme.text(pickHint, Size.Value, Font.Heavy)
pickHintText.LayoutOrder = 2
pickHintText.Size = UDim2.fromOffset(0, 28)
pickHintText.AutomaticSize = Enum.AutomaticSize.X
pickHintText.TextTruncate = Enum.TextTruncate.None
pickHintText.ZIndex = 5
pickHintText.Text = "MASTERY"
local pickBob = TweenService:Create(
	pickHint,
	TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Position = UDim2.fromOffset(RING_SIZE / 2, PILL_Y - space(1)) }
)

-- Health bar with the numbers inside, then the XP bar.
local block = Instance.new("Frame")
block.Name = "Status"
block.Position = UDim2.fromOffset(BLOCK_X, 0)
block.Size = UDim2.fromOffset(BLOCK_WIDTH, SLOTS_Y)
block.BackgroundTransparency = 1
block.Parent = panel

local hudBar = healthBar(block, HEALTH_HEIGHT)
local hudText = UiTheme.text(hudBar.track, Size.Value, Font.Bold)
hudText.Size = UDim2.fromScale(1, 1)
hudText.TextXAlignment = Enum.TextXAlignment.Center
hudText.ZIndex = 3

local xpBar = UiTheme.bar(block, XP_HEIGHT, UiTheme.Gold)
xpBar.track.Name = "XpBar"
xpBar.track.Position = UDim2.fromOffset(0, XP_Y)
xpBar.track.Size = UDim2.new(1, -XP_TEXT_WIDTH, 0, XP_HEIGHT)
xpBar.fill.Size = UDim2.fromScale(0, 1)
-- "12 / 30 XP" right of the bar.
local xpText = UiTheme.text(block, Size.Small + 1, Font.Bold, Strength.Label)
xpText.Name = "XpText"
xpText.AnchorPoint = Vector2.new(1, 0.5)
xpText.Position = UDim2.new(1, 0, 0, XP_Y + XP_HEIGHT / 2)
xpText.Size = UDim2.fromOffset(XP_TEXT_WIDTH - space(2), 16)
xpText.TextXAlignment = Enum.TextXAlignment.Right

local function refreshXp()
	local level = readWholeNumber("Level") or 1
	local xp = readWholeNumber("Xp") or 0
	local toNext = readWholeNumber("XpToNext")
	levelText.Text = tostring(math.max(level, 1))
	xpBar.fill.Size = UDim2.fromScale(if toNext and toNext > 0 then math.clamp(xp / toNext, 0, 1) else 1, 1)
	xpText.Text = if toNext and toNext > 0 then `{xp} / {toNext} XP` else "MAX"
	local picks = readWholeNumber("MasteryPoints") or 0
	local waiting = picks > 0
	pickHintText.Text = if picks > 1 then `MASTERY  x{picks}` else "MASTERY"
	if waiting ~= pickHint.Visible then
		pickHint.Visible = waiting
		if waiting then
			pickBob:Play()
		else
			pickBob:Cancel()
			pickHint.Position = UDim2.fromOffset(RING_SIZE / 2, PILL_Y)
		end
	end
	setPickWaiting(waiting)
end
refreshXp()
player.AttributeChanged:Connect(refreshXp)

-- Ability slots.
type Slot = {
	button: TextButton,
	caption: TextLabel,
	setCooldown: (number, string) -> (), -- share left (0..1), seconds text
	action: string, -- the server action: <action>ReadyAt / <action>Cooldown on the character
	defaultCooldown: number, -- until the server has sent the length
}

local slotRow = Instance.new("Frame")
slotRow.Name = "Skills"
slotRow.Position = UDim2.fromOffset(BLOCK_X, SLOTS_Y)
slotRow.Size = UDim2.fromOffset(BLOCK_WIDTH, SLOT_SIZE)
slotRow.BackgroundTransparency = 1
slotRow.Parent = panel
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, space(3))
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = slotRow

local slots: { Slot } = {}

-- A deep blue block slot with its name in the middle and, if it has one, a navy
-- key chip on its top-left corner.
local function slotButton(name: string, label: string, key: string?, order: number): (TextButton, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = slotRow
	UiTheme.styleBlock(button, "Deep", UiTheme.Radius) -- owner 2026-10-22: Blue was too bright

	local caption = UiTheme.text(button, Size.Value + 2, Font.Heavy) -- owner 2026-10-22: bigger (was Small)
	caption.Position = UDim2.fromOffset(3, 0)
	caption.Size = UDim2.new(1, -6, 1, 0)
	caption.TextXAlignment = Enum.TextXAlignment.Center
	caption.TextScaled = true -- long names shrink to fit the slot
	caption.Text = label
	local captionLimit = Instance.new("UITextSizeConstraint")
	captionLimit.MaxTextSize = Size.Value + 2 -- 18; TELEPORT still shrinks to fit the slot
	captionLimit.Parent = caption

	if key then
		local chip = UiTheme.block(button, "Navy", 6, UiTheme.OutlineThin)
		chip.Name = "Key"
		chip.Position = UDim2.fromOffset(-space(2), -space(2))
		chip.Size = UDim2.fromOffset(0, 18)
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.ZIndex = 4
		local chipPad = Instance.new("UIPadding")
		chipPad.PaddingLeft = UDim.new(0, space(1))
		chipPad.PaddingRight = UDim.new(0, space(1))
		chipPad.Parent = chip
		local keyText = UiTheme.text(chip, Size.Caption, Font.Bold)
		keyText.Size = UDim2.fromOffset(0, 18)
		keyText.AutomaticSize = Enum.AutomaticSize.X
		keyText.TextTruncate = Enum.TextTruncate.None
		keyText.ZIndex = 5
		keyText.Text = key
	end
	return button, caption
end

local function addSlot(name: string, label: string, key: string, order: number, action: string, defaultCooldown: number): TextButton
	local button, caption = slotButton(name, label, key, order)
	-- Cooldown: a dark wedge that sweeps away like a clock, seconds in the centre.
	local setCooldown = UiTheme.radialCover(button, UiTheme.Radius)
	setCooldown(0, "")
	table.insert(slots, {
		button = button,
		caption = caption,
		setCooldown = setCooldown,
		action = action,
		defaultCooldown = defaultCooldown,
	})
	return button
end

local Skills = Config.Hero.Skills
local boltSlot = addSlot("Attack", "BOLT", "LMB", 1, "Pulse", Config.Hero.Pulse.Cooldown)
addSlot("Skill1", "STRIKE", "Q", 2, "Strike", Skills.Strike.Cooldown)
addSlot("Skill2", "TELEPORT", "E", 3, "Teleport", Skills.Teleport.Cooldown)

-- Arcane Resonance pips along the bottom of the BOLT slot (owner 2026-10-22:
-- no separate PASSIVE slot): one per hit needed before the bonus hit; the
-- slot turns gold when the next hit triggers it.
local PIP_SIZE = 7
local pipRow = Instance.new("Frame")
pipRow.Name = "Resonance"
pipRow.AnchorPoint = Vector2.new(0.5, 1)
pipRow.Position = UDim2.new(0.5, 0, 1, -5)
pipRow.Size = UDim2.new(1, 0, 0, PIP_SIZE)
pipRow.BackgroundTransparency = 1
pipRow.ZIndex = 5
pipRow.Parent = boltSlot
local pipLayout = Instance.new("UIListLayout")
pipLayout.FillDirection = Enum.FillDirection.Horizontal
pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
pipLayout.Padding = UDim.new(0, 3)
pipLayout.Parent = pipRow
local pips: { Frame } = {}
local wasCharged: boolean? = nil

local function hasMastery(id: string): boolean
	return player:GetAttribute("Mastery" .. id) == true
end

local function refreshPassive(character: Model?)
	local every = MageAbilities.resonanceEvery(hasMastery)
	local needed = every - 1
	while #pips < needed do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.fromOffset(PIP_SIZE, PIP_SIZE)
		pip.BorderSizePixel = 0
		pip.ZIndex = 5
		pip.Parent = pipRow
		UiTheme.corner(pip, 2)
		local stroke = Instance.new("UIStroke")
		stroke.Color = UiTheme.Ink
		stroke.Thickness = 1.5
		stroke.Parent = pip
		table.insert(pips, pip)
	end
	local hits = if character then character:GetAttribute("Resonance") else nil
	local count = if type(hits) == "number" then math.clamp(math.floor(hits), 0, needed) else 0
	local charged = count >= needed
	for index, pip in pips do
		pip.Visible = index <= needed
		pip.BackgroundColor3 = if index <= count then UiTheme.Text else UiTheme.Ink
	end
	if charged ~= wasCharged then
		wasCharged = charged
		UiTheme.setFill(boltSlot, if charged then "Gold" else "Deep")
	end
end

-- Cooldown sweeps follow the server's <Action>ReadyAt (server time) and
-- <Action>Cooldown (the full length, which masteries can change) attributes.
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local time = Workspace:GetServerTimeNow()
	refreshPassive(character)
	for _, slot in slots do
		local readyAt = if character then character:GetAttribute(slot.action .. "ReadyAt") else nil
		local sentLength = if character then character:GetAttribute(slot.action .. "Cooldown") else nil
		local left = if type(readyAt) == "number" then readyAt - time else 0
		local length = if type(sentLength) == "number" and sentLength > 0 then sentLength else slot.defaultCooldown
		if left > 0 then
			slot.setCooldown(left / length, if left >= 1 then tostring(math.ceil(left)) else string.format("%.1f", left))
		else
			slot.setCooldown(0, "")
		end
	end
end)

local hudConnections: { RBXScriptConnection } = {}

local function refreshHud(character: Model)
	local current, max = readHealth(character)
	setHealth(hudBar, current, max, UiTheme.Ally)
	hudText.Text = `{math.ceil(current)} / {max}`
end

local function watchOwnHero(character: Model)
	for _, connection in hudConnections do
		connection:Disconnect()
	end
	table.clear(hudConnections)
	hudBar.chip.Size = UDim2.fromScale(1, 1)
	refreshHud(character)
	-- Only the attributes the HUD shows (not e.g. the attack cooldown, which changes every shot).
	for _, name in { "Health", "MaxHealth" } do
		table.insert(hudConnections, character:GetAttributeChangedSignal(name):Connect(function()
			refreshHud(character)
		end))
	end
end

-- Overhead bars (other heroes) ------------------------------------------------------
-- Name above a bar, shown within Config.Display.HealthBarRange of your hero.

type Overhead = { billboard: BillboardGui, character: Model, alive: boolean }
local overheads: { [Model]: Overhead } = {}

local function updateOverheadVisibility(overhead: Overhead)
	local own = player.Character
	local ownRoot = own and own:FindFirstChild("HumanoidRootPart")
	local root = overhead.character:FindFirstChild("HumanoidRootPart")
	local near = false
	if ownRoot and ownRoot:IsA("BasePart") and root and root:IsA("BasePart") then
		local offset = root.Position - ownRoot.Position
		near = Vector3.new(offset.X, 0, offset.Z).Magnitude <= Config.Display.HealthBarRange
	end
	overhead.billboard.Enabled = overhead.alive and near
end

local function addOverhead(owner: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	if not (head and head:IsA("BasePart")) then
		return
	end

	-- Parented inside the character, so it is removed together with it.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HeroBar"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(110, 26)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.LightInfluence = 0
	local overhead: Overhead = { billboard = billboard, character = character, alive = false }
	overheads[character] = overhead

	local nameLabel = UiTheme.text(billboard, Size.Small, Font.Bold)
	nameLabel.Size = UDim2.new(1, 0, 0, 14)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.Text = owner.DisplayName
	UiTheme.floatingText(nameLabel)

	local bar = healthBar(billboard, UiTheme.Bar.Unit)
	bar.track.Position = UDim2.fromOffset(0, 17)

	local function refresh()
		local current, max = readHealth(character)
		local ally = character:GetAttribute("Team") == localTeam()
		setHealth(bar, current, max, if ally then UiTheme.Ally else UiTheme.Enemy)
		-- Only heroes get a bar; hide it until the server marks the character.
		overhead.alive = character:GetAttribute("Kind") == "Hero" and current > 0
		updateOverheadVisibility(overhead)
	end
	refresh()
	for _, name in { "Health", "MaxHealth", "Team", "Kind" } do
		character:GetAttributeChangedSignal(name):Connect(refresh) -- ends when the character is removed
	end
	local teamConnection = player:GetAttributeChangedSignal("Team"):Connect(refresh)
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			teamConnection:Disconnect()
			overheads[character] = nil
		end
	end)
	billboard.Parent = character
end

local function onPlayer(owner: Player)
	local function onCharacter(character: Model)
		if owner == player then
			watchOwnHero(character)
		else
			addOverhead(owner, character)
		end
	end
	owner.CharacterAdded:Connect(onCharacter)
	if owner.Character then
		task.spawn(onCharacter, owner.Character)
	end
end

for _, owner in Players:GetPlayers() do
	onPlayer(owner)
end
Players.PlayerAdded:Connect(onPlayer)

task.spawn(function()
	while true do
		for _, overhead in overheads do
			updateOverheadVisibility(overhead)
		end
		task.wait(0.2)
	end
end)
