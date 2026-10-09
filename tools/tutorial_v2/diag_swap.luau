--!strict
-- How much one renumbering changes a break (tutorial v2, the combination search): for the first
-- N usable breaks of a collect file, the standard rack replayed, then each single swap of a solid
-- and a stripe; how often the same balls drop.
--   lune run tools/tutorial_v2/diag_swap.luau <collect.jsonl> [N]
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("./sim")
local Config = Sim.Config
local Rack = Sim.H.require("Physics.Rack")

local rows = {}
for line in (fs.readFile(process.args[1]) :: string):gmatch("[^\n]+") do
	table.insert(rows, serde.decode("json", line))
end
local n = tonumber(process.args[2]) or 20
local function downOf(layout: any, row: any): string
	local balls = Rack.newGame(Sim.geometry, row.seed, layout)
	local cue = Sim.find(balls, 0) :: any
	cue.x, cue.y = row.cx, row.cy
	local outcome = Sim.play(balls, { angle = row.angle, power = row.power })
	local down = Sim.down(outcome)
	-- by rack spot: the standard id that spot held
	return table.concat(down, ",")
end
local STANDARD = Config.Rack.Layout
local same, total, identical = 0, 0, 0
for r = 1, math.min(n, #rows) do
	local row = rows[r]
	local base = downOf(STANDARD, row)
	local want = table.concat(row.down, ",")
	if base == want then
		identical += 1
	end
	-- single swaps 7<->9, 6<->10 ... (a solid with a stripe), read back by spot
	for _, sw in { { 7, 9 }, { 1, 15 }, { 4, 12 } } do
		local layout = {}
		for i, rowIds in STANDARD do
			layout[i] = {}
			for k, id in rowIds do
				layout[i][k] = if id == sw[1] then sw[2] elseif id == sw[2] then sw[1] else id
			end
		end
		local d = downOf(layout, row)
		-- map back to standard ids
		local back = {}
		for id in d:gmatch("%d+") do
			local v = tonumber(id) :: number
			table.insert(back, if v == sw[1] then sw[2] elseif v == sw[2] then sw[1] else v)
		end
		table.sort(back)
		local wantSorted = table.clone(row.down)
		table.sort(wantSorted)
		total += 1
		if table.concat(back, ",") == table.concat(wantSorted, ",") then
			same += 1
		end
	end
end
print(("standard replay identical %d/%d; single swaps keep the same drops %d/%d"):format(identical, math.min(n, #rows), same, total))
