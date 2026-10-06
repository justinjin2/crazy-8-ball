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
}
