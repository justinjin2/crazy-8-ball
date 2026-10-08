--!strict
-- LuckyResult: the card after a lucky block's reel (designer, 2026-10-03): the cue's card big in
-- the middle (InventoryCard, as in the Cues menu, with all its motion: the drifting 8-balls and
-- its rarity's effects; designer 2026-10-08) with sun rays turning behind it in its rarity's
-- colour (Common grey ... Mythic's pastels), "YOU GOT <CUE NAME>!" over it, and "Tap to
-- continue" under it. There is
-- no Keep or Sell: the cue is already in the inventory, and a tap, a click or A closes it.
-- Confetti from Config.UI.Reel.ConfettiFrom; the rays and the reveal sting by rarity only from
-- Config.UI.Reel.EffectsFrom (Rare) up, the economy v4 plan's "win effects only for Rare or
-- better" (a lower cue gets its card and a plain sound). Built in natural pixels inside
-- LuckyOpening's stage; tuning in Config.LuckyBlocks.UI.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local ReelFx = require(script.Parent.ReelFx)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local InventoryCard = require(script.Parent.InventoryCard)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local U = Config.LuckyBlocks.UI
local CO = Config.UI.Reel
local W = Strings.LuckyBlocks
local WHITE = Color3.new(1, 1, 1)

local Result = {}
Result.__index = Result

-- The cue card's size (natural pixels): CardCuePx wide, at the card's own shape.
local function cueSize(): Vector2
	local units: { number } = Config.UI.CueCard.Units :: any
	return Vector2.new(U.CardCuePx, math.floor(U.CardCuePx * units[2] / units[1] + 0.5))
end

-- The rows' heights, top to bottom: the title, the cue card, the hint (natural pixels).
local function rows(): (number, number, number)
	return U.CardTitlePx + 8, cueSize().Y + 2 * U.CardCueGapPx, U.CardHintPx + 6
end

--- The card's natural size.
function Result.size(): Vector2
	local a, b, c = rows()
	return Vector2.new(U.CardWidthPx, a + b + c)
end

--- Build the card for `cueId` (of `rarity`) in `parent`, hidden until show().
function Result.new(parent: Instance, cueId: string, rarity: string): any
	local self: any = setmetatable({}, Result)
	self.alive = true
	self.rarity = rarity
	self.effects = ReelFx.atLeast(rarity, CO.EffectsFrom)
	self.born = os.clock()
	local colour = ReelFx.color(rarity)
	local size = Result.size()

	local root = HudParts.frame(parent, "LuckyResult")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(size.X, size.Y)
	root.Visible = false
	root.ZIndex = 5
	self.root = root

	local titleH, artH, hintH = rows()
	local artMiddle = titleH + artH / 2

	-- The sun rays in the rarity's colour (Mythic: its pastels), turning behind the cue.
	local rays = ReelFx.rays(root, "Rays")
	rays.Image = U.CardRaysImage
	rays.ResampleMode = Enum.ResamplerMode.Default
	local raysSide = math.floor(U.CardWidthPx * U.CardRaysShare)
	rays.Size = UDim2.fromOffset(raysSide, raysSide)
	rays.Position = UDim2.fromOffset(size.X / 2, artMiddle)
	rays.ImageColor3 = if rarity == "Mythic" then WHITE else colour
	rays.ZIndex = 0
	rays.Visible = self.effects
	if rarity == "Mythic" then
		local tint = Instance.new("UIGradient")
		tint.Color = ReelFx.shimmer()
		tint.Parent = rays
	end
	self.rays = rays

	local cueName = CueThumb.cueName(cueId)
	local title =
		HudParts.text(root, "Title", U.CardTitlePx, W.YouGot:format(string.upper(cueName)))
	title.TextWrapped = false
	title.Size = UDim2.fromOffset(size.X, titleH)
	title.ZIndex = 4
	self.title = title

	-- The cue's card: its name and rarity bar on it, moving as in the Cues menu.
	local card = InventoryCard.new(root, { name = "Cue", onPress = function() end })
	card.button.Interactable = false -- a tap anywhere closes the screen (LuckyOpening)
	card.button.Selectable = false
	card.button.AnchorPoint = Vector2.new(0.5, 0.5)
	card.button.Position = UDim2.fromOffset(size.X / 2, artMiddle)
	local cardSize = cueSize()
	card.button.Size = UDim2.fromOffset(cardSize.X, cardSize.Y)
	card.button.ZIndex = 3
	InventoryCard.set(card, { cueId = cueId, bare = true })
	self.card = card
	self.thumb = card.button

	local y = titleH + artH
	local hint = HudParts.text(root, "Hint", U.CardHintPx, "")
	hint.TextWrapped = false
	hint.Position = UDim2.fromOffset(0, y)
	hint.Size = UDim2.fromOffset(size.X, hintH)
	hint.ZIndex = 4
	hint.TextTransparency = 1
	self.hint = hint
	return self
end

--- The words under the card for the device in use.
function Result.setHint(self: any, text: string)
	self.hint.Text = text
end

--- Pop it in: the sting, the rays and glow fading in, confetti for the rare ones (into
--- `confettiParent` at the cue's middle).
function Result.show(self: any, confettiParent: GuiObject?)
	if not self.alive then
		return
	end
	self.root.Visible = true
	UIAnim.popIn(self.root)
	if self.effects then
		ReelFx.sting(self.rarity)
		self.spin = UIAnim.spin(self.rays, U.CardRaysDegreesPerSecond)
	else
		UISound.play(CO.PlainSting)
	end
	UIAnim.bounce(self.thumb)
	if confettiParent and ReelFx.atLeast(self.rarity, CO.ConfettiFrom) then
		local at = self.thumb.AbsolutePosition + self.thumb.AbsoluteSize / 2
		local origin = at - confettiParent.AbsolutePosition
		UIAnim.confetti(confettiParent, origin, ReelFx.palette(self.rarity))
	end
	self.born = os.clock()
	self.loop = RunService.RenderStepped:Connect(function()
		self:step()
	end)
end

function Result.step(self: any)
	local t = os.clock() - self.born
	local shown = math.clamp(t / U.CardInSeconds, 0, 1)
	self.rays.ImageTransparency = 1 - (1 - U.CardRaysTransparency) * shown
	local hintShown = math.clamp((t - U.CardDismissAfterSeconds) / 0.3, 0, 1)
	HudParts.setTextTransparency(self.hint, 1 - hintShown)
end

--- Whether a tap may close it yet (not in its first moment, so a tap meant to skip the reel
--- does not close the card before it is seen).
function Result.canDismiss(self: any): boolean
	return os.clock() - self.born >= U.CardDismissAfterSeconds
end

function Result.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	if self.loop then
		self.loop:Disconnect()
	end
	if self.spin then
		self.spin.stop()
	end
	InventoryCard.destroy(self.card)
	self.root:Destroy()
end

return Result
