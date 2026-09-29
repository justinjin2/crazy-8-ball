--!strict
-- Super Bounce (docs/prompts/ABILITIES_PROMPT.md 7.3): the cue ball keeps bouncing, and the
-- first ball of yours it hits catches the bounce.
--
-- The cue ball: its own material for the shot's first Config.Ults.SuperBounce.Seconds
-- (Arming.extras puts CueRailRestitution, CueRailFriction, CueBallRestitution,
-- CueSlidingFriction, CueRollingFriction and CueUntil in the overrides; Simulation applies
-- them to the cue ball alone, and normal friction returns after CueUntil).
--
-- The caught ball (the designer, 2026-09-29: the cue ball alone measured about +0.05 balls a
-- use, the random knocks helping both sides alike): when the cue ball's first contact is one
-- of the shooter's balls (overrides.Targets, never the 8), that ball gets
-- Config.Ults.SuperBounce.Caught's springier cushions and lower cloth losses for Caught.Seconds
-- from the hit (State.fx.material), and a cushion hit near a pocket's jaw boings it in
-- (Caught.JawReachInches; a ball bouncing at random almost never finds a pocket on its own),
-- so a near miss gets another chance. `ult` events "caught" and "jaw" tell the look. A first
-- contact on the opponent's ball or the 8 catches nothing. Pure and deterministic: the first
-- contact is the step's own event, the target check and the pockets walk their arrays in order.

local Config = require(script.Parent.Parent.Parent.Config)

local SuperBounce = {}

local function isTarget(targets: { number }?, id: number): boolean
	if targets == nil then
		return false
	end
	for _, t in targets do
		if t == id then
			return true
		end
	end
	return false
end

-- The caught ball boings off a pocket's jaw into it: a cushion hit within JawReachInches of a
-- pocket's rim sends it at that pocket's centre at its speed, spin dropped, with an `ult`
-- event of kind "jaw" (the pocket in `other`) for the look.
local function jaws(state: any, events: { any }, id: number, ops: any)
	local C = Config.Ults.SuperBounce.Caught
	local reach = C.JawReachInches
	local mat = state.fx.material and state.fx.material[id]
	if reach == nil or mat == nil or state.time >= mat.Until then
		return
	end
	local boinged: { any } = {}
	for _, ev in events do
		if ev.type == "railHit" and ev.ball == id and ev.x and ev.y then
			for _, b in state.balls do
				if b.id ~= id or b.pocketed then
					continue
				end
				for _, p in state.geometry.pockets do
					local dx, dy = p.x - ev.x, p.y - ev.y
					local d = math.sqrt(dx * dx + dy * dy)
					if d > 1e-9 and d < p.radius + reach then
						local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
						local tx, ty = p.x - b.x, p.y - b.y
						local len = math.sqrt(tx * tx + ty * ty)
						if len > 1e-9 then
							b.vx, b.vy = speed * tx / len, speed * ty / len
							b.wx, b.wy, b.wz = 0, 0, 0
							table.insert(boinged, { pocket = p.id, x = ev.x, y = ev.y })
						end
						break
					end
				end
			end
		end
	end
	for _, j in boinged do
		ops.emit(state, events, "jaw", id, j.pocket, j.x, j.y)
	end
end

function SuperBounce.after(state: any, _dt: number, events: { any }, ops: any)
	local fx = state.fx
	if fx.firstContact then
		if fx.caught then
			jaws(state, events, fx.caught, ops)
		end
		return
	end
	for _, ev in events do
		if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
			local id = if ev.ball == 0 then ev.other else ev.ball
			fx.firstContact = id
			local overrides = state.overrides
			if id and id ~= 8 and isTarget(overrides and overrides.Targets, id) then
				local C = Config.Ults.SuperBounce.Caught
				fx.caught = id
				fx.material = fx.material or {}
				fx.material[id] = {
					RailRestitution = C.RailRestitution,
					RailFriction = C.RailFriction,
					BallRestitution = C.BallRestitution,
					SlidingFriction = C.SlidingFriction,
					RollingFriction = C.RollingFriction,
					Until = state.time + C.Seconds,
				}
				ops.emit(state, events, "caught", id)
			end
			return
		end
	end
end

return SuperBounce
