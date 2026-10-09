--!strict
-- Fire Shot (the designer, 2026-10-08: Super Bounce reworked; the starter ability): the cue
-- ball bursts into flames and leaves the cue at Config.Ults.FireShot.LaunchSpeedScale times
-- its stroke's speed. Its full aim lines (Physics/Aim.fullLines: the guideline's lines after
-- the first ball run on to the next cushion, src/client/Guideline.luau) and the flames and
-- scorch marks (src/client/FireShotFx.luau) are the client's; the physics is only the launch.
--
-- The launch is Black Flash's (Effects/BlackFlash.step): the first step after the strike
-- scales the cue ball's motion along the cloth and its spin, once (state.fx.launched). A hard
-- stroke's little hop (vz) stays as it is. Pure and deterministic: multiplications only.
--
-- The scorch line bends exactly where the cue ball does: `after` sends an `ult` event "turn"
-- for each cushion or ball the cue ball meets, with its centre at that moment (x, y), the
-- other ball (other; nil for a cushion) and the impact speed (value), and "down" where it
-- comes down on the cloth from a hop (the burn starts again there). A cushion hit says where
-- it happened (railHit's x, y); a ball hit and a landing do not, so the cue ball's motion at
-- the step's start (kept by `step`) is carried on to it, or for a later one in the same step,
-- its motion at the step's end carried back. Nothing here changes how any ball moves.

local Config = require(script.Parent.Parent.Parent.Config)

local FireShot = {}

local function findBall(state: any, id: number): any
	for _, b in state.balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

function FireShot.step(state: any, _dt: number)
	local fx = state.fx
	local cue = findBall(state, 0)
	if not fx.launched then
		fx.launched = true
		if cue and not cue.pocketed then
			local k = Config.Ults.FireShot.LaunchSpeedScale
			cue.vx, cue.vy = cue.vx * k, cue.vy * k
			cue.wx, cue.wy, cue.wz = cue.wx * k, cue.wy * k, cue.wz * k
		end
	end
	-- Where the cue ball starts this step and how it moves (the turns' positions, `after`).
	if cue then
		fx.fromT, fx.fromX, fx.fromY = state.time, cue.x, cue.y
		fx.fromVx, fx.fromVy = cue.vx, cue.vy
	end
end

-- The cue ball's own cushion and ball hits and landings among a step's events, in order.
local function cueHits(events: { any }): { any }?
	local hits: { any }? = nil
	for _, ev in events do
		if
			(ev.type == "railHit" and ev.ball == 0)
			or (ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0))
			or (ev.type == "land" and ev.ball == 0)
		then
			local list = hits or {}
			hits = list
			table.insert(list, ev)
		end
	end
	return hits
end

function FireShot.after(state: any, _dt: number, events: { any }, ops: any)
	local hits = cueHits(events)
	if hits == nil then
		return
	end
	local fx = state.fx
	local cue = findBall(state, 0)
	for i, ev in hits do
		local x, y = ev.x, ev.y
		if x == nil or y == nil then
			if i == 1 and fx.fromT then
				local t = ev.t - fx.fromT
				x, y = fx.fromX + fx.fromVx * t, fx.fromY + fx.fromVy * t
			elseif cue then
				local t = state.time - ev.t
				x, y = cue.x - cue.vx * t, cue.y - cue.vy * t
			end
		end
		if x and y then
			if ev.type == "land" then
				ops.emit(state, events, "down", 0, nil, x, y, ev.speed)
			else
				local other = if ev.type == "ballHit"
					then (if ev.ball == 0 then ev.other else ev.ball)
					else nil
				ops.emit(state, events, "turn", 0, other, x, y, ev.speed)
			end
		end
	end
end

return FireShot
