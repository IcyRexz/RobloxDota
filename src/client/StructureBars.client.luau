--!strict
-- Draws a MOBA-style name and health bar above every tower, barracks and core.
-- Green bar = your team, red bar = the enemy. This runs on each player's own
-- screen because "ally" and "enemy" depend on who is looking.
-- The bars only display health; the server owns the real numbers (the
-- structure's Health / MaxHealth attributes) and the bars follow them.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ALLY_COLOR = Color3.fromRGB(70, 200, 90)
local ENEMY_COLOR = Color3.fromRGB(220, 60, 60)
local BAR_BACK_COLOR = Color3.fromRGB(25, 25, 30)
local BAR_WIDTH = 150 -- on-screen pixels, so it stays readable at any distance
local BAR_HEIGHT = 14
local NAME_HEIGHT = 18
local HP_PER_TICK = 100 -- one divider line per 100 health, like MOBA bars
local STRUCTURE_KINDS = { Tower = true, Barracks = true, Core = true }
-- Bars farther than this from your character are hidden.
local SHOW_DISTANCE = 60
local VISIBILITY_CHECK_SECONDS = 0.2
-- Until match teams exist (task T05), everyone is treated as Blue.
local DEFAULT_TEAM = "Blue"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local arena = Workspace:WaitForChild("Arena")

type Bar = {
	billboard: BillboardGui,
	structure: BasePart,
	fill: Frame,
	ticks: Frame,
	hpText: TextLabel,
}
local bars: { Bar } = {}

local function localTeam(): string
	local team = player:GetAttribute("Team")
	return if type(team) == "string" then team else DEFAULT_TEAM
end

local function readHealth(structure: BasePart): (number, number)
	local health = structure:GetAttribute("Health")
	local maxHealth = structure:GetAttribute("MaxHealth")
	local max = if type(maxHealth) == "number" and maxHealth > 0 then maxHealth else 1
	local current = if type(health) == "number" then math.clamp(health, 0, max) else max
	return current, max
end

local function newText(name: string, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextSize = textSize
	label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	return label
end

local function redrawTicks(bar: Bar, max: number)
	bar.ticks:ClearAllChildren()
	local count = math.floor((max - 1) / HP_PER_TICK)
	for i = 1, count do
		local tick = Instance.new("Frame")
		tick.BorderSizePixel = 0
		tick.BackgroundColor3 = BAR_BACK_COLOR
		tick.BackgroundTransparency = 0.4
		tick.Size = UDim2.new(0, 1, 1, 0)
		tick.Position = UDim2.fromScale(i * HP_PER_TICK / max, 0)
		tick.Parent = bar.ticks
	end
end

local function refresh(bar: Bar)
	local current, max = readHealth(bar.structure)
	local isAlly = bar.structure:GetAttribute("Team") == localTeam()
	bar.fill.BackgroundColor3 = if isAlly then ALLY_COLOR else ENEMY_COLOR
	bar.fill.Size = UDim2.fromScale(current / max, 1)
	bar.hpText.Text = string.format("%d / %d", math.ceil(current), max)
	redrawTicks(bar, max)
end

local function createBar(structure: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = structure.Name .. "Bar"
	billboard.Adornee = structure
	billboard.Size = UDim2.fromOffset(BAR_WIDTH, NAME_HEIGHT + BAR_HEIGHT)
	billboard.StudsOffset = Vector3.new(0, structure.Size.Y / 2 + 3, 0)
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false

	local nameLabel = newText("Name", 14)
	nameLabel.Size = UDim2.new(1, 0, 0, NAME_HEIGHT)
	nameLabel.Text = structure.Name:gsub("(%l)(%u)", "%1 %2") -- "RedTower" -> "Red Tower"
	nameLabel.Parent = billboard

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.BorderSizePixel = 0
	back.BackgroundColor3 = BAR_BACK_COLOR
	back.Position = UDim2.fromOffset(0, NAME_HEIGHT)
	back.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
	back.Parent = billboard
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.new(0, 0, 0)
	outline.Thickness = 1
	outline.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Parent = back

	local ticks = Instance.new("Frame")
	ticks.Name = "Ticks"
	ticks.BackgroundTransparency = 1
	ticks.Size = UDim2.fromScale(1, 1)
	ticks.Parent = back

	local hpText = newText("Health", 11)
	hpText.Size = UDim2.fromScale(1, 1)
	hpText.Parent = back

	local bar: Bar = { billboard = billboard, structure = structure, fill = fill, ticks = ticks, hpText = hpText }
	table.insert(bars, bar)
	refresh(bar)
	structure:GetAttributeChangedSignal("Health"):Connect(function()
		refresh(bar)
	end)
	structure:GetAttributeChangedSignal("MaxHealth"):Connect(function()
		refresh(bar)
	end)
	billboard.Parent = playerGui
end

for _, item in arena:GetDescendants() do
	if item:IsA("BasePart") and STRUCTURE_KINDS[item:GetAttribute("Kind")] then
		createBar(item)
	end
end

-- Recolor every bar if this player's team changes (e.g. when a match assigns teams).
player:GetAttributeChangedSignal("Team"):Connect(function()
	for _, bar in bars do
		refresh(bar)
	end
end)

-- Show only the bars near this player's character. With no character (e.g. while
-- respawning) fall back to the camera position so bars don't all vanish.
local function viewerPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

while true do
	local origin = viewerPosition()
	if origin then
		for _, bar in bars do
			bar.billboard.Enabled = (bar.structure.Position - origin).Magnitude <= SHOW_DISTANCE
		end
	end
	task.wait(VISIBILITY_CHECK_SECONDS)
end
