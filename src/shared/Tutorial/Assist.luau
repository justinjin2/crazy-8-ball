--!strict
-- Assist: the tutorial's hidden help in game 1 (docs/prompts/TUTORIAL_V2_PROMPT.md 4.4), one
-- effect for the physics (Ults/Effects registry name "TutorialAssist"). Nothing here is
-- drawn: the player must never notice it.
--
-- - Magnet's pull on the first ball the cue ball hits, if it is the player's (Effects/
--   Magnet, exactly as Tutorial/Rig's assist always did), and also on every other ball of
--   theirs the cue ball itself touches later in the shot (the ricochet's second ball).
-- - The ricochet steer (turn 2 only, overrides.Ricochet): once the cue ball has hit its first
--   ball (and then a cushion, when Ricochet.afterRail), its heading bends gently toward
--   Ricochet's ghost point (where its centre must be when it meets ball `ball` to send it at
--   its pocket), at most SteerPerInch radians per inch rolled and MaxTurn in all, until it
--   touches any ball. A cue ball heading away from the point (more than 90 degrees off) is
--   left alone.
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

-- The ricochet's steer for one step.
local function steer(state: any, dt: number)
	local overrides = state.overrides
	local r = overrides and overrides.Ricochet
	local fx = state.fx
	if type(r) ~= "table" or fx.cueTouched or Magnet.firstHit(state) == nil then
		return
	end
	if r.afterRail and not fx.cueRailAfterHit then
		return -- this ricochet comes off a cushion first: no steer before it
	end
	local cue = findBall(state, 0)
	if cue == nil or cue.pocketed or cue.tip ~= nil then
		return
	end
	local speed = math.sqrt(cue.vx * cue.vx + cue.vy * cue.vy)
	if speed < A.SteerMinSpeed then
		return
	end
	local dx, dy = r.x - cue.x, r.y - cue.y
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist < 1e-6 then
		return
	end
	local ux, uy = cue.vx / speed, cue.vy / speed
	local cosA = (ux * dx + uy * dy) / dist
	if cosA <= 0 then
		return -- heading away: no help
	end
	local sinA = (ux * dy - uy * dx) / dist -- signed: positive turns left
	local turned = fx.steered or 0
	local left = A.MaxTurn - turned
	if left <= 0 then
		return
	end
	-- Only just after a contact (the first ball, a cushion), where a bend reads as part of
	-- the collision's own deflection: WindowInches of roll after each (0: anywhere).
	local windowed = A.WindowInches > 0
	if windowed and (fx.window or 0) <= 0 then
		return
	end
	if windowed then
		fx.window -= speed * dt
	end
	-- This step's allowance (radians, small: sin ~ angle), within what is left.
	local allow = math.min(A.SteerPerInch * speed * dt, left)
	local s = math.clamp(sinA, -allow, allow)
	if s == 0 then
		return
	end
	local c = math.sqrt(1 - s * s)
	cue.vx, cue.vy = c * cue.vx - s * cue.vy, s * cue.vx + c * cue.vy
	cue.wx, cue.wy = c * cue.wx - s * cue.wy, s * cue.wx + c * cue.wy
	fx.steered = turned + math.abs(s)
end

-- The aim help (overrides.AimAt, the escalation after many misses in a row): before the cue
-- ball touches anything, its heading bends toward AimAt (the target's ghost point), at most
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
	if speed < A.SteerMinSpeed or turned >= A.Aim.MaxTurn then
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
	local allow = math.min(A.Aim.PerInch * speed * dt, A.Aim.MaxTurn - turned)
	local s = math.clamp(sinA, -allow, allow)
	if s == 0 then
		return
	end
	local c = math.sqrt(1 - s * s)
	cue.vx, cue.vy = c * cue.vx - s * cue.vy, s * cue.vx + c * cue.vy
	cue.wx, cue.wy = c * cue.wx - s * cue.wy, s * cue.wx + c * cue.wy
	fx.aimed = turned + math.abs(s)
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
	Magnet.step(state, dt)
	local hits = fx.assistHits
	if hits then
		local _, eightPocket = nil, state.overrides.EightPocket
		for _, b in state.balls do
			if hits[b.id] and not b.pocketed then
				Magnet.pull(state, b, eightPocket, 1, dt)
			end
		end
	end
	aimHelp(state, dt)
	steer(state, dt)
	guard(state, dt)
end

function Assist.after(state: any, dt: number, events: { any }, ops: any)
	local fx = state.fx
	local e = inner(state)
	if e and e.after then
		e.after(state, dt, events, ops)
	end
	local first = Magnet.firstHit(state)
	Magnet.after(state, dt, events, ops)
	for _, ev in events do
		if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
			local other = if ev.ball == 0 then ev.other else ev.ball
			if first ~= nil then
				-- A later ball the cue ball meets: the steer ends, and it is pulled if theirs.
				fx.cueTouched = true
				if other ~= first and owned(state, other) then
					fx.assistHits = fx.assistHits or {}
					fx.assistHits[other] = true
				end
			end
			if first == nil then
				fx.window = A.WindowInches
			end
			first = first or other
		elseif ev.type == "railHit" and ev.ball == 0 and first ~= nil then
			fx.cueRailAfterHit = true
			fx.window = A.WindowInches
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
