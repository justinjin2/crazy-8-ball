--!strict
-- Requests: the pure half of the inventory service (src/server/Items.luau). Each player's token
-- bucket, checking an ItemRequest's arguments (the client sends ids and counts only), the
-- Limited shelf's refusals, and turning PlayerData's answers into the reply reasons the client
-- words (Net "ItemRequest"). Pure: no Instances, no Roblox APIs, no clocks (the caller passes
-- `now`) and no randomness; Lune-tested (tests/requests_test.luau).
local Config = require(script.Parent.Parent.Config)
local Catalog = require(script.Parent.Catalog)
local Cases = require(script.Parent.Cases)
local Shop = require(script.Parent.Shop)

local I = Config.Items
local C = Config.Cases

export type Bucket = {
	tokens: number, -- requests left right now (a fraction while it refills)
	at: number, -- when `tokens` was last brought up to date (the caller's clock, seconds)
}

-- One checked request. Only the fields its action uses are set.
export type Request = {
	action: string,
	caseId: string?, -- BuyCase, OpenCase
	cueId: string?, -- SellCue, SellDuplicates (optional), EquipCue, BuyLimited
	count: number?, -- BuyCase, OpenCase, SellCue
	ids: { string }?, -- MarkSeen
	rarity: string?, -- ClaimIndexRow
}

local Requests = {}

--- Every action an ItemRequest may name (Net "ItemRequest").
Requests.Actions = table.freeze({
	"BuyCase",
	"OpenCase",
	"SellCue",
	"SellDuplicates",
	"EquipCue",
	"MarkSeen",
	"ClaimIndexRow",
	"BuyLimited",
})

--- Every reason a refused ItemRequest may answer, for the client's words (Strings) and the
--- protocol comment in Net. Short PascalCase words.
Requests.Reasons = table.freeze({
	"BadRequest", -- an unknown action, a wrong type, an unknown id or a count not allowed
	"TooFast", -- the player's token bucket is empty (Config.Items.RateBurst, RatePerSecond)
	"Busy", -- another request of theirs is still being answered
	"NotLoaded", -- the save (or, for BuyCase, the PolicyService answer) is not ready yet
	"Teleporting", -- the save was let go for a teleport (PlayerData.isHandedOff)
	"NotSold", -- BuyCase: that case is switched off in the shop
	"Restricted", -- BuyCase: paid random items are restricted for this player (ECONOMY 13)
	"NotEnoughMoney", -- BuyCase, BuyLimited: the reply adds `need` (and `price`)
	"NoCases", -- OpenCase: fewer unopened cases of that type than asked
	"NotReady", -- OpenCase: the rest of that case are still on their timers
	"NoFastOpen", -- OpenCase: more than one at a time needs Fast Open
	"NotOwned", -- SellCue, EquipCue: the player has none (or fewer than asked)
	"CantSell", -- SellCue: Exclusive, Unique and Classic never sell
	"Equipped", -- SellCue: the last copy of the equipped cue ("Equip another cue first")
	"Claimed", -- ClaimIndexRow: already claimed
	"Incomplete", -- ClaimIndexRow: the row is not complete
	"NoReward", -- ClaimIndexRow: Exclusive and Unique rows pay nothing
	"NotStarted", -- BuyLimited: its window has not opened
	"Ended", -- BuyLimited: its window has closed
	"SoldOut", -- BuyLimited: every numbered copy is taken
	"Owned", -- BuyLimited: one per player
	"Error", -- anything else (logged on the server): try again
})

---------------------------------------------------------------------------------------------
-- The token bucket
---------------------------------------------------------------------------------------------

--- A full bucket at `now` (Config.Items.RateBurst tokens, or `burst`).
function Requests.newBucket(now: number, burst: number?): Bucket
	return { tokens = burst or I.RateBurst, at = now }
end

--- Takes one token at `now`: true when there was one. The bucket refills at RatePerSecond up to
--- RateBurst (or the given numbers); a clock that runs backwards refills nothing.
function Requests.take(bucket: Bucket, now: number, burst: number?, perSecond: number?): boolean
	local cap = burst or I.RateBurst
	local rate = perSecond or I.RatePerSecond
	local elapsed = now - bucket.at
	if elapsed == elapsed and elapsed > 0 then
		bucket.tokens = math.min(cap, bucket.tokens + elapsed * rate)
	end
	if now == now then
		bucket.at = math.max(bucket.at, now)
	end
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

---------------------------------------------------------------------------------------------
-- Checking a request's arguments
---------------------------------------------------------------------------------------------

-- A whole number in min..max (never NaN or infinite).
local function wholeIn(x: any, min: number, max: number): boolean
	return type(x) == "number" and x == x and x >= min and x <= max and x == math.floor(x)
end

-- A catalog cue id.
local function cueId(x: any): string?
	return if Catalog.exists(x) then x :: string else nil
end

-- A gapless array of 0..max catalog cue ids, or nil. Stops counting past `max`, so a huge
-- table from a client costs little.
local function cueIds(list: any, max: number): { string }?
	if type(list) ~= "table" then
		return nil
	end
	local n = 0
	for key in list do
		if not wholeIn(key, 1, max) then
			return nil
		end
		n += 1
		if n > max then
			return nil
		end
	end
	local ids = {}
	for i = 1, n do
		local id = cueId(list[i])
		if id == nil then
			return nil -- a gap, a non-string or an unknown id
		end
		table.insert(ids, id)
	end
	return ids
end

-- The Index's rows a claim may name: the rarities, then the two groups outside the ladder
-- (PlayerData answers NoReward for those).
local INDEX_ROWS: { [string]: boolean } = { Exclusive = true, Unique = true }
for _, rarity in C.Rarities do
	INDEX_ROWS[rarity] = true
end

-- A count argument: nil means 1.
local function countOf(x: any): any
	return if x == nil then 1 else x
end

--- Checks an ItemRequest's arguments (anything a client sent: any type at all) and answers the
--- request, or (nil, reason). Only shapes and ids are checked here; the player's state (money,
--- ownership, Fast Open, the policy, the save) is the server's to check. Counts: BuyCase 1 or
--- Config.Cases.BulkCount, OpenCase 1 or Config.Cases.FastOpenCount, SellCue 1 up to
--- Config.Save.ItemCountCap (a missing count is 1). BuyCase refuses a switched-off case
--- ("NotSold"); OpenCase takes any known case (a switched-off one can still be given and
--- opened). BuyLimited names a money-priced Limited shelf row (a Robux one is StoreRequest's).
function Requests.parse(action: any, a: any, b: any): (Request?, string?)
	if action == "BuyCase" then
		local case = Cases.get(a)
		local count = countOf(b)
		if case == nil or not Cases.isBuyCount(count) then
			return nil, "BadRequest"
		elseif not case.Enabled then
			return nil, "NotSold"
		end
		return { action = action :: string, caseId = case.Id, count = count }, nil
	elseif action == "OpenCase" then
		local case = Cases.get(a)
		local count = countOf(b)
		if case == nil or not (count == 1 or count == C.FastOpenCount) then
			return nil, "BadRequest"
		end
		return { action = action :: string, caseId = case.Id, count = count }, nil
	elseif action == "SellCue" then
		local id = cueId(a)
		local count = countOf(b)
		if id == nil or not wholeIn(count, 1, Config.Save.ItemCountCap) then
			return nil, "BadRequest"
		end
		return { action = action :: string, cueId = id, count = count }, nil
	elseif action == "SellDuplicates" then
		if a == nil then
			return { action = action :: string }, nil
		end
		local id = cueId(a)
		if id == nil then
			return nil, "BadRequest"
		end
		return { action = action :: string, cueId = id }, nil
	elseif action == "EquipCue" then
		local id = cueId(a)
		if id == nil then
			return nil, "BadRequest"
		end
		return { action = action :: string, cueId = id }, nil
	elseif action == "MarkSeen" then
		local ids = cueIds(a, I.MarkSeenMax)
		if ids == nil then
			return nil, "BadRequest"
		end
		return { action = action :: string, ids = ids }, nil
	elseif action == "ClaimIndexRow" then
		if type(a) ~= "string" or not INDEX_ROWS[a] then
			return nil, "BadRequest"
		end
		return { action = action :: string, rarity = a }, nil
	elseif action == "BuyLimited" then
		local id = cueId(a)
		local row = if id then Shop.limitedFor(id) else nil
		if id == nil or row == nil or type(row.Price) ~= "number" then
			return nil, "BadRequest"
		end
		return { action = action :: string, cueId = id }, nil
	end
	return nil, "BadRequest"
end

---------------------------------------------------------------------------------------------
-- The Limited shelf and PlayerData's answers
---------------------------------------------------------------------------------------------

--- Why a Limited row cannot be bought at `now` ("NotStarted", "Ended", "SoldOut", "Owned"), or
--- nil when it can; and the row's end time (unix seconds) either way. `sold` is the last known
--- copy count (the atomic counter still refuses past the cap); `owned`, whether this player has
--- one (one per player).
function Requests.limitedCheck(
	row: Shop.LimitedRow,
	now: number,
	sold: number?,
	owned: boolean
): (string?, number)
	local state = Shop.limitedState(row, now, sold, owned)
	if now < state.startsAt then
		return "NotStarted", state.endsAt
	elseif now >= state.endsAt then
		return "Ended", state.endsAt
	elseif state.soldOut then
		return "SoldOut", state.endsAt
	elseif state.owned then
		return "Owned", state.endsAt
	end
	return nil, state.endsAt
end

-- PlayerData's reason words -> the reply's.
local FROM_SAVE: { [string]: string } = {
	NotLoaded = "NotLoaded",
	NotEnough = "NoCases", -- openCases: fewer cases than cues
	NotReady = "NotReady", -- openCases: the rest are on their timers
	Invalid = "Error", -- logged by PlayerData: a bad argument that got past the checks here
	Unknown = "BadRequest",
	BadCount = "BadRequest",
	NotSellable = "CantSell",
	Default = "CantSell", -- Classic
	NotOwned = "NotOwned",
	TooMany = "NotOwned", -- selling more copies than owned
	Equipped = "Equipped",
	Claimed = "Claimed",
	Incomplete = "Incomplete",
	NoReward = "NoReward",
}

--- The reply reason for a PlayerData refusal (openCases, sellCue, claimIndexRow): "Error" for
--- anything it does not know.
function Requests.reasonFrom(saveReason: any): string
	return if type(saveReason) == "string" then FROM_SAVE[saveReason] or "Error" else "Error"
end

return Requests
