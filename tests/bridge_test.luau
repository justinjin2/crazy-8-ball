--!strict
-- Checks Config.Bridge against the bridge package's own Parameters.json (assets/bridge).
--
-- ShooterStance picks the notch and holds the shaft from Config.Bridge's numbers, and
-- BridgeBuilder straightens the imported mesh and builds its parts stand-in from them. If
-- they drift from the mesh Blender actually built, the cue floats over the notch or sinks
-- through the head with nothing on screen saying why. This test is what makes copying them by
-- hand safe; after a rebuild of the package, it names the key to update.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local H = require("./harness")

-- Relative to the repo root; tools/test.sh cds there before running.
local PARAMETERS = "assets/bridge/Parameters.json"

local function load(): any
	return serde.decode("json", fs.readFile(PARAMETERS)) :: any
end

local function sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- The same shape, numbers within 1e-6 and strings exactly; arrays in the same order.
local function same(config: any, json: any, path: string)
	if type(json) == "number" then
		H.expect(type(config) == "number", path .. " is not a number in Config")
		H.near(config, json, 1e-6, path)
	elseif type(json) == "table" then
		H.expect(type(config) == "table", path .. " is missing from Config")
		if #json > 0 then
			H.expect(
				#config == #json,
				("%s has %d entries, Parameters.json %d"):format(path, #config, #json)
			)
			for i, value in json do
				same(config[i], value, ("%s[%d]"):format(path, i))
			end
		else
			for _, key in sortedKeys(json) do
				same(config[key], json[key], path .. "." .. key)
			end
		end
	else
		H.expect(
			config == json,
			("%s is %s, Parameters.json says %s"):format(path, tostring(config), tostring(json))
		)
	end
end

-- Config.Bridge.Fallback's keys and the "parameters" they copy.
local FALLBACK = {
	HeadThicknessStuds = "head_thickness",
	NotchRadiusStuds = "notch_radius",
	NotchDepthStuds = "notch_depth",
	NotchRestAboveBottomStuds = "notch_rest_above_bottom",
	LobeCrownStuds = "lobe_crown",
	ShaftHeadDiameterStuds = "shaft_head_diameter",
	CollarDiameterStuds = "collar_diameter",
	CollarFromStuds = "collar_z0",
	CollarToStuds = "collar_z1",
	RingExtraDiameterStuds = "ring_extra_diameter",
	RingLengthStuds = "ring_length",
	RingPosition = "ring_position",
	CapDiameterStuds = "cap_diameter",
	CapFromStuds = "cap_z0",
	CapToStuds = "cap_z1",
}

return {
	["Config.Bridge matches the model the package built"] = function()
		local B = H.require("Config").Bridge
		local json = load()
		-- Every number the game reads, under the same names (roblox_local), and the two the
		-- shaft's clearance and grip need from the raw parameters.
		for _, key in sortedKeys(json.roblox_local) do
			same(B[key], json.roblox_local[key], "Config.Bridge." .. key)
		end
		local p = json.parameters
		H.near(B.ShaftButtRadiusStuds, p.shaft_butt_diameter / 2, 1e-6, "ShaftButtRadiusStuds")
		H.near(B.ShaftStartStuds, p.shaft_z0, 1e-6, "ShaftStartStuds")
		H.near(B.ShaftLengthStuds, p.shaft_length, 1e-6, "ShaftLengthStuds")
		H.near(B.PivotHeightStuds, p.pivot_height, 1e-6, "PivotHeightStuds")
		H.near(B.HeadWidthStuds, p.head_half_width * 2, 1e-6, "HeadWidthStuds")
	end,

	["the parts stand-in has the mesh's dimensions"] = function()
		local F = H.require("Config").Bridge.Fallback
		local p = load().parameters
		for _, key in sortedKeys(FALLBACK) do
			local name = FALLBACK[key]
			H.expect(p[name] ~= nil, "Parameters.json has no parameters." .. name)
			H.near(F[key], p[name], 1e-6, "Config.Bridge.Fallback." .. key)
		end
		for _, key in sortedKeys(F) do
			H.expect(
				FALLBACK[key] ~= nil,
				"Config.Bridge.Fallback." .. key .. " is not checked here"
			)
		end
	end,

	["the notches climb Low, Mid, High, in that order"] = function()
		local B = H.require("Config").Bridge
		local derived = load().derived.NotchHeightsAboveCloth
		local names = {}
		local last = -math.huge
		for i, notch in B.Notches do
			names[i] = notch.Name
			local height = B.PivotHeightStuds + notch.Y
			H.expect(height > last, notch.Name .. " is not above the notch before it")
			H.near(height, derived[notch.Name], 1e-6, notch.Name .. " height above the cloth")
			last = height
		end
		H.expect(
			table.concat(names, ",") == "Low,Mid,High",
			"notch order " .. table.concat(names, ",")
		)
		-- ...and each stands on the cloth: the notch's floor above the head's base.
		local F = B.Fallback
		for _, notch in B.Notches do
			H.expect(
				notch.Y - F.NotchRestAboveBottomStuds > -B.PivotHeightStuds,
				notch.Name .. "'s floor is below the head's base"
			)
		end
	end,

	-- CueShape.radiusAt past the butt is the wider of the butt and the extension; CueClearance
	-- keeps that envelope clear of the rails, so no extension fitting may stick out of it.
	["the cue extension's ring and cap stay inside the clearance envelope"] = function()
		local C = H.require("Config").Cue
		local CueShape = H.require("CueShape")
		local ring = C.ExtensionDiameterStuds * C.Extension.RingDiameterScale / 2
		local L = C.CueLengthStuds
		H.expect(
			ring <= CueShape.radiusAt(L + 1e-6) + 1e-12,
			"the extension ring is wider than the cue"
		)
		H.expect(C.Extension.LengthStepStuds > 0, "a positive extension step")
	end,
}
