--!strict
-- Hero health display on each player's own screen:
--  * bottom-centre HUD for your own hero: level badge (placeholder), health bar
--    with "current / max" text, xp bar (placeholder) and four skill slots with
--    cooldown covers (only the basic attack is live)
--  * over every hero's head: the player's name and a segmented health bar
--    (green your team, red the enemy), one divider per 100 health
-- Both bars show a pale "recent damage" chunk that drains shortly after a hit.
-- Display only: the server owns hero health (the Health/MaxHealth attributes).
-- Desktop layout for now; the phone layout is decided when touch controls are built.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local ALLY_COLOR = Color3.fromRGB(70, 200, 90)
local ENEMY_COLOR = Color3.fromRGB(220, 60, 60)
local DAMAGE_CHIP_COLOR = Color3.fromRGB(255, 235, 200)
local BACK_COLOR = Color3.fromRGB(20, 20, 26)
local PANEL_COLOR = Color3.fromRGB(14, 14, 20)
local BADGE_STROKE = Color3.fromRGB(150, 110, 230)
local CHIP_DELAY = 0.35 -- seconds before the recent-damage chunk drains
local CHIP_DRAIN = 0.3
local HP_PER_TICK = 100
local BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local MEDIUM = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
-- Until match teams exist (task T05), everyone is treated as Blue.
local DEFAULT_TEAM = "Blue"

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

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function newText(parent: Instance, font: Font, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = parent
	return label
end

-- A health bar: dark back, pale damage chip behind the colored fill, optional
-- dividers. setBar updates it.
type BarParts = { back: Frame, chip: Frame, fill: Frame, ticks: Frame? }

local function buildBar(parent: Instance, radius: number, withTicks: boolean): BarParts
	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.BackgroundColor3 = BACK_COLOR
	back.BorderSizePixel = 0
	back.ClipsDescendants = true
	back.Parent = parent
	corner(back, radius)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1.5
	stroke.Parent = back

	local chip = Instance.new("Frame")
	chip.Name = "DamageChip"
	chip.BackgroundColor3 = DAMAGE_CHIP_COLOR
	chip.BorderSizePixel = 0
	chip.Size = UDim2.fromScale(1, 1)
	chip.Parent = back
	corner(chip, radius)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	corner(fill, radius)
	-- Slight top shine.
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	shine.Parent = fill

	local ticks: Frame? = nil
	if withTicks then
		local t = Instance.new("Frame")
		t.Name = "Ticks"
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Parent = back
		ticks = t
	end
	return { back = back, chip = chip, fill = fill, ticks = ticks }
end

local function redrawTicks(parts: BarParts, max: number)
	local ticks = parts.ticks
	if not ticks then
		return
	end
	ticks:ClearAllChildren()
	for i = 1, math.floor((max - 1) / HP_PER_TICK) do
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = BACK_COLOR
		line.BackgroundTransparency = 0.3
		line.Size = UDim2.new(0, 1, 1, 0)
		line.Position = UDim2.fromScale(i * HP_PER_TICK / max, 0)
		line.Parent = ticks
	end
end

-- Moves the fill at once and lets the damage chip catch up after a moment.
local function setBar(parts: BarParts, current: number, max: number, color: Color3)
	local share = current / max
	parts.fill.BackgroundColor3 = color
	parts.fill.Size = UDim2.fromScale(share, 1)
	if share >= parts.chip.Size.X.Scale then
		parts.chip.Size = UDim2.fromScale(share, 1) -- healed: no chip
	else
		TweenService:Create(
			parts.chip,
			TweenInfo.new(CHIP_DRAIN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, CHIP_DELAY),
			{ Size = UDim2.fromScale(share, 1) }
		):Play()
	end
end

-- Centre HUD (your own hero) -------------------------------------------------
-- Bottom centre, two rows:
--   [LV 1] [ZEUS ======= 600 / 600 ==========]
--          [-------- xp (placeholder) -------]
--   [ATTACK] [ 1 ] [ 2 ] [ULT]   skill slots; only the basic attack works so far
-- Slots are buttons (HeroControls.client sends the attack when the Attack slot
-- is pressed), ready for touch later.

local SLOT_SIZE = 62
local SLOT_GAP = 10
local PANEL_WIDTH = 4 * SLOT_SIZE + 3 * SLOT_GAP + 160

type Slot = { button: TextButton, cooldown: Frame, cooldownText: TextLabel, readyAttribute: string? }

local screen = Instance.new("ScreenGui")
screen.Name = "HeroHud"
screen.ResetOnSpawn = false
screen.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -14)
panel.Size = UDim2.fromOffset(PANEL_WIDTH, 52 + 12 + SLOT_SIZE + 14)
panel.BackgroundTransparency = 1
panel.Parent = screen

