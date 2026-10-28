--!strict
-- Prints the badge registry (Config.Badges.List) with each badge's text (Strings.Badges) and
-- icon path as JSON, in registry order, so tools/roblox_badges.py creates exactly what the game
-- awards. Loads Config and Strings through the test harness (no Roblox needed).
-- Usage (from the repo root): lune run tools/export_badges.luau

local serde = require("@lune/serde")
local H = require("../tests/harness")

local Config = H.require("Config")
local Strings = H.require("Strings")

local rows = {}
for _, row in Config.Badges.List do
	local text = Strings.Badges[row.Key] or {}
	table.insert(rows, {
		key = row.Key,
		name = text.Name,
		description = text.Description,
		badgeId = row.BadgeId,
		hasRule = row.Rule ~= nil,
		icon = "assets/ui/badges/" .. row.Key .. ".png",
	})
end

print(serde.encode("json", { universeId = Config.Badges.UniverseId, rows = rows }, false))
