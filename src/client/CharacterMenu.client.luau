--!strict
-- Character Menu (owner spec 2026-10-20, masteries and info area 2026-10-21),
-- built from MenuKit (the layout every full menu shares) in the game's UI
-- design system (docs/11_UI_DESIGN.md). U opens and closes it; clicking the
-- level ring also opens it.
--  * Left: level ring, player name, class, gold XP bar; ATTRIBUTES (Health,
--    Damage, Move Speed, Attack Speed, Range: the server's Stat* attributes,
--    growing each level); ABILITIES (Bolt, the Arcane Resonance passive,
--    Strike, Teleport and the Storm Banner base buff); and the info area,
--    which shows whatever ability or mastery the mouse is over (it keeps the
--    last one shown; no floating tooltips).
--  * Right: MASTERIES, a 3x3 grid (Config.Hero.Masteries). Each tile names
--    what it improves in orange. While a pick is waiting (MasteryPoints) the
--    line under the heading says "1 available" in gold and any untaken tile can
--    be clicked; picking closes the menu. Otherwise untaken tiles are greyed.
--    Taken tiles stay lit with a gold rim and "TAKEN".
-- The game keeps running while it is open (multiplayer): you can still walk,
-- but the mouse is freed (a Modal button) so you can click, and you cannot shoot.
-- Display only: the server (HeroProgress) checks and applies every pick.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local MageAbilities = require(ReplicatedStorage.Shared.MageAbilities)
local MenuKit = require(ReplicatedStorage.Shared.MenuKit)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Hero = Config.Hero
local Pulse = Hero.Pulse
local Skills = Hero.Skills
local Bonus = Hero.MasteryBonus
local formatNumber = MenuKit.formatNumber
local GOLD_HEX = MenuKit.GOLD_HEX

