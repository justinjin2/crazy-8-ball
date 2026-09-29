--!strict
-- Ult effects: the physics side of each built ult, looked up by the name in
-- Config.Ults.Catalog[id].Effect. Simulation.step calls `step(state, dt)` of the effect named
-- in state.overrides.Effect before each fixed step, on the server's settle and on every
-- client's replay alike, so they agree exactly. Pure Luau like Physics: no Instances, no
-- Roblox types, no randomness, no hash-order iteration.
--
-- An effect must never require Physics/Simulation (Simulation requires this registry).
-- A name with no entry here (a placeholder ult) does nothing.

export type Effect = {
	step: (state: any, dt: number) -> (),
}

local Effects: { [string]: Effect } = {
	Magnet = require(script.Magnet),
}

return Effects
