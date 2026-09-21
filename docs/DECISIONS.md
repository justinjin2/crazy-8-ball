# Decisions

Dated one-liners with the reason. This is the only place that records when something was
decided; the GDD and roadmap state the result without dates. Newest at the bottom.

- 2026-09-18: Custom physics instead of Roblox physics. Precision, determinism, and abilities
  need hooks inside the simulation.
- 2026-09-18: 9 ft table at 0.16 studs per inch; balls 1.3 in radius. Readability on phones.
- 2026-09-19: One 3D aim camera, no top-down toggle. Top-down made the 3D pointless.
- 2026-09-19: Orbit camera opposite the aim with automatic whole-table framing; zoom is one
  continuous axis down to a low "down the cue" view. Solved the "aiming backwards shows floor"
  problem without going top-down.
- 2026-09-19: Shot camera pulls out to the whole table instead of following the cue ball.
  Trickshots on other balls were invisible.
- 2026-09-19: Guideline drawn as a one-ball-wide corridor. The centre line alone read wrong
  from the low view.
- 2026-09-19: Sphere-mesh balls with baked textures instead of decals on Ball parts. Decals
  blurred up close.
- 2026-09-19: Imported Blender table model and bright lounge package replace the parts-built
  table and the planned dim room.
- 2026-09-20: Working name Crazy 8 Ball. Currency is "money". No loser finisher effect.
- 2026-09-20: Next milestone is the lounge with twelve server-owned tables (Roadmap 1.5), then
  spin, sound and rules. The server move is needed anyway and the map is built.
- 2026-09-20: Shop, inventory, save data and the first-time flow must exist before the game is
  public; Founder's and Beta items go on sale at that release.
- 2026-09-20: All three difficulty levels are built early as a host option with no lock until
  ranks exist; then the host is locked by peak rank and guests get a warning with Play anyway.
- 2026-09-20: Ability cooldowns count in the user's own turns; the framework supports
  opponent-targeting and opponent-turn abilities from day one.
- 2026-09-20: Solo, 1v1, 2v2 and 3v3 are all in the release; table code is team-shaped from
  the start.
- 2026-09-20: Join by stepping on a floor pad with sound, VFX and a green indicator, replacing
  the hold-E prompt.
- 2026-09-20: Open table after the break; 8 on the break is re-spotted; timeouts are fouls,
  two in a row forfeit; leaving is a forfeit.
- 2026-09-20: PC opponents are labelled everywhere except the scripted first match, which uses
  one disguised PC.
- 2026-09-20: One visible rating number with divisions I (bottom) to V (top), peak rank saved,
  difficulty multipliers, Classic and PC gains capped above Diamond.
- 2026-09-20: One match type: every match against a person or PC changes rating; the old
  "ranked = self-help abilities only" rule is deleted.
- 2026-09-20: Anti-boost by opponents-played-today counters: rating shrinks to zero, money
  shrinks but never to zero, no friend exemption.
- 2026-09-20: Money packs are sold for Robux; all boxes, gacha and trading follow Roblox's
  paid-random-item rules (odds shown, restricted-region catalog).
- 2026-09-20: Unified item catalog; unique IDs with serials per cue and table; abilities are
  account-bound flags; cues and tables trade, including VIP and starter-offer ones; money
  never trades.
- 2026-09-20: Every table collectible is its own full 3D model under a strict budget.
- 2026-09-20: All ages, R6 and R15 allowed, non-alcoholic snack counter, no wagering.
- 2026-09-20: First-time flow per GDD section 14; starter ability Magnet Pocket, kept forever;
  at release players own only the starter and roll the rest.
- 2026-09-20: Rematch and Leave on the post-match screen with a 15 second window.
- 2026-09-20: Aim angle and ball-in-hand position replicated live to opponents and spectators.
- 2026-09-20: Gamepad support is built and checked in every milestone from now on; the pro
  lobby is a separate place reached by teleport.
- 2026-09-20: Reminders trigger on menu open and window focus loss (subtle in-game toast), not
  inside Roblox's own menu.
- 2026-09-20: Codex also writes game code; both tools follow the same rules file (AGENTS.md is
  a symlink to CLAUDE.md) and update STATUS.md. Private GitHub remote; place file committed at
  each milestone; binaries stay in plain git with hygiene rules.
- 2026-09-20: Spectators sitting on lounge chairs get free look only; table cameras wait for
  Roadmap 2.3. Closes the open question in GDD section 6.
