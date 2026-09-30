# Report: the 13 abilities (2026-09-29)

Everything is on the branch **`abilities`** (made from `ultimates`, pushed; nothing touched
`main`, `economy`, `ultimates`, `cue-mesh` or `ranks-money`). All 13 abilities are built:
their rules, their look (Blender models and images, sounds, screen effects), a 3D icon each,
and a measured balance. The spin screen is switched on for live players
(`Config.Ults.ScreenLive = true`), so the branch is ready for you to check, merge and publish.
The brief and the full notes of every step: `docs/prompts/ABILITIES_PROMPT.md`.

## 1. What to try first (about 30 minutes)

1. Open a terminal in the project folder and run `git switch abilities`, then
   `rojo serve default.project.json`. In Studio, click **Connect** in the Rojo plugin.
2. Press **Play** (a solo test is enough for all of this). Walk to any pool table.
3. Type these in chat. They work in Studio only and act on the table nearest you.
   - `/abilitysetup magnet` puts that ability in your slot (since 2026-09-30 it no longer
     sets out a layout or seats you; then play solo and press G, the break included). You can
     use any ability's name, like `/abilitysetup black hole` or `/abilitysetup guangdong tiger`
     (the full name, spaces or not).
   - `/slowmo 0.2` plays every shot at your table at a fifth of the speed, so you can watch
     an effect. `/slowmo` on its own puts it back to normal.
   - `/hold 1.5` freezes the replay 1.5 s into the shot (to look around a moment), `/hold`
     on its own lets it go.
   - `/ulthelp` lists the other ability commands (`/ultfull` fills your bar, `/ultarm` arms
     straight away, `/ult <name>` puts any ability in your slot).
4. Go through the 13 in order, each with `/abilitysetup <name>`, then `/slowmo 0.2` for the
   big ones. What each one should do is in section 2; the chat line tells you the shot.
5. The picks: **Heat Seeker** and **Portals** ask you to pick before you shoot. The camera goes
   top-down. For Heat Seeker, tap or click one of your balls. For Portals, tap twice to place
   the two portals (drag one to move it). Then press **CONFIRM**. On a controller: the stick
   moves the cursor, A picks, Y switches portal, L1 resets, X confirms.
6. **Time Stop:** after your first hit, time freezes. Aim and shoot the cue ball again the
   normal way, up to three times. Each strike has 5 seconds.
7. The spin screen: the **Abilities** button on the left. Press **Odds**: all 13 are listed
   with their chance. Spin with `/spins 10`; `/pity 99` makes the next spin Epic or better.

## 2. The 13 abilities now

Worth = the extra balls of yours it gives per use, on average (section 3).

| Ability | Rarity | What it does | What it looks like |
|---|---|---|---|
| **Magnet** | Common | Your balls that nearly miss a pocket are pulled in. The opponent's feel half the pull. | A blue magnetic field on the cue ball; field lines pull the ball into the pocket; a shockwave on the drop. |
| **Eagle's Eye** | Common | Shows the full path of your shot while you aim, every cushion bounce included. | Gold lines under the white aim line, bounce rings, the pocket glows; an eagle screech. |
| **Super Bounce** | Common | The cue ball goes super bouncy for 8 s. The first ball of yours it hits bounces too, and boings off a pocket's edge straight in. | A rainbow shell and trail on the cue ball; star rings and a boing at every bounce. |
| **Ghost** | Uncommon | The cue ball passes through every ball that isn't yours. The ball it hits passes through them too, and a ghost pulls it into a pocket it nearly misses. | A see-through cue ball in a cold bubble, a little ghost circling it, then flying to the ball it hit; wails and whooshes. |
| **Heat Seeker** | Uncommon | Lock on to one of your balls: the cue ball curves round anything in the way to hit it, and a straight aim at it gets its cut fixed by up to 30 degrees. | A red lock-on reticle and beeps getting faster; a flame and smoke trail in flight. |
| **Rewind** | Rare | Miss (even a foul or a scratch), and the table rewinds for another 10 s shot with the full path shown. Up to twice. | A backward dial on the cue ball; for everyone, a VHS rewind of the whole table; a pink SECOND CHANCE pill. |
| **Time Stop** | Epic | At your first hit time freezes: strike the cue ball up to three more times while everything else stands still. | A violet bubble bursts out, the world goes grey-violet, a clock face on the cloth ticks the 5 s, afterimages on the moving balls. |
| **Chain Lightning** | Epic | Your ball you hit is charged toward a pocket; lightning jumps on to three more balls, pushing each toward a pocket (theirs half as hard). | A bolt strikes the ball, bolts jump ball to ball, blue glow pools on the cloth; thunder and zaps. |
| **Portals** | Rare | Place two portals for your whole turn. Any ball going into one comes out the other; yours come out turned toward a pocket. | Two swirling portals (cyan and violet); balls sink in with a flash and burst out with a pop. |
| **Steel Ball** | Legendary | Your ball you hit is guided into its pocket; then the cue ball curves on to your next ball and guides it in or lines it up. Up to 3 balls. It never scratches. | The cue ball becomes a green-and-cream steel ball with gold spirals; a gold looping path shows where each ball goes. |
| **Black Flash** | Legendary | The first ball you hit shatters, counted as pocketed (even theirs or the 8, with the normal rules), and the blast nudges nearby balls toward pockets. | A pale red frame, thick black lightning with red edges tearing out, the ball shattering into shards. |
| **Black Hole** | Mythic | A black hole opens at your first hit and swallows up to 4 of your balls within 20 in and 1 of theirs within 10 in, each counted as pocketed. | A flat black hole with a bright ring and a white-gold disk over a blue vortex; balls stretch and spiral in; a pop at the end. |
| **Guangdong Tiger** | Mythic | A giant tiger cuts up to 4 of your balls within 20 in and 1 of theirs within 10 in off the table, counted as pocketed. | A gold tiger leaps in, roars and slashes: three glowing claw marks, gouges in the cloth, each ball splitting in half. |

