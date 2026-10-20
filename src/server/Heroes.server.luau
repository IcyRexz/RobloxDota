--!strict
-- Makes every player's character the hero (Zeus for now) and owns hero health.
--  * Marks the character Kind = Hero with the player's team, so minions and
--    towers can target it and CombatService can damage it.
--  * Health lives in the server-owned Health/MaxHealth attributes, like every
--    other unit. The Humanoid's own health just mirrors it (0 = dead), and
--    Roblox's built-in health regeneration is removed.
--  * Death: Roblox respawns the player after Config.Hero.RespawnTime seconds
--    with full health. Spawn protection and death rules come in T08.
--  * Max health and walk speed include the player's level-up picks (HeroProgress),
--    so upgrades survive respawning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroProgress = require(script.Parent.HeroProgress)

local HeroConfig = Config.Hero

Players.RespawnTime = HeroConfig.RespawnTime

local function setupHero(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end

	-- Roblox adds a "Health" script that slowly heals the character; heroes do not regenerate.
	local function removeRegen(child: Instance)
		if child.Name == "Health" and child:IsA("Script") then
			child:Destroy()
		end
	end
	for _, child in character:GetChildren() do
		removeRegen(child)
	end
	character.ChildAdded:Connect(removeRegen)

	-- The hero's team follows the player's (set by PlayerTeams; later by the match).
	-- A hero with no team yet is ignored by minions and towers.
	local function syncTeam()
		local team = player:GetAttribute("Team")
		character:SetAttribute("Team", if typeof(team) == "string" then team else nil)
	end
	syncTeam()
	local teamConnection = player:GetAttributeChangedSignal("Team"):Connect(syncTeam)
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			teamConnection:Disconnect()
		end
	end)

	character:SetAttribute("Kind", "Hero")
	character:SetAttribute("HeroName", HeroConfig.Name)
	local maxHealth = HeroProgress.maxHealth(player)
	character:SetAttribute("MaxHealth", maxHealth)
	character:SetAttribute("Health", maxHealth)

	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = HeroProgress.walkSpeed(player)
	-- Our own overhead bar replaces Roblox's name and health display.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	-- The attribute is the truth; the Humanoid follows it. These connections end
	-- when the character is removed on respawn.
	character:GetAttributeChangedSignal("Health"):Connect(function()
		local health = character:GetAttribute("Health")
		if typeof(health) == "number" then
			humanoid.Health = math.max(health, 0)
		end
	end)
	-- Dying some other way (falling off the map, reset) also zeroes the attribute.
	humanoid.Died:Connect(function()
		character:SetAttribute("Health", 0)
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		setupHero(player, character)
	end)
	if player.Character then
		task.spawn(setupHero, player, player.Character)
	end
end

for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerAdded:Connect(onPlayer)
