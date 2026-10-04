# Lucky-block source assets

YellowBlue.rbxm contains the two bought-pack models used by the current test build. Import
its YellowLuckyBlock and BlueLuckyBlock into ReplicatedStorage.LuckyBlocks. Model code is
in src/server/LuckyBlockService.luau; animation and prompt presentation in src/client/LuckyWorld.luau.

2026-10-03 appearance adjustment: the mesh base colour is neutral white; each original
SurfaceAppearance keeps its colour and normal maps and adds a white emissive mask.
The mask is textures/neutral_mask.png (16 x 16 white RGB), group-owned image asset
104192408636466, uploaded decal 72694723354109. EmissiveMaskContent is a plugin-only write,
so it lives in the model/place. Runtime EmissiveStrength comes from Config.LuckyBlocks.Look
(0.65). Keep the original demo place untouched. The working Crazy 8 Ball Studio templates
have this adjustment; save the place and publish to ship it.

The original demo has much brighter ambient lighting than the rooftop. Neutral base,
gentle texture-coloured fill and neutral viewport lights compensate without changing the
whole lobby. Hotbar/bag previews keep the original PBR maps and use Config.LuckyBlocks.UI
IconAmbient, IconLight and IconLightDirection. Particles use Look.ParticleLightInfluence.
