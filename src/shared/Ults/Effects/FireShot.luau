--!strict
-- Fire Shot (the designer, 2026-10-08: Super Bounce reworked; the starter ability): the cue
-- ball bursts into flames and leaves the cue at Config.Ults.FireShot.LaunchSpeedScale times
-- its stroke's speed. Its full bounce aim line (Physics/Aim.bounceTrace) and the scorch marks
-- on the cloth are the look's (src/client/FireShotFx.luau); the physics is only the launch.
--
-- The launch is Black Flash's (Effects/BlackFlash.step): the first step after the strike
-- scales the cue ball's motion along the cloth and its spin, once (state.fx.launched). A hard
-- stroke's little hop (vz) stays as it is. Pure and deterministic: multiplications only.

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
	if fx.launched then
		return
	end
	fx.launched = true
	local cue = findBall(state, 0)
	if cue == nil or cue.pocketed then
		return
	end
	local k = Config.Ults.FireShot.LaunchSpeedScale
	cue.vx, cue.vy = cue.vx * k, cue.vy * k
	cue.wx, cue.wy, cue.wz = cue.wx * k, cue.wy * k, cue.wz * k
end

return FireShot
