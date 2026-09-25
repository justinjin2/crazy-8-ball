--!strict
-- ShooterStance tests: where the shooter stands and how they reach the cue.
--
-- The hard promises are geometric and easy to break with a sign: the body never stands in
-- or against the table (outside the barrier by the release clearance, at every facing and
-- table yaw), never outside the match fence, holds the cue ON the cue, and changes pose in
-- one direction as a ball moves out of reach - not back and forth at a boundary. A 360
-- degree sweep over positions, pitches, bodies and team sizes holds the first three, and
-- walks along the table hold the rest.

local H = require("./harness")

local Config = H.require("Config")
local Placement = H.require("Placement")
local CueShape = H.require("CueShape")
local CueClearance = H.require("CueClearance")
local ShooterStance = H.require("ShooterStance")
local geometry = H.require("Physics.Table").build({ pocketsOpen = true })

local S = Config.Stance
local s = Config.Table.StudsPerInch
local MODES = { stand = 1, lean = 2, bridge = 3, extension = 4 }

-- The default R15 rig as AvatarPose.measureBody measures it in Studio.
local R15 = S.DefaultBody
-- The default R6 rig, measured the same way: root centre 3 above the floor (HipHeight 0),
-- hips 2, shoulder pivots 3.5, one arm 1.581 from its pivot to the grip attachment.
local R6 = {
	RootHeight = 3,
	WaistHeight = 2,
	ShoulderHeight = 3.5,
	ShoulderHalfWidth = 1.0,
	ArmReach = 1.581,
	HalfWidth = 1.0,
	HalfDepth = 0.5,
}
local function scaled(body: any, k: number): any
	local out = {}
	for key, value in body do
		out[key] = value * k
	end
	return out
end
local BODIES = {
	{ name = "R15", body = R15 },
	{ name = "R6", body = R6 },
	{ name = "R15 x0.8", body = scaled(R15, 0.8) },
	{ name = "R15 x1.3", body = scaled(R15, 1.3) },
}

local function pitchFor(x: number, y: number, angle: number): number
	return CueClearance.pitch(geometry, {}, { cueX = x, cueY = y, angle = angle }).degrees
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

-- Distance from a point to the cue's axis line.
local function offAxis(q: any, st: any, x: number, y: number, z: number): number
	local px, py, pz, ux, uy, uz = axisOf(q, st.pitchDegrees)
	local wx, wy, wz = x - px, y - py, z - pz
	local along = wx * ux + wy * uy + wz * uz
	local ex, ey, ez = wx - ux * along, wy - uy * along, wz - uz * along
	return math.sqrt(ex * ex + ey * ey + ez * ez)
end

-- The body's footprint half extents at the stance's facing.
local function footprint(st: any, body: any): (number, number)
	local fx, fy = math.cos(st.yaw), math.sin(st.yaw)
	return body.HalfDepth * math.abs(fx) + body.HalfWidth * math.abs(fy),
		body.HalfDepth * math.abs(fy) + body.HalfWidth * math.abs(fx)
end

local PLACEMENTS = { Placement.new(10, 2.4, -43, 0), Placement.new(-30, 0, 5, 90) }

-- Outside the barrier by the release clearance at both table yaws, footprint clear of the
-- barrier, inside the fence.
local function checkPlace(st: any, body: any, area: any, label: string)
	for _, p in PLACEMENTS do
		local wx, _, wz = Placement.fromTableStuds(p, st.rootX, st.rootY, st.rootZ)
		local ix = Placement.outsideBarrier(p, wx, wz, area.releaseClearance)
		if ix ~= nil then
			error("root inside the barrier's release clearance: " .. label)
		end
	end
	local ex, ey = footprint(st, body)
	local ux, uy = math.abs(st.rootX), math.abs(st.rootY)
	if ux < area.barrierHx + ex - 1e-9 and uy < area.barrierHy + ey - 1e-9 then
		error("footprint overlaps the barrier: " .. label)
	end
	-- The fence box sits fenceCx along the table (it is longer at the head than the foot).
	local fx = math.abs(st.rootX - area.fenceCx)
	if fx > area.fenceHx - ex + 1e-9 or uy > area.fenceHy - ey + 1e-9 then
		error("footprint outside the fence: " .. label)
	end
	if not st.fenceClamped then
		local m = S.FenceMarginStuds
		if fx > area.fenceHx - ex - m + 1e-9 or uy > area.fenceHy - ey - m + 1e-9 then
			error("inside the fence margin without being clamped: " .. label)
		end
	end
end

-- Everything a stance promises about itself, whatever the shot.
local function checkStance(q: any, st: any, label: string)
	local body = q.body
	checkPlace(st, body, q.area, label)
	local L = q.cueLengthStuds or Config.Cue.CueLengthStuds
	if offAxis(q, st, st.grip.x, st.grip.y, st.grip.z) > 1e-9 then
		error("grip off the cue: " .. label)
	end
	if st.gripFromTipStuds < 0 or st.gripFromTipStuds > L + st.extensionStuds + 1e-9 then
		error("grip beyond the cue: " .. label)
	end
	if math.abs(st.yaw - (q.angle - math.rad(S.TwistDegrees))) > 1e-12 then
		error("facing is not the open stance: " .. label)
	end
	local stands = st.mode == "stand" or st.mode == "lean"
	if stands ~= (st.handBridge ~= nil) or stands == (st.rake ~= nil) then
		error("bridge and rake do not match the mode: " .. label)
	end
	if st.mode == "extension" then
		local E, short = st.extensionStuds, st.shortfallStuds
		local fits = E >= short - 1e-9 and E <= short + S.ExtensionMarginStuds + 1e-9
		local maxed = E == S.MaxExtensionStuds and not st.gripReachable
		if E <= 0 or not (fits or maxed) then
			error(("extension %.3f for a shortfall of %.3f: %s"):format(E, short, label))
		end
	elseif st.extensionStuds ~= 0 then
		error("an extension outside extension mode: " .. label)
	end
	if not (st.pullLimit >= 0 and st.pullLimit <= 1) then
		error("pull limit out of range: " .. label)
	end
