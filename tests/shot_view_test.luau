--!strict
-- Settings' "Camera after a shot" as three views in two saved switches (ShotView; designer,
-- 2026-10-25): the row cycles TOP, VERTICAL, PLAYER, and the switches sent for a view never
-- pass through a third view on the way.

local H = require("./harness")

local function load()
	return H.require("ShotView")
end

return {
	["two switches name one view, PLAYER first"] = function()
		local V = load()
		H.expect(V.of(false, false) == "Top", "neither: TOP")
		H.expect(V.of(false, true) == "Vertical", "tall: VERTICAL")
		H.expect(V.of(true, false) == "Player", "player: PLAYER")
		H.expect(V.of(true, true) == "Player", "both: PLAYER wins")
	end,

	["a press cycles TOP, VERTICAL, PLAYER, then TOP"] = function()
		local V = load()
		H.expect(V.next("Top") == "Vertical", "TOP to VERTICAL")
		H.expect(V.next("Vertical") == "Player", "VERTICAL to PLAYER")
		H.expect(V.next("Player") == "Top", "PLAYER back to TOP")
	end,

	["the switches for a view land on it, showing only the old or the new view between"] = function()
		local V = load()
		for _, from in V.Order do
			for _, to in V.Order do
				local state = {
					ShotCam = from == "Player",
					ShotCamTall = from == "Vertical",
				}
				for _, step in V.switches(to) do
					state[step.key] = step.value
					local shown = V.of(state.ShotCam, state.ShotCamTall)
					H.expect(
						shown == from or shown == to,
						from .. " to " .. to .. " showed " .. shown
					)
				end
				H.expect(V.of(state.ShotCam, state.ShotCamTall) == to, from .. " lands on " .. to)
			end
		end
	end,
}
