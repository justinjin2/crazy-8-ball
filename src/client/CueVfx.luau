--!strict
-- CueVfx: the cue skins' effect rows (CueSkins data) turned into Roblox values and emitters,
-- shared by CueSkinLook (the cue's aura and moving material) and Effects (the ball trail's
-- emitters and the pocket finisher's layers). The rows follow the Blender preview
-- (assets/cue/CueVfx.py), which is what the review clips show; where Roblox differs, this
-- module follows the preview.
--
-- Value formats in a row:
--   number sequence  a number, or {{t, v}, ...} or {{t, v, envelope}, ...}
--   colour           "#RRGGBB", {r, g, b} (0..255), or {{t, colour}, ...}
--   range            a number, or {min, max}
-- Positions on the cue are AtStuds (from the tip; the butt is 7), Up and Side (studs), in the
-- cue MeshPart's frame as (-Side, Up, 3.5 - AtStuds).

local CueVfx = {}

--- A colour from "#RRGGBB" or {r, g, b}.
function CueVfx.color(c: any): Color3
	if type(c) == "string" then
		return Color3.fromHex(c)
	end
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function isColorList(c: any): boolean
	return type(c) == "table" and type(c[1]) == "table"
end

--- A ColorSequence from any colour form (keys outside 0..1 are clamped; ends filled in).
function CueVfx.colorSeq(c: any): ColorSequence
	if c == nil then
		return ColorSequence.new(Color3.new(1, 1, 1))
	end
	if not isColorList(c) then
		return ColorSequence.new(CueVfx.color(c))
	end
	local keys = {}
	for _, k in c do
		table.insert(keys, ColorSequenceKeypoint.new(math.clamp(k[1], 0, 1), CueVfx.color(k[2])))
	end
	if keys[1].Time > 0 then
		table.insert(keys, 1, ColorSequenceKeypoint.new(0, keys[1].Value))
	end
	if keys[#keys].Time < 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, keys[#keys].Value))
	end
	return ColorSequence.new(keys)
end

--- A NumberSequence from a number or a curve with optional envelopes; values below `floor`
--- (when given) are raised to it.
function CueVfx.numberSeq(v: any, floor: number?): NumberSequence
	if v == nil then
		v = 0
	end
	if type(v) == "number" then
		return NumberSequence.new(if floor then math.max(v, floor) else v)
	end
	local keys = {}
	for _, k in v do
		local value = if floor then math.max(k[2], floor) else k[2]
		table.insert(keys, NumberSequenceKeypoint.new(math.clamp(k[1], 0, 1), value, k[3] or 0))
	end
	if keys[1].Time > 0 then
		table.insert(keys, 1, NumberSequenceKeypoint.new(0, keys[1].Value, keys[1].Envelope))
	end
	if keys[#keys].Time < 1 then
		local last = keys[#keys]
		table.insert(keys, NumberSequenceKeypoint.new(1, last.Value, last.Envelope))
	end
	return NumberSequence.new(keys)
end

--- A NumberRange from a number or {min, max}.
function CueVfx.range(v: any, default: number): NumberRange
	if v == nil then
		return NumberRange.new(default)
	end
	if type(v) == "number" then
		return NumberRange.new(v)
	end
	return NumberRange.new(math.min(v[1], v[2]), math.max(v[1], v[2]))
end

--- The largest value a number sequence or number reaches (for sizes).
function CueVfx.maxOf(v: any): number
	if type(v) == "number" then
		return v
	end
	local best = 0
	for _, k in v or {} do
		best = math.max(best, k[2] + (k[3] or 0))
	end
	return best
end

--- A point on the cue (AtStuds, Up, Side) in the cue MeshPart's frame.
function CueVfx.onCue(at: number, up: number?, side: number?): Vector3
	return Vector3.new(-(side or 0), up or 0, 3.5 - at)
end

-- The preview's emission directions in the cue frame are Roblox's NormalIds on an unturned
-- attachment, except Front (+Z, toward the tip) and Back, which are swapped (CueVfx.py's
-- frame); on a Part host turned to lie along the cue (its +Y toward the tip) they map again.
local ON_CUE: { [string]: Enum.NormalId } = {
	Top = Enum.NormalId.Top,
	Bottom = Enum.NormalId.Bottom,
	Right = Enum.NormalId.Right,
	Left = Enum.NormalId.Left,
	Front = Enum.NormalId.Back,
	Back = Enum.NormalId.Front,
}
local ON_PART: { [string]: Enum.NormalId } = {
	Top = Enum.NormalId.Front,
	Bottom = Enum.NormalId.Back,
	Right = Enum.NormalId.Right,
	Left = Enum.NormalId.Left,
	Front = Enum.NormalId.Top,
	Back = Enum.NormalId.Bottom,
}

local LAYOUTS: { [string]: Enum.ParticleFlipbookLayout } = {
	Grid2x2 = Enum.ParticleFlipbookLayout.Grid2x2,
	Grid4x4 = Enum.ParticleFlipbookLayout.Grid4x4,
	Grid8x8 = Enum.ParticleFlipbookLayout.Grid8x8,
}

export type EmitterOpts = {
	-- "cue": a host on the cue (EmissionDirection swapped as above); "part": a Part host laid
	-- along the cue; "world": a host with no turn (the pocket, the ball: Top is world up).
	frame: "cue" | "part" | "world",
	rateScale: number?,
	zOffset: number?, -- added to the row's ZOffset (the back's big sprites go behind the body)
}

--- A ParticleEmitter configured from a row (not parented; Enabled as the row's Rate says).
function CueVfx.emitter(row: any, opts: EmitterOpts): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = row.Name or "Emitter"
	e.Texture = row.Texture or ""
	e.Rate = (row.Rate or 0) * (opts.rateScale or 1)
	e.Lifetime = CueVfx.range(row.Lifetime, 1)
	e.Speed = CueVfx.range(row.Speed, 1)
	e.Size = CueVfx.numberSeq(row.Size or 1, 0)
	e.Transparency = CueVfx.numberSeq(row.Transparency or 0)
	e.Color = CueVfx.colorSeq(row.Color)
	e.LightEmission = row.LightEmission or 0
	e.LightInfluence = row.LightInfluence or 0
	e.Brightness = row.Brightness or 1
	e.LockedToPart = row.LockedToPart == true
	e.ZOffset = (row.ZOffset or 0) + (opts.zOffset or 0)
	local spread = row.SpreadAngle or 0
	e.SpreadAngle = if type(spread) == "number"
		then Vector2.new(spread, spread)
		else Vector2.new(spread[1], spread[2])
	e.Drag = row.Drag or 0
	local acc = row.Acceleration
	e.Acceleration = if acc then Vector3.new(acc[1], acc[2], acc[3]) else Vector3.zero
	local direction = row.EmissionDirection or "Top"
	if opts.frame == "cue" then
		e.EmissionDirection = ON_CUE[direction] or Enum.NormalId.Top
	elseif opts.frame == "part" then
		e.EmissionDirection = ON_PART[direction] or Enum.NormalId.Front
	else
		e.EmissionDirection = (Enum.NormalId :: any)[direction] or Enum.NormalId.Top
	end
	e.Rotation = CueVfx.range(row.Rotation, 0)
	e.RotSpeed = CueVfx.range(row.RotSpeed, 0)
	if row.Orientation then
		e.Orientation = (Enum.ParticleOrientation :: any)[row.Orientation]
	end
	if row.Squash then
		e.Squash = CueVfx.numberSeq(row.Squash)
	end
	local layout = LAYOUTS[row.FlipbookLayout or ""]
	if layout then
		e.FlipbookLayout = layout
		e.FlipbookMode = (Enum.ParticleFlipbookMode :: any)[row.FlipbookMode or "Loop"]
		e.FlipbookFramerate = CueVfx.range(row.FlipbookFramerate, 1)
		e.FlipbookStartRandom = row.FlipbookStartRandom == true
	end
	e.Enabled = e.Rate > 0
	return e
end

return CueVfx
