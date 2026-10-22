--!strict
-- The one UI design system for the whole game (owner decision 2026-10-21;
-- blocky restyle owner 2026-10-22). Every ScreenGui, BillboardGui and
-- on-screen text reads its look from here; the rules and component specs live
-- in docs/11_UI_DESIGN.md. Change a value here and every screen follows.
--
-- The rules (blocky style, owner 2026-10-22):
--  1. Two fonts: Fredoka One for titles, names and numbers (Bold, Heavy);
--     Builder Sans Bold for body text (Regular, Medium).
--  2. Blocks: bright, solid panels with a top-to-bottom gradient, a thick dark
--     ink outline and rounded corners. Navy for HUD pieces; blue, gold, green,
--     red, light and grey blocks for menus, buttons and states.
--  3. Outlined text: white text with a dark ink outline (UiTheme.text does
--     it). Text on a light block is plain ink instead (UiTheme.inkText).
--  4. Colours with a fixed meaning: gold = progress, rewards and what you can
--     do now; green = friendly health, owned / taken and buy buttons; red =
--     enemy health, damage you take, closing and warnings.
--  5. Chunky bars with a dark outline: health 12, XP 8, structure 20, unit 6.
--  6. Spacing in steps of 4 pixels.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UiTheme = {}

-- 1. Type --------------------------------------------------------------------------
local BODY = "rbxasset://fonts/families/BuilderSans.json"
local DISPLAY = Font.fromEnum(Enum.Font.FredokaOne)
UiTheme.Font = table.freeze({
	Regular = Font.new(BODY, Enum.FontWeight.SemiBold), -- body text
	Medium = Font.new(BODY, Enum.FontWeight.Bold), -- labels
	Bold = DISPLAY, -- values, buttons
	Heavy = DISPLAY, -- headings, names
})
-- Text sizes in pixels (before any UIScale).
UiTheme.TextSize = table.freeze({
	Caption = 11, -- section labels (ATTRIBUTES), key hints
	Small = 12, -- secondary lines, XP text
	Body = 14,
	Value = 16, -- numbers in lists, gold count
	Title = 19, -- player name
	Heading = 26, -- panel headings
	Display = 34, -- menu titles on the rim
})

-- 2. Blocks --------------------------------------------------------------------------
-- Dark ink: every outline, and text on light blocks.
UiTheme.Ink = Color3.fromRGB(29, 43, 79)
-- Block fills, top colour then bottom colour (a vertical gradient).
export type FillName = "Navy" | "Blue" | "Deep" | "Sky" | "Gold" | "Green" | "Red" | "Light" | "Grey"
local FILLS: { [string]: { Color3 } } = {
	Navy = { Color3.fromRGB(50, 68, 120), Color3.fromRGB(29, 43, 79) }, -- HUD pieces, profile
	Blue = { Color3.fromRGB(99, 214, 255), Color3.fromRGB(42, 145, 236) }, -- menu body, cards, slots
	Deep = { Color3.fromRGB(78, 124, 214), Color3.fromRGB(44, 78, 162) }, -- ability slots (owner 2026-10-22: Blue too bright)
	Sky = { Color3.fromRGB(169, 240, 255), Color3.fromRGB(92, 200, 247) }, -- the panel behind a grid
	Gold = { Color3.fromRGB(255, 240, 122), Color3.fromRGB(255, 186, 26) }, -- selected, rim, pick
	Green = { Color3.fromRGB(166, 240, 74), Color3.fromRGB(70, 186, 24) }, -- owned, taken, buy
	Red = { Color3.fromRGB(255, 122, 77), Color3.fromRGB(226, 48, 28) }, -- close, warnings
	Light = { Color3.fromRGB(232, 251, 255), Color3.fromRGB(176, 232, 252) }, -- stat rows, tiles, info
	Grey = { Color3.fromRGB(205, 206, 218), Color3.fromRGB(140, 145, 166) }, -- locked, cannot afford
}
UiTheme.Fill = table.freeze(FILLS)
UiTheme.Outline = 3 -- menu blocks
UiTheme.OutlineThin = 2 -- HUD pieces, bars, small chips
UiTheme.Surface = FILLS.Navy[2] -- plain navy (tracks, portraits)
UiTheme.SurfaceTransparency = 0.08 -- HUD blocks over the game (nearly solid)
UiTheme.MenuTransparency = 0 -- full menus
UiTheme.TrackTransparency = 0.1 -- the empty part of a bar
UiTheme.Raised = Color3.new(1, 1, 1) -- soft highlights inside a navy block: white at...
UiTheme.RaisedTransparency = 0.9 -- ...10%
UiTheme.RaisedHoverTransparency = 0.82 -- ...18% (also the "on" row)
UiTheme.DisabledTransparency = 0.94 -- ...6% (locked slots)
UiTheme.Radius = 10 -- HUD pieces, slots, cards
UiTheme.RadiusLarge = 16 -- whole menus
UiTheme.ScrollBar = 4 -- scroll bar thickness (info area)
UiTheme.Scrim = Color3.fromRGB(8, 12, 28) -- dims the game behind a menu
UiTheme.ScrimTransparency = 0.5

