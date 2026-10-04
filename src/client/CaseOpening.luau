--!strict
-- CaseOpening: opening cases (docs/prompts/ECONOMY_UI_PROMPT.md section 11; ECONOMY 7 and 18). A
-- full-screen overlay of its own over the menus (the menu under it stays open), on a soft
-- backdrop that is lighter over a menu, whose own slight dim is already there.
-- - One case: the reel (CaseOpeningReel). open() asks the server (ItemRequest "OpenCase"); the
--   strip is drawn from the case's pool by the odds (purely visual) and slows over about 4 s
--   onto the prize the server chose, ticking per card and glowing in the prize's colour as it
--   settles; Mythic and Secret get a longer build-up (ReelBuild) and a glow that builds in their
--   shimmer or red. Then the prize card (CaseOpeningCard) pops with the sting by rarity, rays
--   from Epic, confetti from Legendary: name, rarity, NEW! or Duplicate, "1,284 exist", and
--   a small Sell (SellCue 1; a confirm from ConfirmSellFrom up; the money flies into the HUD) and
--   Keep / Keep, open next (while cases of that type remain); no Equip (the Inventory). A cue
--   new to the Index reads "NEW! +$250" and its finder's money flies from that pill into the
--   HUD as the card pops (Fast Open: all of it from the grid once every card is up); the HUD
--   waits for it from the server's answer on, so the reel is never given away.
-- - Fast Open (a count above 1): the grid (CaseOpeningGrid), ten cards flipping over quickly,
--   rarest last, no reel; then Equip on a chosen card, Done, and Open 10 again while ten remain.
-- - The first win's case on the result screen: reveal() draws the same reel inside the result
--   screen's frame (fitted to it), then the prize card with Continue.
-- - A tap or click anywhere, or gamepad A, skips to the result; B or Escape skips, then closes.
--   While the server answers an open, none of them does anything for WaitCloseSeconds (the case
--   is being spent); after that they close, and a prize that arrives later shows a line in the
--   menu under it ("Your cue is in your Inventory."; its NEW tag marks it there).
--   The dev command /opencase reaches here as a DevNotice table { kind = "OpenCase", caseId,
--   count? } (string DevNotices are chat lines, Progression's).
-- GUI lane (2026-10-03, C11c/C11d): the overlay first shows the case big in front ("Click to
-- open"); a tap, click or A shakes it, cracks it open in a bright shine, and the reel (or
-- the grid) follows. While it opens, every other screen (the menu under it, the HUD) hides so
-- only the roll shows; they come back with the prize card or the finished grid. A Rare or
-- better prize plays its cutscene (PullCutscene) before its card; the overlay hides while it
-- plays and comes back with the card. The open is sent the moment the overlay opens, so the
-- answer is usually there when the case cracks.
-- The server decides everything: this sends ids and counts and animates the answers. While it
-- is open the left column hides and menus wait (Progression reads isOpen; a match starting
-- closes it). On closing, the gamepad goes back to what it was on if that still shows, else the
-- menu under it chooses (Menus.ensureSelection). Every control works
-- by touch, mouse and gamepad; laid out at a natural size and scaled to fit (phone first: the
-- reel and card fit 750 x 361 at full size). Tuning in Config.UI.CaseOpening, words in
-- Strings.CaseOpening.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local ProgressionRules = Shared:WaitForChild("Progression")
local Cases = require(ProgressionRules:WaitForChild("Cases"))
local Catalog = require(ProgressionRules:WaitForChild("Catalog"))
local Format = require(ProgressionRules:WaitForChild("Format"))
local CaseOpeningCard = require(script.Parent.CaseOpeningCard)
local CaseOpeningFx = require(script.Parent.CaseOpeningFx)
local CaseOpeningGrid = require(script.Parent.CaseOpeningGrid)
local CaseOpeningReel = require(script.Parent.CaseOpeningReel)
local CueAssets = require(script.Parent.CueAssets)
local CueThumb = require(script.Parent.CueThumb)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local PullCutscene = require(script.Parent.PullCutscene)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.CaseOpening
local INK = HudParts.tone("Ink")
local BACK_ACTION = "8ballCaseOpeningBack"
-- Over Menus' B (High + 20) and the roadmap's and result screen's (High + 10), under a confirm
-- dialog's (High + 30): B skips or closes this before anything else hears it.
local BACK_PRIORITY = Enum.ContextActionPriority.High.Value + C.BackPriorityAbove

type Result = CaseOpeningGrid.Result

-- One opening in progress: the overlay's, or the result screen's reveal.
type Session = {
	kind: string, -- "Overlay" or "Reveal"
	area: GuiObject, -- what the stage fills
	holder: Frame?, -- the reveal's own frame in the host (destroyed with the session)
	stage: CaseOpeningFx.Stage,
	title: Frame,
	titleIcon: ImageLabel,
	titleText: TextLabel,
	hint: Frame,
	hintGlyph: ImageLabel,
	hintText: TextLabel,
	focus: TextButton, -- clear and selectable: a gamepad's A on it skips
	-- "Intro" (the case in front), "Cracking", "Waiting", "Reel", "Cutscene", "Card", "Grid",
	-- "Failed", "Closed"
	phase: string,
	intro: { icon: ImageLabel, words: TextLabel, bob: any? }?,
	reply: any?, -- the server's answer, kept while the case is still in front
	cutsceneDone: boolean, -- this prize's cutscene has played
	waitSince: number, -- os.clock() when the open was sent (the Waiting phase began)
	closedWaiting: boolean, -- closed before the server answered (a late prize gets a line)
	caseId: string,
	count: number, -- 1, or Config.Cases.FastOpenCount
	heading: string?, -- the title's words, when not the case's name
	reel: any?,
	card: any?,
	grid: any?,
	result: Result?,
	token: number,
	dialog: MenuFrame.Dialog?,
	dialogUntil: number, -- Escape is ignored until then (a dialog just answered it)
	sold: boolean,
	held: number, -- finder's money the money HUD waits for (answered, not flown yet)
	saved: GuiObject?, -- the reveal's gamepad selection from before it
	onDone: (() -> ())?,
	connections: { RBXScriptConnection },
}

local CaseOpening = {}
CaseOpening.__index = CaseOpening

-- The first case (in Config.Cases.Order) holding a cue of `rarity`, and that cue: for the test
-- pulls (GuiQA "pull", /cutscene).
local function cueOfRarity(rarity: string): (string?, string?)
	for _, caseId in Config.Cases.Order do
		for _, entry in Cases.cueOdds(caseId) do
			if entry.rarity == rarity then
				return caseId, entry.id
			end
		end
	end
	return nil, nil
end

local function words(): any
	return Strings.CaseOpening
end

local function caseName(caseId: string): string
	local names: { [string]: string } = Strings.Items.Cases :: any
	return names[caseId] or caseId
end

local function valid(object: GuiObject?): boolean
	return object ~= nil and object:IsDescendantOf(game)
end

-- A selection worth going back to: still there, selectable and showing (it, every frame above
-- it and its ScreenGui). Never a case row's Open that went with the last case, nor an Open 10
-- hidden once fewer than ten are left.
local function usable(object: GuiObject?): boolean
	if object == nil or not valid(object) or not object.Selectable then
		return false
	end
	local node: Instance? = object
	while node and node:IsA("GuiObject") do
		if not node.Visible then
			return false
		end
		node = node.Parent
	end
	return not (node and node:IsA("LayerCollector") and not node.Enabled)
end

-- Whether a session waiting for the server has waited long enough that B, Escape or a tap may
-- close it.
local function mayCloseWaiting(s: Session): boolean
	return os.clock() - s.waitSince >= C.WaitCloseSeconds
end

-- The server's results, checked: known cues only, the rarity from the answer when it is a
-- real one (else the catalog's).
local function clean(results: any): { Result }
	local list: { Result } = {}
	if type(results) ~= "table" then
		return list
	end
	for _, entry in results do
		if type(entry) ~= "table" then
			continue
		end
		local row = Catalog.get(entry.cue)
		if not row then
			continue
		end
		local rarity = if type(entry.rarity) == "string"
				and Catalog.rarityRank(entry.rarity) > 0
			then entry.rarity
			else row.Rarity
		local count = if type(entry.count) == "number" then entry.count else nil
		local new = entry.new == true
		local found = if type(entry.found) == "number" and entry.found > 0
			then math.floor(entry.found)
			else 0
		table.insert(list, {
			cue = row.Id,
			rarity = rarity,
			new = new,
			duplicate = entry.duplicate == true or (not new and (count == nil or count > 1)),
			count = count,
			found = found,
		})
	end
	return list
end

--------------------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------------------

--- The case opening (closed). `deps`: Progression's shared table (money: MoneyHud, flyer,
--- column, rankHud; read when used).
function CaseOpening.new(screen: ScreenGui, deps: any): any
	local self: any = setmetatable({}, CaseOpening)
	self.screen = screen
	self.deps = deps
	self.opened = false
	self.overlay = nil :: Session?
	self.revealing = nil :: Session?
	self.token = 0
	self.saved = nil :: GuiObject?
	self.bound = false
	self.inputConnections = {} :: { RBXScriptConnection }
	self.backdropTween = nil :: Tween?
	self:build()
	self:listenDev()
	-- Studio checks: play a pull of a chosen rarity (the reel, its cutscene, the card) with a
	-- made-up result (nothing is given), and the intro with "intro".
	GuiQA.add("pull", function(rarity: string, count: number?)
		local caseId, cueId = cueOfRarity(rarity)
		if not caseId or not cueId then
			return "no case holds " .. tostring(rarity)
		end
		local results = {}
		for _ = 1, count or 1 do
			table.insert(results, { cue = cueId, rarity = rarity, count = 2 })
		end
		self:play(caseId, results)
		return cueId
	end)
	return self
end

-- The backdrop (its own ScreenGui over the whole screen, so no edge shows) and the overlay's
-- ScreenGui (inside the device's safe area) just above it, both over the menus.
function CaseOpening.build(self: any)
	local parent = self.screen.Parent
	local order = self.screen.DisplayOrder + C.DisplayOrderAbove
	local back = Instance.new("ScreenGui")
	back.Name = "CaseOpeningBackdrop"
	back.ResetOnSpawn = false
	back.IgnoreGuiInset = true
	back.ScreenInsets = Enum.ScreenInsets.None
	back.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	back.DisplayOrder = order
	back.Enabled = false
	back.Parent = parent
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Selectable = false
	backdrop.BorderSizePixel = 0
	backdrop.BackgroundColor3 = INK
	backdrop.BackgroundTransparency = 1
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = back
	backdrop.Activated:Connect(function()
		local s: Session? = self.overlay
		if s then
			self:tap(s)
		end
	end)
	self.backGui, self.backdrop = back, backdrop

	local gui = Instance.new("ScreenGui")
	gui.Name = "CaseOpening"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = order + 1
	gui.Enabled = false
	gui.Parent = parent
	local root = HudParts.frame(gui, "Root")
	root.Size = UDim2.fromScale(1, 1)
	-- The gamepad's selection stays inside while it is open.
	root.SelectionGroup = true
	root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	local area = HudParts.frame(root, "Area")
	area.Size = UDim2.fromScale(1, 1)
	self.gui, self.root, self.area = gui, root, area
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if self.opened then
			self:placeArea()
		end
	end)
end

-- On a tall screen the overlay stays under Roblox's top bar; a phone uses that row too.
function CaseOpening.placeArea(self: any)
	local height = self.root.AbsoluteSize.Y
	local inset = GuiService:GetGuiInset().Y
	local top = if height - inset >= C.ShortScreenPx then inset else 0
	self.area.Position = UDim2.fromOffset(0, top)
	self.area.Size = UDim2.new(1, 0, 1, -top)
end

-- /opencase: the server's DevNotice with a table opens that case here.
function CaseOpening.listenDev(self: any)
	task.spawn(function()
		local ok, remote = pcall(Net.get, "DevNotice")
		if not ok or typeof(remote) ~= "Instance" or not remote:IsA("RemoteEvent") then
			return
		end
		(remote :: RemoteEvent).OnClientEvent:Connect(function(payload: any)
			if type(payload) ~= "table" then
				return
			end
			if payload.kind == "OpenCase" and type(payload.caseId) == "string" then
				self:open(
					payload.caseId,
					if type(payload.count) == "number" then payload.count else 1
				)
			elseif payload.kind == "Cutscene" and type(payload.rarity) == "string" then
				-- /cutscene: the pull cutscene alone, on a cue of that rarity (nothing given).
				local _, cueId = cueOfRarity(payload.rarity)
				if cueId and not PullCutscene.isPlaying() then
					PullCutscene.play(payload.rarity, cueId, function() end)
				end
			end
		end)
	end)
end

-- A session's stage and its shared parts: the title (the chest and the case's name), the hint
-- line and the clear focus button a gamepad's A skips with.
function CaseOpening.newSession(self: any, kind: string, area: GuiObject, caseId: string): Session
	local stage = CaseOpeningFx.stage(area, "Stage")
	stage.frame.ZIndex = 2
	local focus = Instance.new("TextButton")
	focus.Name = "Skip"
	focus.Text = ""
	focus.AutoButtonColor = false
	focus.BackgroundTransparency = 1
	focus.BorderSizePixel = 0
	focus.Selectable = false
	focus.SelectionImageObject = CaseOpeningFx.noBox()
	focus.Size = UDim2.fromScale(1, 1)
	focus.ZIndex = 1
	focus.Parent = stage.frame
	local title = HudParts.frame(stage.frame, "Title")
	title.ZIndex = 4
	local titleIcon = HudParts.icon(title, "Case", "Chest")
	titleIcon.ZIndex = 1
	local titleText = HudParts.text(title, "Words", C.TitlePx, "")
	titleText.TextWrapped = false
	titleText.ZIndex = 2
	local hint = HudParts.frame(stage.frame, "Hint")
	hint.ZIndex = 4
	local hintGlyph = Instance.new("ImageLabel")
	hintGlyph.Name = "Glyph"
	hintGlyph.BackgroundTransparency = 1
	hintGlyph.ScaleType = Enum.ScaleType.Fit
	hintGlyph.ZIndex = 1
	hintGlyph.Parent = hint
	local hintText = HudParts.text(hint, "Words", C.HintPx, "")
	hintText.TextWrapped = false
	hintText.ZIndex = 2
	local s: Session = {
		kind = kind,
		area = area,
		holder = nil,
		stage = stage,
		title = title,
		titleIcon = titleIcon,
		titleText = titleText,
		hint = hint,
		hintGlyph = hintGlyph,
		hintText = hintText,
		focus = focus,
		phase = "Waiting",
		intro = nil,
		reply = nil,
		cutsceneDone = false,
		waitSince = os.clock(),
		closedWaiting = false,
		caseId = caseId,
		count = 1,
		heading = nil,
		reel = nil,
		card = nil,
		grid = nil,
		result = nil,
		token = 0,
		dialog = nil,
		dialogUntil = 0,
		sold = false,
		held = 0,
		saved = nil,
		onDone = nil,
		connections = {},
	}
	focus.Activated:Connect(function()
		self:tap(s)
	end)
	table.insert(
		s.connections,
		area:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:layout(s)
		end)
	)
	-- The inventory changed (the case count, the equipped cue): the buttons follow.
	table.insert(
		s.connections,
		ItemState.Changed.Items:Connect(function()
			self:refresh(s)
		end)
	)
	table.insert(
		s.connections,
		UserInputService.LastInputTypeChanged:Connect(function()
			self:refreshHint(s)
			if CaseOpeningFx.gamepad() then
				-- After a menu under it has put the gamepad on its own tab.
				task.defer(function()
					self:focus(s)
				end)
			end
		end)
	)
	return s
