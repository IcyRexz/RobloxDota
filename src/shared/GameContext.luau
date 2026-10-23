--!strict
-- Where the local player is (plan slice 1, docs/15_LOBBY_MATCHMAKING_PLAN.md;
-- owner 2026-10-23): "Lobby", "Battle" or "Loading". The server decides it
-- (Player attribute GameContext, written by Match.luau); this only reads it.
-- Client only (uses LocalPlayer).
--
-- UI scripts use it so battle UI never shows in the lobby and battle loops do
-- not run there:
--   GameContext.showIn(screen, "Battle")
--       for a ScreenGui the script never shows or hides itself: Enabled
--       follows the context.
--   GameContext.during("Battle", function() ... return cleanup end)
--       runs the function on entering the context and its cleanup on
--       leaving it (or at once if already inside).
--   GameContext.renderStepped("Battle", fn) / GameContext.every("Battle", s, fn)
--       a RenderStepped connection / a loop every s seconds, alive only in
--       the context.
--   GameContext.is("Battle") for input handlers and one-off checks.
-- Scripts whose ScreenGui opens and closes (menus, death and end screens)
-- keep owning Enabled and close themselves when the context is left.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

export type Context = "Lobby" | "Battle" | "Loading"

local player = Players.LocalPlayer

local function read(): Context
	local value = player:GetAttribute("GameContext")
	if value == "Battle" then
		return "Battle"
	elseif value == "Loading" then
		return "Loading"
	end
	return "Lobby" -- also before the server's first write: players start in the lobby
end

local current: Context = read()
local changedEvent = Instance.new("BindableEvent")

local GameContext = {}

-- Fires (new: Context, old: Context) after the context changes.
GameContext.changed = changedEvent.Event

function GameContext.get(): Context
	return current
end

function GameContext.is(context: Context): boolean
	return current == context
end

player:GetAttributeChangedSignal("GameContext"):Connect(function()
	local new: Context = read()
	local old: Context = current
	if new == old then
		return
	end
	current = new
	changedEvent:Fire(new, old)
end)

function GameContext.during(context: Context, start: () -> (() -> ())?)
	local cleanup: (() -> ())? = nil
	local inside = false
	local function update()
		local now = current == context
		if now == inside then
			return
		end
		inside = now
		if now then
			cleanup = start()
		elseif cleanup then
			local stop = cleanup
			cleanup = nil
			stop()
		end
	end
	GameContext.changed:Connect(update)
	update()
end

function GameContext.showIn(gui: LayerCollector, context: Context)
	local function update()
		gui.Enabled = current == context
	end
	GameContext.changed:Connect(update)
	update()
end

function GameContext.renderStepped(context: Context, step: (deltaTime: number) -> ())
	GameContext.during(context, function()
		local connection = RunService.RenderStepped:Connect(step)
		return function()
			connection:Disconnect()
		end
	end)
end

-- Calls `tick` every `seconds` while in the context (first call on entering).
function GameContext.every(context: Context, seconds: number, tick: () -> ())
	GameContext.during(context, function()
		local thread = task.spawn(function()
			while true do
				tick()
				task.wait(seconds)
			end
		end)
		return function()
			if coroutine.status(thread) ~= "dead" then
				task.cancel(thread)
			end
		end
	end)
end

return GameContext
