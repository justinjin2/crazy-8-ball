--!strict
-- Backrooms: the Secret pull cutscene's hall (PullSecret; designer 2026-10-10: "ominous
-- backrooms type vibes"). The internet's Level 0, built far above the map in the scene's own
-- model: a long hall of mono-yellow wallpaper over damp carpet under a drop ceiling, a light
-- panel down the middle every few studs, dark openings into side halls, the far end lost in
-- haze. Closed on every side, so nothing of the map shows. Visual only; tuning in
-- Config.Cutscenes.Secret.Hall, art from tools/gen_backrooms_art.py.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local CS = Config.Cutscenes
local ART = CS.Art

local Backrooms = {}

-- One light panel in the ceiling: its glowing diffuser and its light. `at` is how far down the
-- hall it hangs (studs from the near wall); `share` its brightness of a full panel.
export type Panel = {
	part: BasePart,
	light: SurfaceLight,
	at: number,
	share: number,
}

export type Hall = {
	frame: CFrame, -- the near wall's foot, in the middle of the hall; -Z runs down the hall
	panels: { Panel }, -- the hall's own, nearest first
	side: { Panel }, -- the side halls' panels
}

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function slab(
	parent: Instance,
	name: string,
	size: Vector3,
	frame: CFrame,
	colour: Color3
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = colour
	part.Size = size
	part.CFrame = frame
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function texture(
	part: BasePart,
	art: string,
	face: Enum.NormalId,
	u: number,
	v: number,
	offsetU: number?
)
	if art == "" then
		return
	end
	local t = Instance.new("Texture")
	t.Texture = art
	t.Face = face
	t.StudsPerTileU = u
	t.StudsPerTileV = v
	t.OffsetStudsU = offsetU or 0
	t.Parent = part
end

--- The hall's frame from its config: the near wall's foot, facing down the hall.
function Backrooms.frame(): CFrame
	local o = CS.Secret.Hall.Origin
	return CFrame.new(o[1], o[2], o[3])
end

--- A point in the hall: `along` studs down it from the near wall, `up` studs over the carpet,
--- `right` studs right of its middle line.
function Backrooms.point(hall: Hall, along: number, up: number, right: number?): Vector3
	return (hall.frame * CFrame.new(right or 0, up, -along)).Position
end

--- A panel at `share` of its full light (0 is out: a dead grey diffuser), in `colour` (its own
--- warm white when not given).
function Backrooms.setPanel(panel: Panel, share: number, colour: Color3?)
	local Hl = CS.Secret.Hall
	local on = share > 0.02
	panel.part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	panel.part.Color = if on
		then rgb(Hl.DeadColour):Lerp(colour or rgb(Hl.PanelColour), math.clamp(share, 0, 1))
		else rgb(Hl.DeadColour)
	panel.light.Enabled = on
	panel.light.Brightness = Hl.Light.Brightness * panel.share * math.clamp(share, 0, 1)
	panel.light.Color = colour or rgb(Hl.Light.Colour)
end

local function panel(parent: Instance, frame: CFrame, at: number, share: number): Panel
	local Hl = CS.Secret.Hall
	local size = Hl.PanelStuds
	local housing = slab(
		parent,
		"Housing",
		Vector3.new(size[1] + 0.4, 0.16, size[2] + 0.4),
		frame * CFrame.new(0, -0.08, 0),
		rgb(Hl.HousingColour)
	)
	housing.Material = Enum.Material.SmoothPlastic
	local diffuser = slab(
		parent,
		"Panel",
		Vector3.new(size[1], 0.1, size[2]),
		frame * CFrame.new(0, -0.18, 0),
		rgb(Hl.PanelColour)
	)
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Bottom
	light.Range = Hl.Light.RangeStuds
	light.Angle = Hl.Light.AngleDegrees
	light.Shadows = false
	light.Parent = diffuser
	local p: Panel = { part = diffuser, light = light, at = at, share = share }
	Backrooms.setPanel(p, 1)
	return p
end

--- Build the hall in `parent` (the scene's model). Its parts are the scene's own: they go with
--- it.
function Backrooms.build(parent: Instance): Hall
	local Hl = CS.Secret.Hall
	local frame = Backrooms.frame()
	local W, H, L, T = Hl.WidthStuds, Hl.HeightStuds, Hl.LengthStuds, Hl.WallStuds
	local folder = Instance.new("Model")
	folder.Name = "Backrooms"
	folder.Parent = parent
	local paper = rgb(Hl.WallpaperColour)
	local function place(along: number, up: number, right: number): CFrame
		return frame * CFrame.new(right, up, -along)
	end

	-- The carpet and the drop ceiling, wide enough to run under the side halls too.
	local span = W + 2 * (Hl.SideDepthMost + T)
	local floor = slab(
		folder,
		"Carpet",
		Vector3.new(span, T, L + 2 * T),
		place(L / 2, -T / 2, 0),
		rgb(Hl.CarpetColour)
	)
	texture(floor, ART.Carpet, Enum.NormalId.Top, Hl.CarpetTileStuds, Hl.CarpetTileStuds)
	local ceiling = slab(
		folder,
		"Ceiling",
		Vector3.new(span, T, L + 2 * T),
		place(L / 2, H + T / 2, 0),
		rgb(Hl.CeilingColour)
	)
	texture(ceiling, ART.Ceiling, Enum.NormalId.Bottom, Hl.CeilingTileStuds, Hl.CeilingTileStuds)

	-- A wall: wallpaper on both faces (one wall's height per tile, so the grime meets the
	-- carpet), its pattern carried on across the gaps.
	local function wall(size: Vector3, at: CFrame, faces: { Enum.NormalId }, offset: number)
		local part = slab(folder, "Wall", size, at, paper)
		for _, face in faces do
			texture(part, ART.Wallpaper, face, H, H, offset)
		end
		return part
	end
	local baseboard = rgb(Hl.BaseboardColour)

	-- The two long walls, broken by the side halls' openings.
	for _, side in { -1, 1 } do
		local gaps = {}
		for _, o in Hl.Openings do
			if o.Side == side then
				table.insert(gaps, { from = o.At - o.Width / 2, to = o.At + o.Width / 2 })
			end
		end
		table.sort(gaps, function(a, b)
			return a.from < b.from
		end)
		local x = side * (W / 2 + T / 2)
		local start = -T
		local pieces = {}
		for _, gap in gaps do
			table.insert(pieces, { from = start, to = gap.from })
			start = gap.to
		end
		table.insert(pieces, { from = start, to = L + T })
		for _, piece in pieces do
			local length = piece.to - piece.from
			if length > 0.05 then
				local middle = (piece.from + piece.to) / 2
				wall(
					Vector3.new(T, H, length),
					place(middle, H / 2, x),
					{ Enum.NormalId.Left, Enum.NormalId.Right },
					piece.from
				)
				slab(
					folder,
					"Baseboard",
					Vector3.new(0.15, Hl.BaseboardStuds, length),
					place(middle, Hl.BaseboardStuds / 2, side * (W / 2 - 0.075)),
					baseboard
				)
			end
		end
	end

	-- The near wall behind the first shot, and the far wall lost in the haze.
	wall(
		Vector3.new(span, H, T),
		place(-T / 2, H / 2, 0),
		{ Enum.NormalId.Front, Enum.NormalId.Back },
		0
	)
	wall(
		Vector3.new(span, H, T),
		place(L + T / 2, H / 2, 0),
		{ Enum.NormalId.Front, Enum.NormalId.Back },
		0
	)

	-- The side halls: a short room through each opening, some lit, some dark.
	local side: { Panel } = {}
	for _, o in Hl.Openings do
		local s: number = o.Side
		local depth: number = o.Depth
		local inner = s * W / 2
		local back = s * (W / 2 + depth + T / 2)
		wall(
			Vector3.new(T, H, o.Width + 2 * T),
			place(o.At, H / 2, back),
			{ Enum.NormalId.Left, Enum.NormalId.Right },
			o.At
		)
		for _, edge in { -1, 1 } do
			wall(
				Vector3.new(depth, H, T),
				place(o.At + edge * (o.Width / 2 + T / 2), H / 2, inner + s * depth / 2),
				{ Enum.NormalId.Front, Enum.NormalId.Back },
				0
			)
		end
		if o.Lit then
			table.insert(
				side,
				panel(folder, place(o.At, H, inner + s * depth / 2), o.At, Hl.SideShare)
			)
		end
	end

	-- The panels down the middle of the hall, nearest first.
	local panels: { Panel } = {}
	local at = Hl.PanelFirstStuds
	while at < L - 2 do
		table.insert(panels, panel(folder, place(at, H, 0), at, 1))
		at += Hl.PanelEveryStuds
	end

	return { frame = frame, panels = panels, side = side }
end

return Backrooms