The skill rule (your call): Magnet, Chain Lightning, Black Flash's blast, Black Hole and the
Tiger also act on the opponent's balls, at half strength. They never touch the 8 (unless it's
your legal 8 shot) or the cue ball. While you aim, a ring shows their reach, with the
opponent's balls inside outlined in red, so where you set them off matters.

## 3. Balance

Measured by the value harness (`tests/ult_value.luau`): 120 tables, three skill levels,
each shot with and without the ability. The worth is net (your extra balls minus theirs
gifted) for a careful player; the careless column aims only for the pot (skill 2).

| Rarity | Target | Ability | Measured worth | Careless |
|---|---|---|---|---|
| Common | 0.33 | Magnet | 0.46 | 0.56 |
| | | Eagle's Eye | 0.34 | |
| | | Super Bounce | 0.33 | |
| Uncommon | 0.5 | Ghost | 0.47 | |
| | | Heat Seeker | 0.40 | |
| Rare | 1 | Rewind | 0.53 | |
| | | Time Stop | 0.47 | |
| Epic | 1.5 | Chain Lightning | 0.96 | 0.72 |
| | | Portals | 0.42 (a low bound) | |
| Legendary | 2.2 | Steel Ball | 1.09 | |
| | | Black Flash | 1.21 | 1.00 |
| Mythic | 2.6 | Black Hole | 1.32 | 1.08 |
| | | Guangdong Tiger | 1.30 | 1.07 |

- Each rarity is a little better than the one below (averages 0.37, 0.44, 0.50, 0.69, 1.15,
  1.31). The top targets can't be reached while nothing reaches more than a fifth of the table
  and the ball caps hold, so they are reported as measured (the brief allowed this).
- Two inversions: Magnet is a bit stronger than Heat Seeker, and Portals measures under the
  Rares. Portals' number is too low: the model player never reuses the portals for the rest of
  the turn. You chose to keep it and see in playtests.
- **Win rates** (`tools/ult_model.py`, each rarity's best ability against Magnet, equal
  players): Common to Epic 49-51%, Legendary 55-56%, Mythic 56%. All the bar's goals still
  pass: both players use an ability in 85%+ of matches, and missing on purpose loses.

## 4. Every assumption (one line each; dated lines in `docs/DECISIONS.md`)

