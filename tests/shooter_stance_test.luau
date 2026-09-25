--!strict
-- ShooterStance tests: where the shooter stands, sits or kneels, and how they reach the cue.
--
-- The hard promises are geometric and easy to break with a sign: the cue is always its own
-- length and both hands are on it (the grip on its back part, the bridge on the cloth or the
-- rail top under it, never over a pocket), the body is in its support's region (on the floor
-- outside the rail, stretching over it with a foot on the floor, or kneeling on the cloth),
-- its torso and head clear the table and the cue, it is inside the match fence, and it stands up on the floor clear of
-- the barrier once the shot is away. A 360 degree sweep over positions, pitches, bodies and
-- team sizes holds all of that; walks and sweeps of the aim hold the rest.

local H = require("./harness")

local Config = H.require("Config")
local Placement = H.require("Placement")
local CueShape = H.require("CueShape")
local CueClearance = H.require("CueClearance")
local ShooterStance = H.require("ShooterStance")
local geometry = H.require("Physics.Table").build({ pocketsOpen = true })

local S = Config.Stance
local K = S.Clearance
local s = Config.Table.StudsPerInch
local TIERS = { stand = 1, lean = 1, stretch = 2, table = 3, rail = 4 }

-- The default R15 rig as AvatarPose.measureBody measures it in Studio.
local R15 = S.DefaultBody
-- The default R6 rig, measured the same way: root centre 3 above the floor (HipHeight 0),
-- hips 2, shoulder pivots 3.5, one arm 1.581 from its pivot to the grip attachment, legs 2
-- (rigid, so the whole leg is its "thigh" and it has no toes to rise on), the neck 4, the
-- head's centre 0.5 above it, the head 1 stud tall and deep.
local R6 = {
	RootHeight = 3,
	WaistHeight = 2,
	ShoulderHeight = 3.5,
	ShoulderHalfWidth = 1.0,
	ArmReach = 1.581,
	HalfWidth = 1.0,
	HalfDepth = 0.5,
	HipHeight = 2,
	ThighLength = 2,
	NeckHeight = 4,
	HeadLift = 0.5,
	HeadRadius = 0.5,
	ToeRise = 0,
}
local function scaled(body: any, k: number): any
	local out = {}
	for key, value in body do
		out[key] = value * k
	end
	return out
end
-- `small`: with a foot on the floor, a body this small cannot reach a ball frozen to a
-- cushion under a steep jump cue, even kneeling (about 2% of ordinary shots); it then stands
-- and its hands come as near the cue as they get. Every other body reaches every shot.
local BODIES = {
	{ name = "R15", body = R15 },
	{ name = "R6", body = R6, small = true },
	{ name = "R15 x0.8", body = scaled(R15, 0.8), small = true },
	{ name = "R15 x1.3", body = scaled(R15, 1.3) },
}

-- The drawn pitch the game would use: the chosen cue angle (default flat), raised as far as
-- the cue must go to clear the rail.
local function pitchFor(x: number, y: number, angle: number, floor: number?): number
	return CueClearance.pitch(
		geometry,
		{},
		{ cueX = x, cueY = y, angle = angle, floorDegrees = floor }
	).degrees
end

local function input(x: number, y: number, angle: number, pitch: number, body: any, area: any): any
	return {
		ballXIn = x,
		ballYIn = y,
		angle = angle,
		pitchDegrees = pitch,
		pull = 0,
		body = body,
		area = area,
	}
end

-- The cue's axis, worked out here from the same Config rather than taken from the module:
-- the strike point P (table studs, height above the floor) and the unit axis direction.
local function axisOf(q: any, pitch: number): (number, number, number, number, number, number)
	local back, right, up = CueShape.strikeOffset(q.spinX or 0, q.spinY or 0)
	local ax, ay = math.cos(q.angle), math.sin(q.angle)
	local theta = math.rad(pitch)
	return (q.ballXIn - ax * back + ay * right) * s,
		(q.ballYIn - ay * back - ax * right) * s,
		q.area.clothZ + (Config.Balls.RenderRadiusInches + up) * s,
		-ax * math.cos(theta),
		-ay * math.cos(theta),
		math.sin(theta)
end

-- Distance from a point to the cue's axis line, and how far along it (from the strike point).
local function offAxis(q: any, st: any, x: number, y: number, z: number): (number, number)
	local px, py, pz, ux, uy, uz = axisOf(q, st.pitchDegrees)
	local wx, wy, wz = x - px, y - py, z - pz
	local along = wx * ux + wy * uy + wz * uz
	local ex, ey, ez = wx - ux * along, wy - uy * along, wz - uz * along
	return math.sqrt(ex * ex + ey * ey + ez * ez), along
