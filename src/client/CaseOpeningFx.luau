--!strict
-- CaseOpeningFx: the small pieces the case opening's reel, prize card and Fast Open grid share
-- (CaseOpening; docs/prompts/ECONOMY_UI_PROMPT.md section 11): rarity colours and palettes,
-- the reveal sting by rarity, a soft glow (the kit's 9-slice shadow tinted a rarity's colour,
-- so no new image), the turning rays, the Mythic shimmer and the Secret breath on one clock,
-- the copies-in-existence count, a fitted stage (laid out at a natural size and scaled to its
-- parent with one UIScale), and a cash chip that flies from a button into the money HUD
-- inside the overlay's own ScreenGui (CashFlyer draws in the HUD screen, which sits under it).
-- Tuning in Config.UI.CaseOpening.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ProgressionRules = Shared:WaitForChild("Progression")
local Catalog = require(ProgressionRules:WaitForChild("Catalog"))
local Format = require(ProgressionRules:WaitForChild("Format"))
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local MenuFrame = require(script.Parent.MenuFrame)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.CaseOpening
local CASH = Config.UI.Progress.Cash
local K = Config.UI.Kit
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local STINGS: { [string]: string } = C.Stings :: any
local WHITE = Color3.new(1, 1, 1)

local Fx = {}

--------------------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------------------

function Fx.textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

function Fx.gamepad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

function Fx.touch(): boolean
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

--- An empty selection box: the kit draws its own gold outline on whatever is selected.
function Fx.noBox(): Frame
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	return box
end

--- Whether `rarity` is `from` or rarer (Common ... Secret; unknown names are the bottom).
function Fx.atLeast(rarity: string, from: string): boolean
	return Catalog.rarityRank(rarity) >= Catalog.rarityRank(from)
end

--- Mythic and Secret: the bigger moment (a longer build-up, a shimmer or a glow).
function Fx.isBig(rarity: string): boolean
	return Fx.atLeast(rarity, C.BigFrom)
end

--- A rarity's colour on the light kit (Secret's red glow; its near-black reads as ink).
function Fx.color(rarity: string): Color3
	return CueThumb.accentColor(rarity)
end

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local SHIMMER: { Color3 } = {}
for _, values in K.MythicShimmer :: { { number } } do
	table.insert(SHIMMER, rgb(values))
end

--- The Mythic pastel shimmer as a gradient's colours (it loops back to its first colour).
function Fx.shimmer(): ColorSequence
	local keys = {}
	for i, c in SHIMMER do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / #SHIMMER, c))
	end
	table.insert(keys, ColorSequenceKeypoint.new(1, SHIMMER[1]))
	return ColorSequence.new(keys)
end

--- The shimmer's colour at time `t` (seconds): it drifts through the pastels in a loop.
function Fx.shimmerAt(t: number): Color3
	local n = #SHIMMER
	local x = (t / C.ShimmerCycleSeconds) % 1 * n
	local i = math.floor(x)
	local a = SHIMMER[i % n + 1]
	local b = SHIMMER[(i + 1) % n + 1]
	return a:Lerp(b, x - i)
end

