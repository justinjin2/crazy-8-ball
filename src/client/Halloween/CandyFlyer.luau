--!strict
-- CandyFlyer: the flying Halloween Candy of each pot (hw-core, 2026-10-29), CashFlyer's twin.
-- The server's MoneyGrant carries each pot's Candy on its grant (`candy`, Config.Halloween.Match
-- .PerPocket) and the balance once they were saved (`candyBalance`). For each such pot a small
-- candy and "+3" pop out just under the pot's cash chip, at the moment the replay drops the
-- ball, hang, then fly on a curve into the Candy pill over the money pill (BoostPill's
-- CandyPill), shrinking and fading into its icon, which thumps; the pill's number counts up as
-- each lands (BoostPill asks CandyFlyer.shown for the number to show). With no pill on screen
-- they fly to the HALLOWEEN tile; with neither they stay a moment and fade. Lower effects: one
-- chip a shot (its total), no overshoot. Tuning in Config.UI.CandyFlyer.
--
-- Cheap: one RenderStepped connection only while a chip is up (disconnected when the last
-- lands), chip frames reused from a small pool, nothing per frame when idle. Purely visual:
-- the server already saved the Candy.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.Parent.HudParts)
local Quality = require(script.Parent.Parent.Quality)
local UIAnim = require(script.Parent.Parent.UIAnim)

local C = Config.UI.CandyFlyer
local SHORT = Config.Multiplayer.Style.ShortHeight

local CandyFlyer = {}

-- A shot's Candy on its way: the balance once it was saved, and how much has not landed yet.
type Group = { after: number, left: number }

type Chip = {
	amount: number,
	group: Group,
	tableId: number,
	pocket: number?,
	startAt: number, -- os.clock() when it pops
	start: Vector2?,
	target: Vector2?, -- where it lands, read once as it sets off
	thump: GuiObject?, -- the pill's icon it thumps on landing
	still: boolean, -- nowhere to fly: it stays and fades
	frame: Frame?,
	scale: UIScale?,
	icon: ImageLabel?,
	text: TextLabel?,
	landed: boolean,
}

local groups: { Group } = {}
local chips: { Chip } = {}
local pool: { Frame } = {}
local loop: RBXScriptConnection? = nil
local layer: Frame? = nil
local deps: any = nil
local pocketToScreen: ((number, number) -> Vector2?)? = nil
local lastStart = -math.huge -- the latest chip start given out (server time), for the stagger

--- The number the Candy pill shows for the saved `balance` (the Candy attribute): the balance
--- less every shot's Candy still flying whose save the balance already holds, so the pill
--- counts up as each chip lands, never ahead of it.
function CandyFlyer.shown(balance: number): number
	local held = 0
	for _, g in groups do
		if balance >= g.after then
			held += g.left
		end
	end
	return math.max(0, balance - held)
end

local function clean(x: any): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x <= 0 then
		return 0
	end
	return math.floor(x)
end

local function finitePoint(p: any): boolean
	return typeof(p) == "Vector2"
		and p.X == p.X
		and p.Y == p.Y
		and math.abs(p.X) < math.huge
		and math.abs(p.Y) < math.huge
end

-- The boost pill (BoostPill), or nil.
local function pill(): any?
	local p = deps and deps.boostPill
	return if type(p) == "table" then p else nil
end

-- Lays the pill out again (its number follows CandyFlyer.shown).
local function relayout()
	local p = pill()
	if p and type(p.layout) == "function" then
		pcall(p.layout, p)
	end
end

-- Where a chip lands (absolute pixels) and the icon that thumps: the Candy pill's icon when it
-- shows, else the HALLOWEEN tile, else nil.
-- Whether `object` and everything over it show (each GuiObject visible, its ScreenGui on).
local function onScreen(object: Instance): boolean
	local at: Instance? = object
	while at ~= nil do
		if at:IsA("GuiObject") and not at.Visible then
			return false
		elseif at:IsA("ScreenGui") then
			return at.Enabled
		end
		at = at.Parent
	end
	return false
end

local function targetOf(): (Vector2?, GuiObject?)
	local p = pill()
	local box = p and p.candyPill
	if typeof(box) == "Instance" and box:IsA("GuiObject") and onScreen(box) then
		local icon = p.candyPillIcon
		local at: GuiObject = if typeof(icon) == "Instance"
				and icon:IsA("GuiObject")
				and icon.Visible
			then icon
			else box
		if at.AbsoluteSize.X > 0 then
			return at.AbsolutePosition + at.AbsoluteSize / 2, at
		end
	end
	local corners = deps and deps.corners
	local tile = corners and corners.eventTile
	if tile and type(tile.target) == "function" then
		local ok, at = pcall(tile.target, tile)
		if ok and finitePoint(at) then
			return at, nil
		end
	end
	return nil, nil
end

local function centre(): Vector2
	local l = layer :: Frame
	return l.AbsolutePosition + l.AbsoluteSize / 2
end

