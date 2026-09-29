--!strict
-- RewindFx: what Rewind looks and sounds like (docs/prompts/ABILITIES_PROMPT.md 7.6, reference
-- 02). The rule is the match engine's (a try that drops none of the shooter's balls is undone
-- and shot again on a 10 s clock); the balls flying back is Match's playback of the shot's
-- frames (Match.startRewind). This draws the rest. Numbers in Config.UI.RewindFx, the sounds in
-- Config.Ults.Audio, the dial in the uploaded Rewind model (tools/blender/abilities/rewind.py)
-- and the screen's images in Config.Ults.Assets.Images (Rewind*).
--
--   * Armed: a flat dial (a counter-clockwise arrow round clock ticks, split magenta, white and
--     green like the reference) pops in round the cue ball with a cassette's clack and turns
--     slowly backward while they aim.
--   * The Rewind shot: the dial stays where the cue ball started (where the table will come
--     back to), with a see-through pink ghost of the cue ball on the spot. If one of the
--     shooter's balls drops, nothing is undone: the dial glitches out with a click.
--   * The rewind (the snapshot's Rewinding phase), for everyone at the table: a VHS rewind on
--     the screen (a colour grade, the edges split magenta and green, scanlines, grain, tearing
--     bands, a tracking band rolling up and the big glitching rewind icon pulsing in the
--     middle) with a tape whirr climbing in pitch; the dial spins fast; the balls fly back
--     along their paths with white-magenta-green streaks. As the table lands, a clunk, a
--     flash, and it all clears. MatchHUD then shows SECOND CHANCE: 10s.
-- Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or with
-- clear(). Without the model the dial is skipped; the rest still shows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local F = Config.UI.RewindFx
local A = Config.Ults.Audio
local IMAGES = Config.Ults.Assets.Images :: any

local ULT = "Rewind"
local MODEL = "Rewind"
local PIECE = "RewindDial"

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

-- One ball's streak: an invisible follower (not turning with the ball) carrying a Trail.
type Streak = { part: Part, trail: Trail }

-- The rewind moment at a table.
type Moment = {
	at: number, -- the server's rewound.at
	handles: { any }, -- ScreenFx handles, released as the table lands
	whirr: Sound?,
	started: number, -- os.clock() it began here
	played: boolean, -- Match's playback has been seen running
	landed: boolean,
	streaks: { [number]: Streak },
}

type TableFx = {
	anchor: BasePart,
	dial: MeshPart?,
	ghost: Part,
	look: number, -- the dial's opacity, 0..1
	pop: number, -- the dial's pop-in, 0..1
	spin: number, -- radians
	spot: { number }?, -- the cue ball's start spot during the shot and the rewind (inches)
	shotSeq: number, -- the Rewind shot being watched (0: none)
	spentAt: number?, -- os.clock() the try was judged spent (the dial glitches out)
	moment: Moment?,
	pulse: number, -- os.clock() the landing's pulse began (0: none)
}

export type RewindFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	seenRewind: { [number]: number }, -- the last rewound.at handled per table
	template: MeshPart?,
	templateFailed: boolean,
	nextCheck: number,
}

local RewindFx = {}
RewindFx.__index = RewindFx

local function templateOf(self: RewindFx): MeshPart?
	if self.template or self.templateFailed then
		return self.template
	end
	local now = os.clock()
	if now < self.nextCheck then
		return nil
	end
	self.nextCheck = now + F.ModelCheckSeconds
	local model = self.kit.models.tryGet(MODEL)
	if model == nil then
		return nil
	end
	local part = model:FindFirstChild(PIECE, true)
	if part == nil or not part:IsA("MeshPart") then
		self.templateFailed = true
		warn(("[8ball] RewindFx: the %s model has no %s"):format(MODEL, PIECE))
		return nil
	end
	local mesh = part :: MeshPart
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.CastShadow = false
	mesh.Transparency = 1
	self.template = mesh
	return mesh
end

local function create(self: RewindFx, id: number): TableFx
	local kit = self.kit
	local anchor = kit.anchor(id)
	local ghost = kit.part(id, "RewindGhost", {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		Color = rgb(F.GhostColor),
		Transparency = 1,
		Size = Vector3.one * ballWidth(),
	})
	local fx: TableFx = {
		anchor = anchor,
		dial = nil,
		ghost = ghost,
		look = 0,
		pop = 0,
		spin = 0,
		spot = nil,
		shotSeq = 0,
		spentAt = nil,
		moment = nil,
		pulse = 0,
	}
	self.tables[id] = fx
	return fx
end

