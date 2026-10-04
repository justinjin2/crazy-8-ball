--!strict
-- LuckyOpening: a lucky block's reel and result (designer, 2026-10-03). Once the block bursts
-- (LuckyClient waits for the server's burstAt), the screen darkens with a very see-through
-- grey-black (no white panel: the world shows through), the block's name sits over a Dark-look
-- reel (CaseOpeningReel { look = "Dark" }: bordered tiles with each cue's name, rarity and
-- chance) that slows onto the cue the server rolled, then the big "YOU GOT <CUE>!" card
-- (LuckyResult) over the undimmed world with rays in the rarity's colour. A tap, click or A skips the reel, then closes
-- the card; the cue is already in the inventory. The rest of the HUD hides while it is up.
-- Tuning in Config.LuckyBlocks.UI; the reel's own in Config.UI.CaseOpening.Reel.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local LuckyBlocks = require(Shared:WaitForChild("Progression"):WaitForChild("LuckyBlocks"))
local CaseOpeningFx = require(script.Parent.CaseOpeningFx)
local CaseOpeningReel = require(script.Parent.CaseOpeningReel)
local HudParts = require(script.Parent.HudParts)
local LuckyResult = require(script.Parent.LuckyResult)

local U = Config.LuckyBlocks.UI
local CO = Config.UI.CaseOpening
local W = Strings.LuckyBlocks
local SKIP = Strings.CaseOpening
local NAMES: { [string]: string } = W.Names
local TAP_ACTION = "8ballLuckyOpeningTap"
local TAP_PRIORITY = Enum.ContextActionPriority.High.Value + CO.BackPriorityAbove

local Opening = {}
Opening.__index = Opening

function Opening.new(screen: ScreenGui): any
	local self: any = setmetatable({}, Opening)
	self.screen = screen
	self.open = false
	self.phase = "Closed" -- Closed, Reel, Card
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
		if CaseOpeningFx.gamepad() then
			return W.ContinuePad
		elseif CaseOpeningFx.touch() then
			return W.Continue
		end
		return W.ContinueMouse
	end
	if CaseOpeningFx.gamepad() then
		return SKIP.SkipPad
	elseif CaseOpeningFx.touch() then
		return SKIP.SkipTouch
	end
	return SKIP.SkipMouse
end

--- Play a block's opening: `kind` (its name over the reel) and the server's Open answer
--- ({ cue, rarity }). `onClosed` runs once it is gone.
function Opening.play(self: any, kind: string, cueId: string, rarity: string, onClosed: (() -> ())?)
	if self.open then
		self:close()
	end
	local row = LuckyBlocks.kind(kind)
	if row == nil then
		return
	end
	self.open = true
	self.onClosed = onClosed
	self:hideOthers()
	self.backGui.Enabled = true
	self.gui.Enabled = true
	self.dim.BackgroundTransparency = 1
	TweenService
		:Create(
			self.dim,
			TweenInfo.new(U.DimSeconds),
			{ BackgroundTransparency = U.DimTransparency }
		)
		:Play()

	local stage = CaseOpeningFx.stage(self.area, "Stage")
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

	local reel = CaseOpeningReel.new(stage.frame, row.Case, { look = "Dark" })
	reel:setPrize(cueId, rarity)
	self.reel = reel
	self.cueId, self.rarity = cueId, rarity
	self.phase = "Reel"
	self:layout()
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
	reel:start(function()
		self:showCard()
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
	local reelH = CaseOpeningReel.height()
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

function Opening.showCard(self: any)
	if not self.open or self.phase ~= "Reel" then
		return
	end
	self.phase = "Card"
	-- The cue reveals straight over the world; keep the transparent tap target active.
	TweenService:Create(self.dim, TweenInfo.new(U.DimSeconds), { BackgroundTransparency = 1 })
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
	elseif self.phase == "Card" and self.card and self.card:canDismiss() then
		self:close()
	end
end

function Opening.close(self: any)
	if not self.open then
		return
	end
	self.open = false
	self.phase = "Closed"
	ContextActionService:UnbindAction(TAP_ACTION)
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
	self:showOthers()
	local done = self.onClosed
	self.onClosed = nil
	if done then
		done()
	end
end

return Opening
