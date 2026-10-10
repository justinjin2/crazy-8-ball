--!strict
-- The ball streak's on-screen maths (StreakHud; Config.UI.Streak): each level's look, the step
-- up's punch, the idle beat and the fire's flare, as plain functions of time so they are tested
-- in Lune. No Instances.
local StreakMath = {}

--- The level whose look a streak of `level` wears: x1..x8, and x8's past it (Solo).
function StreakMath.look(level: number, levels: number): number
	return math.clamp(math.floor(level), 1, levels)
end

--- How much bigger than x1 a level's words are.
function StreakMath.size(level: number, levels: number, grow: number): number
	return 1 + grow * (StreakMath.look(level, levels) - 1)
end

-- Roblox's Back easing out with overshoot `s` (TweenService's curve, s = 1.70158 by default).
function StreakMath.backOut(p: number, s: number?): number
	local k = s or 1.70158
	local x = math.clamp(p, 0, 1) - 1
	return x * x * ((k + 1) * x + k) + 1
end

local function quadOut(p: number): number
	local x = 1 - math.clamp(p, 0, 1)
	return 1 - x * x
end

export type Punch = {
	scale: number, -- the words' scale on top of their size
	white: boolean, -- the impact frames: pure white letters
	frozen: boolean, -- the idle motion holds still (the squash and the impact)
	numberScale: number, -- the number's own slam
	numberTilt: number, -- degrees
}

--- The step up, `t` seconds after its ball dropped (Config.UI.Streak.Step): a squash, two
--- white impact frames, then a punch out settling back while the number slams in tilted.
function StreakMath.punch(t: number, step: any): Punch
	local squash, impact = step.SquashSeconds, step.ImpactSeconds
	if t < squash then
		return {
			scale = 1 - (1 - step.SquashScale) * (t / squash),
			white = false,
			frozen = true,
			numberScale = 1,
			numberTilt = 0,
		}
	elseif t < squash + impact then
		return {
			scale = step.ImpactScale,
			white = true,
			frozen = true,
			numberScale = 1,
			numberTilt = 0,
		}
	end
	local p = (t - squash - impact) / step.SettleSeconds
	if p >= 1 then
		return { scale = 1, white = false, frozen = false, numberScale = 1, numberTilt = 0 }
	end
	local settle = StreakMath.backOut(p, step.SettleOvershoot)
	return {
		scale = step.PunchScale - (step.PunchScale - 1) * settle,
		white = false,
		frozen = false,
		numberScale = 1 + step.NumberSlam * (1 - quadOut(p * 1.6)),
		numberTilt = step.NumberTilt * (1 - quadOut(p * 1.4)),
	}
end

--- x1's entrance: a pop from InFromScale, `t` seconds in.
function StreakMath.popIn(t: number, step: any): number
	return step.InFromScale + (1 - step.InFromScale) * StreakMath.backOut(t / step.InSeconds, 2.6)
end

--- The idle beat: a quick pop every `seconds`, `extra` big, easing away (0 between beats).
function StreakMath.beat(clock: number, seconds: number, extra: number): number
	if seconds <= 0 or extra == 0 then
		return 0
	end
	local p = (clock % seconds) / seconds
	if p < 0.1 then
		return extra * p / 0.1
	end
	return extra * math.exp(-(p - 0.1) * 9)
end

--- The fire's height factor `t` seconds after a step: it grows in from nothing over
--- IgniteSeconds when it lights (x3), else it flares 1 + FlareScale and eases back.
function StreakMath.flare(t: number, ignite: boolean, fire: any, squash: number): number
	if ignite then
		return StreakMath.backOut(math.clamp((t - squash) / fire.IgniteSeconds, 0, 1), 2)
	end
	if t < squash then
		return 1
	end
	return 1 + fire.FlareScale * math.exp(-t * fire.FlareDecay)
end

--- The slide under YOU ARE SOLIDS / STRIPES and back: an ease in and out of `p` (0 to 1).
function StreakMath.slide(p: number): number
	local x = math.clamp(p, 0, 1)
	return x * x * (3 - 2 * x)
end

--- The end's fade, `t` seconds in: (opacity 1 to 0, how far down the letters have dropped 0 to 1).
function StreakMath.fade(t: number, seconds: number): (number, number)
	local p = math.clamp(t / seconds, 0, 1)
	return 1 - p, quadOut(p)
end

return StreakMath
