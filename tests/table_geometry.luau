--!strict
-- Table geometry export: the physics table written out as data, for the Blender script that
-- builds the table model. The model's pockets, jaws and rails are drawn from these numbers,
-- so the table a player sees is the table the balls play on.
--
-- Not a test itself (the runner only picks up *_test.luau files). Two users:
--   tools/export_table_geometry.luau writes encode() to PATH;
--   tests/table_geometry_test.luau fails when the committed PATH no longer matches build().
--
-- Everything comes from Config and the physics modules themselves, never copied numbers:
-- Physics.Table.build for the cushions, jaws and pocket openings, Physics.Rack for the
-- seeded default rack, Placement for the barrier. Arrays keep Physics order and are built
-- by index, never by walking a hash table, so the file is byte-for-byte reproducible.
-- Which pocket and cushion each facing and point belongs to is worked out from the
-- geometry (shared end points, nearest hole), not from the names, and asserted.
--
-- Units: inches unless a key ends in _studs. Frame: the physics frame (x along the length,
-- head rail at -x, foot rail at +x; y across, +y is the top rail with pockets 1-3; z up with
-- the cloth at 0). Multiplayer.BreakLineX is already a physics x in inches (Rules/
-- CuePlacement compares the cue ball's x against it directly), so it is written unchanged.
-- The file says all this itself (frame, units, legend), for the script that reads it.
--
-- serde's JSON encoder sorts object keys, so the output does not depend on table order.

local serde = require("@lune/serde")

local H = require("./harness")

local TableGeometryExport = {}

-- Physics.Table's segment, as the harness hands it over untyped.
type Segment = {
	ax: number,
	ay: number,
	bx: number,
	by: number,
	nx: number,
	ny: number,
	name: string,
}

--- Bump when a key is renamed, removed or changes meaning; the Blender script checks it.
--- Still 1: nothing has read the file yet, so v1 is whatever it says when first committed.
TableGeometryExport.SCHEMA_VERSION = 1

--- Relative to the repo root.
TableGeometryExport.PATH = "assets/table/Geometry.json"

local GENERATOR = "tools/export_table_geometry.luau"
local NOTE = "generated, do not edit; tests/table_geometry_test.luau fails when stale"
local FRAME = table.concat({
	"Physics frame: x along the length (head rail -x, foot rail +x), y across (the top rail",
	"with pockets 1-3 is +y), z up with the cloth at z = 0. Every mesh origin is the table",
	"centre on the floor, so with s = studs_per_inch and h = cloth.above_floor_studs:",
	"Blender native (Z up, the floor at Z = 0) = (x * s, y * s, z * s + h);",
	"Roblox model local, after the FBX importer = (x * s, z * s + h, -y * s).",
}, " ")
local UNITS = table.concat({
	"Lengths are inches unless the key ends in _studs; holes[].studs is studs too (it is",
	"named just studs). Keys ending in _degrees are degrees. Every two-number array is in",
	"plan, [x, y] in the physics frame: segments a, b and normal, spots head and foot,",
	"rack.apex, and holes[].studs = [x * s, y * s]. footprint_studs and",
	"barrier_half_extents_studs are [along x (the length), along y (the width)].",
}, " ")
local LEGEND = {
	segments = table.concat({
		"The 18 cushion nose lines in Physics.Table order; a ball touches one when its centre",
		"is ball.radius from it. kind rail: a straight cushion between two pockets, its",
		"normal pointing onto the cloth. kind facing: the angled cut beside a pocket, a = its",
		"nose end (where its rail segment ends), b = its jaw end, its normal facing into the",
		"pocket throat; pocket = its hole id. The rail segments topLeft, topRight, bottomLeft",
		"and bottomRight are the halves of the long rails (topLeft runs from hole 1 to hole",
		"2), not the holes with those names: match by id and through cushions, never by name.",
	}, " "),
	points = table.concat({
		"The 24 cushion-end points in Physics.Table order, a nose then a jaw per facing. nose:",
		"radius 0, the sharp corner at its facing's a end, where the facing leaves the rail",
		"line. jaw: the rubber knob of radius pockets.jaw_radius centred on its facing's b",
		"end; a ball touches it when its centre is ball.radius + radius from it. facing and",
		"pocket name the segment and the hole it belongs to.",
	}, " "),
	holes = table.concat({
		"The 6 pocket openings in id order. The cloth is cut at radius: a ball drops once its",
		"centre crosses that circle. While it falls its physics centre is held within",
		"radius - ball.radius of the hole centre, so the drawn ball (render_radius) reaches",
		"clear_radius = radius - ball.radius + ball.render_radius: the smallest radius a liner",
		"or cup wall below the cloth may have. It is not where the cloth is cut. facings and",
		"jaws are the hole's two facing segments and their jaw points, ordered so that turning",
		"counterclockwise (seen from +z) about the hole centre from jaws[1] to jaws[2] crosses",
		"the mouth, the table side, where the cloth meets the hole.",
	}, " "),
	cushions = table.concat({
		"The 6 cushions in the Physics.Table order of their rail segments: one rail segment",
		"with a facing at each end. The nose outline runs facings[1] from b to a (jaw to",
		"nose), the rail from a to b, then facings[2] from a to b (nose to jaw); the ends",
		"meet exactly. pockets are the hole ids at facings[1] and facings[2].",
	}, " "),
	pockets = table.concat({
		"Depths are inches below the cloth. drop_depth: the physics drop stops with the drawn",
		"ball's bottom this far down, and the replay draws that fall exactly. min_depth: the",
		"least cup depth, which holds that drop. It does not hold the fade: after the drop",
		"the renderer keeps the ball falling under gravity and drifting outward (away from",
		"the table centre) while it fades out, its bottom reaching fade_depth and its side at",
		"most clear_radius + fade_drift from the hole centre. So the fading ball passes the",
		"cup floor, which is why the floor is near-black. casting_*: the cue clears",
		"casting_top within casting_reach - casting_blend of a hole centre, ramping linearly",
		"down to rail.top at casting_reach, so at plan distance d a casting or cap must stay under",
		"rail.top + (casting_top - rail.top) * clamp((casting_reach - d) / casting_blend, 0, 1).",
		"casting_top is the game's current value; the new caps' measured crown replaces it",
		"(Config.Table.PocketCastingTopInches gives its limit).",
	}, " "),
}

-- Two plan points closer than this are the same point. Physics.Table builds a facing's nose
-- from the same numbers as its rail segment's end, so they agree to the last bit or so.
local SAME_POINT_INCHES = 1e-9

local function distance(ax: number, ay: number, bx: number, by: number): number
	return math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
end

local function segmentKind(name: string): string
	-- Physics.Table names every facing after its pocket ("...Side..", "...Corner.."); the
	-- cushion runs between them are named after their rail alone.
	if name:find("Side") or name:find("Corner") then
		return "facing"
	end
	return "rail"
end

local function pointKind(name: string): string
	if name:sub(-4) == "Nose" then
		return "nose"
	elseif name:sub(-3) == "Jaw" then
		return "jaw"
	end
	error("Physics.Table point " .. name .. " is neither a nose nor a jaw")
end

local function holeKind(name: string): string
	return if name:find("Side") then "side" else "corner"
end

--- The whole export as a plain table (schema v1).
function TableGeometryExport.build(): { [string]: any }
	local Config = H.require("Config")
	local TableGeometry = H.require("Physics.Table")
	local Rack = H.require("Physics.Rack")
	local Placement = H.require("Placement")

	local T = Config.Table
	local B = Config.Balls
	local s = T.StudsPerInch
	local geometry = TableGeometry.build({ pocketsOpen = true })
	local hl, hw = geometry.halfLength, geometry.halfWidth

	-- The hole nearest a plan point, walking the pockets in id order (a tie goes to the
	-- lower id, so the answer never depends on luck).
	local function nearestHole(x: number, y: number): number
		local best, bestDistance = 0, math.huge
		for _, pocket in ipairs(geometry.pockets) do
			local d = distance(x, y, pocket.x, pocket.y)
			if d < bestDistance then
				best, bestDistance = pocket.id, d
			end
		end
		return best
	end

	-- The facing (in segment order) whose nose (a) or jaw (b) end is at a point.
	local function facingEndingAt(x: number, y: number, atNose: boolean): Segment?
		for _, seg in ipairs(geometry.segments) do
			if segmentKind(seg.name) == "facing" then
				local ex, ey = if atNose then seg.ax else seg.bx, if atNose then seg.ay else seg.by
				if distance(x, y, ex, ey) <= SAME_POINT_INCHES then
					return seg
				end
			end
		end
		return nil
	end

	-- A facing belongs to the hole its jaw end guards.
	local function facingPocket(seg: Segment): number
		return nearestHole(seg.bx, seg.by)
	end

	local segments = {}
	local facingsOfHole: { [number]: { Segment } } = {}
	local cornerFacingLength: number? = nil
	for _, seg in ipairs(geometry.segments) do
		local kind = segmentKind(seg.name)
		local entry: { [string]: any } = {
			name = seg.name,
			kind = kind,
			a = { seg.ax, seg.ay },
			b = { seg.bx, seg.by },
			normal = { seg.nx, seg.ny },
		}
		if kind == "facing" then
			local hole = facingPocket(seg)
			entry.pocket = hole
			facingsOfHole[hole] = facingsOfHole[hole] or {}
			table.insert(facingsOfHole[hole], seg)
			if cornerFacingLength == nil and seg.name:find("Corner") then
				cornerFacingLength = distance(seg.ax, seg.ay, seg.bx, seg.by)
			end
		end
		table.insert(segments, entry)
	end
	assert(cornerFacingLength ~= nil, "Physics.Table built no corner facing")

	local points = {}
	local jawOfFacing: { [string]: string } = {}
	for _, p in ipairs(geometry.points) do
		local kind = pointKind(p.name)
		local facing = facingEndingAt(p.x, p.y, kind == "nose")
		assert(facing ~= nil, "Physics.Table point " .. p.name .. " ends no facing")
		if kind == "jaw" then
			jawOfFacing[facing.name] = p.name
		end
		table.insert(points, {
			name = p.name,
			kind = kind,
			x = p.x,
			y = p.y,
			radius = p.radius,
			facing = facing.name,
			pocket = facingPocket(facing),
		})
	end

	-- Each rail segment with the facings that leave its two ends, in chain order.
	local cushions = {}
	for _, seg in ipairs(geometry.segments) do
		if segmentKind(seg.name) == "rail" then
			local first = facingEndingAt(seg.ax, seg.ay, true)
			local last = facingEndingAt(seg.bx, seg.by, true)
			assert(
				first ~= nil and last ~= nil,
				"cushion " .. seg.name .. " does not close: a facing is missing at an end"
			)
			table.insert(cushions, {
				rail = seg.name,
				facings = { first.name, last.name },
				pockets = { facingPocket(first), facingPocket(last) },
			})
		end
	end

	-- The ball is drawn RenderScale larger than it plays. A falling ball's physics centre is
	-- held radius - R from the hole centre (Simulation clamps it to the liner), so the drawn
	-- ball reaches radius - R + render R: clear_radius is the smallest liner or cup wall. The
	-- cloth itself is cut at radius, the drop condition.
	local renderGrowth = B.RenderRadiusInches - B.RadiusInches
	local TAU = 2 * math.pi
	local function turn(from: number, to: number): number
		return (to - from) % TAU
	end
	local holes = {}
	for _, pocket in ipairs(geometry.pockets) do
		local pair = facingsOfHole[pocket.id]
		assert(
			pair ~= nil and #pair == 2,
			("hole %d should have 2 facings, has %d"):format(pocket.id, if pair then #pair else 0)
		)
		-- Order the pair so turning counterclockwise from the first jaw to the second
		-- crosses the mouth (the midpoint of the two noses), not the back of the hole.
		local first, second = pair[1], pair[2]
		local mouth =
			math.atan2((first.ay + second.ay) / 2 - pocket.y, (first.ax + second.ax) / 2 - pocket.x)
		local angleFirst = math.atan2(first.by - pocket.y, first.bx - pocket.x)
		local angleSecond = math.atan2(second.by - pocket.y, second.bx - pocket.x)
		if turn(angleFirst, mouth) > turn(angleFirst, angleSecond) then
			first, second = second, first
		end
		table.insert(holes, {
			id = pocket.id,
			name = pocket.name,
			kind = holeKind(pocket.name),
			x = pocket.x,
			y = pocket.y,
			radius = pocket.radius,
			clear_radius = pocket.radius + renderGrowth,
			studs = { pocket.x * s, pocket.y * s },
			facings = { first.name, second.name },
			jaws = { jawOfFacing[first.name], jawOfFacing[second.name] },
		})
	end

	-- Where the drawn ball goes after the physics drop: BallRenderer.animate keeps it falling
	-- at the drop's speed under gravity and drifting outward while it fades out over
	-- Effects.PocketFadeSeconds. Spelled out here because the renderer is a client module
	-- that cannot run in Lune; change one and change the other.
	local E = Config.Effects
	local gravity = Config.Physics.Gravity
	local drop = T.PocketDropDepthInches
	local fade = E.PocketFadeSeconds
	local fadeDepth = drop + math.sqrt(2 * gravity * drop) * fade + 0.5 * gravity * fade * fade
	local fadeDrift = E.PocketDriftInchesPerSecond * fade

	-- The seeded default rack, cue ball left out; newGame returns the balls sorted by id.
	local rackBalls = {}
	for _, ball in ipairs(Rack.newGame(geometry, Config.Rack.DefaultSeed)) do
		if ball.id ~= 0 then
			table.insert(rackBalls, { id = ball.id, x = ball.x, y = ball.y })
		end
	end

	local headX, headY = TableGeometry.headSpot(geometry)
	local footX, footY = TableGeometry.footSpot(geometry)
	local barrierX, barrierY = Placement.barrierHalfExtents()
	local outerHalfLength = hl + T.RailWidthInches
	local outerHalfWidth = hw + T.RailWidthInches

	return {
		schema_version = TableGeometryExport.SCHEMA_VERSION,
		generator = GENERATOR,
		note = NOTE,
		frame = FRAME,
		units = UNITS,
		legend = LEGEND,
		studs_per_inch = s,
		cloth = {
			length = T.LengthInches,
			width = T.WidthInches,
			half_length = hl,
			half_width = hw,
			above_floor = T.SurfaceHeightInches,
			above_floor_studs = T.SurfaceHeightStuds,
			bed_thickness = T.BedThicknessInches,
		},
		ball = {
			radius = B.RadiusInches,
			render_radius = B.RenderRadiusInches,
		},
		cushion = {
			nose_height = Config.Physics.CushionNoseHeightInches,
			width = T.CushionWidthInches,
		},
		rail = {
			width = T.RailWidthInches,
			top = T.RailTopInches,
			outer_half_length = outerHalfLength,
			outer_half_width = outerHalfWidth,
			footprint_studs = { 2 * outerHalfLength * s, 2 * outerHalfWidth * s },
			-- The whole model must fit inside this invisible wall.
			barrier_half_extents_studs = { barrierX, barrierY },
		},
		pockets = {
			casting_top = T.PocketCastingTopInches,
			casting_reach = T.PocketCastingReachInches,
			casting_blend = T.PocketCastingBlendInches,
			min_depth = T.MinPocketDepthInches,
			drop_depth = drop,
			fade_depth = fadeDepth,
			fade_drift = fadeDrift,
			jaw_radius = T.JawRadiusInches,
			corner = {
				mouth = T.CornerMouthInches,
				radius = T.CornerPocketRadiusInches,
				shelf = T.CornerShelfInches,
				facing_degrees = T.CornerFacingDegrees,
				-- Derived by Physics.Table to reach the shifted opening rim.
				facing_length = cornerFacingLength,
			},
			side = {
				mouth = T.SideMouthInches,
				radius = T.SidePocketRadiusInches,
				inset = T.SidePocketInsetInches,
				facing_degrees = T.SideFacingDegrees,
				facing_length = T.FacingLengthInches,
			},
		},
		holes = holes,
		segments = segments,
		points = points,
		cushions = cushions,
		spots = {
			head = { headX, headY },
			foot = { footX, footY },
			break_line_x = Config.Multiplayer.BreakLineX,
		},
		rack = {
			apex = { footX, footY },
			balls = rackBalls,
		},
	}
end

--- build() as the JSON text the tool writes: pretty, keys sorted, one trailing newline.
function TableGeometryExport.encode(): string
	local data = TableGeometryExport.build()
	-- serde writes NaN and inf as null; a broken geometry must fail here, not reach Blender.
	local function assertFinite(value: any, path: string)
		if type(value) == "number" then
			assert(value == value and math.abs(value) ~= math.huge, path .. " is not finite")
		elseif type(value) == "table" then
			for key, child in value do
				assertFinite(child, path .. "." .. tostring(key))
			end
		end
	end
	assertFinite(data, "Geometry.json")
	return serde.encode("json", data, true) .. "\n"
end

return TableGeometryExport
