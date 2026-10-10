--!strict
-- TutorialHints (client): tutorial v2's first-time hints, for everyone (docs/prompts/
-- TUTORIAL_V2_PROMPT.md 4.8; Tutorial/Steps.Hints). Each shows the first time its moment
-- happens, once, saved (the server's TutorialHints mask: done; TutorialHintsAgain: ignored
-- once): a pointer and a short line, no dim.
--
-- - In a match (Aim, Zoom, BallInHand, Eight, AbilityReady) a hint never pauses the clock,
--   never blocks the table and keeps off its middle: the line at the top, the hand on the HUD
--   (the power bar, the ability button) or none. Never in a rigged game (a tutorial bot at the
--   table, a game 1 skipped halfway included).
-- - In a quiet lobby (RankUp, Mystery, Block, Cue) the hand points at the Rank HUD, the block's
--   hotbar slot or Cues; in the Abilities screen (Abilities) at the code box, then SPIN.
--
-- A hint goes when it is done (the server marks some itself: Block, Cue, Abilities). It is
-- ignored when it times out (Config.Tutorial.Hints.IgnoredAfterSeconds) or its moment passes
-- undone, and may come back once, AgainAfterSeconds later (the second ignore is final). Every
-- outcome goes to the server (TutorialEvent "Hint": the Hint custom event).
--
-- Tutorial runs it whenever no guided step is on screen: after the tutorial or a skip, in a
-- fair first game (path R: its pool controls), in the soft part. Who gets them: players new
-- since tutorial v2 (the server marks all done for older saves; a skipper's pool controls at
-- the skip; each guided step those it teaches, Steps.Taught).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Strings = require(Shared.Strings)
local Steps = require(Shared.Tutorial.Steps)
local Camera = require(script.Parent.Camera)
local LuckyClient = require(script.Parent.LuckyClient)
local Menus = require(script.Parent.Menus)
local Progression = require(script.Parent.Progression)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local TutorialOverlay = require(script.Parent.TutorialOverlay)

local H = Config.Tutorial.Hints
local L = Config.Tutorial.Lessons
local Copy = Strings.Tutorial
local ULTS = Config.UI.UltScreen.Column.Name
local player = Players.LocalPlayer

local TutorialHints = {}

-- What Tutorial lends a hint to draw with.
export type View = {
	overlay: any,
	hand: any,
	words: (set: { [string]: string }, device: string) -> string,
}

-- What a hint sees each frame.
type Ctx = {
	s: any?, -- the snapshot of the table this player sits at, or nil
	myTurn: boolean, -- seated, in a game, and the shooter
	lobby: boolean, -- not seated, and nothing up (no menu, popup, reel or teleport screen)
}

type Hint = {
	name: string,
	-- Its moment is happening now (it may show).
	when: (ctx: Ctx) -> boolean,
	-- It was acted on (checked first, while it shows).
	done: ((ctx: Ctx) -> boolean)?,
	-- Its moment passed while it showed: "Done" (the act ends the moment), "Ignored", or nil
	-- (it just hides, to show again when the moment comes back).
	passed: string?,
	draw: (view: View, device: string) -> string,
}

local function attr(name: string): any
	return player:GetAttribute(name)
end

local function maskHas(name: string, n: number): boolean
	local mask = attr(name)
	return type(mask) == "number" and Steps.has(mask, n)
end