local function ensureDial(self: RewindFx, fx: TableFx): MeshPart?
	if fx.dial and fx.dial.Parent then
		return fx.dial
	end
	local template = templateOf(self)
	if template == nil then
		return nil
	end
	local dial = template:Clone()
	dial.Name = "RewindDial"
	local across = ballWidth() * F.DialBallWidths
	dial.Size = template.Size * (across / math.max(template.Size.X, template.Size.Z))
	dial.Transparency = 1
	dial.Parent = fx.anchor
	fx.dial = dial
	return dial
end

local function dropStreaks(moment: Moment)
	for _, s in moment.streaks do
		s.part:Destroy()
	end
	table.clear(moment.streaks)
end

local function endMoment(fx: TableFx)
	local moment = fx.moment
	if moment == nil then
		return
	end
	fx.moment = nil
	for _, h in moment.handles do
		h:release()
	end
	if moment.whirr then
		moment.whirr:Destroy()
	end
	dropStreaks(moment)
end

local function destroy(self: RewindFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	endMoment(fx)
	if fx.dial then
		fx.dial:Destroy()
	end
	fx.ghost:Destroy()
end

local function playAt(self: RewindFx, id: number, clip: any, at: Vector3, pitch: number?): Sound?
	local kit = self.kit
	local holder = kit.attachment(id, "RewindSound", at)
	local sound = kit.sound.library(clip, holder, { pitch = pitch })
	kit.later(id, 4, function()
		holder:Destroy()
	end)
	return sound
end

-- A sound for the whole table: flat for the players in the match, at the table for anyone
-- else in earshot.
local function playTable(self: RewindFx, id: number, m: any, clip: any): Sound?
	local kit = self.kit
	if kit.screen.involved(self.hub, id) then
		return kit.sound.library(clip, nil, nil)
	end
	return playAt(self, id, clip, kit.tableWorld(m, 0, 0, 0))
end

-- The VHS screen, held until the table lands.
local function screen(self: RewindFx, id: number, moment: Moment)
	local S = self.kit.screen
	local hold = math.huge
	local function keep(h: any)
		if h then
			table.insert(moment.handles, h)
		end
	end
	keep(S.grade(id, F.Grade, F.FadeIn, hold, F.FadeOut))
	keep(S.overlay(id, IMAGES.RewindFringe, {
		fadeIn = F.FadeIn,
		hold = hold,
		fadeOut = F.FadeOut,
		transparency = F.FringeTransparency,
		jitter = F.FringeJitter,
	}))
	keep(S.overlay(id, IMAGES.RewindScanlines, {
		fadeIn = F.FadeIn,
		hold = hold,
		fadeOut = F.FadeOut,
		transparency = F.ScanTransparency,
	}))
	keep(S.overlay(id, IMAGES.RewindStatic, {
		fadeIn = F.FadeIn,
		hold = hold,
		fadeOut = F.FadeOut,
		transparency = F.StaticTransparency,
		rows = 2,
		cols = 2,
		fps = F.StaticFps,
	}))
	keep(S.overlay(id, IMAGES.RewindTracking, {
		fadeIn = F.FadeIn,
		hold = hold,
		fadeOut = F.FadeOut,
		transparency = F.TrackingTransparency,
		scroll = { 0, -F.TrackingScroll },
	}))
	keep(S.overlay(id, IMAGES.RewindTear, {
		fadeIn = F.FadeIn,
		hold = hold,
		fadeOut = F.FadeOut,
		transparency = F.TearTransparency,
		jitter = F.TearJitter,
		jitterSeconds = F.TearJitterSeconds,
	}))
	keep(S.overlay(id, IMAGES.RewindIcon, {
		fadeIn = F.FadeIn,
		hold = hold,
		fadeOut = F.FadeOut,
		transparency = F.IconTransparency,
		rows = 4,
		cols = 4,
		fps = F.IconFps,
		square = F.IconSquare,
		pulseHz = F.IconPulseHz,
		pulseShare = F.IconPulseShare,
	}))
	S.flash(id, F.StartFlash, F.StartFlashSeconds)
	S.shake(id, F.ShakeStuds, F.ShakeSeconds)
end

local function beginMoment(self: RewindFx, id: number, fx: TableFx, m: any, at: number)
	endMoment(fx)
	local moment: Moment = {
		at = at,
		handles = {},
		whirr = nil,
		started = os.clock(),
		played = false,
		landed = false,
		streaks = {},
	}
	fx.moment = moment
	fx.spentAt = nil
	fx.shotSeq = 0 -- undone, not spent
	fx.pulse = 0
	screen(self, id, moment)
	local whirr = playTable(self, id, m, A.RewindWhirr)
	moment.whirr = whirr
	if whirr then
		whirr.PlaybackSpeed = F.WhirrPitchFrom
	end
	-- Held through the moment even with no shot running before the playback starts.
	self.kit.keep(id, Config.Ults.Shared.RewindSeconds + 1)
end

local function land(self: RewindFx, id: number, fx: TableFx, m: any)
	local moment = fx.moment
	if moment == nil or moment.landed then
		return
	end
	moment.landed = true
	local S = self.kit.screen
	for _, h in moment.handles do
		h:release()
	end
	table.clear(moment.handles)
	if moment.whirr then
		moment.whirr:Destroy()
		moment.whirr = nil
	end
	S.flash(id, F.LandFlash, F.LandFlashSeconds)
	playTable(self, id, m, A.RewindClunk)
	fx.pulse = os.clock()
	-- The streaks finish drawing out, then go.
	self.kit.later(id, F.StreakSeconds + 0.1, function()
		if fx.moment == moment then
			dropStreaks(moment)
			fx.moment = nil
		end
	end)
end

-- The balls' streaks follow them while the table flies back.
local function stepStreaks(self: RewindFx, id: number, fx: TableFx, m: any)
	local moment = fx.moment
	if moment == nil or moment.landed then
		return
	end
	local positions = m:rewindPositions()
	if positions == nil then
		return
	end
	local kit = self.kit
	local width = ballWidth() * F.StreakBallWidths
	for ballId in positions do
		local part = kit.ballPart(id, ballId)
		local shown = part ~= nil and (part :: BasePart).Transparency < 0.5
		local streak = moment.streaks[ballId]
		if streak == nil and shown then
			local holder = kit.part(id, "RewindStreak", {
				Transparency = 1,
				Size = Vector3.one * 0.05,
			})
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, width / 2, 0)
			a0.Parent = holder
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -width / 2, 0)
			a1.Parent = holder
			local trail = Instance.new("Trail")
			trail.Attachment0, trail.Attachment1 = a0, a1
			trail.FaceCamera = true
			trail.Lifetime = F.StreakSeconds
			trail.MinLength = 0.02
			trail.LightEmission = 1
			local c = F.StreakColors
			trail.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb(c[1])),
				ColorSequenceKeypoint.new(0.35, rgb(c[2])),
				ColorSequenceKeypoint.new(1, rgb(c[3])),
			})
			trail.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, F.StreakTransparency),
				NumberSequenceKeypoint.new(1, 1),
			})
			trail.WidthScale = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0.3),
			})
			trail.Parent = holder
			holder.CFrame = CFrame.new((part :: BasePart).Position)
			streak = { part = holder, trail = trail }
			moment.streaks[ballId] = streak
		end
		if streak then
			streak.trail.Enabled = shown
			if shown then
				streak.part.CFrame = CFrame.new((part :: BasePart).Position)
			end
		end
	end
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function RewindFx.start(hub: any, _parent: Instance, kit: any): RewindFx
	local self: RewindFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		seenRewind = {},
		template = nil,
		templateFailed = false,
		nextCheck = 0,
	}, RewindFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			endMoment(fx)
		end
		self.tables[tableId] = nil -- its parts went with the anchor
	end)
	-- Fetch the sounds and the screen's images now, so the first rewind is whole.
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in { A.RewindArm, A.RewindWhirr, A.RewindClunk, A.RewindSpent } do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		for _, key in
			{
				"RewindIcon",
				"RewindStatic",
				"RewindScanlines",
				"RewindTear",
				"RewindTracking",
				"RewindFringe",
			}
		do
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

