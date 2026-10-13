--!strict
-- The lobby bots' numbers the designer set (2026-10-12; src/server/Bots/LobbyBots.luau runs
-- them in Studio and live): back on by themselves, the server filled to 11 people, mostly
-- Bronze badges and none above Gold, a bot walking over 2 s after a lonely player steps onto a
-- pad and 15 s after when a free real player is near.
local H = require("./harness")
local Config = H.require("Config")
local Ranks = H.require("Progression.Ranks")
local expect = H.expect

local L = Config.Bots.Lobby
local tests = {}

tests["lobby bots on by default, filling a server to 11 people"] = function()
	expect(L.OnByDefault == true, "on in live lobbies again (2026-10-13, the live lag test)")
	expect(L.People == 11, "filled up to 11")
end

tests["badges are mostly Bronze and never above Gold"] = function()
	local weights: { [string]: number } = {}
	local total = 0
	for _, row in L.Tiers do
		expect(Ranks.tierIndex(row.name) ~= nil, "a real tier: " .. row.name)
		weights[row.name] = row.weight
		total += row.weight
	end
	expect(weights.Bronze == 60 and weights.Silver == 25 and weights.Gold == 15, "60 / 25 / 15")
	expect(total == 100, "the weights are shares")
	for name in weights do
		expect(
			(Ranks.tierIndex(name) :: number) <= (Ranks.tierIndex("Gold") :: number),
			name .. " is Gold or below"
		)
	end
end

tests["a lonely player's bot comes in 2 s, after 15 s when someone free is near"] = function()
	expect(L.ComeAfterSeconds == 2 and L.ComeAnywaySeconds == 15)
	expect(L.ComeTimeoutSeconds > L.ComeAfterSeconds, "the walk's last resort comes later")
	expect(L.NearStuds > 0 and L.KeepStuds < L.NearStuds, "")
	expect(L.LingerStuds[1] >= L.KeepStuds, "lingering never stands closer than a stroll keeps")
	expect(L.LingerLeaveStuds > L.LingerStuds[2], "it walks off only once they moved away")
	expect(L.MaxWaiting >= 1 and L.MinFreeTables >= 1, "")
end

return tests
