--!strict
-- Makes every player's character the hero (the Mage for now) and owns hero
-- health, death, revive and respawn.
--  * Marks the character Kind = Hero with the player's team, so minions and
--    towers can target it and CombatService can damage it.
--  * Health lives in the server-owned Health/MaxHealth attributes, like every
--    other unit. The Humanoid's own health follows it but never reaches 0, so
--    Roblox never kills the body; Roblox's built-in regeneration is removed and
--    our own (HeroProgress.healthRegen, health per second) heals living heroes.
--  * Max health and walk speed include the player's level growth (HeroProgress),
--    so it survives respawning.
--
-- Death and revive (owner 2026-10-23, numbers in Config.Hero.Death):
--  * At 0 health the hero is down: it cannot move, the body is laid on its
--    back where it fell (root anchored) and the respawn countdown starts. The
--    character carries DownedAt / RespawnAt (server time) for the clients'
--    death screen and party list. Clients are told "Fallen".
--  * Revive: while down, a ProximityPrompt (custom style, drawn by
--    Revive.client) on the body lets a living ally hold F. The server checks
--    the reviver (alive, same team, close, not the downed player) when the
--    hold starts and again when it completes, and times the hold itself. While
--    someone holds, the body carries ReviverName / ReviveStartedAt. A revive
--    stands the hero up where it fell with a share of its max health. Each
--    player can be revived once per match (player attribute ReviveUsed; reset
--    with the match later, T15). Clients are told "Revived".
--  * Otherwise, when the countdown ends, the player respawns at the pad with
--    full health (CharacterAutoLoads is off; this script loads characters).
--  * Coming back either way sets ProtectedUntil: CombatService refuses damage
--    until then.
--  * A body Roblox really killed (fell off the map) cannot be revived; the
--    countdown still respawns it.
--
-- Remote: HeroDowned (server -> client only; the server never listens):
--   ("Fallen", player)  /  ("Revived", reviver, player)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local CombatService = require(script.Parent.CombatService)
local Config = require(ReplicatedStorage.Shared.Config)
local HeroProgress = require(script.Parent.HeroProgress)

local HeroConfig = Config.Hero
local Death = HeroConfig.Death

local REGEN_TICK = 0.5 -- seconds between regeneration steps
local GROUND_PROBE_UP = 3 -- studs above the root the ground ray starts (below tree canopies)
local GROUND_PROBE_DOWN = 40
local LYING_CLEARANCE = 0.05 -- a lying body's lowest point sits this far above the ground
local REVIVE_DISTANCE_SLACK = 2 -- studs of leeway for movement during the hold
local REVIVE_TIME_SLACK = 0.25 -- seconds a completed hold may be short (latency)

Players.CharacterAutoLoads = false

local downedEvent = Instance.new("RemoteEvent")
downedEvent.Name = "HeroDowned"
downedEvent.Parent = ReplicatedStorage

-- A hero that is down, by character.
type Downed = {
	player: Player,
	humanoid: Humanoid,
	downedAt: number, -- also the token that ties delayed callbacks to this death
	facing: Vector3, -- flat direction the hero faced when it fell
	prompt: ProximityPrompt?,
	-- The ally whose hold counts (the first to start), when it started and,
	-- once let go, when it ended. Kept after the hold ends because Roblox may
	-- report the release just before the completed trigger.
	holder: Player?,
	holdStartedAt: number,
	holdEndedAt: number?,
	over: boolean, -- revived: the countdown no longer respawns this body
}
local downedOf: { [Model]: Downed } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function respawnDelay(player: Player): number
	local level = HeroProgress.level(player)
	return math.min(Death.RespawnBase + Death.RespawnPerLevel * (level - 1), Death.RespawnMax)
end

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The real ground height under a point (Terrain, floors, rocks), found by a
-- ray, ignoring every character and unit. Falls back to `fallback`.
local function groundUnder(position: Vector3, fallback: number): number
	local ignore: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local minions = Workspace:FindFirstChild("Minions")
	if minions then
		table.insert(ignore, minions)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local origin = position + Vector3.new(0, GROUND_PROBE_UP, 0)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -GROUND_PROBE_DOWN, 0), params)
	return if hit then hit.Position.Y else fallback
end