end

-- Take a session's views down (the reel, the card, the grid).
function CaseOpening.clearViews(self: any, s: Session)
	if s.dialog then
		local dialog = s.dialog
		s.dialog = nil
		dialog.cancel()
	end
	for _, key in { "reel", "card", "grid" } do
		local view = (s :: any)[key]
		if view then
			view:destroy();
			(s :: any)[key] = nil
		end
	end
	s.result = nil
	s.sold = false
	-- Finder's money that never got to fly: the HUD stops waiting and settles.
	if s.held > 0 then
		local money = self.deps and self.deps.money
		if money then
			money:release(s.held)
		end
		s.held = 0
	end
end

-- The HUD waits for finder's money the answer paid until its chip flies (flyFound).
function CaseOpening.holdFound(self: any, s: Session, amount: number)
	local money = self.deps and self.deps.money
	if amount > 0 and money then
		money:expect(amount)
		s.held += amount
	end
end

-- Finder's money flies from `from` (absolute pixels) into the money HUD: the HUD stops waiting
-- for the held amount here and waits for the chip instead.
function CaseOpening.flyFound(self: any, s: Session, from: Vector2, amount: number)
	local money = self.deps and self.deps.money
	local n = math.min(amount, s.held)
	if n <= 0 or not money or s.phase == "Closed" then
		return
	end
	s.held -= n
	money:release(n)
	local layer: GuiObject = if s.kind == "Reveal" and s.holder then s.holder else self.root
	CaseOpeningFx.flyCash(layer, from, n, money, s.stage.scale.Scale)
