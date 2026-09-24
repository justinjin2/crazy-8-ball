--!strict
-- Pure shot decisions. Consume ordered simulation events, never client claims.
local Ball = require(script.Parent.Parent.Physics.Ball)
local Simulation = require(script.Parent.Parent.Physics.Simulation)

type Ball = Ball.Ball
export type Group = "solids" | "stripes"
export type Groups = { [number]: Group }
export type Context = {
	groups: Groups,
	activeTeam: number,
	breakShot: boolean,
	calledPocket: number?,
	requireRail: boolean?, -- false drops the rail-after-contact rule (casual play)
}
export type Pocket = { ball: number, pocket: number }
-- A ball's first drop this shot: `index` is its event's place in outcome.events (the order
-- a client replay dispatches them in), `t` the shot time it went down.
export type Drop = { ball: number, index: number, t: number }
-- The drop that picked the colors on an open table.
export type Assign = { ball: number, index: number }
export type Verdict = {
	groups: Groups,
	foul: boolean,
	reason: string?,
	winner: number?,
	retain: boolean,
	respotEight: boolean,
	pockets: { Pocket },
	assign: Assign?,
}

local Judge = {}

function Judge.group(id: number): Group?
	return if id % 1 ~= 0
		then nil
		elseif id >= 1 and id <= 7 then "solids"
		elseif id >= 9 and id <= 15 then "stripes"
		else nil
end

function Judge.remaining(balls: { Ball }, group: Group?): number
	local count = 0
	if group == nil then
		return count
	end
	for _, ball in balls do
		if not ball.pocketed and Judge.group(ball.id) == group then
			count += 1
		end
	end
	return count
end

function Judge.eligible(balls: { Ball }, group: Group?): boolean
	if group == nil then
		return false
	end
	for _, b in balls do
		if not b.pocketed and Judge.group(b.id) == group then
			return false
		end
	end
	return true
end

function Judge.opposite(group: string): Group
	return if group == "solids" then "stripes" else "solids"
end

--- Solo play clears one group, then the other, then the 8. The group being played now is
--- `first` while any of it remains, the other group after that; nil until `first` exists.
function Judge.soloGroup(balls: { Ball }, first: Group?): Group?
	if first == nil then
		return nil
	end
	return if Judge.remaining(balls, first) > 0 then first else Judge.opposite(first)
end

function Judge.legalTarget(balls: { Ball }, group: Group?, id: number): boolean
	local exists = false
	for _, ball in balls do
		if ball.id == id and not ball.pocketed then
			exists = true
			break
		end
	end
	if id == 0 or not exists then
		return false
	end
	if id == 8 then
		return Judge.eligible(balls, group)
	end
	return if group == nil then Judge.group(id) ~= nil else Judge.group(id) == group
end

