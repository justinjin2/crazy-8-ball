--!strict
-- Portals (docs/prompts/ABILITIES_PROMPT.md 7.9): two portals the shooter placed on the cloth
-- before the shot (overrides.Pick = { ax, ay, bx, by }, checked by Arming.pick). For the whole
-- shot, any ball (the cue ball, either player's, the 8) whose centre passes within
-- Config.Ults.Portals.InnerRadiusInches of a portal's centre comes out of the other portal's
-- centre at the same speed and heading, spin and all (Simulation.Ops.teleport: a ball it lands
-- on is struck at once, as a contact).
--
-- * The pass is found on the centre's path through each fixed step (from where it was before
--   the step to where it is after), so a fast ball cannot skip a portal between two steps.
-- * Only balls on the cloth: not dropping into a pocket, not in the air.
-- * A ball that came out of a portal cannot go into either portal again until its centre has
--   left that exit's inner circle and CooldownSeconds have passed (so a ball never bounces
--   straight back, and a loop through both slows and ends).
-- * `ult` events for the look: "enter" (ball, other = the portal gone into: 1 A, 2 B, at its
--   centre) and "exit" (ball, other = the portal come out of, at its centre), in that order in
--   the same step.
--
-- Only arithmetic and square roots, balls walked in array order, portals A then B: the
-- server's settle and every client's replay step it to identical bits. Pure Luau: must never
-- require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)

local Portals = {}

type Lock = { portal: number, at: number, out: boolean }

--- The two portals of this shot as { x, y } pairs (A, B), or nil when there is no valid pick.
function Portals.spots(state: any): ({ number }?, { number }?)
	local o = state.overrides
	local pick = o and o.Pick
	if type(pick) ~= "table" or #pick < 4 then
		return nil, nil
	end
	return { pick[1], pick[2] }, { pick[3], pick[4] }
end

-- Where each ball's centre was at the start of this step (by array index).
function Portals.step(state: any, _dt: number)
	local fx = state.fx
	local from = fx.from
	if from == nil then
		from = {}
		fx.from = from
	end
	for i, b in state.balls do
		from[2 * i - 1] = b.x
		from[2 * i] = b.y
	end
end

-- Whether the centre's path from (x0, y0) to (x1, y1) comes within r of (cx, cy).
local function passes(
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	cx: number,
	cy: number,
	r: number
): boolean
	local dx, dy = x1 - x0, y1 - y0
	local len2 = dx * dx + dy * dy
	local t = 0
	if len2 > 0 then
		t = ((cx - x0) * dx + (cy - y0) * dy) / len2
		if t < 0 then
			t = 0
		elseif t > 1 then
			t = 1
		end
	end
	local px, py = x0 + dx * t - cx, y0 + dy * t - cy
	return px * px + py * py < r * r
end

function Portals.after(state: any, _dt: number, events: { any }, ops: any)
	local a, b = Portals.spots(state)
	if a == nil or b == nil then
		return
	end
	local P = Config.Ults.Portals
	local r = P.InnerRadiusInches
	local fx = state.fx
	local from = fx.from
	if from == nil then
		return
	end
	local locks: { [number]: Lock } = fx.locks
	if locks == nil then
		locks = {}
		fx.locks = locks
	end
	local spots = { a :: { number }, b :: { number } }
	for i, ball in state.balls do
		if ball.pocketed or ball.tip ~= nil or ball.z ~= 0 or ball.vz ~= 0 then
			continue
		end
		local lock = locks[ball.id]
		if lock then
			if not lock.out then
				local exit = spots[lock.portal]
				local ex, ey = ball.x - exit[1], ball.y - exit[2]
				lock.out = ex * ex + ey * ey >= r * r
			end
			if not lock.out or state.time < lock.at + P.CooldownSeconds then
				continue
			end
			locks[ball.id] = nil
		end
		local x0, y0 = from[2 * i - 1], from[2 * i]
		if x0 == nil or (x0 == ball.x and y0 == ball.y) then
			continue -- not moving this step
		end
		for k = 1, 2 do
			local spot = spots[k]
			if passes(x0, y0, ball.x, ball.y, spot[1], spot[2], r) then
				local other = 3 - k
				local exit = spots[other]
				ops.emit(state, events, "enter", ball.id, k, spot[1], spot[2])
				ops.emit(state, events, "exit", ball.id, other, exit[1], exit[2])
				ops.teleport(state, events, ball, exit[1], exit[2])
				locks[ball.id] = { portal = other, at = state.time, out = false }
				break
			end
		end
	end
end

return Portals