1. The opponent's equipped ability shows on their top-bar badge before they use it.
2. Magnet's field lines are a deeper blue than the reference (the lighter one washed out).
3. Magnet's shockwave spreads at rail height (at cloth height the rails hid it).
4. Eagle's Eye draws the whole path, every cushion (no bounce limit was needed).
5. Super Bounce: a cushion hit within 6 in of a pocket boings your caught ball into it.
6. Ghost's worth is measured on the tables where it changes the best shot.
7. Heat Seeker flies like a missile (a 2 in turning circle, 35 to 160 in/s) along a planned path.
8. Heat Seeker corrects a straight aim's cut by up to 30 degrees.
9. Rewind with ball in hand keeps the usual time to place the ball, then the 10 s shot clock.
10. Rewind's armed look is a backward dial that waits on the cue ball's starting spot.
11. Time Stop: in stopped time you aim with the normal controls under a hint pill; watchers see the struck ball, not your cue.
12. Time Stop adds an armed violet bubble and a clock face on the cloth.
13. Chain Lightning: 15 degrees of steer, three jumps, a 20 in reach, a push that rolls 3x the way.
14. Chain Lightning adds a bolt striking the charged ball and blue pools on the cloth.
15. A ball comes out of a portal's centre, whatever part of the entry it crossed.
16. Steel Ball guides the legal 8 into its called pocket when it is the first ball hit; a later 8 is only lined up.
17. Steel Ball "close" means a clean line within 36 in; a lined-up ball stops 8 in short; it never scratches.
18. Steel Ball's outline is a Highlight; its "nyo-ho" is a whistle until you record one.
19. Black Flash's blast reaches 20 in and nudges balls 1.5x the way to their pocket; the cue ball bounces straight back, never into a pocket.
20. Black Hole opens between the cue ball and the first ball hit, for 2.5 s, and pushes the cue ball away.
21. The tiger is hand-built in Blender (no model generator was reachable).
22. The Tiger's slowed moment is 0.1 s of play over 0.7 s, so the leap and swipe fit.
23. Every ability sound is a Roblox library clip (none uploaded).
24. Full-screen effects reach the phone's screen edge, not a box inside the safe area.
25. A shot Rewind undoes pays no money; leaving or dying mid-rewind is a departure foul, and an emptied side ends the game.
26. A ball resting on a kept portal goes in only after leaving it.
27. A ball an ability removes is never a NICE SHOT.
28. A table's screen effects end once you leave it.

## 5. Every uploaded id

All uploaded to the group (675425213). Ids in `Config.Ults.Assets`; the full list with files
is `tools/upload_manifest.json`. **No audio and no animations were uploaded** (sounds are
library clips; the tiger is animated in code).

**Models** (loaded at runtime by `server/AbilityAssets`):

| Ability | Model id |
|---|---|
| Magnet | 96715013262604 |
| Super Bounce | 75004032615944 |
| Ghost | 100126316259892 |
| Heat Seeker | 130162252552172 |
| Rewind | 110978850889818 |
| Time Stop | 113214769332073 |
| Chain Lightning | 110751750592714 |
| Portals | 134871963661060 |
| Steel Ball | 83844850418816 |
| Black Flash | 75008622077798 |
| Black Hole | 86337602765410 |
| Guangdong Tiger | 119880658779603 |

**Icons** (image ids): Magnet 117672288856146, Eagle's Eye 74728958266759 (a hunter's eye since 2026-09-30), Super Bounce
95265934894642, Ghost 103298708355834, Heat Seeker 109084609734062, Rewind 120627614883189,
Time Stop 88800552854518, Chain Lightning 124544923626211, Portals 117852135071427, Steel Ball
76826199313352, Black Flash 130953532047846, Black Hole 75754504005260, Guangdong Tiger
115608626042209.

**Images** (image ids; the Decal id in brackets):
- Heat Seeker smoke flipbook 81395420363490 (126970755165309).
- Rewind: fringe 73954710228943 (79151185429591), icon flipbook 79830999355189
  (71250904849806), scanlines 106680197039186 (82791665115124), static 114309948120374
  (120393885666074), tear 77495663973716 (78629616715158), tracking 80127029771602
  (92718377745753).
- Time Stop: lens edge 113700118006901 (76685822924680), warp ring 113854329541350
  (126594807194835).
- Chain Lightning: crackle 132435040693570 (100855703223608), glow 107241054746462
  (94198140772777), spark 77146187473853 (115799752256848).
- Portals: burst ring 136798614538270 (128288450574948), sparkles 110779778163475
  (106363579778020), swirl 85317008061907 (101107225209328).
- Steel Ball: gold burst 140169441770879 (74393921524104), gold path 115232544003418
  (95892418217107), gold ribbon 121079900379610 (104561608867251), sparkle 116655548573479
  (74762707211639).
- Black Flash shock ring 74704280023743 (137668531197325).
- Black Hole pop ring 121232364344408 (82080128940075).
- Guangdong Tiger fur frame 131150432548296 (87600337874853).

