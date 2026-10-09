--!strict
-- TutorialGlow: a pocket of the player's table glowing (docs/prompts/TUTORIAL_V2_PROMPT.md 4.4:
-- the aim lesson's "the target pocket glows", and the combination's pocket). A see-through gold
-- neon disc over the hole at the cloth (a ball still drops through it) with a light, and a gold
-- ring round the pocket drawn on the tutorial's screen layer (over the dim, under the text) at
-- the pocket's spot, at least RingPx wide so a far pocket still shows; all pulsing. Only this
-- player sees it. Where the pocket is comes from TutorialAnchors.worldPoint (Main). Numbers in
-- Config.Tutorial.Glow.
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
local TutorialAnchors = require(script.Parent.TutorialAnchors)

local G = Config.Tutorial.Glow
local INCH = Config.Table.StudsPerInch

local TutorialGlow = {}
TutorialGlow.__index = TutorialGlow

export type Glow = typeof(setmetatable(
	{} :: {
		disc: Part?,
		light: PointLight?,
		ring: Frame,
		stroke: UIStroke,
		tableId: number,
		pocket: number,
		clock: number,
	},
	TutorialGlow
))

--- The glow, its ring on `gui` (the tutorial's screen layer).
function TutorialGlow.new(gui: ScreenGui): Glow
	local gold = Color3.fromRGB(G.Color[1], G.Color[2], G.Color[3])
	local ring = Instance.new("Frame")
	ring.Name = "PocketRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.ZIndex = 3 -- over the dim (1) and its hole ring (2), under the line (5)
	ring.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = gold
	stroke.Thickness = G.RingThicknessPx
	stroke.Parent = ring
	return setmetatable({
		disc = nil,
		light = nil,
		ring = ring,
		stroke = stroke,
		tableId = 0,
		pocket = 0,
		clock = 0,
	}, TutorialGlow)
end

-- The disc and its light, made once.
local function discOf(self: Glow): Part
	local disc = self.disc
	if disc then
		return disc
	end
	local gold = Color3.fromRGB(G.Color[1], G.Color[2], G.Color[3])
	local part = Instance.new("Part")
	part.Name = "TutorialPocketGlow"
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = gold
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = gold
	light.Range = G.LightRange
	light.Shadows = false
	light.Parent = part
	self.disc, self.light = part, light
	return part
end

--- Where the glowing pocket is (world), nil when none glows.
function TutorialGlow.point(self: Glow): Vector3?
	if self.tableId == 0 or self.pocket == 0 then
		return nil
	end
	return TutorialAnchors.worldPoint(self.tableId, "pocket", self.pocket)
end

--- Glows pocket `pocket` of table `tableId` (0 or nil: none).
function TutorialGlow.show(self: Glow, tableId: number?, pocket: number?)
	self.tableId, self.pocket = tableId or 0, pocket or 0
	if self.tableId == 0 or self.pocket == 0 then
		self:hide()
	end
end

function TutorialGlow.hide(self: Glow)
	self.tableId, self.pocket = 0, 0
	if self.disc then
		self.disc.Parent = nil
	end
	self.ring.Visible = false
end

--- Every frame: follows the pocket and pulses.
function TutorialGlow.update(self: Glow, dt: number)
	if self.tableId == 0 or self.pocket == 0 then
		return
	end
	self.clock += dt
	local at = self:point()
	local disc = discOf(self)
	local camera = workspace.CurrentCamera
	if at == nil or camera == nil then
		disc.Parent = nil
		self.ring.Visible = false
		return
	end
	local width = G.DiameterInches * INCH
	disc.Size = Vector3.new(G.ThickInches * INCH, width, width)
	-- A cylinder's axis is its X: turned upright, at the cloth.
	disc.CFrame = CFrame.new(at + Vector3.new(0, G.LiftInches * INCH, 0))
		* CFrame.Angles(0, 0, math.pi / 2)
	local wave = (1 + math.sin(self.clock * 2 * math.pi / G.PulseSeconds)) / 2
	disc.Transparency = G.TransparencyMax + (G.TransparencyMin - G.TransparencyMax) * wave
	if self.light then
		self.light.Brightness = G.LightBrightness * (0.5 + 0.5 * wave)
	end
	disc.Parent = workspace
	-- The ring: on screen where the pocket is, RingScale times as wide as the disc looks or
	-- RingPx, whichever is wider.
	local centre, onScreen = camera:WorldToViewportPoint(at)
	if not onScreen then
		self.ring.Visible = false
		return
	end
	local edge = camera:WorldToViewportPoint(at + camera.CFrame.RightVector * width / 2)
	local looks = 2 * (Vector2.new(edge.X, edge.Y) - Vector2.new(centre.X, centre.Y)).Magnitude
	local size = math.max(G.RingPx, looks * G.RingScale) * (1 + G.RingPulse * wave)
	self.ring.Position = UDim2.fromOffset(centre.X, centre.Y)
	self.ring.Size = UDim2.fromOffset(size, size)
	self.stroke.Transparency = G.RingTransparency * (1 - wave)
	self.ring.Visible = true
end

return TutorialGlow
