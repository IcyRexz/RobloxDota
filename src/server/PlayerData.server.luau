--!strict
-- Saved player stats (owner 2026-10-23: "have some stats recorded"; the first
-- piece of T20, following the rules in docs/05_ARCHITECTURE.md). Per player:
-- battles played, wins, losses, zombies killed, Zombie Cores earned (the
-- end-of-battle reward, Config.Rewards), best level reached and time spent
-- in battle. They grow when a battle ends (Match.Ended) for everyone who was
-- in it; a player who left before the end gets nothing for it.
--
-- Saving (DataStoreService, key "u_<UserId>"; a separate store in Studio):
--   * Loaded on join with UpdateAsync, which also takes a session lock (this
--     server's JobId and the time), so two servers never write the same
--     player. A lock held by another server is waited for a few times (it
--     may still be saving after the player left it); a lock older than
--     LOCK_SECONDS (a crashed server) is taken over.
--   * Saved after every battle, every AUTOSAVE_SECONDS if anything changed,
--     on leaving (which also releases the lock) and when the server shuts
--     down (BindToClose). A save never overwrites data whose lock another
--     server holds.
--   * Every DataStore call retries with growing waits. If loading fails (no
--     DataStore access, e.g. Studio without "Enable Studio Access to API
--     Services"), the player plays on with stats from zero that are counted
--     but never saved, so a failure can never overwrite a real save.
-- Player attributes (server-written, display only; the lobby's Stats panel):
--   RecordGames, RecordWins, RecordLosses, RecordKills, RecordZombieCores,
--   RecordBestLevel, RecordBattleSeconds; DataStatus "Loading" | "Saved" |
--   "Unsaved".

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Match = require(script.Parent.Match)

local STORE_NAME = if RunService:IsStudio() then "PlayerData_Studio_v1" else "PlayerData_v1"
local DATA_VERSION = 1
local LOCK_SECONDS = 600 -- a lock this old belongs to a server that is gone
local LOCK_WAITS = 4 -- times a fresh lock held by another server is waited for
local LOCK_WAIT_SECONDS = 3
local RETRIES = 3 -- tries per DataStore call
local AUTOSAVE_SECONDS = 120
local MAX_STAT = 1e12 -- anything bigger in a save is treated as broken

type Stats = {
	games: number,
	wins: number,
	losses: number,
	kills: number,
	zombieCores: number,
	bestLevel: number,
	battleSeconds: number,
}
type Lock = { job: string, time: number }
type SaveData = { version: number, stats: Stats, lock: Lock? }
type Session = { stats: Stats, canSave: boolean, dirty: boolean, lastEpoch: number }

-- Stat field -> its player attribute, in the Stats panel's order.
local FIELDS: { { field: string, attribute: string } } = {
	{ field = "games", attribute = "RecordGames" },
	{ field = "wins", attribute = "RecordWins" },
	{ field = "losses", attribute = "RecordLosses" },
	{ field = "kills", attribute = "RecordKills" },
	{ field = "zombieCores", attribute = "RecordZombieCores" },
	{ field = "bestLevel", attribute = "RecordBestLevel" },
	{ field = "battleSeconds", attribute = "RecordBattleSeconds" },
}

local sessions: { [Player]: Session } = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`[PlayerData] no DataStore access; stats will not be saved: {result}`)
	end
end

local function newStats(): Stats
	return { games = 0, wins = 0, losses = 0, kills = 0, zombieCores = 0, bestLevel = 0, battleSeconds = 0 }
end

-- A saved stats table, with anything missing or broken read as 0.
local function cleanStats(saved: any): Stats
	local stats = newStats()
	if type(saved) == "table" then
		for _, entry in FIELDS do
			local value = saved[entry.field]
			if type(value) == "number" and value == value and value >= 0 and value <= MAX_STAT then
				(stats :: any)[entry.field] = value
			end
		end
	end
	return stats
end

local function keyOf(player: Player): string
	return "u_" .. player.UserId
end

-- Runs a DataStore call, retrying with growing waits. Returns whether it worked.
local function withRetries(what: string, call: () -> ()): boolean
	for attempt = 1, RETRIES do
		local ok, problem = pcall(function(): string?
			call()
			return nil
		end)
		if ok then
			return true
		end
		warn(`[PlayerData] {what} failed (try {attempt}/{RETRIES}): {problem}`)
		if attempt < RETRIES then
			task.wait(2 ^ attempt)
		end
	end
	return false
end

local function publish(player: Player, session: Session)
	for _, entry in FIELDS do
		player:SetAttribute(entry.attribute, (session.stats :: any)[entry.field])
	end
end

local function setStatus(player: Player, status: "Loading" | "Saved" | "Unsaved")
	if player.Parent then
		player:SetAttribute("DataStatus", status)
	end
end

local function load(player: Player)
	setStatus(player, "Loading")
	local session: Session = { stats = newStats(), canSave = false, dirty = false, lastEpoch = -1 }
	sessions[player] = session
	publish(player, session)
	local activeStore = store
	if not activeStore then
		setStatus(player, "Unsaved")
		return
	end
	local key = keyOf(player)
	for _ = 1, LOCK_WAITS do
		local lockedElsewhere = false
		local loaded: SaveData? = nil
		local ok = withRetries(`loading {player.Name}`, function()
			activeStore:UpdateAsync(key, function(old: any): any
				local now = os.time()
				local lock = if type(old) == "table" then old.lock else nil
				if type(lock) == "table" and lock.job ~= game.JobId and type(lock.time) == "number" and now - lock.time < LOCK_SECONDS then
					lockedElsewhere = true
					return nil -- leave it untouched
				end
				local data: SaveData = {
					version = DATA_VERSION,
					stats = cleanStats(if type(old) == "table" then old.stats else nil),
					lock = { job = game.JobId, time = now },
				}
				loaded = data
				return data
			end)
		end)
		if not player.Parent then
			-- Left while loading (PlayerRemoving already dropped the session):
			-- give the lock back so their next server can load at once.
			if loaded and not lockedElsewhere then
				withRetries(`releasing {player.Name}`, function()
					activeStore:UpdateAsync(key, function(old: any): any
						if type(old) == "table" and type(old.lock) == "table" and old.lock.job == game.JobId then
							old.lock = nil
							return old
						end
						return nil
					end)
				end)
			end
			return
		end
		if not ok then
			break
		end
		local data = loaded
		if data and not lockedElsewhere then
			-- Anything counted while loading (a battle that ended) is kept on top.
			local counted = session.stats
			session.stats = data.stats
			for _, entry in FIELDS do
				local add = (counted :: any)[entry.field]
				if entry.field == "bestLevel" then
					session.stats.bestLevel = math.max(session.stats.bestLevel, add)
				else
					(session.stats :: any)[entry.field] += add
				end
			end
			session.dirty = session.dirty or counted.games > 0
			session.canSave = true
			publish(player, session)
			setStatus(player, "Saved")
			return
		end
		task.wait(LOCK_WAIT_SECONDS) -- another server still holds it; it may be saving
	end
	warn(`[PlayerData] {player.Name}: stats could not be loaded; this session is not saved`)
	setStatus(player, "Unsaved")
end

-- Writes the player's stats. `release` gives up the lock (leaving / shutdown).
local function save(player: Player, release: boolean)
	local session = sessions[player]
	local activeStore = store
	if not (session and session.canSave and activeStore) then
		return
	end
	if not session.dirty and not release then
		return
	end
	local stats = table.clone(session.stats)
	local stolen = false
	session.dirty = false
	local ok = withRetries(`saving {player.Name}`, function()
		activeStore:UpdateAsync(keyOf(player), function(old: any): any
			local lock = if type(old) == "table" then old.lock else nil
			if type(lock) == "table" and lock.job ~= game.JobId then
				stolen = true
				return nil -- another server has taken this player over; never overwrite it
			end
			local data: SaveData = {
				version = DATA_VERSION,
				stats = stats,
				lock = if release then nil else { job = game.JobId, time = os.time() },
			}
			return data
		end)
	end)
	if stolen then
		warn(`[PlayerData] {player.Name}: another server holds this save; not saving here any more`)
		session.canSave = false
		setStatus(player, "Unsaved")
	elseif not ok then
		session.dirty = true -- try again at the next save
	end
end

-- A battle ended: everyone who was in it gets it counted, once per battle.
Match.Ended:Connect(function(result: "Won" | "Lost", members: { Player })
	local epoch = Match.epoch()
	local startedAt = Workspace:GetAttribute("MatchStartedAt")
	local endedAt = Workspace:GetAttribute("MatchEndedAt")
	local seconds = if type(startedAt) == "number" and type(endedAt) == "number" then math.max(endedAt - startedAt, 0) else 0
	for _, player in members do
		local session = sessions[player]
		if not session or session.lastEpoch == epoch then
			continue
		end
		session.lastEpoch = epoch
		local stats = session.stats
		local kills = player:GetAttribute("Kills")
		local level = player:GetAttribute("Level")
		local cores = player:GetAttribute("ZombieCoresEarned")
		stats.games += 1
		if result == "Won" then
			stats.wins += 1
		else
			stats.losses += 1
		end
		stats.kills += if type(kills) == "number" then math.max(kills, 0) else 0
		stats.zombieCores += if type(cores) == "number" then math.max(cores, 0) else 0
		stats.bestLevel = math.max(stats.bestLevel, if type(level) == "number" then level else 0)
		stats.battleSeconds += math.floor(seconds)
		session.dirty = true
		publish(player, session)
		task.spawn(save, player, false)
	end
end)

Players.PlayerAdded:Connect(load)
for _, player in Players:GetPlayers() do
	task.spawn(load, player)
end

Players.PlayerRemoving:Connect(function(player)
	save(player, true)
	sessions[player] = nil
end)

-- Autosave: anything changed since the last save.
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for player, session in sessions do
			if session.dirty then
				task.spawn(save, player, false)
			end
		end
	end
end)

-- Shutdown: save everyone (in parallel) and release their locks before the
-- server closes.
game:BindToClose(function()
	local pending = 0
	for player in sessions do
		pending += 1
		task.spawn(function()
			save(player, true)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)
