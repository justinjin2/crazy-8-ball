--!strict
-- Checks Config.Map (the rooftop map's architecture, MapBuilder.prepareImport) against itself and
-- the package: every mesh the generator exports has a row, every row's map set exists, ids and
-- colours are shapes Studio accepts, and the images fit the map's budget.
--
-- The architecture is data rows plus uploaded maps, so a typo here would otherwise only show up
-- as a bare or grey mesh in Studio.

local fs = require("@lune/fs")

local H = require("./harness")

-- Enum.AlphaMode and Enum.Material item names (Config cannot name Enum, so it stores strings).
local ALPHA_MODES = { Opaque = true, Overlay = true, TintMask = true, Transparency = true }
local MATERIALS =
	{ Slate = true, Concrete = true, SmoothPlastic = true, Marble = true, Granite = true }

-- The meshes assets/map/gen_rooftop.py exports (its docstring and geometry()).
local GENERATED = {
	"Parapet",
	"RailingFrame",
	"RailingGlass",
	"Steps",
	"Pergola",
	"PergolaSlats",
	"Vines",
	"TowerTop",
	"TableGlow",
	"FloorShade",
}

local function isAssetId(id: string): boolean
	return id == "" or id:match("^rbxassetid://%d+$") ~= nil
end

local function isHex(colour: string): boolean
	return colour:match("^#%x%x%x%x%x%x$") ~= nil
end

return {
	["every exported mesh has a row, and every row is exported"] = function()
		local M = H.require("Config").Map
		local exported = {}
		for _, name in GENERATED do
			exported[name] = true
			H.expect(M.Meshes[name] ~= nil, ("Config.Map.Meshes has no row for %s"):format(name))
		end
		for name in M.Meshes do
			H.expect(
				exported[name],
				("Config.Map.Meshes.%s is not a mesh the generator exports"):format(name)
			)
		end
		-- The generator's source names each one.
		local source = fs.readFile("assets/map/gen_rooftop.py")
		for _, name in GENERATED do
			H.expect(
				source:find(("Mesh('%s')"):format(name), 1, true) ~= nil,
				name .. " is built in gen_rooftop.py"
			)
		end
	end,

	["each mesh is a map set or a flat colour, in shapes Studio accepts"] = function()
		local M = H.require("Config").Map
		for name, ms in M.Meshes do
			H.expect(type(ms.CastShadow) == "boolean", name .. ": CastShadow")
			if ms.Maps then
				H.expect(
					M.Maps[ms.Maps] ~= nil,
					("%s names the map set %s, which Maps lacks"):format(name, ms.Maps)
				)
			else
				H.expect(
					ms.Color ~= nil and isHex(ms.Color),
					name .. ": a flat mesh needs a hex Color"
				)
			end
			if ms.AlphaMode then
				H.expect(ALPHA_MODES[ms.AlphaMode], name .. ": AlphaMode " .. ms.AlphaMode)
			end
			if ms.Transparency then
				H.expect(
					ms.Transparency >= 0 and ms.Transparency < 1,
					name .. ": Transparency in [0, 1)"
				)
			end
		end
	end,

	["map ids are empty or rbxassetid, and the images fit the budget"] = function()
		local M = H.require("Config").Map
		local unique: { [string]: boolean } = {}
		local count = 0
		local function add(id: string?, where: string)
			if id == nil then
				return
			end
			H.expect(isAssetId(id), ("%s: %q is not an asset id"):format(where, id))
			if id ~= "" and not unique[id] then
				unique[id] = true
				count += 1
			end
		end
		for set, maps in M.Maps do
			add(maps.Color, set .. ".Color")
			add(maps.Normal, set .. ".Normal")
			add(maps.Roughness, set .. ".Roughness")
		end
		add(M.Floor.Color, "Floor.Color")
		add(M.Floor.Normal, "Floor.Normal")
		H.expect(
			count <= M.ImageBudget,
			("the map uses %d images, over the budget of %d"):format(count, M.ImageBudget)
		)
	end,

	["every table sits the same way on the floor's slabs"] = function()
		local Config = H.require("Config")
		local F = Config.Map.Floor
		H.expect(MATERIALS[F.BaseMaterial], "Floor.BaseMaterial " .. F.BaseMaterial)
		H.expect(isHex(F.Tint), "Floor.Tint is a hex colour")
		-- One image holds 2 x 2 slabs, mapped from the world origin. Across, every table's
		-- offset is whole slabs; along, the rows mirror about Z = 0, so each row has a twin.
		local slab = F.StudsPerTile / 2
		local rows = Config.Hub.Tables
		local zs: { [number]: boolean } = {}
		for _, row in rows do
			H.near(
				row.X / slab,
				math.round(row.X / slab),
				1e-9,
				("table %d's X is whole slabs"):format(row.id)
			)
			zs[row.Z] = true
		end
		for z in zs do
			H.expect(zs[-z] ~= nil, ("the row at Z %.2f has a mirror twin"):format(z))
		end
	end,

	["the day lighting preset is numbers and hex colours"] = function()
		local Day = H.require("Config").Lighting.Day
		local function check(t: { [string]: any }, where: string)
			for key, value in t do
				if type(value) == "table" then
					check(value, where .. "." .. key)
				elseif type(value) == "string" then
					H.expect(
						isHex(value),
						("%s.%s: %q is not a hex colour"):format(where, key, value)
					)
				else
					H.expect(type(value) == "number", ("%s.%s is a number"):format(where, key))
				end
			end
		end
		check(Day, "Lighting.Day")
		H.expect(Day.Brightness > 0 and Day.ClockTime >= 0 and Day.ClockTime < 24, "a sane sun")
	end,
}
