--!strict
-- Cluster: simultaneous soft contact for balls that are touching each other.
--
-- Simulation resolves an ordinary collision as one instantaneous impulse between two balls,
-- which is exact for two balls. A rack is fifteen balls a few thousandths of an inch apart,
-- and resolved strictly one pair at a time it behaves like two Newton's cradles: the break's
-- energy runs down the two edges into the back corner balls and the middle hardly moves.
-- Measured over eleven seeded full-power breaks: about 72% of the energy ended up in the 7
-- and the 13, inner balls left at 4-35 in/s, and not one ball was pocketed.
--
-- Real balls are not rigid. For a fraction of a millisecond each ball in the pack is
-- squashed against all of its neighbours at once, and the pushes share out between them.
-- So when a contact involves a ball that is already touching a third ball, the whole group
-- is integrated as soft spheres for as long as any of them are pressed together:
--
--   * Hertz springs, force = k * overlap^1.5, with k chosen so a head-on pair at
--     BallContactReferenceSpeed stays in contact for BallContactMicroseconds;
--   * Tsuji damping, c * overlap^0.25 * closing speed, which gives the same restitution at
--     every impact speed; c is found by bisection so an isolated pair restitutes at exactly
--     BallRestitution through this very integrator;
--   * the pairwise model's contact friction (throw and spin transfer), applied as an
--     impulse per sub-step against the normal impulse of that sub-step;
--   * velocity Verlet at the fixed sub-step SoftContactStep, then back to the event engine
--     the moment the last contact lets go.
--
-- Only + - * / and sqrt are used (overlap^1.5 = overlap * sqrt(overlap)), iteration is in
-- array order, and the sub-step is fixed, so the result is bit-identical on every machine.
-- Cloth friction is left out for the group while the contact lasts: over its few hundred
-- microseconds it changes a ball's speed by well under 1 in/s.

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Ball)
local Flight = require(script.Parent.Flight)
local TableGeometry = require(script.Parent.Table)

type Ball = Ball.Ball
type Geometry = TableGeometry.Geometry

local Cluster = {}

--- Called once per pair per soft phase, in order of first touch, with the time of first
--- touch and the fastest the pair closed along the contact normal while touching. `a` is
--- the earlier ball in the state's list. Called after the phase, in time order.
export type Emit = (a: Ball, b: Ball, t: number, speed: number) -> ()

-- Hertz theory: for F = K * overlap^1.5 between bodies of reduced mass m, a head-on impact at
-- speed v lasts 2.9432 * (m^2 / (K^2 * v))^(1/5). A mathematical constant, not a tuning.
local HERTZ_DURATION = 2.9432

