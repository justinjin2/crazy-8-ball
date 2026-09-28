--!strict
-- CaseOpening: the case opening overlay (docs/prompts/ECONOMY_UI_PROMPT.md section 11): a
-- full-screen overlay of its own (no dim beyond the roadmap's), over the menus.
-- - The reel: a strip of about 40 cue cards from the case's pool (drawn roughly by the odds;
--   purely visual) slides behind a gold marker and slows over about 4 s onto the prize the
--   server already chose (ItemState.request("ItemRequest", "OpenCase", caseId, 1)), a soft
--   tick per card (UISound ReelTick), a glow in the prize's rarity colour as it settles
--   (ReelSettle). Then the prize card pops (rays from Epic, confetti from Legendary): name,
--   rarity, "NEW!" or "Duplicate", "1,284 exist", Equip, Sell (duplicates only) and Open next
--   (while cases of that type remain) or Done. A tap skips to the result. Mythic and Secret
--   get a longer build-up (ReelBuild) and a shimmer.
-- - Fast Open (the FastOpen attribute): Open 10, a grid of ten result cards flipping over one
--   after another, rarest last, no reel.
-- - The first win's Rare Case reveal on the result screen uses the same reel.
-- While it is open the left column hides (Progression.update reads isOpen).
--
-- STUB (2026-09-28, overnight foundation): nothing is drawn yet; open() does nothing and
-- isOpen() is false. The reel is the next agent's.
local CaseOpening = {}
CaseOpening.__index = CaseOpening

--- The case opening (closed). `deps`: see InventoryMenu.new.
function CaseOpening.new(screen: ScreenGui, deps: any): any
	local self: any = setmetatable({}, CaseOpening)
	self.screen = screen
	self.deps = deps
	self.opened = false
	return self
end

--- Open cases on the reel: `caseId` and how many (1, or Config.Cases.FastOpenCount with Fast
--- Open). Stub: does nothing yet.
function CaseOpening.open(_self: any, _caseId: string, _count: number?) end

--- Play results the server already sent (a reply's `results`) on the reel (one) or the grid
--- (several). Stub: does nothing yet.
function CaseOpening.play(_self: any, _caseId: string, _results: { any }) end

--- The first win's Rare Case reveal inside `host` (the result screen): the same reel, onto
--- `prize` ({ case, cue, rarity, new }, MatchSummary.firstWin), then its card with Equip.
--- `opts.onDone` runs when the player is done with it. Stub: calls onDone at once.
function CaseOpening.reveal(_self: any, _host: GuiObject, _prize: any, opts: any?)
	if type(opts) == "table" and type(opts.onDone) == "function" then
		opts.onDone()
	end
end

function CaseOpening.close(self: any)
	self.opened = false
end

function CaseOpening.isOpen(self: any): boolean
	return self.opened
end

return CaseOpening