-- Acted on this session (the server's mask may lag a moment behind).
local doneHere: { [string]: boolean } = {}

local function isDone(name: string): boolean
	local n = Steps.hintBit(name)
	return doneHere[name] == true or (n ~= nil and maskHas("TutorialHints", n))
end

-- A tutorial bot plays at this table: the rigged game 1 (guided, or skipped halfway).
local function rigged(s: any): boolean
	for _, seat in s.seats or {} do
		if type(seat.bot) == "table" and seat.bot.kind == "Tutorial" then
			return true
		end
	end
	return false
end

-- The line only (the hand away).
local function line(view: View, text: string)
	view.overlay:dim(nil)
	view.hand:hide()
	view.overlay:say(text)
end

-- The hand on anchor `anchor` with the line (no dim); the line alone while it is off screen.
local function pointAt(view: View, anchor: string, text: string, place: string?)
	if TutorialAnchors.showing(anchor) then
		local target = TutorialOverlay.guiTarget(anchor)
		view.overlay:dim(target, false) -- no dim: the target only places a "Near" line
		view.hand:point(target)
	else
		view.overlay:dim(nil)
		view.hand:hide()
	end
	view.overlay:say(text, place)
end

-- Spins the Abilities screen can use now (held, or today's free one).
local function canSpin(): boolean
	local spins = attr("UltSpins")
	return (type(spins) == "number" and spins > 0) or attr("UltFreeSpin") == true
end

-- The code box's line: the code and its spins (Config.Daily.Codes).
local function codeText(): string
	local code: string = Config.Ults.CodeBanner.ActiveCode
	local row = Config.Daily.Codes[code]
	return Copy.Hint.AbilitiesCode:format(code, if row and row.Spins then row.Spins else 0)
end

-- The hints, the first whose moment happens shown first.
local HINTS: { Hint } = {
	{
		name = "Eight",
		when = function(ctx: Ctx): boolean
			return ctx.myTurn and ctx.s.phase == "PocketChoice"
		end,
		passed = "Done", -- a pocket was called
		draw = function(view: View, device: string): string
			line(view, view.words(Copy.Eight, device))
			return "Eight" .. device
		end,
	},
	{
		name = "BallInHand",
		when = function(ctx: Ctx): boolean
			return ctx.myTurn
				and ctx.s.phase == "Placement"
				and ctx.s.ballInHand == true
				and not ctx.s.breakShot
		end,
		passed = "Done", -- placed, or shot from where it lay
		draw = function(view: View, device: string): string
			line(view, view.words(Copy.BallInHand, device))
			return "BallInHand" .. device
		end,
	},
	{
		name = "AbilityReady",
		when = function(ctx: Ctx): boolean
			return ctx.myTurn
				and (ctx.s.phase == "Aiming" or ctx.s.phase == "Placement")
				and TutorialAnchors.flag("UltReady")
		end,
		done = function(ctx: Ctx): boolean
			return ctx.s ~= nil and not TutorialAnchors.flag("UltReady") -- used
		end,
		passed = "Ignored", -- shot without it
		draw = function(view: View, device: string): string
			view.overlay:dim(nil)
			if device == "gamepad" then
				view.hand:gesture("hold", (Enum.KeyCode :: any)[Config.UI.Ults.GamepadKey])
			else
				-- A small hand at the prompt's right end: the key it names stays in sight.
				local pad = Config.Tutorial.Lessons.PromptHandPadPx
				view.hand:point(TutorialOverlay.guiTarget("UltPrompt", pad), true, true)
			end
			view.overlay:say(
				view.words(Copy.Hint.AbilityReady, device):format(Config.UI.Ults.KeyboardKey)
			)
			return "AbilityReady" .. device
		end,
	},
	{
		name = "Aim",
		when = function(ctx: Ctx): boolean
			-- From the break (its placement turn may shoot at once) or any aiming turn.
			return ctx.myTurn
				and (ctx.s.phase == "Aiming" or (ctx.s.phase == "Placement" and ctx.s.breakShot))
		end,
		done = function(ctx: Ctx): boolean
			return ctx.s ~= nil and ctx.s.phase == "Resolving" and ctx.s.shooter == player.UserId
		end,
		passed = "Ignored",
		draw = function(view: View, device: string): string
			view.overlay:dim(nil)
			if device == "gamepad" then
				-- A fills the bar (R2 shoots, the line says).
				view.hand:gesture("hold", (Enum.KeyCode :: any)[Config.Input.Gamepad.Shoot.Up])
			else
				view.hand:gesture("pull", TutorialOverlay.guiTarget("PowerBar"))
			end
			view.overlay:say(view.words(Copy.Hint.Aim, device))
			return "Aim" .. device
		end,
	},
	{
		name = "Zoom",
		when = function(ctx: Ctx): boolean
			return ctx.myTurn
				and ctx.s.phase == "Aiming"
				and isDone("Aim") -- a later turn than the aim's
				and Camera.getZoom() < L.ZoomedOut
		end,
		done = function(_ctx: Ctx): boolean
			return Camera.getZoom() >= L.ZoomedOut
		end,
		passed = "Ignored",
		draw = function(view: View, device: string): string
			line(view, view.words(Copy.Hint.Zoom, device)) -- no hand: it would sit on the table
			return "Zoom" .. device
		end,
	},
	{
		name = "Abilities",
		when = function(_ctx: Ctx): boolean
			if not Menus.isOpen(ULTS) or TutorialAnchors.flag("UltSpinning") then
				return false
			end
			local code = attr("TutorialCodeUsed") ~= true and TutorialAnchors.showing("CodeBox")
			return code or (canSpin() and TutorialAnchors.showing("SpinButton"))
		end,
		done = function(_ctx: Ctx): boolean
			return TutorialAnchors.flag("UltSpinning") -- SPIN pressed
		end,
		passed = "Ignored", -- closed without a spin
		draw = function(view: View, _device: string): string
			if attr("TutorialCodeUsed") ~= true and TutorialAnchors.showing("CodeBox") then
				pointAt(view, "CodeBox", codeText(), "Near")
				return "AbilitiesCode"
			end
			pointAt(view, "SpinButton", Copy.Hint.AbilitiesSpin, "Near")
			return "AbilitiesSpin"
		end,
	},
	{
		name = "RankUp",
		when = function(ctx: Ctx): boolean
			return ctx.lobby and attr("RankPending") == true and TutorialAnchors.showing("Rank")
		end,
		done = function(_ctx: Ctx): boolean
			return attr("RankPending") ~= true or Menus.isOpen("Ranked")
		end,
		draw = function(view: View, _device: string): string
			pointAt(view, "Rank", Copy.Hint.RankUp)
			return "RankUp"
		end,
	},
	{
		name = "Mystery",
		when = function(ctx: Ctx): boolean
			return ctx.lobby and LuckyClient.readySlot(Config.Tutorial.MysteryKind) ~= nil
		end,
		done = function(_ctx: Ctx): boolean
			return LuckyClient.isOpen() -- its upgrade screen
		end,
		draw = function(view: View, _device: string): string
			local slot = LuckyClient.readySlot(Config.Tutorial.MysteryKind)
			pointAt(view, "HotbarSlot" .. tostring(slot), Copy.Hint.Mystery)
			return "Mystery" .. tostring(slot)
		end,
	},
	{
		name = "Block",
		when = function(ctx: Ctx): boolean
			return ctx.lobby and LuckyClient.firstReady(Config.Tutorial.MysteryKind) ~= nil
		end,
		done = function(_ctx: Ctx): boolean
			return LuckyClient.isOpen() -- its reel
		end,
		draw = function(view: View, device: string): string
			local text = view.words(Copy.Hint.Block, device)
			local held = LuckyClient.heldKind()
			if held and held ~= Config.Tutorial.MysteryKind then
				line(view, text) -- in hand: now place it
				return "BlockHeld" .. device
			end
			local slot = LuckyClient.firstReady(Config.Tutorial.MysteryKind)
			pointAt(view, "HotbarSlot" .. tostring(slot), text)
			return "Block" .. tostring(slot) .. device
		end,
	},
	{
		name = "Cue",
		when = function(ctx: Ctx): boolean
			-- Only once the block's reel and its reveal are over: the cue is granted at the open,
			-- and the hint must not tell what the reel lands on (the designer, 2026-10-09).
			local cue = attr("TutorialNewCue")
			return ctx.lobby
				and not LuckyClient.busy()
				and type(cue) == "string"
				and cue ~= attr("EquippedCue")
				and TutorialAnchors.showing("Inventory")
		end,
		draw = function(view: View, _device: string): string
			pointAt(view, "Inventory", Copy.Hint.Cue)
			return "Cue"
		end,
	},
}

-- The hint showing now, and when it began; when each was ignored this session.
local current: Hint? = nil
local currentAt = 0
local ignoredAt: { [string]: number } = {}

local function report(name: string, outcome: string)
	Net.get("TutorialEvent"):FireServer("Hint", { name = name, outcome = outcome })
end

-- Whether hint `name` may show: not done, and not ignored too lately.
local function open(name: string, now: number): boolean
	if Steps.hintBit(name) == nil or isDone(name) then
		return false
	end
	-- Ignored once: it may come back once, a while later (the server makes the second final).
	local at = ignoredAt[name]
	return at == nil or now - at >= H.AgainAfterSeconds
end

local function finish(outcome: string?, now: number)
	local hint = current
	if hint == nil then
		return
	end
	current = nil
	if outcome == "Done" then
		doneHere[hint.name] = true
		report(hint.name, "Done")
	elseif outcome == "Ignored" then
		ignoredAt[hint.name] = now
		report(hint.name, "Ignored")
	end
end

local function context(): Ctx
	local s = TutorialAnchors.match()
	local playing = s ~= nil and s.phase ~= "Waiting" and s.phase ~= "Result" and not rigged(s)
	return {
		s = s,
		myTurn = playing and s.shooter == player.UserId,
		lobby = s == nil and Progression.quiet() and not LuckyClient.isOpen(),
	}
end

--- Runs the hints for this frame (`allowed`: no guided step is on screen). Draws the one
--- showing with `view`'s overlay and hand; answers its key, or nil when none shows (Tutorial
--- then clears the line).
function TutorialHints.update(view: View, device: string, allowed: boolean): string?
	local now = os.clock()
	if not allowed then
		finish(nil, now)
		return nil
	end
	local ctx = context()
	local hint = current
	if hint then
		if hint.done and hint.done(ctx) then
			finish("Done", now)
		elseif not hint.when(ctx) then
			finish(hint.passed, now)
		elseif now - currentAt >= H.IgnoredAfterSeconds then
			finish("Ignored", now)
		elseif not open(hint.name, now) then
			finish(nil, now) -- the server marked it done meanwhile
		end
	end
	if current == nil then
		for _, candidate in HINTS do
			if open(candidate.name, now) and candidate.when(ctx) then
				current, currentAt = candidate, now
				report(candidate.name, "Shown")
				break
			end
		end
	end
	local showing = current
	return if showing then showing.draw(view, device) else nil
end

--- Studio QA (TutorialClientQA "hint"): the hint showing now, if any.
function TutorialHints.showing(): string?
	local hint = current
	return if hint then hint.name else nil
end

return TutorialHints
