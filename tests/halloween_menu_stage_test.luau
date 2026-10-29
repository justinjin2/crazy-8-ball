--!strict
-- Every piece the Halloween event menu registers on its Stage (EventMenu.luau's
-- stage:add("Id", ...)) must be named in its open schedule (Config.UI.Halloween.Open.Steps).
-- Stage.close fades every registered piece out and Stage.play brings back only the scheduled
-- ones, so a piece left out shows on the first open and stays invisible after the first close
-- (found 2026-10-29: the Pumpkin King's drop pill, HwKingDrop).

local fs = require("@lune/fs")
local H = require("./harness")

return {
	["every piece the event menu registers is in its open schedule"] = function()
		local Config = H.require("Config")
		local scheduled: { [string]: boolean } = {}
		for _, step in Config.UI.Halloween.Open.Steps do
			for _, id in step.Ids do
				scheduled[id] = true
			end
		end
		local source = fs.readFile("src/client/Halloween/EventMenu.luau")
		local count = 0
		for id in source:gmatch('stage:add%("([%w_]+)"%s*,') do
			count += 1
			H.expect(
				scheduled[id] == true,
				id .. " is registered but not in Config.UI.Halloween.Open.Steps"
			)
		end
		H.expect(count > 0, "found the menu's stage:add calls")
	end,
}
