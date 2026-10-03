--!strict
-- Format: money, XP and chips as they read on screen (Progression/Format).

local H = require("./harness")

local function check(f: (number) -> string, cases: { { any } }, name: string)
	for _, c in cases do
		local got = f(c[1])
		H.expect(got == c[2], ("%s(%s) = %q, expected %q"):format(name, tostring(c[1]), got, c[2]))
	end
end

return {
	["commas"] = function()
		local Format = H.require("Progression.Format")
		check(Format.commas, {
			{ 0, "0" },
			{ 7, "7" },
			{ 999, "999" },
			{ 1000, "1,000" },
			{ 1250, "1,250" },
			{ 100000, "100,000" },
			{ 1234567, "1,234,567" },
			{ -1500, "-1,500" },
			{ -999, "-999" },
			{ 12.9, "12" }, -- cut toward zero
			{ -12.9, "-12" },
			{ -0.5, "0" }, -- never "-0"
			{ 0 / 0, "0" },
		}, "commas")
		H.expect(Format.xp(1000) == "1,000" and Format.xp(0) == "0", "xp")
	end,

	["money in full below a million, shortened from it"] = function()
		local Format = H.require("Progression.Format")
		check(Format.money, {
			{ 0, "$0" },
			{ 10, "$10" },
			{ 1250, "$1,250" },
			{ 999999, "$999,999" },
			{ 1000000, "$1M" },
			{ 1200000, "$1.2M" },
			{ 3490000, "$3.49M" },
			{ 9999999, "$9.99M" }, -- cut, never rounded up
			{ 10000000, "$10M" },
			{ 12500000, "$12.5M" },
			{ 12340000, "$12.34M" },
			{ 12349999, "$12.34M" }, -- cut, never rounded up
			{ 10010000, "$10.01M" },
			{ 999999999, "$999.99M" },
			{ 1000000000, "$1B" },
			{ 1150000000, "$1.15B" },
			{ 1234000000, "$1.23B" },
			{ 1e12, "$1T" },
			{ 2.5e12, "$2.5T" },
			{ 1.5e15, "$1,500T" },
			{ -1250, "-$1,250" },
			{ -12500000, "-$12.5M" },
		}, "money")
	end,

	["money deltas for the chips"] = function()
		local Format = H.require("Progression.Format")
		check(Format.moneyDelta, {
			{ 10, "+$10" },
			{ -150, "-$150" },
			{ 0, "+$0" },
			{ 1250, "+$1,250" },
			{ 12500000, "+$12.5M" },
		}, "moneyDelta")
	end,
}
