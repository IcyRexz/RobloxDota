--!strict
-- Core health strip at the top centre (T10, owner 2026-10-23), in the UI
-- design system (docs/11_UI_DESIGN.md): one navy block, always on,
--   Base Core [green bar, fills from the left]  VS  [red bar, fills from the right] Zombie Core
-- with "current / max" inside each bar. A bar's outline flashes white for a
-- moment when its core loses health. A destroyed core reads 0. Reads the
-- cores' server-written Health / MaxHealth attributes. Display only.
-- TargetInfo.client sits just below it (UiTheme.CoreStripHeight).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GameContext = require(ReplicatedStorage.Shared.GameContext)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Font = UiTheme.Font
local Size = UiTheme.TextSize
local space = UiTheme.space

-- Smaller (owner 2026-10-23; was 330 wide with 14 px bars).
local WIDTH = UiTheme.CoreStripWidth
local BAR_HEIGHT = 12
local LABEL_HEIGHT = 12
local VS_WIDTH = space(6)
local FLASH_SECONDS = 0.25

local player = Players.LocalPlayer
local arena = Workspace:WaitForChild("Arena")

local screen = Instance.new("ScreenGui")
screen.Name = "CoreStrip"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = player:WaitForChild("PlayerGui")
GameContext.showIn(screen, "Battle") -- battle UI: hidden in the lobby

local panel = UiTheme.panel(screen)
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, space(3))
panel.Size = UDim2.fromOffset(WIDTH, UiTheme.CoreStripHeight)
UiTheme.applyScale(panel)

type Side = { team: string, core: BasePart?, bar: UiTheme.Bar, numbers: TextLabel, outline: UIStroke?, shown: number, flashUntil: number }

-- One side of the strip: caption over a bar. `right` mirrors it (fills from the right).
local function side(team: string, title: string, color: Color3, right: boolean): Side
	local half = (WIDTH - VS_WIDTH) / 2 - space(2)
	local x = if right then WIDTH - space(2) - half else space(2)
	local caption = UiTheme.text(panel, Size.Caption, Font.Heavy)
	caption.Position = UDim2.fromOffset(x, space(1))
	caption.Size = UDim2.fromOffset(half, LABEL_HEIGHT)
	caption.TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	caption.Text = title
	local bar = UiTheme.bar(panel, BAR_HEIGHT, color)
	bar.track.Position = UDim2.fromOffset(x, space(1) + LABEL_HEIGHT + 2)
	bar.track.Size = UDim2.fromOffset(half, BAR_HEIGHT)
	if right then
		bar.fill.AnchorPoint = Vector2.new(1, 0)
		bar.fill.Position = UDim2.fromScale(1, 0)
	end
	local numbers = UiTheme.text(bar.track, Size.Caption - 1, Font.Heavy)
	numbers.Size = UDim2.fromScale(1, 1)
	numbers.TextXAlignment = Enum.TextXAlignment.Center
	numbers.ZIndex = 3
	local core: BasePart? = nil
	for _, item in arena:GetDescendants() do
		if item:IsA("BasePart") and item:GetAttribute("Kind") == "Core" and item:GetAttribute("Team") == team then
			core = item
		end
	end
	local outline = bar.track:FindFirstChild("Outline")
	return {
		team = team,
		core = core,
		bar = bar,
		numbers = numbers,
		outline = if outline and outline:IsA("UIStroke") then outline else nil,
		shown = math.huge,
		flashUntil = 0,
	}
end

local sides = {
	side(Config.Teams.Defenders, "Base Core", UiTheme.Ally, false),
	side(Config.Teams.Zombies, "Zombie Core", UiTheme.Enemy, true),
}

-- A core put back by the battlefield reset (T15) arrives as a new part.
arena.DescendantAdded:Connect(function(item: Instance)
	if item:IsA("BasePart") and item:GetAttribute("Kind") == "Core" then
		for _, entry in sides do
			if item:GetAttribute("Team") == entry.team then
				entry.core = item
				entry.shown = math.huge -- no hit flash for coming back
			end
		end
	end
end)

local vs = UiTheme.text(panel, Size.Small, Font.Heavy)
vs.AnchorPoint = Vector2.new(0.5, 0)
vs.Position = UDim2.new(0.5, 0, 0, space(1) + LABEL_HEIGHT)
vs.Size = UDim2.fromOffset(VS_WIDTH, BAR_HEIGHT + 4)
vs.TextXAlignment = Enum.TextXAlignment.Center
vs.TextColor3 = UiTheme.Gold
vs.Text = "VS"

local function readNumber(target: Instance, name: string): number
	local value = target:GetAttribute(name)
	return if type(value) == "number" and value == value then value else 0
end

GameContext.renderStepped("Battle", function()
	local now = os.clock()
	for _, entry in sides do
		local core = entry.core
		local alive = core ~= nil and core.Parent ~= nil
		local maxHealth = if core then math.max(readNumber(core, "MaxHealth"), 1) else 1
		local health = if core and alive then math.clamp(readNumber(core, "Health"), 0, maxHealth) else 0
		entry.bar.fill.Size = UDim2.fromScale(health / maxHealth, 1)
		entry.numbers.Text = `{math.ceil(health)} / {math.round(maxHealth)}`
		if health < entry.shown and entry.shown ~= math.huge then
			entry.flashUntil = now + FLASH_SECONDS
		end
		entry.shown = health
		local outline = entry.outline
		if outline then
			outline.Color = if now < entry.flashUntil then UiTheme.Text else UiTheme.Ink
		end
	end
end)
