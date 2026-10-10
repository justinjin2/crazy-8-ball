--!strict
-- Plan: what game 1 of the tutorial asks for next, read from the table as it is now
-- (docs/prompts/TUTORIAL_V2_PROMPT.md 4.4). Tutorial/Rig asks it at each of the player's turns;
-- the server shows its answers (TutorialGames), and the tools' game simulation plays them.
--
-- - aim: the aim lesson's pot (turn 2): the easiest straight pot that keeps off the
--   combination pair.
-- - pair / combo: the combination (designer, 2026-10-09): two of their balls lined up with a
--   corner pocket, the back one (a) knocked into the front one (b), which drops; combo adds the
--   cue ball's line onto a.
-- - fire: the ability lesson's pot: the cue ball close to one of their balls, that ball far
--   from its pocket (Fire Shot's long line shows it all the way in).
-- - handSpot: a ball-in-hand spot straight behind their easiest ball (the bot's jam check:
--   whether any spot lines one up); comboSpot: one straight behind the pair's back ball (where
--   the tools' simulated player drags it while the combination waits).
-- - eightGlow: the pocket that glows for the 8 ("SELECT WHICH POCKET!"); eightOpen: whether
--   the 8 can still be potted from somewhere (the bot's later visits keep it so).
-- - target: the pot a shot is aimed at (the aim help after many misses).
--
-- Pure: our physics' geometry only, no Instances, no clocks; balls walked in array order.

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Parent.Physics.Ball)
local TableGeometry = require(script.Parent.Parent.Physics.Table)
local Judge = require(script.Parent.Parent.Rules.ShotJudge)
local Placement = require(script.Parent.Parent.Rules.CuePlacement)
local Magnet = require(script.Parent.Parent.Ults.Effects.Magnet)
local Break = require(script.Parent.Break)

type Ball = Ball.Ball
type Geometry = TableGeometry.Geometry

local P = Config.Tutorial.Plan
local D = 2 * Config.Balls.RadiusInches

local Plan = {}

--- A straight pot: ball `ball` into pocket `pocket` from where the cue ball is.
export type Pot = {
	ball: number,
	pocket: number,
	angle: number, -- the cue's angle (radians)
	cut: number, -- degrees
	toGhost: number, -- cue ball to the ghost ball, inches
	toPocket: number, -- the ball to the pocket's mouth, inches
	clear: boolean, -- both lines free of other balls
	ghostX: number,
	ghostY: number,
}

--- A combination pair: `a` sent into `b`, `b` into corner pocket `pocket`.
export type Pair = {
	a: number,
	b: number,
	pocket: number,
	cut: number, -- degrees between a's line to b's ghost and b's line to the pocket
	back: number, -- a's centre to b's ghost point, inches
	toMouth: number, -- b to the pocket's mouth, inches
	gx: number, -- b's ghost point (where a's centre meets b)
	gy: number,
}

--- A combination from the cue ball: the pair, and the cue's line onto a.
export type Combo = Pair & {
	angle: number, -- the cue's angle (radians)
	cueCut: number, -- the cue ball's cut on a, degrees
	distance: number, -- cue ball to a's ghost point, inches
	ax: number, -- a's ghost point (where the cue ball's centre meets a)
	ay: number,
}

local function find(balls: { Ball }, id: number): Ball?
	for _, b in balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

local function pocketOf(geometry: Geometry, id: number): any
	for _, p in geometry.pockets do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- The distance from (px, py) to the segment (ax, ay)-(bx, by).
local function segmentGap(px: number, py: number, ax: number, ay: number, bx: number, by: number)
	local vx, vy = bx - ax, by - ay
	local len2 = vx * vx + vy * vy
	local t = if len2 > 0 then math.clamp(((px - ax) * vx + (py - ay) * vy) / len2, 0, 1) else 0
	local cx, cy = ax + vx * t, ay + vy * t
	return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

-- Whether no ball but those in `skip` lies within `width` of the segment.
local function clear(
	balls: { Ball },
	skip: { [number]: boolean },
	ax: number,
	ay: number,
	bx: number,
	by: number,
	width: number
): boolean
	for _, b in balls do
		if not b.pocketed and not skip[b.id] and segmentGap(b.x, b.y, ax, ay, bx, by) < width then
			return false
		end
	end
	return true
end