-- 3. Colour --------------------------------------------------------------------------
UiTheme.Text = Color3.new(1, 1, 1)
-- White at three strengths, as TextTransparency values (the outline fades with it).
UiTheme.Strength = table.freeze({
	Value = 0, -- numbers, names, titles
	Label = 0.12, -- labels, descriptions
	Faint = 0.4, -- captions, locked, hints
})
UiTheme.Gold = Color3.fromRGB(255, 214, 64)
UiTheme.OnGold = UiTheme.Ink -- text on a gold fill
-- Orange (owner 2026-10-21): only for the "Improves: ..." line on mastery and
-- upgrade tiles and the info area. Dark enough to read on light blocks.
UiTheme.Improves = Color3.fromRGB(222, 104, 0)

-- 4. Meaning -------------------------------------------------------------------------
UiTheme.Ally = Color3.fromRGB(110, 222, 64) -- friendly health
UiTheme.Enemy = Color3.fromRGB(240, 72, 52) -- enemy health, damage you take

-- 5. Bars (heights in pixels) ----------------------------------------------------------
UiTheme.Bar = table.freeze({
	Health = 12,
	Xp = 8,
	Structure = 20, -- with the numbers inside (owner 2026-10-21)
	Unit = 6,
})

-- Size ------------------------------------------------------------------------------
-- All layout numbers in UI scripts are written at 1x; every screen element is
-- drawn this much larger (owner 2026-10-21: everything felt too small; 2026-10-22:
-- a little bigger again with the blocky style). Elements keep their anchor.
UiTheme.Scale = 1.5 -- HUD pieces: health/abilities, Gold, minimap, banners, crosshair
UiTheme.MenuScale = 1.5 -- full menus (still shrunk to fit small screens)
-- Fits the screen (owner 2026-10-23): those scales are right for a window
-- ReferenceHeight pixels tall; on other windows everything grows or shrinks
-- with the window's height, between MinScreenFactor and MaxScreenFactor.
UiTheme.ReferenceHeight = 900
UiTheme.MinScreenFactor = 0.6
UiTheme.MaxScreenFactor = 1.6

-- 6. Spacing -------------------------------------------------------------------------
-- UiTheme.space(3) = 12. Use for padding, gaps and offsets.
function UiTheme.space(steps: number): number
	return steps * 4
end

-- Helpers ------------------------------------------------------------------------------

-- How much larger than at ReferenceHeight the window is (clamped).
function UiTheme.screenFactor(): number
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else UiTheme.ReferenceHeight
	return math.clamp(height / UiTheme.ReferenceHeight, UiTheme.MinScreenFactor, UiTheme.MaxScreenFactor)
end

-- Calls `apply` now and again whenever the window changes size.
local resizeEvent = Instance.new("BindableEvent")
local watchedCamera: Camera? = nil
local cameraConnection: RBXScriptConnection? = nil
local function watchCamera()
	local camera = Workspace.CurrentCamera
	if camera == watchedCamera then
		return
	end
	watchedCamera = camera
	if cameraConnection then
		cameraConnection:Disconnect()
	end
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			resizeEvent:Fire()
		end)
	end
	resizeEvent:Fire()