-- Where a chip pops out: just under its pocket on screen (under the pot's cash chip), kept on
-- screen; the screen's middle when the pocket is not known.
local function startOf(chip: Chip, height: number): Vector2
	local l = layer :: Frame
	local point: Vector2? = nil
	if chip.pocket and pocketToScreen then
		local ok, found = pcall(pocketToScreen :: any, chip.tableId, chip.pocket)
		if ok and finitePoint(found) then
			point = found + Vector2.new(0, height * C.BelowShare)
		end
	end
	if point == nil then
		return centre()
	end
	local topLeft, size = l.AbsolutePosition, l.AbsoluteSize
	local margin = math.min(C.EdgeMarginPx, size.X / 2, size.Y / 2)
	return Vector2.new(
		math.clamp(point.X, topLeft.X + margin, topLeft.X + size.X - margin),
		math.clamp(point.Y, topLeft.Y + margin, topLeft.Y + size.Y - margin)
	)
end

-- A chip frame from the pool, or a new one: the candy icon and its words.
local function takeFrame(): Frame
	local frame = table.remove(pool)
	if frame then
		return frame
	end
	local f = HudParts.frame(layer :: Frame, "CandyChip")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.ZIndex = C.ZIndex
	local icon = Instance.new("ImageLabel")
	icon.Name = "Candy"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = Config.Halloween.CandyIcon
	icon.ZIndex = C.ZIndex + 1
	icon.Parent = f
	local text = HudParts.text(f, "Amount", C.TextPx, "", HudParts.color(C.Tint))
	text.AutoLocalize = false -- only a number
	text.TextWrapped = false
	text.ZIndex = C.ZIndex + 2
	local scale = Instance.new("UIScale")
	scale.Parent = f
	return f
end

local function giveBack(frame: Frame)
	frame.Visible = false
	if #pool < C.PoolSize then
		table.insert(pool, frame)
	else
		frame:Destroy()
	end
end

-- Lays a chip's frame out for its amount (the pool's frames are reused).
local function build(chip: Chip)
	local l = layer :: Frame
	local short = l.AbsoluteSize.Y < SHORT
	local height = if short then C.ShortChipHeightPx else C.ChipHeightPx
	local textPx = if short then C.ShortTextPx else C.TextPx
	local words = Strings.Halloween.Toast:format(Format.commas(chip.amount))
	local textW = TextService:GetTextSize(
		words,
		textPx,
		(Enum.Font :: any)[Config.UI.Kit.Font],
		Vector2.new(10000, 1000)
	).X + C.TextPadPx
	local frame = takeFrame()
	chip.frame = frame
	frame.Size = UDim2.fromOffset(height + textW, height)
	local icon = frame:FindFirstChild("Candy") :: ImageLabel
	icon.Size = UDim2.fromOffset(height, height)
	icon.ImageTransparency = 0
	local text = frame:FindFirstChild("Amount") :: TextLabel
	text.Text = words
	HudParts.setTextSize(text, textPx)
	text.Position = UDim2.fromOffset(height, 0)
	text.Size = UDim2.fromOffset(textW, height)
	HudParts.setTextTransparency(text, 0)
	local scale = frame:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = if Quality.isLow() then 1 else C.PopFromScale
	chip.icon, chip.text, chip.scale = icon, text, scale
	chip.start = startOf(chip, height)
	frame.Visible = false -- until the first frame places it
end

local function fade(chip: Chip, amount: number)
	if chip.icon then
		chip.icon.ImageTransparency = amount
	end
	if chip.text then
		HudParts.setTextTransparency(chip.text, amount)
	end
end

local function curve(from: Vector2, to: Vector2, t: number): Vector2
	local lift = math.max(C.ArcMinLiftPx, (to - from).Magnitude * C.ArcLiftShare)
	local control = from:Lerp(to, 0.25) - Vector2.new(0, lift)
	return from:Lerp(control, t):Lerp(control:Lerp(to, t), t)
end

