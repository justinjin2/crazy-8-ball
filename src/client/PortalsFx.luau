--!strict
-- PortalsFx: what Portals looks and sounds like (docs/prompts/ABILITIES_PROMPT.md 7.9,
-- reference 05). The teleports are physics (Ults/Effects/Portals); this only draws them, off
-- the pick and the replay's `ult` events, so everyone sees them together. Numbers in
-- Config.UI.PortalsFx, the sounds in Config.Ults.Audio (Portal*), the meshes in the uploaded
-- Portals model (tools/blender/abilities/portals.py: PortalRim, PortalCore, PortalDisc), the
-- sparkles and burst ring in Config.Ults.Assets.Images (Portal*).
--
--   * Where the portals are: the shooter's own spots while placing them in the pick view
--     (UltPick.onPortals; a pair the server would refuse turns the rims red), then for everyone
--     the confirmed pick (the snapshot's armed.pick), then the shot's own Pick while it plays,
--     and kept open between the shots of the rest of the shooter's turn (ults.kept).
--   * Each portal: a ragged glowing rim (A cyan, B violet-blue, turning opposite ways) round a
--     thin white-hot ring, a dark swirl turning inside, sparkles streaming in, a soft light on
--     the cloth and a warbling hum. They open with a spiral in, and collapse back the same way
--     once the shot is over.
--   * A ball going in (event "enter"): a copy of it shrinks and sinks into the portal with a
--     flash and a deep whoosh, the portal swells. Coming out ("exit"): a burst ring grows off the
--     exit, sparks and a pop.
-- Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or with
-- clear(). Without the model nothing is drawn but the sounds, bursts and sparks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local UltPick = require(script.Parent.UltPick)

local F = Config.UI.PortalsFx
local PK = Config.UI.UltPick
local A = Config.Ults.Audio
local IMAGES = Config.Ults.Assets.Images :: any

local EFFECT = "Portals"
local MODEL = "Portals"
local PIECES = { "PortalRim", "PortalCore", "PortalDisc" }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ballWidth(): number
	return Config.Balls.RenderRadiusInches * 2 * Config.Table.StudsPerInch
end

local function easeOut(u: number): number
	u = math.clamp(u, 0, 1)
	return 1 - (1 - u) * (1 - u)
end

type Meshes = { parts: { [string]: MeshPart }, sizes: { [string]: Vector3 } }

type Drawn = {
	rim: MeshPart,
	core: MeshPart,
	disc: MeshPart,
	sparkles: { MeshPart },
	halo: Part,
	haloDecal: Decal,
	at: Attachment,
	light: PointLight,
	spin: number,
	swirl: number,
	pulseAt: number, -- os.clock() of the last swell
}

type TableFx = {
	anchor: BasePart,
	portals: { Drawn },
	spots: { { number } }?, -- the two spots drawn now (inches)
	openAt: number?, -- os.clock() they opened
	closeAt: number?, -- os.clock() they began to close
	blocked: boolean,
	hum: Sound?,
	shotSeq: number,
	quiet: boolean,
}

export type PortalsFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	placing: { [number]: any }, -- UltPick's portals for the local shooter's table
	meshes: Meshes?,
	meshesFailed: boolean,
	nextMeshCheck: number,
}

local PortalsFx = {}
PortalsFx.__index = PortalsFx

local function meshesOf(self: PortalsFx): Meshes?
	if self.meshes or self.meshesFailed then
		return self.meshes
	end
	local now = os.clock()
	if now < self.nextMeshCheck then
		return nil
	end
	self.nextMeshCheck = now + F.ModelCheckSeconds
	local model = self.kit.models.tryGet(MODEL)
	if model == nil then
		return nil
	end
	local parts: { [string]: MeshPart } = {}
	local sizes: { [string]: Vector3 } = {}
	for _, name in PIECES do
		local part = model:FindFirstChild(name, true)
		if part == nil or not part:IsA("MeshPart") then
			self.meshesFailed = true
			warn(("[8ball] PortalsFx: the %s model has no %s"):format(MODEL, name))
			return nil
		end
		local mesh = part :: MeshPart
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CastShadow = false
		mesh.Transparency = 1
		parts[name] = mesh
		sizes[name] = mesh.Size
	end
	self.meshes = { parts = parts, sizes = sizes }
	return self.meshes
end

