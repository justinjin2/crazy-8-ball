--!strict
-- Break: the tutorial's rigged rack and break (docs/prompts/TUTORIAL_PROMPT.md step 4; the
-- designer, 2026-10-03). Game 1 opens on a fixed rack (Config.Tutorial.Break.Seed) and the
-- player's break is always the same shot (cue ball spot, angle, full power), found offline by
-- tools/tutorial_break.luau: it pots exactly 3 solids (no stripe, no 8, no scratch) and leaves a
-- 4th solid with an easy straight shot into a corner pocket, the 8 close to a pocket.
--
-- Pure: our physics only, no Instances, no clocks. The server plays the shot in MatchEngine;
-- this module is shared by the search tool, the test and the lesson that follows (`lesson`).

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Parent.Physics.Ball)
local Rack = require(script.Parent.Parent.Physics.Rack)
local Simulation = require(script.Parent.Parent.Physics.Simulation)
local TableGeometry = require(script.Parent.Parent.Physics.Table)
local Judge = require(script.Parent.Parent.Rules.ShotJudge)
local Placement = require(script.Parent.Parent.Rules.CuePlacement)
local ShotInput = require(script.Parent.Parent.ShotInput)

type Ball = Ball.Ball

local B = Config.Tutorial.Break
local D = 2 * Config.Balls.RadiusInches

local Break = {}

export type Shot = { seed: number, cueX: number, cueY: number, angle: number, power: number }

export type Result = {
	balls: { Ball },
	judgement: any,
	scratch: boolean,
	pocketed: { number },
}

export type Lesson = {
	ball: number, -- the solid to pot
	pocket: number, -- into this pocket (its id)
	angle: number, -- the cue angle that pots it (radians)
	cutDegrees: number,
	distance: number, -- cue ball to the object ball, inches
}

--- The configured break (Config.Tutorial.Break).
function Break.shot(): Shot
	return { seed = B.Seed, cueX = B.CueX, cueY = B.CueY, angle = B.Angle, power = B.Power }
end

--- The rack the tutorial's game opens on (its cue ball where the break is played from).
function Break.rack(geometry: TableGeometry.Geometry, shot: Shot?): { Ball }
	local s = shot or Break.shot()
	local balls = Rack.newGame(geometry, s.seed)
	for _, b in balls do
		if b.id == 0 then
			b.x, b.y = s.cueX, s.cueY
		end
	end
	return balls
end

