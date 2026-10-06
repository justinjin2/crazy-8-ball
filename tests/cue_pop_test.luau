--!strict
-- CueSkins.Pop: the pop pass rewrites a copy of a skin row (never the row), deepens colours
-- in every form, and puts a darker, wider, paint-drawn twin behind each aura beam and ribbon.

local H = require("./harness")

local function load()
	return H.require("CueSkins.Pop"), H.require("Config"), H.require("CueSkins")
end

return {
	["deepen raises saturation and lowers brightness, keeping the hue"] = function()
		local Pop = load()
		H.expect(Pop.deepen("#FFFFFF", 0.3, 0.5) == "#808080", "white has no hue: grey")
		H.expect(Pop.deepen("#FF0000", 0.3, 1) == "#FF0000", "a full red stays red")
		H.expect(Pop.deepen({ 128, 191, 255 }, 1, 1) == "#007EFF", "pale blue to full blue")
		local list = Pop.deepenAny({ { 0, "#FFFFFF" }, { 1, "#FF0000" } }, 0.5, 0.5)
		H.expect(list[1][1] == 0 and list[2][1] == 1, "a list keeps its times")
		H.expect(list[2][2] == "#800000", "and deepens each key")
		H.expect(list[1][2] == "#804040", "a grey key takes the list's hue")
	end,

	["thin scales opacity in numbers and curves"] = function()
		local Pop = load()
		H.near(Pop.thin(0, 0.5), 0.5, 1e-9)
		H.near(Pop.thin(1, 0.5), 1, 1e-9)
		local curve = Pop.thin({ { 0, 0.2, 0.1 } }, 0.5)
		H.near(curve[1][2], 0.6, 1e-9)
		H.expect(curve[1][3] == 0.1, "envelope kept")
	end,

	["applies follows the Ids list, and every cue when there is none"] = function()
		local Pop = load()
		H.expect(Pop.applies("A", { Ids = { "A" } }), "listed")
		H.expect(not Pop.applies("B", { Ids = { "A" } }), "not listed")
		H.expect(Pop.applies("B", {}), "no Ids: every cue")
		H.expect(not Pop.applies("A", nil), "no spec: none")
	end,

	["every skin pops without changing its row, each beam and ribbon backed"] = function()
		local Pop, Config, CueSkins = load()
		local spec = Config.CueSkins.Pop
		H.expect(spec ~= nil, "Config.CueSkins.Pop exists")
		for _, id in spec.Ids or {} do
			H.expect(CueSkins.has(id), "a cue on test is a skin: " .. id)
		end
		for _, id in CueSkins.ids() do
			local row = CueSkins.get(id)
			local before = #((row.Aura or {}).Beams or {})
			local orbiters = #((row.Aura or {}).Orbiters or {})
			local out = Pop.pop(row, spec)
			H.expect(out ~= row, id .. ": a copy")
			H.expect(#((row.Aura or {}).Beams or {}) == before, id .. ": the row's beams untouched")
			if row.Aura then
				H.expect(#(out.Aura.Beams or {}) == 2 * before, id .. ": a twin per beam")
				H.expect(#(out.Aura.Orbiters or {}) == 2 * orbiters, id .. ": a twin per ribbon")
				for _, b in out.Aura.Beams or {} do
					if b.Name and b.Name:match("Backing$") then
						H.expect(b.LightEmission == 0, id .. ": a backing is paint")
					end
				end
			end
		end
	end,

	["the outline is the cue's theme colour, with fallbacks"] = function()
		local Pop, Config, CueSkins = load()
		local spec = Config.CueSkins.Pop
		local themed = {
			Outline = {
				Color = "Theme",
				SaturationAdd = 0,
				Value = 1,
				MinSaturation = 0.3,
				Fallback = "#1B2033",
			},
		}
		local function outline(row: any): string
			return Pop.outline(row, themed)
		end
		H.expect(
			outline({ Style = { Trail = { Color = { 150, 215, 255 } } } }) == "#96D7FF",
			"a trail colour"
		)
		H.expect(outline({
			Aura = { Outline = "#FFFFFF" },
			Style = { Trail = { Color = { 255, 0, 0 } } },
		}) == "#FFFFFF", "the skin's own outline first, whatever it is")
		H.expect(outline({
			Style = {
				Trail = { Colors = { { 255, 240, 240 }, { 0, 200, 0 }, { 250, 250, 255 } } },
			},
		}) == "#00C800", "the most vivid of a trail's colours")
		H.expect(outline({
			Style = {
				Trail = { Color = { 255, 255, 255 } },
				Pocket = { Colors = { { 255, 122, 26 } } },
			},
		}) == "#FF7A1A", "a white trail: the pocket burst's colour")
		H.expect(
			outline({ Look = { Shaft = { 200, 200, 200 }, Cap = { 120, 14, 23 } } }) == "#780E17",
			"a plain cue's most vivid stick colour"
		)
		H.expect(
			outline({ Tier = "Rank", Look = { Shaft = { 200, 200, 200 } } }) == "#1B2033",
			"grey: the ink"
		)
		H.expect(
			Pop.outline({}, { Outline = { Color = "#ABCDEF" } }) == "#ABCDEF",
			"a fixed colour"
		)
		for _, id in CueSkins.ids() do
			local c = Pop.outline(CueSkins.get(id), spec)
			H.expect(type(c) == "string" and #c == 7, id .. ": an outline colour")
		end
	end,

	["Legendary and above get a moving palette: the cue's own row, else its colours"] = function()
		local Pop, Config, CueSkins = load()
		local spec = Config.CueSkins.Pop
		local G = spec.Outline.Gradient
		H.expect(Pop.palette({ Tier = "Rare" }, spec) == nil, "a Rare has none")
		local kitsune = Pop.palette(CueSkins.get("KitsuneCue"), spec)
		H.expect(kitsune ~= nil and #kitsune == #G.Palettes.KitsuneCue, "Kitsune: its own row")
		for id in G.Palettes do
			H.expect(CueSkins.has(id), "a Palettes row names a skin: " .. id)
		end
		local phoenix = Pop.palette(CueSkins.get("PhoenixCue"), spec)
		H.expect(phoenix ~= nil and #phoenix >= 2, "Phoenix: its own colours")
		local one = Pop.palette(
			{ Tier = "Legendary", Style = { Trail = { Color = { 212, 175, 55 } } } },
			spec
		)
		H.expect(one ~= nil and #one == 2, "one colour shines: it and a lighter copy")
		for _, id in CueSkins.ids() do
			local row = CueSkins.get(id)
			if G.Tiers[row.Tier] then
				local p = Pop.palette(row, spec)
				H.expect(
					p ~= nil and #p >= 2 and #p <= math.max(G.MaxColors, 3),
					id .. ": a palette"
				)
			end
		end
	end,

	["sample loops through the palette"] = function()
		local Pop = load()
		local p = { "#FF0000", "#0000FF" }
		local r, _, b = Pop.sample(p, 0)
		H.near(r, 1, 1e-9)
		H.near(b, 0, 1e-9)
		r, _, b = Pop.sample(p, 0.25)
		H.near(r, 0.5, 1e-9, "halfway red to blue")
		H.near(b, 0.5, 1e-9)
		r = Pop.sample(p, 1)
		H.near(r, 1, 1e-9, "a whole loop is back at the start")
		r = Pop.sample(p, -0.5)
		H.near(r, 0, 1e-9, "negative phases wrap")
	end,
}
