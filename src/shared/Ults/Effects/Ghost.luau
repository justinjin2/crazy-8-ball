--!strict
-- Ghost (docs/prompts/ABILITIES_PROMPT.md 7.4): for this shot the cue ball passes through the
-- opponent's balls and the 8 (unless it is the shooter's legal 8) and collides only with the
-- shooter's balls and the cushions. The passing itself is the Simulation's contact filter
-- (overrides.PhaseCue, which Arming.extras fills): no contact either way, in the pair search
-- and in soft contact, so the first ball it touches (the fouls) is the first real one.
--
-- At rest (finish): a cue ball that stopped inside a ball it passed through is moved off it, to
-- just clear of it (Config.Ults.Ghost.ClearGapInches): straight away from that ball's centre
-- if that spot is free, otherwise the first free one of eight fixed headings round it, then
-- the same a ball width further out. Free: inside the cushions, off every pocket, clear of
-- every ball. The server and every client run it on the same numbers, so they agree.

local Config = require(script.Parent.Parent.Parent.Config)

local Ghost = {}

local S = math.sqrt(0.5)
local HEADINGS =
	{ { 1, 0 }, { S, S }, { 0, 1 }, { -S, S }, { -1, 0 }, { -S, -S }, { 0, -1 }, { S, -S } }

local function free(state: any, cue: any, x: number, y: number): boolean
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
		if b ~= cue and not b.pocketed then
			local dx, dy = x - b.x, y - b.y
			if dx * dx + dy * dy < 4 * R * R then
				return false
			end
		end
	end
	return true
end

function Ghost.finish(state: any, _events: { any }, _ops: any)
	local overrides = state.overrides
	local phase = overrides and overrides.PhaseCue
	if phase == nil then
		return
	end
	local cue = nil
	for _, b in state.balls do
		if b.id == 0 then
			cue = b
			break
		end
	end
	if cue == nil or cue.pocketed then
		return
	end
	local R = Config.Balls.RadiusInches
	local clear = 2 * R + Config.Ults.Ghost.ClearGapInches
	for _, id in phase do
		local inside = nil
		for _, b in state.balls do
			if b.id == id and not b.pocketed then
				local dx, dy = cue.x - b.x, cue.y - b.y
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
		local dx, dy = cue.x - b.x, cue.y - b.y
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
				if free(state, cue, x, y) then
					cue.x, cue.y = x, y
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

return Ghost
