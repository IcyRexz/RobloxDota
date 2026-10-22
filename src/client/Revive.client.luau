--!strict
-- The revive prompt over a downed ally's body (owner 2026-10-23), in the UI
-- design system (docs/11_UI_DESIGN.md). The server puts a custom-style
-- ProximityPrompt named "RevivePrompt" on the body (Heroes.server); Roblox
-- still handles the F key, distance and hold, and this script only draws it:
-- a navy block with a gold F key chip, "Revive <name>" and a green bar that
-- fills while you hold. Not drawn on your own body or while you are down
-- yourself. Display only: the server checks and times every revive.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local Font = UiTheme.Font
local Size = UiTheme.TextSize
local space = UiTheme.space

local PROMPT_NAME = "RevivePrompt"
local WIDTH = 170
local HEIGHT = 46
local KEY = 26

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

type Shown = { billboard: BillboardGui, bar: UiTheme.Bar, holdStartedAt: number? }
local shown: { [ProximityPrompt]: Shown } = {}

local function isOwnBody(prompt: ProximityPrompt): boolean
	local character = player.Character
	return character ~= nil and prompt:IsDescendantOf(character)
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
	billboard.Name = "RevivePrompt"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(WIDTH * UiTheme.Scale, HEIGHT * UiTheme.Scale)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.ResetOnSpawn = false
	billboard.Parent = playerGui

	local panel = UiTheme.panel(billboard)
	panel.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	UiTheme.applyScale(panel)
	local key = UiTheme.block(panel, "Gold", 6, UiTheme.OutlineThin)
	key.Position = UDim2.fromOffset(space(2), (HEIGHT - KEY) // 2)
	key.Size = UDim2.fromOffset(KEY, KEY)
	local keyText = UiTheme.text(key, Size.Value, Font.Heavy)
	keyText.Size = UDim2.fromScale(1, 1)
	keyText.TextXAlignment = Enum.TextXAlignment.Center
	keyText.Text = "F"
	local textX = space(2) + KEY + space(2)
	local label = UiTheme.text(panel, Size.Body, Font.Bold)
	label.Position = UDim2.fromOffset(textX, space(1) + 2)
	label.Size = UDim2.new(1, -(textX + space(2)), 0, Size.Body + 4)
	label.Text = `{prompt.ActionText} {prompt.ObjectText}`
	local bar = UiTheme.bar(panel, UiTheme.Bar.Unit, UiTheme.Ally)
	bar.track.Position = UDim2.fromOffset(textX, HEIGHT - space(2) - UiTheme.Bar.Unit)
	bar.track.Size = UDim2.new(1, -(textX + space(2)), 0, UiTheme.Bar.Unit)
	bar.fill.Size = UDim2.fromScale(0, 1)

	shown[prompt] = { billboard = billboard, bar = bar, holdStartedAt = nil }
end

ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt.Name == PROMPT_NAME and not isOwnBody(prompt) and player:GetAttribute("Down") ~= true then
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

RunService.RenderStepped:Connect(function()
	for prompt, entry in shown do
		if not prompt.Parent or player:GetAttribute("Down") == true then
			hide(prompt)
		elseif entry.holdStartedAt then
			local share = (os.clock() - entry.holdStartedAt) / math.max(prompt.HoldDuration, 0.01)
			entry.bar.fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
		end
	end
end)
