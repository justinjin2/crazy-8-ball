--!strict
-- The Halloween event cards' live 2D effects (HwCardFxMath, Config.UI.Halloween.CardFx;
-- designer 2026-10-29): every event cue has them, each layer finds its art in the cue's
-- generated skin row (or its own fallback), the sprites stay on the picture, see-through values
-- and flipbook frames stay in range, nothing is random, the Pitchfork's flames pulse smoothly
-- (no frame stepping), and the ladder climbs: the Pitchfork calmest, the Sword richest.

local H = require("./harness")

local function load()
	return H.require("HwCardFxMath"), H.require("Config"), H.require("CueSkins")
end

local EVENT_CUES = { "PitchforkCue", "WitchBroomCue", "JackOLanternCue", "HalloweenSwordCue" }
local KINDS = { Pulse = true, Rise = true, Twinkle = true, Glow = true }

local function total(row: any, low: boolean, Math: any): number
	local n = 0
	for _, layer in row.Layers do
		n += Math.count(layer, low)
	end
	return n
end

return {
	["every event cue has its effects, each layer its art"] = function()
		local Math, Config, CueSkins = load()
		local cues = Config.UI.Halloween.CardFx.Cues :: any
		local Catalog = H.require("Progression.Catalog")
		for _, id in EVENT_CUES do
			local row = cues[id]
			H.expect(type(row) == "table", id .. " has a CardFx row")
			H.expect(#row.Axis == 2, id .. ": the axis is two points")
			local skin = CueSkins.get(id)
			for i, layer in row.Layers do
				H.expect(KINDS[layer.Kind] == true, ("%s layer %d: a known kind"):format(id, i))
				local texture, grid = Math.resolve(skin, layer)
				H.expect(
					string.sub(texture, 1, 13) == "rbxassetid://",
					("%s layer %d: a texture"):format(id, i)
				)
				H.expect(grid >= 1 and grid <= 8, ("%s layer %d: a grid"):format(id, i))
				H.expect(
					(layer.Low or 0) <= (layer.Count or 0),
					("%s layer %d: Lower effects shows no more"):format(id, i)
				)
			end
		end
		for id in cues do
			local cue = Catalog.get(id)
			H.expect(cue ~= nil and cue.Event == "Halloween2026", id .. " is a Halloween 2026 cue")
		end
	end,

	["a layer takes its texture from the skin row, else its own"] = function()
		local Math = load()
		local skin = {
			Aura = {
				Emitters = {
					{ Name = "Glints", Texture = "rbxassetid://1" },
					{ Name = "Flames", Texture = "rbxassetid://2", FlipbookLayout = "Grid4x4" },
				},
			},
			TrailEmitters = {
				{ Name = "Trail", Texture = "rbxassetid://3", FlipbookLayout = "Grid8x8" },
			},
			Pocket = { Layers = { { Name = "Column", Texture = "rbxassetid://4" } } },
		}
		local texture, grid, found = Math.resolve(skin, { Emitter = { "Nope", "Flames" } })
		H.expect(texture == "rbxassetid://2" and grid == 4 and found, "the first name found wins")
		texture, grid = Math.resolve(skin, { Emitter = { "Trail" } })
		H.expect(texture == "rbxassetid://3" and grid == 8, "a trail emitter")
		texture = Math.resolve(skin, { Emitter = { "Column" } })
		H.expect(texture == "rbxassetid://4", "a finisher layer")
		texture, grid, found =
			Math.resolve(skin, { Emitter = { "Gone" }, Texture = "rbxassetid://9", Grid = 2 })
		H.expect(texture == "rbxassetid://9" and grid == 2 and not found, "else its own")
		texture, grid = Math.resolve(nil, { Texture = "rbxassetid://9" })
		H.expect(texture == "rbxassetid://9" and grid == 1, "no skin row: its own")
		H.expect(Math.gridOf("Grid4x4") == 4 and Math.gridOf("Grid2x2") == 2, "grids")
		H.expect(Math.gridOf(nil) == 1 and Math.gridOf("None") == 1, "no flipbook")
		local col, row = Math.cell(6, 4)
		H.expect(col == 2 and row == 1, "frame 6 of a 4 x 4 sheet: column 2, row 1")
	end,

	["the sprites stay on the picture and in range, the same every time"] = function()
		local Math, Config = load()
		local cues = Config.UI.Halloween.CardFx.Cues :: any
		for _, id in EVENT_CUES do
			local row = cues[id]
			for which, layer in row.Layers do
				local grid = layer.Grid or 1
				local tints = if layer.Tints then #layer.Tints else 1
				for index = 1, layer.Count do
					for step = 0, 600 do
						local t = step / 30
						local s = Math.sprite(layer, which, index, t, row.Axis, 12345, grid)
						local again = Math.sprite(layer, which, index, t, row.Axis, 12345, grid)
						local where = ("%s layer %d sprite %d at %.2f s"):format(
							id,
							which,
							index,
							t
						)
						H.expect(s.x == again.x and s.y == again.y, where .. ": deterministic")
						H.expect(
							s.x >= -0.08 and s.x <= 1.08,
							where .. ": x on the picture " .. s.x
						)
						H.expect(
							s.y >= -0.08 and s.y <= 1.08,
							where .. ": y on the picture " .. s.y
						)
						H.expect(
							s.w >= 0 and s.w <= 1 and s.h >= 0 and s.h <= 0.5,
							where .. ": size"
						)
						H.expect(
							s.transparency >= 0 and s.transparency <= 1,
							where .. ": transparency " .. s.transparency
						)
						H.expect(s.frame >= 0 and s.frame < grid * grid, where .. ": frame")
						H.expect(s.tint >= 1 and s.tint <= math.max(1, tints), where .. ": tint")
					end
				end
			end
		end
	end,

	["the Pitchfork's flames pulse smoothly on their prongs"] = function()
		local Math, Config = load()
		local row = (Config.UI.Halloween.CardFx.Cues :: any).PitchforkCue
		local flames = row.Layers[1]
		H.expect(flames.Kind == "Pulse", "its flames are a pulse")
		local first = Math.sprite(flames, 1, 1, 0, row.Axis, 7, flames.Grid)
		local before = first
		for step = 1, 600 do
			local s = Math.sprite(flames, 1, 1, step / 60, row.Axis, 7, flames.Grid)
			H.expect(s.frame == first.frame, "one still frame: no stepping")
			H.expect(s.x == first.x and s.y == first.y, "it stays on its prong")
			H.expect(math.abs(s.w - before.w) < 0.004, "its size changes smoothly")
			H.expect(math.abs(s.transparency - before.transparency) < 0.03, "and its glow")
			before = s
		end
	end,

	["the ladder climbs: the Pitchfork calmest, the Sword richest"] = function()
		local Math, Config = load()
		local cues = Config.UI.Halloween.CardFx.Cues :: any
		local last = -1
		for _, id in EVENT_CUES do
			local n = total(cues[id], false, Math)
			H.expect(n > last, ("%s has more sprites than the cue before (%d)"):format(id, n))
			H.expect(n <= 12, id .. " stays within the budget of 12 sprites")
			H.expect(
				total(cues[id], true, Math) <= math.ceil(n / 2),
				id .. ": Lower effects halves it"
			)
			last = n
		end
	end,
}
