--!strict
-- Steps: tutorial v2's step machine as data (docs/prompts/TUTORIAL_V2_PROMPT.md 4 and 7): the
-- step order, where a rejoin resumes, how an older save's step maps onto this one, which HUD
-- items show at each step, the first-time hints and one-time moments (bits in the save's
-- Flags), and the funnels' step lists. The server keeps the step in the save (Flags.Tutorial)
-- and publishes it as the TutorialStep attribute; the client reads the same table. Pure: no
-- Instances, no clocks.
--
-- Arrow .. Abilities are the guided part (TutorialActive: the menus hide and come back one by
-- one in the chain). Soft is the soft part (every menu, the Win a Match quest, game 2); after
-- game 2 the tutorial is Done. Skipped ends it early (the first-time hints still come).

local Steps = {}

Steps.Order = {
	"Arrow", -- the arrow from their chest to an empty table's pad (any empty table counts)
	"Pad", -- alone on a pad: the bot walks over (path S), or a real player joins (path R)
	"Game1", -- the first game: rigged against the bot (path S) or fair (path R)
	"Result", -- a won game 1: the result, the first win's block, NEW RANK! (the bot leaves)
	"Rank", -- open Rank, CLAIM, close
	"Mystery", -- tap the Mystery block: its upgrade screen climbs once
	"Place", -- place the Uncommon block and open it (the reel lands the tutorial's cue)
	"Cues", -- the Cues icon: the new cue, Equip, close
	"Abilities", -- the Abilities icon: RELEASE, a spin (Magnet), close
	"Soft", -- every icon, Win a Match, the invite, Free Reward, Play Global, game 2
	"Done",
}

-- The ends: nothing more is guided (first-time hints still come).
Steps.Ends = { Done = true, Skipped = true }

-- Game 1's paths (Flags.TutorialPath): S the rigged game against the tutorial bot, R a fair
-- first game with a real person (no rigging, no hidden help; the teaching stays).
Steps.Paths = { S = true, R = true }

-- Why the tutorial ended early (Flags.TutorialWhy): the Skip button, or the fail-safe.
Steps.Reasons = { Skip = true, Error = true }

local INDEX: { [string]: number } = {}
for i, name in Steps.Order do
	INDEX[name] = i
end

--- The step's place in the order (0 for an end state or anything unknown).
function Steps.index(step: string?): number
	return if type(step) == "string" then INDEX[step] or 0 else 0
end

--- Whether `name` is a step of the order or an end state (what a save may hold).
function Steps.known(name: any): boolean
	return type(name) == "string" and (INDEX[name] ~= nil or Steps.Ends[name] == true)
end

--- Whether the tutorial is still running at `step` (any step of the order but Done).
function Steps.active(step: string?): boolean
	return type(step) == "string" and INDEX[step] ~= nil and step ~= "Done"
end

--- Whether `step` is in the guided part (Arrow .. Abilities): the menus hide, popups wait.
function Steps.guided(step: string?): boolean
	local i = Steps.index(step)
	return i > 0 and i < INDEX.Soft
end

--- Whether `step` is in the guided chain after game 1 (Result .. Abilities).
function Steps.chain(step: string?): boolean
	local i = Steps.index(step)
	return i >= INDEX.Result and i < INDEX.Soft
end

--- Whether `step` comes at or after `other` in the order (false for an end state).
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

--- Where a player picks up when they join again with `step` saved. A match cannot be saved
--- halfway, so game 1 starts over from the arrow; the result screens are gone, so the chain
--- picks up at Rank; every other step stays.
function Steps.resume(step: string): string
	if step == "Pad" or step == "Game1" then
		return "Arrow"
	elseif step == "Result" then
		return "Rank"
	end
	return step
end

--- The step a save starts at when it has none: a player who has played before (any match or
--- win) never enters the tutorial; a brand-new one starts at the arrow.
function Steps.initial(matches: number?, wins: number?): string
	if (matches or 0) > 0 or (wins or 0) > 0 then
		return "Done"
	end
	return "Arrow"
end

-- Tutorial v1's step names (docs/prompts/TUTORIAL_PROMPT.md) and the v2 step each continues
-- at. "Drop" and "RareDrop" were written by a v1 bug (not steps): both come after game 1's win.
Steps.Migrate = {
	Arrow1 = "Arrow",
	Request = "Arrow",
	Drop = "Rank",
	RareDrop = "Rank",
	Block = "Rank",
	Equip = "Cues",
	RareBlock = "Abilities",
	Spin = "Abilities",
	Code = "Abilities",
	Back = "Abilities",
	Arrow2 = "Soft",
	Queue = "Soft",
	Game2 = "Soft",
	Lobby = "Soft",
	Nudges = "Soft",
	Cancelled = "Skipped",
}

--- The step to use for a save holding `saved` (anything) with `matches` matches and `wins`
--- wins: a v2 step resumes (Steps.resume), an end stays, a v1 name maps through Steps.Migrate,
--- and anything else is repaired from the stats (Steps.initial: a player who has played is
--- done).
function Steps.load(saved: any, matches: number?, wins: number?): string
	if type(saved) ~= "string" then
		return Steps.initial(matches, wins)
	elseif Steps.Ends[saved] then
		return saved
	elseif INDEX[saved] then
		if (saved == "Pad" or saved == "Game1") and (wins or 0) > 0 then
			return "Rank" -- game 1 was won as the server stopped: its result was missed
		end
		return Steps.resume(saved)
	end
	local mapped = Steps.Migrate[saved]
	if mapped then
		if Steps.Ends[mapped] then
			return mapped
		end
		local step = Steps.resume(mapped)
		-- A v1 save still before game 1 that has played since never starts the tutorial.
		return if step == "Arrow" and ((matches or 0) > 0 or (wins or 0) > 0) then "Done" else step
	end
	return if (matches or 0) > 0 or (wins or 0) > 0 then "Done" else "Arrow"
end

---------------------------------------------------------------------------------------------
-- The HUD: the items the guided part hides and the step each comes back at
---------------------------------------------------------------------------------------------

-- Each item the tutorial hides, and the step it shows from (Soft: when every icon pops in).
-- Rank and the money pill come with the Rank step (the claim's money flies to the pill).
Steps.Reveal = (
	{
		Rank = "Rank",
		Money = "Rank",
		Inventory = "Cues", -- the Cues menu's column tile
		Abilities = "Abilities",
		Shop = "Soft",
		FreeReward = "Soft",
		Trade = "Soft",
		Challenge = "Soft", -- Daily Challenge (HubCorners)
		Offer = "Soft", -- the VIP / Starter Pack tile (HubCorners)
		PlayGlobal = "Soft", -- the spawn pill and a pad's Play Global
		WinTrack = "Soft", -- the daily win track (the Win a Match quest sits there first)
		Invite = "Soft", -- the hub's Invite corner (bottom left, by the money pill)
		Plus = "Soft", -- the hub's Roblox Plus corner beside it
	}
) :: { [string]: string }

--- Whether the HUD item `item` shows at `step` (nil: no tutorial). Anything the tutorial does
--- not hide always shows; after the guided part (Soft, Done, Skipped) everything shows.
function Steps.shows(step: string?, item: string): boolean
	local from = Steps.Reveal[item]
	if from == nil or not Steps.guided(step) then
		return true
	end
	return Steps.atLeast(step, from)
end

---------------------------------------------------------------------------------------------
-- First-time hints and one-time moments: one bit each in a Flags number. Append only: a bit's
-- place is saved, so never reorder or remove a name (retire it with a comment instead).
---------------------------------------------------------------------------------------------

-- First-time hints, for everyone (4.8): each shows the first time its moment happens, once,
-- saved (Flags.TutorialHints: done; Flags.TutorialHintsAgain: ignored once, it may come back
-- once more). The guided steps mark theirs done as they teach them.
Steps.Hints = {
	"Aim", -- a fair first game (path R): drag to aim, then pull the power bar
	"Zoom", -- a fair first game: zoom out to see the angle
	"BallInHand", -- the first ball in hand not taught in game 1
	"Eight", -- the first 8 call not taught in game 1
	"AbilityReady", -- the ability bar is full: how to use it on this device
	"RankUp", -- the first rank-up: claim it in Rank
	"Block", -- the first lucky block in the hotbar: tap it, place it, open it
	"Mystery", -- the first Mystery block: its upgrade screen
	"Cue", -- the first cue won: equip it in Cues
	"Abilities", -- the first visit to Abilities: the RELEASE code, then spin
}

-- The hints each guided step teaches: done once the step is passed the normal way (Game1's
-- only on path S, the rigged game's lessons; path R gets them as hints).
Steps.Taught = (
	{
		Game1 = { "Aim", "Zoom", "BallInHand", "Eight", "AbilityReady" },
		Rank = { "RankUp" },
		Mystery = { "Mystery" },
		Place = { "Block" },
		Cues = { "Cue" },
		Abilities = { "Abilities" },
	}
) :: { [string]: { string } }

-- The pool controls (4.2): taught in the first game whoever it is against, off for skippers.
Steps.PoolHints = (
	{ Aim = true, Zoom = true, BallInHand = true, Eight = true }
) :: { [string]: boolean }

-- One-time moments (Flags.TutorialSeen): a click-once glow, a popup shown once, the quest.
Steps.Seen = {
	"Icons", -- the soft part's icons have popped in
	"Shop", -- each icon's "!" glow until it is clicked once
	"FreeReward",
	"Challenge",
	"Offer",
	"Money",
	"Invite", -- the invite popup, shown once
	"Group", -- Free Reward's frames, highlighted once
	"Favorite",
	"Like",
	"PlayGlobal", -- Play Global's glow until it is pressed
	"Quest", -- the Win a Match quest is on
	"QuestDone", -- ... and won
	"Game2", -- game 2 was found (the soft part's last step)
	"Ready", -- the first-win Rare block's "Ready!" glow, until it is taken in hand
	"InviteAnswered", -- the invite popup's Invite or X was pressed (its InvitePopup event)
}

-- The moments a client may report itself (TutorialEvent "Seen"); the rest the server sees.
Steps.ClientSeen = (
	{
		Icons = true,
		Shop = true,
		FreeReward = true,
		Challenge = true,
		Offer = true,
		Money = true,
		Invite = true,
		Group = true,
		Favorite = true,
		Like = true,
		PlayGlobal = true,
		Ready = true,
	}
) :: { [string]: boolean }

local function indexOf(list: { string }): { [string]: number }
	local map = {}
	for i, name in list do
		map[name] = i
	end
	return map
end

local HINT = indexOf(Steps.Hints)
local SEEN = indexOf(Steps.Seen)

--- A hint's bit number (nil if unknown).
function Steps.hintBit(name: any): number?
	return if type(name) == "string" then HINT[name] else nil
end

--- A one-time moment's bit number (nil if unknown).
function Steps.seenBit(name: any): number?
	return if type(name) == "string" then SEEN[name] else nil
end

local function whole(mask: any): number
	return if type(mask) == "number" and mask == mask and mask >= 0 then math.floor(mask) else 0
end

--- Whether bit `n` (1-based) is set in `mask` (a whole number; anything else counts as 0).
function Steps.has(mask: any, n: number): boolean
	return bit32.btest(whole(mask), bit32.lshift(1, n - 1))
end

--- `mask` with bit `n` set.
function Steps.mark(mask: any, n: number): number
	return bit32.bor(whole(mask), bit32.lshift(1, n - 1))
end

---------------------------------------------------------------------------------------------
-- Funnels (src/server/Funnel.luau, docs/TUTORIAL_FUNNELS.md): each list is one funnel's steps
-- in order. Append only once live: a step's number is its place.
---------------------------------------------------------------------------------------------

-- The onboarding funnel (Roblox's own, everyone new): fields device (first step) and path.
Steps.Funnel = {
	"Joined",
	"ArrowShown",
	"OnTable",
	"Game1Started",
	"Game1Ended",
	"FirstWin",
	"RankClaimed",
	"BlockOpened",
	"CueEquipped",
	"AbilitySpun",
	"ChainDone",
	"Game2Searched",
	"Game2Started",
	"Game2Ended",
	"QuestDone",
	"ThirdMatch",
}

-- The one-time funnels, each step once per player (its own Flags mask).
Steps.Funnels = {
	PathS = { -- the rigged game 1
		"Seated",
		"BotArrived",
		"Break",
		"Aimed",
		"Zoomed",
		"AimPotted",
		"ComboShown",
		"ComboPotted",
		"AbilityUsed",
		"AbilityPotted",
		"BallInHand",
		"EightCalled",
		"Won",
	},
	PathR = { "Seated", "OpponentArrived", "Started", "Ended", "Won" }, -- a fair first game
	Game2 = { "Searched", "Found", "Started", "Ended" },
	Social = {
		"InviteShown",
		"Invited",
		"FreeRewardOpened",
		"DailyClaimed",
		"GroupClicked",
		"FavoriteClicked",
		"LikeClicked",
	},
}

local FUNNEL = indexOf(Steps.Funnel)

--- The onboarding funnel number of a step name (nil if unknown).
function Steps.funnelNumber(name: string): number?
	return FUNNEL[name]
end

--- A one-time funnel's step number (nil if the funnel or step is unknown).
function Steps.funnelStep(funnel: string, name: string): number?
	local list = Steps.Funnels[funnel]
	return if list then table.find(list, name) else nil
end

return Steps
