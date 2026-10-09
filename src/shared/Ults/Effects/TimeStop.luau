--!strict
-- Time Stop (docs/prompts/ABILITIES_PROMPT.md 7.7): the physics side of the mid-shot pause.
-- One shot in three parts, stepped the same way on the server and in every client's replay:
--
-- 1. The shot as struck. FreezeAfterSeconds after the cue ball's first contact with a ball it
--    halts (Simulation Ops.halt) at the end of that fixed step, every ball keeping its
--    motion; with no contact by TimeStopMissSeconds (a miss), it halts then (the Rare+ buff).
--    The cue ball down before the freeze, or every ball at rest: no halt, a plain shot.
-- 2. (Only if the shooter strikes again in stopped time.) `beginStrike` stores every other
--    ball's motion and stops it, and gives the cue ball the strike's seed. The cue ball alone
--    moves until it touches a ball or a cushion, drops, or stops: then it halts again, the
--    struck ball holding what the contact gave it. Up to Shared.TimeStopStrikes strikes: a
--    later one stores the struck ball's new motion with the rest, so time stays stopped for
--    every ball but the cue ball.
-- 3. `resume`: every ball gets back its stored motion (added to anything part 2 gave it), the
--    cue ball keeps its own, and the shot settles to rest.
--
-- The Rare+ buff (2026-10-08: Epic and up nearly always pot): a ball of the shooter's that the
-- cue ball touches in stopped time (overrides.Targets, the 8 only on the legal 8 shot toward
-- the called pocket) is "sent": a `sent` ult event (ball, other = its pocket, at the ball) the
-- moment it is touched, and when time resumes its stored motion is dropped and it rolls down
-- the clear line into the pocket nearest the way the strike pushed it (ChainLightning.lineUp
-- and send). With no clear line it resumes like any other ball.
--
-- The stored motion lives in state.fx (in ball array order), so the server's settle and the
-- replays agree. Pure Luau, no trig or pow.
local Config = require(script.Parent.Parent.Parent.Config)
local ChainLightning = require(script.Parent.ChainLightning)

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

local function findBall(state: any, id: number): any
	for _, b in state.balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

-- The clear line in nearest the way `b` is moving (the strike's push): the pocket's id, the
-- unit heading and the distance (ChainLightning.lineUp), or nil.
local function lineUp(state: any, b: any): (number?, number, number, number)
	if b.z ~= 0 or b.vz ~= 0 then
		return nil, 0, 0, 0
	end
	local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
	local hx, hy = 0, 0
	if speed > 1e-9 then
		hx, hy = b.vx / speed, b.vy / speed
	end
	return ChainLightning.lineUp(state, b, hx, hy)
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
		-- FreezeAfterSeconds after the first contact; with none by TimeStopMissSeconds into the
		-- shot (the strike missed), then: time stops anyway (the Rare+ buff, 2026-10-08).
		local freezeAt = if fx.contactAt ~= nil
			then fx.contactAt + S.FreezeAfterSeconds
			else S.TimeStopMissSeconds
		if state.time >= freezeAt then
			fx.frozeAt = state.time
			ops.emit(state, events, "freeze", 0, nil, nil, nil, S.FrozenSeconds)
			ops.halt(state)
		end
	elseif stage == 2 then
		local cue = cueOf(state)
		local touched = cue == nil or cue.pocketed or not moving(cue)
		local hit: number? = nil
		for _, ev in events do
			if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
				touched = true
				if hit == nil then
					hit = if ev.ball == 0 then ev.other else ev.ball
				end
			elseif (ev.type == "railHit" or ev.type == "pocket") and ev.ball == 0 then
				touched = true
			end
		end
		if touched then
			fx.stage = 2.5
			ops.emit(state, events, "strikeFrozen", 0)
			local b = if hit ~= nil then findBall(state, hit) else nil
			if b and not b.pocketed and ChainLightning.factor(state, b.id) >= 1 then
				local pocket = lineUp(state, b)
				if pocket ~= nil then
					local sent = fx.sent or {}
					sent[b.id] = true
					fx.sent = sent
					ops.emit(state, events, "sent", b.id, pocket, b.x, b.y)
				end
			end
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
	local sent = fx.sent
	for i, b in state.balls do
		if b.pocketed then
			continue
		end
		-- A sent ball rolls into its pocket instead (its clear line found again: a later strike
		-- may have moved things).
		if sent and sent[b.id] then
			local pocket, ux, uy, d = lineUp(state, b)
			if pocket ~= nil then
				ChainLightning.send(b, ux, uy, d, S.TimeStopSendArriveSpeed, 0)
				continue
			end
		end
		local v = stored and stored[i]
		if v then
			b.vx += v[1]
			b.vy += v[2]
			b.vz += v[3]
			b.wx += v[4]
			b.wy += v[5]
			b.wz += v[6]
		end
	end
	fx.stored = nil
	fx.sent = nil
	fx.stage = 3
	state.halted = nil
end

return TimeStop