local function angleBetween(ax: number, ay: number, bx: number, by: number): number
	local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
	if la < 1e-9 or lb < 1e-9 then
		return 180
	end
	return math.deg(math.acos(math.clamp((ax * bx + ay * by) / (la * lb), -1, 1)))
end

-- Whether a ball rolling along (ux, uy) (a unit vector) can drop into pocket `p`: its line
-- within Corner/SideApproachDegrees of straight down the throat.
local function enters(p: any, ux: number, uy: number): boolean
	local tx, ty = Break.throat(p)
	local limit = if p.x == 0 then P.SideApproachDegrees else P.CornerApproachDegrees
	return ux * tx + uy * ty >= math.cos(math.rad(limit))
end

--- The straight pot of `b` into pocket `p` from (cx, cy), or nil when the ghost ball sits on
--- the cue ball or the ball's line cannot enter the pocket. A ball in the jaws is aimed
--- straight down the pocket's throat.
function Plan.pot(
	geometry: Geometry,
	balls: { Ball },
	cx: number,
	cy: number,
	b: Ball,
	p: any
): Pot?
	local mx, my = Magnet.mouthPoint(geometry, p)
	local ux, uy = mx - b.x, my - b.y
	local toPocket = math.sqrt(ux * ux + uy * uy)
	if toPocket < D then
		ux, uy = Break.throat(p)
		mx, my = b.x + ux * D, b.y + uy * D
	else
		ux, uy = ux / toPocket, uy / toPocket
		if not enters(p, ux, uy) then
			return nil
		end
	end
	local gx, gy = b.x - ux * D, b.y - uy * D
	local ax, ay = gx - cx, gy - cy
	local toGhost = math.sqrt(ax * ax + ay * ay)
	if toGhost < D * 0.5 then
		return nil
	end
	local skip = { [0] = true, [b.id] = true }
	local w = D + P.LineMarginInches
	return {
		ball = b.id,
		pocket = p.id,
		angle = math.atan2(ay, ax),
		cut = angleBetween(ax, ay, ux, uy),
		toGhost = toGhost,
		toPocket = toPocket,
		clear = clear(balls, skip, cx, cy, gx, gy, w) and clear(balls, skip, b.x, b.y, mx, my, w),
		ghostX = gx,
		ghostY = gy,
	}
end

--- Every straight pot of `group`'s balls ("eight": the 8; `pocket`: only into that one) from
--- the cue ball.
function Plan.pots(geometry: Geometry, balls: { Ball }, group: string, pocket: number?): { Pot }
	local out = {}
	local cue = find(balls, 0)
	if cue == nil or cue.pocketed then
		return out
	end
	for _, b in balls do
		if b.pocketed or b.id == 0 then
			continue
		end
		if
			(group == "eight" and b.id ~= 8) or (group ~= "eight" and Judge.group(b.id) ~= group)
		then
			continue
		end
		for _, p in geometry.pockets do
			if pocket == nil or p.id == pocket then
				local pot = Plan.pot(geometry, balls, cue.x, cue.y, b, p)
				if pot then
					table.insert(out, pot)
				end
			end
		end
	end
	return out
end

-- How hard a pot looks to a new player (lower is easier).
local function cost(pot: Pot): number
	return pot.cut + P.CostPerInch * (pot.toGhost + pot.toPocket)
end