function Judge.resolve(
	before: { Ball },
	outcome: Simulation.ShotOutcome,
	groups: Groups,
	team: number,
	isBreak: boolean,
	called: number?,
	-- The rail-after-contact rule: after the first hit a ball must drop or some ball must
	-- touch a rail. Standard 8-ball, so on unless the caller passes false (casual tables).
	requireRail: boolean?
)
	local pockets: { number } = {}
	local pocketDetails: { Pocket } = {}
	local drops: { Drop } = {}
	local rails: { [number]: boolean } = {}
	local seenPockets: { [number]: boolean } = {}
	local down: { [number]: boolean } = {}
	for _, ball in before do
		down[ball.id] = ball.pocketed
	end
	-- Explicit tie breaks preserve deterministic simulation order without mutating it.
	local order: { number } = {}
	for index = 1, #outcome.events do
		order[index] = index
	end
	table.sort(order, function(a, b)
		local at, bt = outcome.events[a].t, outcome.events[b].t
		return if at == bt then a < b else at < bt
	end)
	local scratch, eight, eightPocket = false, false, nil
	local contacted, railAfter, pocketAfter = false, false, false
	local first: number? = nil
	for _, index in order do
		local ev = outcome.events[index]
		if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
			if not contacted then
				first = if ev.ball == 0 then ev.other else ev.ball
			end
			contacted = true
		end
		if ev.type == "railHit" and contacted then
			railAfter = true
			if ev.ball ~= 0 then
				rails[ev.ball] = true
			end
		elseif ev.type == "pocket" and not seenPockets[ev.ball] and not down[ev.ball] then
			seenPockets[ev.ball] = true
			if ev.other ~= nil then
				table.insert(pocketDetails, { ball = ev.ball, pocket = ev.other })
			end
			if contacted then
				pocketAfter = true
			end
			scratch = scratch or ev.ball == 0
			if ev.ball == 8 then
				eight, eightPocket = true, ev.other
			end
			if ev.ball ~= 0 then
				table.insert(pockets, ev.ball)
				table.insert(drops, { ball = ev.ball, index = index, t = ev.t })
			end
		end
	end
	first = first or outcome.firstContact
	for _, ball in outcome.finalBalls do
		if ball.id == 0 and ball.pocketed then
			scratch = true
		end
	end
	local foul: string? = nil
	if scratch then
		foul = "Scratch"
	elseif first == nil then
		foul = "NoContact"
	elseif isBreak then
		local count = 0
		for id = 1, 15 do
			if rails[id] then
				count += 1
			end
		end
		-- Any ball may be hit first on the break (standard 8-ball): it is legal when an object
		-- ball drops or four different object balls reach a rail.
		if #pockets == 0 and count < 4 then
			foul = "IllegalBreak"
		end
	elseif not Judge.legalTarget(before, groups[team], first) then
		foul = "WrongContact"
	elseif requireRail ~= false and not railAfter and not pocketAfter then
		foul = "NoRail"
	end

	local winner, reason = nil, nil
	if eight and not isBreak then
		if foul then
			winner, reason = 3 - team, "FoulEight"
		elseif not Judge.eligible(before, groups[team]) then
			winner, reason = 3 - team, "EarlyEight"
		elseif eightPocket ~= called then
			winner, reason = 3 - team, "WrongPocket"
		else
			winner, reason = team, "LegalEight"
		end
	end
	local assign: Assign? = nil
	local resultGroups: Groups = {}
	for side = 1, 2 do
		resultGroups[side] = groups[side]
	end
	if not isBreak and not foul and not eight and resultGroups[team] == nil then
		for _, drop in drops do
			local group = Judge.group(drop.ball)
			if group then
				resultGroups[team] = group :: Group
				resultGroups[3 - team] = Judge.opposite(group)
				assign = { ball = drop.ball, index = drop.index }
				break
			end
		end
	end
	local keep = false
	if not foul and winner == nil then
		for _, id in pockets do
			if isBreak or Judge.group(id) == resultGroups[team] then
				keep = true
			end
		end
	end
	return {
		foul = foul,
		winner = winner,
		reason = reason,
		groups = resultGroups,
		assign = assign,
		keep = keep,
		pockets = pockets,
		pocketDetails = pocketDetails,
		drops = drops,
		respotEight = isBreak and eight,
	}
end

-- Structured entry point for consumers that need chronological, deduplicated pocket
-- locations. resolve keeps the match engine's string-foul/keep contract compatible.
function Judge.judge(before: { Ball }, outcome: Simulation.ShotOutcome, context: Context): Verdict
	local result = Judge.resolve(
		before,
		outcome,
		context.groups,
		context.activeTeam,
		context.breakShot,
		context.calledPocket,
		context.requireRail
	)
	return {
		groups = result.groups,
		foul = result.foul ~= nil,
		reason = result.reason or result.foul,
		winner = result.winner,
		retain = result.keep,
		respotEight = result.respotEight,
		pockets = result.pocketDetails,
		assign = result.assign,
	}
end

return Judge
