# ChatGPT concept prompts for the cue skins

Made 2026-09-29 from the approved plan (`assets/cue/concepts/plan.json`, 62 cues). There are **26 images** to make. The skins run (`docs/prompts/CUE_SKINS_PROMPT.md`) builds every skin from them.

## How to make each image

1. Open a **new chat** in ChatGPT for each image, so the last one doesn't leak into it.
2. Attach the pictures listed under the image. They're in `~/Desktop/8ball-skins/assets/cue/concepts/_attach/`. In ChatGPT, click **+** and then **Add photos & files**.
3. Paste the prompt and send it.
4. **Check it:**
   - Is every cue the same shape as image 1?
   - Is each row the right cue?
   - Is the surface easy to see in the clean side view?
   - Is there any text or a logo on a cue?
   If one row is wrong, ask for one fix at a time. For example: *"Keep everything else exactly the same; only change row 2's forearm to ..."*. Two or three fixes is normal. If a sheet with several cues keeps coming out cramped, ask for it as two images and save them as `C1a.png` and `C1b.png`.
5. **Save it:** download the image, then move it into `~/Desktop/8ball-skins/assets/cue/concepts/` with the exact name shown (for example `C1.png`). The command under each prompt moves your newest download there for you.

**Order: make C1, R1 and E1 first.** The run starts with a pilot of Midnight, Honeycomb and Void from those sheets and shows them to you before doing the rest. Then go down the list; the run asks for any sheet it reaches that isn't there yet.

## C1: Commons 1

**Cues:** Midnight, Arctic, Cherry, Carbon  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/C1.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 4 rows, top to bottom, split by thin grey lines. In each row: the full cue side-on across the whole width, and below it on the right a 3x close-up of the handle (the joint collar to the butt end), also side-on. The cue's name goes under it on the left. Show each cue plainly, with no particles.

The cues:

ROW 1: MIDNIGHT
Look: Metallic gloss black with one matte grey stripe running the full length of the butt, a chrome collar and butt cap, and a smooth black leather wrap. Sleek and modern.
VFX: none (a plain real cue).
Colours: #0E0E10 #6B6E73 #C8CCD0.

ROW 2: ARCTIC
Look: Gloss pearl white with one frosted ice-blue stripe running the full length of the butt, chrome collar and butt cap, and a white leather wrap.
VFX: none (a plain real cue).
Colours: #F4F6F8 #9FD3EE #C8CCD0.

ROW 3: CHERRY
Look: Satin ruby-red maple butt, black Irish-linen wrap, stainless-steel rings, collar and butt cap, and a black carbon shaft. A pro player's cue.
VFX: none (a plain real cue).
Colours: #9B111E #1A1A1A #C8CCD0 #1E1E1E.

ROW 4: CARBON
Look: Carbon fiber from tip to butt, with the checker weave showing under a glossy clear coat, and stainless rings and butt cap. Today's most wanted real-world look.
VFX: none (a plain real cue).
Colours: #1E1E1E #3A3A3A #C8CCD0.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/C1.png
```

## C2: Commons 2

**Cues:** Heritage, Monarch, Cobalt  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/C2.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 3 rows, top to bottom, split by thin grey lines. In each row: the full cue side-on across the whole width, and below it on the right a 3x close-up of the handle (the joint collar to the butt end), also side-on. The cue's name goes under it on the left. Show each cue plainly, with no particles.

The cues:

ROW 1: HERITAGE
Look: The most famous cue design ever: honey birdseye maple with four long black points, each lined with thin black, maple, green and orange veneers, with pearl diamonds in the points and a white linen wrap flecked with green.
VFX: none (a plain real cue).
Colours: #D9A864 #1A1410 #2E6B3A #D9772B #EDE8E0.

ROW 2: MONARCH
Look: Dark black-wood forearm with four long curly-maple points edged in ivory and silver, four short ivory points between them, alternating silver and ivory rings, a black leather wrap and a steel teardrop butt cap.
VFX: none (a plain real cue).
Colours: #15110E #F1EAD8 #D8B98B #BFC3C7.

ROW 3: COBALT
Look: Curly maple stained deep Prussian blue under a gloss finish, a smoke-grey handle with no wrap, and small shimmering blue diamond inlays.
VFX: none (a plain real cue).
Colours: #1C3F6E #6B7078 #9FD3FF.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/C2.png
```

## U1: Uncommons 1

**Cues:** Gummy, Flare, Hornet  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/U1.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 3 rows, top to bottom, split by thin grey lines. In each row: the full cue side-on across the whole width, and below it on the right a 3x close-up of the handle (the joint collar to the butt end), also side-on. The cue's name goes under it on the left. Show each cue plainly, with no particles, but its one glowing ring does glow softly.

The cues:

ROW 1: GUMMY
Look: Soft pastel blobs of pink and light blue, like gummy candy, over see-through silver carbon fiber, with colored joint rings and no wrap.
Glowing ring: pink glowing ring.
Colours: #FF7FB6 #8FD3FF #C9CED4.

ROW 2: FLARE
Look: Electric orange gloss paint with a black carbon collar and butt cap, and a black textured sport grip. Loud and sporty.
Glowing ring: orange glowing ring.
Colours: #FF5A12 #1C1C1C #3A3A3A.

