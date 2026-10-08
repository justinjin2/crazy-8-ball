--!strict
-- CashFlyer: the flying "+$10". For every pot that paid you (the server's MoneyGrant, sent to
-- the shooter only) a chip, one cash bundle and "+$10" in kit text, pops out at the pocket's
-- place on screen with a little overshoot, hangs a moment, then flies on a curve into the money
-- HUD's cash icon, speeding up, shrinking and fading into it, about 1 s in all; on arrival the
-- HUD counts up by its amount (MoneyHud.land). A nice shot's chip is gold ("+$15") and follows its ball's chip; the
-- pots of one shot follow each other by a short stagger, each timed to the moment the replay
-- drops its ball. The result screen and NEW RANK! launch their chips through fly() too.
-- Tuning in Config.UI.Progress.Cash.
--
-- Every chip's amount is told to the HUD the moment it is known (expect: onGrant does it for
-- pots, the result screen and NEW RANK! for their own chips) and always landed, even when the
-- chip cannot be drawn or this flyer is destroyed first, so the HUD never drifts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)

local C = Config.UI.Progress.Cash
local CashFlyer = {}
CashFlyer.__index = CashFlyer

export type CashFlyer = {
	onGrant: (self: CashFlyer, payload: any) -> (),
	fly: (
		self: CashFlyer,
		amount: number,
		from: Vector2,
		kind: string?,
		delay: number?,
		label: string?
	) -> (),
	destroy: (self: CashFlyer) -> (),
}

type Chip = {
	amount: number, -- what lands in the HUD
	from: Vector2?, -- where it pops out, absolute screen pixels (a caller's point)
	tableId: number, -- or out of this table's pocket, looked up when it pops
	pocket: number?,
	start: Vector2?, -- where it popped out, once it has
	kind: string?,
	label: string?,
	startAt: number, -- os.clock() when it pops
	frame: Frame?,
	scale: UIScale?,
	icon: ImageLabel?,
	text: TextLabel?,
	target: Vector2?, -- where it lands, read once as it sets off
	landed: boolean,
}

-- A whole, finite, non-negative amount (anything else lands as nothing).
local function clean(amount: any): number
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount <= 0 then
		return 0
	end
	return math.floor(amount)
end

local function finitePoint(point: any): boolean
	return typeof(point) == "Vector2"
		and point.X == point.X
		and point.Y == point.Y
		and math.abs(point.X) < math.huge
		and math.abs(point.Y) < math.huge
end

--- The flyer, built into `screen` (UI.screen()). `money` is the MoneyHud the chips land in;
--- `pocketToScreen(tableId, pocket)` gives a pocket's absolute screen position (the space of
--- GuiObject.AbsolutePosition, as Camera:WorldToScreenPoint gives), or nil when it is not
--- known. A point off screen is fine: the chip starts at the nearest edge.
function CashFlyer.new(
	screen: ScreenGui,
	money: any,
	pocketToScreen: (tableId: number, pocket: number) -> Vector2?
): CashFlyer
	local self: any = setmetatable({}, CashFlyer)
	self.alive = true
	self.money = money
	self.pocketToScreen = pocketToScreen
	self.chips = {} :: { Chip }
	self.loop = nil :: RBXScriptConnection?
	self.lastStart = -math.huge -- the latest chip start given out (server time), for the stagger
	local layer = HudParts.frame(screen, "CashFlyer")
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = C.ZIndex
	self.layer = layer
	self.screen = screen
	return self
end

-- The screen's middle, where a chip with no pocket starts.
function CashFlyer.centre(self: any): Vector2
	return self.layer.AbsolutePosition + self.layer.AbsoluteSize / 2
end

-- Keep a start point on screen: a pocket off screen starts just inside the nearest edge.
function CashFlyer.clampToScreen(self: any, point: Vector2): Vector2
	local topLeft = self.layer.AbsolutePosition
	local size = self.layer.AbsoluteSize
	local margin = math.min(C.EdgeMarginPx, size.X / 2, size.Y / 2)
	return Vector2.new(
		math.clamp(point.X, topLeft.X + margin, topLeft.X + size.X - margin),
		math.clamp(point.Y, topLeft.Y + margin, topLeft.Y + size.Y - margin)
	)
end

