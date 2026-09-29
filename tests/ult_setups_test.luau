--!strict
-- The developer's /abilitysetup layouts (Config.Ults.Setups; DevCommands, the look check in
-- docs/prompts/ABILITIES_PROMPT.md 5.6): one per ult, every ball on the cloth inside the
-- cushions, clear of the other balls and of the pocket mouths, every object ball listed.

local H = require("./harness")

local function load(): (any, any)
	return H.require("Config"), H.require("Strings")
end

-- Checks every setup's balls with `check(ultId, what, x, y)` for the cue ball and each ball
-- on the cloth ("cue" or the ball's number).
local function eachBall(check: (string, string, number, number) -> ())
	local Config = load()
	for _, id in Config.Ults.Order do
		local setup = Config.Ults.Setups[id]
		if setup then
			check(id, "cue", setup.Cue[1], setup.Cue[2])
			for ball = 1, 15 do
				local spot = setup.Spots[ball]
				if spot then
					check(id, tostring(ball), spot[1], spot[2])
				end
			end
		end
	end
end

return {
	["every ult has a setup, every setup is an ult, and a note says what to shoot"] = function()
		local Config, Strings = load()
		local known = {}
		for _, id in Config.Ults.Order do
			known[id] = true
			H.expect(Config.Ults.Setups[id] ~= nil, id .. " has no setup")
			local note = Strings.Dev.SetupNotes[id]
			H.expect(type(note) == "string" and #note > 0, id .. " has no note")
		end
		for id in Config.Ults.Setups do
			H.expect(known[id] == true, id .. " is not an ult")
		end
		for id in Strings.Dev.SetupNotes do
			H.expect(known[id] == true, id .. "'s note is for no ult")
		end
	end,

	["spots use ball ids 1-15 only, every one listed, the 8 on the cloth"] = function()
		local Config = load()
		for id, setup in Config.Ults.Setups do
			H.expect(
				setup.Groups == "solids" or setup.Groups == "stripes" or setup.Groups == "open",
				id .. ": groups"
			)
			H.expect(type(setup.Cue) == "table" and #setup.Cue == 2, id .. ": cue spot")
			for ball, spot in setup.Spots do
				H.expect(
					type(ball) == "number" and ball % 1 == 0 and ball >= 1 and ball <= 15,
					id .. ": bad ball id " .. tostring(ball)
				)
				H.expect(spot == false or (type(spot) == "table" and #spot == 2), id .. ": spot")
			end
			for ball = 1, 15 do
				H.expect(setup.Spots[ball] ~= nil, ("%s: ball %d not listed"):format(id, ball))
			end
			H.expect(setup.Spots[8] ~= false, id .. ": the 8 is down")
			-- At least one of the caller's balls is up to shoot at.
			local mine = false
			for ball = 1, 15 do
				local solid = ball <= 7
				local ownsIt = setup.Groups == "open" and ball ~= 8
					or setup.Groups == "solids" and solid
					or setup.Groups == "stripes" and ball >= 9
				if ownsIt and setup.Spots[ball] then
					mine = true
				end
			end
			H.expect(mine, id .. ": none of the caller's balls is up")
		end
	end,

	["every ball is inside the cushions and clear of the pocket mouths"] = function()
		local Config = load()
		local T = Config.Table
		local hl, hw = T.LengthInches / 2, T.WidthInches / 2
		-- A ball's radius plus a little: the centre may be at most 48.5 x 23.5 in out.
		local margin = Config.Balls.RadiusInches + 0.375
		-- The six pockets' mouths (corners and the middle of each long rail).
		local mouths = { { -hl, hw }, { 0, hw }, { hl, hw }, { hl, -hw }, { 0, -hw }, { -hl, -hw } }
		local clear = 4 -- inches from a mouth point: well out of every jaw
		eachBall(function(id, what, x, y)
			local where = ("%s: ball %s at (%g, %g)"):format(id, what, x, y)
			H.expect(
				math.abs(x) <= hl - margin and math.abs(y) <= hw - margin,
				where .. " off the cloth"
			)
			for _, m in mouths do
				local d = math.sqrt((x - m[1]) ^ 2 + (y - m[2]) ^ 2)
				H.expect(d >= clear, where .. " in a pocket mouth")
			end
		end)
	end,

	["no two balls overlap"] = function()
		local Config = load()
		local apart = Config.Balls.RadiusInches * 2 + 0.05 -- 2.3 in centre to centre
		for id, setup in Config.Ults.Setups do
			local balls = { { "cue", setup.Cue[1], setup.Cue[2] } }
			for ball = 1, 15 do
				local spot = setup.Spots[ball]
				if spot then
					table.insert(balls, { tostring(ball), spot[1], spot[2] })
				end
			end
			for i = 1, #balls do
				for j = i + 1, #balls do
					local a, b = balls[i], balls[j]
					local d = math.sqrt((a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
					H.expect(
						d >= apart,
						("%s: %s and %s overlap (%.2f in)"):format(id, a[1], b[1], d)
					)
				end
			end
		end
	end,
}