-- The lowest point of the body's own parts (not accessories) as posed now.
local function lowestPointOf(character: Model): number?
	local lowest: number? = nil
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") then
			local cframe, half = part.CFrame, part.Size / 2
			local reach = math.abs(cframe.RightVector.Y) * half.X
				+ math.abs(cframe.UpVector.Y) * half.Y
				+ math.abs(cframe.LookVector.Y) * half.Z
			local bottom = part.Position.Y - reach
			lowest = if lowest then math.min(lowest, bottom) else bottom
		end
	end
	return lowest
end

local function clearReviveDisplay(character: Model)
	character:SetAttribute("ReviverName", nil)
	character:SetAttribute("ReviveStartedAt", nil)
end

-- Back on its feet where it lay (revive): unanchored and handed back to the
-- player's device, which moves its own character.
local function standUp(player: Player, character: Model, state: Downed)
	local root = rootOf(character)
	if root then
		local ground = groundUnder(root.Position, root.Position.Y)
		local position = Vector3.new(root.Position.X, ground + state.humanoid.HipHeight + root.Size.Y / 2, root.Position.Z)
		character:PivotTo(CFrame.lookAt(position, position + state.facing))
		root.Anchored = false
		root:SetNetworkOwner(player)
	end
	state.humanoid.WalkSpeed = HeroProgress.walkSpeed(player)
	state.humanoid.JumpPower = StarterPlayer.CharacterJumpPower
end

-- Can this player revive this downed hero right now?
local function canRevive(reviver: Player, character: Model, state: Downed): boolean
	if reviver == state.player or downedOf[character] ~= state or state.player:GetAttribute("ReviveUsed") == true then
		return false
	end
	local body = reviver.Character
	local bodyRoot = body and rootOf(body)
	local root = rootOf(character)
	return body ~= nil
		and bodyRoot ~= nil
		and root ~= nil
		and body:GetAttribute("Kind") == "Hero"
		and body:GetAttribute("Team") == character:GetAttribute("Team")
		and CombatService.isAlive(body)
		and (bodyRoot.Position - root.Position).Magnitude <= Death.ReviveDistance + REVIVE_DISTANCE_SLACK
end

local function revive(reviver: Player, character: Model, state: Downed)
	local player = state.player
	state.over = true
	downedOf[character] = nil
	if state.prompt then
		state.prompt:Destroy()
	end
	player:SetAttribute("ReviveUsed", true)
	clearReviveDisplay(character)
	character:SetAttribute("DownedAt", nil)
	character:SetAttribute("RespawnAt", nil)
	standUp(player, character, state)
	local maxHealth = HeroProgress.maxHealth(player) -- may have grown while down
	character:SetAttribute("MaxHealth", maxHealth)
	state.humanoid.MaxHealth = maxHealth
	character:SetAttribute("ProtectedUntil", now() + Death.Protection)
	character:SetAttribute("Health", maxHealth * Death.ReviveHealthShare)
	downedEvent:FireAllClients("Revived", reviver, player)
end

local function addRevivePrompt(player: Player, character: Model, root: BasePart, state: Downed)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.Style = Enum.ProximityPromptStyle.Custom -- drawn by Revive.client in the UI design system
	prompt.ActionText = "Revive"
	prompt.ObjectText = player.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = Death.ReviveHold
	prompt.MaxActivationDistance = Death.ReviveDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	state.prompt = prompt

	prompt.PromptButtonHoldBegan:Connect(function(reviver: Player)
		local holding = state.holder ~= nil and state.holdEndedAt == nil
		if (not holding or state.holder == reviver) and canRevive(reviver, character, state) then
			state.holder, state.holdStartedAt, state.holdEndedAt = reviver, now(), nil
			character:SetAttribute("ReviverName", reviver.DisplayName)
			character:SetAttribute("ReviveStartedAt", state.holdStartedAt)
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(reviver: Player)
		if state.holder == reviver and state.holdEndedAt == nil then
			state.holdEndedAt = now()
			clearReviveDisplay(character)
		end
	end)
	prompt.Triggered:Connect(function(reviver: Player)
		-- The hold is timed here, from when the server saw it start; a release
		-- reported just before the trigger is accepted only if it came at the end.
		local time = now()
		local endedAt = state.holdEndedAt or time
		if
			state.holder == reviver
			and time - endedAt <= REVIVE_TIME_SLACK
			and endedAt - state.holdStartedAt >= Death.ReviveHold - REVIVE_TIME_SLACK
			and canRevive(reviver, character, state)
		then
			revive(reviver, character, state)
		end
	end)
end

