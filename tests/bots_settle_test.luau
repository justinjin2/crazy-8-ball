--!strict
-- How a bot match is paid and recorded (the Bots lane; the designer, 2026-10-02): PC bots pay
-- the PC rows; disguised bots pay like people with no streak and count as PC wins; tutorial
-- games and a disguised bot's forfeit count whatever the match time.
local H = require("./harness")
local Settle = H.require("Progression.Settle")
local expect = H.expect

local function match(kind: string?, extra: any?): any
	local bot = if kind then { kind = kind, tier = "Gold", division = 3 } else nil
	if bot and extra then
		for k, v in extra do
			bot[k] = v
		end
	end
	return {
		seats = {
			{ userId = 7, team = 1, connected = true },
			{ userId = -1000, team = 2, connected = true, bot = bot },
		},
	}
end

local tests = {}

tests["each bot kind pays as the designer set"] = function()
	expect(Settle.opponentKind(match("Pc")) == "PC")
	expect(Settle.opponentKind(match("Disguised")) == "Player")
	expect(Settle.opponentKind(match("Tutorial")) == "Player")
	expect(Settle.opponentKind(match(nil)) == "Player")
	expect(Settle.botKind(match(nil)) == nil)
end

tests["a disguised win is recorded as a PC win, a tutorial win as a real one"] = function()
	expect(Settle.recordAs(match("Disguised"), "Player") == "PC")
	expect(Settle.recordAs(match("Tutorial"), "Player") == "Player")
	expect(Settle.recordAs(match("Pc"), "PC") == "PC")
end

tests["no win streak against any bot"] = function()
	expect(Settle.streakCounts(match(nil)))
	for _, kind in { "Pc", "Disguised", "Tutorial" } do
		expect(not Settle.streakCounts(match(kind)), kind)
	end
end

tests["tutorial games and a vanished disguised bot count whatever the time"] = function()
	expect(Settle.botReal(match("Tutorial")))
	expect(not Settle.botReal(match("Disguised")))
	expect(Settle.botReal(match("Disguised", { vanished = true })))
	expect(not Settle.botReal(match("Pc", { vanished = true })))
	expect(not Settle.botReal(match(nil)))
end

tests["bot seats are known"] = function()
	local m = match("Disguised")
	expect(Settle.isBot(m, -1000) and not Settle.isBot(m, 7))
end

return tests
