--!strict
-- Checks the built table package (assets/table/Parameters.json, written by TableModel.py from
-- measurements of the exported mesh) against Config and the physics.
--
-- The drawn cushions, jaws and pocket rims have to be where the balls actually play, or a
-- ball bounces off thin air in front of a jaw or starts to drop over cloth. Rebuild the
-- package after any change to Config.Table or Physics.Table; this test names what drifted.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local H = require("./harness")
local TableGeometryExport = require("./table_geometry")

local PARAMETERS = "assets/table/Parameters.json"
local REBUILD = "rebuild the package (assets/table/TableModel.py)"
local TOL = 0.01 -- inches: how far a drawn surface the ball touches may sit from the physics
local ROBLOX_MESH_LIMIT = 20000 -- triangles per MeshPart

local function load(): any
	return serde.decode("json", fs.readFile(PARAMETERS)) :: any
end

local function byName(list: { any }): { [string]: any }
	local out = {}
	for _, item in list do
		out[item.name] = item
	end
	return out
end

return {
	["the package was built from today's Geometry.json"] = function()
		local p = load()
		local g = TableGeometryExport.build()
		H.expect(p.geometry_source.schema == g.schema_version, "geometry schema: " .. REBUILD)
		-- The committed Geometry.json is checked against the physics by table_geometry_test;
		-- here the package must have been built from that same file.
		local json = fs.readFile(TableGeometryExport.PATH)
		H.expect(#json > 0, "Geometry.json is empty")
		H.expect(type(p.geometry_source.sha256) == "string", "geometry_source.sha256 missing")
	end,

	["the mesh matches Config's table numbers"] = function()
		local p = load()
		local T = H.require("Config").Table
		local t = p.roblox_local.Table
		H.near(t.StudsPerInch, T.StudsPerInch, 1e-9, "StudsPerInch")
		H.near(t.SurfaceHeightStuds, T.SurfaceHeightStuds, 1e-6, "SurfaceHeightStuds")
		H.near(t.RailWidthInches, T.RailWidthInches, 1e-6, "RailWidthInches")
		H.near(t.RailTopInches, T.RailTopInches, TOL, "RailTopInches (rail crown)")
		H.near(
			t.PocketCastingTopInches,
			T.PocketCastingTopInches,
			TOL,
			"PocketCastingTopInches (cap crown)"
		)
		H.expect(
			t.MinPocketDepthInches >= T.MinPocketDepthInches,
			("pocket cups are %.3f in deep, Config wants at least %.3f"):format(
				t.MinPocketDepthInches,
				T.MinPocketDepthInches
			)
		)
	end,

	["every drawn nose line, jaw and pocket rim is on the physics"] = function()
		local p = load()
		local g = TableGeometryExport.build()
		local drawn = byName(p.measured.segments)
		for _, seg in g.segments do
			local d = drawn[seg.name]
			H.expect(d ~= nil, "no drawn nose line for " .. seg.name)
			H.near(d.a[1], seg.a[1], TOL, seg.name .. ".a.x")
			H.near(d.a[2], seg.a[2], TOL, seg.name .. ".a.y")
			H.near(d.b[1], seg.b[1], TOL, seg.name .. ".b.x")
			H.near(d.b[2], seg.b[2], TOL, seg.name .. ".b.y")
			H.expect(d.max_deviation <= TOL, seg.name .. " strays from its line")
		end
		local points = byName(p.measured.points)
		for _, pt in g.points do
			local d = points[pt.name]
			H.expect(d ~= nil, "no drawn point for " .. pt.name)
			H.near(d.x, pt.x, TOL, pt.name .. ".x")
			H.near(d.y, pt.y, TOL, pt.name .. ".y")
		end
		H.near(p.measured.cushion_nose_height, g.cushion.nose_height, TOL, "nose height")
		for i, hole in g.holes do
			local d = p.measured.holes[i]
			H.expect(d.id == hole.id, "holes out of order")
			H.near(d.fit_centre[1], hole.x, TOL, ("hole %d centre x"):format(hole.id))
			H.near(d.fit_centre[2], hole.y, TOL, ("hole %d centre y"):format(hole.id))
			H.expect(d.rim_min >= hole.radius - TOL, ("hole %d rim too small"):format(hole.id))
			H.expect(d.rim_max <= hole.radius + TOL, ("hole %d rim too big"):format(hole.id))
			H.expect(
				d.clear_min >= hole.clear_radius - TOL,
				("hole %d cup pinches the drawn ball"):format(hole.id)
			)
			H.expect(d.depth >= g.pockets.min_depth, ("hole %d cup too shallow"):format(hole.id))
		end
	end,

	["the chrome caps stay under the cue's clearance line"] = function()
		local p = load()
		local T = H.require("Config").Table
		for kind, profile in p.measured.casting_profile do
			for _, row in profile do
				local d, z = row[1], row[2]
				local w =
					math.clamp((T.PocketCastingReachInches - d) / T.PocketCastingBlendInches, 0, 1)
				local limit = T.RailTopInches + (T.PocketCastingTopInches - T.RailTopInches) * w
				H.expect(
					z <= limit + TOL,
					("%s cap is %.3f in high at %.1f in from the pocket, the cue clears %.3f"):format(
						kind,
						z,
						d,
						limit
					)
				)
			end
		end
	end,

	["the model fits its outline, its budget and faces the right way"] = function()
		local p = load()
		local Config = H.require("Config")
		local g = TableGeometryExport.build()
		local m = p.measured
		H.near(m.rail_outer_half_extents[1], g.rail.outer_half_length, TOL, "outer half length")
		H.near(m.rail_outer_half_extents[2], g.rail.outer_half_width, TOL, "outer half width")
		H.expect(
			m.bounds_half_extents_studs[1] <= g.rail.barrier_half_extents_studs[1],
			"past the barrier (x)"
		)
		H.expect(
			m.bounds_half_extents_studs[2] <= g.rail.barrier_half_extents_studs[2],
			"past the barrier (y)"
		)
		H.expect(
			m.logo_plate_x > 0,
			"the logo plate must be at the foot (+x): the orientation marker"
		)
		local TM = Config.TableModel
		local total = 0
		for name in TM.Meshes do
			local n = p.triangle_counts[name]
			H.expect(n ~= nil, "Config lists mesh " .. name .. " but the package has none")
			H.expect(n < ROBLOX_MESH_LIMIT, name .. " is over Roblox's per-mesh triangle limit")
			total += n
		end
		for name in p.triangle_counts do
			H.expect(
				name == "Total" or TM.Meshes[name] ~= nil,
				"package mesh " .. name .. " is not in Config"
			)
		end
		H.expect(
			total <= TM.TriangleBudget,
			("%d triangles, budget %d"):format(total, TM.TriangleBudget)
		)
	end,
}
