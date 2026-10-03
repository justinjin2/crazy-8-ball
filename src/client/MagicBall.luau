--!strict
-- MagicBall: the Case Drop reveal (GUI lane; designer 2026-10-03, C11b). A Case Drop (a win's,
-- on MatchSummary.caseDrop; Mystery Cases, reward drops and /freecase on the CaseDrop remote)
-- already landed in the save; this only shows it, ending on the server's tier:
-- 1. A giant magic 8-ball, "SHAKE MAGIC 8 BALL!", and a see-through finger sweeping to show
--    how. Shake it by dragging back and forth (touch, mouse; a tap or click counts too), the
--    left stick side to side (gamepad; A counts too), or a real shake of a phone.
-- 2. Each shake fills the meter; at the server's climbs (CaseDrop.climbs: one step a tier above
--    Standard) the glow inside jumps a colour with a flash and a ding (Starr Drop style).
-- 3. Full, it turns round to its window and the triangle ticks slowly through the tier names to
--    the final one in its colour (ref 10), with a sparkle and the tier's sting.
-- 4. The ball goes and the case shows in front: Open now / Later (an instant case), or "Ready
--    in 6h" and OK (a case on its timer; it is in the Inventory).
-- Many drops at once (Mystery x10, a day with 3 drops): one ball labelled "x10", one shake, then
-- it bursts into a row of triangles that tick one by one, rarest last, and the cases show with
-- Collect. Seen once (Seen "MagicBall"), a Skip button jumps to the end. Shown through the
-- popup queue (Popups): one at a time, never in a match, never over a menu or the result
-- screen, never in the tutorial. Every control works by touch, mouse and gamepad. Tuning in
-- Config.UI.MagicBall, words in Strings.MagicBall.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local ProgressionRules = Shared:WaitForChild("Progression")
local CaseDrop = require(ProgressionRules:WaitForChild("CaseDrop"))
local CaseOpeningFx = require(script.Parent.CaseOpeningFx)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local Popups = require(script.Parent.Popups)
local RewardChips = require(script.Parent.RewardChips)
local Seen = require(script.Parent.Seen)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local M = Config.UI.MagicBall
local ORDER: { string } = Config.Cases.Order
local CASE_NAMES: { [string]: string } = Strings.Items.Cases :: any
local PAD_ACTION = "8ballMagicBallPad"
local WHITE = Color3.new(1, 1, 1)

export type Drop = {
	source: string,
	tier: string,
	climbs: number,
	readyAt: number,
	instant: boolean,
}

local MagicBall = {}

local screenGui: ScreenGui? = nil
local deps: any = nil
local batches = 0

local function words(): any
	return Strings.MagicBall
end

-- A case tier's rarity (its colour, its sting): Standard reads as Common.
local function rarityOf(tier: string): string
	return if tier == "Standard" then "Common" else tier
end

local function colourOf(tier: string, t: number): Color3
	if tier == "Mythic" then
		return CaseOpeningFx.shimmerAt(t)
	end
	return CaseOpeningFx.color(rarityOf(tier))
end

-- The drops from the server, checked: known tiers only.
local function clean(list: any): { Drop }
	local out: { Drop } = {}
	if type(list) ~= "table" then
		return out
	end
	for _, d in list do
		if type(d) == "table" and type(d.tier) == "string" and CaseDrop.rank(d.tier) > 0 then
			table.insert(out, {
				source = if type(d.source) == "string" then d.source else "Drop",
				tier = d.tier,
				climbs = CaseDrop.climbs(d.tier),
				readyAt = if type(d.readyAt) == "number" then d.readyAt else 0,
				instant = d.instant == true,
			})
		end
	end
	-- Rarest last.
	table.sort(out, function(a, b)
		return CaseDrop.rank(a.tier) < CaseDrop.rank(b.tier)
	end)
	return out
end

local function gamepad(): boolean
	return CaseOpeningFx.gamepad()
end

local function label(parent: Instance, name: string, size: number, text: string): TextLabel
	local object = HudParts.text(parent, name, size, text)
	object.TextWrapped = false
	return object
end

-- The ball's picture, or a drawn stand-in while its image is missing.
local function ballImage(parent: Instance, key: string, name: string): ImageLabel
	local image = HudParts.icon(parent, key, name)
	if image.Image == "" then
		image.BackgroundTransparency = 0
		image.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
		HudParts.corner(image, 9999)
	end
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	return image
end

