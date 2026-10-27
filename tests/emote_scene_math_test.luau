--!strict
-- EmoteSceneMath: our own emotes' scene maths (designer, 2026-10-26): Bullseye's target comes
-- closer or smaller when there is no room and never stands over a table, about half of each
-- handful misses, and a thrown kernel lands where
-- it was aimed.

local H = require("./harness")

local function load()
	return H.require("EmoteSceneMath"), H.require("Config")
end

local function near(x: number, y: number, eps: number?): boolean
	return math.abs(x - y) < (eps or 1e-6)
end

-- A table 19 x 11 studs (the barrier's half extents 9.48 x 5.48), centred at (cx, cz).
local function table_(cx: number, cz: number): any
	return { x = cx, z = cz, cos = 1, sin = 0, hx = 9.48, hz = 5.48 }
end

-- The target's spec from Config, the dancer at the origin facing -Z.
local function spec(Config: any, wall: number, boxes: { any }): any
	local B = Config.EmoteMenu.Custom.Bullseye
	return {
		ox = 0,
		oz = 0,
		dx = 0,
		dz = -1,
		wall = wall,
		boxes = boxes,
		near = B.Near,
		far = B.Far,
		tight = B.Tight,
		back = B.Back,
		half = B.Half,
		margin = B.TableMargin,
		minScale = B.MinScale,
		steps = B.Steps,
	}
end

return {
	["a ray enters a box where it should, from outside, inside and alongside"] = function()
		local M = load()
		local box = { x = 0, z = -10, cos = 1, sin = 0, hx = 2, hz = 3 }
		H.expect(near(M.boxEnter(0, 0, 0, -1, box, 0), 7), "straight in: 7 studs")
		H.expect(near(M.boxEnter(0, 0, 0, -1, box, 1), 6), "grown by 1: 6")
		H.expect(M.boxEnter(0, 0, 0, 1, box, 0) == math.huge, "facing away")
		H.expect(M.boxEnter(5, 0, 0, -1, box, 0) == math.huge, "alongside, outside")
		H.expect(M.boxEnter(0, -10, 1, 0, box, 0) == 0, "from inside")
		-- A box turned a quarter: its length now runs along world Z.
		local turned = { x = 0, z = -10, cos = 0, sin = 1, hx = 3, hz = 2 }
		H.expect(near(M.boxEnter(0, 0, 0, -1, turned, 0), 7), "turned box")
	end,

	["Bullseye's target stands at full size up to Far away in the open"] = function()
		local M, Config = load()
		local B = Config.EmoteMenu.Custom.Bullseye
		local d, s = M.targetSpot(spec(Config, math.huge, {}))
		H.expect(d == B.Far and s == 1, "far, full size")
		-- A wall a stud short of room: the face stands with the easel's back clear of it.
		local wall = B.Far + B.Back - 1
		d, s = M.targetSpot(spec(Config, wall, {}))
		H.expect(d ~= nil and near(d, wall - B.Back) and s == 1, "against the wall")
	end,

	["with no room it comes closer and smaller, and always plays by a wall"] = function()
		local M, Config = load()
		local B = Config.EmoteMenu.Custom.Bullseye
		local d, s = M.targetSpot(spec(Config, 5.5, {}))
		H.expect(d ~= nil and s < 1 and s >= B.MinScale, "smaller")
		H.expect(d ~= nil and d >= B.Tight and d + B.Back * s <= 5.5 + 1e-9, "clear of the wall")
		-- Nose to a wall: the smallest, closest one still stands (it may touch the wall).
		d, s = M.targetSpot(spec(Config, 1, {}))
		H.expect(d == B.Tight and s == B.MinScale, "always plays")
	end,

	["it never stands over a table"] = function()
		local M, Config = load()
		local B = Config.EmoteMenu.Custom.Bullseye
		-- Facing a table 1 stud from its wall: no room for a target at all.
		local d = M.targetSpot(spec(Config, math.huge, { table_(0, -6.48) }))
		H.expect(d == nil, "no target over the table")
		-- A table further off: the target stands short of it, clear of the margin.
		local d2, s2 = M.targetSpot(spec(Config, math.huge, { table_(0, -17) }))
		H.expect(d2 ~= nil, "fits before it")
		local edge = 17 - 5.48 -- the table's near wall
		H.expect(d2 ~= nil and d2 + B.Back * s2 <= edge - B.TableMargin + 1e-9, "short of it")
		-- Standing beside a table, facing along it (a table turned a quarter, its long side
		-- 1.4 studs to the dancer's right): a smaller target fits beside it.
		local beside = { x = 5.48 + 1.4, z = -5, cos = 0, sin = 1, hx = 9.48, hz = 5.48 }
		local d3, s3 = M.targetSpot(spec(Config, math.huge, { beside }))
		H.expect(d3 ~= nil and s3 < 1, "shrunk to fit beside it")
		H.expect(d3 ~= nil and B.Half * s3 + B.TableMargin <= 1.4 + 1e-9, "clear of its side")
	end,

	["about half of each handful misses, the same on every client"] = function()
		local M, Config = load()
		local P = Config.EmoteMenu.Custom.Popcorn
		local a = M.handful(42, P.Count, P.MissShare)
		local b = M.handful(42, P.Count, P.MissShare)
		local misses = 0
		for i, k in a do
			misses += if k.miss then 1 else 0
			H.expect(k.miss == b[i].miss and k.side == b[i].side, "same seed, same handful")
			H.expect(k.kind == 1 or k.kind == 2, "a mesh")
			H.expect(k.side >= -1 and k.side <= 1 and k.lag >= 0 and k.lag < 1, "in range")
		end
		H.expect(#a == P.Count, "count")
		H.expect(misses == math.floor(P.Count * P.MissShare + 0.5), "half miss")
		-- Which ones miss changes from toss to toss.
		local differ = false
		for seed = 1, 20 do
			local c = M.handful(seed, P.Count, P.MissShare)
			for i, k in c do
				if k.miss ~= a[i].miss then
					differ = true
				end
			end
		end
		H.expect(differ, "shuffled")
		local roll = M.rng(7)
		for _ = 1, 1000 do
			local x = roll()
			H.expect(x >= 0 and x < 1, "rng in [0, 1)")
		end
	end,

	["a thrown kernel lands where it was aimed"] = function()
		local M = load()
		local g = 70
		local vx, vy, vz = M.launch(1, 2, 3, 0.5, 4, -1, 0.3, g)
		local x, y, z = M.arc(vx, vy, vz, g, 0.3)
		H.expect(near(1 + x, 0.5) and near(2 + y, 4) and near(3 + z, -1), "on target")
		-- Falling 3 studs after a hop up.
		local t = M.fallTime(3, 5, g)
		local _, dy = M.arc(0, 5, 0, g, t)
		H.expect(t > 0 and near(dy, -3, 1e-6), "lands 3 below")
	end,
}
