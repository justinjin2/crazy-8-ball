--!strict
-- Guideline: the aim trace on the table, in the style of the classic phone pool games.
--   * a corridor one ball wide from the cue ball to the first contact: two thin solid edge
--     lines a ball radius either side of the aim, with a faint dashed centre line whose
--     dashes scroll towards the target so the direction is obvious
--   * a white ring outline where the cue ball will be at first contact (the "ghost" ball)
--   * thin solid lines for where the object ball goes and where the cue ball deflects

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local Aim = require(Shared:WaitForChild("Physics"):WaitForChild("Aim"))

type Trace = Aim.Trace

local Guideline = {}
Guideline.__index = Guideline

type Strip = { part: Part, texture: Texture? }

export type Guideline = typeof(setmetatable(
	{} :: {
		folder: Folder,
		ring: Part,
		path: Strip,
		leftEdge: Strip,
		rightEdge: Strip,
		objectStub: Strip,
		cueStub: Strip,
		scroll: number,
	},
	Guideline
))

local function lineColor(): Color3
	local c = Config.Guideline.Color
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function flatPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = lineColor()
	part.Transparency = 1
	part.Size = Vector3.new(0.05, 0.01, 1)
	part.Parent = parent
	return part
end

local function makeStrip(name: string, parent: Instance, dashed: boolean): Strip
	local G = Config.Guideline
	local part = flatPart(name, parent)
	local texture: Texture? = nil
	if dashed and G.DashTextureId ~= "" then
		local tex = Instance.new("Texture")
		tex.Name = "Dashes"
		tex.Face = Enum.NormalId.Top
		tex.Texture = G.DashTextureId
		tex.Color3 = lineColor()
		tex.Transparency = 1
		tex.StudsPerTileU = G.LineWidthStuds
		tex.StudsPerTileV = G.DashTileStuds
		tex.Parent = part
		texture = tex
	end
	return { part = part, texture = texture }
end

function Guideline.new(parent: Instance): Guideline
	local G = Config.Guideline
	local folder = Instance.new("Folder")
	folder.Name = "Guideline"
	folder.Parent = parent

	-- Ring: a flat square carrying the circle-outline image, sized to the ball.
	local ring = flatPart("Ring", folder)
	local d = TableBuilder.studs(Config.Balls.RadiusInches * 2) * G.RingScale
	ring.Size = Vector3.new(d, 0.01, d)
	if G.RingTextureId ~= "" then
		local decal = Instance.new("Decal")
		decal.Name = "Outline"
		decal.Face = Enum.NormalId.Top
		decal.Texture = G.RingTextureId
		decal.Color3 = lineColor()
		decal.Transparency = 1
		decal.Parent = ring
	end

	local self = setmetatable({
		folder = folder,
		ring = ring,
		path = makeStrip("Path", folder, true),
		leftEdge = makeStrip("LeftEdge", folder, false),
		rightEdge = makeStrip("RightEdge", folder, false),
		objectStub = makeStrip("ObjectStub", folder, false),
		cueStub = makeStrip("CueStub", folder, false),
		scroll = 0,
	}, Guideline)
	return self
end

local function hideStrip(strip: Strip)
	strip.part.Transparency = 1
	if strip.texture then
		strip.texture.Transparency = 1
	end
end

-- Lay a strip flat from (x1, y1) to (x2, y2) in inches. Local +Z runs start -> target so
-- the dash texture's V axis follows the line.
local function placeStrip(
	strip: Strip,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	transparency: number,
	width: number?
)
	local G = Config.Guideline
	local h = G.HeightAboveClothInches
	local a = TableBuilder.toWorld(x1, y1, h)
	local b = TableBuilder.toWorld(x2, y2, h)
	local len = (b - a).Magnitude
	if len < 1e-4 then
		hideStrip(strip)
		return
	end
	strip.part.Size = Vector3.new(width or G.LineWidthStuds, 0.01, len)
	strip.part.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi, 0)
	if strip.texture then
		strip.part.Transparency = 1
		strip.texture.Transparency = transparency
	else
		strip.part.Transparency = transparency
	end
