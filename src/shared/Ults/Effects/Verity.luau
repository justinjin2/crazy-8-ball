--!strict
-- Verity (the abilities rework; evil since the designer's second round, 2026-10-08:
-- docs/prompts/ABILITIES_REWORK_PLAN.md 3): the cue ball is the Verity ball. At its first
-- contact she turns evil, swells up and eats the ball it hit, then rolls on along the shot's
-- line eating more of the shooter's balls.
--
-- * The eat: the step of the cue ball's first contact, the ball it hit is eaten
--   (Simulation.Ops.remove: a `removed` event ShotJudge counts as a pot for its owner, so an
--   opponent's ball goes down for them, and hitting it first is still a wrong-ball foul). The
--   8 off the shooter's legal 8 shot is refused: the contact plays as a normal hit and Verity
--   never turns (no roll either).
-- * The chew: she swells to BodyRadiusInches where the contact was and stays there for
--   EatShotSeconds of play (a tiny back-and-forth keeps the shot in motion). Every ball inside
--   her swollen body is shoved out just clear of it (the 8 only where that cannot drop it).
-- * The roll: then she rolls along the cue ball's heading before the contact at RollSpeed, for
--   at most RollInches, stopping before her body comes within EdgeMarginInches of a cushion or
--   a pocket. The cue ball is her body: it passes through every ball (fx.ghost) and is moved by
--   the roll alone. Each ball her body touches is met: the first MaxEaten of the shooter's are
--   eaten (a pot each), any other ball is bumped aside of her path at BumpSpeed, and she hops
--   over the 8. A ball that leaves her reach is met again if she reaches it again.
-- * The landing: at the roll's end the cue ball stops, solid again, on the nearest spot clear
--   of every ball (LandGapInches of room), on the cloth.
-- * `ult` events for the look: "eat" (ball = the eaten ball, x, y = where it was, value 1 the
--   shooter's, 0 another's, other = how many she has eaten with this one), "refuse" (ball =
--   the 8), "shove" (ball, x, y: pushed out as she swells), "roll" (ball 0, x, y = where the
--   roll starts), "bump" (ball, x, y), "hop" (ball = the 8, x, y) and "land" (ball 0, x, y =
--   where she stops). The replay's state.fx.verity holds the act (its heading) for the look.
--
-- Only arithmetic and square roots (no trig, no pow), balls walked in array order: the
-- server's settle and every client's replay step it to identical bits. Pure Luau: must never
-- require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)
local Ball = require(script.Parent.Parent.Parent.Physics.Ball)

local Verity = {}

local EIGHT = 8
local R = Config.Balls.RadiusInches
-- Eight directions round a ball, for the landing spot (unit vectors, no trig).
local S = 0.7071067811865476
local AROUND =
	{ { 1, 0 }, { S, S }, { 0, 1 }, { -S, S }, { -1, 0 }, { -S, -S }, { 0, -1 }, { S, -S } }

