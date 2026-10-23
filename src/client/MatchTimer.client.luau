--!strict
-- Match clock and event timers (owner 2026-10-23), in the UI design system
-- (docs/11_UI_DESIGN.md), sitting on top of the minimap's top-right corner:
--   [Zombie Surge 0:32]  [12:05]
-- The clock is navy and counts up from the match start; each timed event that
-- is running gets a red pill with its name and time left, to the clock's left,
-- gone when it ends. Read from server-written Workspace attributes
-- (ZombieEvents): MatchStartedAt and Event<id>EndsAt, in server time. Once
-- the match is over (Match.luau: MatchEndedAt) the clock stops at the final
-- time and the event pills go.
-- Display only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GameContext = require(ReplicatedStorage.Shared.GameContext)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local space = UiTheme.space
local PILL_HEIGHT = space(7)

local player = Players.LocalPlayer
-- The minimap's panel; the row hangs above it and scales with it.
local minimap = player:WaitForChild("PlayerGui"):WaitForChild("Minimap"):WaitForChild("Holder") :: Frame

local row = Instance.new("Frame")
row.Name = "Timers"
row.AnchorPoint = Vector2.new(1, 1)
row.Position = UDim2.new(1, 0, 0, -space(2))
row.Size = UDim2.fromOffset(0, PILL_HEIGHT)
row.AutomaticSize = Enum.AutomaticSize.X
row.BackgroundTransparency = 1
row.Parent = minimap
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, space(2))
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = row

local function pill(order: number, fill: UiTheme.FillName): TextLabel
	local block = UiTheme.block(row, fill, UiTheme.Radius, UiTheme.OutlineThin)
	block.LayoutOrder = order
	block.Size = UDim2.fromOffset(0, PILL_HEIGHT)
	block.AutomaticSize = Enum.AutomaticSize.X
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, space(3))
	pad.PaddingRight = UDim.new(0, space(3))
	pad.Parent = block
	local label = UiTheme.text(block, UiTheme.TextSize.Value, UiTheme.Font.Heavy)
	label.Size = UDim2.fromOffset(0, PILL_HEIGHT)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextTruncate = Enum.TextTruncate.None
	return label
end

local function clock(seconds: number): string
	local whole = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local matchClock = pill(100, "Navy")

-- One pill per timed event, made up front and shown while it runs.
type EventPill = { id: string, name: string, label: TextLabel }
local eventPills: { EventPill } = {}
for index, info in Config.Events.List do
	if info.duration then
		local label = pill(index, "Red")
		local block = label.Parent :: Frame
		block.Visible = false
		table.insert(eventPills, { id = info.id, name = info.name, label = label })
	end
end

GameContext.renderStepped("Battle", function()
	local endedAt = Workspace:GetAttribute("MatchEndedAt")
	local over = type(endedAt) == "number"
	local now = if over then endedAt :: number else Workspace:GetServerTimeNow()
	local startedAt = Workspace:GetAttribute("MatchStartedAt")
	matchClock.Text = if type(startedAt) == "number" then clock(now - startedAt) else "0:00"
	for _, entry in eventPills do
		local endsAt = Workspace:GetAttribute(`Event{entry.id}EndsAt`)
		local left = if type(endsAt) == "number" and not over then endsAt - now else 0
		local block = entry.label.Parent :: Frame
		block.Visible = left > 0
		if left > 0 then
			entry.label.Text = `{entry.name} {clock(math.ceil(left))}`
		end
	end
end)
