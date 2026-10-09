--!strict
-- PowerShare: the power bar (0..1) as a share (0..1) of the cue's speed range, and back.
-- Cue.speedForPower and Cue.stickSpeedForPower scale their range by this share; the bots
-- (ShotFinder.powerForSpeed) and Config's strike-sound bands use it too, so every place agrees.
--
-- Two shapes (Config.Cue.PowerMode):
--  * "Anchors" (designer, 2026-10-09: "30% ... feels too low"): the bar goes through named shot
--    speeds (Config.Cue.PowerAnchors, Dr. Dave's speed categories), growing by the same ratio
--    for each step of the bar between two anchors (a straight line in log speed: equal steps
--    of the bar feel like equal steps of power, Weber-Fechner).
--  * "Curve": power ^ PowerCurve, the shape from 2026-09-20 (its bottom fifth is nearly flat).
-- Pure: it takes Config.Cue as an argument and requires nothing, so Config can use it while
-- it loads.

local PowerShare = {}

export type Cue = {
	MinSpeed: number,
	MaxSpeed: number,
	PowerCurve: number,
	PowerMode: string,
	PowerAnchors: { { number } },
}

-- The centre-hit ball speed (in/s) at power `p` along the anchors.
local function anchorSpeed(anchors: { { number } }, p: number): number
	if p <= anchors[1][1] then
		return anchors[1][2]
	end
	for i = 2, #anchors do
		local a, b = anchors[i - 1], anchors[i]
		if p <= b[1] then
			local t = (p - a[1]) / (b[1] - a[1])
			return a[2] * (b[2] / a[2]) ^ t
		end
	end
	return anchors[#anchors][2]
end

--- The share (0..1) of the speed range that power `power` (0..1) gives.
function PowerShare.share(cue: Cue, power: number): number
	local p = math.clamp(power, 0, 1)
	if cue.PowerMode == "Curve" then
		return p ^ cue.PowerCurve
	end
	local speed = anchorSpeed(cue.PowerAnchors, p)
	return math.clamp((speed - cue.MinSpeed) / (cue.MaxSpeed - cue.MinSpeed), 0, 1)
end

--- The power (0..1) that gives `share` of the speed range: the inverse of share. Under the
--- anchors a share of 0 is the first anchor's power (the softest shot).
function PowerShare.power(cue: Cue, share: number): number
	local s = math.clamp(share, 0, 1)
	if cue.PowerMode == "Curve" then
		return s ^ (1 / cue.PowerCurve)
	end
	local anchors = cue.PowerAnchors
	local speed = cue.MinSpeed + s * (cue.MaxSpeed - cue.MinSpeed)
	if speed <= anchors[1][2] then
		return anchors[1][1]
	end
	for i = 2, #anchors do
		local a, b = anchors[i - 1], anchors[i]
		if speed <= b[2] then
			local t = math.log(speed / a[2]) / math.log(b[2] / a[2])
			return a[1] + t * (b[1] - a[1])
		end
	end
	return anchors[#anchors][1]
end

return PowerShare
