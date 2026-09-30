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
--   straight back, and a loop through both slows and ends). A ball resting on a portal at the
--   strike (the kept portals of a later shot) is treated the same: in only once it has left.
-- * One of the shooter's balls coming out (overrides.Targets: the 8 only on the legal 8 shot,
--   toward the called pocket; never the cue ball or the opponent's) is turned toward the pocket
--   mouth nearest its heading, ahead of it, by at most Config.Ults.Portals.ExitSteerTan: a
--   portal lines your ball up (the step 16 buff).
-- * `ult` events for the look: "enter" (ball, other = the portal gone into: 1 A, 2 B, at its
--   centre) and "exit" (ball, other = the portal come out of, at its centre), in that order in
--   the same step.
--
-- Only arithmetic and square roots, balls walked in array order, portals A then B: the
-- server's settle and every client's replay step it to identical bits. Pure Luau: must never
-- require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)
local Magnet = require(script.Parent.Magnet)

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
		-- A ball already resting on a portal at the strike (a kept portal on a later shot of the
		-- turn, where the last shot left it) goes in only once it has left that circle and come
		-- back, as if it had just come out of it (the audit, 2026-09-29).
		local a, b = Portals.spots(state)
		if a ~= nil and b ~= nil then
			local P = Config.Ults.Portals
			local r = P.InnerRadiusInches
			local locks: { [number]: Lock } = {}
			for _, ball in state.balls do
				if ball.pocketed then
					continue
				end
				for k, spot in { a :: { number }, b :: { number } } do
					local dx, dy = ball.x - spot[1], ball.y - spot[2]
					if dx * dx + dy * dy < r * r then
						locks[ball.id] =
							{ portal = k, at = state.time - P.CooldownSeconds, out = false }
						break
					end
				end
			end
			fx.locks = locks
		end
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

local function isTarget(state: any, id: number): boolean
	local targets = state.overrides and state.overrides.Targets
	if targets == nil or id == 0 then
		return false
	end
	for _, v in targets do
		if v == id then
			return true
		end
	end
	return false
end

-- Turn `b`'s heading (velocity and spin alike) toward the pocket mouth nearest it as seen
-- from (x, y) (the exit it is about to come out of), ahead of it, by at most ExitSteerTan (the
-- 8 only toward its called pocket).
local function steer(state: any, b: any, x: number, y: number)
	local tan = Config.Ults.Portals.ExitSteerTan
	local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
	if tan <= 0 or speed < 1e-9 then
		return
	end
	local nx, ny = b.vx / speed, b.vy / speed
	local bestDot, px, py, found = 0, 0, 0, false
	for _, pocket in state.geometry.pockets do
		if b.id == 8 and pocket.id ~= state.overrides.EightPocket then
			continue
		end
		local mx, my = Magnet.mouthPoint(state.geometry, pocket)
		local ux, uy = mx - x, my - y
		local ul = math.sqrt(ux * ux + uy * uy)
		if ul < 1e-9 then
			continue
		end
		ux, uy = ux / ul, uy / ul
		local dot = nx * ux + ny * uy
		if dot > bestDot then
			bestDot, px, py, found = dot, ux, uy, true
		end
	end
	if not found then
		return
	end
	local ox, oy
	local cross = nx * py - ny * px -- > 0: the pocket is anticlockwise of the heading
	if math.abs(cross) <= tan * bestDot then
		ox, oy = px, py
	else
		local sgn = if cross > 0 then tan else -tan
		ox, oy = nx - ny * sgn, ny + nx * sgn
		local ol = math.sqrt(ox * ox + oy * oy)
		ox, oy = ox / ol, oy / ol
	end
	local c = nx * ox + ny * oy
	local s = nx * oy - ny * ox
	b.vx, b.vy = c * b.vx - s * b.vy, s * b.vx + c * b.vy
	b.wx, b.wy = c * b.wx - s * b.wy, s * b.wx + c * b.wy
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
				-- The step it leaves still starts inside the circle: free from the next one.
				continue
			end
			if state.time < lock.at + P.CooldownSeconds then
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
				if isTarget(state, ball.id) then
					steer(state, ball, exit[1], exit[2])
				end
				ops.teleport(state, events, ball, exit[1], exit[2])
				locks[ball.id] = { portal = other, at = state.time, out = false }
				break
			end
		end
	end
end

return Portals
