--!strict
-- Checks Config.Lounge.Tables against the Blender package's own Markers.json.
--
-- Sixty numbers copied by hand from a delivery file is a bug farm, and a wrong one would
-- put a table through a wall or a pillar with no test to catch it. The rule that every
-- tunable lives in Config stands; this test is what makes hand-copying them safe.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local H = require("./harness")

local MARKERS = "assets/lounge/Markers.json"

type Marker = {
	name: string,
	table_number: number,
	position: { number },
	rotation_y_degrees: number,
	cloth_height_above_floor: number,
}

local function markers(): { Marker }
	local raw = serde.decode("json", fs.readFile(MARKERS)) :: any
	return raw.tables
end

return {
	["every lounge table matches Markers.json"] = function()
		local Config = H.require("Config")
		local rows = Config.Lounge.Tables
		local found = markers()
		H.expect(
			#rows == #found,
			("Config has %d tables, Markers.json has %d"):format(#rows, #found)
		)
		-- Index the config rows by id so the two files may list them in any order.
		local byId: { [number]: any } = {}
		for _, row in rows do
			H.expect(byId[row.id] == nil, ("duplicate table id %d in Config"):format(row.id))
			byId[row.id] = row
		end
		for _, m in found do
			local row = byId[m.table_number]
			H.expect(row ~= nil, ("Config is missing table %d"):format(m.table_number))
			local label = m.name
			H.near(row.X, m.position[1], 1e-4, label .. " X")
			H.near(row.Y, m.position[2], 1e-4, label .. " Y")
			H.near(row.Z, m.position[3], 1e-4, label .. " Z")
			H.near(row.YawDegrees, m.rotation_y_degrees, 1e-4, label .. " yaw")
		end
	end,

	["the cloth height in Config is the one the package built to"] = function()
		local Config = H.require("Config")
		-- Placement.toWorld adds Table.SurfaceHeightStuds on top of the floor, so if these
		-- two ever drift the balls float above or sink into every table in the lounge.
		for _, m in markers() do
			H.near(
				Config.Table.SurfaceHeightStuds,
				m.cloth_height_above_floor,
				1e-4,
				m.name .. " cloth height"
			)
		end
	end,

	["every pendant sits over its own table at the height Markers records"] = function()
		local Config = H.require("Config")
		local raw = serde.decode("json", fs.readFile(MARKERS)) :: any
		local byTable: { [number]: any } = {}
		for _, row in Config.Lounge.Tables do
			byTable[row.id] = row
		end
		H.expect(#raw.pendants == 12, "twelve pendants")
		for _, p in raw.pendants do
			local id = tonumber((p.table :: string):match("%d+"))
			local row = byTable[id :: number]
			H.expect(row ~= nil, ("pendant %s names no table"):format(p.name))
			-- Config stores one height above the tier floor rather than twelve positions,
			-- so this is what proves the shortcut is legitimate.
			H.near(row.X, p.position[1], 1e-4, p.name .. " X")
			H.near(row.Z, p.position[3], 1e-4, p.name .. " Z")
			H.near(
				row.Y + Config.Lounge.Pendant.HeightAboveFloor,
				p.position[2],
				1e-4,
				p.name .. " height above its tier"
			)
		end
	end,

	["the pendant light settings are the ones the package suggests"] = function()
		local Config = H.require("Config")
		local raw = serde.decode("json", fs.readFile(MARKERS)) :: any
		local want = raw.pendants[1].suggested_roblox_light
		local got = Config.Lounge.Pendant
		H.near(got.Brightness, want.Brightness, 1e-6, "brightness")
		H.near(got.RangeStuds, want.Range, 1e-6, "range")
		H.near(got.AngleDegrees, want.Angle, 1e-6, "angle")
		for i = 1, 3 do
			H.near(got.Color[i], want.Color[i], 1e-6, "colour channel " .. i)
		end
		-- Not a preference: twelve shadow-casting lights is the most expensive thing this
		-- scene could hold, and STATUS.md carried it as a debt from the single-table build.
		H.expect(got.Shadows == false, "pendants must never cast shadows")
		H.expect(want.Shadows == false, "the package agrees")
	end,

	["the spawn is where the package put it"] = function()
		local Config = H.require("Config")
		local raw = serde.decode("json", fs.readFile(MARKERS)) :: any
		H.near(Config.Lounge.Spawn.X, raw.spawn.position[1], 1e-4, "spawn X")
		H.near(Config.Lounge.Spawn.Y, raw.spawn.position[2], 1e-4, "spawn Y")
		H.near(Config.Lounge.Spawn.Z, raw.spawn.position[3], 1e-4, "spawn Z")
	end,

	["the lounge stands on three tiers of four"] = function()
		local Config = H.require("Config")
		local perTier: { [number]: number } = {}
		for _, row in Config.Lounge.Tables do
			perTier[row.Y] = (perTier[row.Y] or 0) + 1
		end
		local tiers = 0
		for _, count in perTier do
			tiers += 1
			H.expect(count == 4, "every tier holds four tables")
		end
		H.expect(tiers == 3, "there are three tiers")
	end,
}
