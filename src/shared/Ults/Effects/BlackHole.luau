--!strict
-- Black Hole (docs/prompts/ABILITIES_PROMPT.md 7.12): at the cue ball's first contact a black
-- hole opens at the contact point and, for Config.Ults.BlackHole.OpenSeconds, drags the balls
-- near it in, spiralling, and swallows them.
--
-- * The hole: the step of the cue ball's first contact, at the middle of the two centres (a
--   wrong first ball is still a foul: ShotJudge's first contact; the hole opens anyway). No
--   contact at all: nothing happens.
-- * The catch: while it is open, every object ball on the cloth within RadiusInches (the
--   shooter's) or RadiusInches x OpponentFactor (the opponent's, 5.7), the closest first, at
--   most MaxOwn of the shooter's and MaxOpp of the opponent's. Never the cue ball;
--   the 8 only on the shooter's legal 8 shot (it is in overrides.Targets then).
-- * The drag: each caught ball is taken out of every contact (state.fx.ghost) and, before each
--   step, sent straight at the hole at StartSpeed + PullAccel x (time since caught), at most
--   MaxSpeed and never past the hole, with Swirl of that speed sideways (the spiral), dropped
--   whenever the swirl would carry it off the playing area or over a pocket. Always rolling.
-- * The swallow: a caught ball within SwallowInches of the hole leaves the table
--   (Simulation.Ops.remove: a `removed` event ShotJudge counts as a pot for its owner, the 8 by
--   the 8 rules); one still out after GiveUpSeconds goes too.
-- * The cue ball is pushed gently away (PushInches straight back, stopping short of any pocket
--   on its line: BlackFlash.bounce), so it never scratches because of the hole.
-- * `ult` events for the look: "open" (ball = the first ball hit, at the hole), "pull" (a ball
--   caught, at where it was, value = its owner's factor), "swallow" (a ball gone, at the hole).
--
-- Only arithmetic and square roots, no trig and no pow; balls walked in array order (ties keep
-- the first): the server's settle and every client's replay step it to identical bits. Pure
-- Luau: must never require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)
local BlackFlash = require(script.Parent.BlackFlash)

local BlackHole = {}

local EIGHT = 8
local R = Config.Balls.RadiusInches

type Caught = { id: number, t: number, factor: number }
type Hole = { x: number, y: number, t: number, caught: { Caught } }

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

-- The owner's factor for ball `id`: 1 the shooter's (the 8 only when listed: the legal 8
-- shot), OpponentFactor the opponent's (never the 8), 0 never.
local function factorOf(state: any, id: number): number
	local o = state.overrides
	if o == nil or id == 0 then
		return 0
	end
	if contains(o.Targets, id) then
		return 1
	end
	if id ~= EIGHT and contains(o.OppTargets, id) then
		return Config.Ults.Shared.OpponentFactor
	end
	return 0
end

-- The shooter's reach (inches): RadiusInches, never over the cap.
local function reachOf(state: any): number
	local S = Config.Ults.Shared
	return math.min(
		Config.Ults.BlackHole.RadiusInches,
		S.MaxReachShare * 2 * state.geometry.halfLength
	)
end

local function isCaught(hole: Hole, id: number): boolean
	for _, c in hole.caught do
		if c.id == id then
			return true
		end
	end
	return false
end

-- Aim ball `b` at the hole: straight in at `speed` (never past it this step), Swirl of it
-- sideways unless that would leave the playing area or cross a pocket. Rolling.
local function aim(state: any, hole: Hole, b: any, speed: number, dt: number)
	local C = Config.Ults.BlackHole
	local dx, dy = hole.x - b.x, hole.y - b.y
	local r = math.sqrt(dx * dx + dy * dy)
	if r < 1e-9 then
		b.vx, b.vy, b.wx, b.wy, b.wz = 0, 0, 0, 0, 0
		return
	end
	local ux, uy = dx / r, dy / r
	local v = math.min(speed, r / dt)
	local vx, vy = ux * v, uy * v
	local side = v * C.Swirl
	local sx, sy = vx - uy * side, vy + ux * side
	-- The swirl only where its step stays on the cloth, clear of the pockets.
	local nx, ny = b.x + sx * dt, b.y + sy * dt
	local g = state.geometry
	local inside = math.abs(nx) <= g.halfLength - R and math.abs(ny) <= g.halfWidth - R
	if inside then
		for _, p in g.pockets do
			local px, py = nx - p.x, ny - p.y
			local near = p.radius + R
			if px * px + py * py < near * near then
				inside = false
				break
			end
		end
	end
	if inside then
		vx, vy = sx, sy
	end
	b.vx, b.vy = vx, vy
	b.wx, b.wy = -vy / R, vx / R
	b.wz = 0
