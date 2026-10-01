--!strict
-- TimeStopFx: what Time Stop looks and sounds like (docs/prompts/ABILITIES_PROMPT.md 7.7,
-- reference 03). The freeze, the second strike and the resume are physics and the match engine
-- (Ults/Effects/TimeStop, the Frozen phase); this only draws them, off the replay, so everyone
-- sees them together. Numbers in Config.UI.TimeStopFx, the sounds in Config.Ults.Audio, the
-- meshes in the uploaded TimeStop model (tools/blender/abilities/timestop.py): TimeBubble,
-- ClockFace and ClockHand, and the screen's images in Config.Ults.Assets.Images (Time*).
--
--   * Armed: a small shimmering lens bubble (ForceField) turns round the cue ball, with a
--     tick-tock as it arms.
--   * The shot: the bubble rides the cue ball; from its first contact a reverse cymbal swells
--     and the bubble swells with it, peaking on the freeze.
--   * The freeze (the replay's `ult` event "freeze"): a negative flash and a deep boom, the
--     bubble bursts out across the table, a white-violet warp ring grows from the middle of
--     the screen past its edges, then stopped time: the view goes cold violet inside a bright
--     lens edge, a clock face on the cloth round the cue ball sweeps its hand once round the
--     stopped time (Shared.FrozenSeconds) with a slow tick each second, and every ball caught
--     moving shows afterimages behind it. The second strike's cue ball draws a violet trail.
--   * The resume: a second negative flash with a reversed whoosh into a tick-tock, the bubble
--     comes back huge and collapses onto the cue ball, and the colour snaps back.
-- Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or with
-- clear(). Without the model the bubble and the clock are skipped; the rest still shows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local F = Config.UI.TimeStopFx
local A = Config.Ults.Audio
local S = Config.Ults.Shared
local IMAGES = Config.Ults.Assets.Images :: any

local EFFECT = "TimeStop"
local MODEL = "TimeStop"
local PIECES = { "TimeBubble", "ClockFace", "ClockHand" }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function approach(level: number, target: number, dt: number, seconds: number): number
	local step = dt / math.max(seconds, 1e-3)
	if level < target then
		return math.min(target, level + step)
	end
	return math.max(target, level - step)
end

local function ballWidth(): number
	return Config.Balls.RenderRadiusInches * 2 * Config.Table.StudsPerInch
end

local function easeOut(u: number): number
	u = math.clamp(u, 0, 1)
	return 1 - (1 - u) * (1 - u)
end

type Meshes = { parts: { [string]: MeshPart }, sizes: { [string]: Vector3 } }

type TableFx = {
	anchor: BasePart,
	bubble: MeshPart?,
	face: MeshPart?,
	hand: MeshPart?,
	ghosts: { BasePart },
	trail: { part: Part, trail: Trail }?,
	handles: { any }, -- the stopped time's screen (grade, lens), released on the resume
	look: number, -- the armed bubble's opacity
	spin: number,
	shotSeq: number,
	contactAt: number?, -- os.clock() of this shot's first contact
	frozeAt: number?, -- os.clock() of the freeze
	resumedAt: number?, -- os.clock() of the resume
	burstFrom: number, -- the bubble's size (studs) as it burst
	centre: Vector3?, -- the frozen cue ball (the clock's middle)
	nextTick: number,
	struck: number, -- how many strikes in stopped time have begun in the replay
	handFrom: number?, -- os.clock() the clock hand's current sweep began (the freeze, then each strike's end)
	resumed: boolean,
	quiet: boolean, -- caught up late: no screen or sounds for this shot
}

export type TimeStopFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	meshes: Meshes?,
	meshesFailed: boolean,
	nextMeshCheck: number,
}

local TimeStopFx = {}
TimeStopFx.__index = TimeStopFx

local function meshesOf(self: TimeStopFx): Meshes?
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
			warn(("[8ball] TimeStopFx: the %s model has no %s"):format(MODEL, name))
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

