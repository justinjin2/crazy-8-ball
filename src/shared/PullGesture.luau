--!strict
-- PullGesture: turns a drag on the power bar into a pull (0..1), and says whether letting go
-- may shoot. Guards against the fat-fingered shot on a phone (designer, 2026-10-06): a thumb
-- that lands on the bar while swiping, wobbles and lifts used to shoot at the lowest power.
--
-- Touch only (Config.Input.TouchPull); a mouse pulls exactly as before.
--  * A dead zone: the first DeadZonePx down do nothing, and letting go there cancels. Past it
--    the pull starts at the softest shot (MinPowerToShoot) and still reaches full power at the
--    same spot as before, so a soft shot is a pull just past the click-in point.
--  * Sideways is aiming: once the finger has moved LockPx, a mostly sideways drag is not a
--    pull and stays at 0 until it lifts.
--  * A press shorter than MinHoldSeconds never shoots.
-- Pure: no Instances and no Roblox types, so tests/pull_gesture_test.luau runs it in Lune.

local Config = require(script.Parent.Config)

export type Mode = "Undecided" | "Pull" | "Aside"

export type State = {
	touch: boolean,
	startedAt: number,
	mode: Mode,
	pull: number,
}

local PullGesture = {}

--- A press began on the bar at time `now` (seconds, any clock).
function PullGesture.new(touch: boolean, now: number): State
	return { touch = touch, startedAt = now, mode = if touch then "Undecided" else "Pull", pull = 0 }
end

--- The finger is `dx`, `dy` pixels from where it pressed (down is +); `travelPx` is the drag
--- for full power. Returns the pull, 0..1.
function PullGesture.move(state: State, dx: number, dy: number, travelPx: number): number
	local travel = math.max(travelPx, 1)
	if not state.touch then
		state.pull = math.clamp(dy / travel, 0, 1)
		return state.pull
	end
	local T = Config.Input.TouchPull
	if state.mode == "Undecided" and dx * dx + dy * dy >= T.LockPx * T.LockPx then
		state.mode = if math.abs(dx) > math.abs(dy) * T.SidewaysRatio then "Aside" else "Pull"
	end
	if state.mode ~= "Pull" then
		state.pull = 0
		return 0
	end
	local dead = math.min(T.DeadZonePx, travel * 0.5)
	if dy <= dead then
		state.pull = 0
		return 0
	end
	local min = Config.Input.MinPowerToShoot
	state.pull = min + (1 - min) * math.clamp((dy - dead) / (travel - dead), 0, 1)
	return state.pull
end

--- The finger lifted at time `now`: whether this gesture may shoot (the pull still has to
--- reach MinPowerToShoot, as before).
function PullGesture.mayShoot(state: State, now: number): boolean
	if not state.touch then
		return true
	end
	return state.mode == "Pull" and now - state.startedAt >= Config.Input.TouchPull.MinHoldSeconds
end

return PullGesture
