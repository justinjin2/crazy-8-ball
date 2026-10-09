--!strict
-- AbilityFx: every ability's look, started and driven from one place, and the kit they all
-- build with (docs/prompts/ABILITIES_PROMPT.md 5.2, 5.4, 5.7; step 1 of the brief). Numbers in
-- Config.UI.AbilityFx; the reach preview's colours in Config.Ults.Shared.Preview.
--
-- The registry: Config.UI.AbilityFx.Looks maps an ult id to its client look module
-- (Magnet = "MagnetFx"). Each is required and started with Look.start(hub, parent, kit); a
-- missing or broken module is skipped with a warning, and one look's error never stops the
-- others (each call is guarded, and warned about once). What a look may offer, all optional:
--   look:arming(tableId, armed)   the arming moment (UltCutscene's onArming, at readyAt)
--   look:update(dt)               every frame, after the hub has stepped the replays
--   look:clear()                  drop everything at once
--   look:reach(tableId, armed, power) -> (own, opp)?   its reach for the preview, in
--                                     inches; power = the live pull (0..1, 0 before pulling)
--   look:zones(tableId, armed, match) -> { Zone }?   fixed zones instead (Magnet's pockets)
--   look:aiming(tableId, armed, shot?, match)   the local shooter's aim (Eagle's Eye's path):
--       called every frame for the local player's own seated table (hub.mySeat) while its
--       snapshot has an ult armed by the local player whose look this is; `shot` is the input
--       the guideline traces (AimShot), nil while they are not aiming. Called once more with
--       nil when that stops (the ult no longer armed, another seat, another ult), so a look
--       can hide.
--
-- The kit (the third argument of start; a table of plain functions, called with a dot) holds
-- what every look needs: a per-table anchor (an invisible anchored part at the origin, so an
-- attachment's CFrame under it is its world CFrame) that everything of that table hangs off;
-- world positions of balls and table spots; attachment, part, beam, particle and light
-- factories with sane defaults; a light burst; timers cancelled with the table's effects; the
-- replay's events; the armed ult; the reach preview; and ScreenFx, SoundSheet and
-- AbilityModels. A look requires none of this itself (AbilityFx requires the looks).
--
-- Nothing leaks: a table's anchor, its timers and everything under it go when the table stops
-- being drawn (Hub's renderer pool), and otherwise once LingerSeconds have passed with no shot
-- running there and no ult armed (kit.keep holds it longer for an after-shot look like
-- Rewind's). kit.onRelease tells the looks, so they drop what they hold for that table.
--
-- The reach preview (5.7): while an area ability (its catalog row's Area) is armed at the
-- player's own table and they are aiming (the guideline is up, so it is their shot), a soft
-- ring on the cloth at the aim's predicted first contact (the ghost ball's centre) at the
-- ability's full reach, a dashed inner ring at the opponent's reach, and a small red ring
-- round each opponent ball inside it. A look with zones (Magnet) shows those faintly instead.
-- Only the shooter sees it: it is their aiming aid, drawn from their own guideline, and the
-- opponent never has one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local FxMath = require(Shared:WaitForChild("FxMath"))
local Ults = Shared:WaitForChild("Ults")
local Catalog = require(Ults:WaitForChild("Catalog"))
local Arming = require(Ults:WaitForChild("Arming"))
local ScreenFx = require(script.Parent:WaitForChild("ScreenFx"))
local SoundSheet = require(script.Parent:WaitForChild("SoundSheet"))
local AbilityModels = require(script.Parent:WaitForChild("AbilityModels"))

local F = Config.UI.AbilityFx
local PV = F.Preview
local SP = Config.Ults.Shared.Preview

-- The armed ult as the snapshot carries it (src/shared/Ults/Match.luau view).
export type Armed = {
	by: number,
	id: string,
	stage: string,
	at: number,
	readyAt: number,
	seq: number,
	practice: boolean?,
	pick: { number }?,
}

-- A fixed zone for the preview: centre and radius in inches on the table; `oppR` is how
-- close an opponent ball must be to get the red ring (default r).
export type Zone = { x: number, y: number, r: number, oppR: number? }

-- The aim's predicted first contact (Guideline:contact()), in inches.
export type Aim = { x: number, y: number }

-- The shot the local shooter's guideline traces (Main's refreshAim), for look:aiming. `power`
-- is the raw pull (below Config.Input.MinPowerToShoot: not pulling yet).
export type AimShot = {
	angle: number,
	power: number,
	spin: { x: number, y: number },
	elevation: number,
}

type Props = { [string]: any }

export type Kit = {
	anchor: (tableId: number) -> Part,
	keep: (tableId: number, seconds: number) -> (),
	release: (tableId: number) -> (),
	onRelease: (fn: (tableId: number) -> ()) -> (),
	later: (tableId: number, seconds: number, fn: () -> ()) -> thread,
	ballWorld: (match: any, ball: any) -> Vector3,
	tableWorld: (match: any, x: number, y: number, liftInches: number?) -> Vector3,
	ballOf: (match: any, id: number) -> any,
	pocketOf: (match: any, id: number) -> any,
	ballPart: (tableId: number, id: number) -> BasePart?,
	studs: (inches: number) -> number,
	rgb: (c: { number }) -> Color3,
	attachment: (tableId: number, name: string?, at: (Vector3 | CFrame)?) -> Attachment,
	part: (tableId: number, name: string?, props: Props?) -> Part,
	beam: (a0: Attachment, a1: Attachment, props: Props?) -> Beam,
	particles: (parent: Instance, props: Props?) -> ParticleEmitter,
	light: (parent: Instance, props: Props?) -> PointLight,
	burstLight: (
		at: Vector3,
		color: Color3,
		range: number,
		brightness: number,
		seconds: number
	) -> PointLight,
	isShotOf: (match: any, effectName: string) -> boolean,
	armedOf: (snapshot: any, effectName: string?) -> Armed?,
	events: (match: any, fn: (ev: any, index: number) -> ()) -> (),
	allEvents: (fn: (tableId: number, match: any, ev: any, index: number) -> ()) -> (),
	preview: (tableId: number, x: number, y: number, reachOwn: number, reachOpp: number) -> (),
	previewZones: (tableId: number, zones: { Zone }) -> (),
	hidePreview: (tableId: number) -> (),
	screen: typeof(ScreenFx),
	sound: typeof(SoundSheet),
	models: typeof(AbilityModels),
}

type LookEntry = { id: string, name: string, look: any }

-- The look last given look:aiming, and what it was given (for its closing nil).
type AimingTarget = { entry: LookEntry, tableId: number, armed: Armed, match: any }

type TableFx = {
	anchor: Part,
	keepUntil: number, -- os.clock()
}

type Arc = { a0: Attachment, a1: Attachment, beam: Beam }

type PreviewFx = {
	part: Part, -- holds the arcs' attachments (at the origin)
	arcs: { Arc },
	used: number,
	marks: { Part },
	marksUsed: number,
	auto: boolean, -- drawn by the registry itself (hidden by it too)
}

type Burst = {
	at: Attachment,
	light: PointLight,
	started: number,
	seconds: number,
	brightness: number,
}

local AbilityFx = {}
AbilityFx.__index = AbilityFx

export type AbilityFx = typeof(setmetatable(
	{} :: {
		hub: any,
		parent: Instance,
		kit: Kit,
		looks: { LookEntry },
		lookById: { [string]: LookEntry },
		tables: { [number]: TableFx },
		laters: { [number]: { thread } },
		previews: { [number]: PreviewFx },
		releaseListeners: { (number) -> () },
		eventLists: { [any]: { (any, number) -> () } },
		bursts: { Burst },
		burstPart: Part?,
		aiming: AimingTarget?,
	},
	AbilityFx
))

local FALLBACK_SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn("[8ball] AbilityFx: " .. message)
	end
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function apply(instance: Instance, props: Props?)
	if props then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
end

local function invisiblePart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.CFrame = CFrame.identity -- so every attachment's CFrame is its world CFrame
	return part
end

-- Call look:method(...) if it has one; an error is warned about once, never thrown.
local function call(entry: LookEntry, method: string, ...: any): (boolean, any, any)
	local fn = entry.look[method]
	if type(fn) ~= "function" then
		return false, nil, nil
	end
	local ok, a, b = pcall(fn, entry.look, ...)
	if not ok then
		warnOnce(
			entry.name .. "." .. method,
			("%s:%s failed: %s"):format(entry.name, method, tostring(a))
		)
		return false, nil, nil
	end
	return true, a, b
end

local function armedOf(snapshot: any, effectName: string?): Armed?
	local ults = if type(snapshot) == "table" then snapshot.ults else nil
	local armed = if type(ults) == "table" then ults.armed else nil
	if
		type(armed) ~= "table"
		or type(armed.at) ~= "number"
		or type(armed.id) ~= "string"
		or type(armed.by) ~= "number"
	then
		return nil
	end
	if effectName ~= nil then
		local ult = Catalog.get(armed.id)
		if ult == nil or ult.Effect ~= effectName then
			return nil
		end
	end
	return armed :: Armed
end

---------------------------------------------------------------------------------------------
-- Tables: the anchor, its timers, letting go
---------------------------------------------------------------------------------------------

local function release(self: AbilityFx, tableId: number)
	local list = self.laters[tableId]
	if list then
		self.laters[tableId] = nil
		for _, thread in list do
			pcall(task.cancel, thread)
		end
	end
	local fx = self.tables[tableId]
	if fx then
		self.tables[tableId] = nil
		fx.anchor:Destroy()
		for _, listener in self.releaseListeners do
			local ok, err = pcall(listener :: any, tableId)
			if not ok then
				warnOnce("onRelease", "an onRelease listener failed: " .. tostring(err))
			end
		end
	end
end

local function anchor(self: AbilityFx, tableId: number): Part
	local fx = self.tables[tableId]
	local now = os.clock()
	if fx == nil or fx.anchor.Parent == nil then
		local part = invisiblePart(("AbilityFx_%02d"):format(tableId))
		part.Parent = self.parent
		fx = { anchor = part, keepUntil = now + F.LingerSeconds }
		self.tables[tableId] = fx
	end
	local live = fx :: TableFx
	live.keepUntil = math.max(live.keepUntil, now + F.LingerSeconds)
	return live.anchor
end

---------------------------------------------------------------------------------------------
-- The reach preview
---------------------------------------------------------------------------------------------

local function hidePreview(self: AbilityFx, tableId: number)
	local pv = self.previews[tableId]
	if pv then
		self.previews[tableId] = nil
		pv.part:Destroy()
	end
end

local function ensurePreview(self: AbilityFx, tableId: number, auto: boolean): PreviewFx
	local pv = self.previews[tableId]
	if pv == nil or pv.part.Parent == nil then
		local part = invisiblePart(("AbilityPreview_%02d"):format(tableId))
		part.Parent = self.parent
		pv = { part = part, arcs = {}, used = 0, marks = {}, marksUsed = 0, auto = auto }
		self.previews[tableId] = pv
	end
	local live = pv :: PreviewFx
	live.auto = auto
	live.used, live.marksUsed = 0, 0
	return live
end

local function nextArc(pv: PreviewFx): Arc
	pv.used += 1
	local arc = pv.arcs[pv.used]
	if arc == nil then
		local a0 = Instance.new("Attachment")
		a0.Parent = pv.part
		local a1 = Instance.new("Attachment")
		a1.Parent = pv.part
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.FaceCamera = true
		beam.LightEmission = PV.LightEmission
		beam.LightInfluence = 0
		beam.Segments = PV.BeamSegments
		beam.Parent = pv.part
		arc = { a0 = a0, a1 = a1, beam = beam }
		pv.arcs[pv.used] = arc
	end
	return arc :: Arc
end

-- A ring of `r` inches round (cx, cy) on table `m`'s cloth, cut where it would cross the
-- cushions: `segments` arcs, each `drawShare` of its piece (1 = solid, less = dashes).
local function ring(
	pv: PreviewFx,
	m: any,
	cx: number,
	cy: number,
	r: number,
	color: Color3,
	width: number,
	transparency: number,
	segments: number,
	drawShare: number,
	phase: number
)
	if r <= 0 then
		return
	end
	local g = m.state.geometry
	local arcs = FxMath.clipArcs(
		FxMath.ringArcs(segments, drawShare, phase),
		cx,
		cy,
		r,
		g.halfLength,
		g.halfWidth
	)
	local centre = TableBuilder.toWorld(m.placement, cx, cy, PV.LiftInches)
	-- One inch along the table's x and y, in the world (the table may be turned).
	local ex = TableBuilder.toWorld(m.placement, cx + 1, cy, PV.LiftInches) - centre
	local ey = TableBuilder.toWorld(m.placement, cx, cy + 1, PV.LiftInches) - centre
	local seq = NumberSequence.new(transparency)
	local colors = ColorSequence.new(color)
	for _, a in arcs do
		local arc = nextArc(pv)
		local c0, s0 = math.cos(a.from), math.sin(a.from)
		local c1, s1 = math.cos(a.to), math.sin(a.to)
		local p0 = centre + (ex * c0 + ey * s0) * r
		local p1 = centre + (ex * c1 + ey * s1) * r
		local t0 = (ey * c0 - ex * s0).Unit
		local t1 = (ey * c1 - ex * s1).Unit
		arc.a0.CFrame = CFrame.fromMatrix(p0, t0, Vector3.yAxis)
		arc.a1.CFrame = CFrame.fromMatrix(p1, t1, Vector3.yAxis)
		local handle = FxMath.arcHandle(r, a.to - a.from) * ex.Magnitude
		local beam = arc.beam
		beam.CurveSize0 = handle
		beam.CurveSize1 = handle
		beam.Width0 = width
		beam.Width1 = width
		beam.Color = colors
		beam.Transparency = seq
		beam.Enabled = true
	end
end

-- The opponent's balls at table `m` for the side to shoot (Arming.targets, the rule the server
-- arms with): none on an open table.
local function opponentBalls(snapshot: any, m: any): { number }
	if type(snapshot) ~= "table" or type(snapshot.activeTeam) ~= "number" then
		return {}
	end
	local groups = if type(snapshot.groups) == "table" then snapshot.groups else nil
	local ok, _own, opp = pcall(
		Arming.targets :: any,
		groups,
		snapshot.activeTeam,
		snapshot.calledPocket,
		m.state.balls
	)
	return if ok and type(opp) == "table" then opp else {}
end

-- A small red ring round each opponent ball within `oppR` of any of `centres`.
local function markOpponents(pv: PreviewFx, m: any, snapshot: any, centres: { Zone })
	local ringId = Config.Guideline.RingTextureId
	if ringId == "" then
		return -- no ring image: the reach rings still show
	end
	local d = TableBuilder.studs(Config.Balls.RenderRadiusInches * 2) * PV.OutlineBallWidths
	for _, id in opponentBalls(snapshot, m) do
		local b = nil
		for _, ball in m.state.balls do
			if ball.id == id then
				b = ball
				break
			end
		end
		if b == nil or b.pocketed then
			continue
		end
		local inside = false
		for _, z in centres do
			if FxMath.within(b.x - z.x, b.y - z.y, z.oppR or z.r) then
				inside = true
				break
			end
		end
		if not inside then
			continue
		end
		pv.marksUsed += 1
		local mark: Part? = pv.marks[pv.marksUsed]
		if mark == nil then
			local part = invisiblePart("OpponentMark")
			part.Size = Vector3.new(d, 0.01, d)
			local decal = Instance.new("Decal")
			decal.Name = "Outline"
			decal.Face = Enum.NormalId.Top
			decal.Texture = ringId
			decal.Color3 = rgb(SP.ColorOpp)
			decal.Parent = part
			part.Parent = pv.part
			pv.marks[pv.marksUsed] = part
			mark = part
		end
		local live = mark :: Part
		live.CFrame = CFrame.new(TableBuilder.toWorld(m.placement, b.x, b.y, PV.LiftInches))
		local decal = live:FindFirstChild("Outline")
		if decal and decal:IsA("Decal") then
			decal.Transparency = SP.OutlineTransparency
		end
	end
end

-- Hide the arcs and marks this frame's drawing did not use.
local function finishPreview(pv: PreviewFx)
	for i = pv.used + 1, #pv.arcs do
		pv.arcs[i].beam.Enabled = false
	end
	for i = pv.marksUsed + 1, #pv.marks do
		local decal = pv.marks[i]:FindFirstChild("Outline")
		if decal and decal:IsA("Decal") then
			decal.Transparency = 1
		end
	end
end

local function dashPhase(): number
	return 2 * math.pi * os.clock() / PV.DashTurnSeconds
end

local function drawPreview(
	self: AbilityFx,
	tableId: number,
	x: number,
	y: number,
	own: number,
	opp: number,
	auto: boolean
)
	local m = self.hub:matchFor(tableId)
	if m == nil or m.renderer == nil then
		hidePreview(self, tableId)
		return
	end
	local pv = ensurePreview(self, tableId, auto)
	ring(
		pv,
		m,
		x,
		y,
		own,
		rgb(SP.ColorOwn),
		PV.RingWidthStuds,
		SP.RingTransparency,
		PV.RingSegments,
		1,
		0
	)
	ring(
		pv,
		m,
		x,
		y,
		opp,
		rgb(SP.ColorOpp),
		PV.InnerWidthStuds,
		SP.InnerRingTransparency,
		PV.DashSegments,
		PV.DashShare,
		dashPhase()
	)
	markOpponents(pv, m, self.hub.snapshots[tableId], { { x = x, y = y, r = own, oppR = opp } })
	finishPreview(pv)
end

local function drawZones(self: AbilityFx, tableId: number, zones: { Zone }, auto: boolean)
	local m = self.hub:matchFor(tableId)
	if m == nil or m.renderer == nil then
		hidePreview(self, tableId)
		return
	end
	local pv = ensurePreview(self, tableId, auto)
	for _, z in zones do
		ring(
			pv,
			m,
			z.x,
			z.y,
			z.r,
			rgb(SP.ColorOwn),
			PV.RingWidthStuds,
			PV.ZoneTransparency,
			PV.RingSegments,
			1,
			0
		)
	end
	markOpponents(pv, m, self.hub.snapshots[tableId], zones)
	finishPreview(pv)
end

-- The registry's own preview: at the player's table, while they aim with an area ability armed.
local function stepPreview(self: AbilityFx, aim: Aim?, shot: AimShot?)
	local seat = self.hub.mySeat
	local shown: number? = nil
	if aim and seat then
		local m = self.hub:matchFor(seat)
		local armed = armedOf(self.hub.snapshots[seat])
		local ult = armed and Catalog.get(armed.id)
		if m and m.renderer and not m:isBusy() and armed and ult and ult.Area then
			local entry = self.lookById[armed.id]
			local zones: any = nil
			if entry then
				local _, found = call(entry, "zones", seat, armed, m)
				zones = found
			end
			if type(zones) == "table" then
				drawZones(self, seat, zones, true)
			else
				local own, opp = nil, nil
				if entry then
					-- The live pull, for a reach that grows with the shot's power (Black Flash).
					local power = if shot then math.clamp(shot.power, 0, 1) else 0
					local _, a, b = call(entry, "reach", seat, armed, power)
					own, opp = a, b
				end
				local reachOwn = if type(own) == "number" then own else F.PreviewDefaultReachInches
				local reachOpp = if type(opp) == "number"
					then opp
					else reachOwn * Config.Ults.Shared.OpponentFactor
				drawPreview(self, seat, aim.x, aim.y, reachOwn, reachOpp, true)
			end
			shown = seat
		end
	end
	for id, pv in self.previews do
		if pv.auto and id ~= shown then
			hidePreview(self, id)
		end
	end
end

-- look:aiming for the local player's own table while their ult is armed (see the header); the
-- look it went to last frame gets a closing nil when that stops.
local function stepAiming(self: AbilityFx, shot: AimShot?)
	local seat = self.hub.mySeat
	local now: AimingTarget? = nil
	if seat then
		local armed = armedOf(self.hub.snapshots[seat])
		local m = self.hub:matchFor(seat)
		local entry = armed and self.lookById[armed.id]
		local me = Players.LocalPlayer.UserId
		local snapshot = self.hub.snapshots[seat]
		local guide = self.lookById.EaglesEye
		if armed and entry and m and armed.by == me then
			now = { entry = entry, tableId = seat, armed = armed, match = m }
		elseif
			Config.Ults.Shared.RewindRedoGuide
			and guide
			and m
			and snapshot
			and snapshot.redoClock == true
			and snapshot.shooter == me
		then
			-- Rewind's redo (7.6): the shooter aims with Eagle's Eye's full-path guide.
			now = {
				entry = guide,
				tableId = seat,
				armed = { id = "EaglesEye", by = me } :: any,
				match = m,
			}
		end
	end
	local last = self.aiming
	if last and (now == nil or now.entry ~= last.entry or now.tableId ~= last.tableId) then
		call(last.entry, "aiming", last.tableId, last.armed, nil, last.match)
	end
	self.aiming = now
	if now then
		call(now.entry, "aiming", now.tableId, now.armed, shot, now.match)
	end
end

---------------------------------------------------------------------------------------------
-- The kit
---------------------------------------------------------------------------------------------

local function makeKit(self: AbilityFx): Kit
	local hub = self.hub
	local kit: Kit = {} :: any

	--- The table's anchor part (made on first use), kept at least LingerSeconds from now.
	function kit.anchor(tableId: number): Part
		return anchor(self, tableId)
	end

	--- Keep the table's effects at least `seconds` longer (an after-shot look).
	function kit.keep(tableId: number, seconds: number)
		local fx = self.tables[tableId]
		if fx then
			fx.keepUntil = math.max(fx.keepUntil, os.clock() + seconds)
		end
	end

	--- Destroy the table's anchor and everything under it, and cancel its timers, now.
	function kit.release(tableId: number)
		release(self, tableId)
	end

	--- `fn(tableId)` whenever a table's effects are released (drop what you hold for it).
	function kit.onRelease(fn: (number) -> ())
		table.insert(self.releaseListeners, fn)
	end

	--- Run `fn` in `seconds`, unless the table's effects are released first.
	function kit.later(tableId: number, seconds: number, fn: () -> ()): thread
		local list = self.laters[tableId]
		if list == nil then
			list = {}
			self.laters[tableId] = list
		end
		local mine = list :: { thread }
		local thread: thread
		thread = task.delay(seconds, function()
			local i = table.find(mine, thread)
			if i then
				table.remove(mine, i)
			end
			fn()
		end)
		table.insert(mine, thread)
		return thread
	end

	--- Where ball `ball` (a physics Ball) is drawn, in the world.
	function kit.ballWorld(match: any, ball: any): Vector3
		return TableBuilder.toWorld(
			match.placement,
			ball.x,
			ball.y,
			Config.Balls.RenderRadiusInches + (ball.z or 0)
		)
	end

	--- A spot (x, y inches) on table `match`'s cloth, `liftInches` above it, in the world.
	function kit.tableWorld(match: any, x: number, y: number, liftInches: number?): Vector3
		return TableBuilder.toWorld(match.placement, x, y, liftInches or 0)
	end

	--- The ball with id `id` in the replay's state, or nil.
	function kit.ballOf(match: any, id: number): any
		for _, b in match.state.balls do
			if b.id == id then
				return b
			end
		end
		return nil
	end

	--- The pocket with id `id` in the table's geometry, or nil.
	function kit.pocketOf(match: any, id: number): any
		for _, p in match.state.geometry.pockets do
			if p.id == id then
				return p
			end
		end
		return nil
	end

	--- The drawn part of ball `id` at the table (nil when it is not drawn).
	function kit.ballPart(tableId: number, id: number): BasePart?
		local renderer = hub.boundTo and hub.boundTo[tableId]
		if renderer == nil then
			return nil
		end
		local part = renderer.folder:FindFirstChild(if id == 0 then "CueBall" else "Ball" .. id)
		return if part and part:IsA("BasePart") then part else nil
	end

	kit.studs = TableBuilder.studs
	kit.rgb = rgb

	--- An attachment under the table's anchor, at `at` (world) if given.
	function kit.attachment(tableId: number, name: string?, at: (Vector3 | CFrame)?): Attachment
		local a = Instance.new("Attachment")
		a.Name = name or "Fx"
		if typeof(at) == "Vector3" then
			a.CFrame = CFrame.new(at :: Vector3)
		elseif typeof(at) == "CFrame" then
			a.CFrame = at :: CFrame
		end
		a.Parent = anchor(self, tableId)
		return a
	end

	--- An invisible anchored part under the table's anchor (a mesh holder, an emitter's shape),
	--- with `props` set on it.
	function kit.part(tableId: number, name: string?, props: Props?): Part
		local part = invisiblePart(name or "FxPart")
		apply(part, props)
		part.Parent = anchor(self, tableId)
		return part
	end

	--- A beam from `a0` to `a1` (under a0's parent): white, glowing, facing the camera,
	--- F.BeamWidthStuds wide, opaque; `props` override.
	function kit.beam(a0: Attachment, a1: Attachment, props: Props?): Beam
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		beam.Width0 = F.BeamWidthStuds
		beam.Width1 = F.BeamWidthStuds
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Segments = F.BeamSegments
		beam.Transparency = NumberSequence.new(0)
		apply(beam, props)
		beam.Parent = a0.Parent
		return beam
	end

	--- A glowing spark emitter that emits nothing until given a Rate or told to Emit(n);
	--- `props` override.
	function kit.particles(parent: Instance, props: Props?): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Texture = if F.SparkTexture ~= "" then F.SparkTexture else FALLBACK_SPARK
		e.Color = ColorSequence.new(Color3.new(1, 1, 1))
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, F.ParticleSizeStuds),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Lifetime = NumberRange.new(F.ParticleLifetime[1], F.ParticleLifetime[2])
		e.Speed = NumberRange.new(F.ParticleSpeed[1], F.ParticleSpeed[2])
		e.Rotation = NumberRange.new(0, 360)
		e.Rate = 0
		apply(e, props)
		e.Parent = parent
		return e
	end

	--- A point light (no shadows) at F.LightBrightness and F.LightRangeStuds; `props` override.
	function kit.light(parent: Instance, props: Props?): PointLight
		local light = Instance.new("PointLight")
		light.Color = Color3.new(1, 1, 1)
		light.Brightness = F.LightBrightness
		light.Range = F.LightRangeStuds
		light.Shadows = false
		apply(light, props)
		light.Parent = parent
		return light
	end

	--- A light that flares up at `at` and fades out over `seconds`, then is destroyed.
	function kit.burstLight(
		at: Vector3,
		color: Color3,
		range: number,
		brightness: number,
		seconds: number
	): PointLight
		local holder = self.burstPart
		if holder == nil or holder.Parent == nil then
			local part = invisiblePart("AbilityFx_Bursts")
			part.Parent = self.parent
			self.burstPart = part
			holder = part
		end
		local a = Instance.new("Attachment")
		a.CFrame = CFrame.new(at)
		a.Parent = holder
		local light = kit.light(a, { Color = color, Range = range, Brightness = 0 })
		table.insert(self.bursts, {
			at = a,
			light = light,
			started = os.clock(),
			seconds = math.max(seconds, 0.01),
			brightness = brightness,
		})
		return light
	end

	--- True while `match` replays a shot whose overrides carry `effectName`.
	function kit.isShotOf(match: any, effectName: string): boolean
		local o = match.state.overrides
		-- (`Hidden`: the tutorial's game-1 assist, Tutorial/Rig, which draws nothing; an
		-- ability armed in game 1 runs inside it as `Inner` and shows as usual.)
		return match.shot ~= nil
			and o ~= nil
			and ((o.Effect == effectName and not o.Hidden) or o.Inner == effectName)
	end

	--- The snapshot's armed ult (snapshot.ults.armed), checked; with `effectName`, only one whose
	--- effect that is.
	kit.armedOf = armedOf

	--- `fn(ev, index)` for every replay event of `match` (every type, `removed` and `ult` too).
	function kit.events(match: any, fn: (any, number) -> ())
		local list = self.eventLists[match]
		if list == nil then
			local fresh: { (any, number) -> () } = {}
			self.eventLists[match] = fresh
			list = fresh
			match:onEvent(function(ev, index)
				for _, f in fresh do
					local ok, err = pcall(f :: any, ev, index)
					if not ok then
						warnOnce(
							"event:" .. tostring(ev.type),
							"an event listener failed: " .. tostring(err)
						)
					end
				end
			end)
		end
		table.insert(list :: { (any, number) -> () }, fn)
	end

	--- `fn(tableId, match, ev, index)` for every replay event at every table.
	function kit.allEvents(fn: (number, any, any, number) -> ())
		for id, match in hub.matches do
			kit.events(match, function(ev, index)
				fn(id, match, ev, index)
			end)
		end
	end

	--- Draw a reach preview at (x, y) inches yourself (the registry already draws one from
	--- look:reach; one drawn here is the caller's to hide).
	function kit.preview(tableId: number, x: number, y: number, reachOwn: number, reachOpp: number)
		drawPreview(self, tableId, x, y, reachOwn, reachOpp, false)
	end

	--- Draw fixed zones as the preview yourself (the caller's to hide).
	function kit.previewZones(tableId: number, zones: { Zone })
		drawZones(self, tableId, zones, false)
	end

	function kit.hidePreview(tableId: number)
		hidePreview(self, tableId)
	end

	kit.screen = ScreenFx
	kit.sound = SoundSheet
	kit.models = AbilityModels
	return kit
end

---------------------------------------------------------------------------------------------
-- The registry
---------------------------------------------------------------------------------------------

--- Start every look in Config.UI.AbilityFx.Looks for the tables `hub` (src/client/Hub.luau)
--- holds, drawing under `parent`, with `cutscene`'s arming moments forwarded to them. Call
--- update(dt, aim, shot) every frame after hub:update(dt).
function AbilityFx.start(hub: any, parent: Instance, cutscene: any): AbilityFx
	local self = setmetatable({
		hub = hub,
		parent = parent,
		kit = nil :: any,
		looks = {},
		lookById = {},
		tables = {},
		laters = {},
		previews = {},
		releaseListeners = {},
		eventLists = {},
		bursts = {},
		burstPart = nil,
		aiming = nil,
	}, AbilityFx)
	self.kit = makeKit(self)
	ScreenFx.bind(hub)

	-- In id order, so the looks update in the same order every session.
	local ids: { string } = {}
	for id in F.Looks do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local name = F.Looks[id]
		local module = script.Parent:FindFirstChild(name)
		if module == nil or not module:IsA("ModuleScript") then
			warnOnce("missing:" .. name, ("no look module %s for %s: skipped"):format(name, id))
			continue
		end
		local ok, lib = pcall(function()
			return (require :: any)(module)
		end)
		if not ok or type(lib) ~= "table" or type(lib.start) ~= "function" then
			warnOnce(
				"broken:" .. name,
				("look module %s did not load: %s"):format(name, tostring(lib))
			)
			continue
		end
		local started, look = pcall(lib.start, hub, parent, self.kit)
		if not started or look == nil then
			warnOnce("start:" .. name, ("%s.start failed: %s"):format(name, tostring(look)))
			continue
		end
		local entry: LookEntry = { id = id, name = name, look = look }
		table.insert(self.looks, entry)
		self.lookById[id] = entry
	end

	if cutscene then
		cutscene:onArming(function(tableId: number, armed: any)
			AbilityModels.preload()
			for _, entry in self.looks do
				call(entry, "arming", tableId, armed)
			end
		end)
	end
	-- A match starting: fetch the models and sounds now, so the first use does not pop in.
	hub:onSeatChanged(function(id: number?)
		if id then
			AbilityModels.preload()
			SoundSheet.preload()
		end
	end)
	return self
end

--- Every frame, after hub:update(dt) has stepped the replays. `aim` is the local shooter's
--- predicted first contact (Guideline:contact()) and `shot` the input their guideline traces
--- (AimShot), both nil while they are not aiming.
function AbilityFx.update(self: AbilityFx, dt: number, aim: Aim?, shot: AimShot?)
	for _, entry in self.looks do
		call(entry, "update", dt)
	end

	-- Let go of what is no longer needed: a table not drawn at once; otherwise once it has
	-- lingered with no shot running and nothing armed.
	local now = os.clock()
	for id, fx in self.tables do
		local m = self.hub.matches[id]
		local gone = fx.anchor.Parent == nil or (m ~= nil and m.renderer == nil)
		-- Kept Portals (a Turn ability, ults.kept) stay up between the turn's shots too: let
		-- go, they would open again with their sound every LingerSeconds (the audit).
		local snap = self.hub.snapshots[id]
		local ults = if type(snap) == "table" then snap.ults else nil
		local kept = type(ults) == "table" and ults.kept ~= nil
		local busy = m ~= nil and (m:isBusy() or armedOf(snap) ~= nil or kept)
		if busy then
			fx.keepUntil = math.max(fx.keepUntil, now + F.LingerSeconds)
		end
		if gone or (not busy and now >= fx.keepUntil) then
			release(self, id)
		end
	end

	for i = #self.bursts, 1, -1 do
		local b = self.bursts[i]
		local t = now - b.started
		if t >= b.seconds or b.at.Parent == nil then
			table.remove(self.bursts, i)
			b.at:Destroy()
		else
			b.light.Brightness = b.brightness * FxMath.flare(t, b.seconds, F.BurstRiseShare)
		end
	end

	stepPreview(self, aim, shot)
	stepAiming(self, shot)
end

--- Remove every effect at once: every look's, every table's, the screen's and the sounds.
function AbilityFx.clear(self: AbilityFx)
	self.aiming = nil
	for _, entry in self.looks do
		call(entry, "clear")
	end
	local ids: { number } = {}
	for id in self.tables do
		table.insert(ids, id)
	end
	for id in self.laters do
		table.insert(ids, id)
	end
	for _, id in ids do
		release(self, id)
	end
	for id in self.previews do
		hidePreview(self, id)
	end
	for _, b in self.bursts do
		b.at:Destroy()
	end
	table.clear(self.bursts)
	ScreenFx.clearAll()
	SoundSheet.stopAll()
end

--- The kit the looks were given (for a Studio check).
function AbilityFx.kitOf(self: AbilityFx): Kit
	return self.kit
end

return AbilityFx