end

-- The rake's shaft as BridgeBuilder.place draws it, worked out here the same way in table
-- studs (z up): the model turned about the notch with its plate upright and no roll, aimed
-- from the shaft's start through the hold until that settles. Returns the start (the shaft's
-- attachment) and the unit direction of the shaft.
local function drawnShaft(rake: any): (number, number, number, number, number, number)
	local B = Config.Bridge
	local nx, ny = 0, 0
	for _, n in B.Notches do
		if n.Name == rake.notch then
			nx, ny = n.X, n.Y
		end
	end
	local rise = B.ShaftAxisYStuds - ny
	-- The start for a shaft along u: the bridge's +X is level and square to it (z x u), its
	-- +Y is u x X.
	local function start(ux: number, uy: number, uz: number): (number, number, number)
		local plan = math.sqrt(ux * ux + uy * uy)
		local rx, ry = -uy / plan, ux / plan
		local upx, upy, upz = -uz * ry, uz * rx, ux * ry - uy * rx
		return rake.headX - rx * nx + upx * rise,
			rake.headY - ry * nx + upy * rise,
			rake.headZ + upz * rise
	end
	local function unit(x: number, y: number, z: number): (number, number, number)
		local m = math.sqrt(x * x + y * y + z * z)
		return x / m, y / m, z / m
	end
	local ux, uy, uz =
		unit(rake.holdX - rake.headX, rake.holdY - rake.headY, rake.holdZ - rake.headZ)
	for _ = 1, 8 do
		local sx, sy, sz = start(ux, uy, uz)
		local vx, vy, vz = rake.holdX - sx, rake.holdY - sy, rake.holdZ - sz
		if math.sqrt(vx * vx + vy * vy + vz * vz) < 1e-6 then
			break
		end
		vx, vy, vz = unit(vx, vy, vz)
		local settled = math.sqrt((vx - ux) ^ 2 + (vy - uy) ^ 2 + (vz - uz) ^ 2) < 1e-9
		ux, uy, uz = vx, vy, vz
		if settled then
			break
		end
	end
	local sx, sy, sz = start(ux, uy, uz)
	return sx, sy, sz, ux, uy, uz
end

