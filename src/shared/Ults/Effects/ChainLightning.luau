--!strict
-- Chain Lightning (docs/prompts/ABILITIES_PROMPT.md 7.8): the first ball the cue ball hits, if
-- it is the shooter's, is charged, and lightning chains from it ball to ball.
--
-- * The charge: the step of the cue ball's first contact, if that ball is in
--   overrides.Targets (the 8 only on the legal 8 shot, toward overrides.EightPocket), the bolt
--   drives it down the clear line into the pocket nearest its heading (lineUp, the Rare+ buff
--   of 2026-10-08), rolling, at its speed times Boost and never too slow to drop. With no
--   clear line in, its heading turns toward its best pocket (the mouth nearest its line, ahead
--   of it) by at most Config.Ults.ChainLightning.SteerTan (the tangent of the capped angle)
--   and its speed is multiplied by Boost, its spin turned and scaled with it. Any other first
--   ball (the opponent's, the 8 off the legal 8 shot), or no contact at all: no lightning.
-- * The chain: every LinkSeconds after the charge, the bolt jumps from the last ball it struck
--   (the charged ball first) to the nearest ball within ReachInches of it, whoever's it is
--   (5.7): the shooter's (Targets) or the opponent's (OppTargets), never the cue ball, never
--   the 8 unless it is the shooter's legal 8, never a ball it already struck, never more than
--   Config.Ults.ChainLightning.MaxOpp of the opponent's (past that the chain jumps over them) or
--   MaxOwn of the shooter's. Up to Links jumps; the chain ends early when nothing is in
--   reach.
-- * The push: each struck ball rolls toward its closest pocket with a clear line in (no ball
--   in the way, no jaw touched, traced with a ball ClearanceInches fatter), or toward its
--   closest pocket when none is clear; fast enough to roll PushReachShare of the way there
--   (at most PushMaxInches), so a ball near an open pocket drops and a far one only moves
--   toward it. The opponent's get OpponentFactor of that speed. The push is added to any
--   motion the ball already has, as natural roll.
-- * `ult` events for the look: "charge" (ball = the charged ball, other = its pocket, value =
--   1 when it was sent down a clear line), then
--   one "link" per jump (ball = the ball it jumped from, other = the ball struck, value = its
--   push factor: 1 yours, OpponentFactor theirs).
--
-- Only arithmetic and square roots, no trig and no pow; balls, pockets and table pieces walked
-- in array order (ties keep the first): the server's settle and every client's replay step it
-- to identical bits. Pure Luau: must never require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)
local Collision = require(script.Parent.Parent.Parent.Physics.Collision)
local Magnet = require(script.Parent.Magnet)

local ChainLightning = {}

local EIGHT = 8
local R = Config.Balls.RadiusInches

type Chain = {
	from: number, -- the ball the next jump starts from
	struck: { [number]: boolean }, -- every ball the lightning touched (the charged one too)
	links: number,
	own: number,
	opp: number,
	nextAt: number, -- the time of the next jump
	done: boolean,
}

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

--- The push factor lightning strikes this ball with this shot: 1 for the shooter's (the 8 only
--- with a pocket called for it), OpponentFactor for the opponent's, 0 when it is never struck
--- (the cue ball, the 8 otherwise, a ball in neither list).
function ChainLightning.factor(state: any, id: number): number
	local o = state.overrides
	if o == nil or id == 0 then
		return 0
	end
	if id == EIGHT then
		return if o.EightPocket ~= nil and contains(o.Targets, id) then 1 else 0
	end
	if contains(o.Targets, id) then
		return 1
	end
	if contains(o.OppTargets, id) then
		return Config.Ults.Shared.OpponentFactor
	end
	return 0
end

-- On the cloth and in play: not dropped, not in the air, not over a pocket's lip.
local function onCloth(b: any): boolean
	return not b.pocketed and b.tip == nil and b.z == 0 and b.vz == 0
end