--- The combination pairs of `group` on the table, easiest first (Config.Tutorial.Plan.Pair).
function Plan.pairs(geometry: Geometry, balls: { Ball }, group: string): { Pair }
	local C = P.Pair
	local out = {}
	for _, b in balls do
		if b.pocketed or b.id == 0 or b.id == 8 or Judge.group(b.id) ~= group then
			continue
		end
		for _, p in geometry.pockets do
			if p.x == 0 then
				continue -- corner pockets only (the designer)
			end
			local mx, my = Magnet.mouthPoint(geometry, p)
			local ux, uy = mx - b.x, my - b.y
			local toMouth = math.sqrt(ux * ux + uy * uy)
			if toMouth > C.FrontMaxInches or toMouth < D then
				continue
			end
			ux, uy = ux / toMouth, uy / toMouth
			if
				not enters(p, ux, uy)
				or not clear(balls, { [0] = true, [b.id] = true }, b.x, b.y, mx, my, D)
			then
				continue
			end
			local gx, gy = b.x - ux * D, b.y - uy * D
			for _, a in balls do
				if a.pocketed or a.id == 0 or a.id == b.id or Judge.group(a.id) ~= group then
					continue
				end
				local wx, wy = gx - a.x, gy - a.y
				local back = math.sqrt(wx * wx + wy * wy)
				if back > C.BackMaxInches then
					continue
				end
				local cut = if back < 1e-6 then 0 else angleBetween(wx, wy, ux, uy)
				if cut > C.MaxCutDegrees then
					continue
				end
				local skip = { [0] = true, [a.id] = true, [b.id] = true }
				if back > 0.05 and not clear(balls, skip, a.x, a.y, gx, gy, D) then
					continue
				end
				table.insert(out, {
					a = a.id,
					b = b.id,
					pocket = p.id,
					cut = cut,
					back = back,
					toMouth = toMouth,
					gx = gx,
					gy = gy,
				})
			end
		end
	end
	table.sort(out, function(x, y)
		local cx = x.cut + x.back * C.CostPerBackInch + x.toMouth * P.CostPerInch
		local cy = y.cut + y.back * C.CostPerBackInch + y.toMouth * P.CostPerInch
		if cx ~= cy then
			return cx < cy
		end
		return x.a * 100 + x.b < y.a * 100 + y.b
	end)
	return out
end

--- The combination to play from where the cue ball is: the easiest pair with a clear line onto
--- its back ball and a cut on it no wider than Pair.CueMaxCutDegrees; nil when there is none.
function Plan.combo(geometry: Geometry, balls: { Ball }, group: string): Combo?
	local C = P.Pair
	local cue = find(balls, 0)
	if cue == nil or cue.pocketed then
		return nil
	end
	for _, pair in Plan.pairs(geometry, balls, group) do
		local a = find(balls, pair.a) :: Ball
		local wx, wy = pair.gx - a.x, pair.gy - a.y
		local len = math.sqrt(wx * wx + wy * wy)
		if len < 1e-6 then
			local b = find(balls, pair.b) :: Ball
			wx, wy = b.x - a.x, b.y - a.y
			len = math.sqrt(wx * wx + wy * wy)
		end
		wx, wy = wx / len, wy / len
		local gax, gay = a.x - wx * D, a.y - wy * D
		local cx, cy = gax - cue.x, gay - cue.y
		local distance = math.sqrt(cx * cx + cy * cy)
		if distance < D * 0.5 or distance > C.CueMaxInches then
			continue
		end
		local cueCut = angleBetween(cx, cy, wx, wy)
		if cueCut > C.CueMaxCutDegrees then
			continue
		end
		local skip = { [0] = true, [pair.a] = true }
		if not clear(balls, skip, cue.x, cue.y, gax, gay, D + P.LineMarginInches) then
			continue
		end
		local combo = table.clone(pair) :: any
		combo.angle = math.atan2(cy, cx)
		combo.cueCut = cueCut
		combo.distance = distance
		combo.ax, combo.ay = gax, gay
		return combo :: Combo
	end
	return nil
end

--- The aim lesson's pot: the easiest clear pot with a cut up to AimMaxCutDegrees and the cue
--- ball within AimMaxInches of the ghost ball, keeping off the combination pair's balls (a
--- ball's width and AvoidMarginInches more) so that lesson can follow; the easiest such pot
--- that does not, when none does. Nil when there is no pot that easy.
function Plan.aim(geometry: Geometry, balls: { Ball }, group: string): Pot?
	local avoid: { Ball } = {}
	local pair = Plan.pairs(geometry, balls, group)[1]
	if pair then
		avoid = { find(balls, pair.a) :: Ball, find(balls, pair.b) :: Ball }
	end
	local cue = find(balls, 0)
	if cue == nil or cue.pocketed then
		return nil
	end
	-- Whether a pot's ball is one of the pair, or its lines pass near one.
	local function touchesPair(pot: Pot): boolean
		local b = find(balls, pot.ball) :: Ball
		local mx, my = Magnet.mouthPoint(geometry, pocketOf(geometry, pot.pocket))
		local near = D + P.AvoidMarginInches
		for _, o in avoid do
			if
				o.id == pot.ball
				or segmentGap(o.x, o.y, cue.x, cue.y, pot.ghostX, pot.ghostY) < near
				or segmentGap(o.x, o.y, b.x, b.y, mx, my) < near
			then
				return true
			end
		end
		return false
	end
	local best, bestCost, fallback, fallbackCost = nil, math.huge, nil, math.huge
	for _, pot in Plan.pots(geometry, balls, group) do
		if not pot.clear or pot.cut > P.AimMaxCutDegrees or pot.toGhost > P.AimMaxInches then
			continue
		end
		local c = cost(pot)
		if not touchesPair(pot) and c < bestCost then
			best, bestCost = pot, c
		end
		if c < fallbackCost then
			fallback, fallbackCost = pot, c
		end
	end
	return best or fallback
