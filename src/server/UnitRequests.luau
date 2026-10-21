--!strict
-- Lets other server scripts ask Minions.server (a Script, so it cannot be
-- required) to spawn a unit. Used by DevTools for the developer panel.
-- Requests carry only a team, a MinionStats kind and a ground position; the
-- caller checks them first, and Minions ignores kinds it does not know.

local UnitRequests = {}

local spawnRequested = Instance.new("BindableEvent")
-- Fires (team: string, kind: string, position: Vector3).
UnitRequests.SpawnRequested = spawnRequested.Event

function UnitRequests.spawn(team: string, kind: string, position: Vector3)
	spawnRequested:Fire(team, kind, position)
end

return UnitRequests