- 2026-09-20: Table position and yaw live in a pure `Placement` module, not in TableBuilder.
  A pool table is symmetric end to end, so a yaw sign error builds a table that looks right
  and plays mirrored; only a Lune test can catch that.
- 2026-09-20: Balls are turned by the simulation's own angular velocity, never by distance
  travelled. The old way hid the skid, hid side spin, and spun balls wildly down pockets.
- 2026-09-20: Clients step a live simulation from the render loop instead of calling
  `Simulation.run` up front, which blocked a whole frame per break and built a frames table
  of several megabytes. `run` keeps its frames for the tests; the server gets `runHeadless`.
- 2026-09-20: Join by stepping on a floor pad, polled on the server at 5 Hz with a three
  poll dwell. Touched misses a player who stands still; the dwell stops someone crossing a
  pad on the way somewhere else being dragged into a seat.
- 2026-09-20: Pads sit 14 studs out from the table centre, clear of where the shooter
  stands. At 11 studs the shooter was standing on the pad and could never leave.
- 2026-09-20: Clients replay a shot from the server's POST-STRIKE cue ball state, not from
  {angle, power}. Cue.strike goes through libm sin/cos/pow, which are not correctly rounded,
  so re-striking on each client risks a one ulp difference and therefore a different break.
- 2026-09-20: Every shot carries a checksum of the server's final positions and clients warn
  when their replay lands elsewhere. Determinism is measured, not assumed.
- 2026-09-20: Only the nearest few tables draw their balls (a renderer pool). Twelve racked
  tables is 192 ball meshes for something that is a few pixels across the room.
- 2026-09-20: Aim is replicated as one batched unreliable message per tick for all tables,
  not one per table per player.
- 2026-09-20: Gamepad power is on the right trigger, not zoom. A trigger's travel is a power
  bar; mapping an analog axis to zoom wastes it. Departs from the GDD's "or triggers" aside.
- 2026-09-20: Remote players' bodies are not posed for watchers; only their cue is
  replicated. AvatarPose anchors individual limbs, which does not replicate reliably from
  the owning client. Body posing for watchers is deferred to Roadmap 2.3.
- 2026-09-20: Cue PowerCurve 1.6 -> 2.6 and SlidingFriction 0.20 -> 0.25, because balls read
  as sliding on ice. MaxSpeed is a 30 mph break, so at 1.6 a half-pulled bar gave 184 in/s,
  which slides 128 inches before it rolls on a 100 inch table: nothing ever rolled. At 2.6
  the middle of the bar lands on real pool shot speeds and a normal shot rolls within 25
  inches. Hard shots and the break still skid, which is true to pool.
- 2026-09-20: Pendant fixtures lifted 4.5 studs. The package hangs them 4.6 studs above the
  cloth and the aim camera sits at 10.8, so they hung between the player and the table. The
  drop is shortened rather than the fixture moved, so the cord still meets the ceiling.
- 2026-09-20: The shooter is hidden outright while the balls are moving and comes back when
  they stop, rather than staying faintly visible. They used to be posed against the LIVE cue
  ball, so the body slid around the cloth chasing it for the length of the shot.
- 2026-09-20: Past about 8 studs of reach the shooter fades out entirely. A cue ball against
  a cushion with the shot going into it is nearly a table length from anywhere a person could
  stand, and no stance reads as a person from a camera on the far side; fading beats
  contorting.
- 2026-09-21: The placeholder lounge is switched off (`Config.Lounge.Enabled = false`,
  `TableCount = 1`) and testing happens on a plain baseplate with one table. The designer
  does not like the model. The lounge code, the pads, the renderer pool and the server
  authority all stay; only the geometry and the table count change. The imported model was
  moved to ServerStorage rather than deleted.
- 2026-09-21: Sound and juice (Roadmap 1.7) is pulled ahead of spin (1.6) at the designer's
  request.
- 2026-09-21: A cue owns its cue-ball TRAIL and its pocket burst, not just its mesh. Default
  and common cues share one minimalist white translucent wisp; rarer cues bring their own
  pair, which is the main reason to want them. Effects are a named style in catalog data, so
  adding a cue stays a data row plus assets and never code. Built data-driven from the start
  so Roadmap 5.2 only has to add rows.
