--!strict
-- The Sky Lucky Block's clock (Progression/SkyBlock; economy v6, designer 2026-10-10): it needs a
-- finished match today, earns one every EverySeconds of active play, at most PerDay a day, and
-- stops while an earned one waits to fall.

local H = require("./harness")

local function load()
	return H.require("Progression.SkyBlock"), H.require("Config")
end

local function fresh(): (any, any)
	return { SkySeconds = 0, SkyGiven = 0, Matches = 0 }, {}
end

return {
	["the plan's numbers"] = function()
		local _, Config = load()
		local C = Config.SkyBlock
		H.expect(C.EverySeconds == 1800 and C.PerDay == 1 and C.NeedsMatch == true, "")
		H.expect(C.Kind == "Sky" and C.IdleSeconds == 120, "")
	end,

	["the clock waits for today's first finished match"] = function()
		local SkyBlock, Config = load()
		local daily, flags = fresh()
		H.expect(not SkyBlock.running(daily, flags), "no match yet")
		H.expect(not SkyBlock.add(daily, flags, 99999) and daily.SkySeconds == 0, "nothing counted")
		local view = SkyBlock.view(daily, flags)
		H.expect(view.needsMatch and view.left == Config.SkyBlock.EverySeconds, "the banner")
		daily.Matches = 1
		H.expect(SkyBlock.running(daily, flags), "runs after a match")
		H.expect(not SkyBlock.view(daily, flags).needsMatch, "the banner counts down")
	end,

	["one is earned at EverySeconds, then the clock stops while it waits"] = function()
		local SkyBlock, Config = load()
		local every = Config.SkyBlock.EverySeconds
		local daily, flags = fresh()
		daily.Matches = 1
		H.expect(not SkyBlock.add(daily, flags, every - 5), "not yet")
		H.expect(SkyBlock.view(daily, flags).left == 5, "5 seconds left")
		H.expect(not SkyBlock.add(daily, flags, 0 / 0) and not SkyBlock.add(daily, flags, -5), "")
		H.expect(SkyBlock.add(daily, flags, 5), "earned")
		H.expect(flags[SkyBlock.PendingFlag] == true and daily.SkyGiven == 1, "pending")
		H.expect(daily.SkySeconds == 0, "the clock starts over")
		local view = SkyBlock.view(daily, flags)
		H.expect(view.pending and view.today == 1 and view.left == 0, "waiting to fall")
		H.expect(not SkyBlock.running(daily, flags), "stopped while pending")
	end,

	["at most PerDay a day"] = function()
		local SkyBlock, Config = load()
		local C = Config.SkyBlock
		local daily, flags = fresh()
		daily.Matches = 3
		for _ = 1, C.PerDay do
			H.expect(SkyBlock.add(daily, flags, C.EverySeconds), "earned")
			flags[SkyBlock.PendingFlag] = nil -- picked up
		end
		H.expect(daily.SkyGiven == C.PerDay, "today's all")
		H.expect(not SkyBlock.running(daily, flags), "done for today")
		H.expect(not SkyBlock.add(daily, flags, C.EverySeconds), "no more")
		local view = SkyBlock.view(daily, flags)
		H.expect(view.left == 0 and not view.needsMatch and not view.pending, "nothing shows")
	end,
}