end

function CaseOpening.destroySession(self: any, s: Session)
	s.phase = "Closed"
	self:clearViews(s)
	for _, connection in s.connections do
		connection:Disconnect()
	end
	table.clear(s.connections)
	s.stage.frame:Destroy()
	if s.holder then
		s.holder:Destroy()
	end
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

-- The title's words: the heading given, or the case's name (with the count for Fast Open).
function CaseOpening.titleWords(_self: any, s: Session): string
	if s.heading then
		return s.heading
	end
	if s.count > 1 then
		return string.format(words().FastTitle, caseName(s.caseId), Format.commas(s.count))
	end
	return caseName(s.caseId)
end

-- A gamepad button's picture ("" when Roblox has none).
local function glyphFor(key: Enum.KeyCode): string
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode(key)
	end)
	return if ok and type(image) == "string" then image else ""
end

-- The hint under the reel: "Opening..." while the server answers (how to close, once that is
-- allowed), else how to skip.
function CaseOpening.refreshHint(self: any, s: Session)
	if s.phase == "Closed" then
		return
	end
	local W = words()
	local text, glyph = W.Opening, ""
	if s.phase == "Intro" then
		if CaseOpeningFx.gamepad() then
			text, glyph = W.OpenPad, glyphFor(Enum.KeyCode.ButtonA)
		elseif CaseOpeningFx.touch() then
			text = W.OpenTouch
		else
			text = W.OpenMouse
		end
	elseif s.phase == "Cracking" then
		text = W.Opening
	elseif s.phase == "Waiting" then
		if mayCloseWaiting(s) then
			if CaseOpeningFx.gamepad() then
				text, glyph = W.WaitingPad, glyphFor(Enum.KeyCode.ButtonB)
			elseif CaseOpeningFx.touch() then
				text = W.WaitingTouch
			else
				text = W.WaitingMouse
			end
		end
	elseif CaseOpeningFx.gamepad() then
		text, glyph = W.SkipPad, glyphFor(Enum.KeyCode.ButtonA)
	elseif CaseOpeningFx.touch() then
		text = W.SkipTouch
	else
		text = W.SkipMouse
	end
	s.hintText.Text = text
	s.hintGlyph.Image = glyph
	self:layoutHint(s)
