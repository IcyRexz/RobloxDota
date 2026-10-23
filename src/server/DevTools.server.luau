--!strict
-- Developer commands for testing (owner 2026-10-21), sent by the panel under
-- the Gold counter (DevPanel.client). Studio only: in a live game the remote
-- is still created (so the client never waits forever) but every request is
-- ignored. The client names a command (and for Spawn, a unit kind from
-- Config.Dev.SpawnKinds); amounts and positions are decided here, never taken
-- from the client.
--
-- Remote: DevCommand (client -> server): (command: string, kind: string?)
--   "Xp" / "Gold": add Config.Dev.Xp / Gold to the sender.
--   "Spawn", kind: one unit of that kind; zombies Config.Dev.ZombieDistance
--     studs in front of the sender's hero, our soldiers SoldierDistance beside it.
--   "NextEvent": start the next battlefield event now (ZombieEvents).
--   "Event", id: start that event or arrival now (an id from Config.Events
--     List or Arrivals).
--   "Die": the sender's hero drops to 0 health and goes down (Heroes.server).
--   "Win" / "Lose": the Zombie Core / our Base Core takes damage equal to its
--     health through CombatService, so the match ends as it would (Match.luau).
--   Ignored outside Studio, for unknown commands or kinds, or faster than MIN_GAP.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatService = require(script.Parent.CombatService)
local Config = require(ReplicatedStorage.Shared.Config)
local Gold = require(script.Parent.Gold)
local Match = require(script.Parent.Match)
local HeroProgress = require(script.Parent.HeroProgress)
local UnitRequests = require(script.Parent.UnitRequests)
local ZombieEvents = require(script.Parent.ZombieEvents)

local MIN_GAP = 0.15 -- seconds between accepted commands per player
local ZOMBIE_KINDS = { Zombie = true, Brute = true, Spitter = true, Ripper = true }

local commandEvent = Instance.new("RemoteEvent")
commandEvent.Name = "DevCommand"
commandEvent.Parent = ReplicatedStorage

local enabled = RunService:IsStudio()
local lastAt: { [Player]: number } = {}

local function spawnUnit(player: Player, kind: unknown)
	if type(kind) ~= "string" or not table.find(Config.Dev.SpawnKinds, kind) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.xAxis
	local zombie = ZOMBIE_KINDS[kind] == true
	local offset = if zombie
		then look * Config.Dev.ZombieDistance
		else Vector3.new(-look.Z, 0, look.X) * Config.Dev.SoldierDistance
	UnitRequests.spawn(if zombie then Config.Teams.Zombies else Config.Teams.Defenders, kind, root.Position + offset)
end

-- Brings a side's core to 0 through the normal damage path (attacker: the
-- Workspace, on the other side), so Died fires and the match ends.
local function destroyCore(team: string, byTeam: string)
	if not Match.isFighting() then
		return -- only during a fight
	end
	for _, item in Workspace:WaitForChild("Arena"):GetDescendants() do
		if item:IsA("BasePart") and item:GetAttribute("Kind") == "Core" and item:GetAttribute("Team") == team then
			CombatService.applyDamage(item, CombatService.getHealth(item), Workspace, byTeam)
		end
	end
end

local commands: { [string]: (Player, unknown) -> () } = {
	Xp = function(player)
		HeroProgress.addXp(player, Config.Dev.Xp)
	end,
	Gold = function(player)
		Gold.add(player, Config.Dev.Gold)
	end,
	Spawn = spawnUnit,
	NextEvent = function()
		ZombieEvents.triggerNext()
	end,
	Event = function(_player, id)
		if type(id) == "string" then
			ZombieEvents.trigger(id)
		end
	end,
	Die = function(player)
		local character = player.Character
		if character and character:GetAttribute("Kind") == "Hero" then
			character:SetAttribute("Health", 0)
		end
	end,
	Win = function()
		destroyCore(Config.Teams.Zombies, Config.Teams.Defenders)
	end,
	Lose = function()
		destroyCore(Config.Teams.Defenders, Config.Teams.Zombies)
	end,
}

commandEvent.OnServerEvent:Connect(function(player: Player, command: unknown, kind: unknown)
	if not enabled or type(command) ~= "string" then
		return
	end
	local run = commands[command]
	local now = os.clock()
	if not run or now - (lastAt[player] or -math.huge) < MIN_GAP then
		return
	end
	lastAt[player] = now
	run(player, kind)
	print(`[DevTools] {player.Name}: {command}{if type(kind) == "string" then " " .. kind else ""}`)
end)

Players.PlayerRemoving:Connect(function(player)
	lastAt[player] = nil
end)
