--!strict
-- Base Upgrades menu and the Upgrade Workbench (owner spec 2026-10-21). Built
-- from MenuKit, so it shares the Character Menu's layout, text styles and
-- pieces (owner 2026-10-21), with MenuKit's picker top instead of the profile
-- top (owner 2026-10-21: categories at the top left, bigger icons, their
-- numbers below), in the game's UI design system (docs/11_UI_DESIGN.md).
--  * The workbench near the spawn has a "Upgrade Workbench" label and a
--    ProximityPrompt (F, "Open Upgrades"; E is Teleport). Triggering it opens
--    this menu; nothing else does. Walking away (or dying) closes it, as does F.
--  * Left: UPGRADES, three full-width cards (Buildings, Melee Units, Archers:
--    big icon, name, "2/6"; click to select); then what the selected category
--    improves (BUILDINGS, SWORDSMAN or ARCHER) with its current numbers:
--    tower, barracks and core numbers, or soldier stats with everything bought
--    and the heroes' army buffs, and how many each barracks sends per group
--    (improved numbers in gold).
--  * Right: the category's name, its six upgrades (each bought once for its
--    own price, in any order; each names what it improves in orange), and
--    under them the info area showing whatever the mouse is over (owner
--    2026-10-21). Text is MenuKit's large size. The line under the heading
--    shows your Gold in gold, and the server's reply for a moment ("Not Enough
--    Gold", "Too far from the workbench", or what was bought). Owned tiles stay
--    lit with a gold rim and "OWNED"; prices show in gold, or enemy red when
--    you cannot afford them.
-- Reads ReplicatedStorage's Owned<UpgradeId> / Army* attributes, our
-- buildings' BaseMaxHealth / MaxHealth, and the player's Gold attribute.
-- Display only: the server (BaseUpgrades) checks and applies every purchase
-- and takes the Gold.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BaseUpgradeRules = require(ReplicatedStorage.Shared.BaseUpgradeRules)
local Config = require(ReplicatedStorage.Shared.Config)
local MenuKit = require(ReplicatedStorage.Shared.MenuKit)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local BaseConfig = Config.Base
local formatNumber = MenuKit.formatNumber
local GOLD_HEX = MenuKit.GOLD_HEX

local CLOSE_DISTANCE = BaseConfig.WorkbenchRange -- the server's purchase range
local MESSAGE_SECONDS = 2.5
local MESSAGES: { [string]: string } = {
	NotEnoughGold = "Not Enough Gold",
	Owned = "Already bought",
	TooFar = "Too far from the workbench",
}
-- Caption over the stat rows: what the numbers describe.
local STAT_CAPTIONS: { [string]: string } = {
	Buildings = "BUILDINGS",
	MeleeBarracks = "SWORDSMAN",
	ArcherBarracks = "ARCHER",
}
local CATEGORY_TEXT: { [string]: string } = {
	Buildings = "Our towers, barracks and Base Core. Health upgrades also heal each building by the health it gains.",
	MeleeBarracks = "Our swordsmen, sent by every barracks. Upgrades improve every swordsman, living or new.",
	ArcherBarracks = "Our archers, sent by every barracks. Upgrades improve every archer, living or new.",
}

type Category = { id: string, name: string, icon: string, unit: string }
type Describe = () -> (string, string?, string) -- title, improves, body

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local requestEvent = ReplicatedStorage:WaitForChild("BaseUpgrade") :: RemoteEvent
local resultEvent = ReplicatedStorage:WaitForChild("BaseUpgradeResult") :: RemoteEvent
local arena = Workspace:WaitForChild("Arena")

