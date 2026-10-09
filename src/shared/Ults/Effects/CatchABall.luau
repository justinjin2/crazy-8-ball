--!strict
-- Catch-a-Ball (the abilities rework, designer 2026-10-08; docs/prompts/ABILITIES_REWORK_PLAN.md
-- 3): the cue ball is a catch ball for the shot, and whatever ball it hits first is caught.
--
-- * The catch: the step of the cue ball's first contact, the ball it hit leaves the table at
--   once (Simulation.Ops.remove: a `removed` event ShotJudge counts as a pot for its owner, so
--   an opponent's ball goes down for them, and hitting it first is still a wrong-ball foul).
--   The cue ball stops dead where it made the contact (the catch ball dropping to the cloth),
--   its spin and any hop gone. Whatever the caught ball passed the hit on to inside that same
--   step (a tight cluster) is put back: a catch never shoves the others.
-- * The 8 breaks free: off the shooter's legal 8 shot (the 8 is not in overrides.Targets) it
--   is never caught; the contact plays as a normal hit and the shot carries on.
-- * The moment holds for the catch (a `slow` event: HoldShotSeconds of play over HoldSeconds
--   more wall time), so everyone sees the ball open, the beam, the wobbles and the click before
--   the turn moves on.
-- * The second catch (Epic since the designer's second round, 2026-10-08): after the first
--   catch the catch ball hops to the shooter's nearest ball (overrides.Targets, never the 8)
--   within HopReachInches whose line from it stays clear of the pockets, and catches that one
--   too. It waits out the first hold where it is (a tiny back-and-forth keeps the shot in
--   motion), then slides there at HopSpeed through every ball (fx.ghost; the look draws the
--   hop), lands on the ball's own spot as it is taken off (a pot), and holds again
--   (SecondHoldShotSeconds over SecondHoldSeconds). None near: no second catch.
-- * `ult` events for the look: "catch" (ball = the caught ball, x, y = where it was, value =
--   1 the shooter's, 0 another's, other = 1 the first catch, 2 the second) or "breakfree"
--   (ball = the 8, x, y = its centre) at the first contact; "hop" (ball = the next ball, x, y
--   = its spot) with the first catch when a second follows.
--
-- Only arithmetic and square roots, balls walked in array order: the server's settle and every
-- client's replay step it to identical bits. Pure Luau: must never require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)
local Ball = require(script.Parent.Parent.Parent.Physics.Ball)

local CatchABall = {}

local EIGHT = 8

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

-- Sets a ball's motion to (vx, vy), rolling naturally.
local function rollAt(b: any, vx: number, vy: number)
	local R = Config.Balls.RadiusInches
	b.vx, b.vy, b.vz = vx, vy, 0
	b.wx, b.wy, b.wz = -vy / R, vx / R, 0
end

-- True when the segment from (ax, ay) to (bx, by) keeps a ball clear of every pocket's mouth.
local function clearOfPockets(state: any, ax: number, ay: number, bx: number, by: number): boolean
	local R = Config.Balls.RadiusInches
	local margin = Config.Ults.CatchABall.HopPocketMarginInches
	local dx, dy = bx - ax, by - ay
	local len2 = dx * dx + dy * dy
	for _, p in state.geometry.pockets do
		local along = if len2 > 1e-12
			then math.clamp(((p.x - ax) * dx + (p.y - ay) * dy) / len2, 0, 1)
			else 0
		local qx, qy = ax + dx * along - p.x, ay + dy * along - p.y
		local keep = p.radius + R + margin
		if qx * qx + qy * qy < keep * keep then
			return false
		end
	end
	return true
end

--- The ball the catch ball hops to after its first catch at (x, y): the shooter's nearest
--- (overrides.Targets, never the 8) within HopReachInches whose line is clear of the pockets,
--- or nil.
function CatchABall.nextBall(state: any, x: number, y: number): any
	local targets = state.overrides and state.overrides.Targets
	local reach = Config.Ults.CatchABall.HopReachInches
	local best, bestD2 = nil, reach * reach
	for _, b in state.balls do
		if b.id == 0 or b.id == EIGHT or b.pocketed or b.tip ~= nil or b.z ~= 0 then
			continue
		end
		if not contains(targets, b.id) then
			continue
		end
		local dx, dy = b.x - x, b.y - y
		local d2 = dx * dx + dy * dy
		if d2 < bestD2 and clearOfPockets(state, x, y, b.x, b.y) then
			best, bestD2 = b, d2
		end
	end
	return best
end

--- True when the ball the cue ball hit first may be caught: anything but the cue ball, and
--- the 8 only on the shooter's legal 8 shot (listed in overrides.Targets).
function CatchABall.catchable(state: any, id: number): boolean
	if id == 0 then
		return false
	end
	if id == EIGHT then
		local o = state.overrides
		return o ~= nil and contains(o.Targets, EIGHT)
	end
	return true
end

--- Before each step until the catch: where every ball stands and whether it is at rest, so a
--- catch can take back what the caught ball did to its neighbours inside the same step (a
--- tight cluster passes the hit on before the step ends).
function CatchABall.step(state: any, _dt: number)
	local fx = state.fx
	local hop = fx.hop
	if hop and not hop.done then
		local cue = findBall(state, 0)
		if cue == nil then
			return
		end
		local C = Config.Ults.CatchABall
		if state.time < hop.at then
			-- Waiting out the first hold: a back-and-forth of a few thousandths of an inch.
			rollAt(cue, if cue.vx > 0 then -C.HopJiggle else C.HopJiggle, 0)
			return
		end
		local dx, dy = hop.x - cue.x, hop.y - cue.y
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 1e-9 then
			rollAt(cue, dx / len * C.HopSpeed, dy / len * C.HopSpeed)
		end
		hop.moving = true
		return
	end
	if fx.caught ~= nil then
		return
	end
	local pre = fx.pre
	if pre == nil then
		pre = {}
		fx.pre = pre
	end
	for i, b in state.balls do
		local k = 3 * i
		pre[k - 2] = b.x
		pre[k - 1] = b.y
		local still = b.vx == 0 and b.vy == 0 and b.vz == 0 and not b.pocketed
		pre[k] = if still then 1 else 0
	end
end

-- Puts back every object ball that was at rest before this step and moved in it (the caught
-- ball's knock-on), and drops the contacts between them from the step's events; the cue
-- ball's own contacts stay (ShotJudge's first contact).
local function undoKnockOn(state: any, events: { any }, caught: number)
	local pre = state.fx.pre
	if pre == nil then
		return
	end
	local undone: { [number]: boolean } = {}
	for i, b in state.balls do
		local k = 3 * i
		if b.id == 0 or b.id == caught or b.pocketed or pre[k] ~= 1 then
			continue
		end
		if b.x ~= pre[k - 2] or b.y ~= pre[k - 1] or b.vx ~= 0 or b.vy ~= 0 then
			b.x, b.y = pre[k - 2], pre[k - 1]
			Ball.stop(b)
			undone[b.id] = true
		end
	end
	local i = 1
	while i <= #events do
		local ev = events[i]
		local touched = ev.type ~= "ult"
			and ev.type ~= "removed"
			and ev.ball ~= 0
			and (ev.other == nil or ev.other ~= 0)
			and (undone[ev.ball] or ev.ball == caught or (ev.other ~= nil and undone[ev.other]))
		if touched then
			table.remove(events, i)
		else
			i += 1
		end
	end
end

-- The hop's end: once the catch ball reaches (or passes) the next ball's spot, that ball is
-- caught and the catch ball sits on its spot.
local function land(state: any, dt: number, events: { any }, ops: any)
	local fx = state.fx
	local hop = fx.hop
	local cue = findBall(state, 0)
	if cue == nil or not hop.moving then
		return -- still waiting out the first hold
	end
	local C = Config.Ults.CatchABall
	local dx, dy = hop.x - cue.x, hop.y - cue.y
	local ahead = dx * cue.vx + dy * cue.vy
	local near = C.HopSpeed * dt
	if dx * dx + dy * dy > near * near and ahead > 0 then
		return
	end
	hop.done = true
	Ball.stop(cue)
	if fx.ghost then
		fx.ghost[0] = nil
	end
	local b = findBall(state, hop.id)
	if b == nil or b.pocketed then
		return -- gone meanwhile: the catch ball just stops
	end
	local bx, by = b.x, b.y
	ops.remove(state, events, b, "CatchABall")
	cue.x, cue.y = bx, by
	ops.emit(state, events, "catch", hop.id, 2, bx, by, 1)
	ops.emit(state, events, "slow", hop.id, nil, C.SecondHoldShotSeconds, nil, C.SecondHoldSeconds)
end

function CatchABall.after(state: any, dt: number, events: { any }, ops: any)
	local fx = state.fx
	local hop = fx.hop
	if hop and not hop.done then
		land(state, dt, events, ops)
		return
	end
	if fx.caught ~= nil then
		return
	end
	for _, ev in events do
		if ev.type ~= "ballHit" or (ev.ball ~= 0 and ev.other ~= 0) then
			continue
		end
		local id = if ev.ball == 0 then ev.other else ev.ball
		local b = findBall(state, id)
		local cue = findBall(state, 0)
		if b == nil or cue == nil or b.pocketed then
			continue
		end
		local C = Config.Ults.CatchABall
		if not CatchABall.catchable(state, id) then
			fx.caught = -1
			ops.emit(state, events, "breakfree", id, nil, b.x, b.y)
			return
		end
		fx.caught = id
		local bx, by = b.x, b.y
		local own = if contains(state.overrides and state.overrides.Targets, id) then 1 else 0
		ops.remove(state, events, b, "CatchABall")
		undoKnockOn(state, events, id)
		-- The catch ball drops dead where it struck: no roll, no spin (a hop lands by itself).
		Ball.stop(cue)
		ops.emit(state, events, "catch", id, 1, bx, by, own)
		ops.emit(state, events, "slow", id, nil, C.HoldShotSeconds, nil, C.HoldSeconds)
		-- The second catch: the hop to the shooter's nearest ball, after the hold.
		local nextBall = if id == EIGHT then nil else CatchABall.nextBall(state, cue.x, cue.y)
		if nextBall then
			fx.hop = {
				id = nextBall.id,
				x = nextBall.x,
				y = nextBall.y,
				at = state.time + C.HoldShotSeconds,
				moving = false,
				done = false,
			}
			fx.ghost = fx.ghost or {}
			fx.ghost[0] = true
			rollAt(cue, C.HopJiggle, 0)
			ops.emit(state, events, "hop", nextBall.id, nil, nextBall.x, nextBall.y)
		end
		return
	end
end

return CatchABall
