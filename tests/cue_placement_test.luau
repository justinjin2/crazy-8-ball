--!strict
-- Legal placement protects server physics from malformed positions and overlap, while
-- deterministic fallback keeps setup deadlines playable without client input.

local H = require("./harness")

local function setup()
	local Config = H.require("Config")
	local Placement = H.require("Rules.CuePlacement")
	local Ball = H.require("Physics.Ball")
	local Geometry = H.require("Physics.Table")
	local geometry = Geometry.build()
	local balls = H.require("Physics.Rack").newGame(geometry)
	return Placement, balls, geometry, Config, Ball, Geometry
end

return {
	["break placements stay on the head string and inside cushion bounds"] = function()
		local Placement, balls, geometry, Config = setup()
		local x = Config.Multiplayer.BreakLineX
		for _, y in { -20, 0, 20 } do
			H.expect(Placement.valid(balls, geometry, x, y, true))
		end
		H.expect(not Placement.valid(balls, geometry, x + 0.1, 0, true))
		H.expect(not Placement.valid(balls, geometry, x, geometry.halfWidth, true))
		H.expect(
			Placement.valid(balls, geometry, 0, 0, false),
			"ordinary ball-in-hand can cross the head string"
		)
	end,

	["placement rejects nonfinite positions and every outer edge"] = function()
		local Placement, balls, geometry = setup()
		for _, value in { 0 / 0, math.huge, -math.huge } do
			H.expect(not Placement.valid(balls, geometry, value, 0, false))
			H.expect(not Placement.valid(balls, geometry, 0, value, false))
		end
		for _, position in { { 50, 0 }, { -50, 0 }, { 0, 25 }, { 0, -25 }, { 100, 100 } } do
			H.expect(not Placement.valid(balls, geometry, position[1], position[2], false))
		end
	end,

	["cue cannot overlap objects but ignores its own previous position"] = function()
		local Placement, balls, geometry, Config = setup()
		H.expect(Placement.valid(balls, geometry, balls[1].x, balls[1].y, false))
		local object = balls[2]
		H.expect(not Placement.valid(balls, geometry, object.x, object.y, false))
		H.expect(
			not Placement.valid(
				balls,
				geometry,
				object.x - 2 * Config.Balls.RadiusInches,
				object.y,
				false
			),
			"extra clearance prevents touching collisions"
		)
		H.expect(
			Placement.valid(
				balls,
				geometry,
				object.x - 2 * Config.Balls.RadiusInches - 0.1,
				object.y,
				false
			)
		)
		object.pocketed = true
		H.expect(
			Placement.valid(
				balls,
				geometry,
				object.x - 2 * Config.Balls.RadiusInches,
				object.y,
				false
			),
			"down balls do not obstruct placement"
		)
	end,

	["all pocket openings and custom jaws are excluded"] = function()
		local Placement, balls, geometry = setup()
		for _, pocket in geometry.pockets do
			H.expect(not Placement.valid(balls, geometry, pocket.x, pocket.y, false))
		end
		local custom = table.clone(geometry)
		custom.pockets = { { id = 1, x = 0, y = 0, radius = 2, name = "fixture" } }
		H.expect(
			not Placement.valid(balls, custom, 2.5, 0, false),
			"a placed ball cannot overhang a hole"
		)
		custom.pockets = {}
		custom.points = { { x = 0, y = 0, radius = 1, name = "fixture" } }
		H.expect(not Placement.valid(balls, custom, 1.5, 0, false))
		custom.points = {}
		custom.segments = { { ax = 0, ay = -3, bx = 0, by = 3, nx = 1, ny = 0, name = "fixture" } }
		H.expect(not Placement.valid(balls, custom, 0.5, 0, false))
	end,

	["invalid request leaves every ball byte-for-byte unchanged"] = function()
		local Placement, balls, geometry, _, Ball = setup()
		local before = Ball.cloneList(balls)
		H.expect(not Placement.place(balls, geometry, balls[2].x, balls[2].y, false))
		for i, ball in balls do
			for key, value in before[i] do
				H.expect(ball[key] == value, "invalid placement mutated " .. key)
			end
		end
	end,

	["accepted placement clears scratch fall and spin without moving objects"] = function()
		local Placement, balls, geometry, _, Ball = setup()
		local cue = balls[1]
		cue.pocketed, cue.falling, cue.pocket = true, true, 2
		cue.z, cue.vx, cue.vy, cue.vz, cue.wx, cue.wy, cue.wz = -3, 1, 2, 3, 4, 5, 6
		cue.tip = { px = 0, py = 0, nx = 1, ny = 0, theta = 1, omega = 2 }
		local objects = Ball.cloneList(balls)
		H.expect(Placement.place(balls, geometry, 0, 0, false))
		H.expect(cue.x == 0 and cue.y == 0 and cue.z == 0 and not cue.pocketed and not cue.falling)
		H.expect(cue.pocket == nil and cue.tip == nil)
		H.expect(
			cue.vx == 0
				and cue.vy == 0
				and cue.vz == 0
				and cue.wx == 0
				and cue.wy == 0
				and cue.wz == 0
		)
		for i = 2, #balls do
			H.expect(balls[i].x == objects[i].x and balls[i].y == objects[i].y)
		end
	end,

	["fallback is deterministic and legal when the head spot is occupied"] = function()
		local Placement, balls, geometry, Config = setup()
		balls[2].x, balls[2].y = Config.Multiplayer.BreakLineX, 0
		for _, isBreak in { true, false } do
			local x, y = Placement.fallback(balls, geometry, isBreak)
			local repeatX, repeatY = Placement.fallback(balls, geometry, isBreak)
			H.expect(x == repeatX and y == repeatY)
			H.expect(Placement.valid(balls, geometry, x, y, isBreak))
			if isBreak then
				H.expect(x == Config.Multiplayer.BreakLineX and y ~= 0)
			end
		end
	end,

	["eight respots at the foot spot and clears all pocket motion"] = function()
		local Placement, balls, geometry, _, _, Geometry = setup()
		for _, ball in balls do
			if ball.id > 0 then
				ball.pocketed = true
			end
		end
		balls[9].falling, balls[9].pocket, balls[9].vx, balls[9].wz = true, 1, 8, 9
		local x, y = Geometry.footSpot(geometry)
		H.expect(Placement.respotEight(balls, geometry))
		H.expect(balls[9].x == x and balls[9].y == y)
		H.expect(not balls[9].pocketed and not balls[9].falling and balls[9].pocket == nil)
		H.expect(balls[9].vx == 0 and balls[9].wz == 0)
		H.expect(
			balls[1].x == -25 and balls[2].pocketed,
			"cue and other object balls are untouched"
		)
	end,

	["blocked eight spot searches deterministically without overlapping any ball"] = function()
		local Placement, balls, geometry, Config = setup()
		balls[9].pocketed = true
		local x, y = Placement.fallback(balls, geometry, false, 8)
		H.expect(Placement.respotEight(balls, geometry))
		H.expect(balls[9].x == x and balls[9].y == y)
		for _, ball in balls do
			if ball.id ~= 8 and not ball.pocketed then
				H.expect((x - ball.x) ^ 2 + (y - ball.y) ^ 2 >= (2 * Config.Balls.RadiusInches) ^ 2)
			end
		end
	end,

	["resolve leaves a legal spot exactly where it was asked for"] = function()
		local Placement, balls, geometry, Config = setup()
		local state = { balls = balls, geometry = geometry, time = 0 }
		local x, y = Placement.resolve(state, -10, 4, false, balls[1].x, balls[1].y)
		H.expect(x == -10 and y == 4)
		local bx, by = Placement.resolve(state, 123, 5, true, Config.Multiplayer.BreakLineX, 0)
		H.expect(bx == Config.Multiplayer.BreakLineX and by == 5, "the break keeps x exactly")
	end,

	["resolve clamps an off-table want onto the cushions"] = function()
		local Placement, balls, geometry, Config = setup()
		local state = { balls = balls, geometry = geometry, time = 0 }
		local M = Config.Multiplayer
		local r = Config.Balls.RadiusInches + M.PlacementClearanceInches
		local x, y = Placement.resolve(state, -15, 1000, false, balls[1].x, balls[1].y)
		H.expect(x == -15 and Placement.valid(balls, geometry, x, y, false))
		H.near(y, geometry.halfWidth - r, 2 * M.PlacementResolveSlopInches, "long rail")
		x, y = Placement.resolve(state, -1000, 0, false, balls[1].x, balls[1].y)
		H.expect(y == 0 and Placement.valid(balls, geometry, x, y, false))
		H.near(x, -geometry.halfLength + r, 2 * M.PlacementResolveSlopInches, "head rail")
		x, y = Placement.resolve(state, 0, -1000, true, M.BreakLineX, 0)
		H.expect(x == M.BreakLineX and Placement.valid(balls, geometry, x, y, true))
	end,

	["resolve pushes out of a lone object ball along the contact normal"] = function()
		local Placement, _, geometry, Config, Ball = setup()
		local balls = { Ball.new(0, -30, 0), Ball.new(3, 0, 0) }
		local state = { balls = balls, geometry = geometry, time = 0 }
		local M = Config.Multiplayer
		local need = 2 * Config.Balls.RadiusInches + M.PlacementClearanceInches
		local x, y = Placement.resolve(state, 0.5, 0, false, -30, 0)
		H.near(x, need, 2 * M.PlacementResolveSlopInches, "pushed straight out")
		H.expect(y == 0 and Placement.valid(balls, geometry, x, y, false))
		-- Dead centre: leave toward where the drag came from, the same way every time.
		local cx, cy = Placement.resolve(state, 0, 0, false, -30, 0)
		local rx, ry = Placement.resolve(state, 0, 0, false, -30, 0)
		H.expect(cx == rx and cy == ry and cx < 0 and cy == 0)
		H.expect(Placement.valid(balls, geometry, cx, cy, false))
	end,

	["resolve on the break slides along the head string past a ball"] = function()
		local Placement, _, geometry, Config, Ball = setup()
		local X = Config.Multiplayer.BreakLineX
		local balls = { Ball.new(0, X, -10), Ball.new(3, X + 1, 0) }
		local state = { balls = balls, geometry = geometry, time = 0 }
		local x, y = Placement.resolve(state, X + 7, 0.5, true, X, -10)
		H.expect(x == X and y > 0.5, "stays on the line and leaves on its own side")
		H.expect(Placement.valid(balls, geometry, x, y, true))
	end,

	["resolve walks back along the drag when the want is wedged"] = function()
		local Placement, _, geometry, Config, Ball = setup()
		local R = Config.Balls.RadiusInches
		-- A closed ring of balls around the want: no push-out can escape it.
		local balls = { Ball.new(0, -30, 0) }
		for i = 0, 7 do
			local a = i * math.pi / 4
			table.insert(balls, Ball.new(i + 1, 2 * R * math.cos(a), 2 * R * math.sin(a)))
		end
		local state = { balls = balls, geometry = geometry, time = 0 }
		local x, y = Placement.resolve(state, 0, 0, false, -30, 0)
		H.expect(x ~= nil and y ~= nil)
		H.expect(Placement.valid(balls, geometry, x :: number, y :: number, false))
		H.expect(
			y == 0 and (x :: number) > -30 and (x :: number) < 0,
			"on the drag, as far as it goes"
		)
		-- Nothing legal to walk back to: the caller keeps its own spot.
		local fx, fy = Placement.resolve(state, 0, 0, false, 0.5, 0)
		H.expect(fx == 0.5 and fy == 0)
		local nx, ny = Placement.resolve(state, 0, 0, false, nil, nil)
		H.expect(nx == nil and ny == nil)
	end,

	["resolve ignores a nonfinite want"] = function()
		local Placement, balls, geometry = setup()
		local state = { balls = balls, geometry = geometry, time = 0 }
		for _, value in { 0 / 0, math.huge, -math.huge } do
			local x, y = Placement.resolve(state, value, 0, false, 1, 2)
			H.expect(x == 1 and y == 2)
			x, y = Placement.resolve(state, 0, value, true, 1, 2)
			H.expect(x == 1 and y == 2)
		end
	end,

	["every resolved drag spot across the table is legal and repeatable"] = function()
		local Placement, balls, geometry, Config = setup()
		local state = { balls = balls, geometry = geometry, time = 0 }
		for _, isBreak in { false, true } do
			local fromX, fromY = Placement.fallback(balls, geometry, isBreak)
			local count = 0
			-- A serpentine drag over a 7-inch grid reaching past every cushion, each sample
			-- starting from the last one's answer the way a real drag does.
			local row = 0
			for wy = -geometry.halfWidth - 7, geometry.halfWidth + 7, 7 do
				row += 1
				local startX, stopX, step = -geometry.halfLength - 7, geometry.halfLength + 7, 7
				if row % 2 == 0 then
					startX, stopX, step = stopX, startX, -7
				end
				for wx = startX, stopX, step do
					local x, y = Placement.resolve(state, wx, wy, isBreak, fromX, fromY)
					local again, againY = Placement.resolve(state, wx, wy, isBreak, fromX, fromY)
					H.expect(x == again and y == againY, "resolve is deterministic")
					H.expect(x ~= nil and y ~= nil)
					H.expect(
						Placement.valid(balls, geometry, x :: number, y :: number, isBreak),
						("illegal spot for want %.1f, %.1f"):format(wx, wy)
					)
					if isBreak then
						H.expect(x == Config.Multiplayer.BreakLineX)
					end
					fromX, fromY = x :: number, y :: number
					count += 1
				end
			end
			H.expect(count > 100)
		end
	end,

	["missing cue or eight cannot mutate another ball"] = function()
		local Placement, _, geometry, _, Ball = setup()
		local balls = { Ball.new(1, 10, 0) }
		H.expect(not Placement.place(balls, geometry, 0, 0, false))
		H.expect(not Placement.respotEight(balls, geometry))
		H.expect(balls[1].x == 10 and balls[1].id == 1)
	end,
}
