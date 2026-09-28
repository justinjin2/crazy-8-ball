--!strict
-- RewardChips: the small reward chips on the result screen and NEW RANK!
-- (docs/prompts/ECONOMY_UI_PROMPT.md sections 9 and 13), and the flight of a case or a cue from
-- its chip into the left column's Inventory tile.
--
-- A chip is a white kit pill with its picture on the left and its words after it: money (the
-- single cash bundle and "+$300" in green), a case (its own chest and "x2", or "+1 Standard
-- Case"), a cue (its thumbnail and its name) or a chat tag (the speech bubble and the tag drawn
-- as chat draws it, ChatTags). Chips only draw: money still flies with CashFlyer, which lands it
-- in the money HUD.
--
-- A case or a cue flies as a copy of its picture: it pops up off the chip, hangs a moment,
-- then arcs into the Inventory tile (MenuColumn.tileCenter, read every frame, so a column
-- still popping in is followed), shrinking, and the tile bounces as it lands. The column hides
-- under the popups, so while anything is on its way (and a moment after) `catching()` is true
-- and Progression shows the column to catch it. With no column the copy just pops away.
-- Tuning in Config.UI.Progress.Chips. It also words the XP boosts ("ROOKIE x2") for the
-- result screen and the rank HUD.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.Progress.Chips
local K = Config.UI.Kit
local ICONS: { [string]: string } = K.Icons :: any
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]

--- What a chip shows. `text` is its words (RichText when `rich`, measured by `plain`).
export type Spec = {
	kind: string, -- "Money", "Case", "Cue" or "Tag"
	text: string,
	plain: string?, -- the words without markup (a rich tag), for measuring
	rich: boolean?,
	id: string?, -- the case or cue id: its picture
	tint: Color3?, -- the words' colour (the kit's white when nil)
}

export type Chip = {
	root: Frame,
	picture: GuiObject,
	words: TextLabel,
	spec: Spec,
	width: number,
}

-- A copy of a picture on its way to a column tile.
type Flight = {
	kind: string,
	id: string?,
	from: GuiObject, -- the picture it copies (its place and size when it pops)
	deps: any, -- the economy's shared deps: `column`
	target: string, -- the column tile's name
	startAt: number, -- os.clock() when it pops
	layer: Frame,
	ghost: GuiObject?,
	scale: UIScale?,
	start: Vector2?,
	done: boolean,
}

local RewardChips = {}

-- Flights queued or on their way, the frame loop that moves them, one copy layer per screen,
-- and until when the column is still wanted after the last landing.
local flights: { Flight } = {}
local loop: RBXScriptConnection? = nil
local layers: { [ScreenGui]: Frame } = {}
local holdUntil = 0

-- A number for a boost's words: "2", "1.5", "25".
local function number(value: number): string
	local rounded = math.floor(value * 10 + 0.5) / 10
	return if rounded == math.floor(rounded)
		then tostring(math.floor(rounded))
		else ("%.1f"):format(rounded)
end

--- An XP boost's words (ECONOMY 4.5) from its kind ("Rookie", "Vip", "FirstWin", "Streak")
--- and its share (1.0 for +100%): +100% or more as a multiplier ("ROOKIE x2"), less as a
--- percent ("VIP +50%"). Nil for an unknown kind.
function RewardChips.boostWords(kind: string, share: number): string?
	local times: { [string]: string } = Strings.Progress.BoostTimes :: any
	local percent: { [string]: string } = Strings.Progress.BoostPercent :: any
	if type(share) ~= "number" or share ~= share or share <= 0 then
		return nil
	end
	if share >= 1 then
		local words = times[kind]
		return if words then words:format(number(1 + share)) else nil
	end
	local words = percent[kind]
	return if words then words:format(number(share * 100)) else nil
end

--- A case's chest icon key in Config.UI.Kit.Icons ("CaseEpic"), the plain case chest when that
--- case has no icon of its own.
function RewardChips.caseIcon(caseId: string?): string
	local key = if caseId then "Case" .. caseId else "Case"
	return if ICONS[key] and ICONS[key] ~= "" then key else "Case"
end

-- The picture's width for a chip `height` tall: the cash bundle is wide, the rest square.
local function pictureWidth(kind: string, height: number): number
	local inner = height - 4
	return math.floor(if kind == "Money" then inner * C.CashWidthShare else inner)
end

-- A picture: the cash bundle, a case's chest, the chat bubble, or a cue's thumbnail.
local function makePicture(parent: Instance, kind: string, id: string?): GuiObject
	if kind == "Cue" then
		return CueThumb.new(parent, id or "")
	end
	local key = if kind == "Money"
		then "CashSingle"
		elseif kind == "Case" then RewardChips.caseIcon(id)
		else "ChatTag"
	return HudParts.icon(parent, key, "Picture")
