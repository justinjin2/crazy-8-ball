--!strict
-- EmotePropBuilder: the thing a dance holds (Config.EmoteMenu.Props: Gojo's Bloxy Cola, Popcorn's
-- bucket, Bullseye's bow), welded to a body's hand. The server holds it on a dancer (seen by
-- everyone, EmoteService); the menu's previews hold it on their silhouettes (EmotePreview).

local EmotePropBuilder = {}

--- The prop `key` of Config.EmoteMenu.Props welded to `character`'s hand and parented to it,
--- or nil when there is no such prop or hand.
function EmotePropBuilder.build(
	props: { [string]: any },
	key: string?,
	character: Model?
): BasePart?
	local spec = if key then props[key] else nil
	local hand = character and spec and character:FindFirstChild(spec.Hand)
	if not spec or not character or not hand or not hand:IsA("BasePart") then
		return nil
	end
	local part = Instance.new("Part")
	part.Name = "EmoteProp"
	part.Size = Vector3.new(spec.Size[1], spec.Size[2], spec.Size[3])
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = spec.MeshId
	mesh.TextureId = spec.TextureId
	mesh.Parent = part
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = part
	weld.C0 = CFrame.new(spec.Offset[1], spec.Offset[2], spec.Offset[3])
		* CFrame.Angles(math.rad(spec.Turn[1]), math.rad(spec.Turn[2]), math.rad(spec.Turn[3]))
	weld.Parent = part
	part.CFrame = hand.CFrame * weld.C0
	part.Parent = character
	return part
end

return EmotePropBuilder
