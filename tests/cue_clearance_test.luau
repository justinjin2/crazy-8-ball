--!strict
-- CueShape and CueClearance tests: the drawn cue's shape, and the visual pitch that keeps it
-- clear of the rail and the balls.
--
-- The pitch is checked two ways: against the numbers the design worked out by hand (a cue
-- ball 10, 5 and 1 inches from the foot cushion; a ball 3 inches behind), and against an
-- independent brute-force check that samples the drawn cue every quarter inch over a sweep of
-- positions, angles, spins and ball layouts. The second is what makes the first trustworthy:
-- the search could agree with a hand calculation and still let a cue clip a rail at a corner.

local H = require("./harness")

local function setup()
	local Config = H.require("Config")
	local geometry = H.require("Physics.Table").build({ pocketsOpen = true })
	return Config, H.require("CueShape"), H.require("CueClearance"), geometry
end

local function ball(id: number, x: number, y: number): any
	return { id = id, x = x, y = y, z = 0, pocketed = false }
end

local function query(x: number, y: number, angle: number, spinX: number?, spinY: number?): any
	return { cueX = x, cueY = y, angle = angle, spinX = spinX, spinY = spinY }
end

-- The pitch a query gets on an empty table.
local function railPitch(x: number, y: number, angle: number, spinY: number?): number
	local _, _, CueClearance, geometry = setup()
	return CueClearance.pitch(geometry, {}, query(x, y, angle, 0, spinY)).degrees
end

-- A rack plus a scatter of loose balls, from fixed positions (no randomness in tests).
local function layouts(): { { any } }
	local Config, _, _, geometry = setup()
	local Rack = H.require("Physics.Rack")
	local rack = {}
	for _, b in Rack.newGame(geometry, Config.Rack.DefaultSeed) do
		if b.id ~= 0 then
			table.insert(rack, ball(b.id, b.x, b.y))
		end
	end
	local scatter = {}
	local spots = {
		{ -30, 10 },
		{ -8, -3 },
		{ 5, 18 },
		{ 22, -12 },
		{ 40, 4 },
		{ -44, -20 },
		{ 46, 22 },
		{ 0, -23.8 },
	}
	for i, spot in spots do
		table.insert(scatter, ball(i, spot[1], spot[2]))
	end
	return { {}, rack, scatter }
end

