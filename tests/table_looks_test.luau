--!strict
-- Checks the table looks in Config.TableModel: that every look dresses every mesh from a map
-- set that exists, that the numbers and ids are the shapes Studio accepts, that the image
-- budget holds, and that TableBuilder.lookFor picks a real look for every lounge table.
--
-- Looks are data rows plus uploaded maps, never code, so a typo here would otherwise only
-- show up as a bare or wrongly coloured table in Studio.

local H = require("./harness")

-- Enum.AlphaMode item names (Config cannot name Enum, so it stores strings).
local ALPHA_MODES = { Opaque = true, Overlay = true, TintMask = true, Transparency = true }
local MAP_KEYS = { "Color", "Normal", "Roughness", "Metalness" }

local function sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function isAssetId(id: string): boolean
	return id == "" or id:match("^rbxassetid://%d+$") ~= nil
end

return {
	["every look dresses every mesh, and only meshes"] = function()
		local TM = H.require("Config").TableModel
		H.expect(TM.Looks[TM.DefaultLook] ~= nil, "DefaultLook " .. TM.DefaultLook .. " is a look")
		for _, lookName in sortedKeys(TM.Looks) do
			local look = TM.Looks[lookName]
			for _, mesh in sortedKeys(TM.Meshes) do
				H.expect(
					look[mesh] ~= nil,
					("look %s leaves mesh %s undressed"):format(lookName, mesh)
				)
			end
			for _, mesh in sortedKeys(look) do
				H.expect(
					TM.Meshes[mesh] ~= nil,
					("look %s dresses %s, which is not a mesh"):format(lookName, mesh)
				)
			end
		end
	end,

	["every map set a look names exists"] = function()
		local TM = H.require("Config").TableModel
		for _, lookName in sortedKeys(TM.Looks) do
			local look = TM.Looks[lookName]
			for _, mesh in sortedKeys(look) do
				local maps = look[mesh].Maps
				H.expect(
					TM.Maps[maps] ~= nil,
					("look %s gives %s the map set %s, which Maps does not have"):format(
						lookName,
						mesh,
						maps
					)
				)
			end
		end
	end,

	["tints are three whole numbers from 0 to 255"] = function()
		local TM = H.require("Config").TableModel
		for _, lookName in sortedKeys(TM.Looks) do
			local look = TM.Looks[lookName]
			for _, mesh in sortedKeys(look) do
				local tint = look[mesh].Tint
				if tint then
					local label = ("%s.%s tint"):format(lookName, mesh)
					H.expect(#tint == 3, label .. " has three channels")
					for i = 1, 3 do
						local c = tint[i]
						H.expect(
							c == math.floor(c) and c >= 0 and c <= 255,
							("%s channel %d is %s"):format(label, i, tostring(c))
						)
					end
				end
			end
		end
	end,

	["mesh settings are ones Studio accepts"] = function()
		local TM = H.require("Config").TableModel
		for _, mesh in sortedKeys(TM.Meshes) do
			local spec = TM.Meshes[mesh]
			if spec.AlphaMode then
				H.expect(
					ALPHA_MODES[spec.AlphaMode] == true,
					mesh .. " AlphaMode " .. spec.AlphaMode
				)
			end
			H.expect(
				spec.Collision == nil or spec.CanCollide,
				mesh .. " names a Collision shape but does not collide"
			)
		end
		H.expect(TM.Meshes[TM.CapsMesh] ~= nil, "CapsMesh names a mesh")
		H.expect(TM.Meshes.LogoPlate ~= nil, "the LogoPlate is the orientation marker")
		H.expect(TM.Meshes.Cloth ~= nil and TM.Meshes.Body ~= nil, "Cloth and Body place the pivot")
		H.expect(TM.Meshes.Rails ~= nil, "Rails measure the footprint")
	end,

	["LookByTable names lounge tables and real looks"] = function()
		local Config = H.require("Config")
		local TM = Config.TableModel
		local ids: { [number]: boolean } = {}
		for _, row in Config.Lounge.Tables do
			ids[row.id] = true
		end
		for id, look in TM.LookByTable do
			H.expect(
				ids[id] == true,
				("LookByTable names table %s, which the lounge does not have"):format(tostring(id))
			)
			H.expect(
				TM.Looks[look] ~= nil,
				("LookByTable gives table %d the look %s, which does not exist"):format(id, look)
			)
		end
	end,

	["map ids are empty or rbxassetid, and the images fit the budget"] = function()
		local TM = H.require("Config").TableModel
		local unique: { [string]: boolean } = {}
		local count = 0
		for _, setName in sortedKeys(TM.Maps) do
			local set = TM.Maps[setName] :: { [string]: string? }
			H.expect(set.Color ~= nil, setName .. " has a Color map entry")
			for key, id in set do
				H.expect(
					table.find(MAP_KEYS, key) ~= nil,
					("%s has an unknown map %s"):format(setName, key)
				)
				H.expect(
					isAssetId(id :: string),
					("%s.%s is %q, not rbxassetid://digits"):format(setName, key, tostring(id))
				)
				if id ~= "" and not unique[id :: string] then
					unique[id :: string] = true
					count += 1
				end
			end
		end
		H.expect(
			count <= TM.ImageBudget,
			("the looks use %d unique images, over the budget of %d"):format(count, TM.ImageBudget)
		)
	end,

	["every lounge table gets a real look"] = function()
		local Config = H.require("Config")
		local TM = Config.TableModel
		local TableBuilder = H.require("TableBuilder")
		for id = 1, 12 do
			local look = TableBuilder.lookFor(id)
			H.expect(
				TM.Looks[look] ~= nil,
				("table %d wears %s, which is not a look"):format(id, look)
			)
			H.expect(
				look == (TM.LookByTable[id] or TM.DefaultLook),
				("table %d wears %s"):format(id, look)
			)
		end
	end,

	["a table naming a missing look falls back to the default"] = function()
		local TM = H.require("Config").TableModel
		local TableBuilder = H.require("TableBuilder")
		-- Config is one shared table; restore it whatever happens.
		local before = TM.LookByTable[99]
		TM.LookByTable[99] = "NoSuchLook"
		local ok, look = pcall(TableBuilder.lookFor, 99)
		TM.LookByTable[99] = before
		H.expect(ok, tostring(look))
		H.expect(look == TM.DefaultLook, "fell back to " .. tostring(look))
	end,
}
