--!strict
-- Verity (the abilities rework, designer 2026-10-08; docs/prompts/ABILITIES_REWORK_PLAN.md 3):
-- the cue ball is the Verity ball. At its first contact it unfolds into Verity, who grabs the
-- ball it hit, hurls it off the table, then sprints on through the pack.
--
-- * The throw: the step of the cue ball's first contact, the ball it hit leaves the table
--   (Simulation.Ops.remove: a `removed` event ShotJudge counts as a pot for its owner, so an
--   opponent's ball goes down for them, and hitting it first is still a wrong-ball foul). The
--   8 off the shooter's legal 8 shot is refused: the contact plays as a normal hit and Verity
--   never appears (no run either).
-- * The grab: for GrabShotSeconds of play Verity holds where the contact was, shuffling forward
--   at ShuffleSpeed (the shot stays in motion, so it does not end before the run).
-- * The run: then Verity sprints along the cue ball's heading before the contact at RunSpeed,
--   for at most RunInches, stopping short of a cushion or a pocket. The cue ball is Verity's
--   body: it passes through every ball (fx.ghost) and is moved by the run alone. Every object
--   ball her body comes within KickRadiusInches of is kicked once: the first MaxAimed of the
--   shooter's ("trust me, I know everything") are sent along a clean line into a pocket when
--   one exists (ChainLightning.pushTarget, rolling, arriving at AimArriveSpeed); every other
--   ball is booted off to the side of her path at KickSpeed. She steps over the 8.
-- * The landing: at the run's end the cue ball stops, solid again, on the nearest spot clear
--   of every ball (LandGapInches of room), on the cloth.
-- * `ult` events for the look: "grab" (ball = the thrown ball, x, y = where it was, value 1
--   the shooter's, 0 another's), "refuse" (ball = the 8), "run" (ball 0, x, y = where the
--   sprint starts), "kick" (ball = the kicked ball, other = the pocket id for an aimed kick,
--   value 1 aimed, 0 booted) and "land" (ball 0, x, y = where Verity stops). The replay's
--   state.fx.verity holds the run (its heading) for the look.
--
-- Only arithmetic and square roots (no trig, no pow), balls walked in array order: the
-- server's settle and every client's replay step it to identical bits. Pure Luau: must never
-- require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)
local Ball = require(script.Parent.Parent.Parent.Physics.Ball)
local ChainLightning = require(script.Parent.ChainLightning)

local Verity = {}

local EIGHT = 8
local R = Config.Balls.RadiusInches
-- Eight directions round a ball, for the landing spot (unit vectors, no trig).
local S = 0.7071067811865476
local AROUND =
	{ { 1, 0 }, { S, S }, { 0, 1 }, { -S, S }, { -1, 0 }, { -S, -S }, { 0, -1 }, { S, -S } }

export type Run = {
	stage: string, -- "grab", "run", "stop" (landing this step) or "done"
	at: number, -- shot time the stage began
	hx: number, -- the run's unit heading
	hy: number,
	ox: number, -- where the run starts
	oy: number,
	kicked: { [number]: boolean },
	aimed: number,
	announced: boolean,
}

local function findBall(state: any, id: number): any
	for _, b in state.balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

local function contains(list: { number }?, id: number): boolean
	if list == nil then
		return false
	end
	for _, v in list do
		if v == id then
			return true
		end
	end
	return false
end

local function onCloth(b: any): boolean
	return not b.pocketed and b.tip == nil and b.z == 0 and b.vz == 0
end

-- Sets a ball's motion to (vx, vy), rolling naturally.
local function rollAt(b: any, vx: number, vy: number)
	b.vx, b.vy, b.vz = vx, vy, 0
	b.wx, b.wy, b.wz = -vy / R, vx / R, 0
end

--- The run in progress this shot, or nil before the contact (or when Verity was refused).
function Verity.run(state: any): Run?
	local fx = state.fx
	local v = if type(fx) == "table" then fx.verity else nil
	return if type(v) == "table" then v else nil
end

-- True when (x, y) is too near a cushion or a pocket for Verity to keep running.
local function blocked(state: any, x: number, y: number): boolean
	local V = Config.Ults.Verity
	local g = state.geometry
	local margin = R + V.EdgeMarginInches
	if math.abs(x) > g.halfLength - margin or math.abs(y) > g.halfWidth - margin then
		return true
	end
	for _, p in g.pockets do
		local dx, dy = x - p.x, y - p.y
		local reach = p.radius + margin
		if dx * dx + dy * dy < reach * reach then
			return true
		end
	end
	return false
end

-- True when a ball centred at (x, y) would be clear of every other ball (with the gap), on
-- the cloth and away from the pockets.
local function free(state: any, x: number, y: number): boolean
	if blocked(state, x, y) then
		return false
	end
	local gap = 2 * R + Config.Ults.Verity.LandGapInches
	for _, b in state.balls do
		if b.id ~= 0 and not b.pocketed then
			local dx, dy = b.x - x, b.y - y
			if dx * dx + dy * dy < gap * gap then
				return false
			end
		end
	end
	return true
end

-- Put the cue ball down where it stands, or on the nearest free spot round it.
local function land(state: any, cue: any)
	if free(state, cue.x, cue.y) then
		return
	end
	local step = R / 2
	for ring = 1, 40 do
		for _, d in AROUND do
			local x, y = cue.x + d[1] * step * ring, cue.y + d[2] * step * ring
			if free(state, x, y) then
				cue.x, cue.y = x, y
				return
			end
		end
	end
end

