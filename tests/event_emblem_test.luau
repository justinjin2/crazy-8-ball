--!strict
-- The event emblem (EventEmblem, Config.UI.EventEmblem; designer 2026-10-29): the four
-- Halloween 2026 cues wear the "Halloween 2026" badge, picked by their Catalog row's Event (no
-- code per cue); every other cue, an unknown id and nothing wear none.

local H = require("./harness")

return {
	["the Halloween 2026 cues wear the emblem, no other cue does"] = function()
		local Emblem = H.require("EventEmblem")
		local Config = H.require("Config")
		local Catalog = H.require("Progression.Catalog")
		local image = Config.UI.EventEmblem.Images.Halloween2026
		H.expect(string.sub(image, 1, 13) == "rbxassetid://", "the emblem has a picture")
		local count = 0
		for _, cue in Catalog.list() do
			local got = Emblem.image(cue.Id)
			if cue.Event == "Halloween2026" then
				count += 1
				H.expect(got == image, cue.Id .. " wears the Halloween 2026 emblem")
			else
				H.expect(got == nil, cue.Id .. " wears none")
			end
		end
		H.expect(count == 4, "four Halloween 2026 cues: " .. count)
		H.expect(Emblem.image("NoSuchCue") == nil, "an unknown cue: none")
		H.expect(Emblem.image(nil) == nil, "nothing: none")
	end,

	["the emblem keeps its picture's shape"] = function()
		local Emblem = H.require("EventEmblem")
		local w, h = Emblem.size(20)
		H.expect(w == 50 and h == 20, ("20 px tall is 50 x 20: %d x %d"):format(w, h))
		w, h = Emblem.size(0.2)
		H.expect(w >= 1 and h >= 1, "never smaller than a pixel")
	end,
}