ROW 3: HORNET
Look: Bold black-and-yellow geometric two-tone graphics wrapping the forearm, with a black sport grip. Reads like a racing jersey.
Glowing ring: yellow glowing ring.
Colours: #FFD21A #111111 #6B6B6B.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/U1.png
```

## U2: Uncommons 2

**Cues:** Venom, Lagoon, Splice  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/U2.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 3 rows, top to bottom, split by thin grey lines. In each row: the full cue side-on across the whole width, and below it on the right a 3x close-up of the handle (the joint collar to the butt end), also side-on. The cue's name goes under it on the left. Show each cue plainly, with no particles, but its one glowing ring does glow softly.

The cues:

ROW 1: VENOM
Look: Deep black with six long neon-green carbon-fiber points reaching up the forearm, and carbon striping on the sleeve.
Glowing ring: green glowing ring.
Colours: #0A0A0A #39FF14 #2A2A2C.

ROW 2: LAGOON
Look: Gloss black with six bold turquoise-and-white graphic points sweeping up the forearm, and matching turquoise rings.
Glowing ring: turquoise glowing ring.
Colours: #0B0B0B #1FC8C8 #FFFFFF.

ROW 3: SPLICE
Look: Black wood with sixteen long spliced points (eight on the forearm, eight on the sleeve), each layered with bright blue and sky-blue veneers edged in ivory.
Glowing ring: blue glowing ring.
Colours: #15110E #2E86DE #9FE8FF #F1EAD8.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/U2.png
```

## U3: Uncommons 3

**Cues:** Cosmo, Gilded, Pixel  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/U3.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 3 rows, top to bottom, split by thin grey lines. In each row: the full cue side-on across the whole width, and below it on the right a 3x close-up of the handle (the joint collar to the butt end), also side-on. The cue's name goes under it on the left. Show each cue plainly, with no particles, but its one glowing ring does glow softly.

The cues:

ROW 1: COSMO
Look: Gloss metallic black with one shimmering galaxy stripe of deep blue, violet and magenta inlaid along the butt.
Glowing ring: violet glowing ring.
Colours: #0A0A12 #2B3FFF #8A2BE2 #E040A0.

ROW 2: GILDED
Look: A black lacquer forearm used as a canvas: swirling art-deco vines inlaid in gold and mother-of-pearl, with gold rings. Flashy, like a jewellery box.
Glowing ring: gold glowing ring.
Colours: #0D0D0D #D4AF37 #EDE8E0.

ROW 3: PIXEL
Look: A retro arcade 8-bit pattern of magenta, cyan and yellow pixel blocks, like an old game cabinet. For the younger crowd.
Glowing ring: cyan glowing ring.
Colours: #FF2BD6 #1FE0FF #FFE11F #1A1033.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/U3.png
```

## R1: Rares 1

**Cues:** Honeycomb, Neon, Nature, Candy  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/R1.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 4 rows, top to bottom, split by thin grey lines. In each row:
- LEFT two-thirds: the full cue side-on, clean with no particles, so the surface design is fully visible. Below it, a 3x close-up of the handle (the joint collar to the butt end). The cue's name goes under it.
- RIGHT third: a VFX panel on a slightly darker vignette showing the same cue at a 30-degree diagonal with its aura and glow exactly as described. If the row lists a cue ball trail or a pocket finisher, add a small inset for each, labelled BALL TRAIL / POCKET: a white cue ball rolling on dark blue cloth with the trail behind it, or a pool table pocket with the burst coming out of it.

The cues:

ROW 1: HONEYCOMB
Look: Warm amber with a glossy honeycomb pattern across the forearm, glowing honey dripping down between the cells, and a dark brown wrap striped like a bee.
Aura on the cue: tiny cartoon bees buzz in lazy loops around the stick, and drops of glowing honey drip off and fade.
Colours: #F2A516 #5A3A0A #FFD66B #1A1208.

ROW 2: NEON
Look: Glossy black with bright neon-tube lines in hot pink and electric cyan running along it like a sign.
Aura on the cue: a humming neon glow with tiny sparks popping off the tubes, and a subtle flicker.
Colours: #0C0C10 #FF2BD6 #19E6FF.

ROW 3: NATURE
Look: A living-wood cue: green vines spiral up the forearm with little leaves and white flowers budding, and a moss-green wrap.
Aura on the cue: small green leaves drift off and flutter down, with the odd pollen sparkle.
Colours: #6B4A2B #3FA34D #A8E06B #FFFFFF.

ROW 4: CANDY
Look: A red-and-white candy-cane spiral with a glossy sugar shine and a peppermint-swirl butt cap.
Aura on the cue: rainbow sprinkles and sugar sparkles fall off the cue.
Colours: #E0202E #FFFFFF #6FD6A0.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/R1.png
```

## R2: Rares 2

**Cues:** Frostbite, Plasma, Blaze  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/R2.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 3 rows, top to bottom, split by thin grey lines. In each row:
- LEFT two-thirds: the full cue side-on, clean with no particles, so the surface design is fully visible. Below it, a 3x close-up of the handle (the joint collar to the butt end). The cue's name goes under it.
- RIGHT third: a VFX panel on a slightly darker vignette showing the same cue at a 30-degree diagonal with its aura and glow exactly as described. If the row lists a cue ball trail or a pocket finisher, add a small inset for each, labelled BALL TRAIL / POCKET: a white cue ball rolling on dark blue cloth with the trail behind it, or a pool table pocket with the burst coming out of it.

The cues:

ROW 1: FROSTBITE
Look: Frosted ice-crystal glass in pale blue, with frost feathers frozen inside and silver rings.
Aura on the cue: cold mist rolls off the cue and tiny snowflakes fall.
Colours: #DDF3FF #8FD3F4 #C9CDD4.

ROW 2: PLASMA
Look: Dark gunmetal with glowing violet plasma veins pulsing through cracks.
Aura on the cue: violet sparks and small plasma arcs crackle between the rings.
Colours: #2A2B33 #A45CFF #E6CCFF.

