--!strict
-- Lobby panels, one at a time (plan slice 2, docs/15_LOBBY_MATCHMAKING_PLAN.md;
-- owner 2026-10-23). Client only. Every way to reach a lobby function goes
-- through here: the menu bar's buttons, the courtyard's prompts and (later)
-- NPCs and stations all call PanelRouter.open(name), so there is one code path.
--   PanelRouter.register(name, { show = fn, hide = fn })   a panel's owner
--   PanelRouter.open(name)     closes the open panel first, then shows this one
--   PanelRouter.toggle(name)   open, or close if it is the open one
--   PanelRouter.close()        back to the plain lobby view
--   PanelRouter.current()      the open panel's name, or nil
--   PanelRouter.changed        fires (name?) after every change
-- Leaving the lobby (GameContext) closes whatever is open.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameContext = require(ReplicatedStorage.Shared.GameContext)

export type Panel = {
	show: () -> (),
	hide: () -> (),
}

local panels: { [string]: Panel } = {}
local openName: string? = nil
local changedEvent = Instance.new("BindableEvent")

local PanelRouter = {}

PanelRouter.changed = changedEvent.Event

function PanelRouter.register(name: string, panel: Panel)
	assert(panels[name] == nil, `PanelRouter: {name} is already registered`)
	panels[name] = panel
end

function PanelRouter.current(): string?
	return openName
end

function PanelRouter.close()
	local name = openName
	if not name then
		return
	end
	openName = nil
	panels[name].hide()
	changedEvent:Fire(nil)
end

function PanelRouter.open(name: string)
	local panel = panels[name]
	if not panel or openName == name or not GameContext.is("Lobby") then
		return
	end
	local previous = openName
	if previous then
		panels[previous].hide()
	end
	openName = name
	panel.show()
	changedEvent:Fire(name)
end

function PanelRouter.toggle(name: string)
	if openName == name then
		PanelRouter.close()
	else
		PanelRouter.open(name)
	end
end

GameContext.during("Lobby", function()
	return PanelRouter.close
end)

return PanelRouter