--------------------------------------------------------------------------------------------
-- One reveal
--------------------------------------------------------------------------------------------

type View = {
	drops: { Drop },
	done: () -> (),
	ended: boolean,
	gui: ScreenGui,
	stage: CaseOpeningFx.Stage,
	root: Frame,
	title: TextLabel,
	hint: TextLabel,
	ballHolder: Frame,
	ball: ImageLabel,
	glow: ImageLabel,
	count: TextLabel?,
	meter: Frame,
	fill: Frame,
	finger: ImageLabel,
	skip: TextButton,
	area: TextButton,
	shakes: number,
	need: number,
	climbAt: { number },
	climbed: number,
	tier: string, -- the colour the glow shows now
	phase: string, -- "Shake", "Reveal", "Case"
	offset: number, -- the ball's sideways sway, in natural pixels
	connections: { RBXScriptConnection },
	loops: { UIAnim.Handle },
	born: number,
	selected: GuiObject?,
}

local function stopView(v: View)
	if v.ended then
		return
	end
	v.ended = true
	ContextActionService:UnbindAction(PAD_ACTION)
	for _, connection in v.connections do
		connection:Disconnect()
	end
	for _, loop in v.loops do
		loop.stop()
	end
	Seen.mark("MagicBall")
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(v.gui) then
		GuiService.SelectedObject = nil
	end
	UIAnim.popOut(v.root, function()
		v.gui:Destroy()
	end)
	task.delay(1, function()
		if v.gui.Parent then
			v.gui:Destroy()
		end
	end)
	v.done()
end

