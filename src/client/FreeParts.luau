--!strict
-- FreeParts: what the Free Reward menu's sections share (FreeDaily, FreePlaytime, FreeTrack,
-- FreeSocial):
--   * a reward's pictures side by side: the cash stack, each lucky block's own picture once
--     per block (up to Pictures.MaxCopies, overlapping, "x5" past that), the ability spin with
--     "+2", the way the mocks draw them (picks "daily A" and "free_other A", 2026-10-08);
--   * a tile's status button: Claim! (green), Claimed (grey with a check), Locked (grey with a
--     padlock), Tomorrow, Play a match, a countdown (white with a stopwatch) or only a padlock;
--   * the words for what comes with a big prize's block ("+2 Ability Spins").
-- Placed in the Grand Opening card's units at the page's scale k, as the Shop's parts
-- (ShopCards). Sizes in Config.UI.FreeReward, words in Strings.FreeReward.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local RewardsParts = require(script.Parent.RewardsParts)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)

local F = Config.UI.FreeReward
local PIC = F.Pictures
local PILL_MIN = Config.UI.GrandOpeningCard.Layout.PillMinTextPx
local K = Config.UI.Kit
local ICONS: { [string]: string } = K.Icons :: any
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local NAMES: { [string]: string } = Strings.LuckyBlocks.Names :: any
local W = Strings.FreeReward
local round = ShopCards.round

local FreeParts = {}

--------------------------------------------------------------------------------------------
-- A reward's pictures
--------------------------------------------------------------------------------------------

-- One picture: its image, how much it tucks under the one before (a share of its size), the
-- chip on its corner ("+2", "x5"; "" none) and its size (a share: the cash stack is bigger).
type Shot = { image: string, overlap: number, chip: string, share: number }

export type Pictures = {
	root: Frame, -- placed by layoutPictures (AnchorPoint 0.5, 0.5)
	images: { ImageLabel },
	chips: { TextLabel },
	shots: { Shot },
	z: number,
	tint: Color3,
}

--- The picture of lucky block `kind` (Config.LuckyBlocks.Kinds), else the gift box.
function FreeParts.blockImage(kind: string): string
	local row = KINDS[kind]
	local id = if row then row.Icon else nil
	return if type(id) == "string" and id ~= "" then id else ICONS.Gift or ""
end

--- Pictures of a reward in `parent` (at ZIndex `z` and up to z + 12).
function FreeParts.pictures(parent: Instance, name: string, z: number): Pictures
	local root = HudParts.frame(parent, name)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.ZIndex = z
	return { root = root, images = {}, chips = {}, shots = {}, z = z, tint = Color3.new(1, 1, 1) }
end

-- Picture `index`'s image and chip, made when first needed.
local function slot(p: Pictures, index: number): (ImageLabel, TextLabel)
	local image = p.images[index]
	local chip = p.chips[index]
	if image and chip then
		return image, chip
	end
	local made = ShopCards.image(p.root, "Picture" .. index, "", p.z + index)
	local words = HudParts.text(p.root, "Chip" .. index, ShopCards.textPx(PIC.CountUnits, 1), "")
	words.AutoLocalize = false -- "x5", "+2"
	words.TextWrapped = false
	words.AnchorPoint = Vector2.new(1, 1)
	words.TextXAlignment = Enum.TextXAlignment.Right
	words.ZIndex = p.z + 12
	p.images[index] = made
	p.chips[index] = words
	return made, words
end

--- Show `reward` (a RewardsParts.Reward): the cash stack, the blocks, the spins.
function FreeParts.setPictures(p: Pictures, reward: RewardsParts.Reward)
	local shots: { Shot } = {}
	local function add(image: string, chip: string, share: number, overlap: number)
		table.insert(shots, {
			image = image,
			overlap = if #shots == 0 then 0 else overlap,
			chip = chip,
			share = share,
		})
	end
	if reward.money > 0 then
		add(ICONS.CashStack or "", "", PIC.CashShare, PIC.ItemOverlap)
	end
	for _, entry in reward.blocks do
		local image = FreeParts.blockImage(entry.kind)
		local copies = math.min(entry.count, PIC.MaxCopies)
		for copy = 1, copies do
			local chip = if copy == copies and entry.count > copies
				then W.CountChip:format(entry.count)
				else ""
			add(image, chip, 1, if copy == 1 then PIC.ItemOverlap else PIC.CopyOverlap)
		end
	end
	if reward.spins > 0 then
		add(ICONS.UltSpin or "", W.SpinChip:format(reward.spins), 1, PIC.ItemOverlap)
	end
	if reward.lucky > 0 then
		add(ICONS.Lucky or "", W.SpinChip:format(reward.lucky), 1, PIC.ItemOverlap)
	end
	p.shots = shots
	for index, shot in shots do
		local image, chip = slot(p, index)
		if image.Image ~= shot.image then
			image.Image = shot.image
		end
		image.Visible = true
		chip.Text = shot.chip
		chip.Visible = shot.chip ~= ""
	end
	for index = #shots + 1, #p.images do
		p.images[index].Visible = false
		p.chips[index].Visible = false
	end
	FreeParts.tintPictures(p, p.tint)
