--!strict
-- How numbers read on screen: money, XP and chips. Pure (no Instances, no Roblox APIs).
--
-- Money is written in full with commas up to $999,999; from $1,000,000 it is shortened to
-- millions, billions or trillions with at most two decimals, cut (never rounded up, so a
-- balance never reads as more than it is) and without trailing zeros: $1.2M, $3.49M, $10M,
-- $1.23B, $999.99M, $1T (the economy plan, 2026-10-02: "$1.2M style").

-- UI text: the templates below move into Strings later. `%s` is the number as written.
local MONEY = "$%s"
local PLUS = "+"
local MINUS = "-"
-- Shortened money, largest first: from `from` up, the amount in `size`s with its suffix.
local UNITS = {
	{ from = 1e12, size = 1e12, suffix = "T" },
	{ from = 1e9, size = 1e9, suffix = "B" },
	{ from = 1e6, size = 1e6, suffix = "M" },
}

-- Thousands are shortened ("$123K") only by moneyShort, from here up.
local SHORT_K_FROM = 100000

local Format = {}

-- A whole number, cut toward zero; 0 for NaN and the infinities.
local function whole(n: number): number
	if n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	local cut = if n < 0 then math.ceil(n) else math.floor(n)
	return if cut == 0 then 0 else cut -- never "-0"
end

--- 1250 -> "1,250"; -1500 -> "-1,500". Fractions are cut toward zero first.
function Format.commas(n: number): string
	local value = whole(n)
	local digits = ("%.0f"):format(math.abs(value))
	local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return if value < 0 then MINUS .. out else out
end

--- The N of a "1 in N" (BlockDrop.oneIn: 3 significant figures) as words: 2610 -> "2,610",
--- 84700 -> "84,700", 8.24 -> "8.24", 37.6 -> "37.6" (economy v5 plan 3.9).
function Format.oneIn(n: number): string
	if n >= 100 then
		return Format.commas(math.floor(n + 0.5))
	end
	local text = ("%.2f"):format(n)
	text = text:gsub("0+$", ""):gsub("%.$", "")
	return text
end

--- "$1,250"; from $1,000,000 up shortened: "$1.2M", "$12.5M", "$1.23B", "$1T".
function Format.money(n: number): string
	local value = whole(n)
	if value < 0 then
		return MINUS .. Format.money(-value)
	end
	for _, unit in UNITS do
		if value >= unit.from then
			local hundredths = math.floor(value / (unit.size / 100))
			local int, frac = hundredths // 100, hundredths % 100
			local text = Format.commas(int)
			if frac % 10 ~= 0 then
				text ..= (".%02d"):format(frac)
			elseif frac ~= 0 then
				text ..= (".%d"):format(frac // 10)
			end
			return MONEY:format(text .. unit.suffix)
		end
	end
	return MONEY:format(Format.commas(value))
end

--- Money in a tight column (the player list): as `money`, but from $100,000 up to the millions
--- in whole thousands, cut: $123,456 -> "$123K", $999,999 -> "$999K"; then "$1.03M" as usual.
function Format.moneyShort(n: number): string
	local value = whole(n)
	if value < 0 then
		return MINUS .. Format.moneyShort(-value)
	end
	if value >= SHORT_K_FROM and value < 1e6 then
		return MONEY:format(tostring(value // 1000) .. "K")
	end
	return Format.money(value)
end

--- A change in money for the chips: "+$10", "-$150" ("+$0" for nothing).
function Format.moneyDelta(n: number): string
	local value = whole(n)
	return if value < 0 then Format.money(value) else PLUS .. Format.money(value)
end

--- XP: "1,000".
function Format.xp(n: number): string
	return Format.commas(n)
end

return Format