--- A MoneyGrant from the server: {tableId, epoch, seq, total, grants = {{ball, pocket?,
--- amount, kind, at}}}. Every chip is told to the HUD at once, then each pops at its `at` (the
--- server time its ball drops in the replay), a shot's chips staggered so they follow each
--- other, a nice shot's after its ball's.
function CashFlyer.onGrant(self: any, payload: any)
	if not self.alive or type(payload) ~= "table" or type(payload.grants) ~= "table" then
		return
	end
	local tableId = if type(payload.tableId) == "number" then payload.tableId else 0
	local chips = {}
	for _, grant in payload.grants do
		if type(grant) == "table" then
			local amount = clean(grant.amount)
			if amount > 0 then
				table.insert(chips, grant)
				self.money:expect(amount)
			end
		end
	end
	local now = workspace:GetServerTimeNow()
	for _, grant in chips do
		local at = if type(grant.at) == "number" and grant.at == grant.at
			then grant.at + C.DropLeadSeconds
			else now
		at = math.clamp(at, now, now + C.MaxWaitSeconds)
		-- Pots in the same moment follow each other; a nice shot comes after its ball.
		at = math.max(at, self.lastStart + C.StaggerSeconds)
		self.lastStart = at
		local kind = if type(grant.kind) == "string" then grant.kind else "Ball"
		local pocket = if type(grant.pocket) == "number" then grant.pocket else nil
		self:launch(clean(grant.amount), nil, tableId, pocket, kind, at - now, nil)
	end
end

--- One chip worth `amount` from `from` (absolute screen pixels; off screen is handled) after
--- `delay` seconds; it lands `amount` in the HUD on arrival. The caller has already told the
--- HUD it is coming (money:expect, as soon as the amount was known). `kind` "Ball" (or nil) is
--- a plain green chip; anything else (a nice shot, "Total", "Reward") is gold. `label`
--- replaces the chip's words ("+$10" by default), for a chip that shows more than it adds (the
--- result screen's total, whose pots were already paid during play).
function CashFlyer.fly(
	self: any,
	amount: number,
	from: Vector2,
	kind: string?,
	delay: number?,
	label: string?
)
	local n = clean(amount)
	if not self.alive then
		self.money:land(n)
		return
	end
	self:launch(n, if finitePoint(from) then from else nil, 0, nil, kind, delay or 0, label)
end

-- Queue a chip (the HUD already expects its amount): from a screen point, or from a table's
-- pocket (found when the chip pops, where the camera is then).
function CashFlyer.launch(
	self: any,
	amount: number,
	from: Vector2?,
	tableId: number,
	pocket: number?,
	kind: string?,
	delay: number,
	label: string?
)
	local chip: Chip = {
		amount = amount,
		from = from,
		tableId = tableId,
		pocket = pocket,
		start = nil,
		kind = kind,
		label = label,
		startAt = os.clock() + math.max(0, delay),
		frame = nil,
		scale = nil,
		icon = nil,
		text = nil,
		target = nil,
		landed = false,
	}
	table.insert(self.chips, chip)
	if not self.loop then
		self.loop = RunService.RenderStepped:Connect(function()
			self:step()
		end)
	end
end

-- Where a chip pops out: its point, or its pocket on screen now, kept on screen; the screen's
-- middle when neither is known.
function CashFlyer.startOf(self: any, chip: Chip): Vector2
	local point = chip.from
	if not point and chip.pocket then
		local ok, found = pcall(self.pocketToScreen, chip.tableId, chip.pocket)
		if ok and finitePoint(found) then
			point = found
		end
	end
	return if point then self:clampToScreen(point) else self:centre()
end

-- Draw a chip: the cash bundle and its words, green, or gold for anything but a plain ball.
function CashFlyer.build(self: any, chip: Chip)
	chip.start = self:startOf(chip)
	local short = self.layer.AbsoluteSize.Y < Config.Multiplayer.Style.ShortHeight
	local height = if short then C.ShortChipHeightPx else C.ChipHeightPx
	local textSize = if short then C.ShortTextPx else C.TextPx
	local words = chip.label or Format.moneyDelta(chip.amount)
	local plain = chip.kind == nil or chip.kind == "Ball"
	local frame = HudParts.frame(self.layer, "CashChip")
	chip.frame = frame -- so a failure below still takes it down (finish)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Visible = false -- until the first frame places it
	local iconWidth = math.floor(height * C.IconWidthShare)
	local textWidth = TextService:GetTextSize(
		words,
		textSize,
		(Enum.Font :: any)[Config.UI.Kit.Font],
		Vector2.new(10000, 1000)
	).X + 6
	frame.Size = UDim2.fromOffset(iconWidth + textWidth, height)
	local icon = HudParts.icon(frame, "CashSingle", "Cash")
	icon.Size = UDim2.fromOffset(iconWidth, height)
	icon.ZIndex = 1
	local text = HudParts.text(
		frame,
		"Amount",
		textSize,
		words,
		HudParts.tone(if plain then "Green" else "Gold")
	)
	text.AutoLocalize = false -- only a number
	text.TextWrapped = false
	text.Position = UDim2.fromOffset(iconWidth, 0)
	text.Size = UDim2.fromOffset(textWidth, height)
	text.ZIndex = 2
	local scale = Instance.new("UIScale")
	scale.Scale = C.PopFromScale
	scale.Parent = frame
	chip.scale = scale
	chip.icon, chip.text = icon, text
