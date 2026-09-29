--!strict
-- Time Stop (docs/prompts/ABILITIES_PROMPT.md 7.7): the physics side of the mid-shot pause.
-- One shot in three parts, stepped the same way on the server and in every client's replay:
--
-- 1. The shot as struck. FreezeAfterSeconds after the cue ball's first contact with a ball it
--    halts (Simulation Ops.halt) at the end of that fixed step, every ball keeping its
--    motion. No first contact, or the cue ball down before the freeze: no halt, a plain shot.
-- 2. (Only if the shooter strikes again in stopped time.) `beginStrike` stores every other
--    ball's motion and stops it, and gives the cue ball the second strike's seed. The cue ball
--    alone moves until it touches a ball or a cushion, drops, or stops: then it halts again,
--    the struck ball holding what the contact gave it.
-- 3. `resume`: every ball gets back its stored motion (added to anything part 2 gave it), the
--    cue ball keeps its own, and the shot settles to rest.
--
-- The stored motion lives in state.fx (in ball array order), so the server's settle and the
-- replays agree. Pure Luau, no trig or pow.
local Config = require(script.Parent.Parent.Parent.Config)

local TimeStop = {}

local S = Config.Ults.Shared

local function cueOf(state: any): any
	for _, b in state.balls do
		if b.id == 0 then
			return b
		end
	end
	return nil
end

local function moving(b: any): boolean
	if b.pocketed then
		return b.falling
	end
	return b.vx ~= 0 or b.vy ~= 0 or b.wx ~= 0 or b.wy ~= 0 or b.z > 0 or b.vz ~= 0
end

function TimeStop.after(state: any, _dt: number, events: { any }, ops: any)
	local fx = state.fx
	local stage = fx.stage or 1
	if stage == 1 then
		if fx.cancelled or fx.frozeAt then
			return
		end
		local cue = cueOf(state)
		if cue == nil or cue.pocketed then
			fx.cancelled = true -- the cue ball dropped before the freeze
			return
		end
		if fx.contactAt == nil then
			for _, ev in events do
				if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
					fx.contactAt = ev.t
					break
				end
			end
		end
		if fx.contactAt ~= nil and state.time >= fx.contactAt + S.FreezeAfterSeconds then
			fx.frozeAt = state.time
			ops.emit(state, events, "freeze", 0, nil, nil, nil, S.FrozenSeconds)
			ops.halt(state)
		end
	elseif stage == 2 then
		local cue = cueOf(state)
		local touched = cue == nil or cue.pocketed or not moving(cue)
		for _, ev in events do
			if
				(ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0))
				or ((ev.type == "railHit" or ev.type == "pocket") and ev.ball == 0)
			then
				touched = true
			end
		end
		if touched then
			fx.stage = 2.5
			ops.emit(state, events, "strikeFrozen", 0)
			ops.halt(state)
		end
	end
end

--- Whether a halted state is Time Stop's freeze (part 1 done, waiting for a second strike).
function TimeStop.isFrozen(state: any): boolean
	return state.fx ~= nil and state.fx.frozeAt ~= nil and (state.fx.stage or 1) == 1
end

--- Part 2 begins: every ball but the cue ball stops (its motion stored), and the cue ball
--- takes `seed` (the second strike's velocity and spin, quantised by the server).
function TimeStop.beginStrike(state: any, seed: any)
	local fx = state.fx
	local stored = {}
	for i, b in state.balls do
		if b.id ~= 0 and not b.pocketed then
			stored[i] = { b.vx, b.vy, b.vz, b.wx, b.wy, b.wz }
			b.vx, b.vy, b.vz, b.wx, b.wy, b.wz = 0, 0, 0, 0, 0, 0
		end
	end
	fx.stored = stored
	fx.stage = 2
	local cue = cueOf(state)
	if cue then
		cue.vx, cue.vy, cue.vz, cue.z = seed.vx, seed.vy, seed.vz or 0, 0
		cue.wx, cue.wy, cue.wz = seed.wx, seed.wy, seed.wz
	end
	state.halted = nil
end

--- Part 3: time resumes. Every stored motion is added back; then the shot settles on.
function TimeStop.resume(state: any)
	local fx = state.fx
	local stored = fx.stored
	if stored then
		for i, b in state.balls do
			local v = stored[i]
			if v and not b.pocketed then
				b.vx += v[1]
				b.vy += v[2]
				b.vz += v[3]
				b.wx += v[4]
				b.wy += v[5]
				b.wz += v[6]
			end
		end
		fx.stored = nil
	end
	fx.stage = 3
	state.halted = nil
end

return TimeStop
