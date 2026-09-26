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
- 2026-09-19: Imported Blender table model replaces the parts-built table.
- 2026-09-20: Working name Crazy 8 Ball. Currency is "money". No loser finisher effect.
- 2026-09-20: Next milestone is twelve server-owned tables (Roadmap 1.5), then spin, sound and
  rules. The server move is needed anyway.
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
- 2026-09-20: Spectators sitting on chairs get free look only; table cameras wait for
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
  the owning client. Body posing for watchers is deferred to Roadmap 2.3. (Superseded
  2026-09-24: every client now poses the shooter's body itself.)
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
  ball, so the body slid around the cloth chasing it for the length of the shot. (Superseded
  2026-09-24: the shooter now idles on the shot spot while the balls move.)
- 2026-09-20: Past about 8 studs of reach the shooter fades out entirely. A cue ball against
  a cushion with the shot going into it is nearly a table length from anywhere a person could
  stand, and no stance reads as a person from a camera on the far side; fading beats
  contorting. (Superseded 2026-09-24: the rake and the cue extension reach it instead.)
- 2026-09-21: Testing happens on a plain baseplate with a few tables until there is a map.
  The pads, the renderer pool and the server authority are unchanged.
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
  It is withheld when the pocketed ball is the cue ball: a scratch is not a reward.
  Its pitch CLIMBS WITH A RUN rather than wandering. Random jitter was tried first and was the
  wrong idea twice over: it made every pocket differ without any of them meaning anything, and
  a tonal sting that wanders just sounds out of tune. Now the first ball of a run is the plain
  sound and each consecutive ball is a semitone higher, capped at six (a tritone), so the
  pitch is information - it tells you how deep the run is. This is the GDD's streak idea
  arriving in audio before the Rules that will own it.
  A run ends when a shot pockets nothing, which is read at the NEXT cue strike rather than at
  the end of the shot: a strike is the one event guaranteed to arrive, and it arrives before
  anything the new shot can add. A scratch ends it immediately, on the spot.
  The rungs are a MAJOR SCALE - 0, 2, 4, 5, 7, 9, 11, 12 semitones, C D E F G A B C - which is
  why they are held as a list rather than as a step size. It took three goes to get there and
  the two wrong ones are worth keeping:
  A flat semitone per ball was wrong twice over. It is not a scale, and neighbouring rungs a
  minor second apart GRIND when two balls drop close enough to overlap, which they often do.
  A major triad fixed the grinding - every pair of its rungs is a third, fourth, fifth, sixth
  or octave - but was wrong the other way: thirds are LEAPS, so it outlined an arpeggio rather
  than walking a scale, and the designer heard that immediately.
  The cost of a real scale is that two of its seven steps are semitones, E-F and B-C. A run
  deep enough to reach them AND two balls overlapping on exactly that pair is the one case
  that can still grind; rare enough to be worth the scale. The major pentatonic
  { 0, 2, 4, 7, 9, 12 } is the same walk with those two steps removed if it ever is not.
  `BaseSemitones` (-2) transposes the whole ladder, because the recording is not one note: it
  starts on a D and rises a fourth to a G inside itself, so played untouched a run began on D.
  Dropping it a whole tone puts the first ball of a run on C, which is where the scale wants
  to start, and buys headroom as well - the top rung now lands 10 semitones above the
  recording rather than 12.
  Measured through the real event path: a run starts on C and walks C D E F G A B C, with the
  whole tones and semitones falling exactly where a major scale puts them, the recording
  playing untouched at its native D on the second ball, and the octave held beyond that.
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
- 2026-09-21: A ball about to leave the screen ends the camera's hold at once, whichever
  comes first between that and `Shot.HoldSeconds`. Holding a framing that no longer contains
  the shot is the worst case the fixed timer had: a ball banking across the table can be out
  of view well inside half a second, and waiting then means staring at empty cloth while the
  shot happens somewhere off screen. `Shot.OffScreenMargin` (0.06) makes a ball count as gone
  once its CENTRE is within 6% of the screen edge, so the move starts a moment before it truly
  disappears - by the time the centre is at the edge, half the ball is already outside.
  The moment the pull-out starts is RECORDED (`pullOutStart`) rather than derived from
  HoldSeconds, because an early end would otherwise jump the eased curve part-way through
  instead of starting it.
  Pocketed balls are excluded: they are dropping down a hole at the edge of the view, so
  counting them would end the hold on every shot that sinks something, which is the one time
  the close framing is worth keeping.
  Verified in Studio by forcing the margin to 0.92 at runtime so any off-centre ball trips it:
  the hold fell to 0.33s against the 0.50s fallback, with the camera first moving 0.13s after
  the strike. At the real 0.06 the straight shots that could be driven never tripped it and the
  fallback governed, at 0.67 to 0.73s - which is the expected result, since the close view
  looks DOWN the aim line and balls mostly stay inside the cone. The rule earns its keep on
  the shots that throw a ball wide near the shooter's end, not on ordinary ones.
- 2026-09-21: The camera does not leave the close view at all for a shot too small to be worth
  it. `Shot.MinTravelTableLengths` (0.5): if the cue ball could not run half a table length
  even on an empty table, the camera stays exactly where the shot was taken from. A tap that
  moves the ball a few inches has nothing to show at the far end.
  The test is `Cue.rollOutDistance(speed)`, new and pure: the closed-form slide-then-roll
  distance, the same arithmetic Simulation integrates. Verified against the integrator to
  within 0.05 in once the RestSpeed snap is accounted for. It is a BOUND on every ball in the
  shot, because nothing leaves a collision faster than the ball that struck it arrived, so it
  can hold the camera still on a shot where little happens and never on one where something
  travels far.
  The power curve makes this a sharp line rather than a fussy one: 0.20 power runs 0.30
  lengths, 0.25 runs 0.48, 0.30 runs 0.81. Half a table length lands at about a quarter of the
  bar. Binary, not proportional, at the designer's call - the camera does one of two known
  things rather than a different framing on every shot.
  The speed comes from the SIMULATION at the first frame of the shot, not from the power this
  client sent, so it is right for an opponent's shot at the same table.
  `OffScreenMargin` still overrides it: a gently hit ball that reaches the screen edge pulls
  the camera out anyway, because wherever the shot has gone the camera has to follow.
  Verified in Studio: a 0.13-power tap moved the camera 0.00 studs across a 2.51s shot, and a
  full-power shot straight after pulled out 7.07 studs on a 0.65s hold and a 0.95s move.

- 2026-09-22: Physics realism A follows the supplied research: SlidingFriction 0.25 -> 0.20
  (Dr. Dave properties, range 0.15-0.4); RollingFriction 0.012 -> 0.010 (TP B.2,
  range 0.005-0.015); optional ClothPresets slow/medium/fast = 0.015/0.012/0.008.
  The default 0.010 remains independent of the preset table.
- 2026-09-22: Replace radius-dependent SpinFriction 0.044 with SideSpinDecel 10.9 rad/s^2
  (TP B.2 / pooltool via PHYSICS_RESEARCH, range 5-15). At either tested radius, +/-60 rad/s
  takes 1322 steps at 240 Hz to reach zero. Side spin alone no longer keeps a shot open;
  keep it during other balls' motion and clear it at whole-shot completion. Remove the unused
  RestSpin 0.6 cutoff. Horizontal spin and pocket tipping/falling still count as motion.
- 2026-09-22: BallRestitution 0.93 -> 0.95 (Dr. Dave / pooltool, range 0.92-0.98);
  CushionNoseBallFraction 0.625 -> 0.635 (WPA 0.635 +/- 0.01). The cushion resolver itself
  remains unchanged until physics C.
- 2026-09-22: RestSpeed 1.0 -> 0.25 in/s preserves the last slow creep independently of
  english; InstantHitSeconds 1e-5 -> 1e-7 s avoids treating rack-gap contacts at break speed
  as zero-time wedges. Both are numerical choices required by PHYSICS_REALISM_PROMPT A.
- 2026-09-22: Designer's answers for later physics milestones: one power bar reaching
  30 mph, no separate break control; Classic guideline shows the predicted launch direction
  including squirt; regulation 2.25 in physics balls with visual scaling for readability;
  fixed 4-degree elevation for now; physically identical collectible cues. These override
  conflicting alternatives in the research/prompt. D-F will implement them; A does not.

- 2026-09-22: Physics B uses the requested ball-friction speed table (in/s -> coefficient):
  0 -> 0.118, 20 -> 0.072, 40 -> 0.046, 80 -> 0.022, 120 -> 0.014, 200 -> 0.010.
  Linear interpolation and endpoint clamping avoid exp in replays. BallSlipEpsilon is
  1e-9 in/s as specified by the prompt; restitution remains 0.95.
- 2026-09-22: Correct B's incompatible equations/tests using
  [TP A.14](https://drdavepoolinfo.com/technical_proofs/new/TP_A-14.pdf) and
  [pooltool's 2D contact resolver](https://raw.githubusercontent.com/ekiefl/pooltool/main/pooltool/physics/resolve/ball_ball/frictional_inelastic/__init__.py):
  retain the full tangential contact slip and angular impulse, then discard vertical
  translation. Dropping vertical slip would prevent the requested backspin transfer.
  With impulse opposing slip, cue velocity adds it and object velocity subtracts it;
  both angular velocities receive the same torque. The 1/7 impulse cap bounds head-on
  spin transfer by 5/14 and the 20,000-pair test verifies energy never increases.
- 2026-09-22: The prompt's half-ball stun at 40 in/s has 20 in/s contact slip. Its table's
  coefficient 0.072 gives 25.88181 degrees exit (4.11819 degrees throw); the quoted
  26.57-degree exit assumes fixed friction 0.06 (26.56637 exactly to the shown precision).
  Preserve the specified table and test both cases with their appropriate coefficients.
  The prompt/research are corrected rather than tuning the model to contradictory targets.
- 2026-09-22: Preserve the existing three-inch strong follow/draw assertions by moving
  their cue-ball setup from 10 to 6 inches behind the object: with ball-to-ball spin transfer,
  the old setup loses too much backspin before/during contact. Measured separation from stun
  is 4.484608 in for follow and 3.716758 in for draw. No production tuning changed for this.
- 2026-09-22: Designer requested moving on from A's remaining device checks. Keep phone and
  controller acceptance open while implementing B; no roadmap acceptance box is claimed done.

- 2026-09-22: Physics C ports the corrected
  [pooltool Han implementation](https://raw.githubusercontent.com/ekiefl/pooltool/main/pooltool/physics/resolve/ball_cushion/han_2005/model.py),
  checked against its [derivation](https://ekiefl.github.io/2020/04/24/pooltool-theory/#3-han-2005).
  The tilted normal passes through the centre and has zero net torque; both contact tangents
  participate in the stick/slip test. Use slip/3.5 capped by mu times normal impulse, retain
  full angular changes and discard vertical translation. Keep incoming normal event speed.
  Restitution/friction are resolver arguments so later abilities can supply material overrides.
- 2026-09-22: C's requested restitution table is 0.9 at 20 in/s normal approach to 0.6 at
  300 in/s, linearly interpolated and clamped. RailRestitution 0.85 is the empty-table
  fallback; RailFriction remains 0.2. These are prompt calibration values within the research
  range, not a measured curve for our imported table. With the 0.635D nose, rolling
  100 in/s at 45 degrees exits at 43.863807 degrees and 76.397643 in/s. Specify 300 in/s
  for the prompt's perpendicular stun half-speed test: it retains 50.418857%, versus
  70.285286% at 100 in/s. The prompt/research now name the speed and correct the torque claim.
  [Dr. Dave's cushion-efficiency discussion](https://drdavepoolinfo.com/faq/table/cushion-efficiency/)
  explains why rebound efficiency varies with angle, speed and spin.
- 2026-09-22: Under the default table/cone all centres exit outward. For an extreme future
  low-restitution/high-friction override that projects inward, reflect only the residual
  inward component. This enforces the planar rail constraint without increasing its energy;
  an e=0, mu=1 heavy-draw regression exercises this guard. 4,000 seeded contacts check
  energy, planar motion and outward exit, with separate rotation/mirror tests.
- 2026-09-22: CornerShelfBallFraction = 1.5/2.25 implements C's 1.5 in regulation target,
  scaled with ball diameter (research WPA range 1-2.25 in). Current shelf is 1.733333 in.
  Shift corner circles diagonally and derive corner-facing length to their near rim instead
  of leaving the old 1.6 in facing and a gap behind it. Side facings retain 1.6 in. Move the
  escape safety bound beyond the shifted extent; genuine rim crossings still drive drops.
- 2026-09-22: Verify the full bank path, not a universal immediate-angle rule: from the same
  position 8 in before the foot rail at 45 degrees, centre strikes of 40 and 160 in/s reach
  the rail rolling and sliding respectively. After post-cushion cloth slip ends, their angles
  from the normal are 57.216 and 40.877 degrees (gentle long, hard short). The immediate
  impact angles have the opposite ordering, so preserve the measured scope in acceptance.
- 2026-09-22: C inspection found the live imported PoolTableModel bypasses TableBuilder's
  generated geometry. Its visible pockets do not automatically follow the new shelf. The
  designer chose to keep the current table for now. Retain the new physics shelf and defer
  the imported pocket mesh update; no asset or appearance switch.
- 2026-09-22: Designer requested D-F in one run. D uses the inelastic impact equation from
  [TP A.30](https://drdavepoolinfo.com/technical_proofs/new/TP_A-30.pdf), squirt from
  [TP A.31](https://drdavepoolinfo.com/technical_proofs/new/TP_A-31.pdf), and elevated lever
  arms from [pooltool](https://raw.githubusercontent.com/ekiefl/pooltool/main/pooltool/physics/resolve/stick_ball/instantaneous_point/__init__.py).
  Cue mass 19 oz, existing ball mass 6 oz, tip COR 0.73, endmass ratio 25, default/max
  elevation 4 degrees. Internal level-cue tests may use 0; player controls remain fixed at 4.
  Remove artificial SpinFactor; the solid-sphere torque coefficient is physical. Every cue
  style uses the same parameters. Derive stick limits from centre targets 15/528 in/s
  (maximum stick speed 406.981692 in/s), preserving one 30 mph bar and PowerCurve 2.6.
- 2026-09-22: D corrects approximate prompt benchmarks rather than altering the equations:
  V=100 centre gives 129.735566 in/s at 4 degrees; maximum side gives 79.541985 (0.613109x).
  Squirt is 2.223977 degrees. At 20 in/s maximum follow runs 54.909259 in at 4 degrees or
  59.849110 level on friction 0.010. The straight aim aid includes launch squirt; later
  swerve can change a distant contact. Camera rollout uses initial spin, exact for straight
  non-reversing travel and a conservative bound for curved/reversing sliding paths.
- 2026-09-22: Keep strong draw/follow assertions after realistic offset speed loss by using
  a firm 0.4 stroke instead of 0.25. Existing three-inch thresholds remain; measured
  separations are 18.8771 in for follow and 5.81437 in for draw. Level-cue symmetry and C's
  bank measurements explicitly retain level launch conditions instead of assuming a
  4-degree centre hit imparts zero angular velocity.
- 2026-09-22: E spin UI uses 0.05 ball-radius arrow increments, 0.15 gamepad spin dead zone,
  and 0.55 radii/s adjustment with L1 + right stick. Y centers; L1 release keeps the choice.
  Selector buttons are 44 px, toggle 56 px, panel 280 px wide, ball target up to 120 px;
  the target shrinks on short viewports while buttons retain their touch size. Modal edits
  cancel pending pulls and block aiming/zoom/shooting until closed. Reset spin after shots.
- 2026-09-22: E keeps elevation fixed at 4 degrees on the server, rejects NaN/infinity and
  malformed inputs, and clamps finite spin to the 0.5-radius disc. Move existing six-decimal
  seed precision into Config.Physics.SeedPlaces and use ShotInput.quantiseSeed in the actual
  server and tests. Classic object-ball line and tangent cue stub remain geometric; a
  post-contact follow/draw curve is deferred as allowed by the prompt.
- 2026-09-22: Add the per-shot material replay hook with a development SuperBounce row
  (rail restitution 1, friction 0; valid coefficient range 0-1). This is unbalanced test data,
  not an available player ability. The live server authorizes none until ownership/cooldowns
  exist. Reject client overrides; copy validated materials into simulation/replay and clear
  them on completion and the next strike. Three requested spin vectors and the material
  replay match exactly in same-machine regression tests; physical two-client proof remains.
- 2026-09-22: F applies the designer's regulation-size choice: RadiusInches 1.3 -> 1.125
  (WPA 2.25 in diameter), RenderScale 1.08 for readability (visual tuning range 1-1.15).
  Derived render radius 1.215 in is used only for mesh size/height, cue/camera placement and
  ghost-ring art. Collision corridor and all physics keep the regulation radius. Derived
  nose is 1.42875 in, corner shelf 1.5 in, corner/side mouths 4.5/4.95 in. Keep the imported
  table unchanged as explicitly requested; its pocket/nose geometry mismatch is deferred.
- 2026-09-22: Rack.DefaultSeed=1 and JitterInches=0.001 add ordered xorshift32 offsets to
  fourteen balls; cue and apex stay exactly on their spots. Each axis is capped at gap/4,
  preserving non-overlap with the existing 0.005 in gap. Seed zero maps to one. Server
  initial seed is DefaultSeed + table id; Studio reracks advance it. Send seed and exact
  starting positions together, and queue a new rack if a client still replays the previous
  shot. Replace the old local-only B-key reset with a Studio-only, seat-checked server request.
- 2026-09-22: Named scenario fixtures (follow, draw, side cut) freeze explicit layouts, shots
  and final positions with 0.02 in tolerances. These are synthetic regression baselines;
  future measured real shots can be added through the same harness without new test code.
- 2026-09-22: Review the old every-break >=13 balls moved threshold after regulation radius
  and rack jitter. Across 32 consecutive seeds x three existing angles, 96 breaks moved
  11-15 balls beyond one diameter (mean 13.395833), made 23-33 contacts, and used no emergency
  stops or duration caps. Preserve all collision safety assertions and >=20 contacts per
  stroke. Require >=10 moved each and ensemble mean >=13, instead of choosing a lucky seed
  or changing physics to satisfy a universal count that realistic rack variation invalidates.
- 2026-09-22: Designer requested a simpler spin selector: 80 px left-middle ball toggle,
  10% backdrop dimming, no title/hint/box/ring/arrows, and only Center/Done. Outside clicks
  close on release and retain spin. The whole white disc maps to the existing 0.5R legal
  strike range; physics stays unchanged. This explicitly supersedes the drag-button
  alternative for spin. Fixed duplicate top-bar inset subtraction in pointer mapping.
- 2026-09-22: Designer requested a larger red spin marker. Use 22% of the white ball's
  diameter (39.6 px at 180 px, formerly 12 px), also proportional on the toggle and small
  layouts. Preserve the full existing spin range and keep the entire marker inside the ball.
- 2026-09-22: Designer reduced the large selector's red dot to match the left toggle exactly.
  Both now use DotSizePx 17.6, replacing proportional sizing; the full spin range is retained.
  Studio confirms equal rendered sizes, with lint and all 132 tests passing.
- 2026-09-22: Designer preferred the earlier large selector marker, reduced only slightly:
  use 36 px (down from 39.6 px), with the left toggle retaining 17.6 px. Studio visual check,
  lint and all 132 tests pass.

## 2026-09-22 — Shared multiplayer update

Designer approved MULTIPLAYER_SPEC.md and said begin. Three dedicated baseplate tables
share one configurable authority. Individual team slots, longest-waiting host, rotation
after every shot, first queued teammate breaking, open table after break, chronological
legal group assignment and explicit break/8-ball outcomes are agreed. Normal aim remains
orbit; setup uses top-down. Team surrender is unanimous (10 s, 30 s cooldown); disconnects
continue shorthanded and empty teams lose. Resets keep the seat. Timers are server deadlines,
including 2 s intro, 10 s setup phases and 15 s shooting. No rewards or persisted wins.

Implementation detail: if the last teammate disconnects during an accepted shot, finish
its replay/settling first, then award the empty-team forfeit. Runtime QA uses Studio-only
server fixtures and never creates playable bots. Multiplayer starts at whole-table zoom
for HUD/pocket clearance; manual orbit/down-cue zoom is preserved.

Final responsive pass: fine controls replace placement instructions while expanded and
include Lock/Close buttons. Camera framing reserves their actual height. Active-match host
reassignment preserves the original heads-team ownership. The Studio-only finishing-rack
fixtures verify all modes, but full human racks and physical-device acceptance remain open.

2026-09-22: Designer found the multiplayer top panels much too large. Replace the
150 px full-width header with 56 px content-sized strips: portraits beside stable ball
rows, compact central status/clock/Leave. Place at y=4 beside Roblox menu when width
permits, otherwise immediately below its safe inset. Preserve ball diameter and all
teammates; wrap ball rows on narrow screens. This supersedes the original large header.

## 2026-09-22 — Playtest fixes: home view, 3D placement, instant bonus

Designer playtest feedback. Decisions made with the designer:
- The pre-multiplayer middle framing (`Config.Camera.View.ZoomDefault`) is named the
  **home view**. Every turn starts there, and the shot pull-out and return work again.
  `Multiplayer.InitialZoom` (whole table) is removed. The HUD-clear fit now blends in
  from the home view to full zoom-out, so the pull-out has no pop.
- The only top-down view is the 8-ball pocket call. The coin flip is a HUD overlay; no
  camera is taken for it. Break placement and ball in hand happen in the 3D view.
- Placement has no Lock button. Drag (or use arrows or LT + stick) and shoot at any time;
  at 10 s the ball stays put. The ball is predicted locally, streamed unreliably with
  the aim, and committed reliably on release. Rate limits are per channel.
- Ball in hand plus the 8: call the pocket first (top-down), then place in the home view.
- Break pockets keep the table open with no bonus (unchanged). The first ball that
  assigns groups plays its owners' bonus in the same frame as the drop, and the HUD
  reveals both teams' groups at that instant. The server decides everything at shot
  acceptance.
- Pocketed HUD balls get a red X across the whole ball.
This supersedes "setup uses top-down" and "Multiplayer starts at whole-table zoom" above.

## 2026-09-22 — Soft simultaneous contact for touching balls

Designer approved. The break was weak and bunched because every ball-ball contact was an
instantaneous pairwise impulse, so a rack with 0.005 in gaps behaved like two Newton's
cradles (about 72% of the energy to the 7 and 13, nothing pocketed on eleven seeds).
- A ball-ball contact where either ball is within `Physics.ClusterGapInches` (0.02 in) of a
  third ball is resolved as a group of Hertz spheres (`Physics/Cluster.luau`) for as long as
  any of them touch. Two balls alone keep the exact pairwise model, bit for bit.
- Contact time 200 us at 100 in/s (stiff end of real phenolic balls), damping calibrated so
  an isolated pair restitutes at `BallRestitution`, same contact friction as pairwise.
- A cluster that could reach a cushion or pocket inside the phase stays pairwise.
- One `ballHit` per touching pair per phase, timed at first touch with the fastest closing
  speed; the triggering pair reports exactly as before, so first contact is unchanged.
- Measured over 200 seeded full-power breaks: 0.02 -> 0.95 balls pocketed, 6.9 -> 12.2
  distinct object balls to a rail, 11.5 -> 3.2 left in the foot quarter. A square stun
  break's cue ball now comes back off the tight rack at about 13% of its speed.

2026-09-22: Designer changes after playtest: break and ball-in-hand turns open two wheel
notches wider than the home view; placement is 15 s (was 10), aiming 20 s (was 15), the
8-ball call stays 10 s. An invisible wall around each table stops players touching or
jumping on it. Queue slots get a light column, sparkles, a rising scan frame, a glow flare
and a join sound (Creator Store "Beacon SFX" 131677760492710, swappable in Config).

2026-09-23: The break may hit any ball first; it is legal when an object ball drops or four
different object balls reach a rail (standard 8-ball). The apex-first requirement is gone,
so the aim guide never shows an invalid target on the break. Queue-slot effects show only
while the table is still filling (Waiting/Countdown) and fade once the match starts.

2026-09-23: The 8-ball pocket call is final once clicked (or chosen on timeout); it can no
longer be changed while placing or aiming. Only the called pocket stays marked.

2026-09-23: Guideline object/cue lines scale with the cut angle (object cos, cue sin, as the
share of speed each ball carries), like GamePigeon. Longest line 16 in; cushion reflections
keep a fixed line.

2026-09-23: The post-shot zoom-out now needs a shot that could roll 1.5 table lengths (about
35% power on a centre hit), up from 0.5 (about 25%). A ball heading off screen still pulls
the camera out at any power.

## 2026-09-23 — First release: cue skins only

Designer decision: no table skins at first release. Collectibles at release are cue skins
(each with its own trail and pocket effect) plus abilities. Every match uses the standard
table model. Table skins, the table loot box and limited Founder's/Beta/VIP tables move to
Phase 9 (after release) and the GDD's parked list. The catalog's item `type` field keeps
room for tables later. Roadmap 5.3 removed; 7.2, 7.3, trading, GDD section 12, ARCHITECTURE
data model and CLAUDE.md updated to match. No code implemented table skins, so none changed.

2026-09-23: TEMPORARY difficulty trial: Config.Guideline.Enabled = false hides the aim
corridor, contact ring, object/cue lines and the invalid-target hint; only the cue stick
remains. Set it back to true to restore the Classic guideline.

2026-09-23: Difficulty trial over: guideline restored (Config.Guideline.Enabled = true).

2026-09-23: Side spin no longer bends the aim line or the shot. Squirt (launch deflection) and
swerve (from the 4-degree cue's tilted spin axis) are off behind Config.Cue.SideSpinBendsPath =
false; the cue ball leaves exactly along the aim and runs straight to first contact, while side
spin still changes cushion rebounds, throw and spin transfer. Draw and follow are unchanged.
Swerve with a curved guideline is parked in GDD section 18.

2026-09-23: Solo mode. A player alone at any table (1v1, 2v2 or 3v3) can press Play Solo:
no countdown or coin, nobody can join, no clock. Normal break and fouls (ball in hand to
yourself); the first legally pocketed group is cleared first, then the other, then the called
8. The 8 early, on a foul or in the wrong pocket now LOSES (the GDD's "re-racks" is replaced);
Leave → Yes ends the game with no winner. The engine keeps the solo player's current group in
`groups` and the other group on the empty team, so every existing rule check is reused.

2026-09-23: Ball highlights back to the original subtle green outline, with no greying of the
other group. The strong style (vivid outline plus grey wash) stays behind
Config.Multiplayer.Style.StrongBallHighlights = false, set aside for the first-time
playthrough and tutorial (GDD section 14).

2026-09-23: Every foul shows a card under the top bar for 8 s (was 5): FOUL (or FOUL BY name) and one
plain "you must" rule for the foul made (e.g. On the break you must pocket a ball or make 4
balls hit the rails). Written for players new to 8-ball; wording in Strings.Match.FoulExplain.

2026-09-23: The rail-after-contact rule (after the first hit a ball must drop or touch a
rail) applies only in ranked; casual/public tables skip it, so a soft legal tap just ends the
turn. Config.Multiplayer.RailAfterContact = {Casual = false, Ranked = true}; a table's
`ranked` flag picks it (all tables are casual until ranked exists). The break rule is
unchanged. The wrong-ball foul now reads "You must hit one of your own balls first.",
avoiding "color" (a solid and a stripe share each color).

2026-09-23: Guideline object/cue lines shortened from 16 to 11 in at their longest (still
scaled by the cut) to make aiming a little harder.

2026-09-23: Guideline object/cue lines shortened again, 11 to 8 in (half the original 16).

2026-09-23: Pocketed balls stay visible: the drawn ball stops 1.6 in below the cloth (still
showing in the hole) while the physics drop finishes, holds 0.17 s (was 0.5, then 0.25), then rolls 2.5 in outward
while sinking and fading over 0.3 s (was 0.9, then 0.45), like running into the gutter. Presentation only; the
physics and replay are unchanged (Config.Effects.Pocket*).

2026-09-23: New pocket VFX, a gust of wind up out of the pocket in the ball's colour: 3
ribbons corkscrewing up (5 for the 8), stretched streaks shooting up, a shockwave ring on the
cloth, sparkles and a coloured flash; the 8 is 1.6x bigger. Still cue-style data
(Config.Effects.Styles.Default.Pocket) so rare cues can bring their own.

2026-09-24: Pocket drop reworked again: no resting stop or hold. The ball drops with the
physics' real gravity, then keeps accelerating down at the bottom, drifting outward and
fading out in 0.12 s (Config.Effects.PocketFadeSeconds). Rim to gone takes about 0.2 s.

2026-09-24: The pocket VFX plays only for a good pocket for the shooter: never the white,
never the other side's balls, the 8 only once it was theirs to take; any object ball on an
open table; every object ball in solo (the 8 once all fourteen are down).

2026-09-24: The shooter's pose is modelled on the Steam game "9 Ball Roulette". Avatars stay
normal Roblox size, R15 and R6 both supported. So a ball realistically out of reach brings
out a bridge (rake), and past the rake an automatic cue extension. The cue is about 7 studs
(0.09 tip, 0.2 butt). It tilts up to 45 degrees to clear the rail and balls behind the cue
ball; that tilt is visual only and never reaches the physics (fixed 4 degrees). The bridge is
a Blender mesh the designer imports (assets/bridge), with a parts stand-in until then.

2026-09-24: The wind-up is public: the power pull rides the aim stream in 1/50 steps, so
opponents can read roughly how hard a shot will be. It is cosmetic; the shot's power still
comes only from ShotFired.

2026-09-24: After release the shooter idles in the normal Roblox idle on the spot they shot
from, facing the table centre, and cannot move. Same shooter next: straight back to aiming.
Turn passes: released in place with the normal camera, no teleport. The shooter sees their
own body translucent; everyone else sees it fully visible and posed.

2026-09-24: The server places the shooter. It solves the same stance as the clients, holds
the root anchored there (following the aim at most 5 times a second) and, at shot
acceptance, on the shot spot facing the table centre, published as the root's ShotSpot
attribute. Each client writes the root to ShotSpot once after the stroke, so the owner hands
the body back exactly where the server holds it. A held shooter touches nothing (PoolShooter
collision group), so moving it never shoves a spectator.

2026-09-24: Lead calls made during the build:
- The rake gets the same automatic extension as the cue when its shaft cannot reach the hand.
- A steep cue whose grip is out of reach stands the torso up, the "jacked-up" stance.
- A rake whose head cannot stand on the cloth (a ball frozen on a cushion with the cue along
  it) is hidden, and the off hand bridges instead.
- Both extensions cap at 14 studs.

2026-09-24: R15 characters in this place use the Avatar Joint Upgrade (AnimationConstraint
plus BallSocketConstraint, no Motor6D); R6 still uses Motor6D. Posing handles both.
Config.Stance.DefaultBody is the measured default R15 (root 3.19, shoulders 4.04, arm reach
1.93 studs).

2026-09-24: The table is remade. An audit found the current model is the Blender script
build (assets/table/PoolTable.py), not a Meshy mesh: 19,220 triangles in 7 MeshParts, 71% of
them in the pocket cut-outs. Its cloth is one 1024 bake at 36.5 px per stud with no weave.
Its pockets and cushion nose are still sized for the old 2.6 in ball, so the drawn mouths
are 15% wider than the physics (5.2/5.72 in against 4.5/4.95 in). The new model is generated
from the physics geometry and keeps the regulation pro cut the designer has been playing
since 2026-09-22 (corners 2.0 and sides 2.2 ball widths, 1.5 in corner shelf, nose 0.635 of
a ball). Table size and cloth height stay (16 x 8 studs, cloth at 2.9 studs); the poses,
cue, camera and pads are tuned to them. The rails widen to the Pro-Am's 7 in, rounded on top.

2026-09-24: Two looks share the one table model. Blue: photo-16 cloth (about #01A9F7) with
satin black wood showing faint grain, like Diamond's Black PRC. Green: the reference photo's
yellow-green hue at real-cloth brightness (the photo is overexposed and its green channel is
clipped), with red-brown wood; the photo's "oak" samples at a hue of about 8 degrees, closer
to cherry. Chrome caps on all six pockets on both looks, built as a separate part so the
fully detailed corners underneath can ship without them. Pro-Am details: two-piece tapered
legs with bolts, corner blocks, rail seams at the side pockets, a blank logo plate on the
foot end. No ball-return window, and no Diamond name or logo (trademark). The cloth is lightly
played. Both looks are built now; which tables use which is decided later.

2026-09-24: Later table skins are retextures of this one model. This replaces 2026-09-20
("each a full 3D table model"). Textures: masters at 4096, uploads at 2048 for cloth and
wood and 1024 for small parts. The cloth is a repeating near-white tile tinted per look
through SurfaceAppearance.Color, so every cloth colour shares one image set. Roblox has
rendered up to 4K since 2026-01-30 and transcodes 8K uploads down to 4K; low-end Android gets
no 4K. A single unique cloth image cannot reach the close aim view's density even at 4K
(about 230 px per stud against about 420 to 560 needed); a 2048 tile every 3 studs gives
about 680. This replaces the "eight 1024 maps" budget with about 10 to 12 images for all
looks. Blender runs headless from Claude Code; the Blender MCP is configured only for Codex.

2026-09-24: Table de-risk tests (STUDIO_NOTES, "SurfaceAppearance facts") changed four details
of the remake:
- UVs outside 0..1 repeat, so the cloth uses continuous UVs over a repeating tile, with no
  cuts in the mesh.
- Studio uploads render at 1024 (measured with a 1-pixel checker; 2048 and 4096 uploads show a
  resampling beat pattern). So every table map is authored at 4096 and uploaded at 1024. That
  is also the most low-end phones get, so every device sees the full design.
  - The cloth tile repeats every 1.5 studs, which gives 683 px per stud, the same density the
    2048-every-3-studs plan had.
  - The wood is split into two meshes: Rails, with its own 1024 sheet at about 400 px per stud
    and the grain along each rail; and Body (skirt, cabinet, corner blocks and legs) at about
    200 px per stud.
  - About 16 images at 1024 (roughly 22 MB compressed) replace "10 to 12 images, cloth and
    wood at 2048". Revisit 2048 only if a Creator Dashboard upload is shown to render above 1K.
- Vertex colours do not show under a SurfaceAppearance. The cloth's shading near the cushions
  and pockets goes in the transparent Marks overlay (alpha 0.2 and up where possible, because
  fainter alpha dithers). The wood's shading is painted into its sheets.
- The chrome caps use metalness 1 and roughness about 0.15, which reads as polished chrome
  under this place's Sky.
Not tested: whether different cloth tints per look break instancing (low priority; the
fallback is one cloth colour map per look).

2026-09-24: Table remake build calls:
- The new template is named `PoolTable`, so the old `PoolTableModel` stays untouched as the
  rollback until sign-off.
- `Multiplayer.Barrier.MarginStuds` goes from 0.6 to 0.36, so the wider 7 in rail leaves the
  invisible wall where it was.
- The chrome caps' crown is 2.28 in (`PocketCastingTopInches`). The cue-clearance tests allow
  up to 2.351.
- The caps stop on the wood: at least 0.25 in behind the cushion backs at the corners and
  0.9 in at the sides (the designer asked that they not touch the cloth).
- The faint break streak and rack patch are off. Roblox dithers alpha under about 0.15, so
  they drew as a dotted line and a checkered triangle. The foot-spot sticker, the chalk and
  the shading at the cushions and rims stay.
- Table 2 shows the green look as a temporary side-by-side showcase until the designer decides
  which tables use which look.

2026-09-24: Jump shots (designer's priority). Decisions:
- The control is a cue-angle slider inside the spin panel, 4-60 degrees in whole steps, reset
  to 4 after each shot like spin. Tap or drag the track; no arrow buttons, matching the spin
  panel's designer-set style (tapping the track is the button alternative to dragging).
  Arrow keys step it; on gamepad L1 + left stick (D-pad up is reserved by Roblox's menus in
  Studio's input tool, so it is only a bonus).
- Off-table follows standard rules: foul with ball in hand; object balls respotted at the foot
  spot; the 8 off the table loses, or on the break is respotted.
- Rarity for flat shots (designer: rare, cue ball only): superseded the same day by the
  realism review below.
- Raising the cue past 4 degrees keeps the spin disc's meaning (the 4-degree draw bias is
  kept) instead of pooltool's table-frame lever, which would turn a centre-hit jump into a
  screw-back. Every shot at 4 degrees is bit-identical to before.
- A low hop into a rack still uses soft contact (the flyer is laid flat for the phase and
  kicked up after, energy-bounded), so a full-power break still spreads the rack.

2026-09-24: Jump shots, after the independent review (a regression check, a 32,000-shot fuzz and
a realism review against Dr. Dave's TP B.10):
- Jumping a ball over another is realistic, and the model follows TP B.10. Slate
  restitution is 0.6 with no cloth loss, which matches TP B.10's launch angles and clearing
  speeds. A raised cue's top stroke drops to 12 mph (Cue.JumpMaxStickSpeed), reached by
  15 degrees, because nobody swings a raised cue at break speed. A full-power jump now rises
  about 9, 18 and 26 in at 30, 45 and 60 degrees (it was 19, 41 and 62). At 45 degrees a ball
  clears a blocker from about 70% power. At 60 degrees, full power still flies off the table.
- Flat shots stay rare (designer): a near-level stroke gets FlatStrikeBounce 0.4 of the slate
  bounce, rising to all of it at 15 degrees. Rebounds under MinHopSpeed 8 in/s are swallowed.
  Only the top ~4% of the power bar hops, by about 0.1 in. Full power straight at a nearby
  ball pops the cue ball in about 8% of shots and sends it off in about 5% (90 shots).
- Fixed from the fuzz:
  - A ball rising past a cushion froze in mid-air.
  - A cushion launched a flying ball 4-11 ft up. A flying ball below the cushion top now
    rebounds like a ball on the cloth and keeps its own vertical speed.
  - A ball coming down onto a cushion top was teleported.
  - A high ball over a corner mouth was ruled off. Off the table is now judged from the real
    cushion faces and jaws (Simulation.goesOver).
  - A ball perched on another bounced until the shot timed out. It now slides off, and the
    energy for that comes from the contact's loss.
- A ball that flies off is shown landing on the floor and rolling for about a second before
  the foul card (designer). The server holds the foul for exactly that long.
- Deferred (would need the designer): a steep hit above centre jamming instead of jumping,
  and a double hit at steep hard strokes.
- 2026-09-24: The old map model is deleted (package, builder, its test and its Config).
  The client's room module is renamed `Hub`, and `Config.Hub.Tables` is a flat baseplate grid
  until a hub map replaces it.

2026-09-24: Clean cloth (designer): the foot-spot dot and the break smudge are gone. The whole
Marks overlay mesh is removed from every table (`Config.TableModel.Marks = false`, like the
caps switch), leaving the plain tiled cloth; no new images needed.
- 2026-09-25: Regular lobby tables are all green, pro lobby tables all blue
  (`Config.TableModel.DefaultLook = "Green"`, closing the open question in GDD section 16).
- 2026-09-25: The designer signed off the remade table and jump shots after playing them by
  hand (feel, pockets, jump heights). Both merged into main; the tuning numbers stay as tuned.
- 2026-09-25: Sixteen server-owned tables, one per Config.Hub.Tables row, each seating its own
  team size (the row's teamSize; the old one-table-per-mode list is gone).
  - A table's match fence is lopsided: it reaches past the pads at the head and stops 13 studs
    past the centre at the foot, so tables can stand foot to foot.
- 2026-09-25: The rake (mechanical bridge) and the automatic cue extension are gone
  (designer). The cue is always its own length and the table keeps its size: only the
  shooter's pose and position change. This supersedes the 2026-09-24 lines on the rake, its
  extension, the cue extension and the rake that hides by a cushion.
  - The stance is a search: supports (floor, hips up on the rail edge, kneeling on the
    table), each with every side (Config.Stance.Sides), at the least lean that reaches.
    The body is not tied to the cue line, so a ball along a side rail is played from that
    rail.
  - Why the body climbs at all: a Roblox avatar's hip line (2.59 studs) is below this
    table's rail top (3.23), so a body standing on the floor cannot lean far over it. The
    rake used to cover 77% of shots; a larger avatar or a smaller table would not have
    removed the need, and both were ruled out.
  - Measured over an even grid of shots with the default R15: 48% from the floor, 37% on
    the rail, 15% kneeling, all reached. A stance costs about 0.2 ms in Lune.
  - A steep jump cue chokes up further (Stance.SteepGripMinFromTipFraction); a steep cue
    that no bridge on the surface reaches raises the bridge hand under it.
  - After the shot the shooter stands on the floor clear of the barrier, facing the table.
- 2026-09-25 (later): The shooter's pose after the designer's Studio look.
  - Both feet stay planted on the floor in every standing pose: no floating feet, no lifted
    back leg, no tiptoe. The hips up on the rail are gone: an avatar's legs (hip 2.2 studs)
    cannot reach the floor from the rail top (3.23). In their place the body stretches over
    the rail with its belly on the edge (the hips stay outside it, as the table's apron is
    flush with the edge). What that does not reach is taken kneeling on the table, which the
    designer accepts as a bit of humour: 48% floor, 4% stretching, 48% kneeling for the
    default R15 (up from 15% kneeling). Kneeling up on the rail top is the last resort.
  - The head is the avatar's own (AvatarPose.measureBody: neck, head size), placed as the
    pose looks at the cue ball, and stays Stance.Clearance.HeadGapStuds clear of anything
    under any part of it. Head only: big hats and costumes may dip into the table
    (designer). The natural lean is 45 degrees, so the body stands higher.
  - The grip arm reaches back along the cue to hold it near the butt (not beside the chest);
    a long wind-up slides the cue through the hand once the arm is straight. The bridge arm
    reaches out nearly straight toward the ball instead of a fixed 10 in from it.
  - The hips tip and twist only a little: blocky R15 hips turned away from the thighs show a
    gap.
  - Smaller and R6 bodies cannot reach about 2% of ordinary shots (a ball frozen to a
    cushion under a steep jump cue); they stand with the hands as near the cue as they get.
- 2026-09-25: The shooter may walk while the balls roll (designer). The server holds the root
  at the shot spot only for Multiplayer.Stance.HoldAfterShotSeconds (1.2 s, so the stroke plays
  out on every screen) and then lets it go (Engine.shooterHeld); the shooter's own client hands
  the body back as soon as its stroke has played. The shot camera keeps following the balls
  until they stop (designer's choice over the normal camera). Their next turn poses them again
  from wherever they walked. Supersedes the GDD's "unable to move" after the shot.
- 2026-09-25: The test hub map is removed (designer: it was a test, not the final map; they will
  come back to the map). Its code, package, brief and notes are gone; the hub map's look is
  Open again (GDD section 10). Back to a plain baseplate: sixteen 1v1 tables in a four by four
  grid (Config.Hub.Tables), the left two columns green cloth with wood and the right two blue
  cloth with black wood (Config.TableModel.LookByTable), the spawn in front of them.
- 2026-09-25 (later): One queue box per table replaces the per-seat pads and the dedicated
  1v1/2v2/3v3 tables (designer; decided in an interview).
  - Every table has one long box along a long side (Placement.queueBox), up to six players, so
    any table plays 1v1, 2v2 or 3v3. The tables moved from 20 to 26 studs apart to make room;
    the match fence takes in the box, and the shooter's walkway is now the same at both ends.
  - The first in is the host. Everyone in the box sees the queue menu; only the host can use
    it. The next in becomes host if the host leaves, and the settings stay; they reset to
    Classic and abilities on when the box empties and after every game. Leaving the box (or
    Leave) is instant, with no confirmation.
  - Teams: two players split by who came first (the host is team A). Four or six split by
    the half of the box they stand in (head half team A, foot half team B); the halves show
    only then, both grey until each holds half, then both green. Three or five cannot start.
  - No countdown: the host's Start goes straight to the coin flip, which stays. Alone, Start
    offers Play solo and Play against PC; PC says "Coming soon" until bots exist. The GDD's
    15-second automatic start against PC is dropped.
  - Difficulty is the host's, for the whole table (Config.Difficulty): Classic every line,
    Difficult the aim line and its ring only, Challenger no lines at all (it used to be a short
    stub). The group glow and the red X stay at every level.
  - Abilities on/off is in the menu now, on by default, and does nothing until abilities exist.
- 2026-09-25: UI style (designer, after the first reference): cartoony and bubbly, white
  panels, Fredoka One for all text, white text with a dark outline for now, money shown as a
  stack of green cash. Button colours are not decided yet. Recorded in `docs/UI_STYLE.md`.
- 2026-09-25: Rarities are common (grey), uncommon (green), rare (blue), epic (purple),
  legendary (gold), mythic (celestial prismatic), unique (pink, new) and VIP (rainbow);
  "ultra" is dropped. Their order and what VIP rarity means are still Open.
- 2026-09-25: The UI redo (designer interview), settling UI_STYLE's Open items for now:
  - Panels: a thick dark-ink outline, a soft drop shadow, a white-to-pale-blue fade and a faint
    pattern of tiny pool balls (about 8%).
  - Buttons: raised candy buttons (light top, darker lip, a squish when pressed) in traffic
    colours: green Start/Play/Yes, red Leave/Surrender, blue for choices and the house accent,
    yellow for special things. A dialog's leaving or surrendering button is red and the one
    that keeps playing blue. Gamepad selection is a thick gold outline. Colours may change.
  - Icons: glossy cartoon icons with a thick ink outline, drawn in code
    (`tools/gen_ui_art.py`) so they all match; any can be swapped for a better image by id.
  - Motion: things pop in with a small overshoot and pop out quickly; only your turn, the win
    card, a ready Start and a pocketed ball shine, bounce or breathe.
  - The foul popup has no panel: FOUL! and a few plain words on the rule, gone after 3 s (it
    was a card for 8 s).
  - Difficulty icons are aim-line pictures on a little table: many lines, one line, none.
  - The sign over a table shows only when you walk right up to that table (within 6 studs of
    its match area) and pops in; never while you are in a box or playing. The server stopped
    building sixteen always-on billboards.
  - Phones get a compact top bar (a 3v3 fits on one line) and an icon-only red Leave.
  - Ball numbers may go below the 16 px text floor (they are part of the ball), and long player
    names end in "..." rather than shrinking (names are data, not reading text).
- 2026-09-26: UI redo, second round (designer, after playing it):
  - Fine controls are removed on every platform; the rule "every drag has a button
    alternative" becomes "every control works by touch, mouse and gamepad" (CLAUDE.md, GDD
    section 5). The gamepad keeps its sticks, triggers and D-pad steps.
  - Small descriptive text is dark ink with no outline; titles, names and buttons keep white
    with a thick outline (the outline squeezed small letters together).
  - The PC GUI is about 80% of the first build's size.
  - On phones the top bar sits in Roblox's top row beside its buttons, which also stops the
    camera backing away from a tall stacked bar; the power bar starts higher with it.
  - The host menu on a phone is two columns side by side. Play against PC is listed before
    Play solo and has no SOON tag (bots come before release; it does nothing until then); the
    abilities note and the solo hint are gone.
  - Difficulty descriptions: "Easiest, shows aim line and ball path!", "Harder, only aim
    line!", "Hardest! No lines at all!".
  - The table sign also shows whether abilities are on.
  - The ball-in-hand ring is plain blue again, with no ink outline.
- 2026-09-26: The hub map (designer, from the rooftop concept art now in
  `assets/map/reference/`; brief `docs/prompts/ROOFTOP_MAP_PROMPT.md`):
  - All 16 tables are green (the regular lobby); blue stays for the Pro lobby.
  - The tables turn sideways like the art (long sides to the entrance), so the terrace is wide
    and shallow. The grid is recomputed in Config.Hub.Tables in the brief's Stage 1.
  - Day and Sunset, no night, cycling for everyone on a server: 10 min day, 1 min fade, 5 min
    sunset, 1 min fade.
  - Extras in: a fire pit and a grand piano. Out: the infinity-pool strip and banners.
  - The build runs in stages with four designer checkpoints (gray-box layout, rooftop and
    props, city and ocean, lighting). Everything built procedurally in Blender from scripts in
    the repo; Poly Haven CC0 textures as bake inputs, Poly Pizza CC0/CC-BY models only as a
    palm or fern fallback; no AI 3D generators or Creator Store models.
  - Budget: everything we ship under about 512k triangles, leaving room for avatars under the
    designer's 1 million total.
- 2026-09-26: UI redo, third round (designer):
  - The status card says one line ("YOUR TURN", "THEIR TURN", "ALLY'S TURN", "FOUL!",
    "ROLLING"), the clock is bigger, and Leave is a small red door (its touch area stays 44 px).
  - No player names under the top bar's portraits; a rank badge will go there. A player who
    left gets a red X on their faded picture.
  - The host menu on a phone is one column again (two side by side took the whole screen),
    kept short: no DIFFICULTY heading, no "Start alone" hint, Leave beside Start, shorter
    descriptions and reasons. It sits beside Roblox's jump button, or above it if that makes
    it bigger.
  - Money per difficulty: 1x Classic, 1.5x Difficult, 2x Challenger (GDD section 12), shown
    under each difficulty with the new cash icon.
- 2026-09-26: Every table plays one mode again (designer). This supersedes the 2026-09-25 queue
  box and its halves.
  - Ten 1v1, four 2v2 and two 3v3 tables; the 1v1 at the front, the 3v3 at the back.
  - One round pad per table at the head end, toward the spawn, sized by mode, holding both
    teams. Stand anywhere on it to join: no dwell, polled at 10 Hz, and the client pops the
    menu the same frame. The 0.35 s dwell and the halves are gone; the spawn moved back to
    Z 38 to clear the front pads.
  - Start needs the pad full; teams go by arrival, alternately, the host team A. Solo and PC
    only on 1v1 tables.
  - The pad says "step here": a glowing rim (blue, green once somebody is on, gold when full or
    playing), rings pulsing outward and a bobbing arrow while it has room, and the mode written
    big on it.
  - The sign over a table is titled by its mode (1v1, 2v2, 3v3).
- 2026-09-26: Table looks by lobby (designer). Regular lobby, wood frames: green 1v1, raspberry
  red 2v2, slate charcoal 3v3. Pro lobby, black frames: blue 1v1, raspberry red 2v2, slate
  charcoal 3v3. The baseplate shows every combination for testing.
  - Red and charcoal were chosen by colour difference (CIEDE2000) against every ball:
    raspberry (191, 38, 89) keeps at least 17 from the red and maroon balls and slate
    (90, 94, 102) 22 from the 8, where the green cloth is 14.8 from the green ball. A truer
    or darker red blends into the maroon balls (7 to 11).
  - In play both read lighter than their swatches (the raspberry quite pink, the charcoal a
    slate grey); the designer's call whether to trade some contrast for a redder or darker
    felt.
- 2026-09-26: The hub map, Stage 0 (designer interview; spec in `assets/map/Spec.md`):
  - Queue pads on the map sit in front of each table, centred on the long side facing the
    entrance (not at the head end); the pad's shape may still change, so the grid is computed
    from the pad size in Config.
  - The map uses the regular lobby's mode looks (wood frames: green 1v1, raspberry 2v2,
    charcoal 3v3), replacing the brief's "all green".
  - Side seating follows the day view (02): city side planters, palms and lanterns; ocean
    side umbrella sets with loungers and sofa groups along the railing.
  - The entrance stair walks down to a small dead-end landing.
  - Prop scale is split: seats, steps and railings at player scale (1 m = 2.86 studs), big
    decor about 1.4 times that, the layout on the table's scale (the art draws real tables;
    ours are 2.25 times a real one in plan).
  - The snack counter is the art's lit back bar, centred along the back of the lounge.
  - The sunset sun: Roblox's sun always sets toward -X (the city side), so the Sunset state
    uses a real dawn sun (ClockTime 6.4, latitude -30) to sit low over the ocean, right of
    the lounge, as in the art; Day is latitude 45, ClockTime 10. Never a painted sun.
- 2026-09-26: The queue pad is a rectangle again (designer: "go back to the rectangle
  design"). The round pad lasted a day.
  - A white rounded rectangle with a glowing rim, lying along the table's long side toward the
    entrance: 10, 14 or 18 studs long by 5 deep for 1v1, 2v2 and 3v3 (`Queue.PadSizeStuds`).
    The mode and STEP IN or the count are written along it, and rounded outlines pulse out of
    it while it has room.
  - The floating sign sank into the floor over the round pad. A BillboardGui's
    StudsOffsetWorldSpace is measured in its adornee's own axes, and the disc was a Cylinder
    turned on its side, so "up" pointed sideways. The rectangle is turned only about the up
    axis, so the sign rises straight up again.
- 2026-09-26: Rooftop map, Checkpoint A (designer): the layout is approved, with changes.
  - No snack counter for now (parked in GDD section 18); the grand piano is the lounge's
    centrepiece, centred at the back, the bench behind it so the player faces the tables.
  - The glass railing reaches a character's head: 5 studs above the floor (was 3.6).
  - The city is densest in the direction the player faces on arrival (ahead and left), not
    behind the spawn where the stair is; in the gray-box a street grid of podium, shaft and
    crown buildings whose shore bends in toward the middle of the view with distance.
- 2026-09-26: Rank badges (designer, from a reference sheet of ten tier badges).
  - Consistency over the reference: stars for Bronze to Diamond and gems for Expert to
    Grandmaster, 1 to 5 of them for divisions I to V (46 ranked badges); a crown on every tier
    from Expert up, growing each tier (the reference had none on Veteran); Reyes one badge,
    no pips, no signature. Plus a plain grey Unranked badge (47 images).
  - No banner and no words in the images (UI_STYLE's no-words rule); the name is game text.
  - They always shine, more as you climb: sweep; sweep and sparkles from Expert; sweep,
    sparkles and gold rays for Reyes.
  - Drawn in code in the icon style (tools/gen_rank_badges.py) so all 47 match. Kept in
    `assets/ui/ranks/` and not uploaded or wired up yet, so this work does not overlap the
    map session in Studio.
- 2026-09-26: Rank badges redrawn after the reference (designer: "actually looking like a
  badge"). Each tier has its own badge design from the reference sheet (faceted frame, big 8
  ball, the tier's own plates, feathers, shards, fins, laurel or wings) instead of one more
  feather per tier. Kept from the first round: stars and gems for divisions, growing crowns
  from Expert, no banner, Reyes without a signature, the ball in the same place on every badge.
- 2026-09-26: Checkpoint B (the rooftop's props) approved with changes by the designer.
  - Seating is sized for a Roblox character, not a real person. The sofas, the umbrella sets
    with their loungers, the piano and its bench and the coffee table are placed at 1.6x;
    the fire pit at 1.3x, so it still fits inside its U.
  - The centre aisle from the spawn to the lounge is clear: its two crossing planters are
    gone.
  - The four 2v2 tables stand together (2 x 2) in the back-left corner and the two 3v3 in
    the back-right corner, seen from the spawn. The third row's right two tables are now
    1v1, so there are still ten 1v1.
- 2026-09-26: The rooftop map's coast moves out to make room for a promenade and a beach
  below the ocean side (Stage 4, the Spec's number). The waterline goes from X 110 to 205
  and, behind the tower, from Z -150 to -215. The city's bending shore further back stays
  where it was. The gray-box city was re-rolled once, seeded per block from now on, with the
  islands written in as they were.
- 2026-09-26: Rank badges, round three (designer): Diamond takes Grandmaster's cyan and
  Grandmaster turns orange; the stars and gems were too hard to read when small, so they are
  bigger, brighter and each sits in a dark socket; Reyes gets a nod to "The Magician" and
  "Bata": a little wizard hat hooked on the badge's top-right corner (picked from three
  mock-ups: on the corner, worn by the 8 ball, or with a cue as a wand at the bottom).
- 2026-09-26: Rank badges, round four (designer): no wizard hat on Reyes after all; Grandmaster
  is a rainbow badge instead of orange, in the house rainbow (UI_STYLE section 4's VIP
  colours), with each wing feather its own colour and prismatic gems. That it shares VIP's
  rainbow is noted as Open in UI_STYLE section 4.
- 2026-09-26: Rank badges, round five (designer): the overlapping pip sockets looked like icons
  piled on each other, so the pips now sit apart in one smooth curved tray with bevel shading,
  and each has a glow and a small shadow.
- 2026-09-26: Rank badges, round six (designer): the rainbow moves to Reyes (a rainbow frame,
  ring and crown, its crystals and blades red to purple) and Grandmaster becomes black and gold
  (Reyes' old look on Grandmaster's shape, with gold gems). The VIP-rainbow Open note now
  names Reyes.
- 2026-09-26: Rank badges, round seven (designer): the round tray covered the badge's pointed
  bottom and made every badge look round, so the pips now sit in a V (a chevron) that follows
  the frame's point, in one slim tray; one pip sits right at the point. Pips a little smaller
  (still countable at 64 px) so the tray stays inside the badge's shape.
- 2026-09-26: Rank badges, round eight (designer, still preferring the reference): no tray at
  all. The pips sit on the ring's bottom edge like the reference's star, the middle one
  biggest, each with a thick ink outline, a shadow and a glow so they pop by themselves.
- 2026-09-26: The rooftop map's backdrop is split by what each device can draw. At graphics
  levels 1 to 10, where most phones run, Roblox draws nothing beyond a few hundred studs, so:
  - the mid backdrop (the city from 450 to 2,300 studs out and the near islands) is 3D only,
    extra depth on devices that draw it;
  - everything beyond is painted into the skybox (Stage 6), which every device shows.
  A building can't be both built and painted: the two drift up to 8 degrees apart as a
  player crosses the roof. The city's heights step up with distance (only the landmarks rise
  over the roof close in), and its glass is a soft steel grey-blue, so the skyline never
  matches the gameplay's blue arrows and rings on a phone.
- 2026-09-26: Rank badges, round nine (designer): stars were too puffy ("looks AI
  generated"), so they are straight-edged and bevelled; nothing hangs below the pips any more
  (the frame ends at them, and Bronze to Gold lose the dark feet under their plates, Veteran's
  laurel stops beside them); more of the reference's glare (a bright band on polished metal,
  streaks on lit bevels, glints, a glossier 8 ball). Checked in motion with a GIF of all 47.
