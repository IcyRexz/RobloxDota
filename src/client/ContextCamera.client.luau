--!strict
-- Camera and mouse per place in the game (plan slice 1, owner 2026-10-23):
--   Lobby   Roblox's default third-person camera with a free mouse, so the
--           lobby's buttons can be clicked: CameraMode Classic, zoomed out to
--           at least LOBBY_MIN_ZOOM (no first person in the lobby), mouse
--           icon shown.
--   Battle  first person (StarterPlayer.CameraMode = LockFirstPerson in
--           default.project.json), crosshair in the centre, mouse icon
--           hidden (was set by Crosshair.client). Menus and the end screen
--           still show the icon while they are open.
-- The context comes from the server (GameContext.luau). Menus closing as
-- you leave the battle hide the icon (they assume first person); in the
-- lobby this script shows it again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameContext = require(ReplicatedStorage.Shared.GameContext)

local LOBBY_MIN_ZOOM = 10 -- studs from the character, the lobby's closest camera

local player = Players.LocalPlayer
local battleMode = player.CameraMode -- LockFirstPerson, from StarterPlayer
local battleMinZoom = player.CameraMinZoomDistance

local function apply()
	if GameContext.is("Battle") then
		-- Zoom limit first, so first person can pull the camera all the way in.
		player.CameraMinZoomDistance = battleMinZoom
		player.CameraMode = battleMode
		UserInputService.MouseIconEnabled = false
	else
		player.CameraMode = Enum.CameraMode.Classic
		-- A higher minimum also pushes the camera out of first person at once.
		player.CameraMinZoomDistance = math.max(LOBBY_MIN_ZOOM, battleMinZoom)
		UserInputService.MouseIconEnabled = true
	end
end
apply()
GameContext.changed:Connect(apply)

UserInputService:GetPropertyChangedSignal("MouseIconEnabled"):Connect(function()
	if not GameContext.is("Battle") and not UserInputService.MouseIconEnabled then
		UserInputService.MouseIconEnabled = true
	end
end)