end

-- How far along its curve a chip is at `t` (0..1) of its flight: it leaves the hang gently and
-- arrives at full speed (no slow crawl over the money's words).
local function flight(t: number): number
	return t * t * (2 - t)
end

-- Fade a chip (0 shown, 1 gone): the cash, the words and their outline.
local function fade(chip: Chip, amount: number)
	if chip.icon then
		chip.icon.ImageTransparency = amount
	end
	local text = chip.text
	if text then
		text.TextTransparency = amount
		local stroke = text:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = amount
		end
	end
end

-- Where a chip is `t` (0..1) of the way along its curve: a quadratic Bezier from the pocket to
-- the HUD's icon, its control point lifted above the start so the chip rises, then swoops down.
local function curve(from: Vector2, to: Vector2, t: number): Vector2
	local lift = math.max(C.ArcMinLiftPx, (to - from).Magnitude * C.ArcLiftShare)
	local control = from:Lerp(to, 0.25) - Vector2.new(0, lift)
	local a = from:Lerp(control, t)
	local b = control:Lerp(to, t)
	return a:Lerp(b, t)
end

-- Land a chip in the HUD, once, and take it off screen.
function CashFlyer.finish(self: any, chip: Chip)
	if chip.landed then
		return
	end
	chip.landed = true
	if chip.frame then
		chip.frame:Destroy()
		chip.frame = nil
	end
	self.money:land(chip.amount)
end

-- Every frame: pop, hang and fly each chip whose time has come.
function CashFlyer.step(self: any)
	local now = os.clock()
	local origin = self.layer.AbsolutePosition
	local popEnd = C.PopSeconds
	local hangEnd = popEnd + C.HangSeconds
	local flyEnd = hangEnd + C.FlySeconds
	local keep = {}
	for _, chip in self.chips do
		local elapsed = now - chip.startAt
		if elapsed >= 0 and not chip.landed then
			if not chip.frame then
				local ok = pcall(self.build, self, chip)
				if not ok then
					self:finish(chip) -- could not be drawn: the money still lands
				end
			end
			local frame, scale, start = chip.frame, chip.scale, chip.start
			if frame and scale and start then
				if elapsed >= flyEnd then
					self:finish(chip)
				else
					local point, size
					if elapsed < popEnd then
						point = start
						size = C.PopFromScale
							+ (1 - C.PopFromScale) * UIAnim.backOut(elapsed / popEnd)
					elseif elapsed < hangEnd then
						point, size = start, 1
					else
						local t = (elapsed - hangEnd) / C.FlySeconds
						local eased = flight(t)
						-- The landing point, read once: asking a big menu where its money pill
						-- is every frame made it lay itself out again mid-frame, and the chip
						-- was drawn only every other frame (designer, 2026-10-08: choppy).
						local target = chip.target or self.money:iconCenter()
						chip.target = target
						point = curve(start, target, eased)
						size = 1 + (C.EndScale - 1) * eased
						local fadeFrom = 1 - C.FadeShare
						if t > fadeFrom then
							fade(chip, (t - fadeFrom) / C.FadeShare)
						end
					end
					frame.Position = UDim2.fromOffset(point.X - origin.X, point.Y - origin.Y)
					frame.Visible = true
					scale.Scale = size
					-- Reading it back makes Roblox place the chip this very frame. Left alone
					-- with a big menu open, the move was put on screen only every other frame:
					-- 30 steps a second, the choppy flight (recorded, 2026-10-08).
					local _placed = frame.AbsolutePosition
				end
			end
		end
		if not chip.landed then
			table.insert(keep, chip)
		end
	end
	self.chips = keep
	if #keep == 0 and self.loop then
		self.loop:Disconnect()
		self.loop = nil
	end
end

function CashFlyer.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	if self.loop then
		self.loop:Disconnect()
		self.loop = nil
	end
	-- Chips still waiting or flying land at once, so the HUD is not left waiting for them.
	for _, chip in self.chips do
		self:finish(chip)
	end
	self.chips = {}
	self.layer:Destroy()
end

return CashFlyer
