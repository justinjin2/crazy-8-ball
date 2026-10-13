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

-- Runs `fn` with `skip` as the chain's skipped steps (Config.Tutorial.Chain.Skip), then puts
-- the Config's set back.
local function withSkip(skip: { [string]: boolean }, fn: (any) -> ())
	local Steps = load()
	local saved = Steps.Skip
	Steps.Skip = skip
	local ok, err = pcall(fn, Steps)
	Steps.Skip = saved
	if not ok then
		error(err, 0)
	end
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
	["the Win a Match quest's reward is a real lucky block (a Mystery, designer 2026-10-12)"] = function()
		local Config = H.require("Config")
		local soft = Config.Tutorial.Soft
		local kind = soft.QuestRewardBlock
		H.expect(kind == "Mystery", "a Mystery block, not money: " .. tostring(kind))
		H.expect((Config.LuckyBlocks.Kinds :: any)[kind] ~= nil, "a lucky block kind")
		H.expect(type((Config.LuckyBlocks.Kinds :: any)[kind].Icon) == "string", "its picture")
		H.expect(soft.QuestRewardMoney > 0, "money stays the fallback with no block set")
	end,
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
		withSkip({}, function()
			H.expect(Steps.after("Result") == "Rank" and Steps.after("Place") == "Cues", "")
		end)
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
		withSkip({}, function(Steps)
			H.expect(Steps.resume("Pad") == "Arrow" and Steps.resume("Game1") == "Arrow", "game 1")
			H.expect(Steps.resume("Result") == "Rank", "the result screens are gone")
			for _, step in { "Rank", "Mystery", "Place", "Cues", "Abilities", "Soft" } do
				H.expect(Steps.resume(step) == step, step .. " resumes where it was")
			end
		end)
	end,

	["the chain passes over the skipped steps (Rank, Cues: designer 2026-10-12)"] = function()
		local Steps = load()
		H.expect(Steps.Skip.Rank == true and Steps.Skip.Cues == true, "the Config's set")
		H.expect(Steps.after("Result") == "Mystery", "no forced claim in Rank")
		H.expect(Steps.after("Mystery") == "Place", "the Mystery block is still guided")
		H.expect(Steps.after("Place") == "Abilities", "no forced equip in Cues")
		H.expect(Steps.after("Abilities") == "Soft", "")
		-- A save at a skipped step (the update came out while they were there) goes on.
		H.expect(Steps.resume("Result") == "Mystery", "the result screens are gone")
		H.expect(Steps.resume("Rank") == "Mystery" and Steps.resume("Cues") == "Abilities", "")
		H.expect(
			Steps.load("Rank", 1, 1) == "Mystery" and Steps.load("Cues", 1, 1) == "Abilities",
			""
		)
		H.expect(Steps.load("Game1", 1, 1) == "Mystery", "game 1 won as the server stopped")
		H.expect(
			Steps.load("Drop", 1, 1) == "Mystery" and Steps.load("Equip", 1, 1) == "Abilities",
			""
		)
		for _, step in Steps.Order do
			H.expect(not Steps.Skip[Steps.resume(step)], step .. " never resumes at a skipped step")
			local nextStep = Steps.after(step)
			H.expect(
				nextStep and not Steps.Skip[nextStep],
				step .. " never moves to a skipped step"
			)
		end
		-- Their first-time hints count as done once the chain is past them.
		H.expect(#Steps.skippedHints("Result") == 0, "nothing skipped yet")
		local hints = table.concat(Steps.skippedHints("Mystery"), ",")
		H.expect(hints == "RankUp", "Rank's claim hint: " .. hints)
		hints = table.concat(Steps.skippedHints("Abilities"), ",")
		H.expect(hints == "RankUp,Cue", "and the equip hint: " .. hints)
		H.expect(table.concat(Steps.skippedHints("Soft"), ",") == "RankUp,Cue", "")
		H.expect(#Steps.skippedHints("Skipped") == 0 and #Steps.skippedHints(nil) == 0, "ends")
		-- The HUD items of a skipped step come with the next one.
		H.expect(Steps.forward("Rank") == "Mystery" and Steps.forward("Cues") == "Abilities", "")
		H.expect(Steps.forward("Soft") == "Soft" and Steps.forward("Done") == "Done", "")
		H.expect(Steps.shows("Mystery", "Rank") and Steps.shows("Mystery", "Money"), "")
		H.expect(
			not Steps.shows("Place", "Inventory") and Steps.shows("Abilities", "Inventory"),
			""
		)
		withSkip({}, function(S)
			H.expect(#S.skippedHints("Soft") == 0, "nothing skipped: every step teaches its own")
		end)
	end,

	["an old save's step is repaired (the migration map)"] = function()
		withSkip({}, function(Steps)
			H.expect(Steps.load("Drop", 1, 1) == "Rank", "v1's Drop bug: after game 1's win")
			H.expect(Steps.load("RareDrop", 1, 1) == "Rank", "")
			H.expect(
				Steps.load("Arrow1", 0, 0) == "Arrow" and Steps.load("Request", 0, 0) == "Arrow",
				""
			)
			H.expect(Steps.load("Game1", 0, 0) == "Arrow", "a v2 game 1 starts over")
			H.expect(
				Steps.load("Game1", 1, 1) == "Rank" and Steps.load("Pad", 1, 1) == "Rank",
				"game 1 won as the server stopped: on to Rank, not a second game 1"
			)
			H.expect(
				Steps.load("Arrow1", 2, 0) == "Done" and Steps.load("Request", 1, 1) == "Done",
				"a v1 save before game 1 that has played since never starts the tutorial"
			)
			H.expect(
				Steps.load("Equip", 1, 1) == "Cues" and Steps.load("Spin", 1, 1) == "Abilities",
				""
			)
			H.expect(
				Steps.load("Queue", 1, 1) == "Soft" and Steps.load("Nudges", 2, 1) == "Soft",
				""
			)
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
		end)
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
		for step, names in Steps.Taught do
			H.expect(Steps.guided(step), step .. " is a guided step")
			for _, name in names do
				H.expect(Steps.hintBit(name) ~= nil, step .. " teaches a real hint: " .. name)
			end
		end
		for name in Steps.ClientSeen do
			H.expect(Steps.seenBit(name) ~= nil, name .. " is a moment")
		end
		H.expect(
			not Steps.ClientSeen.QuestDone and not Steps.ClientSeen.Game2,
			"server-only moments"
		)
		-- The quest's reward (2026-10-12) came after the live saves' moments: their bits keep
		-- their meaning, and only the server marks it owed or paid.
		H.expect(Steps.seenBit("Played") == 18 and Steps.seenBit("QuestDone") == 13, "old bits")
		H.expect(Steps.seenBit("QuestOwed") == 19 and Steps.seenBit("QuestPaid") == 20, "new bits")
		H.expect(not Steps.ClientSeen.QuestOwed and not Steps.ClientSeen.QuestPaid, "server only")
		-- The soft part's pointer (2026-10-12): after the quest's bits, the client reports them.
		H.expect(
			Steps.seenBit("Pointer") == 21
				and Steps.seenBit("PointerRank") == 22
				and Steps.seenBit("PointerCues") == 23,
			"pointer bits"
		)
		H.expect(
			Steps.ClientSeen.Pointer
				and Steps.ClientSeen.PointerRank
				and Steps.ClientSeen.PointerCues,
			"the client reports the pointer"
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