end

local function dist(ax: number, ay: number, az: number, bx: number, by: number, bz: number)
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end

local function boxDistance(x: number, y: number, hx: number, hy: number): number
	local ex, ey = math.max(0, math.abs(x) - hx), math.max(0, math.abs(y) - hy)
	return math.sqrt(ex * ex + ey * ey)
end

local function inside(x: number, y: number, hx: number, hy: number): boolean
	return math.abs(x) <= hx and math.abs(y) <= hy
end

-- The body as the stance posed it: the waist's height, where the shoulders' centre and each
-- shoulder are (table studs), from the root, the facing and the torso lean alone.
local function shoulders(st: any, body: any): any
	local T = body.ShoulderHeight - body.WaistHeight
	local a = math.rad(st.torsoDegrees)
	local fx, fy = math.cos(st.yaw), math.sin(st.yaw)
	local blx, bly = -fy, fx
	local waistZ = body.WaistHeight + (st.rootZ - body.RootHeight)
	local k = T * math.sin(a)
	local cx, cy, cz = st.rootX + fx * k, st.rootY + fy * k, waistZ + T * math.cos(a)
	local w = body.ShoulderHalfWidth
	return {
		a = a,
		fx = fx,
		fy = fy,
		k = k,
		waistZ = waistZ,
		cx = cx,
		cy = cy,
		cz = cz,
		right = { cx - blx * w, cy - bly * w, cz },
		left = { cx + blx * w, cy + bly * w, cz },
	}
end

-- What anything leaning over a plan point must clear.
local function under(area: any, x: number, y: number): number
	if inside(x, y, area.clothHx, area.clothHy) then
		return area.clothZ + K.ClothStuds
	elseif inside(x, y, area.railHx, area.railHy) then
		return area.railTopZ + K.RailStuds
	end
	return -math.huge
end

-- ...and the highest of those anywhere within r of it: a box within r counts.
local function highestNear(area: any, x: number, y: number, r: number): number
	local z = -math.huge
	if inside(x, y, area.clothHx + r, area.clothHy + r) then
		z = area.clothZ + K.ClothStuds
	end
	local deepInCloth = math.abs(x) + r <= area.clothHx and math.abs(y) + r <= area.clothHy
	if not deepInCloth and inside(x, y, area.railHx + r, area.railHy + r) then
		z = math.max(z, area.railTopZ + K.RailStuds)
	end
	return z
end

-- The head's centre as AvatarPose poses it: on the neck up the leaning spine, pitched at the
-- neck toward the cue ball's centre (Config.Avatar.Head), a pitch up tipping it back.
local function headOf(q: any, st: any, sh: any, body: any): (number, number, number)
	local sa, ca = math.sin(sh.a), math.cos(sh.a)
	local ux, uy, uz = sh.fx * sa, sh.fy * sa, ca
	local kx, ky, kz = -sh.fx * ca, -sh.fy * ca, sa
	local up = body.NeckHeight - body.WaistHeight
	local nx, ny, nz = st.rootX + ux * up, st.rootY + uy * up, sh.waistZ + uz * up
	local bx, by = q.ballXIn * s, q.ballYIn * s
	local bz = q.area.clothZ + Config.Balls.RenderRadiusInches * s
	local lx, ly, lz = bx - nx, by - ny, bz - nz
	local len = math.sqrt(lx * lx + ly * ly + lz * lz)
	local Look = Config.Avatar.Head
	local pitch = math.clamp(
		math.asin((lx * ux + ly * uy + lz * uz) / len) * Look.LookWeight,
		-math.rad(Look.MaxPitchDegrees),
		math.rad(Look.MaxPitchDegrees)
	)
	local lift = body.HeadLift
	local cp, sp = math.cos(pitch), math.sin(pitch)
	return nx + lift * (ux * cp + kx * sp),
		ny + lift * (uy * cp + ky * sp),
		nz + lift * (uz * cp + kz * sp)
end

local function sideNamed(name: string): any
	for _, side in S.Sides do
		if side.Name == name then
			return side
		end
	end
	return nil
end

local EPS = 1e-6

