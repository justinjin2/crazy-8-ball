--!strict
-- BallRenderer: keeps one part per ball and moves it to wherever the simulation says.
--
-- Rotation comes from the simulation's own angular velocity, never from how far the ball
-- moved. That distinction is the whole point: the physics models a SLIDING phase (spin and
-- velocity disagree, which is why a firmly struck cue ball skids before it rolls) and a
-- separate ROLLING phase. Deriving rotation from displacement draws every ball as if it
-- were rolling perfectly from the instant it left the cue, hides side spin completely, and
-- spins balls wildly as they drop into a pocket (the fall is displacement too).
--
-- Preferred look: a real sphere MeshPart (template copied to ReplicatedStorage.Assets by the
-- server) with one baked texture per ball (Config.Balls.Textures). Fallback when the template
-- or a texture is missing: a Ball Part, solids coloured, stripes white with a tinted band
-- decal on the four side faces, number decals front and back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local Ball = require(Shared:WaitForChild("Physics"):WaitForChild("Ball"))

local WHITE = Color3.fromRGB(245, 242, 232)

local BallRenderer = {}
BallRenderer.__index = BallRenderer

export type BallRenderer = typeof(setmetatable(
	{} :: {
		folder: Folder,
		placement: Placement.Placement,
		yaw: CFrame,
		parts: { [number]: BasePart },
		rotations: { [number]: CFrame },
		spinSteps: { [number]: number },
		sunk: { [number]: boolean },
		-- Balls on their way out of sight after reaching the bottom of a pocket: where they
		-- came to rest (table inches), which way the gutter runs, and how far along they are.
		sinking: { [number]: { x: number, y: number, dx: number, dy: number, t: number } },
		-- Balls that flew off the table, carried on to the floor (table inches, z from the
		-- resting height as in the physics) until they fade out.
		flying: { [number]: Flying },
		shadows: { [number]: Part },
	},
	BallRenderer
))

type Flying = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	t: number,
	landedAt: number?,
}

local function ballColor(id: number): Color3
	local colors = Config.Balls.Colors
	local rgb = colors[id]
	if rgb == nil and id >= 9 then
		rgb = colors[id - 8]
	end
	rgb = rgb or { 255, 255, 255 }
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function addDecal(part: Part, face: Enum.NormalId, texture: string, color: Color3?)
	local decal = Instance.new("Decal")
	decal.Face = face
	decal.Texture = texture
	if color then
		decal.Color3 = color
	end
	decal.Parent = part
end

function BallRenderer.new(parent: Instance, p: Placement.Placement, id: number): BallRenderer
	local folder = Instance.new("Folder")
	-- One folder per table, named by table id: twelve folders all called "Balls" would be
	-- unreadable in the explorer once the lounge is built.
	folder.Name = ("Balls_%02d"):format(id)
	folder.Parent = parent
	local self = setmetatable({
		folder = folder,
		placement = p,
		yaw = TableBuilder.yawCFrame(p),
		parts = {},
		rotations = {},
		spinSteps = {},
		sunk = {},
		sinking = {},
		flying = {},
		shadows = {},
	}, BallRenderer)
	return self
end

--- Point this renderer at a different table. The parts are kept and moved rather than
--- rebuilt: walking past a row of tables would otherwise destroy and recreate sixteen
--- MeshParts each time, which is exactly the hitch this pooling exists to avoid.
function BallRenderer.rebind(self: BallRenderer, p: Placement.Placement, id: number)
	self.placement = p
	self.yaw = TableBuilder.yawCFrame(p)
	self.folder.Name = ("Balls_%02d"):format(id)
	-- A ball must not carry the last table's tumble or its pocketed state across.
	for ballId in self.rotations do
		self.rotations[ballId] = CFrame.identity
		self.spinSteps[ballId] = 0
	end
	self.sunk = {}
	self.flying = {}
	for _, shadow in self.shadows do
		shadow.Transparency = 1
	end
end

-- The imported sphere mesh, if the place has it and the server published it.
local function meshTemplate(): MeshPart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild(Config.Balls.MeshTemplate)
	if template and template:IsA("MeshPart") then
		return template
	end
	return nil
end

