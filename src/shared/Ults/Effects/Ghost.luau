--!strict
-- Ghost (docs/prompts/ABILITIES_PROMPT.md 7.4): for this shot the cue ball passes through the
-- opponent's balls and the 8 (unless it is the shooter's legal 8) and collides only with the
-- shooter's balls and the cushions. The passing itself is the Simulation's contact filter
-- (overrides.PhaseCue, which Arming.extras fills): no contact either way, in the pair search
-- and in soft contact, so the first ball it touches (the fouls) is the first real one.
--
-- From the cue ball's first contact (after): the cue ball passes through every ball, the
-- shooter's too (it can no longer kiss one off its line), and, with
-- Config.Ults.Ghost.CarryPhase, the ball it hit passes through the same balls it did (the
-- opponent's and the 8), so a pot blocked by them goes in. Both are State.fx.passes, which the
-- Simulation's contact filter reads each step.
--
-- At rest (finish): a ball that stopped inside a ball it passed through is moved off it, to
-- just clear of it (Config.Ults.Ghost.ClearGapInches): straight away from that ball's centre
-- if that spot is free, otherwise the first free one of eight fixed headings round it, then
-- the same a ball width further out. Free: inside the cushions, off every pocket, clear of
-- every ball. The cue ball first, then the ball it hit. The server and every client run it on
-- the same numbers, so they agree.

local Config = require(script.Parent.Parent.Parent.Config)
local Magnet = require(script.Parent.Magnet)

local Ghost = {}

local S = math.sqrt(0.5)
local HEADINGS =
	{ { 1, 0 }, { S, S }, { 0, 1 }, { -S, S }, { -1, 0 }, { -S, -S }, { 0, -1 }, { S, -S } }

local function free(state: any, ball: any, x: number, y: number): boolean
	local R = Config.Balls.RadiusInches
	local g = state.geometry
	if math.abs(x) > g.halfLength - R or math.abs(y) > g.halfWidth - R then
		return false
	end
	for _, p in g.pockets do
		local dx, dy = x - p.x, y - p.y
		local reach = p.radius + R
		if dx * dx + dy * dy < reach * reach then
			return false
		end
	end
	for _, b in state.balls do
		if b ~= ball and not b.pocketed then
			local dx, dy = x - b.x, y - b.y
			if dx * dx + dy * dy < 4 * R * R then
				return false
			end
		end
	end
	return true
end

local function findBall(state: any, id: number): any
	for _, b in state.balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

-- The ball the cue ball hit (one of the shooter's) is pulled like Magnet's into a pocket it
-- nearly misses, with Config.Ults.Ghost.PullFactor of Magnet's strength (0: off).
function Ghost.step(state: any, dt: number)
	local hit = state.fx.touched
	local factor = Config.Ults.Ghost.PullFactor
	if hit == nil or factor <= 0 then
		return
	end
	local o = state.overrides
	local mine = false
	for _, id in (o and o.Targets) or {} do
		if id == hit then
			mine = true
		end
	end
	local b = if mine then findBall(state, hit) else nil
	if b and not b.pocketed then
		Magnet.pull(state, b, o.EightPocket, factor, dt)
	end
end

function Ghost.after(state: any, _dt: number, events: { any }, _ops: any)
	local fx = state.fx
	local phase = state.overrides and state.overrides.PhaseCue
	if fx.touched or phase == nil then
		return
	end
	for _, ev in events do
		if ev.type ~= "ballHit" or (ev.ball ~= 0 and ev.other ~= 0) then
			continue
		end
		local hit = if ev.ball == 0 then ev.other else ev.ball
		fx.touched = hit
		-- The cue ball: every ball from now on.
		local all: { [number]: boolean } = {}
		for _, b in state.balls do
			if b.id ~= 0 then
				all[b.id] = true
			end
		end
		local passes: { [number]: { [number]: boolean } } = { [0] = all }
		-- The ball it hit: the balls the cue ball passed through (never itself).
		if Config.Ults.Ghost.CarryPhase then
			local carried: { [number]: boolean } = {}
			for _, id in phase do
				if id ~= hit then
					carried[id] = true
				end
			end
			passes[hit] = carried
		end
		fx.passes = passes
		return
	end
end

-- Move `ball` off any of `ids` (in list order) it rests inside.
local function unstick(state: any, ball: any, ids: { number })
	local R = Config.Balls.RadiusInches
	local clear = 2 * R + Config.Ults.Ghost.ClearGapInches
	for _, id in ids do
		local inside = nil
		for _, b in state.balls do
			if b.id == id and b ~= ball and not b.pocketed then
				local dx, dy = ball.x - b.x, ball.y - b.y
				if dx * dx + dy * dy < 4 * R * R then
					inside = b
				end
				break
			end
		end
		if inside == nil then
			continue
		end
		local b = inside
		local candidates: { { number } } = {}
		local dx, dy = ball.x - b.x, ball.y - b.y
		local d = math.sqrt(dx * dx + dy * dy)
		if d > 1e-9 then
			table.insert(candidates, { dx / d, dy / d })
		end
		for _, h in HEADINGS do
			table.insert(candidates, h)
		end
		local moved = false
		for ring = 0, 2 do
			local reach = clear + ring * 2 * R
			for _, h in candidates do
				local x, y = b.x + h[1] * reach, b.y + h[2] * reach
				if free(state, ball, x, y) then
					ball.x, ball.y = x, y
					moved = true
					break
				end
			end
			if moved then
				break
			end
		end
	end
end

function Ghost.finish(state: any, _events: { any }, _ops: any)
	local overrides = state.overrides
	local phase = overrides and overrides.PhaseCue
	if phase == nil then
		return
	end
	-- Every ball id in array order: after the first contact the cue ball passed through all.
	local ids: { number } = {}
	for _, b in state.balls do
		if b.id ~= 0 then
			table.insert(ids, b.id)
		end
	end
	local cue = findBall(state, 0)
	if cue and not cue.pocketed then
		unstick(state, cue, if state.fx.touched then ids else phase)
	end
	local hit = state.fx.touched
	local carried = if hit then findBall(state, hit) else nil
	if carried and not carried.pocketed and state.fx.passes[hit] then
		unstick(state, carried, phase)
	end
end

return Ghost
