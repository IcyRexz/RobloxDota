--!strict
-- End screen (T10, owner 2026-10-23: a score screen), in the UI design system
-- (docs/11_UI_DESIGN.md): when the match is decided the game dims and a navy
-- block in the middle shows
--   VICTORY (gold) / DEFEAT (red)
--   The Zombie Core has fallen / Our Base Core has fallen
--   Time elapsed 14:32  ·  Gold earned 1240   (Gold is shared, so one team total)
--   PLAYER            LV   KILLS   MASTERIES
--   Zac  Mage         19     57    [CB][QR][  ]...      (your row lit)
--   ...one row per player
--          +50 Zombie Cores      (your reward, under the table; owner 2026-10-23)
--          [ Return to lobby ]   (gold button)
--          Back to the lobby in 17      (everyone returns when the results end, T15)
-- The mouse is freed while it shows (owner 2026-10-23; the scrim is a Modal
-- button, as in the menus). Shown to party members only (InParty). The
-- button asks the server to send you back to the lobby now (ReturnToLobby,
-- Match.luau); otherwise everyone goes back when the results run out
-- (Config.Lobby.ResultsSeconds, Workspace ReturnAt). The screen closes once
-- you have left the battle. Rows are the players in the battle; they
-- refresh while players leave. Reads Workspace MatchResult / MatchEndedAt /
-- MatchStartedAt / ReturnAt / GoldEarned (Gold.luau) and each player's
-- Level, Kills, Mastery<id> and ZombieCoresEarned (the meta-progression
-- reward, Match.luau) attributes.
-- Display only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GameContext = require(ReplicatedStorage.Shared.GameContext)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Font = UiTheme.Font
local Size = UiTheme.TextSize
local Strength = UiTheme.Strength
local space = UiTheme.space

local WIDTH = 620
local ROW_HEIGHT = 36
local INSET = space(3)
local CHIP = 20
local CHIP_GAP = 4
local MASTERY_WIDTH = #Config.Hero.MasteryLevels * (CHIP + CHIP_GAP) - CHIP_GAP
-- Columns after the player's name: caption and width; numbers right-aligned,
-- or the mastery chips (one per mastery level, initials once picked).
type Column = { caption: string, width: number, attribute: string?, color: Color3? }
local COLUMNS: { Column } = {
	{ caption = "LV", width = 44, attribute = "Level", color = UiTheme.Gold },
	{ caption = "KILLS", width = 64, attribute = "Kills" },
	{ caption = "MASTERIES", width = MASTERY_WIDTH },
}
local COLUMN_GAP = space(4)

local player = Players.LocalPlayer

local screen = Instance.new("ScreenGui")
screen.Name = "MatchEnd"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 20
screen.Enabled = false
screen.Parent = player:WaitForChild("PlayerGui")

-- A Modal button: while it shows, the first-person mouse lock is released.
local scrim = Instance.new("TextButton")
scrim.Modal = true
scrim.AutoButtonColor = false
scrim.Text = ""
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = UiTheme.Scrim
scrim.BackgroundTransparency = 1
scrim.BorderSizePixel = 0
scrim.Parent = screen

local panel = UiTheme.block(screen, "Navy", UiTheme.RadiusLarge)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.45)
panel.Size = UDim2.fromOffset(WIDTH, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
UiTheme.applyScale(panel)
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, space(5))
pad.PaddingBottom = UDim.new(0, space(4))
pad.PaddingLeft = UDim.new(0, space(5))
pad.PaddingRight = UDim.new(0, space(5))
pad.Parent = panel
local list = Instance.new("UIListLayout")
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Padding = UDim.new(0, space(2))
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = panel

local function line(order: number, size: number, weight: Font, strength: number?): TextLabel
	local label = UiTheme.text(panel, size, weight, strength)
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, size + 8)
	label.TextXAlignment = Enum.TextXAlignment.Center
	return label
end

local title = line(1, Size.Display + 10, Font.Heavy)
local reason = line(2, Size.Title, Font.Bold, Strength.Label)
local elapsed = line(3, Size.Value, Font.Heavy)
elapsed.TextColor3 = UiTheme.Gold