return {
	["the cue's radius is a continuous, never narrowing envelope over every piece"] = function()
		local Config, CueShape = setup()
		local C = Config.Cue
		for _, L in { C.CueLengthStuds, 4.4, 9.3 } do
			H.near(CueShape.radiusAt(0, L), C.CueTipDiameterStuds / 2, 1e-12, "tip radius at 0")
			H.near(CueShape.radiusAt(L, L), C.CueButtDiameterStuds / 2, 1e-12, "butt radius at L")
			local pieces = CueShape.pieces(L, 1.5)
			local previous = -math.huge
			local steps = 4000
			for i = -10, steps + 400 do
				local d = L * i / steps
				local r = CueShape.radiusAt(d, L)
				H.expect(r >= previous - 1e-12, ("the envelope narrows at %.4f studs"):format(d))
				-- Continuity: a step this small can only move the envelope a little.
				if previous > -math.huge then
					H.expect(r - previous < 0.01, ("the envelope jumps at %.4f studs"):format(d))
				end
				previous = r
				for _, piece in pieces do
					if d >= piece.from and d <= piece.to then
						H.expect(
							r >= piece.diameter / 2 - 1e-12,
							("%s is wider than the envelope at %.4f"):format(piece.name, d)
						)
					end
				end
			end
			-- Inches in, inches out.
			local s = Config.Table.StudsPerInch
			H.near(CueShape.radiusAtInches(10, L), CueShape.radiusAt(10 * s, L) / s, 1e-12, "in")
		end
	end,

	["the pieces run tip to butt without gaps"] = function()
		local Config, CueShape = setup()
		local L = Config.Cue.CueLengthStuds
		local pieces = CueShape.pieces()
		H.expect(#pieces == #Config.Cue.Profile, "one piece per profile row")
		H.near(pieces[1].from, 0, 1e-12, "starts at the tip")
		for i = 2, #pieces do
			H.near(pieces[i].from, pieces[i - 1].to, 1e-12, "contiguous")
			H.expect(pieces[i].diameter >= pieces[i - 1].diameter, "never narrows toward the butt")
		end
		H.near(pieces[#pieces].to, L, 1e-9, "covers exactly the length")
		H.expect(pieces[1].name == "Tip" and pieces[1].look == "Tip", "the tip keeps its name")
		local names = {}
		for _, piece in pieces do
			H.expect(names[piece.name] == nil, "piece names are unique: " .. piece.name)
			names[piece.name] = true
		end
	end,

	["the tip meets the rendered ball: a centre hit is one radius straight back"] = function()
		local Config, CueShape = setup()
		local Rr = Config.Balls.RenderRadiusInches
		local back, right, up = CueShape.strikeOffset(0, 0)
		H.near(back, Rr, 1e-12, "back")
		H.near(right, 0, 1e-12, "right")
		H.near(up, 0, 1e-12, "up")
		for _, spin in { { 0.5, 0 }, { 0, -0.5 }, { 0.35, 0.35 }, { -0.2, 0.4 } } do
			local b, r, u = CueShape.strikeOffset(spin[1], spin[2])
			H.near(b * b + r * r + u * u, Rr * Rr, 1e-9, "on the rendered sphere")
			H.near(r, spin[1] * Rr, 1e-12, "right follows spin x")
			H.near(u, spin[2] * Rr, 1e-12, "up follows spin y")
		end
	end,

	["the design's worked examples near the foot cushion"] = function()
		local _, _, CueClearance, geometry = setup()
		-- Shooting toward the head rail (angle pi) with the cue coming back over the foot rail.
		-- The design's hand numbers: 10 in of cloth behind -> about 9 degrees, 5 in -> about 22,
		-- the ball frozen to the cushion (tip over the rail) -> about 34.
		for _, case in { { 40, 8, 11 }, { 45, 20, 25 }, { 48.875, 31, 38 } } do
			local r = CueClearance.pitch(geometry, {}, query(case[1], 0, math.pi))
			H.expect(
				r.degrees >= case[2] and r.degrees <= case[3],
				("x = %.3f: %.2f degrees, expected %d-%d"):format(
					case[1],
					r.degrees,
					case[2],
					case[3]
				)
			)
			H.expect(r.limit == "rail", "the rail set it, got " .. r.limit)
		end
	end,

	["an open table leaves the cue at the physics elevation"] = function()
		local Config, _, CueClearance, geometry = setup()
		local E = Config.Cue.CueElevationDegrees
		for degrees = 0, 345, 15 do
			local r = CueClearance.pitch(geometry, {}, query(0, 0, math.rad(degrees)))
			if degrees == 90 or degrees == 270 then
				-- Straight across from the centre the 7 stud cue runs back over a side pocket's
				-- casting, which stands 0.16 in proud of the rail: a hair of tilt.
				H.expect(r.limit == "rail" and r.degrees > E and r.degrees < E + 0.5, "side")
			else
				H.expect(r.degrees == E, ("%d: %.4f"):format(degrees, r.degrees))
				H.expect(r.limit == "floor", "nothing raised it")
			end
		end
	end,

	["the pitch only rises as the cushion comes closer"] = function()
		for _, y in { 0, 12 } do
			local previous = 0
			for i = 0, 76 do
				local x = 30 + i * 0.25
				local p = railPitch(x, y, math.pi)
				H.expect(p >= previous - 1e-6, ("x = %.2f: %.4f after %.4f"):format(x, p, previous))
				previous = p
			end
		end
	end,

	["a ball behind the cue raises it; one off to the side lets it pass"] = function()
		local Config, _, CueClearance, geometry = setup()
		local R = Config.Balls.RadiusInches
		local E = Config.Cue.CueElevationDegrees
		-- The cue ball at the centre shooting +x, an object ball behind it.
		local function pitchWith(back: number, lateral: number): any
			return CueClearance.pitch(geometry, { ball(5, -back, lateral) }, query(0, 0, 0))
		end
		local behind = pitchWith(2 * R + 3, 0) -- a 3 in gap between the balls
		H.expect(
			behind.degrees >= 23 and behind.degrees <= 28,
			("3 in behind: %.2f"):format(behind.degrees)
		)
		H.expect(behind.limit == "ball" and behind.blockingBall == 5, "the ball set it")
		local offset = pitchWith(2 * R + 3, 1)
		H.expect(offset.degrees < behind.degrees, "1 in to the side needs less")
		H.expect(offset.degrees > E, "...but still some")
		local clear = pitchWith(2 * R + 3, 2)
		H.expect(clear.degrees == E, ("2 in to the side passes: %.3f"):format(clear.degrees))
		-- Frozen right behind: the stroke line itself is blocked, so only the drawn cue can
		-- clear it (the design's ~33 degrees), never the cap and never below the elevation.
		local frozen = pitchWith(2 * R + 1e-4, 0)
		H.expect(frozen.limit == "ballSegment" or frozen.limit == "cap", "frozen: " .. frozen.limit)
		H.expect(frozen.degrees >= E, "never below the elevation")
		H.expect(
			frozen.degrees > 30 and frozen.degrees < 37,
			("frozen: %.2f"):format(frozen.degrees)
		)
		-- A pocketed ball is not in the way.
		local gone = ball(5, -(2 * R + 3), 0)
		gone.pocketed = true
		H.expect(CueClearance.pitch(geometry, { gone }, query(0, 0, 0)).degrees == E, "pocketed")
	end,

	["draw raises the cue near a rail and follow lowers it"] = function()
		local centre = railPitch(45, 0, math.pi, 0)
		local draw = railPitch(45, 0, math.pi, -0.5)
		local follow = railPitch(45, 0, math.pi, 0.5)
		H.expect(draw > centre + 1, ("draw %.2f vs centre %.2f"):format(draw, centre))
		H.expect(follow < centre - 1, ("follow %.2f vs centre %.2f"):format(follow, centre))
	end,

	["the pocket castings never lower the pitch, and raise it near a pocket"] = function()
		local Config, _, CueClearance, geometry = setup()
		local T = Config.Table
		local cases = {}
		for _, spot in { { 47, 21 }, { -46, -22.5 }, { 2, 23.5 }, { 45.5, -23 } } do
			for degrees = 0, 330, 30 do
				table.insert(cases, query(spot[1], spot[2], math.rad(degrees)))
			end
		end
		local with = {}
		for i, q in cases do
			with[i] = CueClearance.pitch(geometry, {}, q).degrees
		end
		local saved = T.PocketCastingTopInches
		T.PocketCastingTopInches = T.RailTopInches -- no castings, for comparison
		local ok, err = pcall(function()
			local raised = 0
			for i, q in cases do
				local without = CueClearance.pitch(geometry, {}, q).degrees
				H.expect(with[i] >= without - 1e-9, "a casting lowered the pitch")
				if with[i] > without + 0.05 then
					raised += 1
				end
			end
			H.expect(raised > 0, "no casting ever raised the pitch near a pocket")
		end)
		T.PocketCastingTopInches = saved
		H.expect(ok, tostring(err))
	end,

	["sweep: the drawn cue clears the rail and the balls everywhere it can be"] = function()
		local Config, CueShape, CueClearance, geometry = setup()
		local C, T = Config.Cue, Config.Table
		local s = T.StudsPerInch
		local Rr = Config.Balls.RenderRadiusInches
		local R = Config.Balls.RadiusInches
		local hl, hw = geometry.halfLength, geometry.halfWidth
		local E, cap = C.CueElevationDegrees, C.VisualPitchMaxDegrees
		local rMax = CueShape.radiusAtInches(math.huge)
		local spots = {}
		for x = -45, 45, 15 do
			for y = -20, 20, 10 do
				table.insert(spots, { x, y })
			end
		end
		for _, spot in
			{
				{ 48.875, 0 },
				{ -48.875, 9 },
				{ 20, 23.875 },
				{ -31, -23.875 },
				{ 47, 22 },
				{ -47, 22 },
				{ 47, -22 },
				{ -47, -22 },
			}
		do
			table.insert(spots, spot)
		end
		local spins = { { 0, 0 }, { 0, -0.5 }, { 0.35, 0.35 } }
		local checked, capped, tight = 0, 0, 0
		for _, balls in layouts() do
			for _, spot in spots do
				-- Balls overlapping the cue ball cannot happen on a real table.
				local here = {}
				for _, b in balls do
					if (b.x - spot[1]) ^ 2 + (b.y - spot[2]) ^ 2 > (2 * R) ^ 2 then
						table.insert(here, b)
					end
				end
				for step = 0, 47 do
					local angle = math.rad(step * 7.5)
					for _, spin in spins do
						local q = query(spot[1], spot[2], angle, spin[1], spin[2])
						local r = CueClearance.pitch(geometry, here, q)
						H.expect(r.degrees >= E and r.degrees <= cap, "pitch out of range")
						if r.limit == "cap" then
							capped += 1
							continue
						end
						checked += 1
						-- Independent check: walk the drawn cue a quarter inch at a time.
						local theta = math.rad(r.degrees)
						local c, sn = math.cos(theta), math.sin(theta)
						local back, right, up = CueShape.strikeOffset(spin[1], spin[2])
						local ax, ay = math.cos(angle), math.sin(angle)
						local px, py =
							spot[1] - ax * back + ay * right, spot[2] - ay * back - ax * right
						local pz = Rr + up
						local gR = C.CueRestGapInches
						local gEnd = gR + C.CuePullBackStuds / s + C.CueLengthStuds / s
						-- Only balls the cue can come near; the rest are clear on plan alone.
						local near = {}
						for _, b in here do
							local lateral = (b.x - px) * ay - (b.y - py) * ax
							if math.abs(lateral) < Rr + rMax + C.VisualBallClearanceInches then
								table.insert(near, b)
							end
						end
						local where = ("(%.1f, %.1f) at %.1f degrees"):format(
							spot[1],
							spot[2],
							step * 7.5
						)
						local railLimit = hl + T.RailWidthInches + rMax
						local sideLimit = hw + T.RailWidthInches + rMax
						local along = gR
						while along <= gEnd do
							local x, y = px - ax * along * c, py - ay * along * c
							local z = pz + along * sn
							-- The widest the cue gets is a cheap first test for both checks.
							local ux, uy = math.abs(x), math.abs(y)
							local maybe = (ux > hl - rMax or uy > hw - rMax)
								and ux < railLimit
								and uy < sideLimit
							local rad = if maybe or #near > 0
								then CueShape.radiusAtInches(along - gR)
								else 0
							if
								maybe
								and (ux > hl - rad or uy > hw - rad)
								and ux < hl + T.RailWidthInches + rad
								and uy < hw + T.RailWidthInches + rad
							then
								-- The casting blend at this point, measured leniently (the search
								-- uses the nearest point of the whole crossing).
								local nearest = math.huge
								for _, pocket in geometry.pockets do
									local dx, dy = x - pocket.x, y - pocket.y
									nearest = math.min(nearest, math.sqrt(dx * dx + dy * dy))
								end
								local w = math.clamp(
									(T.PocketCastingReachInches - nearest - rad - 0.01)
										/ T.PocketCastingBlendInches,
									0,
									1
								)
								local top = T.RailTopInches
									+ (T.PocketCastingTopInches - T.RailTopInches) * w
								if z - rad / c < top + C.VisualRailClearanceInches - 1e-6 then
									error("cue under the rail top from " .. where)
								end
							end
							for _, b in near do
								local dx, dy, dz = x - b.x, y - b.y, z - Rr
								local need = Rr + rad + C.VisualBallClearanceInches - 0.01
								if dx * dx + dy * dy + dz * dz < need * need then
									error(("cue through ball %d from %s"):format(b.id, where))
								end
							end
							along += 0.25
						end
						H.expect(
							(
								CueClearance.isClear(
									geometry,
									here,
									q,
									r.degrees,
									r.limit ~= "ballSegment"
								)
							),
							"isClear disagrees with the pitch it came from"
						)
						-- Tight: a rail-set pitch a twentieth of a degree lower hits the rail.
						if r.limit == "rail" and #here == 0 then
							tight += 1
							local ok, why =
								CueClearance.isClear(geometry, {}, q, r.degrees - 0.05, false)
							H.expect(not ok and why == "rail", "a rail pitch is not tight")
						end
					end
				end
			end
		end
		H.expect(checked > 10000 and tight > 100, ("checked %d, tight %d"):format(checked, tight))
		H.expect(capped < checked / 20, ("capped %d of %d"):format(capped, checked + capped))
	end,

	-- The sweep steps its aims 7.5 degrees apart, which never lines the cue up along a
	-- cushion. There the cue's side reaches the rail far before its axis crosses the cushion,
	-- so walk the drawn cue for aims within 2 degrees of each cushion, 0.05 degrees apart, with
	-- english and draw, from balls frozen to (and just off) that cushion.
	["grazing a cushion: the cue clears the rail and the answer only improves with pitch"] = function()
		local Config, CueShape, CueClearance, geometry = setup()
		local C, T = Config.Cue, Config.Table
		local s = T.StudsPerInch
		local Rr = Config.Balls.RenderRadiusInches
		local hl, hw = geometry.halfLength, geometry.halfWidth
		local E, cap = C.CueElevationDegrees, C.VisualPitchMaxDegrees
		local frozenX, frozenY = hl - Config.Balls.RadiusInches, hw - Config.Balls.RadiusInches
		-- Each spot with the two aims that run along its cushion.
		local spots = {
			{ -30, frozenY, 0, 180 },
			{ 20, frozenY - 0.4, 0, 180 },
			{ 0, -frozenY, 0, 180 },
			{ frozenX, 0, 90, 270 },
			{ -frozenX, 12, 90, 270 },
		}
		local spins = { { 0, 0 }, { 0.5, 0 }, { -0.5, 0 }, { 0.35, -0.35 } }
		local gR = C.CueRestGapInches
		local gEnd = gR + C.CuePullBackStuds / s + C.CueLengthStuds / s
		local checked = 0
		for _, spot in spots do
			for _, spin in spins do
				for _, along in { spot[3], spot[4] } do
					for tenth = -40, 40 do
						local degrees = along + tenth * 0.05
						local angle = math.rad(degrees)
						local q = query(spot[1], spot[2], angle, spin[1], spin[2])
						local r = CueClearance.pitch(geometry, {}, q)
						local where = ("(%.3f, %.3f) at %.2f, spin (%.2f, %.2f): %.2f %s"):format(
							spot[1],
							spot[2],
							degrees,
							spin[1],
							spin[2],
							r.degrees,
							r.limit
						)
						H.expect(r.degrees >= E and r.degrees <= cap, "out of range " .. where)
						-- Clear, then never blocked again as the pitch rises.
						local wasClear = false
						for d = E, cap, 1 do
							local ok = CueClearance.isClear(geometry, {}, q, d, true)
							H.expect(
								ok or not wasClear,
								("blocked again at %d: %s"):format(d, where)
							)
							wasClear = ok
						end
						if r.limit ~= "cap" then
							checked += 1
							-- Walk the drawn cue a quarter inch at a time: wherever its side is over
							-- the rail, its underside clears the rail top (castings measured as in
							-- the sweep).
							local theta = math.rad(r.degrees)
							local c, sn = math.cos(theta), math.sin(theta)
							local back, right, up = CueShape.strikeOffset(spin[1], spin[2])
							local ax, ay = math.cos(angle), math.sin(angle)
							local px, py =
								spot[1] - ax * back + ay * right, spot[2] - ay * back - ax * right
							local at = gR
							while at <= gEnd do
								local x, y = px - ax * at * c, py - ay * at * c
								local rad = CueShape.radiusAtInches(at - gR)
								local ux, uy = math.abs(x), math.abs(y)
								if
									(ux > hl - rad or uy > hw - rad)
									and ux < hl + T.RailWidthInches + rad
									and uy < hw + T.RailWidthInches + rad
								then
									local nearest = math.huge
									for _, pocket in geometry.pockets do
										local dx, dy = x - pocket.x, y - pocket.y
										nearest = math.min(nearest, math.sqrt(dx * dx + dy * dy))
									end
									local w = math.clamp(
										(T.PocketCastingReachInches - nearest - rad - 0.01)
											/ T.PocketCastingBlendInches,
										0,
										1
									)
									local top = T.RailTopInches
										+ (T.PocketCastingTopInches - T.RailTopInches) * w
									local under = Rr + up + at * sn - rad / c
									if under < top + C.VisualRailClearanceInches - 1e-6 then
										error(
											("cue under the rail top at %.2f in: %s"):format(
												at,
												where
											)
										)
									end
								end
								at += 0.25
							end
						end
					end
				end
			end
		end
		H.expect(checked > 2000, ("only %d grazing aims were not capped"):format(checked))
		-- Two cases that went wrong once: a cue left at the elevation, sunk into the rail it
		-- runs along, and one that popped up near the cap for a fraction of a degree of aim.
		local sunk = CueClearance.pitch(geometry, {}, query(-30, frozenY, math.rad(180.5), 0.5, 0))
		H.expect(sunk.limit == "rail" and sunk.degrees > E + 1, "sank into the rail")
		local popped = query(frozenX, 0, math.rad(89.5), 0.5, 0)
		H.expect(CueClearance.pitch(geometry, {}, popped).degrees < 10, "popped up")
	end,

	["a longer wind-up never lowers the pitch"] = function()
		local Config, _, CueClearance, geometry = setup()
		local rest = Config.Cue.CueRestGapInches
		local full = rest + Config.Cue.CuePullBackStuds / Config.Table.StudsPerInch
		for _, balls in layouts() do
			for _, spot in { { 44, 3 }, { -47, -10 }, { 10, 22 }, { 0, 0 }, { -20, -23 } } do
				for degrees = 0, 350, 10 do
					local q = query(spot[1], spot[2], math.rad(degrees))
					local base = CueClearance.pitch(geometry, balls, q).degrees
					q.fullGapInches = full + 5
					local longer = CueClearance.pitch(geometry, balls, q).degrees
					H.expect(longer >= base - 1e-6, ("%.3f then %.3f"):format(base, longer))
				end
			end
		end
	end,

	["easing rises fast, falls slow, converges and holds still at the target"] = function()
		local _, _, CueClearance = setup()
		H.expect(CueClearance.ease(12, 12, 0.016) == 12, "a fixed point")
		H.expect(CueClearance.ease(4, 20, 0) == 4, "no time, no move")
		local up = CueClearance.ease(4, 20, 0.016) - 4
		local down = 20 - CueClearance.ease(20, 4, 0.016)
		H.expect(up > 0 and down > 0 and up > down * 2, "rises faster than it falls")
		local shown = 4
		for _ = 1, 120 do
			shown = CueClearance.ease(shown, 30, 1 / 60)
			H.expect(shown <= 30, "never overshoots")
		end
		H.near(shown, 30, 1e-6, "converges")
	end,

	["asking for pitches never changes the config"] = function()
		local Config, _, CueClearance, geometry = setup()
		local C = Config.Cue
		local before = {}
		for key, value in C do
			if type(value) == "number" or type(value) == "boolean" then
				before[key] = value
			end
		end
		local profile = {}
		for i, row in C.Profile do
			profile[i] = { row.To, row.Taper, row.Look }
		end
		for _, balls in layouts() do
			CueClearance.pitch(geometry, balls, query(48.875, 0, math.pi, 0.2, -0.4))
			CueClearance.pitch(geometry, balls, query(-10, 3, 0.7))
		end
		for key, value in before do
			H.expect(C[key] == value, "Config.Cue." .. key .. " changed")
		end
		for i, row in C.Profile do
			local was = profile[i]
			H.expect(row.To == was[1] and row.Taper == was[2] and row.Look == was[3], "Profile")
		end
	end,
}
