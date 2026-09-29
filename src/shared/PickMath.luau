--!strict
-- PickMath: the pure helpers behind the aim-phase pick view (src/client/UltPick.luau;
-- docs/prompts/ABILITIES_PROMPT.md 5.2, 7.5 Heat Seeker, 7.9 Portals). No Instances, no
-- clocks, no randomness; every list is walked in array order.
--
-- * Which pick the local player owes, read from a snapshot's `ults` view the way the server's
--   Ults/Match.pickNeeded reads its own state, so the client asks exactly when the server
--   would refuse the shot with "PickRequired".
-- * Whether the snapshot's pick is the one the client sent (the view shows again if not).
-- * The gamepad's moves between pickable balls (D-pad: the nearest ball that way on screen,
--   as the 8's pocket rings do) and the nearest ball to a pointer or cursor.
-- * Portal spots: kept on the cloth, a starting spot for portal B, and whether one spot is
--   clear on its own (Ults/Arming's own rule, so the preview never disagrees with the server).
local Config = require(script.Parent.Config)
local Arming = require(script.Parent.Ults.Arming)
local Catalog = require(script.Parent.Ults.Catalog)

local P = Config.UI.UltPick
local S = Config.Ults.Shared

local PickMath = {}

-- A candidate on screen (or on the table): its ball id and where it is.
export type Point = { id: number, x: number, y: number }

--- The pick kind of the local player's armed ability ("OwnBall", "Portals"), or nil: `ults` is
--- the snapshot's `ults` view, `shooter` the snapshot's shooter. Only for the shooter's own
--- armed ult (stage Armed, or still Arming past its readyAt by `now`: the server flips it on its
--- next tick), a built ult whose catalog row has a Pick. Whether a pick is already made is
--- left to the caller (see `owed`).
function PickMath.kind(ults: any, shooter: any, userId: number, now: number): string?
	local armed = type(ults) == "table" and ults.armed or nil
	if type(armed) ~= "table" or armed.by ~= userId or shooter ~= userId then
		return nil
	end
	local ready = armed.stage == "Armed"
		or (armed.stage == "Arming" and type(armed.readyAt) == "number" and now >= armed.readyAt)
	if not ready then
		return nil
	end
	local ult = Catalog.get(armed.id)
	if ult == nil or not ult.Built then
		return nil
	end
	return ult.Pick
end

--- The pick still owed before the shot, or nil: `kind` with no pick in the snapshot yet (the
--- server's Ults/Match.pickNeeded).
function PickMath.owed(ults: any, shooter: any, userId: number, now: number): string?
	local kind = PickMath.kind(ults, shooter, userId, now)
	if kind == nil or ults.armed.pick ~= nil then
		return nil
	end
	return kind
end

--- The table action's fields for a pick ({ ball } or { ax, ay, bx, by }), from the pick as
--- the overrides carry it ({ id } or { ax, ay, bx, by }).
function PickMath.request(kind: string, pick: { number }): { [string]: number }
	if kind == "OwnBall" then
		return { ball = pick[1] }
	end
	return { ax = pick[1], ay = pick[2], bx = pick[3], by = pick[4] }
end

--- True when `a` and `b` are the same pick (both arrays of numbers, equal within a hair).
function PickMath.same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b or #a == 0 then
		return false
	end
	for i = 1, #a do
		local x, y = a[i], b[i]
		if type(x) ~= "number" or type(y) ~= "number" or math.abs(x - y) > 1e-6 then
			return false
		end
	end
	return true
end

--- The candidate nearest (x, y) within `reach`, or nil. A tie goes to the earlier one.
function PickMath.nearest(points: { Point }, x: number, y: number, reach: number): number?
	local best, bestD = nil, reach * reach
	for _, p in points do
		local dx, dy = p.x - x, p.y - y
		local d = dx * dx + dy * dy
		if d <= bestD and (best == nil or d < bestD) then
			best, bestD = p.id, d
		end
	end
	return best
end

--- The gamepad's D-pad: from (fromX, fromY), the candidate that way (`dirX`, `dirY`, in the
--- same space as the points; screen pixels with y down), or nil when none lies that way. As
--- the 8's pocket rings: within about 63 degrees of the push, nearest first, sideways distance
--- counting Config.UI.UltPick.NavAcrossWeight times. `skip` (the current ball) is never chosen.
function PickMath.step(
	points: { Point },
	fromX: number,
	fromY: number,
	dirX: number,
	dirY: number,
	skip: number?
): number?
	local length = math.sqrt(dirX * dirX + dirY * dirY)
	if length < 1e-9 then
		return nil
	end
	local ux, uy = dirX / length, dirY / length
	local best, bestScore = nil, math.huge
	for _, p in points do
		if p.id ~= skip then
			local ox, oy = p.x - fromX, p.y - fromY
			local along = ox * ux + oy * uy
			local across = math.abs(ox * uy - oy * ux)
			if along > 0 and across <= along * 2 then
				local score = along + across * P.NavAcrossWeight
				if score < bestScore then
					best, bestScore = p.id, score
				end
			end
		end
	end
	return best
end

-- How far a portal's centre must stay inside the cushion lines (Ults/Arming's clearance).
local function clearance(): number
	return S.Pick.PortalClearBallWidths * 2 * Config.Balls.RadiusInches
end

--- A spot kept on the cloth, at least the portals' clearance inside the cushion lines.
function PickMath.clampToCloth(x: number, y: number, geometry: any): (number, number)
	local c = clearance()
	local hx = math.max(0, geometry.halfLength - c)
	local hy = math.max(0, geometry.halfWidth - c)
	return math.clamp(x, -hx, hx), math.clamp(y, -hy, hy)
end

--- Where portal A starts for a gamepad (Config.UI.UltPick.PortalStartX along the length, on
--- the centre line), kept on the cloth.
function PickMath.startSpot(geometry: any): (number, number)
	return PickMath.clampToCloth(P.PortalStartX, 0, geometry)
end

--- Where portal B starts for a gamepad once A is at (ax, ay): mirrored across the table's
--- middle, and pushed along the length until it is at least the minimum gap from A.
function PickMath.partnerSpot(ax: number, ay: number, geometry: any): (number, number)
	local gap = S.Pick.PortalMinGapInches * P.PartnerGapShare
	local bx = -ax
	if math.abs(bx - ax) < gap then
		bx = ax + (if ax <= 0 then gap else -gap)
	end
	return PickMath.clampToCloth(bx, ay, geometry)
end

--- True when one portal spot is clear on its own of the cushions, the pockets and every ball:
--- Ults/Arming.pick's own check (a pair on the same spot fails only on the gap if the spot
--- itself is clear).
function PickMath.spotClear(x: number, y: number, geometry: any, balls: { any }): boolean
	local _, why =
		Arming.pick("Portals", { ax = x, ay = y, bx = x, by = y }, geometry, nil, 1, balls)
	return why ~= "PortalBlocked" and why ~= "BadPick"
end

return PickMath
