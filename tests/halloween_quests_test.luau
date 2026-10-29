--!strict
-- Halloween quests (Halloween/Quests; Config.Halloween.Quests): six boards of four, progress on
-- today's board only (with overflow inside it), Alts while a hook is off, claims, and the older
-- boards' finished quests paid by themselves once a newer board opens.

local H = require("./harness")

local ALL_ON = { king = true, pickups = true, ult = true }
local ALL_OFF = { king = false, pickups = false, ult = false }

local function load()
	return H.require("Halloween.Quests"), H.require("Config").Halloween
end

-- The key of the first quest of `kind` on board `n` (hooks on), or nil.
local function keyOf(Quests: any, n: number, kind: string, hooks: any): string?
	for _, q in Quests.board(n, hooks) do
		if q.kind == kind then
			return q.key
		end
	end
	return nil
end

return {
	["six boards of four, rewards 60/100/150/250 in slot order"] = function()
		local Quests, C = load()
		H.expect(Quests.count() == 6, "six boards")
		for n = 1, 6 do
			local board = Quests.board(n, ALL_ON)
			H.expect(board ~= nil and #board == 4, "four on board " .. n)
			for slot, q in board or {} do
				H.expect(q.reward == C.Quests.Rewards[slot], "reward by slot")
				H.expect(q.key == ("%d.%d"):format(n, slot), "key")
				H.expect(q.need >= 1, "need")
			end
		end
		H.expect(Quests.board(7, ALL_ON) == nil, "no seventh")
	end,

	["Alts stand in while a hook is off"] = function()
		local Quests = load()
		local on, off = Quests.board(2, ALL_ON), Quests.board(2, ALL_OFF)
		H.expect(on ~= nil and off ~= nil, "board 2")
		local kingOn, kingOff = (on :: any)[2], (off :: any)[2]
		H.expect(kingOn.kind == "King" and kingOn.need == 1, "the King")
		H.expect(kingOff.kind == "Matches" and kingOff.need == 4, "its Alt")
		H.expect(kingOff.key == kingOn.key, "same key")
		local pickOff = (Quests.board(1, ALL_OFF) :: any)[4]
		H.expect(pickOff.kind == "Balls" and pickOff.need == 30, "pickups -> balls x2")
		local ultOff = (Quests.board(3, ALL_OFF) :: any)[1]
		H.expect(ultOff.kind == "Matches" and ultOff.need == 5, "abilities -> matches 5")
		-- The map on but the King off (HalloweenMap.Enabled with Boss.Enabled false): only the
		-- King's quests swap.
		local mixed = Quests.board(2, { king = false, pickups = true, ult = true }) :: any
		H.expect(
			mixed[2].kind == "Matches" and mixed[1].kind == "TeamMatches",
			"only the King swaps"
		)
	end,

	["no board shows the same quest twice, whichever hooks are off"] = function()
		local Quests = load()
		for _, king in { true, false } do
			for _, pickups in { true, false } do
				for _, ult in { true, false } do
					local hooks = { king = king, pickups = pickups, ult = ult }
					for n = 1, Quests.count() do
						local seen = {}
						for _, quest in Quests.board(n, hooks) or {} do
							local id = quest.kind .. quest.need
							H.expect(seen[id] == nil, ("board %d: %s twice"):format(n, id))
							seen[id] = true
						end
					end
				end
			end
		end
	end,

	["active seconds fill a Play-minutes quest only on its own day"] = function()
		local Quests = load()
		local q = {}
		H.expect(#Quests.route(q, 3, ALL_ON, "Active", 5) == 0, "no Active quest on board 3")
		local four = keyOf(Quests, 4, "Active", ALL_ON) :: string
		local six = keyOf(Quests, 6, "Active", ALL_ON) :: string
		for _ = 1, 400 do
			Quests.route(q, 4, ALL_ON, "Active", 5) -- the server's 5 s ticks on Oct 31
		end
		H.expect(q[four] == 1800, "board 4's 30 minutes: " .. tostring(q[four]))
		H.expect(q[six] == nil, "board 6 never gets board 4's time")
		H.expect(#Quests.route(q, 5, ALL_ON, "Active", 5) == 0, "board 5 has none")
		local r = Quests.route(q, 6, ALL_ON, "Active", 5)
		H.expect(#r == 1 and r[1].key == six and q[six] == 5, "board 6 on its day")
	end,

	["a win counts only on today's board, never an older one"] = function()
		local Quests = load()
		local q = {}
		local r = Quests.route(q, 3, ALL_ON, "Wins", 1)
		local b3 = keyOf(Quests, 3, "Wins", ALL_ON) :: string
		H.expect(#r == 1 and r[1].key == b3 and not r[1].done, "board 3's Wins")
		H.expect(q[keyOf(Quests, 1, "Wins", ALL_ON) :: string] == nil, "board 1 untouched")
		H.expect(q[keyOf(Quests, 2, "Wins", ALL_ON) :: string] == nil, "board 2 untouched")
		H.expect(#Quests.route(q, 0, ALL_ON, "Wins", 1) == 0, "before the first board: none")
		H.expect(#Quests.route(q, 7, ALL_ON, "Wins", 1) == 0, "past the last: none")
	end,

	["an amount fills today's quest and the rest flows to the board's next of that kind"] = function()
		local Quests = load()
		local q = {}
		-- Board 1 with the pickups off: Balls 15 and (the pickups' Alt) Balls 30.
		local r = Quests.route(q, 1, ALL_OFF, "Balls", 20)
		local list = Quests.board(1, ALL_OFF) :: any
		local k1, k2 = list[2].key, list[4].key
		H.expect(list[2].need == 15 and list[4].need == 30, "the two Balls quests")
		H.expect(q[k1] == 15 and q[k2] == 5 and #r == 2, "15 then 5")
		Quests.route(q, 1, ALL_OFF, "Balls", 100)
		H.expect(q[k2] == 30, "capped at the need; the rest is dropped (never board 2)")
		H.expect(q[keyOf(Quests, 2, "Balls", ALL_OFF) :: string] == nil, "board 2 untouched")
		H.expect(Quests.route(q, 1, ALL_OFF, "Balls", 5)[1] == nil, "nothing left open")
		H.expect(#Quests.route(q, 1, ALL_OFF, "Balls", 0) == 0, "zero routes nothing")
	end,

	["once a newer board opens, the older boards' finished unclaimed quests are due to be paid"] = function()
		local Quests = load()
		local q = {}
		-- Board 1: a win and 15 balls finished on its day, its first quest claimed.
		Quests.route(q, 1, ALL_ON, "Wins", 1)
		Quests.route(q, 1, ALL_ON, "Balls", 15)
		Quests.route(q, 1, ALL_ON, "Matches", 2) -- 2 of 3: not finished
		local claimed = { [keyOf(Quests, 1, "Wins", ALL_ON) :: string] = true }
		H.expect(#Quests.pastDue(q, claimed, 1, ALL_ON) == 0, "board 1 is today's: nothing due")
		-- Board 2 opens; a board 2 quest finished today is not due (it is claimed by hand).
		Quests.route(q, 2, ALL_ON, "Wins", 2)
		local due = Quests.pastDue(q, claimed, 2, ALL_ON)
		H.expect(#due == 1 and due[1].key == keyOf(Quests, 1, "Balls", ALL_ON), "board 1's Balls")
		H.expect(due[1].reward == 100, "its 100 Candy")
		claimed[due[1].key] = true
		H.expect(#Quests.pastDue(q, claimed, 2, ALL_ON) == 0, "paid once")
		-- Board 3: board 2's Wins (finished, unclaimed) is due now.
		local later = Quests.pastDue(q, claimed, 3, ALL_ON)
		H.expect(#later == 1 and later[1].key == keyOf(Quests, 2, "Wins", ALL_ON), "board 2's Wins")
		H.expect(#Quests.pastDue({}, {}, 6, ALL_ON) == 0, "nothing finished, nothing due")
	end,

	["claimable, find and done"] = function()
		local Quests = load()
		local q = {}
		Quests.route(q, 1, ALL_ON, "Wins", 1)
		local list = Quests.claimable(q, {}, 1, ALL_ON)
		H.expect(#list == 1 and list[1].kind == "Wins", "one to claim")
		H.expect(#Quests.claimable(q, { [list[1].key] = true }, 1, ALL_ON) == 0, "claimed")
		H.expect(Quests.find("1.1", 1, ALL_ON) ~= nil, "found")
		H.expect(Quests.find("2.1", 1, ALL_ON) == nil, "a board not open")
		H.expect(Quests.find("x", 6, ALL_ON) == nil and Quests.find("9.9", 6, ALL_ON) == nil, "")
	end,

	["the end claims a King or Pickups quest finished while the map ran, even with it off"] = function()
		local Quests = load()
		-- Finished while the King and the pickups ran (the event as it went)...
		local q = {}
		for n = 1, 6 do
			Quests.route(q, n, ALL_ON, "King", 5)
			Quests.route(q, n, ALL_ON, "Pickups", 50)
		end
		local king, pickups
		for n = 1, 6 do
			king = king or keyOf(Quests, n, "King", ALL_ON)
			pickups = pickups or keyOf(Quests, n, "Pickups", ALL_ON)
		end
		H.expect(king ~= nil and pickups ~= nil, "the boards have both")
		local kingKey, pickupsKey = king :: string, pickups :: string
		-- Without the end's own claim, the map's switches off would lose both (the bug).
		local lost = true
		for _, quest in Quests.claimable(q, {}, 6, { king = false, pickups = false, ult = true }) do
			lost = lost and quest.key ~= kingKey and quest.key ~= pickupsKey
		end
		H.expect(lost, "claimable alone misses them")
		-- ...converted on a first join after the map lane switched its King and pickups off: the
		-- quests read as their Alts (higher needs), yet what was finished still pays.
		local mapOff = { king = false, pickups = false, ult = true }
		local keys: { [string]: boolean } = {}
		for _, quest in Quests.endClaimable(q, {}, 6, mapOff) do
			H.expect(keys[quest.key] == nil, "each quest once: " .. quest.key)
			keys[quest.key] = true
		end
		H.expect(keys[kingKey] == true, "the King quest " .. kingKey)
		H.expect(keys[pickupsKey] == true, "the Pickups quest " .. pickupsKey)
		-- A quest claimed already is not claimed again; with every hook on it is claimable as ever.
		local all = #Quests.endClaimable(q, {}, 6, mapOff)
		H.expect(
			#Quests.endClaimable(q, { [kingKey] = true }, 6, mapOff) == all - 1,
			"claimed once"
		)
		H.expect(
			#Quests.endClaimable(q, {}, 6, ALL_ON) == #Quests.claimable(q, {}, 6, ALL_ON),
			"same as claimable when on"
		)
		H.expect(#Quests.endClaimable({}, {}, 6, ALL_OFF) == 0, "nothing finished, nothing claimed")
	end,

	["find takes only a quest's own key, never another spelling of it"] = function()
		local Quests = load()
		-- A claim is recorded under the key the client sent: "01.4" or "1.04" finding quest
		-- 1.4 would let one finished quest be claimed once per spelling.
		H.expect(Quests.find("1.4", 1, ALL_ON) ~= nil, "the real key")
		for _, spelling in { "01.4", "001.4", "1.04", "01.04", "1.4 ", " 1.4", "+1.4", "1.4.0" } do
			H.expect(Quests.find(spelling, 1, ALL_ON) == nil, "refused: " .. spelling)
		end
	end,

	["each board's four go easiest first (by expected minutes)"] = function()
		local Quests = load()
		-- A rough clock: 6.3 min a match, half of them won, 5.75 balls a match, a King win in
		-- about 3 tries, 25 pickups an hour, one nice shot in 3 matches, an ability in half.
		local minutes: { [string]: number } = {
			Matches = 6.3,
			Wins = 12.6,
			Balls = 6.3 / 5.75,
			NiceShots = 18.9,
			TeamMatches = 8,
			TeamWins = 16,
			UltMatches = 12.6,
			King = 18,
			Pickups = 2.4,
			Active = 1 / 60,
		}
		for n = 1, 6 do
			local last = 0
			for _, q in Quests.board(n, ALL_ON) or {} do
				local m = minutes[q.kind] * q.need
				H.expect(m >= last * 0.6, ("board %d: %s after a much longer one"):format(n, q.key))
				last = math.max(last, m)
			end
		end
	end,
}
