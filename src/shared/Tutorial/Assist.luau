--!strict
-- Assist: the tutorial's hidden help in game 1 (docs/prompts/TUTORIAL_V2_PROMPT.md 4.4), one
-- effect for the physics (Ults/Effects registry name "TutorialAssist"). Nothing here is
-- drawn: the player must never notice it.
--
-- - A pull on the first ball the cue ball hits, if it is the player's (Pull.Lesson on a
--   lesson shot, overrides.Lesson; Pull.First otherwise), and on every other ball of theirs
--   the cue ball itself touches later in the shot (Pull.Later). "Magnet": Effects/Magnet's
--   full pull, as the first tutorial's assist always did. "Gentle": only the turn Magnet would
--   give it, at most Pull.MaxTurn in all per ball, its speed untouched, so it hides in the
--   throw and drift a real ball has. "Off".
-- - The combination (overrides.Combo = { first, ball, x, y }, the combination lesson): the
--   back ball (first) is not pulled toward a pocket; from the cue ball's hit until it meets
--   another ball its heading bends gently toward (x, y), the front ball's ghost point
--   (Combo.PerInch per inch rolled, Combo.MaxTurn in all); once it meets the front ball, that
--   one gets the lesson's pull (Pull.Lesson).
-- - The carry (overrides.Carry, the aim lesson's and the combination's own pot): that ball,
--   rolling at its pocket, meets less cloth (Carry), so a soft lesson shot still drops.
-- - An inner effect (overrides.Inner, e.g. "FireShot" when the player's own ability is armed
--   in game 1) steps first, so the ability works as it always does with the help on top.
--
-- Pure like every effect (Ults/Effects): arithmetic and square roots only, balls walked in
-- array order, per-shot scratch in state.fx. Must never require Physics/Simulation.

local Config = require(script.Parent.Parent.Config)
local Magnet = require(script.Parent.Parent.Ults.Effects.Magnet)

local A = Config.Tutorial.Assist

local Assist = {}

-- The inner effect's module (lazily: the registry requires this module).
local function inner(state: any): any?
	local overrides = state.overrides
	local name = overrides and overrides.Inner
	if type(name) ~= "string" or name == "TutorialAssist" then
		return nil
	end
	local Effects = require(script.Parent.Parent.Ults.Effects) :: any
	return Effects[name]
end

local function findBall(state: any, id: number): any
	for _, b in state.balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

-- The player's balls the cue ball touched after the first (state.fx.assistHits), pulled too.
local function owned(state: any, id: number): boolean
	local overrides = state.overrides
	local targets = overrides and overrides.Targets
	if type(targets) ~= "table" or id == 0 then
		return false
	end
	for _, t in targets do
		if t == id then
			return id ~= 8 or overrides.EightPocket ~= nil
		end
	end
	return false
end

-- The gentle pull for one step: the turn Magnet.pull would give `b` (worked out on its
-- velocity, then put back), at most Pull.PerInch per inch rolled and within what is left of
-- Pull.MaxTurn for it (fx.pulled), and no change of speed.
local function gentle(state: any, b: any, eightPocket: number?, dt: number)
	local vx, vy, wx, wy = b.vx, b.vy, b.wx, b.wy
	Magnet.pull(state, b, eightPocket, 1, dt)
	local nx, ny = b.vx, b.vy
	b.vx, b.vy, b.wx, b.wy = vx, vy, wx, wy
	local s0 = math.sqrt(vx * vx + vy * vy)
	local s1 = math.sqrt(nx * nx + ny * ny)
	if s0 < 1e-9 or s1 < 1e-9 then
		return
	end
	local fx = state.fx
	fx.pulled = fx.pulled or {}
	local used = fx.pulled[b.id] or 0
	local left = math.min(A.Pull.MaxTurn - used, A.Pull.PerInch * s0 * dt)
	if left <= 0 then
		return
	end
	local s = math.clamp((vx * ny - vy * nx) / (s0 * s1), -left, left)
	if s == 0 then
		return
	end
	local c = math.sqrt(1 - s * s)
	b.vx, b.vy = c * vx - s * vy, s * vx + c * vy
	b.wx, b.wy = c * wx - s * wy, s * wx + c * wy
	fx.pulled[b.id] = used + math.abs(s)
end

-- One ball's pull for one step in `mode` (Config.Tutorial.Assist.Pull). Magnet's turns are
-- summed into fx.pulled too (as sines), so the tools and Studio can see how far the help bent
-- each ball.
local function pull(state: any, b: any, eightPocket: number?, dt: number, mode: string)
	if mode == "Magnet" then
		local vx, vy = b.vx, b.vy
		Magnet.pull(state, b, eightPocket, 1, dt)
		local s0 = math.sqrt(vx * vx + vy * vy)
		local s1 = math.sqrt(b.vx * b.vx + b.vy * b.vy)
		if s0 > 1e-9 and s1 > 1e-9 then
			local fx = state.fx
			fx.pulled = fx.pulled or {}
			fx.pulled[b.id] = (fx.pulled[b.id] or 0) + math.abs(vx * b.vy - vy * b.vx) / (s0 * s1)
		end
	elseif mode == "Gentle" then
		gentle(state, b, eightPocket, dt)
	end
