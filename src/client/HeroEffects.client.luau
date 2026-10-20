--!strict
-- Hero attack effects on each player's own screen:
--  * Zeus's basic attack: a short jagged lightning bolt from his hand to where
--    the shot ended (the enemy hit, or the end of its range on a miss), plus a
--    small flash
--  * the target flashes white for a moment
--  * a damage number pops up over the target: white for hits you dealt, red
--    for hits you took (other players' fights show no numbers)
-- Display only: the server has already decided the hit (HeroAttack event).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local FloatingText = require(ReplicatedStorage.Shared.FloatingText)

local BOLT_COLOR = Color3.fromRGB(150, 210, 255)
local BOLT_SEGMENTS = 6
local BOLT_JITTER = 1.2 -- studs a kink may stray from the straight line
local BOLT_WIDTH = 0.25
local BOLT_SECONDS = 0.28 -- a little longer so each hit reads (owner 2026-10-21)

local HIT_FLASH_SECONDS = 0.2
-- Damage numbers follow the UI design system (docs/11_UI_DESIGN.md).
local DEALT_COLOR = UiTheme.Text
local TAKEN_COLOR = UiTheme.Enemy

local player = Players.LocalPlayer
local attackEvent = ReplicatedStorage:WaitForChild("HeroAttack") :: RemoteEvent

local function newEffectPart(size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cframe
	part.Color = BOLT_COLOR
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = Workspace
	return part
end

local function fadeAndRemove(part: BasePart)
	local tween = TweenService:Create(part, TweenInfo.new(BOLT_SECONDS), { Transparency = 1 })
	tween.Completed:Once(function()
		part:Destroy()
	end)
	tween:Play()
end

local function startPoint(attacker: Model): Vector3?
	local hand = attacker:FindFirstChild("RightHand") or attacker:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		return hand.Position
	end
	local root = attacker:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function endPoint(target: Instance, from: Vector3): Vector3?
	if target:IsA("BasePart") then
		-- A structure: the nearest point of its side, at the hand's height.
		local centre, half = target.Position, target.Size / 2
		return Vector3.new(
			math.clamp(from.X, centre.X - half.X, centre.X + half.X),
			math.clamp(from.Y, centre.Y - half.Y, centre.Y + half.Y),
			math.clamp(from.Z, centre.Z - half.Z, centre.Z + half.Z)
		)
	end
	local root = target:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function drawBolt(from: Vector3, to: Vector3)
	local points = { from }
	for i = 1, BOLT_SEGMENTS - 1 do
		local base = from:Lerp(to, i / BOLT_SEGMENTS)
		local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * BOLT_JITTER
		table.insert(points, base + jitter)
	end
	table.insert(points, to)

	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		if length > 0.01 then
			local segment = newEffectPart(Vector3.new(BOLT_WIDTH, BOLT_WIDTH, length), CFrame.lookAt((a + b) / 2, b))
			fadeAndRemove(segment)
		end
	end

	local flash = newEffectPart(Vector3.one * 1.6, CFrame.new(to))
	flash.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = BOLT_COLOR
	light.Range = 10
	light.Brightness = 3
	light.Parent = flash
	fadeAndRemove(flash)
end

local function flashTarget(target: Instance)
	local flash = Instance.new("Highlight")
	flash.FillColor = Color3.new(1, 1, 1)
	flash.FillTransparency = 0.35
	flash.OutlineTransparency = 1
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.Adornee = target
	flash.Parent = Workspace
	local tween = TweenService:Create(flash, TweenInfo.new(HIT_FLASH_SECONDS), { FillTransparency = 1 })
	tween.Completed:Once(function()
		flash:Destroy()
	end)
	tween:Play()
end

-- Bigger hits get bigger numbers (up to +10 px).
local function numberSize(amount: number): number
	return 22 + math.min(10, math.floor(amount / 30))
end

local function showNumber(at: Vector3, amount: number, color: Color3)
	FloatingText.show(at, tostring(math.round(amount)), { color = color, size = numberSize(amount) })
end

attackEvent.OnClientEvent:Connect(function(attacker: unknown, target: unknown, dealt: unknown, shotEnd: unknown)
	if not (typeof(attacker) == "Instance" and attacker:IsA("Model")) then
		return
	end
	local hitTarget: Instance? = nil
	if typeof(target) == "Instance" and (target:IsA("Model") or target:IsA("BasePart")) then
		hitTarget = target
	end
	local from = startPoint(attacker)
	local to = if typeof(shotEnd) == "Vector3" then shotEnd elseif from and hitTarget then endPoint(hitTarget, from) else nil
	if not (from and to and (to - from).Magnitude < 100) then
		return
	end
	drawBolt(from, to)
	if not hitTarget then
		return -- a miss: just the bolt
	end
	flashTarget(hitTarget)
	if type(dealt) == "number" and dealt == dealt and dealt > 0 and dealt < 100000 then
		if attacker == player.Character then
			showNumber(to, dealt, DEALT_COLOR)
		elseif hitTarget == player.Character then
			showNumber(to, dealt, TAKEN_COLOR)
		end
	end
end)