end

--- How wide a chip is at `height` with words `textPx` tall.
function RewardChips.width(spec: Spec, height: number, textPx: number): number
	local words =
		TextService:GetTextSize(spec.plain or spec.text, textPx, FONT, Vector2.new(10000, 1000)).X
	return math.ceil(C.PadPx + pictureWidth(spec.kind, height) + C.GapPx + words + C.EndPadPx)
end

--- A chip in `parent`, `height` tall with words `textPx` tall, hidden (pop it in). Place it
--- with its root; its size is set.
function RewardChips.new(parent: Instance, spec: Spec, height: number, textPx: number): Chip
	local width = RewardChips.width(spec, height, textPx)
	local root = HudParts.pill(parent, spec.kind .. "Chip")
	root.Size = UDim2.fromOffset(width, height)
	root.Visible = false
	local pictureW = pictureWidth(spec.kind, height)
	local picture = makePicture(root, spec.kind, spec.id)
	picture.Name = "Picture"
	picture.Position = UDim2.fromOffset(C.PadPx, 2)
	picture.Size = UDim2.fromOffset(pictureW, height - 4)
	picture.ZIndex = 2
	local left = C.PadPx + pictureW + C.GapPx
	local words = HudParts.text(root, "Words", textPx, spec.text, spec.tint)
	words.RichText = spec.rich == true
	words.AutoLocalize = false -- a number, a name or a tag, worded from Strings already
	words.TextWrapped = false
	words.TextXAlignment = Enum.TextXAlignment.Left
	words.Position = UDim2.fromOffset(left, 1)
	-- Relative to the chip, so a chip made narrower than its words shrinks them to fit.
	words.Size = UDim2.new(1, -(left + C.EndPadPx - 2), 1, -2)
	words.ZIndex = 2
	return { root = root, picture = picture, words = words, spec = spec, width = width }
end