ROW 3: BLAZE
Look: Charcoal wood with glowing orange ember cracks, like a log in a campfire.
Aura on the cue: embers and sparks rise off the cue and drift upward.
Colours: #2B2522 #FF7A1A #FFC24D.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/R2.png
```

## R3: Rares 3

**Cues:** Phantom, Tidal, Sakura  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/R3.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 3 rows, top to bottom, split by thin grey lines. In each row:
- LEFT two-thirds: the full cue side-on, clean with no particles, so the surface design is fully visible. Below it, a 3x close-up of the handle (the joint collar to the butt end). The cue's name goes under it.
- RIGHT third: a VFX panel on a slightly darker vignette showing the same cue at a 30-degree diagonal with its aura and glow exactly as described. If the row lists a cue ball trail or a pocket finisher, add a small inset for each, labelled BALL TRAIL / POCKET: a white cue ball rolling on dark blue cloth with the trail behind it, or a pool table pocket with the burst coming out of it.

The cues:

ROW 1: PHANTOM
Look: A pale ghostly white-teal with a see-through look, with faint spirit wisps swirling inside. Spooky but cute.
Aura on the cue: small friendly cartoon ghost wisps float up and fade.
Colours: #E8FFFB #8FE8DA #3C5A66.

ROW 2: TIDAL
Look: Deep ocean blue fading to teal, with a pearl inlay and a sea-foam wrap.
Aura on the cue: bubbles wobble up off the cue and pop.
Colours: #0A3D7A #1CA7B8 #F2F7F7.

ROW 3: SAKURA
Look: Black lacquer painted with pink cherry-blossom branches outlined in gold, and a pink silk wrap.
Aura on the cue: soft pink petals drift off and spin down.
Colours: #141014 #FF9CC7 #D4AF37 #FFD6E7.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/R3.png
```

## E1: Epics 1

**Cues:** Void, Shooting Star, Magma  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/E1.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 3 rows, top to bottom, split by thin grey lines. In each row:
- LEFT two-thirds: the full cue side-on, clean with no particles, so the surface design is fully visible. Below it, a 3x close-up of the handle (the joint collar to the butt end). The cue's name goes under it.
- RIGHT third: a VFX panel on a slightly darker vignette showing the same cue at a 30-degree diagonal with its aura and glow exactly as described. If the row lists a cue ball trail or a pocket finisher, add a small inset for each, labelled BALL TRAIL / POCKET: a white cue ball rolling on dark blue cloth with the trail behind it, or a pool table pocket with the burst coming out of it.

The cues:

ROW 1: VOID
Look: Matte black that seems to swallow light, with a violet glow along its edges. A black-hole swirl turns slowly on the forearm.
Moving material: the black-hole swirl turns. Aura on the cue: dark purple motes are pulled INTO the cue. Cue ball trail: purple-black smoke that bends as it follows the ball.
Colours: #050508 #5B1FA8 #B98AF0.

ROW 2: SHOOTING STAR
Look: Midnight navy with gold star inlays and a starfield drifting along the cue.
Moving material: the starfield drifts. Aura on the cue: tiny shooting stars streak along the stick. Pocket finisher: a burst of little gold five-point stars.
Colours: #0B1440 #FFD76A #FFFFFF.

ROW 3: MAGMA
Look: Black volcanic rock with molten lava flowing slowly through its cracks.
Moving material: the lava flows. Aura on the cue: embers and heat haze with glowing lava drips. Cue ball trail: a trail of embers. Pocket finisher: a lava splash.
Colours: #1A1412 #FF5A0A #FFC23D.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/E1.png
```

## E2: Epics 2

**Cues:** Toxic, Blood Moon, Prism  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/E2.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 3 rows, top to bottom, split by thin grey lines. In each row:
- LEFT two-thirds: the full cue side-on, clean with no particles, so the surface design is fully visible. Below it, a 3x close-up of the handle (the joint collar to the butt end). The cue's name goes under it.
- RIGHT third: a VFX panel on a slightly darker vignette showing the same cue at a 30-degree diagonal with its aura and glow exactly as described. If the row lists a cue ball trail or a pocket finisher, add a small inset for each, labelled BALL TRAIL / POCKET: a white cue ball rolling on dark blue cloth with the trail behind it, or a pool table pocket with the burst coming out of it.

The cues:

ROW 1: TOXIC
Look: Acid-green radioactive goo bubbling inside a glass-look shaft, with black-and-yellow hazard bands.
Moving material: the goo bubbles and rises. Aura on the cue: green bubbles rise and pop, with a faint green glow. Cue ball trail: a dripping green goo trail.
Colours: #0F140A #7CFF2B #E6FF3D.

ROW 2: BLOOD MOON
Look: Deep crimson and black lacquer with a red moon on the butt and slow red mist drifting inside. No blood, just mood.
Moving material: the red mist drifts. Aura on the cue: crimson mist rises off the cue, like Grow a Garden's Bloodlit. Pocket finisher: a crimson moon ring pulses out.
Colours: #1A0508 #B3121F #FF4A4A.

ROW 3: PRISM
Look: A clear faceted crystal cue with sharp prism edges set in thin silver, catching light and splitting it into rainbow streaks inside the glass.
Moving material: rainbow light streaks travel through the crystal facets. Aura on the cue: prism flashes and little rainbow refraction glints dance around the stick. Pocket finisher: a burst of glittering crystal shards that scatter rainbow light.
Colours: #F5FBFF #BDE6FF #FF9ACD #9AFFE0.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/E2.png
```

