--!strict
-- The Halloween track (Halloween/Track; Config.Halloween.Track): PLAN's 11 steps, due steps for
-- a total and a given set, the next step.

local H = require("./harness")

local function load()
	return H.require("Halloween.Track"), H.require("Config").Halloween
end

return {
	["eleven steps, ascending, the cues where the designer put them (2026-10-29)"] = function()
		local Track = load()
		local steps = Track.steps()
		H.expect(#steps == 11, "eleven")
		local want = {
			{ 50, "Spins", 1 },
			{ 150, "Spins", 2 },
			{ 300, "Money", 2500 },
			{ 500, "Cue", "PitchforkCue" },
			{ 1000, "Spins", 2 },
			{ 1500, "Money", 5000 },
			{ 2000, "Cue", "WitchBroomCue" },
			{ 3000, "Spins", 3 },
			{ 4500, "Money", 10000 },
			{ 5500, "Spins", 5 },
			{ 7000, "Cue", "HalloweenSwordCue" },
		}
		for i, w in want do
			local step: any = steps[i]
			H.expect(step.At == w[1], "At " .. i)
			H.expect(Track.kind(step) == w[2] and step[w[2]] == w[3], "prize " .. i)
		end
	end,

	["due: every step reached and not given, in order"] = function()
		local Track = load()
		H.expect(#Track.due(49, {}) == 0, "none under 50")
		local due = Track.due(520, {})
		H.expect(#due == 4 and due[1] == 1 and due[4] == 4, "50, 150, 300, 500")
		due = Track.due(520, { ["1"] = true, ["3"] = true })
		H.expect(#due == 2 and due[1] == 2 and due[2] == 4, "a held cue stays due")
		H.expect(#Track.due(7000, {}) == 11, "all at 7,000")
	end,

	["next: the first step not reached"] = function()
		local Track = load()
		local i, step = Track.next(0)
		H.expect(i == 1 and step ~= nil and step.At == 50, "50 first")
		i = Track.next(6999)
		H.expect(i == 11, "the Broom")
		H.expect(Track.next(7000) == nil, "none past it")
	end,
}