-- A row frame: the player column, then the number columns from the right.
local function rowCells(parent: Frame, size: number, weight: Font, strength: number?): (TextLabel, { TextLabel })
	local cells: { TextLabel } = {}
	local x = WIDTH - space(10) - INSET
	for index = #COLUMNS, 1, -1 do
		local column = COLUMNS[index]
		x -= column.width
		local cell = UiTheme.text(parent, size, weight, strength)
		cell.Position = UDim2.fromOffset(x, 0)
		cell.Size = UDim2.new(0, column.width, 1, 0)
		cell.TextXAlignment = Enum.TextXAlignment.Right
		cells[index] = cell
		x -= COLUMN_GAP
	end
	local name = UiTheme.text(parent, size, weight, strength)
	name.Position = UDim2.fromOffset(INSET, 0)
	name.Size = UDim2.new(0, x - INSET, 1, 0)
	return name, cells
end

local header = Instance.new("Frame")
header.LayoutOrder = 4
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 18)
header.Parent = panel
local headerName, headerCells = rowCells(header, Size.Caption, Font.Bold, Strength.Faint)
headerName.Text = "PLAYER"
for index, column in COLUMNS do
	headerCells[index].Text = column.caption
	if not column.attribute then
		headerCells[index].TextXAlignment = Enum.TextXAlignment.Left -- over the chips
	end
end

local rows = Instance.new("Frame")
rows.LayoutOrder = 5
rows.BackgroundTransparency = 1
rows.Size = UDim2.fromScale(1, 0)
rows.AutomaticSize = Enum.AutomaticSize.Y
rows.Parent = panel
local rowList = Instance.new("UIListLayout")
rowList.Padding = UDim.new(0, space(1))
rowList.SortOrder = Enum.SortOrder.LayoutOrder
rowList.Parent = rows

-- Your reward, out of the table (owner 2026-10-23): "+50 Zombie Cores".
local reward = line(6, Size.Title + 4, Font.Heavy)
reward.TextColor3 = UiTheme.Enemy -- Zombie Cores stay red, as their table column was

local lobbyButton = Instance.new("TextButton")
lobbyButton.Name = "ReturnToLobby"
lobbyButton.LayoutOrder = 7
lobbyButton.AutoButtonColor = false
lobbyButton.Text = ""
lobbyButton.Size = UDim2.fromOffset(220, 48)
lobbyButton.BackgroundTransparency = 0
lobbyButton.Parent = panel
UiTheme.styleBlock(lobbyButton, "Gold", UiTheme.Radius)
UiTheme.pressable(lobbyButton)
local lobbyLabel = UiTheme.text(lobbyButton, Size.Value, Font.Heavy)
lobbyLabel.Size = UDim2.fromScale(1, 1)
lobbyLabel.TextXAlignment = Enum.TextXAlignment.Center
lobbyLabel.Text = "Return to lobby"
UiTheme.inkText(lobbyLabel)

local backIn = line(8, Size.Small, Font.Medium, Strength.Label)

local returnEvent = ReplicatedStorage:WaitForChild("ReturnToLobby") :: RemoteEvent
lobbyButton.Activated:Connect(function()
	returnEvent:FireServer()
end)

local function readNumber(target: Instance, name: string): number
	local value = target:GetAttribute(name)
	return if type(value) == "number" and value == value then value else 0
end

