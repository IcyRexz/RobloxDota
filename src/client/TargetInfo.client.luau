--!strict
-- Target panel at the top centre, just under the core strip (owner 2026-10-21;
-- moved down 2026-10-23, T10): the face, name and health
-- of whatever you are aiming at (the enemy under the red marker, or an ally
-- under the crosshair, published by HeroControls.client as the local player's
-- "AimTarget" ObjectValue).
-- In the UI design system (docs/11_UI_DESIGN.md): one surface panel, a round
-- portrait, name and "current / max", a thin health bar (red enemy, green ally).
-- The portrait is a small 3D view of the unit's head (ViewportFrame); buildings
-- show a short tag instead. The panel lingers briefly after you look away so
-- it does not flicker. Display only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameContext = require(ReplicatedStorage.Shared.GameContext)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Font = UiTheme.Font
local Size = UiTheme.TextSize
local Strength = UiTheme.Strength
local space = UiTheme.space

local PANEL_WIDTH = 260
local PORTRAIT = 44
local LINGER_SECONDS = 0.6 -- stays this long after the target is lost
local FADE_SECONDS = 0.2
local UNIT_NAMES: { [string]: string } = { Zombie = "Zombie", Brute = "Brute", Spitter = "Spitter", Ripper = "Ripper", Melee = "Swordsman", Archer = "Archer" }
local STRUCTURE_TAGS: { [string]: string } = { Tower = "TWR", Barracks = "BRK", Core = "CORE", Nest = "NEST" }
-- Players are always on our side; used until the server sets the attribute.
local DEFAULT_TEAM = Config.Teams.Defenders

local player = Players.LocalPlayer
local aimValue = player:WaitForChild("AimTarget") :: ObjectValue

local screen = Instance.new("ScreenGui")
screen.Name = "TargetInfo"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = player:WaitForChild("PlayerGui")
GameContext.showIn(screen, "Battle") -- battle UI: hidden in the lobby

local panel = UiTheme.panel(screen)
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0)
-- Just below the core health strip (CoreStrip.client), following the window size.
UiTheme.onScreenResize(function()
	local stripBottom = space(3) + UiTheme.CoreStripHeight * UiTheme.Scale * UiTheme.screenFactor()
	panel.Position = UDim2.new(0.5, 0, 0, stripBottom + space(2))
end)
panel.Size = UDim2.fromOffset(PANEL_WIDTH, PORTRAIT + space(4))
panel.Visible = false
local canvas = Instance.new("CanvasGroup") -- fades the whole panel at once
canvas.Size = UDim2.fromScale(1, 1)
canvas.BackgroundTransparency = 1
canvas.Parent = panel
UiTheme.applyScale(panel)

