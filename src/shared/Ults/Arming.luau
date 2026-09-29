--!strict
-- What the server's rules hand an ability for its shot (docs/prompts/ABILITIES_PROMPT.md 5.2,
-- 5.7): which balls are the shooter's and which the opponent's, the aim-phase pick, and each
-- ability's own extra overrides. Pure: no Instances, no clocks, no randomness; every list is
-- built in ball-id order.
--
-- * Whose balls (5.7). "Yours" is your group's balls still up; on an open table every ball
--   but the 8; on your legal 8 shot (your group cleared, a pocket called) the 8 counts as
--   yours (EightPocket = the called pocket). "The opponent's" is the other group's balls
--   still up (none on an open table). Never the cue ball; the 8 only as yours on your legal 8
--   shot. The effect decides what it does with each list (the area abilities act on the
--   opponent's at Config.Ults.Shared.OpponentFactor; the others ignore it).
-- * Picks. `Arming.pick` checks a pick from the client against the table: "OwnBall" is one of
--   your balls (the 8 only on your legal 8 shot); "Portals" is two spots on the cloth clear
--   of the cushions, the pockets, every ball and each other. Anything else is refused.
-- * Extras. `Arming.extras(id, ctx)` is each ability's own overrides (Ghost's PhaseCue, Super
--   Bounce's cue material ...), from Config; an ability with none adds nothing.
local Config = require(script.Parent.Parent.Config)
local Judge = require(script.Parent.Parent.Rules.ShotJudge)

local S = Config.Ults.Shared

local Arming = {}

export type Context = {
	own: { number },
	opp: { number },
	eightPocket: number?,
	legalEight: boolean, -- the shooter's legal 8 shot
	open: boolean, -- no groups yet
	pick: { number }?,
	balls: { any }, -- the table just before the strike
}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

--- The shooter's balls and the opponent's for this shot (5.7), in id order, and the 8's
--- called pocket when the 8 is theirs. `groups` is the table's groups, `team` the shooter's
--- side, `called` the called pocket, `before` the balls just before the strike.
function Arming.targets(
	groups: { [number]: string }?,
	team: number,
	called: number?,
	before: { any }
): ({ number }, { number }, number?, boolean)
	local mine = if type(groups) == "table" then groups[team] else nil
	local theirs = if type(groups) == "table" then groups[3 - team] else nil
	local own: { number } = {}
	local opp: { number } = {}
	local eightPocket: number? = nil
	local legalEight = mine ~= nil and Judge.eligible(before, mine :: any) and called ~= nil
	for _, b in before do
		if b.pocketed or b.id == 0 then
			continue
		end
		local g = Judge.group(b.id)
		if b.id == 8 then
			if legalEight then
				table.insert(own, 8)
				eightPocket = called
			end
		elseif mine == nil or g == mine then
			table.insert(own, b.id) -- an open table: every ball but the 8
		elseif g == theirs then
			table.insert(opp, b.id)
		end
	end
	table.sort(own)
	table.sort(opp)
	return own, opp, eightPocket, legalEight
end

--- Checks a pick from the client for an armed ult whose catalog row asks for `kind`. Returns
--- the pick as the overrides carry it ({ ballId } or { ax, ay, bx, by }), or nil and why.
function Arming.pick(
	kind: string,
	request: any,
	geometry: any,
	groups: { [number]: string }?,
	team: number,
	before: { any }
): ({ number }?, string?)
	if type(request) ~= "table" then
		return nil, "BadPick"
	end
	if kind == "OwnBall" then
		local id = request.ball
		if type(id) ~= "number" or id % 1 ~= 0 then
			return nil, "BadPick"
		end
		local mine = if type(groups) == "table" then groups[team] else nil
		if not Judge.legalTarget(before, mine :: any, id) then
			return nil, "NotYourBall"
		end
		return { id }, nil
	elseif kind == "Portals" then
		local ax, ay, bx, by = request.ax, request.ay, request.bx, request.by
		if not (finite(ax) and finite(ay) and finite(bx) and finite(by)) then
			return nil, "BadPick"
		end
		local R = Config.Balls.RadiusInches
		local clear = S.Pick.PortalClearBallWidths * 2 * R
		local function spotOk(x: number, y: number): boolean
			if
				math.abs(x) > geometry.halfLength - clear
				or math.abs(y) > geometry.halfWidth - clear
			then
				return false
			end
			for _, p in geometry.pockets do
				local dx, dy = x - p.x, y - p.y
				local reach = p.radius + clear
				if dx * dx + dy * dy < reach * reach then
					return false
				end
			end
			for _, b in before do
				if not b.pocketed then
					local dx, dy = x - b.x, y - b.y
					local reach = clear + R
					if dx * dx + dy * dy < reach * reach then
						return false
					end
				end
			end
			return true
		end
		if not spotOk(ax, ay) or not spotOk(bx, by) then
			return nil, "PortalBlocked"
		end
		local gx, gy = ax - bx, ay - by
		if gx * gx + gy * gy < S.Pick.PortalMinGapInches * S.Pick.PortalMinGapInches then
			return nil, "PortalsTooClose"
		end
		return { ax, ay, bx, by }, nil
	end
	return nil, "NoPick"
end

-- Each ability's own overrides, from Config (filled as each ability is built).
local EXTRAS: { [string]: (ctx: Context) -> { [string]: any } } = {}

-- Super Bounce (7.3): the cue ball's own bouncy material until the cap.
EXTRAS.SuperBounce = function(_ctx: Context): { [string]: any }
	local SB = Config.Ults.SuperBounce
	return {
		CueRailRestitution = SB.RailRestitution,
		CueRailFriction = SB.RailFriction,
		CueBallRestitution = SB.BallRestitution,
		CueSlidingFriction = SB.SlidingFriction,
		CueRollingFriction = SB.RollingFriction,
		CueUntil = SB.Seconds,
	}
end

--- The ability's own extra overrides for this shot (none for most).
function Arming.extras(effect: string, ctx: Context): { [string]: any }
	local build = EXTRAS[effect]
	return if build then build(ctx) else {}
end

Arming.EXTRAS = EXTRAS

return Arming