export type Act = {
	stage: string, -- "eat", "roll", "stop" (landing this step) or "done"
	at: number, -- shot time the stage began
	hx: number, -- the roll's unit heading
	hy: number,
	ox: number, -- where the roll starts
	oy: number,
	inside: { [number]: boolean }, -- the balls inside her reach now (met on the way in)
	eaten: number, -- the shooter's balls eaten on the roll
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

--- Her act this shot, or nil before the contact (or when Verity was refused).
function Verity.act(state: any): Act?
	local fx = state.fx
	local v = if type(fx) == "table" then fx.verity else nil
	return if type(v) == "table" then v else nil
end

-- True when a body of `radius` centred at (x, y) comes within `margin` of a cushion line or
-- a pocket's mouth.
local function nearEdge(state: any, x: number, y: number, radius: number, margin: number): boolean
	local g = state.geometry
	local room = radius + margin
	if math.abs(x) > g.halfLength - room or math.abs(y) > g.halfWidth - room then
		return true
	end
	for _, p in g.pockets do
		local dx, dy = x - p.x, y - p.y
		local reach = p.radius + room
		if dx * dx + dy * dy < reach * reach then
			return true
		end
	end
	return false
end

-- True when the cue ball centred at (x, y) would be clear of every other ball (with the
-- gap), on the cloth and away from the pockets.
local function free(state: any, x: number, y: number): boolean
	local V = Config.Ults.Verity
	if nearEdge(state, x, y, R, V.LandEdgeInches) then
		return false
	end
	local gap = 2 * R + V.LandGapInches
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

-- True when the 8 rolled `s` inches along (nx, ny) stays well clear of every pocket.
local function safeFor8(state: any, b: any, nx: number, ny: number, s: number): boolean
	for _, p in state.geometry.pockets do
		-- The nearest point of the 8's short run to the pocket.
		local along = math.clamp((p.x - b.x) * nx + (p.y - b.y) * ny, 0, s)
		local dx, dy = b.x + nx * along - p.x, b.y + ny * along - p.y
		local keep = p.radius + 2 * R
		if dx * dx + dy * dy < keep * keep then
			return false
		end
	end
	return true
end

-- Adds (vx, vy) to a ball's motion, rolling naturally.
local function push(b: any, vx: number, vy: number)
	rollAt(b, b.vx + vx, b.vy + vy)
end

-- She swells over ball `b` (`dist` from her centre): it is shoved out along the line from her
-- centre, as fast as rolls it just clear of her body.
local function shove(
	state: any,
	act: Act,
	cue: any,
	b: any,
	dist: number,
	events: { any },
	ops: any
)
	local V = Config.Ults.Verity
	local nx, ny = act.hx, act.hy
	if dist > 1e-9 then
		nx, ny = (b.x - cue.x) / dist, (b.y - cue.y) / dist
	end
	local s = V.BodyRadiusInches + R + V.ShoveGapInches - dist
	if s <= 0 then
		return
	end
	if b.id == EIGHT and not safeFor8(state, b, nx, ny, s) then
		ops.emit(state, events, "hop", b.id, nil, b.x, b.y)
		return
	end
	local mu = Config.Physics.RollingFriction * Config.Physics.Gravity
	local speed = math.sqrt(2 * mu * s)
	push(b, nx * speed, ny * speed)
	ops.emit(state, events, "shove", b.id, nil, b.x, b.y)
end

-- Ball `b` met on the roll: eaten (one of the shooter's, while she may eat more), hopped (the
-- 8), or bumped aside of her path.
local function meetOnRoll(state: any, act: Act, cue: any, b: any, events: { any }, ops: any)
	local V = Config.Ults.Verity
	if b.id == EIGHT then
		ops.emit(state, events, "hop", b.id, nil, b.x, b.y)
		return
	end
	local targets = state.overrides and state.overrides.Targets
	if contains(targets, b.id) and act.eaten < V.MaxEaten then
		act.eaten += 1
		local x, y = b.x, b.y
		ops.remove(state, events, b, "Verity")
		ops.emit(state, events, "eat", b.id, act.eaten + 1, x, y, 1)
		return
	end
	local px, py = -act.hy, act.hx
	local side = (b.x - cue.x) * px + (b.y - cue.y) * py
	if side < 0 then
		px, py = -px, -py
	end
	local kx, ky =
		px * V.BumpSide + act.hx * V.BumpForward, py * V.BumpSide + act.hy * V.BumpForward
	local len = math.sqrt(kx * kx + ky * ky)
	push(b, kx / len * V.BumpSpeed, ky / len * V.BumpSpeed)
	ops.emit(state, events, "bump", b.id, nil, b.x, b.y)
end

-- Every ball on the cloth that has just come inside her reach is met (shoved while she eats,
-- else as meetOnRoll); a ball that has left it may be met again.
local function meetAll(state: any, act: Act, cue: any, events: { any }, ops: any)
	local V = Config.Ults.Verity
	local reach = V.BodyRadiusInches + R
	local targets = state.overrides and state.overrides.Targets
	for _, b in state.balls do
		if b.id == 0 or b.pocketed then
			continue
		end
		-- One of yours she can still eat on the roll is slurped in from further off.
		local within = reach
		if
			act.stage == "roll"
			and b.id ~= EIGHT
			and act.eaten < V.MaxEaten
			and contains(targets, b.id)
		then
			within = math.max(reach, V.EatReachInches)
		end
		local dx, dy = b.x - cue.x, b.y - cue.y
		local d2 = dx * dx + dy * dy
		if d2 >= within * within or not onCloth(b) then
			act.inside[b.id] = nil
			continue
		end
		if act.inside[b.id] then
			continue
		end
		act.inside[b.id] = true
		if act.stage == "eat" then
			shove(state, act, cue, b, math.sqrt(d2), events, ops)
		else
			meetOnRoll(state, act, cue, b, events, ops)
		end
	end
end

-- She chews in place: a back-and-forth of ChewJiggle each step (a few thousandths of an inch,
-- unseen) keeps the shot in motion while she stays where she is.
local function chew(cue: any)
	local jiggle = Config.Ults.Verity.ChewJiggle
	rollAt(cue, if cue.vx > 0 then -jiggle else jiggle, 0)
end

--- Before each step: the cue ball's heading until the contact; then her own motion (in place
--- while she eats, the roll), and the roll's end when it reaches its distance or a cushion or
--- pocket is next.
function Verity.step(state: any, dt: number)
	local fx = state.fx
	local cue = findBall(state, 0)
	if cue == nil then
		return
	end
	local act = Verity.act(state)
	if act == nil then
		if fx.verityRefused == nil and (cue.vx ~= 0 or cue.vy ~= 0) then
			fx.heading = { cue.vx, cue.vy }
		end
		return
	end
	local V = Config.Ults.Verity
	if act.stage == "eat" then
		if state.time - act.at < V.EatShotSeconds then
			chew(cue)
			return
		end
		-- The roll meets every ball inside her reach afresh (one she shoved may still be there).
		act.stage, act.at = "roll", state.time
		act.ox, act.oy = cue.x, cue.y
		table.clear(act.inside)
	end
	if act.stage == "roll" then
		local dx, dy = cue.x - act.ox, cue.y - act.oy
		local nx, ny = cue.x + act.hx * V.RollSpeed * dt, cue.y + act.hy * V.RollSpeed * dt
		if
			dx * dx + dy * dy >= V.RollInches * V.RollInches
			or nearEdge(state, nx, ny, V.BodyRadiusInches, V.EdgeMarginInches)
		then
			act.stage = "stop"
			Ball.stop(cue)
			return
		end
		rollAt(cue, act.hx * V.RollSpeed, act.hy * V.RollSpeed)
	end
