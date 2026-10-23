--!strict
-- The match: the lobby rooms, the battle, its result and the reset (T05,
-- T10, T15; owner 2026-10-23, following games like Zombie Rush Survival and
-- Survive The Swarm: the lobby only gathers players; each group goes off to
-- its battle and its pad is free again at once).
--
-- Lobby rooms: one per queue dais (Lobby.Pads, four in a row; owner
-- 2026-10-23). Each room's state is on its dais part (attribute RoomState):
--   Idle     nothing is open there. E on that dais (or Play in the lobby
--            menu, which takes the first idle pad) shows the Create lobby
--            panel (LobbyMenu.client): the map (Config.Lobby.Maps) and 1 to
--            MaxBattlePlayers players.
--   Open     its creator is in it and the countdown (Config.Lobby.
--            CountdownSeconds) runs. Others press E on that dais to join.
--            A full room still waits out the countdown.
--   Waiting  the countdown ended while the battlefield was busy (or other
--            rooms were already waiting): rooms go in the order they started
--            waiting, one battle at a time (one battlefield per server until
--            the two-place split).
--   A player is in at most one room. Joining or creating one stands them on
--   its dais, and they stay inside its circle until they click Exit lobby
--   (owner 2026-10-23; LobbyMenu.client, "Leave" below): Lobby.client keeps
--   them in smoothly and the server pulls back anyone who still gets out.
--   A room everyone leaves closes. When the group goes into the battle the room
--   closes too, so a new one can open on that pad straight away.
--
-- The battle (Workspace attribute MatchPhase):
--   Idle       the battlefield is free and clean.
--   Starting   a group has just arrived: the loading screen shows
--              (GameContext "Loading") for Config.Lobby.LoadingSeconds while
--              they stand on our base's spawn pad.
--   Fighting   the battle runs (spawning, events and the clock start now:
--              Started fires). Nobody else can join it.
--   Ended      a core fell: the result is decided once (Lost when our Base
--              Core falls, Won when the Zombie Core falls), rewards are given
--              and everything freezes (CombatService refuses all damage, units
--              stand still, heroes cannot act). After Config.Lobby.
--              ResultsSeconds (or the end screen's button) each player goes
--              back to the lobby behind a short loading screen.
--   Resetting  everyone has left the battle: every system registered with
--              Match.onReset puts the battlefield back as it was (structures,
--              units, nests, events, Gold, levels, upgrades), then Idle. The
--              first waiting room goes in at once.
-- A battle everyone leaves (left the game) is reset the same way.
-- Every battle has an epoch (MatchEpoch, bumped at the start and at the reset)
-- so delayed callbacks can check theirs.
--
-- Attributes on each dais (server-written): RoomState, RoomMap (a map Id),
--   RoomMaxPlayers, RoomSize, CountdownEndsAt (server time, while Open).
-- Workspace attributes: MatchPhase, MatchEpoch, BattleMap (the map Id the
--   battle was opened with), PartySize (players in the battle),
--   MatchStartedAt / MatchEndedAt / ReturnAt (server time), MatchResult
--   "Won" | "Lost".
-- Player attributes: InRoom (the pad number of their room), InParty (in the
--   battle), GameContext ("Lobby" | "Loading" | "Battle", read by
--   src/shared/GameContext.luau), ZombieCoresEarned (the reward at the end,
--   Config.Rewards; added to the saved stats by PlayerData.server).
-- Remotes:
--   LobbyRequest (client -> server): ("Create", pad: whole number or nil,
--     mapId: string, maxPlayers: whole number) from the Create lobby panel;
--     nil pad = the first idle one. ("Leave") from the Exit lobby button.
--     Rate limited. Joining uses the daises' prompts.
--   LobbyNotice (server -> client, text): why a request was refused, shown as
--     a short message in the lobby (LobbyMenu.client).
--   ReturnToLobby (client -> server, no arguments): the end screen's button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatService = require(script.Parent.CombatService)
local Config = require(ReplicatedStorage.Shared.Config)
local Lobby = require(script.Parent.Lobby)

local LobbyConfig = Config.Lobby

export type Phase = "Idle" | "Starting" | "Fighting" | "Ended" | "Resetting"
type RoomState = "Idle" | "Open" | "Waiting"
type Room = {
	pad: number,
	dais: BasePart,
	state: RoomState,
	members: { [Player]: true },
	token: number, -- bumps whenever the room closes or restarts its countdown
	waitingSince: number, -- order among waiting rooms
}

local Match = {}

local startedEvent = Instance.new("BindableEvent")
-- Fires (epoch) when a battle starts fighting.
Match.Started = startedEvent.Event
local endedEvent = Instance.new("BindableEvent")
-- Fires (result: "Won" | "Lost", players: { Player }) once per battle, when it
-- ends, with the players who were in it.
Match.Ended = endedEvent.Event

local returnEvent = Instance.new("RemoteEvent")
returnEvent.Name = "ReturnToLobby"
returnEvent.Parent = ReplicatedStorage
local requestEvent = Instance.new("RemoteEvent")
requestEvent.Name = "LobbyRequest"
requestEvent.Parent = ReplicatedStorage
local noticeEvent = Instance.new("RemoteEvent")
noticeEvent.Name = "LobbyNotice"
noticeEvent.Parent = ReplicatedStorage

local phase: Phase = "Idle"
local epoch = 0
local party: { [Player]: true } = {} -- in the battle
local returning: { [Player]: true } = {} -- on the loading screen back to the lobby
local rooms: { Room } = {}
-- Studs a character's centre keeps inside its dais's edge (Lobby.client
-- uses the same); the server pulls back anyone LEASH_SLACK beyond the edge.
local LEASH_INSET = 1
local LEASH_SLACK = 2
local LEASH_CHECK_SECONDS = 0.25
local roomOf: { [Player]: Room } = {}
local waitCounter = 0

type ResetHandler = { order: number, name: string, run: () -> () }
local resetHandlers: { ResetHandler } = {}

local function count(set: { [Player]: true }): number
	local total = 0
	for _ in set do
		total += 1
	end
	return total
end

local function membersOf(set: { [Player]: true }): { Player }
	local list: { Player } = {}
	for player in set do
		table.insert(list, player)
	end
	return list
end

-- Where a player is, for the clients (GameContext.luau shows or hides UI and
-- picks the camera by it).
local function refreshContext(player: Player)
	local context = if returning[player]
		then "Loading"
		elseif party[player] and phase == "Starting" then "Loading"
		elseif party[player] and (phase == "Fighting" or phase == "Ended") then "Battle"
		else "Lobby"
	if player:GetAttribute("GameContext") ~= context then
		player:SetAttribute("GameContext", context)
	end
end

local function setPhase(new: Phase)
	phase = new
	Workspace:SetAttribute("MatchPhase", new)
	for _, player in Players:GetPlayers() do
		refreshContext(player)
	end
end
setPhase("Idle")
Workspace:SetAttribute("MatchEpoch", epoch)
Workspace:SetAttribute("PartySize", 0)

function Match.phase(): Phase
	return phase
end

function Match.epoch(): number
	return epoch
end

function Match.isFighting(): boolean
	return phase == "Fighting"
end

function Match.isOver(): boolean
	return phase == "Ended"
end

function Match.inParty(player: Player): boolean
	return party[player] == true
end

-- In the battle (arriving, fighting or frozen at the end), as opposed to the lobby.
function Match.inBattle(player: Player): boolean
	return party[player] == true and (phase == "Starting" or phase == "Fighting" or phase == "Ended")
end

-- Everyone in the battle.
function Match.partyMembers(): { Player }
	return membersOf(party)
end

-- Registers a step of the battlefield reset (T15). Steps run in `order`
-- (lower first): structures come back before upgrades re-apply to them, then
-- units and the flow fields. An error in one step is reported and the others
-- still run.
function Match.onReset(order: number, name: string, run: () -> ())
	table.insert(resetHandlers, { order = order, name = name, run = run })
	table.sort(resetHandlers, function(a, b)
		return a.order < b.order
	end)
end

-- Holds a hero still once the match is over (also for heroes that respawn after).
function Match.freezeHero(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end
end

local function notify(player: Player, text: string)
	if player.Parent then
		noticeEvent:FireClient(player, text)
	end
end

local function setInParty(player: Player, inParty: boolean)
	if inParty then
		party[player] = true
	else
		party[player] = nil
	end
	player:SetAttribute("InParty", inParty)
	Workspace:SetAttribute("PartySize", count(party))
	refreshContext(player)
end

-- Lobby rooms ----------------------------------------------------------------------

for _, pad in Lobby.Pads do
	local room: Room = { pad = pad.index, dais = pad.dais, state = "Idle", members = {}, token = 0, waitingSince = 0 }
	rooms[pad.index] = room
	pad.dais:SetAttribute("RoomState", "Idle")
	pad.dais:SetAttribute("RoomSize", 0)
end

local function setRoomState(room: Room, state: RoomState)
	room.state = state
	room.dais:SetAttribute("RoomState", state)
end

-- Stands a player's character on a dais: where they are if already inside
-- its circle, otherwise at the nearest point well inside it, feet on the
-- stone found by a ray (Lobby.groundAt).
local function standOnDais(player: Player, dais: BasePart)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and root and root:IsA("BasePart")) or humanoid.Health <= 0 then
		return
	end
	local centre = dais.Position
	local offset = Vector3.new(root.Position.X - centre.X, 0, root.Position.Z - centre.Z)
	local inner = LobbyConfig.QueueRadius - LEASH_INSET * 2
	if offset.Magnitude <= LobbyConfig.QueueRadius - LEASH_INSET then
		return
	end
	local spot = centre + (if offset.Magnitude > 0.01 then offset.Unit * inner else Vector3.zero)
	local ground = Lobby.groundAt(spot.X, spot.Z)
	local position = Vector3.new(spot.X, ground + humanoid.HipHeight + root.Size.Y / 2, spot.Z)
	character:PivotTo(CFrame.lookAt(position, Vector3.new(centre.X, position.Y, centre.Z)))
	root.AssemblyLinearVelocity = Vector3.zero
end

-- Puts a player into a room (leaving any other), or out of rooms with nil.
local function setRoom(player: Player, room: Room?)
	local old = roomOf[player]
	if old then
		old.members[player] = nil
		old.dais:SetAttribute("RoomSize", count(old.members))
	end
	if room then
		room.members[player] = true
		room.dais:SetAttribute("RoomSize", count(room.members))
		roomOf[player] = room
		player:SetAttribute("InRoom", room.pad)
		standOnDais(player, room.dais)
	else
		roomOf[player] = nil
		player:SetAttribute("InRoom", nil)
	end
end

-- Closes a room: everyone in it is out, its pad is free again.
local function closeRoom(room: Room)
	room.token += 1
	for _, player in membersOf(room.members) do
		setRoom(player, nil)
	end
	room.dais:SetAttribute("CountdownEndsAt", nil)
	room.dais:SetAttribute("RoomMap", nil)
	room.dais:SetAttribute("RoomMaxPlayers", nil)
	setRoomState(room, "Idle")
end

-- A room with nobody left in it closes.
local function closeIfEmpty(room: Room)
	if room.state ~= "Idle" and next(room.members) == nil then
		closeRoom(room)
		print(`[Match] lobby on pad {room.pad} closed: nobody left in it`)
	end
end

local function roomMaxPlayers(room: Room): number
	local value = room.dais:GetAttribute("RoomMaxPlayers")
	return if type(value) == "number" then value else LobbyConfig.MaxBattlePlayers
end

-- The room that has waited longest for the battlefield, if any.
local function firstWaiting(): Room?
	local best: Room? = nil
	for _, room in rooms do
		if room.state == "Waiting" and (best == nil or room.waitingSince < best.waitingSince) then
			best = room
		end
	end
	return best
end

-- The battle -----------------------------------------------------------------------

local launch: (room: Room) -> () -- defined below (reset and launch call each other)

-- Puts the battlefield back as it was, once nobody is in the battle.
local function resetBattle()
	if phase == "Idle" or phase == "Resetting" then
		return
	end
	setPhase("Resetting")
	epoch += 1 -- anything delayed from the old battle sees a new epoch
	Workspace:SetAttribute("MatchEpoch", epoch)
	for _, player in membersOf(party) do
		setInParty(player, false)
	end
	Workspace:SetAttribute("MatchResult", nil)
	Workspace:SetAttribute("MatchStartedAt", nil)
	Workspace:SetAttribute("MatchEndedAt", nil)
	Workspace:SetAttribute("ReturnAt", nil)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("ZombieCoresEarned", nil)
	end
	for _, handler in resetHandlers do
		local ok, problem = pcall(function(): string?
			handler.run()
			return nil
		end)
		if not ok then
			warn(`[Match] reset step {handler.name} failed: {problem}`)
		end
	end
	setPhase("Idle")
	print("[Match] battlefield reset")
	-- The longest-waiting room goes in (one that emptied meanwhile is closed
	-- by launch and the next one tried).
	while Match.phase() == "Idle" do
		local waiting = firstWaiting()
		if not waiting then
			break
		end
		launch(waiting)
	end
end

-- A battle nobody is in any more (everyone returned or left) is reset.
local function resetIfEmpty()
	if count(party) == 0 and (phase == "Starting" or phase == "Fighting" or phase == "Ended") then
		resetBattle()
	end
end

-- Sends a room's group into the battle: the room closes (its pad is free
-- again), they stand on our base's spawn pad behind the loading screen, and
-- the fight starts after LoadingSeconds.
function launch(room: Room)
	local members = membersOf(room.members)
	local mapId = room.dais:GetAttribute("RoomMap")
	closeRoom(room)
	if #members == 0 or phase ~= "Idle" then
		return
	end
	epoch += 1
	local myEpoch = epoch
	Workspace:SetAttribute("MatchEpoch", epoch)
	Workspace:SetAttribute("BattleMap", mapId) -- for the loading screen (one battlefield so far)
	setPhase("Starting")
	-- A fresh character each (PlayerTeams.server stands it on the base pad),
	-- so it starts with this battle's level-1 stats.
	for _, member in members do
		setInParty(member, true)
		task.spawn(function()
			local ok = pcall(function()
				member:LoadCharacterAsync()
			end)
			if not ok then
				warn(`[Match] could not load {member.Name} at the base`)
			end
		end)
	end
	print(`[Match] battle {epoch}: {#members} player(s) arriving from pad {room.pad}`)
	task.delay(LobbyConfig.LoadingSeconds, function()
		if epoch ~= myEpoch or Match.phase() ~= "Starting" then
			return
		end
		if count(party) == 0 then
			resetBattle()
			return
		end
		Workspace:SetAttribute("MatchStartedAt", Workspace:GetServerTimeNow())
		setPhase("Fighting")
		print(`[Match] battle {epoch} started with {count(party)} player(s)`)
		startedEvent:Fire(epoch)
	end)