-- A chip done: its Candy counts on the pill (the pill's icon thumps when it flew there).
local function finish(chip: Chip, thump: GuiObject?)
	if chip.landed then
		return
	end
	chip.landed = true
	chip.group.left = math.max(0, chip.group.left - chip.amount)
	if chip.group.left <= 0 then
		local i = table.find(groups, chip.group)
		if i then
			table.remove(groups, i)
		end
	end
	if chip.frame then
		giveBack(chip.frame)
		chip.frame = nil
	end
	if thump and not Quality.isLow() then
		pcall(UIAnim.thump, thump)
	end
	relayout()
end

local function step()
	local now = os.clock()
	local l = layer
	if l == nil or l.Parent == nil then
		for _, chip in chips do
			finish(chip, nil)
		end
		chips = {}
	end
	local origin = if l then l.AbsolutePosition else Vector2.zero
	local popEnd = C.PopSeconds
	local hangEnd = popEnd + C.HangSeconds
	local keep = {}
	for _, chip in chips do
		local elapsed = now - chip.startAt
		if elapsed >= 0 and not chip.landed then
			if chip.frame == nil and not pcall(build, chip) then
				finish(chip, nil) -- could not be drawn: the pill still counts it
			end
			local frame, scale, start = chip.frame, chip.scale, chip.start
			if frame and scale and start then
				local point, size = start, 1
				if elapsed < popEnd then
					size = if Quality.isLow()
						then 1
						else C.PopFromScale + (1 - C.PopFromScale) * UIAnim.backOut(
							elapsed / popEnd
						)
				elseif elapsed >= hangEnd then
					if chip.target == nil then
						local at, icon = targetOf()
						chip.target = at or start
						chip.thump = icon
						chip.still = at == nil
					end
					local still = chip.still
					local length = if still then C.StillSeconds else C.FlySeconds
					local t = math.clamp((elapsed - hangEnd) / length, 0, 1)
					if t >= 1 then
						finish(chip, chip.thump)
					else
						local eased = if still then 0 else t * t * (2 - t)
						point = curve(start, chip.target :: Vector2, eased)
						size = 1 + (C.EndScale - 1) * eased
						local fadeFrom = 1 - C.FadeShare
						if t > fadeFrom then
							fade(chip, (t - fadeFrom) / C.FadeShare)
						end
					end
				end
				if not chip.landed then
					frame.Position = UDim2.fromOffset(point.X - origin.X, point.Y - origin.Y)
					frame.Visible = true
					scale.Scale = size
					-- Read back so Roblox places it this frame (CashFlyer's fix for a big menu
					-- drawing the move only every other frame).
					local _placed = frame.AbsolutePosition
				end
			end
		end
		if not chip.landed then
			table.insert(keep, chip)
		end
	end
	chips = keep
	if #chips == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function launch(amount: number, group: Group, tableId: number, pocket: number?, delay: number)
	table.insert(chips, {
		amount = amount,
		group = group,
		tableId = tableId,
		pocket = pocket,
		startAt = os.clock() + math.max(0, delay),
		start = nil,
		target = nil,
		thump = nil,
		still = false,
		frame = nil,
		scale = nil,
		icon = nil,
		text = nil,
		landed = false,
	})
	if loop == nil then
		loop = RunService.RenderStepped:Connect(function()
			local ok, err = pcall(function(): any
				step()
				return nil
			end)
			if not ok then
				warn("[8ball] CandyFlyer: " .. tostring(err))
				for _, chip in chips do
					finish(chip, nil)
				end
				chips = {}
				if loop then
					loop:Disconnect()
					loop = nil
				end
			end
		end)
	end
end

--- A MoneyGrant from the server: its grants' `candy` fly from their pockets (see the top).
function CandyFlyer.onGrant(payload: any)
	if layer == nil or type(payload) ~= "table" or type(payload.grants) ~= "table" then
		return
	end
	-- Nothing before HwOn (the tutorial's real match pays its pots quietly, like CandyToast).
	if Players.LocalPlayer:GetAttribute("HwOn") ~= true then
		return
	end
	local tableId = if type(payload.tableId) == "number" then payload.tableId else 0
	local pots = {}
	local total = 0
	for _, grant in payload.grants do
		if type(grant) == "table" then
			local n = clean(grant.candy)
			if n > 0 then
				table.insert(pots, grant)
				total += n
			end
		end
	end
	if total <= 0 then
		return
	end
	local balance = clean(payload.candyBalance)
	local group: Group = { after = if balance > 0 then balance else math.huge, left = total }
	table.insert(groups, group)
	relayout() -- the pill holds this shot's Candy back from now on
	local now = workspace:GetServerTimeNow()
	local function delayOf(grant: any): number
		local at = if type(grant.at) == "number" and grant.at == grant.at then grant.at else now
		at = math.clamp(at + C.FollowSeconds, now, now + C.MaxWaitSeconds)
		at = math.max(at, lastStart + C.StaggerSeconds)
		lastStart = at
		return at - now
	end
	if Quality.isLow() then
		-- Lower effects: one chip for the shot, from its first pot.
		local first = pots[1]
		launch(
			total,
			group,
			tableId,
			if type(first.pocket) == "number" then first.pocket else nil,
			delayOf(first)
		)
		return
	end
	for _, grant in pots do
		launch(
			clean(grant.candy),
			group,
			tableId,
			if type(grant.pocket) == "number" then grant.pocket else nil,
			delayOf(grant)
		)
	end
end

local started = false

--- Built once by Progression with the HUD's screen, its shared deps (deps.boostPill: the pill
--- the chips fly to; deps.corners: the HALLOWEEN tile) and the pockets' screen positions.
function CandyFlyer.start(
	screen: ScreenGui,
	sharedDeps: any,
	pockets: (tableId: number, pocket: number) -> Vector2?
)
	if started then
		return
	end
	started = true
	deps = sharedDeps
	pocketToScreen = pockets
	local l = HudParts.frame(screen, "CandyFlyer")
	l.Size = UDim2.fromScale(1, 1)
	l.ZIndex = C.ZIndex
	layer = l
	Net.get("MoneyGrant").OnClientEvent:Connect(function(payload: any)
		local ok, err = pcall(function(): any
			CandyFlyer.onGrant(payload)
			return nil
		end)
		if not ok then
			warn("[8ball] CandyFlyer: " .. tostring(err))
		end
	end)
end

return CandyFlyer
