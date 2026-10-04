--!strict
-- CuePiece: a cue skin's 3D piece (CueSkins.piece rows: Phoenix's wings, the Kraken's
-- tentacles, the Celestial Dragon, the Kitsune's mask and running fox, Eclipse's orbits, the
-- pocket creatures), built from its Edit-mode template and moved every frame by its joints
-- (CueSkins.Motion, the Blender reference's maths).
--
-- Templates: ReplicatedStorage[Config.CueSkins.PiecesFolder].<piece> holds one MeshPart per
-- rigid part (named as the row's part) and one Model per skinned file (RootPart, Bones and
-- skinned MeshParts, as the importer made them), dressed in Edit by
-- tools/build_cue_templates.luau (Material, Color, SurfaceAppearance cannot all be set here).
--
-- Every part is unanchored, massless and touches nothing, welded to a ROOT part: the cue's
-- mesh (so the piece follows the stick in the hands and on a back with no extra code) or the
-- pocket finisher's own anchored root. Roblox's importer turns every uploaded model half a
-- turn about its up axis (FLIP; the shared cue mesh too), so a rigid part's Weld.C0 is
-- J(t) * Offset * FLIP, a skinned model's RootPart is welded at FLIP, and each Bone gets
-- Transform = B^-1 * Motion.jointDelta * B, B the bone's rest frame in the piece's frame read
-- from the template (the importer turns bones too: the dragon's top bone is half a turn
-- about Y, and assuming square bones threw its body past the butt).
-- Joints marked Aura (the dragon, the running fox) hide with the aura.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CueSkins = require(Shared:WaitForChild("CueSkins"))
local Motion = require(Shared:WaitForChild("CueSkins"):WaitForChild("Motion"))
local Quality = require(script.Parent.Quality)

local CuePiece = {}
CuePiece.__index = CuePiece

-- The importer's half turn about Y (its own inverse).
local FLIP = CFrame.Angles(0, math.pi, 0)

type Rigid = { part: BasePart, weld: Weld, joint: string, offset: CFrame, base: number }
type Skinned = {
	model: Model,
	parts: { BasePart },
	base: { number },
	bones: { { bone: Bone, joint: string, parent: string?, rest: CFrame } },
}
type Rider = { part: BasePart, weld: Weld, joint: string, rest: CFrame }

export type CuePiece = typeof(setmetatable(
	{} :: {
		id: string,
		model: Model,
		rig: Motion.Rig,
		rigid: { Rigid },
		skinned: { Skinned },
		riders: { Rider },
		auraJoints: { [string]: boolean },
		auraShown: boolean,
		auraShare: number,
		layers: { [string]: string },
		scale: number,
		pose: { [string]: Motion.Xf },
	},
	CuePiece
))

local function cframe(x: Motion.Xf, scale: number?): CFrame
	local R, P = x.R, x.P
	local s = scale or 1
	return CFrame.new(
		P[1] * s,
		P[2] * s,
		P[3] * s,
		R[1],
		R[2],
		R[3],
		R[4],
		R[5],
		R[6],
		R[7],
		R[8],
		R[9]
	)
end
CuePiece.cframe = cframe

local function loose(part: BasePart)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function template(id: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild(Config.CueSkins.PiecesFolder)
	return folder and folder:FindFirstChild(id)
end

--- True when the piece's template is in the place.
function CuePiece.available(id: string): boolean
	return CueSkins.piece(id) ~= nil and template(id) ~= nil
end

--- Build piece `id` welded to `root` (its frame: the cue mesh for a cue piece, the pocket
--- root for a pocket piece), in `parent`. Nil when the row or the template is missing.
function CuePiece.new(id: string, root: BasePart, parent: Instance): CuePiece?
	local row = CueSkins.piece(id)
	local source = template(id)
	if row == nil or source == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Piece_" .. id
	local rig = Motion.rig(row)
	local auraJoints: { [string]: boolean } = {}
	local layers: { [string]: string } = {}
	for _, name in rig.order do
		local j = rig.joints[name]
		auraJoints[name] = j.aura or (j.parent ~= nil and auraJoints[j.parent] == true)
		layers[name] = row.Joints[name].Layer or (j.parent and layers[j.parent]) or ""
	end
	local rigid: { Rigid } = {}
	local skinned: { Skinned } = {}
	local doneModels: { [string]: boolean } = {}
	for _, p in row.Parts do
		if p.Model then
			if not doneModels[p.Model] then
				doneModels[p.Model] = true
				local src = source:FindFirstChild(p.Model)
				if src and src:IsA("Model") then
					local copy = src:Clone()
					local parts, base = {}, {}
					local rootPart = copy:FindFirstChild("RootPart") :: BasePart?
					for _, d in copy:GetDescendants() do
						if d:IsA("BasePart") then
							loose(d)
							if d ~= rootPart then
								table.insert(parts, d)
								table.insert(base, d.Transparency)
							end
						end
					end
					-- Rest frames before the weld moves anything: the template's RootPart frame is
					-- the importer's turned piece frame.
					local rootFrame = if rootPart then rootPart.CFrame else CFrame.identity
					local bones = {}
					for _, d in copy:GetDescendants() do
						if d:IsA("Bone") and rig.joints[d.Name] then
							local parentBone = d.Parent
							table.insert(bones, {
								bone = d,
								joint = d.Name,
								parent = if parentBone and parentBone:IsA("Bone")
									then parentBone.Name
									else nil,
								rest = FLIP * rootFrame:ToObjectSpace(d.WorldCFrame),
							})
						end
					end
					if rootPart then
						rootPart.Transparency = 1
						local weld = Instance.new("Weld")
						weld.Part0 = root
						weld.Part1 = rootPart
						weld.C0 = FLIP
						weld.C1 = CFrame.identity
						weld.Parent = rootPart
					end
					copy.Parent = model
					table.insert(
						skinned,
						{ model = copy, parts = parts, base = base, bones = bones }
					)
				end
			end
		else
			local src = source:FindFirstChild(p.Name)
			if src and src:IsA("BasePart") then
				local part = src:Clone()
				loose(part)
				local weld = Instance.new("Weld")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = part
				part.Parent = model
				local o = p.Offset
				table.insert(rigid, {
					part = part,
					weld = weld,
					joint = p.Joint,
					offset = CFrame.new(o[1], o[2], o[3]) * FLIP,
					base = part.Transparency,
				})
			end
		end
	end
	model.Parent = parent
	local self = setmetatable({
		id = id,
		model = model,
		rig = rig,
		rigid = rigid,
		skinned = skinned,
		riders = {},
		auraJoints = auraJoints,
		auraShown = true,
		auraShare = 1,
		layers = layers,
		scale = 1,
		pose = {},
	}, CuePiece)
	self:step(0)
	return self
end

--- Weld `part` to ride joint `joint` (its rest place `rest` in the piece's frame): an
--- emitter host on a moving wing or a swimming body. It is moved with the joint every step.
function CuePiece.ride(self: CuePiece, part: BasePart, joint: string, rest: CFrame, root: BasePart)
	loose(part)
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	table.insert(self.riders, { part = part, weld = weld, joint = joint, rest = rest })
	local x = self.pose[joint]
	weld.C0 = (if x then cframe(x, self.scale) else CFrame.identity) * rest
end

--- Whether a joint (or one of its parents) is aura.
function CuePiece.isAura(self: CuePiece, joint: string): boolean
	return self.auraJoints[joint] == true
end

--- Move every joint to time `t` (seconds on the piece's clock).
function CuePiece.step(self: CuePiece, t: number)
	local pose = Motion.pose(self.rig, t)
	self.pose = pose
	local s = self.scale
	for _, r in self.rigid do
		if self.auraShown or not self.auraJoints[r.joint] then
			local x = pose[r.joint]
			local offset = if s == 1 then r.offset else CFrame.new(r.offset.Position * s) * FLIP
			r.weld.C0 = (if x then cframe(x, s) else CFrame.identity) * offset
		end
	end
	for _, r in self.riders do
		local x = pose[r.joint]
		r.weld.C0 = (if x then cframe(x, s) else CFrame.identity) * r.rest
	end
	for _, sk in self.skinned do
		for _, b in sk.bones do
			if self.auraShown or not self.auraJoints[b.joint] then
				local x = Motion.jointDelta(pose, b.joint, b.parent)
				local rest = if s == 1
					then b.rest
					else CFrame.new(b.rest.Position * s) * b.rest.Rotation
				b.bone.Transform = rest:Inverse() * cframe(x, s) * rest
			end
		end
	end
end

-- A skinned model counts as aura when its root bone's joint is.
local function skinnedAura(self: CuePiece, sk: Skinned): boolean
	for _, b in sk.bones do
		if b.parent == nil then
			return self.auraJoints[b.joint] == true
		end
	end
	return false
end

--- Show or hide the aura joints (the shooter's turn hides them; LocalTransparencyModifier, so
--- nothing about the parts is rebuilt).
function CuePiece.setAura(self: CuePiece, shown: boolean)
	if shown == self.auraShown then
		return
	end
	self.auraShown = shown
	local modifier = if shown then 0 else 1
	for _, r in self.rigid do
		if self.auraJoints[r.joint] then
			r.part.LocalTransparencyModifier = modifier
		end
	end
	for _, sk in self.skinned do
		if skinnedAura(self, sk) then
			for _, part in sk.parts do
				part.LocalTransparencyModifier = modifier
			end
		end
	end
end

--- Fade the whole piece: 0 as built, 1 gone (the pocket piece's Transparency curve).
function CuePiece.setFade(self: CuePiece, fade: number)
	for _, r in self.rigid do
		r.part.Transparency = r.base + (1 - r.base) * fade
	end
	for _, sk in self.skinned do
		for i, part in sk.parts do
			part.Transparency = sk.base[i] + (1 - sk.base[i]) * fade
		end
	end
end

--- Deepen the piece against bright light (a pocket finisher's creature): its ForceField shell
--- parts `shellFade` of the way to clear (setFade fades from there), every glow
--- (SurfaceAppearance EmissiveStrength) `emissiveScale` as strong and, given `tint`, its
--- colour maps tinted by it (SurfaceAppearance.Color multiplies the map).
function CuePiece.deepen(self: CuePiece, shellFade: number, emissiveScale: number, tint: Color3?)
	local function shell(part: BasePart, base: number): number
		if part.Material ~= Enum.Material.ForceField then
			return base
		end
		local deeper = base + (1 - base) * shellFade
		part.Transparency = deeper
		return deeper
	end
	for _, r in self.rigid do
		r.base = shell(r.part, r.base)
	end
	for _, sk in self.skinned do
		for i, part in sk.parts do
			sk.base[i] = shell(part, sk.base[i])
		end
	end
	for _, d in self.model:GetDescendants() do
		if d:IsA("SurfaceAppearance") then
			d.EmissiveStrength *= emissiveScale
			if tint then
				d.Color = tint
			end
		end
	end
end

--- Every part of the piece follows `modifier` (a stick's camera fade), aura joints staying
--- hidden while the aura is.
function CuePiece.setModifier(self: CuePiece, modifier: number)
	local function layerModifier(joint: string): number
		local layer = self.layers[joint]
		local quality = if Quality.isLow() then Config.CueSkins.LowerPieceLayers[layer] or 1 else 1
		local quiet = if self.auraJoints[joint] and layer ~= "" then self.auraShare else 1
		return 1 - (1 - modifier) * quality * quiet
	end
	for _, r in self.rigid do
		local hidden = not self.auraShown and self.auraJoints[r.joint]
		r.part.LocalTransparencyModifier = if hidden then 1 else layerModifier(r.joint)
	end
	for _, sk in self.skinned do
		local hidden = not self.auraShown and skinnedAura(self, sk)
		local share = modifier
		for _, bone in sk.bones do
			if bone.parent == nil then
				share = layerModifier(bone.joint)
				break
			end
		end
		for _, part in sk.parts do
			part.LocalTransparencyModifier = if hidden then 1 else share
		end
	end
end

--- Uniform scale about the root (the pocket piece grows as it rises): sizes and every
--- position the joints give.
function CuePiece.setScale(self: CuePiece, scale: number)
	if math.abs(scale - self.scale) < 1e-4 then
		return
	end
	self.model:ScaleTo(math.max(scale, 0.01))
	self.scale = scale
end

function CuePiece.destroy(self: CuePiece)
	self.model:Destroy()
end

return CuePiece
