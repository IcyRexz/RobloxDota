--!strict
-- Name and health bar above every tower, barracks and core, in the game's UI
-- design system (docs/11_UI_DESIGN.md): the name in floating white text above
-- an 18 px bar, green for your side, red for the enemy, with "current / max"
-- inside it (owner 2026-10-21: the numbers of the MOBA-era bars, a bit
-- bigger than them; no segment ticks). Runs on each player's own screen because "ally"
-- and "enemy" depend on who is looking. Shown within Config.Display.HealthBarRange.
-- The bars only display health; the server owns the real numbers (the
-- structure's Health / MaxHealth attributes) and the bars follow them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local BAR_WIDTH = 200 -- on-screen pixels, so it stays readable at any distance
local NAME_HEIGHT = 24
local VISIBILITY_CHECK_SECONDS = 0.2
-- Players are always on our side; used until the server sets the attribute.
local DEFAULT_TEAM = Config.Teams.Defenders

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local arena = Workspace:WaitForChild("Arena")

type Bar = { billboard: BillboardGui, structure: BasePart, fill: Frame, healthText: TextLabel }
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

local function refresh(bar: Bar)
	local current, max = readHealth(bar.structure)
	local isAlly = bar.structure:GetAttribute("Team") == localTeam()
	bar.fill.BackgroundColor3 = if isAlly then UiTheme.Ally else UiTheme.Enemy
	bar.fill.Size = UDim2.fromScale(current / max, 1)
	bar.healthText.Text = `{math.ceil(current)} / {math.round(max)}`
end

local function createBar(structure: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = structure.Name .. "Bar"
	billboard.Adornee = structure
	billboard.Size = UDim2.fromOffset(BAR_WIDTH, NAME_HEIGHT + 4 + UiTheme.Bar.Structure)
	billboard.StudsOffset = Vector3.new(0, structure.Size.Y / 2 + 3, 0)
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false

	local nameLabel = UiTheme.text(billboard, UiTheme.TextSize.Title, UiTheme.Font.Bold)
	nameLabel.Size = UDim2.new(1, 0, 0, NAME_HEIGHT)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	-- Name with the building's icon (Icon attribute: barracks and Base Core).
	-- DisplayName overrides the part name (owner 2026-10-21: both barracks
	-- read "Barracks").
	local displayName = structure:GetAttribute("DisplayName")
	local baseName = if type(displayName) == "string"
		then displayName
		else structure.Name:gsub("(%l)(%u)", "%1 %2") -- "LeftTower" -> "Left Tower"
	local icon = structure:GetAttribute("Icon")
	nameLabel.Text = if type(icon) == "string" then `{icon}  {baseName}` else baseName
	UiTheme.floatingText(nameLabel)

	local parts = UiTheme.bar(billboard, UiTheme.Bar.Structure, UiTheme.Ally)
	parts.track.Position = UDim2.fromOffset(0, NAME_HEIGHT + 4)
	local healthText = UiTheme.text(parts.track, UiTheme.TextSize.Body, UiTheme.Font.Bold)
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.TextXAlignment = Enum.TextXAlignment.Center
	healthText.ZIndex = 2 -- above the fill
	UiTheme.floatingText(healthText)

	local bar: Bar = { billboard = billboard, structure = structure, fill = parts.fill, healthText = healthText }
	table.insert(bars, bar)
	refresh(bar)
	structure:GetAttributeChangedSignal("Health"):Connect(function()
		refresh(bar)
	end)
	structure:GetAttributeChangedSignal("MaxHealth"):Connect(function()
		refresh(bar)
	end)
	billboard.Parent = playerGui

	-- The server removes a structure when it is destroyed; drop its bar too.
	structure.AncestryChanged:Connect(function()
		if not structure:IsDescendantOf(game) then
			billboard:Destroy()
			local index = table.find(bars, bar)
			if index then
				table.remove(bars, index)
			end
		end
	end)
end

for _, item in arena:GetDescendants() do
	if item:IsA("BasePart") and Targeting.StructureKinds[item:GetAttribute("Kind")] then
		createBar(item)
	end
end
-- Structures added later: zombie nests, and fallen structures put back by the
-- battlefield reset (T15; they arrive as new parts).
arena.DescendantAdded:Connect(function(item: Instance)
	if item:IsA("BasePart") and Targeting.StructureKinds[item:GetAttribute("Kind")] then
		createBar(item)
	end
end)

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
			-- Bars farther than HealthBarRange from your hero (flat distance) are hidden.
			local offset = bar.structure.Position - origin
			bar.billboard.Enabled = Vector3.new(offset.X, 0, offset.Z).Magnitude <= Config.Display.HealthBarRange
		end
	end
	task.wait(VISIBILITY_CHECK_SECONDS)
end
