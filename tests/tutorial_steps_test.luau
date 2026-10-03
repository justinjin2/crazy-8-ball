--!strict
-- Steps (Tutorial/Steps): the tutorial's step order, resume rules, what the HUD shows, and the
-- onboarding funnel's numbers and once-only bits (docs/prompts/TUTORIAL_PROMPT.md).

local H = require("./harness")

local function load()
	return H.require("Tutorial.Steps")
end

return {
	["a new save starts at the arrow, a player who has played is done"] = function()
		local Steps = load()
		H.expect(Steps.initial(0, 0) == "Arrow1", "brand new")
		H.expect(Steps.initial(1, 0) == "Done", "a match played")
		H.expect(Steps.initial(0, 1) == "Done", "a win")
	end,

	["the order moves on one step at a time and ends at Done"] = function()
		local Steps = load()
		H.expect(Steps.after("Arrow1") == "Request" and Steps.after("Game1") == "Drop", "")
		H.expect(Steps.after("Nudges") == "Done" and Steps.after("Done") == "Done", "the end")
		H.expect(Steps.after("Skipped") == nil, "an end state has no next")
		H.expect(Steps.atLeast("Spin", "Abilities") and not Steps.atLeast("Drop", "Abilities"), "")
		H.expect(not Steps.atLeast("Skipped", "Arrow1"), "an end state is not a step")
	end,

	["a rejoin restarts game 1 and game 2, and finishes in the real server"] = function()
		local Steps = load()
		H.expect(Steps.resume("Game1", false) == "Arrow1", "game 1 again from the start")
		H.expect(Steps.resume("Request", false) == "Arrow1", "on the pad")
		H.expect(Steps.resume("Spin", false) == "Spin", "a later step stays")
		H.expect(Steps.resume("Drop", false) == "Drop", "the Bronze case resumes")
		H.expect(Steps.resume("Queue", false) == "Arrow2", "the queue")
		H.expect(Steps.resume("Queue", true) == "Game2", "arrived in the arena from the queue")
		H.expect(Steps.resume("Arrow2", true) == "Game2", "a teleport before the pad was noted")
		H.expect(Steps.resume("Game2", false) == "Arrow2", "game 2 in a lobby")
		H.expect(Steps.resume("Game2", true) == "Game2", "game 2 in its arena")
		H.expect(Steps.resume("Lobby", false) == "Nudges", "back from the arena")
		H.expect(Steps.resume("Lobby", true) == "Lobby", "still in the arena")
	end,

	["the first server hides the menus; Abilities appears at its step"] = function()
		local Steps = load()
		H.expect(Steps.firstServer("Arrow1") and Steps.firstServer("Lobby"), "first server")
		H.expect(not Steps.firstServer("Nudges") and not Steps.firstServer("Done"), "real server")
		H.expect(not Steps.firstServer("Skipped") and not Steps.firstServer(nil), "none")
		for _, item in { "Shop", "Inventory", "Rank", "FreeReward" } do
			H.expect(not Steps.shows("Game1", item) and not Steps.shows("Arrow2", item), item)
			H.expect(Steps.shows("Nudges", item) and Steps.shows("Skipped", item), item .. " back")
		end
		H.expect(not Steps.shows("Drop", "Abilities") and Steps.shows("Abilities", "Abilities"), "")
		H.expect(Steps.shows("Game1", "Money"), "anything else always shows")
	end,

	["every funnel step has a number and is marked once"] = function()
		local Steps = load()
		H.expect(#Steps.Funnel == 22, "the designer's 22 steps")
		H.expect(
			Steps.funnelNumber("Joined") == 1 and Steps.funnelNumber("CameBackNextDay") == 22,
			""
		)
		local mask = 0
		H.expect(not Steps.funnelHas(mask, 7), "not yet")
		mask = Steps.funnelMark(mask, 7)
		mask = Steps.funnelMark(mask, 22)
		H.expect(Steps.funnelHas(mask, 7) and Steps.funnelHas(mask, 22), "marked")
		H.expect(not Steps.funnelHas(mask, 8) and not Steps.funnelHas(nil, 1), "others not")
		H.expect(Steps.funnelMark(mask, 7) == mask, "marking twice changes nothing")
	end,
}
