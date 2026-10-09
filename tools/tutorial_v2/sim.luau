--!strict
-- Shared pieces of the tutorial v2 simulations (docs/prompts/TUTORIAL_V2_PROMPT.md 5.1, 5.2):
-- the table, a traced break (every ball's path, to measure how slowly a ball drops), table
-- reading helpers (pockets, mouths, clear lines, cut angles) and a JSON writer. Runs in Lune
-- on the game's own shared modules (tests/harness).
local H = require("../../tests/harness")
local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Rack = H.require("Physics.Rack")
local Simulation = H.require("Physics.Simulation")
local TableGeometry = H.require("Physics.Table")
local Judge = H.require("Rules.ShotJudge")
local Placement = H.require("Rules.CuePlacement")
local ShotInput = H.require("ShotInput")
local Break = H.require("Tutorial.Break")

local Sim = {}

Sim.H = H
Sim.Config = Config

-- The hidden help's tuning from the environment, so a sweep can try settings without editing
-- Config: TUT_STEER, TUT_MAXTURN, TUT_WINDOW (the ricochet's steer), TUT_PULL_FIRST and
-- TUT_PULL_LATER (the pull's modes), TUT_PULLMAX and TUT_PULLINCH (Gentle's turns),
-- TUT_GUARDMAX and TUT_GUARDINCH (the cue-ball guard's).
do
	local env = require("@lune/process").env
	local A = Config.Tutorial.Assist
	A.SteerPerInch = tonumber(env.TUT_STEER) or A.SteerPerInch
	A.MaxTurn = tonumber(env.TUT_MAXTURN) or A.MaxTurn
	A.WindowInches = tonumber(env.TUT_WINDOW) or A.WindowInches
	A.Pull.First = env.TUT_PULL_FIRST or A.Pull.First
	A.Pull.Later = env.TUT_PULL_LATER or A.Pull.Later
	A.Pull.MaxTurn = tonumber(env.TUT_PULLMAX) or A.Pull.MaxTurn
	A.Pull.PerInch = tonumber(env.TUT_PULLINCH) or A.Pull.PerInch
	A.Guard.MaxTurn = tonumber(env.TUT_GUARDMAX) or A.Guard.MaxTurn
	A.Guard.PerInch = tonumber(env.TUT_GUARDINCH) or A.Guard.PerInch
end
Sim.geometry = TableGeometry.build({ pocketsOpen = true })
Sim.R = Config.Balls.RadiusInches
Sim.D = 2 * Config.Balls.RadiusInches
Sim.DT = Config.Physics.FixedStep
Sim.Margin = 0.25 -- inches kept clear beyond a ball's width on a planned line (a ball resting
-- against the cue ball is grazed by any path that only just clears it)

local geometry = Sim.geometry
local D = Sim.D

--- The head spot and the foot spot (the rack's apex).
Sim.headX, Sim.headY = TableGeometry.headSpot(geometry)
Sim.footX, Sim.footY = TableGeometry.footSpot(geometry)

--- The middle of pocket `p`'s mouth (Break's own rule).
function Sim.mouth(p: any): (number, number)
	local hl, hw = geometry.halfLength, geometry.halfWidth
	local sy = if p.y > 0 then 1 else -1
	if p.x == 0 then
		return 0, sy * hw
	end
	local sx = if p.x > 0 then 1 else -1
	local half = Config.Table.CornerMouthInches / math.sqrt(2) / 2
	return sx * (hl - half), sy * (hw - half)
end

function Sim.pocket(id: number): any
	for _, p in geometry.pockets do
		if p.id == id then
			return p
		end
	end
	error("no pocket " .. id)
end

function Sim.find(balls: { any }, id: number): any?
	for _, b in balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

local function segmentGap(px: number, py: number, ax: number, ay: number, bx: number, by: number)
	local vx, vy = bx - ax, by - ay
	local len2 = vx * vx + vy * vy
	local t = if len2 > 0 then math.clamp(((px - ax) * vx + (py - ay) * vy) / len2, 0, 1) else 0
	local cx, cy = ax + vx * t, ay + vy * t
	return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end
Sim.segmentGap = segmentGap

--- Whether no ball but those in `skip` lies within `width` of the segment.
function Sim.clear(
	balls: { any },
	skip: { [number]: boolean },
	ax: number,
	ay: number,
	bx: number,
	by: number,
	width: number?
): boolean
	local w = width or D
	for _, b in balls do
		if not b.pocketed and not skip[b.id] then
			if segmentGap(b.x, b.y, ax, ay, bx, by) < w then
				return false
			end
		end
	end
	return true
end

--- A straight pot of ball `b` into pocket `p` from the cue ball at (cx, cy): the cue angle,
--- the cut (degrees), cue-to-ghost and ball-to-mouth distances, and whether both lines are
--- clear. Nil when the ghost ball is behind the cue ball.
function Sim.pot(balls: { any }, cx: number, cy: number, b: any, p: any): any?
	local mx, my = Sim.mouth(p)
	local ux, uy = mx - b.x, my - b.y
	local toPocket = math.sqrt(ux * ux + uy * uy)
	if toPocket < D then
		-- In the jaws: straight down the pocket's throat (Tutorial/Break.lesson's rule).
		ux, uy = Break.throat(p)
		mx, my = b.x + ux * D, b.y + uy * D
	else
		ux, uy = ux / toPocket, uy / toPocket
	end
	local gx, gy = b.x - ux * D, b.y - uy * D
	local ax, ay = gx - cx, gy - cy
	local toGhost = math.sqrt(ax * ax + ay * ay)
	if toGhost < D * 0.5 then
		return nil
	end
	local cosCut = (ax * ux + ay * uy) / toGhost
	local cut = math.deg(math.acos(math.clamp(cosCut, -1, 1)))
	local skipCue = { [0] = true, [b.id] = true }
	local w = D + Sim.Margin
	local clear = Sim.clear(balls, skipCue, cx, cy, gx, gy, w)
		and Sim.clear(balls, skipCue, b.x, b.y, mx, my, w)
	return {
		ball = b.id,
		pocket = p.id,
		angle = math.atan2(ay, ax),
		cut = cut,
		toGhost = toGhost,
		toPocket = toPocket,
		clear = clear,
		ghostX = gx,
		ghostY = gy,
	}
end

--- Every straight pot of the group's balls from the cue ball (clear or not).
function Sim.pots(balls: { any }, group: string, onlyClear: boolean?): { any }
	local cue = Sim.find(balls, 0)
	local out = {}
	if cue == nil or cue.pocketed then
		return out
	end
	for _, b in balls do
		if not b.pocketed and b.id ~= 0 and Judge.group(b.id) == group then
			for _, p in geometry.pockets do
				local pot = Sim.pot(balls, cue.x, cue.y, b, p)
				if pot and (pot.clear or not onlyClear) then
					table.insert(out, pot)
				end
			end
		end
	end
	return out
end

--- Plays a shot from `balls` exactly as the server does (ShotInput, the strike, the seed
--- quantised, settled), with optional overrides armed (an effect). Returns the outcome, when
--- `trace` is set every ball's (t, x, y, speed, tipping) per step until it drops, and the
--- effect's per-shot scratch (state.fx).
function Sim.play(balls: { any }, shot: any, arm: any?, trace: boolean?): (any, any?, any?)
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	local input = ShotInput.validate({
		angle = shot.angle,
		power = shot.power,
		spin = shot.spin or { x = 0, y = 0 },
	}, nil) :: any
	local events = { Simulation.strike(sim, input) }
	if arm then
		Simulation.armEffect(sim, arm.Effect, arm.Targets, arm.EightPocket, arm.extra)
	end
	for _, b in sim.balls do
		if b.id == 0 then
			ShotInput.quantiseSeed(b)
		end
	end
	if not trace then
		local outcome = Simulation.settle(sim, events)
		return outcome, nil, sim.fx
	end
	-- The same loop as settle, stepping by hand to record the paths.
	local P = Config.Physics
	local paths: { [number]: { any } } = {}
	local steps = 0
	local maxSteps = math.floor(P.MaxShotSeconds / P.FixedStep)
	while not Simulation.isAtRest(sim) and steps < maxSteps do
		Simulation.step(sim, P.FixedStep, events)
		steps += 1
		for _, b in sim.balls do
			if not b.pocketed or b.tip ~= nil then
				local path = paths[b.id] or {}
				paths[b.id] = path
				path[#path + 1] =
					{ sim.time, b.x, b.y, math.sqrt(b.vx * b.vx + b.vy * b.vy), b.tip ~= nil }
			end
		end
	end
	Simulation.finishShot(sim, events)
	return {
		events = events,
		finalBalls = Ball.cloneList(sim.balls),
		firstContact = Simulation.firstContact(events),
		duration = sim.time,
		steps = steps,
	},
		paths,
		sim.fx
end

--- The break's opening balls: the rack for `seed`, the cue ball at (cx, cy).
function Sim.rack(seed: number, cx: number, cy: number): { any }
	local balls = Rack.newGame(geometry, seed)
	local cue = Sim.find(balls, 0) :: any
	cue.x, cue.y = cx, cy
	return balls
end

--- Judges a shot from `before` with the shooter's team 1 and `groups` (nil: open table),
--- as the server's ShotJudge does for a break when `breakShot`.
function Sim.judge(
	before: { any },
	outcome: any,
	groups: any?,
	breakShot: boolean,
	called: number?
): any
	return Judge.resolve(before, outcome, groups or {}, 1, breakShot, called, false)
end

--- The balls pocketed in an outcome, the cue ball apart.
function Sim.down(outcome: any): ({ number }, boolean)
	local list, scratch = {}, false
	for _, b in outcome.finalBalls do
		if b.pocketed then
			if b.id == 0 then
				scratch = true
			else
				table.insert(list, b.id)
			end
		end
	end
	return list, scratch
end

--- How a pocketed ball went in, from its traced path: seconds spent within `near` inches of
--- where it was captured before the capture, seconds tipping over the lip, and its speed at
--- capture (in/s).
function Sim.dropFeel(path: { any }, near: number): any
	-- The capture: the first step it tips or the last step traced.
	local last = #path
	for i, row in path do
		if row[5] then
			last = i
			break
		end
	end
	local cx, cy = path[last][2], path[last][3]
	local t1 = path[last][1]
	local t0 = t1
	for i = last, 1, -1 do
		local row = path[i]
		if math.sqrt((row[2] - cx) ^ 2 + (row[3] - cy) ^ 2) > near then
			break
		end
		t0 = row[1]
	end
	local tipping = 0
	for i = last, #path do
		if path[i][5] then
			tipping += Sim.DT
		end
	end
	return { nearSeconds = t1 - t0, tipSeconds = tipping, speed = path[math.max(1, last - 1)][4] }
end

--- Minimal JSON for plain tables (numbers, strings, booleans, arrays, string-keyed maps).
function Sim.json(value: any): string
	local kind = type(value)
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then
			return "null"
		end
		if value == math.floor(value) and math.abs(value) < 1e15 then
			return ("%d"):format(value)
		end
		return ("%.6g"):format(value)
	elseif kind == "string" then
		return '"'
			.. value:gsub('[%c"\\]', function(c: string): string
				return ("\\u%04x"):format(string.byte(c))
			end)
			.. '"'
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "nil" then
		return "null"
	elseif kind == "table" then
		if #value > 0 or next(value) == nil then
			local parts = {}
			for _, v in value do
				table.insert(parts, Sim.json(v))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in value do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local parts = {}
		for _, k in keys do
			table.insert(parts, Sim.json(k) .. ":" .. Sim.json(value[k]))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

--- The tutorial's hidden help as Tutorial/Rig.assist arms it: Magnet on the first ball hit if
--- it is one of the shooter's `group` (the 8 only toward `called` once it is theirs), nothing
--- drawn.
local Arming = H.require("Ults.Arming")
function Sim.magnet(balls: { any }, group: string, called: number?): any
	local groups = { group, Judge.opposite(group :: any) }
	local own, _, eightPocket, legalEight = Arming.targets(groups, 1, called, balls)
	local extra = Arming.extras("Magnet", {
		own = own,
		opp = {},
		eightPocket = eightPocket,
		legalEight = legalEight,
		open = false,
		pick = nil,
		balls = balls,
	})
	extra.OppTargets = {}
	extra.Hidden = true
	return { Effect = "Magnet", Targets = own, EightPocket = eightPocket, extra = extra }
end

--- Whether a ball sits within `inches` of any pocket's mouth.
function Sim.nearPocket(b: any, inches: number): (boolean, number, number?)
	local best, which = math.huge, nil
	for _, p in geometry.pockets do
		local mx, my = Sim.mouth(p)
		local d = math.sqrt((b.x - mx) ^ 2 + (b.y - my) ^ 2)
		if d < best then
			best, which = d, p.id
		end
	end
	return best < inches, best, which
end

-- The pots a new player might choose, easiest first (cut, then the distances).
Sim.MaxCut = 65 -- no new player tries a thinner cut than this
function Sim.choices(balls: { any }, group: string): { any }
	local list = {}
	for _, pot in Sim.pots(balls, group, true) do
		if pot.cut <= Sim.MaxCut then
			table.insert(list, pot)
		end
	end
	if #list == 0 then
		for _, pot in Sim.pots(balls, group, false) do
			if pot.cut <= Sim.MaxCut then
				table.insert(list, pot)
			end
		end
	end
	table.sort(list, function(a, b)
		local ca = a.cut + 0.4 * a.toGhost + 0.4 * a.toPocket
		local cb = b.cut + 0.4 * b.toGhost + 0.4 * b.toPocket
		return ca < cb
	end)
	return list
end

-- The ability lesson's pot (4.4): the cue ball close to one of their balls and that ball far
-- from the pocket, a clear and gentle cut. Nil when nothing fits (then the easiest pot).
function Sim.firePlan(balls: { any }, group: string): any?
	local best, bestScore = nil, -math.huge
	for _, pot in Sim.pots(balls, group, true) do
		if pot.cut <= 35 then
			local score = math.min(pot.toPocket, 28) * 0.5 - pot.toGhost * 0.8 - pot.cut * 1.2
			if score > bestScore then
				best, bestScore = pot, score
			end
		end
	end
	return best
end

local _ = Placement
return Sim