end

-- Back to the lobby behind a short loading screen (a fresh character there).
local function returnToLobby(player: Player)
	if not party[player] then
		return
	end
	returning[player] = true
	setInParty(player, false)
	task.spawn(function()
		local ok = pcall(function()
			player:LoadCharacterAsync()
		end)
		if not ok then
			warn(`[Match] could not load {player.Name} in the lobby`)
		end
		task.wait(LobbyConfig.ReturnLoadingSeconds)
		returning[player] = nil
		if player.Parent then
			refreshContext(player)
		end
	end)
	resetIfEmpty()
end

local function finish(result: "Won" | "Lost")
	if phase ~= "Fighting" then
		return -- decided once, and only in a fight
	end
	local myEpoch = epoch
	-- Rewards and freezing first, so the end screen (shown on MatchResult)
	-- already has them.
	local members = membersOf(party)
	for _, member in members do
		member:SetAttribute("ZombieCoresEarned", Config.Rewards.ZombieCores)
		if member.Character then
			Match.freezeHero(member.Character)
		end
	end
	local now = Workspace:GetServerTimeNow()
	Workspace:SetAttribute("MatchEndedAt", now)
	Workspace:SetAttribute("ReturnAt", now + LobbyConfig.ResultsSeconds)
	Workspace:SetAttribute("MatchResult", result)
	setPhase("Ended")
	print(`[Match] {result}`)
	endedEvent:Fire(result, members)
	-- After the results everyone still here goes back to the lobby.
	task.delay(LobbyConfig.ResultsSeconds, function()
		if epoch == myEpoch and Match.phase() == "Ended" then
			for _, member in membersOf(party) do
				returnToLobby(member)
			end
		end
	end)
