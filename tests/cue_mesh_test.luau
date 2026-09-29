--!strict
-- The shared cue mesh's catalog hook-up (Config.Cue.MeshSkins, CueStickBuilder's mesh path).

local H = require("./harness")

return {
	["every mesh skin is a catalog cue"] = function()
		local Config = H.require("Config")
		local Catalog = H.require("Progression.Catalog")
		H.expect(#Config.Cue.MeshSkins >= 1, "at least one mesh skin")
		local seen = {}
		for _, id in Config.Cue.MeshSkins do
			H.expect(Catalog.exists(id), id .. " is not a catalog cue")
			H.expect(not seen[id], id .. " is listed twice")
			seen[id] = true
		end
		H.expect(seen[Config.Cue.DefaultStyle] == true, "the default cue is drawn from the mesh")
	end,

	["one mesh skin until the SurfaceAppearance swap exists"] = function()
		-- CueStickBuilder's slot shows its own template's SurfaceAppearance. A second mesh
		-- skin needs the swap described in CueStickBuilder's paint (clone the template's
		-- SurfaceAppearance into the slot); write it, then raise this limit.
		local Config = H.require("Config")
		H.expect(#Config.Cue.MeshSkins == 1, "a second mesh skin needs the SurfaceAppearance swap")
	end,
}
