--!strict
-- CueSkins.Motion: the cue skins' moving maths, pure (no Instances, no Roblox types), so Lune
-- tests it against the Blender reference (assets/cue/CuePieces.py: _wave, path_frame,
-- motion_matrix, joint_matrix; CueVfx.py: wave).
--
-- A transform here is an Xf: a 3x3 rotation R (row-major, 9 numbers) and a translation P, the
-- same thing a CFrame holds; the client turns one into a CFrame with `cframe`. Everything is
-- in the Roblox cue frame (X = -Side, Y = Up, Z = 3.5 - AtStuds; the pocket frame for a
-- pocket piece, Z = Blender Y): piece.json's Axis, Dir, Pivot and path samples are written in
-- the Blender cue frame and are turned once by A = [[-1,0,0],[0,0,1],[0,1,0]] (Blender
-- (x, y, z) -> Roblox (-x, z, y), determinant +1, so turns keep their sign).

local Motion = {}

export type Xf = { R: { number }, P: { number } }

local IDENTITY_R = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

function Motion.identity(): Xf
	return { R = table.clone(IDENTITY_R), P = { 0, 0, 0 } }
end

function Motion.translate(x: number, y: number, z: number): Xf
	return { R = table.clone(IDENTITY_R), P = { x, y, z } }
end

--- a * b (apply b first, then a), as CFrame multiplication.
function Motion.mul(a: Xf, b: Xf): Xf
	local A, B = a.R, b.R
	local R = {
		A[1] * B[1] + A[2] * B[4] + A[3] * B[7],
		A[1] * B[2] + A[2] * B[5] + A[3] * B[8],
		A[1] * B[3] + A[2] * B[6] + A[3] * B[9],
		A[4] * B[1] + A[5] * B[4] + A[6] * B[7],
		A[4] * B[2] + A[5] * B[5] + A[6] * B[8],
		A[4] * B[3] + A[5] * B[6] + A[6] * B[9],
		A[7] * B[1] + A[8] * B[4] + A[9] * B[7],
		A[7] * B[2] + A[8] * B[5] + A[9] * B[8],
		A[7] * B[3] + A[8] * B[6] + A[9] * B[9],
	}
	local p = b.P
	local P = {
		A[1] * p[1] + A[2] * p[2] + A[3] * p[3] + a.P[1],
		A[4] * p[1] + A[5] * p[2] + A[6] * p[3] + a.P[2],
		A[7] * p[1] + A[8] * p[2] + A[9] * p[3] + a.P[3],
	}
	return { R = R, P = P }
end

--- The inverse of a rigid transform.
function Motion.inverse(x: Xf): Xf
	local R = x.R
	local T = { R[1], R[4], R[7], R[2], R[5], R[8], R[3], R[6], R[9] }
	local p = x.P
	return {
		R = T,
		P = {
			-(T[1] * p[1] + T[2] * p[2] + T[3] * p[3]),
			-(T[4] * p[1] + T[5] * p[2] + T[6] * p[3]),
			-(T[7] * p[1] + T[8] * p[2] + T[9] * p[3]),
		},
	}
end

--- A turn of `angle` radians about `axis` (any length), right-handed.
function Motion.rotate(axis: { number }, angle: number): Xf
	local n = math.sqrt(axis[1] ^ 2 + axis[2] ^ 2 + axis[3] ^ 2) + 1e-12
	local x, y, z = axis[1] / n, axis[2] / n, axis[3] / n
	local c, s = math.cos(angle), math.sin(angle)
	local C = 1 - c
	return {
		R = {
			c + x * x * C,
			x * y * C - z * s,
			x * z * C + y * s,
			y * x * C + z * s,
			c + y * y * C,
			y * z * C - x * s,
			z * x * C - y * s,
			z * y * C + x * s,
			c + z * z * C,
		},
		P = { 0, 0, 0 },
	}
end

--- Blender cue-frame vector -> Roblox cue-frame vector.
function Motion.toRoblox(v: { number }): { number }
	return { -v[1], v[3], v[2] }
end

---------------------------------------------------------------------------------------------
-- Waves
---------------------------------------------------------------------------------------------