end

CombatService.Died:Connect(function(target: Instance)
	if target:GetAttribute("Kind") ~= "Core" then
		return
	end
	local team = target:GetAttribute("Team")
	if team == Config.Teams.Defenders then
		finish("Lost")
	elseif team == Config.Teams.Zombies then
		finish("Won")
	end
end)

-- Opening, joining and leaving rooms -------------------------------------------------

local function startCountdown(room: Room)
	room.token += 1
	local token = room.token
	setRoomState(room, "Open")
	room.dais:SetAttribute("CountdownEndsAt", Workspace:GetServerTimeNow() + LobbyConfig.CountdownSeconds)
	task.delay(LobbyConfig.CountdownSeconds, function()
		if room.token ~= token or room.state ~= "Open" then
			return -- closed (or restarted) meanwhile
		end
		room.dais:SetAttribute("CountdownEndsAt", nil)
		if next(room.members) == nil then
			closeRoom(room)
		elseif phase == "Idle" and firstWaiting() == nil then
			launch(room)
		else
			waitCounter += 1
			room.waitingSince = waitCounter
			setRoomState(room, "Waiting") -- goes when its turn comes (resetBattle)
			print(`[Match] lobby on pad {room.pad} waiting for the battlefield`)
		end
	end)
end

local function isMapId(mapId: string): boolean
	for _, map in LobbyConfig.Maps do
		if map.Id == mapId then
			return true
		end
	end
	return false
