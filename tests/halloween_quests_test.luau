--!strict
-- Halloween quests (Halloween/Quests; Config.Halloween.Quests): six boards of four, routed
-- oldest unfinished first with overflow, Alts while a hook is off, claims.

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

	["active seconds fill the Play-minutes quests only once their boards open, oldest first"] = function()
		local Quests = load()
		local q = {}
		H.expect(#Quests.route(q, 3, ALL_ON, "Active", 5) == 0, "no Active quest on boards 1-3")
		local four = keyOf(Quests, 4, "Active", ALL_ON)
		local six = keyOf(Quests, 6, "Active", ALL_ON)
		for _ = 1, 360 do
			Quests.route(q, 6, ALL_ON, "Active", 5) -- the server's 5 s ticks
		end
		H.expect(q[four] == 1800, "board 4's 30 minutes: " .. tostring(q[four]))
		H.expect(q[six] == nil or q[six] == 0, "board 6 waits")
		local r = Quests.route(q, 6, ALL_ON, "Active", 5)
		H.expect(#r == 1 and r[1].key == six and q[six] == 5, "then board 6")
	end,

	["one win counts once, on the oldest open board with that quest unfinished"] = function()
		local Quests = load()
		local q = {}
		local r = Quests.route(q, 3, ALL_ON, "Wins", 1)
		H.expect(#r == 1 and r[1].key == keyOf(Quests, 1, "Wins", ALL_ON) and r[1].done, "board 1")
		r = Quests.route(q, 3, ALL_ON, "Wins", 1)
		local b2 = keyOf(Quests, 2, "Wins", ALL_ON) :: string
		H.expect(#r == 1 and r[1].key == b2 and not r[1].done, "then board 2")
		H.expect(q[b2] == 1, "1 of 2")
	end,

	["an amount fills the oldest quest and the rest flows on"] = function()
		local Quests = load()
		local q = {}
		-- Board 1 needs 15 balls, board 2 30: 20 balls fill board 1 and put 5 on board 2.
		local r = Quests.route(q, 2, ALL_ON, "Balls", 20)
		local k1 = keyOf(Quests, 1, "Balls", ALL_ON) :: string
		local k2 = keyOf(Quests, 2, "Balls", ALL_ON) :: string
		H.expect(q[k1] == 15 and q[k2] == 5 and #r == 2, "15 then 5")
		-- Only open boards: board 3 is not open, so the rest is dropped.
		Quests.route(q, 2, ALL_ON, "Balls", 100)
		H.expect(q[k2] == 30, "capped at the need")
		H.expect(Quests.route(q, 2, ALL_ON, "Balls", 5)[1] == nil, "nothing left open")
		H.expect(#Quests.route(q, 2, ALL_ON, "Balls", 0) == 0, "zero routes nothing")
	end,

	["a hard quest never blocks later boards' other quests"] = function()
		local Quests = load()
		local q = {}
		-- The King on board 2 unfinished; a win still lands on board 2's and board 3's Wins.
		Quests.route(q, 3, ALL_ON, "Wins", 1)
		Quests.route(q, 3, ALL_ON, "Wins", 2)
		H.expect(q[keyOf(Quests, 2, "Wins", ALL_ON) :: string] == 2, "board 2 wins done")
		Quests.route(q, 3, ALL_ON, "Wins", 1)
		H.expect(q[keyOf(Quests, 3, "Wins", ALL_ON) :: string] == 1, "board 3 next")
		H.expect(q[keyOf(Quests, 2, "King", ALL_ON) :: string] == nil, "the King still open")
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
		for _ = 1, 50 do
			Quests.route(q, 6, ALL_ON, "King", 1)
			Quests.route(q, 6, ALL_ON, "Pickups", 1)
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
		-- about 3 tries, 54 pickups an hour (a match player who walks about while waiting: the
		-- 2026-10-29 target), one nice shot in 3 matches, an ability in half.
		local minutes: { [string]: number } = {
			Matches = 6.3,
			Wins = 12.6,
			Balls = 6.3 / 5.75,
			NiceShots = 18.9,
			TeamMatches = 8,
			TeamWins = 16,
			UltMatches = 12.6,
			King = 18,
			Pickups = 60 / 54,
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