- 2026-09-21: Anti-boost counters are deleted. Rematches against the same person are unlimited
  and fully rated; the only test is whether the match was real (over one minute of server-
  tracked match time and not a forfeit). Forfeits still cost the forfeiter rating, and repeat
  forfeits against the same opponent give the winner nothing. The old counters punished
  friends playing honestly; a time check punishes only the throw.
- 2026-09-20: The game's sounds are the designer's own recordings, uploaded to the group that
  owns the place so they resolve by id with nothing inserted into Studio by hand. Fourteen
  clips: six ball-on-ball takes (including two with a slight rattle), one cushion, two cue
  strikes, two pocket drops and three rolling takes. Only the aim tick is still a Roblox
  library sound, because it is a UI click rather than a pool sound and none was recorded.
- 2026-09-20: Clip choice is RANDOM and never repeats the previous clip; impact SPEED drives
  volume and pitch. These are separate mechanisms on purpose. Variation is what stops a break
  sounding like a machine gun, and no amount of pitch shifting substitutes for it, because
  the ear spots exact repetition instantly. The designer asked for the rattle takes to be
  used randomly rather than reserved for a special event, so all six clacks sit in one pool.
- 2026-09-20: Every clip carries a MEASURED gain that levels it against the others, taken with
  `tools/measure_audio.luau` (AudioPlayer -> AudioAnalyzer in Studio). Without it the random
  choice, not the impact speed, decides how loud a hit is: the recordings span 14 dB, from
  the cushion take at peak 0.18 to the pocket drops at 0.91. `ball_rolling_1` measured 15x
  quieter than 2 and 3, so it carries a gain of 15; its noise floor sits 10.4 dB below its
  own average, which is the measurement that says the material survives the boost.
- 2026-09-20: The volume curve is LOGARITHMIC, not linear. Measured over 48 shots, the median
  ball-on-ball contact is 3.6 in/s and the 90th percentile is 66.8 while a break tops 520, so
  the old linear divide-by-200 put 49% of audible contacts in the bottom fifth of the range
  and the table sounded timid at every power. The log curve puts 8 of 10 volume deciles in
  real use instead of 5.
- 2026-09-20: The rolling sound is ONE continuous sound for the whole table, following the
  fastest ball still moving and emitted from that ball, rather than one loop per ball.
  Sixteen loops would phase against each other and cost sixteen voices for something the ear
  hears as a single texture. It is built from two alternating Sounds that CROSSFADE at equal
  power rather than one looped Sound, because the recordings are not known to loop seamlessly
  and Roblox re-encodes uploads anyway; a seam clicks every couple of seconds and during the
  quiet stretch of a shot that click would be the only thing audible. Each pass also starts
  at a random offset, because the slow tier holds a single recording and the table spends
  about two thirds of a shot in it.
- 2026-09-20: `SoundService.DopplerScale` is set to 0 (the engine clamps it to 0.001). The
  camera sweeps out to the whole-table view at the moment a break fires and the roll emitter
  moves between balls, so Doppler would warble every clip against the pitch the audio module
  is deliberately setting, and it would be very hard to recognise as Doppler.
- 2026-09-20: `Config.Audio.RollOffMinStuds` went from 8 to 18 and the distance model is set
  explicitly to InverseTapered. The playfield is only about 16 x 8 studs and the camera was
  measured at 16.2 to 17.5 studs during a shot and 2.2 studs in the close aiming view, so a
  min distance of 8 sat inside the camera's own range and the mix changed with the zoom.
  Roblox's default Inverse model also never reaches zero, which made RollOffMaxStuds a number
  that did nothing.
- 2026-09-20: Impact emitters are pooled Attachments on one anchored part rather than a fresh
  Part per contact. A Part-parented Sound is affected by `SoundService.VolumetricAudio`, a
  place-level setting anyone could flip in Studio, while an Attachment is a point source
  whatever that is set to.
- 2026-09-20: Cushion clips are chosen by IMPACT SPEED, not at random. A soft bounce off the
  rail and a hard thud into it are different sounds, not one sound at two volumes, so a
  second cushion recording was added with a speed band: the soft take up to 70 in/s, the hard
  one from 40. The bands OVERLAP deliberately and the choice is random inside the overlap,
  which blends one recording into the other instead of switching at a line a player would
  learn to hear. A speed that falls in no band makes the whole list eligible, so a typo in
  Config leaves the event a bit random rather than silent. `SoundMix.pickBanded` is the
  mechanism and any clip list can use it.
