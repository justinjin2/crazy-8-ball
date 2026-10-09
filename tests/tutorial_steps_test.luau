--!strict
-- Steps (Tutorial/Steps, tutorial v2): the step order, resume and migration rules, what the HUD
-- shows, the hint and moment bits, the funnels' lists; and the step-name guard: every step
-- name the code uses is a real step (docs/prompts/TUTORIAL_V2_PROMPT.md 7.2; v1 once moved
-- players to a step that did not exist, "Drop", and the tutorial died there).
local fs = require("@lune/fs")

local H = require("./harness")

local function load()
	return H.require("Tutorial.Steps")
end

-- Every .luau file under `dir`.
local function files(dir: string, out: { string }): { string }
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			files(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
	return out
end

-- The step names `source` uses, each with its line: string literals in a step's place.
local PATTERNS = {
	'setStep%([^,]+,%s*"(%w+)"', -- setStep(player, "X")
	'advance%([^,]+,%s*"(%w+)"', -- advance(player, "X")
	'[Ss]tep%b()%s*[=~]=%s*"(%w+)"', -- service.step(player) == "X"
	'[Ss]tep%s*[=~]=%s*"(%w+)"', -- step == "X", previous ~= "X"
	'"TutorialStep"%)%s*[=~]=%s*"(%w+)"', -- GetAttribute("TutorialStep") == "X"
	'Steps%.%a+%([^)]-,%s*"(%w+)"%)', -- Steps.atLeast(step, "X")
	'%f[%w]step%s*=%s*"(%w+)"', -- { step = "X" }
	'fallbackOf%("(%w+)"%)', -- the client's and server's fallback times
}

-- Step-keyed tables (local NAME_STEPS = { X = ... }, HOST_HIDES) and step-valued report
-- tables (DONE_REPORTS = { Report = "X" }).
local function tableNames(source: string): { { name: string, line: number } }
	local out = {}
	local lines = string.split(source, "\n")
	local i = 1
	while i <= #lines do
		local line = lines[i]
		local keyed = string.match(line, "^local [%u_]*STEPS?[%u_]*[^=]*= {")
			or string.match(line, "^local HOST_HIDES[^=]*= {")
		local valued = string.match(line, "^local DONE_REPORTS[^=]*= {")
		if keyed or valued then
			i += 1
			while i <= #lines and not string.match(lines[i], "^}") do
				local key = string.match(lines[i], "^\t(%w+) = ")
				local value = string.match(lines[i], '^\t%w+ = "(%w+)"')
				if keyed and key then
					table.insert(out, { name = key, line = i })
				elseif valued and value then
					table.insert(out, { name = value, line = i })
				end
				i += 1
			end
		end
		i += 1
	end
	return out
end

local function used(source: string): { { name: string, line: number } }
	local out = tableNames(source)
	for n, line in string.split(source, "\n") do
		if not string.match(line, "^%s*%-%-") then
			for _, pattern in PATTERNS do
				for name in string.gmatch(line, pattern) do
					table.insert(out, { name = name, line = n })
				end
			end
		end
	end
	return out
end

return {
	["a new save starts at the arrow; a player who has played never enters"] = function()
		local Steps = load()
		H.expect(Steps.initial(0, 0) == "Arrow", "brand new")
		H.expect(Steps.initial(1, 0) == "Done", "a match played")
		H.expect(Steps.initial(0, 1) == "Done", "a win")
		H.expect(Steps.initial(nil, nil) == "Arrow", "no stats yet")
	end,

	["the order moves on one step at a time and ends at Done"] = function()
		local Steps = load()
		H.expect(Steps.after("Arrow") == "Pad" and Steps.after("Game1") == "Result", "")
		H.expect(Steps.after("Abilities") == "Soft" and Steps.after("Soft") == "Done", "")
		H.expect(Steps.after("Done") == "Done" and Steps.after("Skipped") == nil, "the ends")
		H.expect(Steps.atLeast("Cues", "Rank") and not Steps.atLeast("Rank", "Cues"), "")
		H.expect(not Steps.atLeast("Skipped", "Arrow"), "an end state is not a step")
		H.expect(Steps.active("Soft") and not Steps.active("Done"), "Soft runs, Done does not")
		H.expect(not Steps.active("Skipped") and not Steps.active(nil), "")
		H.expect(Steps.guided("Arrow") and Steps.guided("Abilities"), "the guided part")
		H.expect(not Steps.guided("Soft") and not Steps.guided("Done"), "")
		H.expect(
			Steps.chain("Result") and Steps.chain("Abilities") and not Steps.chain("Game1"),
			""
		)
	end,

	["a rejoin plays game 1 again from the arrow and resumes the chain"] = function()
		local Steps = load()
		H.expect(Steps.resume("Pad") == "Arrow" and Steps.resume("Game1") == "Arrow", "game 1")
		H.expect(Steps.resume("Result") == "Rank", "the result screens are gone")
		for _, step in { "Rank", "Mystery", "Place", "Cues", "Abilities", "Soft" } do
			H.expect(Steps.resume(step) == step, step .. " resumes where it was")
		end
	end,

	["an old save's step is repaired (the migration map)"] = function()
		local Steps = load()
		H.expect(Steps.load("Drop", 1, 1) == "Rank", "v1's Drop bug: after game 1's win")
		H.expect(Steps.load("RareDrop", 1, 1) == "Rank", "")
		H.expect(
			Steps.load("Arrow1", 0, 0) == "Arrow" and Steps.load("Request", 0, 0) == "Arrow",
			""
		)
		H.expect(Steps.load("Game1", 0, 0) == "Arrow", "a v2 game 1 starts over")
		H.expect(
			Steps.load("Equip", 1, 1) == "Cues" and Steps.load("Spin", 1, 1) == "Abilities",
			""
		)
		H.expect(Steps.load("Queue", 1, 1) == "Soft" and Steps.load("Nudges", 2, 1) == "Soft", "")
		H.expect(Steps.load("Cancelled", 1, 0) == "Skipped", "v1's cancel is an end")
		H.expect(
			Steps.load("Done", 3, 2) == "Done" and Steps.load("Skipped", 0, 0) == "Skipped",
			""
		)
		H.expect(Steps.load("Bogus", 2, 0) == "Done", "unknown, has played: done")
		H.expect(Steps.load("Bogus", 0, 0) == "Arrow", "unknown, brand new: the arrow")
		H.expect(
			Steps.load(nil, 0, 0) == "Arrow" and Steps.load(nil, 5, 2) == "Done",
			"no step yet"
		)
		H.expect(Steps.load(42, 0, 0) == "Arrow", "not a string")
		for old, new in Steps.Migrate do
			H.expect(Steps.known(new), old .. " maps to a real step")
			H.expect(not Steps.known(old) or old == "Game1", old .. " is not a v2 name")
		end
	end,

	["the guided part hides the menus and brings them back one by one"] = function()
		local Steps = load()
		for _, item in { "Rank", "Money", "Inventory", "Abilities", "Shop", "FreeReward", "Offer" } do
			H.expect(not Steps.shows("Arrow", item) and not Steps.shows("Game1", item), item)
			H.expect(not Steps.shows("Result", item), item .. " hidden after game 1")
			H.expect(Steps.shows("Soft", item) and Steps.shows("Done", item), item .. " at the end")
			H.expect(Steps.shows("Skipped", item) and Steps.shows(nil, item), item .. " skipped")
		end
		H.expect(Steps.shows("Rank", "Rank") and Steps.shows("Rank", "Money"), "Rank's step")
		H.expect(not Steps.shows("Rank", "Inventory") and Steps.shows("Cues", "Inventory"), "")
		H.expect(not Steps.shows("Cues", "Abilities") and Steps.shows("Abilities", "Abilities"), "")
		H.expect(not Steps.shows("Abilities", "Shop"), "the Shop pops in with the soft part")
		H.expect(Steps.shows("Game1", "Settings"), "anything the tutorial does not hide shows")
		for item, from in Steps.Reveal do
			H.expect(Steps.index(from) > 0, item .. " comes back at a real step")
		end
	end,

	["hint and moment bits are marked once and never collide"] = function()
		local Steps = load()
		H.expect(#Steps.Hints <= 31 and #Steps.Seen <= 31, "fits a Flags number")
		H.expect(Steps.hintBit("Aim") == 1 and Steps.hintBit("Nope") == nil, "")
		for name in Steps.PoolHints do
			H.expect(Steps.hintBit(name) ~= nil, name .. " is a hint")
		end
		for name in Steps.ClientSeen do
			H.expect(Steps.seenBit(name) ~= nil, name .. " is a moment")
		end
		H.expect(
			not Steps.ClientSeen.QuestDone and not Steps.ClientSeen.Game2,
			"server-only moments"
		)
		local mask = 0
		H.expect(not Steps.has(mask, 3), "not yet")
		mask = Steps.mark(mask, 3)
		mask = Steps.mark(mask, 14)
		H.expect(Steps.has(mask, 3) and Steps.has(mask, 14) and not Steps.has(mask, 4), "")
		H.expect(Steps.mark(mask, 3) == mask, "marking twice changes nothing")
		H.expect(not Steps.has(nil, 1) and not Steps.has(-5, 1) and not Steps.has(0 / 0, 1), "junk")
	end,

	["every funnel fits Roblox's limits and names its steps once"] = function()
		local Steps = load()
		local Config = H.require("Config")
		H.expect(#Steps.Funnel <= 31, "onboarding fits a Flags number")
		H.expect(
			Steps.funnelNumber("Joined") == 1 and Steps.funnelNumber("ThirdMatch") == #Steps.Funnel,
			""
		)
		local funnels = 1 + 3 -- onboarding + Shop, Block, AbilitySpins
		for name, list in Steps.Funnels do
			funnels += 1
			H.expect(#list <= 31, name .. " fits a Flags number")
			H.expect(Config.Tutorial.Funnel.Once[name] ~= nil, name .. " has a Flags key")
			local seen = {}
			for _, step in list do
				H.expect(not seen[step], name .. " names " .. step .. " once")
				seen[step] = true
			end
		end
		H.expect(funnels <= 10, "Roblox allows 10 funnels")
		H.expect(
			Steps.funnelStep("PathS", "Won") ~= nil and Steps.funnelStep("PathS", "Nope") == nil,
			""
		)
	end,

	["Config's step timings name real steps"] = function()
		local Steps = load()
		local Config = H.require("Config")
		for step in Config.Tutorial.Timing.Fallback do
			H.expect(Steps.index(step) > 0, "Timing.Fallback." .. step .. " is a step")
		end
	end,

	["the step-name guard: every step name in src/ is a real step"] = function()
		local Steps = load()
		local bad = {}
		local count = 0
		for _, path in files("src", {}) do
			local source = fs.readFile(path)
			-- Only code that reads the tutorial's step can use a step name (other files have
			-- steps of their own: a cutscene's, a QA hook's).
			local reads = string.find(path, "Tutorial", 1, true)
				or string.find(source, "TutorialStep", 1, true)
				or string.find(source, "TutorialService", 1, true)
				or string.find(source, "Tutorial.Steps", 1, true)
				or string.find(source, "TutorialGames", 1, true)
			for _, use in if reads then used(source) else {} do
				count += 1
				if not Steps.known(use.name) then
					table.insert(bad, ("%s:%d %s"):format(path, use.line, use.name))
				end
			end
		end
		H.expect(count >= 30, "the scan finds the step names (" .. count .. ")")
		H.expect(#bad == 0, "not steps: " .. table.concat(bad, "; "))
	end,

	["the guard catches a step that does not exist"] = function()
		local Steps = load()
		local source = table.concat({
			'service.setStep(player, "Drop")',
			'if TutorialService.step(player) == "Queue" then',
			"local HOST_HIDES = {",
			'\tLobby = { "Rematch" },',
			"}",
		}, "\n")
		local names = {}
		for _, use in used(source) do
			if not Steps.known(use.name) then
				table.insert(names, use.name)
			end
		end
		table.sort(names)
		H.expect(
			table.concat(names, ",") == "Drop,Lobby,Queue",
			"found: " .. table.concat(names, ",")
		)
	end,
}