end

function CaseOpening.layoutHint(_self: any, s: Session)
	local h = C.HintHeightPx
	local glyph = s.hintGlyph.Image ~= ""
	local textW = math.ceil(CaseOpeningFx.textWidth(s.hintText.Text, C.HintPx)) + 6
	local glyphW = if glyph then h + C.HintGlyphGapPx else 0
	local width = glyphW + textW
	s.hintGlyph.Visible = glyph
	s.hintGlyph.Size = UDim2.fromOffset(h, h)
	s.hintText.Position = UDim2.fromOffset(glyphW, 0)
	s.hintText.Size = UDim2.fromOffset(textW, h)
	local x = s.hint.Position.X.Offset
	s.hint.AnchorPoint = Vector2.new(0.5, 0)
	s.hint.Position = UDim2.fromOffset(x, s.hint.Position.Y.Offset)
	s.hint.Size = UDim2.fromOffset(width, h)
end

-- The title row centred at `y`: the chest, then the words.
function CaseOpening.layoutTitle(self: any, s: Session, width: number, y: number)
	local h = C.TitleHeightPx
	local text = self:titleWords(s)
	s.titleText.Text = text
	HudParts.setIcon(s.titleIcon, "Case" .. s.caseId)
	if s.titleIcon.Image == "" then
		HudParts.setIcon(s.titleIcon, "Case")
	end
	local iconSize = math.floor(h * C.TitleIconShare)
	local room = width - 2 * C.MarginPx - iconSize - C.TitleGapPx
	local textW =
		math.max(1, math.min(room, math.ceil(CaseOpeningFx.textWidth(text, C.TitlePx)) + 8))
	local total = iconSize + C.TitleGapPx + textW
	s.title.AnchorPoint = Vector2.new(0.5, 0)
	s.title.Position = UDim2.fromOffset(math.floor(width / 2), math.floor(y))
	s.title.Size = UDim2.fromOffset(total, h)
	s.titleIcon.Size = UDim2.fromOffset(iconSize, iconSize)
	s.titleIcon.Position = UDim2.fromOffset(0, math.floor((h - iconSize) / 2))
	s.titleText.Position = UDim2.fromOffset(iconSize + C.TitleGapPx, 0)
	s.titleText.Size = UDim2.fromOffset(textW, h)
end

--- Fit the session's stage to its area and place what its phase shows.
function CaseOpening.layout(self: any, s: Session)
	if s.phase == "Closed" then
		return
	end
	local reveal = s.kind == "Reveal"
	local minScale = if reveal then C.RevealMinScale else C.MinScale
	local maxScale = if reveal then C.RevealMaxScale else C.MaxScale
	local margin = C.MarginPx
	local titleH, gap, hintH = C.TitleHeightPx, C.GapPx, C.HintHeightPx
	local stage = s.stage
	local card, grid, reel = s.card, s.grid, s.reel
	if s.phase == "Card" and card then
		local size: Vector2 = card:size()
		local natural =
			stage.fit(size + Vector2.new(2, 2) * C.CardMarginPx, minScale, maxScale, margin)
		card.root.Position = UDim2.fromOffset(math.floor(natural.X / 2), math.floor(natural.Y / 2))
		s.title.Visible = false
		s.hint.Visible = false
		return
	end
	if s.phase == "Grid" and grid then
		local size: Vector2 = grid:size()
		local need = Vector2.new(math.max(size.X, C.TitleMinWidthPx), titleH + gap + size.Y)
		local natural = stage.fit(need, minScale, maxScale, margin)
		local top = math.floor((natural.Y - need.Y) / 2)
		self:layoutTitle(s, natural.X, top)
		s.title.Visible = true
		grid.root.Position =
			UDim2.fromOffset(math.floor(natural.X / 2), top + titleH + gap + math.floor(size.Y / 2))
		s.hint.Visible = false
		return
	end
	-- The case in front: the title, the big chest, the hint line.
	local intro = s.intro
	if (s.phase == "Intro" or s.phase == "Cracking") and intro then
		local I = C.Intro
		local need = Vector2.new(C.StageMinWidthPx, titleH + gap + I.ChestPx + gap + hintH)
		local natural = stage.fit(need, minScale, maxScale, margin)
		local top = math.floor((natural.Y - need.Y) / 2)
		self:layoutTitle(s, natural.X, top)
		s.title.Visible = true
		local y = top + titleH + gap
		if intro.bob then
			intro.bob.stop()
		end
		intro.icon.Size = UDim2.fromOffset(I.ChestPx, I.ChestPx)
		intro.icon.Position =
			UDim2.fromOffset(math.floor(natural.X / 2), y + math.floor(I.ChestPx / 2))
		if s.phase == "Intro" then
			intro.bob = UIAnim.bob(intro.icon)
		end
		y += I.ChestPx + gap
		if reel then
			reel.root.Visible = false
		end
		s.hint.Position = UDim2.fromOffset(math.floor(natural.X / 2), y)
		s.hint.Visible = true
		self:refreshHint(s)
		return
	end
	if reel then
		reel.root.Visible = true
	end
	-- Waiting, the reel, or a failure: the title, the reel (one case), the hint line.
	local reelH = if reel then CaseOpeningReel.height() else 0
	local reelGap = if reel then gap else 0
	local needW = if reveal then C.RevealMinWidthPx else C.StageMinWidthPx
	local need = Vector2.new(needW, titleH + gap + reelH + reelGap + hintH)
	local natural = stage.fit(need, minScale, maxScale, margin)
	local top = math.floor((natural.Y - need.Y) / 2)
	self:layoutTitle(s, natural.X, top)
	s.title.Visible = true
	local y = top + titleH + gap
	if reel then
		local width = math.min(natural.X - 2 * C.ReelSideMarginPx, C.Reel.MaxWidthPx)
		reel:layout(math.max(C.Reel.MinWidthPx, width))
		reel.root.Position = UDim2.fromOffset(math.floor(natural.X / 2), y + math.floor(reelH / 2))
		y += reelH + reelGap
	end
	s.hint.Position = UDim2.fromOffset(math.floor(natural.X / 2), y)
	s.hint.Visible = true
	self:refreshHint(s)
