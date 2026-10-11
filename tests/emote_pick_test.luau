--!strict
-- EmotePick: the emote wheel's empty slots get the owned emotes (designer, 2026-10-11:
-- Roblox's wheel says "disabled" with no emote in a slot).

local H = require("./harness")

local function load()
	return H.require("EmotePick"), H.require("Config")
end

return {
	["empty slots get the owned emotes in name order, one a slot"] = function()
		local P = load()
		local out = P.fill({ "Tilt", "Hello", "Shrug" }, 0, 8)
		H.expect(out ~= nil and #out == 3, "three")
		local o = out :: any
		H.expect(o[1].Slot == 1 and o[1].Name == "Hello", "Hello first")
		H.expect(o[2].Slot == 2 and o[2].Name == "Shrug", "then Shrug")
		H.expect(o[3].Slot == 3 and o[3].Name == "Tilt", "then Tilt")
	end,

	["never more than the wheel's slots"] = function()
		local P = load()
		local owned = {}
		for i = 1, 12 do
			table.insert(owned, ("Emote%02d"):format(i))
		end
		local out = P.fill(owned, 0, 8) :: any
		H.expect(#out == 8 and out[8].Slot == 8 and out[8].Name == "Emote08", "eight")
	end,

	["a player's own slots are kept, and no emotes means nothing to do"] = function()
		local P = load()
		H.expect(P.fill({ "Hello" }, 1, 8) == nil, "already chose")
		H.expect(P.fill({}, 0, 8) == nil, "owns none")
	end,

	["it is on for the live game, the wheel's eight slots"] = function()
		local _, Config = load()
		H.expect(Config.Emotes.FillEmptySlots == true and Config.Emotes.Slots == 8, "on, 8")
	end,
}