end

-- A player who can use the lobby: not in a battle or on its loading screens.
local function inLobby(player: Player): boolean
	return not party[player] and not returning[player]
end

-- Opens a room on `pad` (nil: the first idle pad) for the player, who picks
-- the map and how many players it takes; they join it and its countdown
-- starts. The one path for the Create lobby panel.
function Match.createLobby(player: Player, pad: number?, mapId: string, maxPlayers: number)
	if not inLobby(player) then
		return
	end
	if roomOf[player] then
		notify(player, "You are already in a lobby: click Exit lobby to leave it")
		return
	end
	if not isMapId(mapId) or maxPlayers % 1 ~= 0 or maxPlayers < 1 or maxPlayers > LobbyConfig.MaxBattlePlayers then
		return
	end
	local room: Room? = nil
	if pad then
		room = rooms[pad]
	else
		for _, candidate in rooms do
			if candidate.state == "Idle" then
				room = candidate
				break
			end
		end
	end
	if not room then
		notify(player, "Every pad has a lobby open: press E on a dais to join one")
		return
	end
	if room.state ~= "Idle" then
		notify(player, "A lobby is already open there: press E on the dais to join it")
		return
	end
	room.dais:SetAttribute("RoomMap", mapId)
	room.dais:SetAttribute("RoomMaxPlayers", maxPlayers)
	setRoom(player, room)
	startCountdown(room)
	print(`[Match] {player.Name} opened a lobby on pad {room.pad}: {mapId}, {maxPlayers} player(s)`)
