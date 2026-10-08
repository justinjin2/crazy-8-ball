--!strict
-- BoneAnim: plays the baked bone animations (tools/bake_bone_anims.py: VerityAnims,
-- TigerAnims) on an uploaded skinned model by setting each Bone's Transform every frame.
--
-- The data is each bone's skinning delta (posed * rest^-1) in the model's armature space, the
-- space the importer laid the mesh in (Blender (x, y, z) -> (-x, z, y), the part's own axes).
-- A delta moves the skin exactly as Blender did whatever way the importer turned the bones
-- themselves (STUDIO_NOTES "Skinned glb models"). new() fits that space to the model as it
-- stands: its scale from the bones' rest spread against the data's, its origin from the root
-- bone. Call refit() after a Model:ScaleTo.

local BoneAnim = {}
BoneAnim.__index = BoneAnim

export type Action = {
	Fps: number,
	Frames: number,
	Loop: boolean,
	Tracks: { [string]: string }, -- per bone, 7 comma-separated numbers a frame
}

export type Data = {
	Root: string,
	RootRest: { number },
	Rest: { [string]: { number } },
	Bones: { string },
	Parents: { [string]: string },
	Actions: { [string]: Action },
}

type Joint = {
	bone: Bone,
	name: string,
	parent: number, -- index of the parent joint, 0 for the part
	rest: CFrame, -- the bone's rest frame in the part's space (Transforms left out)
}

type Fields = {
	data: Data,
	part: BasePart,
	joints: { Joint },
	origin: CFrame, -- the armature space's origin in the part's space
	scale: number, -- studs per armature unit
	frames: { [string]: { [string]: { CFrame } } }, -- action -> bone -> per-frame delta
	posed: { CFrame }, -- per joint, this frame's frame in the part's space (scratch)
	deltas: { [string]: CFrame }, -- this frame's deltas (scratch)
}

export type Player = typeof(setmetatable({} :: Fields, BoneAnim))

local function vec(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

--- A player for `model` (the uploaded model: a MeshPart with the bones under it), or nil when
--- it has no bones `data` animates.
function BoneAnim.new(model: Instance, data: Data): Player?
	local rootBone: Bone? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") and d.Name == data.Root then
			rootBone = d
			break
		end
	end
	local part = rootBone and rootBone.Parent
	if rootBone == nil or part == nil or not part:IsA("BasePart") then
		return nil
	end
	local joints: { Joint } = {}
	-- Parents before children: a walk down from the root bone.
	local function walk(b: Bone, parent: number)
		table.insert(joints, { bone = b, name = b.Name, parent = parent, rest = CFrame.identity })
		local index = #joints
		for _, c in b:GetChildren() do
			if c:IsA("Bone") then
				walk(c, index)
			end
		end
	end
	walk(rootBone :: Bone, 0)
	local self = setmetatable(
		{
			data = data,
			part = part :: BasePart,
			joints = joints,
			origin = CFrame.identity,
			scale = 1,
			frames = {},
			posed = table.create(#joints, CFrame.identity),
			deltas = {},
		} :: Fields,
		BoneAnim
	)
	self:refit()
	return self
end

--- Re-read the bones' rest frames and fit the armature space again (after a ScaleTo).
function BoneAnim.refit(self: Player)
	local joints = self.joints
	-- From the bones' CFrames alone, which never hold a Transform.
	for _, j in joints do
		local up = if j.parent == 0 then CFrame.identity else joints[j.parent].rest
		j.rest = up * j.bone.CFrame
	end
	local data = self.data
	local root = joints[1]
	local rootRest = vec(data.RootRest)
	local spreadHere, spreadData = 0, 0
	for _, j in joints do
		local at = data.Rest[j.name]
		if at ~= nil then
			spreadHere += (j.rest.Position - root.rest.Position).Magnitude
			spreadData += (vec(at) - rootRest).Magnitude
		end
	end
	self.scale = if spreadData > 1e-6 then spreadHere / spreadData else 1
	-- The import keeps the armature's (mapped) axes as the part's own: no turn, only a shift.
	self.origin = CFrame.new(root.rest.Position - rootRest * self.scale)
end

--- How long action `name` runs once, in seconds (0 if unknown).
function BoneAnim.length(self: Player, name: string): number
	local a = self.data.Actions[name]
	return if a then a.Frames / a.Fps else 0
end

-- Action `name`'s deltas as CFrames, per bone per frame (built on first use).
function BoneAnim.framesOf(self: Player, name: string): { [string]: { CFrame } }?
	local cached = self.frames[name]
	if cached then
		return cached
	end
	local a = self.data.Actions[name]
	if a == nil then
		return nil
	end
	local out: { [string]: { CFrame } } = {}
	for bone, text in a.Tracks do
		local nums: { number } = {}
		for i, s in string.split(text, ",") do
			nums[i] = tonumber(s) or 0
		end
		local list = table.create(a.Frames)
		for f = 0, a.Frames - 1 do
			local o = f * 7
			list[f + 1] = CFrame.new(
				nums[o + 5],
				nums[o + 6],
				nums[o + 7],
				nums[o + 1],
				nums[o + 2],
				nums[o + 3],
				nums[o + 4]
			)
		end
		out[bone] = list
	end
	self.frames[name] = out
	return out
end

-- The deltas of action `name` at `seconds` into `into`, mixed toward what is already there by
-- `weight` (1 replaces). A looping action wraps; a one-shot holds its last frame.
local function sample(
	self: Player,
	into: { [string]: CFrame },
	name: string,
	seconds: number,
	weight: number
)
	local a = self.data.Actions[name]
	local frames = self:framesOf(name)
	if a == nil or frames == nil then
		return
	end
	local f = math.max(seconds, 0) * a.Fps
	local i0, i1, alpha
	if a.Loop then
		f %= a.Frames
		i0 = math.floor(f)
		i1 = (i0 + 1) % a.Frames
		alpha = f - i0
	else
		f = math.min(f, a.Frames - 1)
		i0 = math.floor(f)
		i1 = math.min(i0 + 1, a.Frames - 1)
		alpha = f - i0
	end
	for bone, list in frames do
		local d = list[i0 + 1]:Lerp(list[i1 + 1], alpha)
		local had: CFrame? = into[bone]
		if weight < 1 and had then
			d = had:Lerp(d, weight)
		end
		into[bone] = d
	end
end

--- Pose the model: action `name` at `seconds`; optionally mixed toward action `other` at
--- `otherSeconds` by `mix` (0 = all `name`, 1 = all `other`), for a cross-fade.
function BoneAnim.pose(
	self: Player,
	name: string,
	seconds: number,
	other: string?,
	otherSeconds: number?,
	mix: number?
)
	local deltas = self.deltas
	table.clear(deltas)
	sample(self, deltas, name, seconds, 1)
	if other ~= nil and mix ~= nil and mix > 0 then
		sample(self, deltas, other, otherSeconds or 0, math.min(mix, 1))
	end
	self:apply(deltas)
end

--- Set every bone's Transform so the skin moves by `deltas` (bone name -> armature-space
--- delta); bones without one follow their parent.
function BoneAnim.apply(self: Player, deltas: { [string]: CFrame })
	local origin = self.origin
	local back = origin:Inverse()
	local k = self.scale
	local posed = self.posed
	for i, j in self.joints do
		local up = if j.parent == 0 then CFrame.identity else posed[j.parent]
		local base = up * j.bone.CFrame
		local d = deltas[j.name]
		if d then
			local want = origin * (CFrame.new(d.Position * k) * d.Rotation) * back * j.rest
			j.bone.Transform = base:Inverse() * want
			posed[i] = want
		else
			j.bone.Transform = CFrame.identity
			posed[i] = base
		end
	end
end

--- Back to the rest pose.
function BoneAnim.rest(self: Player)
	for _, j in self.joints do
		j.bone.Transform = CFrame.identity
	end
end

--- Where bone `name` is in the world now (its posed frame), or nil if the model has no such
--- bone. For attaching things to a hand or a paw.
function BoneAnim.worldOf(self: Player, name: string): CFrame?
	for i, j in self.joints do
		if j.name == name then
			return self.part.CFrame * self.posed[i]
		end
	end
	return nil
end

return BoneAnim
