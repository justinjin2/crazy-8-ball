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
	-- { Asset = <model id>, Name = <template name>, Tint = Color3? (the pack particles; nil keeps
	--   white), Scroll = <image>? (a moving texture on every face of the frame, tagged for
	--   LuckyWorld), Extra = { <emitter> }? (more particles on the VFX attachment) },
	{ Asset = 137008354368931, Name = "StandardBlock" }, -- v3: yellow rims, beige faces
	{
		Asset = 131944205075030, -- v3: thinner flush rims
		Name = "MysteryBlock",
		Scroll = "RAINBOW", -- textures/rainbow_scroll.png
		Extra = { "RainbowTwinkles" },
	},
}
local IMAGES = {
	RAINBOW = "rbxassetid://107891048379160", -- rainbow_scroll.png (decal 121880113191370)
}
local SCROLL_TAG = "LuckyScroll" -- Config.LuckyBlocks.Look.Scroll.Tag
local TWINKLE = "rbxassetid://93784382803534" -- the cue skins' white twinkle (Config, Sparkle)
local function rainbowSequence(): ColorSequence
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 0.75, 1)))
	end
	return ColorSequence.new(keys)
end
-- Extra emitters by name: our own particles, added to the pack's glow set.
local EMITTERS = {
	-- A few small rainbow twinkles drifting up off the block (the Mystery block).
	RainbowTwinkles = function(): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Name = "RainbowTwinkles"
		e.Texture = TWINKLE
		e.Color = rainbowSequence()
		e.Rate = 4
		e.Lifetime = NumberRange.new(1.2, 1.8)
		e.Speed = NumberRange.new(0.6, 1.2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.Acceleration = Vector3.new(0, 0.8, 0)
		e.LightEmission = 0.8
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		return e
	end,
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
	-- On the frame part, so a Box emitter spawns over the block's surface, not inside it.
	local frame = model:FindFirstChild("Frame")
	for _, name in b.Extra or {} do
		EMITTERS[name]().Parent = frame or root
	end
	if b.Scroll and frame then
		for _, face in Enum.NormalId:GetEnumItems() do
			local t = Instance.new("Texture")
			t.Name = "Scroll" .. face.Name
			t.Face = face
			t.Texture = IMAGES[b.Scroll]
			t.StudsPerTileU = 6
			t.StudsPerTileV = 6
			t.Parent = frame
			t:AddTag(SCROLL_TAG)
		end
	end
	local old = folder:FindFirstChild(b.Name)
	if old then
		old:Destroy()
	end
	model.Parent = folder
	table.insert(report, ("%s: %d parts"):format(b.Name, #model:GetDescendants()))
end
return table.concat(report, "\n")