## E3: Epics 3

**Cues:** Aurora, Disco, Hacked  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/E3.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 3 rows, top to bottom, split by thin grey lines. In each row:
- LEFT two-thirds: the full cue side-on, clean with no particles, so the surface design is fully visible. Below it, a 3x close-up of the handle (the joint collar to the butt end). The cue's name goes under it.
- RIGHT third: a VFX panel on a slightly darker vignette showing the same cue at a 30-degree diagonal with its aura and glow exactly as described. If the row lists a cue ball trail or a pocket finisher, add a small inset for each, labelled BALL TRAIL / POCKET: a white cue ball rolling on dark blue cloth with the trail behind it, or a pool table pocket with the burst coming out of it.

The cues:

ROW 1: AURORA
Look: A dark cue with green, teal and violet aurora ribbons flowing along it.
Moving material: the aurora ribbons flow. Aura on the cue: soft floating light motes. Cue ball trail: an aurora ribbon trail.
Colours: #0A1624 #2BF0B0 #7A5CFF #3DB8FF.

ROW 2: DISCO
Look: Mirror-ball facets all along a silver cue.
Moving material: colored light specks sweep across the mirrors. Aura on the cue: spots of colored light spin around. Pocket finisher: confetti and disco light rays.
Colours: #C0C4CC #FF3D9A #3DE0FF #FFE13D.

ROW 3: HACKED
Look: Glossy black with glowing green 8-bit code (blocky binary digits and pixel glyphs) running along the shaft and filling the forearm and sleeve, with a green glowing ring and a black textured wrap. A hacker-terminal look.
Moving material: the green code scrolls along the cue. Aura on the cue: green binary digits rain down around the stick, matrix-style, with the odd glitch flicker. Cue ball trail: a green pixel data trail that breaks into falling digits.
Colours: #05080A #2BFF5A #0F7A2A #C8CCD0.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/E3.png
```

## L1: Legendary: Chroma

**Cues:** Chroma  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/L1.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout, like a premium item showcase sheet:
- TOP: the full cue side-on across the whole width, clean with no particles, with its name CHROMA and rarity LEGENDARY in small caps above it.
- MIDDLE: three close-ups side by side, labelled SHAFT AND JOINT, FOREARM, BUTT: the upper shaft and the joint collar; the forearm; and the butt sleeve and bumper.
- BOTTOM: three VFX panels side by side, labelled AURA, BALL TRAIL, POCKET FINISHER:
  - AURA: the cue held diagonally, glowing with its aura and moving material.
  - BALL TRAIL: a white cue ball rolling fast across dark blue cloth, with the trail behind it.
  - POCKET FINISHER: a pool table's corner pocket with the finisher bursting out of it.
Make the VFX bright, bold and eye-catching (this is one of the rarest, most valuable items in the game), while the cue's own surface stays readable in the top view.

The cue:
THE CUE: CHROMA
Look: Mirror chrome whose whole color cycles smoothly through the rainbow, MM2 Chroma style. The biggest value signal across Roblox.
Moving material: the whole cue cycles through the rainbow. Aura on the cue: rainbow sparkles and floating rainbow shards orbiting the stick. Cue ball trail: a rainbow ribbon. Pocket finisher: a rainbow shockwave ring that bursts into sparkles.
Colours: #FF3D3D #FFD23D #3DFF8A #3D8AFF #B03DFF.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/L1.png
```

## L2: Legendary: Thunderstrike

**Cues:** Thunderstrike  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/L2.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout, like a premium item showcase sheet:
- TOP: the full cue side-on across the whole width, clean with no particles, with its name THUNDERSTRIKE and rarity LEGENDARY in small caps above it.
- MIDDLE: three close-ups side by side, labelled SHAFT AND JOINT, FOREARM, BUTT: the upper shaft and the joint collar; the forearm; and the butt sleeve and bumper.
- BOTTOM: three VFX panels side by side, labelled AURA, BALL TRAIL, POCKET FINISHER:
  - AURA: the cue held diagonally, glowing with its aura and moving material.
  - BALL TRAIL: a white cue ball rolling fast across dark blue cloth, with the trail behind it.
  - POCKET FINISHER: a pool table's corner pocket with the finisher bursting out of it.
Make the VFX bright, bold and eye-catching (this is one of the rarest, most valuable items in the game), while the cue's own surface stays readable in the top view.

The cue:
THE CUE: THUNDERSTRIKE
Look: Storm-grey steel with glowing blue lightning veins that pulse brighter at random.
Moving material: electricity flows through the veins. Aura on the cue: lightning arcs crawl up and down the cue, with a bright crack flash now and then and a small storm cloud of static at the butt. Cue ball trail: a jagged electric trail. Pocket finisher: a lightning bolt strikes down into the pocket with a flash.
Colours: #3A4250 #3DB8FF #FFFFFF.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/L2.png
```

## L3: Legendary: Phoenix

**Cues:** Phoenix  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/L3.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout, like a premium item showcase sheet:
- TOP: the full cue side-on across the whole width, clean with no particles, with its name PHOENIX and rarity LEGENDARY in small caps above it.
- MIDDLE: three close-ups side by side, labelled SHAFT AND JOINT, FOREARM, BUTT: the upper shaft and the joint collar; the forearm; and the butt sleeve and bumper.
- BOTTOM: three VFX panels side by side, labelled AURA, BALL TRAIL, POCKET FINISHER:
  - AURA: the cue held diagonally, glowing with its aura and moving material.
  - BALL TRAIL: a white cue ball rolling fast across dark blue cloth, with the trail behind it.
  - POCKET FINISHER: a pool table's corner pocket with the finisher bursting out of it.
Make the VFX bright, bold and eye-catching (this is one of the rarest, most valuable items in the game), while the cue's own surface stays readable in the top view.

The cue:
THE CUE: PHOENIX
Look: A crimson-to-gold gradient engraved with flame feathers.
Moving material: fire glows and shifts through the feather engraving. Aura on the cue: wings of flame made of particles flare out from the handle and fold back, with burning feathers peeling off. Cue ball trail: a fiery feather trail. Pocket finisher: a flame bird flares up out of the pocket.
Colours: #B3121F #FF7A1A #FFD23D.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/L3.png
```