end

--------------------------------------------------------------------------------------------
-- Phases, focus and input
--------------------------------------------------------------------------------------------

function CaseOpening.setPhase(self: any, s: Session, phase: string)
	s.phase = phase
	self:layout(s)
	self:focus(s)
end

--- Put a gamepad's selection where it belongs now: the clear skip button while something
--- turns or waits, the card's or grid's button once it has settled. Only with a gamepad in
--- use (a mouse or touch never gets a selection), never over a confirm dialog.
function CaseOpening.focus(_self: any, s: Session)
	if s.phase == "Closed" then
		return
	end
	local card, grid = s.card, s.grid
	local skipping = s.phase == "Intro"
		or s.phase == "Cracking"
		or s.phase == "Waiting"
		or s.phase == "Reel"
		or s.phase == "Failed"
		or (s.phase == "Grid" and grid ~= nil and grid:isFlipping())
	s.focus.Selectable = skipping
	if not CaseOpeningFx.gamepad() or s.dialog then
		return
	end
	if skipping then
		GuiService.SelectedObject = s.focus
	elseif s.phase == "Card" and card then
		GuiService.SelectedObject = card:focusButton()
	elseif s.phase == "Grid" and grid then
		GuiService.SelectedObject = grid:focusButton()
	end
end

-- The session B and Escape talk to: the reveal while one runs, else the overlay.
function CaseOpening.active(self: any): Session?
	return self.revealing or self.overlay
end

-- B (and LB, RB, kept from the menu under it) while a session is up; Escape too.
function CaseOpening.bindInput(self: any)
	if self.bound then
		return
	end
	self.bound = true
	ContextActionService:BindActionAtPriority(
		BACK_ACTION,
		function(_name: string, state: Enum.UserInputState, input: InputObject)
			if state == Enum.UserInputState.Begin and input.KeyCode == Enum.KeyCode.ButtonB then
				local s = self:active()
				if s then
					self:back(s)
				end
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		BACK_PRIORITY,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1
	)
	table.insert(
		self.inputConnections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode ~= Enum.KeyCode.Escape then
				return
			end
			local s = self:active()
			if not s or s.dialog or os.clock() < s.dialogUntil then
				return -- a confirm dialog answers this press itself
			end
			Menus.swallowEscape(input) -- the menu under the overlay stays open
			self:back(s)
		end)
	)
end

function CaseOpening.unbindInput(self: any)
	if not self.bound or self:active() then
		return
	end
	self.bound = false
	ContextActionService:UnbindAction(BACK_ACTION)
	for _, connection in self.inputConnections do
		connection:Disconnect()
	end
	table.clear(self.inputConnections)
end

-- A tap, click or A: skip what is turning (or close a failure, or a wait that has run long).
function CaseOpening.tap(self: any, s: Session)
	local reel, grid = s.reel, s.grid
	if s.phase == "Intro" then
		self:crack(s)
	elseif s.phase == "Reel" and reel then
		reel:skip()
	elseif s.phase == "Grid" and grid and grid:isFlipping() then
		grid:skip()
	elseif s.phase == "Failed" or (s.phase == "Waiting" and mayCloseWaiting(s)) then
		self:finish(s)
	end
end

-- B or Escape: skip what is turning, else close (not in the first moments of a wait: the case
-- is being spent and its reel is on its way).
function CaseOpening.back(self: any, s: Session)
	if
		s.dialog
		or s.phase == "Cutscene" -- the cutscene answers B itself
		or s.phase == "Cracking"
		or (s.phase == "Waiting" and not mayCloseWaiting(s))
	then
		return
	end
	local grid = s.grid
	if s.phase == "Reel" or (s.phase == "Grid" and grid and grid:isFlipping()) then
		self:tap(s)
	else
		self:finish(s)
	end
end

-- The player is done with a session: the overlay closes, the reveal hands back.
function CaseOpening.finish(self: any, s: Session)
	if s.kind == "Reveal" then
		self:endReveal(s, true)
	elseif self.overlay == s then
		self:close()
	end
end

--------------------------------------------------------------------------------------------
-- Opening
--------------------------------------------------------------------------------------------

-- Open the overlay (if it is not up) on `caseId` and return its session, its views cleared.
function CaseOpening.show(self: any, caseId: string): Session
	local s: Session? = self.overlay
	if not self.opened then
		self.opened = true
		local selected = GuiService.SelectedObject
		self.saved = selected
		self.backGui.Enabled = true
		self.gui.Enabled = true
		self.backdrop.Modal = true -- frees a mouse that shift-lock (or the camera) holds
		self:placeArea()
		if self.backdropTween then
			self.backdropTween:Cancel()
		end
		local over = if Menus.isOpen()
			then C.BackdropOverMenuTransparency
			else C.BackdropTransparency
		self.backdropTween = TweenService:Create(
			self.backdrop,
			TweenInfo.new(C.BackdropSeconds),
			{ BackgroundTransparency = over }
		)
		self.backdropTween:Play()
		self:bindInput()
	end
	self:hideOthers()
	if not s then
		s = self:newSession("Overlay", self.area, caseId)
		self.overlay = s
	end
	local session = s :: Session
	self:clearViews(session)
	session.caseId = caseId
	session.heading = nil
	return session
end

