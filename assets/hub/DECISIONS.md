# Skyline Club hub: decisions

Choices made while building, with the tradeoff. The stage 1 layout was approved by the designer on
2026-09-25; stages 2 to 6 were built straight through.

- **2026-09-25, stage 1: the spawn stair moved to the middle of the south side, and the zones
  swapped bands.** The brief's starting plan put the stair beside the 1v1 zone in the south-east,
  which puts the far 2v2 tables about 150 studs from the foot of the stair (the rule is 128). The
  stair now lands in a central plaza. The 1v1 zone (10 tables) takes the north windows, 2v2 sits
  south-west beside the stair, and 3v3 sits north-east. Tradeoff: the lounge and bar move to the
  south-east instead of the north windows. They keep the east windows, the terrace and the piano
  by the glass, and the bar now faces the plaza, so spawn, bar, kiosks and screen share one
  crossroads.
- **2026-09-25, stage 1: the 2v2 tables run east-west.** Four north-south tables need 67 studs of
  depth, and that would have squeezed the walkway. East-west they need 50. Their join pads are at
  the east and west ends.
- **2026-09-25, stage 1: pads face the walkway or an inner aisle, never a window.** The 1v1 back
  row faces south into a 16-stud aisle (pads 8 studs from the front row). Pads on the window side
  would have been 139 studs from the stair.
- **2026-09-25, stage 1: a spawn prow.** The balcony has an 8-stud landing jutting out over the
  plaza. The stair runs down from it, which brings the stair foot 8 studs closer to everything.
  Under it there is 10.2 studs of clear height.
- **2026-09-25, stage 1: the featured screen is on the south wall above the balcony, over the
  stair.** Everyone on the main floor faces it. Armchairs sit beneath it on the balcony (the
  ref_06 mural wall). A tall wall beside the plaza would have blocked the spawn view of the 2v2
  zone. Tradeoff: players on the balcony have it behind them.
- **2026-09-25, stage 1: the top-3 statues stand as a podium at the plaza's walkway edge.**
- **2026-09-25, stage 1: the walk audit uses a 2-stud avatar radius (arms out)** and measures to
  each table's join pad, not its nearest rail, the stricter reading of the rule.
- **2026-09-25, stage 1: the room is 171.5 x 151.5**, slightly over "about 170 x 150". The 1v1
  window seats need 10 studs of clearance plus 3 of depth, and the 3v3 needs 12 on the east.

## Stages 2 to 6 (2026-09-25)

- **One palette atlas for the flat-coloured architecture.** Walls, frames, gold trim, glossy
  black and the zone colours are cells of one 512 texture (colour, roughness, metalness).
  Every architecture mesh therefore costs one texture set, and still gets the right
  roughness, which plain Roblox materials can't give. Tradeoff: no baked AO on the
  architecture. Tiled floors can't carry unique AO, and Roblox has no second UV set.
- **AO is baked on the props only**, into one 1024 atlas at 45 % strength ("lightly"). The
  fabric of armchairs and poufs stays near white, so SurfaceAppearance.Color tints it per
  placement (zone colours) from a single master.
- **Marble reflection as a transparent overlay.** A reflection can't live in a repeating
  floor texture. It sits 0.004 studs above the marble with its own 0 to 1 UVs, and only the
  brightest 40 % of reflections show, at 35 % at most, so the marble never looks milky.
  Roblox lights draw their own live highlights, so lamps are left out of the bake.
- **Curved corners in the north-east and north-west**, with the yellow band sweeping round
  them, to meet ref_07's curved wall. **The ref_02 yellow wall** is a curved-topped fin beside
  the cue-room window.
- **Seating:** 78 armchairs in pairs with side tables along every edge, 20 more along the
  balcony rail looking over the club, sofas in the lounge and 3v3 window lounge, booths
  under the balcony, 8 bar stools, stair-seat tiers. The one gallery row is pushed east, so
  table 4 has seats within 20 studs.
- **The bar moved 1.5 studs east** after the furniture went in, so an avatar with arms out
  can walk between the stair seats and the bar stools. The walk from the plaza to the lounge
  and terrace stays 101 studs, not 123.
- **Towers:** 30 placements of 4 backless masters, 210 to 400 studs out, mostly below eye
  level, so the view opens over the city to the mountains. Near towers first stood 170 studs
  out and walled off the east windows.
- **Lit windows use SurfaceAppearance EmissiveMaskContent**, checked in Studio. The
  dusk look reuses the night maps with a smaller mask (`Facade_Night_EmissiveDusk.png`).
  That mask lives in the night set, so the skyline keeps to 4 texture sets.
- **The haze deck uses vertex colours on a bare MeshPart**, with no texture set. Its Color
  changes with the time of day.
- **Preview lighting mimics Roblox:** the camera and reflections see the sunset sky, while
  indirect light is a flat, cool ambient, as in Roblox. That keeps the walls cloud white and
  the furniture saturated. The first preview took the peach tint of the dusk sky everywhere.
- **Phone crop:** rendered both 844 x 390 (how Roblox phones are held) and 390 x 844 (the
  brief's size).
- **Validation checks:** closed shells are required for collision boxes and prop masters.
  Glow strips and the backless towers are exempt, as the brief makes them. Architecture and
  furniture are built as visible surfaces with no hidden faces, and their open-edge counts
  are reported for information. The silhouette cards were re-authored at 4096 so every
  master is 4096.
