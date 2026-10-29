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

	["the emblem sits bottom right, just over the name, never wider than its room"] = function()
		local Emblem = H.require("EventEmblem")
		local x, y, w, h = Emblem.place(150, 137, 5, 2, 20)
		H.expect(w == 50 and h == 20, ("its shape kept: %d x %d"):format(w, h))
		H.expect(x == 95, "its right side 5 px in from the card's right edge: " .. x)
		H.expect(y == 115, "its foot 2 px over the name: " .. y)
		x, y, w, h = Emblem.place(100, 80, 5, 2, 30, 40)
		H.expect(
			w == 40 and h == 16,
			("too wide: shrunk to the room, its shape kept: %d x %d"):format(w, h)
		)
		H.expect(x == 55 and y == 62, ("still bottom right over the name: %d, %d"):format(x, y))
	end,

	["on a cue card it clears NEW, Equipped, the padlock and CLAIM!"] = function()
		-- InventoryCard's layout in card units (Config.UI.CueCard): the name's top over the bar
		-- (a long name wraps to two lines), the left pills, the padlock, the CLAIM! words.
		local Emblem = H.require("EventEmblem")
		local Config = H.require("Config")
		local CC = Config.UI.CueCard
		local L = CC.Layout
		local EU = Config.UI.EventEmblem.CardUnits
		local cardW, cardH = CC.Units[1], CC.Units[2]
		local barTop = cardH - L.BarUnits[3] - L.BarUnits[2]
		for lines = 1, 2 do
			local nameTop = barTop - L.NameGapUnits - L.NameUnits * L.NameLineShare * lines
			local x, y, w, h =
				Emblem.place(cardW, nameTop, EU[1], EU[2], EU[3], cardW - 2 * L.PillUnits[1])
			H.expect(x >= cardW / 2 and x + w <= cardW - EU[1] + 1, "on the right")
			H.expect(y + h <= nameTop, "over the name")
			H.expect(y >= L.SecondPillTopUnits + L.PillUnits[3], "under NEW and Equipped's rows")
			H.expect(y >= L.LockUnits[2] + L.LockUnits[3], "under the padlock")
			local claimBottom = cardH * CC.Locked.LockAt[2] + CC.Locked.ClaimUnits[2] / 2
			H.expect(
				y >= claimBottom,
				("under CLAIM! (%d lines: %.1f >= %.1f)"):format(lines, y, claimBottom)
			)
		end
	end,

	["the emblem keeps its picture's shape"] = function()
		local Emblem = H.require("EventEmblem")
		local w, h = Emblem.size(20)
		H.expect(w == 50 and h == 20, ("20 px tall is 50 x 20: %d x %d"):format(w, h))
		w, h = Emblem.size(0.2)
		H.expect(w >= 1 and h >= 1, "never smaller than a pixel")
	end,
}
