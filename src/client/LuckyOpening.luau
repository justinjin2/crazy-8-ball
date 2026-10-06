--!strict
-- LuckyOpening: a lucky block's reel and result (designer, 2026-10-03). Once the block bursts
-- (LuckyClient waits for the server's burstAt), the screen darkens with a very see-through
-- grey-black (no white panel: the world shows through), the block's name sits over a Dark-look
-- reel (BlockReel { look = "Dark" }: bordered tiles with each cue's name, rarity and chance)
-- that slows onto the cue the server rolled. A Rare or better cue then plays its pull
-- cutscene (PullCutscene; moved here from the cases 2026-10-04, being redone): a second before
-- the reel stops (designer, 2026-10-05: the suspense of "did I really just pull this")
-- everything fades to black over the reel's last crawl, the reel's screens go once it is
-- black, and the scene plays; then the big "YOU GOT
-- <CUE>!" card (LuckyResult) over the dimmed world with rays in the rarity's colour. A tap,
-- click or A skips the reel, then the cutscene (an old one, once it has been seen; never Rare),
-- then closes the card; the cue is already in the inventory. The rest of the HUD
-- hides while it is up. Tuning in Config.LuckyBlocks.UI; the reel's own in Config.UI.Reel.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local LuckyBlocks = require(Shared:WaitForChild("Progression"):WaitForChild("LuckyBlocks"))
local BlockReel = require(script.Parent.BlockReel)
local HudParts = require(script.Parent.HudParts)
local LuckyResult = require(script.Parent.LuckyResult)
local PullCutscene = require(script.Parent.PullCutscene)
local ReelFx = require(script.Parent.ReelFx)
local ScreenBlur = require(script.Parent.ScreenBlur)
local UIAnim = require(script.Parent.UIAnim)

local U = Config.LuckyBlocks.UI
local CO = Config.UI.Reel
local W = Strings.LuckyBlocks
local SKIP = Strings.Reel
local NAMES: { [string]: string } = W.Names
local TAP_ACTION = "8ballLuckyOpeningTap"
local TAP_PRIORITY = Enum.ContextActionPriority.High.Value + CO.BackPriorityAbove

local Opening = {}
Opening.__index = Opening

function Opening.new(screen: ScreenGui): any
	local self: any = setmetatable({}, Opening)
	self.screen = screen
	self.open = false
	self.phase = "Closed" -- Closed, Lead (the blur's head start), Reel, Scene (the pull cutscene), Card
	self.reel = nil :: any
	self.card = nil :: any
	self.hidden = nil :: { ScreenGui }?
	self.onClosed = nil :: (() -> ())?
	self:build()
	return self
end

function Opening.build(self: any)
	local parent = self.screen.Parent
	local order = self.screen.DisplayOrder + U.DisplayOrderAbove
	local back = Instance.new("ScreenGui")
	back.Name = "LuckyOpeningDim"
	back.ResetOnSpawn = false
	back.IgnoreGuiInset = true
	back.ScreenInsets = Enum.ScreenInsets.None
	back.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	back.DisplayOrder = order
	back.Enabled = false
	back.Parent = parent
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Selectable = false
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = HudParts.color(U.DimColor)
	dim.BackgroundTransparency = 1
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = back
	dim.Activated:Connect(function()
		self:tap()
	end)
	self.backGui, self.dim = back, dim

	local gui = Instance.new("ScreenGui")
	gui.Name = "LuckyOpening"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = order + 1
	gui.Enabled = false
	gui.Parent = parent
	local area = HudParts.frame(gui, "Area")
	area.Size = UDim2.fromScale(1, 1)
	self.gui, self.area = gui, area
	area:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if self.open then
			self:layout()
		end
	end)
end

function Opening.isOpen(self: any): boolean
	return self.open
end

-- Every other enabled ScreenGui goes while it is up (the hotbar and HUD too).
function Opening.hideOthers(self: any)
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
				and gui.Name ~= "Freecam"
			then
				gui.Enabled = false
				table.insert(hidden, gui)
			end
		end
	end
	self.hidden = hidden
end

function Opening.showOthers(self: any)
	local hidden = self.hidden
	self.hidden = nil
	for _, gui in hidden or {} do
		if gui.Parent then
			gui.Enabled = true
		end
	end
end

local function hintFor(phase: string): string
	if phase == "Card" then
		if ReelFx.gamepad() then
			return W.ContinuePad
		elseif ReelFx.touch() then
			return W.Continue
		end
		return W.ContinueMouse
	end
	if ReelFx.gamepad() then
		return SKIP.SkipPad
	elseif ReelFx.touch() then
		return SKIP.SkipTouch
	end
	return SKIP.SkipMouse
end

--- Play a block's opening: `kind` (its name over the reel) and the server's Open answer
--- ({ cue, rarity, oddsId }; `oddsId` is the odds row the reel shows: the Mystery block's
--- rolled tier's). `onClosed` runs once it is gone.
function Opening.play(
	self: any,
	kind: string,
	cueId: string,
	rarity: string,
	onClosed: (() -> ())?,
	oddsId: string?
)
	if self.open then
		self:close()
	end
	local row = LuckyBlocks.kind(kind)
	if row == nil then
		return
	end
	local reelOdds = if type(oddsId) == "string" then oddsId else row.Odds
	if reelOdds == nil then
		return
	end
	self.open = true
	self.onClosed = onClosed
	self:hideOthers()
	self.backGui.Enabled = true
	self.gui.Enabled = true
	self.dim.BackgroundTransparency = 1
	ScreenBlur.set(self, true)
	TweenService
		:Create(
			self.dim,
			TweenInfo.new(U.DimSeconds),
			{ BackgroundTransparency = U.DimTransparency }
		)
		:Play()
	-- The world starts to blur a moment before the reel pops up, so the blur is seen to fade
	-- in (designer, 2026-10-06: at the same moment it looked instant).
	self.playId = (self.playId or 0) + 1
	local playId = self.playId
	self.phase = "Lead"
	task.delay(Config.UI.Blur.ReelLeadSeconds, function()
		if self.open and self.playId == playId then
			self:startReel(kind, cueId, rarity, reelOdds)
		end
	end)
end

-- The reel itself, once the blur has a head start (play).
function Opening.startReel(self: any, kind: string, cueId: string, rarity: string, reelOdds: string)
	local stage = ReelFx.stage(self.area, "Stage")
	self.stage = stage
	local title = HudParts.text(stage.frame, "Title", CO.TitlePx, NAMES[kind] or kind)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.TextWrapped = false
	title.ZIndex = 4
	self.title = title
	local hint = HudParts.text(stage.frame, "Hint", CO.HintPx, hintFor("Reel"))
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.TextWrapped = false
	hint.ZIndex = 4
	self.hint = hint

	local reel = BlockReel.new(stage.frame, reelOdds, { look = "Dark" })
	reel:setPrize(cueId, rarity)
	self.reel = reel
	self.cueId, self.rarity = cueId, rarity
	self.phase = "Reel"
	self:layout()
	-- One by one, quickly: the title, the reel's window and each card, then the hint; the spin
	-- starts once the last card is on its way (designer, 2026-10-06).
	local S = Config.UI.Kit.Motion.Stagger
	UIAnim.expandIn(title, 0)
	local spinAt = reel:intro(S.GapSeconds)
	UIAnim.expandIn(hint, spinAt)
	local playId = self.playId
	ContextActionService:BindActionAtPriority(
		TAP_ACTION,
		function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				self:tap()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		TAP_PRIORITY,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Return,
		Enum.KeyCode.Space,
		Enum.KeyCode.Escape
	)
	task.delay(spinAt, function()
		if not (self.open and self.playId == playId and self.reel == reel) then
			return
		end
		reel:start(function()
			self:afterReel()
		end, function()
			self:stopping()
		end, if PullCutscene.has(rarity) then Config.Cutscenes.Black.LeadSeconds else 0)
	end)
end

function Opening.layout(self: any)
	local stage = self.stage
	if not self.open or stage == nil then
		return
	end
	if self.phase == "Card" and self.card then
		local size = LuckyResult.size()
		local natural = stage.fit(
			size + Vector2.new(2, 2) * CO.CardMarginPx,
			U.MinScale,
			U.MaxScale,
			U.MarginPx
		)
		self.card.root.Position =
			UDim2.fromOffset(math.floor(natural.X / 2), math.floor(natural.Y / 2))
		self.title.Visible = false
		self.hint.Visible = false
		return
	end
	local titleH, gap, hintH = CO.TitleHeightPx, CO.GapPx, CO.HintHeightPx
	local reelH = BlockReel.height()
	local need = Vector2.new(CO.StageMinWidthPx, titleH + gap + reelH + gap + hintH)
	local natural = stage.fit(need, U.MinScale, U.MaxScale, U.MarginPx)
	local top = math.floor((natural.Y - need.Y) / 2)
	self.title.Position = UDim2.fromOffset(math.floor(natural.X / 2), top)
	self.title.Size = UDim2.fromOffset(natural.X, titleH)
	local y = top + titleH + gap
	if self.reel then
		local width = math.min(natural.X - 2 * CO.ReelSideMarginPx, CO.Reel.MaxWidthPx)
		self.reel:layout(math.max(CO.Reel.MinWidthPx, width))
		self.reel.root.Position =
			UDim2.fromOffset(math.floor(natural.X / 2), y + math.floor(reelH / 2))
	end
	y += reelH + gap
	self.hint.Position = UDim2.fromOffset(math.floor(natural.X / 2), y)
	self.hint.Size = UDim2.fromOffset(natural.X, hintH)
	self.hint.Text = hintFor("Reel")
end

-- The reel is a second from stopping on the prize: a Rare or better cue's pull cutscene starts
-- now, fading everything to black over its last crawl (its screens go once it is black), then
-- the card. Anything else waits for the reel to settle (afterReel).
function Opening.stopping(self: any)
	if not self.open or self.phase ~= "Reel" or not PullCutscene.has(self.rarity) then
		return
	end
	self.phase = "Scene"
	local ok = pcall(PullCutscene.play, self.rarity, self.cueId, function()
		local phase: string = self.phase
		if not self.open or phase ~= "Scene" then
			return
		end
		self.gui.Enabled = true
		self.backGui.Enabled = true
		self:showCard()
	end, function()
		self.gui.Enabled = false
		self.backGui.Enabled = false
	end)
	if not ok then
		self.gui.Enabled = true
		self.backGui.Enabled = true
		self:showCard()
	end
end

-- The reel has settled and held: the card (a pull with a cutscene is already in it).
function Opening.afterReel(self: any)
	if not self.open or self.phase ~= "Reel" then
		return
	end
	self:showCard()
end

function Opening.showCard(self: any)
	local phase: string = self.phase
	if not self.open or (phase ~= "Reel" and phase ~= "Scene") then
		return
	end
	self.phase = "Card"
	-- Keep the world dimmed for contrast through the cue reveal.
	TweenService
		:Create(
			self.dim,
			TweenInfo.new(U.DimSeconds),
			{ BackgroundTransparency = U.DimTransparency }
		)
		:Play()
	if self.reel then
		self.reel:destroy()
		self.reel = nil
	end
	local card = LuckyResult.new(self.stage.frame, self.cueId, self.rarity)
	card:setHint(hintFor("Card"))
	self.card = card
	self:layout()
	card:show(self.stage.frame)
end

function Opening.tap(self: any)
	if not self.open then
		return
	end
	if self.phase == "Reel" and self.reel then
		self.reel:skip()
	elseif self.phase == "Scene" then
		PullCutscene.trySkip() -- once the kind has been seen; its own done() shows the card
	elseif self.phase == "Card" and self.card and self.card:canDismiss() then
		self:close()
	end
end

function Opening.close(self: any)
	if not self.open then
		return
	end
	local wasScene = self.phase == "Scene"
	self.open = false
	self.phase = "Closed"
	ContextActionService:UnbindAction(TAP_ACTION)
	if wasScene then
		PullCutscene.stop()
	end
	if self.reel then
		self.reel:destroy()
		self.reel = nil
	end
	if self.card then
		self.card:destroy()
		self.card = nil
	end
	if self.stage then
		self.stage.frame:Destroy()
		self.stage = nil
	end
	self.backGui.Enabled = false
	self.gui.Enabled = false
	ScreenBlur.set(self, false)
	self:showOthers()
	PullCutscene.cardClosed() -- a Legendary's ambience plays on a moment, then tapers
	local done = self.onClosed
	self.onClosed = nil
	if done then
		done()
	end
end

return Opening
