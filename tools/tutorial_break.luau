--!strict
-- Finds the tutorial's rigged rack and break (docs/prompts/TUTORIAL_PROMPT.md step 4; the
-- designer, 2026-10-03): a rack seed and a break shot, played in our own physics, that pot
-- exactly 3 solids (no stripe, no 8, no scratch) and leave a 4th solid with an easy straight
-- shot into a corner pocket from where the cue ball stops, the 8 close to a pocket. The result
-- goes into Config.Tutorial.Break by hand; tests/tutorial_break_test.luau checks it still holds.
--
-- Usage (from the repo root):
--   lune run tools/tutorial_break.luau                 # seeds 1..400
--   lune run tools/tutorial_break.luau --seeds 2000 --from 1

local process = require("@lune/process")

local H = require("../tests/harness")
local Config = H.require("Config")
local Rack = H.require("Physics.Rack")
local TableGeometry = H.require("Physics.Table")
local Simulation = H.require("Physics.Simulation")
local Judge = H.require("Rules.ShotJudge")
local Plan = H.require("Tutorial.Break")

local seeds, from = 400, 1
local args = process.args
local i = 1
while i <= #args do
	if args[i] == "--seeds" then
		seeds = tonumber(args[i + 1]) :: number
		i += 1
	elseif args[i] == "--from" then
		from = tonumber(args[i + 1]) :: number
		i += 1
	end
	i += 1
end

local geometry = TableGeometry.build({ pocketsOpen = true })
local hx, hy = TableGeometry.headSpot(geometry)
local fx, fy = TableGeometry.footSpot(geometry)
local straight = math.atan2(fy - hy, fx - hx)

-- The break tries for each seed: the cue ball along the head string, aimed at the apex with
-- small turns either side, full power, no spin.
local OFFSETS = { 0, -3, 3, -6, 6 }
local TURNS = { 0, -0.004, 0.004, -0.008, 0.008 }

local best: any = nil
local clock = os.clock()
local tried = 0
local threes = 0
for seed = from, from + seeds - 1 do
	for _, dy in OFFSETS do
		for _, turn in TURNS do
			local shot = {
				seed = seed,
				cueX = hx,
				cueY = hy + dy,
				angle = math.atan2(fy - (hy + dy), fx - hx) + turn,
				power = 1,
			}
			tried += 1
			local result = Plan.play(geometry, shot)
			local solids = 0
			for _, id in result.pocketed do
				if id < 8 then
					solids += 1
				end
			end
			if
				solids == Config.Tutorial.Break.Solids
				and #result.pocketed == solids
				and not result.scratch
			then
				threes += 1
			end
			local score = Plan.score(geometry, result)
			if score and (best == nil or score.total > best.score.total) then
				best = { shot = shot, score = score }
				print(
					("seed %d dy %+.1f turn %+.3f: score %.2f (aim cut %.1f deg, %.0f in, 8 %.0f in from a pocket)"):format(
						seed,
						dy,
						turn,
						score.total,
						score.cutDegrees,
						score.distance,
						score.eightGap
					)
				)
			end
		end
	end
end
print(
	("%d breaks in %.1f s, %d potted exactly the solids wanted"):format(
		tried,
		os.clock() - clock,
		threes
	)
)
if best then
	local s = best.shot
	print("Best (paste into Config.Tutorial.Break):")
	print(
		("Seed = %d, CueX = %.4f, CueY = %.4f, Angle = %.6f, Power = 1"):format(
			s.seed,
			s.cueX,
			s.cueY,
			s.angle
		)
	)
	print(("aim lesson: ball %d into pocket %d"):format(best.score.ball, best.score.pocket))
else
	print("none found")
end
local _ = { Config, Rack, Simulation, Judge, straight }
