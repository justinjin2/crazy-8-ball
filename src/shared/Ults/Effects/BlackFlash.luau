--!strict
-- Black Flash (docs/prompts/ABILITIES_PROMPT.md 7.11): the first ball the cue ball hits,
-- whoever's it is, is destroyed in a black flash, and the blast nudges the balls round it
-- toward their pockets.
--
-- * The flash: the step of the cue ball's first contact, that ball leaves the table
--   (Simulation.Ops.remove, a `removed` event that ShotJudge counts exactly as a pot for its
--   owner: the 8 by the 8's rules, a win on the legal 8 shot, a loss otherwise). A wrong first
--   ball is still a foul (ShotJudge's first contact). No contact at all: nothing happens.
-- * The blast: every object ball within Config.Ults.BlackFlash.RadiusInches of where it was
--   (the closest first) is nudged toward its closest pocket with a clean line in
--   (ChainLightning.pushTarget; the closest pocket when none is clean), rolling NudgeShare of
--   the way there (at most NudgeMaxInches), added to its motion as natural roll: the shooter's
--   at full strength, the opponent's at OpponentFactor (5.7). Never the 8 or the cue ball; at
--   most MaxOwnPerUse of the shooter's (counting the shattered ball when it is theirs) and
--   MaxOppPerUse of the opponent's.
-- * The cue ball bounces straight back from the explosion, rolling BounceInches, shortened so
--   it stops short of any pocket on its line (it never scratches because of the blast).
-- * `ult` events for the look: "flash" (ball = the shattered ball, at its centre), "slow" (the
--   hit-stop: the replay crawls through HitStopShotSeconds over HitStopSeconds more), then a
--   "nudge" per nudged ball (other = its pocket, value = its factor).
--
-- Only arithmetic and square roots, no trig and no pow; balls and pockets walked in array
-- order (ties keep the first): the server's settle and every client's replay step it to
-- identical bits. Pure Luau: must never require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)
local ChainLightning = require(script.Parent.ChainLightning)

local BlackFlash = {}

local EIGHT = 8
local R = Config.Balls.RadiusInches

local function findBall(state: any, id: number): any
	for _, b in state.balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

local function contains(list: { number }?, id: number): boolean
	if list == nil then
		return false
	end
	for _, v in list do
		if v == id then
			return true
		end
	end
	return false
end

local function onCloth(b: any): boolean
	return not b.pocketed and b.tip == nil and b.z == 0 and b.vz == 0
end

local function decel(): number
	return Config.Physics.RollingFriction * Config.Physics.Gravity
end

-- The nudge factor for ball `id`: 1 the shooter's, OpponentFactor the opponent's, 0 never
-- (the 8, the cue ball, a ball in neither list).
local function factorOf(state: any, id: number): number
	local o = state.overrides
	if o == nil or id == 0 or id == EIGHT then
		return 0
	end
	if contains(o.Targets, id) then
		return 1
	end
	if contains(o.OppTargets, id) then
		return Config.Ults.Shared.OpponentFactor
	end
	return 0
end

-- Nudge every ball in reach of (x, y), the closest first, within the caps.
local function blast(state: any, events: { any }, ops: any, x: number, y: number, ownUsed: number)
	local C = Config.Ults.BlackFlash
	local S = Config.Ults.Shared
	local reach2 = C.RadiusInches * C.RadiusInches
	local list: { { ball: any, d2: number, factor: number } } = {}
	for _, b in state.balls do
		if not onCloth(b) then
			continue
		end
		local factor = factorOf(state, b.id)
		if factor <= 0 then
			continue
		end
		local dx, dy = b.x - x, b.y - y
		local d2 = dx * dx + dy * dy
		if d2 <= reach2 then
			table.insert(list, { ball = b, d2 = d2, factor = factor })
		end
	end
	-- Closest first; equal distances keep array order (an insertion sort: stable).
	for i = 2, #list do
		local item = list[i]
		local j = i - 1
		while j >= 1 and list[j].d2 > item.d2 do
			list[j + 1] = list[j]
			j -= 1
		end
		list[j + 1] = item
	end
	local own, opp = ownUsed, 0
	for _, item in list do
		local b = item.ball
		if item.factor >= 1 then
			if own >= S.MaxOwnPerUse then
				continue
			end
			own += 1
		else
			if opp >= S.MaxOppPerUse then
				continue
			end
			opp += 1
		end
		local pocket, hx, hy, d = ChainLightning.pushTarget(state, b)
		if pocket == nil then
			continue
		end
		local roll = math.min(d * C.NudgeShare, C.NudgeMaxInches)
		local speed = math.sqrt(2 * decel() * roll) * item.factor
		local vx, vy = hx * speed, hy * speed
		b.vx += vx
		b.vy += vy
		b.wx += -vy / R
		b.wy += vx / R
		ops.emit(state, events, "nudge", b.id, pocket.id, b.x, b.y, item.factor)
	end
end

-- The cue ball rolls straight back from (x, y), BounceInches, stopping short of any pocket on
-- its line.
local function bounce(state: any, cue: any, x: number, y: number)
	local C = Config.Ults.BlackFlash
	local dx, dy = cue.x - x, cue.y - y
	local l = math.sqrt(dx * dx + dy * dy)
	if l < 1e-9 then
		return
	end
	local hx, hy = dx / l, dy / l
	local roll = C.BounceInches
	for _, p in state.geometry.pockets do
		local px, py = p.x - cue.x, p.y - cue.y
		local t = px * hx + py * hy
		local ex, ey = px - hx * t, py - hy * t
		local near = p.radius + R + C.PocketClearInches
		if t > 0 and ex * ex + ey * ey < near * near then
			roll = math.min(roll, math.max(0, t - near))
		end
	end
	local speed = math.sqrt(2 * decel() * roll)
	cue.vx, cue.vy = hx * speed, hy * speed
	cue.wx, cue.wy = -cue.vy / R, cue.vx / R
	cue.wz = 0
end

function BlackFlash.after(state: any, _dt: number, events: { any }, ops: any)
	local fx = state.fx
	if fx.flashed then
		return
	end
	for _, ev in events do
		if ev.type ~= "ballHit" or (ev.ball ~= 0 and ev.other ~= 0) then
			continue
		end
		local id = if ev.ball == 0 then ev.other else ev.ball
		local b = findBall(state, id)
		local cue = findBall(state, 0)
		if b == nil or cue == nil then
			continue
		end
		fx.flashed = true
		local x, y = b.x, b.y
		ops.remove(state, events, b, "BlackFlash")
		ops.emit(state, events, "flash", id, nil, x, y)
		-- The hit-stop: the replay crawls through HitStopShotSeconds of play over
		-- HitStopSeconds more (Match's slow-motion moments; the server waits that much more).
		local C = Config.Ults.BlackFlash
		ops.emit(state, events, "slow", id, nil, C.HitStopShotSeconds, nil, C.HitStopSeconds)
		local mine = contains(state.overrides and state.overrides.Targets, id)
		blast(state, events, ops, x, y, if mine then 1 else 0)
		if not cue.pocketed then
			bounce(state, cue, x, y)
		end
		return
	end
end

return BlackFlash
