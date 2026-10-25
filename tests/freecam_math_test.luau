--!strict
-- FreecamMath: the lobby freecam stays inside the rooftop's walls and under their tops, slides
-- along a wall it is pushed into, reaches the stairs, and never tips past its pitch limit.

local H = require("./harness")

local function load()
	return H.require("FreecamMath"), H.require("Config")
end

local still = { lookX = 0, lookY = 0, moveX = 0, moveZ = 0, rise = 0, fast = false }

local function inside(F: any, x: number, y: number, z: number): boolean
	local inset = F.WallInsetStuds
	for _, box in F.Boxes do
		if
			x >= box.MinX + inset - 1e-6
			and x <= box.MaxX - inset + 1e-6
			and z >= box.MinZ + inset - 1e-6
			and z <= box.MaxZ - inset + 1e-6
			and y >= box.MinY - 1e-6
			and y <= box.MaxY + 1e-6
		then
			return true
		end
	end
	return false
end

return {
	["a point inside the roof is left where it is"] = function()
		local M, Config = load()
		local x, y, z = M.clamp(10, 6, -20, Config.Freecam)
		H.near(x, 10, 1e-9)
		H.near(y, 6, 1e-9)
		H.near(z, -20, 1e-9)
	end,

	["past every wall and over the tops comes back inside"] = function()
		local M, Config = load()
		local F = Config.Freecam
		for _, p in
			{
				{ 200, 6, 0 }, -- the ocean side
				{ -200, 6, 0 }, -- the city side
				{ 0, 6, -300 }, -- behind the lounge
				{ 50, 6, 150 }, -- out the front, beside the stairs
				{ 0, 6, 150 }, -- out past the lower landing
				{ 0, 500, 0 }, -- up over the walls
				{ 0, -50, 0 }, -- down through the floor
			}
		do
			local x, y, z = M.clamp(p[1], p[2], p[3], F)
			H.expect(inside(F, x, y, z), ("(%d, %d, %d) came back inside"):format(p[1], p[2], p[3]))
			H.expect(math.abs(x) < 93 and z < 106.85 and y < 40, "never at or past a wall")
		end
	end,

	["the stairs to the lower landing are reachable"] = function()
		local M, Config = load()
		local x, y, z = M.clamp(0, 1, 100, Config.Freecam)
		H.near(x, 0, 1e-9)
		H.near(y, 1, 1e-9)
		H.near(z, 100, 1e-9)
	end,

	["a push into a wall slides along it"] = function()
		local M, Config = load()
		local F = Config.Freecam
		-- Facing the ocean wall (yaw -90: +X) right against it, pushed forward and right.
		local state = { x = 93 - F.WallInsetStuds, y = 6, z = 0, yaw = -math.pi / 2, pitch = 0 }
		local input = { lookX = 0, lookY = 0, moveX = 1, moveZ = -1, rise = 0, fast = false }
		local after = M.step(state, input, 0.5, F, F)
		H.near(after.x, 93 - F.WallInsetStuds, 1e-6, "held at the wall")
		H.expect(after.z > 1, "slid along it")
	end,

	["it flies where it looks, and the pitch stops at the limit"] = function()
		local M, Config = load()
		local F = Config.Freecam
		local state = { x = 0, y = 6, z = 0, yaw = 0, pitch = 0 }
		local forward = { lookX = 0, lookY = 0, moveX = 0, moveZ = -1, rise = 0, fast = false }
		local moved = M.step(state, forward, 1, F, F)
		H.near(moved.z, -F.SpeedStuds, 1e-2, "yaw 0 looks down -Z (at full speed after a second)")
		local tipped = M.step(
			state,
			{ lookX = 0, lookY = 10, moveX = 0, moveZ = 0, rise = 0, fast = false },
			1,
			F,
			F
		)
		H.near(tipped.pitch, math.rad(F.PitchLimitDegrees), 1e-9, "held at the limit")
		local climbed = M.step(tipped, forward, 0.5, F, F)
		H.expect(climbed.y > 6, "looking up and flying forward climbs")
		local still2 = M.step(state, still, 1, F, F)
		H.near(still2.x, 0, 1e-9)
		H.near(still2.z, 0, 1e-9)
	end,

	["let go, it glides a little, then rests"] = function()
		local M, Config = load()
		local F = Config.Freecam
		local forward = { lookX = 0, lookY = 0, moveX = 0, moveZ = -1, rise = 0, fast = false }
		local state = { x = 0, y = 6, z = 0, yaw = 0, pitch = 0 }
		for _ = 1, 60 do
			state = M.step(state, forward, 1 / 60, F, F)
		end
		H.near(state.vz or 0, -F.SpeedStuds, 0.05 * F.SpeedStuds, "up to speed within a second")
		local at = state.z
		local after = M.step(state, still, 1 / 60, F, F)
		H.expect(after.z < at - 0.1, "still moving the frame after letting go")
		for _ = 1, 120 do
			after = M.step(after, still, 1 / 60, F, F)
		end
		local glide = at - after.z
		H.expect(
			glide > 0.5 * F.SpeedStuds * F.GlideSeconds
				and glide < 1.5 * F.SpeedStuds * F.GlideSeconds,
			("glided about Speed x GlideSeconds (%.2f studs)"):format(glide)
		)
		H.expect(math.abs(after.vz or 0) < 0.01, "at rest after two seconds")
	end,

	["a wall stops the velocity going into it"] = function()
		local M, Config = load()
		local F = Config.Freecam
		local edge = 93 - F.WallInsetStuds
		local state = { x = edge, y = 6, z = 0, yaw = 0, pitch = 0, vx = 20, vy = 0, vz = -5 }
		local after = M.step(state, still, 1 / 60, F, F)
		H.near(after.x, edge, 1e-9, "held at the wall")
		H.near(after.vx or 0, 0, 1e-9, "no speed left into it")
		H.expect((after.vz or 0) < 0, "still sliding along it")
	end,
}