- 2026-09-20: Rails were turned down 10.1 dB and now sit 12.6 dB below a ball-on-ball clack at
  the same impact speed, where they used to sit 2.4 dB below it. A cushion is a duller,
  quieter thing than two phenolic balls meeting, and rails are the most frequent contact in
  the game after ball hits, so at the old level they dominated every shot. The new soft
  cushion recording is also the hottest asset in the set (peak 0.955 against the old rail's
  0.182), so its measured gain of 0.52 takes another 14.4 dB off it relative to playing it
  raw. The gap between rails and clacks lives in `Config.Audio.Rail.MaxVolume`.
- 2026-09-20: The rolling loop was 13.1 dB too loud and is now at `Roll.MaxVolume = 0.10`.
  The cause was a mixing error, not taste: the rolling clips are levelled on RMS and the
  impact clips on PEAK - each correct on its own, since RMS is what you hear in continuous
  material and peak is what you hear in a transient - but the two families were never checked
  against each other. At the old 0.45 the roll sat 4.2 dB ABOVE a ball-on-ball clack in RMS
  terms, continuously, while a clack lasts 0.08 seconds, so it sat on top of the whole mix.
  It now sits about 9 dB under a clack, which is where a background bed belongs.
- 2026-09-20: The floor for ball-on-ball sound dropped from 12 in/s to 1, split out of the
  shared `MinImpactSpeed` into `MinClackSpeed` and `MinRailSpeed` so cushions keep their own.
  Measured over 48 shots, 66% of all ball contacts happen below 12 in/s and the median is
  3.6, so the old floor silenced two thirds of the game's contacts and gentle touches made no
  sound at all. Replaying the rate limiter against real event times, the floor was the whole
  problem: it takes a shot from 2.5 audible clacks to 4.5, while tightening the gap between
  clacks from 0.035 all the way to 0.010 only reaches 5.6 and takes the busiest single second
  from 13 clacks to 19, which is where a break turns to mush. The gap moved 0.035 -> 0.022
  and stopped there. Contacts under about 0.05 in/s stay silent: those are two balls already
  touching being re-detected, and a settled rack must not buzz.
- 2026-09-20: `Config.Audio.Clack` carries its own `QuietSpeed` of 1 in/s against the shared
  10. With the shared floor every contact below 10 in/s flattened onto the same minimum
  volume, so even once they were audible they would all have sounded identical. Starting the
  clack curve at 1 gives the bottom two thirds of the range somewhere to go, and because the
  curve is a ratio the change tapers to nothing at the top: +6.3 dB at 12 in/s, +2.4 dB at
  40, +0.0 dB at break speed. Breaks are untouched; only the gentle end moved.
- 2026-09-20: The soft ball-on-ball take is banded to gentle contacts (up to 25 in/s, alone
  below 6), the five firmer takes from 6 up. It is a recording of a gentle contact, so
  playing it for a break - or playing a firm take for a ball rolling into another one - is
  simply the wrong sound. This supersedes the earlier "all six at random": the designer asked
  for soft touches to play the soft clack.
- 2026-09-20: The harder cushion recording (`ball_hitting_edge_table_hard`) is dropped and the
  softer take now covers EVERY rail contact, gentle through hard, at the designer's call: the
  old one did not sound like a ball meeting a cushion. A clean sample carried across the range
  by volume and pitch beats an unconvincing one used at its "correct" speed, so this
  supersedes the speed banding added for cushions earlier the same day.
  The cost is variation, since rails are the most frequent contact in the game after ball
  hits and there is now one take for all of them. `Config.Audio.Rail` therefore carries its
  own `PitchJitter` of 0.05 against the global 0.04, and its speed-driven pitch range was
  narrowed from 0.88..1.08 to 0.90..1.07 so the two together stay inside the 15% beyond which
  a pitched sample stops sounding like the same object being struck. Measured: 34 cushion
  hits across 13.6 dB of volume and 16 distinct pitches.