-- Portrait: a round 3D view of the head, or a tag for buildings.
local portrait = Instance.new("ViewportFrame")
portrait.Name = "Portrait"
portrait.Position = UDim2.fromOffset(space(2), space(2))
portrait.Size = UDim2.fromOffset(PORTRAIT, PORTRAIT)
portrait.BackgroundColor3 = UiTheme.Raised
portrait.BackgroundTransparency = UiTheme.RaisedHoverTransparency
portrait.Ambient = Color3.fromRGB(200, 200, 200)
portrait.LightColor = Color3.new(1, 1, 1)
portrait.LightDirection = Vector3.new(-1, -1, -1)
portrait.Parent = canvas
UiTheme.corner(portrait, PORTRAIT // 2)
local portraitCamera = Instance.new("Camera")
portraitCamera.FieldOfView = 30
portraitCamera.Parent = portrait
portrait.CurrentCamera = portraitCamera
local portraitTag = UiTheme.text(portrait, Size.Caption, Font.Heavy, Strength.Label)
portraitTag.Size = UDim2.fromScale(1, 1)
portraitTag.TextXAlignment = Enum.TextXAlignment.Center

local TEXT_X = space(2) + PORTRAIT + space(3)
local nameText = UiTheme.text(canvas, Size.Value - 1, Font.Heavy)
nameText.Position = UDim2.fromOffset(TEXT_X, space(3))
nameText.Size = UDim2.new(1, -(TEXT_X + space(3) + 70), 0, 18)
local healthText = UiTheme.text(canvas, Size.Small, Font.Bold, Strength.Label)
healthText.AnchorPoint = Vector2.new(1, 0)
healthText.Position = UDim2.new(1, -space(3), 0, space(3))
healthText.Size = UDim2.fromOffset(70, 18)
healthText.TextXAlignment = Enum.TextXAlignment.Right
local bar = UiTheme.bar(canvas, UiTheme.Bar.Health, UiTheme.Enemy)
bar.track.Position = UDim2.fromOffset(TEXT_X, space(3) + 22)
bar.track.Size = UDim2.new(1, -(TEXT_X + space(3)), 0, UiTheme.Bar.Health)

local function localTeam(): string
	local team = player:GetAttribute("Team")
	return if type(team) == "string" then team else DEFAULT_TEAM
end

local function displayName(target: Instance): string
	local kind = target:GetAttribute("Kind")
	if kind == "Minion" then
		local unitType = target:GetAttribute("MinionType")
		return if type(unitType) == "string" then UNIT_NAMES[unitType] or unitType else "Unit"
	elseif kind == "Hero" and target:IsA("Model") then
		local owner = Players:GetPlayerFromCharacter(target)
		return if owner then owner.DisplayName else target.Name
	end
	local override = target:GetAttribute("DisplayName") -- e.g. both barracks: "Barracks"
	if type(override) == "string" then
		return override
	end
	local spaced = target.Name:gsub("(%l)(%u)", "%1 %2") -- "ZombieCore" -> "Zombie Core"
	return spaced
end

-- Puts a still copy of the unit in the portrait, its head framed from the front.
local function showPortrait(target: Instance)
	portrait:ClearAllChildren()
	portraitCamera = Instance.new("Camera")
	portraitCamera.FieldOfView = 30
	portraitCamera.Parent = portrait
	portrait.CurrentCamera = portraitCamera
	portraitTag = UiTheme.text(portrait, Size.Caption, Font.Heavy, Strength.Label)
	portraitTag.Size = UDim2.fromScale(1, 1)
	portraitTag.TextXAlignment = Enum.TextXAlignment.Center
	UiTheme.corner(portrait, PORTRAIT // 2)

	local head = if target:IsA("Model") then target:FindFirstChild("Head") else nil
	if not (head and head:IsA("BasePart")) then
		local kind = target:GetAttribute("Kind")
		portraitTag.Text = if type(kind) == "string" then STRUCTURE_TAGS[kind] or "" else ""
		return
	end
	portraitTag.Text = ""
	local world = Instance.new("WorldModel")
	world.Parent = portrait
	-- The whole body is copied, not just the head: a lone head loses its skin
	-- colour (it showed white, owner 2026-10-23), the whole model keeps it the
	-- same way every spawned unit does. The camera only frames the head.
	local wasArchivable = target.Archivable
	target.Archivable = true
	local copy = target:Clone()
	target.Archivable = wasArchivable
	-- Scripts are removed before the copy is parented: a LocalScript (a
	-- player's Animate) would otherwise start running inside the PlayerGui.
	for _, item in copy:GetDescendants() do
		if item:IsA("LuaSourceContainer") or item:IsA("BillboardGui") or item:IsA("Sound") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
		end
	end
	local copyHumanoid = copy:FindFirstChildOfClass("Humanoid")
	if copyHumanoid then
		copyHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	copy.Parent = world
	-- Camera in front of the face, looking back at it.
	local front = head.CFrame.LookVector
	portraitCamera.CFrame = CFrame.lookAt(head.Position + front * 3.2 + Vector3.new(0, 0.15, 0), head.Position)
end

-- State -------------------------------------------------------------------------------

local shown: Instance? = nil
local lostAt: number? = nil

local function isAlive(target: Instance): boolean
	local health = target:GetAttribute("Health")
	return target.Parent ~= nil and type(health) == "number" and health > 0
end

local fades: { Tween } = {}

local function stopFades()
	for _, tween in fades do
		tween:Cancel()
	end
	table.clear(fades)
end

local function setVisible(visible: boolean)
	stopFades() -- a new target during a fade-out must not be faded away
	if visible then
		panel.Visible = true
		canvas.GroupTransparency = 0
		panel.BackgroundTransparency = UiTheme.SurfaceTransparency
	else
		local info = TweenInfo.new(FADE_SECONDS)
		local groupFade = TweenService:Create(canvas, info, { GroupTransparency = 1 })
		local panelFade = TweenService:Create(panel, info, { BackgroundTransparency = 1 })
		panelFade.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and shown == nil then
				panel.Visible = false
			end
		end)
		fades = { groupFade, panelFade }
		groupFade:Play()
		panelFade:Play()
	end
end

GameContext.renderStepped("Battle", function()
	local target = aimValue.Value
	if target and isAlive(target) then
		lostAt = nil
		if target ~= shown then
			shown = target
			showPortrait(target)
			nameText.Text = displayName(target)
			setVisible(true)
		end
	elseif shown then
		-- Keep the last target a moment, unless it died.
		lostAt = lostAt or os.clock()
		if not isAlive(shown) or os.clock() - (lostAt :: number) >= LINGER_SECONDS then
			shown = nil
			setVisible(false)
		end
	end
	local current = shown
	if current then
		local health = current:GetAttribute("Health")
		local maxHealth = current:GetAttribute("MaxHealth")
		local max = if type(maxHealth) == "number" and maxHealth > 0 then maxHealth else 1
		local hp = if type(health) == "number" then math.clamp(health, 0, max) else 0
		bar.fill.Size = UDim2.fromScale(hp / max, 1)
		bar.fill.BackgroundColor3 = if current:GetAttribute("Team") == localTeam() then UiTheme.Ally else UiTheme.Enemy
		healthText.Text = `{math.ceil(hp)} / {math.round(max)}`
	end
end)