-- Grid rows the largest category needs (the info area sits under them).
local mostTiles = 0
for _, list in BaseConfig.Upgrades do
	mostTiles = math.max(mostTiles, #list)
end

local menu = MenuKit.new("BaseUpgrades", playerGui, {
	statsCaption = "",
	pickerCaption = "UPGRADES",
	pickerCount = #BaseConfig.Categories,
	closeText = "F to close",
	statRows = 6, -- Buildings shows six numbers; soldiers five
	infoUnderGrid = math.ceil(mostTiles / MenuKit.COLUMNS),
	largeText = true,
})

-- Helpers ---------------------------------------------------------------------------

local function isOwned(id: string): boolean
	return ReplicatedStorage:GetAttribute("Owned" .. id) == true
end

local function gold(): number
	local value = player:GetAttribute("Gold")
	return if type(value) == "number" and value == value then math.floor(value) else 0
end

local function share(name: string): number
	local value = ReplicatedStorage:GetAttribute(name)
	return if type(value) == "number" and value == value then value else 0
end

-- The heroes' army buffs as the server last published them.
local function army(): BaseUpgradeRules.Army
	return { health = share("ArmyHealth"), damage = share("ArmyDamage"), attackSpeed = share("ArmyAttackSpeed") }
end

-- How much of a category is bought: (done, total).
local function progressOf(category: Category): (number, number)
	local list = BaseConfig.Upgrades[category.id]
	local count = 0
	for _, info in list do
		count += if isOwned(info.id) then 1 else 0
	end
	return count, #list
end

-- A building kind's map max health (before upgrades), from any of our
-- buildings of that kind; remembered, so it still shows once they fall.
local baseMaxHealth: { [string]: number } = {}
local function mapMaxHealth(kind: string): number?
	if baseMaxHealth[kind] then
		return baseMaxHealth[kind]
	end
	for _, item in arena:GetDescendants() do
		if item:GetAttribute("Kind") == kind and item:GetAttribute("Team") == Config.Teams.Defenders then
			local value = item:GetAttribute("BaseMaxHealth") or item:GetAttribute("MaxHealth")
			if type(value) == "number" then
				baseMaxHealth[kind] = value
				return value
			end
		end
	end
	return nil
end

-- How many of a kind one barracks sends in each group: the group's own count
-- plus Reinforcements (every standing barracks sends this many).
local function perBarracks(kind: string, extra: number): number
	local count = extra
	for _, stats in Config.Minion.Groups[Config.Teams.Defenders] do
		count += if stats.kind == kind then 1 else 0
	end
	return count
end

local function buildingLines(): { { any } }
	local mods = BaseUpgradeRules.buildingMods(isOwned)
	local tower = BaseUpgradeRules.towerStats(mods)
	local structure = Config.Structure
	local function health(label: string, kind: string, gain: number): { any }
		local base = mapMaxHealth(kind)
		local value = if base then tostring(BaseUpgradeRules.buildingMaxHealth(kind, base, mods)) else "-"
		return { label, value, gain > 0 }
	end
	return {
		health("Tower Health", "Tower", mods.towerHealth),
		{ "Tower Damage", tostring(tower.damage), mods.towerDamage > 0 },
		{ "Tower Attack Speed", `{formatNumber(1 / tower.attackInterval)}/s`, tower.attackInterval < structure.TowerAttackInterval },
		{ "Tower Range", formatNumber(tower.range), mods.towerRange > 0 },
		health("Barracks Health", "Barracks", mods.barracksHealth),
		health("Core Health", "Core", mods.coreHealth),
	}
end

local function statLines(category: Category): { { any } }
	if category.unit == "" then
		return buildingLines()
	end
	local base = Config.Minion[category.unit] :: Config.MinionStats
	local mods = BaseUpgradeRules.unitMods(category.unit, isOwned, army())
	local stats = BaseUpgradeRules.applyMods(base, mods)
	return {
		{ "Health", tostring(stats.maxHealth), stats.maxHealth > base.maxHealth },
		{ "Damage", tostring(stats.damage), stats.damage > base.damage },
		{ "Attack Speed", `{formatNumber(1 / stats.attackInterval)}/s`, stats.attackInterval < base.attackInterval },
		{ "Range", formatNumber(stats.attackRange), stats.attackRange > base.attackRange },
		{
			"Per barracks",
			`{perBarracks(base.kind, mods.extraPerGroup)} every {Config.Minion.GroupInterval[Config.Teams.Defenders]}s`,
			mods.extraPerGroup > 0,
		},
	}
end

-- Info area: shows what the mouse is over and keeps the last one shown.
local currentInfo: Describe

local function showInfo(describe: Describe)
	currentInfo = describe
	MenuKit.showInfo(menu, describe())
end

local function describeCategory(category: Category): Describe
	return function()
		local done, total = progressOf(category)
		return category.name, nil, `{CATEGORY_TEXT[category.id] or ""}\n\nUpgrades owned <b>{done}</b> / {total}`
	end
end

-- Categories ----------------------------------------------------------------------------

local selected: Category = BaseConfig.Categories[1]
local selectCategory: (Category) -> () -- defined below

type CategoryCard = { category: Category, card: MenuKit.Card }
local categoryCards: { CategoryCard } = {}

for index, category in BaseConfig.Categories do
	local card = MenuKit.card(menu, category.icon, category.name, index)
	table.insert(categoryCards, { category = category, card = card })
	local describe = describeCategory(category)
	card.button.MouseEnter:Connect(function()
		card.hover = true
		MenuKit.styleCard(card, category == selected)
		showInfo(describe)
	end)
	card.button.MouseLeave:Connect(function()
		card.hover = false
		MenuKit.styleCard(card, category == selected)
	end)
	card.button.Activated:Connect(function()
		selectCategory(category)
		showInfo(describe)
	end)
end

-- Upgrade tiles ------------------------------------------------------------------------

local pips: { Frame } = {}

-- A tile and how to read its state: (state, corner text, corner colour).
type UpgradeTile = { tile: MenuKit.Tile, state: () -> (string, string, Color3?) }
local tiles: { UpgradeTile } = {}

local function priceColor(cost: number): Color3
	return if gold() >= cost then UiTheme.Gold else UiTheme.Enemy
end

local function styleUpgrade(view: UpgradeTile)
	MenuKit.styleTile(view.tile, view.state())
end

local function addTile(
	index: number,
	name: string,
	improves: string,
	text: string,
	state: () -> (string, string, Color3?),
	describe: Describe,
	buy: () -> ()
)
	local tile = MenuKit.tile(menu, index)
	tile.name.Text = name
	tile.improves.Text = `Improves: {improves}`
	tile.text.Text = text
	local view: UpgradeTile = { tile = tile, state = state }
	table.insert(tiles, view)
	tile.button.MouseEnter:Connect(function()
		tile.hover = true
		styleUpgrade(view)
		showInfo(describe)
	end)
	tile.button.MouseLeave:Connect(function()
		tile.hover = false
		styleUpgrade(view)
	end)
	tile.button.Activated:Connect(function()
		if view.state() == "open" then
			buy() -- the server checks Gold and replies
		end
	end)
end

-- Rebuilds the grid and pips for the selected category.
local function buildGrid()
	menu.grid:ClearAllChildren()
	table.clear(tiles)
	local category = selected
	local list = BaseConfig.Upgrades[category.id]
	pips = MenuKit.pips(menu, #list)
	for index, info in list do
		local function state(): (string, string, Color3?)
			if isOwned(info.id) then
				return "taken", "OWNED", nil
			end
			return "open", `{info.cost} Gold`, priceColor(info.cost)
		end
		addTile(index, info.name, info.improves, info.text, state, function()
			local status = if isOwned(info.id) then `<font color="#{GOLD_HEX}">Owned</font>` else "Click to buy it."
			return info.name, info.improves, `{info.text}\n\nCost <b>{info.cost}</b> Gold   {status}`
		end, function()
			requestEvent:FireServer(category.id, info.id)
		end)
	end
end

-- Refresh -------------------------------------------------------------------------

local messageText: string? = nil
local messageColor = UiTheme.Text
local messageToken = 0

local function refresh()
	local done = progressOf(selected)
	for _, entry in categoryCards do
		local cardDone, cardTotal = progressOf(entry.category)
		entry.card.detail.Text = `{cardDone}/{cardTotal}`
		MenuKit.styleCard(entry.card, entry.category == selected)
	end
	menu.statsCaption.Text = STAT_CAPTIONS[selected.id] or ""
	MenuKit.setStats(menu, statLines(selected))
	menu.heading.Text = selected.name

	if messageText then
		menu.headingSub.Text = messageText
		menu.headingSub.TextColor3 = messageColor
	else
		menu.headingSub.Text = `{gold()} Gold  ·  click an upgrade to buy it`
		menu.headingSub.TextColor3 = UiTheme.Gold
	end
	menu.headingSub.TextTransparency = 0
	for index, pip in pips do
		MenuKit.setPip(pip, if index <= done then "done" else "")
	end
	for _, view in tiles do
		styleUpgrade(view)
	end
	MenuKit.showInfo(menu, currentInfo()) -- keep its numbers current
end

-- The server's reply shows on the line under the heading for a moment.
local function showMessage(text: string, color: Color3)
	messageToken += 1
	local token = messageToken
	messageText, messageColor = text, color
	refresh()
	task.delay(MESSAGE_SECONDS, function()
		if messageToken == token then
			messageText = nil
			refresh()
		end
	end)
end

function selectCategory(category: Category)
	selected = category
	buildGrid()
	refresh()
end

currentInfo = describeCategory(selected)

resultEvent.OnClientEvent:Connect(function(result: unknown, id: unknown, detail: unknown)
	if result == "Bought" then
		local info = BaseUpgradeRules.upgrade(id, detail)
		showMessage(if info then `{info.name} bought` else "Bought", UiTheme.Gold)
	elseif type(result) == "string" and MESSAGES[result] then
		showMessage(MESSAGES[result], if result == "NotEnoughGold" then UiTheme.Enemy else UiTheme.Text)
	end
end)

-- Open / close -----------------------------------------------------------------------

-- The workbench is part of the base map (Arena > PlayerBase > UpgradeWorkbench).
local playerBase = arena:WaitForChild("PlayerBase", 30)
local bench = if playerBase then playerBase:WaitForChild("UpgradeWorkbench", 30) :: BasePart? else nil

local function setOpen(open: boolean)
	if menu.screen.Enabled == open then
		return
	end
	if open then
		menu.fitToScreen()
		messageText = nil
		selectCategory(selected)
	end
	menu.screen.Enabled = open
	-- The crosshair script hides the mouse icon; show it while the menu is open.
	UserInputService.MouseIconEnabled = open
end

ReplicatedStorage.AttributeChanged:Connect(function()
	if menu.screen.Enabled then
		refresh()
	end
end)
player:GetAttributeChangedSignal("Gold"):Connect(function()
	if menu.screen.Enabled then
		refresh()
	end
end)

-- Close when the hero walks away from the workbench or dies.
RunService.Heartbeat:Connect(function()
	if not menu.screen.Enabled then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local near = bench ~= nil
		and root ~= nil
		and root:IsA("BasePart")
		and (root.Position - bench.Position).Magnitude <= CLOSE_DISTANCE
	if not (humanoid and humanoid.Health > 0 and near) then
		setOpen(false)
	end
end)

-- Workbench: label and prompt ---------------------------------------------------------

if bench then
	local label = Instance.new("BillboardGui")
	label.Name = "WorkbenchLabel"
	label.Adornee = bench
	label.Size = UDim2.fromOffset(240, 27) -- 1.5x (owner 2026-10-21)
	label.StudsOffset = Vector3.new(0, bench.Size.Y / 2 + 1.5, 0)
	label.MaxDistance = 60
	label.LightInfluence = 0
	label.ResetOnSpawn = false
	local text = UiTheme.text(label, UiTheme.TextSize.Small * 1.5, UiTheme.Font.Bold)
	text.Size = UDim2.fromScale(1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.Text = "Upgrade Workbench"
	UiTheme.floatingText(text)
	label.Parent = playerGui

	local prompt = bench:WaitForChild("OpenUpgrades", 10)
	if prompt and prompt:IsA("ProximityPrompt") then
		-- On a device, Triggered fires only for this player's own use of the prompt.
		prompt.Triggered:Connect(function()
			setOpen(not menu.screen.Enabled)
		end)
	end
else
	warn("[BaseUpgradeMenu] No UpgradeWorkbench in the map")
end
