--!strict
-- The ability value harness from the command line (tests/ult_value.luau; the brief's 5.3).
-- Measures how many extra balls one use of an ability is worth, for the careful and the
-- careless model shooter at three skill levels, prints a summary and a JSON line per ability,
-- and writes tools/ult_value_results.json (keyed by ult id; other ults' rows are kept), which
-- tools/ult_model.py reads.
--
-- Usage (from the repo root):
--   lune run tools/ult_value.luau Magnet                  # about 1-3 minutes
--   lune run tools/ult_value.luau Magnet --quick          # about 10 seconds, rough numbers
--   lune run tools/ult_value.luau all --samples 60 --skill 2
--   lune run tools/ult_value.luau Magnet --seed 7 --no-write
--   lune run tools/ult_value.luau Ghost --useful --no-write   # only where it changes the shot
--   lune run tools/ult_value.luau BlackHole --set BlackHole.MaxOwn=4 --no-write   # try a tune

local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local V = require("../tests/ult_value")
local H = require("../tests/harness")

local Config = H.require("Config")

local RESULTS = "tools/ult_value_results.json"
local DEFAULT_SAMPLES = 120
local QUICK_SAMPLES = 12

local function usage(message: string?)
	if message then
		print(message)
	end
	print("usage: lune run tools/ult_value.luau <UltId|all> [--samples N] [--skill 1|2|3|all]")
	print("       [--quick] [--seed N] [--careful-only|--careless-only] [--no-write]")
	print("       [--useful]  only the tables where the ability changes the best shot")
	print("       [--set Block.Key=number]  try a Config.Ults number for this run only")
	print("ults: " .. table.concat(Config.Ults.Order, ", "))
	process.exit(1)
end

local args = process.args
local target: string? = nil
local samples: number? = nil
local skills = { 1, 2, 3 }
local seed = 1
local shooters = { "careful", "careless" }
local write = true
local useful = false
local i = 1
while i <= #args do
	local a = args[i]
	if a == "--samples" then
		i += 1
		samples = tonumber(args[i])
		if samples == nil or samples < 1 then
			usage("--samples needs a number")
		end
	elseif a == "--skill" then
		i += 1
		local v = args[i]
		if v == "all" then
			skills = { 1, 2, 3 }
		elseif v == "1" or v == "2" or v == "3" then
			skills = { tonumber(v) :: number }
		else
			usage("--skill is 1, 2, 3 or all")
		end
	elseif a == "--seed" then
		i += 1
		seed = tonumber(args[i]) or usage("--seed needs a number") :: any
	elseif a == "--quick" then
		samples = samples or QUICK_SAMPLES
	elseif a == "--careful-only" then
		shooters = { "careful" }
	elseif a == "--careless-only" then
		shooters = { "careless" }
	elseif a == "--useful" then
		useful = true
	elseif a == "--no-write" then
		write = false
	elseif a == "--set" then
		-- Config.Ults.<Block>.<Key> = number for this run (a tune to try; never written).
		i += 1
		local block, key, value = string.match(args[i] or "", "^(%w+)%.(%w+)=(.+)$")
		local number = tonumber(value)
		local into = if block then (Config.Ults :: any)[block] else nil
		if type(into) ~= "table" or number == nil or into[key :: string] == nil then
			usage("--set needs Block.Key=number for an existing Config.Ults number")
		end
		into[key :: string] = number
		write = false
	elseif a:sub(1, 2) == "--" then
		usage("unknown option " .. a)
	elseif target == nil then
		target = a
	else
		usage("one ult at a time (or all)")
	end
	i += 1
end
if target == nil then
	usage()
end

local ults: { string } = {}
if target == "all" then
	ults = table.clone(Config.Ults.Order)
elseif Config.Ults.Catalog[target :: string] then
	ults = { target :: string }
else
	usage("unknown ult " .. tostring(target))
end

local measuredAt = "unknown"
pcall(function()
	measuredAt = DateTime.now():toIsoDate():sub(1, 10)
end)

local results: { [string]: any } = {}
if fs.isFile(RESULTS) then
	local ok, decoded = pcall(serde.decode, "json" :: any, fs.readFile(RESULTS))
	if ok and type(decoded) == "table" then
		results = decoded
	end
end

-- The plain shots and outcomes are the same for every ability: play them once.
local cache = {}
for _, id in ults do
	local report = V.measure(id, {
		samples = samples or DEFAULT_SAMPLES,
		seed = seed,
		skills = skills,
		shooters = shooters,
		measuredAt = measuredAt,
		cache = cache,
		useful = useful,
		progress = function(done: number, total: number)
			if done % 10 == 0 or done == total then
				stdio.write(("\r  %s: %d / %d states"):format(id, done, total))
				if done == total then
					stdio.write("\n")
				end
			end
		end,
	})
	print(V.format(report))
	print("JSON " .. serde.encode("json", report, false))
	print()
	results[id] = report
end

if write then
	fs.writeFile(RESULTS, serde.encode("json", results, true))
	print("wrote " .. RESULTS)
end