**Superseded uploads to archive** (replaced by the ids above; nothing uses them). Decals can be
archived through the API (`POST .../assets/v1/assets/{id}:archive`, STUDIO_NOTES); models can
only be removed by hand in Creator Hub.
- Magnet pilot: model 87739568467897; decal 82187472592157 (the pilot's FieldBeam).
- Chain Lightning: model 116394570082854.
- Steel Ball: models 117230071734301, 84390532154285, 85966886940190, 100629865883823; decals
  108164652976149, 130156479584094.
- Black Flash: models 110511377729729, 131385936821483; decal 112993995726160.
- Black Hole: model 132811966269359.
- Guangdong Tiger: models 93994396609133, 109390616019165, 86221317508788; decals
  122114074802883, 76952602462039.

## 6. Credits

Every model and image was made for this game by script in Blender
(`tools/blender/abilities/`). Every ability sound is a public Roblox library clip; the list
with each uploader is `assets/abilities/CREDITS.md` (Pro Sound Effects, APM and players' own
uploads). Your ult_activate and ult_ready sounds are yours. The reference images were only
looked at, never shipped.

## 7. Known issues (nothing is BLOCKED)

- **Portals measures low** (0.42, under the Rares), and **Magnet** sits a bit over **Heat Seeker**.
- **The tiger** is hand-built. It reads as a gold tiger, but a generated or downloaded
  detailed tiger model would look better. It needs a model generator (Hyper3D, Hunyuan3D or
  Tripo, switched on in the Blender addon) or a CC-BY Sketchfab model. It still leans
  orange-red under the grade from some angles, and at a far contact its head can touch the top
  of the frame.
- **The ability cutscene on a phone** stops at the safe area (its ScreenGui lacks
  `ScreenInsets.None`). That is the ultimates work's code, so I left it alone; it's a one-line
  change.
- **The daily-reward reminder toast** can sit over the ability pill on a phone (seen when the
  window loses focus). This is not ability code.
- Look notes left from the checks:
  - Magnet's pull is small from the overhead replay camera.
  - Rewind's green dial edge fades on the green cloth.
  - Time Stop's lens edge also tints the HUD.
  - Chain Lightning's forks are thin from the top camera.
  - Portals' violet portal reads lighter than the cyan one.
  - Steel Ball's pot burst is pale on the bright cloth.
  - Black Flash's and Black Hole's screen grades and streaks run on wall time, so under
    `/slowmo` they end early (at normal speed they match).
- **Super Bounce's `/abilitysetup` shot** missed once in the playthrough (the effect itself
  worked).
- The live developer commands (you, the place creator and group rank 255) can arm abilities in
  real matches. That's insider-only; say if you want them limited to Studio.
- The two ability slot purchases read "Soon". Their game passes belong to the ultimates work.

## 8. What needs you

1. **A real controller:** the pick view (stick or D-pad, A, X, Y, L1) and Time Stop's strikes.
   Studio's MCP can't press gamepad buttons.
2. **A real phone:** touch aim in stopped time (Time Stop), and whether the big payoffs (the
   Tiger, Black Hole, Black Flash) run smoothly. The emulator checked framing and taps only.
3. **Two real players** (Test > Clients and Servers, or a friend): both screens should show
   the same effect at the same moment, and the opponent's view of each ability.
4. **Time Stop, two strikes in a row:** after a strike you should be able to strike again at
   once. I fixed a 2 s wait there, but the fix is in the real input path, which only a hand can
   test.
5. **Record your own "nyo-ho"** for Steel Ball (a two-note whistle stands in). Upload it and put
   its id in `Config.Ults.Sounds.SteelCall`.
6. **Archive the superseded uploads** (section 5).
7. **Merge `abilities` and publish** when you're happy. I don't merge or publish. Studio's
   Team Create already holds the place; save a copy to `place/8ball.rbxl` once at the merge if
   you want git to have it.

## 9. Ideas for later (also in the GDD's parked list)

- A generated or downloaded detailed tiger model for Guangdong Tiger.
- Portals: if playtests agree it's weak, let the kept portals pot one of your balls for free,
  or move it to Rare.
- The PC opponent (and future bots) using abilities other than Magnet, with a picker for Heat
  Seeker and Portals.
- A short "how it works" card for each ability on the spin screen (a looping clip of the effect).
- Sound sheets per rarity to cut the number of sound loads (the player is ready, nothing packed yet).
