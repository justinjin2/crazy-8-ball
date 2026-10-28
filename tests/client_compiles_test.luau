--!strict
-- Every script under src/ must compile, and Main.client must keep room for more top-level
-- locals. Luau allows 200 locals in one function; past that a script fails to compile in
-- Studio and live ("Out of local registers"), and nothing else in lint or the suite compiles
-- Main.client (found 2026-10-28: it had 14 to spare before the Halloween lanes added hooks).
-- Add a hook inside `do ... end` so it costs no top-level local.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local HEADROOM = 8 -- top-level locals Main.client must still be able to take

local function scripts(dir: string, out: { string }): { string }
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			scripts(path, out)
		elseif name:match("%.luau$") or name:match("%.lua$") then
			table.insert(out, path)
		end
	end
	return out
end

local function compiles(source: string): (boolean, string?)
	local ok, err = pcall(luau.compile, source)
	return ok, if ok then nil else tostring(err)
end

return {
	["every script under src compiles"] = function()
		local bad = {}
		for _, path in scripts("src", {}) do
			local ok, err = compiles(fs.readFile(path))
			if not ok then
				table.insert(bad, path .. ": " .. (err or "?"))
			end
		end
		assert(#bad == 0, "scripts that do not compile:\n" .. table.concat(bad, "\n"))
	end,

	["Main.client keeps room for more top-level locals"] = function()
		local source = fs.readFile("src/client/Main.client.luau")
		local pad = {}
		for i = 1, HEADROOM do
			-- a table is never folded into a constant, so each one takes a register
			table.insert(pad, ("local __headroom%d = {}"):format(i))
		end
		local ok, err = compiles(source .. "\n" .. table.concat(pad, "\n") .. "\n")
		assert(
			ok,
			("Main.client has fewer than %d top-level locals left before Luau's 200 limit; put new hooks inside `do ... end` (%s)"):format(
				HEADROOM,
				err or "?"
			)
		)
	end,
}