end

-- E on a dais with a room open: join it (leaving any other room).
-- With none open there the client shows the Create lobby panel instead
-- (LobbyMenu.client); nothing here.
function Match.toggleRoom(player: Player, pad: number)
	local room = rooms[pad]
	if not room or room.state == "Idle" or not inLobby(player) then
		return
	end
	local old = roomOf[player]
	if old == room then
		return -- leaving is the Exit lobby button (Match.leaveRoom)
	end
	if count(room.members) >= roomMaxPlayers(room) then
		notify(player, "This lobby is full")
		return
	end
	setRoom(player, room)
	if old then
		closeIfEmpty(old)
	end
end

-- The Exit lobby button: out of their room, free to walk again.
function Match.leaveRoom(player: Player)
	local room = roomOf[player]
	if not room or not inLobby(player) then
		return
	end
	setRoom(player, nil)
	closeIfEmpty(room)
end

-- The server's side of the leash: anyone in a room found beyond its dais's
-- edge (a lagging or modified client, a respawn in the courtyard) is put
-- back on the dais.
task.spawn(function()
	while true do
		task.wait(LEASH_CHECK_SECONDS)
		for player, room in roomOf do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local offset = Vector3.new(root.Position.X - room.dais.Position.X, 0, root.Position.Z - room.dais.Position.Z)
				if offset.Magnitude > LobbyConfig.QueueRadius + LEASH_SLACK then
					standOnDais(player, room.dais)
				end
			end
		end
	end
end)