local function newMesh(self: TimeStopFx, fx: TableFx, name: string): MeshPart?
	local meshes = meshesOf(self)
	local template = meshes and meshes.parts[name]
	if template == nil then
		return nil
	end
	local part = template:Clone()
	part.Transparency = 1
	part.Parent = fx.anchor
	return part
end

-- A mesh sized so its widest side is `studs`.
local function sizeTo(self: TimeStopFx, part: MeshPart, name: string, studs: number)
	local meshes = self.meshes
	local base = meshes and meshes.sizes[name]
	if base then
		part.Size = base * (studs / math.max(base.X, base.Z))
	end
end

local function ensureBubble(self: TimeStopFx, fx: TableFx): MeshPart?
	if fx.bubble and fx.bubble.Parent then
		return fx.bubble
	end
	local bubble = newMesh(self, fx, "TimeBubble")
	if bubble then
		bubble.Material = Enum.Material.ForceField
		bubble.Color = rgb(F.BubbleColor)
		fx.bubble = bubble
	end
	return bubble
end

local function create(self: TimeStopFx, id: number): TableFx
	local fx: TableFx = {
		anchor = self.kit.anchor(id),
		bubble = nil,
		face = nil,
		hand = nil,
		ghosts = {},
		trail = nil,
		handles = {},
		look = 0,
		spin = 0,
		shotSeq = 0,
		contactAt = nil,
		frozeAt = nil,
		resumedAt = nil,
		burstFrom = 0,
		centre = nil,
		nextTick = 0,
		struck = 0,
		resumed = false,
		quiet = false,
	}
	self.tables[id] = fx
	return fx
end

local function dropGhosts(fx: TableFx)
	for _, g in fx.ghosts do
		g:Destroy()
	end
	table.clear(fx.ghosts)
end

local function dropTrail(fx: TableFx)
	if fx.trail then
		fx.trail.part:Destroy()
		fx.trail = nil
	end
end

local function releaseScreen(fx: TableFx)
	for _, h in fx.handles do
		h:release()
	end
	table.clear(fx.handles)
end