--- Plays `shot` on its rack in our physics and judges it as a break, exactly the server's path
--- (MatchEngine.acceptShot: the shot read by ShotInput, the strike's seed quantised, settled).
function Break.play(geometry: TableGeometry.Geometry, shot: Shot): Result
	local sim = Simulation.newState(geometry, Rack.newGame(geometry, shot.seed))
	Placement.set(sim, 0, shot.cueX, shot.cueY)
	local before = Ball.cloneList(sim.balls)
	local input = ShotInput.validate({
		angle = shot.angle,
		power = shot.power,
		spin = { x = 0, y = 0 },
	}, nil) :: any
	local strike = Simulation.strike(sim, input)
	for _, b in sim.balls do
		if b.id == 0 then
			ShotInput.quantiseSeed(b)
		end
	end
	local outcome = Simulation.settle(sim, { strike })
	local j = Judge.resolve(before, outcome, {}, 1, true, nil, false)
	local pocketed, scratch = {}, false
	for _, b in outcome.finalBalls do
		if b.pocketed then
			if b.id == 0 then
				scratch = true
			else
				table.insert(pocketed, b.id)
			end
		end
	end
	return { balls = outcome.finalBalls, judgement = j, scratch = scratch, pocketed = pocketed }
end

-- The point a ball aims at to drop in pocket `p` (the middle of its mouth).
local function mouth(geometry: TableGeometry.Geometry, p: any): (number, number)
	local hl, hw = geometry.halfLength, geometry.halfWidth
	local sy = if p.y > 0 then 1 else -1
	if p.x == 0 then
		return 0, sy * hw
	end
	local sx = if p.x > 0 then 1 else -1
	local half = Config.Table.CornerMouthInches / math.sqrt(2) / 2
	return sx * (hl - half), sy * (hw - half)
end

-- The distance from (px, py) to the segment (ax, ay)-(bx, by).
local function segmentGap(px: number, py: number, ax: number, ay: number, bx: number, by: number)
	local vx, vy = bx - ax, by - ay
	local len2 = vx * vx + vy * vy
	local t = if len2 > 0 then math.clamp(((px - ax) * vx + (py - ay) * vy) / len2, 0, 1) else 0
	local cx, cy = ax + vx * t, ay + vy * t
	return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

-- Whether nothing but `skip` (and the cue ball) lies within a ball's width of the segment.
local function clear(balls: { Ball }, skip: number, ax: number, ay: number, bx: number, by: number)
	for _, b in balls do
		if not b.pocketed and b.id ~= 0 and b.id ~= skip then
			if segmentGap(b.x, b.y, ax, ay, bx, by) < D then
				return false
			end
		end
	end
	return true
end

--- The direction straight down pocket `p`'s throat, into the pocket: 45 degrees for a corner,
--- straight across for a side pocket.
function Break.throat(p: any): (number, number)
	local sy = if p.y > 0 then 1 else -1
	if p.x == 0 then
		return 0, sy
	end
	local sx = if p.x > 0 then 1 else -1
	local k = 1 / math.sqrt(2)
	return sx * k, sy * k
end

--- The easiest straight pot of a ball of `group` ("eight": the 8 itself) from the cue ball
--- into a pocket (corner pockets only when `cornersOnly`): a clear line from the cue ball to
--- the ghost ball and from the ball to the pocket, a cut no wider than `maxCut` (default
--- LessonMaxCutDegrees), the cheapest; nil when there is none.
function Break.lesson(
	geometry: TableGeometry.Geometry,
	balls: { Ball },
	group: string,
	cornersOnly: boolean?,
	maxCut: number?
): Lesson?
	local cue = nil
	for _, b in balls do
		if b.id == 0 and not b.pocketed then
			cue = b
		end
	end
	if cue == nil then
		return nil
	end
	local best: Lesson? = nil
	local bestCost = math.huge
	local widest = maxCut or B.LessonMaxCutDegrees
	for _, b in balls do
		if b.pocketed or (if group == "eight" then b.id ~= 8 else Judge.group(b.id) ~= group) then
			continue
		end
		for _, p in geometry.pockets do
			if cornersOnly and p.x == 0 then
				continue
			end
			local mx, my = mouth(geometry, p)
			local ux, uy = mx - b.x, my - b.y
			local toPocket = math.sqrt(ux * ux + uy * uy)
			if toPocket < D then
				-- A ball in the jaws: past or at the mouth's middle that line points anywhere,
				-- and only a hit straight down the pocket's throat reaches it.
				ux, uy = Break.throat(p)
			else
				ux, uy = ux / toPocket, uy / toPocket
			end
			local gx, gy = b.x - ux * D, b.y - uy * D
			local ax, ay = gx - cue.x, gy - cue.y
			local toGhost = math.sqrt(ax * ax + ay * ay)
			if toGhost < D then
				continue
			end
			local cosCut = (ax * ux + ay * uy) / toGhost
			local cut = math.deg(math.acos(math.clamp(cosCut, -1, 1)))
			if cut > widest then
				continue
			end
			if
				not clear(balls, b.id, cue.x, cue.y, gx, gy)
				or not clear(balls, b.id, b.x, b.y, mx, my)
			then
				continue
			end
			local cost = cut + toGhost * B.LessonCostPerInch + toPocket * B.LessonCostPerInch
			if cost < bestCost then
				bestCost = cost
				best = {
					ball = b.id,
					pocket = p.id,
					angle = math.atan2(ay, ax),
					cutDegrees = cut,
					distance = toGhost,
				}
			end
		end
	end
	return best
end

--- Whether the 8 sits ready for the player's last shot: within EightNearInches of a pocket's
--- mouth with nothing between it and that pocket.
function Break.eightPlaced(geometry: TableGeometry.Geometry, balls: { Ball }): boolean
	local eight = nil
	for _, b in balls do
		if b.id == 8 and not b.pocketed then
			eight = b
		end
	end
	if eight == nil then
		return false
	end
	for _, p in geometry.pockets do
		local mx, my = mouth(geometry, p)
		local gap = math.sqrt((eight.x - mx) ^ 2 + (eight.y - my) ^ 2)
		if gap < B.EightNearInches and clear(balls, 8, eight.x, eight.y, mx, my) then
			return true
		end
	end
	return false
end

--- The pocket the 8 obviously goes in (the "SELECT WHICH POCKET" lesson): the nearest one
--- with a clear line from the 8, else the nearest. Nil when the 8 is down.
function Break.eightPocket(geometry: TableGeometry.Geometry, balls: { Ball }): number?
	local eight = nil
	for _, b in balls do
		if b.id == 8 and not b.pocketed then
			eight = b
		end
	end
	if eight == nil then
		return nil
	end
	local best, bestGap, open, openGap = nil, math.huge, nil, math.huge
	for _, p in geometry.pockets do
		local mx, my = mouth(geometry, p)
		local gap = math.sqrt((eight.x - mx) ^ 2 + (eight.y - my) ^ 2)
		if gap < bestGap then
			best, bestGap = p.id, gap
		end
		if gap < openGap and clear(balls, 8, eight.x, eight.y, mx, my) then
			open, openGap = p.id, gap
		end
	end
	return open or best
end

--- How good a break `result` is for the tutorial (higher is better), or nil when it does not
--- do the job: exactly Solids solids down and nothing else, the shooter keeps the table, a
--- straight corner pot for the next solid.
function Break.score(geometry: TableGeometry.Geometry, result: Result): any?
	local j = result.judgement
	if result.scratch or j.foul ~= nil or j.winner ~= nil or not j.keep then
		return nil
	end
	if #result.pocketed ~= B.Solids then
		return nil
	end
	for _, id in result.pocketed do
		if Judge.group(id) ~= "solids" then
			return nil
		end
	end
	local lesson = Break.lesson(geometry, result.balls, "solids", true)
	if lesson == nil or lesson.distance > B.LessonMaxInches then
		return nil
	end
	local eightGap = math.huge
	for _, b in result.balls do
		if b.id == 8 and not b.pocketed then
			for _, p in geometry.pockets do
				local mx, my = mouth(geometry, p)
				eightGap = math.min(eightGap, math.sqrt((b.x - mx) ^ 2 + (b.y - my) ^ 2))
			end
		end
	end
	local total = 100 - lesson.cutDegrees - lesson.distance * B.LessonCostPerInch
	if eightGap < B.EightNearInches then
		total += B.EightNearBonus
	end
	return {
		total = total,
		ball = lesson.ball,
		pocket = lesson.pocket,
		cutDegrees = lesson.cutDegrees,
		distance = lesson.distance,
		eightGap = eightGap,
	}
end

local _ = TableGeometry
return Break
