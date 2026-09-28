--!strict
-- Prints the ult bar numbers from src/shared/Config.luau as JSON, so tools/ult_model.py models
-- the same numbers the game uses. Loads Config through the test harness (no Roblox needed).
-- Usage (from the repo root): lune run tools/export_ult_config.luau

local serde = require("@lune/serde")
local H = require("../tests/harness")

local Ults = H.require("Config").Ults
print(serde.encode("json", {
	Fill = Ults.Fill,
	BarMax = Ults.BarMax,
	MaxPerMatch = Ults.MaxPerMatch,
}, false))