function BallRenderer.ensure(self: BallRenderer, id: number): BasePart
	local existing = self.parts[id]
	if existing then
		return existing
	end
	local diameter = TableBuilder.studs(Config.Balls.RenderRadiusInches * 2)
	local textureId = Config.Balls.Textures[id] or ""
	local template = meshTemplate()
	if template and textureId ~= "" then
		local mesh = template:Clone()
		mesh.Name = if id == 0 then "CueBall" else ("Ball" .. id)
		mesh.Size = Vector3.new(diameter, diameter, diameter)
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CastShadow = true
		mesh.Material = (Enum.Material :: any)[Config.Look.BallMaterial]
		mesh.Reflectance = Config.Balls.Reflectance
		-- See Config.Balls.DoubleSided: this is what makes an inside-out mesh still show
		-- its near surface, and therefore still appear to roll the way it is travelling.
		mesh.DoubleSided = Config.Balls.DoubleSided
		mesh.Color = Color3.new(1, 1, 1)
		mesh.TextureID = textureId
		mesh.Transparency = 0
		mesh.Parent = self.folder
		self.parts[id] = mesh
		self.rotations[id] = CFrame.identity
		return mesh
	end
	local part = Instance.new("Part")
	part.Name = if id == 0 then "CueBall" else ("Ball" .. id)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = true
	part.Material = (Enum.Material :: any)[Config.Look.BallMaterial]
	part.Reflectance = Config.Balls.Reflectance

	local decals = Config.Balls.Decals
	local isStripe = id >= 9
	local color = ballColor(id)
	if isStripe and decals.StripeBand ~= "" then
		part.Color = WHITE
		for _, face in
			{ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
		do
			addDecal(part, face, decals.StripeBand, color)
		end
	else
		part.Color = color
	end
	local numberId = decals.Numbers[id]
	if id > 0 and numberId and numberId ~= "" then
		addDecal(part, Enum.NormalId.Front, numberId)
		addDecal(part, Enum.NormalId.Back, numberId)
	end

	part.Parent = self.folder
	self.parts[id] = part
	self.rotations[id] = CFrame.identity
	return part
end

--- Place ball `id` at physics coordinates (inches) without turning it. zIn is the height
--- relative to the cloth (negative while dropping into a pocket).
function BallRenderer.place(self: BallRenderer, id: number, xIn: number, yIn: number, zIn: number?)
	if self.sunk[id] then
		return
	end
	local part = self:ensure(id)
	local pos =
		TableBuilder.toWorld(self.placement, xIn, yIn, Config.Balls.RenderRadiusInches + (zIn or 0))
	part.CFrame = CFrame.new(pos) * self.rotations[id]
end

-- Thousands of CFrame multiplications drift off orthonormal, which shears the ball. Every
-- so often, rebuild the rotation from two re-squared axes.
local function renormalise(rot: CFrame): CFrame
	local right = rot.RightVector.Unit
	local up = rot.UpVector
	up = (up - right * up:Dot(right)).Unit
	return CFrame.fromMatrix(Vector3.zero, right, up)
end

-- The shadow disc under ball `id` at height z (inches above the cloth), or hidden.
local function shadowAt(self: BallRenderer, id: number, x: number, y: number, z: number)
	local S = Config.Effects.Shadow
	local shadow: Part? = self.shadows[id]
	if z < S.MinHeightInches then
		if shadow then
			shadow.Transparency = 1
		end
		return
	end
	if not shadow then
		local disc = Instance.new("Part")
		disc.Name = "Shadow" .. id
		disc.Shape = Enum.PartType.Cylinder
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanQuery = false
		disc.CanTouch = false
		disc.CastShadow = false
		disc.Material = Enum.Material.SmoothPlastic
		disc.Color = Color3.fromRGB(S.Color[1], S.Color[2], S.Color[3])
		disc.Parent = self.folder
		self.shadows[id] = disc
		shadow = disc
	end
	local disc = shadow :: Part
	local d = TableBuilder.studs(Config.Balls.RenderRadiusInches * 2) * (1 + S.GrowPerInch * z)
	disc.Size = Vector3.new(0.01, d, d)
	-- A cylinder's axis is its X: stand it up, just above the cloth.
	disc.CFrame = CFrame.new(TableBuilder.toWorld(self.placement, x, y, 0.02))
		* CFrame.Angles(0, 0, math.pi / 2)
	disc.Transparency = S.NearTransparency
		+ (1 - S.NearTransparency) * math.clamp(z / S.FadeHeightInches, 0, 1)
end

--- Move and turn ball `b` for a frame of `dt` seconds. The turn comes from the ball's
--- angular velocity, so a skidding ball barely rotates and a ball with side spin turns on
--- the spot, exactly as the simulation says.
function BallRenderer.step(self: BallRenderer, b: Ball.Ball, dt: number)
	if self.sunk[b.id] or self.sinking[b.id] or self.flying[b.id] then
		return
	end
	shadowAt(self, b.id, b.x, b.y, if b.pocketed then 0 else b.z)
	local part = self:ensure(b.id)
	local pos =
		TableBuilder.toWorld(self.placement, b.x, b.y, Config.Balls.RenderRadiusInches + b.z)
	local rot = self.rotations[b.id]
	-- Physics (x, y, z) maps to world (X, -Z, Y). That map is a proper rotation, so angular
	-- velocity (a pseudovector) transforms exactly like a vector; then the table's own yaw
	-- turns it the rest of the way into world space. Miss the yaw and every ball on a
	-- turned table rolls sideways.
	local w = self.yaw:VectorToWorldSpace(Vector3.new(b.wx, b.wz, -b.wy))
	local rate = w.Magnitude
	if rate > 1e-6 and dt > 0 then
		rot = CFrame.fromAxisAngle(w / rate, rate * dt) * rot
		local n = (self.spinSteps[b.id] or 0) + 1
		if n >= Config.Balls.RotationRenormaliseSteps then
			n = 0
			rot = renormalise(rot)
		end
		self.spinSteps[b.id] = n
		self.rotations[b.id] = rot
	end
	part.CFrame = CFrame.new(pos) * rot
end

local function setFade(part: BasePart, transparency: number)
	part.Transparency = transparency
	for _, child in part:GetChildren() do
		if child:IsA("Decal") then
			child.Transparency = transparency
		end
	end
end

--- A ball has reached the bottom of the physics drop at (x, y) table inches. Rather than
--- vanishing there, it keeps falling under real gravity - carrying on at the speed the drop
--- reached, drifting a touch outward the way a ball runs off into the gutter - and fades out
--- over Config.Effects.PocketFadeSeconds. Without a position it just hides.
function BallRenderer.sink(self: BallRenderer, id: number, x: number?, y: number?)
	if self.sunk[id] or self.sinking[id] then
		return
	end
	if x == nil or y == nil then
		self.sunk[id] = true
		setFade(self:ensure(id), 1)
		return
	end
	local length = math.sqrt(x * x + y * y)
	local dx, dy = if length > 1e-6 then x / length else 0, if length > 1e-6 then y / length else 1
	self.sinking[id] = { x = x, y = y, dx = dx, dy = dy, t = 0 }
end

--- Ball `b` has just flown off the table: carry it on along its flight, down past the rail
--- to the floor, a bounce, and out of sight. Cosmetic only; the physics has let it go.
function BallRenderer.flyOff(self: BallRenderer, b: Ball.Ball)
	if self.sunk[b.id] or self.sinking[b.id] or self.flying[b.id] then
		return
	end
	shadowAt(self, b.id, 0, 0, 0)
	self.flying[b.id] = { x = b.x, y = b.y, z = b.z, vx = b.vx, vy = b.vy, vz = b.vz, t = 0 }
end

--- Move the sinking and flying balls along. Call every frame, shot or no shot: a ball that
--- drops at the end of a shot is still on its way out after the replay has finished.
function BallRenderer.animate(self: BallRenderer, dt: number)
	local E = Config.Effects
	local g = Config.Physics.Gravity
	local T = Config.Table
	local R = Config.Balls.RadiusInches
	local floor = -T.SurfaceHeightInches
	-- The wooden rail's footprint: past the cushion line, out to the outer edge.
	local outerX = T.LengthInches / 2 + T.RailWidthInches
	local outerY = T.WidthInches / 2 + T.RailWidthInches
	for id, f in self.flying do
		f.t += dt
		f.x += f.vx * dt
		f.y += f.vy * dt
		if f.landedAt and f.z <= floor and math.abs(f.vz) < 1 then
			-- Rolling on the floor: it slows to a stop.
			local speed = math.sqrt(f.vx * f.vx + f.vy * f.vy)
			if speed > 0 then
				local slower = math.max(0, speed - E.FloorRollDecel * dt) / speed
				f.vx *= slower
				f.vy *= slower
			end
			f.z, f.vz = floor, 0
		else
			f.vz -= g * dt
			f.z += f.vz * dt
			local overRail = math.abs(f.x) < outerX and math.abs(f.y) < outerY
			if overRail and f.z > 0 and f.z < T.RailTopInches and f.vz < 0 then
				-- Came down on the rail top: skip off it and carry on over the edge.
				f.z = T.RailTopInches
				f.vz = -f.vz * E.FlyOffRailRestitution
			elseif f.z <= floor and f.vz < 0 then
				f.z = floor
				f.vz = -f.vz * E.FlyOffFloorRestitution
				f.landedAt = f.landedAt or f.t
			end
		end
		local part = self:ensure(id)
		-- Turn it the way it travels, as a rolling ball does.
		local w = self.yaw:VectorToWorldSpace(Vector3.new(-f.vy / R, 0, -f.vx / R))
		local rate = w.Magnitude
		if rate > 1e-6 then
			self.rotations[id] = CFrame.fromAxisAngle(w / rate, rate * dt) * self.rotations[id]
		end
		part.CFrame = CFrame.new(
			TableBuilder.toWorld(self.placement, f.x, f.y, Config.Balls.RenderRadiusInches + f.z)
		) * self.rotations[id]
		-- Seen landing and rolling for FlyOffRollSeconds, then gone.
		local fade = if f.landedAt
			then math.clamp((f.t - f.landedAt - E.FlyOffRollSeconds) / E.FlyOffFadeSeconds, 0, 1)
			else 0
		setFade(part, fade)
		if fade >= 1 or f.t >= E.FlyOffMaxSeconds then
			self.flying[id] = nil
			self.sunk[id] = true
			setFade(part, 1)
		end
	end
	for id, s in self.sinking do
		s.t += dt
		local part = self:ensure(id)
		local u = math.clamp(s.t / E.PocketFadeSeconds, 0, 1)
		-- Real gravity, continuing from the speed the physics drop reached at the bottom.
		local depth = Config.Table.PocketDropDepthInches
		local speed = math.sqrt(2 * g * depth)
		depth += speed * s.t + 0.5 * g * s.t * s.t
		local along = E.PocketDriftInchesPerSecond * s.t
		local pos = TableBuilder.toWorld(
			self.placement,
			s.x + s.dx * along,
			s.y + s.dy * along,
			Config.Balls.RenderRadiusInches - depth
		)
		-- Keep it turning the way it was rolling as it runs off.
		local w = self.yaw:VectorToWorldSpace(Vector3.new(-s.dy, 0, -s.dx))
		if w.Magnitude > 1e-6 then
			self.rotations[id] = CFrame.fromAxisAngle(w.Unit, E.PocketGutterSpin * dt)
				* self.rotations[id]
		end
		part.CFrame = CFrame.new(pos) * self.rotations[id]
		setFade(part, u)
		if u >= 1 then
			self.sinking[id] = nil
			self.sunk[id] = true
		end
	end
end

--- Bring a ball back onto the table (cue ball after a scratch, or a new rack). The ball
--- comes back upright: a fresh rack should not inherit the last game's tumbling.
function BallRenderer.restore(self: BallRenderer, id: number, xIn: number, yIn: number)
	local part = self:ensure(id)
	self.sunk[id] = nil
	self.sinking[id] = nil
	self.flying[id] = nil
	shadowAt(self, id, xIn, yIn, 0)
	self.rotations[id] = CFrame.identity
	self.spinSteps[id] = 0
	setFade(part, 0)
	self:place(id, xIn, yIn)
end

function BallRenderer.setVisible(self: BallRenderer, id: number, visible: boolean)
	local part = self:ensure(id)
	if visible then
		self.sunk[id] = nil
		self.sinking[id] = nil
		self.flying[id] = nil
		setFade(part, 0)
	elseif not self.sinking[id] and not self.flying[id] then
		-- A ball still rolling out of a pocket (or bouncing on the floor) finishes that on
		-- its own and ends hidden.
		self.sunk[id] = true
		setFade(part, 1)
		shadowAt(self, id, 0, 0, 0)
	end
end

return BallRenderer
