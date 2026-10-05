--!strict
-- UltSpinAnim: the spin itself on the ult spin screen (docs/prompts/ULTIMATES_PROMPT.md section
-- 9.4), UBG style. The server has already rolled and saved; this only plays what it sent.
-- The name at the top cycles through ult names in their rarity colours, fast then slowing
-- (Config.UI.UltScreen.Spin), with the block reel's tick per change, and lands on the result
-- with the reel's sting for its tier. Epic and up get a 1 s build-up before landing (the reel's
-- whoosh, the names teasing the top rarities), a screen flash and the bigger sting; Legendary
-- and up confetti too. A tap, a click or gamepad A skips to the result; VIP's Skip lands
-- at once. The screen (UltScreen) does the rest on landing: the aura's burst, the avatar's hop,
-- the new state drawn.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Catalog = require(Shared:WaitForChild("Ults"):WaitForChild("Catalog"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)
local Parts = require(script.Parent.UltScreenParts)

local SP = Config.UI.UltScreen.Spin
local STINGS: { [string]: string } = Config.UI.Reel.Stings :: any
local SKIP = Strings.Reel
local SKIP_ACTION = "8ballUltSpinSkip"
-- Over Menus' B (+20) and a popup's (+30): A skips the spin before a selected button hears it.
local SKIP_PRIORITY = Enum.ContextActionPriority.High.Value + 35

export type Result = { id: string, rarity: string, wasPity: boolean? }

export type Hooks = {
	-- Show an ult's name at the top in its rarity colour (`pop`: it bounces as it lands).
	showName: (id: string, pop: boolean) -> (),
	-- Where the name's middle is on the screen, for the confetti.
	nameCenter: () -> Vector2,
	-- The result's tier word has gone (the description may show again in its row).
	tierGone: (() -> ())?,
}

local UltSpinAnim = {}
UltSpinAnim.__index = UltSpinAnim

local function atLeast(rarity: string?, from: string): boolean
	return Catalog.rarityIndex(rarity) >= Catalog.rarityIndex(from)
end

--- The spin's overlay pieces in `root` (the screen's full-size frame).
function UltSpinAnim.new(root: Frame, hooks: Hooks): any
	local self: any = setmetatable({}, UltSpinAnim)
	self.root = root
	self.hooks = hooks
	self.playing = false
	self.token = 0
	self.result = nil :: Result?
	self.done = nil :: ((boolean) -> ())?
	self.rng = Random.new()
	self.all = Catalog.list()
	self.top = {} :: { string }
	for _, id in self.all do
		if atLeast(Catalog.rarity(id), SP.BuildFrom) then
			table.insert(self.top, id)
		end
	end

	-- A tap or click anywhere while it spins skips to the result.
	local catcher = Parts.catcher(root, "SpinSkip")
	catcher.ZIndex = 55
	catcher.Visible = false
	catcher.Activated:Connect(function()
		self:skip()
	end)
	self.catcher = catcher

	-- The tier under the name (GUI lane, step 13): it ticks with each name in its colour and
	-- slams on the result.
	local tier = HudParts.text(root, "Tier", SP.TierTextPx[2], "")
	tier.AnchorPoint = Vector2.new(0.5, 0)
	tier.Size = UDim2.fromOffset(SP.TierTextPx[2] * 10, SP.TierTextPx[2] + 8)
	tier.TextWrapped = false
	tier.ZIndex = 54
	tier.Visible = false
	self.tier = tier
	self.tierToken = 0

	local flash = HudParts.frame(root, "Flash")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 58
	flash.Visible = false
	self.flash = flash

	local hint = HudParts.frame(root, "SkipHint")
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.ZIndex = 56
	hint.Visible = false
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.ZIndex = 57
	glyph.Parent = hint
	local words = HudParts.text(hint, "Words", SP.HintTextPx[2], "")
	words.TextWrapped = false
	words.ZIndex = 57
	self.hint, self.glyph, self.words = hint, glyph, words
	self.hintPx = SP.HintTextPx[2]
	return self
end

