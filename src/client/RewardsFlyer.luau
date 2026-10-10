--!strict
-- RewardsFlyer: what a claim in the Rewards menu gave flies out of the button that claimed it
-- (docs/prompts/ECONOMY_UI_PROMPT.md section 11): the money as the kit's cash chip ("+$250",
-- CashFlyer's look and timing) into the money HUD, which counts up as it lands; each lucky
-- block as its 3D icon (with "x2") on a curve to the hotbar when it shows (deps.hotbarCenter,
-- bumpHotbar), else the left column's Inventory tile, which bounces (MenuColumn.tileCenter and
-- bump); a cue (its thumbnail: the first week's Week One Cue) to the Inventory tile; ult spins
-- and Lucky Spins (their icons with "+2") the same way to the column's Ults button, or the
-- Rewards tile when the column has no Ults button (RewardsParts.SpinTiles). Everything flies in
-- its own ScreenGui just over the menus,
-- so it is seen over the open menu's panel (the HUDs sit under it; on a phone the panel covers
-- them and the chips land where they are). Purely visual: the server already put the reward
-- in the save.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local BlockIcon = require(script.Parent.BlockIcon)
local CashFlyer = require(script.Parent.CashFlyer)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local RewardsParts = require(script.Parent.RewardsParts)
local UIAnim = require(script.Parent.UIAnim)

local F = Config.UI.Rewards.Fly
local DIM = Config.UI.Progress.Roadmap -- a menu's ScreenGui sits DisplayOrderAbove the HUD's

local RewardsFlyer = {}
RewardsFlyer.__index = RewardsFlyer

local function finitePoint(point: any): boolean
	return typeof(point) == "Vector2"
		and point.X == point.X
		and point.Y == point.Y
		and math.abs(point.X) < math.huge
		and math.abs(point.Y) < math.huge
end

