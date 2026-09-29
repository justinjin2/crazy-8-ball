--!strict
-- PickMath (src/shared/PickMath.luau): the pure helpers behind the aim-phase pick view. Which
-- pick the local player owes (mirroring the server's Ults/Match.pickNeeded), matching a sent
-- pick against the snapshot's, the gamepad's D-pad step between balls, the nearest ball to a
-- pointer, and the portal spots (kept on the cloth, B's starting spot, one spot's clearance by
-- Ults/Arming's own rule).

local H = require("./harness")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local TableGeometry = H.require("Physics.Table")
local Arming = H.require("Ults.Arming")
local PickMath = H.require("PickMath")

local geometry = TableGeometry.build({ pocketsOpen = true })
local R = Config.Balls.RadiusInches
local Pick = Config.Ults.Shared.Pick
local CLEAR = Pick.PortalClearBallWidths * 2 * R

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local ME, THEM = 101, 202

-- A snapshot's ults view with `id` armed by `by`.
local function ults(
	id: string,
	by: number,
	stage: string?,
	pick: { number }?,
	readyAt: number?
): any
	return {
		on = true,
		bars = {},
		armed = {
			by = by,
			id = id,
			stage = stage or "Armed",
			readyAt = readyAt or 0,
			seq = 1,
			pick = pick,
		},
	}
end

-- Runs `fn` with an ult's catalog row marked built (Heat Seeker and Portals are placeholders
-- until their own step), then puts it back.
local function built(id: string, fn: () -> ())
	local row = (Config.Ults.Catalog :: any)[id]
	local was = row.Built
	row.Built = true
	local ok, err = pcall(fn)
	row.Built = was
	if not ok then
		error(err, 0)
	end
end

local tests = {}

function tests.noPickWithoutAnArmedPickAbility()
	check(PickMath.kind(nil, ME, ME, 0) == nil, "no ults view")
	check(PickMath.kind({ on = true, bars = {} }, ME, ME, 0) == nil, "nothing armed")
	check(PickMath.kind(ults("Magnet", ME), ME, ME, 0) == nil, "Magnet has no pick")
	check(PickMath.kind(ults("NoSuchUlt", ME), ME, ME, 0) == nil, "an unknown id")
end

function tests.unbuiltAbilitiesOweNoPickLikeTheServer()
	-- Ults/Match.pickNeeded asks only for a built ult: a placeholder would be refused "NoPick".
	if (Config.Ults.Catalog :: any).HeatSeeker.Built then
		return -- built since: covered by the tests below
	end
	check(PickMath.kind(ults("HeatSeeker", ME), ME, ME, 0) == nil, "a placeholder owes nothing")
end

function tests.ownBallAndPortalsAreOwedByTheShooterOnly()
	built("HeatSeeker", function()
		check(PickMath.kind(ults("HeatSeeker", ME), ME, ME, 0) == "OwnBall", "Heat Seeker")
		check(PickMath.owed(ults("HeatSeeker", ME), ME, ME, 0) == "OwnBall", "owed")
		check(PickMath.kind(ults("HeatSeeker", THEM), THEM, ME, 0) == nil, "the opponent's")
		check(PickMath.kind(ults("HeatSeeker", ME), THEM, ME, 0) == nil, "not the shooter")
	end)
	built("Portals", function()
		check(PickMath.owed(ults("Portals", ME), ME, ME, 0) == "Portals", "Portals")
	end)
end

function tests.aPickMadeIsNoLongerOwed()
	built("HeatSeeker", function()
		local u = ults("HeatSeeker", ME, "Armed", { 3 })
		check(PickMath.kind(u, ME, ME, 0) == "OwnBall", "still a pick ability")
		check(PickMath.owed(u, ME, ME, 0) == nil, "already picked")
	end)
end

function tests.armingWaitsForReadyAt()
	built("Portals", function()
		local u = ults("Portals", ME, "Arming", nil, 50)
		check(PickMath.kind(u, ME, ME, 49.9) == nil, "still in its cutscene")
		check(PickMath.kind(u, ME, ME, 50) == "Portals", "past readyAt, before the server's tick")
	end)
end

function tests.requestFieldsMatchTheTableAction()
	local ball = PickMath.request("OwnBall", { 5 })
	check(ball.ball == 5 and ball.ax == nil, "a ball pick")
	local p = PickMath.request("Portals", { -20, 5, 30, -6 })
	check(p.ax == -20 and p.ay == 5 and p.bx == 30 and p.by == -6, "a portals pick")
end

function tests.samePickComparesEveryNumber()
	check(PickMath.same({ 3 }, { 3 }), "one ball")
	check(not PickMath.same({ 3 }, { 4 }), "another ball")
	check(PickMath.same({ 1, 2, 3, 4 }, { 1, 2, 3, 4 + 1e-9 }), "a hair apart")
	check(not PickMath.same({ 1, 2, 3, 4 }, { 1, 2, 3, 5 }), "a portal moved")
	check(not PickMath.same({ 1, 2 }, { 1, 2, 3, 4 }), "different lengths")
	check(not PickMath.same(nil, { 1 }), "no pick")
	check(not PickMath.same({}, {}), "empty is no pick")
end

function tests.nearestWithinReach()
	local points =
		{ { id = 1, x = 0, y = 0 }, { id = 2, x = 10, y = 0 }, { id = 3, x = 10, y = 0 } }
	check(PickMath.nearest(points, 8, 0, 5) == 2, "the closest, a tie to the earlier")
	check(PickMath.nearest(points, 1, 1, 5) == 1, "ball 1")
	check(PickMath.nearest(points, 50, 50, 5) == nil, "none in reach")
	check(PickMath.nearest({}, 0, 0, math.huge) == nil, "none at all")
end

function tests.dpadStepsToTheNearestBallThatWay()
	-- Screen pixels, y down.
	local points = {
		{ id = 1, x = 100, y = 100 },
		{ id = 2, x = 200, y = 100 }, -- straight right of 1
		{ id = 3, x = 160, y = 40 }, -- up and right of 1, nearer but off the line
		{ id = 4, x = 100, y = 300 }, -- straight down
	}
	check(
		PickMath.step(points, 100, 100, 1, 0, 1) == 2,
		"right: straight beats nearer-but-sideways"
	)
	check(PickMath.step(points, 100, 100, 0, 1, 1) == 4, "down")
	check(PickMath.step(points, 100, 100, 0, -1, 1) == 3, "up: the one up there")
	check(PickMath.step(points, 100, 100, -1, 0, 1) == nil, "nothing to the left")
	check(PickMath.step(points, 100, 100, 0, 0, 1) == nil, "no push")
	check(PickMath.step(points, 100, 100, 1, 0, 2) == 3, "skipping the current one")
end

function tests.spotsStayOnTheCloth()
	local x, y = PickMath.clampToCloth(500, -500, geometry)
	check(math.abs(x - (geometry.halfLength - CLEAR)) < 1e-9, "x inside the cushion line")
	check(math.abs(y + (geometry.halfWidth - CLEAR)) < 1e-9, "y inside the cushion line")
	local a, b = PickMath.clampToCloth(3, 4, geometry)
	check(a == 3 and b == 4, "a spot on the cloth is kept")
	local sx, sy = PickMath.startSpot(geometry)
	check(math.abs(sx) <= geometry.halfLength - CLEAR and sy == 0, "portal A's gamepad start")
end

function tests.partnerSpotIsFarEnoughApart()
	for _, ax in { -25, -3, 0, 4, 30, geometry.halfLength } do
		local cx, cy = PickMath.clampToCloth(ax, 5, geometry)
		local bx, by = PickMath.partnerSpot(cx, cy, geometry)
		local gap = math.sqrt((bx - cx) ^ 2 + (by - cy) ^ 2)
		check(
			gap >= Pick.PortalMinGapInches,
			("B is %.2f in from A at x=%s"):format(gap, tostring(ax))
		)
		check(math.abs(bx) <= geometry.halfLength - CLEAR + 1e-9, "B on the cloth")
	end
end

function tests.spotClearAgreesWithArming()
	local balls = { Ball.new(0, -30, 0), Ball.new(1, 20, 10) }
	check(PickMath.spotClear(0, 0, geometry, balls), "open cloth")
	check(not PickMath.spotClear(20, 10, geometry, balls), "on a ball")
	check(not PickMath.spotClear(20 + R, 10, geometry, balls), "touching a ball")
	check(not PickMath.spotClear(0, geometry.halfWidth - R, geometry, balls), "against a cushion")
	local pocket = geometry.pockets[1]
	check(not PickMath.spotClear(pocket.x, pocket.y, geometry, balls), "in a pocket")
	-- Two clear spots far apart: the server's own check takes them.
	local ok =
		Arming.pick("Portals", { ax = 0, ay = 0, bx = 35, by = -10 }, geometry, nil, 1, balls)
	check(ok ~= nil, "a pair of clear spots is accepted")
	local _, why =
		Arming.pick("Portals", { ax = 0, ay = 0, bx = 3, by = 0 }, geometry, nil, 1, balls)
	check(why == "PortalsTooClose", "two clear spots too close")
end

return tests
