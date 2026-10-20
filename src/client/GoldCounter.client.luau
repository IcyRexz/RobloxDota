--!strict
-- Gold counter in the top-right corner (owner 2026-10-20), in the game's UI
-- design system (docs/11_UI_DESIGN.md): a surface pill with a gold dot and the
-- player's Gold, read from the server-written Player attribute "Gold"
-- (Gold.server). The number pops briefly when it goes up, and a gold "+1"
-- floats up from the zombie you finished off (GoldGained event). Display only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local FloatingText = require(ReplicatedStorage.Shared.FloatingText)

local space = UiTheme.space
local AMOUNT_SIZE = UiTheme.TextSize.Value
local POP_SIZE = AMOUNT_SIZE + 8 -- the number briefly grows when gold comes in
local MAX_POPUP_DISTANCE = 300 -- ignore positions far from you (bad data)

local player = Players.LocalPlayer

local screen = Instance.new("ScreenGui")
screen.Name = "GoldCounter"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true -- flush to the window's top-right corner (owner 2026-10-21)
screen.Parent = player:WaitForChild("PlayerGui")

local panel = UiTheme.panel(screen)
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -space(3), 0, space(3))
panel.Size = UDim2.fromOffset(space(2), space(8))
panel.AutomaticSize = Enum.AutomaticSize.X
UiTheme.applyScale(panel)
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, space(3))
pad.PaddingRight = UDim.new(0, space(3))
pad.Parent = panel
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, space(2))
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local coin = Instance.new("Frame")
coin.Name = "Coin"
coin.LayoutOrder = 1
coin.Size = UDim2.fromOffset(12, 12)
coin.BackgroundColor3 = UiTheme.Gold
coin.BorderSizePixel = 0
coin.Parent = panel
UiTheme.corner(coin, 6)

local amount = UiTheme.text(panel, AMOUNT_SIZE, UiTheme.Font.Heavy)
amount.Name = "Amount"
amount.LayoutOrder = 2
amount.Size = UDim2.fromOffset(0, space(8))
amount.AutomaticSize = Enum.AutomaticSize.X
amount.TextTruncate = Enum.TextTruncate.None
amount.Text = "0"

local shown = 0
local function refresh()
	local value = player:GetAttribute("Gold")
	local gold = if type(value) == "number" and value == value and value >= 0 and value < 1e12 then math.floor(value) else 0
	amount.Text = tostring(gold)
	if gold > shown then
		-- Pop: grow, then spring back, so a gain is noticed.
		amount.TextSize = POP_SIZE
		amount.TextColor3 = UiTheme.Gold
		local settle = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(amount, settle, { TextSize = AMOUNT_SIZE }):Play()
		TweenService:Create(amount, TweenInfo.new(0.6), { TextColor3 = UiTheme.Text }):Play()
	end
	shown = gold
end
refresh()
player:GetAttributeChangedSignal("Gold"):Connect(refresh)

-- "+N" floating up from where the gold was earned (shared FloatingText motion).
local function popup(gained: number, at: Vector3)
	FloatingText.show(at, `+{gained}`, { color = UiTheme.Gold, size = 26, lift = 3.5, scatter = 0.3 })
end

local gainedEvent = ReplicatedStorage:WaitForChild("GoldGained") :: RemoteEvent
gainedEvent.OnClientEvent:Connect(function(gained: unknown, at: unknown)
	if type(gained) ~= "number" or gained ~= gained or gained <= 0 or gained > 1e6 or typeof(at) ~= "Vector3" then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera and (at - camera.CFrame.Position).Magnitude > MAX_POPUP_DISTANCE then
		return
	end
	popup(math.floor(gained), at)
end)
