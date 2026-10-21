--!strict
-- The one UI design system for the whole game (owner decision 2026-10-21).
-- Every ScreenGui, BillboardGui and on-screen text reads its look from here;
-- the rules and component specs live in docs/11_UI_DESIGN.md. Change a value
-- here and every screen follows.
--
-- The six rules:
--  1. One font: Builder Sans. Weight and size carry the hierarchy.
--  2. One surface: a see-through dark panel. No thick borders, no outlines;
--     small, consistent corner rounding.
--  3. One accent: gold, only for progress and rewards (level, XP, Gold,
--     talents, the hovered card). Everything else is white at three strengths.
--  4. Colours with a fixed meaning only: green = friendly health, red = enemy
--     health (and damage you take).
--  5. Thin bars with their label above, never inside: health 8, XP 3,
--     structure 5, unit 4 pixels.
--  6. Spacing in steps of 4 pixels.

local UiTheme = {}

-- 1. Type --------------------------------------------------------------------------
local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
UiTheme.Font = table.freeze({
	Regular = Font.new(FAMILY, Enum.FontWeight.Regular),
	Medium = Font.new(FAMILY, Enum.FontWeight.Medium),
	Bold = Font.new(FAMILY, Enum.FontWeight.Bold),
	Heavy = Font.new(FAMILY, Enum.FontWeight.ExtraBold),
})
-- Text sizes in pixels (before any UIScale).
UiTheme.TextSize = table.freeze({
	Caption = 11, -- section labels (ATTRIBUTES), key hints
	Small = 12, -- secondary lines, XP text
	Body = 14,
	Value = 16, -- numbers in lists, gold count
	Title = 19, -- player name
	Heading = 24, -- panel headings
})

-- 2. Surface -----------------------------------------------------------------------
UiTheme.Surface = Color3.fromRGB(12, 14, 18)
UiTheme.SurfaceTransparency = 0.38 -- HUD pieces over the game
UiTheme.MenuTransparency = 0.18 -- full menus (more solid, easier to read)
UiTheme.TrackTransparency = 0.45 -- the empty part of a bar
UiTheme.Raised = Color3.new(1, 1, 1) -- cards and slots inside a menu: white at...
UiTheme.RaisedTransparency = 0.94 -- ...6%
UiTheme.RaisedHoverTransparency = 0.9 -- ...10% (also the "on" ability slot)
UiTheme.DisabledTransparency = 0.96 -- ...4% (locked slots)
UiTheme.Radius = 8 -- HUD pieces, slots, cards
UiTheme.RadiusLarge = 12 -- whole menus
UiTheme.ScrollBar = 3 -- scroll bar thickness (info area)
UiTheme.Scrim = Color3.new(0, 0, 0) -- dims the game behind a menu
UiTheme.ScrimTransparency = 0.5

-- 3. Colour --------------------------------------------------------------------------
UiTheme.Text = Color3.new(1, 1, 1)
-- White at three strengths, as TextTransparency values.
UiTheme.Strength = table.freeze({
	Value = 0, -- numbers, names, titles
	Label = 0.35, -- labels, descriptions
	Faint = 0.6, -- captions, locked, hints
})
UiTheme.Gold = Color3.fromRGB(245, 196, 81)
UiTheme.OnGold = Color3.fromRGB(26, 20, 8) -- text on a gold fill
-- Orange (owner 2026-10-21): only for the "Improves: ..." line on mastery and
-- upgrade tiles, so what a pick affects stands out from its gold state.
UiTheme.Improves = Color3.fromRGB(255, 150, 60)

-- 4. Meaning -------------------------------------------------------------------------
UiTheme.Ally = Color3.fromRGB(94, 211, 126) -- friendly health
UiTheme.Enemy = Color3.fromRGB(229, 83, 75) -- enemy health, damage you take

-- 5. Bars (heights in pixels) ----------------------------------------------------------
UiTheme.Bar = table.freeze({
	Health = 8,
	Xp = 3,
	Structure = 18, -- owner 2026-10-21: bigger than the MOBA-era 14, with the numbers inside
	Unit = 4,
})

-- Size ------------------------------------------------------------------------------
-- All layout numbers in UI scripts are written at 1x; every screen element is
-- drawn this much larger (owner 2026-10-21: everything felt too small).
-- Elements keep their anchor, so they grow in place.
UiTheme.Scale = 1.4 -- HUD pieces: health/abilities, Gold, minimap, banners, crosshair
UiTheme.MenuScale = 1.5 -- full menus (still shrunk to fit small screens)