end

--- The pots a new player might pick, easiest first: the clear ones up to MaxCutDegrees, else
--- any (all blocked).
function Plan.choices(geometry: Geometry, balls: { Ball }, group: string): { Pot }
	local list = {}
	for _, pot in Plan.pots(geometry, balls, group) do
		if pot.clear and pot.cut <= P.MaxCutDegrees then
			table.insert(list, pot)
		end
	end
	if #list == 0 then
		for _, pot in Plan.pots(geometry, balls, group) do
			if pot.cut <= P.MaxCutDegrees then
				table.insert(list, pot)
			end
		end
	end
	table.sort(list, function(a, b)
		local ca, cb = cost(a), cost(b)
		if ca ~= cb then
			return ca < cb
		end
		return a.ball * 10 + a.pocket < b.ball * 10 + b.pocket
	end)
	return list
end

--- The ability lesson's pot: a clear pot up to Fire.MaxCutDegrees, the cue ball close to the
--- ball and the ball far from its pocket scoring best. Nil when there is none.
function Plan.fire(geometry: Geometry, balls: { Ball }, group: string): Pot?
	local F = P.Fire
	local best, bestScore = nil, -math.huge
	for _, pot in Plan.pots(geometry, balls, group) do
		if pot.clear and pot.cut <= F.MaxCutDegrees then
			local score = math.min(pot.toPocket, F.FarInches) * F.PerFarInch
				- pot.toGhost * F.PerNearInch
				- pot.cut * F.PerCutDegree
			if score > bestScore then
				best, bestScore = pot, score
			end
		end
	end
	return best
end

--- Whether `pot` is a good ability setup now (its ball within Fire.GoodInches of the cue ball).
function Plan.fireGood(pot: Pot?): boolean
	return pot ~= nil and pot.toGhost <= P.Fire.GoodInches
end

--- A ball-in-hand spot straight behind the easiest of their balls (the 8 into `called`
--- once theirs are gone), Hand.BackInches back from its ghost ball, on a legal spot with a
--- clear line. Nil when no spot is free.
function Plan.handSpot(
	geometry: Geometry,
	balls: { Ball },
	group: string,
	called: number?
): (number?, number?)
	local targets = {}
	for _, b in balls do
		if not b.pocketed and b.id ~= 0 and b.id ~= 8 and Judge.group(b.id) == group then
			table.insert(targets, b)
		end
	end
	local eightOnly = #targets == 0
	if eightOnly then
		local eight = find(balls, 8)
		if eight and not eight.pocketed then
			table.insert(targets, eight)
		end
	end
	local best, bx, by = math.huge, nil, nil
	for _, b in targets do
		for _, p in geometry.pockets do
			if eightOnly and called ~= nil and p.id ~= called then
				continue
			end
			local mx, my = Magnet.mouthPoint(geometry, p)
			local skip = { [0] = true, [b.id] = true }
			if not clear(balls, skip, b.x, b.y, mx, my, D) then
				continue
			end
			local ux, uy = mx - b.x, my - b.y
			local len = math.sqrt(ux * ux + uy * uy)
			if len < D then
				ux, uy = Break.throat(p)
			else
				ux, uy = ux / len, uy / len
				if not enters(p, ux, uy) then
					continue
				end
			end
			local gx, gy = b.x - ux * D, b.y - uy * D
			for _, back in P.Hand.BackInches do
				local x, y = gx - ux * back, gy - uy * back
				if
					Placement.valid(balls, geometry, x, y, false)
					and clear(balls, skip, x, y, gx, gy, D)
				then
					local c = (len + back) * P.Hand.CostPerInch
					if c < best then
						best, bx, by = c, x, y
					end
					break
				end
			end
		end
	end
	return bx, by
