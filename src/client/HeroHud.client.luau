--!strict
-- Hero HUD on each player's own screen, in the game's UI design system
-- (docs/11_UI_DESIGN.md, values from UiTheme):
--  * bottom centre, your own hero: a level ring, hero name and "current / max"
--    above a thin health bar, a thin gold XP bar with "xp / next XP" beside it,
--    and four ability slots with cooldown covers. The basic attack is always
--    live; abilities 1-3 light up once their talent is taken (Has<Ability>).
--    Level and XP follow the server's Level / Xp / XpToNext Player attributes.
--    The ring is quiet normally and turns gold with a soft pulsing glow only
--    while a talent pick is waiting (UpgradesPending > 0), with a gold "U" pill
--    above it; clicking the ring (or pressing U) opens the Character Menu
--    (CharacterMenu.client).
--  * over every other hero's head: their name above a thin health bar (green
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
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Font = UiTheme.Font
local Size = UiTheme.TextSize
local Strength = UiTheme.Strength
local space = UiTheme.space

local CHIP_DELAY = 0.35 -- seconds before the recent-damage chunk drains
local CHIP_DRAIN = 0.3
local CHIP_TRANSPARENCY = 0.5 -- the chunk is white at 50%
local RING_SIZE = 52
local BLOCK_WIDTH = 300
local SLOT_SIZE = 40
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
-- [ring]  Zeus                     600 / 600
--         ==================================   health (8 px)
--         ------------                         xp (3 px, gold)
--         [BOLT] [ 1 ] [ 2 ] [ 3 ]             ability slots

local screen = Instance.new("ScreenGui")
screen.Name = "HeroHud"
screen.ResetOnSpawn = false
screen.Parent = playerGui

local BLOCK_X = RING_SIZE + space(3)
local SLOTS_Y = space(12) -- below the name, health bar and XP bar
local XP_TEXT_WIDTH = 76 -- room right of the XP bar for "xp / next XP"
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -space(4))
panel.Size = UDim2.fromOffset(BLOCK_X + BLOCK_WIDTH, SLOTS_Y + SLOT_SIZE)
panel.BackgroundTransparency = 1
panel.Parent = screen
UiTheme.applyScale(panel)

-- Level ring (the badge). Named LevelBadge / OpenUpgrades for CharacterMenu.client.
-- Soft gold glow behind the ring, shown (pulsing) only while a pick is waiting.
local GLOW_SIZE = RING_SIZE + space(4)
local glow = Instance.new("Frame")
glow.Name = "Glow"
glow.AnchorPoint = Vector2.new(0.5, 0.5)
glow.Position = UDim2.fromOffset(RING_SIZE / 2, RING_SIZE / 2)
glow.Size = UDim2.fromOffset(GLOW_SIZE, GLOW_SIZE)
glow.BackgroundColor3 = UiTheme.Gold
glow.BackgroundTransparency = 0.8
glow.BorderSizePixel = 0
glow.Visible = false
glow.Parent = panel
UiTheme.corner(glow, GLOW_SIZE // 2)
local glowPulse = TweenService:Create(
	glow,
	TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ BackgroundTransparency = 0.95, Size = UDim2.fromOffset(GLOW_SIZE + space(2), GLOW_SIZE + space(2)) }
)

