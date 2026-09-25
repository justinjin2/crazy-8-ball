--!strict
-- Avatar: the local player's own body as the shooter, through one ShooterPoser (a respawn gets
-- a new one). Every frame it works out the shot's look (the cue's pitch that clears the rail and
-- the balls, eased; the stance; the cue), hands the poser that frame, and gives Main the cue to
-- draw in the very same frame, which is what keeps the hands on it.
--
-- fire() calls strike(): the inputs freeze (angle, cue spot, spin, pitch, stance), so the body
-- never chases the ball once it moves, and the poser plays the stroke from the drawn wind-up into
-- the ball, rests there until the replay moves it (ballMoving), and follows through. After that
-- the body idles on its own, facing the table, at the spot the server holds it at, until the
-- next turn: straight back to aiming if it is this player's again; otherwise release() hands it
-- back where it stands. Before the shot, while the cue is hidden (the cue ball dragged in hand,
-- a modal open), the body idles too, but where the live stance stands, following it.
--
-- On this player's own screen the body is translucent (aiming and idle alike), fades out
-- entirely as the camera nears it and has its accessories hidden, so it never covers the table.
-- Everyone else sees it whole (WatchedShooters).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AvatarPose = require(Shared:WaitForChild("AvatarPose"))
local Config = require(Shared:WaitForChild("Config"))
local CueClearance = require(Shared:WaitForChild("CueClearance"))
local Placement = require(Shared:WaitForChild("Placement"))
local ShooterStance = require(Shared:WaitForChild("ShooterStance"))
local ShooterPoser = require(script.Parent.ShooterPoser)

local Avatar = {}
Avatar.__index = Avatar

-- What Main hands update() every frame (one table, filled in place).
export type Context = {
	placement: Placement.Placement?, -- the table being played
	teamSize: number, -- players a side there (the fence the stance stays inside)
	state: any, -- the match's ball state (geometry, balls): the drawn cue clears them
	cueX: number?, -- the cue ball, table inches; nil while it is down
	cueY: number?,
	angle: number, -- aim angle, radians
	pull: number, -- the wind-up drawn right now, 0..1
	spin: { x: number, y: number }?, -- strike offset, ball radii
	elevation: number?, -- the chosen cue angle, degrees: the drawn cue never goes lower
	showCue: boolean, -- the player may aim now (canShoot, and not dragging the cue ball)
	-- The shot is the player's to take and not taken yet (their turn, no shot sent, the balls
	-- still): while the cue is hidden all the same (the cue ball dragged, a modal open) the
	-- body idles where the live stance stands, following a dragged ball.
	aimTurn: boolean,
	cameraPos: Vector3?, -- where the camera is, for the body's fade
}

-- What update() returns (one table, reused): draw the cue from these.
export type Out = {
	visible: boolean, -- the cue is drawn (aiming or stroking)
	tip: CFrame, -- ...at this tip (CueStickBuilder.placeAt)
}

-- While the server holds the root (anchored, and in a collision group that touches nothing,
-- the floor included) the Humanoid finds no floor under it and may read Freefall, and the
-- Animate idle that plays after the stroke would then be the fall. So Freefall is off while
-- the root is held, and back as it was the moment the server lets the root go.
type Footing = {
	humanoid: Humanoid,
	root: BasePart,
	enabled: boolean, -- Freefall as it was
	conn: RBXScriptConnection?,
}

export type Avatar = typeof(setmetatable(
	{} :: {
		character: Model?,
		poser: ShooterPoser.Poser?,
		-- Whether the player is MEANT to be at a table, as opposed to whether this particular
		-- body currently is: a respawn hands over a fresh character, which is posed the moment
		-- it is meant to be.
		wanted: boolean,
		frame: AvatarPose.Frame,
		out: Out,
		-- compose()'s inputs: the live ones rebuilt every frame, and the stroke's, frozen at the
		-- strike (only while the stroke plays).
		live: ShooterPoser.Inputs?,
		liveValid: boolean, -- `live` was filled this turn (strike freezes from it)
		frozen: ShooterPoser.Inputs?,
		frozenValid: boolean,
		memory: ShooterStance.Memory?, -- the last live stance's, for its hysteresis
		-- The drawn pitch: shown (eased) and its target, worked out again only when what it
		-- depends on changes (a new turn can move the balls, so it forgets then).
		pitchShown: number?,
		pitchTarget: number,
		pitchKey: { number },
		pitchState: any,
		pitchQuery: CueClearance.Query,
		footing: Footing?,
	},
	Avatar
))

