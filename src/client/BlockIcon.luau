--!strict
-- BlockIcon: a lucky block's picture for a GUI (the shop's block cards, rewards, trades; the
-- hotbar draws its own). A kind with an Icon (its glossy 2D art, Config.LuckyBlocks.Kinds)
-- shows that, bobbing gently; else a slowly turning 3D picture in a ViewportFrame lit the way
-- the hotbar lit its icons (Config.LuckyBlocks.UI). A kind whose model is not in the place yet (a pack block still to
-- be imported) shows its kit icon instead (Config.UI.Shop.Page.Block.Fallback), so the shop
-- never shows an empty square. `pop` makes the block grow a little and settle (an idle pop).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LuckyBlocks = require(Shared:WaitForChild("Progression"):WaitForChild("LuckyBlocks"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)

local L = Config.LuckyBlocks
local U = L.UI
local B = Config.UI.Shop.Page.Block
local FALLBACK: { [string]: string } = B.Fallback :: any

local BlockIcon = {}

export type Icon = {
	root: Frame,
	viewport: ViewportFrame,
	model: Model?,
	base: CFrame,
	fallback: ImageLabel?,
	kind: string,
	turn: UIAnim.Handle?,
	aura: UIAnim.Handle?, -- a Rainbow kind's cycling glow
	pop: (self: Icon) -> (),
	destroy: (self: Icon) -> (),
}

--- The kit icon a kind shows while its model is missing (the hotbar and bag use it too).
function BlockIcon.fallbackKey(kind: string): string
	local key = FALLBACK[kind]
	local icons: { [string]: string } = Config.UI.Kit.Icons :: any
	if key and icons[key] and icons[key] ~= "" then
		return key
	end
	return B.FallbackDefault
end
local fallbackKey = BlockIcon.fallbackKey

--- The cycling pastel aura behind a Rainbow kind's icon (Config.LuckyBlocks.UI.RainbowAura):
--- a soft glow under `parent`'s other children, its colour drifting round the palette.
--- Returns the loop's handle (stop it with the icon).
function BlockIcon.aura(parent: GuiObject, zIndex: number): UIAnim.Handle
	local A = U.RainbowAura
	local glow = HudParts.icon(parent, "SoftGlow", "Aura")
	glow.Image = Config.UI.Kit.Art.SoftGlow -- (an Art image, not a kit icon)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(A.Reach, A.Reach)
	glow.ImageTransparency = A.Transparency
	glow.ZIndex = zIndex
	local colors: { Color3 } = {}
	for _, c in A.Colors :: { { number } } do
		table.insert(colors, Color3.fromRGB(c[1], c[2], c[3]))
	end
	local n = #colors
	local loop = UIAnim.loop(glow, function(clock)
		local at = (clock / A.Seconds) % 1 * n
		local i = math.floor(at)
		local a = colors[i + 1]
		local b = colors[(i + 1) % n + 1]
		glow.ImageColor3 = a:Lerp(b, at - i)
	end)
	return {
		stop = function()
			loop.stop()
			glow:Destroy()
		end,
	}
end

--- A block icon of `kind` filling `parent` (size the parent; the icon fills it). `still`
--- (an odds row's small block) does not turn: it holds a three-quarter view.
function BlockIcon.new(parent: Instance, kind: string, still: boolean?): Icon
	local root = HudParts.frame(parent, "BlockIcon")
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 3
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.LightDirection = Vector3.new(table.unpack(U.IconLightDirection))
	viewport.ZIndex = 3
	viewport.Parent = root
	local camera = Instance.new("Camera")
	camera.FieldOfView = U.IconFieldOfView
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local row = LuckyBlocks.kind(kind)
	local ambient = if row and row.IconAmbient then row.IconAmbient else U.IconAmbient
	local light = if row and row.IconLight then row.IconLight else U.IconLight
	viewport.Ambient = Color3.new(ambient, ambient, ambient)
	viewport.LightColor = Color3.new(light, light, light)

	local icon: Icon = {
		root = root,
		viewport = viewport,
		model = nil,
		base = CFrame.identity,
		fallback = nil,
		kind = kind,
		turn = nil,
		aura = nil,
		pop = BlockIcon.pop,
		destroy = BlockIcon.destroy,
	}
	if row and row.Rainbow == true and not still then
		icon.aura = BlockIcon.aura(root, 2)
	end
	if row and row.Icon and row.Icon ~= "" then
		viewport.Visible = false
		local picture = Instance.new("ImageLabel")
		picture.Name = "Picture"
		picture.BackgroundTransparency = 1
		picture.Image = row.Icon
		picture.AnchorPoint = Vector2.new(0.5, 0.5)
		picture.Position = UDim2.fromScale(0.5, 0.5)
		picture.Size = UDim2.fromScale(1, 1)
		picture.ScaleType = Enum.ScaleType.Fit
		picture.ZIndex = 3
		picture.Parent = root
		icon.fallback = picture
		if not still then
			icon.turn = UIAnim.bob(picture)
		end
		return icon
	end
	local folder = ReplicatedStorage:FindFirstChild(L.ModelFolder)
	local source = if row and folder then folder:FindFirstChild(row.Model) else nil
	if source and source:IsA("Model") then
		local model = source:Clone()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d:FindFirstChildOfClass("SurfaceAppearance") then
				-- The pack's grey base bleeds through its Overlay colour map (a part-built
				-- block, the Lucky 8, keeps its own colours).
				d.Color = Color3.new(1, 1, 1)
			elseif d:IsA("SurfaceAppearance") then
				d.EmissiveStrength = if row and row.EmissiveStrength
					then row.EmissiveStrength
					else L.Look.EmissiveStrength
			end
			if
				d:IsA("ParticleEmitter")
				or d:IsA("Light")
				or d:IsA("AnimationController")
				or d:IsA("LuaSourceContainer")
			then
				d:Destroy()
			end
		end
		-- The block's box centred on the origin (the pivot may sit off its middle: wings, a
		-- crown), the camera a little above, looking at the middle.
		model:PivotTo(CFrame.identity)
		local box, size = model:GetBoundingBox()
		model:PivotTo(CFrame.new(-box.Position))
		local edge = math.max(size.X, size.Y, size.Z)
		model.Parent = viewport
		icon.model = model
		icon.base = model:GetPivot()
		local distance = edge * U.IconDistance / (if row then row.IconScale or 1 else 1)
		camera.CFrame =
			CFrame.lookAt(Vector3.new(0, edge * U.IconAboveShare, distance), Vector3.zero)
		-- Turns go round the box's middle (the origin), not the pivot.
		if still then
			model:PivotTo(CFrame.Angles(0, math.rad(B.IconYawDegrees), 0) * icon.base)
		else
			-- A slow turn (only while on screen).
			icon.turn = UIAnim.loop(viewport, function(clock)
				local angle = math.rad(clock * U.IconTurnDegreesPerSecond)
				model:PivotTo(CFrame.Angles(0, angle, 0) * icon.base)
			end)
		end
	else
		viewport.Visible = false
		local image = HudParts.icon(root, fallbackKey(kind), "Fallback")
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(1, 1)
		image.ScaleType = Enum.ScaleType.Fit
		image.ZIndex = 3
		icon.fallback = image
		if not still then
			icon.turn = UIAnim.bob(image)
		end
	end
	return icon
end

--- A little pop: the block grows to Config.UI.Shop.Page.IconPop.Scale and settles.
function BlockIcon.pop(icon: Icon)
	local scale = UIAnim.scaleOf(icon.root)
	scale.Scale = Config.UI.Shop.Page.IconPop.Scale
	TweenService:Create(
		scale,
		TweenInfo.new(
			Config.UI.Kit.Motion.PopSeconds,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		),
		{ Scale = 1 }
	):Play()
end

function BlockIcon.destroy(icon: Icon)
	if icon.turn then
		icon.turn.stop()
		icon.turn = nil
	end
	if icon.aura then
		icon.aura.stop()
		icon.aura = nil
	end
	icon.root:Destroy()
end

return BlockIcon
