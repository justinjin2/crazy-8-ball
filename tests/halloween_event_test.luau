--!strict
-- The Halloween event's window (Halloween/Event; Config.Halloween, docs/halloween/PLAN.md):
-- every boundary second, the Candy Rush and the double day (never 4x), the boards and the
-- Rush chip's text.

local H = require("./harness")

local function load()
	return H.require("Halloween.Event"), H.require("Config").Halloween
end

-- Runs `fn` with Config.Halloween.Enabled set to `on`, then puts it back.
local function withEnabled(on: boolean, fn: () -> ())
	local C = H.require("Config").Halloween
	local saved = C.Enabled
	C.Enabled = on
	local ok, err = pcall(fn)
	C.Enabled = saved
	if not ok then
		error(err, 0)
	end
end

local COUNTDOWN = 1793226600 -- Wed Oct 28 18:30:00 EDT
local START = 1793228400 -- 19:00:00 EDT (23:00 UTC)
local DOUBLE_FROM = 1793419200 -- Sat Oct 31 00:00:00 EDT
local DOUBLE_TO = 1793505600 -- Sun Nov 1 00:00:00 EDT
local END = 1793750400 -- Tue Nov 3 19:00:00 EST

return {
	["the plan's times"] = function()
		local _, C = load()
		H.expect(C.CountdownAt == COUNTDOWN and C.StartsAt == START and C.EndsAt == END, "times")
		H.expect(C.Double.From == DOUBLE_FROM and C.Double.To == DOUBLE_TO, "Oct 31 US Eastern")
		H.expect(C.Boards == 6 and C.BoardSeconds == 86400, "six daily boards")
		H.expect(C.Rush.Minutes == 10 and C.EventMultiplier == 2, "Rush 10 min, 2x")
		H.expect(C.CountdownAt < C.StartsAt and C.StartsAt < C.EndsAt, "in order")
		H.expect(C.StartsAt % 3600 == 0, "starts on the hour (a Rush lines up with UTC hours)")
	end,

	["every state boundary, to the second"] = function()
		local Event = load()
		H.expect(Event.state(COUNTDOWN - 1) == "Before", "18:29:59")
		H.expect(Event.state(COUNTDOWN) == "Countdown", "18:30:00")
		H.expect(Event.state(START - 1) == "Countdown", "18:59:59")
		H.expect(Event.state(START) == "Live", "19:00:00")
		H.expect(Event.isLive(START) and not Event.isLive(START - 1), "isLive")
		H.expect(Event.state(END - 1) == "Live", "Nov 3 18:59:59 EST")
		H.expect(Event.state(END) == "Ended", "Nov 3 19:00:00 EST")
		H.expect(not Event.isLive(END) and Event.over(END) and not Event.over(END - 1), "over")
		H.expect(Event.endsIn(END - 90) == 90 and Event.endsIn(END + 5) == 0, "endsIn")
		H.expect(Event.startsIn(START - 1800) == 1800 and Event.startsIn(START) == 0, "startsIn")
	end,

	["switched off it is always Before, but still over after EndsAt"] = function()
		withEnabled(false, function()
			local Event = load()
			H.expect(Event.state(START + 10) == "Before", "off")
			H.expect(not Event.isLive(START + 10) and Event.multiplier(START + 10) == 1, "nothing")
			H.expect(Event.rushChip(START + 10) == nil, "no chip")
			H.expect(Event.over(END), "saved Candy still converts")
		end)
	end,

	["the Candy Rush: UTC minutes 0-9 of every hour, only while Live"] = function()
		local Event = load()
		H.expect(Event.rushActive(START), "19:00:00 is a Rush (23:00 UTC)")
		H.expect(Event.rushActive(START + 9 * 60 + 59), "9:59")
		H.expect(not Event.rushActive(START + 10 * 60), "10:00")
		H.expect(not Event.rushActive(START + 59 * 60 + 59), "59:59")
		H.expect(Event.rushActive(START + 3600), "the next hour")
		H.expect(not Event.rushActive(START - 3600), "not before the event")
		H.expect(not Event.rushActive(END), "not after it (00:00 UTC)")
		H.expect(Event.rushEndsAt(START + 5) == START + 600, "ends at minute 10")
		H.expect(Event.rushEndsAt(START + 600) == nil, "no Rush in progress")
		H.expect(Event.nextRushAt(START + 600) == START + 3600, "next hour")
		H.expect(Event.nextRushAt(START + 3600) == START + 3600, "on the hour")
		H.expect(Event.nextRushAt(COUNTDOWN) == START, "before the event: its first Rush")
		local ends = END
		H.expect(Event.nextRushAt(ends - 3600 - 1) == ends - 3600, "the last Rush")
		H.expect(Event.nextRushAt(ends - 3600 + 1) == nil, "none in the last hour")
		H.expect(Event.nextRushAt(ends + 10) == nil, "none after the end")
	end,

	["the double day is Oct 31 in US Eastern time"] = function()
		local Event = load()
		H.expect(not Event.doubleDay(DOUBLE_FROM - 1), "Oct 30 23:59:59 EDT")
		H.expect(Event.doubleDay(DOUBLE_FROM), "Oct 31 00:00:00 EDT")
		H.expect(Event.doubleDay(DOUBLE_TO - 1), "Oct 31 23:59:59 EDT")
		H.expect(not Event.doubleDay(DOUBLE_TO), "Nov 1 00:00:00 EDT")
	end,

	["the multiplier is 1 or 2, never 4"] = function()
		local Event = load()
		H.expect(Event.multiplier(START - 1) == 1, "before")
		H.expect(Event.multiplier(START) == 2, "a Rush")
		H.expect(Event.multiplier(START + 600) == 1, "no Rush")
		-- A Rush on the double day (the top of an hour on Oct 31) is still 2x.
		local rushOnDouble = DOUBLE_FROM + 3600 - DOUBLE_FROM % 3600
		H.expect(Event.rushActive(rushOnDouble) and Event.doubleDay(rushOnDouble), "both on")
		H.expect(Event.multiplier(rushOnDouble) == 2, "never stacked")
		H.expect(Event.multiplier(DOUBLE_FROM + 1800) == 2, "the double day alone")
		for t = START - 7200, END + 7200, 37 do
			local m = Event.multiplier(t)
			H.expect(m == 1 or m == 2, "only 1 or 2")
		end
		H.expect(Event.multiplier(END) == 1, "after")
	end,

	["a new board every day at 23:00 UTC, six in all"] = function()
		local Event = load()
		H.expect(Event.boardIndex(START - 1) == 0, "no board before")
		H.expect(Event.boardIndex(START) == 1, "board 1 at 19:00")
		H.expect(Event.boardIndex(START + 86399) == 1, "still board 1")
		H.expect(Event.boardIndex(START + 86400) == 2, "board 2")
		H.expect(Event.boardIndex(START + 5 * 86400 - 1) == 5, "the last second of board 5")
		H.expect(Event.boardIndex(START + 5 * 86400) == 6, "board 6")
		H.expect(Event.boardIndex(END - 1) == 6 and Event.boardIndex(END + 86400) == 6, "6 at most")
		for n = 1, 6 do
			H.expect(Event.boardOpensAt(n) == START + (n - 1) * 86400, "opens at " .. n)
			H.expect(Event.boardIndex(Event.boardOpensAt(n)) == n, "index at opening " .. n)
		end
		-- Board 4 opens on Halloween night (Oct 31 19:00 EDT).
		H.expect(Event.boardOpensAt(4) == DOUBLE_FROM + 19 * 3600, "Halloween night")
	end,

	["the Rush chip's text"] = function()
		local Event = load()
		local chip = Event.rushChip(START + 108) -- 1:48 into a Rush: 8:12 left
		H.expect(chip ~= nil and chip.text == "2x CANDY 8:12", "Rush text")
		H.expect(chip ~= nil and chip.endsAt == START + 600 and chip.kind == "Rush", "Rush end")
		H.expect(Event.rushChip(START + 600) == nil, "no chip between Rushes")
		H.expect(Event.rushChip(START - 1) == nil, "no chip before")
		local t = DOUBLE_TO - (9 * 3600 + 12 * 60 + 44) -- 9:12:44 left of Oct 31
		local double = Event.rushChip(t)
		H.expect(double ~= nil and double.text == "2x CANDY 9:12:44", "double text")
		H.expect(double ~= nil and double.endsAt == DOUBLE_TO and double.kind == "Double", "double")
		H.expect(Event.rushChip(DOUBLE_TO + 600) == nil, "Nov 1, between Rushes")
	end,

	["the clock and short formats"] = function()
		local Event = load()
		H.expect(Event.clock(0) == "0:00" and Event.clock(1799) == "29:59", "m:ss")
		H.expect(Event.clock(3600) == "1:00:00" and Event.clock(-5) == "0:00", "h:mm:ss")
		H.expect(Event.short(5 * 86400 + 23 * 3600 + 59) == "5d 23h", "days")
		H.expect(Event.short(3 * 3600 + 120) == "3h 2m" and Event.short(59) == "0m", "hours")
	end,
}