end
watchCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
function UiTheme.onScreenResize(apply: () -> ()): RBXScriptConnection
	apply()
	return resizeEvent.Event:Connect(apply)
end

-- Draws a screen element at UiTheme.Scale (or a given scale) around its
-- anchor, times screenFactor, following the window size.
function UiTheme.applyScale(target: GuiObject, scale: number?): UIScale
	local uiScale = Instance.new("UIScale")
	local base = scale or UiTheme.Scale
	local connection = UiTheme.onScreenResize(function()
		uiScale.Scale = base * UiTheme.screenFactor()
	end)
	uiScale.Destroying:Connect(function()
		connection:Disconnect()
	end)
	uiScale.Parent = target
	return uiScale
end

function UiTheme.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or UiTheme.Radius)
	c.Parent = parent
end

-- The outline thickness that suits a text size: thin enough that letters with
-- small holes (o, e, a) stay open (owner 2026-10-22: size / 8 filled them in).
function UiTheme.outlineFor(size: number): number
	return math.clamp(size / 12, 1, 2.5)
end

-- Gives a label the dark ink outline. The outline fades with the text, so
-- fading TextTransparency (banners, popups) fades both. Safe to call twice.
function UiTheme.outlineText(label: TextLabel | TextButton, thickness: number?)
	local stroke = label:FindFirstChild("Outline")
	if not (stroke and stroke:IsA("UIStroke")) then
		local made = Instance.new("UIStroke")
		made.Name = "Outline"
		made.Color = UiTheme.Ink
		made.LineJoinMode = Enum.LineJoinMode.Round
		made.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		made.Transparency = label.TextTransparency
		made.Parent = label
		label:GetPropertyChangedSignal("TextTransparency"):Connect(function()
			made.Transparency = label.TextTransparency
		end)
		stroke = made
	end
	local outline = stroke :: UIStroke
	outline.Enabled = true
	outline.Thickness = thickness or UiTheme.outlineFor(label.TextSize)
end

-- Plain ink text without an outline, for light blocks (stat rows, info area).
function UiTheme.inkText(label: TextLabel)
	label.TextColor3 = UiTheme.Ink
	local stroke = label:FindFirstChild("Outline")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Enabled = false
	end
end