local function destroy(self: TimeStopFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	releaseScreen(fx)
	dropGhosts(fx)
	dropTrail(fx)
	for _, part in { fx.bubble, fx.face, fx.hand } do
		if part then
			part:Destroy()
		end
	end
end

local function playAt(self: TimeStopFx, id: number, clip: any, at: Vector3, pitch: number?): Sound?
	local kit = self.kit
	local holder = kit.attachment(id, "TimeSound", at)
	local sound = kit.sound.library(clip, holder, { pitch = pitch })
	kit.later(id, 4, function()
		holder:Destroy()
	end)
	return sound
end

-- Flat for the players in the match, at the table for anyone else in earshot.
local function playTable(self: TimeStopFx, id: number, m: any, clip: any, pitch: number?): Sound?
	local kit = self.kit
	if kit.screen.involved(self.hub, id) then
		return kit.sound.library(clip, nil, { pitch = pitch })
	end
	return playAt(self, id, clip, kit.tableWorld(m, 0, 0, 0), pitch)
end

-- Afterimages behind every ball caught moving.
local function makeGhosts(self: TimeStopFx, id: number, fx: TableFx, m: any)
	dropGhosts(fx)
	local kit = self.kit
	local studsPerInch = Config.Table.StudsPerInch
	for _, b in m.state.balls do
		if b.pocketed then
			continue
		end
		local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
		local part = kit.ballPart(id, b.id)
		if speed < F.GhostMinSpeed or part == nil then
			continue
		end
		local here = kit.tableWorld(m, b.x, b.y, 0)
		local ahead = kit.tableWorld(m, b.x + b.vx, b.y + b.vy, 0)
		local dir = (ahead - here).Unit
		local gap = math.min(
			speed * F.GhostSpacingSeconds * studsPerInch,
			ballWidth() * F.GhostMaxBallWidths
		)
		for k = 1, F.Ghosts do
			local ghost = (part :: BasePart):Clone()
			for _, child in ghost:GetChildren() do
				if not child:IsA("Decal") then
					child:Destroy()
				end
			end
			ghost.Name = "TimeGhost"
			ghost.Anchored = true
			ghost.CanCollide = false
			ghost.CanQuery = false
			ghost.CanTouch = false
			ghost.CastShadow = false
			local alpha = F.GhostTransparency[k] or 0.9
			ghost.Transparency = alpha
			for _, child in ghost:GetChildren() do
				if child:IsA("Decal") then
					child.Transparency = alpha
				end
			end
			ghost.CFrame = (part :: BasePart).CFrame - dir * gap * k
			ghost.Parent = fx.anchor
			table.insert(fx.ghosts, ghost)
		end
	end
end

local function freeze(self: TimeStopFx, id: number, fx: TableFx, m: any)
	local kit = self.kit
	local t = os.clock()
	fx.frozeAt = t
	fx.nextTick = t + F.TickSeconds
	local part = kit.ballPart(id, 0)
	fx.centre = if part then (part :: BasePart).Position else nil
	fx.burstFrom = ballWidth() * F.SwellBallWidths
	makeGhosts(self, id, fx, m)
	if fx.quiet then
		return
	end
	local screen = kit.screen
	screen.invert(id, F.InvertSeconds)
	screen.shake(id, F.ShakeStuds, F.ShakeSeconds)
	screen.overlay(id, IMAGES.TimeWarpRing, {
		fadeIn = 0.03,
		hold = F.RingSeconds * 0.5,
		fadeOut = F.RingSeconds * 0.5,
		transparency = F.RingTransparency,
		square = F.RingSquare,
		pulseHz = 0,
		pulseShare = 0,
		growFrom = F.RingGrowFrom,
		growTo = F.RingGrowTo,
		growSeconds = F.RingSeconds,
	})
	local grade = screen.grade(id, F.Grade, F.GradeFadeIn, math.huge, F.GradeFadeOut)
	if grade then
		table.insert(fx.handles, grade)
	end
	local lens = screen.overlay(id, IMAGES.TimeLensEdge, {
		fadeIn = F.LensFadeIn,
		hold = math.huge,
		fadeOut = F.LensFadeOut,
		transparency = F.LensTransparency,
	})
	if lens then
		table.insert(fx.handles, lens)
	end
	playTable(self, id, m, A.TimeBoom)
end

local function resume(self: TimeStopFx, id: number, fx: TableFx, m: any)
	fx.resumed = true
	fx.resumedAt = os.clock()
	releaseScreen(fx)
	dropGhosts(fx)
	dropTrail(fx)
	if fx.quiet or fx.frozeAt == nil then
		return
	end
	self.kit.screen.invert(id, F.InvertSeconds)
	playTable(self, id, m, A.TimeResume)
	self.kit.later(id, F.ResumeTickDelay, function()
		playTable(self, id, m, A.TimeTickTock)
	end)
end

-- The second strike's cue ball: a violet trail while it moves in stopped time.
local function startTrail(self: TimeStopFx, id: number, fx: TableFx)
	dropTrail(fx)
	local kit = self.kit
	local holder = kit.part(id, "TimeTrail", { Transparency = 1, Size = Vector3.one * 0.05 })
	local width = ballWidth() * 0.8
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = holder
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.FaceCamera = true
	trail.Lifetime = F.TrailSeconds
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(rgb(F.TrailColor))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = holder
	fx.trail = { part = holder, trail = trail }
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function TimeStopFx.start(hub: any, _parent: Instance, kit: any): TimeStopFx
	local self: TimeStopFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
	}, TimeStopFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			releaseScreen(fx)
		end
		self.tables[tableId] = nil -- its parts went with the anchor
	end)
	kit.allEvents(function(tableId: number, m: any, ev: any, _index: number)
		if not kit.isShotOf(m, EFFECT) or m.renderer == nil then
			return
		end
		local fx = self.tables[tableId] or create(self, tableId)
		if fx.shotSeq ~= m.seq then
			return -- the update below has not met this shot yet
		end
		local late = m.state.time - ev.t > F.FreshSeconds
		if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) and fx.contactAt == nil then
			fx.contactAt = os.clock()
			if not late and not fx.quiet then
				playTable(self, tableId, m, A.TimeSwell, F.SwellPitch)
			end
		elseif ev.type == "ult" and ev.kind == "freeze" and fx.frozeAt == nil then
			fx.quiet = fx.quiet or late
			freeze(self, tableId, fx, m)
			fx.handFrom = fx.frozeAt
		elseif ev.type == "ult" and ev.kind == "strikeFrozen" and fx.frozeAt then
			-- A strike's part is done: the hand sweeps the next window from the top.
			fx.handFrom = os.clock()
		end
	end)
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in { A.TimeSwell, A.TimeBoom, A.TimeTick, A.TimeResume, A.TimeTickTock } do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		for _, key in { "TimeWarpRing", "TimeLensEdge" } do
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

