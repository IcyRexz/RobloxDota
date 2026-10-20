--!strict
-- Floating text in the world (damage numbers, "+1" gold), shared so every
-- popup moves the same way (owner 2026-10-21: popups felt too quick):
--  1. pop: appears slightly small and springs past full size, then settles
--  2. hold: stays readable for a moment
--  3. drift: rises and fades out
-- Client-side display only. Text style follows the UI design system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local FloatingText = {}

local POP_SECONDS = 0.18
local HOLD_SECONDS = 0.45
local DRIFT_SECONDS = 0.9
local RISE = 3.5 -- studs during the drift

export type Options = {
	color: Color3?,
	size: number?, -- text size in pixels at full size
	scatter: number?, -- studs of random sideways offset, so quick hits do not stack
	lift: number?, -- studs above `at` where it appears
}

function FloatingText.show(at: Vector3, text: string, options: Options?)
	local color = (options and options.color) or UiTheme.Text
	local size = (options and options.size) or 24
	local scatter = (options and options.scatter) or 1.2
	local lift = (options and options.lift) or 2.5

	local anchor = Instance.new("Part")
	anchor.Name = "FloatingText"
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = at + Vector3.new((math.random() - 0.5) * 2 * scatter, lift, (math.random() - 0.5) * 2 * scatter)
	anchor.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(size * 5, size * 1.6)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = anchor
	billboard.Parent = anchor
	local label = UiTheme.text(billboard, math.floor(size * 0.6), UiTheme.Font.Heavy)
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextColor3 = color
	label.Text = text
	UiTheme.floatingText(label)
	label.TextStrokeTransparency = 0.35

	-- 1. Pop: overshoot to 125%, then settle to full size.
	local overshoot = TweenService:Create(
		label,
		TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextSize = math.floor(size * 1.25) }
	)
	overshoot.Completed:Once(function()
		TweenService:Create(label, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextSize = size }):Play()
	end)
	overshoot:Play()

	-- 2. Hold, then 3. drift up and fade.
	task.delay(POP_SECONDS + HOLD_SECONDS, function()
		if not anchor.Parent then
			return
		end
		local drift = TweenInfo.new(DRIFT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(anchor, drift, { Position = anchor.Position + Vector3.new(0, RISE, 0) }):Play()
		local fade = TweenService:Create(label, drift, { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade.Completed:Once(function()
			anchor:Destroy()
		end)
		fade:Play()
	end)
end

return FloatingText