--- 0..1..0 over `seconds`: a slow breath (Secret's glow).
function Fx.breath(t: number, seconds: number): number
	return 0.5 + 0.5 * math.sin(t / seconds * math.pi * 2)
end

--- The glow colour of a rarity at time `t`: Mythic drifts through its shimmer, Secret is its
--- red, the rest their own colour.
function Fx.glowAt(rarity: string, t: number): Color3
	if rarity == "Mythic" then
		return Fx.shimmerAt(t)
	end
	return Fx.color(rarity)
end

--- Confetti colours for a rarity (Legendary gold and white, Mythic its pastels, Secret red,
--- white and ink; else the rarity with gold and white).
function Fx.palette(rarity: string): { Color3 }
	if rarity == "Mythic" then
		return table.clone(SHIMMER)
	elseif rarity == "Secret" then
		return { rgb(K.SecretGlow), WHITE, rgb(K.Rarity.Secret), rgb(K.SecretGlow) }
	end
	return { Fx.color(rarity), WHITE, HudParts.tone("Gold"), Fx.color(rarity) }
end

--- The reveal sting for a rarity (Config.UI.CaseOpening.Stings -> a Config.Audio.Ui key).
function Fx.sting(rarity: string)
	UISound.play(STINGS[rarity] or STINGS.Default)
end

--- Copies of a cue in existence (ReplicatedStorage.CueCounts, one attribute per cue id), or
--- nil before the first read.
function Fx.existCount(cueId: string): number?
	local counts = ReplicatedStorage:FindFirstChild("CueCounts")
	local value = if counts then counts:GetAttribute(cueId) else nil
	if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return nil
	end
	return math.floor(value)
end

--- Whether the player has Fast Open (the server's FastOpen attribute).
function Fx.hasFastOpen(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("FastOpen") == true
end

--------------------------------------------------------------------------------------------
-- Glows and rays
--------------------------------------------------------------------------------------------

--- A soft glow: the kit's blurred 9-slice square, tinted (set ImageColor3) and hidden (set
--- ImageTransparency). Place it round a box with Fx.placeHalo.
function Fx.halo(parent: Instance, name: string): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.Image = K.ShadowImage
	image.ScaleType = Enum.ScaleType.Slice
	local s = K.ShadowSlice
	image.SliceCenter = Rect.new(s[1], s[2], s[3], s[4])
	image.ImageTransparency = 1
	image.Parent = parent
	return image
end

--- Put a glow round a box (its top-left and size, in the parent's pixels), `spread` past
--- every side.
function Fx.placeHalo(halo: ImageLabel, position: Vector2, size: Vector2, spread: number)
	halo.Position = UDim2.fromOffset(position.X - spread, position.Y - spread)
	halo.Size = UDim2.fromOffset(size.X + 2 * spread, size.Y + 2 * spread)
end

--- The kit's rays image (hidden until faded in), centred on its position.
function Fx.rays(parent: Instance, name: string): ImageLabel
	local rays = Instance.new("ImageLabel")
	rays.Name = name
	rays.BackgroundTransparency = 1
	rays.Image = K.Art.Rays
	rays.ImageTransparency = 1
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Parent = parent
	return rays
end

--------------------------------------------------------------------------------------------
-- The stage: laid out at a natural size, scaled to fit its parent
--------------------------------------------------------------------------------------------

export type Stage = {
	frame: Frame, -- put everything in here, in natural pixels
	scale: UIScale,
	size: Vector2, -- the natural size after the last fit
	fit: (need: Vector2, minScale: number, maxScale: number, margin: number) -> Vector2,
}

--- A frame that fills `parent` and is scaled so a `need`-sized layout (natural pixels) fits
--- inside it with `margin` round it: fit(need, min, max, margin) sets the scale and returns
--- the stage's natural size (the parent's size over the scale).
function Fx.stage(parent: GuiObject, name: string): Stage
	local frame = HudParts.frame(parent, name)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	local scale = Instance.new("UIScale")
	scale.Name = "Fit"
	scale.Parent = frame
	local stage: Stage
	stage = {
		frame = frame,
		scale = scale,
		size = Vector2.new(1, 1),
		fit = function(need: Vector2, minScale: number, maxScale: number, margin: number): Vector2
			local room = parent.AbsoluteSize / MenuFrame.scaleOf(parent)
			local w = math.max(1, room.X - 2 * margin)
			local h = math.max(1, room.Y - 2 * margin)
			local s = math.clamp(math.min(w / need.X, h / need.Y), minScale, maxScale)
			local natural = Vector2.new(math.floor(room.X / s), math.floor(room.Y / s))
			scale.Scale = s
			frame.Size = UDim2.fromOffset(natural.X, natural.Y)
			stage.size = natural
			return natural
		end,
	}
	return stage
end

--------------------------------------------------------------------------------------------
-- A cash chip into the money HUD
--------------------------------------------------------------------------------------------

-- A quadratic curve from `from` to `to`, its control point lifted so the chip rises first.
local function curve(from: Vector2, to: Vector2, t: number): Vector2
	local lift = math.max(CASH.ArcMinLiftPx, (to - from).Magnitude * CASH.ArcLiftShare)
	local control = from:Lerp(to, 0.25) - Vector2.new(0, lift)
	return from:Lerp(control, t):Lerp(control:Lerp(to, t), t)
end

--- A gold "+$600" chip pops at `from` (absolute pixels), hangs, and flies on a curve into the
--- money HUD's cash icon, drawn in `layer` (a full-screen frame of the overlay's ScreenGui,
--- `scale` its stage's scale); the HUD counts up as it lands. The HUD is told at once
--- (money:expect) and always landed, even if the chip cannot be drawn.
function Fx.flyCash(layer: GuiObject, from: Vector2, amount: number, money: any, scale: number)
	if type(amount) ~= "number" or amount <= 0 or money == nil then
		return
	end
	money:expect(amount)
	local landed = false
	local function land()
		if not landed then
			landed = true
			money:land(amount)
		end
	end
	local ok = pcall(function()
		local height = math.floor(C.ChipHeightPx * scale)
		local textSize = math.max(K.Text.Min, math.floor(C.ChipTextPx * scale))
		local words = Format.moneyDelta(amount)
		local iconWidth = math.floor(height * CASH.IconWidthShare)
		local wordsWidth = math.ceil(Fx.textWidth(words, textSize)) + 6
		local chip = HudParts.frame(layer, "CashChip")
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		chip.Size = UDim2.fromOffset(iconWidth + wordsWidth, height)
		chip.ZIndex = C.ChipZIndex
		local icon = HudParts.icon(chip, "CashSingle", "Cash")
		icon.Size = UDim2.fromOffset(iconWidth, height)
		icon.ZIndex = C.ChipZIndex
		local text = HudParts.text(chip, "Amount", textSize, words, HudParts.tone("Gold"))
		text.AutoLocalize = false -- only a number
		text.TextWrapped = false
		text.Position = UDim2.fromOffset(iconWidth, 0)
		text.Size = UDim2.fromOffset(wordsWidth, height)
		text.ZIndex = C.ChipZIndex + 1
		local size = Instance.new("UIScale")
		size.Scale = CASH.PopFromScale
		size.Parent = chip
		local origin = layer.AbsolutePosition
		local start = from - origin
		local target: Vector2 = money:iconCenter() - origin
		chip.Position = UDim2.fromOffset(start.X, start.Y)
		local began = os.clock()
		local connection: RBXScriptConnection? = nil
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - began
			local fly = t - CASH.PopSeconds - CASH.HangSeconds
			if fly >= CASH.FlySeconds or not chip.Parent then
				if connection then
					connection:Disconnect()
				end
				chip:Destroy()
				land()
				return
			end
			if fly < 0 then
				size.Scale = CASH.PopFromScale
					+ (1 - CASH.PopFromScale) * UIAnim.backOut(t / CASH.PopSeconds)
				return
			end
			local u = UIAnim.quadOut(fly / CASH.FlySeconds)
			local at = curve(start, target, u)
			chip.Position = UDim2.fromOffset(at.X, at.Y)
			size.Scale = 1 + (CASH.EndScale - 1) * u
		end)
		-- Never wait forever: whatever happens, the HUD hears about the money.
		task.delay(CASH.PopSeconds + CASH.HangSeconds + CASH.FlySeconds + 1, land)
	end)
	if not ok then
		land()
	end
end

return Fx