-- The pockets a ball may be sent to: only the called one for the 8.
local function allowed(state: any, b: any, pocket: any): boolean
	return b.id ~= EIGHT or pocket.id == state.overrides.EightPocket
end

--- Whether a ball of radius `r` rolling from (x, y) along the unit (hx, hy) drops into `pocket`
--- before touching any cushion, jaw or other ball (Steel Ball uses it too).
function ChainLightning.clearInto(
	state: any,
	b: any,
	pocket: any,
	hx: number,
	hy: number,
	r: number
): boolean
	local fx, fy = b.x - pocket.x, b.y - pocket.y
	local along = fx * hx + fy * hy
	local c = fx * fx + fy * fy - pocket.radius * pocket.radius
	local enter
	if c <= 0 then
		return true
	else
		local disc = along * along - c
		if disc < 0 or along >= 0 then
			return false
		end
		enter = -along - math.sqrt(disc)
	end
	local geometry = state.geometry
	for _, seg in geometry.segments do
		if Collision.segmentTOI(b.x, b.y, hx, hy, r, seg, enter) then
			return false
		end
	end
	for _, pt in geometry.points do
		if Collision.pointTOI(b.x, b.y, hx, hy, r, pt.x, pt.y, pt.radius, enter) then
			return false
		end
	end
	-- Another ball whose centre comes within two radii of the path before the opening.
	for _, o in state.balls do
		if o == b or o.pocketed then
			continue
		end
		local ox, oy = o.x - b.x, o.y - b.y
		local t = ox * hx + oy * hy
		if t > 0 and t < enter + R then
			local px, py = ox - hx * t, oy - hy * t
			if px * px + py * py < (R + r) * (R + r) then
				return false
			end
		end
	end
	return true
end

-- Offsets across a pocket's opening tried for a clear line in, as shares of its radius (the
-- centre first, then either side, nearer first).
local AIM_OFFSETS = { 0, 0.3, -0.3, 0.6, -0.6, 0.85, -0.85 }

