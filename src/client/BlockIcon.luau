--!strict
-- BlockIcon: a slowly turning 3D picture of a lucky block for a GUI (the shop's block cards;
-- the hotbar draws its own), in a ViewportFrame lit the way the hotbar lights its icons
-- (Config.LuckyBlocks.UI). A kind whose model is not in the place yet (a pack block still to
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
	pop: (self: Icon) -> (),
	destroy: (self: Icon) -> (),
}

-- The kit icon a kind shows while its model is missing.
local function fallbackKey(kind: string): string
	local key = FALLBACK[kind]
	local icons: { [string]: string } = Config.UI.Kit.Icons :: any
	if key and icons[key] and icons[key] ~= "" then
		return key
	end
	return "Case"
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
		pop = BlockIcon.pop,
		destroy = BlockIcon.destroy,
	}
	local folder = ReplicatedStorage:FindFirstChild(L.ModelFolder)
	local source = if row and folder then folder:FindFirstChild(row.Model) else nil
	if source and source:IsA("Model") then
		local model = source:Clone()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = Color3.new(1, 1, 1) -- the pack's grey base bleeds through its map
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
		local _, size = model:GetBoundingBox()
		local edge = math.max(size.X, size.Y, size.Z)
		model:PivotTo(CFrame.new(0, -edge / 2, 0))
		model.Parent = viewport
		icon.model = model
		icon.base = model:GetPivot()
		local distance = edge * U.IconDistance / (if row then row.IconScale or 1 else 1)
		camera.CFrame = CFrame.lookAt(Vector3.new(0, edge * 0.55, distance), Vector3.new(0, 0, 0))
		if still then
			model:PivotTo(icon.base * CFrame.Angles(0, math.rad(B.IconYawDegrees), 0))
		else
			-- A slow turn (only while on screen).
			icon.turn = UIAnim.loop(viewport, function(clock)
				local angle = math.rad(clock * U.IconTurnDegreesPerSecond)
				model:PivotTo(icon.base * CFrame.Angles(0, angle, 0))
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
	icon.root:Destroy()
end

return BlockIcon
