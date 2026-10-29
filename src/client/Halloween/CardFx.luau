--!strict
-- CardFx: an event cue card's live 2D effects in the Halloween menu (designer, 2026-10-29:
-- "each event cue card shows its VFX animated as live 2D effects made from the cue's own art",
-- richer up the ladder: the Pitchfork calmest, the Sword richest). The cue picture stays still;
-- the cue's own effect art (its skin row's emitter textures, HwCardFxMath.resolve) plays over
-- it in sprites placed in shares of the picture's square (Config.UI.Halloween.CardFx), and a
-- Glow layer sits behind it. A flipbook sprite is a clipping frame holding the whole sheet,
-- moved by whole frames (size-free: a re-uploaded sheet of another size still lines up), so it
-- is never rotated; a plain picture may turn.
--
-- No loop here: the menu runs one loop for every card while it is open and calls `step`; `hide`
-- puts every sprite away (on close, before a card lands). Lower effects: the layer's Low count.
-- Reduce Motion: only the Glow shows, still.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CardMath = require(Shared:WaitForChild("CardMath"))
local CueSkins = require(Shared:WaitForChild("CueSkins"))
local HwCardFxMath = require(Shared:WaitForChild("HwCardFxMath"))

local FX = Config.UI.Halloween.CardFx
local CUES: { [string]: any } = FX.Cues :: any
local WHITE = Color3.new(1, 1, 1)

local CardFx = {}

type Sprite = {
	outer: GuiObject, -- placed and sized (the clip frame, or the picture itself)
	image: ImageLabel, -- tinted and faded (the sheet inside the clip frame, or the picture)
	cell: number, -- the frame showing (-1: none yet)
}

type Layer = {
	config: any,
	which: number,
	grid: number,
	sprites: { Sprite },
	tints: { Color3 },
}

export type Fx = {
	back: Frame, -- behind the cue picture
	front: Frame, -- over it
	axis: any,
	seed: number,
	layers: { Layer },
	shown: boolean,
}

local function square(parent: Instance, name: string, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function makeSprite(parent: Frame, texture: string, grid: number, anchorY: number): Sprite
	local image = Instance.new("ImageLabel")
	image.Name = "Sprite"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = texture
	image.ScaleType = Enum.ScaleType.Stretch
	image.Visible = true
	if grid <= 1 then
		image.AnchorPoint = Vector2.new(0.5, anchorY)
		image.Visible = false
		image.Parent = parent
		return { outer = image, image = image, cell = -1 }
	end
	local clip = Instance.new("Frame")
	clip.Name = "Flipbook"
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.ClipsDescendants = true
	clip.AnchorPoint = Vector2.new(0.5, anchorY)
	clip.Visible = false
	clip.Parent = parent
	image.Size = UDim2.fromScale(grid, grid)
	image.Parent = clip
	return { outer = clip, image = image, cell = -1 }
end

--- The effects for catalog cue `cueId` in its picture box `parent` (the card's Art frame, whose
--- CueThumb gets ZIndex 2 so the layers sit behind (1) and over (3) it), or nil for a cue with
--- no CardFx row or the switch off. Built hidden.
function CardFx.new(parent: GuiObject, cueId: string, thumb: GuiObject): Fx?
	local row = CUES[cueId]
	if FX.Enabled ~= true or type(row) ~= "table" then
		return nil
	end
	local skin = CueSkins.get(cueId)
	thumb.ZIndex = 2
	local back = square(parent, "FxBack", 1)
	local front = square(parent, "FxFront", 3)
	local layers: { Layer } = {}
	for which, config in row.Layers do
		local texture, grid = HwCardFxMath.resolve(skin, config)
		if texture ~= "" then
			local tints: { Color3 } = {}
			for _, hex in (config.Tints or { "#FFFFFF" }) :: { string } do
				table.insert(tints, Color3.fromHex(hex))
			end
			local layer: Layer =
				{ config = config, which = which, grid = grid, sprites = {}, tints = tints }
			local holder = if config.Back then back else front
			local anchorY = config.AnchorY or 0.5
			for _ = 1, math.max(HwCardFxMath.count(config, false), HwCardFxMath.count(config, true)) do
				table.insert(layer.sprites, makeSprite(holder, texture, grid, anchorY))
			end
			table.insert(layers, layer)
		end
	end
	return {
		back = back,
		front = front,
		axis = row.Axis,
		seed = CardMath.seed(cueId),
		layers = layers,
		shown = false,
	}
end

--- Size the layers to the cue picture's square (`side` pixels, centred in the box).
function CardFx.layout(fx: Fx, side: number)
	fx.back.Size = UDim2.fromOffset(side, side)
	fx.front.Size = UDim2.fromOffset(side, side)
end

--- Put every sprite away.
function CardFx.hide(fx: Fx)
	if not fx.shown then
		return
	end
	fx.shown = false
	for _, layer in fx.layers do
		for _, sprite in layer.sprites do
			sprite.outer.Visible = false
		end
	end
end

--- One step at `clock` seconds: `low` with Lower effects, `reduced` with Reduce Motion.
function CardFx.step(fx: Fx, clock: number, low: boolean, reduced: boolean)
	fx.shown = true
	for _, layer in fx.layers do
		local config = layer.config
		local glow = config.Kind == "Glow"
		local count = if reduced and not glow then 0 else HwCardFxMath.count(config, low)
		local t = if reduced then 0 else clock
		for index, sprite in layer.sprites do
			local on = index <= count
			if sprite.outer.Visible ~= on then
				sprite.outer.Visible = on
			end
			if on then
				local s =
					HwCardFxMath.sprite(config, layer.which, index, t, fx.axis, fx.seed, layer.grid)
				sprite.outer.Position = UDim2.fromScale(s.x, s.y)
				sprite.outer.Size = UDim2.fromScale(s.w, s.h)
				sprite.image.ImageTransparency = s.transparency
				if layer.grid <= 1 then
					sprite.image.Rotation = s.rotation
					local tint = layer.tints[s.tint] or WHITE
					if sprite.image.ImageColor3 ~= tint then
						sprite.image.ImageColor3 = tint
					end
				elseif s.frame ~= sprite.cell then
					sprite.cell = s.frame
					local col, row = HwCardFxMath.cell(s.frame, layer.grid)
					sprite.image.Position = UDim2.fromScale(-col, -row)
					local tint = layer.tints[s.tint] or WHITE
					if sprite.image.ImageColor3 ~= tint then
						sprite.image.ImageColor3 = tint
					end
				end
			end
		end
	end
end

--- Take the effects away.
function CardFx.destroy(fx: Fx)
	fx.back:Destroy()
	fx.front:Destroy()
end

return CardFx