-- Kick ball `b` (once): toward a pocket for one of the shooter's while the aimed kicks last,
-- else off to the side of the run.
local function kick(state: any, v: Run, cue: any, b: any, events: { any }, ops: any)
	local V = Config.Ults.Verity
	v.kicked[b.id] = true
	if contains(state.overrides and state.overrides.Targets, b.id) and v.aimed < V.MaxAimed then
		local pocket, kx, ky, d, clear = ChainLightning.pushTarget(state, b)
		if pocket and clear then
			v.aimed += 1
			local mu = Config.Physics.RollingFriction * Config.Physics.Gravity
			local speed = math.sqrt(2 * mu * d + V.AimArriveSpeed * V.AimArriveSpeed)
			speed = math.min(speed, V.KickSpeed)
			rollAt(b, kx * speed, ky * speed)
			ops.emit(state, events, "kick", b.id, pocket.id, b.x, b.y, 1)
			return
		end
	end
	-- Booted aside: away from the run's line, a little forward.
	local px, py = -v.hy, v.hx
	local side = (b.x - cue.x) * px + (b.y - cue.y) * py
	if side < 0 then
		px, py = -px, -py
	end
	local kx, ky = px * V.KickSide + v.hx * V.KickForward, py * V.KickSide + v.hy * V.KickForward
	local len = math.sqrt(kx * kx + ky * ky)
	rollAt(b, kx / len * V.KickSpeed, ky / len * V.KickSpeed)
	ops.emit(state, events, "kick", b.id, nil, b.x, b.y, 0)
end

--- Before each step: the cue ball's heading until the contact; then Verity's own motion (the
--- shuffle while she grabs, the sprint), and the run's end when it reaches its distance or a
--- cushion or pocket is next.
function Verity.step(state: any, dt: number)
	local fx = state.fx
	local cue = findBall(state, 0)
	if cue == nil then
		return
	end
	local v = Verity.run(state)
	if v == nil then
		if fx.verityRefused == nil and (cue.vx ~= 0 or cue.vy ~= 0) then
			fx.heading = { cue.vx, cue.vy }
		end
		return
	end
	local V = Config.Ults.Verity
	if v.stage == "grab" then
		if state.time - v.at >= V.GrabShotSeconds then
			v.stage, v.at = "run", state.time
			v.ox, v.oy = cue.x, cue.y
		else
			rollAt(cue, v.hx * V.ShuffleSpeed, v.hy * V.ShuffleSpeed)
			return
		end
	end
	if v.stage == "run" then
		local dx, dy = cue.x - v.ox, cue.y - v.oy
		local nx, ny = cue.x + v.hx * V.RunSpeed * dt, cue.y + v.hy * V.RunSpeed * dt
		if dx * dx + dy * dy >= V.RunInches * V.RunInches or blocked(state, nx, ny) then
			v.stage = "stop"
			Ball.stop(cue)
			return
		end
		rollAt(cue, v.hx * V.RunSpeed, v.hy * V.RunSpeed)
	end
end

--- After each step: the contact (the throw), the run's start, the kicks and the landing.
function Verity.after(state: any, _dt: number, events: { any }, ops: any)
	local fx = state.fx
	local cue = findBall(state, 0)
	if cue == nil or fx.verityRefused then
		return
	end
	local v = Verity.run(state)
	if v == nil then
		for _, ev in events do
			if ev.type ~= "ballHit" or (ev.ball ~= 0 and ev.other ~= 0) then
				continue
			end
			local id = if ev.ball == 0 then ev.other else ev.ball
			local b = findBall(state, id)
			if b == nil or b.pocketed then
				continue
			end
			local targets = state.overrides and state.overrides.Targets
			if id == EIGHT and not contains(targets, EIGHT) then
				fx.verityRefused = true
				ops.emit(state, events, "refuse", id, nil, b.x, b.y)
				return
			end
			-- The run's heading: the cue ball's before the contact (else toward the ball).
			local hx, hy = b.x - cue.x, b.y - cue.y
			local heading = fx.heading
			if type(heading) == "table" then
				hx, hy = heading[1], heading[2]
			end
			local len = math.sqrt(hx * hx + hy * hy)
			if len < 1e-9 then
				hx, hy, len = 1, 0, 1
			end
			local bx, by = b.x, b.y
			local own = if contains(targets, id) then 1 else 0
			ops.remove(state, events, b, "Verity")
			ops.emit(state, events, "grab", id, nil, bx, by, own)
			-- Already shuffling: a cue ball left at rest here would end the shot at once.
			local shuffle = Config.Ults.Verity.ShuffleSpeed
			rollAt(cue, hx / len * shuffle, hy / len * shuffle)
			fx.ghost = fx.ghost or {}
			fx.ghost[0] = true
			fx.verity = {
				stage = "grab",
				at = state.time,
				hx = hx / len,
				hy = hy / len,
				ox = cue.x,
				oy = cue.y,
				kicked = {},
				aimed = 0,
				announced = false,
			} :: Run
			return
		end
		return
	end
	if v.stage == "run" then
		if not v.announced then
			v.announced = true
			ops.emit(state, events, "run", 0, nil, cue.x, cue.y)
		end
		local reach = Config.Ults.Verity.KickRadiusInches
		for _, b in state.balls do
			if b.id == 0 or b.id == EIGHT or v.kicked[b.id] or not onCloth(b) then
				continue
			end
			local dx, dy = b.x - cue.x, b.y - cue.y
			if dx * dx + dy * dy < reach * reach then
				kick(state, v, cue, b, events, ops)
			end
		end
	elseif v.stage == "stop" then
		v.stage = "done"
		Ball.stop(cue)
		fx.ghost[0] = nil
		land(state, cue)
		ops.emit(state, events, "land", 0, nil, cue.x, cue.y)
	end
end

return Verity
