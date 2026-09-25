--!strict
-- WatchedShooters: everyone else's shooter, as this client draws them. At every table whose
-- balls are drawn (Hub's pool, Config.Hub.RenderedTables) the player lining up there is
-- posed in their stance, FULLY VISIBLE, holding their cue (the drawn pitch and the wind-up
-- off the aim stream), stretching over the rail or up on the table when the ball is out of
-- reach.
-- When the replay of their shot starts, the stroke plays from the exact angle and cue-ball
-- spot the server accepted (Hub.shots), and the body then idles at the spot it shot from
-- (the server's ShotSpot, see ShooterPoser) until the server lets the root go
-- (Engine.shooterHeld) and the player walks off while the balls roll.
--
-- A remote body is only ever moved on this client: its limbs are anchored and placed here
-- while it is posed, and nothing else about it is touched (never its transparency, never its
-- Animate script: that is only ever the local player's own, in Avatar). Every way a pose can
-- end goes through drop(), which destroys the poser (every limb let go) and hides the cue:
--   the shooter changes or the turn passes    the snapshot's shooter, Engine.shooterLocked
--   the game ends, a new one starts           Engine.shooterLocked (Result, Waiting, ...)
--   the table leaves the pool                 Hub.rebind -> unbind, and cueOf each frame
--   the shooter respawns                      their Character is a different model
--   the shooter leaves the game               Players.PlayerRemoving -> forgetUser
--   the body is taken out of the game         its Parent is nil
--   the local player becomes the shooter      Avatar poses them instead
-- and the server letting the root go early is the poser's own guard.
--
-- TableService.constrain holds a shooter only while Engine.shooterLocked is true (and lets
-- them walk once their stroke has played, Engine.shooterHeld), and the poser's own guard lets
-- the limbs go the moment the root is let go, so a body is only ever posed here while the
-- server holds its root.
--
-- One slot per pooled cue, built up front with its frame and its inputs, so a frame
-- allocates nothing here. A table far from the camera poses less often (Config.Avatar.Watch).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AimStream = require(Shared:WaitForChild("AimStream"))
local AvatarPose = require(Shared:WaitForChild("AvatarPose"))
local Config = require(Shared:WaitForChild("Config"))
local CueClearance = require(Shared:WaitForChild("CueClearance"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local Placement = require(Shared:WaitForChild("Placement"))
local ShooterStance = require(Shared:WaitForChild("ShooterStance"))
local Engine = require(Shared:WaitForChild("Rules"):WaitForChild("MatchEngine"))
local Match = require(script.Parent:WaitForChild("Match"))
local ShooterPoser = require(script.Parent:WaitForChild("ShooterPoser"))

local WatchedShooters = {}
WatchedShooters.__index = WatchedShooters

-- One table's live aim off the stream (Hub): what was last heard, and what is drawn,
-- eased so a stream of a few a second never steps.
export type Aim = {
	angle: number, -- radians, last heard
	shown: number, -- ...as drawn
	by: number, -- the shooter's UserId
	x: number, -- cue ball, table inches, last heard
	y: number,
	shownX: number, -- ...as drawn (a ball in hand slides)
	shownY: number,
	pull: number, -- the wind-up, 0..1, whole 1/Config.Aim.PullSteps steps
	shownPull: number,
	elevation: number?, -- the shooter's cue angle, degrees (the drawn cue never goes lower)
}

-- The last shot the server accepted at a table (ShotResult), as a stroke freezes on it.
export type Shot = {
	epoch: number,
	seq: number,
	angle: number, -- the direction the cue ball left in, radians
	x: number, -- where the cue ball stood before the shot, table inches
	y: number,
}

-- What update() reads from the Hub this frame, all keyed by table id.
type Source = {
	cueOf: { [number]: Model }, -- the pooled cue drawing each table
	snapshots: { [number]: any },
	matches: { [number]: Match.Match },
	aims: { [number]: Aim },
	shots: { [number]: Shot },
}

-- CueClearance's last answer for a slot, reused while the aim, the ball and the table stand
-- still (a shooter thinking costs nothing).
type Clearance = {
	valid: boolean,
	angle: number,
	x: number,
	y: number,
	seq: number, -- the Match's shot and shown-down counters: the balls have not moved since
	version: number,
	elevation: number,
	degrees: number,
}

-- One pooled cue and everything drawn with it.
type Slot = {
	cue: Model, -- Hub's, bound to a table by Hub.cueOf
	frame: AvatarPose.Frame,
	inputs: ShooterPoser.Inputs,
	query: CueClearance.Query,
	clearance: Clearance,
	tableId: number?, -- the table this slot drew last
	userId: number?, -- the shooter posed, and the body
	character: Model?,
	poser: ShooterPoser.Poser?,
	epoch: number, -- the turn: a new one aims afresh
	turnId: number,
	memory: ShooterStance.Memory?, -- the stance's hysteresis, threaded through one turn
	-- What is drawn: the live aim, or the shot's own numbers once the stroke is frozen on them.
	angle: number,
	x: number, -- cue ball, table inches
	y: number,
	pull: number,
	elevation: number, -- the shooter's chosen cue angle, the floor for the drawn pitch
	pitch: number?, -- the drawn pitch, eased (nil: snap to the next target)
	-- The stroke has started: the inputs above (and the memory) no longer follow the aim, so
	-- compose() solves the very stance the stroke started from every frame.
	frozen: boolean,
	strikeSeq: number?, -- the replay this turn's stroke was started for
	sincePose: number, -- seconds since this slot last posed (far tables)
	-- The last compose(): what it was given. While nothing has moved it is not asked again (a
	-- shooter thinking costs no stance solve): the frame and the cue stay as they are.
	composed: boolean,
	composedAngle: number,
	composedX: number,
	composedY: number,
	composedPull: number,
	composedPitch: number,
	composedBody: ShooterStance.Body?,
}

export type WatchedShooters = typeof(setmetatable(
	{} :: {
		slots: { [Model]: Slot },
		source: Source, -- this frame's, refilled by update()
	},
	WatchedShooters
))

-- The phases a shooter lines up in: only then is their aim drawn live.
local AIM_PHASES: { [string]: boolean } = { Intro = true, Placement = true, Aiming = true }

-- Below these an aim, a ball, a wind-up and a pitch count as still (radians, table inches, a
-- share of a full pull, degrees): far finer than anything shows, and the eased values settle
-- under them within a second or two. (internal)
local STILL_ANGLE = 1e-5
local STILL_SPOT = 1e-4
local STILL_PULL = 1e-4
local STILL_PITCH = 1e-4

--- The watchers for Hub's pooled cues: one slot per cue, built now.
function WatchedShooters.new(cues: { Model }): WatchedShooters
	local slots: { [Model]: Slot } = {}
	for _, cue in cues do
		slots[cue] = {
			cue = cue,
			frame = AvatarPose.newFrame(),
			inputs = {
				placement = Placement.new(0, 0, 0, 0), -- the table's, before every compose()
				teamSize = 1,
				body = Config.Stance.DefaultBody,
				cueX = 0,
				cueY = 0,
				angle = 0,
				spinX = 0, -- the aim stream carries no spin: the cue is drawn at the centre
				spinY = 0,
				pitch = Config.Cue.CueElevationDegrees,
				pull = 0,
				gap = nil,
				memory = nil,
			},
			query = { cueX = 0, cueY = 0, angle = 0 },
			clearance = {
				valid = false,
				angle = 0,
				x = 0,
				y = 0,
				seq = 0,
				version = 0,
				elevation = 0,
				degrees = 0,
			},
			tableId = nil,
			userId = nil,
			character = nil,
			poser = nil,
			epoch = -1,
			turnId = -1,
			memory = nil,
			angle = 0,
			x = 0,
			y = 0,
			pull = 0,
			elevation = Config.Cue.CueElevationDegrees,
			pitch = nil,
			frozen = false,
			strikeSeq = nil,
			sincePose = math.huge,
			composed = false,
			composedAngle = 0,
			composedX = 0,
			composedY = 0,
			composedPull = 0,
			composedPitch = 0,
			composedBody = nil,
		}
	end
	return setmetatable({
		slots = slots,
		source = { cueOf = {}, snapshots = {}, matches = {}, aims = {}, shots = {} },
	}, WatchedShooters)
end

-- A new turn (or a new shooter) aims afresh: nothing frozen, no hysteresis carried over.
local function forgetTurn(slot: Slot)
	slot.memory = nil
	slot.pitch = nil
	slot.frozen = false
	slot.strikeSeq = nil
	slot.sincePose = math.huge
	slot.composed = false
end

-- Let go of whoever this slot posed: every limb back as it was, the cue hidden.
local function drop(slot: Slot)
	if slot.poser then
		slot.poser:destroy()
		slot.poser = nil
	end
	if slot.userId ~= nil then
		slot.userId, slot.character = nil, nil
		slot.epoch, slot.turnId = -1, -1
		forgetTurn(slot)
	end
	CueStickBuilder.setVisible(slot.cue, false)
end

--- Table `id` has left the pool: let go of its shooter.
function WatchedShooters.unbind(self: WatchedShooters, id: number)
	for _, slot in self.slots do
		if slot.tableId == id then
			drop(slot)
			slot.tableId = nil
		end
	end
end

--- The player `userId` has left the game: let go of their body wherever it is posed.
function WatchedShooters.forgetUser(self: WatchedShooters, userId: number)
	for _, slot in self.slots do
		if slot.userId == userId then
			drop(slot)
		end
	end
end

-- The drawn cue's pitch for the slot's aim (CueClearance, VISUAL ONLY), asked again only when
-- the aim, the ball or the table's balls have moved.
local function pitchTarget(slot: Slot, m: Match.Match): number
	local c = slot.clearance
	if
		c.valid
		and c.seq == m.seq
		and c.version == m.downVersion
		and c.elevation == slot.elevation
		and math.abs(AimStream.angleDelta(slot.angle, c.angle)) < STILL_ANGLE
		and math.abs(slot.x - c.x) < STILL_SPOT
		and math.abs(slot.y - c.y) < STILL_SPOT
	then
		return c.degrees
	end
	local q = slot.query
	q.cueX, q.cueY, q.angle, q.floorDegrees = slot.x, slot.y, slot.angle, slot.elevation
	c.degrees = CueClearance.pitch(m.state.geometry, m.state.balls, q).degrees
	c.valid, c.seq, c.version, c.elevation = true, m.seq, m.downVersion, slot.elevation
	c.angle, c.x, c.y = slot.angle, slot.x, slot.y
	return c.degrees
end

-- One pooled table this frame.
local function step(
	slot: Slot,
	id: number,
	dt: number,
	source: Source,
	me: Player,
	cameraPos: Vector3?
)
	local s = source.snapshots[id]
	local m: Match.Match? = source.matches[id]
	local shooterId = if s then s.shooter else nil
	if
		s == nil
		or not m
		or type(shooterId) ~= "number"
		or shooterId == me.UserId
		or not Engine.shooterLocked(s.phase, s.solo)
	then
		drop(slot)
		return
	end
	local owner = Players:GetPlayerByUserId(shooterId)
	local character = owner and owner.Character
	if character == nil or character.Parent == nil or character == me.Character then
		drop(slot)
		return
	end
	-- A different shooter, or the same one respawned: start again with a fresh poser.
	if slot.userId ~= shooterId or slot.character ~= character then
		drop(slot)
		slot.userId, slot.character = shooterId, character
	end
	local poser = slot.poser
	if poser == nil then
		poser = ShooterPoser.new(character, false)
		slot.poser = poser
	end
	assert(poser, "unreachable")
	if slot.epoch ~= s.epoch or slot.turnId ~= s.turnId then
		slot.epoch, slot.turnId = s.epoch, s.turnId
		-- A stroke still playing belongs to the last turn's shot.
		if poser:stroking() then
			poser:cancelStroke()
		end
		forgetTurn(slot)
	end

	local aim = source.aims[id]
	local busy = m:isBusy()
	local ball = m:findCueBall()
	local lining = AIM_PHASES[s.phase] == true and not busy and ball ~= nil and not ball.pocketed
	local heard = lining and aim ~= nil and aim.by == shooterId
	if heard and aim and ball then
		-- The ball, not the stream's spot: a ball in hand is eased onto its spot (Hub).
		slot.angle, slot.x, slot.y, slot.pull = aim.shown, ball.x, ball.y, aim.shownPull
		slot.elevation = aim.elevation or Config.Cue.CueElevationDegrees
	end
	-- The server drops a table from the aim stream the moment it accepts the shot, and the
	-- stream is unreliable, so that can land a frame or more before the ShotResult starts the
	-- replay: the last aim drawn this turn is held until then, or the body would idle and the
	-- stroke never play.
	local aimLive = heard or (lining and slot.composed and poser.state == "aim")

	-- The replay of this turn's shot has started: the stroke plays, frozen on the numbers the
	-- server accepted (the aim may already be gone from the stream), or the last aim drawn.
	local strike = busy and slot.strikeSeq ~= m.seq and poser.state == "aim"
	if strike then
		slot.strikeSeq = m.seq
		local shot = source.shots[id]
		if shot and shot.epoch == m.epoch and shot.seq == m.seq then
			slot.angle, slot.x, slot.y = shot.angle, shot.x, shot.y
		end
		slot.frozen = true
	end

	local gap = poser:advance(dt)
	if gap == nil and not aimLive and not strike then
		-- Nothing to line up: the body is the owner's again (idle after the stroke, or as the
		-- server holds it), with no cue.
		poser:pose("idle", nil, dt)
		CueStickBuilder.setVisible(slot.cue, false)
		slot.sincePose = math.huge -- the next aim poses at once
		return
	end

	-- Far away, pose less often; a stroke starting always lands at once.
	local W = Config.Avatar.Watch
	local p = m.placement
	slot.sincePose += dt
	if
		not strike
		and cameraPos ~= nil
		and (cameraPos - Vector3.new(p.x, p.y, p.z)).Magnitude > W.FarStuds
		and slot.sincePose < 1 / W.FarPosesPerSecond
	then
		return
	end
	local elapsed = slot.sincePose
	slot.sincePose = 0

	if not slot.frozen or slot.pitch == nil then
		local target = pitchTarget(slot, m)
		local shown = slot.pitch
		slot.pitch = if shown then CueClearance.ease(shown, target, elapsed) else target
	end

	-- The measured body, as the server measures the one it places; a rig that cannot be
	-- measured stands as the default one.
	local body = AvatarPose.measureBody(character) or Config.Stance.DefaultBody
	local pitch = slot.pitch or Config.Cue.CueElevationDegrees
	local still = slot.composed
		and gap == nil
		and not strike
		and body == slot.composedBody
		and math.abs(AimStream.angleDelta(slot.angle, slot.composedAngle)) < STILL_ANGLE
		and math.abs(slot.x - slot.composedX) < STILL_SPOT
		and math.abs(slot.y - slot.composedY) < STILL_SPOT
		and math.abs(slot.pull - slot.composedPull) < STILL_PULL
		and math.abs(pitch - slot.composedPitch) < STILL_PITCH
	if not still then
		local inputs = slot.inputs
		inputs.placement = p
		inputs.teamSize = s.teamSize or 1
		inputs.body = body
		inputs.cueX, inputs.cueY = slot.x, slot.y
		inputs.angle = slot.angle
		inputs.pitch = pitch
		inputs.pull = slot.pull
		inputs.gap = gap
		inputs.memory = slot.memory
		local stance, tip = ShooterPoser.compose(inputs, slot.frame)
		if not slot.frozen then
			slot.memory = stance.memory
		end
		slot.composed = true
		slot.composedAngle, slot.composedX, slot.composedY = slot.angle, slot.x, slot.y
		slot.composedPull, slot.composedPitch, slot.composedBody = slot.pull, pitch, body
		CueStickBuilder.placeAt(slot.cue, tip)
		if strike then
			-- The stroke starts from the cue as it is drawn this frame (the wind-up at the
			-- let-go), the ball already moving; the body idles at the stance's spot unless the
			-- server's ShotSpot says otherwise.
			poser:strike(
				stance.cueGapStuds,
				true,
				Config.Avatar.Stroke.WatcherSeconds,
				ShooterPoser.idleSpot(p, stance)
			)
		end
	end
	-- Posed even when still: the root may still be easing onto the stance, and the poser skips
	-- a frame that changes nothing itself.
	poser:pose("aim", slot.frame, elapsed)
	CueStickBuilder.setVisible(slot.cue, true)
end

--- Pose every pooled table's shooter for this frame, from the Hub's tables (keyed by table
--- id): the cue each pooled table is drawn with, the snapshots, the Matches, the aims (eased
--- already) and the last shot accepted at each.
function WatchedShooters.update(
	self: WatchedShooters,
	dt: number,
	cueOf: { [number]: Model },
	snapshots: { [number]: any },
	matches: { [number]: Match.Match },
	aims: { [number]: Aim },
	shots: { [number]: Shot }
)
	debug.profilebegin("WatchedShooters")
	local source = self.source
	source.cueOf, source.snapshots, source.matches = cueOf, snapshots, matches
	source.aims, source.shots = aims, shots
	-- A slot whose table has left the pool (Hub.rebind also calls unbind).
	for cue, slot in self.slots do
		local id = slot.tableId
		if id ~= nil and cueOf[id] ~= cue then
			drop(slot)
			slot.tableId = nil
		end
	end
	local me = Players.LocalPlayer
	local camera = Workspace.CurrentCamera
	local cameraPos = if camera then camera.CFrame.Position else nil
	for id, cue in cueOf do
		local slot = self.slots[cue]
		if slot then
			if slot.tableId ~= id then
				drop(slot)
				slot.tableId = id
			end
			step(slot, id, dt, source, me, cameraPos)
		end
	end
	debug.profileend()
end

return WatchedShooters