- 2026-09-20: A hard break now STACKS its contacts instead of queueing them. Contacts at or
  above `Config.Audio.StackSpeed` (110 in/s) skip the minimum gap between clacks and are
  allowed to sound together, up to ten inside a tenth of a second. 110 is a measured
  discriminator rather than a guess: on a full-power break nine contacts clear it and every
  one falls inside the same 90 ms window, starting 0.091s in as the cue ball reaches the
  rack, while at half power nothing reaches it at all. A contact can never be faster than the
  ball that struck it, so the cue-ball speed is a hard ceiling - stacking is impossible below
  52% power, which keeps it entirely out of ordinary play. Nine sounds of equal level sum to
  about +9.5 dB, and that, not the volume curve, is where a break's weight comes from: the
  clack curve itself only moved 1.0 -> 1.1, because nine voices pushed much harder would sum
  into the master mixer's ceiling and clipping is uglier than being a shade quiet.
- 2026-09-20: Cushions dropped another 8 dB at the designer's call and now sit 22 to 30 dB
  below a ball-on-ball contact at the same speed - present but barely noticeable, which is
  where the game's most frequent contact belongs. `Config.Audio.Rail.MaxVolume` is the number
  to raise if they become inaudible rather than subtle.
- 2026-09-20: The power control keeps its vertical bar and fill, and gains a top-down CUE
  lying inside it that slides down as you pull. A cue-only control with no bar was built and
  tried first at the designer's request and rejected on sight of it running, so the bar came
  back with the cue inside rather than instead of it.
- 2026-09-20: A cue's LOOK is data, like its effects already were. `Config.Cue.Styles` lists
  segments from tip to butt - leather tip, ferrule, shaft, joint collar, forearm, ring, wrap,
  butt cap - each a share of the length and a colour, plus how far the cue tapers. The style
  name is the same key `Config.Effects.Styles` uses, so one name picks a cue's whole identity:
  its look, its trail and its pocket burst. A collectible cue stays a data row (Roadmap 5.2)
  and the same row can drive the 2D cue in the control, the 3D stick on the table and an
  inventory thumbnail. `src/shared/CueArt.luau` turns a style into slices and is Lune-tested,
  because a Frame cannot be a trapezoid: the taper is built from thin stacked bands, and
  getting a band boundary or a taper direction wrong looks like bad art rather than a bug.
- 2026-09-20: Drawing the cue back plays a rubber-tension recording whose volume and pitch
  follow how far back it is. Pitch RISES with the pull here, the opposite of an impact:
  tightening something raises its pitch, while a harder knock reads as heavier and lower. The
  recording swells over its 2.776 seconds, so a drag held past the end loops back to 1.3s
  rather than to zero - restarting at the quiet head would drop the tension out from under a
  player who is still holding the cue back. It is driven from the pull value rather than from
  the control, so a gamepad trigger makes exactly the same sound as a finger.
- 2026-09-21: The power cue nearly fills the bar at rest and slides a WHOLE bar height at
  full pull, so it leaves the bar completely and hangs below it, per GamePigeon reference
  shots the designer supplied. The bar deliberately does not clip its children, or the cue
  would be cut off at the bottom edge instead of travelling past it, and the percentage label
  moved above the bar because at full pull the cue covers everything beneath it.
- 2026-09-21: The tension sound is played straight through at ONE volume and stopped when the
  pull ends. It first scaled volume and pitch with how far back the cue was, and that was
  wrong for this recording: measured, it is quiet friction that only builds late (RMS 0.006
  across its first stretch against 0.025 near its end), so scaling the start down as well
  left the beginning of every pull all but inaudible - and the beginning is the part you hear
  most, because that is when your finger is actually moving. The loop-back-past-the-quiet-head
  machinery went with it; a pull held past 2.776s simply ends, which is what "the normal
  sound" means.
- 2026-09-21: The power bar is anchored HIGH on the screen rather than centred, and its
  height fraction dropped 0.62 -> 0.42. The control needs room for the bar and for the cue
  hanging a whole bar height beneath it - about 1.97 bar heights all told - and a centred bar
  pushed the bottom of the cue off the screen. Measured before: 66 px of the cue fell off the
  bottom edge at full pull. After: the whole cue is on screen with 123 px to spare.
- 2026-09-21: The tension sound follows the MOTION of drawing back, not the tension of being
  held there. It plays only while the pull is still growing and goes quiet once it stops, the
  way friction actually does; pressing the control makes no sound and neither does holding at
  full power. This needs a per-frame check rather than an event, because a finger that stops
  moving sends no further input and nothing would otherwise tell the sound to stop - it is
  the clock that notices. A drag that pauses and carries on RESUMES the recording rather than
  restarting it, so an ordinary stop-start drag keeps rubbing instead of re-triggering the
  clip's opening over and over.
