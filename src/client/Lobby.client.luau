--!strict
-- The lobby's prompts and notice boards (T05, owner 2026-10-23), in the UI
-- design system (docs/11_UI_DESIGN.md). The courtyard and its four queue
-- daises are built by the server (Lobby.luau); each dais runs its own lobby
-- room (Match.luau, attributes on the dais). The courtyard only gathers
-- players (like Zombie Rush Survival / Survive The Swarm): it shows the
-- rooms, never the battle. This draws:
--   * each dais's prompt (custom style; Roblox still handles the key):
--     "E  Create lobby" while no room is open there (LobbyMenu.client then
--     shows the Create lobby panel), "E  Join battle" / "E  Lobby full"
--     while one is open or waiting. While the player is in a room every
--     prompt is switched off for them (locally): only Exit lobby leaves.
--   * each dais's notice board, the only countdown (owner 2026-10-23: not
--     twice, just the board): "Start a new game here" while no room is open;
--     otherwise the map's name, "2/4 players" and "Starting in 7" with the
--     number in red, or "Waiting for the battlefield".
-- Reads each dais's RoomState / RoomMap / RoomMaxPlayers / RoomSize /
-- CountdownEndsAt and the local player's InRoom (their room's pad number).
-- Also the smooth side of the dais leash (owner 2026-10-23): while in a
-- room the character's centre is kept LEASH_INSET inside its dais's edge,
-- each frame after physics. The server (Match.luau) still pulls back anyone
-- beyond the edge, so this only makes the edge feel like a wall.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GameContext = require(ReplicatedStorage.Shared.GameContext)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Font = UiTheme.Font
local Size = UiTheme.TextSize
local space = UiTheme.space

local PROMPT_WIDTH = 170
local PROMPT_HEIGHT = 46
local KEY = 26
local RED_HEX = UiTheme.Enemy:ToHex() -- countdown numbers (owner 2026-10-23)
local LEASH_INSET = 1 -- studs inside the dais edge (Match.luau uses the same)
local LEASH_REACH = 4 -- studs beyond the edge this still holds; farther is the server's

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local lobby = Workspace:WaitForChild("Lobby")

local function readNumber(target: Instance, name: string): number
	local value = target:GetAttribute(name)
	return if type(value) == "number" and value == value then value else 0
end

-- A dais's room: "Idle" | "Open" | "Waiting" (Match.luau).
local function roomState(dais: Instance): string
	local value = dais:GetAttribute("RoomState")
	return if type(value) == "string" then value else "Idle"
end

local function mapName(dais: Instance): string
	local id = dais:GetAttribute("RoomMap")
	for _, map in Config.Lobby.Maps do
		if map.Id == id then
			return map.Name
		end
	end
	return ""
end

-- Prompts -------------------------------------------------------------------------

type Shown = { billboard: BillboardGui, label: TextLabel, bar: UiTheme.Bar, holdStartedAt: number? }
local shown: { [ProximityPrompt]: Shown } = {}

local function promptText(prompt: ProximityPrompt): string
	local dais = prompt.Parent
	if prompt.Name ~= "QueuePrompt" or not dais then
		return prompt.ActionText
	end
	if roomState(dais) == "Idle" then
		return "Create lobby"
	end
	local full = readNumber(dais, "RoomSize") >= readNumber(dais, "RoomMaxPlayers")
	return if full then "Lobby full" else "Join battle"
end

local function wanted(prompt: ProximityPrompt): boolean
	return prompt.Name == "QueuePrompt"
end

local function hide(prompt: ProximityPrompt)
	local entry = shown[prompt]
	if entry then
		entry.billboard:Destroy()
		shown[prompt] = nil
	end
end

local function show(prompt: ProximityPrompt)
	local adornee = prompt.Parent
	if shown[prompt] or not (adornee and adornee:IsA("BasePart")) then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = prompt.Name
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(PROMPT_WIDTH * UiTheme.Scale, PROMPT_HEIGHT * UiTheme.Scale)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.ResetOnSpawn = false
	billboard.Parent = playerGui
	local panel = UiTheme.panel(billboard)
	panel.Size = UDim2.fromOffset(PROMPT_WIDTH, PROMPT_HEIGHT)
	local scale = Instance.new("UIScale") -- fixed: the billboard's pixel size is fixed too
	scale.Scale = UiTheme.Scale
	scale.Parent = panel
	local key = UiTheme.block(panel, "Gold", 6, UiTheme.OutlineThin)
	key.Position = UDim2.fromOffset(space(2), (PROMPT_HEIGHT - KEY) // 2)
	key.Size = UDim2.fromOffset(KEY, KEY)
	local keyText = UiTheme.text(key, Size.Value, Font.Heavy)
	keyText.Size = UDim2.fromScale(1, 1)
	keyText.TextXAlignment = Enum.TextXAlignment.Center
	keyText.Text = prompt.KeyboardKeyCode.Name
	local textX = space(2) + KEY + space(2)
	local label = UiTheme.text(panel, Size.Body, Font.Bold)
	label.Position = UDim2.fromOffset(textX, if prompt.HoldDuration > 0 then space(1) + 2 else (PROMPT_HEIGHT - 20) // 2)
	label.Size = UDim2.new(1, -(textX + space(2)), 0, Size.Body + 4)
	label.Text = promptText(prompt)
	local bar = UiTheme.bar(panel, UiTheme.Bar.Unit, UiTheme.Ally)
	bar.track.Position = UDim2.fromOffset(textX, PROMPT_HEIGHT - space(2) - UiTheme.Bar.Unit)
	bar.track.Size = UDim2.new(1, -(textX + space(2)), 0, UiTheme.Bar.Unit)
	bar.track.Visible = prompt.HoldDuration > 0
	bar.fill.Size = UDim2.fromScale(0, 1)
	shown[prompt] = { billboard = billboard, label = label, bar = bar, holdStartedAt = nil }
end

local function isLobbyPrompt(prompt: ProximityPrompt): boolean
	return prompt:IsDescendantOf(lobby)
end

ProximityPromptService.PromptShown:Connect(function(prompt)
	if isLobbyPrompt(prompt) and wanted(prompt) then
		show(prompt)
	end
end)
ProximityPromptService.PromptHidden:Connect(hide)
ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
	local entry = shown[prompt]
	if entry then
		entry.holdStartedAt = os.clock()
	end
end)
ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
	local entry = shown[prompt]
	if entry then
		entry.holdStartedAt = nil
		entry.bar.fill.Size = UDim2.fromScale(0, 1)
	end
end)

