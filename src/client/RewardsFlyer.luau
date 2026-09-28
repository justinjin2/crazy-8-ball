--!strict
-- RewardsFlyer: what a claim in the Rewards menu gave flies out of the button that claimed it
-- (docs/prompts/ECONOMY_UI_PROMPT.md section 11): the money as the kit's cash chip ("+$250",
-- CashFlyer's look and timing) into the money HUD, which counts up as it lands; each case as
-- its chest (with "x2") on a curve to the left column's Inventory tile, which bounces
-- (MenuColumn.tileCenter and bump). Everything flies in its own ScreenGui just over the menus,
-- so it is seen over the open menu's panel (the HUDs sit under it; on a phone the panel covers
-- them and the chips land where they are). Purely visual: the server already put the reward
-- in the save.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local CashFlyer = require(script.Parent.CashFlyer)
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
	local layer = HudParts.frame(gui, "Cases")
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

--- Fly a reward ({ money, cases } in either shape, as RewardRequest answers) out of `from`
--- (absolute pixels: the button's centre).
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
	for index, entry in reward.cases do
		self:flyCase(entry, start, delay + (index - 1) * F.StaggerSeconds)
	end
end

-- One case's chest (with "x2") from `from` to the Inventory tile, after `delay` seconds.
function RewardsFlyer.flyCase(
	self: any,
	entry: RewardsParts.CaseCount,
	from: Vector2,
	delay: number
)
	local layer: Frame = self.layer
	local short = layer.AbsoluteSize.Y < Config.Multiplayer.Style.ShortHeight
	local size = if short then F.ShortCaseSizePx else F.CaseSizePx
	local chip = HudParts.frame(layer, "CaseChip")
	chip.AnchorPoint = Vector2.new(0.5, 0.5)
	chip.Size = UDim2.fromOffset(size, size)
	chip.ZIndex = F.ZIndex
	chip.Visible = false
	local pictures = RewardsParts.pictures({ money = 0, cases = { entry } })
	local picture = pictures[1]
	local icon = HudParts.icon(chip, if picture then picture.key else "Case", "Chest")
	icon.Size = UDim2.fromScale(1, 1)
	icon.ZIndex = F.ZIndex + 1
	if entry.count > 1 then
		local count = HudParts.text(
			chip,
			"Count",
			F.CountTextPx,
			Strings.Menus.Rewards.CaseCount:format(entry.count)
		)
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
	local function finish(landed: boolean)
		if connection then
			connection:Disconnect()
			connection = nil
		end
		chip:Destroy()
		local column = deps and deps.column
		if landed and column then
			pcall(column.bump, column, "Inventory")
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
		local column = deps and deps.column
		local target: Vector2? = nil
		if column then
			local ok, found = pcall(column.tileCenter, column, "Inventory")
			if ok and finitePoint(found) then
				target = found
			end
		end
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
			-- Nowhere to land (no column): it pops out where it is.
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
