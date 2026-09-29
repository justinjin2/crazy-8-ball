--!strict
-- The shared ability value harness (tests/ult_value.luau; docs/prompts/ABILITIES_PROMPT.md
-- 5.3): its random numbers and table states are seeded, its model shooter pots an easy shot
-- more often the better it is, Magnet measures positive, a placeholder exactly 0, Rewind
-- counts only the redo, and a measurement repeats to the bit. Small samples: the real
-- numbers come from `lune run tools/ult_value.luau <UltId>`.
local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Judge = H.require("Rules.ShotJudge")
local serde = require("@lune/serde")

local expect = H.expect
local tests = {}

local Catalog = Config.Ults.Catalog

-- Switch a catalog row to Built for the body only.
local function built(id: string, body: () -> ())
	local row = Catalog[id]
	local was = row.Built
	row.Built = true
	local ok, err = pcall(body)
	row.Built = was
	if not ok then
		error(err, 0)
	end
end

local function zero(): number
	return 0
end

local function snapshot(ts: V.TableState): string
	local parts = { ts.family, tostring(ts.open), tostring(ts.onEight) }
	for _, b in ts.balls do
		table.insert(parts, ("%d:%.9f:%.9f:%s"):format(b.id, b.x, b.y, tostring(b.pocketed)))
	end
	return table.concat(parts, "|")
end

-- Ball 1 straight in to the top-right corner, 15 in from its mouth, the cue ball 15 in behind
-- it on the same line; one stripe and the 8 far away.
local function straightIn(): V.TableState
	local geometry = V.geometry
	local half = Config.Table.CornerMouthInches / math.sqrt(2) / 2
	local mx, my = geometry.halfLength - half, geometry.halfWidth - half
	local r = 1 / math.sqrt(2)
	return V.customState({
		{ 0, mx - 30 * r, my - 30 * r },
		{ 1, mx - 15 * r, my - 15 * r },
		{ 8, -30, -15 },
		{ 9, -40, 15 },
	})
end

function tests.random_numbers_and_table_states_are_seeded()
	local a, b = V.rng(42), V.rng(42)
	for _ = 1, 50 do
		expect(V.nextU32(a) == V.nextU32(b), "the same seed, the same sequence")
	end
	expect(V.nextU32(V.rng(42)) ~= V.nextU32(V.rng(43)), "different seeds differ")
	expect(V.seedOf(1, 2, 3) == V.seedOf(1, 2, 3) and V.seedOf(1, 2, 3) ~= V.seedOf(1, 3, 2))

	local first = {}
	for _, family in V.FAMILIES do
		first[family] = snapshot(V.tableState(901, 1, family))
	end
	V.resetStates()
	for _, family in V.FAMILIES do
		local ts = V.tableState(901, 1, family)
		expect(snapshot(ts) == first[family], family .. ": the same seed makes the same table")
		expect(not V.findBall(ts.balls, 0).pocketed and not V.findBall(ts.balls, 8).pocketed)
	end
	expect(
		snapshot(V.tableState(902, 1, "fresh")) ~= first.fresh,
		"another seed makes another table"
	)
	local mid = V.tableState(901, 1, "mid")
	local late = V.tableState(901, 1, "late")
	for _, group in { "solids", "stripes" } do
		expect(Judge.remaining(mid.balls, group) <= 6, "mid tables keep at most 6 a group")
		expect(Judge.remaining(late.balls, group) <= 3, "late tables keep at most 3 a group")
	end
end