-- Row 1: level badge and health bar.
local badge = Instance.new("Frame")
badge.Name = "LevelBadge"
badge.Size = UDim2.fromOffset(64, 46)
badge.BackgroundColor3 = PANEL_COLOR
badge.BackgroundTransparency = 0.1
badge.Parent = panel
corner(badge, 10)
local badgeStroke = Instance.new("UIStroke")
badgeStroke.Color = BADGE_STROKE
badgeStroke.Thickness = 2.5
badgeStroke.Parent = badge
local levelText = newText(badge, BOLD, 20)
levelText.Text = "LV 1" -- placeholder: levels are not in scope yet

local hudBar = buildBar(panel, 8, false)
hudBar.back.Position = UDim2.fromOffset(74, 0)
hudBar.back.Size = UDim2.new(1, -74, 0, 34)
local hudText = newText(hudBar.back, BOLD, 19)
hudText.ZIndex = 3

local heroNameText = newText(hudBar.back, MEDIUM, 13)
heroNameText.TextXAlignment = Enum.TextXAlignment.Left
heroNameText.Position = UDim2.fromOffset(10, 0)
heroNameText.Size = UDim2.new(0, 100, 1, 0)
heroNameText.ZIndex = 3

local xpBack = Instance.new("Frame")
xpBack.Name = "XpBar" -- placeholder: experience is not in scope yet
xpBack.Position = UDim2.fromOffset(74, 39)
xpBack.Size = UDim2.new(1, -74, 0, 6)
xpBack.BackgroundColor3 = BACK_COLOR
xpBack.BorderSizePixel = 0
xpBack.Parent = panel
corner(xpBack, 3)

-- Row 2: skill slots.
local slotRow = Instance.new("Frame")
slotRow.Name = "Skills"
slotRow.AnchorPoint = Vector2.new(0.5, 1)
slotRow.Position = UDim2.fromScale(0.5, 1)
slotRow.Size = UDim2.fromOffset(4 * SLOT_SIZE + 3 * SLOT_GAP, SLOT_SIZE + 10)
slotRow.BackgroundTransparency = 1
slotRow.Parent = panel
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0, SLOT_GAP)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = slotRow

local slots: { Slot } = {}

local function addSlot(name: string, label: string, key: string, order: number, locked: boolean, readyAttribute: string?)
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
	button.BackgroundColor3 = if locked then Color3.fromRGB(30, 30, 36) else Color3.fromRGB(40, 50, 80)
	button.AutoButtonColor = not locked
	button.Text = ""
	button.Active = not locked
	button.Parent = slotRow
	corner(button, 10)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = if locked then Color3.fromRGB(70, 70, 80) else Color3.fromRGB(120, 170, 255)
	stroke.Thickness = 2
	stroke.Parent = button

	local caption = newText(button, BOLD, 12)
	caption.Text = if locked then label .. "\nlocked" else label
	caption.TextColor3 = if locked then Color3.fromRGB(150, 150, 160) else Color3.new(1, 1, 1)

	-- Key hint chip in the top-left corner (desktop test keys).
	local chip = Instance.new("Frame")
	chip.Position = UDim2.fromOffset(-6, -8)
	chip.Size = UDim2.fromOffset(26, 16)
	chip.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	chip.ZIndex = 4
	chip.Parent = button
	corner(chip, 4)
	local keyText = newText(chip, BOLD, 10)
	keyText.Text = key
	keyText.ZIndex = 5

	-- Cooldown: a dark cover that shrinks downward, with seconds left.
	local cover = Instance.new("Frame")
	cover.Name = "Cooldown"
	cover.AnchorPoint = Vector2.new(0, 1)
	cover.Position = UDim2.fromScale(0, 1)
	cover.Size = UDim2.fromScale(1, 0)
	cover.BackgroundColor3 = Color3.new(0, 0, 0)
	cover.BackgroundTransparency = 0.35
	cover.BorderSizePixel = 0
	cover.ZIndex = 2
	cover.Parent = button
	corner(cover, 10)
	local coverText = newText(cover, BOLD, 16)
	coverText.ZIndex = 3

	table.insert(slots, { button = button, cooldown = cover, cooldownText = coverText, readyAttribute = readyAttribute })