-- The case(s) in front at the end: Open now / Later, OK, or Collect.
local function showCases(v: View)
	if v.phase == "Case" or v.ended then
		return
	end
	v.phase = "Case"
	v.skip.Visible = false
	v.meter.Visible = false
	v.finger.Visible = false
	v.hint.Visible = false
	local W = words()
	local stage = v.stage.frame
	for _, child in stage:GetChildren() do
		if child.Name == "Triangle" or child.Name == "Row" then
			child:Destroy()
		end
	end
	UIAnim.popOut(v.ballHolder)
	local drops = v.drops
	local holder = HudParts.frame(stage, "Cases")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromOffset(M.StageWidthPx / 2, M.StageHeightPx / 2 - 20)
	holder.Size = UDim2.fromOffset(M.StageWidthPx, M.CasePx + 70)
	holder.ZIndex = 5
	-- One icon per tier, with its count.
	local tiers: { string } = {}
	local counts: { [string]: number } = {}
	for _, d in drops do
		if not counts[d.tier] then
			table.insert(tiers, d.tier)
			counts[d.tier] = 0
		end
		counts[d.tier] += 1
	end
	local size = if #tiers > 1 then M.SmallCasePx else M.CasePx
	local gap = 14
	local total = #tiers * size + (#tiers - 1) * gap
	for i, tier in tiers do
		local icon = HudParts.icon(holder, RewardChips.caseIcon(tier), "Case" .. i)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Size = UDim2.fromOffset(size, size)
		icon.Position = UDim2.fromOffset(
			M.StageWidthPx / 2 - total / 2 + (i - 1) * (size + gap) + size / 2,
			size / 2
		)
		icon.ZIndex = 6
		local rays = CaseOpeningFx.rays(holder, "Rays" .. i)
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = icon.Position
		rays.Size = UDim2.fromOffset(size * M.RaysShare, size * M.RaysShare)
		rays.ImageColor3 = if tier == "Standard" then WHITE else colourOf(tier, 0)
		rays.ImageTransparency = M.GlowTransparency
		rays.ZIndex = 5
		table.insert(v.loops, UIAnim.spin(rays, M.RaysDegreesPerSecond))
		UIAnim.slam(icon, colourOf(tier, 0))
		table.insert(v.loops, UIAnim.bob(icon))
		if counts[tier] > 1 then
			local n = label(icon, "Count", 26, W.Count:format(counts[tier]))
			n.AnchorPoint = Vector2.new(1, 1)
			n.Position = UDim2.fromScale(1, 1)
			n.Size = UDim2.fromOffset(60, 30)
			n.TextColor3 = HudParts.tone("Gold")
			n.ZIndex = 7
		end
	end
	local first = drops[#drops]
	local name = if #drops == 1
		then CASE_NAMES[first.tier] or first.tier
		else W.ManyCases:format(#drops)
	v.title.Text = name
	v.title.TextColor3 = colourOf(first.tier, 0)
	-- The line under: the timer, or nothing.
	local line = label(holder, "Line", 22, "")
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.fromOffset(M.StageWidthPx / 2, size + 8)
	line.Size = UDim2.fromOffset(M.StageWidthPx - 40, 28)
	line.TextColor3 = HudParts.color(Config.UI.Kit.Numbers.Count)
	line.ZIndex = 6
	if #drops == 1 and not first.instant and first.readyAt > 0 then
		local function refresh()
			local left = first.readyAt - workspace:GetServerTimeNow()
			line.Text = if left > 0 then W.ReadyIn:format(ShopParts.timeLeft(left)) else W.Ready
		end
		refresh()
		table.insert(v.connections, RunService.Heartbeat:Connect(refresh))
	elseif #drops > 1 then
		line.Text = W.InInventory
	end
	-- The buttons.
	local row = HudParts.frame(stage, "Buttons")
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position =
		UDim2.fromOffset(M.StageWidthPx / 2, M.StageHeightPx / 2 - 20 + (M.CasePx + 70) / 2 + 6)
	row.ZIndex = 6
	local buttons: { TextButton } = {}
	local openable = #drops == 1
		and (first.instant or first.readyAt <= workspace:GetServerTimeNow())
	if openable then
		local open = HudParts.candy(row, W.OpenNow, function()
			UISound.play("Click")
			local caseOpening = deps and deps.caseOpening
			local tier = first.tier
			stopView(v)
			if caseOpening then
				task.delay(0.2, function()
					caseOpening:open(tier, 1)
				end)
			end
		end, "Green")
		table.insert(buttons, open)
		local later = HudParts.candy(row, W.Later, function()
			UISound.play("Click")
			stopView(v)
		end, "Blue")
		table.insert(buttons, later)
	else
		local ok = HudParts.candy(row, if #drops > 1 then W.Collect else W.Ok, function()
			UISound.play("Click")
			stopView(v)
		end, "Green")
		table.insert(buttons, ok)
	end
	local width = M.ButtonWidthPx
	row.Size = UDim2.fromOffset(#buttons * width + (#buttons - 1) * 12, M.ButtonPx)
	for i, button in buttons do
		button.Position = UDim2.fromOffset((i - 1) * (width + 12), 0)
		button.Size = UDim2.fromOffset(width, M.ButtonPx)
		HudParts.setButtonTextSize(button, 22)
		HudParts.setMinHit(button, 44)
		button.ZIndex = 7
	end
	UIAnim.popIn(row)
	if gamepad() then
		GuiService.SelectedObject = buttons[1]
	end
end

-- The triangle window: ticks through the tier names slowly to the final one.
local function tickTriangle(
	v: View,
	parent: Instance,
	at: Vector2,
	size: number,
	finalTier: string,
	quick: boolean,
	onDone: () -> ()
)
	local triangle = HudParts.icon(parent, "MagicTriangle", "Triangle")
	triangle.AnchorPoint = Vector2.new(0.5, 0.5)
	triangle.Position = UDim2.fromOffset(at.X, at.Y)
	triangle.Size = UDim2.fromOffset(size, size)
	triangle.ZIndex = 6
	if triangle.Image == "" then
		triangle.BackgroundTransparency = 0
		triangle.BackgroundColor3 = WHITE
		triangle.Rotation = 45
	end
	local text = label(triangle, "Tier", math.floor(size * 0.17), "")
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.36)
	text.Size = UDim2.fromScale(0.8, 0.22)
	text.Rotation = if triangle.Image == "" then -45 else 0
	text.ZIndex = 7
	local W = words()
	local last = CaseDrop.rank(finalTier)
	task.spawn(function()
		local wait = if quick then M.QuickTickSeconds else M.TickSeconds
		for rank = 1, last do
			if v.ended then
				return
			end
			local tier = ORDER[rank]
			text.Text = (W.Tier :: any)[tier] or tier
			local colour = colourOf(tier, 0)
			triangle.ImageColor3 = WHITE:Lerp(colour, 0.85)
			text.TextColor3 = WHITE
			UISound.play("ReelTick", 0.9 + rank * 0.05)
			UIAnim.bounce(triangle)
			if rank < last then
				task.wait(wait)
				wait *= M.TickSlowdown
			end
		end
		if v.ended then
			return
		end
		UIAnim.glowBurst(triangle, colourOf(finalTier, 0), 1.6)
		table.insert(v.loops, UIAnim.sparkle(triangle, colourOf(finalTier, 0)))
		CaseOpeningFx.sting(rarityOf(finalTier))
		task.wait(M.HoldSeconds)
		onDone()
	end)
end

-- Full: the ball turns round to its window, then the triangle(s) tick to the server's tiers.
local function reveal(v: View)
	if v.phase ~= "Shake" or v.ended then
		return
	end
	v.phase = "Reveal"
	v.finger.Visible = false
	v.hint.Visible = false
	v.meter.Visible = false
	v.offset = 0
	local drops = v.drops
	local ball = v.ball
	local turn = TweenService:Create(
		ball,
		TweenInfo.new(M.FlipSeconds / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = UDim2.fromOffset(4, M.BallPx) }
	)
	turn.Completed:Once(function()
		if v.ended then
			return
		end
		HudParts.setIcon(ball, "MagicBallWindow")
		TweenService:Create(
			ball,
			TweenInfo.new(M.FlipSeconds / 2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(M.BallPx, M.BallPx) }
		):Play()
		task.wait(M.FlipSeconds / 2)
		if v.ended then
			return
		end
		if #drops == 1 then
			tickTriangle(
				v,
				v.ballHolder,
				Vector2.new(M.BallPx / 2, M.BallPx / 2),
				math.floor(M.BallPx * M.TriangleShare),
				drops[1].tier,
				false,
				function()
					showCases(v)
				end
			)
			return
		end
		-- Many: the ball bursts into a row of triangles, rarest last.
		UIAnim.glowBurst(ball, WHITE, 2)
		UISound.play("ReelSettle")
		UIAnim.popOut(v.ballHolder)
		local rowCount = math.min(#drops, M.RowMax)
		local size = math.floor(math.min(M.TrianglePx, (M.StageWidthPx - 40) / rowCount - 8))
		local lines = math.ceil(#drops / rowCount)
		local index = 0
		local function nextOne()
			index += 1
			if index > #drops or v.ended then
				showCases(v)
				return
			end
			local line = math.floor((index - 1) / rowCount)
			local col = (index - 1) % rowCount
			local inLine = math.min(rowCount, #drops - line * rowCount)
			local x = M.StageWidthPx / 2 + (col - (inLine - 1) / 2) * (size + 8)
			local y = M.StageHeightPx / 2 + (line - (lines - 1) / 2) * (size + 10)
			tickTriangle(
				v,
				v.stage.frame,
				Vector2.new(x, y),
				size,
				drops[index].tier,
				index < #drops,
				nextOne
			)
		end
		nextOne()
	end)
	turn:Play()
end

-- One shake: the ball jolts, the meter fills, and at a climb the glow jumps a colour.
local function shake(v: View, direction: number)
	if v.phase ~= "Shake" or v.ended then
		return
	end
	v.shakes += 1
	v.finger.Visible = false
	UISound.play("ReelTick", 0.8 + 0.05 * v.shakes)
	v.offset = direction * M.JoltPx
	local u = math.clamp(v.shakes / v.need, 0, 1)
	TweenService:Create(v.fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(u, 1) }):Play()
	while v.climbed < #v.climbAt and v.shakes >= v.climbAt[v.climbed + 1] do
		v.climbed += 1
		v.tier = ORDER[math.min(v.climbed + 1, #ORDER)]
		UISound.play("Claim", 1 + 0.1 * v.climbed)
		UIAnim.glowBurst(v.ball, colourOf(v.tier, 0), 1.8)
		UIAnim.bounce(v.ballHolder)
	end
	if v.shakes >= v.need then
		task.delay(M.FullPauseSeconds, function()
			reveal(v)
		end)
	end
end

-- The shakes the meter needs, and the shakes the climbs land on (evenly over them).
local function plan(climbs: number): (number, { number })
	local need = M.Shakes
	local at = {}
	for i = 1, climbs do
		table.insert(at, math.max(1, math.floor(i * need / (climbs + 1) + 0.5)))
	end
	return need, at
end

local function play(drops: { Drop }, done: () -> ())
	local parent = screenGui
	if not parent or #drops == 0 then
		done()
		return
	end
	local W = words()
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "MagicBall"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = parent.DisplayOrder + M.DisplayOrderAbove
	gui.Parent = playerGui
	local backdrop = Instance.new("TextButton") -- swallows presses meant for what is behind
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Selectable = false
	backdrop.BorderSizePixel = 0
	backdrop.BackgroundColor3 = HudParts.tone("Ink")
	backdrop.BackgroundTransparency = M.BackdropTransparency
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui
	local root = HudParts.frame(gui, "Root")
	root.Size = UDim2.fromScale(1, 1)
	root.SelectionGroup = true
	local stage = CaseOpeningFx.stage(root, "Stage")
	local frame = stage.frame
	-- The whole stage is the drag / tap area.
	local area = Instance.new("TextButton")
	area.Name = "Area"
	area.Text = ""
	area.AutoButtonColor = false
	area.BackgroundTransparency = 1
	area.Size = UDim2.fromScale(1, 1)
	area.Selectable = false
	area.ZIndex = 1
	area.Parent = frame
	local title = label(frame, "Title", M.TitlePx, W.Title)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromOffset(M.StageWidthPx / 2, 8)
	title.Size = UDim2.fromOffset(M.StageWidthPx - 20, M.TitlePx + 8)
	title.TextColor3 = HudParts.tone("Gold")
	title.ZIndex = 4
	local hintWords = if gamepad()
		then W.HintPad
		elseif CaseOpeningFx.touch() then W.HintTouch
		else W.HintMouse
	local hint = label(frame, "Hint", M.HintPx, hintWords)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.fromOffset(M.StageWidthPx / 2, M.TitlePx + 14)
	hint.Size = UDim2.fromOffset(M.StageWidthPx - 20, M.HintPx + 6)
	hint.ZIndex = 4
	-- The ball, its glow behind, the "x10".
	local ballHolder = HudParts.frame(frame, "BallHolder")
	ballHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	ballHolder.Size = UDim2.fromOffset(M.BallPx, M.BallPx)
	ballHolder.Position = UDim2.fromOffset(M.StageWidthPx / 2, M.StageHeightPx / 2 + 10)
	ballHolder.ZIndex = 3
	-- Turning rays behind it in the colour of the tier it has climbed to.
	local glow = CaseOpeningFx.rays(ballHolder, "Glow")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromOffset(M.BallPx * M.RaysShare, M.BallPx * M.RaysShare)
	glow.ZIndex = 2
	local ball = ballImage(ballHolder, "MagicBall", "Ball")
	ball.Position = UDim2.fromScale(0.5, 0.5)
	ball.Size = UDim2.fromOffset(M.BallPx, M.BallPx)
	ball.ZIndex = 3
	local count: TextLabel? = nil
	if #drops > 1 then
		local n = label(ballHolder, "Count", M.CountPx, W.Count:format(#drops))
		n.AnchorPoint = Vector2.new(1, 0)
		n.Position = UDim2.fromScale(1.05, -0.05)
		n.Size = UDim2.fromOffset(120, M.CountPx + 6)
		n.TextColor3 = HudParts.tone("Gold")
		n.ZIndex = 5
		count = n
	end
	-- The meter under it.
	local meter = HudParts.frame(frame, "Meter")
	meter.AnchorPoint = Vector2.new(0.5, 0)
	meter.Position =
		UDim2.fromOffset(M.StageWidthPx / 2, M.StageHeightPx / 2 + 10 + M.BallPx / 2 + 16)
	meter.Size = UDim2.fromOffset(M.MeterWidthPx, M.MeterPx)
	meter.BackgroundTransparency = 0
	meter.BackgroundColor3 = HudParts.tone("Ink")
	meter.ZIndex = 4
	HudParts.corner(meter, M.MeterPx)
	local fill = HudParts.frame(meter, "Fill")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = HudParts.tone("Gold")
	fill.ZIndex = 5
	HudParts.corner(fill, M.MeterPx)
	-- The see-through finger sweeping back and forth.
	local finger = HudParts.icon(frame, "HandPointer", "Finger")
	finger.AnchorPoint = Vector2.new(0.5, 0)
	finger.Size = UDim2.fromOffset(M.FingerPx, M.FingerPx)
	finger.ImageTransparency = M.FingerTransparency
	finger.ZIndex = 6
	-- Skip, once it was seen.
	-- The candy's own action (its enlarged hit area calls only that), set once the view exists.
	local onSkip: () -> () = function() end
	local skip = HudParts.candy(frame, W.Skip, function()
		onSkip()
	end, "White")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1) -- bottom right, clear of the title
	skip.Position = UDim2.fromOffset(M.StageWidthPx - 8, M.StageHeightPx - 8)
	skip.Size = UDim2.fromOffset(M.SkipWidthPx, M.SkipHeightPx)
	skip.ZIndex = 8
	skip.Visible = Seen.get("MagicBall")
	HudParts.setMinHit(skip, 44)

	local need, climbAt = plan(if #drops == 1 then drops[1].climbs else 0)
	local v: View = {
		drops = drops,
		done = done,
		ended = false,
		gui = gui,
		stage = stage,
		root = root,
		title = title,
		hint = hint,
		ballHolder = ballHolder,
		ball = ball,
		glow = glow,
		count = count,
		meter = meter,
		fill = fill,
		finger = finger,
		skip = skip,
		area = area,
		shakes = 0,
		need = need,
		climbAt = climbAt,
		climbed = 0,
		tier = "Standard",
		phase = "Shake",
		offset = 0,
		connections = {},
		loops = {},
		born = os.clock(),
		selected = nil,
	}
	onSkip = function()
		UISound.play("Click")
		showCases(v)
	end
	table.insert(v.loops, UIAnim.shake(title, "Wiggle"))

	-- Fit the stage to the screen.
	local function fit()
		stage.fit(Vector2.new(M.StageWidthPx, M.StageHeightPx), M.MinScale, M.MaxScale, 8)
		frame.Size = UDim2.fromOffset(M.StageWidthPx, M.StageHeightPx)
	end
	fit()
	table.insert(v.connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))

	-- Every frame: the sway back to the middle, the finger, the glow's colour.
	table.insert(
		v.connections,
		RunService.RenderStepped:Connect(function(dt: number)
			local t = os.clock() - v.born
			v.offset *= math.exp(-dt * M.SwayReturnPerSecond)
			if v.phase == "Shake" then
				ball.Rotation = v.offset * M.RotatePerPx
				ball.Position = UDim2.new(0.5, v.offset, 0.5, 0)
				finger.Position = UDim2.fromOffset(
					M.StageWidthPx / 2 + math.sin(t * M.FingerSpeed) * M.FingerSweepPx,
					M.StageHeightPx / 2 + 10 + M.BallPx * 0.15
				)
			end
			glow.ImageColor3 = if v.tier == "Standard" then WHITE else colourOf(v.tier, t)
			glow.ImageTransparency = M.GlowTransparency + 0.1 * math.sin(t * 3)
			glow.Rotation = (t * M.RaysDegreesPerSecond) % 360
		end)
	)

	-- Drag back and forth: a turn after at least ShakeMinPx counts as a shake.
	local dragging: InputObject? = nil
	local direction = 0
	local peak = 0
	local start = 0
	local moved = false
	table.insert(
		v.connections,
		area.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = input
				direction = 0
				start = input.Position.X
				peak = start
				moved = false
			end
		end)
	)
	table.insert(
		v.connections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if v.phase ~= "Shake" then
				return
			end
			local drag = dragging
			if
				drag
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or (input.UserInputType == Enum.UserInputType.Touch and input == drag)
				)
			then
				local x = input.Position.X
				local scale = stage.scale.Scale
				local minPx = M.ShakeMinPx * scale
				if math.abs(x - start) > minPx * 0.5 then
					moved = true
				end
				v.offset = math.clamp((x - start) / scale, -M.SwayPx, M.SwayPx)
				if direction == 0 then
					if math.abs(x - start) >= minPx then
						direction = if x > start then 1 else -1
						peak = x
					end
				elseif direction == 1 then
					if x > peak then
						peak = x
					elseif peak - x >= minPx then
						shake(v, -1)
						direction = -1
						peak = x
					end
				else
					if x < peak then
						peak = x
					elseif x - peak >= minPx then
						shake(v, 1)
						direction = 1
						peak = x
					end
				end
			elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
				-- The stick side to side.
				local x = input.Position.X
				if x > M.StickThreshold and direction ~= 1 then
					direction = 1
					shake(v, 1)
				elseif x < -M.StickThreshold and direction ~= -1 then
					direction = -1
					shake(v, -1)
				end
			end
		end)
	)
	table.insert(
		v.connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if
				dragging
				and (input.UserInputType == Enum.UserInputType.MouseButton1 or input == dragging)
			then
				-- A tap or click with no drag counts as a shake too.
				if not moved then
					shake(v, if v.shakes % 2 == 0 then 1 else -1)
				end
				dragging = nil
				direction = 0
			end
		end)
	)
	-- A real shake of a phone.
	if UserInputService.AccelerometerEnabled then
		local last = Vector3.zero
		local lastShake = 0
		table.insert(
			v.connections,
			UserInputService.DeviceAccelerationChanged:Connect(function(input: InputObject)
				local a = input.Position
				if (a - last).Magnitude > M.AccelThreshold and os.clock() - lastShake > 0.15 then
					lastShake = os.clock()
					shake(v, if a.X > last.X then 1 else -1)
				end
				last = a
			end)
		)
	end
	-- A on a gamepad counts as a shake (and presses the selected button at the end).
	ContextActionService:BindActionAtPriority(
		PAD_ACTION,
		function(_name: string, state: Enum.UserInputState, input: InputObject)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if input.KeyCode == Enum.KeyCode.ButtonA and v.phase == "Shake" then
				shake(v, if v.shakes % 2 == 0 then 1 else -1)
				return Enum.ContextActionResult.Sink
			elseif input.KeyCode == Enum.KeyCode.ButtonY and skip.Visible then
				showCases(v)
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.ContextActionPriority.High.Value + 30,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonY
	)
	UIAnim.popIn(root)
	UISound.play("Banner")
end

--------------------------------------------------------------------------------------------
-- Starting
--------------------------------------------------------------------------------------------

--- Queue a reveal for drops the server sent (one reveal for the whole list). Not while the
--- tutorial runs (TutorialActive): it shows its own drops, which would otherwise play again
--- once it ends (the tutorial lane's request).
function MagicBall.push(list: any)
	local drops = clean(list)
	local player = Players.LocalPlayer
	if #drops == 0 or (player and player:GetAttribute("TutorialActive") == true) then
		return
	end
	batches += 1
	Popups.push({
		id = "MagicBall" .. batches,
		show = function(done: () -> ())
			play(drops, done)
		end,
	})
end

--- Listen for drops: the CaseDrop remote (Mystery Cases, rewards, /freecase) and a win's drop
--- on MatchSummary (shown after the result screen closes, through the popup queue).
function MagicBall.start(screen: ScreenGui, d: any)
	screenGui = screen
	deps = d
	task.spawn(function()
		local ok, remote = pcall(Net.get, "CaseDrop")
		if ok and typeof(remote) == "Instance" and remote:IsA("RemoteEvent") then
			(remote :: RemoteEvent).OnClientEvent:Connect(function(list: any)
				-- A reward's drops come just before its RewardGiven: its popup goes first.
				task.delay(M.QueueDelaySeconds, MagicBall.push, list)
			end)
		end
	end)
	task.spawn(function()
		local ok, remote = pcall(Net.get, "MatchSummary")
		if ok and typeof(remote) == "Instance" and remote:IsA("RemoteEvent") then
			(remote :: RemoteEvent).OnClientEvent:Connect(function(summary: any)
				if type(summary) == "table" and type(summary.caseDrop) == "table" then
					MagicBall.push({ summary.caseDrop })
				end
			end)
		end
	end)
	GuiQA.add("magicBall", function(tier: string?, n: number?)
		local list = {}
		for i = 1, n or 1 do
			local t = tier or ORDER[((i - 1) % #ORDER) + 1]
			table.insert(list, { source = "Dev", tier = t, readyAt = 0, instant = true })
		end
		MagicBall.push(list)
		return #list
	end)
end

return MagicBall
