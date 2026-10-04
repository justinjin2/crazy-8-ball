--!strict
-- LuckyResult: the card after a lucky block's reel (designer, 2026-10-03): the cue big in the
-- middle with sun rays turning behind it in its rarity's colour (Common grey ... Mythic's
-- pastels), "YOU GOT <CUE NAME>!" over it, its rarity under it, and "Tap to continue". There is
-- no Keep or Sell: the cue is already in the inventory, and a tap, a click or A closes it.
-- Confetti from Config.UI.CaseOpening.ConfettiFrom, the reveal sting by rarity. Built in
-- natural pixels inside LuckyOpening's stage; tuning in Config.LuckyBlocks.UI.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local CaseOpeningFx = require(script.Parent.CaseOpeningFx)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)

local U = Config.LuckyBlocks.UI
local CO = Config.UI.CaseOpening
local W = Strings.LuckyBlocks
local WHITE = Color3.new(1, 1, 1)

local Result = {}
Result.__index = Result

-- The rows' heights, top to bottom: the title, the art, the name... (natural pixels).
local function rows(): (number, number, number, number, number)
	return U.CardTitlePx + 8, U.CardArtPx, U.CardNamePx + 6, U.CardRarityPx + 6, U.CardHintPx + 6
end

--- The card's natural size.
function Result.size(): Vector2
	local a, b, c, d, e = rows()
	return Vector2.new(U.CardWidthPx, a + b + c + d + e)
end

--- Build the card for `cueId` (of `rarity`) in `parent`, hidden until show().
function Result.new(parent: Instance, cueId: string, rarity: string): any
	local self: any = setmetatable({}, Result)
	self.alive = true
	self.rarity = rarity
	self.born = os.clock()
	local colour = CaseOpeningFx.color(rarity)
	local size = Result.size()

	local root = HudParts.frame(parent, "LuckyResult")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(size.X, size.Y)
	root.Visible = false
	root.ZIndex = 5
	self.root = root

	local titleH, artH, nameH, rarityH, hintH = rows()
	local artMiddle = titleH + artH / 2

	-- The sun rays in the rarity's colour (Mythic: its pastels), turning behind the cue.
	local rays = CaseOpeningFx.rays(root, "Rays")
	local raysSide = math.floor(U.CardWidthPx * U.CardRaysShare)
	rays.Size = UDim2.fromOffset(raysSide, raysSide)
	rays.Position = UDim2.fromOffset(size.X / 2, artMiddle)
	rays.ImageColor3 = if rarity == "Mythic" then WHITE else colour
	rays.ZIndex = 0
	if rarity == "Mythic" then
		local tint = Instance.new("UIGradient")
		tint.Color = CaseOpeningFx.shimmer()
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

	local thumb = CueThumb.new(root, cueId)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.fromOffset(size.X / 2, artMiddle)
	thumb.Size = UDim2.fromOffset(artH, artH)
	thumb.ZIndex = 3
	self.thumb = thumb

	local y = titleH + artH
	local name = HudParts.text(root, "Name", U.CardNamePx, cueName)
	name.TextWrapped = false
	name.Position = UDim2.fromOffset(0, y)
	name.Size = UDim2.fromOffset(size.X, nameH)
	name.ZIndex = 4
	y += nameH
	local rarityLabel =
		HudParts.text(root, "Rarity", U.CardRarityPx, CueThumb.rarityName(rarity), colour)
	rarityLabel.TextWrapped = false
	rarityLabel.Position = UDim2.fromOffset(0, y)
	rarityLabel.Size = UDim2.fromOffset(size.X, rarityH)
	rarityLabel.ZIndex = 4
	y += rarityH
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
	CaseOpeningFx.sting(self.rarity)
	self.spin = UIAnim.spin(self.rays, U.CardRaysDegreesPerSecond)
	UIAnim.bounce(self.thumb)
	if confettiParent and CaseOpeningFx.atLeast(self.rarity, CO.ConfettiFrom) then
		local at = self.thumb.AbsolutePosition + self.thumb.AbsoluteSize / 2
		local origin = at - confettiParent.AbsolutePosition
		UIAnim.confetti(confettiParent, origin, CaseOpeningFx.palette(self.rarity))
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
	self.root:Destroy()
end

return Result