--- Open cases on the reel: `caseId` and how many (1, or Config.Cases.FastOpenCount with Fast
--- Open). Sends ItemRequest "OpenCase" itself and plays the answer; a refusal shows its reason
--- and closes. Ignored while a reel or the grid is still turning.
function CaseOpening.open(self: any, caseId: string, count: number?)
	if type(caseId) ~= "string" or Cases.get(caseId) == nil then
		return
	end
	local n = if type(count) == "number" and count > 1 then Config.Cases.FastOpenCount else 1
	local current: Session? = self.overlay
	if current then
		local grid = current.grid
		if
			current.phase == "Waiting"
			or current.phase == "Reel"
			or (current.phase == "Grid" and grid and grid:isFlipping())
		then
			return -- one at a time
		end
	end
	local s = self:show(caseId)
	s.count = n
	s.reply = nil
	if n == 1 then
		s.reel = CaseOpeningReel.new(s.stage.frame, caseId)
		s.reel.root.ZIndex = 3
	end
	s.waitSince = os.clock()
	self:startIntro(s)
	self.token += 1
	local token = self.token
	s.token = token
	-- A slow answer: the hint says how to close once that is allowed.
	task.delay(C.WaitCloseSeconds, function()
		if s.phase == "Waiting" and s.token == token then
			self:refreshHint(s)
		end
	end)
	task.spawn(function()
		local reply = ItemState.request("ItemRequest", "OpenCase", caseId, n)
		if
			self.overlay == s
			and s.token == token
			and (s.phase == "Intro" or s.phase == "Cracking")
		then
			s.reply = reply -- played once the case has cracked open
			return
		end
		if self.overlay ~= s or s.token ~= token or s.phase ~= "Waiting" then
			-- Closed, or opened again, while it was on its way. Closed while waiting: the prize
			-- is in the inventory all the same, so the menu under it says so.
			if s.closedWaiting and s.token == token and reply.ok == true then
				local W = words()
				Menus.notice(if n > 1 then W.LateMany else W.LateOne, "Green")
			end
			return
		end
		self:answer(s, caseId, reply)
	end)
end

-- The server's answer to an open, on screen: its reason, or the reel or grid.
function CaseOpening.answer(self: any, s: Session, caseId: string, reply: any)
	if reply.ok ~= true then
		self:fail(s, reply)
		return
	end
	local id = if type(reply.caseId) == "string" and Cases.get(reply.caseId)
		then reply.caseId
		else caseId
	self:playIn(s, id, reply.results)
end

-- The case in front, big and bobbing: "Click to open".
function CaseOpening.startIntro(self: any, s: Session)
	if s.intro then
		s.intro.icon:Destroy()
		s.intro = nil
	end
	local icon = HudParts.icon(s.stage.frame, "Case" .. s.caseId, "IntroChest")
	if icon.Image == "" then
		HudParts.setIcon(icon, "Case")
	end
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.ZIndex = 3
	s.intro = { icon = icon, words = s.hintText, bob = nil }
	self:setPhase(s, "Intro")
	UIAnim.popIn(icon)
end

-- Opened: it shakes harder and harder, cracks in a bright shine, and the roll follows.
function CaseOpening.crack(self: any, s: Session)
	local intro = s.intro
	if s.phase ~= "Intro" or not intro then
		return
	end
	local I = C.Intro
	self:setPhase(s, "Cracking")
	if intro.bob then
		intro.bob.stop()
		intro.bob = nil
	end
	UISound.play("ReelBuild")
	local icon = intro.icon
	local born = os.clock()
	local base = icon.Size
	local shaking: RBXScriptConnection? = nil
	shaking = RunService.RenderStepped:Connect(function()
		local t = os.clock() - born
		if (s.phase :: string) ~= "Cracking" or not icon.Parent then
			if shaking then
				shaking:Disconnect()
			end
			return
		end
		local u = math.clamp(t / I.ShakeSeconds, 0, 1)
		icon.Rotation = I.ShakeDegrees * u * math.sin(t * I.ShakeSpeed)
		icon.Size = UDim2.fromOffset(
			base.X.Offset * (1 + I.SwellShare * u),
			base.Y.Offset * (1 + I.SwellShare * u)
		)
		if u >= 1 then
			if shaking then
				shaking:Disconnect()
			end
			icon.Rotation = 0
			UIAnim.glowBurst(icon, HudParts.tone("Gold"), I.BurstReach)
			UISound.play("ReelSettle")
			self:flashStage(s)
			UIAnim.popOut(icon, function()
				icon:Destroy()
			end)
			task.delay(I.AfterBurstSeconds, function()
				if (s.phase :: string) ~= "Cracking" then
					return
				end
				s.intro = nil
				self:setPhase(s, "Waiting")
				local reply = s.reply
				s.reply = nil
				if reply then
					self:answer(s, s.caseId, reply)
				end
			end)
		end
	end)
end

