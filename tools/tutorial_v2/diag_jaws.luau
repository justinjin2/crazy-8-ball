--!strict
-- Tutorial v2: can a ball resting in a corner pocket's throat be hit? Puts the 8 at (x, y), the
-- cue ball straight down the throat `back` inches behind it, and shoots along the throat at a
-- few angles and powers, printing what the cue ball touches first.
--   lune run tools/tutorial_v2/diag_jaws.luau <x> <y> [back]
local process = require("@lune/process")
local Sim = require("./sim")
local Ball = Sim.H.require("Physics.Ball")
local Break = Sim.H.require("Tutorial.Break")
local x, y = tonumber(process.args[1]) :: number, tonumber(process.args[2]) :: number
local back = tonumber(process.args[3]) or 10
local balls = {}
for id = 0, 15 do
	local b = Ball.new(id, 0, 0)
	b.pocketed = id ~= 0 and id ~= 8
	table.insert(balls, b)
end
local eight = Sim.find(balls, 8) :: any
eight.x, eight.y = x, y
local best, pk = math.huge, nil
for _, p in Sim.geometry.pockets do
	local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
	if d < best then
		best, pk = d, p
	end
end
local ux, uy = Break.throat(pk)
local cue = Sim.find(balls, 0) :: any
cue.x, cue.y = x - ux * (Sim.D + back), y - uy * (Sim.D + back)
print(
	("8 at %.2f %.2f, pocket %d at %.2f %.2f, cue at %.2f %.2f, half %.2f x %.2f"):format(
		x,
		y,
		pk.id,
		pk.x,
		pk.y,
		cue.x,
		cue.y,
		Sim.geometry.halfLength,
		Sim.geometry.halfWidth
	)
)
local base = math.atan2(uy, ux)
for _, deg in { -3, -1.5, 0, 1.5, 3 } do
	for _, power in { 0.2, 0.5 } do
		local outcome = Sim.play(balls, { angle = base + math.rad(deg), power = power })
		local first, rails = nil, 0
		for _, ev in outcome.events do
			if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) and first == nil then
				first = if ev.ball == 0 then ev.other else ev.ball
			elseif ev.type == "railHit" and ev.ball == 0 and first == nil then
				rails += 1
			end
		end
		local e = Sim.find(outcome.finalBalls, 8) :: any
		local c = Sim.find(outcome.finalBalls, 0) :: any
		print(
			("  %+.1f deg power %.1f: first %s, rails before %d, 8 down %s, cue down %s"):format(
				deg,
				power,
				tostring(first),
				rails,
				tostring(e.pocketed),
				tostring(c.pocketed)
			)
		)
	end
end