end

-- The combination's steer: the back ball, after the cue ball's hit and before it meets
-- another ball, bends toward the front ball's ghost point.
local function comboSteer(state: any, combo: any, dt: number)
	local fx = state.fx
	if fx.comboTouched or Magnet.firstHit(state) ~= combo.first then
		return
	end
	local a = findBall(state, combo.first)
	if a == nil or a.pocketed or a.tip ~= nil then
		return
	end
	local speed = math.sqrt(a.vx * a.vx + a.vy * a.vy)
	local turned = fx.comboTurned or 0
	if speed < A.SteerMinSpeed or turned >= A.Combo.MaxTurn then
		return
	end
	local dx, dy = combo.x - a.x, combo.y - a.y
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist < 1e-6 then
		return
	end
	local ux, uy = a.vx / speed, a.vy / speed
	if (ux * dx + uy * dy) <= 0 then
		return -- heading away from it: left alone
	end
	local sinA = (ux * dy - uy * dx) / dist
	local allow = math.min(A.Combo.PerInch * speed * dt, A.Combo.MaxTurn - turned)
	local s = math.clamp(sinA, -allow, allow)
	if s == 0 then
		return
	end
	local c = math.sqrt(1 - s * s)
	a.vx, a.vy = c * a.vx - s * a.vy, s * a.vx + c * a.vy
	a.wx, a.wy = c * a.wx - s * a.wy, s * a.wx + c * a.wy
	fx.comboTurned = turned + math.abs(s)
end

-- The aim help (overrides.AimAt: a lesson's ghost point, or the escalation after many misses
-- in a row): before the cue ball touches anything, its heading bends toward AimAt, at most
-- Aim.PerInch radians per inch rolled and Aim.MaxTurn in all.
local function aimHelp(state: any, dt: number)
	local overrides = state.overrides
	local at = overrides and overrides.AimAt
	if type(at) ~= "table" or Magnet.firstHit(state) ~= nil then
		return
	end
	local fx = state.fx
	local cue = findBall(state, 0)
	if cue == nil or cue.pocketed or cue.tip ~= nil then
		return
	end
	local speed = math.sqrt(cue.vx * cue.vx + cue.vy * cue.vy)
	local turned = fx.aimed or 0
	local maxTurn, perInch = A.Aim.MaxTurn, A.Aim.PerInch
	if speed < A.SteerMinSpeed or turned >= maxTurn then
		return
	end
	local dx, dy = at.x - cue.x, at.y - cue.y
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist < 1e-6 then
		return
	end
	local ux, uy = cue.vx / speed, cue.vy / speed
	if (ux * dx + uy * dy) <= 0 then
		return
	end
	local sinA = (ux * dy - uy * dx) / dist
	local allow = math.min(perInch * speed * dt, maxTurn - turned)
	local s = math.clamp(sinA, -allow, allow)
	if s == 0 then
		return
	end
	local c = math.sqrt(1 - s * s)
	cue.vx, cue.vy = c * cue.vx - s * cue.vy, s * cue.vx + c * cue.vy
	cue.wx, cue.wy = c * cue.wx - s * cue.wy, s * cue.wx + c * cue.wy
	fx.aimed = turned + math.abs(s)
end