--- The arming moment at table `tableId` (UltCutscene's onArming): the dial pops in with a
--- cassette's clack.
function RewindFx.arming(self: RewindFx, tableId: number, armed: any)
	local m = self.hub:matchFor(tableId)
	if armed == nil or armed.id ~= ULT or m == nil or m.renderer == nil then
		return
	end
	local fx = self.tables[tableId] or create(self, tableId)
	fx.pop = 0
	fx.spentAt = nil
	ensureDial(self, fx)
	local cue = m:findCueBall()
	if cue then
		playAt(self, tableId, A.RewindArm, self.kit.ballWorld(m, cue))
	end
end

--- Every frame, after the hub has stepped the replays.
function RewindFx.update(self: RewindFx, dt: number)
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
		local snapshot = self.hub.snapshots[id]
		local armed = kit.armedOf(snapshot)
		local isArmed = armed ~= nil
			and armed.id == ULT
			and not m:isBusy()
			and (armed.stage == "Armed" or now >= (armed.readyAt or math.huge))
		local shot = m.shot ~= nil and m.shot.ult == ULT
		-- The rewind moment: the snapshot's Rewinding phase, once per rewound.at.
		local rewound = snapshot and snapshot.rewound
		local fresh = type(rewound) == "table"
			and type(rewound.at) == "number"
			and snapshot.phase == "Rewinding"
			and self.seenRewind[id] ~= rewound.at
		if fresh then
			self.seenRewind[id] = rewound.at
		end
		local startMoment = fresh and now - rewound.at < F.FreshSeconds
		if fx == nil then
			if not (isArmed or shot or startMoment) then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		if startMoment then
			beginMoment(self, id, live, m, rewound.at)
		end
		-- The spot the table comes back to: where the cue ball began the Rewind shot.
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
			live.spot = m.shot.cueStart
			live.spentAt = nil
		end
		-- A Rewind shot that finished without being undone: the ability is spent.
		if
			not shot
			and live.shotSeq ~= 0
			and live.moment == nil
			and live.spentAt == nil
			and m.seq == live.shotSeq
			and m.tape == nil
			and m.rewinding == nil
		then
			live.spentAt = t
			live.shotSeq = 0
			local dial = live.dial
			if dial and live.look > 0.01 then
				playAt(self, id, A.RewindSpent, dial.Position)
			end
		end
		local moment = live.moment
		if moment then
			if m.rewinding then
				moment.played = true
			end
			stepStreaks(self, id, live, m)
			-- The whirr: sped up to fill the playback, climbing in pitch as it goes.
			local length = F.LeadSeconds + F.MaxPlaySeconds
			local u = math.clamp((t - moment.started) / length, 0, 1)
			if moment.whirr then
				moment.whirr.PlaybackSpeed = F.WhirrPitchFrom
					+ (F.WhirrPitchTo - F.WhirrPitchFrom) * u
			end
			-- Lands when the playback ends, or (no playback here) after the usual length.
			local over = (moment.played and m.rewinding == nil)
				or (not moment.played and t - moment.started >= length)
				or snapshot.phase ~= "Rewinding"
			if over and not moment.landed then
				land(self, id, live, m)
			end
		end
		-- The dial: round the cue ball while armed; on the start spot through the shot and the
		-- rewind; glitching out when spent; pulsing out as the table lands.
		local rewinding = live.moment ~= nil and not live.moment.landed
		local spotOn = (shot or rewinding) and live.spot ~= nil
		local want = isArmed or spotOn
		local spent = live.spentAt ~= nil and t - (live.spentAt :: number) < F.SpentSeconds
		local pulsing = live.pulse > 0 and t - live.pulse < F.PopSeconds * 2
		if isArmed and not spotOn then
			live.spot = nil
		end
		live.look = approach(live.look, if want then 1 else 0, dt, F.PopSeconds)
		if spent then
			live.look = 1 - (t - (live.spentAt :: number)) / F.SpentSeconds
		end
		live.pop = approach(live.pop, if want then 1 else 0, dt, F.PopSeconds)
		local speed = if rewinding then F.RewindSpinDegreesPerSecond else F.SpinDegreesPerSecond
		live.spin += math.rad(speed) * dt
		local centre: Vector3? = nil
		local spot = live.spot
		if spot then
			centre = kit.tableWorld(m, spot[1], spot[2], F.LiftInches)
		else
			local cue = m:findCueBall()
			if cue and not cue.pocketed then
				centre = kit.tableWorld(m, cue.x, cue.y, F.LiftInches)
			end
		end
		local dial = if live.look > 0.001 or want then ensureDial(self, live) else live.dial
		if dial and centre then
			local size = 0.6 + 0.4 * live.pop
			if pulsing then
				size *= 1 + 0.5 * (t - live.pulse) / (F.PopSeconds * 2)
			end
			local template = self.template
			if template then
				local across = ballWidth() * F.DialBallWidths * size
				dial.Size = template.Size * (across / math.max(template.Size.X, template.Size.Z))
			end
			dial.CFrame = CFrame.new(centre) * CFrame.Angles(0, live.spin, 0)
			local flicker = if spent
				then (if math.sin(t * F.FlickerHz * 2 * math.pi) > 0 then 1 else 0.3)
				else 1
			local opacity = live.look * flicker
			if pulsing then
				opacity *= 1 - (t - live.pulse) / (F.PopSeconds * 2)
			end
			dial.Transparency = 1 - (1 - F.DialTransparency) * math.clamp(opacity, 0, 1)
		elseif dial then
			dial.Transparency = 1
		end
		-- The ghost of the cue ball on the spot, while the real one is away.
		if spotOn and spot then
			live.ghost.CFrame =
				CFrame.new(kit.tableWorld(m, spot[1], spot[2], Config.Balls.RenderRadiusInches))
			live.ghost.Transparency = 1 - (1 - F.GhostTransparency) * live.look
		else
			live.ghost.Transparency = 1
		end
		if
			not want
			and not spent
			and live.look <= 0.001
			and live.moment == nil
			and not pulsing
			and live.shotSeq == 0
		then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function RewindFx.clear(self: RewindFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return RewindFx
