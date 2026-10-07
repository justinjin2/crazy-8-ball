-- Turns an uploaded lucky block model (tools/luckyblock_build.py's glb) into its template in
-- ReplicatedStorage.LuckyBlocks (designer, 2026-10-07). An Edit-mode command, not a script: paste
-- it into the Studio MCP's execute_luau (Edit) after setting BLOCKS below. Every SurfaceAppearance
-- map can only be set in Edit (docs/STUDIO_NOTES.md), so the templates live in the place: save and
-- publish after a run.
--
-- Each MeshPart's colour map is the image the glb upload made (its TextureID), moved into a
-- SurfaceAppearance with a roughness map (the gloss) and the white emissive mask every block
-- uses (assets/luckyblocks/Readme.md, "Rooftop look"). The pack's glow particles and light (from
-- YellowLuckyBlock) go on the RootPart, tinted per kind.

local BLOCKS = {
	-- { Asset = <model id>, Name = <template name>, Tint = Color3? (the particles; nil keeps white) },
	{ Asset = 132245263388441, Name = "StandardBlock" },
	{ Asset = 72158769287664, Name = "MysteryBlock" },
}
local ROUGH = {
	Glossy = "rbxassetid://98760410664616", -- rough_022.png
	Satin = "rbxassetid://120409166438752", -- rough_045.png
}
local PIECE_ROUGH = { Frame = "Glossy", Core = "Glossy", Glyph = "Satin" }
local EMISSIVE_MASK = "rbxassetid://104192408636466" -- textures/neutral_mask.png

local IS = game:GetService("InsertService")
local folder = game.ReplicatedStorage.LuckyBlocks
local vfxSource = folder.YellowLuckyBlock:FindFirstChild("VFX", true)

local report = {}
for _, b in BLOCKS do
	local model = IS:LoadAsset(b.Asset):FindFirstChildOfClass("Model")
	model.Name = b.Name
	local poses = model:FindFirstChild("InitialPoses")
	if poses then
		poses:Destroy()
	end
	local root = model:FindFirstChild("RootPart")
	root.Transparency = 1
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CanCollide = false
	model.PrimaryPart = root
	for _, part in model:GetChildren() do
		if part:IsA("MeshPart") then
			part.Name = part.Name:gsub("%.%d+$", "") -- Blender's "Glyph.001"
			local sa = Instance.new("SurfaceAppearance")
			sa.ColorMapContent = Content.fromUri(part.TextureID)
			sa.RoughnessMapContent = Content.fromUri(ROUGH[PIECE_ROUGH[part.Name] or "Glossy"])
			sa.EmissiveMaskContent = Content.fromUri(EMISSIVE_MASK)
			sa.EmissiveTint = Color3.new(1, 1, 1)
			sa.AlphaMode = Enum.AlphaMode.Overlay
			sa.Parent = part
			part.TextureID = ""
			part.Color = Color3.new(1, 1, 1)
			part.CanCollide = false
		end
	end
	local controller = model:FindFirstChildOfClass("AnimationController")
		or Instance.new("AnimationController", model)
	if not controller:FindFirstChildOfClass("Animator") then
		Instance.new("Animator", controller)
	end
	-- The pivot at the bottom centre, as the pack's blocks (the game sets blocks down by it).
	local box, size = model:GetBoundingBox()
	root.PivotOffset = CFrame.new(root.CFrame:PointToObjectSpace(box.Position - Vector3.new(0, size.Y / 2, 0)))
	local vfx = vfxSource:Clone()
	vfx.Position = Vector3.zero
	if b.Tint then
		for _, d in vfx:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				d.Color = ColorSequence.new(b.Tint)
			elseif d:IsA("Light") then
				d.Color = b.Tint
			end
		end
	end
	vfx.Parent = root
	local old = folder:FindFirstChild(b.Name)
	if old then
		old:Destroy()
	end
	model.Parent = folder
	table.insert(report, ("%s: %d parts"):format(b.Name, #model:GetDescendants()))
end
return table.concat(report, "\n")
