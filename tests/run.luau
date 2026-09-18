--!strict
-- Test runner. Every tests/*_test.luau returns a table of { [name] = function }.
-- Usage: lune run tests/run.luau   (or tools/test.sh)

local fs = require("@lune/fs")
local process = require("@lune/process")

local files = {}
for _, entry in fs.readDir("tests") do
	if entry:match("_test%.luau$") then
		table.insert(files, entry)
	end
end
table.sort(files)

local passed, failed = 0, 0
local startedAt = os.clock()

for _, file in files do
	local moduleName = (file:gsub("%.luau$", ""))
	local suite = require("./" .. moduleName) :: { [string]: () -> () }
	local names = {}
	for name in suite do
		table.insert(names, name)
	end
	table.sort(names)

	print(moduleName)
	for _, name in names do
		local ok, err = pcall(suite[name])
		if ok then
			passed += 1
			print("  PASS  " .. name)
		else
			failed += 1
			print("  FAIL  " .. name)
			print("        " .. tostring(err))
		end
	end
end

print(("\n%d passed, %d failed in %.2fs"):format(passed, failed, os.clock() - startedAt))
if failed > 0 then
	process.exit(1)
end