-- 6. Spacing -------------------------------------------------------------------------
-- UiTheme.space(3) = 12. Use for padding, gaps and offsets.
function UiTheme.space(steps: number): number
	return steps * 4
end

-- Helpers ------------------------------------------------------------------------------

-- Draws a screen element at UiTheme.Scale (or a given scale) around its anchor.
function UiTheme.applyScale(target: GuiObject, scale: number?): UIScale
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scale or UiTheme.Scale
	uiScale.Parent = target
	return uiScale
end

function UiTheme.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or UiTheme.Radius)
	c.Parent = parent
end

-- A transparent text label in the theme font, white at the given strength.
function UiTheme.text(parent: Instance, size: number, weight: Font, strength: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = weight
	label.TextSize = size
	label.TextColor3 = UiTheme.Text
	label.TextTransparency = strength or UiTheme.Strength.Value
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
	return label
end

-- A HUD surface panel (see-through dark, rounded, no outline).
function UiTheme.panel(parent: Instance, transparency: number?, radius: number?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = UiTheme.Surface
	frame.BackgroundTransparency = transparency or UiTheme.SurfaceTransparency
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UiTheme.corner(frame, radius)
	return frame
end

export type Bar = { track: Frame, fill: Frame }

-- A thin bar: dark see-through track with a rounded fill. Set the fill's
-- Size.X.Scale (0..1) to show the amount.
function UiTheme.bar(parent: Instance, height: number, color: Color3): Bar
	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.Size = UDim2.new(1, 0, 0, height)
	track.BackgroundColor3 = UiTheme.Surface
	track.BackgroundTransparency = UiTheme.TrackTransparency
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = parent
	UiTheme.corner(track, math.ceil(height / 2))
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track
	UiTheme.corner(fill, math.ceil(height / 2))
	return { track = track, fill = fill }
end

-- A soft dark shadow behind text that floats over the game world (structure
-- names, gold popups), so it stays readable on bright sky or grass.
function UiTheme.floatingText(label: TextLabel)
	label.TextStrokeColor3 = UiTheme.Surface
	label.TextStrokeTransparency = 0.55
end

-- A circular cooldown cover for a slot: a dark wedge that sweeps away like a
-- clock hand, with the seconds left in the centre. Returns a function taking
-- the share of the cooldown still left (1 = just used, 0 = ready) and the text.
-- Built from two half-panels, each showing a rotated hard-edged gradient; a
-- CanvasGroup clips it to the slot's rounded corners.
local SHARP_HALF = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.499, 0),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(1, 1),
})

function UiTheme.radialCover(parent: GuiObject, radius: number?): (number, string) -> ()
	local group = Instance.new("CanvasGroup")
	group.Name = "Cooldown"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.ZIndex = 2
	group.Parent = parent
	UiTheme.corner(group, radius)

	local gradients: { UIGradient } = {}
	for index, side in { 1, 0 } do -- right half, then left half
		local half = Instance.new("Frame")
		half.Position = UDim2.fromScale(side * 0.5, 0)
		half.Size = UDim2.fromScale(0.5, 1)
		half.BackgroundTransparency = 1
		half.ClipsDescendants = true
		half.Parent = group
		local fill = Instance.new("Frame")
		fill.Position = UDim2.fromScale(-side, 0)
		fill.Size = UDim2.fromScale(2, 1)
		fill.BackgroundColor3 = UiTheme.Surface
		fill.BackgroundTransparency = 0.2
		fill.BorderSizePixel = 0
		fill.Parent = half
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = SHARP_HALF
		gradient.Parent = fill
		gradients[index] = gradient
	end

	local label = UiTheme.text(parent, UiTheme.TextSize.Value, UiTheme.Font.Heavy)
	label.Name = "CooldownText"
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 3
	UiTheme.floatingText(label)

	-- The wedge covers the angle [0, A] clockwise from 12 o'clock, A = left * 360.
	-- Each half shows its part of it by rotating its gradient to A (clamped to its half).
	return function(left: number, text: string)
		local angle = math.clamp(left, 0, 1) * 360
		group.Visible = angle > 0
		gradients[1].Rotation = math.min(angle, 180)
		gradients[2].Rotation = math.max(angle, 180)
		label.Text = text
	end
end

return table.freeze(UiTheme)