-- Everything a stance promises about itself, whatever the shot. With `mayMiss` (a small body)
-- a stance that reached nothing only has to be where it may be with its grip on the cue;
-- returns whether it reached.
local function checkStance(q: any, st: any, label: string, mayMiss: boolean?): boolean
	local body, area = q.body, q.area
	local C = Config.Cue
	local L = q.cueLengthStuds or C.CueLengthStuds
	local gR = C.CueRestGapInches * s

	-- The facing is one of the configured sides.
	local side = sideNamed(st.side)
	H.expect(side ~= nil, "unknown side " .. tostring(st.side) .. ": " .. label)
	H.near(st.yaw, q.angle - math.rad(side.TwistDegrees), 1e-12, "facing: " .. label)

	-- The support's region and height.
	local x, y = st.rootX, st.rootY
	if st.mode == "stand" or st.mode == "lean" then
		H.expect(
			boxDistance(x, y, area.railHx, area.railHy) >= S.FloorGapStuds - EPS,
			"standing against or in the table: " .. label
		)
	elseif st.mode == "stretch" then
		local St = S.Stretch
		local hi, lo = St.MaxOutStuds + EPS, St.MinOutStuds - EPS
		H.expect(
			inside(x, y, area.railHx + hi, area.railHy + hi)
				and not inside(x, y, area.railHx + lo, area.railHy + lo),
			"stretching but not by the rail edge: " .. label
		)
		-- The planted leg reaches the floor on its toes.
		H.expect(
			ShooterStance.hipHeight("stretch", body, area) <= body.HipHeight + body.ToeRise + EPS,
			"the planted foot is off the floor: " .. label
		)
	elseif st.mode == "rail" then
		local k = S.Table.RailKneelOutStuds
		H.expect(
			inside(x, y, area.railHx - k + EPS, area.railHy - k + EPS)
				and not inside(x, y, area.clothHx - EPS, area.clothHy - EPS),
			"kneeling off the rail top: " .. label
		)
	else
		H.expect(st.mode == "table", "unknown mode: " .. label)
		local k = S.Table.KneelInsetStuds
		H.expect(
			inside(x, y, area.clothHx - k + EPS, area.clothHy - k + EPS),
			"kneeling off the cloth: " .. label
		)
	end
	local hip = ShooterStance.hipHeight(st.mode, body, area)
	H.near(st.rootZ, body.RootHeight + hip - body.HipHeight, 1e-9, "root height: " .. label)

	-- Inside the fence (its box sits fenceCx along the table).
	local foot = math.sqrt(body.HalfDepth ^ 2 + body.HalfWidth ^ 2)
	H.expect(
		math.abs(x - area.fenceCx) <= area.fenceHx - foot - S.FenceMarginStuds + EPS
			and math.abs(y) <= area.fenceHy - foot - S.FenceMarginStuds + EPS,
		"outside the fence: " .. label
	)

	-- The grip: on the cue, on its back part, in the right arm's reach (at rest).
	local off = offAxis(q, st, st.grip.x, st.grip.y, st.grip.z)
	H.expect(off < 1e-9, "grip off the cue: " .. label)
	H.expect(
		st.gripFromTipStuds >= S.SteepGripMinFromTipFraction * L - EPS
			and st.gripFromTipStuds <= L - S.GripButtEndStuds + EPS,
		"grip off the cue's back part: " .. label
	)
	if mayMiss and not (st.gripReachable and st.bridgeReachable) then
		return false
	end
	H.expect(st.gripReachable, "the grip is out of reach: " .. label)
	local sh = shoulders(st, body)
	local px, py, pz, ux, uy, uz = axisOf(q, st.pitchDegrees)
	local restAlong = gR + st.gripFromTipStuds
	local gx, gy, gz = px + ux * restAlong, py + uy * restAlong, pz + uz * restAlong
	H.expect(
		dist(gx, gy, gz, sh.right[1], sh.right[2], sh.right[3])
			<= body.ArmReach * S.ArmMaxFraction + 1e-6,
		"the right arm does not reach the grip: " .. label
	)

	-- The bridge: under the cue, on the cloth or the rail top, never over a pocket, in the left
	-- arm's reach.
	local b = st.handBridge
	H.expect(st.bridgeReachable, "the bridge is out of reach: " .. label)
	local bOff, bAlong = offAxis(q, st, b.x, b.y, b.cueZ)
	H.expect(bOff < 1e-9, "the bridge is not under the cue: " .. label)
	H.near(bAlong, b.alongStuds, 1e-9, "bridge along: " .. label)
	H.expect(
		b.alongStuds <= math.max(S.MaxBridgeInches * s, S.BridgeFromBallInches * s) + 1,
		"the bridge is too far from the ball: " .. label
	)
	H.expect(b.alongStuds >= gR + S.BridgeTipClearInches * s - EPS, "bridge on the tip: " .. label)
	if b.onRail then
		H.near(b.surfaceZ, area.railTopZ, 1e-12, "rail bridge height: " .. label)
		local inset = S.RailBridgeInsetInches * s
		H.expect(
			inside(b.x, b.y, area.railHx - inset + EPS, area.railHy - inset + EPS)
				and not inside(b.x, b.y, area.clothHx + inset - EPS, area.clothHy + inset - EPS),
			"a rail bridge off the rail: " .. label
		)
	else
		H.near(b.surfaceZ, area.clothZ, 1e-12, "cloth bridge height: " .. label)
		local inset = S.BridgeFrozenInsetInches * s
		H.expect(
			inside(b.x, b.y, area.clothHx - inset + EPS, area.clothHy - inset + EPS),
			"a cloth bridge off the cloth: " .. label
		)
	end
	for _, pocket in area.pockets do
		H.expect(
			(b.x - pocket.x) ^ 2 + (b.y - pocket.y) ^ 2 >= pocket.r ^ 2 - EPS,
			"a bridge over a pocket: " .. label
		)
	end
	local rise = b.cueZ - b.surfaceZ
	H.expect(rise >= S.BridgeMinRiseStuds - EPS, "the cue lies on the surface: " .. label)
	if not b.raised then
		H.expect(rise <= S.BridgeMaxRiseStuds + EPS, "the cue floats over the hand: " .. label)
		H.near(b.handZ, b.surfaceZ + S.BridgeHandHeightStuds, 1e-12, "hand height: " .. label)
	else
		H.expect(b.cueZ - b.handZ <= S.BridgeMaxRiseStuds + EPS, "a raised hand far under the cue")
	end
	-- The bridge arm reaches out as far as BridgeArmExtendFraction takes it (the search's own
	-- reach may be longer).
	local reach = body.ArmReach
		* math.max(
			S.BridgeArmExtendFraction,
			if st.mode == "stand"
				then S.ArmNaturalFraction
				elseif st.mode == "lean" then S.ArmNaturalFraction
					+ (S.ArmMaxFraction - S.ArmNaturalFraction) * st.lean
				else S.ArmMaxFraction
		)
	H.expect(
		dist(b.x, b.y, b.handZ, sh.left[1], sh.left[2], sh.left[3]) <= reach + 1e-4,
		("the left arm does not reach the bridge (%.4f > %.4f): %s"):format(
			dist(b.x, b.y, b.handZ, sh.left[1], sh.left[2], sh.left[3]),
			reach,
			label
		)
	)

	-- The torso and head clear the table, and the cue passes clear of them.
	local function cueDistance(qx: number, qy: number, qz: number): number
		local wx, wy, wz = qx - px, qy - py, qz - pz
		local along = math.clamp(wx * ux + wy * uy + wz * uz, gR, gR + L)
		return dist(qx, qy, qz, px + ux * along, py + uy * along, pz + uz * along)
	end
	for _, t in K.TorsoFractions do
		local tx, ty = x + sh.fx * sh.k * t, y + sh.fy * sh.k * t
		local tz = sh.waistZ + (sh.cz - sh.waistZ) * t
		local floor = under(area, tx, ty)
		local onRail = not inside(tx, ty, area.clothHx, area.clothHy)
			and inside(tx, ty, area.railHx, area.railHy)
		if st.mode == "stretch" and t < 0.5 and onRail then
			floor -= S.Stretch.BellyIntoRailStuds -- the belly on the rail edge
		end
		H.expect(tz - K.TorsoHalfThicknessStuds >= floor - EPS, "torso: " .. label)
		H.expect(cueDistance(tx, ty, tz) >= K.CueTorsoStuds - EPS, "cue in torso: " .. label)
	end
	local hx, hy, hz = headOf(q, st, sh, body)
	local r = body.HeadRadius
	H.expect(
		hz - r - K.HeadGapStuds >= highestNear(area, hx, hy, r) - EPS,
		"head in the table: " .. label
	)
	H.expect(cueDistance(hx, hy, hz) >= r + K.CueHeadStuds - EPS, "cue in the head: " .. label)

	-- The idle spot: on the floor, clear of the barrier (and turning there is clear too).
	local ix, iy, iz = ShooterStance.idle(st)
	H.near(iz, body.RootHeight, 1e-12, "idle on the floor: " .. label)
	local grow = math.max(foot, area.releaseClearance)
	H.expect(
		not inside(ix, iy, area.barrierHx + grow - EPS, area.barrierHy + grow - EPS),
		"idle inside the barrier: " .. label
	)
	return true