-- The carry (overrides.Carry = { ball, pocket }, the lesson's own pot): while that ball rolls
-- toward its pocket's mouth (within Carry.ConeCos, within Carry.Inches of it) the cloth holds
-- it back less (its rolling friction times Carry.FrictionShare, through state.fx.material), so
-- a soft lesson shot that would have stopped short just drops; off that line, the cloth is
-- the cloth again.
local function carry(state: any)
	local overrides = state.overrides
	local c = overrides and overrides.Carry
	if type(c) ~= "table" then
		return
	end
	local b = findBall(state, c.ball)
	if b == nil or b.pocketed then
		return
	end
	local fx = state.fx
	fx.material = fx.material or {}
	local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
	local on = false
	if speed > 1e-6 then
		for _, p in state.geometry.pockets do
			if p.id == c.pocket then
				local mx, my = Magnet.mouthPoint(state.geometry, p)
				local dx, dy = mx - b.x, my - b.y
				local dist = math.sqrt(dx * dx + dy * dy)
				on = dist > 1e-6
					and dist < A.Carry.Inches
					and (b.vx * dx + b.vy * dy) / (speed * dist) > A.Carry.ConeCos
			end
		end
	end
	if on then
		fx.material[b.id] = {
			RollingFriction = Config.Physics.RollingFriction * A.Carry.FrictionShare,
			Until = math.huge,
		}
		fx.carried = true
	elseif fx.material[b.id] then
		fx.material[b.id] = nil
	end
end

-- The cue-ball guard (overrides.Guard): after its first ball, a cue ball rolling into a
-- pocket's mouth is turned gently away from it (a lip-out), at most Guard.PerInch radians per
-- inch rolled and Guard.MaxTurn in all, so a new player's game-1 shot seldom scratches.
local function guard(state: any, dt: number)
	local overrides = state.overrides
	if not (overrides and overrides.Guard) or Magnet.firstHit(state) == nil then
		return -- only after the first ball: before it, the mouth may hold the very ball aimed at
	end
	local G = A.Guard
	local fx = state.fx
	local cue = findBall(state, 0)
	if cue == nil or cue.pocketed or cue.tip ~= nil then
		return
	end
	local speed = math.sqrt(cue.vx * cue.vx + cue.vy * cue.vy)
	local turned = fx.guarded or 0
	if speed < A.SteerMinSpeed or turned >= G.MaxTurn then
		return
	end
	local ux, uy = cue.vx / speed, cue.vy / speed
	for _, p in state.geometry.pockets do
		local mx, my = Magnet.mouthPoint(state.geometry, p)
		local dx, dy = mx - cue.x, my - cue.y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist > 1e-6 and dist < G.Inches then
			local cosA = (ux * dx + uy * dy) / dist
			if cosA > G.ConeCos then
				-- Heading in: turn away from the mouth's middle (to the left when dead on).
				local sinA = (ux * dy - uy * dx) / dist
				local away = if sinA > 0 then -1 else 1
				local s = away * math.min(G.PerInch * speed * dt, G.MaxTurn - turned)
				local c = math.sqrt(1 - s * s)
				cue.vx, cue.vy = c * cue.vx - s * cue.vy, s * cue.vx + c * cue.vy
				cue.wx, cue.wy = c * cue.wx - s * cue.wy, s * cue.wx + c * cue.wy
				fx.guarded = turned + math.abs(s)
				return
			end
		end
	end
end

function Assist.step(state: any, dt: number)
	local fx = state.fx
	local e = inner(state)
	if e and e.step then
		e.step(state, dt)
	end
	local eightPocket = state.overrides.EightPocket
	local combo = state.overrides.Combo
	if type(combo) ~= "table" then
		combo = nil
	end
	local first = Magnet.firstHit(state)
	local b = if first ~= nil and owned(state, first) then findBall(state, first) else nil
	if combo and first == combo.first then
		b = nil -- the combination's back ball goes at the front one, not a pocket
	end
	if b and not b.pocketed then
		pull(
			state,
			b,
			eightPocket,
			dt,
			if state.overrides.Lesson then A.Pull.Lesson else A.Pull.First
		)
	end
	local hits = fx.assistHits
	if hits and A.Pull.Later ~= "Off" then
		for _, other in state.balls do
			if hits[other.id] and not other.pocketed then
				pull(state, other, eightPocket, dt, A.Pull.Later)
			end
		end
	end
	if combo then
		if fx.comboHit then
			local front = findBall(state, combo.ball)
			if front and not front.pocketed and owned(state, front.id) then
				pull(state, front, eightPocket, dt, A.Pull.Lesson)
			end
		end
		comboSteer(state, combo, dt)
	end
	aimHelp(state, dt)
	guard(state, dt)
	carry(state)
end

function Assist.after(state: any, dt: number, events: { any }, ops: any)
	local fx = state.fx
	local e = inner(state)
	if e and e.after then
		e.after(state, dt, events, ops)
	end
	local first = Magnet.firstHit(state)
	Magnet.after(state, dt, events, ops)
	local combo = state.overrides.Combo
	if type(combo) ~= "table" then
		combo = nil
	end
	for _, ev in events do
		if combo and ev.type == "ballHit" and ev.ball ~= 0 and ev.other ~= 0 then
			-- The back ball meets another ball: its steer ends; the front one is pulled.
			if ev.ball == combo.first or ev.other == combo.first then
				fx.comboTouched = true
				local other = if ev.ball == combo.first then ev.other else ev.ball
				if other == combo.ball then
					fx.comboHit = true
				end
			end
		end
		if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
			local other = if ev.ball == 0 then ev.other else ev.ball
			if first ~= nil and other ~= first and owned(state, other) then
				-- A later ball of theirs the cue ball meets is pulled too.
				fx.assistHits = fx.assistHits or {}
				fx.assistHits[other] = true
			end
			first = first or other
		end
	end
end

function Assist.finish(state: any, events: { any }, ops: any)
	local e = inner(state)
	if e and e.finish then
		e.finish(state, events, ops)
	end
end

return Assist