--- A piece motion's wave in -1..1 (CuePieces._wave): Phase in degrees; Shape sine, snap (a
--- sharpened sine: quick close, slow open), pulse (a quick swing in the first 30% of each
--- period, rest after) or saw (one way, -1 to 1 over a period, then straight back: a scan
--- line sweeping tip to butt).
function Motion.pieceWave(t: number, m: any): number
	local period = m.Period or 2
	local x = 2 * math.pi * t / period + math.rad(m.Phase or 0)
	local shape = m.Shape or "sine"
	if shape == "snap" then
		local s = math.sin(x)
		return math.sign(s) * math.abs(s) ^ 0.35
	elseif shape == "pulse" then
		local u = (x / (2 * math.pi)) % 1
		return if u < 0.3 then math.sin(math.pi * math.min(u / 0.3, 1)) else 0
	elseif shape == "saw" then
		local u = (x / (2 * math.pi)) % 1
		return 2 * u - 1
	end
	return math.sin(x)
end

--- A Glitch motion's jolt at time t (CuePieces.glitch_offset): once every Period seconds
--- (from Phase seconds in) the joint jumps Amp studs along Dir for Seconds, the sign flipping
--- on each of Steps equal sub-steps, then sits still; 0 outside the window.
function Motion.glitchOffset(t: number, m: any): number
	local period = m.Period or 3
	local secs = m.Seconds or 0.15
	local steps = math.max(1, m.Steps or 3)
	local u = (t - (m.Phase or 0)) % period
	if u >= secs then
		return 0
	end
	local n = math.floor(u / secs * steps)
	return (m.Amp or 0.05) * (if n % 2 == 0 then 1 else -1)
end

--- Whether a Blink visual has its parts gone at time t: during a window of Seconds once every
--- Period (from Phase seconds in), the parts vanish on every other of Count equal sub-steps
--- (shown, gone, shown, ...), a glitch's blink.
function Motion.blinkGone(t: number, v: any): boolean
	local period = v.Period or 3
	local secs = v.Seconds or 0.15
	local count = math.max(1, v.Count or 4)
	local u = (t - (v.Phase or 0)) % period
	if u >= secs then
		return false
	end
	return math.floor(u / secs * count) % 2 == 1
end

--- An effect wave between Min and Max (CueVfx.wave): Phase is a share of a period; Shape sine
--- (starts at Min), flicker (mostly near Max with quick dips; never reaches Min), beat (a
--- heartbeat's two bumps) or life (a hologram panel's life: Min at birth, popping in over
--- the first 6% of the period with one blink, Max to 82%, then dissolving to Min with a blink
--- halfway down).
function Motion.vfxWave(t: number, spec: any): number
	local lo, hi = spec.Min or 0, spec.Max or 1
	local ph = (t / (spec.Period or 2) + (spec.Phase or 0)) % 1
	local shape = spec.Shape or "sine"
	local k
	if shape == "life" then
		if ph < 0.06 then
			k = if ph > 0.02 and ph < 0.035 then 0.15 else ph / 0.06
		elseif ph < 0.82 then
			k = 1
		else
			local u = (ph - 0.82) / 0.18
			k = if u > 0.5 and u < 0.6 then 0.1 else 1 - u
		end
	elseif shape == "flicker" then
		k = 0.85 + 0.15 * math.sin(2 * math.pi * ph)
		if math.sin(37 * t) * math.sin(11.3 * t) > 0.93 then
			k *= 0.45
		end
	elseif shape == "beat" then
		k = math.exp(-((ph - 0.1) / 0.08) ^ 2) + 0.6 * math.exp(-((ph - 0.32) / 0.08) ^ 2)
		k = math.min(k, 1)
	else
		k = 0.5 - 0.5 * math.cos(2 * math.pi * ph)
	end
	return lo + (hi - lo) * k
end

--- A curve [[t, v], ...] (or a plain number) read at k in 0..1, linearly.
function Motion.curve(c: any, k: number): number
	if type(c) == "number" then
		return c
	end
	local n = #c
	if k <= c[1][1] then
		return c[1][2]
	end
	for i = 2, n do
		local a, b = c[i - 1], c[i]
		if k <= b[1] then
			local span = b[1] - a[1]
			local f = if span > 0 then (k - a[1]) / span else 1
			return a[2] + (b[2] - a[2]) * f
		end
	end
	return c[n][2]