local function clone(self: PortalsFx, fx: TableFx, name: string): MeshPart
	local part = ((self.meshes :: Meshes).parts[name]):Clone()
	part.Parent = fx.anchor
	return part
end

local function newPortal(self: PortalsFx, id: number, fx: TableFx, index: number): Drawn?
	if meshesOf(self) == nil then
		return nil
	end
	local colour = rgb(if index == 1 then PK.PortalColorA else PK.PortalColorB)
	local rim = clone(self, fx, "PortalRim")
	rim.TextureID = ""
	rim.Material = Enum.Material.Neon
	rim.Color = colour
	local core = clone(self, fx, "PortalCore")
	core.TextureID = ""
	core.Material = Enum.Material.Neon
	core.Color = Color3.new(1, 1, 1)
	local disc = clone(self, fx, "PortalDisc")
	disc.Material = Enum.Material.SmoothPlastic
	disc.Color = rgb(F.DiscTint) -- darker than white: the portal's own light still lifts it
	local sparkles = {}
	for _ = 1, 2 do
		local layer = clone(self, fx, "PortalDisc")
		layer.TextureID = IMAGES.PortalSparkles
		layer.Material = Enum.Material.SmoothPlastic
		layer.Color = Color3.new(1, 1, 1)
		table.insert(sparkles, layer)
	end
	local halo = self.kit.part(id, "PortalHalo", { Size = Vector3.new(0.1, 0.02, 0.1) })
	local haloDecal = Instance.new("Decal")
	haloDecal.Face = Enum.NormalId.Top
	haloDecal.Texture = IMAGES.ChainGlow
	haloDecal.Color3 = colour
	haloDecal.Transparency = 1
	haloDecal.Parent = halo
	local at = self.kit.attachment(id, "PortalLight")
	local light = self.kit.light(at, {
		Color = colour,
		Brightness = 0,
		Range = ballWidth() * F.LightRangeBallWidths,
	})
	return {
		rim = rim,
		core = core,
		disc = disc,
		sparkles = sparkles,
		halo = halo,
		haloDecal = haloDecal,
		at = at,
		light = light,
		spin = 0,
		swirl = 0,
		pulseAt = -math.huge,
	}
end

local function dropPortal(p: Drawn)
	p.rim:Destroy()
	p.core:Destroy()
	p.disc:Destroy()
	for _, layer in p.sparkles do
		layer:Destroy()
	end
	p.halo:Destroy()
	p.at:Destroy()
end

local function stopHum(fx: TableFx)
	if fx.hum then
		local holder = fx.hum.Parent
		fx.hum:Destroy()
		if holder and holder:IsA("Attachment") then
			holder:Destroy()
		end
		fx.hum = nil
	end
end

local function create(self: PortalsFx, id: number): TableFx
	local fx: TableFx = {
		anchor = self.kit.anchor(id),
		portals = {},
		spots = nil,
		openAt = nil,
		closeAt = nil,
		blocked = false,
		hum = nil,
		shotSeq = 0,
		quiet = false,
	}
	self.tables[id] = fx
	return fx
end

local function destroy(self: PortalsFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	for _, p in fx.portals do
		dropPortal(p)
	end
	table.clear(fx.portals)
	stopHum(fx)
end

local function playAt(self: PortalsFx, id: number, clip: any, at: Vector3, opts: any?): Sound?
	local kit = self.kit
	local holder = kit.attachment(id, "PortalSound", at)
	local sound = kit.sound.library(clip, holder, opts)
	if not (opts and opts.looped) then
		kit.later(id, 4, function()
			holder:Destroy()
		end)
	end
	return sound
end

-- The two spots to draw at this table now (inches): the shooter's own while placing, the
-- confirmed pick while armed or kept for the turn, the shot's Pick while it plays. Also whether
-- the pair is refused.
local function wantedSpots(self: PortalsFx, id: number, m: any): ({ { number } }?, boolean, boolean)
	local kit = self.kit
	if kit.isShotOf(m, EFFECT) then
		local pick = m.state.overrides and m.state.overrides.Pick
		if type(pick) == "table" and #pick >= 4 then
			return { { pick[1], pick[2] }, { pick[3], pick[4] } }, false, true
		end
		return nil, false, true
	end
	local armed = kit.armedOf(self.hub.snapshots[id], EFFECT)
	local placing = if armed then self.placing[id] else nil -- stale once the ability is used
	if placing and (placing.a or placing.b) then
		local list = {}
		if placing.a then
			table.insert(list, { placing.a.x, placing.a.y })
		end
		if placing.b then
			table.insert(list, { placing.b.x, placing.b.y })
		end
		return list, placing.valid == false, false
	end
	if armed and not m:isBusy() and type(armed.pick) == "table" and #armed.pick >= 4 then
		local p = armed.pick
		return { { p[1], p[2] }, { p[3], p[4] } }, false, false
	end
	-- Kept open for the rest of the shooter's turn (the snapshot's ults.kept).
	local snapshot = self.hub.snapshots[id]
	local ults = if type(snapshot) == "table" then snapshot.ults else nil
	local kept = if type(ults) == "table" then ults.kept else nil
	if
		type(kept) == "table"
		and kept.id == "Portals"
		and not m:isBusy()
		and type(kept.pick) == "table"
		and #kept.pick >= 4
	then
		local p = kept.pick
		return { { p[1], p[2] }, { p[3], p[4] } }, false, false
	end
	return nil, false, false