## L4: Legendary: Kraken

**Cues:** Kraken  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/L4.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout, like a premium item showcase sheet:
- TOP: the full cue side-on across the whole width, clean with no particles, with its name KRAKEN and rarity LEGENDARY in small caps above it.
- MIDDLE: three close-ups side by side, labelled SHAFT AND JOINT, FOREARM, BUTT: the upper shaft and the joint collar; the forearm; and the butt sleeve and bumper.
- BOTTOM: three VFX panels side by side, labelled AURA, BALL TRAIL, POCKET FINISHER:
  - AURA: the cue held diagonally, glowing with its aura and moving material.
  - BALL TRAIL: a white cue ball rolling fast across dark blue cloth, with the trail behind it.
  - POCKET FINISHER: a pool table's corner pocket with the finisher bursting out of it.
Make the VFX bright, bold and eye-catching (this is one of the rarest, most valuable items in the game), while the cue's own surface stays readable in the top view.

The cue:
THE CUE: KRAKEN
Look: Deep-sea teal and abyss purple, with dark tentacles painted wrapping the handle, dotted with glowing bioluminescent spots.
Moving material: the bioluminescent spots pulse in waves. Aura on the cue: glowing bubbles and bioluminescent specks, with a see-through ghostly tentacle curling around the cue now and then. Cue ball trail: an inky water trail with bubbles. Pocket finisher: a water splash, an ink cloud and a tentacle flick.
Colours: #062B3A #3A1F6B #2BF0D0.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/L4.png
```

## L5: Legendary: Seraph

**Cues:** Seraph  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/L5.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout, like a premium item showcase sheet:
- TOP: the full cue side-on across the whole width, clean with no particles, with its name SERAPH and rarity LEGENDARY in small caps above it.
- MIDDLE: three close-ups side by side, labelled SHAFT AND JOINT, FOREARM, BUTT: the upper shaft and the joint collar; the forearm; and the butt sleeve and bumper.
- BOTTOM: three VFX panels side by side, labelled AURA, BALL TRAIL, POCKET FINISHER:
  - AURA: the cue held diagonally, glowing with its aura and moving material.
  - BALL TRAIL: a white cue ball rolling fast across dark blue cloth, with the trail behind it.
  - POCKET FINISHER: a pool table's corner pocket with the finisher bursting out of it.
Make the VFX bright, bold and eye-catching (this is one of the rarest, most valuable items in the game), while the cue's own surface stays readable in the top view.

The cue:
THE CUE: SERAPH
Look: White marble with gold filigree.
Moving material: gold light runs along the filigree. Aura on the cue: a glowing halo of light floats above the butt, with white feathers drifting down through golden light motes. Cue ball trail: a golden light ribbon. Pocket finisher: a beam of heavenly light shines down into the pocket, with feathers.
Colours: #FAFAF5 #D4AF37 #FFF3C4.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/L5.png
```

## L6: Legendary: Infernal

**Cues:** Infernal  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/L6.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout, like a premium item showcase sheet:
- TOP: the full cue side-on across the whole width, clean with no particles, with its name INFERNAL and rarity LEGENDARY in small caps above it.
- MIDDLE: three close-ups side by side, labelled SHAFT AND JOINT, FOREARM, BUTT: the upper shaft and the joint collar; the forearm; and the butt sleeve and bumper.
- BOTTOM: three VFX panels side by side, labelled AURA, BALL TRAIL, POCKET FINISHER:
  - AURA: the cue held diagonally, glowing with its aura and moving material.
  - BALL TRAIL: a white cue ball rolling fast across dark blue cloth, with the trail behind it.
  - POCKET FINISHER: a pool table's corner pocket with the finisher bursting out of it.
Make the VFX bright, bold and eye-catching (this is one of the rarest, most valuable items in the game), while the cue's own surface stays readable in the top view.

The cue:
THE CUE: INFERNAL
Look: Obsidian black with red-hot cracks and a cartoon horned skull emblem painted on the butt (no gore).
Moving material: magma pulses through the cracks. Aura on the cue: dark red hellfire licks up the handle, with ember sparks. Cue ball trail: a black-and-red fire trail. Pocket finisher: a hellfire eruption with a skull-shaped puff of smoke.
Colours: #0A0A0C #E0201A #FF8A1F.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/L6.png
```

## L7: Legendary: Clockwork

**Cues:** Clockwork  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/L7.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout, like a premium item showcase sheet:
- TOP: the full cue side-on across the whole width, clean with no particles, with its name CLOCKWORK and rarity LEGENDARY in small caps above it.
- MIDDLE: three close-ups side by side, labelled SHAFT AND JOINT, FOREARM, BUTT: the upper shaft and the joint collar; the forearm; and the butt sleeve and bumper.
- BOTTOM: three VFX panels side by side, labelled AURA, BALL TRAIL, POCKET FINISHER:
  - AURA: the cue held diagonally, glowing with its aura and moving material.
  - BALL TRAIL: a white cue ball rolling fast across dark blue cloth, with the trail behind it.
  - POCKET FINISHER: a pool table's corner pocket with the finisher bursting out of it.
Make the VFX bright, bold and eye-catching (this is one of the rarest, most valuable items in the game), while the cue's own surface stays readable in the top view.

The cue:
THE CUE: CLOCKWORK
Look: Brass and copper with a glass-look forearm full of gears.
Moving material: the gears visibly turn. Aura on the cue: little steam puffs and tiny cogs dropping off. Cue ball trail: brass sparks and steam. Pocket finisher: cogs pop out and spin away with a burst of steam.
Colours: #B5873A #8C4A2F #E8D9B0.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/L7.png
```