end

--- Tint the pictures (white: as drawn), a claimed day's grey under its check. A tint, not a
--- fade: the menu's open drives every transparency from what it read as it started.
function FreeParts.tintPictures(p: Pictures, tint: Color3)
	p.tint = tint
	for _, image in p.images do
		image.ImageColor3 = tint
	end
end

--- The tint of a claimed reward's pictures (Config.UI.FreeReward.ClaimedTint), else white.
function FreeParts.claimedTint(claimed: boolean): Color3
	return if claimed then ShopCards.rgb(F.ClaimedTint) else Color3.new(1, 1, 1)
end

--- Lay the pictures out centred on (x, y) units, each `size` units square, the row at most
--- `widest` units wide (they shrink to fit), at the scale `k`.
function FreeParts.layoutPictures(
	p: Pictures,
	k: number,
	x: number,
	y: number,
	size: number,
	widest: number
)
	local shots = p.shots
	local px = size * k
	local function across(one: number): number
		local width = 0
		for index, shot in shots do
			local w = one * shot.share
			width += if index == 1 then w else w * (1 - shot.overlap)
		end
		return width
	end
	local total = across(px)
	local most = widest * k
	if total > most and total > 0 then
		px *= most / total
		total = most
	end
	p.root.Position = UDim2.fromOffset(round(x * k), round(y * k))
	p.root.Size = UDim2.fromOffset(math.max(1, round(total)), math.max(1, round(px)))
	-- A chip sits over its picture, so on a phone it may go under MinTextPx (as the shop's pills).
	local chipPx = math.max(PILL_MIN, round(PIC.CountUnits * k))
	local at = 0
	for index, shot in shots do
		local one = px * shot.share
		if index > 1 then
			at -= one * shot.overlap
		end
		local image, chip = p.images[index], p.chips[index]
		image.Position = UDim2.fromOffset(round(at + one / 2), round(px / 2))
		image.Size = UDim2.fromOffset(round(one), round(one))
		chip.Position = UDim2.fromOffset(round(at + one + chipPx * 0.2), round(px / 2 + one / 2))
		chip.Size = UDim2.fromOffset(round(one), chipPx + 6)
		HudParts.setTextSize(chip, chipPx)
		at += one
	end
	p.root.Visible = #shots > 0
end

--------------------------------------------------------------------------------------------
-- A tile's status button
--------------------------------------------------------------------------------------------

-- What each status button shows now (its mode, words and busy), so a tick changes nothing
-- that is already right.
local shown: { [TextButton]: string } = setmetatable({}, { __mode = "k" }) :: any

--- A status button (a kit candy) centred on its position; `onPress` claims.
function FreeParts.status(parent: Instance, name: string, onPress: () -> ()): TextButton
	local button = HudParts.candy(parent, "", onPress, "Green")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.ZIndex = 6
	return button
end

--- Show a status: "Claim" (green; it cannot be pressed while `busy`), "Claimed" (grey, the
--- check), "Locked" (grey, the padlock), "Tomorrow", "Play" (Play a match), "Wait" (white, the
--- stopwatch and `text`, the time left) or "Lock" (grey, only the padlock).
function FreeParts.setStatus(button: TextButton, mode: string, text: string?, busy: boolean?)
	local key = mode .. "|" .. (text or "") .. "|" .. tostring(busy == true)
	if shown[button] == key then
		return
	end
	shown[button] = key
	if mode == "Claim" then
		HudParts.setTone(button, "Green")
		HudParts.setButtonIcon(button, nil)
		HudParts.setText(button, W.Claim)
		HudParts.setEnabled(button, busy ~= true)
		return
	end
	local tone, icon, words = "Grey", nil :: string?, ""
	if mode == "Claimed" then
		icon, words = "Check", W.Claimed
	elseif mode == "Wait" then
		tone, icon, words = "White", "Stopwatch", text or ""
	elseif mode == "Lock" then
		icon = "Lock"
	elseif mode == "Tomorrow" then
		words = W.Tomorrow
	elseif mode == "Play" then
		words = W.PlayFirst
	else
		icon, words = "Lock", W.Locked
	end
	HudParts.setTone(button, tone)
	HudParts.setButtonIcon(button, icon)
	HudParts.setText(button, words)
	HudParts.setEnabled(button, false, false)
end

--- Place a status button `w` x `h` pixels centred on (x, y) pixels, its words `textPx` tall.
function FreeParts.placeStatus(
	button: TextButton,
	x: number,
	y: number,
	w: number,
	h: number,
	textPx: number
)
	button.Position = UDim2.fromOffset(round(x), round(y))
	button.Size = UDim2.fromOffset(round(w), round(h))
	HudParts.setButtonTextSize(button, textPx)
	HudParts.setMinHit(button, Config.UI.Menu.Frame.TouchMinPx)
end

--- Place a status button `w` x `h` units centred on (x, y) units, its words `textUnits` tall.
function FreeParts.layoutStatus(
	button: TextButton,
	k: number,
	x: number,
	y: number,
	w: number,
	h: number,
	textUnits: number
)
	FreeParts.placeStatus(
		button,
		x * k,
		y * k,
		w * k,
		ShopCards.buttonPx(h, k),
		ShopCards.textPx(textUnits, k)
	)
end

--- Where a tile's status button goes (its centre and height in pixels): at `y` units, `h`
--- units tall, its words `textUnits` tall, yet never past `footPx` (the tile's foot less its
--- room). On a phone it keeps its words' smallest size plus StatusPadPx and moves up to fit.
function FreeParts.statusAt(
	k: number,
	y: number,
	h: number,
	textUnits: number,
	footPx: number
): (number, number, number)
	local textPx = ShopCards.textPx(textUnits, k)
	local at, height = ShopCards.above(y, h, textPx, F.StatusPadPx, footPx, k)
	return at, height, textPx
end

--- Fit something `size` units tall centred at `y` units between `top` and `bottom` pixels:
--- its centre and size in pixels (it shrinks when the room is short, as on a phone).
function FreeParts.fit(
	k: number,
	y: number,
	size: number,
	top: number,
	bottom: number
): (number, number)
	local px = math.max(1, math.min(size * k, bottom - top))
	local low, high = top + px / 2, math.max(top + px / 2, bottom - px / 2)
	return math.clamp(y * k, low, high), px
end

--- A Claim button's breathe while it can be pressed (stop the handle when it cannot).
function FreeParts.pulse(button: TextButton): UIAnim.Handle
	return UIAnim.pulse(button, F.ClaimPulse.Size, F.ClaimPulse.Seconds)
end

--------------------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------------------

--- What comes with a big prize's block (its art shows one `heroKind` block), one entry each:
--- "+2 Ability Spins", "+$5,000", "+1 Rare Lucky Block". A cue comes first: its name, then its
--- rarity in its colour ("Chroma Cue", "Legendary"; rich text: economy v5's first week).
function FreeParts.extras(reward: RewardsParts.Reward, heroKind: string?): { string }
	local parts: { string } = {}
	local cues: { string } = reward.cues or {}
	for _, id in cues do
		local rarity = CueThumb.rarityOf(id)
		local word = string.format(
			'<font color="#%s">%s</font>',
			CueThumb.accentColor(rarity):ToHex(),
			CueThumb.rarityName(rarity)
		)
		table.insert(parts, CueThumb.cueName(id))
		table.insert(parts, word)
	end
	if reward.money > 0 then
		table.insert(parts, W.HeroMoney:format(Format.money(reward.money)))
	end
	for _, entry in reward.blocks do
		local count = if entry.kind == heroKind then entry.count - 1 else entry.count
		if count > 0 then
			table.insert(parts, W.HeroBlock:format(count, NAMES[entry.kind] or entry.kind))
		end
	end
	if reward.spins == 1 then
		table.insert(parts, W.HeroSpin)
	elseif reward.spins > 1 then
		table.insert(parts, W.HeroSpins:format(reward.spins))
	end
	return parts
end

--- `parts` on one line when they fit in `width` pixels at `px`, else one to a line (each may
--- still wrap); the words and how tall they stand.
function FreeParts.wordsFit(parts: { string }, px: number, width: number): (string, number)
	local one = table.concat(parts, "  ")
	if #parts < 2 or ShopParts.textWidth(one, px) <= width then
		return one, ShopParts.wrapHeight(one, px, width)
	end
	local height = 0
	for _, part in parts do
		height += ShopParts.wrapHeight(part, px, width)
	end
	return table.concat(parts, "\n"), height
end

--- The reward's best lucky block (the latest in Config.LuckyBlocks.Order), else nil.
function FreeParts.bestBlock(reward: RewardsParts.Reward): string?
	local best = RewardsParts.bestBlock(reward)
	return if best then best.kind else nil
end

return FreeParts