-- The rake's own promises: the head under the cue on the cloth, the notch at the cue's
-- height or the hover said so, the shaft as drawn over the rail, the hand on a shaft that
-- long.
local function checkRake(q: any, st: any, label: string): (boolean, boolean, string)
	local rake = st.rake
	local B, K = Config.Bridge, S.Rake
	local area = q.area
	local px, py, pz, ux, uy, uz = axisOf(q, st.pitchDegrees)
	local plan = math.sqrt(ux * ux + uy * uy)
	-- Under the cue: on the cue's line in plan, behind the ball.
	local hx, hy = rake.headX - px, rake.headY - py
	local h = (hx * ux + hy * uy) / plan
	if h <= 0 or math.abs(hx * uy - hy * ux) / plan > 1e-9 then
		error("rake head is not under the cue: " .. label)
	end
	local inset = K.HeadInsetInches * s
	local notch = nil
	for _, n in B.Notches do
		if n.Name == rake.notch then
			notch = n
		end
	end
	assert(notch, "unknown notch " .. tostring(rake.notch))
	-- The head's centre line, X to the cue's left (+X is the aim's right).
	local ax, ay = math.cos(q.angle), math.sin(q.angle)
	local centreX, centreY = rake.headX - notch.X * ay, rake.headY + notch.X * ax
	if rake.onCloth then
		for _, point in { { rake.headX, rake.headY }, { centreX, centreY } } do
			if
				math.abs(point[1]) > area.clothHx - inset + 1e-9
				or math.abs(point[2]) > area.clothHy - inset + 1e-9
			then
				error("rake head is not on the cloth: " .. label)
			end
		end
	else
		-- Only allowed when no point of the cue line past the resting tip stands on the cloth
		-- inside the inset: walk it and look.
		local restTip = (Config.Cue.CueRestGapInches + S.BridgeTipClearInches) * s * plan
		for i = 0, 400 do
			local t = restTip + i * 0.025
			local x, y = px + ux / plan * t, py + uy / plan * t
			if
				math.abs(x) < area.clothHx - inset - 1e-6
				and math.abs(y) < area.clothHy - inset - 1e-6
			then
				-- The High notch (X = 0) could have stood here.
				error(("rake head off the cloth without cause (%.3f): %s"):format(t, label))
			end
		end
	end
	-- The hand bridge the off hand makes when no rake is drawn: under the cue,
	-- behind the ball, on the cloth or the rail top, and never off the table, however far
	-- down the cue line an off-cloth head has run.
	local fallback = rake.bridge
	local bx, by = fallback.x - px, fallback.y - py
	if (bx * ux + by * uy) / plan <= 0 or math.abs(bx * uy - by * ux) / plan > 1e-9 then
		error("the rake's fallback hand bridge is not under the cue: " .. label)
	end
	if
		fallback.surfaceZ ~= (if fallback.onRail then area.railTopZ else area.clothZ)
		or math.abs(fallback.x) > area.railHx + 1e-9
		or math.abs(fallback.y) > area.railHy + 1e-9
	then
		error("the rake's fallback hand bridge is off the table: " .. label)
	end
	H.near(rake.headZ, area.clothZ + B.PivotHeightStuds + notch.Y, 1e-9, "the notch's height")
	local cueZ = pz + h * uz / plan
	H.near(rake.cueZ, cueZ, 1e-9, "the cue's height over the head")
	local err = cueZ - rake.headZ
	if rake.hover == 0 then
		if math.abs(err) > K.NotchToleranceStuds + 1e-9 then
			error(("the cue is %.3f off the notch: %s"):format(err, label))
		end
	elseif math.abs(rake.hover - err) > 1e-9 or math.abs(err) <= K.NotchToleranceStuds then
		error("hover does not report the cue's height: " .. label)
	end
	-- The shaft as drawn, with the hand on it, sampled from its start to the hand against the
	-- rail (only promised for a head on the cloth).
	local attachX, attachY, attachZ, sux, suy, suz = drawnShaft(rake)
	local vx, vy, vz = rake.holdX - attachX, rake.holdY - attachY, rake.holdZ - attachZ
	local held = vx * sux + vy * suy + vz * suz
	local off = math.sqrt(math.max(0, vx * vx + vy * vy + vz * vz - held * held))
	if held <= 0 or off > 1e-6 then
		error(("the hand is %.2g off the drawn shaft: %s"):format(off, label))
	end
	local run = math.sqrt(vx * vx + vy * vy)
	local across = math.sqrt(sux * sux + suy * suy)
	local k = suz / across
	local r = B.ShaftButtRadiusStuds
	local under = r * math.sqrt(1 + k * k)
	local need = area.railTopZ + K.RailClearanceInches * s - 1e-6
	for i = 0, 200 do
		local t = run * i / 200
		local x, y = attachX + sux / across * t, attachY + suy / across * t
		local ox, oy = math.abs(x), math.abs(y)
		local overRail = (ox > area.clothHx - r or oy > area.clothHy - r)
			and ox < area.railHx + r
			and oy < area.railHy + r
		if rake.onCloth and overRail and attachZ + k * t - under < need then
			error("the rake's shaft touches the rail: " .. label)
		end
	end
	-- A head nearer than a full wind-up needs cuts the drawn wind-up: at a full pull the tip
	-- still stops BridgeTipClear short of it.
	local fullGap = Config.Cue.CueRestGapInches * s + st.pullLimit * Config.Cue.CuePullBackStuds
	if h / plan - fullGap < S.BridgeTipClearInches * s - 1e-9 then
		error("the tip reaches the rake's head: " .. label)
	end
	H.near(rake.length, held + K.HandleBeyondHandStuds, 1e-9, "length")
	-- The shaft's extension: whole steps, the least that keeps the hand on the shaft, and the
	-- hand only slides in once the extension is as long as it gets.
	local shaftEnd = B.ShaftStartStuds + B.ShaftLengthStuds
	local E, step = rake.extensionStuds, Config.Cue.Extension.LengthStepStuds
	if
		E < 0
		or E > K.MaxExtensionStuds + 1e-9
		or math.abs(E / step - math.round(E / step)) > 1e-6
	then
		error(("a rake extension of %.4f: %s"):format(E, label))
	end
	if rake.length > shaftEnd + E + 1e-9 then
		error("the hand is past the end of the shaft: " .. label)
	end
	if E > 0 and rake.length <= shaftEnd + E - step + 1e-9 and rake.slideStuds == 0 then
		error("the rake's extension is longer than it needs: " .. label)
	end
	if rake.slideStuds < 0 then
		error("negative slide: " .. label)
	end
	if rake.slideStuds > 0 and E < K.MaxExtensionStuds - 1e-9 then
		error("the hand slid with extension to spare: " .. label)
	end
	-- The hand holds the shaft where the body wants it (HoldForward ahead of the root, out
	-- at the left shoulder) unless raising that to clear the rail took it out of the arm's
	-- full reach; then it holds the shaft at full stretch, unless no clear line comes
	-- within reach at all, when holdReachable says so. (A slide for want of extension is
	-- the exception, checked above.)
	local body = q.body
	local reach = body.ArmReach * S.ArmMaxFraction
	local fx, fy = math.cos(st.yaw), math.sin(st.yaw)
	local shw = body.ShoulderHalfWidth
	local torso, T = math.rad(st.torsoDegrees), body.ShoulderHeight - body.WaistHeight
	local ahead = T * math.sin(torso)
	local shoulder = math.sqrt(
		(rake.holdX - (st.rootX + fx * ahead - fy * shw)) ^ 2
			+ (rake.holdY - (st.rootY + fy * ahead + fx * shw)) ^ 2
			+ (rake.holdZ - (body.WaistHeight + T * math.cos(torso))) ^ 2
	)
	if rake.holdReachable ~= (shoulder <= reach + 1e-9) then
		error(("holdReachable is wrong (%.4f from the shoulder): %s"):format(shoulder, label))
	end
	-- How the hold was found: "kept" where the body wants it, "slid" down the same shaft,
	-- "turned" onto another, "short" of the reach, or "capped" by the extension's limit.
	local how = "capped"
	if rake.slideStuds == 0 then
		local wantX = st.rootX + fx * K.HoldForwardStuds - fy * shw
		local wantY = st.rootY + fy * K.HoldForwardStuds + fx * shw
		local kept = math.abs(rake.holdX - wantX) <= 1e-9 and math.abs(rake.holdY - wantY) <= 1e-9
		if kept and not rake.holdReachable then
			error("the hand kept a place out of its reach: " .. label)
		elseif not kept and rake.holdReachable and shoulder < reach - 1e-6 then
			error(("the hand left its place %.4f inside its reach: %s"):format(shoulder, label))
		end
		-- The same shaft in plan: the attachment, the wanted spot and the hold in a line.
		local ex, ey = wantX - attachX, wantY - attachY
		local cross = math.abs(ex * (rake.holdY - attachY) - ey * (rake.holdX - attachX))
		how = if kept
			then "kept"
			elseif not rake.holdReachable then "short"
			elseif cross <= 1e-9 * math.sqrt(ex * ex + ey * ey) * run then "slid"
			else "turned"
	end
	return rake.holdReachable, rake.onCloth, how
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

-- Two stances (or any plain tables) with the same keys and exactly the same values.
local function same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not same(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- The first INTERIOR_SPOTS of sweepSpots are away from every cushion.
local INTERIOR_SPOTS = 12
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
		}
	do
		table.insert(spots, spot)
	end
	return spots
end

return {
	["sweep: 360 degrees round the table, never in the table, never out of the fence"] = function()
		local rakes: { [string]: number } = {}
		local solves, unreachable, offCloth = 0, 0, 0
		for _, teamSize in { 1, 3 } do
			local area = ShooterStance.area(teamSize)
			for spotIndex, spot in sweepSpots() do
				for step = 0, 71 do
					local angle = math.rad(step * 5)
					for _, pitch in { 4, 20, 40 } do
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
								pitch
							)
							checkStance(q, st, label)
							if st.rake then
								rakes[b.name] = (rakes[b.name] or 0) + 1
								local reachable, onCloth = checkRake(q, st, label)
								if not onCloth and spotIndex <= INTERIOR_SPOTS then
									offCloth += 1
								end
								-- An ordinary body using the rake holds it, at every pitch: the
								-- shaft's own extension reaches the hand however far back the
								-- body stands, and a shaft raised over the rail out of reach
								-- slides or turns back into it.
								if b.name == "R15" and onCloth and not reachable then
									unreachable += 1
								end
							end
						end
					end
				end
			end
		end
		H.expect(solves <= 40000, ("the sweep grew to %d solves"):format(solves))
		H.expect(unreachable == 0, ("R15 cannot reach the rake %d times"):format(unreachable))
		-- Away from the cushions the head always finds cloth. (A ball frozen to a cushion with
		-- the cue glancing along it has none 2 in clear behind it; checkRake has already made
		-- sure those really have none.)
		H.expect(offCloth == 0, ("the rake is off the cloth %d times mid-table"):format(offCloth))
		-- A shorter reach rakes at least as often.
		H.expect((rakes.R6 or 0) >= (rakes.R15 or 0), "R6 rakes less often than R15")
		H.expect((rakes["R15 x0.8"] or 0) >= (rakes.R15 or 0), "a small body rakes less often")
	end,

	["the body stands open, with the cue under the chin"] = function()
		local area = ShooterStance.area(1)
		for _, b in BODIES do
			local body = b.body
			local T = body.ShoulderHeight - body.WaistHeight
			local aRail = math.acos(
				math.clamp(
					(area.railTopZ + S.RailShoulderClearanceStuds - body.WaistHeight) / T,
					-1,
					1
				)
			)
			local side = T
					* math.sin(math.min(math.rad(S.LeanNaturalDegrees), aRail))
					* math.sin(math.rad(S.TwistDegrees))
				+ S.ChinSideStuds
			for _, case in { { -40, 0, 0 }, { 10, -12, 2.2 }, { 30, 20, 4.4 }, { -5, 5, 5.9 } } do
				local q = input(case[1], case[2], case[3], 4, body, area)
				local st = ShooterStance.solve(q)
				local px, py = axisOf(q, 4)
				-- Left of the cue line (the aim's left is (-ay, ax)) by exactly `side`.
				local lateral = (st.rootX - px) * -math.sin(case[3])
					+ (st.rootY - py) * math.cos(case[3])
				H.near(lateral, side, 1e-9, b.name .. " side offset")
				H.near(st.yaw, case[3] - math.rad(S.TwistDegrees), 1e-12, "facing")
			end
		end
	end,

	-- A ball 10 in off the shooter's own cushion, shot along the table with the cue flat: the
	-- body stands at the natural distance (nothing pushes it back), worked out here from
	-- Config by the design's formula: the grip at its natural place on the cue and
	-- GripBehindRootStuds behind the hip, unless the bridge hand's comfortable reach, leaning
	-- at the natural angle, holds the body closer. The grip is then GripBehindRootStuds
	-- behind the hip.
	["a comfortable shot is a natural stance"] = function()
		local C = Config.Cue
		local area = ShooterStance.area(1)
		local body = R15
		local q = input(-40, 0, 0, C.CueElevationDegrees, body, area)
		local st = ShooterStance.solve(q)
		H.expect(st.mode == "stand", "stands: " .. st.mode)
		H.near(st.overhangStuds, 0, 1e-12, "no overhang")
		H.expect(not st.fenceClamped, "the fence is nowhere near")
		H.expect(st.gripReachable, "and the hand reaches the grip")

		local L, gR = C.CueLengthStuds, C.CueRestGapInches * s
		local c = math.cos(math.rad(C.CueElevationDegrees))
		local px, py = axisOf(q, C.CueElevationDegrees)
		local back = CueShape.strikeOffset(0, 0) * s
		-- The grip's natural distance: this far back along the cue from the strike point.
		local byGrip = (gR + L * (1 - S.GripFromButtFraction)) * c - S.GripBehindRootStuds
		-- The bridge on the cloth, and the furthest a rail bridge goes (the root never
		-- depends on which the hand takes).
		local cloth = math.max(
			S.BridgeFromBallInches * s - back,
			gR + C.CuePullBackStuds + S.BridgeTipClearInches * s
		) * c
		local nose = Placement.rayExit(px, py, -1, 0, area.clothHx, area.clothHy)
		local outer = Placement.rayExit(px, py, -1, 0, area.railHx, area.railHy)
		local inset = S.RailBridgeInsetInches * s
		local bridge = math.min(cloth, math.max(nose + inset, outer - inset))
		-- The left hand's comfortable reach from the natural lean (stopped short of the rail).
		local T = body.ShoulderHeight - body.WaistHeight
		local psi = math.rad(S.TwistDegrees)
		local aRail = math.acos(
			math.clamp((area.railTopZ + S.RailShoulderClearanceStuds - body.WaistHeight) / T, -1, 1)
		)
		local lean = math.min(math.rad(S.LeanNaturalDegrees), aRail)
		local forward = body.ShoulderHalfWidth * math.sin(psi) + T * math.sin(lean) * math.cos(psi)
		local across = S.ChinSideStuds + body.ShoulderHalfWidth * math.cos(psi)
		local drop = body.WaistHeight + T * math.cos(lean) - (area.clothZ + S.BridgeHandHeightStuds)
		local comfortable = body.ArmReach * S.ArmNaturalFraction
		local byHand = bridge
			+ forward
			+ math.sqrt(math.max(0, comfortable ^ 2 - across ^ 2 - drop ^ 2))
		local natural = math.min(byGrip, byHand)
		-- The root that far back along the cue line (b = -x) from the strike point.
		H.near(px - st.rootX, natural, 1e-9, "the root stands at the natural distance")
		H.near(
			st.gripFromTipStuds,
			(natural + S.GripBehindRootStuds) / c - gR,
			1e-9,
			"the grip sits GripBehindRootStuds behind the hip"
		)
		H.expect(
			st.gripFromTipStuds <= L * (1 - S.GripFromButtFraction) + 1e-9,
			"never further back than its natural place on the cue"
		)
	end,

	["modes only step up as the ball moves away, and the extension only grows"] = function()
		for _, b in { { "R15", R15 }, { "R6", R6 } } do
			for _, line in { { 0, 1 }, { 10, 1 }, { 0, -1 } } do
				local y, dir = line[1], line[2]
				local angle = if dir > 0 then 0 else math.pi
				local area = ShooterStance.area(1)
				local lastMode, lastE = 0, 0
				for i = -48, 48 do
					local x = i * dir
					local q = input(x, y, angle, pitchFor(x, y, angle), b[2], area)
					local st = ShooterStance.solve(q)
					local label = ("%s ball (%d, %d) toward %s"):format(b[1], x, y, tostring(dir))
					checkStance(q, st, label)
					H.expect(MODES[st.mode] >= lastMode, "mode stepped back: " .. label)
					H.expect(st.extensionStuds >= lastE - 1e-9, "extension shrank: " .. label)
					lastMode, lastE = MODES[st.mode], st.extensionStuds
				end
				H.expect(lastMode == MODES.extension, "a ball at the far rail needs the extension")
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
					H.expect(rest.mode == full.mode, "the pull changed the mode")
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

	["hysteresis: each boundary is crossed once each way, and jitter does not flicker"] = function()
		local area = ShooterStance.area(1)
		local function kind(st: any): number
			return if st.mode == "extension" then 3 elseif st.mode == "bridge" then 2 else 1
		end
		for _, b in { { "R15", R15 }, { "R6", R6 } } do
			local function at(x: number, memory: any): any
				local q = input(x, 0, 0, pitchFor(x, 0, 0), b[2], area)
				q.memory = memory
				return ShooterStance.solve(q)
			end
			-- Out and back along the table, threading the memory.
			local memory, last, lastRail = nil, 0, true
			local up: { [number]: number } = {}
			for i = 0, 384 do
				local x = -48 + i * 0.25
				local st = at(x, memory)
				H.expect(kind(st) >= last, ("%s stepped back at %.2f going out"):format(b[1], x))
				H.expect(not st.memory.onRail or lastRail, "back onto the rail going out")
				if kind(st) > last and last > 0 then
					up[kind(st)] = x
				end
				last, lastRail, memory = kind(st), st.memory.onRail, st.memory
			end
			local down: { [number]: number } = {}
			for i = 0, 384 do
				local x = 48 - i * 0.25
				local st = at(x, memory)
				H.expect(kind(st) <= last, ("%s stepped up at %.2f coming back"):format(b[1], x))
				if kind(st) < last then
					down[last] = x
				end
				last, memory = kind(st), st.memory
			end
			H.expect(up[2] ~= nil and up[3] ~= nil, b[1] .. ": the walk found both boundaries")
			for k, x in up do
				local back = down[k]
				H.expect(back ~= nil and back < x, ("%s: no hysteresis at %.2f"):format(b[1], x))
				-- Jitter a quarter inch either side of where it switched: it switches once.
				local st = at(x - 0.25, nil)
				memory = st.memory
				local changes, was = 0, kind(st)
				for j = 1, 12 do
					local now = at(if j % 2 == 1 then x else x - 0.25, memory)
					if kind(now) ~= was then
						changes += 1
					end
					was, memory = kind(now), now.memory
				end
				H.expect(changes <= 1, ("%s flickers at %.2f"):format(b[1], x))
			end
		end
	end,

	-- The client threads its memory frame to frame; the server solves afresh at the shot (or
	-- with its own memory). The root must come out the same whatever memory it is given:
	-- threaded along a walk, none, or one that disagrees on purpose (a rail bridge it does not
	-- have, the rake with an extension). The rail choice's hysteresis once leaked into the
	-- root near the head rail for scaled bodies, so the walk covers the cushion at several
	-- offsets and angles and bodies of other sizes and proportions.
	["the root never depends on the memory, so the server and the client agree"] = function()
		local area = ShooterStance.area(1)
		local narrow = scaled(R15, 0.95)
		narrow.HalfWidth, narrow.ShoulderHalfWidth =
			R15.HalfWidth * 0.7, R15.ShoulderHalfWidth * 0.7
		local bodies = {
			{ name = "R15 x0.9", body = scaled(R15, 0.9) },
			{ name = "R15 x1.5", body = scaled(R15, 1.5) },
			{ name = "R15 narrow", body = narrow },
			{
				name = "tall, short-armed",
				body = {
					RootHeight = 2.8,
					WaistHeight = 2.6,
					ShoulderHeight = 4.6,
					ShoulderHalfWidth = 0.7,
					ArmReach = 1.6,
					HalfWidth = 0.7,
					HalfDepth = 0.5,
				},
			},
		}
		for _, b in BODIES do
			table.insert(bodies, b)
		end
		local liars = {
			{ mode = "stand", extensionStuds = 0, onRail = true },
			{ mode = "extension", extensionStuds = 3, onRail = false },
		}
		for _, y in { -12, -11, 0, 7, 12 } do
			for _, degrees in { 0, 20, 30, 45, 111, 160, 200, 290 } do
				local angle = math.rad(degrees)
				local pitches = {}
				for i = 0, 48 do
					pitches[i] = pitchFor(-48 + i * 2, y, angle)
				end
				for _, b in bodies do
					local memory = nil
					for i = 0, 48 do
						local x = -48 + i * 2
						local q = input(x, y, angle, pitches[i], b.body, area)
						local fresh = ShooterStance.solve(q)
						local label = ("%s ball (%d, %d) at %d"):format(b.name, x, y, degrees)
						-- By index: a table starting { memory, ... } would skip a nil memory.
						for k = 1, 1 + #liars do
							q.memory = if k == 1 then memory else liars[k - 1]
							local st = ShooterStance.solve(q)
							H.expect(st.rootX == fresh.rootX and st.rootY == fresh.rootY, label)
							if k == 1 then
								memory = st.memory
							end
						end
					end
				end
			end
		end
	end,

	["a tight fence holds the body in, but the barrier always wins"] = function()
		-- 3 studs past the barrier still fits the body beyond the release clearance, so the
		-- fence clamps far stances and every check holds; 1 stud cannot, so the barrier wins.
		for _, extra in { 3, 1 } do
			local area = ShooterStance.area(1)
			area.fenceHx, area.fenceHy = area.barrierHx + extra, area.barrierHy + extra
			area.fenceCx = 0
			local clamped, count = 0, 0
			for _, spot in sweepSpots() do
				for step = 0, 23 do
					local angle = math.rad(step * 15)
					local q = input(spot[1], spot[2], angle, 4, R15, area)
					local st = ShooterStance.solve(q)
					local label = ("fence +%d at %d"):format(extra, step * 15)
					count += 1
					if st.fenceClamped then
						clamped += 1
					end
					if extra == 3 then
						checkPlace(st, R15, area, label)
					else
						local ex, ey = footprint(st, R15)
						local ux, uy = math.abs(st.rootX), math.abs(st.rootY)
						local clear = math.max(area.releaseClearance, ex, ey)
						H.expect(
							ux >= area.barrierHx + math.min(clear, ex) - 1e-9
								or uy >= area.barrierHy + math.min(clear, ey) - 1e-9,
							"the barrier lost: " .. label
						)
						for _, p in PLACEMENTS do
							local wx, _, wz = Placement.fromTableStuds(p, st.rootX, st.rootY, 0)
							H.expect(
								Placement.outsideBarrier(p, wx, wz, area.releaseClearance) == nil,
								"inside the release clearance: " .. label
							)
						end
					end
				end
			end
			if extra == 3 then
				H.expect(clamped > 0 and clamped < count, "the fence clamped none or all")
			else
				H.expect(clamped == count, "an impossible fence must clamp every stance")
			end
		end
	end,

	["a ball near the shooter's cushion bridges on the rail and shortens the wind-up"] = function()
		local area = ShooterStance.area(1)
		local q = input(-46, 0, 0, pitchFor(-46, 0, 0), R15, area)
		local st = ShooterStance.solve(q)
		local bridge = assert(st.handBridge, "a hand bridge")
		H.expect(bridge.onRail, "on the rail")
		H.near(bridge.surfaceZ, area.railTopZ, 1e-12, "on the rail top")
		H.expect(st.pullLimit < 1, "the wind-up is cut short")
		-- At a full pull the tip still stops BridgeTipClear short of the bridge.
		q.pull = 1
		local full = ShooterStance.solve(q)
		local px, py = axisOf(q, full.pitchDegrees)
		local plan = math.sqrt((bridge.x - px) ^ 2 + (bridge.y - py) ^ 2)
		local along = plan / math.cos(math.rad(full.pitchDegrees))
		H.expect(
			along - full.cueGapStuds >= S.BridgeTipClearInches * s - 1e-9,
			"the tip passes the bridge"
		)
		-- And the bridge hand lies on the rail, inside its edges.
		H.expect(math.abs(bridge.x) >= area.clothHx and math.abs(bridge.x) <= area.railHx, "rail")
	end,

	["corners: every aim is legal and the root glides"] = function()
		local area = ShooterStance.area(1)
		local function solveAt(corner: { number }, degrees: number, memory: any): any
			local angle = math.rad(degrees)
			local q =
				input(corner[1], corner[2], angle, pitchFor(corner[1], corner[2], angle), R15, area)
			q.memory = memory
			return ShooterStance.solve(q), q
		end
		local worst, fast = 0, 0
		for _, corner in { { 47, 22 }, { -47, 22 }, { 47, -22 }, { -47, -22 } } do
			local memory, last = nil, nil
			for step = 0, 720 do
				local st, q = solveAt(corner, step * 0.5, memory)
				checkStance(
					q,
					st,
					("corner (%d, %d) at %.1f"):format(corner[1], corner[2], step * 0.5)
				)
				if last then
					local moved =
						math.sqrt((st.rootX - last.rootX) ^ 2 + (st.rootY - last.rootY) ^ 2)
					worst = math.max(worst, moved)
					if moved > 0.35 then
						-- Faster than the design's 0.35 studs per half degree. That happens where
						-- the cue line runs nearly along a side of the barrier and the spot slides
						-- along that side; it must still be a glide, not a jump: split into
						-- tenths, no tenth may move more than 0.2.
						fast += 1
						local prev = last
						for k = 1, 10 do
							local sub = solveAt(corner, (step - 1) * 0.5 + k * 0.05, nil)
							local d = math.sqrt(
								(sub.rootX - prev.rootX) ^ 2 + (sub.rootY - prev.rootY) ^ 2
							)
							H.expect(d <= 0.2, ("a jump inside %.1f degrees"):format(step * 0.5))
							prev = sub
						end
					end
				end
				last, memory = st, st.memory
			end
		end
		-- Measured: the fastest glide is about 1.12 studs per half degree, on a handful of steps.
		H.expect(worst <= 1.25, ("the root moved %.3f studs in half a degree"):format(worst))
		H.expect(fast < 100, ("%d fast steps"):format(fast))
	end,

	-- The cue rests in a notch at the full wind-up's distance when the cue is nearly flat. A
	-- raised cue is above every notch there, so the head comes in toward the ball, only as
	-- far as a notch needs (cutting the wind-up least), never onto the resting tip; past that
	-- it keeps the least hover.
	["the rake's head comes in until a notch meets a raised cue"] = function()
		local area = ShooterStance.area(1)
		local K = S.Rake
		local restTip = (Config.Cue.CueRestGapInches + S.BridgeTipClearInches) * s
		local function rakeAt(pitch: number): (any, number, any)
			local q = input(0, 0, 0, pitch, R15, area)
			local st = ShooterStance.solve(q)
			local label = ("pitch %d"):format(pitch)
			checkStance(q, st, label)
			local rake = assert(st.rake, "a rake at the table's centre: " .. label)
			checkRake(q, st, label)
			local px, py = axisOf(q, pitch)
			local along = math.sqrt((rake.headX - px) ^ 2 + (rake.headY - py) ^ 2)
				/ math.cos(math.rad(pitch))
			return st, along, rake
		end
		local flat = rakeAt(4)
		H.expect(flat.rake.hover == 0 and flat.pullLimit == 1, "a flat cue keeps the full wind-up")
		for _, pitch in { 8, 12, 16 } do
			local st, along, rake = rakeAt(pitch)
			H.expect(rake.hover == 0, ("pitch %d: no notch meets the cue"):format(pitch))
			H.expect(st.pullLimit < 1, ("pitch %d: the head did not come in"):format(pitch))
			H.expect(along >= restTip - 1e-9, ("pitch %d: on the resting tip"):format(pitch))
			-- As far back as it fits: the cue rides at the top of the notch's tolerance.
			H.near(rake.cueZ - rake.headZ, K.NotchToleranceStuds, 1e-9, "as far back as fits")
		end
		for _, pitch in { 30, 40 } do
			local steep, along, rake = rakeAt(pitch)
			H.expect(rake.hover > 0, "a steep cue is above every notch even at the resting tip")
			H.near(along, restTip, 1e-9, "the least hover is at the resting tip")
			H.near(steep.pullLimit, 0, 1e-9, "with no room left for a wind-up")
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

	-- Turning to the table centre must not swing the footprint into the barrier or the fence
	-- (both collide for a player in a match): a body whose footprint diagonal is wider than
	-- the release clearance (R15 x1.3) is the one that finds out.
	["after the shot the shooter stands on the same spot facing the table centre"] = function()
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
						H.expect(x == st.rootX and y == st.rootY and z == st.rootZ, "moved")
						local d = math.sqrt(x * x + y * y)
						H.near(math.cos(yaw) * -x + math.sin(yaw) * -y, d, 1e-9, "faces the centre")
						local idle = table.clone(st)
						idle.yaw = yaw
						local label = ("idle %s team %d ball (%.2f, %.2f) at %d"):format(
							b.name,
							teamSize,
							spot[1],
							spot[2],
							step * 15
						)
						checkPlace(idle, b.body, area, label)
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
	end,

	-- Raising the hold until the shaft clears the rail can lift it out of the off arm's reach:
	-- a shaft that crosses the rail close to the head climbs all the way back to a body
	-- standing far off (a ball by a corner, the cue running back along the side rail). The
	-- hand then slides down that same shaft into reach or, when the shaft passes above the
	-- reach altogether, the shaft turns about the head onto a clear line the arm reaches;
	-- either way it holds it at full stretch (checkRake). A turn only happens when it must:
	-- with no turn allowed those holds are out of reach. (The slides come from balls a few
	-- inches off a side cushion, added to the sweep's spots here.)
	["a hold raised out of reach slides down the shaft, or the shaft turns into reach"] = function()
		local counts: { [string]: number } = {}
		local spots = sweepSpots()
		table.insert(spots, { -12, 19 })
		table.insert(spots, { 12, -19 })
		for _, teamSize in { 1, 3 } do
			local area = ShooterStance.area(teamSize)
			for _, spot in spots do
				for step = 0, 71 do
					local angle = math.rad(step * 5)
					for _, pitch in { 4, 20, 40 } do
						local q = input(spot[1], spot[2], angle, pitch, R15, area)
						local st = ShooterStance.solve(q)
						if st.rake then
							local label = ("team %d ball (%.2f, %.2f) at %d, pitch %d"):format(
								teamSize,
								spot[1],
								spot[2],
								step * 5,
								pitch
							)
							local _, _, how = checkRake(q, st, label)
							counts[how] = (counts[how] or 0) + 1
							if how == "turned" then
								local fixed = solveWith(S.Rake, "HoldTurnMaxDegrees", 0, q)
								H.expect(
									fixed.rake ~= nil and not fixed.rake.holdReachable,
									"turned without needing to: " .. label
								)
							end
						end
					end
				end
			end
		end
		H.expect((counts.slid or 0) > 0, "no hold slid down its shaft")
		H.expect((counts.turned or 0) > 0, "no shaft turned")
		H.expect(
			counts.short == nil,
			("R15 fell short of the rake %d times"):format(counts.short or 0)
		)
	end,

	-- A far ball puts the rake's head a table's length from a body standing back at the near
	-- rail. The hand keeps its place and the shaft grows to it; with no extension allowed at
	-- all (the old behaviour) the hand slides in along the shaft instead. Nothing but the
	-- rake's hold may differ between the two: not the root, the mode, the torso or the grip.
	["a shaft too short for the hand gets an extension, and nothing else changes"] = function()
		local K = S.Rake
		local extended = 0
		for _, teamSize in { 1, 3 } do
			local area = ShooterStance.area(teamSize)
			for _, spot in sweepSpots() do
				for step = 0, 23 do
					local angle = math.rad(step * 15)
					for _, pitch in { 4, pitchFor(spot[1], spot[2], angle), 40 } do
						for _, b in BODIES do
							local q = input(spot[1], spot[2], angle, pitch, b.body, area)
							local st = ShooterStance.solve(q)
							local bare = solveWith(K, "MaxExtensionStuds", 0, q)
							local label = ("%s team %d ball (%.2f, %.2f) at %d, pitch %.1f"):format(
								b.name,
								teamSize,
								spot[1],
								spot[2],
								step * 15,
								pitch
							)
							H.expect(
								st.rootX == bare.rootX
									and st.rootY == bare.rootY
									and st.rootZ == bare.rootZ
									and st.yaw == bare.yaw,
								"the rake's extension moved the root: " .. label
							)
							H.expect(
								st.mode == bare.mode
									and st.torsoDegrees == bare.torsoDegrees
									and same(st.grip, bare.grip)
									and st.gripReachable == bare.gripReachable,
								"the rake's extension changed the body: " .. label
							)
							H.expect(
								same(st, ShooterStance.solve(q)),
								"not deterministic: " .. label
							)
							local rake, short = st.rake, bare.rake
							if rake and short then
								H.expect(short.extensionStuds == 0, "an extension past the cap")
								H.expect(rake.slideStuds == 0, "the hand slid: " .. label)
								-- Where the body wants it (out at the left shoulder, HoldForward
								-- ahead of the root), or at the edge of the arm's reach.
								checkRake(q, st, label)
								H.near(
									rake.length,
									short.length + short.slideStuds,
									1e-9,
									"the shaft reaches as far as the hand slid: " .. label
								)
								if short.slideStuds > 0 then
									extended += 1
									H.expect(rake.extensionStuds > 0, "no extension: " .. label)
								else
									H.expect(
										same(rake, short),
										"an extension for nothing: " .. label
									)
								end
							else
								H.expect(
									rake == nil and short == nil,
									"the rake came or went: " .. label
								)
							end
						end
					end
				end
			end
		end
		H.expect(extended > 0, "no rake in the sweep needed an extension")
	end,

	-- The upright retry only ever acts on a grip the chosen lean cannot reach: then the torso
	-- is upright, the grip is reached at least as often, and a hand bridge only gives way to
	-- the rake when that gets the grip hand onto the cue. The root never moves for it.
	["an out-of-reach grip stands the torso up, and never makes a stance worse"] = function()
		local function raking(mode: string): boolean
			return mode == "bridge" or mode == "extension"
		end
		local before, after, improved, upright = 0, 0, 0, 0
		for _, teamSize in { 1, 3 } do
			local area = ShooterStance.area(teamSize)
			for _, spot in sweepSpots() do
				for step = 0, 23 do
					local angle = math.rad(step * 15)
					for _, pitch in { pitchFor(spot[1], spot[2], angle), 20, 40 } do
						for _, b in BODIES do
							local q = input(spot[1], spot[2], angle, pitch, b.body, area)
							local st = ShooterStance.solve(q)
							local lean = solveWith(S, "UprightWhenGripOutOfReach", false, q)
							local label = ("%s team %d ball (%.2f, %.2f) at %d, pitch %.1f"):format(
								b.name,
								teamSize,
								spot[1],
								spot[2],
								step * 15,
								pitch
							)
							checkStance(q, st, label)
							if st.rake then
								checkRake(q, st, label)
							end
							H.expect(
								st.rootX == lean.rootX
									and st.rootY == lean.rootY
									and st.rootZ == lean.rootZ
									and st.yaw == lean.yaw,
								"standing up moved the root: " .. label
							)
							before += if lean.gripReachable then 1 else 0
							after += if st.gripReachable then 1 else 0
							if not same(st, lean) then
								upright += 1
								H.expect(
									not lean.gripReachable,
									"changed a reachable grip: " .. label
								)
								H.expect(
									st.torsoDegrees == 0 and st.lean == 0,
									"changed but not upright: " .. label
								)
								H.expect(
									st.gripReachable or raking(st.mode) == raking(lean.mode),
									"brought the rake out for a grip it still misses: " .. label
								)
								improved += if st.gripReachable then 1 else 0
							end
							q.memory = st.memory
							H.expect(
								same(ShooterStance.solve(q), ShooterStance.solve(q)),
								"not deterministic: " .. label
							)
						end
					end
				end
			end
		end
		H.expect(after >= before, ("reached %d grips upright, %d leaning"):format(after, before))
		H.expect(upright > 0 and improved > 0, "standing up never helped")
	end,
}