local badge = UiTheme.panel(panel, nil, RING_SIZE // 2)
badge.Name = "LevelBadge"
badge.Size = UDim2.fromOffset(RING_SIZE, RING_SIZE)
badge.ZIndex = 2
local ring = Instance.new("UIStroke")
ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
ring.Parent = badge

-- Quiet white ring normally; gold, thicker and glowing while a pick is waiting.
local function setPickWaiting(waiting: boolean)
	ring.Color = if waiting then UiTheme.Gold else UiTheme.Text
	ring.Transparency = if waiting then 0 else 0.75
	ring.Thickness = if waiting then 2.5 else 1.5
	glow.Visible = waiting
	if waiting then
		glowPulse:Play()
	else
		glowPulse:Cancel()
	end
end
setPickWaiting(false)
local levelCaption = UiTheme.text(badge, 9, Font.Bold, Strength.Label)
levelCaption.Position = UDim2.fromOffset(0, 9)
levelCaption.Size = UDim2.new(1, 0, 0, 10)
levelCaption.TextXAlignment = Enum.TextXAlignment.Center
levelCaption.Text = "LV"
local levelText = UiTheme.text(badge, 20, Font.Heavy)
levelText.Position = UDim2.fromOffset(0, 19)
levelText.Size = UDim2.new(1, 0, 0, 22)
levelText.TextXAlignment = Enum.TextXAlignment.Center
levelText.Text = "1"
local badgeButton = Instance.new("TextButton")
badgeButton.Name = "OpenUpgrades"
badgeButton.BackgroundTransparency = 1
badgeButton.Text = ""
badgeButton.Size = UDim2.fromScale(1, 1)
badgeButton.ZIndex = 3
badgeButton.Parent = badge

-- "LEVEL UP" pill above the ring while a talent pick is waiting: a gold pill
-- with a dark key chip showing U (opens the Character Menu), and "x2" when
-- several picks are queued. It bobs gently so it is noticed without shouting.
local pickHint = Instance.new("Frame")
pickHint.Name = "PickHint"
pickHint.AnchorPoint = Vector2.new(0, 1)
pickHint.Position = UDim2.fromOffset(0, -space(2))
pickHint.Size = UDim2.fromOffset(0, 22)
pickHint.AutomaticSize = Enum.AutomaticSize.X
pickHint.BackgroundColor3 = UiTheme.Gold
pickHint.BorderSizePixel = 0
pickHint.Visible = false
pickHint.ZIndex = 4
pickHint.Parent = panel
UiTheme.corner(pickHint, 11)
local pickPad = Instance.new("UIPadding")
pickPad.PaddingLeft = UDim.new(0, 3)
pickPad.PaddingRight = UDim.new(0, space(2))
pickPad.Parent = pickHint
local pickLayout = Instance.new("UIListLayout")
pickLayout.FillDirection = Enum.FillDirection.Horizontal
pickLayout.VerticalAlignment = Enum.VerticalAlignment.Center
pickLayout.Padding = UDim.new(0, space(1) + 2)
pickLayout.SortOrder = Enum.SortOrder.LayoutOrder
pickLayout.Parent = pickHint
local keyChip = Instance.new("Frame")
keyChip.LayoutOrder = 1
keyChip.Size = UDim2.fromOffset(16, 16)
keyChip.BackgroundColor3 = UiTheme.OnGold
keyChip.BorderSizePixel = 0
keyChip.ZIndex = 5
keyChip.Parent = pickHint
UiTheme.corner(keyChip, 8)
local keyChipText = UiTheme.text(keyChip, Size.Caption, Font.Heavy)
keyChipText.Size = UDim2.fromScale(1, 1)
keyChipText.TextXAlignment = Enum.TextXAlignment.Center
keyChipText.TextColor3 = UiTheme.Gold
keyChipText.Text = "U"
keyChipText.ZIndex = 6
local pickHintText = UiTheme.text(pickHint, Size.Small, Font.Heavy)
pickHintText.LayoutOrder = 2
pickHintText.Size = UDim2.fromOffset(0, 22)
pickHintText.AutomaticSize = Enum.AutomaticSize.X
pickHintText.TextTruncate = Enum.TextTruncate.None
pickHintText.TextColor3 = UiTheme.OnGold
pickHintText.ZIndex = 5
pickHintText.Text = "LEVEL UP"
local pickBob = TweenService:Create(
	pickHint,
	TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Position = UDim2.fromOffset(0, -space(3)) }
)
pickHintText.TextColor3 = UiTheme.OnGold
pickHintText.Text = "U  talent"

-- Name and health numbers above the bar.
local block = Instance.new("Frame")
block.Name = "Status"
block.Position = UDim2.fromOffset(BLOCK_X, 0)
block.Size = UDim2.fromOffset(BLOCK_WIDTH, SLOTS_Y)
block.BackgroundTransparency = 1
block.Parent = panel

local heroNameText = UiTheme.text(block, Size.Small, Font.Bold, Strength.Label)
heroNameText.Size = UDim2.new(0.5, 0, 0, 16)
UiTheme.floatingText(heroNameText)
local hudText = UiTheme.text(block, Size.Small, Font.Bold)
hudText.AnchorPoint = Vector2.new(1, 0)
hudText.Position = UDim2.fromScale(1, 0)
hudText.Size = UDim2.new(0.5, 0, 0, 16)
hudText.TextXAlignment = Enum.TextXAlignment.Right
UiTheme.floatingText(hudText)

local hudBar = healthBar(block, UiTheme.Bar.Health)
hudBar.track.Position = UDim2.fromOffset(0, space(5))

local XP_Y = space(5) + UiTheme.Bar.Health + space(2)
local xpBar = UiTheme.bar(block, UiTheme.Bar.Xp, UiTheme.Gold)
xpBar.track.Name = "XpBar"
xpBar.track.Position = UDim2.fromOffset(0, XP_Y)
xpBar.track.Size = UDim2.new(1, -XP_TEXT_WIDTH, 0, UiTheme.Bar.Xp)
xpBar.fill.Size = UDim2.fromScale(0, 1)
-- "12 / 30 XP" right of the bar (labels sit beside bars, never inside).
local xpText = UiTheme.text(block, Size.Caption, Font.Bold, Strength.Label)
xpText.Name = "XpText"
xpText.AnchorPoint = Vector2.new(1, 0.5)
xpText.Position = UDim2.new(1, 0, 0, XP_Y + UiTheme.Bar.Xp / 2)
xpText.Size = UDim2.fromOffset(XP_TEXT_WIDTH - space(2), 14)
xpText.TextXAlignment = Enum.TextXAlignment.Right
UiTheme.floatingText(xpText)

