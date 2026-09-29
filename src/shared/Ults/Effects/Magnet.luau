--!strict
-- Magnet (the first ult, docs/prompts/ULTIMATES_PROMPT.md 7.3): for the whole shot, each
-- allowed ball moving toward a pocket inside that pocket's capture zone is steered in.
--
-- It STEERS rather than pushes, and only as much as it must. At the start of each fixed step
-- the ball's straight path is traced (the same exact contact tests the simulation uses): if
-- it already drops cleanly into the opening, with a little room to spare, it is left alone,
-- so a pot that was going in never changes. If it would hit a jaw, a facing or the cushion
-- beside the mouth first, its velocity is turned away from that side, just far enough to
-- clear it or as far as this step's pull allows, and its spin (wx, wy) turns with it about
-- the vertical so a rolling ball stays rolling. Nothing ever gains speed or energy, and a
-- ball that is not moving is never touched, so a slow ball that stops short of the mouth
-- stays where it stops. The pull grows as the ball nears the mouth (closeness ^ Power) and
-- fades with speed above FadeSpeed, so it rescues near misses and jaw rattles but is never a
-- vacuum.
--
-- Which balls: overrides.Targets, decided by the server's rules (the shooter's group; the 8
-- only on their legal 8 shot). The cue ball is never pulled, even if listed, and the 8 only
-- toward overrides.EightPocket (never at all without one).
--
-- Only arithmetic and square roots (IEEE-exact everywhere), no trig, so every device turns
-- the ball by exactly the same bits. Pure Luau: must never require Physics/Simulation.

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
		EightPocket: number?,
	}?,
}

export type Pull = {
	ball: number, -- ball id
	pocket: number, -- pocket id
	strength: number, -- 0-1: closeness to the mouth, faded by speed (what the effects draw)
	steering: boolean, -- true while it is actually being turned (false: already on line)
}

local Magnet = {}

local EIGHT = 8
-- Bisection steps when finding how far to turn inside one step's allowance.
local SEARCH_STEPS = 8

--- The middle of a pocket's mouth: between the two cushion noses for a corner, on the cushion
--- line for a side. The capture zone is a circle around it.
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

-- The cushion faces and jaw points around each pocket's mouth (every rail ends at a mouth, so
-- an end near it finds the rails beside it too), per geometry. Built in the geometry's own
-- array order, so the traces are the same everywhere.
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
	local reach = (Config.Ults.Magnet.CaptureBallWidths + 2) * 2 * Config.Balls.RadiusInches
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

--- 0-1 speed factor: 1 up to FadeSpeed, then falling as (FadeSpeed / speed) ^ FadePower.
local function speedFactor(speed: number): number
	local M = Config.Ults.Magnet
	if speed <= M.FadeSpeed then
		return 1
	end
	return (M.FadeSpeed / speed) ^ M.FadePower
end

-- The set of ball ids the effect may act on, or nil when it has none.
local function targetSet(state: State): ({ [number]: boolean }?, number?)
	local overrides = state.overrides
	if overrides == nil or overrides.Targets == nil then
		return nil, nil
	end
	local set: { [number]: boolean } = {}
	for _, id in overrides.Targets do
		if id ~= 0 then -- never the cue ball
			set[id] = true
		end
	end
	return set, overrides.EightPocket
end

type Zone = {
	pocket: Pocket,
	strength: number,
	mx: number,
	my: number,
	ux: number,
	uy: number,
}

