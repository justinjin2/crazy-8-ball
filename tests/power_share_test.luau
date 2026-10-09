--!strict
-- The power bar's shape (Physics/PowerShare, Config.Cue.PowerMode and PowerAnchors).

local H = require("./harness")

local function setup()
	return H.require("Config"), H.require("Physics.PowerShare"), H.require("Physics.Cue")
end

-- Run `callback` with the bar in `mode`, and always put the designer's setting back.
local function withMode(Config, mode: string, callback: () -> ())
	local saved = Config.Cue.PowerMode
	Config.Cue.PowerMode = mode
	local ok, err = pcall(callback)
	Config.Cue.PowerMode = saved
	if not ok then
		error(err)
	end
end

return {
	["the anchors run from the softest shot to the break, rising"] = function()
		local Config = setup()
		local C = Config.Cue
		local anchors = C.PowerAnchors
		H.expect(C.PowerMode == "Anchors", "the designer's trial shape")
		H.expect(anchors[1][1] == Config.Input.MinPowerToShoot, "starts at the softest shot")
		H.expect(anchors[1][2] == C.MinSpeed, "at MinSpeed")
		H.expect(
			anchors[#anchors][1] == 1 and anchors[#anchors][2] == C.MaxSpeed,
			"ends at MaxSpeed"
		)
		for i = 2, #anchors do
			H.expect(anchors[i][1] > anchors[i - 1][1], "powers rise")
			H.expect(anchors[i][2] > anchors[i - 1][2], "speeds rise")
		end
	end,

	["each shape rises with the bar and its inverse gives the bar back"] = function()
		local Config, PowerShare = setup()
		for _, mode in { "Anchors", "Curve" } do
			withMode(Config, mode, function()
				local last = -1
				for i = 4, 100 do
					local p = i / 100
					local share = PowerShare.share(Config.Cue, p)
					H.expect(share > last, mode .. " rises at " .. i)
					H.expect(share >= 0 and share <= 1, mode .. " stays a share")
					H.near(
						PowerShare.power(Config.Cue, share),
						p,
						1e-9,
						mode .. " inverse at " .. i
					)
					last = share
				end
				H.near(PowerShare.share(Config.Cue, 1), 1, 1e-12, mode .. " full")
			end)
		end
	end,

	["the bottom of the bar is alive: 10% is clearly harder than the softest shot"] = function()
		local Config, _, Cue = setup()
		local mph = 17.6
		H.expect(Cue.speedForPower(0.1) >= 1.5 * Cue.speedForPower(0.04), "10% vs 4%")
		H.expect(Cue.speedForPower(0.3) / mph >= 3, "30% is a medium shot, 3 mph or more")
		H.near(Cue.speedForPower(1), Config.Cue.MaxSpeed, 1e-9, "full is the break")
		withMode(Config, "Curve", function()
			H.expect(Cue.speedForPower(0.1) < 1.1 * Cue.speedForPower(0.04), "the old flat bottom")
		end)
	end,

	["from 60% up the anchors are never faster than the old curve (balls still roll)"] = function()
		local Config, _, Cue = setup()
		local new, old = {}, {}
		for i = 60, 100 do
			new[i] = Cue.speedForPower(i / 100)
		end
		withMode(Config, "Curve", function()
			for i = 60, 100 do
				old[i] = Cue.speedForPower(i / 100)
			end
		end)
		for i = 60, 100 do
			H.expect(new[i] <= old[i] + 1e-9, ("%d%%: %.1f against %.1f"):format(i, new[i], old[i]))
		end
	end,
}
