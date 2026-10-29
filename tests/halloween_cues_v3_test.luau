--!strict
-- The Halloween 2026 cues' v3 effect rules (lane cuesA, designer 2026-10-29): the Pitchfork's
-- outer prongs stay solid while aiming and its two tip flames burn small and steady; the
-- Jack-o'-Lantern's finisher laugh is quiet and heard only near the table, its rising head
-- has no circling mini jacks. Read from the generated skin and piece rows.

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

	["the Jack's laugh is quiet and only near the table"] = function()
		local CueSkins = H.require("CueSkins")
		local row = CueSkins.get("JackOLanternCue")
		local sound = row.Pocket and row.Pocket.Sound
		H.expect(sound ~= nil and type(sound.Asset) == "string", "the laugh row")
		-- at least 55% quieter than the 0.6 it shipped with
		H.expect(sound.Volume <= 0.6 * 0.45 + 1e-9, "laugh volume " .. tostring(sound.Volume))
		H.expect(
			type(sound.RollOffMaxStuds) == "number" and sound.RollOffMaxStuds <= 25,
			"silent from 25 studs"
		)
		H.expect(
			type(sound.RollOffMinStuds) == "number"
				and sound.RollOffMinStuds < sound.RollOffMaxStuds,
			"a roll-off range"
		)
	end,

	["the Jack's rising head has no circling mini jacks"] = function()
		local CueSkins = H.require("CueSkins")
		local row = CueSkins.get("JackOLanternCue")
		local pid = row.Pocket.Piece.Piece
		local piece = CueSkins.piece(pid)
		H.expect(piece ~= nil, "the rise piece " .. tostring(pid))
		H.expect(piece.Joints.Orbit == nil, "no Orbit joint")
		for _, part in piece.Parts do
			H.expect(part.Joint ~= "Orbit", "part " .. part.Name .. " on the Orbit")
		end
		local burst = 0
		for _, layer in row.Pocket.Layers do
			burst += layer.Burst or 0
		end
		H.expect(burst <= 60, ("finisher bursts %d particles (at most 60)"):format(burst))
	end,
}
