--!strict
-- Developer panel just under the Gold counter (owner 2026-10-21), in the UI
-- design system (docs/11_UI_DESIGN.md): a small surface panel with rows of
-- buttons, right-aligned under the counter:
--   DEV    +30 XP  +200 Gold          (amounts from Config.Dev)
--   SPAWN  Zombie Brute Spitter Swordsman Archer   (Config.Dev.SpawnKinds)
--   EVENT  Next event
-- The camera locks the mouse in first person, so ` (backquote) frees it for
-- clicking the panel (a Modal button) and locks it again. Shown only in
-- Studio; each click asks the server (DevTools.server), which decides.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

if not RunService:IsStudio() then
	return
end

local space = UiTheme.space
local ROW_HEIGHT = space(7)
local MOUSE_KEY = Enum.KeyCode.Backquote
-- Gold counter: space(3) from the top, space(8) tall at UiTheme.Scale.
local TOP = space(3) + space(8) * UiTheme.Scale + space(2)
local ZOMBIE_KINDS = { Zombie = true, Brute = true, Spitter = true }
local KIND_LABELS: { [string]: string } = { Melee = "Swordsman" }

local player = Players.LocalPlayer
local commandEvent = ReplicatedStorage:WaitForChild("DevCommand") :: RemoteEvent

local screen = Instance.new("ScreenGui")
screen.Name = "DevPanel"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true -- lines up with the Gold counter
screen.Parent = player:WaitForChild("PlayerGui")

local panel = UiTheme.panel(screen)
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -space(3), 0, TOP)
panel.Size = UDim2.fromOffset(0, 0)
panel.AutomaticSize = Enum.AutomaticSize.XY
UiTheme.applyScale(panel)
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, space(1))
pad.PaddingBottom = UDim.new(0, space(1))
pad.PaddingLeft = UDim.new(0, space(2))
pad.PaddingRight = UDim.new(0, space(1))
pad.Parent = panel
local rows = Instance.new("UIListLayout")
rows.FillDirection = Enum.FillDirection.Vertical
rows.HorizontalAlignment = Enum.HorizontalAlignment.Right
rows.Padding = UDim.new(0, space(1))
rows.SortOrder = Enum.SortOrder.LayoutOrder
rows.Parent = panel

-- A row: faint caption, then its buttons, left to right.
local function row(order: number, captionText: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = captionText
	frame.LayoutOrder = order
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(0, ROW_HEIGHT)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, space(1))
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	local caption = UiTheme.text(frame, UiTheme.TextSize.Caption, UiTheme.Font.Bold, UiTheme.Strength.Faint)
	caption.LayoutOrder = 0
	caption.Size = UDim2.fromOffset(space(12), ROW_HEIGHT)
	caption.TextTruncate = Enum.TextTruncate.None
	caption.Text = captionText
	return frame
end

local function button(parent: Frame, order: number, label: string, color: Color3, command: string, kind: string?)
	local b = Instance.new("TextButton")
	b.Name = label
	b.LayoutOrder = order
	b.AutoButtonColor = false
	b.Size = UDim2.fromOffset(0, ROW_HEIGHT)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.BackgroundColor3 = UiTheme.Raised
	b.BackgroundTransparency = UiTheme.RaisedTransparency
	b.BorderSizePixel = 0
	b.FontFace = UiTheme.Font.Bold
	b.TextSize = UiTheme.TextSize.Body
	b.TextColor3 = color
	b.Text = label
	b.Parent = parent
	UiTheme.corner(b)
	local inner = Instance.new("UIPadding")
	inner.PaddingLeft = UDim.new(0, space(2))
	inner.PaddingRight = UDim.new(0, space(2))
	inner.Parent = b
	b.MouseEnter:Connect(function()
		b.BackgroundTransparency = UiTheme.RaisedHoverTransparency
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundTransparency = UiTheme.RaisedTransparency
	end)
	b.Activated:Connect(function()
		commandEvent:FireServer(command, kind)
	end)
end

local devRow = row(1, "DEV")
button(devRow, 1, `+{Config.Dev.Xp} XP`, UiTheme.Text, "Xp")
button(devRow, 2, `+{Config.Dev.Gold} Gold`, UiTheme.Gold, "Gold")

local spawnRow = row(2, "SPAWN")
for index, kind in Config.Dev.SpawnKinds do
	local color = if ZOMBIE_KINDS[kind] then UiTheme.Enemy else UiTheme.Ally
	button(spawnRow, index, KIND_LABELS[kind] or kind, color, "Spawn", kind)
end

local eventRow = row(3, "EVENT")
button(eventRow, 1, "Next event", UiTheme.Text, "NextEvent")

local hint = UiTheme.text(panel, UiTheme.TextSize.Caption, UiTheme.Font.Medium, UiTheme.Strength.Faint)
hint.LayoutOrder = 4
hint.Size = UDim2.fromOffset(0, space(4))
hint.AutomaticSize = Enum.AutomaticSize.X
hint.TextTruncate = Enum.TextTruncate.None
hint.Text = "` to use the mouse"

-- Freeing the mouse: a Modal button releases the first-person mouse lock
-- while it is visible (same trick as the menus' scrim).
local freer = Instance.new("TextButton")
freer.Name = "MouseFreer"
freer.Modal = true
freer.Visible = false
freer.BackgroundTransparency = 1
freer.Text = ""
freer.Size = UDim2.fromOffset(0, 0)
freer.Parent = screen

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= MOUSE_KEY then
		return
	end
	local free = not freer.Visible
	freer.Visible = free
	UserInputService.MouseIconEnabled = free
	hint.Text = if free then "` to lock the mouse again" else "` to use the mouse"
end)