end

--- After each step: the contact (the eat), the shoves, the roll's start and meetings, and the
--- landing.
function Verity.after(state: any, _dt: number, events: { any }, ops: any)
	local fx = state.fx
	local cue = findBall(state, 0)
	if cue == nil or fx.verityRefused then
		return
	end
	local act = Verity.act(state)
	if act == nil then
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
			-- The roll's heading: the cue ball's before the contact (else toward the ball).
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
			ops.emit(state, events, "eat", id, 1, bx, by, own)
			chew(cue)
			fx.ghost = fx.ghost or {}
			fx.ghost[0] = true
			local fresh: Act = {
				stage = "eat",
				at = state.time,
				hx = hx / len,
				hy = hy / len,
				ox = cue.x,
				oy = cue.y,
				inside = {},
				eaten = 0,
				announced = false,
			}
			fx.verity = fresh
			meetAll(state, fresh, cue, events, ops) -- she swells over her neighbours at once
			return
		end
		return
	end
	if act.stage == "eat" then
		meetAll(state, act, cue, events, ops)
	elseif act.stage == "roll" then
		if not act.announced then
			act.announced = true
			ops.emit(state, events, "roll", 0, nil, act.ox, act.oy)
		end
		meetAll(state, act, cue, events, ops)
	elseif act.stage == "stop" then
		act.stage = "done"
		Ball.stop(cue)
		fx.ghost[0] = nil
		land(state, cue)
		ops.emit(state, events, "land", 0, nil, cue.x, cue.y)
	end
end

return Verity
