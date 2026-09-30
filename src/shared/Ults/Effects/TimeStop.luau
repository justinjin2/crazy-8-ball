--!strict
-- Time Stop (docs/prompts/ABILITIES_PROMPT.md 7.7): the physics side of the mid-shot pause.
-- One shot in three parts, stepped the same way on the server and in every client's replay:
--
-- 1. The shot as struck. FreezeAfterSeconds after the cue ball's first contact with a ball it
--    halts (Simulation Ops.halt) at the end of that fixed step, every ball keeping its
--    motion. No first contact, or the cue ball down before the freeze: no halt, a plain shot.
-- 2. (Only if the shooter strikes again in stopped time.) `beginStrike` stores every other
--    ball's motion and stops it, and gives the cue ball the strike's seed. The cue ball alone
--    moves until it touches a ball or a cushion, drops, or stops: then it halts again, the
--    struck ball holding what the contact gave it. Up to Shared.TimeStopStrikes strikes: a
--    later one stores the struck ball's new motion with the rest, so time stays stopped for
--    every ball but the cue ball.
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

--- Whether a halted state is Time Stop's freeze waiting for a strike: part 1 done, or a
--- strike's part done with strikes left.
function TimeStop.isFrozen(state: any): boolean
	local fx = state.fx
	if fx == nil or fx.frozeAt == nil then
		return false
	end
	local stage = fx.stage or 1
	return stage == 1 or (stage == 2.5 and (fx.strikes or 0) < S.TimeStopStrikes)
end

--- A strike's part begins: every ball but the cue ball stops (its motion stored), and the cue
--- ball takes `seed` (the strike's velocity and spin, quantised by the server).
function TimeStop.beginStrike(state: any, seed: any)
	local fx = state.fx
	local stored = fx.stored or {}
	for i, b in state.balls do
		if b.id ~= 0 and not b.pocketed then
			local v = stored[i]
			if v then
				v[1] += b.vx
				v[2] += b.vy
				v[3] += b.vz
				v[4] += b.wx
				v[5] += b.wy
				v[6] += b.wz
			else
				stored[i] = { b.vx, b.vy, b.vz, b.wx, b.wy, b.wz }
			end
			b.vx, b.vy, b.vz, b.wx, b.wy, b.wz = 0, 0, 0, 0, 0, 0
		end
	end
	fx.stored = stored
	fx.strikes = (fx.strikes or 0) + 1
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
