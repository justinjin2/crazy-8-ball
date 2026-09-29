--!strict
-- Prints the ult bar numbers and the catalog from src/shared/Config.luau as JSON, so
-- tools/ult_model.py models the same numbers the game uses. Loads Config through the test
-- harness (no Roblox needed).
-- Usage (from the repo root): lune run tools/export_ult_config.luau

local serde = require("@lune/serde")
local H = require("../tests/harness")

local Ults = H.require("Config").Ults

-- Each ult's rarity, whether it is built, and its measured worth per use (balls).
local catalog = {}
for _, id in Ults.Order do
	local row = Ults.Catalog[id]
	catalog[id] = { Rarity = row.Rarity, Built = row.Built, Worth = row.Worth }
end

print(serde.encode("json", {
	Fill = Ults.Fill,
	BarMax = Ults.BarMax,
	MaxPerMatch = Ults.MaxPerMatch,
	Order = Ults.Order,
	Rarities = Ults.Rarities,
	Catalog = catalog,
}, false))