-- "Chain Bolt" -> "CB" (as on the Tab scoreboard).
local function initials(name: string): string
	local letters = ""
	for word in name:gmatch("%a+") do
		letters ..= word:sub(1, 1)
	end
	return string.upper(if #letters >= 2 then letters:sub(1, 2) else name:sub(1, 2))
end

-- One chip per mastery level inside `cell`: the picked masteries' initials in
-- gold with a gold line, then faint empty slots.
local function masteryChips(cell: TextLabel, owner: Player)
	cell.Text = ""
	local taken: { string } = {}
	for _, info in Config.Hero.Masteries do
		if owner:GetAttribute("Mastery" .. info.id) == true then
			table.insert(taken, initials(info.name))
		end
	end
	for index = 1, #Config.Hero.MasteryLevels do
		local chip = UiTheme.text(cell, Size.Caption - 1, Font.Heavy)
		chip.Position = UDim2.fromOffset((index - 1) * (CHIP + CHIP_GAP), (ROW_HEIGHT - CHIP) // 2)
		chip.Size = UDim2.fromOffset(CHIP, CHIP)
		chip.TextXAlignment = Enum.TextXAlignment.Center
		chip.TextColor3 = UiTheme.Gold
		chip.Text = taken[index] or ""
		chip.BackgroundColor3 = UiTheme.Raised
		chip.BackgroundTransparency = if taken[index] then UiTheme.RaisedHoverTransparency else UiTheme.DisabledTransparency
		chip.BorderSizePixel = 0
		UiTheme.corner(chip, 6)
		local chipLine = Instance.new("UIStroke")
		chipLine.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		chipLine.Thickness = 1
		chipLine.Color = if taken[index] then UiTheme.Gold else UiTheme.Text
		chipLine.Transparency = if taken[index] then 0.3 else 0.82
		chipLine.Parent = chip
	end
end

local function clock(seconds: number): string
	local whole = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function buildRows()
	for _, child in rows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for _, owner in Players:GetPlayers() do
		if owner:GetAttribute("InParty") ~= true then
			continue -- not in this battle (waiting in the lobby, or already back)
		end
		local row = Instance.new("Frame")
		row.LayoutOrder = if owner == player then 0 else 1
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.BackgroundColor3 = UiTheme.Raised
		row.BackgroundTransparency = if owner == player then UiTheme.RaisedHoverTransparency else 1
		row.BorderSizePixel = 0
		row.Parent = rows
		UiTheme.corner(row)
		local name, cells = rowCells(row, Size.Value, Font.Heavy)
		local character = owner.Character
		local heroName = if character then character:GetAttribute("HeroName") else nil
		name.Text = `{owner.DisplayName}  {if type(heroName) == "string" then heroName else Config.Hero.Name}`
		for index, column in COLUMNS do
			local attribute = column.attribute
			if not attribute then
				masteryChips(cells[index], owner)
				continue
			end
			local value = math.floor(readNumber(owner, attribute))
			if attribute == "Level" then
				value = math.max(value, 1)
			end
			cells[index].Text = tostring(value)
			if column.color then
				cells[index].TextColor3 = column.color
			end
		end
	end
end

local function show()
	local result = Workspace:GetAttribute("MatchResult")
	if (result ~= "Won" and result ~= "Lost") or player:GetAttribute("InParty") ~= true or not GameContext.is("Battle") then
		return
	end
	local won = result == "Won"
	title.Text = if won then "VICTORY" else "DEFEAT"
	title.TextColor3 = if won then UiTheme.Gold else UiTheme.Enemy
	reason.Text = if won then "The Zombie Core has fallen" else "Our Base Core has fallen"
	local time = clock(readNumber(Workspace, "MatchEndedAt") - readNumber(Workspace, "MatchStartedAt"))
	elapsed.Text = `Time elapsed {time}   ·   Gold earned {math.floor(readNumber(Workspace, "GoldEarned"))}`
	buildRows()
	reward.Text = `+{math.floor(readNumber(player, "ZombieCoresEarned"))} Zombie Cores`
	if not screen.Enabled then
		screen.Enabled = true
		UserInputService.MouseIconEnabled = true
		TweenService:Create(scrim, TweenInfo.new(0.5), { BackgroundTransparency = UiTheme.ScrimTransparency }):Play()
		-- The countdown to going back, only while the screen shows.
		task.spawn(function()
			while screen.Enabled do
				local left = math.max(math.ceil(readNumber(Workspace, "ReturnAt") - Workspace:GetServerTimeNow()), 0)
				backIn.Text = `Back to the lobby in {left}`
				task.wait(0.25)
			end
		end)
	end
end

Workspace:GetAttributeChangedSignal("MatchResult"):Connect(show)
Players.PlayerRemoving:Connect(function()
	task.defer(function()
		if screen.Enabled then
			buildRows()
		end
	end)
end)
show()

-- Back in the lobby (left the party): close the screen and lock the mouse again.
player:GetAttributeChangedSignal("InParty"):Connect(function()
	if player:GetAttribute("InParty") ~= true and screen.Enabled then
		screen.Enabled = false
		scrim.BackgroundTransparency = 1
		UserInputService.MouseIconEnabled = false
	end
end)
