--!strict
-- The Halloween 2026 cues' v3 effect rules (lane cuesA, designer 2026-10-29): the Pitchfork's
-- outer prongs stay solid while aiming and its two tip flames burn small and steady; the
-- Jack-o'-Lantern's finisher laugh is quiet and heard only near the table, its rising head
-- has no circling mini jacks; the Witch's Broom's finisher has nothing ring-like (the Beta
-- cue's look: ring decals, a flat swirl disc, the gust's ribbons, rings turning round the
-- pocket) and its witch flies alone (no moon) on a 64-frame flipbook; its bristle head is short
-- enough not to stab the floor from a normal character's back. Read from the generated skin and
-- piece rows.

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

	["the Broom's finisher has nothing ring-like"] = function()
		local CueSkins = H.require("CueSkins")
		local row = CueSkins.get("WitchBroomCue")
		local pocket = row.Pocket
		H.expect(#(pocket.Rings or {}) == 0, "no ring decals")
		H.expect(pocket.KeepRibbons == false, "no shared gust ribbons")
		for _, layer in pocket.Layers do
			H.expect(
				layer.Orientation ~= "VelocityPerpendicular",
				layer.Name .. ": a flat disc or ring layer"
			)
		end
		local piece = CueSkins.piece(pocket.Piece.Piece)
		H.expect(piece ~= nil and #piece.Parts > 0, "the finisher piece " .. pocket.Piece.Piece)
		for name, joint in piece.Joints do
			for _, m in joint.Motion or {} do
				-- a spin about the pocket's up axis (Z in the piece frame) turns a ring round it
				local vertical = m.Kind == "Spin" and m.Axis and m.Axis[3] ~= 0
				H.expect(not vertical, name .. ": spins round the pocket like a ring")
			end
		end
	end,

	["the Broom's witch flies alone on a smooth flipbook"] = function()
		local CueSkins = H.require("CueSkins")
		local row = CueSkins.get("WitchBroomCue")
		local witch = nil
		for _, layer in row.Pocket.Layers do
			H.expect(layer.Name ~= "WitchMoon", "the witch-and-moon layer is gone")
			if layer.Name == "Witch" then
				witch = layer
			end
		end
		H.expect(witch ~= nil, "the witch layer")
		H.expect(witch.FlipbookLayout == "Grid8x8", "64 frames")
		H.expect(witch.FlipbookMode == "OneShot", "one fly-by a burst")
		H.expect(witch.Lifetime[2] <= 1.3, "a fast fly-by (at most 1.3 s)")
		H.expect(
			type(witch.Texture) == "string" and witch.Texture:sub(1, 13) == "rbxassetid://",
			"an uploaded flipbook"
		)
	end,

	["the Broom's bristle head ends at most 1.2 studs past the butt"] = function()
		local CueSkins = H.require("CueSkins")
		local piece = CueSkins.piece(CueSkins.get("WitchBroomCue").Body)
		-- the cue MeshPart frame: the butt at z = -3.5 (7 studs long, centred)
		local far = 0
		for _, part in piece.Parts do
			if part.Joint == "Bristles" then
				far = math.max(far, -3.5 - (part.Offset[3] - part.Size[3] / 2))
			end
		end
		H.expect(far > 0.8, ("the bristles reach %.2f past the butt (a real head)"):format(far))
		-- 1.48 clipped into the ground on a normal character's back (designer 2026-10-29)
		H.expect(far <= 1.2, ("the bristles reach %.2f past the butt (at most 1.2)"):format(far))
	end,
}
