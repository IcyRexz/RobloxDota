--!strict
-- Effects for Zeus's abilities on every player's screen, driven by the server's
-- SkillFx event (HeroActions.server). World effects (not UI), in the lightning
-- colour of the basic attack:
--  * Strike: the area flashes on the ground, then a jagged bolt drops from the
--    sky when the damage lands, with a ring bursting outward.
--  * Dash: a short streak behind the dashing hero; DashPush: a ring where they land.
--  * BallCharge: a growing ball at the caster's hand; BallFly: the ball flies
--    to its target, following it, and bursts on arrival.
--  * Hit (sent to the caster only): a damage number over the target, like the
--    basic attack's (UI design system).
-- Display only: the server has already decided every hit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GroundRing = require(ReplicatedStorage.Shared.GroundRing)
local FloatingText = require(ReplicatedStorage.Shared.FloatingText)

local COLOR = Color3.fromRGB(150, 210, 255)
local MAX_TIME = 5 -- ignore effect messages with longer times (bad data)
local MAX_RADIUS = 60

local skillFx = ReplicatedStorage:WaitForChild("SkillFx") :: RemoteEvent

local function effectPart(size: Vector3, transparency: number): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = COLOR
	part.Material = Enum.Material.Neon
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = Workspace
	return part
end

local function fadeOut(part: BasePart, seconds: number, grow: Vector3?)
	local goal: { [string]: any } = { Transparency = 1 }
	if grow then
		goal.Size = grow
	end
	local tween = TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween.Completed:Once(function()
		part:Destroy()
	end)
	tween:Play()
end

-- A ring on the ground (following its shape) that bursts outward from
-- `startRadius` to `endRadius` while fading.
local function groundBurst(at: Vector3, startRadius: number, endRadius: number, seconds: number)
	local ring = GroundRing.new(COLOR, endRadius, 0.1, 0.6)
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime
		local alpha = math.min(elapsed / seconds, 1)
		local eased = 1 - (1 - alpha) * (1 - alpha)
		ring:place(at, startRadius + (endRadius - startRadius) * eased)
		ring:setTransparency(0.1 + 0.9 * alpha, 0.6 + 0.4 * alpha)
		if alpha >= 1 then
			connection:Disconnect()
			ring:destroy()
		end
	end)
end

-- A jagged bolt between two points, fading quickly.
local function bolt(from: Vector3, to: Vector3, width: number)
	local points = { from }
	for i = 1, 7 do
		local base = from:Lerp(to, i / 8)
		table.insert(points, base + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 3)
	end
	table.insert(points, to)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		if length > 0.01 then
			local segment = effectPart(Vector3.new(width, width, length), 0)
			segment.CFrame = CFrame.lookAt((a + b) / 2, b)
			fadeOut(segment, 0.3)
		end
	end
end

local function rootOf(model: Instance): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function handOf(hero: Model): Vector3?
	local hand = hero:FindFirstChild("RightHand")
	if hand and hand:IsA("BasePart") then
		return hand.Position
	end
	local root = rootOf(hero)
	return if root then root.Position else nil
end

local function centreOf(target: Instance): Vector3?
	if target:IsA("BasePart") then
		return target.Position
	end
	local root = rootOf(target)
	return if root then root.Position else nil
end

local function validTime(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= MAX_TIME
end

local function validRadius(value: unknown): boolean
	return type(value) == "number" and value == value and value > 0 and value <= MAX_RADIUS
end

-- Damage number over a target (caster only), in the UI design system.
local function showNumber(at: Vector3, amount: number)
	FloatingText.show(at, tostring(math.round(amount)), { size = 22 + math.min(10, math.floor(amount / 30)) })
end

-- Effects ----------------------------------------------------------------------------

local function onStrike(point: Vector3, radius: number, delay: number)
	-- The area shows on the ground now (a warning), the bolt lands after the delay.
	local area = GroundRing.new(COLOR, radius, 0.2, 0.6)
	area:place(point)
	task.delay(delay, function()
		area:destroy()
		bolt(point + Vector3.new(0, 60, 0), point, 0.6)
		groundBurst(point, radius * 0.3, radius, 0.6)
	end)
end

local function onDash(hero: Model, duration: number)
	local root = rootOf(hero)
	if not root then
		return
	end
	local trail = effectPart(Vector3.new(0.4, 0.4, 0.4), 0.3)
	local start = root.Position
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime
		local now = root.Position
		local length = (now - start).Magnitude
		if length > 0.05 then
			trail.Size = Vector3.new(0.4, 0.4, length)
			trail.CFrame = CFrame.lookAt((start + now) / 2, now)
		end
		if elapsed >= duration or not root.Parent then
			connection:Disconnect()
			fadeOut(trail, 0.3)
		end
	end)
end

local function onDashPush(point: Vector3, radius: number)
	groundBurst(point, 1, radius, 0.5)
end

local function onBallCharge(hero: Model, chargeTime: number)
	local ball = effectPart(Vector3.one * 0.4, 0.1)
	ball.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = COLOR
	light.Range = 8
	light.Brightness = 2
	light.Parent = ball
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime
		local hand = handOf(hero)
		if hand then
			ball.Position = hand
		end
		local size = 0.4 + 1.6 * math.min(elapsed / math.max(chargeTime, 0.01), 1)
		ball.Size = Vector3.one * size
		if elapsed >= chargeTime or not hero.Parent then
			connection:Disconnect()
			ball:Destroy() -- BallFly takes over (or the cast fizzled)
		end
	end)
end

local function onBallFly(hero: Model, target: Instance, flightTime: number)
	local start = handOf(hero)
	if not start then
		return
	end
	local ball = effectPart(Vector3.one * 2, 0)
	ball.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = COLOR
	light.Range = 12
	light.Brightness = 3
	light.Parent = ball
	ball.Position = start
	local lastPoint = centreOf(target) or start
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime
		lastPoint = centreOf(target) or lastPoint -- follow the target while it exists
		local alpha = math.min(elapsed / math.max(flightTime, 0.01), 1)
		ball.Position = start:Lerp(lastPoint, alpha)
		if alpha >= 1 then
			connection:Disconnect()
			ball:Destroy()
			local burst = effectPart(Vector3.one * 2, 0.2)
			burst.Shape = Enum.PartType.Ball
			burst.Position = lastPoint
			fadeOut(burst, 0.35, Vector3.one * 9)
		end
	end)
end

skillFx.OnClientEvent:Connect(function(kind: unknown, a: unknown, b: unknown, c: unknown)
	if kind == "Strike" then
		if typeof(a) == "Vector3" and validRadius(b) and validTime(c) then
			onStrike(a, b :: number, c :: number)
		end
	elseif kind == "Dash" then
		if typeof(a) == "Instance" and a:IsA("Model") and validTime(b) then
			onDash(a, b :: number)
		end
	elseif kind == "DashPush" then
		if typeof(a) == "Vector3" and validRadius(b) then
			onDashPush(a, b :: number)
		end
	elseif kind == "BallCharge" then
		if typeof(a) == "Instance" and a:IsA("Model") and validTime(b) then
			onBallCharge(a, b :: number)
		end
	elseif kind == "BallFly" then
		if typeof(a) == "Instance" and a:IsA("Model") and typeof(b) == "Instance" and validTime(c) then
			onBallFly(a, b, c :: number)
		end
	elseif kind == "Hit" then
		if typeof(a) == "Instance" and type(b) == "number" and b == b and b > 0 and b < 100000 then
			local at = centreOf(a)
			if at then
				showNumber(at, b)
			end
		end
	end
end)
