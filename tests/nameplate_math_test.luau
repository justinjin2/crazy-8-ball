--!strict
-- NameplateMath: the flag after a player's name never overlaps it, for any username's length
-- (3 to 20 characters, the narrowest to the widest letters), and stays close to it.

local H = require("./harness")

local function load()
	return H.require("NameplateMath"), H.require("Config").UI.Progress.Nameplate
end

-- A name's width over its height in Fredoka One, from "iii" (narrowest, 3 letters) to 20
-- W's (widest, 20 letters), with a flag emoji about 1.3 times as wide as tall.
local ASPECTS = { 0.6, 1, 2, 4.5, 8, 12, 16, 19 }
local FLAG = 1.3

return {
	the_flag_starts_after_the_name_box_for_every_length = function()
		local M, P = load()
		for _, aspect in ASPECTS do
			local r = M.row(aspect, FLAG, P)
			-- TextScaled letters never pass their box, so the flag clears them whatever the font.
			H.expect(
				r.flagX >= r.nameX + r.nameW + P.FlagGapShare - 1e-9,
				"the flag clears the name at " .. aspect
			)
			H.expect(r.units >= r.flagX + r.flagW - 1e-9, "the row holds the flag at " .. aspect)
			H.expect(
				r.nameW >= aspect * P.NameShare,
				"the box holds the measured words at " .. aspect
			)
		end
	end,
	the_flag_stays_close_to_a_long_name = function()
		local M, P = load()
		local r = M.row(19, FLAG, P)
		local lettersEnd = r.nameX + 19 * P.NameShare
		H.expect(r.flagX - lettersEnd <= 0.35, "a 20-letter name keeps its flag close")
	end,
	no_flag_means_no_room_for_one = function()
		local M, P = load()
		local r = M.row(4.5, 0, P)
		H.expect(r.flagW == 0, "no flag box")
		H.expect(math.abs(r.units - (r.nameX + r.nameW)) < 1e-9, "the row ends with the name")
	end,
}
