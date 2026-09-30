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

-- Which kind of nice shot a pot was. Pay and effects key off these names (Config.Economy).
export type Kind = "Bank" | "Kick" | "Combo" | "Carom"

--- Which nice shot ball `ballId`, dropping at `events[dropIndex]`, was: "Combo" (another
--- object ball knocked it in, touching it first), "Kick" (the cue ball met a cushion before
--- it), "Carom" (the cue ball met another ball before it), "Bank" (it met a cushion itself
--- after it was touched), or nil for a plain pot and for the cue ball. When the cue ball met
--- both a cushion and another ball on its way, the first of the two names it.
function NiceShot.kind(
	events: { Event },
	ballId: number,
	dropIndex: number,
	pockets: { Pocket }
): Kind?
	if ballId == 0 then
		return nil
	end
	-- A ball an ability took off the table (Black Flash, Black Hole, the Tiger: a "removed"
	-- event) counts as pocketed but was no shot of the player's: never a nice shot.
	local drop = events[dropIndex]
	if drop ~= nil and drop.type == "removed" then
		return nil
	end
	local cueDetour: Kind? = nil -- the cue ball met a cushion (Kick) or another ball (Carom)
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
				if partner ~= 0 then
					return "Combo"
				elseif cueDetour ~= nil then
					return cueDetour -- the cue ball came round to it
				end
			elseif partner == nil and not touched and (ev.ball == 0 or other == 0) then
				cueDetour = cueDetour or "Carom" -- the cue ball hit another ball first
			end
		elseif ev.type == "railHit" and awayFromPockets(ev, pockets) then
			if ev.ball == ballId and touched then
				return "Bank"
			elseif ev.ball == 0 and not touched then
				cueDetour = cueDetour or "Kick"
			end
		end
	end
	return nil
end

--- Whether ball `ballId`, dropping at `events[dropIndex]`, was a nice shot (any kind).
function NiceShot.isNice(
	events: { Event },
	ballId: number,
	dropIndex: number,
	pockets: { Pocket }
): boolean
	return NiceShot.kind(events, ballId, dropIndex, pockets) ~= nil
end

return NiceShot
