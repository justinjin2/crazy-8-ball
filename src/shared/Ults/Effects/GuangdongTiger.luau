--!strict
-- Guangdong Tiger (docs/prompts/ABILITIES_PROMPT.md 7.13): at the cue ball's first contact a
-- giant tiger swipes the area round it and the balls there are cut off the table.
--
-- * The swipe: the step of the cue ball's first contact, centred on the middle of the two
--   centres (a wrong first ball is still a foul: ShotJudge's first contact; the swipe happens
--   anyway). No contact at all: nothing happens.
-- * The cut: every object ball on the cloth within Config.Ults.GuangdongTiger.RadiusInches
--   (the shooter's) or RadiusInches x OpponentFactor (the opponent's, 5.7), the closest first,
--   at most MaxOwnPerUse of the shooter's and MaxOppPerUse of the opponent's, leaves the table
--   at once (Simulation.Ops.remove: a `removed` event ShotJudge counts as a pot for its owner).
--   Never the cue ball; the 8 only on the shooter's legal 8 shot (it is in overrides.Targets).
-- * The moment slows (a `slow` event: SlowShotSeconds of play over SlowSeconds more), then the
--   shot carries on.
-- * `ult` events for the look: "swipe" (ball = the first ball hit, at the centre), "slow", then a
--   "cut" per ball (at where it was, value = its owner's factor, other = the order it was cut).
--
-- Only arithmetic and square roots, no trig and no pow; balls walked in array order (ties keep
-- the first): the server's settle and every client's replay step it to identical bits. Pure
-- Luau: must never require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)

local GuangdongTiger = {}

local EIGHT = 8

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

-- The owner's factor for ball `id`: 1 the shooter's (the 8 only when listed: the legal 8
-- shot), OpponentFactor the opponent's (never the 8), 0 never.
local function factorOf(state: any, id: number): number
	local o = state.overrides
	if o == nil or id == 0 then
		return 0
	end
	if contains(o.Targets, id) then
		return 1
	end
	if id ~= EIGHT and contains(o.OppTargets, id) then
		return Config.Ults.Shared.OpponentFactor
	end
	return 0
end

-- Cut every ball in reach of (x, y), the closest first, within the caps.
local function cut(state: any, events: { any }, ops: any, x: number, y: number)
	local S = Config.Ults.Shared
	local reach = math.min(
		Config.Ults.GuangdongTiger.RadiusInches,
		S.MaxReachShare * 2 * state.geometry.halfLength
	)
	local list: { { ball: any, d2: number, factor: number } } = {}
	for _, b in state.balls do
		if b.id == 0 or not onCloth(b) then
			continue
		end
		local factor = factorOf(state, b.id)
		if factor <= 0 then
			continue
		end
		local r = if factor >= 1 then reach else reach * S.OpponentFactor
		local dx, dy = b.x - x, b.y - y
		local d2 = dx * dx + dy * dy
		if d2 <= r * r then
			table.insert(list, { ball = b, d2 = d2, factor = factor })
		end
	end
	-- Closest first; equal distances keep array order (an insertion sort: stable).
	for i = 2, #list do
		local item = list[i]
		local j = i - 1
		while j >= 1 and list[j].d2 > item.d2 do
			list[j + 1] = list[j]
			j -= 1
		end
		list[j + 1] = item
	end
	local own, opp, order = 0, 0, 0
	for _, item in list do
		local b = item.ball
		if item.factor >= 1 then
			if own >= S.MaxOwnPerUse then
				continue
			end
			own += 1
		else
			if opp >= S.MaxOppPerUse then
				continue
			end
			opp += 1
		end
		order += 1
		local bx, by = b.x, b.y
		ops.remove(state, events, b, "GuangdongTiger")
		ops.emit(state, events, "cut", b.id, order, bx, by, item.factor)
	end
end

function GuangdongTiger.after(state: any, _dt: number, events: { any }, ops: any)
	local fx = state.fx
	if fx.swiped then
		return
	end
	for _, ev in events do
		if ev.type ~= "ballHit" or (ev.ball ~= 0 and ev.other ~= 0) then
			continue
		end
		local id = if ev.ball == 0 then ev.other else ev.ball
		local b = findBall(state, id)
		local cue = findBall(state, 0)
		if b == nil or cue == nil then
			continue
		end
		fx.swiped = true
		local x, y = (b.x + cue.x) / 2, (b.y + cue.y) / 2
		local C = Config.Ults.GuangdongTiger
		ops.emit(state, events, "swipe", id, nil, x, y)
		ops.emit(state, events, "slow", id, nil, C.SlowShotSeconds, nil, C.SlowSeconds)
		cut(state, events, ops, x, y)
		return
	end
end

return GuangdongTiger