--- The pocket a struck ball is pushed toward, the unit heading, the distance to the point
--- aimed at, and whether that line drops clean: the closest pocket with a clear line in (aimed
--- at the opening's centre, or beside it), else the closest pocket's centre.
function ChainLightning.pushTarget(state: any, b: any): (any, number, number, number, boolean)
	local C = Config.Ults.ChainLightning
	local r = R + C.ClearanceInches
	local best, bestD, clear = nil, math.huge, false
	local bx, by = 0, 0
	for _, pocket in state.geometry.pockets do
		if not allowed(state, b, pocket) then
			continue
		end
		local dx, dy = pocket.x - b.x, pocket.y - b.y
		local d = math.sqrt(dx * dx + dy * dy)
		if d < 1e-9 then
			continue
		end
		local hx, hy = dx / d, dy / d
		local found, fx, fy, fd = false, hx, hy, d
		for _, share in AIM_OFFSETS do
			-- A point across the opening (perpendicular to the line at its centre).
			local off = share * pocket.radius
			local ax, ay = dx - hy * off, dy + hx * off
			local al = math.sqrt(ax * ax + ay * ay)
			local tx, ty = ax / al, ay / al
			if ChainLightning.clearInto(state, b, pocket, tx, ty, r) then
				found, fx, fy, fd = true, tx, ty, al
				break
			end
		end
		if (found and not clear) or (found == clear and fd < bestD) then
			best, bestD, clear, bx, by = pocket, fd, found, fx, fy
		end
	end
	return best, bx, by, bestD, clear
end

--- The line a ball is sent down into a pocket (the Rare+ buffs, 2026-10-08: Chain Lightning's
--- charge, a portal's exit, Time Stop's struck ball): of the pockets it may go to with a clear
--- line in (tried as pushTarget's: the opening's centre, then beside it), the one nearest the
--- heading (hx, hy), or the closest when there is no heading. Returns the pocket's id, the
--- unit heading and the distance to the point aimed at; nil when no line is clear.
function ChainLightning.lineUp(
	state: any,
	b: any,
	hx: number,
	hy: number
): (number?, number, number, number)
	local r = R + Config.Ults.ChainLightning.ClearanceInches
	local heading = hx ~= 0 or hy ~= 0
	local bestId, bestScore, ux, uy, ud = nil, -math.huge, 0, 0, 0
	for _, pocket in state.geometry.pockets do
		if not allowed(state, b, pocket) then
			continue
		end
		local dx, dy = pocket.x - b.x, pocket.y - b.y
		local d = math.sqrt(dx * dx + dy * dy)
		if d < 1e-9 then
			continue
		end
		local px, py = dx / d, dy / d
		for _, share in AIM_OFFSETS do
			local off = share * pocket.radius
			local ax, ay = dx - py * off, dy + px * off
			local al = math.sqrt(ax * ax + ay * ay)
			local tx, ty = ax / al, ay / al
			if ChainLightning.clearInto(state, b, pocket, tx, ty, r) then
				local score = if heading then tx * hx + ty * hy else -al
				if score > bestScore then
					bestId, bestScore, ux, uy, ud = pocket.id, score, tx, ty, al
				end
				break
			end
		end
	end
	return bestId, ux, uy, ud
end

--- Send `b` down the unit (ux, uy) toward a point `d` inches on: rolling, no side spin, fast
--- enough to get there still doing `arrive` in/s, and never slower than `least`.
function ChainLightning.send(
	b: any,
	ux: number,
	uy: number,
	d: number,
	arrive: number,
	least: number
)
	local decel = Config.Physics.RollingFriction * Config.Physics.Gravity
	local speed = math.max(math.sqrt(arrive * arrive + 2 * decel * d), least)
	b.vx, b.vy = ux * speed, uy * speed
	b.wx, b.wy, b.wz = -b.vy / R, b.vx / R, 0
end

-- Push `b` toward its pocket at `factor` of the full push, added to its motion as natural roll.
local function push(state: any, b: any, factor: number)
	local C = Config.Ults.ChainLightning
	local pocket, hx, hy, d = ChainLightning.pushTarget(state, b)
	if pocket == nil then
		return
	end
	local roll = math.min(d * C.PushReachShare, C.PushMaxInches)
	-- Rolling from speed v stops after v^2 / (2 * decel): the speed that rolls `roll` inches.
	local decel = Config.Physics.RollingFriction * Config.Physics.Gravity
	local speed = math.sqrt(2 * decel * roll) * factor
	local vx, vy = hx * speed, hy * speed
	b.vx += vx
	b.vy += vy
	b.wx += -vy / R
	b.wy += vx / R
end

-- The charged ball's pocket. The bolt drives it down the clear line in nearest its heading
-- (lineUp), boosted and never too slow to get there; with no clear line, its heading turns
-- toward the mouth nearest its line, ahead of it, by at most SteerTan (only the called pocket
-- for the 8).
local function charge(state: any, b: any): (number?, boolean)
	local C = Config.Ults.ChainLightning
	local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
	if speed < 1e-9 then
		return nil, false
	end
	local nx, ny = b.vx / speed, b.vy / speed
	local lined, lx, ly, ld = ChainLightning.lineUp(state, b, nx, ny)
	if lined ~= nil then
		ChainLightning.send(b, lx, ly, ld, C.ChargeArriveSpeed, speed * C.Boost)
		return lined, true
	end
	local bestDot, px, py, bestId = 0, 0, 0, nil
	for _, pocket in state.geometry.pockets do
		if not allowed(state, b, pocket) then
			continue
		end
		local mx, my = Magnet.mouthPoint(state.geometry, pocket)
		local ux, uy = mx - b.x, my - b.y
		local ul = math.sqrt(ux * ux + uy * uy)
		if ul < 1e-9 then
			continue
		end
		ux, uy = ux / ul, uy / ul
		local dot = nx * ux + ny * uy
		if dot > bestDot then
			bestDot, px, py, bestId = dot, ux, uy, pocket.id
		end
	end
	local ox, oy = nx, ny
	if bestId ~= nil then
		local cross = nx * py - ny * px -- > 0: the pocket is anticlockwise of the heading
		if math.abs(cross) <= C.SteerTan * bestDot then
			ox, oy = px, py -- within the cap: straight at it
		else
			local s = if cross > 0 then C.SteerTan else -C.SteerTan
			ox, oy = nx - ny * s, ny + nx * s
			local ol = math.sqrt(ox * ox + oy * oy)
			ox, oy = ox / ol, oy / ol
		end
	end
	-- Turn and scale velocity and spin alike (c, s: the turn's cosine and sine x the boost).
	local c = (nx * ox + ny * oy) * C.Boost
	local s = (nx * oy - ny * ox) * C.Boost
	b.vx, b.vy = c * b.vx - s * b.vy, s * b.vx + c * b.vy
	b.wx, b.wy = c * b.wx - s * b.wy, s * b.wx + c * b.wy
	return bestId, false
end

-- The nearest ball the chain may jump to from `from`, or nil.
local function nextLink(state: any, chain: Chain, from: any): (any, number)
	local C = Config.Ults.ChainLightning
	local S = Config.Ults.Shared
	local reach = math.min(C.ReachInches, S.MaxReachShare * 2 * state.geometry.halfLength)
	local best, bestD2, bestFactor = nil, reach * reach, 0
	for _, b in state.balls do
		if b == from or chain.struck[b.id] or not onCloth(b) then
			continue
		end
		local factor = ChainLightning.factor(state, b.id)
		if factor <= 0 then
			continue
		end
		if factor < 1 and chain.opp >= Config.Ults.ChainLightning.MaxOpp then
			continue
		end
		if factor >= 1 and chain.own >= Config.Ults.ChainLightning.MaxOwn then
			continue
		end
		local dx, dy = b.x - from.x, b.y - from.y
		local d2 = dx * dx + dy * dy
		if d2 <= bestD2 then
			if best == nil or d2 < bestD2 then
				best, bestD2, bestFactor = b, d2, factor
			end
		end
	end
	return best, bestFactor
end

function ChainLightning.after(state: any, _dt: number, events: { any }, ops: any)
	local fx = state.fx
	if fx.cancelled then
		return
	end
	local chain: Chain? = fx.chain
	if chain == nil then
		local first = nil
		for _, ev in events do
			if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
				first = if ev.ball == 0 then ev.other else ev.ball
				break
			end
		end
		if first == nil then
			return
		end
		local b = findBall(state, first)
		if b == nil or ChainLightning.factor(state, first) < 1 or b.pocketed then
			fx.cancelled = true -- not the shooter's ball: no lightning
			return
		end
		local pocket, lined = charge(state, b)
		fx.chain = {
			from = first,
			struck = { [first] = true },
			links = 0,
			own = 0,
			opp = 0,
			nextAt = state.time + Config.Ults.ChainLightning.LinkSeconds,
			done = false,
		}
		ops.emit(state, events, "charge", first, pocket, b.x, b.y, if lined then 1 else nil)
		return
	end
	if chain.done or state.time < chain.nextAt then
		return
	end
	local C = Config.Ults.ChainLightning
	local from = findBall(state, chain.from)
	local to, factor = nil, 0
	if from then
		to, factor = nextLink(state, chain, from)
	end
	if to == nil then
		chain.done = true
		return
	end
	chain.struck[to.id] = true
	chain.links += 1
	if factor >= 1 then
		chain.own += 1
	else
		chain.opp += 1
	end
	push(state, to, factor)
	ops.emit(state, events, "link", chain.from, to.id, to.x, to.y, factor)
	chain.from = to.id
	chain.nextAt = state.time + C.LinkSeconds
	chain.done = chain.links >= C.Links
end

return ChainLightning
