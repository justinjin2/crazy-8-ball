--!strict
-- NICE SHOT! (designer, 2026-09-27): whether a ball that dropped was a skill shot. Any pot but
-- a plain one is: a bank (the ball off a cushion), a combo (knocked in by another object
-- ball), a kick (the cue ball off a cushion first) or a carom (the cue ball off another ball
-- first). A plain pot is the cue ball going straight to the ball, touching it first, and the
-- ball going straight in. Pure: it reads the shot's ordered events, as the replay dispatches
-- them. Whose pot it was, and the break, are the caller's to judge.
local Config = require(script.Parent.Parent.Config)
local Simulation = require(script.Parent.Parent.Physics.Simulation)
local Table = require(script.Parent.Parent.Physics.Table)

type Event = Simulation.Event
type Pocket = Table.Pocket

local C = Config.Effects.NiceShot
local NiceShot = {}

-- A cushion, not the jaws or facings of a pocket (those are rail hits too, right at it).
local function awayFromPockets(ev: Event, pockets: { Pocket }): boolean
	local x, y = ev.x, ev.y
	if x == nil or y == nil then
		return false
	end
	local clear = C.RailClearInches * C.RailClearInches
	for _, p in pockets do
		if (x - p.x) ^ 2 + (y - p.y) ^ 2 < clear then
			return false
		end
	end
	return true
end

--- Whether ball `ballId`, dropping at `events[dropIndex]`, was a nice shot.
function NiceShot.isNice(
	events: { Event },
	ballId: number,
	dropIndex: number,
	pockets: { Pocket }
): boolean
	if ballId == 0 then
		return false
	end
	local cueDetour = false -- the cue ball met a cushion or another ball before this one
	local touched = false
	for index = 1, math.min(dropIndex, #events) do
		local ev = events[index]
		if ev.type == "ballHit" then
			local other = ev.other
			local partner = if ev.ball == ballId
				then other
				elseif other == ballId then ev.ball
				else nil
			if partner ~= nil and not touched then
				touched = true
				if partner ~= 0 or cueDetour then
					return true -- a combo, or the cue ball came round to it: a kick or carom
				end
			elseif partner == nil and not touched and (ev.ball == 0 or other == 0) then
				cueDetour = true -- the cue ball hit another ball first
			end
		elseif ev.type == "railHit" and awayFromPockets(ev, pockets) then
			if ev.ball == ballId and touched then
				return true -- a bank
			elseif ev.ball == 0 and not touched then
				cueDetour = true
			end
		end
	end
	return false
end

return NiceShot