--- The arming moment at table `tableId` (UltCutscene's onArming): the bubble pops on with a
--- tick-tock.
function TimeStopFx.arming(self: TimeStopFx, tableId: number, armed: any)
	local m = self.hub:matchFor(tableId)
	if armed == nil or armed.id ~= EFFECT or m == nil or m.renderer == nil then
		return
	end
	local fx = self.tables[tableId] or create(self, tableId)
	fx.look = 0
	ensureBubble(self, fx)
	local cue = m:findCueBall()
	if cue then
		playAt(self, tableId, A.TimeTickTock, self.kit.ballWorld(m, cue))
	end
end

--- Every frame, after the hub has stepped the replays.
function TimeStopFx.update(self: TimeStopFx, dt: number)
	local now = workspace:GetServerTimeNow()
	local t = os.clock()
	local kit = self.kit
	for id, m in self.hub.matches do
		local fx = self.tables[id]
		if m.renderer == nil then
			if fx then
				destroy(self, id)
			end
			continue
		end
		local armed = kit.armedOf(self.hub.snapshots[id], EFFECT)
		local shot = kit.isShotOf(m, EFFECT)
		local wantArmed = armed ~= nil
			and not m:isBusy()
			and (armed.stage == "Armed" or now >= (armed.readyAt or math.huge))
		if fx == nil then
			if not (wantArmed or shot) then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		if shot and live.shotSeq ~= m.seq then
			-- A new Time Stop shot: a replay that began long ago (a late join) stays quiet.
			live.shotSeq = m.seq
			live.contactAt, live.frozeAt, live.resumedAt = nil, nil, nil
			live.struck, live.resumed, live.handFrom = 0, false, nil
			live.quiet = m.state.time > F.FreshSeconds
			releaseScreen(live)
			dropGhosts(live)
			dropTrail(live)
		end
		local mshot = m.shot
		-- The second strike begins, and the resume, as the replay applies them.
		if shot and mshot and mshot.applied then
			if mshot.applied.strikes > live.struck then
				live.struck = mshot.applied.strikes
				startTrail(self, id, live)
				if not live.quiet and live.centre then
					playAt(self, id, A.TimeTickTock, live.centre)
				end
			end
			if mshot.applied.resume and not live.resumed and live.frozeAt then
				resume(self, id, live, m)
			end
		end
		local frozen = live.frozeAt ~= nil and not live.resumed and shot
		-- The ticks while frozen.
		if frozen and not live.quiet and t >= live.nextTick then
			live.nextTick = t + F.TickSeconds
			if live.centre then
				playAt(self, id, A.TimeTick, live.centre)
			end
		end
		local cuePart = kit.ballPart(id, 0)
		local cue = m:findCueBall()
		local cueOn = cuePart ~= nil and cue ~= nil and not cue.pocketed
		if live.trail and cueOn then
			live.trail.part.CFrame = CFrame.new((cuePart :: BasePart).Position)
		end
		-- The bubble: armed and riding on the cue ball, swelling from the contact; bursting on
		-- the freeze; gone while frozen; collapsing onto the cue ball on the resume.
		local bubble = if wantArmed
				or shot
				or live.resumedAt
			then ensureBubble(self, live)
			else live.bubble
		live.spin += math.rad(F.SpinDegreesPerSecond) * dt
		local riding = (wantArmed or (shot and live.frozeAt == nil)) and cueOn
		live.look = approach(live.look, if riding then 1 else 0, dt, F.PopSeconds)
		if bubble then
			local size, alpha, at = 0, 1, nil :: Vector3?
			if live.frozeAt and not live.resumed then
				local u = (t - live.frozeAt) / F.BurstSeconds
				if u < 1 then
					size = live.burstFrom + (F.BurstStuds - live.burstFrom) * easeOut(u)
					alpha = F.BubbleTransparency + (1 - F.BubbleTransparency) * u
					at = live.centre
				end
			elseif live.resumedAt and t - live.resumedAt < F.CollapseSeconds then
				local u = (t - live.resumedAt) / F.CollapseSeconds
				size = F.BurstStuds + (ballWidth() * F.BubbleBallWidths - F.BurstStuds) * easeOut(u)
				alpha = F.BubbleTransparency + (1 - F.BubbleTransparency) * u * u
				at = if cueOn then (cuePart :: BasePart).Position else live.centre
			elseif live.look > 0.001 and cueOn then
				local swell = 0
				if live.contactAt then
					swell = math.clamp((t - live.contactAt) / S.FreezeAfterSeconds, 0, 1)
				end
				size = ballWidth()
					* (F.BubbleBallWidths + (F.SwellBallWidths - F.BubbleBallWidths) * swell)
					* (0.5 + 0.5 * live.look)
				alpha = 1 - (1 - F.BubbleTransparency) * live.look
				at = (cuePart :: BasePart).Position
			end
			if at and size > 0 then
				sizeTo(self, bubble, "TimeBubble", size)
				bubble.CFrame = CFrame.new(at) * CFrame.Angles(0, live.spin, 0)
				bubble.Transparency = alpha
				-- The warp pattern only while it is small: blown up across the table its
				-- streaks turn to blocky bars, and the plain ForceField reads as a clear lens.
				local template = self.meshes and self.meshes.parts.TimeBubble
				local plain = size > ballWidth() * F.PatternMaxBallWidths
				bubble.TextureID = if plain or template == nil then "" else template.TextureID
			else
				bubble.Transparency = 1
			end
		end
		-- The clock face round the frozen cue ball, its hand sweeping the stopped time once.
		local clockOn = frozen and live.centre ~= nil
		if clockOn and live.face == nil then
			live.face = newMesh(self, live, "ClockFace")
			live.hand = newMesh(self, live, "ClockHand")
		end
		local face, hand = live.face, live.hand
		if face and hand then
			local centre = live.centre
			local shown = if clockOn and live.frozeAt
				then math.clamp((t - live.frozeAt) / F.ClockFadeSeconds, 0, 1)
				else 0
			if centre and shown > 0 then
				local studs = ballWidth() * F.ClockBallWidths
				local lift = Vector3.yAxis
					* (F.LiftInches * Config.Table.StudsPerInch - ballWidth() / 2)
				sizeTo(self, face, "ClockFace", studs)
				face.CFrame = CFrame.new(centre + lift)
				local base = self.meshes and self.meshes.sizes.ClockHand
				if base then
					local scale = studs / 2
					hand.Size = base * scale
					local length = base.Z * scale
					local turn = -2
						* math.pi
						* math.clamp(
							(t - (live.handFrom or live.frozeAt) :: number) / S.FrozenSeconds,
							0,
							1
						)
					hand.CFrame = CFrame.new(centre + lift + Vector3.yAxis * 0.01)
						* CFrame.Angles(0, turn, 0)
						* CFrame.new(0, 0, length * F.HandCentreShare)
				end
				local alpha = 1 - (1 - F.ClockTransparency) * shown
				face.Transparency = alpha
				hand.Transparency = alpha
			else
				face.Transparency = 1
				hand.Transparency = 1
				if not clockOn then
					face:Destroy()
					hand:Destroy()
					live.face, live.hand = nil, nil
				end
			end
		end
		local collapsing = live.resumedAt ~= nil and t - live.resumedAt < F.CollapseSeconds
		if not wantArmed and not shot and not collapsing and live.look <= 0.001 then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function TimeStopFx.clear(self: TimeStopFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return TimeStopFx