-- Notice boards (one per dais) -----------------------------------------------------

type Board = { dais: BasePart, title: TextLabel, players: TextLabel, wait: TextLabel }
local boards: { Board } = {}

for index in Config.Lobby.Pads do
	local dais = lobby:WaitForChild(`QueueDais{index}`) :: BasePart
	local boardPart = lobby:WaitForChild(`NoticeBoard{index}`) :: BasePart
	local surface = Instance.new("SurfaceGui")
	surface.Name = `NoticeBoard{index}`
	surface.Adornee = boardPart
	surface.Face = Enum.NormalId.Left -- the face toward the plaza (Lobby.BoardFace)
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.ResetOnSpawn = false
	surface.Parent = playerGui
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, space(3))
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = surface
	local function boardLine(order: number, size: number): TextLabel
		local label = UiTheme.text(surface, size, Font.Heavy)
		label.LayoutOrder = order
		label.Size = UDim2.new(1, -space(8), 0, size + 10)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.RichText = true
		return label
	end
	local title = boardLine(1, 48) -- "Start a new game here" fits the 14-stud board at this size
	title.TextColor3 = UiTheme.Gold
	table.insert(boards, { dais = dais, title = title, players = boardLine(2, 34), wait = boardLine(3, 40) })
end

local function refreshBoard(board: Board)
	local dais = board.dais
	local state = roomState(dais)
	local open = state ~= "Idle"
	board.title.Text = if open then mapName(dais) else "Start a new game here"
	board.players.Visible = open
	board.wait.Visible = open
	if not open then
		return
	end
	board.players.Text = `{math.floor(readNumber(dais, "RoomSize"))}/{math.floor(readNumber(dais, "RoomMaxPlayers"))} players`
	if state == "Waiting" then
		board.wait.Text = "Waiting for the battlefield"
	else
		local left = math.max(math.ceil(readNumber(dais, "CountdownEndsAt") - Workspace:GetServerTimeNow()), 0)
		board.wait.Text = `Starting in <font color="#{RED_HEX}">{left}</font>`
	end
end

-- In a room: no dais prompts (they would only join another room).
local function refreshPromptsEnabled()
	local free = player:GetAttribute("InRoom") == nil
	for _, item in lobby:GetDescendants() do
		if item:IsA("ProximityPrompt") and item.Name == "QueuePrompt" then
			item.Enabled = free
		end
	end
end
player:GetAttributeChangedSignal("InRoom"):Connect(refreshPromptsEnabled)
refreshPromptsEnabled()

-- The leash: keeps the character inside its room's dais. Runs after physics
-- so the edge holds before the frame is drawn; outward speed is dropped so
-- the character does not keep pushing through.
RunService.PostSimulation:Connect(function()
	local pad = readNumber(player, "InRoom")
	local dais = if pad > 0 then lobby:FindFirstChild(`QueueDais{pad}`) else nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (dais and dais:IsA("BasePart") and root and root:IsA("BasePart")) then
		return
	end
	local centre = dais.Position
	local offset = Vector3.new(root.Position.X - centre.X, 0, root.Position.Z - centre.Z)
	local limit = Config.Lobby.QueueRadius - LEASH_INSET
	local distance = offset.Magnitude
	if distance <= limit or distance > Config.Lobby.QueueRadius + LEASH_REACH then
		return
	end
	local outward = offset.Unit
	local held = Vector3.new(centre.X, root.Position.Y, centre.Z) + outward * limit
	root.CFrame = root.CFrame.Rotation + held
	local velocity = root.AssemblyLinearVelocity
	local away = velocity:Dot(outward)
	if away > 0 then
		root.AssemblyLinearVelocity = velocity - outward * away
	end
end)

GameContext.renderStepped("Lobby", function()
	for _, board in boards do
		refreshBoard(board)
	end
	for prompt, entry in shown do
		if not prompt.Parent or not wanted(prompt) then
			hide(prompt)
		else
			entry.label.Text = promptText(prompt)
			if entry.holdStartedAt then
				local share = (os.clock() - entry.holdStartedAt) / math.max(prompt.HoldDuration, 0.01)
				entry.bar.fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
			end
		end
	end
end)
