--!strict
-- Steps: the tutorial's step order, what a rejoin resumes at, what the HUD shows at each step
-- and the onboarding funnel's numbers (docs/prompts/TUTORIAL_PROMPT.md). The server keeps the
-- step in the save (Flags.Tutorial) and sets the TutorialStep attribute; the client reads the
-- same table. Pure: no Instances, no clocks.
--
-- The first server (Arrow1 .. Lobby): game 1, its rewards, the Abilities lesson and game 2.
-- Nudges runs in the real server the player lands in after game 2; Done, Skipped and
-- Cancelled are the end states.

local Steps = {}

Steps.Order = {
	"Arrow1", -- the floor arrow to the reserved table, "Join a table!"
	"Request", -- on the pad: press Request opponent
	"Game1", -- the rigged match
	"Drop", -- Bronze's Case Drop (a Standard Case) through the 8-ball, opened
	"RareDrop", -- the match's Rare Case through the 8-ball (its 1 h timer runs)
	"Abilities", -- the hand on the Abilities icon
	"Spin", -- the one starter spin (Magnet)
	"Code", -- type RELEASE for 3 more spins
	"Back", -- close the spin screen
	"Arrow2", -- the arrow to a pad again
	"Queue", -- press Join Global Queue
	"Game2", -- the arena game against a disguised Bronze bot
	"Lobby", -- press Lobby (back to a public server)
	"Nudges", -- the real server: Rank, Inventory, Shop, Free Reward
	"Done",
}

-- The ends: nothing more is shown.
Steps.Ends = { Done = true, Skipped = true, Cancelled = true }

-- The real server's nudges, in order (Flags.TutorialNudge counts them done).
Steps.Nudges = { "Rank", "Inventory", "Shop", "FreeReward" }

-- Why a tutorial was cancelled (Flags.TutorialWhy).
Steps.Reasons = { Skip = true, OtherTable = true, Friend = true }

local INDEX: { [string]: number } = {}
for i, name in Steps.Order do
	INDEX[name] = i
end

--- The step's place in the order (0 for an end state or anything unknown).
function Steps.index(step: string?): number
	return if type(step) == "string" then INDEX[step] or 0 else 0
end

--- Whether `step` is a step of the order (not an end state).
function Steps.valid(step: any): boolean
	return type(step) == "string" and INDEX[step] ~= nil and step ~= "Done"
end

--- Whether the tutorial is still running (any step of the order but Done).
function Steps.active(step: string?): boolean
	return Steps.valid(step)
end

--- Whether `step` comes at or after `other` in the order.
function Steps.atLeast(step: string?, other: string): boolean
	local i = Steps.index(step)
	return i > 0 and i >= (INDEX[other] or math.huge)
end

--- The next step after `step` (Done after the last; nil for an end state).
function Steps.after(step: string): string?
	local i = INDEX[step]
	if i == nil then
		return nil
	end
	return Steps.Order[math.min(i + 1, #Steps.Order)]
end

--- Whether the step belongs to the first server, where the tutorial hides the menus and holds
--- the popups (the player attribute TutorialActive).
function Steps.firstServer(step: string?): boolean
	local i = Steps.index(step)
	return i > 0 and i < INDEX.Nudges
end

--- Where a player picks up when they join again with `step` saved. A match cannot be saved
--- halfway, so game 1 starts over (designer, 2026-10-03) and game 2 goes back to its arrow;
--- outside an arena, a finished game 2 is the real server. Arriving in an arena from the
--- global queue (Arrow2 or Queue saved in the lobby) is game 2. Anything not a step stays.
function Steps.resume(step: string, inArena: boolean): string
	if step == "Request" or step == "Game1" then
		return "Arrow1"
	elseif step == "Arrow2" or step == "Queue" then
		return if inArena then "Game2" else "Arrow2"
	elseif step == "Game2" then
		return if inArena then "Game2" else "Arrow2"
	elseif step == "Lobby" then
		return if inArena then "Lobby" else "Nudges"
	end
	return step
end

--- The step a save starts at when it has none: a player who has played before (any match)
--- has nothing to learn; a brand-new one starts at the arrow.
function Steps.initial(matches: number, wins: number): string
	if (matches or 0) > 0 or (wins or 0) > 0 then
		return "Done"
	end
	return "Arrow1"
end

-- The column and HUD items the tutorial hides in the first server; each appears when the
-- tutorial points at it (Abilities from its step) and all of them in the real server.
local ITEMS = {
	Shop = true,
	Inventory = true,
	Abilities = true,
	Rank = true,
	FreeReward = true,
	Trade = true,
}

--- Whether the HUD item `item` (Shop, Inventory, Abilities, Rank, FreeReward) shows at `step`.
--- Anything not hidden by the tutorial shows.
function Steps.shows(step: string?, item: string): boolean
	if ITEMS[item] == nil or not Steps.firstServer(step) then
		return true
	end
	if item == "Abilities" then
		return Steps.atLeast(step, "Abilities")
	end
	return false
end

--- The real server's nudge now (step Nudges), from how many of Steps.Nudges are done, whether
--- rank rewards wait, and when the newest Rare Case's timer ends (nil: none) at unix time
--- `now`. Answers the nudge's name and its place in Steps.Nudges (nil for the case ones):
--- the four in order (Rank only while something waits to be claimed), then "CaseWait" while
--- the Rare Case's timer runs and "CaseReady" once it has ended; nil when nothing is left.
function Steps.nudge(
	done: number,
	rankPending: boolean,
	rareAt: number?,
	now: number
): (string?, number?)
	for i = math.max(0, math.floor(done)) + 1, #Steps.Nudges do
		local name = Steps.Nudges[i]
		if name ~= "Rank" or rankPending then
			return name, i
		end
	end
	if rareAt then
		return if now >= rareAt then "CaseReady" else "CaseWait", nil
	end
	return nil, nil
end

-- The onboarding funnel (AnalyticsService:LogOnboardingFunnelStepEvent), in the designer's order.
Steps.Funnel = {
	"Joined",
	"SawArrow",
	"SteppedOnPad",
	"PressedRequest",
	"Game1Started",
	"Broke",
	"PottedAimShot",
	"UsedAbility",
	"CalledEight",
	"WonGame1",
	"OpenedStandardCase",
	"SawRareCase",
	"OpenedAbilities",
	"SpunAbility",
	"JoinedGlobalQueue",
	"WonGame2",
	"BackInLobby",
	"ClaimedDaily",
	"ClaimedRank",
	"OpenedRareCase",
	"PlayedThirdMatch",
	"CameBackNextDay",
}

local FUNNEL: { [string]: number } = {}
for i, name in Steps.Funnel do
	FUNNEL[name] = i
end

--- The onboarding funnel number of a step name (nil if unknown).
function Steps.funnelNumber(name: string): number?
	return FUNNEL[name]
end

--- Whether funnel step `n` is marked in `mask` (a whole number, one bit per step).
function Steps.funnelHas(mask: number?, n: number): boolean
	local m = if type(mask) == "number" and mask == mask then math.floor(mask) else 0
	return bit32.btest(m, bit32.lshift(1, n - 1))
end

--- `mask` with funnel step `n` marked.
function Steps.funnelMark(mask: number?, n: number): number
	local m = if type(mask) == "number" and mask == mask then math.floor(mask) else 0
	return bit32.bor(m, bit32.lshift(1, n - 1))
end

return Steps