end

-- Catch every ball in reach not yet caught, the closest first, within the caps.
local function catch(state: any, events: { any }, ops: any, hole: Hole)
	local S = Config.Ults.Shared
	local reach = reachOf(state)
	local own, opp = 0, 0
	for _, c in hole.caught do
		if c.factor >= 1 then
			own += 1
		else
			opp += 1
		end
	end
	if own >= Config.Ults.BlackHole.MaxOwn and opp >= Config.Ults.BlackHole.MaxOpp then
		return
	end
	local list: { { ball: any, d2: number, factor: number } } = {}
	for _, b in state.balls do
		if b.id == 0 or not onCloth(b) or isCaught(hole, b.id) then
			continue
		end
		local factor = factorOf(state, b.id)
		if factor <= 0 then
			continue
		end
		local r = if factor >= 1 then reach else reach * S.OpponentFactor
		local dx, dy = b.x - hole.x, b.y - hole.y
		local d2 = dx * dx + dy * dy
		if d2 <= r * r then
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
	local C = Config.Ults.BlackHole
	for _, item in list do
		local b = item.ball
		if item.factor >= 1 then
			if own >= Config.Ults.BlackHole.MaxOwn then
				continue
			end
			own += 1
		else
			if opp >= Config.Ults.BlackHole.MaxOpp then
				continue
			end
			opp += 1
		end
		table.insert(hole.caught, { id = b.id, t = state.time, factor = item.factor })
		state.fx.ghost = state.fx.ghost or {}
		state.fx.ghost[b.id] = true
		ops.emit(state, events, "pull", b.id, nil, b.x, b.y, item.factor)
		-- Moving at once: a ball caught at rest must not let the shot settle before the drag.
		aim(state, hole, b, C.StartSpeed, Config.Physics.FixedStep)
	end
end

function BlackHole.step(state: any, dt: number)
	local hole: Hole? = state.fx.hole
	if hole == nil then
		return
	end
	local C = Config.Ults.BlackHole
	for _, c in hole.caught do
		local b = findBall(state, c.id)
		if b and not b.pocketed then
			local speed = math.min(C.MaxSpeed, C.StartSpeed + C.PullAccel * (state.time - c.t))
			aim(state, hole, b, speed, dt)
		end
	end
end

function BlackHole.after(state: any, _dt: number, events: { any }, ops: any)
	local fx = state.fx
	local C = Config.Ults.BlackHole
	local hole: Hole? = fx.hole
	if hole == nil then
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
			local opened: Hole = {
				x = (b.x + cue.x) / 2,
				y = (b.y + cue.y) / 2,
				t = state.time,
				caught = {},
			}
			fx.hole = opened
			ops.emit(state, events, "open", id, nil, opened.x, opened.y)
			if not cue.pocketed then
				BlackFlash.bounce(state, cue, opened.x, opened.y, C.PushInches)
			end
			catch(state, events, ops, opened)
			return
		end
		return
	end
	-- Swallow the caught balls that reached it (or ran out of time).
	local late = state.time - hole.t > C.GiveUpSeconds
	for _, c in hole.caught do
		local b = findBall(state, c.id)
		if b == nil or b.pocketed then
			continue
		end
		local dx, dy = b.x - hole.x, b.y - hole.y
		if late or dx * dx + dy * dy <= C.SwallowInches * C.SwallowInches then
			ops.remove(state, events, b, "BlackHole")
			ops.emit(state, events, "swallow", c.id, nil, hole.x, hole.y, c.factor)
		end
	end
	if state.time - hole.t <= C.OpenSeconds then
		catch(state, events, ops, hole)
	end
end

return BlackHole
