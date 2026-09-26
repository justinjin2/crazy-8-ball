--!strict
-- Checks the map's drifting sailboats (MapMotion.boatPose with Config.Map.Near.Boat): the same
-- time gives the same pose (every client agrees), they drift slowly and smoothly with the bow
-- ahead, and every path stays out at sea, clear of the land and the beach (the coast is the
-- one assets/map/city_plan.py writes into assets/map/Layout.json).

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local H = require("./harness")

local LAYOUT = "assets/map/Layout.json"
local CLEAR = 150 -- studs a boat keeps from the land's edge

local function setup()
	local Config = H.require("Config")
	local MapMotion = H.require("MapMotion")
	return Config.Map.Near.Boat, MapMotion
end

-- Every path sampled over one loop, dt apart.
local function samples(path: any, dt: number): { number }
	local out = {}
	local t = 0
	while t <= path.Seconds do
		table.insert(out, t)
		t += dt
	end
	return out
end

return {
	["the same time gives the same pose"] = function()
		local Boat, MapMotion = setup()
		for _, path in Boat.Paths do
			for _, t in { 0, 12.5, 1234.567, 1.7e9 } do
				local a, b = MapMotion.boatPose(path, t, Boat), MapMotion.boatPose(path, t, Boat)
				H.expect(
					a.x == b.x and a.y == b.y and a.z == b.z and a.yaw == b.yaw,
					"deterministic"
				)
			end
		end
	end,

	["boats drift slowly and smoothly, bow first"] = function()
		local Boat, MapMotion = setup()
		local dt = 0.25
		for i, path in Boat.Paths do
			H.expect(
				MapMotion.topSpeed(path) <= Boat.MaxSpeed,
				("boat %d's top speed %.2f is over MaxSpeed %.2f"):format(
					i,
					MapMotion.topSpeed(path),
					Boat.MaxSpeed
				)
			)
			local prev = MapMotion.boatPose(path, 0, Boat)
			for _, t in samples(path, dt) do
				local p = MapMotion.boatPose(path, t + dt, Boat)
				local dx, dz = p.x - prev.x, p.z - prev.z
				local step = math.sqrt(dx * dx + dz * dz)
				H.expect(
					step / dt <= Boat.MaxSpeed * 1.001,
					("boat %d jumps %.2f studs at %.2f"):format(i, step, t)
				)
				if step > 1e-6 then
					-- The bow (the boat's +Z turned by yaw) points the way it is going.
					local fx, fz = math.sin(prev.yaw), math.cos(prev.yaw)
					H.expect(
						(fx * dx + fz * dz) / step > 0.98,
						("boat %d sails sideways at %.2f"):format(i, t)
					)
				end
				H.expect(math.abs(p.y - Boat.SeaY) <= Boat.BobHeight + 1e-9, "bobs only a little")
				prev = p
			end
		end
	end,

	["every boat stays at sea, clear of the land"] = function()
		local Boat, MapMotion = setup()
		local world = (serde.decode("json", fs.readFile(LAYOUT)) :: any).world
		H.expect(world ~= nil, "Layout.json has the world (re-run assets/map/map_layout.py)")
		H.expect(Boat.SeaY == world.sea_y, "Config's boat SeaY is city_plan's sea_y")
		-- The city's shore behind the waterline (city_plan.city_edge_x).
		local function cityEdge(z: number): number
			return math.min(
				world.city_edge_max,
				world.city_back_x + (world.city_bend_z - z) * world.city_creep
			)
		end
		for i, path in Boat.Paths do
			for _, t in samples(path, 5) do
				local p = MapMotion.boatPose(path, t, Boat)
				local offOceanSide = p.x > world.shore_x + CLEAR
				local behind = p.z < world.shore_z - CLEAR and p.x > cityEdge(p.z) + CLEAR
				H.expect(
					offOceanSide or behind,
					("boat %d reaches (%.0f, %.0f), too near the land"):format(i, p.x, p.z)
				)
			end
		end
	end,
}
