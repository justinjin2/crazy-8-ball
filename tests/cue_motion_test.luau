--!strict
-- CueSkins.Motion against the Blender reference: joint transforms from CuePieces.joint_matrix
-- (tests/cue_motion_fixture.json, written by tools/cue_motion_fixture.py) for pieces with
-- every motion kind (Hinge with sine/snap/pulse waves, Spin, Bob with a saw wave, Glitch, the
-- dragon's Path), at
-- several times, in the Roblox cue frame. piece.json rounds pivots to 0.1 mm, hence 1e-3.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local H = require("./harness")

local TOLERANCE = 1e-3

return {
	["every joint of every fixture piece matches the Blender reference"] = function()
		local Motion = H.require("CueSkins.Motion")
		local rows = serde.decode("json", fs.readFile("tests/cue_motion_fixture.json"))
		local rigs: { [string]: any } = {}
		local poses: { [string]: any } = {}
		local checked = 0
		for _, row in rows do
			local rig = rigs[row.piece]
			if rig == nil then
				rig = Motion.rig(H.require("CueSkins.Pieces." .. row.piece))
				rigs[row.piece] = rig
			end
			local key = row.piece .. "@" .. tostring(row.t)
			local pose = poses[key]
			if pose == nil then
				pose = Motion.pose(rig, row.t)
				poses[key] = pose
			end
			local got = pose[row.joint]
			H.expect(got ~= nil, key .. ": no joint " .. row.joint)
			for i = 1, 9 do
				H.near(got.R[i], row.R[i], TOLERANCE, ("%s %s R[%d]"):format(key, row.joint, i))
			end
			for i = 1, 3 do
				H.near(got.P[i], row.P[i], TOLERANCE, ("%s %s P[%d]"):format(key, row.joint, i))
			end
			checked += 1
		end
		H.expect(checked >= 300, ("only %d joints checked"):format(checked))
	end,

	["waves: piece shapes and effect shapes"] = function()
		local Motion = H.require("CueSkins.Motion")
		H.near(Motion.pieceWave(0.5, { Period = 2 }), 1, 1e-9, "sine peak at a quarter period")
		H.near(Motion.pieceWave(0.5, { Period = 2, Shape = "snap" }), 1, 1e-9, "snap peak")
		H.near(
			Motion.pieceWave(0.25, { Period = 2, Shape = "snap" }),
			math.sqrt(0.5) ^ 0.35,
			1e-9,
			"snap"
		)
		H.near(Motion.pieceWave(0.3, { Period = 2, Shape = "pulse" }), 1, 1e-9, "pulse peak")
		H.near(Motion.pieceWave(1.2, { Period = 2, Shape = "pulse" }), 0, 1e-9, "pulse rest")
		H.near(Motion.pieceWave(0, { Period = 2, Shape = "saw" }), -1, 1e-9, "saw starts at -1")
		H.near(Motion.pieceWave(1.5, { Period = 2, Shape = "saw" }), 0.5, 1e-9, "saw climbs")
		H.near(Motion.pieceWave(1.999, { Period = 2, Shape = "saw" }), 0.999, 1e-9, "saw top")
		H.near(Motion.pieceWave(2, { Period = 2, Shape = "saw" }), -1, 1e-9, "saw snaps back")
		local g = { Period = 4, Seconds = 0.3, Amp = 0.1, Steps = 3, Phase = 1 }
		H.near(Motion.glitchOffset(0.5, g), 0, 1e-9, "glitch rests outside its window")
		H.near(Motion.glitchOffset(1.05, g), 0.1, 1e-9, "glitch first step +")
		H.near(Motion.glitchOffset(1.15, g), -0.1, 1e-9, "glitch second step -")
		H.near(Motion.glitchOffset(5.25, g), 0.1, 1e-9, "glitch third step +, next period")
		H.near(Motion.glitchOffset(1.3, g), 0, 1e-9, "glitch over")
		local b = { Period = 4, Seconds = 0.4, Count = 4, Phase = 1 }
		H.expect(not Motion.blinkGone(0.5, b), "blink shown outside its window")
		H.expect(not Motion.blinkGone(1.05, b), "blink shown on the first sub-step")
		H.expect(Motion.blinkGone(1.15, b), "blink gone on the second")
		H.expect(not Motion.blinkGone(1.25, b), "blink shown on the third")
		H.expect(Motion.blinkGone(5.35, b), "blink gone on the fourth, next period")
		H.near(Motion.vfxWave(0, { Min = 0.2, Max = 1 }), 0.2, 1e-9, "sine starts at Min")
		H.near(Motion.vfxWave(1, { Min = 0.2, Max = 1, Period = 2 }), 1, 1e-9, "sine Max at half")
		H.near(
			Motion.vfxWave(0.25, { Min = 0, Max = 1, Period = 1, Phase = 0.25 }),
			1,
			1e-9,
			"Phase"
		)
		local beat = Motion.vfxWave(0.1, { Min = 0, Max = 1, Period = 1, Shape = "beat" })
		H.near(beat, 1, 1e-9, "beat's first bump")
		for t = 0, 3, 0.01 do
			local f = Motion.vfxWave(t, { Min = 0, Max = 1, Shape = "flicker" })
			H.expect(f >= 0.315 and f <= 1, "flicker stays in 0.315..1")
		end
		H.near(Motion.curve({ { 0, -1 }, { 0.3, 0.2 }, { 1, 0.4 } }, 0.15), -0.4, 1e-9, "curve")
		H.near(Motion.curve(0.7, 0.4), 0.7, 1e-9, "a number is a flat curve")
	end,

	["bone transforms undo the rest and the parent bone"] = function()
		local Motion = H.require("CueSkins.Motion")
		local rig = Motion.rig(H.require("CueSkins.Pieces.kitsune"))
		local pose = Motion.pose(rig, 1.7)
		-- A bone's model transform rebuilt from its parent's and its own Transform is J * Rest.
		local parent, bone = "Mask", "EarRight"
		local pivotP, pivotB = rig.joints[parent].pivot, rig.joints[bone].pivot
		local restP = Motion.translate(pivotP[1], pivotP[2], pivotP[3])
		local restB = Motion.translate(pivotB[1], pivotB[2], pivotB[3])
		local parentWorld = Motion.mul(pose[parent], restP)
		local localRest = Motion.mul(Motion.inverse(restP), restB)
		local T = Motion.boneTransform(pose, rig, bone, parent)
		local world = Motion.mul(parentWorld, Motion.mul(localRest, T))
		local want = Motion.mul(pose[bone], restB)
		for i = 1, 9 do
			H.near(world.R[i], want.R[i], 1e-9, "R")
		end
		for i = 1, 3 do
			H.near(world.P[i], want.P[i], 1e-9, "P")
		end
	end,
}