-- An outlined text label in the theme font, white at the given strength.
function UiTheme.text(parent: Instance, size: number, weight: Font, strength: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = weight
	label.TextSize = size
	label.TextColor3 = UiTheme.Text
	label.TextTransparency = strength or UiTheme.Strength.Value
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	UiTheme.outlineText(label)
	label.Parent = parent
	return label
end

-- Turns any GuiObject into a block: gradient fill, ink outline, rounded corners.
-- The outline fades with BackgroundTransparency, so fading a block's
-- background (banners, the target panel) fades its outline too.
function UiTheme.styleBlock(object: GuiObject, fill: FillName, radius: number?, thickness: number?)
	object.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient supplies the colour
	object.BorderSizePixel = 0
	UiTheme.corner(object, radius)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Fill"
	gradient.Rotation = 90
	gradient.Parent = object
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outline"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = UiTheme.Ink
	stroke.Thickness = thickness or UiTheme.Outline
	stroke.Parent = object
	local base = object.BackgroundTransparency
	local function follow()
		local share = if base >= 1 then object.BackgroundTransparency else (object.BackgroundTransparency - base) / (1 - base)
		stroke.Transparency = math.clamp(share, 0, 1)
	end
	follow()
	object:GetPropertyChangedSignal("BackgroundTransparency"):Connect(follow)
	UiTheme.setFill(object, fill)
end

-- Changes a block's fill (selected, owned, hover...).
function UiTheme.setFill(object: GuiObject, fill: FillName)
	local gradient = object:FindFirstChild("Fill")
	local colors = FILLS[fill]
	if gradient and gradient:IsA("UIGradient") and colors then
		gradient.Color = ColorSequence.new(colors[1], colors[2])
	end
end

-- Changes a block's outline: white marks the hovered or selected block.
function UiTheme.setOutline(object: GuiObject, color: Color3, thickness: number?)
	local stroke = object:FindFirstChild("Outline")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = color
		stroke.Thickness = thickness or UiTheme.Outline
	end
end

-- Hover and click feedback for a button (owner 2026-10-22): it grows a little
-- while the mouse is over it and squashes while pressed. Uses its own UIScale,
-- so do not give the button another one.
local PRESS_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
UiTheme.HoverScale = 1.06
UiTheme.PressScale = 0.93
function UiTheme.pressable(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Name = "Press"
	scale.Parent = button
	local over = false
	local function to(value: number)
		TweenService:Create(scale, PRESS_TWEEN, { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		over = true
		to(UiTheme.HoverScale)
	end)
	button.MouseLeave:Connect(function()
		over = false
		to(1)
	end)
	button.MouseButton1Down:Connect(function()
		to(UiTheme.PressScale)
	end)
	button.MouseButton1Up:Connect(function()
		to(if over then UiTheme.HoverScale else 1)
	end)
	-- A hidden button forgets its hover (it may reappear under a still mouse).
	button:GetPropertyChangedSignal("Visible"):Connect(function()
		over = false
		scale.Scale = 1
	end)
end

-- A new block frame.
function UiTheme.block(parent: Instance, fill: FillName, radius: number?, thickness: number?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 0
	frame.Parent = parent
	UiTheme.styleBlock(frame, fill, radius, thickness)
	return frame
end

-- A HUD panel: a nearly solid navy block with an outline.
function UiTheme.panel(parent: Instance, transparency: number?, radius: number?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = transparency or UiTheme.SurfaceTransparency
	frame.Parent = parent
	UiTheme.styleBlock(frame, "Navy", radius, UiTheme.OutlineThin)
	return frame
end

export type Bar = { track: Frame, fill: Frame }

-- A chunky bar: dark track with an ink outline and a glossy rounded fill. Set
-- the fill's Size.X.Scale (0..1) to show the amount.
local GLOSS_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
	ColorSequenceKeypoint.new(0.45, Color3.fromRGB(235, 235, 235)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 190, 190)),
})
function UiTheme.bar(parent: Instance, height: number, color: Color3): Bar
	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.Size = UDim2.new(1, 0, 0, height)
	track.BackgroundColor3 = UiTheme.Ink
	track.BackgroundTransparency = UiTheme.TrackTransparency
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = parent
	UiTheme.corner(track, math.ceil(height / 2))
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outline"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = UiTheme.Ink
	stroke.Thickness = if height >= 10 then UiTheme.OutlineThin else 1.5
	stroke.Parent = track
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track
	UiTheme.corner(fill, math.ceil(height / 2))
	-- Lighter on top, darker below: multiplies the fill colour.
	local gloss = Instance.new("UIGradient")
	gloss.Rotation = 90
	gloss.Color = GLOSS_COLOR
	gloss.Parent = fill
	return { track = track, fill = fill }
end

-- Text that floats over the game world (structure names, gold popups): the
-- ink outline keeps it readable on bright sky or grass. UiTheme.text already
-- adds it; this also turns off Roblox's older text stroke.
function UiTheme.floatingText(label: TextLabel)
	UiTheme.outlineText(label)
	label.TextStrokeTransparency = 1
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

function UiTheme.radialCover(parent: GuiObject, radius: number?, textSize: number?): (number, string) -> ()
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
		fill.BackgroundColor3 = UiTheme.Ink
		fill.BackgroundTransparency = 0.25
		fill.BorderSizePixel = 0
		fill.Parent = half
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = SHARP_HALF
		gradient.Parent = fill
		gradients[index] = gradient
	end

	local label = UiTheme.text(parent, textSize or UiTheme.TextSize.Title, UiTheme.Font.Heavy)
	label.Name = "CooldownText"
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 3

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