end

-- The portal's world centre and its radius in studs.
local function where(self: PortalsFx, m: any, spot: { number }): Vector3
	return self.kit.tableWorld(m, spot[1], spot[2], F.LiftInches)
end

local function radius(): number
	return ballWidth() * PK.PortalRingBallWidths
end

-- A ball going into portal `k`: a copy of it shrinks and sinks, a flash, a whoosh, a swell.
local function enter(self: PortalsFx, id: number, fx: TableFx, m: any, ev: any)
	local kit = self.kit
	local k = ev.other
	local spot = fx.spots and fx.spots[k]
	if spot == nil then
		return
	end
	local centre = where(self, m, spot)
	local portal = fx.portals[k]
	if portal then
		portal.pulseAt = os.clock()
	end
	local part = kit.ballPart(id, ev.ball)
	if part then
		local ghost = (part :: BasePart):Clone()
		for _, child in ghost:GetChildren() do
			if not child:IsA("Decal") and not child:IsA("SpecialMesh") then
				child:Destroy()
			end
		end
		ghost.Name = "PortalSink"
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanQuery = false
		ghost.CanTouch = false
		ghost.CastShadow = false
		ghost.Parent = fx.anchor
		local size = ghost.Size
		local start = (part :: BasePart).CFrame
		local born = os.clock()
		local conn: RBXScriptConnection
		conn = game:GetService("RunService").RenderStepped:Connect(function()
			local u = (os.clock() - born) / F.SinkSeconds
			if u >= 1 or ghost.Parent == nil then
				conn:Disconnect()
				ghost:Destroy()
				return
			end
			local e = easeOut(u)
			ghost.Size = size * (1 - e * 0.95)
			ghost.CFrame = CFrame.new(
				start.Position:Lerp(centre - Vector3.yAxis * ballWidth() * 0.5 * e, e)
			) * start.Rotation * CFrame.Angles(0, e * math.pi * 2, 0)
		end)
		kit.later(id, F.SinkSeconds + 0.5, function()
			if conn.Connected then
				conn:Disconnect()
			end
			ghost:Destroy()
		end)
	end
	if fx.quiet then
		return
	end
	local colour = rgb(if k == 1 then PK.PortalColorA else PK.PortalColorB)
	kit.burstLight(
		centre + Vector3.yAxis * ballWidth() * 2,
		colour,
		ballWidth() * 6,
		F.FlashBrightness,
		F.FlashSeconds
	)
	playAt(self, id, A.PortalEnter, centre)
end