-- The pocket whose capture zone holds this ball, if it is on the cloth and moving toward it
-- (the nearest mouth wins), and how strongly it pulls (0-1).
local function zoneOf(geometry: Geometry, b: Ball, eightPocket: number?): Zone?
	-- On the cloth and in play only: not in the air, not over or into a pocket.
	if b.pocketed or b.z ~= 0 or b.vz ~= 0 then
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
	local zoneRadius = M.CaptureBallWidths * 2 * Config.Balls.RadiusInches
	local best: Zone? = nil
	local bestCloseness = 0
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
		-- Moving toward the pocket: the velocity has a real component toward its centre.
		local cx, cy = pocket.x - b.x, pocket.y - b.y
		local centreDist = math.sqrt(cx * cx + cy * cy)
		if
			centreDist < 1e-9
			or (b.vx * cx + b.vy * cy) / (speed * centreDist) <= M.MinApproachCos
		then
			continue
		end
		local closeness = 1 - mouthDist / zoneRadius
		if closeness > bestCloseness then
			-- The mouth direction: across the pocket's axis (mouth middle to opening centre).
			local ax, ay = pocket.x - mx, pocket.y - my
			local axisLength = math.sqrt(ax * ax + ay * ay)
			bestCloseness = closeness
			best = {
				pocket = pocket,
				strength = 0,
				mx = mx,
				my = my,
				ux = -ay / axisLength,
				uy = ax / axisLength,
			}
		end
	end
	if best then
		best.strength = bestCloseness ^ M.Power * speedFactor(speed)
	end
	return best
end

-- The heading (hx, hy) turned by the angle whose sine is `s` (positive = counter-clockwise).
local function turned(hx: number, hy: number, s: number): (number, number)
	local c = math.sqrt(1 - s * s)
	return c * hx - s * hy, s * hx + c * hy
end

-- How far to turn one ball this step, as the sine of the angle (signed), or 0 when it is on
-- line. `limit` is this step's allowance.
local function turnFor(geometry: Geometry, b: Ball, zone: Zone, limit: number): number
	local M = Config.Ults.Magnet
	local near = nearMouth(geometry, zone.pocket)
	local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
	local hx, hy = b.vx / speed, b.vy / speed
	-- Traced a little fatter than the ball, so "on line" leaves room to spare.
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

--- Which allowed balls are inside a capture zone and moving toward its pocket right now, how
--- strongly they are pulled (0-1), and whether each is actually being turned. MagnetFx calls
--- this on its replay state every frame for the beam and the pocket ring.
function Magnet.activePulls(state: State): { Pull }
	local pulls: { Pull } = {}
	local set, eightPocket = targetSet(state)
	if set == nil then
		return pulls
	end
	for _, b in state.balls do
		if set[b.id] then
			local zone = zoneOf(state.geometry, b, eightPocket)
			if zone and zone.strength > 0 then
				table.insert(pulls, {
					ball = b.id,
					pocket = zone.pocket.id,
					strength = zone.strength,
					steering = turnFor(state.geometry, b, zone, 1e-3) ~= 0,
				})
			end
		end
	end
	return pulls
end

--- Turn every pulled ball for one fixed step of `dt` seconds. Called by Simulation.step before
--- the step is advanced, on the server and on every client's replay alike.
function Magnet.step(state: State, dt: number)
	local set, eightPocket = targetSet(state)
	if set == nil then
		return
	end
	local M = Config.Ults.Magnet
	for _, b in state.balls do
		if not set[b.id] then
			continue
		end
		local zone = zoneOf(state.geometry, b, eightPocket)
		if zone == nil or zone.strength <= 0 then
			continue
		end
		-- This step's allowance: the path bends per inch travelled, so a slow and a firm ball
		-- curve alike (before the speed fade), capped so one step never swings it far.
		local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
		local bend = if zone.pocket.x == 0 then M.SideMaxBend else M.MaxBend
		local limit = math.min(bend * zone.strength * speed * dt, M.MaxStepTurn)
		local s = turnFor(state.geometry, b, zone, limit)
		if s == 0 then
			continue
		end
		local c = math.sqrt(1 - s * s)
		b.vx, b.vy = c * b.vx - s * b.vy, s * b.vx + c * b.vy
		b.wx, b.wy = c * b.wx - s * b.wy, s * b.wx + c * b.wy
	end
end

return Magnet