local FREEFALL = Enum.HumanoidStateType.Freefall

-- Keys for the pitch cache: the inputs the pitch depends on while the balls stand still.
local PITCH_ANGLE, PITCH_X, PITCH_Y, PITCH_SPIN_X, PITCH_SPIN_Y, PITCH_FLOOR = 1, 2, 3, 4, 5, 6

local function restGap(): number
	return Config.Cue.CueRestGapInches * Config.Table.StudsPerInch
end

-- Freefall back as it was: the server has let the root go, or the body is gone.
local function letGo(self: Avatar)
	local footing = self.footing
	if footing == nil then
		return
	end
	self.footing = nil
	if footing.conn then
		footing.conn:Disconnect()
	end
	if footing.humanoid.Parent then
		footing.humanoid:SetStateEnabled(FREEFALL, footing.enabled)
	end
end

-- Freefall off while the server holds the root (see Footing). Idempotent: one call a frame.
local function holdFooting(self: Avatar, character: Model)
	if self.footing then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or not root.Anchored then
		return
	end
	local footing: Footing = {
		humanoid = humanoid,
		root = root,
		enabled = humanoid:GetStateEnabled(FREEFALL),
		conn = nil,
	}
	footing.conn = root:GetPropertyChangedSignal("Anchored"):Connect(function()
		if not root.Anchored and self.footing == footing then
			letGo(self)
		end
	end)
	self.footing = footing
	humanoid:SetStateEnabled(FREEFALL, false)
	if humanoid:GetState() == FREEFALL then
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
end

local function newInputs(p: Placement.Placement): ShooterPoser.Inputs
	return {
		placement = p,
		teamSize = 1,
		body = Config.Stance.DefaultBody,
		cueX = 0,
		cueY = 0,
		angle = 0,
		spinX = 0,
		spinY = 0,
		pitch = Config.Cue.CueElevationDegrees,
		pull = 0,
		gap = nil,
		memory = nil,
	}
end

-- Forget everything a turn aimed with: the next aim starts afresh.
local function forgetAim(self: Avatar)
	self.liveValid = false
	self.memory = nil
	self.pitchShown = nil
	self.pitchState = nil
end

function Avatar.new(): Avatar
	local self = setmetatable({
		character = nil :: Model?,
		poser = nil :: ShooterPoser.Poser?,
		wanted = false,
		frame = AvatarPose.newFrame(),
		out = { visible = false, tip = CFrame.identity },
		live = nil :: ShooterPoser.Inputs?,
		liveValid = false,
		frozen = nil :: ShooterPoser.Inputs?,
		frozenValid = false,
		memory = nil :: ShooterStance.Memory?,
		pitchShown = nil :: number?,
		pitchTarget = Config.Cue.CueElevationDegrees,
		pitchKey = table.create(6, 0),
		pitchState = nil :: any,
		pitchQuery = {
			cueX = 0,
			cueY = 0,
			angle = 0,
			spinX = 0,
			spinY = 0,
			floorDegrees = Config.Cue.CueElevationDegrees,
		},
		footing = nil :: Footing?,
	}, Avatar)
	local player = Players.LocalPlayer
	local function onCharacter(character: Model)
		-- A respawn hands over a fresh body: the old one's poser puts back what it wrote (if the
		-- body is still about) and a new poser takes this one, the moment it is meant to.
		local old = self.poser
		if old then
			old:destroy()
		end
		letGo(self)
		self.character = character
		self.poser = ShooterPoser.new(character, true)
		self.frozenValid = false
		forgetAim(self)
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	return self
end

--- The player is at a table as the shooter: pose them (idempotent; call every frame).
function Avatar.take(self: Avatar)
	self.wanted = true
end