end

---------------------------------------------------------------------------------------------
-- Paths (the Celestial Dragon swims along one)
---------------------------------------------------------------------------------------------

local function quatSlerp(a: { number }, b: { number }, f: number): (number, number, number, number)
	local aw, ax, ay, az = a[1], a[2], a[3], a[4]
	local bw, bx, by, bz = b[1], b[2], b[3], b[4]
	local dot = aw * bw + ax * bx + ay * by + az * bz
	if dot < 0 then -- the short way round
		bw, bx, by, bz, dot = -bw, -bx, -by, -bz, -dot
	end
	local wa, wb
	if dot > 0.9995 then
		wa, wb = 1 - f, f
	else
		local theta = math.acos(math.clamp(dot, -1, 1))
		local s = math.sin(theta)
		wa, wb = math.sin((1 - f) * theta) / s, math.sin(f * theta) / s
	end
	local w, x, y, z = aw * wa + bw * wb, ax * wa + bx * wb, ay * wa + by * wb, az * wa + bz * wb
	local n = math.sqrt(w * w + x * x + y * y + z * z)
	return w / n, x / n, y / n, z / n
end

local function quatMatrix(w: number, x: number, y: number, z: number): { number }
	return {
		1 - 2 * (y * y + z * z),
		2 * (x * y - z * w),
		2 * (x * z + y * w),
		2 * (x * y + z * w),
		1 - 2 * (x * x + z * z),
		2 * (y * z - x * w),
		2 * (x * z - y * w),
		2 * (y * z + x * w),
		1 - 2 * (x * x + y * y),
	}
end

-- A = Blender -> Roblox as a matrix (row-major).
local A = { R = { -1, 0, 0, 0, 0, 1, 0, 1, 0 }, P = { 0, 0, 0 } }

--- A looping path's frame at arc length s, in the Roblox frame (CuePieces.path_frame turned by
--- A, the point moved by `zoff` along Z): samples [x, y, z, qw, qx, qy, qz] every Step studs,
--- the point lerped and the turn slerped between them.
function Motion.pathFrame(path: any, s: number, zoff: number): Xf
	local F = path.Frames
	local n = #F
	local u = (s / path.Step) % n
	local i = math.floor(u)
	local f = u - i
	local a, b = F[i + 1], F[(i + 1) % n + 1]
	local w, x, y, z = quatSlerp({ a[4], a[5], a[6], a[7] }, { b[4], b[5], b[6], b[7] }, f)
	local blender: Xf = {
		R = quatMatrix(w, x, y, z),
		P = { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f },
	}
	local out = Motion.mul(A, blender)
	out.P[3] += zoff
	return out
end

---------------------------------------------------------------------------------------------
-- Rigs: a piece's joints, compiled once
---------------------------------------------------------------------------------------------

export type Joint = {
	name: string,
	parent: string?,
	pivot: { number },
	motions: { any },
	visuals: { any }, -- Fade, Blink, Glow rows the client applies to the joint's parts
	aura: boolean,
	low: string?, -- "hide": gone under Lower effects (Quality)
}

export type Rig = {
	joints: { [string]: Joint },
	order: { string }, -- parents before children, by name inside a depth: deterministic
	paths: { [string]: any },
	zoff: number,
}

--- Compile a piece row (CueSkins.Pieces.<id>) into a rig: axes and directions turned into the
--- Roblox frame, joints ordered parents first.
function Motion.rig(piece: any): Rig
	local joints: { [string]: Joint } = {}
	for name, j in piece.Joints do
		local motions = {}
		for _, m in j.Motion or {} do
			local c = table.clone(m)
			if m.Axis then
				c.Axis = Motion.toRoblox(m.Axis)
			end
			if m.Dir then
				c.Dir = Motion.toRoblox(m.Dir)
			end
			table.insert(motions, c)
		end
		joints[name] = {
			name = name,
			parent = j.Parent,
			pivot = j.PivotRoblox,
			motions = motions,
			visuals = j.Visual or {},
			aura = j.Aura == true,
			low = j.Low,
		}
	end
	local depth: { [string]: number } = {}
	local function depthOf(name: string): number
		if depth[name] == nil then
			local parent = joints[name].parent
			depth[name] = if parent and joints[parent] then depthOf(parent) + 1 else 0
		end
		return depth[name]
	end
	local order = {}
	for name in joints do
		depthOf(name)
		table.insert(order, name)
	end
	table.sort(order, function(a, b)
		if depth[a] ~= depth[b] then
			return depth[a] < depth[b]
		end
		return a < b
	end)
	return {
		joints = joints,
		order = order,
		paths = piece.Paths or {},
		zoff = if piece.Frame == "pocket" then 0 else 3.5,
	}