-- A ball coming out of portal `k`: the burst ring, sparks, a pop, a swell.
local function exit(self: PortalsFx, id: number, fx: TableFx, m: any, ev: any)
	local kit = self.kit
	local k = ev.other
	local spot = fx.spots and fx.spots[k]
	if spot == nil then
		return
	end
	local centre = where(self, m, spot)
	local portal = fx.portals[k]
	if portal then
		portal.pulseAt = os.clock()
	end
	local colour = rgb(if k == 1 then PK.PortalColorA else PK.PortalColorB)
	local r = radius()
	local ring = kit.part(id, "PortalBurst", {
		Size = Vector3.new(r * 2, 0.02, r * 2),
		CFrame = CFrame.new(centre + Vector3.yAxis * 0.01),
	})
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = IMAGES.PortalBurst
	decal.Color3 = colour:Lerp(Color3.new(1, 1, 1), 0.4)
	decal.Parent = ring
	local born = os.clock()
	local conn: RBXScriptConnection
	conn = game:GetService("RunService").RenderStepped:Connect(function()
		local u = (os.clock() - born) / F.BurstSeconds
		if u >= 1 or ring.Parent == nil then
			conn:Disconnect()
			ring:Destroy()
			return
		end
		local s = 1 + (F.BurstTo - 1) * easeOut(u)
		ring.Size = Vector3.new(r * 2 * s, 0.02, r * 2 * s)
		decal.Transparency = F.BurstTransparency + (1 - F.BurstTransparency) * u
	end)
	kit.later(id, F.BurstSeconds + 0.5, function()
		if conn.Connected then
			conn:Disconnect()
		end
		ring:Destroy()
	end)
	local holder = kit.attachment(id, "PortalSparks", centre + Vector3.yAxis * ballWidth() * 0.4)
	local e = kit.particles(holder, {
		Color = ColorSequence.new(Color3.new(1, 1, 1), colour),
		SpreadAngle = Vector2.new(70, 70),
		Speed = NumberRange.new(4, 9),
		Drag = 5,
		Acceleration = Vector3.new(0, -6, 0),
		EmissionDirection = Enum.NormalId.Top,
	})
	e:Emit(F.Sparks)
	kit.later(id, 1.2, function()
		holder:Destroy()
	end)
	if not fx.quiet then
		playAt(self, id, A.PortalExit, centre)
	end
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function PortalsFx.start(hub: any, _parent: Instance, kit: any): PortalsFx
	local self: PortalsFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		placing = {},
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
	}, PortalsFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			stopHum(fx)
		end
		self.tables[tableId] = nil -- its parts went with the anchor
	end)
	UltPick.onPortals(function(tableId: number, info: any)
		self.placing[tableId] = info
	end)
	kit.allEvents(function(tableId: number, m: any, ev: any, _index: number)
		if ev.type ~= "ult" or not kit.isShotOf(m, EFFECT) or m.renderer == nil then
			return
		end
		local fx = self.tables[tableId]
		if fx == nil or fx.shotSeq ~= m.seq then
			return -- the update below has not met this shot yet
		end
		if ev.kind == "enter" then
			enter(self, tableId, fx, m, ev)
		elseif ev.kind == "exit" then
			exit(self, tableId, fx, m, ev)
		end
	end)
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in { A.PortalHum, A.PortalEnter, A.PortalExit, A.PortalOpen, A.PortalClose } do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		for _, key in { "PortalSparkles", "PortalBurst" } do
			local decal = Instance.new("Decal")
			decal.Texture = IMAGES[key]
			table.insert(list, decal)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		for _, item in list do
			item:Destroy()
		end
	end)
	return self
end