## M1: Mythic: Celestial Dragon

**Cues:** Celestial Dragon  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/M1.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design. The ONE exception is the custom 3D piece described below, which is added to this model.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.
For this cue, the Celestial Dragon in image 2 is the starting point: keep its spirit, but put it on image 1's exact cue shape.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout, like a premium item showcase sheet:
- TOP: the full cue side-on across the whole width, clean with no particles, with its name CELESTIAL DRAGON and rarity MYTHIC in small caps above it.
- MIDDLE: three close-ups side by side, labelled SHAFT AND JOINT, FOREARM, BUTT: the upper shaft and the joint collar; the forearm; and the custom 3D piece from two angles.
- BOTTOM: three VFX panels side by side, labelled AURA, BALL TRAIL, POCKET FINISHER:
  - AURA: the cue held diagonally, glowing with its aura and moving material.
  - BALL TRAIL: a white cue ball rolling fast across dark blue cloth, with the trail behind it.
  - POCKET FINISHER: a pool table's corner pocket with the finisher bursting out of it.
Make the VFX bright, bold and eye-catching (this is one of the rarest, most valuable items in the game), while the cue's own surface stays readable in the top view.

The cue:
THE CUE: CELESTIAL DRAGON
Look: A pearl-white and gold cue, wrapped from butt to shaft by a see-through starlight dragon made of blue energy. The gold-horned dragon's head rests at the butt, and a glowing star gem sits in the cap. From your concept sheet.
Custom 3D piece: a see-through starlight dragon made of glowing blue energy coils around the cue from the butt up along the shaft, and its gold-horned dragon head rests at the butt; a glowing star gem is set in the butt cap.
Moving material: energy flows through the dragon's body, and it shimmers with star dust. Aura on the cue: drifting star dust and soft blue light. Cue ball trail: a comet of starlight with a dragon-tail swish. Pocket finisher: a starburst as a spectral dragon head flashes out and roars.
Colours: #FAFAF5 #D4AF37 #4FA8FF #C9E6FF.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/M1.png
```

## M2: Mythic: Kitsune

**Cues:** Kitsune  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/M2.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design. The ONE exception is the custom 3D piece described below, which is added to this model.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout, like a premium item showcase sheet:
- TOP: the full cue side-on across the whole width, clean with no particles, with its name KITSUNE and rarity MYTHIC in small caps above it.
- MIDDLE: three close-ups side by side, labelled SHAFT AND JOINT, FOREARM, BUTT: the upper shaft and the joint collar; the forearm; and the custom 3D piece from two angles.
- BOTTOM: three VFX panels side by side, labelled AURA, BALL TRAIL, POCKET FINISHER:
  - AURA: the cue held diagonally, glowing with its aura and moving material.
  - BALL TRAIL: a white cue ball rolling fast across dark blue cloth, with the trail behind it.
  - POCKET FINISHER: a pool table's corner pocket with the finisher bursting out of it.
Make the VFX bright, bold and eye-catching (this is one of the rarest, most valuable items in the game), while the cue's own surface stays readable in the top view.

The cue:
THE CUE: KITSUNE
Look: White porcelain with crimson lacquer and gold. Butt piece: a spirit-fox mask, with nine see-through tails of violet-pink foxfire flowing off the handle. Anime-inspired, with no named characters.
Custom 3D piece: a white-and-crimson spirit-fox mask sits at the butt, and nine see-through violet-pink foxfire tails flow off the handle (the tails are glowing energy, not solid).
Moving material: the nine tails sway and flicker. Aura on the cue: foxfire orbs circle the cue. Cue ball trail: a violet foxfire trail. Pocket finisher: nine foxfire orbs burst out and swirl up.
Colours: #FAF7F2 #C8102E #D4AF37 #C77DFF.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/M2.png
```

## M3: Mythic: Apex

**Cues:** Apex  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/M3.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design. The ONE exception is the custom 3D piece described below, which is added to this model.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout, like a premium item showcase sheet:
- TOP: the full cue side-on across the whole width, clean with no particles, with its name APEX and rarity MYTHIC in small caps above it.
- MIDDLE: three close-ups side by side, labelled SHAFT AND JOINT, FOREARM, BUTT: the upper shaft and the joint collar; the forearm; and the custom 3D piece from two angles.
- BOTTOM: three VFX panels side by side, labelled AURA, BALL TRAIL, POCKET FINISHER:
  - AURA: the cue held diagonally, glowing with its aura and moving material.
  - BALL TRAIL: a white cue ball rolling fast across dark blue cloth, with the trail behind it.
  - POCKET FINISHER: a pool table's corner pocket with the finisher bursting out of it.
Make the VFX bright, bold and eye-catching (this is one of the rarest, most valuable items in the game), while the cue's own surface stays readable in the top view.

