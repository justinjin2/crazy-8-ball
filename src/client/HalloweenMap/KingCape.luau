--!strict
-- KingCape (Halloween 2026, king lane): the Pumpkin King's cloth cape on this client
-- (Config.HalloweenMap.King.Cloth; designer, 2026-10-29: "too blocky and doesn't have regular
-- physics when he's shooting, should actually sway like a cape").
--
-- The server dresses every King body (the throne figure, each table King) with an anchor on
-- his UpperTorso (the Cloth.Anchor Attachment: the collar's middle, KingLook) and tags the body
-- Cloth.Tag. Here a throttled scan picks the nearest Cloth.MaxCapes of them within MaxStuds of
-- the camera, and each frame steps their cloth: a chain of Rows points hung from the collar
-- (verlet with follow-the-leader lengths: each point keeps its speed less Damping, falls with
-- Gravity, is blown by the Flare and a gentle Wind with each King's own phase, keeps the line
-- of the row above by Bend, and gives back FtlDamping of the pull the next row took, so it
-- never whips). Each point is pushed out of his torso and legs through their backs and kept
-- off the floor, or on his throne off the cushion and the pumpkin behind him (the anchor's
-- SeatY and WallZ attributes, in his root's space), so it drapes over his back when he bends
-- to shoot. Each row is two anchored parts (purple Fabric outside, the orange lining inside)
-- and a gold collar tops it: 17 parts a King, all moved with one BulkMoveTo.
--
-- Main's RenderStepped calls KingCape.step after the frame is drawn (WatchedShooters poses a
-- King at his table with AvatarPose's BulkMoveTo inside it, and the rise moves the throne in a
-- render step before it), so the cape hangs from where his torso is shown. A cape off screen
-- waits (its parts stay put); past MaxStuds it goes and its parts wait in the pool. Every
-- other frame on Lower effects (Quality); hanging still, no swing or wind, under Reduce Motion
-- (UIAnim.reduced). A step that errors puts the capes away for this session (warned once):
-- never the frame.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GuiQA = require(script.Parent.Parent:WaitForChild("GuiQA"))
local Quality = require(script.Parent.Parent:WaitForChild("Quality"))
local UIAnim = require(script.Parent.Parent:WaitForChild("UIAnim"))

local KL = Config.HalloweenMap.King
local C = KL.Cloth

local KingCape = {}

-- The body parts the cloth never passes through (each pushed out through its back, +Z).
local BODY =
	{ "UpperTorso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
local DOWN = Vector3.new(0, -1, 0)
local TAU = 2 * math.pi

type Set = { cloth: { BasePart }, lining: { BasePart }, collar: BasePart }

type Cape = {
	model: Model,
	torso: BasePart,
	root: BasePart,
	anchor: Attachment,
	boxes: { BasePart },
	set: Set,
	seg: number, -- each row's length
	thick: number, -- the cloth's thickness
	outside: CFrame, -- the cloth's and the lining's offsets from the chain (out, in)
	inside: CFrame,
	collarAt: CFrame,
	feet: number, -- his root's height over his feet (HipHeight and half the root)
	seatY: number?, -- his throne's cushion top and pumpkin front (root space), if seated
	wallZ: number?,
	pos: { Vector3 }, -- the chain, collar first
	vel: { Vector3 }, -- each point's move last step
	pull: { Vector3 }, -- this step's follow-the-leader correction per point
	prior: { Vector3 }, -- each point before this step
	phase: number, -- his own wind
	last: Vector3?, -- the collar last step (a jump hangs it afresh)
}

local tracked: { [Model]: boolean } = {}
local capes: { [Model]: Cape } = {}
local pool: { Set } = {}
local holder: Folder? = nil
local started = false
local broken = false
local frame = 0
local bank = 0
local sinceScan = math.huge
local parts: { BasePart } = {}
local frames: { CFrame } = {}
local random = Random.new()

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function part(name: string, colour: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Color = colour
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function folder(): Folder
	local f = holder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "KingCapes"
	made.Parent = Workspace
	holder = made
	return made
end

local function takeSet(): Set
	local set = table.remove(pool)
	if set then
		return set
	end
	local cloth: { BasePart }, lining: { BasePart } = {}, {}
	for i = 1, C.Rows do
		cloth[i] = part("Cape", rgb(KL.Cape), Enum.Material.Fabric)
		lining[i] = part("CapeLining", rgb(KL.Lining), Enum.Material.Fabric)
	end
	return {
		cloth = cloth,
		lining = lining,
		collar = part("CapeCollar", rgb(KL.Gold), Enum.Material.Metal),
	}
end

local function putSet(set: Set)
	for i = 1, C.Rows do
		set.cloth[i].Parent = nil
		set.lining[i].Parent = nil
	end
	set.collar.Parent = nil
	table.insert(pool, set)
end

local function drop(model: Instance)
	local c = capes[model :: Model]
	if c then
		capes[model :: Model] = nil
		putSet(c.set)
	end
end

-- Pushes `p` out of his body (through each part's back) and off the floor or his throne.
local function collide(c: Cape, p: Vector3): Vector3
	local m = C.Margin
	for _, box in c.boxes do
		local cf = box.CFrame
		local lp = cf:PointToObjectSpace(p)
		local half = box.Size * 0.5
		local back = half.Z + m
		if
			lp.Z < back
			and lp.Z > -half.Z - m
			and math.abs(lp.X) < half.X + m
			and math.abs(lp.Y) < half.Y + m
		then
			p = cf:PointToWorldSpace(Vector3.new(lp.X, lp.Y, back))
		end
	end
	local rootCF = c.root.CFrame
	local seatY, wallZ = c.seatY, c.wallZ
	if seatY and wallZ then
		local rp = rootCF:PointToObjectSpace(p)
		local y = math.max(rp.Y, seatY + m)
		local z = math.min(rp.Z, wallZ - m)
		if y ~= rp.Y or z ~= rp.Z then
			p = rootCF:PointToWorldSpace(Vector3.new(rp.X, y, z))
		end
	else
		local floor = rootCF.Position.Y - c.feet + m
		if p.Y < floor then
			p = Vector3.new(p.X, floor, p.Z)
		end
	end
	return p
end

-- The chain hung straight down from `top` (over his back and off his body), at rest.
local function hang(c: Cape, top: Vector3)
	c.pos[1] = top
	for i = 2, C.Rows + 1 do
		local above = c.pos[i - 1]
		local p = collide(c, above + DOWN * c.seg)
		local d = p - above
		local len = d.Magnitude
		c.pos[i] = if len > 1e-4 then above + d * (c.seg / len) else above + DOWN * c.seg
		c.vel[i] = Vector3.zero
	end
	c.last = top
end

-- One fixed step of the cloth (h seconds; `t` the wind's clock).
local function simulate(c: Cape, h: number, t: number, top: Vector3, cf: CFrame)
	local back, right, up = cf.ZVector, cf.XVector, cf.YVector
	local W = C.Wind
	local gust = 0.5 + 0.5 * math.sin(t * TAU * W.Hz + c.phase)
	local side = W.Side * math.sin(t * TAU * W.Hz * 0.7 + c.phase * 1.7)
	local acc = DOWN * C.Gravity + back * (C.Flare + W.Studs * gust) + right * side
	local push = acc * (h * h)
	local keep = 1 - C.Damping
	local pos, vel, pull, old = c.pos, c.vel, c.pull, c.prior
	pos[1] = top
	local n = C.Rows + 1
	for i = 2, n do
		old[i] = pos[i]
		local above = pos[i - 1]
		local p = pos[i] + vel[i] * keep + push
		-- each row keeps (Bend) the line of the one above (the first: down his back)
		local line = if i == 2 then -up else (above - pos[i - 2]).Unit
		p = p:Lerp(above + line * c.seg, C.Bend)
		p = collide(c, p)
		local d = p - above
		local len = d.Magnitude
		local fixed = if len > 1e-4 then above + d * (c.seg / len) else above - up * c.seg
		pull[i] = fixed - p
		pos[i] = fixed
	end
	for i = 2, n do
		local ahead = if i < n then pull[i + 1] else Vector3.zero
		vel[i] = (pos[i] - old[i]) - ahead * C.FtlDamping
	end
end

-- Appends the cape's parts and their CFrames for this frame from `from` on; the new count.
local function place(c: Cape, cf: CFrame, from: number): number
	local right, up = cf.XVector, cf.YVector
	local n = from
	for i = 1, C.Rows do
		local a, b = c.pos[i], c.pos[i + 1]
		local axis = a - b
		local len = axis.Magnitude
		local u = if len > 1e-5 then axis / len else up
		local r = right - u * right:Dot(u)
		local rl = r.Magnitude
		r = if rl > 1e-4 then r / rl else right
		local row = CFrame.fromMatrix((a + b) * 0.5, r, u)
		n += 1
		parts[n] = c.set.cloth[i]
		frames[n] = row * c.outside
		n += 1
		parts[n] = c.set.lining[i]
		frames[n] = row * c.inside
	end
	n += 1
	parts[n] = c.set.collar
	frames[n] = CFrame.fromMatrix(c.pos[1], right, up) * c.collarAt
	return n
end

local function build(model: Model, torso: BasePart, root: BasePart, anchor: Attachment)
	local s = torso.Size
	local seatY = anchor:GetAttribute("SeatY")
	local wallZ = anchor:GetAttribute("WallZ")
	local seated = type(seatY) == "number" and type(wallZ) == "number"
	local length = s.Y * (if seated then C.SeatedLength else C.Length)
	local seg = length / C.Rows
	local thick = s.Z * C.Thickness
	local set = takeSet()
	local parent = folder()
	for i = 1, C.Rows do
		local w = s.X * (C.TopWidth + (C.HemWidth - C.TopWidth) * (i - 0.5) / C.Rows)
		set.cloth[i].Size = Vector3.new(w, seg * (1 + C.Overlap), thick)
		set.lining[i].Size = Vector3.new(w * 0.97, seg * (1 + C.Overlap), thick * 0.5)
		set.cloth[i].Parent = parent
		set.lining[i].Parent = parent
	end
	local collarH = s.Y * 0.09
	set.collar.Size = Vector3.new(s.X * C.TopWidth + thick * 2, collarH, thick * 1.6)
	set.collar.Parent = parent
	local boxes = {}
	for _, name in BODY do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			table.insert(boxes, p)
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local c: Cape = {
		model = model,
		torso = torso,
		root = root,
		anchor = anchor,
		boxes = boxes,
		set = set,
		seg = seg,
		thick = thick,
		outside = CFrame.new(0, 0, thick * 0.4),
		inside = CFrame.new(0, 0, -thick * 0.35),
		collarAt = CFrame.new(0, -collarH * 0.3, thick * 0.4),
		feet = (if hum then hum.HipHeight else 2) + root.Size.Y / 2,
		seatY = if seated then seatY :: number else nil,
		wallZ = if seated then wallZ :: number else nil,
		pos = table.create(C.Rows + 1, anchor.WorldPosition),
		vel = table.create(C.Rows + 1, Vector3.zero),
		pull = table.create(C.Rows + 1, Vector3.zero),
		prior = table.create(C.Rows + 1, Vector3.zero),
		phase = random:NextNumber(0, TAU),
		last = nil,
	}
	hang(c, anchor.WorldPosition)
	capes[model] = c
end

-- The King's parts this cape needs, or nil while they have not streamed in.
local function partsOf(model: Model): (BasePart?, BasePart?, Attachment?)
	local torso = model:FindFirstChild("UpperTorso")
	local root = model:FindFirstChild("HumanoidRootPart")
	local anchor = torso and torso:FindFirstChild(C.Anchor)
	if
		torso
		and torso:IsA("BasePart")
		and root
		and root:IsA("BasePart")
		and anchor
		and anchor:IsA("Attachment")
		and torso:IsDescendantOf(Workspace)
	then
		return torso, root, anchor
	end
	return nil, nil, nil
end

-- The nearest Kings in range get a cape; the rest let theirs go.
local function scan()
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local eye = cam.CFrame.Position
	local near: { { model: Model, d: number } } = {}
	for model in tracked do
		if model.Parent == nil then
			tracked[model] = nil
			drop(model)
			continue
		end
		local torso = partsOf(model)
		local d = if torso then (torso.Position - eye).Magnitude else math.huge
		if d <= C.MaxStuds then
			table.insert(near, { model = model, d = d })
		end
	end
	table.sort(near, function(a, b)
		return a.d < b.d
	end)
	local want: { [Model]: boolean } = {}
	for i = 1, math.min(#near, C.MaxCapes) do
		want[near[i].model] = true
	end
	for model, c in capes do
		-- (a respawned or rebuilt torso gets a fresh cape)
		if not want[model] or c.torso.Parent ~= model or c.anchor.Parent ~= c.torso then
			drop(model)
		end
	end
	for model in want do
		if capes[model] == nil then
			local torso, root, anchor = partsOf(model)
			if torso and root and anchor then
				build(model, torso, root, anchor)
			end
		end
	end
end

-- Whether a point is on (or just off) the screen.
local function shown(cam: Camera, at: Vector3): boolean
	local v = cam:WorldToViewportPoint(at)
	if v.Z < 0 then
		return v.Z > -6 -- just behind the camera: its cloth may still reach into view
	end
	local size = cam.ViewportSize
	local m = size.Y * 0.3
	return v.X > -m and v.X < size.X + m and v.Y > -m and v.Y < size.Y + m
end

local function stepAll(dt: number)
	sinceScan += dt
	if sinceScan >= C.ScanSeconds then
		sinceScan = 0
		scan()
	end
	if next(capes) == nil then
		bank = 0
		return
	end
	frame += 1
	bank += math.min(dt, 0.25)
	if Quality.isLow() and frame % 2 == 1 then
		return -- every other frame (the cloth's steps catch up on the next)
	end
	local h = C.StepSeconds
	local steps = math.floor(bank / h)
	bank -= steps * h
	steps = math.min(steps, C.MaxSteps)
	local still = UIAnim.reduced()
	local cam = Workspace.CurrentCamera
	local t = os.clock()
	local n = 0
	for model, c in capes do
		if c.torso.Parent ~= model or c.root.Parent ~= model then
			drop(model)
			continue
		end
		local cf = c.torso.CFrame
		local top = c.anchor.WorldPosition
		if cam and not shown(cam, cf.Position) and not shown(cam, c.pos[C.Rows + 1]) then
			continue -- off screen: it waits
		end
		local last = c.last
		if still or last == nil or (top - last).Magnitude > C.JumpStuds then
			hang(c, top)
		else
			for k = 1, steps do
				simulate(c, h, t + (k - steps) * h, top, cf)
			end
			c.pos[1] = top
			c.last = top
		end
		n = place(c, cf, n)
	end
	for i = #parts, n + 1, -1 do
		parts[i] = nil
		frames[i] = nil
	end
	if n > 0 then
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

--- One frame of every cape in range (Main's RenderStepped, after the frame's poses). Does
--- nothing until KingCape.start, and almost nothing while no King is about.
function KingCape.step(dt: number)
	if not started or broken or next(tracked) == nil then
		return
	end
	local ok, err = pcall(function(): any
		stepAll(dt)
		return nil
	end)
	if not ok then
		broken = true
		warn("[HalloweenMap] the King's cape stopped: " .. tostring(err))
		for model in capes do
			drop(model)
		end
	end
end

--- Start following the King bodies (once, from MapClient; nothing with Cloth.Enabled off).
function KingCape.start()
	if started or not C.Enabled then
		return
	end
	started = true
	local function add(inst: Instance)
		if inst:IsA("Model") then
			tracked[inst] = true
			sinceScan = math.huge -- looked at next frame
		end
	end
	CollectionService:GetInstanceAddedSignal(C.Tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(C.Tag):Connect(function(inst: Instance)
		tracked[inst :: Model] = nil
		drop(inst)
	end)
	for _, inst in CollectionService:GetTagged(C.Tag) do
		add(inst)
	end
	-- Studio: PlayerScripts.GuiQA:Invoke("capes") -> what is drawn now.
	GuiQA.add("capes", function(): string
		local count, kings = 0, 0
		for _ in capes do
			count += 1
		end
		for _ in tracked do
			kings += 1
		end
		return ("%d capes drawn (%d parts) of %d King bodies tracked; pool %d%s"):format(
			count,
			count * (C.Rows * 2 + 1),
			kings,
			#pool,
			if broken then "; STOPPED by an error" else ""
		)
	end)
end

return KingCape