local function goDown(player: Player, character: Model, humanoid: Humanoid)
	if downedOf[character] or character:GetAttribute("DownedAt") ~= nil then
		return
	end
	local downedAt = now()
	local wait = respawnDelay(player)
	local root = rootOf(character)
	local look = if root then root.CFrame.LookVector else -Vector3.zAxis
	local facing = Vector3.new(look.X, 0, look.Z)
	local state: Downed = {
		player = player,
		humanoid = humanoid,
		downedAt = downedAt,
		facing = if facing.Magnitude > 0.01 then facing.Unit else -Vector3.zAxis,
		prompt = nil,
		holder = nil,
		holdStartedAt = 0,
		holdEndedAt = nil,
		over = false,
	}
	downedOf[character] = state
	character:SetAttribute("DownedAt", downedAt)
	character:SetAttribute("RespawnAt", downedAt + wait)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	-- Laid on its back where it fell, head away from where it faced. Only a
	-- body Roblox has not killed itself can lie down and be revived.
	local bodyIntact = humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Dead
	if root and bodyIntact then
		-- Turned flat first, then lifted or lowered so its lowest part rests
		-- exactly on the ground found by a ray (not a height formula, which
		-- left the body inside the terrain).
		local feet = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
		local ground = groundUnder(root.Position, feet)
		root.Anchored = true
		local position = root.Position
		character:PivotTo(CFrame.lookAt(position, position + state.facing) * CFrame.Angles(math.rad(90), 0, 0))
		local lowest = lowestPointOf(character)
		if lowest then
			character:PivotTo(character:GetPivot() + Vector3.new(0, ground + LYING_CLEARANCE - lowest, 0))
		end
		if player:GetAttribute("ReviveUsed") ~= true then
			addRevivePrompt(player, character, root, state)
		end
	end
	downedEvent:FireAllClients("Fallen", player)

	task.delay(wait, function()
		-- Only this death: not one that was revived (and maybe died again
		-- since). A body Roblox destroyed (fell off the map) still respawns.
		if state.over or not player.Parent or (player.Character ~= nil and player.Character ~= character) then
			return
		end
		state.over = true
		downedOf[character] = nil
		player:LoadCharacterAsync()
	end)
end

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
			downedOf[character] = nil
		end
	end)

	character:SetAttribute("Kind", "Hero")
	character:SetAttribute("HeroName", HeroConfig.Name)
	local maxHealth = HeroProgress.maxHealth(player)
	character:SetAttribute("MaxHealth", maxHealth)
	character:SetAttribute("Health", maxHealth)
	character:SetAttribute("ProtectedUntil", now() + Death.Protection)

	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = HeroProgress.walkSpeed(player)
	-- Our own overhead bar replaces Roblox's name and health display.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	-- The attribute is the truth; the Humanoid follows it, but never down to 0
	-- (that would make Roblox kill and break the body). 0 means down. These
	-- connections end when the character is removed on respawn.
	character:GetAttributeChangedSignal("Health"):Connect(function()
		local health = character:GetAttribute("Health")
		if typeof(health) ~= "number" then
			return
		end
		if health <= 0 then
			goDown(player, character, humanoid)
		elseif humanoid.Health > 0 then
			humanoid.Health = math.clamp(health, 1, humanoid.MaxHealth)
		end
	end)
	-- Dying some other way (falling off the map) also zeroes the attribute.
	humanoid.Died:Connect(function()
		character:SetAttribute("Health", 0)
		goDown(player, character, humanoid) -- already at 0 if it was down
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		setupHero(player, character)
	end)
	if player.Character then
		task.spawn(setupHero, player, player.Character)
	else
		task.spawn(function()
			player:LoadCharacterAsync()
		end)
	end
end

for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerAdded:Connect(onPlayer)

-- Natural regeneration: living heroes below max health heal a little each tick.
-- The down (health 0) do not; they come back on revive or respawn.
local function regenerate(elapsed: number)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not (character and character:GetAttribute("Kind") == "Hero" and CombatService.isAlive(character)) then
			continue
		end
		local maxHealth = character:GetAttribute("MaxHealth")
		local health = CombatService.getHealth(character)
		if typeof(maxHealth) == "number" and health < maxHealth then
			local heal = HeroProgress.healthRegen(player) * elapsed
			character:SetAttribute("Health", math.min(health + heal, maxHealth))
		end
	end
end

task.spawn(function()
	while true do
		regenerate(task.wait(REGEN_TICK))
	end
end)
