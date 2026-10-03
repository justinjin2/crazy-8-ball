--!strict
-- The bot duel from the command line (tests/bot_duel.luau): each tier's bot against a model
-- player of the same rank, the player's win share against the designer's target, and the shot
-- kinds the bot played. Writes tools/bot_duel_results.json.
--
-- Usage (from the repo root):
--   lune run tools/bot_duel.luau                     # every tier, 60 games each
--   lune run tools/bot_duel.luau Gold --games 200
--   lune run tools/bot_duel.luau Gold --make 0.55 --no-write    # try a Make chance
--   lune run tools/bot_duel.luau Gold --player Silver --no-write  # a weaker player

local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Duel = require("../tests/bot_duel")
local H = require("../tests/harness")

local Config = H.require("Config")

local RESULTS = "tools/bot_duel_results.json"

-- The designer's targets (2026-10-02): the player's chance of beating the bot of their rank.
local TARGET = {
	Bronze = 0.9,
	Silver = 0.8,
	Gold = 0.65,
	Platinum = 0.57,
	Diamond = 0.5,
	Expert = 0.5,
	Veteran = 0.45,
	Master = 0.4,
	Grandmaster = 0.35,
	Reyes = 0.3,
}

local tiers: { string } = {}
local games, seed, write = 60, 1, true
local overrides: any = {}
local args = process.args
local i = 1
while i <= #args do
	local a = args[i]
	if a == "--games" then
		games = tonumber(args[i + 1]) :: number
		i += 1
	elseif a == "--seed" then
		seed = tonumber(args[i + 1]) :: number
		i += 1
	elseif a == "--make" then
		overrides.make = tonumber(args[i + 1])
		write = false
		i += 1
	elseif a == "--player" then
		overrides.player = args[i + 1]
		write = false
		i += 1
	elseif a == "--aim" then
		overrides.skill = overrides.skill or { aim = 1, power = 0.1 }
		overrides.skill.aim = tonumber(args[i + 1])
		write = false
		i += 1
	elseif a == "--power" then
		overrides.skill = overrides.skill or { aim = 1, power = 0.1 }
		overrides.skill.power = tonumber(args[i + 1])
		write = false
		i += 1
	elseif a == "--no-write" then
		write = false
	else
		table.insert(tiers, a)
	end
	i += 1
end
if #tiers == 0 then
	tiers = table.clone(Config.Ranks.Tiers)
end

local results = {}
if fs.isFile(RESULTS) then
	results = serde.decode("json", fs.readFile(RESULTS))
end

for _, tier in tiers do
	local started = os.clock()
	local r = Duel.run(tier, games, seed, overrides)
	local kinds = {}
	for k, n in r.kinds do
		table.insert(kinds, ("%s %d"):format(k, n))
	end
	table.sort(kinds)
	print(
		("%-12s player wins %5.1f%% (target %2.0f%%)  pots %2.0f%%  %d/%d played  %.0f shots/game  %.1fs  [%s]"):format(
			tier,
			r.playerWins * 100,
			(TARGET[tier] or 0) * 100,
			r.playerPotRate * 100,
			r.played,
			r.games,
			r.meanShots,
			os.clock() - started,
			table.concat(kinds, ", ")
		)
	)
	if write then
		results[tier] = {
			playerWins = r.playerWins,
			target = TARGET[tier],
			games = r.games,
			played = r.played,
			make = (Config.Bots.Tiers :: any)[tier].Make,
			at = DateTime.now():toIsoDate(),
		}
	end
end

if write then
	fs.writeFile(RESULTS, serde.encode("json", results, true))
end