- 2026-09-21: The aim tick dropped to 0.12 and is now quieter than EVERY ball-on-ball
  contact, measured: 2.1 dB under the quietest audible clack and 21.5 dB under a typical one.
  It fires on every step of rotation, so it is the most repeated sound in the game by a wide
  margin and being merely quiet on paper was not enough.
- 2026-09-21: The rubber-band recording ENDS with the band being released, and this sound
  must only ever be something under tension, so playback is held to the stretch before it.
  The release is a single unmistakable transient at 2.539s - RMS 0.130 and peak 0.810 against
  nothing above RMS 0.029 or peak 0.13 anywhere earlier - so the Sound is given a playback
  region of 0 to 2.45s and the engine itself will not go there. It also loops back to 1.0s
  rather than stopping, so a drag with more than 2.45 seconds of continuous motion keeps
  stretching instead of falling silent. Verified: playback ranged 0.011 to 2.347 and stayed
  0.192s clear of the snap.
- 2026-09-21: The power bar dropped to a top fraction of 0.145. At 0.07 its PULL label sat
  behind the Leave button, which occupies the top right corner down to 52 px. The label now
  clears it by 12 px and the whole cue still fits at full pull with 43 px to spare.
- 2026-09-21: A ball dropping nudges the camera a hair TOWARD the pocket it went into. It is
  sized as a reward rather than an effect: a sixth of a stud at full strength against a camera
  12 to 15 studs out, about half a percent of the view, over a quarter of a second, swinging
  barely more than once. Horizontal only, because a camera that bobs vertically is far more
  nauseating than one that slides, and it is FAST repeated motion rather than large motion
  that makes people feel sick. A gentler drop gets less of it, but every drop gets some: a
  pocket that gave nothing back would feel broken.
  The shake is added on top of a pose the smoothing chases separately, never folded into it.
  Lerping from an already-shaken camera would smear the shake into the smoothing and let it
  drift; keeping them apart is what lets it settle to exactly zero.
- 2026-09-21: A pocket's opening is DERIVED from the mouth it belongs to, not tuned
  separately: radius = half the mouth width, placed so the rim is tangent to the line joining
  the two cushion noses (`Config.Table.PocketOpeningMouthFraction`, 1.0). A corner opening
  therefore lands exactly on the table corner at radius 2.600, and the corner jaw tips fall
  at 2.609 from that centre - the rim and the jaws coincide, which is what a real pocket looks
  like. The old numbers were four free fractions that had drifted into nonsense: the physics
  captured at 1.950 while the art drew 2.450, so a ball's centre could be half an inch inside
  the visible hole and still not fall, a ball had to travel 3.12 in past the mouth before
  anything took it, and a ball hugging the rail into a corner could never reach the hole at
  all - its centre line missed the circle by 0.6 in, so it only vanished via an axis-aligned
  fallback 4.25 in further on. Balls entering off-centre still meet a shelf, which is what
  keeps rattling and hanging in the jaws possible; they just stop being permanent. Measured
  after: 203 shots at a corner gave 174 pocketed, 29 rattled back onto the cloth and 0 left
  stranded past the cushion line; 203 at a side gave 101, 102 and 0.
- 2026-09-21: TableBuilder cuts the pocket hole one leather thickness wider than that same
  radius, so the lining's INNER face lands exactly on the physics rim. Art and physics now
  read one number and cannot drift apart, and `Look.PocketLinerExtraInches` is gone. The
  falling ball's SURFACE rides the liner rather than its centre, which had let half the ball
  hang through the leather on the way down.
- 2026-09-21: A ball whose centre crosses the rim TIPS IN rather than being teleported into a
  fall. It pivots about the rim point it crossed - a solid sphere on an edge, so with I about
  the pivot = 7/5 m R^2, alpha = (5g/7R) sin(theta) - and leaves the lip the moment the edge
  stops pushing back, R*omega^2 >= g cos(theta). That single rule covers the whole range with
  no threshold to pick: a ball that trickles over hangs and takes about a third of a second to
  topple, while anything arriving at 50 in/s or more fails the test on its first evaluation
  and drops exactly as it always did. Measured in the live server: 0.163s at 3 in/s, 0.100s at
  8, 0.025s at 20, 0.000s at 60 and 150.
