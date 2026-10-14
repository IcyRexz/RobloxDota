--!strict
-- Mobile Legends-style announcement banner, centred near the top of the screen:
-- a team-colored strip (the color of the team that scored) that fades out at
-- the sides, with bold white text, e.g.
--   THE RED TEAM HAS LOST THEIR INHIBITOR
--       BLUE MINIONS ARE NOW STRONGER
-- Banners queue, so two quick kills show one after another.
-- Display only: the server decides when a structure is destroyed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SHOW_SECONDS = 3
local SLIDE_IN_SECONDS = 0.25
local FADE_OUT_SECONDS = 0.4
local START_WIDTH_SCALE = 0.6 -- the strip opens out sideways from the middle

-- Strip colors (the scoring team) and the brighter text tint for team names.
local TEAM_STRIP_COLORS: { [string]: Color3 } = {
	Blue = Color3.fromRGB(30, 90, 200),
	Red = Color3.fromRGB(190, 35, 35),
}
local TEAM_TEXT_COLORS: { [string]: Color3 } = {
	Blue = Color3.fromRGB(140, 190, 255),
	Red = Color3.fromRGB(255, 130, 120),
}
local NEUTRAL_STRIP = Color3.fromRGB(40, 40, 48)
local BOLD_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local MEDIUM_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
-- The map calls it Barracks; players know it as the inhibitor.
local DISPLAY_NAMES: { [string]: string } = { Tower = "Tower", Barracks = "Inhibitor", Core = "Core" }
-- Until match teams exist (task T05), everyone is treated as Blue.
local DEFAULT_TEAM = "Blue"

local player = Players.LocalPlayer
local destroyedEvent = ReplicatedStorage:WaitForChild("StructureDestroyed") :: RemoteEvent

local function localTeam(): string
	local team = player:GetAttribute("Team")
	return if type(team) == "string" then team else DEFAULT_TEAM
end

local function teamName(team: string): string
	local color = TEAM_TEXT_COLORS[team] or Color3.new(1, 1, 1)
	return `<font color="#{color:ToHex()}">{string.upper(team)}</font>`
end

-- Banner ---------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "Announcements"
screen.ResetOnSpawn = false
screen.DisplayOrder = 10
screen.IgnoreGuiInset = false
screen.Parent = player:WaitForChild("PlayerGui")

-- Holder keeps the position/size limits; the strip inside it animates.
local holder = Instance.new("Frame")
holder.Name = "Banner"
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = UDim2.fromScale(0.5, 0.17) -- upper middle: clear of thumbs and joystick
holder.Size = UDim2.new(0.85, 0, 0, 64)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.Parent = screen
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(620, math.huge)
sizeLimit.Parent = holder

local strip = Instance.new("Frame")
strip.Name = "Strip"
strip.AnchorPoint = Vector2.new(0.5, 0.5)
strip.Position = UDim2.fromScale(0.5, 0.5)
strip.Size = UDim2.fromScale(1, 1)
strip.BorderSizePixel = 0
strip.Parent = holder

-- Solid in the middle, fading out to the sides, with a slight top-to-bottom shine.
local fade = Instance.new("UIGradient")
fade.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.25, 0.1),
	NumberSequenceKeypoint.new(0.75, 0.1),
	NumberSequenceKeypoint.new(1, 1),
})
fade.Color = ColorSequence.new(Color3.new(1, 1, 1))
fade.Parent = strip

-- A thin white line along the top and bottom edges, fading the same way.
for _, y in { 0, 1 } do
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, y)
	line.Position = UDim2.fromScale(0.5, y)
	line.Size = UDim2.new(1, 0, 0, 2)
	line.BackgroundColor3 = Color3.new(1, 1, 1)
	line.BackgroundTransparency = 0.2
	line.BorderSizePixel = 0
	line.Parent = strip
	local lineFade = Instance.new("UIGradient")
	lineFade.Transparency = fade.Transparency
	lineFade.Parent = line
end

local function newLabel(name: string, top: number, height: number, font: Font, maxTextSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.08, top)
	label.Size = UDim2.fromScale(0.84, height)
	label.FontFace = font
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.5
	label.TextScaled = true
	label.RichText = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxTextSize
	limit.Parent = label
	label.Parent = strip
	return label
end
local headline = newLabel("Headline", 0.12, 0.46, BOLD_FONT, 26)
local subline = newLabel("Subline", 0.6, 0.28, MEDIUM_FONT, 16)

local function fadeTo(alpha: number, seconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(strip, info, { BackgroundTransparency = alpha }):Play()
	for _, child in strip:GetChildren() do
		if child:IsA("TextLabel") then
			TweenService:Create(child, info, { TextTransparency = alpha, TextStrokeTransparency = 0.5 + 0.5 * alpha }):Play()
		elseif child:IsA("Frame") then
			TweenService:Create(child, info, { BackgroundTransparency = 0.2 + 0.8 * alpha }):Play()
		end
	end
end

-- Queue ----------------------------------------------------------------------

type Message = { headline: string, subline: string, stripColor: Color3 }
local queue: { Message } = {}
local showing = false

local function showNext()
	local message = table.remove(queue, 1)
	if not message then
		showing = false
		holder.Visible = false
		return
	end
	showing = true
	headline.Text = message.headline
	subline.Text = message.subline
	strip.BackgroundColor3 = message.stripColor

	fadeTo(1, 0)
	strip.Size = UDim2.fromScale(START_WIDTH_SCALE, 1)
	holder.Visible = true
	fadeTo(0, SLIDE_IN_SECONDS)
	TweenService:Create(
		strip,
		TweenInfo.new(SLIDE_IN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(1, 1) }
	):Play()

	task.delay(SHOW_SECONDS, function()
		fadeTo(1, FADE_OUT_SECONDS)
		task.delay(FADE_OUT_SECONDS, showNext)
	end)
end

local function announce(message: Message)
	table.insert(queue, message)
	if not showing then
		showNext()
	end
end

-- Structure destroyed --------------------------------------------------------

destroyedEvent.OnClientEvent:Connect(function(kind: unknown, team: unknown, killerTeam: unknown)
	if type(kind) ~= "string" or type(team) ~= "string" or type(killerTeam) ~= "string" then
		return
	end
	local name = DISPLAY_NAMES[kind]
	if not (name and TEAM_STRIP_COLORS[team]) then
		return
	end
	local ours = team == localTeam()
	local detail = if kind == "Barracks" and TEAM_STRIP_COLORS[killerTeam]
		then `{teamName(killerTeam)} MINIONS ARE NOW STRONGER`
		elseif ours then `YOUR {string.upper(name)} HAS FALLEN`
		else `ENEMY {string.upper(name)} DESTROYED`
	announce({
		headline = `THE {teamName(team)} TEAM HAS LOST THEIR {string.upper(name)}`,
		subline = detail,
		stripColor = TEAM_STRIP_COLORS[killerTeam] or NEUTRAL_STRIP,
	})
end)