end

-- One joint's own motion at time t, about its pivot (motion_matrix): the motion list applied
-- left to right; a Path rides the track so that the joint's own transform is X itself.
local function own(rig: Rig, joint: Joint, t: number): Xf
	local M = Motion.identity()
	local pivot = joint.pivot
	local toPivot = Motion.translate(pivot[1], pivot[2], pivot[3])
	local fromPivot = Motion.translate(-pivot[1], -pivot[2], -pivot[3])
	for _, m in joint.motions do
		local kind = m.Kind
		if kind == "Path" then
			local path = rig.paths[m.Path]
			local X = Motion.mul(
				Motion.pathFrame(path, m.Rest + m.Speed * t, rig.zoff),
				Motion.inverse(Motion.pathFrame(path, m.Rest, rig.zoff))
			)
			M = Motion.mul(M, Motion.mul(fromPivot, Motion.mul(X, toPivot)))
		elseif kind == "Hinge" or kind == "Sway" then
			local angle = math.rad((m.Base or 0) + (m.Amp or 10) * Motion.pieceWave(t, m))
			M = Motion.mul(M, Motion.rotate(m.Axis or { -1, 0, 0 }, angle))
		elseif kind == "Spin" then
			local angle = math.rad((m.Rate or 90) * t + (m.Phase or 0))
			M = Motion.mul(M, Motion.rotate(m.Axis or { 0, 0, 1 }, angle))
		elseif kind == "Bob" then
			local d = m.Dir or { 0, 1, 0 }
			local k = (m.Amp or 0.02) * Motion.pieceWave(t, m)
			M = Motion.mul(M, Motion.translate(d[1] * k, d[2] * k, d[3] * k))
		elseif kind == "Glitch" then
			local d = m.Dir or { -1, 0, 0 }
			local k = Motion.glitchOffset(t, m)
			M = Motion.mul(M, Motion.translate(d[1] * k, d[2] * k, d[3] * k))
		end
	end
	return Motion.mul(toPivot, Motion.mul(M, fromPivot))
end

--- Every joint's full transform at time t (joint_matrix: the parent's, then its own motion
--- about its pivot), by joint name.
function Motion.pose(rig: Rig, t: number): { [string]: Xf }
	local out: { [string]: Xf } = {}
	for _, name in rig.order do
		local joint = rig.joints[name]
		local mine = own(rig, joint, t)
		local parent = joint.parent
		out[name] = if parent and out[parent] then Motion.mul(out[parent], mine) else mine
	end
	return out
end

--- A skinned bone's Transform from a pose: Rest^-1 * J_parent^-1 * J_bone * Rest, Rest the
--- bone's rest (unturned, its head at the joint's pivot), J_parent the parent bone's (nil for
--- a root bone, whose J carries its whole joint chain).
function Motion.boneTransform(
	pose: { [string]: Xf },
	rig: Rig,
	bone: string,
	parentBone: string?
): Xf
	local pivot = rig.joints[bone].pivot
	local rest = Motion.translate(pivot[1], pivot[2], pivot[3])
	local rel = Motion.jointDelta(pose, bone, parentBone)
	return Motion.mul(Motion.inverse(rest), Motion.mul(rel, rest))
end

--- A joint's motion relative to its parent bone's: J_parent^-1 * J_bone (J_bone alone when the
--- parent bone is not a joint). A bone whose rest frame in the piece is B, turned however the
--- importer left it, takes Transform = B^-1 * jointDelta * B (CuePiece).
function Motion.jointDelta(pose: { [string]: Xf }, bone: string, parentBone: string?): Xf
	local J = pose[bone]
	if parentBone and pose[parentBone] then
		return Motion.mul(Motion.inverse(pose[parentBone]), J)
	end
	return J
end

return Motion
