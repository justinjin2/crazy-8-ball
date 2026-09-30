--!strict
-- Magnet (the first ult, docs/prompts/ULTIMATES_PROMPT.md 7.3; buffed 2026-09-28): for the
-- whole shot, each allowed ball that has been hit (it is moving: object balls start the shot
-- at rest) is magnetised. Inside a pocket's big pull zone and heading roughly toward that
-- pocket, it is pulled in so you can see it working, harder the closer it gets
-- (closeness ^ Power):
--
-- * Its path bends in. At the start of each fixed step its straight path is traced (the same
--   exact contact tests the simulation uses, with a ball a little fatter): if it already
--   drops cleanly into the opening it is not turned, so a pot that was going in stays on
--   its line. If it would hit a jaw, a facing or a cushion first, or pass the opening, its
--   heading turns away from that side by this step's allowance (bend per inch rolled, so
--   the curve tightens toward the mouth instead of snapping), or just far enough to clear.
-- * Its speed is blended toward CaptureSpeed: a fast ball is braked hard near the pocket, as
--   if caught, and eased in; a slow ball creeping toward the pocket is pulled up to that
--   creep speed so it does not die at the lip. Spin (wx, wy) turns and scales with the
--   velocity, so a rolling ball stays rolling.
--
-- Balls below MinSpeed (at rest) are never touched: it is not a vacuum on still balls, and a
-- ball is magnetised only once it moves. Balls heading away from every pocket are left alone.
--
-- Which balls (the skill rule, docs/prompts/ABILITIES_PROMPT.md 5.7): overrides.Targets at
-- full strength (the shooter's group; the 8 only on their legal 8 shot) and
-- overrides.OppTargets (the opponent's group) at Config.Ults.Shared.OpponentFactor, both
-- decided by the server's rules. The cue ball is never pulled, even if listed; the 8 never
-- as the opponent's, and as yours only toward overrides.EightPocket.
--
-- Only arithmetic and square roots (IEEE-exact everywhere), no trig and no pow (powers are
-- multiplied out), balls, pockets and table pieces walked in array order, and no state kept
-- between steps: the server and every client's replay step it to identical bits. Pure Luau:
-- must never require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)
local Ball = require(script.Parent.Parent.Parent.Physics.Ball)
local Collision = require(script.Parent.Parent.Parent.Physics.Collision)
local TableGeometry = require(script.Parent.Parent.Parent.Physics.Table)

type Ball = Ball.Ball
type Pocket = TableGeometry.Pocket
type Geometry = TableGeometry.Geometry
type Segment = TableGeometry.Segment
type Point = TableGeometry.Point

-- The part of Simulation.State this reads (Simulation.State itself cannot be required here).
export type State = {
	geometry: Geometry,
	balls: { Ball },
	overrides: {
		Effect: string?,
		Targets: { number }?,
		OppTargets: { number }?,
		EightPocket: number?,
	}?,
}

export type Pull = {
	ball: number, -- ball id
	pocket: number, -- pocket id
	strength: number, -- 0-1: closeness to the mouth ^ Power, x the owner's factor (drawn)
	factor: number, -- 1 for the shooter's ball, OpponentFactor for the opponent's
	steering: boolean, -- true while its velocity is actually being changed (turned or re-sped)
	braking: boolean, -- true while it is being slowed toward CaptureSpeed
}

local Magnet = {}

local EIGHT = 8
-- Bisection steps when finding how far to turn inside one step's allowance.
local SEARCH_STEPS = 8

--- The middle of a pocket's mouth: between the two cushion noses for a corner, on the cushion
--- line for a side. The pull zone is a circle around it.
function Magnet.mouthPoint(geometry: Geometry, pocket: Pocket): (number, number)
	local hl, hw = geometry.halfLength, geometry.halfWidth
	local sy = if pocket.y > 0 then 1 else -1
	if pocket.x == 0 then
		return 0, sy * hw
	end
	local sx = if pocket.x > 0 then 1 else -1
	local half = Config.Table.CornerMouthInches / math.sqrt(2) / 2
	return sx * (hl - half), sy * (hw - half)
end

-- x ^ n for a whole n >= 0, multiplied out (pow() is not bit-identical on every device).
local function power(x: number, n: number): number
	local out = 1
	for _ = 1, n do
		out *= x
	end
	return out
end

-- The cushion faces and jaw points a ball in a pocket's pull zone could meet on its way in:
-- every piece with an end within the zone (plus a margin), per geometry. Built in the
-- geometry's own array order, so the traces are the same everywhere.
type Near = { segments: { Segment }, points: { Point } }
local nearCache: { [Geometry]: { [number]: Near } } = setmetatable({} :: any, { __mode = "k" })

local function nearMouth(geometry: Geometry, pocket: Pocket): Near
	local perPocket = nearCache[geometry]
	if perPocket == nil then
		perPocket = {}
		nearCache[geometry] = perPocket
	end
	local near = perPocket[pocket.id]
	if near then
		return near
	end
	local mx, my = Magnet.mouthPoint(geometry, pocket)
	local reach = (Config.Ults.Magnet.ZoneBallWidths + 2) * 2 * Config.Balls.RadiusInches
	local function close(x: number, y: number): boolean
		return (x - mx) * (x - mx) + (y - my) * (y - my) < reach * reach
	end
	local built: Near = { segments = {}, points = {} }
	for _, seg in geometry.segments do
		if close(seg.ax, seg.ay) or close(seg.bx, seg.by) then
			table.insert(built.segments, seg)
		end
	end
	for _, pt in geometry.points do
		if close(pt.x, pt.y) then
			table.insert(built.points, pt)
		end
	end
	perPocket[pocket.id] = built
	return built
end

-- Trace a ball of radius `r` from (x, y) along the unit heading (hx, hy). Returns 0 when its
-- centre crosses the pocket's opening rim before it touches anything, or else which side of
-- the pocket's axis it goes wrong on (+1 or -1, along the mouth direction ux, uy): where it
-- first touches a cushion or jaw, or the side it passes the opening on.
local function trace(
	near: Near,
	pocket: Pocket,
	mx: number,
	my: number,
	ux: number,
	uy: number,
	x: number,
	y: number,
	hx: number,
	hy: number,
	r: number
): number
	-- Where the centre enters the opening circle, if it does.
	local fx, fy = x - pocket.x, y - pocket.y
	local b = fx * hx + fy * hy
	local c = fx * fx + fy * fy - pocket.radius * pocket.radius
	local enter = math.huge
	if c <= 0 then
		enter = 0
	else
		local disc = b * b - c
		if disc >= 0 and b < 0 then
			enter = -b - math.sqrt(disc)
		end
	end
	local reach = if enter < math.huge then enter else math.sqrt(fx * fx + fy * fy) + pocket.radius
	local hit = reach
	local found = false
	for _, seg in near.segments do
		local t = Collision.segmentTOI(x, y, hx, hy, r, seg, hit)
		if t and (t < hit or not found) then
			hit, found = t, true
		end
	end
	for _, pt in near.points do
		local t = Collision.pointTOI(x, y, hx, hy, r, pt.x, pt.y, pt.radius, hit)
		if t and (t < hit or not found) then
			hit, found = t, true
		end
	end
	if not found and enter < math.huge then
		return 0 -- clean: in before it touches anything
	end
	-- Blocked at `hit`, or never reaching the opening: judged by its nearest pass.
	local at = if found then hit else -b
	local side = (x + hx * at - mx) * ux + (y + hy * at - my) * uy
	return if side >= 0 then 1 else -1
end

-- The ball ids the effect may act on, each with its strength factor (1 for the shooter's,
-- OpponentFactor for the opponent's), or nil when it has none.
local function targetSet(state: State): ({ [number]: number }?, number?)
	local overrides = state.overrides
	if overrides == nil or overrides.Targets == nil then
		return nil, nil
	end
	local set: { [number]: number } = {}
	if overrides.OppTargets then
		local factor = Config.Ults.Shared.OpponentFactor
		for _, id in overrides.OppTargets do
			if id ~= 0 and id ~= EIGHT then -- never the cue ball, never the 8 as theirs
				set[id] = factor
			end
		end
	end
	for _, id in overrides.Targets do
		if id ~= 0 then -- never the cue ball
			set[id] = 1
		end
	end
	return set, overrides.EightPocket
end

--- Whether Magnet may act on this ball this shot: listed in overrides.Targets or OppTargets,
--- not the cue ball, and the 8 only as the shooter's with a pocket called for it. MagnetFx
--- can mark a ball magnetised the first time it moves while this is true.
function Magnet.isTarget(state: State, ballId: number): boolean
	return Magnet.factor(state, ballId) > 0
end

--- The strength this ball is pulled at this shot: 1 for the shooter's, OpponentFactor for the
--- opponent's, 0 when it is not pulled at all.
function Magnet.factor(state: State, ballId: number): number
	local set, eightPocket = targetSet(state)
	local factor = if set then set[ballId] else nil
	if factor == nil or (ballId == EIGHT and eightPocket == nil) then
		return 0
	end
	return factor
end

type Zone = {
	pocket: Pocket,
	closeness: number, -- 0 at the zone's edge, 1 at (or past) the mouth
	strength: number, -- closeness ^ Power x the owner's factor
	mx: number, -- the mouth middle
	my: number,
	ux: number, -- the mouth direction (across the pocket's axis)
	uy: number,
}

-- The pocket whose pull zone holds this ball, if it is on the cloth, moving, and heading
-- roughly toward that pocket (the closest mouth wins; ties keep the first pocket).
local function zoneOf(geometry: Geometry, b: Ball, eightPocket: number?, factor: number): Zone?
	-- On the cloth and in play only: not in the air, not over or into a pocket.
	if b.pocketed or b.tip ~= nil or b.z ~= 0 or b.vz ~= 0 then
		return nil
	end
	if b.id == EIGHT and eightPocket == nil then
		return nil
	end
	local M = Config.Ults.Magnet
	local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
	if speed < M.MinSpeed then
		return nil
	end
	local zoneRadius = M.ZoneBallWidths * 2 * Config.Balls.RadiusInches
	local best: Zone? = nil
	for _, pocket in geometry.pockets do
		if b.id == EIGHT and pocket.id ~= eightPocket then
			continue
		end
		local mx, my = Magnet.mouthPoint(geometry, pocket)
		local dmx, dmy = b.x - mx, b.y - my
		local mouthDist = math.sqrt(dmx * dmx + dmy * dmy)
		if mouthDist >= zoneRadius then
			continue
		end
		-- Heading roughly toward the pocket: inside the approach cone around the line to its
		-- centre.
		local cx, cy = pocket.x - b.x, pocket.y - b.y
		local centreDist = math.sqrt(cx * cx + cy * cy)
		if
			centreDist < 1e-9
			or (b.vx * cx + b.vy * cy) / (speed * centreDist) <= M.MinApproachCos
		then
			continue
		end
		-- The pocket's axis (mouth middle to opening centre); past the mouth line counts as
		-- right at the mouth.
		local ax, ay = pocket.x - mx, pocket.y - my
		local axisLength = math.sqrt(ax * ax + ay * ay)
		ax, ay = ax / axisLength, ay / axisLength
		local closeness = if dmx * ax + dmy * ay > 0 then 1 else 1 - mouthDist / zoneRadius
		if best == nil or closeness > best.closeness then
			best = {
				pocket = pocket,
				closeness = closeness,
				strength = power(closeness, M.Power) * factor,
				mx = mx,
				my = my,
				ux = -ay,
				uy = ax,
			}
		end
	end
	return best
end

-- The heading (hx, hy) turned by the angle whose sine is `s` (positive = counter-clockwise).
local function turned(hx: number, hy: number, s: number): (number, number)
	local c = math.sqrt(1 - s * s)
	return c * hx - s * hy, s * hx + c * hy
end

-- How far to turn one ball this step, as the sine of the angle (signed), or 0 when its path
-- already drops cleanly. `limit` is this step's allowance: all of it while the path still
-- goes wrong on the same side, less when that would swing it past a clean line.
local function turnFor(geometry: Geometry, b: Ball, zone: Zone, limit: number): number
	local M = Config.Ults.Magnet
	local near = nearMouth(geometry, zone.pocket)
	local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
	local hx, hy = b.vx / speed, b.vy / speed
	-- Traced a little fatter than the ball, so "clean" leaves room to spare.
	local r = Config.Balls.RadiusInches + M.ClearanceInches
	local function side(s: number): number
		local tx, ty = turned(hx, hy, s)
		return trace(near, zone.pocket, zone.mx, zone.my, zone.ux, zone.uy, b.x, b.y, tx, ty, r)
	end
	local wrong = side(0)
	if wrong == 0 then
		return 0
	end
	-- Turning counter-clockwise moves the path toward +u across the mouth, so turn away from
	-- the side it goes wrong on.
	local direction = -wrong
	if side(direction * limit) == wrong then
		return direction * limit -- still wrong with the whole allowance: use all of it
	end
	-- The least turn that clears it (bisection keeps it exact and the same everywhere).
	local lo, hi = 0, limit
	for _ = 1, SEARCH_STEPS do
		local mid = (lo + hi) / 2
		if side(direction * mid) == wrong then
			lo = mid
		else
			hi = mid
		end
	end
	return direction * hi
end

-- This step's turn allowance (the sine of the angle): the path bends per inch rolled, so a
-- slow and a fast ball follow the same curve, capped so one step never swings it far.
local function allowance(zone: Zone, speed: number, dt: number): number
	local M = Config.Ults.Magnet
	local bend = if zone.pocket.x == 0 then M.SideBend else M.CornerBend
	return math.min(bend * zone.strength * speed * dt, M.MaxStepTurn)
end

-- The speed this step leaves a ball at: braked toward CaptureSpeed per inch rolled when
-- faster (so however hard it was hit it is caught over the same stretch), pulled up to it
-- per second when slower.
local function newSpeed(zone: Zone, speed: number, dt: number): number
	local M = Config.Ults.Magnet
	local rate = if speed > M.CaptureSpeed
		then M.BrakePerInch * speed * dt
		else M.CreepPerSecond * dt
	return speed + (M.CaptureSpeed - speed) * math.min(1, rate * zone.strength)
end

--- Which allowed balls are inside a pull zone and heading toward its pocket right now, how
--- strongly they are pulled (0-1), whether each is actually being turned or re-sped, and
--- whether it is being braked. MagnetFx calls this on its replay state every frame.
function Magnet.activePulls(state: State): { Pull }
	local pulls: { Pull } = {}
	local set, eightPocket = targetSet(state)
	if set == nil then
		return pulls
	end
	local dt = Config.Physics.FixedStep
	for _, b in state.balls do
		local factor = set[b.id]
		if factor then
			local zone = zoneOf(state.geometry, b, eightPocket, factor)
			if zone and zone.strength > 0 then
				local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
				local after = newSpeed(zone, speed, dt)
				local turn = turnFor(state.geometry, b, zone, allowance(zone, speed, dt))
				table.insert(pulls, {
					ball = b.id,
					pocket = zone.pocket.id,
					strength = zone.strength,
					factor = factor,
					steering = turn ~= 0 or after ~= speed,
					braking = after < speed,
				})
			end
		end
	end
	return pulls
end

--- Pull every magnetised ball for one fixed step of `dt` seconds. Called by Simulation.step
--- before the step is advanced, on the server and on every client's replay alike.
function Magnet.step(state: State, dt: number)
	local set, eightPocket = targetSet(state)
	if set == nil then
		return
	end
	for _, b in state.balls do
		local factor = set[b.id]
		if factor ~= nil then
			Magnet.pull(state, b, eightPocket, factor, dt)
		end
	end
end

--- One ball's pull for one fixed step (Magnet.step's body; Ghost pulls the ball it hit with
--- it): `factor` its owner's strength, `eightPocket` the called pocket (the 8 only toward it).
function Magnet.pull(state: State, b: Ball, eightPocket: number?, factor: number, dt: number)
	local zone = zoneOf(state.geometry, b, eightPocket, factor)
	if zone == nil or zone.strength <= 0 then
		return
	end
	local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
	local s = turnFor(state.geometry, b, zone, allowance(zone, speed, dt))
	local scale = newSpeed(zone, speed, dt) / speed
	-- Turn by the angle whose sine is s and scale by `scale`, velocity and spin alike.
	local c = math.sqrt(1 - s * s) * scale
	s *= scale
	b.vx, b.vy = c * b.vx - s * b.vy, s * b.vx + c * b.vy
	b.wx, b.wy = c * b.wx - s * b.wy, s * b.wx + c * b.wy
end

return Magnet