function tests.the_model_shooter_pots_an_easy_straight_in_more_often_when_better()
	local ts = straightIn()
	local plan = V.shots(ts, 1)[1]
	expect(not plan.safe and plan.ball == 1 and plan.pocket == 3, "it sees the straight-in")
	expect(V.play(ts, plan, 1, 0, 0, nil, zero).own == 1, "without noise it goes in")
	local rates = {}
	for skill = 1, 3 do
		local rng = V.rng(V.seedOf(77, skill))
		local pots = 0
		for _ = 1, 40 do
			local r = V.play(ts, plan, skill, V.gauss(rng), V.gauss(rng), nil, zero)
			pots += if r.own > 0 then 1 else 0
		end
		rates[skill] = pots / 40
	end
	print(
		("        straight-in pot rate by skill: %.2f, %.2f, %.2f"):format(
			rates[1],
			rates[2],
			rates[3]
		)
	)
	expect(rates[1] >= 0.75, "a strong shooter makes it most of the time")
	expect(rates[3] <= rates[1] - 0.25, "a weak shooter clearly less")
end

function tests.magnet_measures_positive_for_the_careless_shooter()
	local report = V.measure("Magnet", { samples = 15, skills = { 2 }, shooters = { "careless" } })
	local st = report.skills[1].careless :: V.Stat
	print(
		("        Magnet, careless, skill 2, %d states: worth %+.3f +- %.3f, pots %.0f%% > %.0f%%"):format(
			st.n,
			st.worth,
			st.worthSE,
			100 * st.potWithout,
			100 * st.potWith
		)
	)
	expect(st.n == 15)
	expect(st.worth > 0, "Magnet adds balls")
end

function tests.a_placeholder_measures_exactly_zero()
	expect(Catalog.ChainLightning.Built == false, "Chain Lightning is still a placeholder")
	local report =
		V.measure("ChainLightning", { samples = 5, skills = { 2 }, topK = 3, simulateInert = true })
	for _, name in { "careful", "careless" } do
		local st = (report.skills[1] :: any)[name] :: V.Stat
		expect(st.n == 5)
		expect(st.worth == 0 and st.oppGifted == 0 and st.net == 0, name .. ": worth exactly 0")
		expect(st.ownWith == st.ownWithout and st.potWith == st.potWithout, name .. ": identical")
		expect(st.foulBackfire == 0 and st.oppBackfire == 0 and st.eightBackfire == 0)
	end
end

function tests.rewind_counts_only_the_redo()
	local ts = straightIn()
	local plan = V.shots(ts, 1)[1]
	-- Eight sigma of aim error misses; the redo's draws are all 0 and pot.
	local missed = V.play(ts, plan, 2, 8, 0, "Rewind", zero)
	expect(missed.own == 0 and not missed.redone, "a placeholder Rewind does nothing")
	built("Rewind", function()
		local r = V.play(ts, plan, 2, 8, 0, "Rewind", zero)
		expect(r.redone, "none of theirs dropped: the table rewinds")
		expect(r.own == 1, "only the redo counts (it pots)")
		local again = V.play(ts, plan, 2, 8, 0, "Rewind", function(): number
			return 8
		end)
		expect(again.redone and again.own == 0, "a redo that misses counts as the miss")
		local first = V.play(ts, plan, 2, 0, 0, "Rewind", function(): number
			return 8
		end)
		expect(not first.redone and first.own == 1, "a pot on the first try: no rewind")
	end)
end

function tests.time_stop_freezes_and_the_model_strikes_again()
	local ts = V.customState({
		{ 0, -20, 0 },
		{ 1, 0, 0 },
		{ 2, 30, 10 },
		{ 8, -30, -15 },
		{ 9, -40, 15 },
	})
	local plan = V.shots(ts, 1)[1]
	built("TimeStop", function()
		local r = V.play(ts, plan, 2, 0, 0, "TimeStop", zero)
		expect(r.halted and r.struckFrozen, "the freeze, then a second strike")
		local again = V.play(ts, plan, 2, 0, 0, "TimeStop", zero)
		expect(again.own == r.own and again.opp == r.opp and again.foul == r.foul, "repeatable")
	end)
end

function tests.a_measurement_repeats_to_the_bit()
	local options = { samples = 4, skills = { 2 }, topK = 3 }
	local a = V.measure("Magnet", table.clone(options) :: any)
	local b = V.measure("Magnet", table.clone(options) :: any)
	expect(serde.encode("json", a.skills) == serde.encode("json", b.skills), "identical numbers")
end

return tests