-- A bright white shine over the stage as the case bursts open.
function CaseOpening.flashStage(_self: any, s: Session)
	local flash = Instance.new("Frame")
	flash.Name = "Shine"
	flash.BorderSizePixel = 0
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 0.15
	flash.AnchorPoint = Vector2.new(0.5, 0.5)
	flash.Position = UDim2.fromScale(0.5, 0.5)
	flash.Size = UDim2.fromScale(3, 3)
	flash.ZIndex = 8
	flash.Parent = s.stage.frame
	local tween = TweenService:Create(
		flash,
		TweenInfo.new(C.Intro.ShineSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	tween.Completed:Once(function()
		flash:Destroy()
	end)
	tween:Play()
end

-- Every other screen of ours hides while a case opens (only the roll shows) and comes back
-- with the prize card, the finished grid or the overlay closing.
function CaseOpening.hideOthers(self: any)
	if self.hiddenGuis then
		return
	end
	local hidden = {}
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, gui in playerGui:GetChildren() do
			if
				gui:IsA("ScreenGui")
				and gui.Enabled
				and gui ~= self.gui
				and gui ~= self.backGui
				and gui.Name ~= "PullCutscene"
				and gui.Name ~= "Freecam"
			then
				gui.Enabled = false
				table.insert(hidden, gui)
			end
		end
	end
	self.hiddenGuis = hidden
end

function CaseOpening.showOthers(self: any)
	local hidden = self.hiddenGuis
	self.hiddenGuis = nil
	if hidden then
		for _, gui in hidden do
			if gui.Parent then
				gui.Enabled = true
			end
		end
	end
end

--- Play results the server already sent (an OpenCase reply's `results`): the reel for one, the
--- grid for several. Opens the overlay if it is not up.
function CaseOpening.play(self: any, caseId: string, results: { any })
	if type(caseId) ~= "string" then
		return
	end
	local current: Session? = self.overlay
	if current and (current.phase == "Reel" or current.phase == "Grid") then
		self:clearViews(current)
	end
	local s = self:show(caseId)
	self.token += 1
	s.token = self.token
	s.count = if type(results) == "table" and #results > 1 then #results else 1
	self:playIn(s, caseId, results)
end

-- Put an answer on screen: the reel onto one prize, or the grid.
function CaseOpening.playIn(self: any, s: Session, caseId: string, results: any)
	local list = clean(results)
	if #list == 0 then
		self:fail(s, "Default")
		return
	end
	s.caseId = caseId
	local found = 0
	for _, result in list do
		found += result.found or 0
		-- Download the won cue's look while the reel spins, so Equip shows it at once.
		CueAssets.preload(result.cue)
	end
	self:holdFound(s, found)
	if #list == 1 then
		local result = list[1]
		s.result = result
		s.cutsceneDone = false
		s.count = 1
		local old = s.reel
		local reel: any = old
		if not old or old.caseId ~= caseId or old:isSpinning() then
			if old then
				old:destroy()
			end
			reel = CaseOpeningReel.new(s.stage.frame, caseId)
			reel.root.ZIndex = 3
			s.reel = reel
		end
		reel:setPrize(result.cue, result.rarity)
		self:setPhase(s, "Reel")
		reel:start(function()
			self:showCard(s)
		end)
		return
	end
	if s.reel then
		s.reel:destroy()
		s.reel = nil
	end
	s.count = #list
	local grid = CaseOpeningGrid.new(s.stage.frame, caseId, list, {
		onEquip = function(result: Result)
			self:equip(s, result.cue)
		end,
		onDone = function()
			self:finish(s)
		end,
		onAgain = function()
			self:open(s.caseId, Config.Cases.FastOpenCount)
		end,
		onFlipped = function()
			self:showOthers()
			self:refresh(s)
			self:focus(s)
			local frame = s.stage.frame
			self:flyFound(s, frame.AbsolutePosition + frame.AbsoluteSize / 2, s.held)
		end,
	})
	grid.onResize = function()
		self:layout(s)
	end
	s.grid = grid
	grid:setEquipped(ItemState.equipped())
	grid:start() -- turning from now on, so a gamepad's A lands on the skip button
	self:setPhase(s, "Grid")
end

-- The reel settled: the prize card pops in its place.
function CaseOpening.showCard(self: any, s: Session)
	local result = s.result
	if s.phase ~= "Reel" or not result then
		return
	end
	-- A Rare or better pull plays its cutscene first; the overlay hides while it plays.
	if s.kind == "Overlay" and not s.cutsceneDone and PullCutscene.has(result.rarity) then
		s.cutsceneDone = true
		s.phase = "Cutscene"
		self.gui.Enabled = false
		self.backGui.Enabled = false
		PullCutscene.play(result.rarity, result.cue, function()
			if self.overlay ~= s or (s.phase :: string) ~= "Cutscene" then
				return
			end
			self.gui.Enabled = true
			self.backGui.Enabled = true
			s.phase = "Reel"
			self:showCard(s)
		end)
		return
	end
	if s.kind == "Overlay" then
		self:showOthers()
	end
	local card = CaseOpeningCard.new(s.stage.frame, {
		caseId = s.caseId,
		cue = result.cue,
		rarity = result.rarity,
		new = result.new,
		duplicate = result.duplicate,
		count = result.count,
		found = result.found,
	}, {
		reveal = s.kind == "Reveal",
		onSell = function()
			self:sell(s)
		end,
		onNext = function()
			self:open(s.caseId, 1)
		end,
		onDone = function()
			self:finish(s)
		end,
	})
	s.card = card
	card:setSell("Ready", Cases.sellValue(result.cue))
	self:refresh(s)
	-- The reel goes as the card pops over its place (the stage is fitted to the card now).
	local reel = s.reel
	s.reel = nil
	if reel then
		reel:destroy()
	end
	self:setPhase(s, "Card")
	card:show(s.stage.frame, card:artCentre())
	local found = result.found or 0
	if found > 0 then
		task.delay(C.FoundFlyDelaySeconds, function()
			if s.card == card then
				self:flyFound(s, card:foundPoint(), found)
			end
		end)
	end
end

-- An open that did not work: its reason on a notice, then the overlay closes by itself (a tap
-- or B closes it sooner).
function CaseOpening.fail(self: any, s: Session, reply: any)
	self:setPhase(s, "Failed")
	s.hint.Visible = false
	MenuFrame.showNotice(s.stage.frame, MenuFrame.reason(reply), "Red")
	local token = s.token
	task.delay(C.FailCloseSeconds, function()
		if s.phase == "Failed" and s.token == token then
			self:finish(s)
		end
	end)
end

-- The buttons that follow the inventory: Open next's count, the grid's Equipped, Open 10 again.
function CaseOpening.refresh(_self: any, s: Session)
	local card, grid = s.card, s.grid
	local left = ItemState.caseCount(s.caseId)
	if card and s.result then
		card:setNext(if left > 0 then left else nil)
	end
	if grid then
		grid:setEquipped(ItemState.equipped())
		grid:setAgain(
			not grid:isFlipping()
				and CaseOpeningFx.hasFastOpen()
				and left >= Config.Cases.FastOpenCount
		)
	end
end

-- A short line over the stage (the server's answer).
function CaseOpening.notice(_self: any, s: Session, text: string, toneName: string?)
	if s.phase ~= "Closed" then
		MenuFrame.showNotice(s.stage.frame, text, toneName)
	end
end

--------------------------------------------------------------------------------------------
-- Equip and sell
--------------------------------------------------------------------------------------------

-- Equip the grid's chosen cue (the single prize card has no Equip: the Inventory does it);
-- the server's answer decides.
function CaseOpening.equip(self: any, s: Session, cueId: string)
	local view = s.grid
	if not view then
		return
	end
	view:setEquipBusy(true)
	task.spawn(function()
		local reply = ItemState.request("ItemRequest", "EquipCue", cueId)
		if s.phase == "Closed" or s.grid ~= view then
			return
		end
		if reply.ok == true then
			view:setEquipped(cueId)
		else
			view:setEquipBusy(false)
			self:notice(s, MenuFrame.reason(reply), "Red")
		end
	end)
end

-- Sell one copy of a duplicate (asking first from ConfirmSellFrom up): the money flies from
-- the button into the money HUD.
function CaseOpening.sell(self: any, s: Session)
	local result, card = s.result, s.card
	if not result or not card or s.sold or s.dialog then
		return
	end
	local cueId = result.cue
	local price = Cases.sellValue(cueId)
	local function go()
		card:setSell("Busy")
		task.spawn(function()
			local reply = ItemState.request("ItemRequest", "SellCue", cueId, 1)
			if s.phase == "Closed" or s.card ~= card then
				return -- the HUD still settles to the saved total by itself
			end
			if reply.ok == true then
				s.sold = true
				card:setSell("Sold")
				local amount = if type(reply.money) == "number" then reply.money else 0
				CaseOpeningFx.flyCash(
					self.root,
					card:sellPoint(),
					amount,
					self.deps and self.deps.money,
					s.stage.scale.Scale
				)
			else
				card:setSell("Ready", price)
				self:notice(s, MenuFrame.reason(reply), "Red")
			end
		end)
	end
	if not Cases.needsConfirm(cueId) then
		go()
		return
	end
	local W = words()
	s.dialog = MenuFrame.ask(s.stage.frame, {
		title = W.SellTitle,
		text = string.format(
			W.SellConfirm,
			CueThumb.rarityName(result.rarity),
			CueThumb.cueName(cueId),
			Format.money(price)
		),
		yes = W.SellYes,
		no = W.SellNo,
		yesTone = "Red",
		noTone = "Blue",
	}, function(yes: boolean)
		s.dialog = nil
		s.dialogUntil = os.clock() + C.DialogGraceSeconds
		if yes and s.card == card then
			go()
		end
	end)
end

--------------------------------------------------------------------------------------------
-- The result screen's reveal
--------------------------------------------------------------------------------------------

--- The first win's case on the result screen: the same reel drawn inside `host` (fitted to
--- it), onto `prize` ({ case, cue, rarity, new }, MatchSummary.firstWin; the cue is already
--- owned), then its card with Equip and Continue. `opts.onDone` runs once, when the player is
--- done with it (Continue, B or Escape), or at once if the prize cannot be shown.
function CaseOpening.reveal(self: any, host: GuiObject, prize: any, opts: any?)
	local onDone: (() -> ())? = nil
	if type(opts) == "table" and type(opts.onDone) == "function" then
		onDone = opts.onDone
	end
	local row = if type(prize) == "table" then Catalog.get(prize.cue) else nil
	if typeof(host) ~= "Instance" or not host:IsA("GuiObject") or not row then
		if onDone then
			onDone()
		end
		return
	end
	local previous: Session? = self.revealing
	if previous then
		self:endReveal(previous, true)
	end
	local caseId = if Cases.get(prize.case) then prize.case else Config.Cases.FirstWinCase
	local rarity = if type(prize.rarity) == "string"
			and Catalog.rarityRank(prize.rarity) > 0
		then prize.rarity
		else row.Rarity
	local holder = HudParts.frame(host, "CaseReveal")
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = C.RevealZIndex
	local s = self:newSession("Reveal", holder, caseId)
	s.holder = holder
	s.onDone = onDone
	s.saved = GuiService.SelectedObject
	s.heading = string.format(words().FirstWin, caseName(caseId))
	local new = prize.new ~= false
	local found = if type(prize.found) == "number" and prize.found > 0
		then math.floor(prize.found)
		else 0
	s.result = {
		cue = row.Id,
		rarity = rarity,
		new = new,
		duplicate = not new,
		count = nil,
		found = found,
	}
	self:holdFound(s, found)
	self.revealing = s
	self:bindInput()
	-- The result screen closing takes the reveal with it: hand back so nothing waits on it.
	table.insert(
		s.connections,
		holder.AncestryChanged:Connect(function()
			if not holder:IsDescendantOf(game) and self.revealing == s then
				self:endReveal(s, true)
			end
		end)
	)
	local reel = CaseOpeningReel.new(s.stage.frame, caseId)
	reel.root.ZIndex = 3
	reel:setPrize(row.Id, rarity)
	s.reel = reel
	self:setPhase(s, "Reel")
	reel:start(function()
		self:showCard(s)
	end)
end

-- End the reveal (its frame goes), put the gamepad back and, if asked, tell the result screen.
function CaseOpening.endReveal(self: any, s: Session, notify: boolean)
	if s.phase == "Closed" then
		return
	end
	local onDone = s.onDone
	s.onDone = nil
	if self.revealing == s then
		self.revealing = nil
	end
	local selected = GuiService.SelectedObject
	local inside = selected ~= nil and s.holder ~= nil and selected:IsDescendantOf(s.holder)
	self:destroySession(s)
	if inside or GuiService.SelectedObject == nil then
		GuiService.SelectedObject = if valid(s.saved) then s.saved else nil
	end
	self:unbindInput()
	if notify and onDone then
		onDone()
	end
end

--------------------------------------------------------------------------------------------
-- Closing
--------------------------------------------------------------------------------------------

--- Close the overlay: what shows pops out, the backdrop fades, the gamepad's selection goes
--- back to where it was (the menu under it). A reel still turning just stops: the cue is
--- already in the inventory.
function CaseOpening.close(self: any)
	if not self.opened then
		return
	end
	self.opened = false
	local s: Session? = self.overlay
	self.overlay = nil
	self.backdrop.Modal = false
	if s and s.phase == "Cutscene" then
		s.phase = "Closed"
		PullCutscene.stop()
	end
	self:showOthers()
	local selected = GuiService.SelectedObject
	if selected == nil or selected:IsDescendantOf(self.gui) then
		if usable(self.saved) then
			GuiService.SelectedObject = self.saved
		else
			-- What it was on is gone or hidden (the last case's row, Open 10 with fewer than
			-- ten left): the menu under it chooses.
			GuiService.SelectedObject = nil
			Menus.ensureSelection()
		end
	end
	self.saved = nil
	self:unbindInput()
	if self.backdropTween then
		self.backdropTween:Cancel()
	end
	self.backdropTween = TweenService:Create(
		self.backdrop,
		TweenInfo.new(C.BackdropSeconds),
		{ BackgroundTransparency = 1 }
	)
	self.backdropTween:Play()
	local cleared = false
	local function gone()
		if cleared then
			return
		end
		cleared = true
		if s then
			self:destroySession(s)
		end
		if not self.opened then
			self.backGui.Enabled = false
			self.gui.Enabled = false
		end
	end
	if not s then
		gone()
		return
	end
	local session = s :: Session
	if session.dialog then
		local dialog = session.dialog
		session.dialog = nil
		dialog.cancel()
	end
	session.closedWaiting = session.phase == "Waiting"
		or session.phase == "Intro"
		or session.phase == "Cracking"
	session.phase = "Closed"
	local view = session.card or session.grid or session.reel
	if view and view.root.Visible then
		UIAnim.popOut(view.root, gone)
		-- A pop-out cut short never calls back: never leave the overlay up.
		task.delay(Config.UI.Kit.Motion.OutSeconds + C.CloseBackstopSeconds, gone)
	else
		gone()
	end
end

function CaseOpening.isOpen(self: any): boolean
	return self.opened
end

return CaseOpening