local function refreshXp()
	local level = readWholeNumber("Level") or 1
	local xp = readWholeNumber("Xp") or 0
	local toNext = readWholeNumber("XpToNext")
	levelText.Text = tostring(math.max(level, 1))
	xpBar.fill.Size = UDim2.fromScale(if toNext and toNext > 0 then math.clamp(xp / toNext, 0, 1) else 1, 1)
	xpText.Text = if toNext and toNext > 0 then `{xp} / {toNext} XP` else "MAX"
	local picks = readWholeNumber("UpgradesPending") or 0
	local waiting = picks > 0
	pickHintText.Text = if picks > 1 then `LEVEL UP  x{picks}` else "LEVEL UP"
	if waiting ~= pickHint.Visible then
		pickHint.Visible = waiting
		if waiting then
			pickBob:Play()
		else
			pickBob:Cancel()
			pickHint.Position = UDim2.fromOffset(0, -space(2))
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
	readyAttribute: string?,
	unlockAttribute: string?, -- Player attribute that unlocks it (nil = always on)
	label: string, -- caption once unlocked
	key: string,
}

local slotRow = Instance.new("Frame")
slotRow.Name = "Skills"
slotRow.Position = UDim2.fromOffset(BLOCK_X, SLOTS_Y)
slotRow.Size = UDim2.fromOffset(BLOCK_WIDTH, SLOT_SIZE)
slotRow.BackgroundTransparency = 1
slotRow.Parent = panel
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, space(2))
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = slotRow

local slots: { Slot } = {}

local function addSlot(name: string, label: string, key: string, order: number, readyAttribute: string?, unlockAttribute: string?)
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
	button.BackgroundColor3 = UiTheme.Surface
	button.Text = ""
	button.Parent = slotRow
	UiTheme.corner(button)

	local keyText = UiTheme.text(button, 9, Font.Bold, Strength.Faint)
	keyText.Position = UDim2.fromOffset(space(1), 2)
	keyText.Size = UDim2.fromOffset(SLOT_SIZE, 10)
	keyText.Text = key

	local caption = UiTheme.text(button, 10, Font.Heavy)
	caption.Position = UDim2.fromOffset(0, 6)
	caption.Size = UDim2.fromScale(1, 1)
	caption.TextXAlignment = Enum.TextXAlignment.Center

	-- Cooldown: a dark wedge that sweeps away like a clock, seconds in the centre.
	local setCooldown = UiTheme.radialCover(button)
	setCooldown(0, "")

	table.insert(slots, {
		button = button,
		caption = caption,
		setCooldown = setCooldown,
		readyAttribute = readyAttribute,
		unlockAttribute = unlockAttribute,
		label = label,
		key = key,
	})
end

addSlot("Attack", "BOLT", "LMB", 1, "PulseReadyAt", nil)
addSlot("Skill1", "STRIKE", "1", 2, "StrikeReadyAt", "HasStrike")
addSlot("Skill2", "DASH", "2", 3, "DashReadyAt", "HasDash")
addSlot("Ultimate", "BALL", "3", 4, "BallReadyAt", "HasBall")

-- Locked slots are dim and show only their key; unlocked ones show their name.
local function refreshSlots()
	for _, slot in slots do
		local unlocked = slot.unlockAttribute == nil or player:GetAttribute(slot.unlockAttribute) == true
		slot.button.BackgroundTransparency = if unlocked then UiTheme.SurfaceTransparency else 0.65
		slot.button.AutoButtonColor = unlocked
		slot.button.Active = unlocked
		slot.caption.Text = if unlocked then slot.label else slot.key
		slot.caption.TextTransparency = if unlocked then Strength.Value else Strength.Faint
	end
end
refreshSlots()
player.AttributeChanged:Connect(refreshSlots)

-- Cooldown covers follow the server's "<Action>ReadyAt" attributes (server time).
local Skills = Config.Hero.Skills
local cooldownLengths: { [string]: number } = {
	PulseReadyAt = Config.Hero.Pulse.Cooldown,
	StrikeReadyAt = Skills.Strike.Cooldown,
	DashReadyAt = Skills.Dash.Cooldown,
	BallReadyAt = Skills.Ball.Cooldown,
}
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local time = Workspace:GetServerTimeNow()
	for _, slot in slots do
		local attribute = slot.readyAttribute
		local readyAt = if character and attribute then character:GetAttribute(attribute) else nil
		local left = if type(readyAt) == "number" then readyAt - time else 0
		local length = if attribute then cooldownLengths[attribute] else nil
		if left > 0 and length then
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
	local heroName = character:GetAttribute("HeroName")
	heroNameText.Text = if type(heroName) == "string" then heroName else "Hero"
end

local function watchOwnHero(character: Model)
	for _, connection in hudConnections do
		connection:Disconnect()
	end
	table.clear(hudConnections)
	hudBar.chip.Size = UDim2.fromScale(1, 1)
	refreshHud(character)
	-- Only the attributes the HUD shows (not e.g. the attack cooldown, which changes every shot).
	for _, name in { "Health", "MaxHealth", "HeroName" } do
		table.insert(hudConnections, character:GetAttributeChangedSignal(name):Connect(function()
			refreshHud(character)
		end))
	end
end

-- Overhead bars (other heroes) ------------------------------------------------------
-- Name above a thin bar, shown within Config.Display.HealthBarRange of your hero.

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
	billboard.Size = UDim2.fromOffset(110, 22)
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