- 2026-09-21: The pocket event fires when the ball comes OFF the lip, not when it crosses the
  rim. Fired at the crossing a hanger would report ~0 in/s and its drop would be inaudible;
  off the lip it carries the ~17 in/s gravity has given it, which is an honest number for the
  sound mix. A fast ball separates on the first test, so its event is unchanged.
- 2026-09-21: `Simulation.isAtRest` now says a ball sitting still over an opening is NOT at
  rest. Without it a shot could end with a ball balanced over the hole and nothing would ever
  look at it again, which together with `capturePockets` skipping stopped balls is what made
  hangers permanent.
- 2026-09-21: Cue strikes are banded by POWER, not picked at random: cue_strike_2 over the
  bottom quarter of the bar, cue_strike_1 over the middle half, cue_strike_3 over the top
  quarter. Held as power fractions and converted to cue ball speeds in Config's derived block,
  because speed goes as power^2.6 and the two are nothing like proportional - 25% of the bar
  is 29 in/s out of 528, so writing the bands as speeds would hide where the lines actually
  fall. Band edges are inclusive at both ends, so exactly on a line either neighbour may play.
  cue_strike_3 is levelled to the same peak as the others but is four times the length of
  cue_strike_2, so it still reads as a much bigger sound - which is what makes the top of the
  bar feel different rather than just louder.
- 2026-09-21: The aim tick needed a rate limiter once it stopped being a 22 ms library click.
  A tick fires every 2 degrees of rotation and a gamepad stick held hard over turns at 80
  degrees a second, so 40 ticks a second; at 0.107s per clip that is four or more sounding
  at once, continuously, and four voices spent on a UI click. `MinSecondsBetweenTicks` is set
  just under the clip's own length so two can never overlap. Slow, careful aiming never
  reaches the limit, which is exactly where per-degree feedback is worth having; a fast sweep
  becomes a steady click instead of a smear. Verified: 60 ticks requested back to back over
  one second played 10.
- 2026-09-21: The new tick's LEVEL was carried across rather than re-picked by ear. The
  library click played at volume 0.12 against peak 0.230 at gain 1, so 0.028 reached the
  mixer; the new clip peaks at 0.729 and its gain brings that to 0.5, so volume 0.055 puts
  exactly 0.028 back. That keeps it 2.0 dB under the quietest audible clack and 25.9 dB under
  a loud one, which is the bar the tick has to clear as the most repeated sound in the game.
- 2026-09-21: A bright UI sting now layers on top of every pocket drop, forced a voice the
  same way the drop is. Sized at 12.0 dB under the drop at the drop's loudest: the drop is the
  event and this is the garnish, and the drop is already the loudest thing in the game.
  Pitched dead straight, with PitchJitter 0, because a UI sting that wanders in pitch stops
  sounding deliberate - the opposite of the impact sounds, where wobble is the disguise. It is
  withheld when the pocketed ball is the cue ball: a scratch is not a reward.
  Lowered to 15.8 dB under the drop the same day, at the designer's ear: 12 dB still sat too
  far forward for something whose whole job is to be felt rather than noticed.
- 2026-09-21: The aim tick fires every 0.1 degrees, not every 2, at the designer's call. The
  smallest deliberate movement a player can make is a nudge tap at 0.2 degrees, which under
  the old value was a tenth of a tick - so careful aiming, the one place per-degree feedback
  is worth having, was silent. Slow aiming now clicks on every single step: measured at 3
  deg/s, all 23 ticks asked for in a second played.
- 2026-09-21: `MinSecondsBetweenTicks` stays at 0.1, and it is a CEILING rather than a rhythm:
  under it every 0.1 degree clicks, over it the extra steps are swallowed. Both halves of the
  behaviour fall out of that one number. At 0.1 degrees a tick, a 10-a-second ceiling is one
  degree per second - so adjusting slower than that, which is what nudging by tenths is, every
  single step sounds, and sweeping faster it stops trying to keep up. Measured: at 0.5 deg/s
  all 9 steps played and at 1 deg/s all 17; by 3 deg/s it is one click per 0.38 degrees, at
  40 one per 4.2, at 400 one per 44. So the faster the aim moves the more ground a click
  covers, which is the point.
  It was briefly 0.033 on the theory that the envelope (90% of the energy spent by 48 ms)
  allowed 30 a second. It does allow it, but 30 a second is a continuous ratchet three clips
  deep, and only the slow half of the range is worth tracking step for step. Tracking how
  audible the clip is answered the wrong question; the question is how busy the sound should
  be.