-- A point on a quadratic curve from `from` to `to`, its control point lifted above the start
-- (the cash chips' curve).
local function curve(from: Vector2, to: Vector2, t: number): Vector2
	local lift = math.max(F.ArcMinLiftPx, (to - from).Magnitude * F.ArcLiftShare)
	local control = from:Lerp(to, 0.25) - Vector2.new(0, lift)
	local a = from:Lerp(control, t)
	local b = control:Lerp(to, t)
	return a:Lerp(b, t)
end

--- The flyer for one menu. `screen` is the HUD's ScreenGui (the flyer's own goes over the
--- menus'); `deps` is Progression's shared table (money: MoneyHud, column: MenuColumn), read
--- when a reward flies.
function RewardsFlyer.new(screen: ScreenGui, deps: any): any
	local self: any = setmetatable({}, RewardsFlyer)
	self.deps = deps
	local gui = Instance.new("ScreenGui")
	gui.Name = "RewardsFlyer"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder + DIM.DisplayOrderAbove + F.DisplayOrderAbove
	gui.Parent = screen.Parent
	self.gui = gui
	local layer = HudParts.frame(gui, "Flights")
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = F.ZIndex
	self.layer = layer
	self.cash = nil :: any -- a CashFlyer over the menus, made on the first money
	return self
end

-- The CashFlyer that draws the money chips in this flyer's ScreenGui (no pockets here).
function RewardsFlyer.cashFlyer(self: any): any?
	if self.cash then
		return self.cash
	end
	local money = self.deps and self.deps.money
	if not money then
		return nil
	end
	self.cash = CashFlyer.new(self.gui, money, function(_tableId: number, _pocket: number): Vector2?
		return nil
	end)
	return self.cash
end

--- Fly a reward ({ money, blocks, spins, lucky } in either shape, as RewardRequest answers)
--- out of `from` (absolute pixels: the button's centre).
function RewardsFlyer.reward(self: any, value: any, from: Vector2)
	local reward = RewardsParts.reward(value)
	local start = if finitePoint(from)
		then from
		else self.layer.AbsolutePosition + self.layer.AbsoluteSize / 2
	local delay = 0
	if reward.money > 0 then
		local money = self.deps and self.deps.money
		local cash = self:cashFlyer()
		if money and cash then
			money:expect(reward.money)
			cash:fly(reward.money, start, "Reward", 0)
			delay = F.AfterMoneySeconds
		end
	end
	-- The blocks, the cues, then the spins' icons, one after another.
	local items = RewardsParts.pictures({
		money = 0,
		blocks = reward.blocks,
		spins = reward.spins,
		lucky = reward.lucky,
		cues = reward.cues,
	})
	for index, picture in items do
		local tiles = if picture.label then RewardsParts.SpinTiles else { "Inventory" }
		self:flyPicture(picture, tiles, start, delay + (index - 1) * F.StaggerSeconds)
	end
end

-- Where a picture lands: a block's the hotbar's middle while the bar shows ("Hotbar"); else
-- the first of `tiles` the column has, and its centre now (nil: no column, or none of them).
local function tileOf(deps: any, block: boolean, tiles: { string }): (string?, Vector2?)
	if type(deps) ~= "table" then
		return nil, nil
	end
	if block and type(deps.hotbarCenter) == "function" then
		local ok, point = pcall(deps.hotbarCenter)
		if ok and finitePoint(point) then
			return "Hotbar", point
		end
	end
	local column = deps.column
	if not column then
		return nil, nil
	end
	for _, name in tiles do
		local ok, found = pcall(column.tileCenter, column, name)
		if ok and finitePoint(found) then
			return name, found
		end
	end
	return nil, nil
end

-- One picture (a lucky block with "x2", a cue's thumbnail, or a spin icon with "+2") from
-- `from` to the hotbar (a block) or the first of the column's `tiles` it has, after `delay`
-- seconds.
function RewardsFlyer.flyPicture(
	self: any,
	picture: RewardsParts.Picture,
	tiles: { string },
	from: Vector2,
	delay: number
)
	local layer: Frame = self.layer
	local short = layer.AbsoluteSize.Y < Config.Multiplayer.Style.ShortHeight
	local size = if short then F.ShortBlockSizePx else F.BlockSizePx
	local block = picture.key == "Block"
	local chip = HudParts.frame(layer, if picture.label then "SpinChip" else "ItemChip")
	chip.AnchorPoint = Vector2.new(0.5, 0.5)
	chip.Size = UDim2.fromOffset(size, size)
	chip.ZIndex = F.ZIndex
	chip.Visible = false
	if block then
		local icon = BlockIcon.new(chip, picture.kind or "", false)
		icon.root.ZIndex = F.ZIndex + 1
		icon.viewport.ZIndex = F.ZIndex + 1
		if icon.fallback then
			icon.fallback.ZIndex = F.ZIndex + 1
		end
	elseif picture.key == "Cue" then
		local thumb = CueThumb.new(chip, picture.cue or "")
		thumb.Size = UDim2.fromScale(1, 1)
		thumb.ZIndex = F.ZIndex + 1
	else
		local icon = HudParts.icon(chip, picture.key, "Picture")
		icon.Size = UDim2.fromScale(1, 1)
		icon.ZIndex = F.ZIndex + 1
	end
	local words = picture.label
		or (
			if picture.count > 1 then Strings.Menus.Rewards.BlockCount:format(picture.count) else ""
		)
	if words ~= "" then
		local count = HudParts.text(chip, "Count", F.CountTextPx, words)
		count.AutoLocalize = false
		count.TextWrapped = false
		count.AnchorPoint = Vector2.new(1, 1)
		count.Position = UDim2.new(1, 4, 1, 4)
		count.Size = UDim2.fromOffset(size, F.CountTextPx + 4)
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.ZIndex = F.ZIndex + 2
	end
	local scale = Instance.new("UIScale")
	scale.Scale = F.PopFromScale
	scale.Parent = chip

	local deps = self.deps
	local startAt = os.clock() + delay
	local popEnd = F.PopSeconds
	local hangEnd = popEnd + F.HangSeconds
	local flyEnd = hangEnd + F.FlySeconds
	local connection: RBXScriptConnection? = nil
	local landing: string? = nil -- the tile it is flying to
	local function finish(landed: boolean)
		if connection then
			connection:Disconnect()
			connection = nil
		end
		chip:Destroy()
		local column = deps and deps.column
		if landed and landing == "Hotbar" and deps and type(deps.bumpHotbar) == "function" then
			pcall(deps.bumpHotbar)
		elseif landed and column and landing then
			pcall(column.bump, column, landing)
		end
	end
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startAt
		if elapsed < 0 then
			return
		end
		if not layer.Parent then
			finish(false)
			return
		end
		local origin = layer.AbsolutePosition
		local name, target = tileOf(deps, block, tiles)
		landing = name
		local point, k
		if elapsed < popEnd then
			point = from
			k = F.PopFromScale + (1 - F.PopFromScale) * UIAnim.backOut(elapsed / popEnd)
		elseif elapsed < hangEnd then
			point, k = from, 1
		elseif elapsed < flyEnd and target then
			local t = (elapsed - hangEnd) / F.FlySeconds
			local eased = t * t * (3 - 2 * t)
			point = curve(from, target, eased)
			k = 1 + (F.EndScale - 1) * eased
		elseif target then
			finish(true)
			return
		else
			-- Nowhere to land (no column, no hotbar): it pops out where it is.
			UIAnim.popOut(chip, function()
				finish(false)
			end)
			if connection then
				connection:Disconnect()
				connection = nil
			end
			return
		end
		chip.Position = UDim2.fromOffset(point.X - origin.X, point.Y - origin.Y)
		chip.Visible = true
		scale.Scale = k
	end)
end

function RewardsFlyer.destroy(self: any)
	if self.cash then
		self.cash:destroy()
		self.cash = nil
	end
	self.gui:Destroy()
end

return RewardsFlyer