end

addSlot("Attack", "ATTACK", "LMB", 1, false, "PulseReadyAt")
addSlot("Skill1", "SKILL 1", "1", 2, true, nil)
addSlot("Skill2", "SKILL 2", "2", 3, true, nil)
addSlot("Ultimate", "ULT", "3", 4, true, nil)

-- Cooldown covers follow the server's "<Action>ReadyAt" attributes (server time).
local cooldownLengths: { [string]: number } = { PulseReadyAt = Config.Hero.Pulse.Cooldown }
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local time = Workspace:GetServerTimeNow()
	for _, slot in slots do
		local attribute = slot.readyAttribute
		local readyAt = if character and attribute then character:GetAttribute(attribute) else nil
		local left = if type(readyAt) == "number" then readyAt - time else 0
		local length = if attribute then cooldownLengths[attribute] else nil
		if left > 0 and length then
			slot.cooldown.Size = UDim2.fromScale(1, math.clamp(left / length, 0, 1))
			slot.cooldownText.Text = if left >= 1 then tostring(math.ceil(left)) else string.format("%.1f", left)
		else
			slot.cooldown.Size = UDim2.fromScale(1, 0)
			slot.cooldownText.Text = ""
		end
	end
end)

local hudConnection: RBXScriptConnection? = nil

local function refreshHud(character: Model)
	local current, max = readHealth(character)
	setBar(hudBar, current, max, ALLY_COLOR)
	hudText.Text = `{math.ceil(current)} / {max}`
	local heroName = character:GetAttribute("HeroName")
	heroNameText.Text = string.upper(if type(heroName) == "string" then heroName else "Hero")
end

local function watchOwnHero(character: Model)
	if hudConnection then
		hudConnection:Disconnect()
	end
	hudBar.chip.Size = UDim2.fromScale(1, 1)
	refreshHud(character)
	hudConnection = character.AttributeChanged:Connect(function()
		refreshHud(character)
	end)
end

-- Overhead bars (every hero) --------------------------------------------------
-- Your own is always shown; others within Config.Display.HealthBarRange of your hero.

type Overhead = { billboard: BillboardGui, character: Model, isOwn: boolean, alive: boolean }
local overheads: { [Model]: Overhead } = {}

local function updateOverheadVisibility(overhead: Overhead)
	local own = player.Character
	local ownRoot = own and own:FindFirstChild("HumanoidRootPart")
	local root = overhead.character:FindFirstChild("HumanoidRootPart")
	local near = overhead.isOwn
	if not near and ownRoot and ownRoot:IsA("BasePart") and root and root:IsA("BasePart") then
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
	billboard.Size = UDim2.fromOffset(120, 30)
	billboard.StudsOffset = Vector3.new(0, 2.8, 0)
	billboard.LightInfluence = 0
	local overhead: Overhead = { billboard = billboard, character = character, isOwn = owner == player, alive = false }
	overheads[character] = overhead

	local nameLabel = newText(billboard, MEDIUM, 13)
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.Text = owner.DisplayName

	local parts = buildBar(billboard, 3, true)
	parts.back.Position = UDim2.fromOffset(0, 17)
	parts.back.Size = UDim2.new(1, 0, 0, 11)

	local function refresh()
		local current, max = readHealth(character)
		local ally = character:GetAttribute("Team") == localTeam()
		setBar(parts, current, max, if ally then ALLY_COLOR else ENEMY_COLOR)
		redrawTicks(parts, max)
		-- Only heroes get a bar; hide it until the server marks the character.
		overhead.alive = character:GetAttribute("Kind") == "Hero" and current > 0
		updateOverheadVisibility(overhead)
	end
	refresh()
	character.AttributeChanged:Connect(refresh) -- ends when the character is removed
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
		end
		addOverhead(owner, character)
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