end

--- A ball-in-hand spot that lines up the combination: straight behind the easiest pair's
--- back ball on its line to the front ball's ghost point (a straight hit sends it in),
--- Hand.BackInches back, on a legal spot with a clear line. Nil when there is no pair or spot.
function Plan.comboSpot(geometry: Geometry, balls: { Ball }, group: string): (number?, number?)
	for _, pair in Plan.pairs(geometry, balls, group) do
		local a = find(balls, pair.a) :: Ball
		local wx, wy = pair.gx - a.x, pair.gy - a.y
		local len = math.sqrt(wx * wx + wy * wy)
		if len < 1e-6 then
			local b = find(balls, pair.b) :: Ball
			wx, wy = b.x - a.x, b.y - a.y
			len = math.sqrt(wx * wx + wy * wy)
		end
		wx, wy = wx / len, wy / len
		local gax, gay = a.x - wx * D, a.y - wy * D
		local skip = { [0] = true, [pair.a] = true }
		for _, back in P.Hand.BackInches do
			local x, y = gax - wx * back, gay - wy * back
			if
				Placement.valid(balls, geometry, x, y, false)
				and clear(balls, skip, x, y, gax, gay, D + P.LineMarginInches)
			then
				return x, y
			end
		end
	end
	return nil, nil
end

--- The pocket that glows for the 8: the easiest pot of the 8 from the cue ball (a cut up to
--- EightGlowMaxCutDegrees), else the 8's own pocket (Break.eightPocket; always with ball in
--- hand, where the cue ball can go anywhere). Nil when the 8 is down.
function Plan.eightGlow(geometry: Geometry, balls: { Ball }, hand: boolean): number?
	if not hand then
		local lesson = Break.lesson(geometry, balls, "eight", false, P.EightGlowMaxCutDegrees)
		if lesson then
			return lesson.pocket
		end
	end
	return Break.eightPocket(geometry, balls)
end

--- Whether the 8 can still be potted from somewhere: a pocket its line can enter, clear of
--- the other balls, with the spot the cue ball must hit it from (its ghost ball) on the cloth
--- and free. False when the 8 is down.
function Plan.eightOpen(geometry: Geometry, balls: { Ball }): boolean
	local eight = find(balls, 8)
	if eight == nil or eight.pocketed then
		return false
	end
	local R = D / 2
	local skip = { [0] = true, [8] = true }
	for _, p in geometry.pockets do
		local mx, my = Magnet.mouthPoint(geometry, p)
		local ux, uy = mx - eight.x, my - eight.y
		local len = math.sqrt(ux * ux + uy * uy)
		if len < D then
			ux, uy = Break.throat(p)
		else
			ux, uy = ux / len, uy / len
			if not enters(p, ux, uy) or not clear(balls, skip, eight.x, eight.y, mx, my, D) then
				continue
			end
		end
		local gx, gy = eight.x - ux * D, eight.y - uy * D
		if math.abs(gx) > geometry.halfLength - R or math.abs(gy) > geometry.halfWidth - R then
			continue -- the ghost ball would sit inside a cushion
		end
		local free = true
		for _, b in balls do
			if not b.pocketed and not skip[b.id] then
				local gap = math.sqrt((b.x - gx) ^ 2 + (b.y - gy) ^ 2)
				if gap < D + P.LineMarginInches then
					free = false
				end
			end
		end
		if free then
			return true
		end
	end
	return false
end

--- The pot a shot at `angle` is aimed at: the player's pot (the 8 into `called` once their
--- group is cleared) whose line is nearest the shot's, within TargetDegrees. Nil when none.
function Plan.target(
	geometry: Geometry,
	balls: { Ball },
	group: string,
	called: number?,
	angle: number
): Pot?
	local onEight = Judge.eligible(balls, group :: any)
	local list = if onEight
		then Plan.pots(geometry, balls, "eight", called)
		else Plan.pots(geometry, balls, group)
	local best, bestOff = nil, math.rad(P.TargetDegrees)
	for _, pot in list do
		local off = math.abs((pot.angle - angle + math.pi) % (2 * math.pi) - math.pi)
		if off < bestOff then
			best, bestOff = pot, off
		end
	end
	return best
end

return Plan