--- Give the body back to the player: the poser puts back all it wrote (limbs, fade, Animate)
--- and leaves the root where it is, which is where the server lets it go. No step-out: the
--- stance never stands inside the table's barrier.
function Avatar.release(self: Avatar)
	self.wanted = false
	local poser = self.poser
	if poser then
		poser:pose("rest", nil, 0)
	end
	self.frozenValid = false
	forgetAim(self)
	-- Freefall comes back once the server lets the root go (a poll later), not before: until
	-- then the body still stands on nothing.
	local footing = self.footing
	if footing and not footing.root.Anchored then
		letGo(self)
	end
end

--- A new turn (the same shooter again included): the next aim starts afresh. A stroke still
--- playing out finishes on its own frozen inputs.
function Avatar.newTurn(self: Avatar)
	if not Avatar.stroking(self) then
		self.frozenValid = false
	end
	forgetAim(self)
end

--- The shot is fired, the cue ball in hand at (x, y) table inches when given. `windUp` (0..1)
--- is how far the cue is drawn back as it goes: the shot's power when it was drawn on the bar
--- or a trigger, 0 for the precision button (a short jab from the cue at rest). Freezes what
--- the stroke plays from (the last frame's angle, spin, eased pitch and the stance, with the
--- cue ball where the shot has it) and strokes from that wind-up (as far as the stance lets
--- the cue draw back) into the ball.
function Avatar.strike(self: Avatar, windUp: number, x: number?, y: number?)
	local poser, live = self.poser, self.live
	if not poser or not live or not self.liveValid or poser.state ~= "aim" then
		return -- nothing aimed this turn (or the body is not held yet): no stroke to play
	end
	local frozen: ShooterPoser.Inputs = self.frozen or newInputs(live.placement)
	self.frozen = frozen
	-- Field by field: nil ones (memory) must overwrite too.
	frozen.placement, frozen.teamSize, frozen.body = live.placement, live.teamSize, live.body
	frozen.cueX, frozen.cueY = x or live.cueX, y or live.cueY
	frozen.angle, frozen.spinX, frozen.spinY = live.angle, live.spinX, live.spinY
	frozen.pitch, frozen.memory = live.pitch, live.memory
	-- The stroke's gap comes from the poser; the stance's own wind-up plays no part.
	frozen.pull, frozen.gap = 0, nil
	self.frozenValid = true
	local stance = ShooterPoser.compose(frozen, self.frame)
	local fromGap = restGap()
		+ math.clamp(windUp, 0, 1) * Config.Cue.CuePullBackStuds * stance.pullLimit
	poser:strike(
		fromGap,
		false,
		Config.Avatar.Stroke.Seconds,
		ShooterPoser.idleSpot(frozen.placement, stance)
	)
end

--- The replay has the ball moving: the stroke may follow through.
function Avatar.ballMoving(self: Avatar)
	local poser = self.poser
	if poser then
		poser:ballMoving()
	end
end

--- The server turned the shot down: back to aiming from the live inputs.
function Avatar.cancelStroke(self: Avatar)
	local poser = self.poser
	if poser then
		poser:cancelStroke()
	end
	self.frozenValid = false
end

--- Whether the stroke is playing (the cue stays drawn through it).
function Avatar.stroking(self: Avatar): boolean
	local poser = self.poser
	return poser ~= nil and poser:stroking()
end

-- The drawn pitch for the live inputs, eased (CueClearance: VISUAL ONLY, never fired).
local function pitchFor(
	self: Avatar,
	dt: number,
	live: ShooterPoser.Inputs,
	state: any,
	floor: number
): number
	local key = self.pitchKey
	if
		self.pitchState ~= state
		or key[PITCH_ANGLE] ~= live.angle
		or key[PITCH_X] ~= live.cueX
		or key[PITCH_Y] ~= live.cueY
		or key[PITCH_SPIN_X] ~= live.spinX
		or key[PITCH_SPIN_Y] ~= live.spinY
		or key[PITCH_FLOOR] ~= floor
	then
		self.pitchState = state
		key[PITCH_ANGLE], key[PITCH_X], key[PITCH_Y] = live.angle, live.cueX, live.cueY
		key[PITCH_SPIN_X], key[PITCH_SPIN_Y], key[PITCH_FLOOR] = live.spinX, live.spinY, floor
		local q = self.pitchQuery
		q.floorDegrees = floor
		q.cueX, q.cueY, q.angle, q.spinX, q.spinY =
			live.cueX, live.cueY, live.angle, live.spinX, live.spinY
		self.pitchTarget = CueClearance.pitch(state.geometry, state.balls, q).degrees
	end
	local was = self.pitchShown
	local shown = if was == nil
		then self.pitchTarget
		else CueClearance.ease(was, self.pitchTarget, dt)
	self.pitchShown = shown
	return shown