The cue:
THE CUE: APEX
Look: A gunmetal mech cue with orange armor panels and cyan light strips. Butt piece: a robotic claw arm that flexes and clicks, with thruster vents that flare. It absorbs your Robotic Arm idea.
Custom 3D piece: a small robotic claw arm is mounted at the butt (three gunmetal fingers with orange armour and cyan joints), with two thruster vents on the sleeve.
Moving material: the claw flexes and the vents flare. Aura on the cue: holographic HUD rings scan up and down the cue. Cue ball trail: jet exhaust with a cyan afterimage. Pocket finisher: a targeting reticle locks on, then a blast of energy.
Colours: #2E3238 #FF7A1A #19E6FF.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/M3.png
```

## S1: Secret: Eclipse

**Cues:** Eclipse  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/S1.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design. The ONE exception is the custom 3D piece described below, which is added to this model.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout, like a premium item showcase sheet:
- TOP: the full cue side-on across the whole width, clean with no particles, with its name ECLIPSE and rarity SECRET in small caps above it.
- MIDDLE: three close-ups side by side, labelled SHAFT AND JOINT, FOREARM, BUTT: the upper shaft and the joint collar; the forearm; and the custom 3D piece from two angles.
- BOTTOM: three VFX panels side by side, labelled AURA, BALL TRAIL, POCKET FINISHER:
  - AURA: the cue held diagonally, glowing with its aura and moving material.
  - BALL TRAIL: a white cue ball rolling fast across dark blue cloth, with the trail behind it.
  - POCKET FINISHER: a pool table's corner pocket with the finisher bursting out of it.
Make the VFX bright, bold and eye-catching (this is one of the rarest, most valuable items in the game), while the cue's own surface stays readable in the top view.

The cue:
THE CUE: ECLIPSE
Look: Black obsidian with a molten-gold corona line along the cue. Butt piece: a floating total eclipse, a black sphere ringed by a blazing gold corona, with a tiny silver moon orbiting it. The most expensive-looking thing in the game.
Custom 3D piece: a floating total eclipse hovers just past the butt end: a black sphere ringed by a blazing gold corona, with a tiny silver moon orbiting it.
Moving material: the corona blazes and flares. Aura on the cue: solar flares lick off the corona while the air around the cue darkens slightly, with gold sparks. Cue ball trail: half gold, half black light. Pocket finisher: a dark ring pulses out as the pocket is eclipsed, then a gold corona flare bursts.
Colours: #050505 #FFB300 #FFF1B0 #C9CDD4.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/S1.png
```

## X1: Starter and VIP

**Cues:** Starter Cue, VIP Cue  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/X1.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 2 rows, top to bottom, split by thin grey lines. In each row:
- LEFT two-thirds: the full cue side-on, clean with no particles, so the surface design is fully visible. Below it, a 3x close-up of the handle (the joint collar to the butt end). The cue's name goes under it.
- RIGHT third: a VFX panel on a slightly darker vignette showing the same cue at a 30-degree diagonal with its aura and glow exactly as described. If the row lists a cue ball trail or a pocket finisher, add a small inset for each, labelled BALL TRAIL / POCKET: a white cue ball rolling on dark blue cloth with the trail behind it, or a pool table pocket with the burst coming out of it.

The cues:

ROW 1: STARTER CUE
Look: A friendly rookie cue: cream maple, a sky-blue forearm, a sunny yellow wrap and a little 8-ball emblem on the butt cap. The existing colors, now on the real mesh.
Glowing ring: blue glowing ring.
Colours: #E6D7B9 #3B9BFF #FFC928 #FFFFFF.

ROW 2: VIP CUE
Look: Black and gold, with a gold crown emblem on the butt and one ring that cycles rainbow (your VIP rainbow). It sits below Chroma, so buying VIP never beats a real Legendary.
Aura on the cue: gold glitter with a rainbow shimmer. Cue ball trail: a gold wisp with a rainbow edge. Pocket finisher: a small gold crown pops up.
Colours: #0E0E12 #D4AF37 #FF3D3D #3D8AFF.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/X1.png
```

## K1: Rank cues 1 (Bronze to Diamond)

**Cues:** Bronze Cue, Silver Cue, Gold Cue, Platinum Cue, Diamond Cue  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png, _attach/3_rank_badges.png  
**Save as:** `assets/cue/concepts/K1.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.
Image 3 shows the ten rank badges, Bronze to Reyes, left to right. Each rank cue's butt cap carries a small version of its own tier's badge as the emblem (seen from the side on the full view, face-on in the close-up).

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 5 rows, top to bottom, split by thin grey lines. The five cues share ONE design, a polished trophy-metal cue, and change only their metal, colours and VFX. In each row:
- LEFT two-thirds: the full cue side-on, clean, with its name under it.
- RIGHT third: a face-on close-up of the butt cap emblem (its tier badge from image 3), and next to it the cue at a 30-degree diagonal showing its VFX (a row with no VFX shows the cue alone).

The cues:

ROW 1: BRONZE CUE
Look: Brushed bronze trophy metal, with the Bronze badge on the butt.
Aura on the cue: none.
Colours: #B06A3B #6B3A1E.

ROW 2: SILVER CUE
Look: Polished silver.
Aura on the cue: a faint shine sweeps along the metal.
Colours: #C9CDD4 #7A7F88.

ROW 3: GOLD CUE
Look: Polished gold.
Aura on the cue: the shine sweep plus a few gold sparkles.
Colours: #D4AF37 #8A6A12.

ROW 4: PLATINUM CUE
Look: Ice-white platinum.
Aura on the cue: a shimmer with sparkles.
Colours: #E6ECF2 #8FB8D8.