- 2026-09-21: The tick's volume stays at its carried-over 0.055. It was cut about 4 dB while
  the gap was 0.033, because clips piling three deep are heard as far louder than an
  occasional click. At a 0.1 gap consecutive ticks no longer overlap at all - the clip is more
  than 34 dB down past 65 ms - so that correction had nothing left to correct for. Measured at
  2 voices at every aim speed, against 4 to 8 before.
- 2026-09-21: The cue, the ghost ball and the guideline are gone the instant the cue is
  released, and come back when the table is the player's again. They used to sit on screen
  through the whole server round trip, still pointing at a shot already taken, because the
  only thing hiding them was `match:isBusy()` - and the shot does not begin on the client.
  Inputs go to the server and the balls only move when it broadcasts the result back, so
  `isBusy()` stays false for the entire trip. A client-side `awaitingShot` now carries the
  state from the release to the server's answer, cleared at the end of the shot, on a
  rejected shot, and on leaving the table. Measured at 60 Hz: the cue and the guideline
  disappear on the SAME sample as the power bar returning to zero, 0.0 ms after release.
- 2026-09-21: One `canAim()` decides whether any of the aiming visuals are drawn, rather than
  each of them testing its own conditions. They are one idea - this is your shot to take - and
  three copies of that test would eventually disagree. It is also where the Rules hook in at
  Roadmap 2.1: "is a shot running" becomes "is it my turn" in one place.
- 2026-09-21: The on-screen nudge arrows at the bottom of the screen are gone, at the
  designer's call. They were the only non-drag way to aim on phone and on PC, so this leaves
  CLAUDE.md's "every drag has a button alternative" unmet for aiming on those two: the gamepad
  keeps its D-pad nudge, and `Config.Input.NudgeDegrees` and the repeat timings stay because
  that path still uses them. If fine aiming turns out to need a button again, the cheapest
  restoration is keyboard arrow keys on PC; the phone would need something new.
- 2026-09-21: The status line is a developer readout, not part of the game, so it is off by
  default and `Config.Debug.StatusKey` (F3) brings it in and out. Its listener is separate
  from the test keys: it is a readout rather than something that changes the game, so it must
  work while a shot is running and whether or not `TestKeysEnabled` is on. Visibility is two
  flags - at a table, and asked for - so leaving a table does not forget that it was wanted.
  Keyboard only, deliberately: it is a tool, not a feature that needs a phone path.
- 2026-09-21: Every turn starts from the same framing. `Camera.View.ZoomDefault` is 0.625, the
  exact midpoint of the zoom range, which is also the halfway point in SCROLL NOTCHES because
  the distance is interpolated geometrically - so it is the middle however it is measured. At
  the 9 ft table that is 5.3 studs from the cue ball at a 35 degree pitch, against 10.1 studs
  at 50 degrees fitted and 2.2 studs at 18 degrees closest. The camera resets to it at the end
  of every shot rather than returning to whatever the player pinched to, so a zoom made for
  one shot does not quietly become the setting for the match.
- 2026-09-21: The camera no longer leaves at the strike. It holds the framing the shot was
  taken from for `Shot.HoldSeconds` (0.5, down from 1.0, which was a wait) while the cue ball
  travels - long enough to see it leave and reach the first object ball on most shots, short
  enough not to feel like a pause - then pulls out to the
  whole table over `Shot.PullOutSeconds`, smoothstepped so the move has no corners at either
  end, with the existing exponential easing on top. It was 1.2s against a 0.35s easing, which
  took 1.6s to get 95% of the way out and read as slow; 0.7 against 0.22 does it in 0.93s.
  Both numbers came down together, because cutting only one leaves the other setting the pace.
  The eased shape survives the cut - measured at 7%, 22%, 40%, 58%, 74%, 89%, 96% - so it
  still starts and lands softly with the speed in the middle. Leaving immediately threw the view
  away at the exact moment worth watching from where it was aimed, and read as a lurch.
  Measured in Studio against the table centre, which is fixed - measuring against the cue ball
  is meaningless mid-shot, because the ball moves while the camera's anchor is frozen: strike
  at 6.57s, camera first moves at 7.77s (a 1.20s hold), 95% of the way out by 9.30s (a 1.6s
  move), and settled back at zoom 0.625 once the balls stopped.