--- Every frame, after the hub has stepped the replays.
function PortalsFx.update(self: PortalsFx, dt: number)
	local t = os.clock()
	for id, m in self.hub.matches do
		local fx = self.tables[id]
		if m.renderer == nil then
			if fx then
				destroy(self, id)
			end
			continue
		end
		local spots, blocked, shot = wantedSpots(self, id, m)
		if fx == nil then
			if spots == nil then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
			live.quiet = m.state.time > F.FreshSeconds
		end
		-- Open, follow the spots, or close.
		if spots then
			if live.openAt == nil or live.closeAt then
				live.openAt = t
				live.closeAt = nil
				if spots[1] and not live.quiet then
					playAt(self, id, A.PortalOpen, where(self, m, spots[1]))
				end
			end
			live.spots = spots
			live.blocked = blocked
		elseif live.openAt and live.closeAt == nil then
			live.closeAt = t
			if live.spots and live.spots[1] and not live.quiet then
				playAt(self, id, A.PortalClose, where(self, m, live.spots[1]))
			end
		end
		local open = 0
		if live.openAt then
			open = easeOut((t - live.openAt) / F.OpenSeconds)
		end
		if live.closeAt then
			local u = (t - live.closeAt) / F.CloseSeconds
			if u >= 1 then
				destroy(self, id)
				continue
			end
			open = math.min(open, 1 - easeOut(u))
		end
		-- Draw each portal.
		local list = live.spots or {}
		for k = 1, 2 do
			local spot = list[k]
			local portal: Drawn? = live.portals[k]
			if spot == nil then
				if portal then
					dropPortal(portal)
					live.portals[k] = nil
				end
				continue
			end
			if portal == nil then
				portal = newPortal(self, id, live, k)
				if portal == nil then
					continue
				end
				live.portals[k] = portal
			end
			local p = portal :: Drawn
			local dir = if k == 1 then 1 else -1
			local spinUp = (1 - open) * F.OpenTurns * math.pi * 2
			p.spin += math.rad(F.RimSpinDegrees) * dt * dir
			p.swirl += math.rad(F.SwirlSpinDegrees) * dt * dir
			local pulse = 1
			local since = t - p.pulseAt
			if since < F.PulseSeconds then
				pulse = 1 + (F.Pulse - 1) * math.sin(math.pi * since / F.PulseSeconds)
			end
			local r = radius() * open * pulse
			local centre = where(self, m, spot)
			local sizes = (self.meshes :: Meshes).sizes
			local turn = CFrame.Angles(0, p.spin + spinUp * dir, 0)
			local base = CFrame.new(centre)
			p.rim.Size = sizes.PortalRim * r
			p.rim.CFrame = base * turn
			p.core.Size = sizes.PortalCore * r
			p.core.CFrame = base * CFrame.Angles(0, -p.spin * 1.7 + spinUp * dir, 0)
			local discSize = sizes.PortalDisc * r
			p.disc.Size = Vector3.new(discSize.X, 0.001, discSize.Z)
			p.disc.CFrame = base
				* CFrame.new(0, -0.004, 0)
				* CFrame.Angles(0, p.swirl + spinUp * dir, 0)
			local visible = r > 1e-3
			local colour = if live.blocked
				then rgb(PK.PortalBlockedColor)
				else rgb(if k == 1 then PK.PortalColorA else PK.PortalColorB)
			p.rim.Color = colour
			p.rim.Transparency = if visible then F.RimTransparency else 1
			p.core.Transparency = if visible then F.CoreTransparency else 1
			p.disc.Transparency = if visible then F.DiscTransparency else 1
			for i, layer in p.sparkles do
				local u = ((t / F.SparkleSeconds) + (i - 1) * 0.5) % 1
				local s = F.SparkleFrom + (F.SparkleTo - F.SparkleFrom) * u
				local size = sizes.PortalDisc * r * s
				layer.Size = Vector3.new(size.X, 0.001, size.Z)
				layer.CFrame = base
					* CFrame.new(0, 0.002 * i, 0)
					* CFrame.Angles(
						0,
						(p.swirl * F.SparkleSpinDegrees / F.SwirlSpinDegrees) + u * dir,
						0
					)
				local fade = math.sin(math.pi * u)
				layer.Transparency = if visible then 1 - (1 - F.SparkleTransparency) * fade else 1
			end
			local hs = radius() * 2 * F.HaloScale * open * pulse
			p.halo.Size = Vector3.new(hs, 0.02, hs)
			p.halo.CFrame = base * CFrame.new(0, -0.012, 0)
			p.haloDecal.Color3 = colour
			p.haloDecal.Transparency = if visible
				then F.HaloTransparency + F.HaloPulse * math.sin(t * F.HaloHz * math.pi * 2)
				else 1
			p.at.CFrame = CFrame.new(centre + Vector3.yAxis * ballWidth())
			p.light.Brightness = F.LightBrightness * open * pulse
		end
		-- The hum while open, between the two.
		local humming = open > 0.05 and list[1] ~= nil and not live.quiet
		if humming and live.hum == nil then
			live.hum = playAt(self, id, A.PortalHum, where(self, m, list[1]), {
				looped = true,
				volume = F.HumVolume,
			})
		elseif not humming then
			stopHum(live)
		end
		if live.hum and live.hum.Parent then
			local mid = where(self, m, list[1])
			if list[2] then
				mid = (mid + where(self, m, list[2])) / 2
			end
			(live.hum.Parent :: Attachment).CFrame = CFrame.new(mid)
			live.hum.Volume = A.PortalHum.Volume * F.HumVolume * open
		end
	end
end

--- Remove every effect at once.
function PortalsFx.clear(self: PortalsFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return PortalsFx