end

-- Solve with one Config key set otherwise, putting it back even if the solve fails.
local function solveWith(t: any, key: string, value: any, q: any): any
	local was = t[key]
	t[key] = value
	local ok, result = pcall(ShooterStance.solve, q)
	t[key] = was
	if not ok then
		error(result, 0)
	end
	return result
end

local function sweepSpots(): { { number } }
	local spots = {}
	for _, x in { -36, -12, 12, 36 } do
		for _, y in { -15, 0, 15 } do
			table.insert(spots, { x, y })
		end
	end
	local R = Config.Balls.RadiusInches
	local hl, hw = geometry.halfLength - R, geometry.halfWidth - R -- frozen to a cushion
	for _, spot in
		{
			{ hl, 10 },
			{ -hl, -10 },
			{ 20, hw },
			{ -20, -hw },
			{ 47, 22 },
			{ -47, 22 },
			{ 47, -22 },
			{ -47, -22 },
			{ 0, 0 },
			{ -47, 0 },
		}
	do
		table.insert(spots, spot)
	end
	return spots
end

return {
	["sweep: 360 degrees round the table, both hands on the cue, the body where it may be"] = function()
		local tiers: { [string]: { number } } = {}
		local solves = 0
		local misses: { [string]: number } = {}
		for _, teamSize in { 1, 3 } do
			local area = ShooterStance.area(teamSize)
			for _, spot in sweepSpots() do
				for step = 0, 71 do
					local angle = math.rad(step * 5)
					for _, chosen in { 4, 20, 40 } do
						local pitch = pitchFor(spot[1], spot[2], angle, chosen)
						for _, b in BODIES do
							local q = input(spot[1], spot[2], angle, pitch, b.body, area)
							q.pull = step % 2
							local st = ShooterStance.solve(q)
							solves += 1
							local label = ("%s team %d ball (%.2f, %.2f) at %d, pitch %d"):format(
								b.name,
								teamSize,
								spot[1],
								spot[2],
								step * 5,
								chosen
							)
							if not checkStance(q, st, label, b.small) then
								misses[b.name] = (misses[b.name] or 0) + 1
							end
							local row = tiers[b.name] or { 0, 0, 0, 0 }
							tiers[b.name] = row
							row[TIERS[st.mode]] += 1
						end
					end
				end
			end
		end
		H.expect(solves <= 40000, ("the sweep grew to %d solves"):format(solves))
		-- The sweep's spots are the hard ones (frozen to cushions, in the corners, steep cues):
		-- a small body still reaches nearly all of them.
		for _, b in BODIES do
			local n = 0
			for _, count in tiers[b.name] do
				n += count
			end
			H.expect(
				(misses[b.name] or 0) <= 0.1 * n,
				("%s reached nothing in %d of %d"):format(b.name, misses[b.name] or 0, n)
			)
		end
		-- A shorter reach climbs at least as often.
		local function climbs(name: string): number
			local row = tiers[name]
			return row[2] + row[3] + row[4]
		end
		H.expect(climbs("R15 x0.8") >= climbs("R15"), "a small body climbs less often")
		H.expect(climbs("R15 x1.3") <= climbs("R15"), "a big body climbs more often")
	end,

	-- The split over an even grid of ordinary shots (flat cue): about half from the floor and
	-- the far-in ones kneeling on the table (a foot on the floor reaches only so far onto a
	-- table this size; designer, 2026-09-25). Printed so a tuning change shows what it did.
	["most shots are taken from the floor, few from the table"] = function()
		local area = ShooterStance.area(1)
		local L, W = Config.Table.LengthInches, Config.Table.WidthInches
		local R = Config.Balls.RadiusInches
		local count, n = { 0, 0, 0, 0 }, 0
		for i = 0, 16 do
			for j = 0, 8 do
				local x = -L / 2 + R + (L - 2 * R) * i / 16
				local y = -W / 2 + R + (W - 2 * R) * j / 8
				for k = 0, 35 do
					local angle = k / 36 * 2 * math.pi
					local st =
						ShooterStance.solve(input(x, y, angle, pitchFor(x, y, angle), R15, area))
					count[TIERS[st.mode]] += 1
					n += 1
				end
			end
		end
		local floor, stretch, tbl, rail = count[1] / n, count[2] / n, count[3] / n, count[4] / n
		print(
			("        R15: floor %.1f%%, stretch %.1f%%, table %.1f%%, rail %.1f%%"):format(
				floor * 100,
				stretch * 100,
				tbl * 100,
				rail * 100
			)
		)
		H.expect(floor >= 0.45, "fewer than 45% of shots from the floor")
		H.expect(tbl + rail <= 0.5, "more than half the shots kneeling on the table")
		H.expect(rail <= 0.01, "the default body kneels on the rail top")
	end,

	-- A comfortable shot is taken standing, near upright, in the open stance with the chin over
	-- the cue or just beside it (right over it, a real head would sit too low over the rail).
	["a comfortable shot is a natural stance at the natural distance"] = function()
		local C = Config.Cue
		local area = ShooterStance.area(1)
		local q = input(-40, 0, 0, C.CueElevationDegrees, R15, area)
		local st = ShooterStance.solve(q)
		H.expect(st.mode == "stand" or st.mode == "lean", "stands: " .. st.mode)
		H.expect(st.side == "classic" or st.side == "classicOut", "the open stance: " .. st.side)
		H.expect(st.torsoDegrees <= S.LeanNaturalDegrees + 5, "near the natural lean")
		-- The root no further back along the cue than where the grip sits just behind the hip at
		-- its natural place on the cue (nearer, when the bridge hand wants it), and clear of the
		-- rail.
		local gR, L = C.CueRestGapInches * s, C.CueLengthStuds
		local c = math.cos(math.rad(C.CueElevationDegrees))
		local px = axisOf(q, C.CueElevationDegrees)
		local natural = (gR + L * (1 - S.GripFromButtFraction)) * c - S.GripBehindRootStuds
		local outside = px + area.railHx + S.FloorGapStuds -- the root's distance to stand clear
		H.expect(px - st.rootX <= natural + 1e-9, "further back than natural")
		H.expect(px - st.rootX >= outside - 1e-9, "against the rail")
		checkStance(q, st, "comfortable")
	end,

	-- The designer's example: a ball by a side rail with the shot running along it. A player
	-- plays it from that side rail beside the ball, not away at the end rail: from the floor
	-- when it reaches, else kneeling on the cloth by that rail.
	["a ball by the side rail, shot along it, is played from that side rail"] = function()
		local area = ShooterStance.area(1)
		for _, case in { { -10, 20, 0 }, { 10, -20, math.pi }, { 6, 20, 0 } } do
			local x, y, angle = case[1], case[2], case[3]
			local q = input(x, y, angle, pitchFor(x, y, angle), R15, area)
			local st = ShooterStance.solve(q)
			local label = ("ball (%d, %d) at %.2f"):format(x, y, angle)
			checkStance(q, st, label)
			-- On that side of the table, level with the ball rather than at the end rail.
			H.expect(st.rootY * y > 0, "the body is on the far side: " .. label)
			H.expect(math.abs(st.rootY) >= math.abs(y) * s - 1, "not by that rail: " .. label)
			H.expect(math.abs(st.rootX) < area.railHx, "at the end rail: " .. label)
		end
	end,

	["the table's supports only step up as the ball moves away"] = function()
		for _, b in { { "R15", R15, false }, { "R6", R6, true } } do
			for _, line in { { 0, 1 }, { 10, 1 }, { 0, -1 } } do
				local y, dir = line[1], line[2]
				local angle = if dir > 0 then 0 else math.pi
				local area = ShooterStance.area(1)
				local last, memory = 0, nil
				for i = -48, 48 do
					local x = i * dir
					local q = input(x, y, angle, pitchFor(x, y, angle), b[2], area)
					q.memory = memory
					local st = ShooterStance.solve(q)
					memory = st.memory
					local label = ("%s ball (%d, %d) toward %s"):format(b[1], x, y, tostring(dir))
					if checkStance(q, st, label, b[3]) then
						H.expect(TIERS[st.mode] >= last, "stepped back down: " .. label)
						last = TIERS[st.mode]
					end
				end
				H.expect(
					last >= TIERS.stretch,
					"a ball at the far rail is not reached from the floor"
				)
			end
		end
	end,

	["the grip rides the cue through the wind-up; the root stays put"] = function()
		local area = ShooterStance.area(1)
		for _, spot in sweepSpots() do
			for step = 0, 11 do
				local angle = math.rad(step * 30 + 7)
				for _, b in BODIES do
					local q = input(
						spot[1],
						spot[2],
						angle,
						pitchFor(spot[1], spot[2], angle),
						b.body,
						area
					)
					local rest = ShooterStance.solve(q)
					q.pull = 1
					local full = ShooterStance.solve(q)
					H.expect(rest.rootX == full.rootX and rest.rootY == full.rootY, "root moved")
					H.expect(rest.mode == full.mode and rest.side == full.side, "pose changed")
					local _, _, _, ux, uy, uz = axisOf(q, rest.pitchDegrees)
					local slide = Config.Cue.CuePullBackStuds * rest.pullLimit
					H.near(full.grip.x - rest.grip.x, ux * slide, 1e-9, "grip x")
					H.near(full.grip.y - rest.grip.y, uy * slide, 1e-9, "grip y")
					H.near(full.grip.z - rest.grip.z, uz * slide, 1e-9, "grip z")
					H.near(full.cueGapStuds - rest.cueGapStuds, slide, 1e-12, "the gap")
					H.near(full.gripFromTipStuds, rest.gripFromTipStuds, 1e-12, "same hold")
				end
			end
		end
	end,

	-- Turning the aim all the way round, a frame at a time as a player does, the body moves
	-- smoothly within a pose, with at most a few hops, and changes pose rarely, never flicking
	-- straight back. (A change of pose, the bridge hand moving between the cloth and the rail
	-- included, and a hop may move the root further: the poser glides it there.)
	["turning the aim round: few pose changes, no flicker, a smooth root in between"] = function()
		local area = ShooterStance.area(1)
		for _, ball in { { 0, 0 }, { -30, 12 }, { 44, -20 }, { -10, 20 }, { -47, -22 } } do
			local memory, last = nil, nil
			local changes, hops, history = 0, 0, {}
			for tenth = 0, 3600, 5 do
				local angle = math.rad(tenth / 10)
				local q =
					input(ball[1], ball[2], angle, pitchFor(ball[1], ball[2], angle), R15, area)
				q.memory = memory
				local st = ShooterStance.solve(q)
				memory = st.memory
				-- A pose: the support, the side and the bridge's surface.
				local function poseKey(x: any): string
					return x.mode .. "/" .. x.side .. "/" .. tostring(x.handBridge.onRail)
				end
				local key = poseKey(st)
				if last then
					local lastKey = poseKey(last)
					local moved =
						math.sqrt((st.rootX - last.rootX) ^ 2 + (st.rootY - last.rootY) ^ 2)
					if key == lastKey then
						-- Within a pose the root moves a little per step; a rare hop (the least
						-- lean that reaches finding a different spot) the poser glides over.
						if moved > 0.6 then
							hops += 1
						end
					else
						changes += 1
						-- Never straight back to the pose of a moment ago (within 1 degree).
						local back = history[#history - 1]
						if back and back.key == key then
							H.expect(
								tenth - back.at > 10,
								("flicker %s at %.1f deg"):format(key, tenth / 10)
							)
						end
					end
				end
				if not last or key ~= poseKey(last) then
					table.insert(history, { key = key, at = tenth })
				end
				last = st
			end
			H.expect(
				changes <= 30,
				("%d pose changes round ball (%d, %d)"):format(changes, ball[1], ball[2])
			)
			H.expect(hops <= 4, ("%d hops round ball (%d, %d)"):format(hops, ball[1], ball[2]))
		end
	end,

	["a ball near the shooter's cushion bridges on the rail and shortens the wind-up"] = function()
		local area = ShooterStance.area(1)
		local q = input(-46, 0, 0, pitchFor(-46, 0, 0), R15, area)
		local st = ShooterStance.solve(q)
		local bridge = st.handBridge
		H.expect(bridge.onRail, "on the rail")
		H.near(bridge.surfaceZ, area.railTopZ, 1e-12, "on the rail top")
		H.expect(st.pullLimit < 1, "the wind-up is cut short")
		-- At a full pull the tip still stops BridgeTipClear short of the bridge.
		q.pull = 1
		local full = ShooterStance.solve(q)
		H.expect(
			full.handBridge.alongStuds - full.cueGapStuds >= S.BridgeTipClearInches * s - 1e-9,
			"the tip passes the bridge"
		)
		checkStance(q, full, "near cushion")
	end,

	["a ball frozen to a cushion, the cue along it, bridges right against the cushion"] = function()
		local area = ShooterStance.area(1)
		local R = Config.Balls.RadiusInches
		local x = -(geometry.halfLength - R)
		for _, angle in { math.pi / 2, -math.pi / 2 } do
			local q = input(x, 0, angle, pitchFor(x, 0, angle), R15, area)
			local st = ShooterStance.solve(q)
			checkStance(q, st, "frozen")
			H.expect(not st.handBridge.onRail and not st.handBridge.raised, "on the cloth")
			H.expect(
				math.abs(st.handBridge.x) > area.clothHx - S.BridgeCushionInsetInches * s,
				"closer to the cushion than an ordinary bridge"
			)
		end
	end,

	["the same input always gives the same stance"] = function()
		local area = ShooterStance.area(3)
		local function flat(st: any): string
			local parts = {}
			local function add(prefix: string, t: any)
				local keys = {}
				for key in t do
					table.insert(keys, key)
				end
				table.sort(keys)
				for _, key in keys do
					local v = t[key]
					if type(v) == "table" then
						add(prefix .. key .. ".", v)
					else
						table.insert(parts, prefix .. key .. "=" .. tostring(v))
					end
				end
			end
			add("", st)
			return table.concat(parts, ";")
		end
		for _, b in BODIES do
			for _, spot in sweepSpots() do
				local q = input(spot[1], spot[2], 2.1, 12, b.body, area)
				q.spinX, q.spinY, q.pull = 0.2, -0.3, 0.6
				local first = ShooterStance.solve(q)
				H.expect(flat(first) == flat(ShooterStance.solve(q)), "not deterministic")
				q.memory = first.memory
				H.expect(flat(ShooterStance.solve(q)) == flat(ShooterStance.solve(q)), "memory")
			end
		end
	end,

	-- The memory only breaks near-ties: the stance it keeps is always one the search could
	-- have picked on its own (checkStance holds either way), and on an ordinary shot it
	-- changes nothing at all.
	["the memory only keeps a near-equal pose"] = function()
		local area = ShooterStance.area(1)
		local q = input(-40, 0, 0, 4, R15, area)
		local plain = ShooterStance.solve(q)
		q.memory = { mode = "stretch", side = "square", onRail = true }
		local remembered = ShooterStance.solve(q)
		H.expect(
			remembered.mode == plain.mode and remembered.side == plain.side,
			"kept a worse pose"
		)
		H.expect(remembered.rootX == plain.rootX and remembered.rootY == plain.rootY, "moved")
	end,

	["after the shot the shooter stands up on the floor facing the table centre"] = function()
		for _, teamSize in { 1, 3 } do
			local area = ShooterStance.area(teamSize)
			for _, spot in sweepSpots() do
				for step = 0, 23 do
					local angle = math.rad(step * 15)
					local pitch = pitchFor(spot[1], spot[2], angle)
					for _, b in BODIES do
						local st =
							ShooterStance.solve(input(spot[1], spot[2], angle, pitch, b.body, area))
						local x, y, z, yaw = ShooterStance.idle(st)
						H.near(z, b.body.RootHeight, 1e-12, "on the floor")
						local d = math.sqrt(x * x + y * y)
						H.near(math.cos(yaw) * -x + math.sin(yaw) * -y, d, 1e-9, "faces the centre")
						-- Standing well clear already: the very same spot.
						local foot = math.sqrt(b.body.HalfDepth ^ 2 + b.body.HalfWidth ^ 2)
						local grow = math.max(foot, area.releaseClearance) + S.SlopStuds
						if
							not inside(
								st.rootX,
								st.rootY,
								area.barrierHx + grow,
								area.barrierHy + grow
							)
						then
							H.near(x, st.rootX, 1e-9, "moved though clear")
							H.near(y, st.rootY, 1e-9, "moved though clear")
						end
						-- Clear of the barrier and inside the fence at any facing.
						H.expect(
							not inside(
								x,
								y,
								area.barrierHx + grow - EPS,
								area.barrierHy + grow - EPS
							),
							"idle in the barrier"
						)
						H.expect(
							math.abs(x - area.fenceCx)
								<= math.max(
										area.fenceHx,
										area.barrierHx + grow + math.abs(area.fenceCx)
									)
									+ EPS,
							"idle outside the fence"
						)
					end
				end
			end
		end
	end,

	["the area matches the table, the barrier and the fence"] = function()
		local T = Config.Table
		local area = ShooterStance.area(2)
		local bx, by = Placement.barrierHalfExtents()
		local fx, fy, fcx = Placement.fenceHalfExtents(2)
		H.near(area.clothHx, T.LengthInches / 2 * s, 1e-12, "cloth")
		H.near(area.railHy, (T.WidthInches / 2 + T.RailWidthInches) * s, 1e-12, "rail")
		H.expect(area.barrierHx == bx and area.barrierHy == by, "barrier")
		H.expect(area.fenceHx == fx and area.fenceHy == fy and area.fenceCx == fcx, "fence")
		H.near(area.railTopZ - area.clothZ, T.RailTopInches * s, 1e-12, "rail top")
		H.expect(area.releaseClearance == Config.Multiplayer.Barrier.ReleaseClearanceStuds, "rc")
		H.expect(#area.pockets == 6, "six pockets")
		for _, pocket in area.pockets do
			H.expect(math.abs(math.abs(pocket.y) - area.clothHy) < 1e-12, "pockets on the rails")
		end
	end,

	-- Without a hand bridge that sits low enough (a steep jump cue with the ball far in), the
	-- hand stands up under the cue rather than leaving it floating.
	["a steep cue far from any rail raises the bridge hand under it"] = function()
		local area = ShooterStance.area(1)
		local q = input(0, 0, 0, 45, R15, area)
		local st = solveWith(S, "BridgeMaxRiseStuds", 0.2, q)
		H.expect(st.handBridge.raised, "raised")
		H.expect(st.handBridge.cueZ - st.handBridge.handZ <= 0.2 + 1e-9, "the hand under the cue")
	end,
}
