--!strict
-- Prints a break's final table (every ball, its nearest pocket) and the pockets' mouths.
--   lune run tools/tutorial_v2/show_break.luau <seed> <cueX> <cueY> <angle> <power>
local process = require("@lune/process")
local Sim = require("./sim")
local a = process.args
local balls = Sim.rack(tonumber(a[1]) or 2497, tonumber(a[2]) or -25, tonumber(a[3]) or -0.125)
local outcome = Sim.play(balls, { angle = tonumber(a[4]) or -0.000117999, power = tonumber(a[5]) or 0.95 })
for _, b in outcome.finalBalls do
	if not b.pocketed then
		local _, d, p = Sim.nearPocket(b, 99)
		print(("%2d  %7.2f %7.2f   nearest pocket P%d %.1f in"):format(b.id, b.x, b.y, p, d))
	else
		print(("%2d  down"):format(b.id))
	end
end
for _, p in Sim.geometry.pockets do
	local mx, my = Sim.mouth(p)
	print(("P%d at %.1f %.1f mouth %.1f %.1f"):format(p.id, p.x, p.y, mx, my))
end