ROW 5: DIAMOND CUE
Look: Platinum set with blue diamond inlays.
Aura on the cue: diamond sparkles and a soft glow.
Colours: #BDE6FF #3D8AFF.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/K1.png
```

## K2: Rank cues 2 (Expert to Reyes)

**Cues:** Expert Cue, Veteran Cue, Master Cue, Grandmaster Cue, Reyes Cue  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png, _attach/3_rank_badges.png  
**Save as:** `assets/cue/concepts/K2.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.
Image 3 shows the ten rank badges, Bronze to Reyes, left to right. Each rank cue's butt cap carries a small version of its own tier's badge as the emblem (seen from the side on the full view, face-on in the close-up).

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 5 rows, top to bottom, split by thin grey lines. The five cues share ONE design, a polished trophy-metal cue, and change only their metal, colours and VFX. In each row:
- LEFT two-thirds: the full cue side-on, clean, with its name under it.
- RIGHT third: a face-on close-up of the butt cap emblem (its tier badge from image 3), and next to it the cue at a 30-degree diagonal showing its VFX (a row with no VFX shows the cue alone).

The cues:

ROW 1: EXPERT CUE
Look: Ruby red with gold.
Aura on the cue: red energy rising.
Colours: #E84048 #FFC83C.

ROW 2: VETERAN CUE
Look: Emerald green with gold.
Aura on the cue: green spirit flame.
Colours: #40C460 #FFC83C.

ROW 3: MASTER CUE
Look: Amethyst purple with gold.
Aura on the cue: purple flame. Cue ball trail: its own purple trail.
Colours: #9E5CE6 #FFC83C.

ROW 4: GRANDMASTER CUE
Look: Black with gold veins, matching the badge's black feathers.
Aura on the cue: a dark aura with gold embers. Cue ball trail: a gold-and-black trail. Pocket finisher: a gold burst.
Colours: #3C3846 #FFC428 #141218.

ROW 5: REYES CUE
Look: White gold with rainbow cycling, and the turning gold rays of the Reyes badge behind the emblem. The ultimate proof of skill.
Moving material: the rainbow cycles and the rays turn. Aura on the cue: rainbow light and gold rays. Cue ball trail: a rainbow trail. Pocket finisher: a rainbow crown burst.
Colours: #FFFFFF #FF3D3D #3DFF8A #3D8AFF #FFD23D.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/K2.png
```

## Q1: Unique cues

**Cues:** Founder's Cue, Beta Cue, Grand Opening  
**Attach:** _attach/1_cue_shape.png, _attach/2_style_reference.png  
**Save as:** `assets/cue/concepts/Q1.png`

```text
Image 1 is THE cue model. Every cue on this sheet has exactly this silhouette, length, taper and parts, in this order from left to right: dark leather tip, short white ferrule, long thin tapered shaft, a metal joint collar, the forearm, one thin ring, the wrap (handle), the butt sleeve, and a rubber bumper at the very end. Do not change the shape or proportions and do not add parts; only change the surface design.
Image 2 is a style reference only: copy its premium dark showcase look, glossy semi-realistic materials and bright stylised glowing VFX. Do not copy its cues or its layout.

Sheet rules:
- This is a design spec sheet a 3D artist will copy exactly, so clarity beats drama.
- Landscape 3:2. Flat dark charcoal background (#16181D). Soft, even studio light; no harsh reflections hiding the design.
- Every full-cue view is perfectly side-on and horizontal, tip on the LEFT, butt on the RIGHT, all cues the same length.
- Use the listed hex colours.
- No text, letters, numbers or logos on the cues. The only text on the sheet: the names and labels asked for below, in small clean white capitals.
- Nothing else on the sheet: no props, no hands, no extra objects.

Layout: 3 rows, top to bottom, split by thin grey lines. In each row:
- LEFT two-thirds: the full cue side-on, clean with no particles, so the surface design is fully visible. Below it, a 3x close-up of the handle (the joint collar to the butt end). The cue's name goes under it.
- RIGHT third: a VFX panel on a slightly darker vignette showing the same cue at a 30-degree diagonal with its aura and glow exactly as described. If the row lists a cue ball trail or a pocket finisher, add a small inset for each, labelled BALL TRAIL / POCKET: a white cue ball rolling on dark blue cloth with the trail behind it, or a pool table pocket with the burst coming out of it.

The cues:

ROW 1: FOUNDER'S CUE
Look: Rose gold and black, with a founder's crest (a gold 8-ball crest) at the butt. The serial number shows in the UI, not on the texture.
Aura on the cue: slow rose-gold stardust. Pocket finisher: a rose-gold crest flash.
Colours: #1A1A1F #E8A0B4 #D4AF37.

ROW 2: BETA CUE
Look: A prototype: dark blueprint blue covered in glowing white blueprint lines, with parts shown as wireframe, as if the cue is still being designed. Pink accents.
Moving material: blueprint lines draw themselves along the cue. Aura on the cue: hologram scan lines. Cue ball trail: a wireframe line trail.
Colours: #0B1E3A #FFFFFF #FF5CB8.

ROW 3: GRAND OPENING
Look: A celebration cue: navy lacquer painted with firework bursts, and gold rings.
Aura on the cue: sparkler fizz. Cue ball trail: a sparkler trail. Pocket finisher: a fireworks show over the pocket.
Colours: #0B1440 #FFD23D #FF3D9A #3DE0FF.
```

Move your newest download into place:

```bash
mv "$(ls -t ~/Downloads/*.png | head -1)" ~/Desktop/8ball-skins/assets/cue/concepts/Q1.png
```
