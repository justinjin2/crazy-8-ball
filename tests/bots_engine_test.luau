--!strict
-- The engine's bot hooks (the Bots lane): against bots the real player always breaks
-- (`breakFor`), on the first game and every rematch, whichever side the coin picks.
local H = require("./harness")
local E = H.require("Rules.MatchEngine")
local expect = H.expect

local BOT = -1000

-- A 1v1 pad: the real player `host` first, then the bot (or the bot first).
local function pad(botFirst: boolean): any
	local m = E.new(1, 1)
	if botFirst then
		expect(E.join(m, BOT, "Bot", "Bot", 0))
		expect(E.join(m, 7, "Real", "Real", 0.1))
	else
		expect(E.join(m, 7, "Real", "Real", 0))
		expect(E.join(m, BOT, "Bot", "Bot", 0.1))
	end
	m.breakFor = 7
	return m
end

local function teamOf(m: any, id: number): number
	return (E.seat(m, id) :: any).team
end

local tests = {}

tests["the real player breaks whatever the coin, host or not"] = function()
	for _, botFirst in { false, true } do
		for coin = 1, 2 do
			local m = pad(botFirst)
			expect(
				E.action(
					m,
					m.hostId,
					{ kind = "Start", epoch = m.epoch, turnId = m.turnId },
					0,
					coin
				)
			)
			expect(m.coin.winnerTeam == teamOf(m, 7), "the coin lands for the real player")
			expect(m.coin.breaker == 7, "they break")
			expect(m.activeTeam == teamOf(m, 7))
		end
	end
end

tests["a rematch against a bot: the real player breaks again"] = function()
	local m = pad(false)
	expect(E.action(m, m.hostId, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 0, 2))
	E.advance(m, m.deadline) -- the coin
	expect(E.action(m, 7, { kind = "Surrender", epoch = m.epoch, turnId = m.turnId }, 1))
	expect(m.phase == "Result")
	for _, id in { 7, BOT } do
		expect(E.action(m, id, { kind = "Rematch", epoch = m.epoch, turnId = m.turnId }, 2))
	end
	E.advance(m, 2)
	expect(m.phase ~= "Result", "the rematch started")
	expect(m.breakFor == 7, "kept through the rematch")
	expect(m.activeTeam == teamOf(m, 7), "the real player breaks the rematch too")
end

tests["without breakFor the coin decides as before"] = function()
	local m = E.new(1, 1)
	expect(E.join(m, 1, "a", "a", 0))
	expect(E.join(m, 2, "b", "b", 0.1))
	expect(E.action(m, 1, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 0, 2))
	expect(m.coin.winnerTeam == 2)
end

return tests