--- Lay chips out in centred rows no wider than `maxWidth` (a chip wider than that gets a row of
--- its own), from `top` in their parent, around the middle `centreX`. Returns how tall the
--- rows are and the widest row.
function RewardChips.flow(
	chips: { Chip },
	centreX: number,
	top: number,
	maxWidth: number,
	height: number,
	gap: number,
	rowGap: number
): (number, number)
	local rows: { { Chip } } = {}
	local widths: { number } = {}
	for _, chip in chips do
		local row = rows[#rows]
		local wide = if row then widths[#rows] + gap + chip.width else math.huge
		if row and wide <= maxWidth then
			table.insert(row, chip)
			widths[#rows] = wide
		else
			table.insert(rows, { chip })
			table.insert(widths, chip.width)
		end
	end
	local widest = 0
	for r, row in rows do
		local x = centreX - widths[r] / 2
		local y = top + (r - 1) * (height + rowGap)
		for _, chip in row do
			chip.root.AnchorPoint = Vector2.new(0, 0)
			chip.root.Position = UDim2.fromOffset(math.floor(x + 0.5), y)
			x += chip.width + gap
		end
		widest = math.max(widest, widths[r])
	end
	local tall = if #rows > 0 then #rows * height + (#rows - 1) * rowGap else 0
	return tall, widest
end

--- How tall `count` chips of these widths would be in rows no wider than `maxWidth` (as flow
--- lays them), and the widest row.
function RewardChips.measure(
	widthsOf: { number },
	maxWidth: number,
	height: number,
	gap: number,
	rowGap: number
): (number, number)
	local rows, current, widest = 0, 0, 0
	for _, width in widthsOf do
		if rows > 0 and current + gap + width <= maxWidth then
			current += gap + width
		else
			rows += 1
			current = width
		end
		widest = math.max(widest, current)
	end
	return if rows > 0 then rows * height + (rows - 1) * rowGap else 0, widest
end

--------------------------------------------------------------------------------------------
-- Flights into the left column
--------------------------------------------------------------------------------------------

-- The copies' layer in `screen`, over everything (made once per screen).
local function layerIn(screen: ScreenGui): Frame
	local old = layers[screen]
	if old and old.Parent then
		return old
	end
	local layer = HudParts.frame(screen, "ItemFlyer")
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = C.ZIndex
	layers[screen] = layer
	return layer
end

-- Where a flight lands: its tile's centre now, or nil (no column, or no such tile).
local function targetOf(flight: Flight): Vector2?
	local column = if type(flight.deps) == "table" then flight.deps.column else nil
	if not column then
		return nil
	end
	local ok, point = pcall(column.tileCenter, column, flight.target)
	return if ok and typeof(point) == "Vector2" then point else nil
end

-- The copy lands (or gives up): gone, the tile bounces, and the column stays a moment more.
local function land(flight: Flight, arrived: boolean)
	if flight.done then
		return
	end
	flight.done = true
	if flight.ghost then
		flight.ghost:Destroy()
		flight.ghost = nil
	end
	holdUntil = math.max(holdUntil, os.clock() + C.HoldSeconds)
	if arrived then
		local column = if type(flight.deps) == "table" then flight.deps.column else nil
		if column then
			pcall(column.bump, column, flight.target)
		end
		UISound.play(C.LandSound, C.LandPitch)
	end
end

-- Draw a flight's copy over its picture, where the picture is now.
local function build(flight: Flight)
	local from = flight.from
	local size = from.AbsoluteSize
	local ghost = makePicture(flight.layer, flight.kind, flight.id)
	ghost.Name = "Flying" .. flight.kind
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Size = UDim2.fromOffset(math.max(8, size.X), math.max(8, size.Y))
	ghost.Visible = false
	local scale = Instance.new("UIScale")
	scale.Parent = ghost
	flight.ghost = ghost
	flight.scale = scale
	flight.start = from.AbsolutePosition + size / 2
end

-- A point `t` (0..1) along the arc from `a` to `b`: it rises first, then swoops in.
local function arc(a: Vector2, b: Vector2, t: number): Vector2
	local lift = math.max(C.ArcMinLiftPx, (b - a).Magnitude * C.ArcLiftShare)
	local control = a:Lerp(b, 0.3) - Vector2.new(0, lift)
	return a:Lerp(control, t):Lerp(control:Lerp(b, t), t)
end

local function step()
	local now = os.clock()
	local popEnd = C.PopSeconds
	local hangEnd = popEnd + C.HangSeconds
	local flyEnd = hangEnd + C.FlySeconds
	local keep: { Flight } = {}
	for _, flight in flights do
		local elapsed = now - flight.startAt
		if not flight.done and elapsed >= 0 then
			if not flight.ghost then
				-- Its chip may have gone with its screen before its turn: nothing to copy.
				local gone = not flight.from.Parent or not flight.layer.Parent
				if gone or not pcall(build, flight) then
					land(flight, false)
				end
			end
			local ghost, scale, start = flight.ghost, flight.scale, flight.start
			if ghost and scale and start then
				local target = targetOf(flight)
				local origin = flight.layer.AbsolutePosition
				local point, size, fade = start, 1, 0
				if elapsed >= flyEnd then
					land(flight, target ~= nil)
				elseif elapsed < popEnd then
					size = 1 + (C.PopScale - 1) * UIAnim.backOut(elapsed / popEnd)
				elseif elapsed < hangEnd then
					size = C.PopScale
				else
					local t = (elapsed - hangEnd) / C.FlySeconds
					local eased = t * t * (3 - 2 * t)
					if target then
						point = arc(start, target, eased)
						size = C.PopScale + (C.EndScale - C.PopScale) * eased
					else
						size = C.PopScale * (1 - eased) -- nowhere to go: it shrinks away
						fade = eased
					end
				end
				if not flight.done then
					ghost.Position = UDim2.fromOffset(point.X - origin.X, point.Y - origin.Y)
					ghost.Visible = true
					scale.Scale = math.max(0.01, size)
					if ghost:IsA("ImageLabel") then
						ghost.ImageTransparency = fade
					end
				end
			end
		end
		if not flight.done then
			table.insert(keep, flight)
		end
	end
	flights = keep
	if #keep == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

--- Fly a copy of `chip`'s picture (a case or a cue) into the column tile `target`
--- ("Inventory") after `delay` seconds. `screen` is the ScreenGui the copy is drawn in; `deps`
--- the economy's shared table (its `column`, read when the copy flies). The chip itself stays.
function RewardChips.fly(screen: ScreenGui, chip: Chip, deps: any, target: string, delay: number?)
	local flight: Flight = {
		kind = chip.spec.kind,
		id = chip.spec.id,
		from = chip.picture,
		deps = deps,
		target = target,
		startAt = os.clock() + math.max(0, delay or 0),
		layer = layerIn(screen),
		ghost = nil,
		scale = nil,
		start = nil,
		done = false,
	}
	table.insert(flights, flight)
	if not loop then
		loop = RunService.RenderStepped:Connect(function()
			local ok, err: any = pcall(step)
			if not ok then
				warn("[8ball] RewardChips: " .. tostring(err))
				for _, each in flights do
					land(each, false)
				end
				flights = {}
				if loop then
					loop:Disconnect()
					loop = nil
				end
			end
		end)
	end
end

--- Whether something is on its way to the column (or just landed): Progression shows the
--- column meanwhile, even under a popup, so the tile is there to catch it.
function RewardChips.catching(): boolean
	return #flights > 0 or os.clock() < holdUntil
end

return RewardChips
