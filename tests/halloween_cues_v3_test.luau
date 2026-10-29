--!strict
-- The Halloween 2026 cues' v3 effect rules (lane cuesA, designer 2026-10-29): the Pitchfork's
-- outer prongs stay solid while aiming and its two tip flames burn small and steady. Read from
-- the generated skin and piece rows.

local H = require("./harness")

local function maxOf(seq: any): number
	if type(seq) == "number" then
		return seq
	end
	local m = 0
	for _, key in seq do
		m = math.max(m, key[2])
	end
	return m
end

return {
	["the Pitchfork's outer prongs never fade while aiming"] = function()
		local CueSkins = H.require("CueSkins")
		local row = CueSkins.get("PitchforkCue")
		H.expect(row ~= nil and row.Body == "pitchfork", "the Pitchfork's body row")
		local piece = CueSkins.piece("pitchfork")
		H.expect(piece ~= nil and piece.Joints.Tines ~= nil, "the fork's Tines joint")
		for name, joint in piece.Joints do
			H.expect(
				joint.Aim == nil,
				"pitchfork joint " .. name .. " has Aim " .. tostring(joint.Aim)
			)
		end
	end,

	["the Pitchfork's tip flames are small, slow and locked to the points"] = function()
		local CueSkins = H.require("CueSkins")
		local row = CueSkins.get("PitchforkCue")
		local flames = 0
		for _, e in row.Aura.Emitters do
			if e.Name == "TipFlameA" or e.Name == "TipFlameB" then
				flames += 1
				H.expect(e.LockedToPart == true, e.Name .. ": locked to the prong's point")
				H.expect(e.Lifetime[1] >= 0.9, e.Name .. ": lives at least 0.9 s (no blink)")
				H.expect(maxOf(e.Size) <= 0.22, e.Name .. ": at most 0.22 studs")
				H.expect(e.Transparency[1][2] >= 0.9, e.Name .. ": fades in, never pops")
				-- about 7 overlapping a flame (Rate x Lifetime): one steady flame
				H.expect(
					e.Rate * e.Lifetime[1] >= 6,
					e.Name .. ": enough overlap for a steady flame"
				)
			end
		end
		H.expect(flames == 2, "two tip flames")
	end,
}
