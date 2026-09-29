--!strict
-- Ult effects: the physics side of each built ult, looked up by the name in
-- Config.Ults.Catalog[id].Effect. Pure Luau like Physics: no Instances, no Roblox types, no
-- randomness, no trig or pow (only arithmetic and square roots, IEEE-exact everywhere), and
-- every list walked in array order, never hash order. The server's settle and every client's
-- replay step it the same way, so they agree to the bit.
--
-- Simulation.step calls, for the effect named in state.overrides.Effect:
--   step(state, dt)                 before each fixed step (a velocity change before anything
--                                   moves: Magnet's pull, Heat Seeker's steering)
--   after(state, dt, events, ops)   after it, with that step's own events (the contacts it
--                                   just made: the cue ball's first hit is here the step it
--                                   happens) and Simulation.Ops: remove (a ball leaves play,
--                                   counted as pocketed), teleport, halt (end this part of the
--                                   shot: Time Stop), emit (an `ult` event for the look)
--   finish(state, events, ops)      once at rest (Ghost moves the cue ball off a ball)
-- Each is optional. Per-shot scratch lives in `state.fx` (a table, fresh at every strike and
-- replay start); `state.fx.ghost` (ball id -> true) takes a ball out of every contact.
--
-- An effect must never require Physics/Simulation (Simulation requires this registry); the
-- ops come in as an argument. A name with no entry here (a placeholder ult) does nothing.

export type Effect = {
	step: ((state: any, dt: number) -> ())?,
	after: ((state: any, dt: number, events: { any }, ops: any) -> ())?,
	finish: ((state: any, events: { any }, ops: any) -> ())?,
}

local Effects: { [string]: Effect } = {
	BlackFlash = require(script.BlackFlash) :: any,
	BlackHole = require(script.BlackHole) :: any,
	ChainLightning = require(script.ChainLightning) :: any,
	EaglesEye = require(script.EaglesEye) :: any,
	Ghost = require(script.Ghost) :: any,
	GuangdongTiger = require(script.GuangdongTiger) :: any,
	HeatSeeker = require(script.HeatSeeker) :: any,
	Magnet = require(script.Magnet) :: any,
	Portals = require(script.Portals) :: any,
	SteelBall = require(script.SteelBall) :: any,
	SuperBounce = require(script.SuperBounce) :: any,
	TimeStop = require(script.TimeStop) :: any,
}

return Effects