for _, pad in Lobby.Pads do
	pad.prompt.Triggered:Connect(function(player: Player)
		Match.toggleRoom(player, pad.index)
	end)
end

-- The Create lobby panel (LobbyMenu.client), see LobbyRequest at the top.
local REQUEST_GAP = 0.3 -- seconds between requests per player
local MAX_MAP_ID = 40 -- characters
local lastRequestAt: { [Player]: number } = {}
requestEvent.OnServerEvent:Connect(function(player: Player, action: unknown, pad: unknown, mapId: unknown, maxPlayers: unknown)
	local now = os.clock()
	if now - (lastRequestAt[player] or -math.huge) < REQUEST_GAP then
		return
	end
	lastRequestAt[player] = now
	if action == "Leave" then
		Match.leaveRoom(player)
		return
	end
	if action ~= "Create" or type(mapId) ~= "string" or #mapId > MAX_MAP_ID or type(maxPlayers) ~= "number" or maxPlayers ~= maxPlayers then
		return
	end
	if pad ~= nil and not (type(pad) == "number" and rooms[pad] ~= nil) then
		return -- not one of the pads
	end
	Match.createLobby(player, pad :: number?, mapId, maxPlayers)
end)

-- The end screen's button: back to the lobby before the results run out.
local lastReturnAt: { [Player]: number } = {}
returnEvent.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	if phase ~= "Ended" or not party[player] or now - (lastReturnAt[player] or -math.huge) < 1 then
		return
	end
	lastReturnAt[player] = now
	returnToLobby(player)
end)

Players.PlayerAdded:Connect(refreshContext)
for _, player in Players:GetPlayers() do
	refreshContext(player)
end

Players.PlayerRemoving:Connect(function(player)
	local room = roomOf[player]
	if room then
		setRoom(player, nil)
		closeIfEmpty(room)
	end
	if party[player] then
		party[player] = nil
		Workspace:SetAttribute("PartySize", count(party))
		resetIfEmpty()
	end
	returning[player] = nil
	lastReturnAt[player] = nil
	lastRequestAt[player] = nil
end)

return Match