-- Attributes on the left, in order: label, server attribute, unit.
local STATS = {
	{ "Health", "StatMaxHealth", "" },
	{ "Health Regen", "StatHealthRegen", "/s" },
	{ "Damage", "StatAttackDamage", "" },
	{ "Move Speed", "StatMoveSpeed", "" },
	{ "Attack Speed", "StatAttackSpeed", "/s" },
	{ "Range", "StatAttackRange", "" },
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local chooseEvent = ReplicatedStorage:WaitForChild("ChooseMastery") :: RemoteEvent

local menu = MenuKit.new("CharacterMenu", playerGui, {
	statsCaption = "ATTRIBUTES",
	slotsCaption = "ABILITIES",
	closeText = "U to close",
	statRows = #STATS,
})
menu.ringCaption.Text = "LV"
menu.title.Text = player.DisplayName
menu.heading.Text = "Masteries"

-- Helpers ---------------------------------------------------------------------------

local function readNumber(name: string): number?
	local value = player:GetAttribute(name)
	if type(value) ~= "number" or value ~= value or math.abs(value) > 1e9 then
		return nil
	end
	return value
end

local function points(): number
	return math.floor(readNumber("MasteryPoints") or 0)
end

local function hasMastery(id: string): boolean
	return player:GetAttribute("Mastery" .. id) == true
end

local function percent(share: number): string
	return `{math.round(share * 100)}%`
end

local function statText(attribute: string): string
	local value = readNumber(attribute)
	return if value then formatNumber(value) else "-"
end

-- Ability damage grows with level (and Arcane Power) in step with the basic attack.
local function damageShare(): number
	local damage = readNumber("StatAttackDamage")
	return if damage then damage / Pulse.Damage else 1
end

-- Masteries taken that improve `name`, as gold lines for the info area.
local function takenFor(name: string): string
	local lines = ""
	for _, info in Hero.Masteries do
		if info.improves == name and hasMastery(info.id) then
			lines ..= `\n<font color="#{GOLD_HEX}">{info.name}</font>: {info.text}`
		end
	end
	return if lines ~= "" then "\n" .. lines else ""
end

-- What each mastery does, with its numbers (the server uses the same Config values).
local MASTERY_DETAILS: { [string]: () -> string } = {
	ChainBolt = function()
		return `Jumps to the nearest other enemy within <b>{Pulse.Chain.Range}</b> studs for <b>{percent(Pulse.Chain.Factor)}</b> damage.`
	end,
	QuickResonance = function()
		return `Arcane Resonance every <b>{Hero.Resonance.QuickEvery}</b> hits instead of {Hero.Resonance.Every}.`
	end,
	Thunderstorm = function()
		local S = Skills.Strike.Storm
		return `For <b>{S.Duration}</b> s the area strikes one enemy inside it every <b>{S.Interval}</b> s, `
			.. `for <b>{percent(S.Factor)}</b> of the strike's damage.`
	end,
	EmpoweredLightning = function()
		local E = Skills.Strike.Empowered
		return `<b>+{percent(E.RadiusFactor - 1)}</b> area size and <b>+{percent(E.DamageFactor - 1)}</b> damage.`
	end,
	QuickBlink = function()
		local T = Skills.Teleport
		return `Cooldown <b>{formatNumber(T.Cooldown)}</b> s -&gt; <b>{formatNumber(T.Cooldown * T.QuickFactor)}</b> s.`
	end,
	Vitality = function()
		return `<b>+{percent(Bonus.Vitality)}</b> max health, healed at once.`
	end,
	ArcanePower = function()
		return `<b>+{percent(Bonus.ArcanePower)}</b> damage on Lightning Bolt and every ability.`
	end,
	WarDrums = function()
		return `All our soldiers attack <b>{percent(Bonus.WarDrums)}</b> faster. Does not stack with another player's War Drums.`
	end,
	Fortify = function()
		return `All our soldiers get <b>+{percent(Bonus.Fortify)}</b> health. Does not stack with another player's Fortify.`
	end,
}

-- Info area: shows what the mouse is over and keeps the last one shown.
type Describe = () -> (string, string?, string) -- title, improves, body
local currentInfo: Describe

local function showInfo(describe: Describe)
	currentInfo = describe
	MenuKit.showInfo(menu, describe())
end

-- Abilities ---------------------------------------------------------------------------

type Ability = { tag: string, describe: Describe }
local ABILITIES: { Ability } = {
	{
		tag = "BOLT",
		describe = function()
			return "Lightning Bolt  [LMB]",
				nil,
				"Hits the first enemy where you aim. Aim assist locks on near the crosshair.\n\n"
					.. `Damage <b>{statText("StatAttackDamage")}</b>   Range <b>{statText("StatAttackRange")}</b>   `
					.. `Cooldown <b>{formatNumber(Pulse.Cooldown)}</b> s`
					.. takenFor("Lightning Bolt")
		end,
	},
	{
		tag = "PASSIVE",
		describe = function()
			local every = MageAbilities.resonanceEvery(hasMastery)
			return "Arcane Resonance  [Passive]",
				nil,
				`One bolt in every <b>{every}</b> that hit deals <b>{formatNumber(1 + Hero.Resonance.BonusFactor)}x</b> damage. `
					.. "The pips under your Bolt slot count up."
					.. takenFor("Arcane Resonance")
		end,
	},
	{
		tag = "STRIKE",
		describe = function()
			local S = Skills.Strike
			return "Lightning Strike  [Q]",
				nil,
				"Hold Q to aim at the ground, release to call lightning on the area.\n\n"
					.. `Damage <b>{formatNumber(MageAbilities.strikeDamage(hasMastery) * damageShare())}</b>   `
					.. `Radius <b>{formatNumber(MageAbilities.strikeRadius(hasMastery))}</b>   Cooldown <b>{S.Cooldown}</b> s`
					.. takenFor("Lightning Strike")
		end,
	},
	{
		tag = "TELEPORT",
		describe = function()
			local T = Skills.Teleport
			return "Teleport  [E]",
				nil,
				"Hold E to aim at open ground, release to blink there.\n\n"
					.. `Range <b>{T.Range}</b>   Cooldown <b>{formatNumber(MageAbilities.teleportCooldown(hasMastery))}</b> s`
					.. takenFor("Teleport")
		end,
	},
	{
		tag = "BANNER",
		describe = function()
			local B = Hero.BaseBuff
			return `{B.name}  [Base buff]`,
				nil,
				`All our soldiers deal <b>+{percent(B.Damage)}</b> damage while you are in the match. `
					.. "Does not stack with another Mage's banner."
		end,
	},
}

for index, ability in ABILITIES do
	local slot = MenuKit.slot(menu, ability.tag, index)
	slot.button.MouseEnter:Connect(function()
		showInfo(ability.describe)
	end)
	slot.button.Activated:Connect(function()
		showInfo(ability.describe)
	end)
end

-- Masteries -----------------------------------------------------------------------------

local pips = MenuKit.pips(menu, #Hero.MasteryLevels)
local setOpen: (boolean) -> () -- defined below

type MasteryTile = { info: Config.MasteryInfo, tile: MenuKit.Tile }
local tiles: { MasteryTile } = {}

local function styleMastery(view: MasteryTile)
	local taken = hasMastery(view.info.id)
	local state = if taken then "taken" elseif points() > 0 then "open" else "locked"
	MenuKit.styleTile(view.tile, state, if taken then "TAKEN" else "")
end

local function describeMastery(info: Config.MasteryInfo): Describe
	return function()
		local status = if hasMastery(info.id)
			then `<font color="#{GOLD_HEX}">Taken</font>`
			elseif points() > 0 then "Click to take it."
			else "Earn a pick at the next mastery level."
		return info.name, info.improves, `{MASTERY_DETAILS[info.id]()}\n\n{status}`
	end
end

for index, info in Hero.Masteries do
	local tile = MenuKit.tile(menu, index)
	tile.name.Text = info.name
	tile.improves.Text = `Improves: {info.improves}`
	tile.text.Text = info.text
	local view: MasteryTile = { info = info, tile = tile }
	table.insert(tiles, view)
	local describe = describeMastery(info)
	tile.button.MouseEnter:Connect(function()
		tile.hover = true
		styleMastery(view)
		showInfo(describe)
	end)
	tile.button.MouseLeave:Connect(function()
		tile.hover = false
		styleMastery(view)
	end)
	tile.button.Activated:Connect(function()
		if points() > 0 and not hasMastery(info.id) then
			chooseEvent:FireServer(info.id)
			setOpen(false) -- picking closes the menu (owner 2026-10-20)
		end
	end)
end

-- Refresh -------------------------------------------------------------------------

local function refresh()
	local character = player.Character
	local heroName = character and character:GetAttribute("HeroName")
	menu.subtitle.Text = if type(heroName) == "string" then heroName else Hero.Name

	local level = math.max(math.floor(readNumber("Level") or 1), 1)
	local xp = math.floor(readNumber("Xp") or 0)
	local toNext = math.floor(readNumber("XpToNext") or 0)
	menu.ringValue.Text = tostring(level)
	menu.bar.fill.Size = UDim2.fromScale(if toNext > 0 then math.clamp(xp / toNext, 0, 1) else 1, 1)
	menu.barLabel.Text = if toNext > 0 then `{xp} / {toNext} XP` else "MAX LEVEL"

	local lines: { { any } } = {}
	for _, stat in STATS do
		local value = readNumber(stat[2])
		local line: { any } = { stat[1], if value then formatNumber(value) .. stat[3] else "-", false }
		table.insert(lines, line)
	end
	MenuKit.setStats(menu, lines)

	local waiting = points()
	local takenCount = 0
	for _, info in Hero.Masteries do
		takenCount += if hasMastery(info.id) then 1 else 0
	end
	local nextLevel: number? = nil
	for _, masteryLevel in Hero.MasteryLevels do
		if masteryLevel > level then
			nextLevel = masteryLevel
			break
		end
	end
	if waiting > 0 then
		menu.headingSub.Text = `{waiting} available  ·  pick one`
		menu.headingSub.TextColor3 = UiTheme.Gold
		menu.headingSub.TextTransparency = 0
	else
		menu.headingSub.Text = if nextLevel then `Next at level {nextLevel}` else "All masteries chosen"
		menu.headingSub.TextColor3 = UiTheme.Text
		menu.headingSub.TextTransparency = UiTheme.Strength.Label
	end
	for index, pip in pips do
		MenuKit.setPip(pip, if index <= takenCount then "done" elseif index <= takenCount + waiting then "open" else "")
	end
	for _, view in tiles do
		styleMastery(view)
	end
	MenuKit.showInfo(menu, currentInfo()) -- keep its numbers current
end

currentInfo = ABILITIES[1].describe

-- Open / close -----------------------------------------------------------------------

function setOpen(open: boolean)
	if menu.screen.Enabled == open then
		return
	end
	if open then
		menu.fitToScreen()
		refresh()
	end
	menu.screen.Enabled = open
	-- The crosshair script hides the mouse icon; show it while the menu is open.
	UserInputService.MouseIconEnabled = open
end

player.AttributeChanged:Connect(function()
	if menu.screen.Enabled then
		refresh()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.U then
		setOpen(not menu.screen.Enabled)
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