--- Place "Tap to skip": its top centre at `at` (the screen's pixels), `width` wide.
function UltSpinAnim.layout(self: any, at: Vector2, width: number, short: boolean)
	self.hintPx = if short then SP.HintTextPx[1] else SP.HintTextPx[2]
	self.hintAt = at
	-- While it spins the tier word takes this row and the hint sits under it.
	self.tierPx = if short then SP.TierTextPx[1] else SP.TierTextPx[2]
	HudParts.setTextSize(self.tier, self.tierPx)
	self.tier.Size = UDim2.fromOffset(self.tierPx * 10, self.tierPx + 8)
	local below = if self.playing then self.tierPx + SP.TierGapPx else 0
	self.hint.Position = UDim2.fromOffset(at.X, at.Y + below)
	self.hint.Size = UDim2.fromOffset(width, self.hintPx + 6)
	self:drawHint()
end

-- The hint's words for the last input: tap, click, or the gamepad's A picture and "Skip".
function UltSpinAnim.drawHint(self: any)
	local px = self.hintPx
	HudParts.setTextSize(self.words, px)
	local height = px + 6
	local image = ""
	local text = SKIP.SkipMouse
	if Parts.isGamepad() then
		text = SKIP.SkipPad
		local ok, found = pcall(function()
			return UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
		end)
		image = if ok and type(found) == "string" then found else ""
	elseif UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
		text = SKIP.SkipTouch
	end
	self.words.Text = text
	self.glyph.Image = image
	self.glyph.Visible = image ~= ""
	local width = self.hint.AbsoluteSize.X / math.max(0.01, UIAnim.scaleOf(self.hint).Scale)
	local textW = math.ceil(Parts.textWidth(text, px)) + 6
	local glyphW = if image ~= "" then height + 4 else 0
	local left = math.floor((math.max(width, 1) - textW - glyphW) / 2)
	self.glyph.Size = UDim2.fromOffset(height, height)
	self.glyph.Position = UDim2.fromOffset(left, 0)
	self.words.Position = UDim2.fromOffset(left + glyphW, 0)
	self.words.Size = UDim2.fromOffset(textW, height)
end

function UltSpinAnim.isPlaying(self: any): boolean
	return self.playing
end

-- A name for the cycling, never the one just shown (the build-up teases Epic and up).
function UltSpinAnim.pick(self: any, last: string?, top: boolean): string
	local list: { string } = if top and #self.top > 1 then self.top else self.all
	if #list == 0 then
		return last or ""
	end
	for _ = 1, 4 do
		local id = list[self.rng:NextInteger(1, #list)]
		if id ~= last then
			return id
		end
	end
	return list[1]
end

--- Play a spin that landed on `result`. `instant` (VIP's Skip) lands at once. `done`
--- runs once it has landed (false) or was cut short silently by cancel (true).
function UltSpinAnim.play(self: any, result: Result, instant: boolean, done: (boolean) -> ())
	self:cancel()
	self.token += 1
	local token = self.token
	self.playing = true
	self.result = result
	self.done = done
	if instant then
		self:land()
		return
	end
	self.catcher.Visible = true
	local at: Vector2? = self.hintAt
	if at then
		self.hint.Position = UDim2.fromOffset(at.X, at.Y + (self.tierPx or 0) + SP.TierGapPx)
	end
	self:drawHint()
	UIAnim.popIn(self.hint)
	ContextActionService:BindActionAtPriority(
		SKIP_ACTION,
		function(_name: string, state: Enum.UserInputState, _input: InputObject)
			if state == Enum.UserInputState.Begin then
				self:skip()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		SKIP_PRIORITY,
		Enum.KeyCode.ButtonA
	)
	local big = atLeast(result.rarity, SP.BuildFrom)
	local total = SP.Seconds + (if big then SP.BuildSeconds else 0)
	task.spawn(function()
		local elapsed = 0
		local last: string? = nil
		local built = false
		while self.token == token and elapsed < total do
			local building = big and elapsed >= total - SP.BuildSeconds
			if building and not built then
				built = true
				UISound.play("ReelBuild")
			end
			last = self:pick(last, building)
			self.hooks.showName(last :: string, false)
			self:showTier(Catalog.rarity(last) or "Common", false)
			UISound.play("ReelTick")
			local t = math.clamp(elapsed / total, 0, 1)
			local step = SP.FirstStepSeconds
				+ (SP.LastStepSeconds - SP.FirstStepSeconds) * t ^ SP.StepPower
			elapsed += task.wait(math.min(step, total - elapsed + 0.01))
		end
		if self.token == token and self.playing then
			self:land()
		end
	end)
end

-- The tier word under the name (in the description's row), in its colour; `final`: the
-- result's (it slams, stays a moment, then goes and the description comes back).
function UltSpinAnim.showTier(self: any, rarity: string, final: boolean)
	local tier: TextLabel = self.tier
	local words: { [string]: string } = Strings.Ults.Rarities :: any
	tier.Text = string.upper(words[rarity] or rarity)
	Parts.paint(tier, rarity)
	local at: Vector2 = self.hintAt or (self.hooks.nameCenter() - self.root.AbsolutePosition)
	tier.Position = UDim2.fromOffset(at.X, at.Y)
	tier.Visible = true
	self.tierToken += 1
	if final then
		UIAnim.slam(tier, Parts.rarityColor(rarity))
		local mine = self.tierToken
		task.delay(SP.TierHoldSeconds, function()
			if self.tierToken == mine and tier.Visible then
				self:hideTier()
			end
		end)
	end
end

--- Whether the tier word is on screen (the description waits for it).
function UltSpinAnim.tierShowing(self: any): boolean
	return self.tier.Visible
end

-- The tier word goes (it pops out) and the description may come back.
function UltSpinAnim.hideTier(self: any)
	self.tierToken += 1
	if self.tier.Visible then
		UIAnim.popOut(self.tier)
	end
	local gone = self.hooks.tierGone
	if gone then
		gone()
	end
end

-- Stop listening for the skip.
function UltSpinAnim.release(self: any)
	ContextActionService:UnbindAction(SKIP_ACTION)
	self.catcher.Visible = false
	if self.hint.Visible then
		UIAnim.popOut(self.hint)
	end
end

--- Land on the result now: the name pops in its colour with its tier's sting; Epic and up
--- flash the screen, Legendary and up throw confetti.
function UltSpinAnim.land(self: any)
	if not self.playing then
		return
	end
	self.playing = false
	self.token += 1
	self:release()
	local result: Result = self.result
	local rarity = result.rarity
	self.hooks.showName(result.id, true)
	self:showTier(rarity, true)
	UISound.play(STINGS[rarity] or STINGS.Default)
	if atLeast(rarity, SP.FlashFrom) then
		local flash: Frame = self.flash
		flash.BackgroundColor3 = Color3.new(1, 1, 1):Lerp(Parts.rarityColor(rarity), 0.25)
		flash.BackgroundTransparency = SP.FlashTransparency
		flash.Visible = true
		local tween = TweenService:Create(
			flash,
			TweenInfo.new(SP.FlashSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		)
		tween.Completed:Connect(function()
			if flash.BackgroundTransparency >= 1 then
				flash.Visible = false
			end
		end)
		tween:Play()
	end
	if atLeast(rarity, SP.ConfettiFrom) then
		local centre = self.hooks.nameCenter() - self.root.AbsolutePosition
		UIAnim.confetti(
			self.root,
			centre,
			{ Parts.rarityColor(rarity), Color3.new(1, 1, 1) },
			SP.ConfettiScale
		)
	end
	local done = self.done
	self.done = nil
	if done then
		done(false)
	end
end

--- Skip to the result (a tap, a click or A while it cycles).
function UltSpinAnim.skip(self: any)
	if self.playing then
		UISound.play("Click")
		self:land()
	end
end

--- Cut a spin short with no sting (the screen is closing): `done` hears true.
function UltSpinAnim.cancel(self: any)
	if not self.playing then
		return
	end
	self.playing = false
	self.token += 1
	self:release()
	self.tierToken += 1
	self.tier.Visible = false
	local done = self.done
	self.done = nil
	if done then
		done(true)
	end
end

--- An Auto Spin result, shown quickly: the name pops; Rare and up play their sting, the rest
--- the tick.
function UltSpinAnim.quick(self: any, result: Result)
	self.hooks.showName(result.id, true)
	if atLeast(result.rarity, SP.AutoStingFrom) then
		UISound.play(STINGS[result.rarity] or STINGS.Default)
	else
		UISound.play("ReelTick")
	end
end

return UltSpinAnim