---------------------------------------------------------------------------------------------
-- Friction (shared with Simulation's pairwise model)
---------------------------------------------------------------------------------------------

--- Ordered piecewise-linear contact friction, clamped to the tabulated endpoint values.
function Cluster.ballFriction(slipSpeed: number): number
	local points = Config.Physics.BallFrictionTable
	if slipSpeed <= points[1].Speed then
		return points[1].Friction
	end
	for i = 2, #points do
		local upper = points[i]
		if slipSpeed <= upper.Speed then
			local lower = points[i - 1]
			local fraction = (slipSpeed - lower.Speed) / (upper.Speed - lower.Speed)
			return lower.Friction + fraction * (upper.Friction - lower.Friction)
		end
	end
	return points[#points].Friction
end

--- Contact friction for a normal impulse `j` (per unit mass) along the unit normal (nx, ny)
--- from ball a to ball b: TP A.14 / pooltool throw and spin transfer. Takes a's velocity
--- minus b's and the SUM of their spins, and returns the friction impulse along the
--- tangent t = (-ny, nx, 0) and along the vertical, both as applied to ball a (b takes the
--- opposite linear impulse and the SAME angular one: opposite forces at opposite contact
--- arms). The normal impulse cannot change either component of the relative surface
--- velocity, so this can be evaluated after it. Returns 0, 0 when there is no slip.
function Cluster.frictionImpulse(
	dvx: number,
	dvy: number,
	swx: number,
	swy: number,
	swz: number,
	nx: number,
	ny: number,
	j: number
): (number, number)
	local R = Config.Balls.RadiusInches
	local slipAlong = -dvx * ny + dvy * nx + R * swz
	local slipVertical = R * (swx * ny - swy * nx)
	local slipSpeed = math.sqrt(slipAlong * slipAlong + slipVertical * slipVertical)
	if slipSpeed > Config.Physics.BallSlipEpsilon then
		-- Unit masses and I = 0.4 R^2 give contact inverse mass 7. The cap prevents
		-- slip reversing during impact and limits head-on spin transfer to 5/14.
		local impulse = math.min(Cluster.ballFriction(slipSpeed) * j, slipSpeed / 7)
		return -impulse * slipAlong / slipSpeed, -impulse * slipVertical / slipSpeed
	end
	return 0, 0
end

---------------------------------------------------------------------------------------------
-- Material: stiffness from the contact time, damping from the restitution
---------------------------------------------------------------------------------------------

-- Both are per unit mass: each ball of a pair overlapping by d accelerates apart at
-- stiffness * d^1.5 + damping * d^0.25 * closing speed. Cached against the Config values
-- they were derived from, so a test that changes one gets a matching material.
local stiffness, damping = 0, 0
local derivedFrom: { number } = {}

local resolvePhase: (members: { Ball }, first: Ball, second: Ball, t0: number, emit: Emit?) -> number

local function material()
	local P = Config.Physics
	local key = {
		P.BallContactMicroseconds,
		P.BallContactReferenceSpeed,
		P.BallRestitution,
		P.SoftContactStep,
		P.SoftContactMaxSeconds,
		Config.Balls.RadiusInches,
	}
	local same = #derivedFrom == #key
	for i, value in key do
		same = same and derivedFrom[i] == value
	end
	if same then
		return
	end
	derivedFrom = key

	-- Relative motion of two unit masses has reduced mass 1/2.
	local q = P.BallContactMicroseconds * 1e-6 / HERTZ_DURATION
	stiffness = math.sqrt(0.25 / (P.BallContactReferenceSpeed * q * q * q * q * q))

	-- Restitution of an isolated head-on pair through the real integrator, for a damping.
	local R = Config.Balls.RadiusInches
	local speed = P.BallContactReferenceSpeed
	local function restitution(c: number): number
		damping = c
		local a, b = Ball.new(0, 0, 0), Ball.new(1, 2 * R, 0)
		a.vx = speed
		resolvePhase({ a, b }, a, b, 0, nil)
		return (b.vx - a.vx) / speed
	end
	local target = P.BallRestitution
	if restitution(0) <= target then
		damping = 0
		return
	end
	-- Restitution falls monotonically as damping rises: bracket, then bisect.
	local low, high = 0, math.sqrt(stiffness)
	while restitution(high) > target do
		low, high = high, high * 2
	end
	for _ = 1, 48 do
		local mid = (low + high) / 2
		if restitution(mid) > target then
			low = mid
		else
			high = mid
		end
	end
	damping = (low + high) / 2
end

---------------------------------------------------------------------------------------------
-- Who is in the group
---------------------------------------------------------------------------------------------

--- True when a contact between a and b should be soft: either ball is within
--- ClusterGapInches of some third ball. Balls in `skip` are ignored.
function Cluster.touchesAnother(
	balls: { Ball },
	a: Ball,
	b: Ball,
	skip: { [Ball]: boolean }?
): boolean
	local reach = 2 * Config.Balls.RadiusInches + Config.Physics.ClusterGapInches
	local reach2 = reach * reach
	for _, c in balls do
		if c == a or c == b or c.pocketed or (skip and skip[c]) then
			continue
		end
		local ax, ay = c.x - a.x, c.y - a.y
		local bx, by = c.x - b.x, c.y - b.y
		if ax * ax + ay * ay <= reach2 or bx * bx + by * by <= reach2 then
			return true
		end
	end
	return false
end

local function groupEnergy(members: { Ball }): number
	local R = Config.Balls.RadiusInches
	local total = 0
	for _, m in members do
		total += Ball.kineticEnergy(m, R)
	end
	return total
end

--- Every ball the soft phase must include, in list order, or nil when the group could
--- reach a cushion or pocket before the phase is certain to be over (the caller then uses
--- the pairwise model, which handles cushions exactly).
---
--- No ball in the group can move faster than sqrt(2 E), E being the group's kinetic energy
--- (contacts only ever remove energy), so within SoftContactMaxSeconds it moves at most
--- that times the cap. Any ball that could close the distance to a member within the cap is
--- pulled in too, and that repeats until nothing more is in reach: no contact between the
--- group and a ball outside it can happen while the phase runs. (The one gap: two outside
--- balls colliding during the phase could fling one faster than it was going. That needs
--- two unrelated contacts inside the same millisecond, and the late contact is still found
--- at t = 0 right after the phase and resolved.)
function Cluster.gather(
	balls: { Ball },
	a: Ball,
	b: Ball,
	geometry: Geometry,
	skip: { [Ball]: boolean }?,
	flyer: Ball?
): { Ball }?
	local P = Config.Physics
	local R = Config.Balls.RadiusInches
	local window = P.SoftContactMaxSeconds
	local inGroup: { [Ball]: boolean } = { [a] = true, [b] = true }
	local chosen: { Ball } = { a, b }
	local energy = Ball.kineticEnergy(a, R) + Ball.kineticEnergy(b, R)
	local grew = true
	while grew do
		grew = false
		local vBound = math.sqrt(2 * energy)
		for _, c in balls do
			if inGroup[c] or c.pocketed or (skip and skip[c]) then
				continue
			end
			local reach = 2 * R + math.max(P.ClusterGapInches, (vBound + Ball.speed(c)) * window)
			for _, m in chosen do
				local dx, dy = c.x - m.x, c.y - m.y
				if dx * dx + dy * dy <= reach * reach then
					inGroup[c] = true
					table.insert(chosen, c)
					energy += Ball.kineticEnergy(c, R)
					grew = true
					break
				end
			end
		end
	end

	-- The soft phase is planar: a ball in the air among them takes the pairwise 3-D model.
	-- The one exception is `flyer`, a ball hopping low into the group, which the caller has
	-- laid flat for the phase and gives its vertical kick afterwards.
	for _, m in chosen do
		if m ~= flyer and Flight.isAirborne(m) then
			return nil
		end
	end

	-- Stay clear of every cushion line and pocket opening: facings, jaws and openings all
	-- lie on or beyond the cushion line, and every opening within its radius of one.
	local T = Config.Table
	local margin = math.max(R, T.CornerPocketRadiusInches, T.SidePocketRadiusInches)
		+ math.sqrt(2 * energy) * window
	for _, m in chosen do
		if
			math.abs(m.x) + margin >= geometry.halfLength
			or math.abs(m.y) + margin >= geometry.halfWidth
		then
			return nil
		end
	end

	local members: { Ball } = table.create(#chosen)
	for _, c in balls do
		if inGroup[c] then
			table.insert(members, c)
		end
	end
	return members
end

---------------------------------------------------------------------------------------------
-- The soft phase
---------------------------------------------------------------------------------------------

resolvePhase = function(
	members: { Ball },
	first: Ball,
	second: Ball,
	t0: number,
	emit: Emit?
): number
	local P = Config.Physics
	local R = Config.Balls.RadiusInches
	local sqrt = math.sqrt
	local frictionImpulse = Cluster.frictionImpulse
	local n = #members
	local h = P.SoftContactStep
	local halfH = 0.5 * h
	local maxSteps = math.max(1, math.floor(P.SoftContactMaxSeconds / h + 0.5))
	local skin = P.SoftContactSkinInches
	local touching = 2 * R
	local touching2 = touching * touching
	local listed2 = (touching + skin) * (touching + skin)
	local k, c = stiffness, damping

	-- Work on flat arrays: the loop below runs a few hundred times per phase, and array
	-- reads are cheaper than field reads on the ball tables.
	local x, y = table.create(n, 0), table.create(n, 0)
	local vx, vy = table.create(n, 0), table.create(n, 0)
	local wx, wy, wz = table.create(n, 0), table.create(n, 0), table.create(n, 0)
	for i, m in members do
		x[i], y[i], vx[i], vy[i] = m.x, m.y, m.vx, m.vy
		wx[i], wy[i], wz[i] = m.wx, m.wy, m.wz
	end

	local energyBefore = groupEnergy(members)
	-- Neighbour list: every pair closer than contact plus a skin. No ball outruns
	-- sqrt(2 E), so a pair outside the list cannot close the skin before the next rebuild.
	local vBound = sqrt(2 * energyBefore)
	local rebuildEvery = if vBound > 0
		then math.max(1, math.floor(skin / (2 * vBound * h)))
		else maxSteps

	-- One event per pair per phase, timed at its first touch and reporting the fastest it
	-- closed while touching (a ball pressed by the one behind it closes faster after first
	-- touch). record[pair key] is 0 before first touch, else its index in the report lists;
	-- the pair that set the phase off already has its event, so it is marked -1.
	local record = table.create(n * n, 0)
	for i, m in members do
		for j, o in members do
			if (m == first and o == second) or (m == second and o == first) then
				record[(i - 1) * n + j] = -1
			end
		end
	end
	local reportI, reportJ = {} :: { number }, {} :: { number }
	local reportT, reportSpeed = {} :: { number }, {} :: { number }

	local ax, ay = table.create(n, 0), table.create(n, 0)
	local pairI, pairJ = {} :: { number }, {} :: { number }
	local pairF, pairNx, pairNy = {} :: { number }, {} :: { number }, {} :: { number }
	local pairCount = 0

	local function rebuild()
		pairCount = 0
		for i = 1, n do
			local xi, yi = x[i], y[i]
			for j = i + 1, n do
				local dx, dy = x[j] - xi, y[j] - yi
				if dx * dx + dy * dy < listed2 then
					pairCount += 1
					pairI[pairCount], pairJ[pairCount] = i, j
					pairF[pairCount] = 0
				end
			end
		end
	end

	-- Velocity Verlet: half kick, drift, forces at the new positions, half kick. Forces are
	-- inline rather than in a helper because this is the hot loop of the whole phase.
	rebuild()
	local steps, sinceRebuild, touched = 0, 0, false
	local active = 0
	while true do
		-- Contact forces at the current positions and velocities.
		for i = 1, n do
			ax[i], ay[i] = 0, 0
		end
		active = 0
		local t = t0 + steps * h
		for p = 1, pairCount do
			local i, j = pairI[p], pairJ[p]
			local dx, dy = x[j] - x[i], y[j] - y[i]
			local d2 = dx * dx + dy * dy
			if d2 < touching2 then
				active += 1
				local d = sqrt(d2)
				local nx, ny = dx / d, dy / d
				local overlap = touching - d
				local root = sqrt(overlap)
				local closing = (vx[i] - vx[j]) * nx + (vy[i] - vy[j]) * ny
				-- Contacts push, never pull: damping may cancel the spring on the way out.
				local f = k * overlap * root + c * sqrt(root) * closing
				if f < 0 then
					f = 0
				end
				pairF[p], pairNx[p], pairNy[p] = f, nx, ny
				ax[i] -= f * nx
				ay[i] -= f * ny
				ax[j] += f * nx
				ay[j] += f * ny
				local key = (i - 1) * n + j
				local index = record[key]
				if index == 0 then
					index = #reportT + 1
					record[key] = index
					reportI[index], reportJ[index] = i, j
					reportT[index], reportSpeed[index] = t, 0
				end
				if index > 0 and closing > reportSpeed[index] then
					reportSpeed[index] = closing
				end
			else
				pairF[p] = 0
			end
		end
		if steps > 0 then
			for i = 1, n do
				vx[i] += halfH * ax[i]
				vy[i] += halfH * ay[i]
			end
			if active == 0 then
				if touched then
					break -- every contact has let go
				end
			else
				touched = true
				-- Friction against this sub-step's normal impulse, pair by pair in list order.
				for p = 1, pairCount do
					local f = pairF[p]
					if f > 0 then
						local i, j = pairI[p], pairJ[p]
						local nx, ny = pairNx[p], pairNy[p]
						local along, vertical = frictionImpulse(
							vx[i] - vx[j],
							vy[i] - vy[j],
							wx[i] + wx[j],
							wy[i] + wy[j],
							wz[i] + wz[j],
							nx,
							ny,
							f * h
						)
						if along ~= 0 or vertical ~= 0 then
							local jx, jy = -ny * along, nx * along
							vx[i] += jx
							vy[i] += jy
							vx[j] -= jx
							vy[j] -= jy
							local dwx, dwy, dwz =
								2.5 * ny * vertical / R, -2.5 * nx * vertical / R, 2.5 * along / R
							wx[i] += dwx
							wy[i] += dwy
							wz[i] += dwz
							wx[j] += dwx
							wy[j] += dwy
							wz[j] += dwz
						end
					end
				end
			end
		end
		if steps >= maxSteps then
			break
		end
		steps += 1
		for i = 1, n do
			local u, v = vx[i] + halfH * ax[i], vy[i] + halfH * ay[i]
			vx[i], vy[i] = u, v
			x[i] += h * u
			y[i] += h * v
		end
		sinceRebuild += 1
		if sinceRebuild >= rebuildEvery then
			sinceRebuild = 0
			rebuild()
		end
	end

	for i, m in members do
		m.x, m.y, m.vx, m.vy = x[i], y[i], vx[i], vy[i]
		m.wx, m.wy, m.wz = wx[i], wy[i], wz[i]
	end

	-- Only reached through the cap: part the balls still pressed together so the event
	-- engine starts from legal positions. Their stored spring energy is simply lost.
	for _ = 1, 4 do
		local parted = true
		for i = 1, n do
			local a = members[i]
			for j = i + 1, n do
				local b = members[j]
				local dx, dy = b.x - a.x, b.y - a.y
				local d = math.sqrt(dx * dx + dy * dy)
				local want = touching + P.ContactSlop
				if d < want and d > 1e-12 then
					parted = false
					local push = (want - d) / 2
					a.x -= dx / d * push
					a.y -= dy / d * push
					b.x += dx / d * push
					b.y += dy / d * push
				end
			end
		end
		if parted then
			break
		end
	end

	-- The integrator conserves energy only to within its truncation error. Never let that
	-- error add energy: shrink the balls' velocities relative to the group's mean, which
	-- leaves momentum exactly as it is.
	local energyAfter = groupEnergy(members)
	if energyAfter > energyBefore then
		local mx, my = 0, 0
		for _, m in members do
			mx += m.vx
			my += m.vy
		end
		mx, my = mx / n, my / n
		local relative = 0
		for _, m in members do
			local dx, dy = m.vx - mx, m.vy - my
			relative += 0.5 * (dx * dx + dy * dy)
		end
		local excess = energyAfter - energyBefore
		local scale = if relative > excess then math.sqrt((relative - excess) / relative) else 0
		for _, m in members do
			m.vx = mx + (m.vx - mx) * scale
			m.vy = my + (m.vy - my) * scale
		end
	end
	if emit then
		for index, t in reportT do
			if reportSpeed[index] > 0 then
				emit(members[reportI[index]], members[reportJ[index]], t, reportSpeed[index])
			end
		end
	end
	return steps * h
end

--- Integrate `members` (from gather) through their soft contact, starting at time t0 when
--- `first` and `second` have just touched. Positions, velocities and spins are updated in
--- place; the caller must hold every other ball still in time while this runs, then advance
--- them by the returned duration. `emit` receives one event per pair that touched.
function Cluster.resolve(
	members: { Ball },
	first: Ball,
	second: Ball,
	t0: number,
	emit: Emit?
): number
	material()
	return resolvePhase(members, first, second, t0, emit)
end

--- The derived per-unit-mass stiffness and damping, for tests and tuning.
function Cluster.material(): (number, number)
	material()
	return stiffness, damping
end

-- Derive the material once up front (about 10 ms), so the first break does not pay for it.
material()

return Cluster