end

function Guideline.show(self: Guideline, trace: Trace)
	if trace.contact == "none" then
		self:hide()
		return
	end
	local G = Config.Guideline
	local R = Config.Balls.RadiusInches
	local ringR = R * G.RingScale
	local stub = G.StubLengthInches

	-- Corridor from the cue ball to the ghost ball: edges a ball radius either side of the
	-- aim line, running from under the cue ball to the sides of the ring; the dashed centre
	-- line runs from the cue ball's front edge to the ring's near edge.
	local dx, dy = trace.ghostX - trace.startX, trace.ghostY - trace.startY
	local len = math.sqrt(dx * dx + dy * dy)
	if len > R + ringR then
		local ux, uy = dx / len, dy / len
		local px, py = -uy, ux -- perpendicular to the aim
		local function placeEdge(strip: Strip, sgn: number)
			placeStrip(
				strip,
				trace.startX + px * R * sgn,
				trace.startY + py * R * sgn,
				trace.ghostX + px * R * sgn,
				trace.ghostY + py * R * sgn,
				G.EdgeTransparency,
				G.EdgeWidthStuds
			)
		end
		placeEdge(self.leftEdge, 1)
		placeEdge(self.rightEdge, -1)
		if G.ShowCentreLine then
			placeStrip(
				self.path,
				trace.startX + ux * R,
				trace.startY + uy * R,
				trace.ghostX - ux * ringR,
				trace.ghostY - uy * ringR,
				G.CentreLineTransparency
			)
		else
			hideStrip(self.path)
		end
	else
		hideStrip(self.path)
		hideStrip(self.leftEdge)
		hideStrip(self.rightEdge)
	end

	self.ring.CFrame =
		CFrame.new(TableBuilder.toWorld(trace.ghostX, trace.ghostY, G.HeightAboveClothInches))
	local outline = self.ring:FindFirstChild("Outline")
	if outline and outline:IsA("Decal") then
		outline.Transparency = G.LineTransparency
	else
		self.ring.Transparency = G.LineTransparency
	end

	-- Object ball direction: from the object ball's far edge outward.
	if trace.contact == "ball" then
		local ox, oy =
			trace.ghostX + trace.objectDirX * (ringR + 2 * R),
			trace.ghostY + trace.objectDirY * (ringR + 2 * R)
		placeStrip(
			self.objectStub,
			ox,
			oy,
			ox + trace.objectDirX * stub,
			oy + trace.objectDirY * stub,
			G.StubTransparency
		)
	else
		hideStrip(self.objectStub)
	end
	-- Cue ball deflection: from the ring's edge outward.
	local cx, cy = trace.ghostX + trace.cueDirX * ringR, trace.ghostY + trace.cueDirY * ringR
	placeStrip(
		self.cueStub,
		cx,
		cy,
		cx + trace.cueDirX * stub * G.CueStubScale,
		cy + trace.cueDirY * stub * G.CueStubScale,
		G.StubTransparency
	)
end

--- Scroll the dashes towards the target. Call every frame.
function Guideline.update(self: Guideline, dt: number)
	local G = Config.Guideline
	self.scroll = (self.scroll + dt * G.DashSpeed * G.DashTileStuds) % G.DashTileStuds
	local offset = if G.DashFlip then self.scroll else -self.scroll
	if self.path.texture then
		self.path.texture.OffsetStudsV = offset
	end
end

function Guideline.hide(self: Guideline)
	hideStrip(self.path)
	hideStrip(self.leftEdge)
	hideStrip(self.rightEdge)
	hideStrip(self.objectStub)
	hideStrip(self.cueStub)
	self.ring.Transparency = 1
	local outline = self.ring:FindFirstChild("Outline")
	if outline and outline:IsA("Decal") then
		outline.Transparency = 1
	end
end

return Guideline