end

-- The body's own fade on this screen: the aim or idle transparency, out to fully gone as the
-- camera comes near it. The poser writes only what changed (and again for a rebuilt rig).
local function fade(poser: ShooterPoser.Poser, character: Model, ctx: Context)
	local state = poser.state
	if state == "rest" then
		return -- not held yet: the body is as the player left it
	end
	local A = Config.Avatar
	local target = if state == "idle" then A.IdleTransparency else A.AimTransparency
	local root = character:FindFirstChild("HumanoidRootPart")
	local cameraPos = ctx.cameraPos
	if cameraPos and root and root:IsA("BasePart") then
		local d = (root.Position - cameraPos).Magnitude
		local k = math.clamp(
			(d - A.FadeNearStuds) / math.max(A.FadeFarStuds - A.FadeNearStuds, 1e-3),
			0,
			1
		)
		target = 1 - (1 - target) * k
	end
	-- Quantised, so a camera drifting by a hair is not a new fade.
	target = math.floor(target * 50 + 0.5) / 50
	poser:setFade(target, A.HideAccessoriesWhileAiming)
end

--- One frame: advance the stroke, pose the body and say what to draw. Call every frame while
--- this player is the shooter, after take(). Returns the same table every time.
function Avatar.update(self: Avatar, dt: number, ctx: Context): Out
	local out = self.out
	out.visible = false
	local poser, character, p = self.poser, self.character, ctx.placement
	if not poser or not character or not p or not self.wanted then
		return out
	end
	holdFooting(self, character)

	-- Aiming while the player may, and through the stroke whatever else is going on. Idle on
	-- the player's own turn while the cue is hidden (the cue ball dragged, a modal open),
	-- following the live stance there; otherwise (the balls rolling after the stroke) idle
	-- where the body stands, the root never written.
	local gap = poser:advance(dt)
	local following = gap == nil and not ctx.showCue and ctx.aimTurn
	local inputs: ShooterPoser.Inputs? = nil
	if gap ~= nil and self.frozenValid then
		inputs = self.frozen
	elseif gap ~= nil or ctx.showCue or following then
		local cueX, cueY, state = ctx.cueX, ctx.cueY, ctx.state
		if cueX and cueY and state then
			local was = self.live
			local live: ShooterPoser.Inputs = if was and was.placement == p
				then was
				else newInputs(p)
			self.live = live
			live.teamSize = ctx.teamSize
			live.body = AvatarPose.measureBody(character) or Config.Stance.DefaultBody
			live.cueX, live.cueY, live.angle = cueX, cueY, ctx.angle
			local spin = ctx.spin
			live.spinX = if spin then spin.x else 0
			live.spinY = if spin then spin.y else 0
			live.pull = ctx.pull
			live.memory = self.memory
			live.pitch =
				pitchFor(self, dt, live, state, ctx.elevation or Config.Cue.CueElevationDegrees)
			self.liveValid = true
			inputs = live
		end
	end

	if inputs then
		inputs.gap = gap
		local stance, tip = ShooterPoser.compose(inputs, self.frame)
		if inputs == self.live then
			self.memory = stance.memory
		end
		if following then
			poser:pose("idle", self.frame, dt) -- no cue
		else
			poser:pose("aim", self.frame, dt)
			out.visible, out.tip = true, tip
		end
	else
		poser:pose("idle", nil, dt)
	end
	fade(poser, character, ctx)
	return out
end

return Avatar
