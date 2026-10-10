# Decisions

Dated one-liners with the reason. This is the only place that records when something was
decided; the GDD and roadmap state the result without dates. Newest at the bottom. Each line
is the call as it was made then, not a permanent rule: a later line can change or reverse it
(see "Past decisions are not set in stone" in `CLAUDE.md`).

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
- 2026-09-26: The rooftop map's far horizon (Stage 6) is painted into the skybox, not on the
  brief's far cards: cards 2,000 studs out would vanish on the phones that need them most
  (graphics levels 1 to 10 draw nothing that far). The 3D water and land stop at 2,600 studs,
  where the painting takes over. Along the way:
  - the big island behind the pergola moved from azimuth 3 to 7, clear of the city's shore;
  - the near islands stay 3D only (a painted twin showed as a ghost peak behind its 3D island
    from the roof's edges); five far-only islands on the ocean side, one a range behind the
    near peak right of the pergola, give phones islands there instead;
  - the far city's towers gather in three downtowns ahead-left, with six painted landmarks,
    over a low carpet: a skyline's hierarchy rather than an even band;
  - beyond the near world the stair side's thinning eases in by bearing (90 to 135 degrees)
    instead of a straight line at Z 250, and the 3D city's outer 400 studs step down toward
    the painting, so no hard edge shows in the city-side view (the near world is unchanged).
- 2026-09-26: Rooftop map, Checkpoint C (designer): the far horizon is approved as it is, with
  the city showing through the pergola's left half. The city, mountains and sea are background:
  the lighting and atmosphere (Stage 7) soften and blur them so the focal point is the pool
  tables, which also masks the backdrop's low poly. No detail pass on the backdrop is planned.
- 2026-09-26: The rooftop map's day and sunset cycle (Stage 7):
  - Lighting.Technology is gone (the place is on Roblox's unified lighting, style Soft), so
    the brief's Future step is dropped; the look was tuned in Play.
  - The lit windows at sunset are an emissive mask on the skyline's own texture, not the
    brief's Neon window mesh: the same glow with no new MeshParts, triangles or import, and
    phones (which draw no 3D skyline) see the lit windows painted in the sunset sky.
  - The sky swap: one swap from the blue day sky straight to the magenta sunset popped, and a
    haze bump made it worse (Atmosphere haze takes the sky's colour and tints the whole
    rooftop), so a third, in-between dusk sky is rendered from the same cloud scene and the
    cycle swaps day, dusk, sunset; the haze bump is only a hint.
  - The background is kept soft by depth of field (the roof sharp to 260 studs; PC-class
    devices) as the designer asked at Checkpoint C; the sunset has no haze (it fogged the 3D
    world away in Play).
  - The designer's `/day` and `/sunset` chat commands (only for them, the group's owner, or
    anyone in Studio; checked on the server) send the whole server's cycle toward that state
    through its one-minute fade, so the transition shows.
- 2026-09-26: The rooftop's city, after the designer's look in Play:
  - **Full detail.** The near world and the mid backdrop draw at RenderFidelity Precise, not
    the brief's Performance. Roblox's distance LOD crumpled the boxy meshes and smeared
    their textures: far towers warped, and the parks and beach below read as "random terraces
    of grass" and odd sand. It costs about 75,000 triangles at full detail, inside the caps.
    Only the tower's walls keep Automatic.
  - **The stair side is filled.** The empty flat grey ground behind the spawn was the mid
    city's thinning (the stair side "seldom looked at"). The designer chose buildings over a
    fog that would also have hidden the city they like.
    - The mid city keeps every block there, still low (40 to 120 studs, the roof 300 up), and
      the strip beside the beach promenade is built too.
    - The near world's parks and the painted far city are unchanged.
  - **A light haze.** Atmosphere Density 0.15 and Offset 0.2 by day and at sunset (Haze stays
    0) fade the far city and its join with the painted sky; the roof stays crisp. Density 0.3
    greyed the whole city in a test.
  - This revisits Checkpoint C's "no detail pass on the backdrop": the designer asked.

- 2026-09-26: The rooftop map's camera zooms out at most 40 studs (`Config.Hub.CameraMaxZoom`;
  Roblox's is 128), so the camera stays near the roof. At the lowest graphics levels Roblox leaves
  the outer city undrawn (STUDIO_NOTES), and zoomed far out the camera saw a grey plain; the
  designer chose the cap over re-chunking the city. The near world's park behind the tower is one
  patch of lawn: its separate lawns, paving and dotted trees read as odd terraces from the roof.
- 2026-09-26: The rooftop map's city, from the designer's notes after playing it:
  - Round the tower, the lawns are gone: small city blocks (low buildings, two to five floors)
    with streets, lane lines and crossings running up to the tower's plaza, and street trees.
  - The mid city's canopy trees and lawn blocks are gone (they read as black rocks at sunset);
    real streets run between its blocks. Its brown facades are a light tan and greige, with
    punched windows in the texture (no new triangles; the mid city fell from 66,665 to 53,397).
  - The city's shore has a paved promenade and a beach; the ground uses Roblox's asphalt,
    pavement and sand materials instead of flat colour; the shore's edge steps every 30 studs.
  - At sunset every building, near and mid, is tinted pink-lavender and its windows glow warm
    yellow (emissive masks on both sheets; the near city's new).
  - The ground painted in the sky is grey streets and pale blocks, not grey-green, so the lowest
    graphics levels (which do not draw the 3D ground far out) show a city, not a green field.
- 2026-09-26: Players walk 30% faster on the roof (`Config.Hub.WalkSpeed` 20.8, Roblox's 16);
  the sea has a visible swell (Terrain waves 0.25 at speed 12, day and sunset; they were kept
  near flat since Stage 4); and every grid cell of land that no block and no near-world ground
  covers (by the promenade, and behind the tower on the city side) is a paved lot with a low
  building (`city_plan.edge_cells`), so no bare grey ground is left in the city (designer).
- 2026-09-26: The camera's zoom cap is gone (designer: Roblox's own zoom). Every table has a
  lamp over it (`Config.Look.TableLight`: a spotlight on the cloth, no shadows), off by day
  and lit at sunset by the day cycle (`Config.Lighting`'s TableLights), because the tables
  were too dark to play at sunset (designer).
- 2026-09-26: The fire pit burns only at sunset, with our own effect instead of its static flame
  mesh or Roblox's stock Fire (designer): cel-shaded flame licks from an 8 x 8 flipbook drawn by
  `assets/map/gen_fire.py`, embers, a glow, a little smoke and a flickering light, built on each
  client by `FirePit` and faded in by the day cycle (`Config.Lighting`'s Fire). Few long-lived
  looping flames rather than many short ones, because Roblox thins particles at low graphics levels.
- 2026-09-26 (later): The fire pit uses Roblox's own Fire after all (designer: the custom effect
  above did not suit). Still only at sunset, the static flame mesh still hidden, with the warm
  flickering light; the custom flipbook, its images and gen_fire.py are removed.
- 2026-09-26: Rooftop map, Checkpoint D (the sunset and the day/sunset cycle) approved by the
  designer after the changes above; Stage 8 finishes the map.
- 2026-09-26: The road to release (designer). The order of work: (1) the pool game itself, its
  UI and mechanics, fitting and working on phone and console; (2) ranks and EXP; (3) bots, ten
  of them, one per tier, Bronze easiest to Reyes hardest, each player meeting the bot of their
  rank; (4) the cue models and textures, money, the shop, inventory, an index, loot boxes and
  trading. The roadmap is reordered to match; milestones keep their numbers.
  - Not in the release: abilities, the pro lobby and the global queue. The pro lobby and the
    global queue follow about one to two weeks after release, since nobody can reach the pro
    lobby's rank at launch. Abilities are up for debate once the economy, bots, ranks and cues
    are in: they come only if matches need more fun (the ability gacha goes with them).
  - Trading moves into the release (it was after it). EXP and an index are new (details Open).
  - Save data (4.3) moves ahead of ranks, because ranks, EXP and money must persist; the UI pass
    (4.2) moves into the pool-game stage.
- 2026-09-26: The first-time tutorial (8.1, the onboarding first match) and the analytics funnel
  (8.2) are built together once everything else is done, just before the performance pass and
  the game page (designer).
- 2026-09-26: After a shot the camera pulls out to a fixed semi-top-down side view of the whole
  table instead of the whole table along the aim (designer, as a test; the older view stays
  behind `Config.Camera.Shot.PullOutView`). It swings round the table from the long side needing
  the smaller turn, so it never turns more than about a quarter of the way round (less motion,
  less dizziness). The designer kept the half-second hold, kept soft shots in the aiming view,
  chose about 0.9 s for the swing, and a swing back to the aiming view when the balls stop.
  The side view is fitted exactly between the match HUD's bands (the old stepwise HUD fit left
  the table up to 12% small).
- 2026-09-26: Lighting brighter and more saturated, like the top Roblox games (designer: the
  game read washed out and hazy, especially at sunset; keep it bright and happy but warm and
  cosy). Day: sun 2.6, a lighter warm shade, atmosphere 0.08, saturation +0.2, contrast +0.12.
  Sunset becomes a golden hour: the sun 12 degrees up (ClockTime 7.4, was 6.4 and 4 degrees,
  which left the roof lit only by the lavender shade), sun 3.4 and golden, a warm tan shade,
  half the magenta sky fill, a thin peach haze, saturation +0.15 (0.25 turned the felt neon).
  Tuned from Play captures against the old look.
- 2026-09-26: The match HUD as small as possible on every device (designer: it blocked the
  table): the top bar is the balls plus a sliver (37 px computer, 30 phone; was 64 and 52), the
  portrait, clock, phase icon and Leave shrink into it (Leave keeps a 44 px touch area), one
  row of balls shrinks its balls to 16 px before two rows are used, and the ball-in-hand hint
  is a thin line as wide as its words.
- 2026-09-26: Balls pocketed on the break play the bonus sound for the breaker's team
  (designer; the break was physical-only). The break still never assigns groups, and the 8 on
  the break (re-spotted) gives none.
- 2026-09-26: The shot clock's last 5 seconds tick once a second for the shooter, the last two a
  little higher, stopping when they shoot (designer: pressure to shoot). The sound is licensed
  (APM's "TICK TOCK 06 120BPM" in Roblox's library, its first tick only): the store's "clock
  tick" uploads are players' rips of other games, which the GDD's licensed-audio rule forbids.
- 2026-09-26: A match's invisible walls stand 3 studs beyond its area on every side
  (`Config.Multiplayer.Fence.RoomStuds`, `Placement.matchWalls`), so a player waiting for their
  turn has a little room to walk about (designer). The match area itself (layout, pads, signs)
  is unchanged; neighbours' walls still stand 2 and 4 studs apart, so nobody reaches another
  table (a Lune test keeps it so).
- 2026-09-26: The match top bar redone for every resolution (designer): one row always, laid out
  once and scaled down to fit (a UIScale); the status card is gone, replaced by a 2 s turn popup
  on turn changes ("YOUR TURN" / "OPPONENT'S TURN" / "ALLY'S TURN"); the shot clock big and
  centred between the teams, hidden when no clock runs; Leave at the bar's right end on every
  platform. On a computer or tablet the power bar is bigger and centred on the right (its cue
  slides 0.55 of the bar there so it stays on screen). A zoom guide over the spin button during
  your turn: a mouse-wheel or pinch icon and the word "Zoom", no background (designer: not the
  kit's card style), always shown during your turn.
- 2026-09-26: The zoom guide is greyed out, smaller and reads "Zoom In/Out", so it looks like a
  control guide rather than a button (designer); its mouse icon shows a big ridged wheel
  rolling up and down.
- 2026-09-27: The power bar sits 5% of the screen higher on a computer or tablet (designer;
  phones keep it just under the top bar, where Leave sits above it).
- 2026-09-27: Fredoka One kept; text under 20 px gets a 1 px outline instead of 2 px (designer,
  after a Studio comparison with Nunito Heavy, Builder Sans Heavy, Montserrat Black and Luckiest
  Guy). Roblox strokes the inside edges of letters, so a 2 px outline closed the holes of o, a,
  e, 0 and 8 at 14 px; 1 px keeps them open.
- 2026-09-27 (designer): the Leave door fills its button (icon-only buttons at 95%); the zoom
  guide lighter and bigger (40 px icon, 16 px words) with the mouse wheel circled in red; the top
  bar is pinned to where Roblox's top row really is (an iPhone 17 Pro drew it lower, over the
  table, because its screen starts below GuiService's inset); on a phone the camera starts one
  zoom step closer and the break opens there too (Camera.View.PhoneZoomNotchesIn and
  PhoneBallInHandZoomNotches).
- 2026-09-27: When the first legal ball after the break decides the groups, each player gets a
  2.5 s popup, "YOU ARE SOLIDS" or "YOU ARE STRIPES", with a solid or striped ball (designer).
- 2026-09-27: The group popup (YOU ARE SOLIDS / STRIPES) stays up 3.5 s, a second longer
  (designer).
- 2026-09-27: With ball in hand the big clock shows the time to shoot (15 s to move plus the
  20 s shot clock, one countdown) and a blue "MOVE 12s" pill under it shows the moving time,
  so the 15 s to move no longer reads as 15 s to shoot (designer).
- 2026-09-27: Changed: with ball in hand the big clock holds at the 20 s shot clock (not 35 s
  counting down) and starts only when the MOVE pill reaches 0 (designer).
- 2026-09-27: The break's hint is short and in capitals: "DRAG BALL ANYWHERE ON LINE" (designer).
- 2026-09-27: The break gets one 20 s clock (Multiplayer.BreakSeconds) to move the cue ball
  and shoot, not 15 s to move plus 20 s to aim; running out is a timeout foul that counts
  toward the two-timeout forfeit, and the opponent gets ball in hand anywhere (designer).
- 2026-09-27: The coin flip card shows a few words at a time: YOU ARE HEADS/TAILS on the
  still coin (0.5 s), the flip (1.2 s), then YOU BREAK or <NAME> BREAKS (1.3 s). CoinSeconds
  2.6 -> 3; the team line and "wins the flip" are gone (designer).
- 2026-09-27: NICE SHOT! over the pocket for a good pot that was not plain: a bank, combo,
  kick or carom (Rules/NiceShot); rail hits within 7 in of a pocket are its jaws and do not
  count; never on the break (designer).
- 2026-09-27: Nothing darkens the screen: the coin, result and leave/surrender cards and the
  spin picker are just popups (ModalDim 0.45 -> 0, spin OverlayTransparency 0.9 -> 1) (designer).
- 2026-09-27: The zoom guide hides after the player's first zoom and stays hidden for the session; it returns on the next visit (designer).
- 2026-09-27: NICE SHOT! is a lot smaller: 22 px text (was 40), rays 90 px (was 150) (designer).
- 2026-09-27: NICE SHOT! text 18 px (was 22), rays 74 px (designer).
- 2026-09-27: Queue area as one card over the table (designer): the pad says JOIN and is
  see-through glass tinted with its rim; the host's menu and the sign float over the middle of
  the table, not the pad; guests on the pad see the sign, not a greyed menu; the money each
  difficulty pays sits in its tile under the name; no Leave button (walk off). Start on a pad
  that is not full waits (settings shown, Back) and the game starts by itself 3 s after the pad
  fills (at once if everyone was already on). Alone on a 1v1 table: Request opponent (a
  Join/Dismiss popup with the host's face for everyone not at a table; Join teleports them onto
  the pad), Play against PC, Play solo. Defaults picked by Claude, open to change: Join
  teleports, the popup lasts 15 s, the host may ask again after 20 s.
- 2026-09-27 (later): Simpler still (designer): no settings and no Start. Stepping on shows the
  host a small card top right ("Classic 1v1", the count, waiting) with Request opponent (Request
  players on 2v2/3v3), and on 1v1 alone Play against PC and Play solo; a full pad starts by
  itself 3 s after the last one stepped on. Public tables play Classic with no abilities (no
  toggle; Difficult and Challenger may become pro-lobby only). The sign is back over the pad,
  without abilities. Supersedes the card over the table and the Start/Back flow above.
- 2026-09-27 (later): Smaller queue GUI (designer): the sign over the pad drops the JOIN pill
  and "Join to play" and fits its rows (220 px wide), the mode written bigger (34 px); the
  host card is tucked top right at 72% on phone-sized screens (under 500 px tall) and sits on
  the right, halfway down, on big ones; after Request it folds to "Requested!" and unfolds if
  nobody joins within 15 s (one request window: the popup, the fold and the re-ask wait are
  all 15 s, was 15 and 20). The pad's arrow hides while its sign is up, so it never covers
  the mode (Claude's call).
- 2026-09-27 (later): Queue GUI polish (designer): the sign's count and difficulty sit 16 px
  apart, centred (they touched); the host card goes in the very top right corner beside the
  top bar at 85% (was 72%, and 120 px in from the edge when no jump button showed), shrinking
  only to clear a showing jump button; its folding parts no longer clip the buttons' sides;
  "Waiting for opponent" gets three dots that light up one by one.
- 2026-09-27: Ball in hand after a foul: 10 s to move the cue ball (was 15), then the shot
  clock (designer).
- 2026-09-27: The host's card goes the moment the host steps off the pad, not after the
  server's exit grace; the request popup is smaller and lower (250 x 66, was 330 x 96) so it
  clears the player's legs, its buttons keeping a 44 px touch area (designer).
- 2026-09-27: The green balls (6 and 14) are a deeper green, RGB 12, 92, 52 (was 20, 130, 70),
  so they stand out on the green cloth: CIEDE2000 against the cloth 31.6 (was 17.2), still
  30.6 from the 8 (designer asked; the shade is Claude's pick).
- 2026-09-27: The host card is 1.3x on big screens (PC, console, tablet; was 1x) (designer),
  raised to end above a tablet's jump button.
- 2026-09-27 (overnight, ranks and money; designer's answers): demotion above Diamond drops
  divisions but never a tier (Master III can fall to Master I, never to Veteran); placeholder
  pace 4 wins a division (1,000 XP a division, a win +250); Rank and Money also show in
  Roblox's player list (leaderstats); work on the branch `ranks-money`.
- 2026-09-27: Saves use ProfileStore (loleris, vendored at a pinned commit) wrapped by
  `PlayerData`, the only module that touches DataStores; Studio uses its own store
  (`PlayerData_Studio_v1`) so tests never touch real saves.
- 2026-09-27: Running out of shot-clock timeouts counts as a forfeit like a surrender: no
  consolation XP and no match bonus for the team that timed out (overnight assumption).
- 2026-09-27: Under the one-minute mark a forfeiter is charged only when the loss costs XP
  (Expert and up, -150, and the match counts); a lower-tier forfeiter under the mark gets
  nothing and the match is not counted, so a quick quit never makes an Unranked player
  Bronze I (overnight assumption).
- 2026-09-27: A server shutdown (an update, "shut down all servers") voids running matches:
  nobody is charged a forfeit and nobody is paid the match; the money their pots paid stays
  (overnight assumption, from the save-layer audit).
- 2026-09-27: A player cannot take a seat until their save has loaded, so a match result
  always has somewhere to go (overnight assumption, from the audit).
- 2026-09-27: Solo pays per ball (30%, then $1 after $300 a UTC day) and has no match bonus
  and no XP; its end screen shows the pots' money only (overnight assumption).
- 2026-09-27: Money for a shot is saved the moment the server accepts it; the flying cash is
  only its animation, timed to the ball dropping in the replay (overnight assumption).
- 2026-09-27: On an open table only a legal pot pays: an early 8 pays nothing for the other
  balls it took down; the break pays $10 a ball but no nice-shot bonus (almost every break
  ball would read as a combo); the 8 pays only when it wins (overnight assumption).
- 2026-09-27: A solo grant that starts under the $300 daily cap is paid in full even if it
  crosses it; after the cap a ball pays $1 and nice shots nothing (overnight assumption).
- 2026-09-27: Money from 10 million is shortened with up to two decimals, cut not rounded
  ("$12.5M", "$999.99M", "$1.23B") (overnight assumption).
- 2026-09-27: `/rank` sets the rank, makes the save rated and moves the peak to it, so
  rewards below it are treated as paid; `/resetdata` clears everything, so rewards can be
  earned again (overnight assumption).
- 2026-09-27: A draw gives 0 XP and no bonus; it counts as a match only when real
  (overnight assumption).
- 2026-09-27: Tier colours for the roadmap and confetti are in `Config.Ranks.Colors`:
  Bronze copper, Silver steel, Gold, Platinum pale blue, Diamond cyan, Expert red, Veteran
  green, Master purple, Grandmaster near-black, Reyes pink (overnight assumption, from the
  badges and the roadmap reference).
- 2026-09-27: The money icon is the three-bundle cash stack after reference 04 (it replaces
  the old Money icon everywhere); the single bundle is the flying "+$10" chip's icon.
- 2026-09-27: Interface sounds are placeholders from Roblox's own library and APM Music,
  chosen by name and length without being heard (overnight assumption; list in
  `assets/audio/README.md`).
- 2026-09-27: The end-of-match screen's cards show usernames, like the nameplates (overnight
  assumption). Its dim (50%) and NEW RANK!'s (45%) were removed the same day: popups never
  darken the screen (designer, now written in UI_STYLE section 2); only the Ranked roadmap
  keeps its slight dim.
- 2026-09-27: Nameplates are drawn over the world (AlwaysOnTop), like Roblox's own names, so
  hats and walls never cut them, sized in studs to read like reference 02; your own plate
  shows too (overnight assumption; `Config.UI.Progress.Nameplate`).
- 2026-09-27: The rank HUD shows Unranked as an empty bar of Bronze I's 1,000 XP, and Reyes as
  a full shimmering rainbow bar with just the XP; a jump across divisions fills, flashes and
  lands on the new rank in one step (overnight assumption).
- 2026-09-27: The roadmap's next-reward card shows the next reward not yet paid, so after a
  drop it points past the peak; on a phone the tier strip shows badges without names
  (overnight assumption).
- 2026-09-27: Gamepad: Y (when no queue card or join prompt wants it) selects the rank badge;
  A opens the roadmap; B closes it. A selected badge shows by its hover pop, not a gold ring
  (overnight assumption).
- 2026-09-27: The money HUD never shows more than the saved total: a preview's made-up money
  (/result, /newrank) only bumps the icon (overnight assumption).
- 2026-09-27: Money ignores the table's difficulty multiplier for now
  (`Config.Economy.UseDifficultyMultiplier = false`): no screen sets a difficulty, but the
  server still accepts one, so a modified client could claim 2x. Turn it on with the
  difficulty lock (Roadmap 6.2) (overnight assumption, from the second audit).
- 2026-09-27 (designer, after trying the overnight build): the whole rank HUD (badge and pill)
  grows on hover and squish-bounces on click; badges shimmer far less (a faint sweep every 7 to
  9 s instead of 2 to 4) and sparkle instead, a burst of sparkles on hover and press.
- 2026-09-27 (designer): the roadmap follows reference 03: the ten tiers side by side with
  arrows and swipe (no divisions in the row; five dots per tier), no bottom strip; the left card
  shows your rank with an arrow to the next division and its reward; "Rewards for <tier>" shows
  money, a Case (x1, soon), the chat tag and a Cue ("Platinum Cue", soon) for every tier,
  opening on your next tier, and tapping a tier shows its rewards.
- 2026-09-27 (designer): a chat tag before your name in chat: the tier only, in capitals, in
  the tier's colour ("[PLATINUM]"); the name keeps Roblox's colour; none for Unranked. The
  colours are brighter chat versions (`Config.Ranks.ChatColors`; Grandmaster gold, Reyes
  rainbow).
- 2026-09-27 (designer): an 8 that loses the game (early, wrong pocket, on a foul) gets no
  celebration at all: no NICE SHOT!, no pocket burst, no sting. The server marks the shot
  (`eightWins`).
- 2026-09-27: The next tier in the roadmap stays in full colour like reference 03; only tiers
  after it are greyed (Claude's pick).
- 2026-09-27 (designer): the roadmap loses its line of XP rules under the cards; the rank HUD
  is bigger on a computer (1.5 times its phone size, was 1.15); the hover sound is Roblox's
  "RBLX UI Hover 01" (0.2 s) instead of the 2.7 s Cute Pop. The roadmap's arrows get a
  one-piece chevron image, since four rotated bars left a seam at the tip.
- 2026-09-27 (designer): while you shoot at a called pocket, its marker sits inside the hole
  (sized from the hole on screen) with no caption, never over the jaws; choosing keeps the
  44 px rings.
- 2026-09-27 (designer): the panel pattern is faint soft 8 balls of a few sizes, each turned
  its own way, after the designer's reference, instead of tiny flat pool balls; for every
  panel now and later (it comes from the kit's card).
- 2026-09-27 (designer): the 8-ball pattern is one small size on an even staggered grid, all
  turned alike and slightly blurred; the scattered mix of sizes was too big and busy.
- 2026-09-27 (designer): back to the scattered 8 balls of a few sizes; the even grid looked
  worse.
- 2026-09-27 (designer): menus (the roadmap, the host menu, later the shop and the rest) have
  a pale-blue header band for the title and close button, and their content on a near-white
  sheet with big rounded top corners and a thin light-blue edge (HudParts.menuCard).
- 2026-09-27 (designer, economy interview): the economy plan is `docs/ECONOMY.md`, with a
  model that checks its numbers (`tools/economy_model.py`). Anchors: 5-8 minute matches; a
  typical player plays an hour a day; first Epic after a few hours, first Legendary in 1-2
  weeks, first Mythic in at least a month, Secrets take months and come mostly from the shop.
- 2026-09-27 (designer): EXP and rank are two bars: RP (the saved RankXp) can fall from
  Diamond; EXP fills an account Level that only rises. VIP's 2x EXP can then never buy rank.
- 2026-09-27 (designer): only the winner of a real match gets a free Standard Case, every win
  for new players and fewer later (both a new-player allowance and a daily one); solo never.
- 2026-09-27 (designer): duplicates can be sold back for money; no trade-up.
- 2026-09-27 (designer): today's deals are the same for everyone, unlimited copies, one per
  player; at least one Epic, never a guaranteed Legendary, Secrets only when the designer
  pins one.
- 2026-09-27 (designer): rarities Common to Mythic plus Secret from cases and the shop; Unique
  (numbered limited copies) and a new group, **Exclusive** (VIP Cue, rank cues, Starter Cue),
  never from cases. Rank cues can't be traded, so a Reyes Cue proves Reyes.
- 2026-09-27 (designer): four money cases (Standard, Rare, Epic, Legendary), each guaranteeing
  one rarity below its name.
- 2026-09-27 (designer): VIP is 2x money and 2x EXP. The half-price VIP offer runs 24 hours
  from the first join plus one 24-hour comeback after 7 days, not 15 minutes: Roblox's own
  monetization rules call a very short discount window unfair, and a discounted pass would
  show publicly in the Store tab (research).
- 2026-09-27 (designer): Grandmaster and Reyes are leaderboard seats; from Veteran up a tier
  can be lost after a 3-loss shield, Expert is safe for good (this replaces this morning's
  "never out of a tier"); Difficult unlocks at Gold, Challenger at Diamond; soft seasons later.
- 2026-09-27 (designer): the first session must feel fast and rewarding, and the release must
  suit a small game that never reaches thousands of players; numbers can be changed later.
- 2026-09-27 (Claude's calls, from the model and research; overrule any): every number in
  ECONOMY.md; Levels pay money, never cases (a case that VIP's EXP can speed up would be a
  paid random item); a Rookie Boost of 2x EXP for the first 25 matches; the first win's reveal
  is a Rare Case; streak day 7 an Epic Case and a Legendary Case for four full weeks; secrets
  from cases at 1 in 1,000 Legendary Cases at best; Reyes seats as the top 10% of eligible
  players (at most 50) so the top scales down for a small game; PC RP x0.5 at every tier at
  launch so a lone high player can climb; boosts add rather than multiply; Money Party and
  Fast Open at launch, a Cue Pass later; the starter pack holds no case.
- 2026-09-27 (designer, PS5 pad): Y in the hub opens or closes Ranked (it used to select the
  rank badge, which froze walking); a pull is called off by moving the stick or the D-pad;
  holding L1, the left stick is spin and the right stick the cue angle; choosing the 8's
  pocket, the stick goes to the ring that way on screen; a controller guide strip (Roblox's
  own button glyphs) and a Circle beside Leave while it is your turn on a gamepad.
- 2026-09-27 (designer): a match starts ready to play on a gamepad: any leftover selection
  (the host menu's button handed on to the spin toggle) is dropped; only the leave dialog,
  the pocket rings and the result screens keep one.
- 2026-09-27 (designer): while L1 holds the spin panel open, the controller guide shows the
  spin controls (left stick Spin, right stick Angle, Y Center spin) instead of the aim ones.
- 2026-09-27 (designer): X (Xbox A) is the only gamepad shot button: hold to build power,
  release to shoot. The analog R2 pull did not work well and is unbound.
- 2026-09-27 (designer): no level gate on trading (it was Level 10); anyone can trade from the
  start. Levels have no max (100 was only the last milestone). Alt farming is limited by the
  free-case rules instead.
- 2026-09-27 (designer): no direct buying of case cues; the rotating "today's deals" shop is
  dropped (research: items that stay buyable lose trade value, while items sold briefly then
  retired gain it, as with MM2's limited bundles). A Limited shelf sells exclusive, numbered
  Unique cues for a set time, then never again. Every cue shows how many copies exist.
- 2026-09-27: with the shop gone, case Secret odds rise (Legendary Case 1 in 400) so a
  dedicated player still gets one in months, not years (Claude's call from the model).
- 2026-09-27 (designer): deals are only on cases (bulk 10-for-9, occasional genuine case sales,
  timed special event cases with their own cues), never a guaranteed case cue. The Limited
  shelf of timed exclusives stays.
- 2026-09-27 (designer asked for a small-game check): bots give x0.75 RP to Diamond (x0.5 from
  Expert) and a free case on every win; the opponent-gap factor is gentler from Bronze to
  Diamond (scale 12, never under 30%) and strict from Expert. Before, a player with only bots
  or only weaker opponents needed twice as long to reach Diamond (Claude's call from the model).
- 2026-09-27 (designer): a red Cancel under "Requested!" takes a request for an opponent back;
  everyone's popup closes and the host's card unfolds at once. A new request waits 3 s after
  the last one (Queue.RerequestSeconds) so Request and Cancel cannot flood popups.
- 2026-09-28 (designer): the global queue moves into the release and is built now (it was
  planned for one to two weeks after release). Join Global Queue is the host card's 4th
  choice on every pad; 1v1 alone, 2v2 needs 2 on the pad, 3v3 needs 3; the first whole side
  by arrival goes and anyone extra stays. Players stay on the pad while searching (stepping
  off cancels; a pad that fills plays locally). Closest rank first, anyone after 10 s.
- 2026-09-28 (designer): the arena is a reserved server of the same place (one file, one
  publish; Claude's recommendation, chosen by the designer), a placeholder dark room after
  the reference image until the art exists. After each game: Rematch (all must agree),
  Play another (the whole team together in 2v2/3v3) and Lobby (back to the server you came
  from). The series score is counted (1-0, 2-1 ...).
- 2026-09-28 (designer): rematches alternate who breaks, with no coin flip (the GDD said a
  fresh coin flip); the rematch window is 20 s (was 15 s in the GDD) so the result screen can
  be read. Lobby tables get Rematch and the series score too, with Leave.
- 2026-09-28 (Claude): each server takes turns pairing the queue (a lease in MemoryStore) and
  keeps two reserved servers ready; a save is let go before a teleport (PlayerData.handOff)
  and ProfileStore looks again after 1.5 s (was 5 s) when a save is still held, so arriving
  never waits on the old server. Walking away from a finished lobby game declines the
  rematch.
- 2026-09-28 (designer): the arena reuses the rooftop instead of a new map (to save time):
  the same light and day cycle, started at day, with only one table, in the middle, in the
  blue felt on black. The placeholder dark room is gone.
- 2026-09-28 (designer): division sizes only grow up the ladder, so every Expert-and-up RP
  number is tripled (Expert 4,500, Veteran and Master 6,000; Challenger +675 / -517); the pace
  of climbing is unchanged.
- 2026-09-28 (designer): every UI's buttons are evenly spaced. The host card's rows are now
  stacked by code (QueueMenu.stack), so a fold's outline room no longer doubles a gap.
- 2026-09-28: Lobby goes back to the server you came from only while it is still open with
  players and room; otherwise to any lobby server (an emptied server shuts down, and Roblox
  showed error 771 for it).
- 2026-09-28 (designer): the win streak shows over the head as "🔥 N" from the first win.
  Claude's rules (easy to change): real wins against people count (as for rank XP), any loss
  ends it including a quick surrender or leaving, a draw leaves it, and it is saved.
- 2026-09-28 (designer): no account Level or EXP; rank XP is the one progression and the main
  status flex. XP is never lost: losses give a little to Platinum (+25 there) and 0 from
  Diamond, so nobody drops a rank (replaces the Elo losses, the Veteran+ shield and demotion).
  Grandmaster and Reyes are fixed XP amounts, not leaderboard seats; Reyes at 2,352,500 XP.
  Ranks never reset. VIP gets 2x money and +50% XP. Skill sets the speed: harder modes, a +25%
  win streak from the 3rd win, and the opponent-gap factor. Level money moved into rank
  division rewards; the Rookie Boost and first-win-of-day bonus now boost XP.
- 2026-09-28 (Claude's calls from the model): division sizes from Diamond I (8,000) grow about
  17% a division so Expert takes about 60 hours at a 50% win rate and Reyes about 1,100 hours
  at 55%; the Diamond tier reward is 2 Epic Cases (a Legendary Case there made first
  Legendaries too fast once the Rookie Boost sped up ranks); the anti-alt rule "loser must be
  Level 3" became "loser must have played 5 real matches".
- 2026-09-28 (designer, interview before the overnight economy build): four buttons in one
  column on the left, a bit smaller, top to bottom Shop, Inventory, Rewards, Trade; Shop holds
  Cases, Limited, Money and VIP, Inventory holds Cues, Cases and the Index, Rewards holds Daily,
  Playtime and Codes; Trade opens a "Soon" frame (trading is a later session). Cases open on a
  spinning reel (Rivals / CS style). New icons are drawn in code (`tools/gen_ui_art.py`) after
  references 06 (the column tiles) and 07 (the case chest). The Index shows never-owned cues as
  dark silhouettes with "?", and completing a rarity row pays once. Written into ECONOMY.md
  section 18.
- 2026-09-28 (overnight assumption): match XP rounds half to even, because ECONOMY 4.2's table
  was printed by Python's round (Difficult Bronze win 312.5 -> 312, Challenger Platinum loss
  37.5 -> 38); money keeps rounding half up.
- 2026-09-28 (overnight assumption): the Index's Legendary, Mythic and Secret rows give a title
  only, no money (money there would reward luck more than play); Exclusive and Unique are
  listed with no row reward.
- 2026-09-28 (overnight assumption): Secret's colour is near-black with a red glow (UI_STYLE
  4's suggestion); Mythic's solid colour (card frames, chips) is its shimmer's lilac #B79CFF,
  with the pastel shimmer over deep space where there is room.
- 2026-09-28 (overnight assumption): 30 placeholder case cue names and looks (pool and rooftop
  words: Chalk Dust ... Starfall, Nebula, Eclipse), ten rank cues in their tier colours (Reyes
  and VIP in the house rainbow), the Starter, Founder's and Beta cues. Rank cues' trails go by
  tier (Bronze-Gold Uncommon, Platinum-Diamond Rare, Expert-Master Epic, Grandmaster
  Legendary, Reyes Mythic).
- 2026-09-28 (overnight assumption): in a team match the same-opponent count (anti-farm, 3.6)
  is the most-played opponent's; the login streak runs in cycles of four weeks (the Legendary
  Case on day 28, then week 1 again); the Event Case, switched off, drops the normal pool
  until an event gives it its own cues; placeholder codes WELCOME ($500 and a Standard Case),
  8BALL ($250) and ROOFTOP (a Rare Case, until 2026-12-31).
- 2026-09-28 (overnight assumption): Robux prices show Roblox's own Robux glyph (U+E002) inside
  the price text (it renders in Fredoka One and takes the text's colour), never our own icon.
- 2026-09-28 (overnight assumption): the match settle. A team's gap uses the other side's
  average division (Unranked counts as Bronze I); in a team match the most experienced loser
  must have played 5 real matches for the winner's free case, a loser who already gave 3
  cases today blocks it, and the case counts against every losing account; today's first-win
  XP boost is used only by a win that gives XP; the first win's Rare Case is rolled at settle
  and shown as a reveal instead of a case chip; a player who leaves after the one-minute mark
  counts a real loss, and the pots of one who leaves before it add to the short-match total;
  solo pots get the VIP and Money Party boosts (ECONOMY 3.5, "everything earned in play") under
  the solo cap. PC opponents are recognised when the engine marks them (none exist yet).
- 2026-09-28 (overnight assumption): items and counters. If PolicyService never answers, that
  player is treated as restricted for the session (cases already owned still open); a Mythic or
  Secret unboxing is announced 6 s after the roll so the banner never spoils the opener's reel;
  every Reyes (the first and later ones) is announced in every server; banners use usernames;
  copies-in-existence counts show nothing until the first read; a Limited copy number taken
  for a purchase that then fails is burned (a gap in the numbers), never reused.
- 2026-09-28 (overnight assumption): Robux. A Founder's Cue receipt that cannot be granted
  (sold out, ended, already owned, counter down) stays NotProcessedYet and is logged, never
  swapped for money; a pass bought in game counts once UserOwnsGamePassAsync confirms it (three
  tries, 5 s apart; Studio trusts the purchase event); a VIP through the welcome offer sees the
  VIP pass as Owned; Robux prices are read once per server (not per-player regional prices);
  the Money Party shows the latest buyer's username. Playtime counts every second the save is
  loaded, AFK included; the code box waits 2 s between tries, and a malformed code answers
  "That code doesn't exist".
- 2026-09-28 (overnight assumption): the menus. A full menu (Shop, Inventory, Rewards, Trade)
  is the same kind of screen as the roadmap and reuses its slight dim; a tap on the dim closes
  it; one menu at a time; all close when a match starts. On a phone the panel takes the whole
  screen with its title in Roblox's top-bar row, and the tabs share that row when they fit. The
  Shop and Inventory show a money pill in their header, and money earned inside a menu flies to
  that pill. Gamepad: the column's tiles are never selectable (a selected button would take the
  stick from walking); in the hub the D-pad opens them (up Shop, right Inventory, down Rewards,
  left Trade) and each tile shows its D-pad glyph while a gamepad is in use.
- 2026-09-28 (overnight assumption): the Inventory. The detail panel always shows a cue (the
  first on open) and each open resets the filter to All; Sell asks first from Epic up, Sell all
  duplicates always asks; Exclusive, Unique and Classic show a padlock and "Can't be sold";
  NEW tags clear when the player leaves the Cues tab; the tabs carry their own red dots (new
  cues, unopened cases, a claimable Index row).
- 2026-09-28 (overnight assumption): the case opening. The reel is drawn from the true odds (a
  Standard reel is mostly grey and green); the prize sits at slot 34 of 40 and lands at a random
  point on its card; 4.2 s spin, 6 s for Mythic and Secret with the build-up starting 1.8 s
  before the stop; rays from Epic, confetti from Legendary; tapping outside the card does
  nothing (X, Done, B close it); Fast Open's grid puts the rarest card last and chooses it, and
  has no Sell. The first win's reveal plays in place of the result screen's cards, then the
  result and NEW RANK! follow. The backdrop over a menu is dark enough to hide the menu's title.
- 2026-09-28 (overnight assumption): the Shop. The VIP line reads "Same case odds as everyone";
  the Standard Case says "Any rarity can drop"; Buy 10 carries a "Pay for 9" sticker; there is
  no confirm before buying cases with money (buttons fade while a request is out); a Fast Open
  owner's "Open now" after Buy 10 opens all ten; the Starter Pack stays listed as Owned until
  its window ends; the first-purchase double shows as a ribbon plus an x2 pill per pack (the
  amounts stay at their base values); pack names Handful ... Fortune from ECONOMY 11.1.
- 2026-09-28 (overnight assumption): Rewards and Trade. The seven day tiles are a 4 + 3 grid
  (day 7 double-wide) so they fit a phone; the reminder names the best part of tomorrow's
  reward ("your Rare Case and more!") and says "Your daily reward is ready!" while today's is
  unclaimed; the toast shows at the bottom middle when Roblox's menu opens or the window loses
  focus, at most once every 2 minutes; a playtime gift shows Claim from the client's estimate;
  a code's answer shows under the box (above a phone keyboard). Trade lists everyone else in
  the server with a grey Trade button that says "Trading is coming soon!".
- 2026-09-28 (overnight assumption): the existing screens. A boost of +100% or more reads as a
  multiplier ("ROOKIE x2"), a smaller one as a percent ("VIP +50%"); boost colours Rookie
  green, First win gold, Streak red, VIP rainbow; "+0 XP" is white; NEW RANK! stays 5 s; the
  column shows while a case or cue flies to it; the ROOKIE pill hangs under the XP bar's right
  end; VIP names get a rainbow sweep now and then; chat lines for unboxings and Reyes post at
  once, even during a match. Rank cues count in the copies in existence too.
- 2026-09-28 (overnight assumption, from the audit): a Robux receipt is checked again when it
  arrives, since a client can open any product's purchase box itself. A VIP offer bought when
  already VIP or outside its windows, a second Starter Pack, and a Founder's Cue that sold
  out, ended or is already owned pay money instead, at the first pack's rate (Robux x 900 / 49:
  VIP offer $5,491, Starter Pack $1,451, Founder's $27,532), logged; nobody pays for nothing.
  This replaces the earlier line that left an ungrantable Founder's receipt unprocessed. The
  offer windows and a Limited's end get 10 minutes of grace at receipt time. A paid Money
  Party always adds its full 15 minutes (the one-hour cap only stops the prompt). A pass
  bought in game counts at once from the server's purchase event.
- 2026-09-28 (overnight assumption, from the audit): a Limited copy number belongs to the
  player it was handed to (the counter remembers who got which), so a retry or a rejoin gets
  the same number and leaving mid-purchase wastes none. Case sales are capped at 50% off
  (`Config.Cases.MaxSalePercent`): past about 61%, buying, opening and selling back made money.
- 2026-09-28 (overnight assumption, from the audit): the anti-farm table of today's opponents
  keeps 300 accounts (was 50); past that, a new account reads as the worst count (floor pay,
  no free case), so meeting many accounts never switches anti-farm off.
- 2026-09-28 (overnight assumption, from the audit): client. An open still waiting for the
  server can be closed after 3 s ("Still opening... Tap to close"); a cue that lands after that
  shows "Your cue is in your Inventory." The case reel closes when a match starts. The Rewards
  "!" for a complete Index row now shows a line in Rewards with an Open Index button (the
  row is claimed in Inventory > Index). Menus and the reel's backdrop are Modal, so shift
  lock never traps the cursor. The unbox banner waits 9 s, past the longest reel.
- 2026-09-28: Abilities stay and come in the release, reworked as **ultimates**: one comeback
  bar filled by the same rules for everyone (little for your own runs, a lot for trickshots and
  for falling behind), used about once a match, activated before the shot with a short
  cutscene, acting on the balls to help the user rather than sabotage. Replaces the cooldown
  design (2026-09-20) and the "not in the release" call (2026-09-26). The designer wants a
  trump card that levels the field when someone is down a lot.
- 2026-09-28 (designer): the left column's blue candy tiles are gone; each button is just its
  icon, bigger (78 px slots on a computer, 52 on a phone), with its word across the icon's
  lower edge.
- 2026-09-28 (designer, replaces the overnight "[VIP] after the rank tag" and "a rainbow sweep
  now and then"): in chat a VIP's line reads "[VIP] [GOLD] Name": [VIP] first, in the rainbow,
  then the rank tag, and the name in Roblox's own colour. Over the head a VIP's name is the
  house rainbow with its colours drifting calmly (one loop in 8 s).
- 2026-09-28 (designer): Exclusive cues never trade, the VIP and Starter cues included (they
  were tradable); Unique cues trade.
- 2026-09-28 (designer): the Index overhaul. A cue never found is a "?" card; tapping any card
  shows its name and the cue turning in 3D beside the list, black until found, in its real
  look once found.
- 2026-09-28 (designer asked for "some extra money" for every new cue; the amounts are this
  session's call, tune freely): finder's money, paid once per cue the first time it enters
  the Index: Common $50, Uncommon $100, Rare $250, Epic $750, Legendary $2,500, Mythic
  $10,000, Secret $50,000, Exclusive $500, Unique $1,000. Shown as "NEW! +$250" on a case
  prize (the money flies from it), as a banner for any other source. Open for the trading
  session: whether a cue got by trade pays it (suggestion: no).
- 2026-09-28 (designer, replaces the overnight "a title for every row"): the Index rows'
  "Collector" titles are dropped as adding nothing. Rows pay money up to Epic; Legendary,
  Mythic and Secret rows now pay nothing (this session's call: money there was already ruled
  out as rewarding luck; the designer can add some). Old saves keep the titles, unlisted.
- 2026-09-28 (designer): the Cues tab's rarity filter chips are replaced by one sort button
  (Rarest first as the default, Common first, Most copies; Name A-Z added as useful). The
  chosen order lasts while the player stays in the server (this session's call).
- 2026-09-28 (designer): sorting by rarity puts Exclusive between Epic and Legendary (it was
  above Secret); Unique stays on top. The Index keeps its rows in the same order as before.
- 2026-09-28 (designer): hovering anything pressable makes it sway gently (a small dance, not
  fast or slow: about 3 degrees, 1.4 s a rock); on the rank HUD only the badge shakes. Touch
  has no hover, so taps never start it (this session's call).
- 2026-09-28 (designer, ultimates interview): ults are core gameplay: both players should use
  their ult in 80%+ of matches (run-outs left out). The bar fills by the same rules for
  everyone (section 5 of the ultimates brief: own balls +8/+6/+5/+4 then +2, nice shot +20,
  opponent's ball +8 plus 7 per ball behind, +15 per legal turn end, +6 per opponent turn end,
  turn-end fill capped at 50, Classic x1.3, x0.3 after the first ult, at most 2).
- 2026-09-28 (designer): ults are on by default everywhere (public tables, the global queue,
  arenas, vs PC); solo gets a free Practice ult. This replaces "public tables play Classic
  with no abilities" (2026-09-27). The global queue alone offers Ults: On / Off (two pools).
- 2026-09-28 (designer): paid ult spins override ECONOMY 11.7: spins for Robux and money,
  Lucky Spins for Robux, odds always shown, pity kept, PolicyService-restricted players blocked
  from paying. Legendary 1 in 150, Mythic 1 in 1,000. Slots UBG style (3; slots 2 and 3 are
  passes at 59 and 99 R$). Robux prices 15/50/100/449, Lucky 49 and 3 for 129.
- 2026-09-28 (designer): the power ladder: higher rarities are cooler and stronger (Common
  about 1/3 of a ball per use up to Legendary/Mythic a guaranteed ball plus 1-2, 3 at most).
- 2026-09-28 (overnight assumption): a teammate's ball gives +2 of a bar; the opponent's
  match bar shows a small ult icon that lights when their ult is ready (fair, visible
  information).
- 2026-09-28 (overnight assumption): ult_ready (an 8.2 s jingle) plays 3 s then fades over
  0.8 s so it never talks over the shot (`Config.Ults.Audio.Ready.MaxSeconds`, 0 = whole).
- 2026-09-28 (overnight assumption): the save keeps the three slots as a gapless array of
  strings ("" = empty) and the locks as three booleans, because ProfileStore takes no arrays
  with holes.
- 2026-09-28 (overnight assumption): Mythic's aura on the spin screen is red-black with
  crackling arcs (the brief's colours), unlike its pastel card shimmer.
- 2026-09-28 (overnight assumption): money spins cost $1,750 each with no bulk discount, about
  2.4 hours of Classic play, so Robux stays the cheap route.
- 2026-09-28 (overnight assumption, from the fuller model): own-ball fill raised to
  +10/+8/+6/+5 then +3 and the after-first-ult rate lowered to x0.25, so "both players use
  an ult" holds with room (worst 85%, was 81%) and second ults stay under 2%. A run of 7 gives
  +38 (+49 in Classic), still half a bar.
- 2026-09-28: NEW RANK! now dims the screen behind it (designer: it overlapped the match
  results awkwardly). Black at 0.5 transparency, fading with the popup. It is two screens plus
  400 px, centred, so no edge shows on any device. It is the popup's own backdrop inside PoolHud,
  not a separate ScreenGui, so the money HUD and flying chips stay bright above it.
- 2026-09-28: The ult cutscene's avatar stands upright in its own window inside the tilted band
  (a ViewportFrame neither rotates nor clips under a rotated frame), framed to include a hat.
- 2026-09-28 (overnight assumption): In a No-ults global search, the 30 s offer's Yes moves
  only this search into the Ults On pool (it keeps its waiting time); the saved toggle stays
  Off. No hides the offer for the rest of that search. The Ults toggle is hidden, and refused
  by the server, while a search runs. The server takes a Yes up to 1 s early (clock drift).
  "Play another" from an arena stays in the arena's pool.
- 2026-09-28 (overnight assumption): A restricted player (PolicyService: no paid random items)
  cannot buy spins with Robux or money, but can use spins and Lucky Spins they already hold or
  get free (starter, daily, rank-ups, codes). While the spin screen is hidden
  (`Config.Ults.ScreenLive = false`), spin requests answer NotLive.
- 2026-09-28 (overnight assumption): Rank-up spins are paid on reaching a tier's division I
  (ECONOMY 11.7's table); the day's last playtime gift adds its spin to the gift rather than
  replacing it; an ult icon also shows beside a teammate on your own side; a difficulty the
  fill table does not list gets x1.
- 2026-09-28 (overnight assumption): The spin screen: gamepad X opens Ults in the hub (the
  D-pad's four directions are taken; X is the ult button in a match); Robux is the default buy
  mode, the R$/$ choice kept for the session; the free-spin reminder only in the leave toast,
  and only while the screen is live; while open the HUD, RankHud, touch controls and walking
  are put away and come back exactly as they were; closing stops a running Auto Spin; each
  slot card is one button (select or buy) with its own lock button; the code box sits in the
  odds column under the pity note; the room sits at (0, 3000, 40000) only while open; the
  Mythic name shimmers pastel while its aura is red-black; the Auto Spin "Use Lucky Spins"
  switch shows only for a player who holds some and is not restricted.
- 2026-09-28: A Lucky Spin never lands a Common (audit): its odds only move to Uncommon or
  better, and while no such ult is built Lucky Spins and their products are refused
  ("LuckyClosed"). Solo Practice ult shots pay no money and count no stats. Lobby tables can
  no longer turn ults off (SetAbilities refused); only the No-ults arena plays without.
- 2026-09-28: Ults are called Abilities everywhere players see them (the designer: 'Ult doesn't
  look right'); code names keep 'Ult'; the promo code is ABILITIES.
- 2026-09-28: The spin screen's backdrop is the real world where the player stands (the
  designer): the avatar clone stands in place, the camera looks from the player's own camera
  side (the next clear side round if a wall is in the way), and every player's character and
  name plate is hidden on that client while it is open. The dark room and its swirl are gone.
- 2026-09-28: The code box sits on its own, centred between the third slot card and SPIN (the
  designer); with no room there (narrow screens) it goes back under the odds, and on a phone it
  stays in the Odds popup (overnight assumption: the phone layout has no free space for it).
- 2026-09-28: The cutscene panel is the kit's white with a thick line in the ability's rarity
  colour, a soft glow of it and speed lines in it (the designer: no dark background); the
  avatar's bust fades out at the bottom so it never ends in a hard line.
- 2026-09-28: Magnet buffed (the designer: a way bigger radius, the ball visibly slowed and
  pulled in, a magnet look on each ball it hits). The zone is 7.5 ball widths round each mouth
  (was 3); inside it a moving ball heading within 60 degrees of the pocket is braked or pulled
  toward 18 in/s and curved in by the exact jaw trace (a clean pot is never turned). Measured:
  misses within 2 widths 100% (was 88% / 28%), 2.5-4 widths 97% (was 0%), direct pots 100%,
  about +0.46 of a ball per use for an average shooter (+0.6 or more for weaker aim), well
  over the ladder's Common target (1/3); the designer's call. Each of the shooter's balls
  charges when hit (a zap, sparks, red and blue rings); the pull streams dust into the pocket
  and draws a vortex of motes into it.
- 2026-09-28: The cutscene is half as long, 0.8 s (was 1.6 s; every step of its timeline
  halved), and the ability's own effect arms 0.1 s after it (was 1.0 s): the designer found
  the wait from pressing to seeing the effect too long. The shot clock pause is now 0.9 s.
- 2026-09-29 (assumption): the opponent's equipped ability icon shows on their top-bar badge before they use it (the brief lists the opponent's ready icon); easy to hide if the designer prefers.
- 2026-09-29 (assumption): Magnet's field lines draw in a deeper flat blue (45,115,240) than the
  reference's #7BA3D6: the reference's blue washed out to near white on the lit green cloth.
  Same hue, just deeper; the designer may want it lighter.
- 2026-09-29 (assumption): Magnet's drop shockwave spreads at rail-top height, not on the cloth:
  a ring centred on a pocket is mostly behind the rails at cloth height.
- 2026-09-29 (assumption): Eagle's Eye's harness aim aid is 0.15 degrees (an armed shooter's aim
  error shrinks to at most that); it lands Eagle's Eye at +0.38 to +0.43 balls per use at skill
  2, on the Common row, so the path is drawn in full (no MaxRails).
- 2026-09-29: Super Bounce: the first ball of yours the cue ball hits catches the bounce too
  (never the 8 or the opponent's): springier cushions and lower cloth losses for 8 s, and a
  cushion hit within 6 in of a pocket's rim boings it into that pocket. The designer chose it
  after the cue ball alone measured about +0.05 balls a use (the random knocks help both sides
  alike). (assumption) the jaw boing: a ball bouncing at random for even 30 s almost never
  found a pocket in our physics, so without it the catch added only +0.03 to +0.10. Measured
  +0.27 / +0.37 to +0.39 / +0.28 to +0.32 at skills 1 / 2 / 3 against the Common 0.33.
- 2026-09-29 (assumption): Ghost's worth is measured on the tables where it changes the
  shooter's best shot (`tools/ult_value.luau --useful`), since a player reaches for it only
  then; on every table it measures about 0 because an open pot is nearly always there. On
  useful tables it is +0.25 / +0.11 / +0.02 balls a use at skills 1 / 2 / 3, under the
  Uncommon 0.5; left as built for the balance pass (step 16), which can buff it or move it
  down a row.
- 2026-09-29 (assumption): Heat Seeker plans its path (A* on a 1-inch grid, once at the strike)
  and flies it like a missile: a 2-inch minimum turn radius at any speed and a 35 to 160 in/s
  speed band until its first contact (a full-power shot is slowed to cruise). A fixed turn
  rate and local dodging reached the locked ball too rarely (84-87%); this reaches 95%.
- 2026-09-29 (assumption): Heat Seeker's direct-aim cut correction is capped at 20 degrees
  (+0.34 balls a use at skill 2); it saturates near +0.38, under the Uncommon 0.5. Left for the
  balance pass (step 16) with Ghost.
- 2026-09-29 (assumption): Rewind measured +0.16 / +0.19 / +0.20 balls a use at skills 1/2/3
  (careless) against the Rare 1.0; the harness counts only the shot, so it misses the kept turn
  and the erased foul. Left for the balance pass (step 16), which decides the whole-turn measure.
- 2026-09-29 (assumption): Rewind's redo with ball in hand keeps the usual time to move the cue
  ball; the redo's 10 s is the shot clock after it. The HUD hides the clock during the rewind
  moment and shows SECOND CHANCE: 10s under it for the redo turn.
- 2026-09-29 (assumption): Rewind's armed look is a flat backward dial round the cue ball
  (not in the brief) that stays on the cue ball's start spot through the shot, with a ghost of
  the cue ball, so everyone sees where the table will come back to. The table flies back at 3x
  (slower shots) up to 1.7 s, so a long shot rewinds faster. The sounds are library clips (no
  audio upload used).
- 2026-09-29 (assumption): Time Stop ships at the measured worth (+0.13 to +0.37 per shot)
  under the Rare 1.0 band; like Rewind, the harness counts only the shot and plays the second
  strike as a plain shot from the frozen spot, so the balance pass (step 16) decides.
- 2026-09-29 (assumption): in stopped time the shooter aims with the normal controls and a
  hint pill (TIME STOPPED · STRIKE THE CUE BALL AGAIN); the shot clock and ability pill are
  hidden. The server streams no aims in Frozen, so watchers see the struck cue ball but not
  the cue before it.
- 2026-09-29 (assumption): Time Stop's look adds an armed violet bubble on the cue ball and a
  clock face on the cloth whose hand sweeps once round the 5 s; the big bubble is a plain
  ForceField lens (its pattern only while small). The sounds are library clips (no audio
  upload used).
- 2026-09-29 (assumption): Chain Lightning's numbers go past the brief's starting ones (15
  degrees of steer, not 8; 4 jumps, not 3; a 20 in reach, the cap; a push that rolls 3x the
  distance to the pocket): the brief's measured about +0.6 net a use, these +1.1, the bottom of
  the Epic band. The chain hops from ball to ball (each jump's reach from the last ball struck),
  a push aims at the closest pocket with a clear line in, and the charged ball's own count does
  not use up one of the 3-of-yours cap. The balance pass (step 16) decides.
- 2026-09-29 (assumption): Chain Lightning's look adds a bolt striking down onto the charged
  ball and a deep blue pool on the cloth under each glowing ball (the reference's blue ground,
  so the white arcs read on the green cloth); jump bolts stutter on three times. The sounds are
  library clips (no audio upload used).
- 2026-09-29 (assumption): Portals' worth measures +0.3 to +0.4, far under Epic; the rule
  helps only the one shot and the harness counts one shot, so it is flagged for the balance
  pass (step 16) with a suggestion to keep the portals open for the whole turn. The harness's
  Portals planner redirects the object ball (A just past it on its line, B short of a pocket's
  mouth on the same heading).
- 2026-09-29 (assumption): a ball comes out of the exit portal's centre (not offset by where it
  crossed the entry), so every trip is the same; the pick ring shows at 1.3 ball widths (was 1)
  so the portals read as holes a ball fits through; each portal has a soft glow on the cloth.
  The sounds are library clips (no audio upload used).
- 2026-09-29 (assumption): Steel Ball guides the legal 8 into its called pocket when it is the
  first ball hit (the 8 counts as yours on that shot, as for Chain Lightning); a follow-up 8 is
  only ever lined up. Follow-ups are the first ball's group; the first ball's pocket passes over
  one another ball blocks the way into.
- 2026-09-29 (assumption): Steel Ball's "close" is a clean line with the opening within 36 in;
  a lined-up ball stops 8 in short. Its worth measures +1.0 to +1.2 (Legendary target 2.2): the
  harness counts one shot, so the line-up's value is unmeasured. Flagged for the balance pass,
  with the option of guiding every next ball in (about +2).
- 2026-09-29 (assumption): the guidance never scratches: the cue ball stops dead behind a
  lined-up ball and wherever the guidance gives up, and turns straight onto its path near a
  pocket.
- 2026-09-29 (assumption): the steel ball's black outline is a Highlight (an inverted-hull mesh
  draws solid in Roblox); the "nyo-ho" is a library two-note whistle call until a recorded one
  exists. The art director's review was acted on (darker shell with bold ink, two orange-gold
  ribbons, a looping path, the burst on the pot only).
- 2026-09-29 (assumption): Black Flash's blast reaches 20 in (the reach cap) and rolls a ball
  1.5x the way to its pocket (at most 40 in); its worth (about +1.2) is under Legendary 2.2 because the harness
  counts one shot, flagged for the balance pass. The cue ball bounces back 6 in, cut short
  before any pocket on its line. The hit-stop reuses the replay's `slow` event (0.15 s).
- 2026-09-29 (assumption): Black Flash's sounds are library clips (a bass impact, a glass
  shatter, an electric crackle), no upload. The art director's review was acted on: a pale
  high-contrast grade instead of a dark red one, fat bolts with a wide red Neon rim behind the
  Highlight outline, bigger shards, short arcs on the armed cue ball.
- 2026-09-29 (assumption): Black Hole opens at the middle of the cue ball and the first ball
  hit, catches for 2.5 s within 20 in (the cap; the opponent's within 10 in), drags each
  caught ball straight in with a 0.6 sideways swirl (dropped near a cushion or pocket) through
  every other ball (ghosted), and swallows it within 0.5 in; the cue ball is pushed 6 in away.
  Its worth (about +1.15) is under Mythic 2.6 because the harness counts one shot: flagged for
  the balance pass.
- 2026-09-29 (assumption): Black Hole's sounds are library clips (a hollow rumble drone, an
  orchestral suck swell, Time Stop's reversed whoosh, Portals' pop pitched down), no upload.
  The art director's review was acted on (lensed arcs, a smaller white-gold disk, a bigger flat
  horizon, a flowing second vortex layer, a punchier close). Its description no longer says
  "(not your opponent's)": the opponent's balls within half the reach go too (5.7).
- 2026-09-29 (assumption): Guangdong Tiger's tiger is hand-built in Blender (metaball parts
  baked to textures, rigid parts animated in code round joint markers), because no model
  generator or model download was reachable from this session. A generated or downloaded
  detailed tiger could replace it later without code changes (the same part and joint names).
- 2026-09-29 (assumption): Guangdong Tiger's slowed moment is 0.1 s of play over 0.7 s of wall
  time (a seventh speed), not "about 0.3 s at quarter speed": the tiger's leap and swipe need
  about 0.6 s, and the tiger runs on its own clock (wall time and `/slowmo`, never the slow).
  The cut balls leave the physics at once; the look keeps copies in place until the strike.
- 2026-09-29 (assumption): Guangdong Tiger's sounds are library clips (Pro Sound Effects' tiger
  roar and body impact pitched down, a sword-split slash played three times), no upload. Its
  worth (+1.03 to +1.16 careful) is under Mythic 2.6 and is flagged for the step 16 balance
  pass. The art director's two reviews (5/10, then 7/10) were acted on.
- 2026-09-29 (designer): the step 16 balance pass buffs the weak abilities instead of moving
  rarities. Ghost: from the first contact the cue ball passes every ball, the ball it hit passes
  the ones the cue ball did, and a ghost pulls that ball into a pocket it nearly misses (the
  designer's pick over leaving it situational or swapping it with Magnet). Rewind: two redos,
  each showing Eagle's Eye's full path. Time Stop: three strikes in stopped time. Portals: open
  for the shooter's whole turn. The Legendary and Mythic caps go up: Black Flash 4 of yours,
  Black Hole and the Tiger 4 of yours and 1 of theirs (the old "3 balls at most" is replaced).
- 2026-09-29 (designer): Portals keeps its buffs (whole turn, a 2 in capture circle, your
  balls steered up to 15 degrees toward a pocket on the way out) and is flagged: it measures
  0.42 a use, under the Rares, because the model shooter never reuses the kept portals.
  Playtests decide.
- 2026-09-29 (assumption): Heat Seeker's cut correction goes to 30 degrees (0.40 a use, above
  the Commons' mean) and Chain Lightning drops to three jumps (0.96, clear of the Legendaries'
  1.09-1.21). Worth in the catalog is now the measured value (the careful shooter's mean over
  three skills); the ladder is judged on each rarity's mean (0.37, 0.44, 0.50, 0.69, 1.15,
  1.31), with Magnet over Heat Seeker the one other inversion left.
- 2026-09-29 (assumption): full-screen ability effects (ScreenFx's layers, Eagle's Eye's
  vignette) draw to the very edge of a phone's screen (`ScreenInsets.None`), not the safe area:
  the default inset drew the vignette's edge as a hard box inside the screen. The ult cutscene's
  ScreenGui has the same default; it belongs to the ultimates work and is only flagged here.
- 2026-09-29 (assumption): a shot Rewind undoes pays no money and counts in no stats (its
  balls come back); a shooter who leaves or dies during a rewind gets the departure foul, as in
  Aiming (the redo was theirs), and a side emptied mid-shot ends the game instead of rewinding.
- 2026-09-29 (assumption): a ball resting on a kept portal at the strike is treated as just
  come out of it: it goes in only after it has left that circle.
- 2026-09-29 (assumption): a ball an ability removes (Black Flash, Black Hole, the Tiger) is
  never a NICE SHOT, even after a combo or a bank; balls a portal, Magnet or a push sends into a
  pocket still can be (a real pot).
- 2026-09-29 (assumption): a table's screen effects end once it no longer involves the player
  (their seat left, or out of watching range), checked every 0.5 s.
- 2026-09-29: the spin screen is live for everyone (`Config.Ults.ScreenLive = true`) with all
  13 abilities built; Chain Lightning, Steel Ball and Black Flash's one-line descriptions now
  say what they do (the brief's "ready for launch").
- 2026-09-30 (designer): solo practice uses the real ability bar and controls (G, a tap on the
  bar, gamepad X), always full and ready, instead of the small "Practice ability" button.
  Balls pocketed with a practice ability pay no money, now including the redos a practice
  Rewind gives; real matches still pay for ability pots (the designer chose solo only).
- 2026-09-30 (designer): physics and aiming tuned after "the game is too easy". The power
  bar tops out at 25 mph (was 30; pros average about 24 mph on the break), rolling friction
  0.0125 (was 0.010, still inside the real 0.005-0.015 cloth range) so shots end 5-20% sooner,
  and the guideline's short lines are 7 in (were 8). Measured: a straight full-power break
  pots 0.60 balls (was 1.00), pots one 47% of the time (was 67%) and scratches 5.5% (was
  2%); no hop at full power any more. The camera's pull-out line moved to 1.0 table length
  to stay at about 35% of the bar.
- 2026-09-30 (designer): every admin, dev and testing command is for the designer's account
  (Painicane, user id 544959133) alone, in Studio and live, now and for any command added
  later. Other players, Studio collaborators and a group owner get nothing; money, rank and
  cues come only from playing or from Robux. `DevCommands` no longer lets anyone in Studio or
  the owning group's owner in (`Config.Debug.Commands.GroupRank` removed); the Studio-only
  `DevCommandsQA` test hook, a server script, can still run a command for a test player.
- 2026-09-30 (designer): solo practice abilities work on the break too. `/abilitysetup <id>`
  only puts that ability in your selected slot (no table, no match) and works for the
  designer's account alone (`Config.Debug.Commands.UserIds`), in Studio and live; the racked
  layouts (`Config.Ults.Setups`) are gone. Magnet pulls only the first ball the cue ball hits
  (a cluster by a pocket let one shot pull about five in), and its pocket zone, field lines
  and aiming rings are 30% smaller (5.25 ball widths, was 7.5). Measured worth 0.35 a use
  (was 0.48 on the new physics), level with the other Commons.
- 2026-09-30: Magnet's armed look rides the rolling cue ball and passes to the first ball hit
  (lines and sparks at contact), so the player sees which ball got the pull. The giving
  commands (ability, cues, cases, spins, money, rank, xp) are the designer's alone and take a
  player name to give to someone else in the server (designer request).
- 2026-09-30 (designer): Portals is now Rare and Time Stop Epic (they swapped rarities). Their
  worths are unchanged (Portals 0.42, Time Stop 0.47), so Time Stop pulls the Epic mean down and
  Portals sits beside Rewind; revisit when each is reviewed.
- 2026-09-30 (designer): Magnet no longer draws on the balls: the red and blue pole caps and
  the red and blue rings circling the armed cue ball and the hit ball are gone. The blue field
  round the ball, the hand-off, the charge burst, the pull lines and the pocket effects stay.
- 2026-09-30 (designer): Eagle's Eye shows its gold path only once the player starts pulling
  the cue back (it used to show while aiming, at the last shot's power), and its icon is a
  hunter's eye (a big cat's amber slit-pupil eye with a heavy brow) instead of an eagle.
- 2026-09-30 (designer, with a close-up reference): the Eagle's Eye icon is "hunter eyes": one
  hooded human eye with a detailed sparkling green iris (an amber ring round the pupil) and a
  low heavy brow drawn hair by hair, replacing the cat's eye made earlier the same day.
- 2026-09-30 (designer, with a bald eagle close-up): the Eagle's Eye icon goes back to an
  eagle, but only its eye: a glistening pale-gold iris with fine fibres and a big black pupil
  in a yellow ring, a black brow line cutting across its top for the hunter's glare. It
  replaces the hunter-eyes icon made earlier the same day.
- 2026-09-30 (designer): new clips for Black Flash's hit (only the first of the file's three
  hits plays), Steel Ball's activation and first hit (later contacts keep the short clank), and
  Time Stop's freeze (the swell before it stays). Black Flash launches the cue ball at 3x the
  power bar's speed (Config.Ults.BlackFlash.LaunchSpeedScale; spin scaled, the hop not). While
  the local shooter's Legendary or Mythic ability is armed, the power bar wears its skin
  (Config.UI.PowerSkins): Black Flash lightning, Steel Ball green with the steel ball, Black
  Hole deep space with the hole, Guangdong Tiger tiger skin.
- 2026-09-30 (designer): Black Flash's blast pushes balls half as far (NudgeShare 1.5 -> 0.75,
  NudgeMaxInches 40 -> 20); its measured worth fell to 0.51 / 0.68 / 0.77 net (was 1.29 / 1.47
  / 1.58), under the Epic mean, flagged for the designer. The shattered ball's pieces stay on
  the cloth 5 s longer (ShardSeconds 6.1) and settle there.
- 2026-09-30 (designer): Black Flash's blast reach scales with the shot's power: RadiusInches x
  (0.2 + 0.8 x power), 20 in at full, 6.4 in at 15%, 4 in at the softest (RadiusMinShare 0.2),
  so the shooter chooses power when opponent balls are near. The shot's power rides in the
  overrides (ShotPower, set by armEffect from the strike); the aiming ring follows the live pull
  and the shockwave ring grows to the shot's reach. Worth 0.48 / 0.63 / 0.72 net (was 0.51 /
  0.68 / 0.77). New icon: black lightning with a red outline and the cue ball with speed
  trails (not a shuriken). Fixed: a hard shot's flash could land in the replay's first frame
  and its look (shatter, ring, sound) was skipped.
- 2026-09-30 (designer): Time Stop gives one strike in stopped time, not three: the freeze
  still comes 1 s after the first contact, then the shooter has 8 s (FrozenSeconds, was 5) to
  line up and strike; time resumes 1 s (ResumeAfterStrikeSeconds, was 0.75) after the strike's
  cue ball touches something, or by itself at 8 s. Worth fell to 0.24 / 0.31 / 0.18 net (was
  0.65 / 0.42 / 0.34), flagged. The freeze sound is now 119468975319371 (the earlier id was
  the wrong clip).
- 2026-09-30 (designer): Time Stop's clock tells the time left: the hand starts at 12 (turned
  to the top of each viewer's own screen, following their camera) and goes once round
  clockwise in the 8 s, time resuming as it gets back to 12; after the strike it runs the rest
  of the way round over the 1 s before time resumes.
- 2026-09-30 (designer): TEMPORARY difficulty picker on the host's queue card: Classic,
  Difficult and Challenger side by side under the title, the picked one lit yellow, hidden
  while a global search runs. It sends the existing SetDifficulty (host only, before the game;
  the server resets it after each game). No rank lock (Roadmap 6.2) and the money multiplier
  stays off (Config.Economy.UseDifficultyMultiplier), so it cannot be used to earn more.
- 2026-09-29: One shared cue mesh for every cue skin (brief `docs/prompts/CUE_MESH_PROMPT.md`):
  a lathe of the drawn cue's own outline, 32 around, 3,456 triangles, one 1024 atlas; Classic
  is its first skin, drawn from the mesh in hand, for watched shooters, in the Index and on the
  back; the other 47 cues keep their bands. A skin is five paint-kit panels turned into four
  maps by `assets/cue/CueTextures.py`, never code.
- 2026-09-29: BackCue built (the designer's ask of 2026-09-28): everyone's equipped cue on
  their back, hidden in the same frame it is in their hands.
- 2026-09-29 (assumption): the UVs are conformal strips (u along the cue by the integral of
  ds/r, v round it), cut per zone, with the tip dome and the butt's end face as discs. The
  "no stretch" rule is measured area-weighted per strip (at most 1.05; worst 1.029), with the
  worst single face reported (1.105, limit 1.15): a lathe's steep tapers cannot be exactly
  unstretched face by face within the triangle budget.
- 2026-09-29 (assumption): the handle gets about 1.56 times the shaft's texel density (567
  against 363 px per stud) and 78% of the atlas, since the handle is what players look at.
- 2026-09-29 (assumption): the tip's dome uses a nickel radius ratio (0.4175/0.256 of the
  tip's radius); the bumper is 0.0875 studs round and 0.035 long, a skin colour; `cap_end` is
  the bumper's flat end face (about 87 px across in the atlas: enough for a badge, not text).
- 2026-09-29 (assumption): tip, ferrule and bumper are plain skin colours, not panels.
- 2026-09-29 (assumption): Classic's maps are drawn straight into the atlas with numpy in
  Blender's Python (the same 3D lookup as the panels), not a Cycles bake: exact, no lighting
  in the colour map, deterministic. The linen wrap's thread pitch (0.011 studs) is stylised to
  read at play distance.
- 2026-09-29 (assumption): `CueTemplate.py` runs on the Mac's own Python 3 with Pillow, since
  Blender's Python has no Pillow; nothing else in the package needs it.
- 2026-09-29 (assumption): a skin template is a Model in `ReplicatedStorage.CueSkins` named by
  the catalog id, with PrimaryPart `Cue` and its pivot at the tip. The swap between two mesh
  skins is left as a note in `CueStickBuilder.paintStick` plus a test guard, since there is only
  one mesh skin. A silhouette (the Index's cue not found yet) always uses the bands.
- 2026-09-29 (assumption): BackCue welds its own pooled sticks and repaints them only while
  detached, instead of `CueStickBuilder.wear()` (which repaints in place and would move a
  welded body). Its numbers, all in `Config.Cue.Back` (tune): tilt 36 degrees, 0.3 studs off
  the back, crossing 4.3 studs from the tip, the butt at least 0.8 studs off the floor (small
  bodies slide it up), +30 degrees while seated, only within 90 studs of the camera, a pool of
  12, refreshed every 0.3 s. Seated on the lobby's loungers and sofas the backrest hides the
  middle of the stick; the tip still shows over the shoulder and the butt clears the seat.
- 2026-09-29: **The Starter Cue can be traded** (designer). It is the one Exclusive cue that trades; VIP, rank and season cues still never trade, and it still can't be sold back. ECONOMY sections 6, 11.4 and 12 updated. The code (`Catalog.luau` Tradable, `tests/catalog_test.luau`'s "no Exclusive cue trades" check) changes in the cue import session, which replaces the catalog anyway.
- 2026-09-29: **Cue skins run: tooling calls** (assumptions, the designer reviews them with the pilot):
  - (assumption) OpenAI images use **gpt-image-2.5-sunburst**, the newest gpt-image on the key (Sunburst holds precise edits); spend is estimated at GPT Image 2's token rates (text in $5/M, image in $8/M, image out $30/M) in `assets/cue/concepts/openai_log.jsonl`.
  - (assumption) Every panel is painted in real cue coordinates by `assets/cue/CuePaint.py`, with same-size companion maps (height, roughness, metal, glow) that `CueTextures.py` now maps too. Procedural skins lay the shaft tile once (`"repeats": 1`), so the shaft has no visible repeat.
  - (assumption) The emissive map is a greyscale mask: Roblox lights the colour map by it, times EmissiveTint and EmissiveStrength (1 adds the colour once). To confirm on import.
  - (assumption) A design the plan calls "one stripe" sits on the **top** of the cue (the side you see in the hand and on the back), since the cue is only ever seen side-on in the Index as it spins.
  - (assumption) An aura that runs along the handle is a ParticleEmitter in a small invisible, massless, non-colliding Part welded along the cue (its Box or Cylinder shape sets where particles start; Cylinder with ShapeInOut Inward pulls them in); single-point effects use Attachments. Positions are in studs from the tip (the butt is 7).
  - (assumption) Epic "moving materials" use Roblox pieces that move: camera-facing sprites with RotSpeed and ZOffset laid over the painted art (Void's turning swirl), Beams with TextureSpeed, and pulsed EmissiveStrength/Color; Legendary and up may add up to 4 SurfaceAppearance frames.
  - (assumption) Rares keep the default pocket gust in the ball's colour (the plan lists only a tinted trail for them); today's placeholder Rare row that tints the gust blue goes.
  - (assumption) The concept sheets draw a longer butt sleeve than the mesh has; designs are mapped onto the mesh's own zones, since the cue's shape never changes.
  - (assumption) Previews: EEVEE, the Standard view on the concepts' charcoal, a CC0 studio HDRI (Poly Haven) for reflections only, and a modest bloom (threshold 0.85) standing in for Roblox's Lighting.Bloom. AgX and PBR Neutral were tried and washed the glows out.
  - (assumption) Git: the OpenAI takes (`skins/<id>/ai/`), skin files, sprites, crops, scripts, tier sheets and logs are committed; the procedural panels and all maps are rebuilt (`python3 tools/cue_skin.py <id> --paint --maps`) and ignored, which keeps the repo well under the 300 MB line.
- 2026-09-29: **Auras run the whole cue, tip to butt, from Rare up** (designer, after the pilot: "not enough aura or effects, it needs to be more prominent and around the entire cue"). Every Rare and up gets a glowing halo round its whole outline (a camera-facing Beam from tip to butt, wider than the cue, pulsing gently; it costs no particles), emitters that span the whole length instead of the handle, and stronger emissive. Epic and up add a second Beam of energy streaming along the cue (TextureSpeed). The particle budgets per second (Rare 20, Epic 35, Legendary+ 60) stay; Beams are extra.

- 2026-09-29: **Cue skins: pilot approved; match the concepts and vary the auras** (designer: "looks a lot better now yes, continue ... do not compromise on the visual detail of the cues and try to get it as close as possible to the reference images. try not to make every single aura the same halo effect"). Surfaces are drawn to the concept's detail (Roblox's emissive masks carry the glow). From Rare up, each aura is its own kind of effect (flame, energy, lightning, orbiting pieces, curved Beams, flipbook sprites), not the same halo on every cue; the particle budgets stay.
- 2026-09-29 (assumption): Inlaid points, lozenges and diamonds are centred 45 degrees off the top of the cue, so one faces a camera above and to the side (the Index, the sheets, a cue on a player's back) as in the concepts; a single stripe stays on the top.
- 2026-09-29 (assumption): **Uncommons keep one glowing ring** (the tier rule) even where a concept lights three (Gummy, Flare, Hornet); the others are painted in the ring's colour. The glowing ring sits in the ring zone, between the forearm and the wrap, where every U concept puts its brightest ring. Paint that looks luminous in a concept (Cosmo's nebula, Pixel's blocks) stays paint on Uncommons.
- 2026-09-29 (assumption): Venom, Lagoon and Splice (U2) draw no metal joint collar: their points run over the joint (painted like the forearm, with the hairline seam where the shaft screws on) and the chrome band sits in the ring zone before the glowing ring, as the concept shows.
- 2026-09-29 (assumption): An OpenAI panel's centrepiece (painted on the middle row, the top of the cue) may be turned 45 degrees round the cue (`roll_deg` in the skin file) so it faces the viewer like the inlays; used on Gilded, Cosmo and the Flare and Hornet sleeves.
- 2026-09-29 (assumption): **New aura pieces for the import**, all built from Roblox parts a small generic cue-VFX script drives (the report lists what `CueStickBuilder` needs): **Orbiters** (an Attachment pair a script flies along a helix round the cue, carrying a Trail, optionally a glowing head); **Arcs** (lightning: chains of short Beams whose Attachments a script re-jitters every 0.1-0.2 s, shown for part of each interval); **curved Beams** (CurveSize0/1 with the Attachments' Axis, turned by a script: `Twist`); **PointLights** with a scripted flicker. None of them count against the particle budgets; the budgets stay particles per second.
- 2026-09-29 (assumption): Rare aura sprites (flame flipbook, snowflake, bubble, ghost, leaves, blossom, petals, sprinkles, neon and lightning strips, candy stripe) are drawn by script (`CueVfx.py sprites <id>`), not bought, so they are deterministic and free.
- 2026-09-29 (assumption): **Epic moving materials are overlay Beams**: camera-facing Beams as wide as the cue, one per painted section (shaft, forearm, sleeve; never over the metal collar), lying just in front of it (ZOffset about its radius) with a mostly clear texture that scrolls (TextureSpeed), plus a pulse on EmissiveStrength. SurfaceAppearance maps can't move, and this keeps every Epic to Beams, pulses and particles as the brief allows. Epics whose plan lists a pocket finisher also tint the default gust (Style.Pocket.Colors) under their own layers.
- 2026-09-29 (assumption): Painted centrepieces on procedural Epics (Blood Moon's moons) face the same way as the OpenAI centrepieces turned by `roll_deg`, 45 degrees off the top (`FACE` in CuePaint), with a second one opposite so the back view shows one too.
- 2026-09-29 (assumption): **Legendary moving materials use SurfaceAppearance frames**: up to 4 pre-built SurfaceAppearances per skin (skin JSON `"frames": {"Count", "Keys"}`; frame n painted to `skins/<id>_f<n>/`, mapped to `textures/<id>_f<n>_*`, only the maps named in Keys kept), swapped by a script in a listed order at a set speed (`vfx.Moving.Frames`: Maps, FrameSeconds, Order). Most swap only the EmissiveMap (a glow that moves: Thunderstrike, Phoenix, Kraken, Seraph, Infernal); Chroma swaps ColorMap and EmissiveMap (hue-turned frames); Clockwork swaps every map (the gears turn).
- 2026-09-29 (assumption): Chroma's colour cycle is 4 hue-turned frames plus the flowing rainbow overlay, not a script tinting SurfaceAppearance.Color: a tint can only darken the maps, so it greyed the silver and the black, and the frames keep the painted rainbow bands and the neutral trim exact.
- 2026-09-29 (assumption): Legendaries paint OpenAI panels on the whole cue (shaft too) where the concept's detail can't be drawn by code; the painter trims letterboxed takes automatically, and a skin may give `zones_px` (the zone lines measured by hand) when a take draws a line too far off for the search. Clockwork stays procedural: the gears have to move frame by frame, which a generated picture can't do.
- 2026-09-29 (assumption): Big Legendary set pieces (Phoenix's wings and firebird, Kraken's tentacle, Infernal's smoke skull, Seraph's light column, Thunderstrike's bolts) are camera-facing flipbook particles drawn by script, not 3D parts: the tier has no custom 3D piece.
- 2026-09-29 (assumption): **Mythic pieces are scripted 3D, exported as MeshParts with a motion spec.** Each piece is modelled by script in headless Blender and exported per joint and material (OBJ in the Roblox cue frame, recentred on its bounding box) with `pieces/<id>/piece.json`: each part's Roblox Material, Color, Transparency, Reflectance, Joint and Offset, and each joint's Parent, Pivot and Motion list (Hinge / Sway about an axis, Spin, Bob; sine, snap or pulse waves). A small generic script animates the joints from that spec; `joint_matrix` in `CuePieces.py` is the reference maths. Materials are plain Roblox materials (Neon for glowing eyes, lenses and strips; ForceField for see-through energy), no SurfaceAppearance on pieces.
- 2026-09-29 (assumption): Mythic pieces stay about 9-21k triangles each (the dragon's body is the most), well inside a MeshPart's limit; the dragon head, fox mask and claw arm are candidates for a generated model later (listed in the report), the scripted versions are complete on their own.
- 2026-09-29 (assumption): Kitsune's nine tails are curved camera-facing Beams whose far ends a script sways (`Sway`), not 3D; Apex has three claws, not the concept's four, so each claw stays readable on a cue this thin.
- 2026-09-29 (assumption): **A glow that must hug a 3D piece's outline is a camera-facing particle, not geometry.** Eclipse's corona is particles centred on the black sphere, sized so the sprite's ring lands on the outline, with ZOffset equal to the sphere's radius so the whole ring draws in front of it from every angle. A ForceField shell round the sphere tinted the whole sphere gold, and a Neon ring only reads face-on.
- 2026-09-29 (assumption): The Starter and VIP cues take their VFX from plan.json, not from the extra effects drawn on their concept sheet (the Starter keeps only its blue ring and a blue wisp). The VIP's "ring that cycles rainbow" is a white emissive ring whose SurfaceAppearance.EmissiveTint a small script turns round the hue wheel (3 s), so only what glows cycles; its gold crown emblem sits on the butt face, the sleeve keeps the concept's gem.
- 2026-09-29 (assumption): The 8-ball emblem on the Starter's sleeve and the rank badges (a pool 8-ball in a shield) count as the game's icon, not text on a cue, since plan.json asks for them.
- 2026-09-29 (assumption): **The ten rank cues are one procedural design** (`rank_cue`), not ten OpenAI paint jobs, so they really are "one shared trophy design" that climbs in metal and colour; the concepts' chevrons, badges and gems are drawn by code. Pale chevrons (Platinum) are glossy enamel rather than metal, which reflects the room and reads dark. The rank badge on the butt face is a shield with the pool 8-ball, a crown from Expert up and gold rays on Reyes.
- 2026-09-29 (assumption): The Expert, Veteran and Master flames use a new white flame-tongue flipbook (`vfx/rank/energy_flame_4x4.png`) tinted per rank, not the shared `fire_4x4` (orange and drop-shaped: tinted violet it came out red, and small copies read as drops). Each also gets two runners (Orbiters) winding round the cue. Upper rank cues sit within the Epic budget (at most 35/s; they peak at 29.6/s on Reyes).
- 2026-09-30 (designer): **VFX upgrade pass, rarest first.** Many effects were underwhelming, flat or choppy. Every ball trail is brighter, clearer and longer (`tools/cue_trail_pass.py`: at least 0.9-1.2 s by tier, held nearly solid until the last half of its life, a bright core ribbon, Roblox `Trail.Brightness`); long-lived flipbooks use 64-frame Grid8x8 sheets (`CueVfx.flipbook8`) instead of 16 frames stretched over a second or more; per-skin upgrades live in `tools/cue_vfx_upgrades.py`, and the skin JSONs are now the source (the scratchpad generators are retired).
- 2026-09-30 (designer): **Set pieces become 3D.** Big camera-facing sprites (Phoenix wings, Kraken tentacles, the pocket creatures) look like flat cut-outs from most angles; they are rebuilt as scripted 3D pieces with particles only for glow and sparks. Creature models (dragon, fox, phoenix, kraken) are generated with a 3D generator from the concept art and cleaned, reduced and detail-baked in Blender; the brief's ban on the Blender MCP is lifted for this generation step (designer's choice "Generate + Blender").
- 2026-09-30 (assumption): The preview now places each effect object at its particles' centre so Blender sorts effects back to front like Roblox sorts particles (a black disc with ZOffset now covers the glow behind it, as it will in game).
- 2026-09-30 (designer): **Meshy for the creature models** (the designer bought a Meshy API plan and allowed the credits needed). The pipeline: OpenAI paints a clean, isolated render of the object from its concept crop (`assets/cue/models/refs/`), `tools/meshy_generate.py` turns it into a textured model (latest Meshy model, 2k geometry, 2k PBR maps, about 35 credits each; the key lives in the Keychain as MESHY_API_KEY), and `CuePieces.Kit.model` fits it to the cue in headless Blender: placed, cut where needed, reduced to under 20k triangles (a MeshPart's limit), its maps at 1024 px worn as a SurfaceAppearance with an emissive mask picked from the colour map (eyes). The Kitsune mask and the Celestial Dragon head are now generated models; their scripted versions stay as `*_scripted` builders only to render the old pocket flipbooks until the pocket creatures are 3D.
- 2026-09-30 (assumption): Generated models are committed as a compact copy (`source.glb` reduced to 150k triangles and `maps/` at 1024 px, about 10 MB each); the full downloads (25-75 MB) stay local and out of git (`assets/cue/models/.gitignore`), since the repo has no Git LFS and nothing past 1024 px reaches Roblox.
- 2026-09-30 (assumption): The Kitsune's nine foxfire tails now stream back from the mask's collar along the handle (fanned round it) instead of out past the butt, so they no longer cover the new mask's face.
- 2026-09-30 (assumption): **Pocket creatures are rising 3D pieces** (`vfx.Pocket.Piece`, built in the pocket frame by `CuePiecesPocket.py`): the piece's parts are cloned at the pocket, turned to face the camera, and over their life rise (Rise, studs above the pocket's mouth), grow (Scale), turn (Spin) and fade (Transparency), their joints moving meanwhile. The dragon, spirit fox and firebird are Meshy models glowing from within (an emissive mask from their own brightness, tinted per creature); the Kraken's tentacle is scripted. The firebird was generated twice: the first, from a straight front view, came out flat as a card (0.16 studs deep), so it was redone from a three-quarter view.
- 2026-09-30 (assumption): **Every trail follows the trail standard** (`tools/cue_trail_pass.py`), Uncommon included (life 0.8 s, Brightness 1.6). Warm trails (red is the seen colour's strongest channel, more than 80 above its blue) are nearly fully blended (LightEmission 0.2, the core too): Roblox keeps the felt behind a trail at 1 - alpha × (1 - LightEmission), so added orange or red over the blue felt read pink and white in the renders. Their glow comes from Brightness. Cool trails stay additive (textured ones as designed, plain ones 0.5). The core is the trail's lightest colour only 20% whiter at Brightness 2.2 (it was 45% and 3.0, which bleached every hue to white). Dark trails (Eclipse, Infernal, Kraken, Void, Grandmaster) are named in the pass, keeping Brightness 1 so their black reads.
- 2026-09-30 (assumption): **Infernal's horned skull is a generated 3D piece** (Meshy, `models/infernal_skull`), on top of the butt near its end, the face tipped back to glare past the butt at a player aiming from behind and the horns swept toward the tip (the concept has it on the handle's side; on top it faces the aiming camera and the 50-degree stills). The same model, bust cut away, is the pocket finisher's rising skull in place of the flat smoke-skull flipbook, and that pocket drops the default swirl ribbons (`KeepRibbons: false`), which crossed in front of it. Only its eyes and magma cracks glow: glowing the whole skull washed its silver to copper.
- 2026-09-30 (assumption): **Clockwork's gears are a scripted 3D piece** (no generator needed: gears are exact geometry). Each gear is its own joint spinning about its axle (`Spin`), meshing gears sharing a tooth size and turning opposite ways at rates inverse to their radii so the teeth roll together; a Neon ring inlaid in each face keeps the brass reading as lit in dim light. Every pocket creature now drops the default swirl ribbons (`KeepRibbons: false`, set by `pocket_piece`): they crossed in front of the rising piece.
- 2026-09-30 (assumption): **Arcs need Radius 0.15 or more and many short segments.** At Radius 0.1 an arc lies on the cue's surface and hides inside it (Eclipse and Thunderstrike both had this); with few long segments and a big Jitter it reads as bent wire, so lightning uses about 20-26 segments with Jitter 0.06-0.11, WidthStuds 0.16-0.2 (the bolt strip's glow needs the width) and a saturated blue at Brightness 2.2-2.4 (brighter bleaches to white).
- 2026-09-30 (assumption): **The Epic auras are stronger inside the same budget** (35 particles a second): bigger particles that live longer, Orbiter ribbons (no particles) twice as wide and further out, haze layers, Arcs on Blood Moon. Epics still get no 3D piece and keep their pocket finishers only where `plan.json` lists them, so the Legendaries (3D pieces, their own pockets) stay clearly above them. The upgrade pass is idempotent (`grow` scales from each emitter's original size), so `tools/cue_vfx_upgrades.py` can be re-run safely.
- 2026-09-30 (designer): **Eclipse is space, not lightning.** "Eclipse should not have a yellow lightning effect, that's too lazy; it should look like space effects, orbital galaxy vibes with a glowing eclipse for the aura." The Arcs and gold fire are removed; the piece adds four tilted gold orbital rings (each with a travelling planet-bead) and an asteroid belt of ten tumbling rocks, the eclipse sphere grows from radius 0.28 to 0.36, and the VFX adds a turning spiral-galaxy sprite behind it, stars and nebula haze.
- 2026-09-30 (designer): **The generated creatures are rigged, animated holograms.** "They need to be rigged and have some animation like the old version where the wings flap, mouth opens, and look more like spiritual energy, not actual models, more like holograms." The Celestial Dragon head and pocket dragon, the Kitsune mask and pocket fox, the pocket firebird and the pocket skull are now skinned meshes: `Kit.model(..., bones=...)` weights each vertex to bones that are the piece's joints (weights are hierarchical: a bone takes its share of its parent's weight) and exports a skinned `.glb` (part spec `Skinned`, `Bones`, `Mesh`) in the Roblox cue frame. At runtime each Bone's `Transform = Rest^-1 * J_parent^-1 * J_bone * Rest`, J being the joint's motion (Hinge/Spin/Bob/Sway) as for moving parts. The hologram look is baked, no runtime cost: a SurfaceAppearance with AlphaMode Transparency whose ColorMap is the model's lightness tinted (alpha 0.04-0.32, horizontal scanlines baked in world height), an EmissiveMask glowing on the lines, edges and eyes, and a ForceField shell (a decimated 8k-triangle copy pushed out slightly) that shimmers. Each hologram piece is 27.5k triangles (19.5k model plus the shell). The pocket dragon is turned side-on (seen head-on it read as a column). (assumption) The Infernal butt skull stays solid obsidian (it is an ornament on the cue, not a spirit); the Phoenix cue wings and Kraken tentacles were already scripted animated energy and are unchanged.
- 2026-09-30 (designer): **Eclipse gets a giant eclipse aura** towards the back of the cue, its ring like the concept's: a black disc 3.6 studs across centred 4.6 studs along the cue (camera-facing, so a disc from every side, ZOffset behind the cue and its orbits), a razor-thin white-gold ring with fiery wisps, the galaxy moved behind it, and two huge gold orbits (3D) sweeping round the cue. The disc and ring never turn and their fades overlap exactly (a new particle every 2 s, fading over 1 s as the oldest fades out), so they hold steady. (assumption) Giant solar flares were tried on the rim and dropped (at that size they read as thick white tubes). Whether it blocks the view while aiming is settled below (the aura is off on the shooter's turn).
- 2026-09-30 (designer): **The aura sits behind the back and is off while shooting.** Worn on the back, the cue shows in front of the body and the aura behind it (never covering the avatar). On the player's turn to shoot the cue's aura is switched off so it doesn't distract; it comes back when the cue is on the back again. For the import session (CUE_SKINS_REPORT 6.3).
- 2026-09-30 (designer): **The upgrade pass covers the Rares, the Rank cues and the VIP Cue** ("finish the remaining rare cues and rank"; the Unique cues wait for later). Rares (at most 20 particles a second): bigger particles, ribbons of light winding round the cue (Orbiters, not particles) on most, faint haze layers, Plasma's arcs to the Arc standard (off the surface, finely jagged). Rank and VIP: bigger particles, wider glows, and the rank runners (Orbiters that were 0.04 wide and inside the cue's glow) made wide enough to see.
- 2026-09-30 (assumption): **A Rare's pocket gust is mostly in its own colours** (`Style.Pocket.Colors` from its trail and core, `ColorShare` 0.7). Rares still add no pocket layers of their own (the tier rule); the gust in the potted ball's colour read as unrelated to the cue (red swirls from a blue Frostbite).
- 2026-09-30 (assumption): **Gold, Platinum and Diamond get a tinted trail** in their metal (gold, ice-white, diamond blue) with the Rank length and core, in place of the shared white wisp, so the trail climbs with the rank as the aura does (Bronze and Silver keep the plain wisp). Rank budgets: Gold to Diamond at most 20 particles a second like a Rare, Veteran and up at most 35 like an Epic.
- 2026-09-30 (assumption): **The review file's Designer column is for the designer only.** The upgrade notes had been written there; they are moved into the Built column.
- 2026-09-30 (assumption): **Trail colours hold over the blue felt.** A deep red trail (green and blue under 30% of red: Candy, Blood Moon, Expert) is fully blended (LightEmission 0, Brightness 1.2, `deep_red` in `tools/cue_trail_pass.py`): at any additive share it read pink. A textured trail's core takes the texture's colour, not the white tint (Grandmaster, VIP gold; Master violet, its tint violet too): a white core drowned the texture. The new aura ribbons use the soft glowing band (`trail_soft`), fully additive: the thin wisp texture read as grey threads.
- 2026-09-30 (designer): **The Celestial Dragon is a whole spirit dragon coiling round the cue, the Kitsune gets a small running spirit fox.** "An animated spiritual dragon spiralling around the cue, not just a dragon head at the butt" (the concept's coiling dragon, head past the tip) and "a small kitsune model constantly running, smooth animations". The dragon's body is scripted (a coil with its own scale texture, a ForceField sheath, a Neon core and flame fins, skinned to a Spin root and seven body bones carrying a travelling wave) with the generated head moved onto its neck; the fox is a new Meshy model (from a side-view gallop reference, 35 credits) rigged for a gallop (front and hind legs half a stride apart, body rise and pitch, head and tails) and carried round the forearm by a Spin. (assumption) Both are aura: a joint can now be marked `Aura` in piece.json and the runtime hides it on the shooter's turn with the rest of the aura. The dragon's snout ends a few inches (about 0.35 studs) short of the tip, never past it (designer: first "not past the tip, a little past halfway", then "a little closer to the tip, a few inches back"); its head circles the shaft as it swims. The fox runs a circle round the forearm (paws toward the cue), the only path the joint motions give that never ends.
- 2026-09-30 (designer): **The Celestial Dragon moves like a live dragon.** "Move its head more and more spiralling animation, like it's a live dragon with more rigging and animation." The rig grows from 7 body bones to 16 joints: ten body bones carrying two travelling waves (sideways and outward, 2.0 s and 3.1 s), a Tail flick, a two-bone neck (Neck1, Neck2) under the Head, so the rearing, sway, nod and look add up; a roar every 4.8 s (head rears back, jaw gapes); the coil swims at 44°/s (was 32) and surges 0.06 studs along the cue. (assumption) The neck's rearing only ever lifts the head away from the cue (its hinges have a Base equal to their swing), as a full swing dipped the head into the cue; the head's closest approach to the tip is 0.22 studs (0.35 at rest). The spirit flames now ride all ten body bones and the neck at 1.2 a second each (the same total).
- 2026-09-30 (designer): **The Celestial Dragon swims back and forth along the cue.** "Slithers around back and forth from the cue from tip to butt and turns around, faster animation, more fluid and smooth." The fixed coil is replaced by a swimming loop: the dragon circles the cue three turns each way while it runs between the butt end and the tip end, turning round at each end, a lap every 10 s; its 4.5-stud body (30 spine bones) follows the path its head swam, with a quick body wave and a tail flick. (assumption) A new generic motion kind, `Path`, does this: a joint rides a looping track stored in `piece.json` `Paths` (`CuePieces.path_frame`, report 6.3); the runtime gets the same maths as the other motions. The loop runs on a larger radius going to the butt than coming back so the dragon never swims through itself; the snout stays at least 0.34 studs short of the tip. This supersedes the 16-joint coil entry above.
- 2026-09-30 (designer): **The cue tiers are the plan's** (`cue_skins_plan.html`): 62 cues, 47 case cues (8 Common, 9 Uncommon, 10 Rare, 9 Epic, 7 Legendary, 3 Mythic, 1 Secret), plus Starter and VIP, 10 Rank and 3 Unique. Every skin file already matched; the game's catalog still has the 30 placeholders and is fixed at import (report 6.1, now with the full tier table). **Classic is labelled Common but stays the free default cue**: everyone owns it, it drops from no case, and it cannot be traded or sold (so the cases drop 7 Commons).
- 2026-10-01 (designer): **The cue skins go straight onto `abilities`** (no import branch), and **the 30 placeholder case cues are removed** from every save (migration 3 -> 4: owned, NEW tags, Index finds; an equipped one becomes Classic), with no swap or refund.
- 2026-10-01 (designer): **Shop, case and inventory pictures are rendered** (`assets/cue/CuePreview.py --thumb`: the whole cue side-on with its surface and glow, the same framing for every cue); the Index keeps the live 3D cue.
- 2026-10-01 (assumption): **A skin's trail and pocket style live in its data row** (`skin:<CatalogId>` style keys over `Config.Effects.Styles.Default`), not as 58 hand-copied rows in Config; the tier rows stay as fallbacks.
- 2026-10-01 (assumption): **A cue's moving material (its Moving beams) counts as surface**, so it shows in the hands as well as on the back; only the Aura goes off on the shooter's turn. A cue in the hands (only seen while aiming) never shows its aura.
- 2026-10-01 (assumption): **Classic counts as found in the Index's Common row** (everyone owns it). A Common row reward already claimed under the old catalog stays claimed.
- 2026-10-01 (designer): **The full aura shows in the hands too** (replaces "no aura in the hands" and "aura off on the shooter's turn" of 2026-09-30/10-01), and on the back at full rate (no more half rate).
- 2026-10-01 (designer): **Bloom on in the lobby** (day Intensity 1, Size 24, Threshold 2.6; sunset 0.8/24/2.6): HDR effects (particle Brightness above about 3) bloom, the floor, balls, tables and UI do not (Threshold 1.1-1.8 made the balls glow).
- 2026-10-01 (designer): **Eclipse becomes a smaller glowing eclipse** near the butt (a black disc in a white-hot ring with a blazing gold corona) inside a violet space cloud with gold dust, stars and orbits; the giant black disc, its ring and wisps and the big galaxy are dropped.
- 2026-10-01 (designer): **Cue VFX are judged only in the real lobby lighting** (tools/vfx_lab.luau), never on the dark Blender preview, and visuals come before optimisation. Every Rare+ aura follows the **VFX v2 standard** (tools/cue_vfx_v2.py): a saturated smoke body layer (normal blend) that carries the colour on the cream floor, an additive HDR glow layer, crisp star/glint accents, and an outline (Aura.Highlight) on a 3D creature that must read through the cloud. Celestial Dragon, Kitsune and Eclipse are done first for review.
- 2026-10-01 (designer): **Every cue with an aura wears a thin outline and a faint tint of its colour** (a Highlight on the stick; its tier's colour unless the skin sets Aura.Outline), so it stands out on the bright lobby. Only the nearest cues' Highlights show (Config.CueSkins.Outline.MaxShown 14: Roblox draws 31 and a match's ball outlines use up to 15).
- 2026-10-01 (designer): **Every cue is 1.6x wider, the tip kept as it was** (butt 0.2 -> 0.32 studs; the first ~2 studs as slim as before), so a skin's art and the cue itself read next to a Roblox character. Done on the shared mesh, not by stretching in Roblox: every skin repainted on the new UVs (the AI panels resized, not re-bought: from the side the squeeze barely reads), effects moved out with the surface (`tools/cue_widen.py`), butt pieces refitted (Kitsune's mask and Infernal's skull bigger, Apex's claw grown 1.6x). A thicker cue tilts up to about a degree more to clear a side rail on shots across the table (visual only).
- 2026-10-01 (designer): **A switched cue appears only fully loaded.** Equipping a cue removes the old one from the back (and the hands) at once; the new one appears only when its textures, 3D piece and effects are downloaded, with its aura already full, so it reads as a different cue, never the old one being retextured. A cue is downloaded when it is picked in the inventory or won from a case, so Equip is usually instant; a slow download shows it after at most 6 s anyway.
- 2026-10-01 (designer): **No visible loading on a switched cue, on any device or graphics quality** (the first fix still showed the new cue white, then textured). A cue is revealed only after a hidden copy, drawn 99% see-through in front of the camera, has made the renderer load every texture. A first-time switch takes about 2-3 s with nothing on the back; picking the cue in the inventory first makes Equip instant. A texture that fails to download is fetched again before the cue shows. After 15 s the cue shows anyway.
- 2026-10-01 (designer): **A cue switch is an instant one-frame swap with no empty gap**, replacing "the old cue disappears at once": the old cue stays on the back and in the hands until the new one is fully loaded, then they swap in one frame. Roblox needs about 1.5-3 s to load a cue not used yet this session (no code can shorten that), so the swap happens that long after Equip; a cue picked in the inventory first, or used in the last minute, swaps at once.
- 2026-10-01 (designer): **A cue's pocket creature, pocket bursts and trail are loaded before it is played with** (they showed grey the first time): your own cue's at once, and everyone's at the tables near you while they sit there. A creature still not loaded when a ball drops is left out of that pocket rather than shown grey.
- 2026-10-01 (designer): **Nobody can fall out of the map.** A held shooter is let go only standing on the floor and clear of the table (after a match a player had dropped under the map), and anyone who still ends up 12 studs below the lobby floor is put straight back on the spawn mat.
- 2026-10-01 (designer): **A cue's aura stays on the cue as you walk**: every aura emitter moves with the cue except tiny specks, which drift off thinly, and orbiter ribbons shorten while the cue moves (the flames had smeared behind the player).
- 2026-10-01 (designer): **Kitsune and Celestial Dragon are calmer**: pulses and flickers about half as fast and smooth (no random flicker dips), sparkles fewer, slower and softer. **Kitsune's aura is a soft pastel pink** (was deep purple-magenta). Eclipse and Apex unchanged.
- 2026-10-01 (designer): **The aura outline is a thin, faint line in the rarity (or skin) colour with no tint over the cue**; a piece's own highlight (the dragon, the fox) is a soft edge. Black was considered; rarity colours stay.
- 2026-10-01 (designer): **Quieter auras in a match**: the shooter's cue runs its aura at its tier's share (Rare/Epic/Exclusive/Rank half, Legendary/Mythic/Secret a quarter); on your own turn every cue at your table does; a player waiting while someone else shoots keeps the full aura.
- 2026-10-01 (designer): **Ball trails are short and quick**: at most 0.45 s (the plain wisp is 0.34 s; special cues ran 0.8-1.2 s), ball sprites half as long-lived, a textured trail stretched once along its length rather than tiled. The trail's ends are now held level across the ball's path (on the rolling ball they turned with it, which made every trail look dashed).
- 2026-10-01 (designer): **Pocket finisher creatures stand out**: a dark outline, their colour tinted toward the skin's pocket colour, a fainter glassy shell, less glow and a dimmer pocket flash while one shows. A dark fill was tried and greyed the creature, so it is off.
- 2026-10-01 (designer): **Eclipse's pocket disc always faces the camera** (it stayed upright and squashed into an ellipse from the top-down view).
- 2026-10-01 (designer): **Kitsune and Celestial Dragon are barely there while quiet in a match**: their aura runs at 7% (`Config.CueSkins.Quiet.SkinShares`, a per-skin share in place of the tier's quarter).
- 2026-10-02 (designer): **The global queue's Abilities: On / Off toggle is gone** (and its "search with them on?" offer): every search plays with abilities on; a save still holding Off is ignored, and the server refuses the old toggle.
- 2026-10-02 (designer): **Difficult and Challenger unlock at Gold I** (Challenger was Diamond I). Below it the host card shows them greyed with "Requires Gold I+" under them; the server refuses them, and a waiting table whose new host is below Gold I goes back to Classic. The money multiplier stays off.
- 2026-10-02 (designer): **The host card's buttons are taller** (54 px, levels 40) to fill the room the Abilities toggle left, and **Join Global Queue is green** (was blue); Play solo stays green.
- 2026-10-02 (designer): **The host card's text is bigger too** (Config.Multiplayer.Style.QueueText: title 26, buttons 24, levels 22, status 18, small lines 15), not just its buttons.
- 2026-10-02 (designer): **On a phone the level words and "Requires Gold I+" fit their buttons**: the card measures them and gives the three words one shared size that fits (and the two notes another), never below 7 px; the card is wider (290, was 260) so they stay readable. A one-line kit text does not shrink by itself, which is why they overlapped.
- 2026-10-02 (designer): **Difficult pays 1.25x and Challenger 1.5x rank XP, and the host card says so** ("1.25x XP" / "1.5x XP" under the buttons). Ranking now passes the table's difficulty into the XP sum; until now every match had counted as Classic.
- 2026-10-02 (designer): **"Requires Gold I+" is one banner across the locked levels** (with a padlock, over the buttons' lower edge) instead of a tiny line under each button, and the XP lines are bigger (18 px).
- 2026-10-02 (designer): **On a phone the PULL bar moves further right** (8 px margin, and 35% of the safe area's right strip) so players stop launching by accident, and **touch aim drags turn 15% more** (TouchAimScale 1.15; mouse and gamepad unchanged).
- 2026-10-02 (designer): **Full-screen ability effects and the ult cutscene show only to the players seated at that table**; the 40-stud "standing nearby" spectator radius is gone (lobby players walking past saw them).
- 2026-10-02 (designer): **The called 8-ball pocket is marked for everyone in the match** (teammates and opponents, every mode), not only the shooter.
- 2026-10-02 (designer): **A jump shot's guideline shows its arc in the air** (Classic only): dots along every hop, live with the pull, a shadow line on the cloth under each, landing rings kept, and the aim line from where the ball settles.
- 2026-10-02 (designer): **Raised above the default angle, your own cue is 95% see-through with no aura on your screen** (Config.Cue.RaisedCueFade); everyone else still sees it whole.
- 2026-10-02 (designer): **The host card's "1.25x XP" / "1.5x XP" are blue outlined text** (the kit's button text in Blue, 20 px), so they read as a bonus.
- 2026-10-02 (designer): **The XP bonus lines are a brighter sky blue** (70, 205, 255; Config.Multiplayer.Style.QueueXpColor), brighter than the kit's Blue.
- 2026-10-02 (designer): **Play solo is blue**, like Play against PC (was green); Join Global Queue stays green.
- 2026-10-02 (designer): **Play solo has a grey person icon** (new PersonGrey, uploaded under the group) so it stands out on its blue button, like the robot on Play against PC.
- 2026-10-02 (designer): **Rank rework: XP only from winning.** Friends reached Gold I in a few hours (Rookie x2, first-win x2, cheap flat Bronze to Platinum). Now a win is 100 XP (x1.25 Difficult, x1.5 Challenger), a loss 0; the Rookie Boost, the first-win-of-the-day bonus, VIP's +50% XP and Classic's win fade are gone (only the win streak's +25% stays). The ladder is counted in wins: 1 win to Bronze I (Unranked until the first win), 2 more to Bronze II, one more each division to Platinum V, then a ramp sized for a 3 h a day, 50% player: Expert about 1 month, Veteran 2, Master 3.5, Grandmaster 6, Reyes about 9 (307,500 XP, 3,075 Classic wins). Every rank was reset (save v5); rewards already paid stay and the old peak is kept so nothing pays twice. Hosting Difficult and Challenger stays at Gold I (now about 17 hours of play). Cases, money and rank-reward amounts are next, after the shop research.
- 2026-10-02 (designer, Bots lane): **disguised bots wear real Roblox avatars** from random real user ids (accounts from 2020 on, never banned or blank) with a made-up username, each unique and never an existing username. They are not in Roblox's own Esc player list (the one hint); the custom in-server player list shows them. Replaces "never a real user's avatar, never pretend to be a real person" (lane file, GDD 14). The designer knows other games do this; it is their call.
- 2026-10-02 (designer, Bots lane): **lobby bots play each other** (replaces GDD 6 "PC never plays PC").
- 2026-10-02 (designer, Bots lane): the real player **always breaks** against any bot (the coin is shown, rigged; rematches too).
- 2026-10-02 (designer, Bots lane): a bot shot takes **2 to 4 s** (random, +2 s with ball in hand), the same at every rank; it lines up with small left-right adjustments. The ability cutscene is extra.
- 2026-10-02 (designer, Bots lane): **one skill level per tier**; the player's chance of beating the bot of their own rank: Bronze 90%, Silver 80, Gold 65, Platinum 57, Diamond 50, Expert 50, Veteran 45, Master 40, Grandmaster 35, Reyes 30 (Reyes misses about 2-3% of shots). Behind by 2+ balls it makes its shots more often: +5, +6, +7, +8, +9, +10, +8, +6, +4, +1.5 points. Misses are near misses, never wild.
- 2026-10-02 (designer, Bots lane): a bot's ability is random, weighted like a real spin; none Legendary or higher when the player is Gold or below. Bots never chat or emote (the tutorial bot's "AUGHHHH!" is the one exception). The opponent's aim line is never shown (like a person's).
- 2026-10-02 (designer, Bots lane): **Play against PC**: one robot from a Roblox catalog bundle (picked from screenshots), named "<Tier> Bot", always the player's own tier (Unranked: Bronze), table difficulty does not change it, Rematch accepted at once, works in private servers, pays the PC rows.
- 2026-10-02 (designer, Bots lane): **2v2/3v3 lobby tables**: bots never join by themselves; the host can press **Fill with PC** once their own side is full, filling the other team with PC robots at the team's average tier (replaces "PC can fill any seat"). The global queue's 2v2/3v3 gives a disguised all-bot team after 25 s at the real team's average rank.
- 2026-10-02 (designer, Bots lane): **global 1v1 fallback**: no real player after 10 s, a disguised bot of the player's own tier in a real arena (teleport and all); no rematch.
- 2026-10-02 (designer, Bots lane): **disguised wins** pay money, XP and the free case like a real match, with no win streak, stored as PC wins (never on the most-wins board). A disguised bot that forfeits gives a full disguised win even under the one-minute mark. Both tutorial games are real wins; the tutorial bot's early 8 pays in full.
- 2026-10-02 (designer, Bots lane): disguised lobby bot rematch: it waits for the player, answers 1-3 s later and accepts about 85% of the time.
- 2026-10-02 (designer, Bots lane): lobby bots start bot-vs-bot games only while at least 3 1v1 tables stay free; a real player stepping onto their pad makes them stop and walk off.
- 2026-10-02 (designer, Bots lane): bot names in a real-Roblox mix (`PixelPanda_482`, `itz_mikey77`, `xXShadowStrikeXx`, `coolkid2013`...).
- 2026-10-03 (designer, Economy lane): **save v6 is a full wipe** (only friends had played): every older save starts over as a new player's, keeping only its purchase receipt ids. This supersedes v5's rank-only reset.
- 2026-10-03 (designer, Economy lane): **money is x10** everywhere ($100 a ball, $500 a win, $150 a loss); boosts add (VIP, Money Party, the Starter hour, group +10%), so the Starter hour's 2x on top of VIP's gives x3.
- 2026-10-03 (designer, Economy lane): **Case Drops replace bought cases**: every real win rolls one of six cases with pity (Rare by the 10th, Epic by the 150th); Rare and up open on timers (1 h, 6 h, 24 h, 48 h); no case is sold for money. The first win's guaranteed Rare Case keeps its 1 h timer. Instant cases end the reveal on Open now / Later.
- 2026-10-03 (designer, Economy lane): **the restock shop**: new cases every 10 minutes, the same in every server, with a filler of 3 Mystery Cases for $14,700 and a Legendary Case 0.15% of the time (25 across every server).
- 2026-10-03 (designer, Economy lane): Legendary pulls are announced in the server; Mythic and Secret in every server.
- 2026-10-03 (designer, Economy lane): **group 675425213**: Join + Claim gives 3 Case Drops once, and +10% match money while a member. Six like codes (LIKES1K to LIKES100K) are switched on live with `/code on`. Invites with light checks (invite launch data, a brand-new save, any real win, at most 5 a month).
- 2026-10-03 (designer, Economy lane): **trading is in the release, open to anyone in the server** (no 25-win gate), cues and ready cases, never money; 50 trades of history.
- 2026-10-03 (designer, Economy lane): the hidden disguised-bot limit (20 disguised wins a UTC day, then PC pay and no drop) shows nothing to the player.
- 2026-10-03 (designer, Economy lane): **Grand Opening Cue** ($149,000, 14 days, numbered, placeholder colours) starts on a date the designer sets; no next Limited scheduled yet.
- 2026-10-03 (Economy lane): the login reward is claimed by itself on join on loop day 1; the streak freeze covers one missed day once a UTC week (Monday start); VIP's daily spin is added to each day's login claim; "any real match" for invites means any non-solo win (people, disguised bots, Play against PC).
- 2026-10-03 (Economy lane): a bot's Mythic+ cue is always a Mythic, never the Secret cue.
- 2026-10-03 (designer): **the Cutscenes lane is folded into the GUI lane**: one lane owns every screen and every reward moment (match result, the 8-ball Case Drop reveal, case opening, cue pulls, rank-up, spin reveals), so one style runs through all of them. The remaining lanes are GUI and Tutorial.
- 2026-10-03 (designer, GUI lane): the 1v1 match-result cutscene (winner standing with the cue, loser on the ground) plays at lobby tables and arenas, against people, disguised bots and PC; 2v2, 3v3 and Solo keep the result screen. A cutscene can be skipped once seen once.
- 2026-10-03 (designer, GUI lane): **near-misses on the case reel** about 1 roll in 5 on every case (paid too), the real odds unchanged; replaces ECONOMY 11.7's "no fake near-misses". Legendary, Mythic and Secret pulls get the gold beam, the deep-space sky and the red-white glitch blackout; sky effects are local for Rare and Epic and server-wide from Legendary.
- 2026-10-03 (designer, GUI lane): the 8-ball shows each climb while shaken; many drops at once are one shake and a row of triangles; a tap counts as a shake. A win's 8-ball shows after the result screen, through the popup queue.
- 2026-10-03 (designer, GUI lane): **release sale**: money packs 4-7, VIP and 10 Mystery Cases 30% off for 14 days from the Grand Opening Cue's start, as six separate sale products shown only in the window. Roblox Plus members get +10% match money.
- 2026-10-03 (designer, GUI lane): the like reward becomes a **favorite** reward ($10,000 + 1 Case Drop, reported by the client, once per player); the card still asks for a like with nothing tied to it. The invite reward goes to the inviter once ever.
- 2026-10-03 (designer, GUI lane): the first-leave gift is a Rare Case on its 1 h timer; "COME BACK TOMORROW" plays every time the window loses focus or the Roblox menu opens.
- 2026-10-03 (designer, GUI lane): Secret's colour is near-black with a red-white glitch shimmer; VIP drops the rainbow for gold with a crown mark (the rainbow is for deals).
- 2026-10-03 (designer, GUI lane): **global boards** Most wins vs players and Highest rank, as two lobby signs (top 10) and a player-list tab (top 50 and your place), stored in server-written OrderedDataStores (the one exception to "saves through the save layer": a public ranking, never a save). No nation board.
- 2026-10-03 (designer, GUI lane): our own player list (top right); disguised and tutorial bots appear in it with their rank, money and a fixed believable wins count, never a flag. Settings gear beside the rank card. Trade starts from the player list: two halves of 8 slots, a giant READY with 3-2-1, "Want" marks an item on the other screen.
- 2026-10-03 (designer, GUI lane): the daily login is claimed by the server on join every day and at midnight UTC, with its popup; the Rewards and Trade menus leave the column (codes in Settings). Inventory has one Items tab (cases on top) and the Index. No lobby music. Idle icons turn gently; hover keeps the small sway and adds soft sun rays.
- 2026-10-03 (designer, Tutorial lane): the tutorial runs in the real public server the player joins (no 15-bot tutorial lobby). Game 1: the break pots 3 solids and leaves a 4th near a corner, the aim is locked straight, a hidden Magnet-strength pull on the player's balls, no shot clock, losing on the 8 impossible; game 2 goes through the real global queue (the bot's wait cut to 1 s). Leaving mid-game-1 restarts game 1; later steps resume. Skip asks to confirm and keeps game 1 going without guidance.
- 2026-10-03 (designer, Tutorial lane): the Bronze Case Drop is a forced Standard Case opened with "Open now" to a forced Uncommon cue, then the match's Rare Case. Bronze's 1 Case Drop is given at once; **every other rank reward is held until claimed in Rank** (NEW RANK! says "Claim your rewards in Rank!", Rank gets a red dot and glow). The first spin is forced to Magnet; Heat Seeker is the default ability; the RELEASE code replaces ABILITIES.
- 2026-10-03 (designer, Tutorial lane): the tutorial's light dim is a deliberate exception to "popups never darken". Real-server nudges show one at a time, only in the lobby, and an ignored one comes back until clicked.
- 2026-10-03 (designer, Tutorial lane): funnels: onboarding (22 steps, new players only), skipped/cancelled, the shop (repeating), Case Drop and ability spins.
- 2026-10-03 (integrator): the tutorial's claim gate sits in the daily claim itself, so the join claim and the midnight claim both wait while a player is in the tutorial's first server.
- 2026-10-03 (designer, bug pass): **no near-misses on the case reel** (the GUI lane's fake-out is removed; back to ECONOMY 11.7's "no fake near-misses"): the reel slows straight onto the prize. ReelPlan and its test are gone.
- 2026-10-03 (designer, bug pass): the prize card after a case has **two buttons, a small Sell and a wide Keep**; no Equip on it (cues are equipped in the Inventory; the Open 10 grid keeps its Equip). The tutorial gains an **Equip step** after the Uncommon cue: Inventory shows for it, the hand leads to Inventory, the cue's card and Equip; closing the Inventory without equipping moves on.
- 2026-10-03 (designer, bug pass): the tutorial hand is **redrawn upright** (index finger up, after the designer's "tap here" icon) with tap lines that flash on each tap; it is never turned upside down.
- 2026-10-03 (designer, bug pass): Inventory text is bigger and a cue card's line is only its chance ("34% chance"; the "fewer than 10 exist" part is gone). The menus' 8-ball pattern no longer drifts (it moved in whole pixels and looked choppy).
- 2026-10-03 (bug pass): the power bar's cue picture is turned by its real lean (37.45 degrees, measured from the thumbnails), not 45, so it stands straight.
- 2026-10-03 (designer, bug pass): the **lobby leaderboard signs are off for now** (`Config.Leaderboards.SignsOn = false`; the designer will find them a better place). The boards still save and still show in the player list's Top Wins / Top Rank tabs.
- 2026-10-03 (designer, bug pass): the tutorial's code step: once the code box is clicked the dim goes away and the gold ring and hand move to **Redeem** ("Type RELEASE, then click Redeem!"), trusting the player types RELEASE.
- 2026-10-03 (designer, bug pass): **no offer popups, ever.** The join popup for limited offers (ShopOfferPopup) is gone; the Starter Pack and VIP's welcome offer (50% off) stand as buttons with their countdowns under the Daily Challenge on the right while open, and a press opens the Shop on them. The "COME BACK TOMORROW FOR" screen and the "Your FREE SPIN is ready!" toast on leaving or losing focus are off for now (`Config.UI.ComeBack.ShowOnLeave`, `Config.UI.Rewards.Toast.ShowOnLeave`); the one-time leave gift still comes.
- 2026-10-03 (designer): Reyes reads **"The King"** under its name on the rank roadmap (`Strings.Ranks.Titles`).

## 2026-10-03: lucky blocks, native interaction and brighter presentation

Designer requested Roblox's own hold prompt, much larger held blocks, stronger colours in
the world and inventory, then a 0.5 s hold, an opening spin one second shorter and faster
from its start, and removal of the black background behind a pulled cue. Native
ProximityPrompt replaces the custom BillboardGui. Held edge is 2.8 studs (was 1.5); rise is
1.4 s (was 2.4), spin 2 -> 9 turns/s. The result drops its square shadow-image halo and
fades the reel dim away. The source models' texture ids were already identical; their
original demo uses much brighter ambient light. Preserve the maps, use a neutral white
base and gentle texture-coloured emissive fill, and light inventory viewports separately.
The original source place is unchanged. Physical controller acceptance remains pending.

## 2026-10-03: adding pack lucky blocks is a recipe, not a project

Designer asked that "add <BlockName>" be enough for any assistant to bring a block from the
bought pack into the game. The recipe is in `assets/luckyblocks/Readme.md`:
`tools/luckyblock_extract.luau` (model plus idle animation, with a check for motions already
uploaded), an Open Cloud upload to the group, `tools/studio_relay.py` with an Edit-mode
SerializationService import, then a Config row and a name. Each kind may name its own idle
animation (`Kinds[kind].Idle`, optional; it falls back to `Anim.BlockIdle`). The odds and
timer of a new block stay the designer's call.

- **2026-10-03 — Lucky-block follow-up (designer).** Multiple placed blocks retain separate
  0.5 s native hold-E/X/touch prompts, not one open-all action. Unopened blocks stay in the
  session-locked inventory; transient floor copies disappear on leave. Standard casts no
  physical light, other tiers do; particles remain. Player names follow case odds, retaining
  Yellow/Blue save IDs. Added Green/Uncommon (60 s), Void Lava/Epic (1 h), Gold King/Legendary
  (6 h), all seeded/refilled solely for Painicane. Designer bypass retains countdowns; other
  players can buy a 19 Robux skip (3716368528). A late receipt stores a reusable credit instead
  of losing value; paid skips preserve paid cue origin. Darken the reel AND reveal (reverses
  the earlier no-result-dim request); replace pixelated rays with a soft transparent texture.
  Confirmed WAV order: 403299 Common–Uncommon, 403300 Rare–Epic, 403298 Legendary–Secret,
  403984 anticipation; placement 4612375802, rank-up 2789429656. Preserve authored PBR tints
  on new pack models and lower Gold King's fill to keep surface detail.

- **2026-10-03 — Legendary size correction (designer).** Gold King uses 1.8x world/held
  scale and 1.25x preview framing; its crown must not shrink the central box below the other
  lucky blocks. Align the box body with the hands, and animate throws with its actual height.

- **2026-10-04 — Lucky-block skip landing (designer).** First skip advances to a short
  final reel approach and retains the winning-card settle before the cue reveal. A second
  skip during this sequence reveals immediately. Other case reels retain their existing skip.

- **2026-10-04 — Readable first-skip approach (designer).** Extend the remaining roll
  from 0.45 s / 1.5 cards to 1 s / 2 cards so the cue before the winner visibly passes the
  marker. Keep second-click immediate reveal.

- **2026-10-04 — Shop GUI v3 (designer).** The shop follows the designer's pasted reference
  images (`~/Desktop/GUI-refs/pasted/`), not the ChatGPT result sheets. Order:
  Grand Opening hero, Mystery block, restock, Starter + VIP, money, passes; tabs Featured,
  Blocks, Money, Passes (Starter and VIP under Passes). Menus build in from the top left;
  cards shimmer and icons pop now and then. A gold "+" by the money HUD opens the Shop on
  Money. Starter Pack and VIP are two wide bands side by side (stacked on a phone).
- **2026-10-04 — Lucky block models (designer).** Standard yellow, Uncommon green, Rare blue,
  Epic Void Lava, Grand Opening = Gold King, Legendary = Gold Majestic, Sky = Diamond Ghost
  recoloured lighter baby blue, Mythic = Gold Titan painted pastel rainbow with a cycling
  aura, Mystery = Standard reskinned black with rainbow rims, Lucky 8 = a part-built black
  cube with white "8" discs and silver rims (code bob), Starter gift = Standard red with a
  gold tie. VIP halves block timers and opens fast; Quick Cases is retired.
- **2026-10-04 — Gifting (designer).** A small gift square beside every Robux option in the
  shop, the hero included, buys that developer product for a player chosen from a Gift Player
  list (the designer's layout references; our style). Passes, restock items and timer skips
  are not giftable. The gift is the giver's own product purchase; the receipt grants the
  receiver (their first-buy double and offer windows), and a receiver who left leaves the
  item with the giver.
- **2026-10-04 — Shop GUI v3 interview (designer, to the CLI session).** The rail's top
  button says **Featured** (not Deals). The Grand Opening hero sits under a "— FEATURED —"
  header with its own "GRAND OPENING LUCKY BLOCK" title inside the band. One "— LUCKY
  BLOCKS —" header covers the Mystery band and the restock tiles; the restock keeps its dark
  stopwatch bar ("New blocks in 6:12 · each slot: ...") above its tiles, as in the ChatGPT
  sheet P4. "FIRST BUY x2" shows on every money pack until the first buy is used. The NEW
  badges on Featured and Blocks stay up all through the Grand Opening window, and the
  seen-once rule still clears every other mark. The designer's pasted references moved to
  `~/Desktop/GUI-refs/pasted/` next to the ChatGPT results (one folder for all GUI refs).
- **2026-10-04 — Shop v3 sections built to the references (CLI session).** Money buttons are
  gold and Robux buttons green everywhere on the page (references 12, 13, 21). The Grand
  Opening band's "save 12% / 29%" notes come from the Robux prices, the sale's price while it
  runs. The Mystery band shows no crossed-out price: its x10 column's "-30% SALE" sticker says
  it (reference 13 over UI_STYLE 13's crossed-price list). Restock tiles show one chase cue
  from each of the case's top three rarities with its chance. Money packs drop the pack name
  and the bonus line (reference 15 shows the art, the amount and the button only). Passes
  are wide tiles; Roblox Plus says "+10% money and a tag" with a Get button. A block kind
  without a model shows its kit icon in the Shop, the hotbar and the bag; the Mythic block's
  icons carry a cycling pastel aura.
- **2026-10-04 — Every block kind has its model; cases leave the player's view (designer).**
  The Gold Majestic (Legendary), Gold Titan (Mythic, pastel colormap), Diamond Ghost (Sky,
  baby-blue colormap), Mystery and Starter (the Standard block with their colormaps) and the
  part-built Lucky 8 cube are in the place (`assets/luckyblocks/Readme.md`). Nothing shows a
  case chest any more: a missing model shows the gift box, the thank-you burst shows the
  block itself, and every player-facing "case" word now says lucky block ("Blocks" tabs,
  "LUCKY BLOCKS" in the inventory, "2 Rare Lucky Blocks" in rewards). The old case reel code
  stays behind the scenes until it is retired. In Studio the Grand Opening deal opens on
  server start (`Config.Debug.StudioOpening`) so the Featured section is always there.
- **2026-10-04 — Cases, the Magic 8 Ball and the reward popups are retired (designer, to
  the CLI session).** Lucky blocks replace cases everywhere, in code, icons and words. A
  **win gives one Mystery lucky block** (it rolls its tier when opened; the very first real
  win keeps the guaranteed Rare block on its 1 h timer, which the tutorial waits on). Every
  reward row that paid cases pays blocks (`Drops = n` -> `Blocks = { Mystery = n }`,
  `Cases = { Rare = 1 }` -> `Blocks = { Rare = 1 }`); one reward shape everywhere:
  `{ money, blocks, spins, lucky }`. **Ready blocks are tradable** (a block on its timer is
  not). **The tutorial teaches the block**: Bronze's at-once reward is a Standard block the
  player throws and opens (forced to an Uncommon cue), the Rare step points at the Rare block
  counting down in the hotbar, the last nudge is "Your block is ready!". **Old saves drop
  their cases** (save version 7, nothing converted). **Daily login and playtime gifts are
  claimed in the Rewards menu** (no auto-claim, no `RewardGiven`); there is no reward popup
  of any kind any more ("they moved to the rewards icon"): the Magic 8 Ball shake, the
  playtime and login popups, the come-back screen and the first-leave gift are gone. **The
  Rare to Secret pull cutscenes move to the lucky blocks**: they play after the lucky reel
  settles, before the YOU GOT card, and will be reworked later. Quick Cases, the four case
  timer-skip products, the money skip and the case sale are retired (Quick Cases folded into
  VIP; `UltState.fastOpen` is `vip`). **The Shop is emptied** to its frame, background and
  the Featured, Blocks, Money and Passes buttons for the GUI overhaul (the server-side shop
  stays). **Inventory opens on Cues** with Cues and Index only; blocks live in the hotbar and
  bag. The case icons, the 8-ball art and their art-tool entries are deleted. `docs/ECONOMY.md`
  is the GUI spec; no GUI is built until the designer asks. Kept as they were: the Free
  Reward page and tile, the hub corner buttons, NEW RANK! and the rank-claim card.
- **2026-10-04 — Quicker turns, levelled sounds, a one-tap reel skip (designer).** The pause
  after a shot that pocketed a ball is 0.6 s (`Multiplayer.PocketSettleSeconds`, was 1 s). The
  ability-ready sound is cut to a third (`Ults.Audio.Ready.Volume` 0.15, was 0.45) and never
  plays in solo, where the bar is simply always full. The 2D sounds (UI, rewards, reel, match
  cues) were measured through an AudioAnalyzer and levelled to about YourTurn's loudness: the
  Secret heartbeat (was 8x louder) and the rank fanfares (2x) came down most; the foul clip gets
  its own `FoulSoundVolume`. The 3D ability effect sounds were left as tuned by ear in the
  abilities review. The lucky-block reel skip is one tap: the strip races on to the prize in
  `UI.Reel.SkipSeconds` (0.7 s) instead of jumping, replacing the two-stage skip.
- **2026-10-05 — Pull cutscenes start black; Rare redone (designer, Sol's RNG style).** Every
  Rare-or-better pull fades the whole screen to black the moment the reel stops
  (`Cutscenes.Black.InSeconds` 0.6 s, over the reel's own glide and hold), then plays its
  scene. Rare: 0.4 s more black, a soft blue glow swells from the middle to a full blue screen
  (0.52 s) while a riser builds (`Audio.Ui.RiserRare`, the designer's file, peak lined up with
  the flash), a white flash, and the card is under the white as it fades (0.35 s). The old
  sky-streak Rare scene is gone; Rare is never skipped. Epic and up keep their old scenes,
  lifting the black off as they begin, until each is redone. The reveal sting is still the
  trial 4612378086 for every rarity. First timings (0.35 s fade, 0.15 s held, 0.45 s swell) were too fast:
  the black is 0.5 s longer and the swell 15% slower.
- **2026-10-05 — The pull cutscene starts a second before the reel stops (designer).** For
  Rare and up the black fade begins `Cutscenes.Black.LeadSeconds` (1 s) before the reel lands,
  so the prize is glimpsed in the last crawl but never seen to settle: the suspense of "did I
  really just pull this". `/cutscene <rarity>` works again for the designer: it plays a whole
  lucky block opening (reel, cutscene, card) on a cue of that rarity, giving nothing.
- **2026-10-05 — Epic pull cutscene redone: the purple vortex (designer's sounds, Claude's
  look).** The designer's longer riser (`Audio.Ui.RiserEpic`, peak 1.98 s) and a pulsing bass
  hit (`ImpactEpic`) both start with the fade to black. In the black a purple ring pulses out on
  the bass; purple rays spin up and grow over a glow and haze while sparkles spiral in from the
  corners, a second pulse; then everything collapses into a bright point and bursts white on
  the riser's peak, the card under the white. Never skipped. The old streak scene is gone;
  a redone scene's riser and impact are now generic (`Riser`, `RiserPeakSeconds`, `Impact` in
  its `Config.Cutscenes` row).
- **2026-10-05 — Legendary cutscene tuned (designer).** The cinematic track plays out whole:
  after the hit the picture fades to black (0.6 s; a cut was too sudden, 0.9 s too slow)
  while it rings out; the rise starts 0.1 s after the hit, under the fade and the track's
  last ring (later starts were too late), and the warp shows from the black. The top-down
  sky shot looks down from in front of the player (it was from behind). Then: the beam lands
  0.2 s sooner (3.83 s into the track) with the rise kept where it was (4.13 s), the fade to
  black is quicker (0.35 s), and the warp opens as a tiny twinkling star in the middle that
  grows with the rise into the full warp at the flash. Then: the hit's light blinds the
  screen (a white-gold glare in 0.06 s, held 0.1 s) and it goes black in 0.15 s, so the warp
  starts 0.31 s after the hit. Trying (designer): the hit fades to white instead (glare in
  0.12 s, the fade 0.35 s) and the warp plays on white, its palest pieces deep gold
  (`Backdrop`, `DeepGold`; black is `Backdrop = { 0, 0, 0 }`). Then: the rise 0.5 s sooner
  (0.2 s before the hit), a brighter yellow for the warp (`WarpGold`), and the warp starts on
  plain white: a sharp eight-point yellow star pulses up from nothing in the middle, spinning
  and pulsing faster as it grows with the rise; the round glow, haze and shafts stay faint on
  white so it keeps its shape. Then: the star is a pointed eight-spike flare (long vertical
  spikes, `Art.StarFlare`) with a lighter inner one; it pulses 3 times while turning, then
  stops pulsing and expands, spinning faster and faster, until it fills the screen on the
  flash; the letterbox bars slide away halfway through the white. The opener's aurora is held
  while their card shows and lingers 5.5 s after they close it; a very faint looping "Aurora"
  ambience plays under the card and runs on 1 s after it closes, then tapers away (1.2 s).
  Everyone else's aurora runs 18 s.
- **2026-10-05 — No Legendary aurora in the sky (designer).** The gold sky aurora (SkyAurora,
  the server's checked "Reveal" and the Banner "Aurora") is removed; nothing shows in the sky
  for a Legendary, for the opener or anyone else. The card's faint "Aurora" ambience stays
  (PullCutscene.cardClosed tapers it). The rest of the Legendary scene is good for now. The
  Legendary's own announcement ("X unboxed a Legendary <cue>!", this server only) stays.
- **2026-10-05 — [GLOBAL] lines for Mythic and Secret pulls (designer).** In every server the
  line reads "[GLOBAL]: <username> pulled a Mythical <cue>!" in a pastel rainbow (a gradient
  on the banner, letter by letter in chat; `Config.UI.Menu.Banner.GlobalMythic`) or "...
  pulled a Secret <cue>!" in red (`GlobalSecret`).
- **2026-10-05 — Note for the Mythic and Secret redo (designer).** Both also get the
  Legendary's bonus reveal sounds: the "Cinematic Hit" on the flash and the faint angelic
  "Aurora" ambience under the card, tapering after it closes. The beam falls in 0.45 s (was 1.3 s)
  and lands on the track's final hit (4.03 s); the film follows the track's own playback clock,
  so a late-loading sound cannot put them out of step. The hit's shake is far heavier: a jolt
  down, then a smooth-noise shake with roll dying over 1.2 s, with a rumble as the beam falls.
- **2026-10-05 — Legendary pull cutscene redone: a film, a starlight warp and a gold aurora
  (designer's brief and sounds, Claude's look).** Part one is a film behind black letterbox
  bars, close on the player: the black fades up on them as the designer's "Logo Reveal" plays;
  the camera swings from their side round to their front, then looks up past them (wide lens)
  at a gold star gathering light above, then from high in the sky as a beam of gold light
  (energy core, glow, haze, spiralling ribbons, sparks) falls from the star and slams into them
  on the track's impact (4.0 s): sparks, a shockwave, a turning ring and sigil on the ground,
  a gold glare, the screen shaking. Every shot stops short of anything solid between the
  camera and the player (no more clipping through tables). A hard cut to black, then part two:
  a gold starlight warp (streaks flying out, rays, light pillars, rings) while "Chaos Rise"
  builds; a white flash on its peak with "Cinematic Hit", and the card. Skippable once seen.
  Then a gold aurora (`SkyAurora`: curtains of light, shooting streaks, sparkles, a slight dim)
  for 14 s for everyone in the server: the opener's client says its card is showing
  (BlockRequest "Reveal"), the server checks a Legendary was opened in the last minute and
  sends the Banner "Aurora". The old grey-world beam and the Legendary sky tint are gone.
- **2026-10-05 — No introduction when the 8 must be called (designer).** A turn that starts
  owing the call for the 8 goes straight to PocketChoice: the 2 s Intro held the pocket rings
  back while the top-down view and the prompt were already up (every return to the table after
  missing the 8).
- **2026-10-05 — The designer's own Unique cues: unnumbered owner copies.** `/givecue` gives a
  Unique cue (Beta, Grand Opening, Founder's...) to the designer's own account only, as an owner
  copy (`Inventory.OwnerUnique`): no copy number, never counted among the copies in existence,
  never takes a Limited number or stock, never traded or sold. Given to anyone else it is
  refused. The old "buy it on the Limited shelf" refusal is gone.
- **2026-10-05 — There is no Founder's Cue (designer).** It never exists in the game: its
  catalog row and name are removed (2 Unique cues: Grand Opening and Beta, both from the Grand
  Opening block). The tests' stand-in Unique and Robux Limited are now the Grand Opening Cue.
- **2026-10-05 — A crowd clap under NICE SHOT! (designer).** The designer's "XMS CROWD Clap
  Small", cut to 1.6 s with a fast fade (`Audio.Clips.NiceClap`, `Audio.NiceClap`), plays at the
  pocket with the NICE SHOT! pop, about half as loud as the bonus sting it sits under; the sting
  stays the main sound.
  Fixed the same day: the first cut (0.25 s full, then the fade, at volume 0.09) played but was
  buried under the sting's opening hit; the clap is now full for 0.6 s (1.8 s in all) at 0.26.
- 2026-10-05: Pull announcements never name the cue, only its rarity (designer): "X unboxed a
  Legendary Cue!" in the server, "[GLOBAL]: X pulled a Mythical Cue!" / "... a Secret Cue!" in
  every server.
- 2026-10-05: The player stands still through every pull cutscene (designer): walk speed and
  jump go to 0 and AutoRotate off for the scene, so shift lock no longer turns the character
  as the cutscene camera moves; everything goes back when the scene ends.
- 2026-10-05: A night in the day cycle, and no sun disc for now (designer: a lighting test to
  see if the cue models' textures and auras pop more in the dark). The cycle is Day 10 min,
  fade, Sunset 5 min, fade, Night 5 min, fade, a 30 s dawn (the sunset's light), fade back
  (`Config.Lighting.Cycle`; this replaces "no night" from Stage 7). Night is a moonlit roof:
  the painted sky dimmed to black by Roblox with stars and a moon over the sea, a deep blue
  shade, the table lamps at 5 (sunset 3) and the under-table glow stronger. The sun disc is
  hidden by day and sunset (`SunAngularSize` 0; it still lights the roof). `/day`, `/sunset`
  and the new `/night` now hold the light there for the whole server (a minute's fade per
  step) instead of letting the cycle run on; the new `/cycle` fades back into the cycle.
- 2026-10-05: Night is not pitch black (designer: a purple sky, the city still seen, its windows
  lit yellow like a night skyline). The sun stops at the horizon (ClockTime 6.15) instead of
  setting, since Roblox dims the sky to black any lower; the night shows the day's painted sky
  dimmed to deep blue and tinted purple, with stars and the moon behind the city. The city's
  windows glow at strength 6 in amber (`Config.Lighting.Night.Windows`). The sunset-to-night
  sky swap happens at blend 1.9 where the sun dips to the horizon and both skies are dark
  (`NightSkySwap`). Only the windows the emissive masks mark light up (about a third on the
  mid skyline); every window lit would need a new mask image.
- 2026-10-05: Night dropped (designer: "just get rid of night time"); the cycle is Day and
  Sunset again, and `/night` is gone. Kept from the night work: the sun's disc stays hidden
  by day and sunset (the designer wants to see the map without it), and `/day` and `/sunset`
  hold the light with `/cycle` to let it run. The fade between day and sunset is 10 seconds
  (was 1 minute, too slow) and is written every frame (it was written at most 12 times a
  second, which looked choppy); `Config.Lighting.Cycle.Rate` is gone.
- 2026-10-05: No sunlight either (designer: "i thought the sun was removed", the sun's
  shadows and light streaks still showed at sunset). `Brightness` 0 by day and sunset (was 2.6
  and 3.4); the roof kept bright by the exposure (0.35), a lighter warm day shade (#C0A898)
  and more of the sky's fill at sunset (0.4). Only the sun's light is off; the lamps, glow and
  lanterns are unchanged.
- 2026-10-05: Sunlight back (designer: "too dark now, go back"): `Brightness` 2.6 by day and
  3.4 at sunset with their old exposure and shade, so the sun's shadows are back. The sun's
  disc stays hidden; the 10 second, every-frame fade stays.
- 2026-10-05: A test (designer): the left column's four words (Shop, Inventory, Abilities,
  Free Reward) in Montserrat at its heaviest weight instead of Fredoka One, still white with
  the ink outline (`Config.UI.Menu.Column.LabelFont`). Everything else keeps Fredoka One
  (UI_STYLE) until the designer decides.
- 2026-10-05: **Cue pop test** (designer: cues lost on the bright roof). On test for Frostbite
  only (`Config.CueSkins.Pop.Ids`): a solid ink outline replaces the faint rarity-colour line
  of 2026-10-01, auras drawn less additively with a dark backing behind beams and ribbons, the
  emissive 1.6x. Code only; no reimport and no lighting change. Rolled out or dropped after
  the designer looks.
- 2026-10-05 (designer): **the pop outline is the cue's own theme colour, not black**
  (Frostbite light blue, Candy red, Flare orange): its Aura.Outline, else its trail colour,
  else its pocket burst's, else its rarity colour. Popped cues with no aura get it too. On
  test for six cues (`Config.CueSkins.Pop.Ids`).
- 2026-10-05 (designer): **every cue wears the solid theme-colour outline** (was the six test
  cues); a theme colour must be vivid (`MinSaturation` 0.3) or the next source is tried, and
  grey cues get the UI's ink. Close up, camera-facing ribbons draw the outline because
  Roblox thins a Highlight's outline away near the camera. The aura rewrite stays on test.
- 2026-10-05 (designer): **Legendary, Mythic and Secret outlines are a moving gradient of the
  cue's own theme** (Phoenix yellow, orange, red), not one shared Mythic palette ("the blue
  is too off-putting" on Kitsune). Kitsune, Celestial Dragon and Eclipse have hand-picked
  palettes in `Config.CueSkins.Pop.Outline.Gradient.Palettes`.
- 2026-10-05 (designer): **Common and Uncommon outlines are much smaller**, Common the least
  (`Config.CueSkins.Pop.Outline.ByRarity`: Roblox's Highlight has one width, so it is fainter;
  the close-range ribbons are thinner). A cue's rarity for its outline is its catalog Effect
  when that is on the ladder, so rank and special cues (Grandmaster, VIP, Reyes) also get the
  Legendary-and-up moving gradient.
- 2026-10-05: the close-range outline ribbons narrow to the bare cue at the tip and butt and
  turn off while the stick has any camera fade or is seen near end-on (the designer saw a
  square end and the whole cue filled with the outline colour on the back).
- 2026-10-05: The left column's word test moves from Montserrat Black to **Builder Extended
  ExtraBold** (designer; ExtraBold is its heaviest cut in Roblox). Still a test; everything
  else keeps Fredoka One. Roblox has no plain Fredoka (only Fredoka One), and no letter
  spacing or horizontal/vertical text stretch (checked in Studio).
- 2026-10-05: A look (designer): the whole Free Reward page, its title bar included, in
  Builder Extended ExtraBold too (`Config.UI.FreeReward.Font`; nil puts it back on Fredoka
  One). Still a test, not a kit change.
- 2026-10-05: Fonts back on Fredoka One everywhere (designer, after the Montserrat Black and
  Builder Extended looks; the font is still open). `LabelFont` and `FreeReward.Font` stay as
  switches for another try.
- 2026-10-05: **Filled letter holes** (designer: the holes of o, a, g, e... read as a thin
  outline; they should be solid ink). Roblox's text outline reaches only a little way into a
  hole, however thick (checked in Studio), so `HoleFill` lays two ink copies of the text under
  it, nudged left and right by 8% of the text size, with the text again on top. On test on the
  Free Reward page only (`Config.UI.FreeReward.FillHoles`) until the font is settled; then it
  can go on every outlined text.
- 2026-10-05: **Sunset less yellow** (designer: "way too yellow saturated"): the sun's tint on
  lit faces #FFCB88 to #FFDDB8, the shade #B8A090 to #B4A49C, the haze #F6C2A4 to #F0C8BC,
  and ColorCorrection saturation 0.15 to 0.05 with a near-white tint. The sky, lanterns and
  lit windows are unchanged.
- 2026-10-05: **Font tests from one place** (designer): `Config.UI.FontTest` puts a font on
  one screen (by its ScreenGui's name) or on every screen at once (`FontTest`); empty keeps
  Fredoka One. It replaces the Free Reward page's own font switch.
- 2026-10-05: **No ghost cue** (designer, seen live: a faint cue and a round blur across the
  view, plainest over a match's felt). The cause was CueAssets' hidden copies: each cue about
  to be shown (and the shot effects of the cues being played) is drawn 99% see-through in
  front of the camera so its textures load before it appears (2026-10-01); at full size that
  1% still showed. The copies are now shrunk to 5% (`Config.CueSkins.Warm.Scale`): still
  drawn, so textures still load, but a few pixels at 1% are never seen. Nothing else in the
  game is drawn hidden in view (the effects preload with PreloadAsync).
- 2026-10-05: The hidden cue-loading copies moved from the middle of the view to the screen's
  top-left corner, under Roblox's round menu button (designer: "where almost no one would
  look"; `Config.CueSkins.Warm.CornerPx`, 34 by 30 px). Measured in Studio: the shrunk copies
  span about x 17-51, y 15-36 px, all on screen (so still drawn and loaded) and inside the
  button, which is drawn over the world.
- **2026-10-06 — STATUS.md is current state only (designer).** The 1,849-line log moved to
  `docs/archive/STATUS_HISTORY.md` (newest first); STATUS.md is rewritten in place, under about
  100 lines, and a finished step's entry moves to the top of the archive. CLAUDE.md says so.
- **2026-10-06 — Builder Extended tried and dropped (designer).** Tested on the hub corners,
  rank, money, hotbar, lucky block roll, nameplates and Free Reward page; the designer went
  back to Fredoka One. `Config.UI.FontTest` is empty again and stays for later font tests.
- **2026-10-06 — Queue arrows only near you (designer).** A pad's bobbing arrow shows only
  within `QueueVisual.ArrowNearStuds` (35) of your character, fading in and out; at spawn
  that is the two tables in front.
- **2026-10-06 — Pale-blue frame borders (designer).** The Shop, Inventory, Abilities and
  Free Reward frames and cards are outlined in `Kit.PaleEdge` instead of ink, for now only
  these four (`Config.UI.Menu.PaleEdgeMenus`); buttons keep their ink outlines.
- **2026-10-06 — The left column's words in capitals (designer).** SHOP, INVENTORY,
  ABILITIES, FREE REWARD.
- 2026-10-06: **Text drop on test** (designer, after a Halloween store reference): under each
  outlined letter on the Free Reward page an ink copy with the outline, moved down 6% of the
  text size (at least 2 px), gives a thick dark lip (`Config.UI.FreeReward.TextDrop`; the
  designer picked 6% over 10% and 14%). The hole fill's nudge is now the outline's thickness
  (at least 8% of the text size), so big text keeps its shape. Tried on every outlined text
  (`Config.UI.Kit.HoleFill.Everywhere`) and turned off: small text (card names, Sort, the
  money pill) looked blobby, as a 2 px nudge on a 1 px outline makes the letters touch.
- 2026-10-06 (designer): **Solid holes on every outlined text from 20 px up**
  (`Config.UI.Kit.HoleFill.MinTextPx`); smaller text keeps its open holes, as filling them
  needs letters a pixel bolder. A text that grows past 20 px gets the fill then.
- 2026-10-06 (designer: "a tiny tiny bit" less lip): the text drop is 4.5% of the text size,
  at least 1.5 px (was 6%, at least 2 px; every Free Reward text was at the 2 px floor). It is
  set as a share of the label's height, because a padding's pixels are whole and 1 px would
  have halved it; on a high-DPI screen the half pixel shows.
- 2026-10-06 (designer: "put the lip everywhere"): the text lip is on every outlined text from
  20 px up, on every screen (`Config.UI.Kit.HoleFill.Drop.Everywhere`); the Free Reward
  page's own switch is gone. Smaller text has neither the lip nor the filled holes.
- 2026-10-06: **Lip on small text, on test** (designer): text under 20 px in the left column
  and the whole Inventory screen gets the lip (1.5 px) without the hole fill, which made
  small letters touch (`Config.UI.Kit.HoleFill.Drop.SmallText`, paths as in FontTest).
- 2026-10-06 (designer): **The lip on every outlined text, small text too** (the left column
  and Inventory test is over). Small text (a 1 px outline) still has no hole fill. Fix: the
  fill and the lip are sized from the outline's thickness, not TextSize. A scaled text's
  TextSize is only its largest size: the nameplate's is 100 for 34 px letters, so its copies
  moved 8 px against a 3 px outline and showed as dark blobs beside the name. The lip is
  0.45 of the outline (about 4.5% of the text), at least 1.5 px.
- 2026-10-06: Fix (designer saw "READY!" twice over a held lucky block, the lower one black):
  the held block's timer is built while its billboard is off, so its label had no height and
  the lip, a share of that height, went a whole line down. A label with no height now gets
  the lip in whole pixels until it is laid out; HoleFill listens to AbsoluteSize directly.
- 2026-10-06 (designer, after a reference): **Blur instead of every dark dim.** Menus (all
  MenuFrame screens), the Ranked roadmap, the lucky block reel, the match results and NEW
  RANK! blur the 3D world (a BlurEffect on the camera, size 20, 0.2 s in and out:
  `ScreenBlur`, `Config.UI.Blur`); their dark layers are now clear (they still take taps).
  The tutorial's spotlight dim and the pull cutscenes' black stay.
- 2026-10-06 (designer: the reel's blur "doesn't seem to fade in"): the lucky block reel now
  pops up 0.15 s after the blur starts (`Config.UI.Blur.ReelLeadSeconds`); at the same moment
  the reel covered the fade.
- 2026-10-06 (designer: the reel's cards "all appear at once"; they should expand in "all
  individually in rapid succession"): the lucky block reel enters one piece at a time: the
  title, the reel's window, each card in view left to right growing from nothing (0.18 s
  each, 0.04 s apart), then the hint; the spin starts after the last card (about 0.45 s in).
  `UIAnim.expandIn`, `Config.UI.Kit.Motion.Stagger`; any screen can use it.
- 2026-10-06: Smooth slow GUI motion (lively Shop gate 1, approved by the designer): anything
  slow moves the picture inside a still label, never the label. Scrolls are a window into a
  2 x 2 seamless tile slid by fractional ImageRectOffset; floats are whole-pixel Position plus
  the leftover fraction in ImageRectOffset; breathing is ImageRectSize zoom; rocks and spins
  are Rotation. Pops are UIScale with a fade done in code (no CanvasGroup); fast moves (pops,
  bursts, confetti) may use Position. Effects are flipbooks on one ImageLabel and our own
  pooled particles. Measured from 60 fps recordings (STUDIO_NOTES).
- 2026-10-06 (designer, after three real-text versions in Studio): the Grand Opening title
  is real text in the kit font, Fredoka One, letter by letter on an arch with a cyan rim, one
  merged navy outline, an orange depth and a gold gradient face (`ArchTitle`), not the painted
  logo cut from 13b. Words stay translatable; each letter can pop in by itself.
- 2026-10-06 (designer, gate 2): the Grand Opening subtitle is straight (no arch); the Shop
  header's 8-ball pattern goes to transparency 0.6 (from 0.7); the block's odds are a sky-blue
  "i" badge that never hides, opening the full odds pop-up (not an always-visible chip row).
  The crown and block are completed as whole pieces (no hidden parts), so they can be reused
  elsewhere. The cues are rendered from the in-game models (tip left, like 13b) rather than
  cut from 13b.
- 2026-10-06 (designer, gate 3, the animatic): the Shop open's default timings are approved
  (1.4 s open, 0.04 s stagger, 0.28 s pops from 60% past 110%, 0.2 s unroll; in
  `Config.UI.Motion` and `Config.UI.Shop.Open`). The Grand Opening title pops in as one piece,
  not letter by letter. The Grand Opening card's mini fireworks play at half speed and burst
  half as often (15 fps, every 1.5 s), calm like the gold ribbons.
- 2026-10-06 (lively Shop, step 7): the new menu frame is a kit switch,
  `Config.UI.Menu.LivelyMenus` (Shop only for now); other menus keep the pop-in frame. The
  header's 8-balls use the approved animatic's numbers (a repeat 260 px across, one repeat every
  16 s up-left, transparency 0.6) on a new picture with a 200 texel period, so one scroll window
  covers the widest panel. On a phone the 8-ball flair sits on the top edge just right of the
  title (Roblox's buttons own the top-left corner), kept on screen as it hops.
- 2026-10-06 (lively Shop, step 8): the Grand Opening card keeps every word at 16 px or more on
  screen, so its pills, odds chips and button words are bigger than in 13b at small sizes. Pages
  narrower than 760 px (phones) restack it (block and title on top, the cue cards side by side,
  then the buttons) and scroll. The crossed-out old Robux prices sit on a small white sticker at
  each button's top-right corner instead of inside the button (they did not fit at 16 px).
- 2026-10-06 (designer, lively Shop gate 4): the Featured card's part of the Shop's open plays
  twice as fast (the whole open 1.07 s). The card no longer restacks or scrolls on a phone: it
  keeps the cue cards beside the block and scales to fit the page whole, with its smallest
  text at 11 px (this card only; the kit's 16 px stays elsewhere). Each Robux button is shrunk
  for a purple gift square on its left (the Gift Player popup, `ShopGift`, back from history),
  shows only its price with the old price struck through in red inside it (the white sticker
  is gone), and the pack's "1 block / 3 blocks / 10 blocks" sits between the green and gold
  rows.
- 2026-10-06 (designer, lively Shop gate 4, second round): the Shop covers far less of the
  screen. The lively panel never enters Roblox's top-bar row (the title no longer sits beside
  Roblox's buttons on a phone), is at most 66% of the screen's width, and is only as tall as
  the Grand Opening card; it is centred, and the page scrolls on below the card to the rest of
  the white sheet ("More deals coming soon!"). The jump buttons stand outside its right edge;
  the 8-ball flair is pinned on its left edge. The card's buttons are taller (64 units) and its
  smallest text is 12 px. The crown is baked into the block's picture (block_crowned.png), so
  it breathes and shines with the block and arrives with it (its own drop is gone).
- 2026-10-06 (designer): **one thing at a time.** While any full menu is open, every other
  screen of ours disappears (rank bar, settings, left column, money, corners, hotbar, player
  list, thumbstick) and comes back when it closes (`HudFocus`). The lively Shop's header is
  smaller (title, money pill, a 34 px red X; tighter padding), the FEATURED row is tighter, and
  the first screen shows the top of the next section ("- BLOCKS -") so players see there is
  more and scroll. The cue cards' UNIQUE / LIMITED pills are smaller (down to 9 px) and the
  odds chip sits at the bottom-right of both cards. The 8-ball sits low on the left edge.
  GrandOpening1/3/10 were created on Roblox (ids in Config; icon: the crowned block); the
  poppers, streamers and twinkles stay on.
- 2026-10-06 (designer): the cue cards lose their LIMITED pill (UNIQUE only; the subtitle
  still says LIMITED). The lively header: the basket and "Shop" fill the row, the red X is a
  little smaller than the money pill, and the money pill has the money HUD's gold "+", which
  jumps to the Shop's Money group (its money packs, once that section is built).
- 2026-10-06 (designer): no "save 12% / 29%" under the money buttons; the room went to bigger
  buttons (bigger Robux glyph, cash bundle and words), the Robux row a little bigger than the
  money row. The gift squares are smaller than the Robux row, clear of the cue cards. The
  Grand Opening cue has a pulsing yellow glow round it (go_cue_glow.png,
  `tools/gui/cue_glow.py`) so it stands out of its background.
- 2026-10-06 (designer): **the Grand Opening Cue is now the Firework Cue**, everywhere a player
  or a doc sees it from now on (Strings, the shop card's "FIREWORK CUE", the cue skin's name,
  the GrandOpening1/3/10 descriptions on Roblox, GDD, ECONOMY, ROADMAP). Its id stays
  `GrandOpeningCue` so saves keep it; the Grand Opening Lucky Block and deal keep their names.
  Older dated notes keep the old name. Its card's gold ribbons turn at half speed (4.8 s), and
  the green Robux row is a little shorter, clear of the cue cards.
- 2026-10-06: **the Firework Cue is renamed behind the scenes too** (designer: "should be
  renamed firework cue even behind the scenes too"; this replaces the line above that kept
  the old id). Its catalog id is now `FireworkCue` and its skin, piece and asset ids
  `firework`, in code, Config, tests, tools, asset files and the place. Owned copies are kept:
  save version 8 renames the id in every cue map, the equipped cue and the trade history; the
  copies-in-existence count folds the old id into the new; the Limited numbering keeps the old
  DataStore key `GrandOpeningCue`, so copy numbers carry on and never repeat
  (`Config.Items.RenamedCues`). The Grand Opening Lucky Block and its products keep their names.
- 2026-10-06: the Shop's Firework Cue card shows its gold ribbons as **a still picture** instead
  of the ribbon loop (designer: the loop looked choppy). The ribbons never move: they pulse,
  dimming and glowing back (a rock like the 8-ball flair was tried and dropped); the cue itself
  stays still with its glow and shine. The lucky block and crown breathe a little faster (3.1 s to 2.3 s).
  **Only the Robux buttons shine**; the money buttons stay still, so the eye goes to Robux.
- 2026-10-06: **the lively Shop is the template for every GUI** (designer: "every future gui
  should follow this same workflow and format, with the background frame, animation popup").
  The method is the project skill `.claude/skills/lively-gui/`. Other menus switch to the new
  frame each when it is rebuilt with the skill, not all at once. The process scales: big
  screens go through every gate (target picture, art sheet, animatic, Studio first look,
  final); small popups and HUD pieces get a Studio first look, then the final check. A target
  picture comes from the designer when they have one, otherwise Claude mocks two or three to
  pick from. Next after this run: the Shop's Blocks, Money and Passes pages.
- 2026-10-06: **the block's odds open from its "i" badge only**, not the whole block (designer;
  hover, click, tap or A on the badge). **Every close X that B closes shows the controller's
  back button** (Circle, or B on Xbox) on its corner while a gamepad is the last input, like
  the menu column's D-pad glyphs (`HudParts.padBack`; every menu, and popups with their own X).
- 2026-10-06: **the balls pulse to call things out** (designer). The groups decided: every
  solid and stripe glows and pulses for as long as the YOU ARE popup (yours green, theirs red,
  from each player's side). A team down to its last ball (the 8 not counted): that ball pulses
  for 3 s as a warning, once per team per game (a miss and a later turn never repeat it; the
  opponent sinking your ball down to one counts too). Not in solo. `BallCallouts` decides,
  `BallPulse` draws, `Config.Multiplayer.Style.BallPulse` tunes.
- 2026-10-06: **ball callouts are green only, slower and brighter** (designer). The other group
  no longer glows red at the reveal; only your own group pulses. The last-ball warning pulses
  green for everyone. Each callout is 3 pulses of 2 s (6 s, longer than the YOU ARE popup) and
  brighter (`Config.Multiplayer.Style.BallPulse`: Color, Pulses, PulseSeconds, FillPeak).
- 2026-10-06: **no fat-fingered shots on a phone** (designer). A thumb that landed on the power
  bar while swiping, wobbled and lifted used to shoot at the lowest power. On a finger now
  (`PullGesture`, `Config.Input.TouchPull`): a 24 px dead zone where letting go cancels; past it
  the bar bumps ("clicks in") at the softest shot (4%) and full power stays at the same spot; a
  mostly sideways drag never shoots; a press under 0.15 s never shoots. A mouse is unchanged. The
  4% minimum stays (the server checks it): 1% and 4% both hit at the 15 in/s speed floor
  (`Config.Cue.MinSpeed`), so a lower minimum would only change the label.
- 2026-10-06: **ball callouts pulse 4 times, not 3** (designer), both at the reveal and at a
  team's last ball: 8 s at 2 s a pulse (`Config.Multiplayer.Style.BallPulse.Pulses`).
- 2026-10-06 (designer): **the phone's power bar stays inside the safe area.** A real iPhone
  cut it off under the notch (it reached 35% into the side safe area, 2026-10-02, to keep it
  from the aiming thumb); `Config.UI.PowerBarPhoneInsetShare` is 0 now, the bar 8 px in from
  the safe edge, same size. The touch guard (`TouchPull`) now does the thumb's job.
- 2026-10-06 (designer): **a raised cue has every effect off, every cue, for everyone**: raised
  by its player at all, or lifted over a rail or a ball more than 2 degrees
  (`Config.Cue.RaisedFxOffDegrees`; the lift is +0.75 at 25 in from a rail, +3 at 15 in, +19
  at 5 in). Off means the aura, the moving material, the outlines and the creature piece; the
  stick stays. They come back when it comes down or the shot is done. Was: only your own cue,
  only on your screen, only when chosen, and only the aura.
- 2026-10-06 (designer): **the 1v1 tables are tournament blue again** on the wood frame (the
  look `BlueWood`, the arena's cloth tint); green is no longer used in the lobby. Its
  SurfaceAppearances were copied from `ServerStorage.TableLooks.Green` in Edit mode (same maps).
- 2026-10-06 (designer): **no money "+" during a game** (`MoneyHud.setPlusShown`).
- 2026-10-06 (designer): **the game's logo is on every table's logo plate** (the 9 x 3 in plate
  on the foot rail), 5.5 x 2.2 in inside the pinstripe, as a first look (`assets/table/
  LogoPlate.py`, `assets/ui/logo/Crazy8Logo.png`, `Config.TableModel.Maps.LogoPlate`). The
  stored looks in `ServerStorage.TableLooks` were updated in Edit mode: save and publish.
  Bigger spots (printed on the cloth, the cabinet side) are offered, not built.
- 2026-10-06 (designer): **the 1v1 result cutscene drops the posed players**: the fade to
  black and the camera's pan down onto the table stay, nobody is copied or hidden
  (`Config.Cutscenes.Result.Posed = false`; the posing code stays behind the switch).
- 2026-10-06 (designer): **NEW RANK! darkens the screen again** (50% black, with the blur): it
  is the one popup that stacks on another screen (the match results), so the dim sets it
  apart. Every other screen still only blurs.
- 2026-10-07 (designer): **The player list is like Roblox's own.** Flush in the top-right corner
  of Roblox's top bar row, the Shop's lively header band (scrolling 8-balls) over the white
  sheet; one list, no tabs: the rank badge and username, then Wins and Money columns. It starts
  folded on every touch screen (phones and tablets) and is smaller on a phone (3.3 rows), and
  narrows to stay clear of the Settings gear. The global Top Wins / Top Rank boards leave the
  HUD (the lobby signs keep them); a new home for them is parked until just before release.
- 2026-10-07: **Nothing on the rank HUD pokes off the top of the screen.** The red "!" moved
  in onto the badge (`PendingDotAt`) and the HUD sits low enough that the dot stays on screen
  at its biggest (hover, press bounce, breath) on a phone, a tablet and a computer.
- 2026-10-07 (designer): **No player list on a phone for now** (the HUD screen under
  `Multiplayer.Style.ShortHeight`): it took too much of the screen. Tablets and computers keep it.
- 2026-10-07 (designer): **The rank HUD and the Settings gear sit in line with Roblox's own
  top-bar buttons** on every screen: the pill and the gear are 44 px tall like them, from 12 px
  down the row; the badge's box shrank 70 to 58 (its art shows 44 px) and the computer's 1.5x
  enlargement is gone.
- 2026-10-07 (designer): **A phone's lucky block hotbar shows only slots 1-3** (9 was too
  crowded; `Config.LuckyBlocks.UI.PhoneHotbarSlots`); the rest wait in the bag ("+n"). It also
  uncovers the money HUD's "+" and Invite. Tablets and computers keep 9.
- 2026-10-07 (designer): **The player list's header matches the rank HUD** on tablets and
  computers: "Players (n)" in the rank name's size (18), the band tight round it (30 px; the
  pill's 44 left too much space) and centred on the same line as the pill and Roblox's buttons.
- 2026-10-07 (designer, after a long-names test): **The player list is 360 px wide** on tablets
  and computers (was 300; the Wins column 52 to 42) and the **country flag has its own place
  after the name**, never cut: a long name ends in "..." instead (a typical 20-letter name
  shows 17).
- 2026-10-07 (designer): **The player list shortens money from $100,000 up** to whole
  thousands ("$123K", cut, never rounded up; `Format.moneyShort`), then "$1.03M" as before.
  Only the list: the money HUD and every other screen keep the full number.
- 2026-10-07 (designer): **Every person in the player list has their own box**: a white
  rounded card with a thin pale blue edge and a 4 px gap (yours pale blue). With money shortened
  the Money column went 82 to 66 px, so a typical 20-letter name fits whole with its flag.
- 2026-10-07 (designer): **The rank HUD is bigger on a computer or tablet again** (1.3x, and the
  badge alone 1.35x more, about its centre); a phone's stays small, in line with Roblox's
  buttons. **The player list starts folded on every screen**; left open, it opens again on the
  next join (a saved switch with no Settings row, `Config.Settings.Hidden` "ListOpen").
- 2026-10-07 (designer): **Matchmaking is one option: the matchmaking bar** (look A of three
  mocks). The pad card (difficulty, Request opponent, Join Global Queue, Play against PC, Play
  solo, Fill with PC) is gone; everyone on a waiting pad sees one slim bar above the hotbar
  (mode icon, n/2 chip, "Waiting for opponent..."), on every table. The host gets "Don't want
  to wait?" and a big green **Play Global** after 3 s, or 5 s with a Roblox friend in the
  server; searching shows the time and a small red X. Reason: "simplify the whole matchmaking
  and not overwhelm them".
- 2026-10-07 (designer): **"<name> needs an opponent!" is sent by the server on step-on** when
  the host has no Roblox friend in the server (any friend counts, even in a match), once per
  step-on with a 15 s cooldown; with a friend here nobody is asked (friends come over).
  Lobby bots no longer answer it: Play Global is the way to a bot.
- 2026-10-07 (designer): **The global queue's 1v1 bot fallback went 10 s to 5 s.** A lobby
  search now meets its bot before the rank window widens to anyone (10 s), so a real player
  far from the rank is skipped.
- 2026-10-07 (designer): **Lobby tables play Classic for now**; Play solo, Play against PC,
  Fill with PC and the difficulty choice move somewhere else later (server handlers kept;
  the server refuses a client's Request, Cancel or difficulty).
- 2026-10-07 (designer): **The tutorial only teaches stepping on the pad**: game 1's bot comes
  by itself on the pad, and game 2's search starts by itself (no Request or Join Global Queue
  hand).
- 2026-10-07 (designer, gate D notes): **The matchmaking bar's Play Global breathes more
  gently** (1.015 over 1.6 s instead of the house 1.03 over 0.9 s) and **its mode icon is the
  old pad card's Classic picture** again, not the new cue-on-green square.
- 2026-10-07 (designer, gate D approved): "Don't want to wait?" 1 px bigger (17 to 18); 2v2
  and 3v3 show nothing different on the bar (the same Classic icon and count chip).
- 2026-10-07 (designer): **A red X on Play Global dismisses it** for someone who would rather
  keep waiting; on a pad it stays hidden until the next step-on.
- 2026-10-07 (designer): **The spawn pill**: a player alone in a public server (never a
  private one, never before the tutorial is over) gets "Don't want to wait?" and Play Global
  on spawn. It goes after 20 s, on its X, on a pad or when a real player joins; pressed, it
  searches with no pad (`SoloSearch`), and stepping on a pad cancels that search.
- 2026-10-07 (designer): **The result cutscene redone**: no pose, so the camera comes down
  from high above into the player's own camera; Legendary-style letterbox bars slide in with
  the fade and slide out as the result screen opens, partway down the pan and centred. The
  result screen never closes by itself (only Continue, or a rematch), and a lobby rematch row
  that runs out turns into Continue. A winner hears 403300 (the old Rare reveal sting,
  101099108525458) as Continue shows.
- 2026-10-07 (designer): **Result screen polish**: every money line reads "+$800"; a win's
  Total pops whole on the sting's first hit and the block chip and Continue on its second
  (`Result.WinSting`). The result cutscene also plays when a 1v1 ends by a player leaving the
  server, walking out or surrendering, for both sides.
- 2026-10-07 (designer): **The result cutscene's camera is a sky tilt-down**: it fades in aimed
  50 degrees up from just above and behind the player's camera, then only the pitch turns
  (the horizon stays level) as it eases down and forward into that camera over 2.2 s.
- 2026-10-07 (designer): the result tilt starts lower (20 degrees up, the map's skyline and
  tables already in view) and runs 30% quicker (1.55 s).
- 2026-10-07 (designer): the ability bar reaching 100% plays the Smash Bros. Smash Ball sound and
  an ability going off plays the Smash Bros. Final Smash activation, both trimmed of silence and
  normalized to -16 LUFS (assets/audio/abilities). Every game sound was measured through an
  AudioAnalyzer and only turned down: Volume x 90th-percentile RMS about 0.045 for a sting, at
  most 0.06 for a big moment, 0.025 for a loop, no peak past 0.6. Ability sounds sat up to 6x
  over and a few peaked 2 to 4x past full scale (Time Stop's tick-tock, Black Hole's pop, the
  portal exit); the lucky block reveals and pull cutscenes up to 3x.
- 2026-10-07 (designer): temporary developer commands `/solo` (play the 1v1 pad you stand on
  alone) and `/bot [tier]` (play the computer there, your tier unless named), since the pad
  lost its solo and PC buttons with the matchmaking bar. The designer's account only.
- 2026-10-07 (designer): when an 8-ball rule loses the game (pocketed early, wrong pocket, a
  foul on the 8, the 8 off the table), the result screen shows a red LOSE over your card with
  why under it ("You pocketed the 8 ball early."; "Your team ..." in a team game), like the
  foul popup. Raised above WINNER's line so it clears your rank badge. `/result lose early`
  (or pocket, foul, off) previews it.
- 2026-10-07 (designer): NEW RANK! no longer shows over the result screen, in a game, during a
  rematch or in an arena. It waits until the player is free in a lobby server with the results
  closed (even still standing on the pad), then plays one popup per division gained since the
  last one seen, in order (Bronze I, then Bronze II, ...). The save remembers the last one seen
  (`Flags.RankShown`; existing saves start at their peak, no backlog). On the result screen,
  each rank reached holds the XP bar full and solid yellow saying NEW RANK! for 1 s (was a
  0.35 s white flash), then the bar carries on.
- 2026-10-07: The match result screen keeps its old layout exactly (designer: a rebuild into
  one lively panel was reverted the same day); only the rewards card's faint 8-balls now
  scroll up-left like the lively Shop's header (`Config.UI.Progress.Result.PatternPxPerSecond`).
  "The new moving 8-ball frame" on an existing screen means this: same screen, moving 8-balls.
- 2026-10-07: The result screen puts DEFEAT in red over the losing side, on WINNER's line, in
  every game with a winner (was LOSE, only over your side when an 8-ball rule lost it). The
  reason line stays under it for your own loss to an 8-ball rule.
- 2026-10-07: The Shop's Featured (hero) card starts as the panel finishes unrolling (0.2 s,
  was 0.36 s), everything on it 0.16 s sooner; the whole open is 0.91 s (was 1.07 s). Designer:
  too long a pause between the frame opening and the hero card.
- 2026-10-07 (designer interview): **Lucky blocks move to our own models.** The 3D blocks match
  the shop art (the Grand Opening crowned block): one master cube built in Blender with the
  pack's `joint1`/`joint2` bones, so the uploaded Box Idle animation plays on it unchanged; each
  kind is a texture, an optional topper on the top bone and a recoloured pack VFX set. The pack
  blocks are replaced over time. Legendary, Mythic and Sky keep wings (the pack's winged rig and
  idle). Every kind gets a glossy 2D icon in the Grand Opening art style (the block only, not
  the card), used in the Shop, the hotbar and the bag (every 3D-viewport block icon goes). The
  Starter block is a red lucky block gift-wrapped in a gold ribbon and bow; the **Gift block**
  stays its own kind (white, gold ribbon and bow, a gold clock face): it is given when a player
  leaves, to open when they come back the next day (the delivery rules are still open). First
  batch: 8 Ball, Starter, Gift, Mythic, Sky, Mystery; once their concepts are approved, the same
  for Standard, Uncommon, Rare, Epic and Legendary. Order: concept sheet, 2D icons, then 3D.
- 2026-10-07 (designer, lucky block concepts round B): **every block keeps the in-game frame**:
  thick edge bars with a chunky corner cube bulging out at each of the 8 corners, and clean face
  panels (round A's flat squares on the faces were the image model's mistake). The Grand Opening
  shop art may be redrawn on the same frame. **The Gift block** is given once, the first time a
  player leaves the game, on a 12-hour timer, and falls from the sky in its own cutscene (may
  change later; the design is finalized first). Its build waits on the concepts.
- 2026-10-07 (designer, concepts final): **round B for every block** (thick edge bars with a
  chunky cube bulging out at each corner), **except Mystery, which uses round C** (the same bars
  meeting flush, nothing sticking out). The redrawn Grand Opening block (B) replaces the Shop's
  art. The tier ladder is drawn in the same style: Standard yellow, Uncommon green, Rare blue,
  Epic dark purple with violet energy cracks, Legendary orange-gold with golden wings. The
  approved art lives in `~/Desktop/8ball-refs/lucky-blocks/` (`concepts_b/`, `concepts_c/mystery_c.png`,
  `tiers/`). Building starts: the master block in Blender on the pack's own C_01 skeleton.
- 2026-10-07: **Our own lucky block models are in the game** (Standard and Mystery first). Built
  in headless Blender from a script (`tools/luckyblock_build.py`), uploaded as glb, assembled into
  templates in Edit (`tools/luckyblock_template.luau`). The idle is the pack's Box Idle moved onto
  our rig (`tools/luckyblock_anims.luau`, LuckyBoxIdle): the pack's motion is a hover, not a
  squash, so a copy in studs matches it exactly (measured in Studio). The pack's glow particles
  and light are copied onto each block. The designer allowed uploads for this job without asking
  each time (dry-run first).
- 2026-10-07 (designer): **Standard** is lemon-yellow rims with beige-brown faces ("more yellow
  than gold"). **Mystery** has thinner flush rims, a rainbow that keeps moving around the frame
  (slowed to 1.2 studs/s, `Config.LuckyBlocks.Look.Scroll`) and a few rainbow twinkles. Checked
  in Studio through the real hotbar: keys equip with the hold pose, a click throws, switching and
  putting away leave no hold loop behind, both land with their idle, opening works, console clean.
- 2026-10-07 (designer): Standard moves back toward the pack's original: golden-beige rims and
  brown faces that darken toward the bottom, white "?" (replaces the lemon-yellow/beige try).
- 2026-10-07 (designer): **the cue card pictures show the cue as it looks in game** (replaces
  the 2026-10-03 no-aura snapshot): the aura frozen at one moment at twice its particle rate,
  the in-game theme outline (the moving gradient's colours from Legendary up, Common and
  Uncommon fainter) with a thin ink line outside it, the cue 1.45x thicker (was 1.15x) and
  filling more of the card, a little more saturation and contrast. An exaggerated try (a colour
  halo, bigger and deeper particles) was turned down: "the first samples were better".
  All 61 re-rendered (`CuePreview.py --thumb`, outline colours from
  `tools/export_cue_outlines.luau`) and uploaded.
- 2026-10-07: Every lucky block kind is our own model (the pack's models are unused). Winged
  blocks (Legendary, Mythic, Sky) idle with a wing flap on top of the pack's hover
  (LuckyWingIdle, 2 flaps a loop, 20 degrees). A block with wings or a topper is scaled so its
  cube matches the others' (SizeMultiplier = longest side / cube), and blocks on the floor keep
  apart by their width, not a fixed gap. The 8 Ball block hovers by animation now (no code bob).
- 2026-10-07: The pack's pulsing glow on a lucky block waits until its timer is done (designer).
- 2026-10-07: Every GUI shows a lucky block's 2D icon (the approved concept art) instead of a
  turning 3D view: the hotbar and bag, and through BlockIcon the rewards, trades and roadmap.
- 2026-10-07: The Gift drop (designer): only the first time a player leaves the game, a Gift
  block is owed, its 12 h timer counting from that leave; on their next lobby visit, after the
  tutorial, it falls from the sky in a cutscene with black bars, a glowing trail and a crash
  with particles, and they pick it up. A teleport to or from a match is not a leave; not picked
  up, it falls again next visit.
- 2026-10-07: The cue in the pull bar is drawn shorter (PowerCueArtLength 1.12 to 1.24): the
  redrawn cue pictures poked out over the bar (designer).
- 2026-10-07: VIP has no lucky block timers at all (designer: "to make it even more appealing";
  it halved them before). Every block a VIP gets opens at once (VipTimerFactor 0), and timers
  already running finish when the save loads with VIP or VIP is bought.
- 2026-10-07: Lobby bots are off by default in every server (designer: "only real people").
  Config.Bots.Lobby.OnByDefault = false; the designer's /lobbybots still turns them on in one
  server. The global queue's fallback bot, Play against PC and the tutorial's bots are unchanged.
- 2026-10-07: The Mystery block opens on its own upgrade screen, like Star Drop (designer). Its
  hotbar slot says OPEN!; 4 presses, the first shows the starting tier, each later one may
  raise it one tier, never down (Config.BlockOdds.Drop.Upgrade: 7% / 4% / 1% / 2% / 1% a press
  from Standard up). The designer chose to keep today's final odds and pity exactly: the server
  rolls the final tier first and picks the path the chain would take to it. The block becomes
  that tier's block in its slot, on that tier's timer. An upgrade is a bounce then an impact
  (white flash, screen shake, burst); the designer dropped the spin. After the last press,
  "Tap to collect" (or 4 s). The background is the blur plus the tier's glow, not a full
  backdrop.
- 2026-10-07: New lucky block timers (designer): Standard none, Uncommon 1 min, Rare 5 min, Epic
  1 h, Legendary 6 h, Mythic 12 h, the Gift still 12 h, every other kind none (the Mystery
  block's 5 minutes are gone). Blocks already counting down keep the time they had.
- 2026-10-07: The Mystery screen's presses are faster and smoother (designer: "each transition
  1 second or less"): an upgrade is one quick hop and the impact, about 0.6 s (0.7 s for the
  first), a kept tier 0.35 s; the block moves with sub-pixel smoothing and its float never stops
  under a press.
- 2026-10-07: The Mystery screen's shake is smooth (designer: "choppy"): smooth noise with a
  fade-out on the whole screen, the block and the camera, and the block's size moves sub-pixel
  too; the bounce is faster (an upgrade about 0.55 s, a kept tier 0.25 s).
- 2026-10-07: The hotbar's bag works like Roblox's backpack (designer): a click or tap on a
  block equips it with the bag still open (again unequips; a world click throws); a Mystery
  block opens its upgrade screen; dragging into the hotbar still works. The ` / ~ key opens the
  bag on PC.
- 2026-10-08: The queue pad is a queue portal (designer): as long as the table (19 studs) and
  just off its rail (6.5 to 14.5 studs from the table's centre line, over the shooter's walkway
  on the entrance side; the far edge did not move, so the fence and the map grid stayed put),
  the same for every mode. Blue with room, green with someone on, gold when full or playing.
  Glowing outlines rise from its rim and fade as they climb, with sparkles; the arrow sits a
  little lower with JOIN under it, bobbing with it (`Config.Multiplayer.QueueVisual.Portal`).
- 2026-10-08: A GUI redo, one screen at a time, each from an approved concept before it is
  built (designer): the cue card first, then the Cues menu, the lucky block spin and YOU GOT,
  Free Reward, then upgrade ideas for Abilities and Ranked (`docs/prompts/CUES_LIVELY_PROMPT.md`).
  The Inventory becomes **Cues** (a cue icon, no tab row); the Index moves to a book button
  inside it, beside Sort. The ten rank cues become one rarity, **Ranked**, each card in its
  tier's colours. The rarity's name goes inside each card's rarity bar.
- 2026-10-08: Favoriting the game gives $10,000 and a **Lucky 8 Block** (was a Mystery block),
  shown with its icon on the Free Reward card (designer); the group reward stays 3 Mystery
  blocks. Roblox cannot check a like, so only the favorite is rewarded.
- 2026-10-08: The Abilities screen and the Ranked roadmap opened blank: the one-thing-at-a-time
  focus hid their own ScreenGuis. Fixed to show exactly as before (designer: "add back the
  ability gui and rank gui").
- 2026-10-08: Cue cards show their chance on every card, in Cues and on the lucky block spin
  (designer), as a chip in the top-left corner; the faint 8-balls behind the cards are real
  8-balls with their 8 showing, kept very faint so they never distract (designer: "too
  distracting ... more transparent").
- 2026-10-08: The new cue card's look (designer, concept round 4): the rarity bar in the
  rarity's colour with the word in white; the faint 8-balls in each card's colour; the motion
  per rarity as shown on the concept page; a Ranked card's tier badge shown whole over the
  bar's end; a chance chip only on cues that drop from a block (none on Ranked, VIP, Starter).
- 2026-10-08: The new cue card is built as approved (concept round 4) for the Cues grid and the
  Index; the reel's cards follow with the spin's concept. The ten rank cues are the **Ranked**
  rarity in the data (their group stays Exclusive, so they still never trade, sell or double),
  sorted between Epic and Legendary, highest tier first; they pay Exclusive's finder's money
  ($5,000) and get their own Index row. An Index cell is at least 100 px wide (110 on a
  computer) so the rarity's word fits at the 12 px floor.
- 2026-10-08: The Cues menu's layout (designer, concept 2 round 1 notes): Sort, Sell all and the
  way to the Index stand on tiles outside the panel's right edge, with 5 cards per row; the
  Index is a two-part My Cues / Index switch that slides back and forth (designer: "its like a
  toggle where it switches back and forth"), not a book button with a back arrow; the Index
  shows the chosen cue as a flat picture that sways instead of the 3D turning cue; a copy
  number sits just above the card's name on the right, clear of the cue's tip; card words keep
  the same share of the card on a phone as on a computer (designer: "should be similar scale
  on pc"), replacing the 12 px floor for card names.
- 2026-10-08: Requested by the designer: numbers on the first 1,000 copies of every cue, every
  rarity, from the public release, so early players own "one of the first thousand cues even
  if it was a common cue", and how many exist shown for every rarity. Its rules (which cues,
  selling, trading) are being asked; it changes saves, selling and trading, so it is planned
  on its own after the Cues menu.
- 2026-10-08: The copy-number rules (designer): every cue that drops from a block (Common to
  Secret) is numbered on its first 1,000 copies; Unique cues keep numbering every copy; Ranked,
  VIP, Starter and Classic stay plain. Sell all never sells a numbered copy (one is sold only
  from its own card, after a warning); a sold number is gone for good, never handed out again.
  How many exist shows on a cue's big card for every rarity, never on the grid's small cards.
- 2026-10-08: Copy numbers reopened by the designer the same day ("maybe instead of 1000 maybe
  just 100"; worried that players get piles of numbered copies, even Commons, beside the plain
  ones; "research and decide for me a proposal"). Proposed, waiting for the OK: number only the
  first 100 copies of every Rare, Epic, Legendary, Mythic and Secret cue; Commons and Uncommons
  never; each numbered copy is its own card just before that cue's plain stack. The economy
  model at the planned launch size puts the end of each cue's first 100 at day 1 for Rare,
  about day 13 Epic, 29 Legendary, 49 Mythic and 3 months Secret.
- 2026-10-08: Approved (designer: "ok"): copy numbers on the first 100 copies of every Rare,
  Epic, Legendary, Mythic and Secret cue, never on Commons or Uncommons, each numbered copy its
  own card just before that cue's plain stack; and concept 2, the Cues menu, at round 2 (the
  My Cues / Index switch, 5 per row, the Index's flat swaying picture, the copy number above
  the name, card words at the card's scale on a phone). The CUES icon is picked next.
- 2026-10-08: The CUES icon has nothing behind it (designer: "no table behind it, just the cue
  and white ball"): the felt option is dropped; one cue lined up on a white cue ball, clear of
  the column's red dot and its word.
- 2026-10-08: Numbered copies get an engraving on the cue itself (designer: "for cues with
  serial numbers add an engraving somewhere on all the cues, show me an example before
  implementing on all of them"). Example shown, waiting for the OK: a gold nameplate with the
  number on the butt sleeve, on the cue in hand and on the back in the lobby. It is built with
  the copy numbers.
- 2026-10-08: The Cues menu is built from concept 2 (the Inventory renamed; brief
  `docs/prompts/CUES_LIVELY_PROMPT.md`). Two small calls made while building: the money "+" in
  every lively header now pops in with its money pill (it showed alone on the empty panel,
  the Shop too), and the Index's detail panel grows from its centre instead of popping (a big
  box overshooting poked out of the menu).
- 2026-10-08: The CUES button's icon is the Classic Cue, long and slim (designer: "should be look
  like the classic cue"), with no ball at rest: the ball pops in on hover and the cue hits it
  (concept 2b round 3, waiting for the OK). The black / black wood choice is dropped.
- 2026-10-08: The CUES icon is drawn like the real Classic Cue (designer: "make the dark brown
  and black part shorter like an actual looking cue"): about half maple shaft, a fifth forearm
  and a fifth wrap, as measured on the game's cue. It is the same size and in the same place as
  the other column icons (designer: "same like width and length as all the other icons"); only
  the ball leaves that box when it is hit (concept 2b round 5, waiting for the OK).
- 2026-10-08 (designer): The CUES icon is approved at round 5 ("looks good. replace the
  backpack now"): it is the CUES tile, the Cues menu's header icon and the switch's My Cues half.
- 2026-10-08 (designer): Notes on the built Cues menu. The rail's tiles are evenly spaced (the
  gap counts from a hanging pill's bottom). Sort starts on Rarest first on every open. The
  Index's chosen cue is its card, standing still, no longer a swaying picture. A never-found cue
  is its whole card under a light grey veil with a padlock; it is no longer a silhouette. The
  big card and the Index's panel sit on the Shop sheet's tiny pool-ball dots. A clicked card no
  longer stays gold, the big card opens without the gold burst and with a small nudge, and a
  hovered card leans 1.2 degrees, slowly. The click sound is a warm little "boop" ("UI pop",
  0.18 s; it was Roblox's thin small click).
- 2026-10-08: The menus' money pill shows the money HUD's number, so a sale's money counts up
  as its chip lands instead of jumping before the chip flies (designer: "not smooth and looks
  laggy"). The pill resizes alone, without laying the whole menu out again. A Cues view hidden
  during a change redraws when it is shown. Spent money counts down at once, because no chip
  brings it.
- 2026-10-08: "Sell all sold the numbered copies": no numbered copy exists yet. The "#12"
  chips were Studio-only stand-in numbers on plain duplicates (`GuiQA "cuesCopies"`, off in
  every new session). Sell all only sells Block cues' extras and keeps one. Once copy numbers
  exist it skips numbered copies (GDD 18).
- 2026-10-08 (designer): A numbered copy's engraving sits near the cue's butt end only, never
  near the tip.
- 2026-10-08 (designer asked which screen size to use first): the laptop size (1366 x 768),
  then the phone. Menus are designed at a computer's size and scaled down.
- 2026-10-08 (designer): The Cues menu's switch splits into two tiles, My Cues and Index (the
  view you are in blue, as the Shop's jump buttons), so all four rail tiles are one size and
  evenly spaced; Sort and Sell dupes still step aside in the Index. "Sell all" is now "Sell
  dupes".
- 2026-10-08 (designer): Equipping a cue plays sound 117649901456711 (`Config.Audio.Ui.Equip`,
  levelled near the click). Never-found cards in the Index keep their moving background under
  the grey veil and padlock.
- 2026-10-08 (designer: the money flying in was "super choppy"): the chip now leaves gently,
  speeds into the cash icon and fades into it over the last 30% of its flight, and the cash icon
  swells smoothly (`UIAnim.thump`, `Kit.Motion.Thump`) where the whole pill used to jump to full
  size in one frame. The same applies to the money HUD.
- 2026-10-08 (designer): The lucky block reel and YOU GOT use the new cue card, built without a
  concept at the designer's word. No card on the reel moves, the prize neither (a moving prize
  would give the pull away before the stop); YOU GOT shows the cue's card with all its motion
  (the drifting 8-balls and its rarity's effects). The reel's old dark see-through tiles and the
  YOU GOT's separate name and rarity lines are gone.
- 2026-10-08 (designer: "yes make rarer cues appear more often"): the lucky block reel draws its
  strip with each cue's odds to the power 0.3 (`Config.UI.Reel.Reel.WeightPower`, was 1, the
  true odds). Purely for show: the prize and the odds shown never change. A Standard strip goes
  from about 30 Common, 9 Uncommon and 1 Rare in 40 to about 17, 14, 7, with an Epic most spins
  and a Legendary about every other spin.
- 2026-10-08 (designer, to try): the reel's cards get a dark see-through face with their
  rarity's edge, as the old tiles had, in place of the card's colours and 8-balls ("the white
  backgrounds are a little bit too busy"). A switch, `Config.UI.Reel.Reel.ClearCards`, until
  the designer decides; YOU GOT keeps the full card.
- 2026-10-08 (designer: the money from a sale or a claim "STILL choppy ... as if it's lagging the
  entire screen", smooth in a match): recorded at 60 fps, the chip inside the Cues menu moved
  only every other frame (30 a second) while the menu's header pattern moved every frame. The
  chip was drawn in the menu's own ScreenGui, about 7,850 parts with every card built; in a match
  it flies in the light HUD ScreenGui. The Cues menu's chips now fly in their own small ScreenGui
  just over the menu (`CuesCashFlyer`, kept on by HudFocus), as the Rewards menu's
  (`RewardsFlyer`) always have. Studio check `GuiQA "loopCost"`: the Cues view's idle loops take
  about 2.3 ms a frame on the Mac (0.07 ms in the lobby).
- 2026-10-08 (designer: the money chip "still looks very choppy"): the real cause, found by
  recording a real Index claim and logging the chip each frame: the game moved the chip every
  frame, but with a big menu open Roblox put the move on screen only every other frame (30 a
  second), unless something read the chip's position back that frame (a debug log that did so
  made it smooth, which is how it was found). CashFlyer now reads each chip's AbsolutePosition
  after moving it, so it is placed every frame (checked: every recorded frame moves, Index view
  and a real claim). Each chip also reads its landing point once instead of every frame. The
  own-ScreenGui change above stays; on its own it did not fix it.
- 2026-10-08: The GUI redo pauses after the Cues menu and the lucky block reel's cards
  (designer): the economy plan, a cheaper and more balanced economy, comes first. The designer
  continues the remaining lively GUIs (Free Reward, Abilities, Ranked) from another session.
- 2026-10-08 (designer: "ok approved"): economy v4, "the forgiving economy", replaces the
  economy's numbers and several rules (`docs/prompts/ECONOMY_V4_PLAN.md`; today's state in
  `docs/ECONOMY.md`). The targets: about 15-22% of active players own an Epic and 2-3% a
  Legendary after week 1; 25-35% and 6-9% at day 30. `tools/economy_model.py` meets every
  target with Config's numbers (day 30: Epic 32%, Legendary 7.8%, Mythic 0.9%, Secret 0.1%).
- 2026-10-08 (designer): Robux prices drop everywhere (packs from 25 R$, VIP 399, Mystery 5 /
  45, Grand Opening 19 / 49 / 149, restock 15 / 99 / 599 / 1,699, spins 9 / 39 / 75 / 299, the
  skip 4 / 9 / 15 by time left). The products are updated through Open Cloud
  (`tools/roblox_products.py --sync`) right before the merge.
- 2026-10-08 (designer's call, the recommendation): copy numbers keep #1-100 for every rarity,
  though v4 hands those out within about the first month; alts are handled by the first-week
  match rule (a login day counts only after a finished match). No 7-day trade hold for now.
- 2026-10-08: the Grand Opening runs 30 days (the designer: "start at publish, maybe 30-45
  days"; the plan modelled 21). The copy caps (Firework 1,000, Beta 100) keep the Uniques the
  same at any length, so the window can be stretched without making more.
- 2026-10-08: the launch bonus (+30% on money packs, 10 Mystery blocks come as 13) replaces the
  30% release sale, during the Grand Opening window plus the receipt grace. The 13-for-10 is on
  the Robux 10-pack only; the money bulk price is unchanged. The six sale products are retired
  ("Closed" in the shop, off sale on Roblox, never deleted).
- 2026-10-08: the Starter Pack is no longer a paid random item in Config (`Random` off): where
  PolicyService restricts paid random items it gives $40,000 and the hour of 2x money with no
  block, so it can be sold everywhere.
- 2026-10-08: "Best value" moves to Pack7 (+40%, the biggest bonus); Pack6 lost it.
- 2026-10-08: a bulk product's `Was` is the same count bought one at a time (Spin5 45 = 5 x 9),
  shown as "one by one", never as a former price (Roblox's fake-discount rule).
- 2026-10-08: no minimum gap between two login claims: the 08:00 UTC reset alone decides the
  day, so a claim at 07:59 and one at 08:01 are two days.
- 2026-10-08: the restock's Rare block has Stock 2 per player per restock (one block per
  press); Epic and up stay at 1.
- 2026-10-08: VIP's daily Rare block counts a player whose PolicyService answer has not arrived
  as restricted: they get $5,000 that day. Safer than handing a paid random item early.
- 2026-10-08: the save migration to version 9 gives the first-week loop as done to a save with
  7 or more claimed login days (it had its first week under the old loop), and starts today's
  daily counters over for the new 08:00 UTC day boundary.
- 2026-10-08: a skip credit remembers its price tier (4 / 9 / 15 R$); a cheap credit never
  finishes a longer timer than it was bought for.
- 2026-10-08: unopened paid blocks trade or gift only between two players whose paid random
  items are allowed; a restricted giver cannot gift a random product.
- 2026-10-08 (designer: "if a person is actively moving when they click abilities, the cue
  appears in front of them, or if they jump, it shows the real character is on the ground ...
  needs to make it look like the character view is the actual character"): the ability spin
  screen films the player's real character (`Config.UI.UltScreen.Stage.Live`), not a client
  copy standing on the ground under them. Opening holds it (walk speed and jump at 0, its run
  cut); a jump or fall goes on with the camera following it down, up to `SettleSeconds`; once
  down it turns to the camera, is anchored on this client at its standing height and plays its
  own idle; closing gives everything back. The old copy is what made a running player's hidden
  character (and its cue) keep going in front of the copy.
- 2026-10-08 (designer: "just get rid of lucky spins as it doesnt exist anymore"): Lucky Spins
  are retired (`Config.Ults.Earn.LuckySpins = false`). The spin screen loses the Lucky bar, the
  Lucky odds switch and the Buy Lucky row; Lucky1 and Lucky3 are `Retired` (refused in game,
  marked retired in `tools/products_spec.json`, taken off sale by `--sync` when this ships,
  never deleted). Save v10 turns Lucky Spins still held into plain spins (capped at 100,000); a
  late Lucky receipt or a reward row with LuckySpins pays the same count of plain spins. The
  server's Lucky roll stays, unreachable. The Store no longer reads live prices of Retired
  products.
- 2026-10-08 (designer: the Ranked rewards "needs consistency with the rewards icons as some of
  them are bigger and smaller than others"): every reward tile on the Ranked screen is one
  width with one picture size, and all their words one size (the biggest that fits). A tile
  used to be as wide as its words, so "[DIAMOND]" made a big picture and "Epic" a small one. The
  chat tag shrinks on its own (`TileTagMinPx`); one block shows just its name (no "x1").
- 2026-10-08 (designer: "a claim all robux option as well (put a fair price ...)"; priced by
  the days left, the designer's pick): Claim All claims every day still ahead in this 7-day
  login row at once (`Daily.claimAll`). Today's unclaimed day is claimed whole (its track prize
  and VIP's part, no match needed: it is bought); the later days give their own reward only
  (VIP's daily part and the 28-day track stay with real login days). Price by days left
  (`Config.Daily.ClaimAll`): first week 399 / 349 / 299 R$ for 6-7 / 3-5 / 1-2 days, later weeks
  129 / 99 / 59 R$, about half the shop value. A paid random item (refused and hidden where
  restricted), never a gift. A receipt pays at most its product's days; with nothing left it
  pays the money fallback. The six products are in the spec, made when the Daily screen ships.
- 2026-10-08 (designer, on the GUI mock page: "spending 1700 robux for 760000 and thats still
  not enough to buy like a legendary lucky block ... money definitely needs a boost"): the money
  packs are boosted to $10,000 / $21,000 / $47,500 / $110,000 / $250,000 / $600,000 /
  $1,500,000 for 25 / 49 / 99 / 199 / 399 / 799 / 1,699 R$ (bonus 0 / 7 / 20 / 38 / 57 / 88 /
  121%). The biggest buys a restock Legendary block's money price; every block still costs more
  through money than its own Robux price; the economy model's rarity targets all still hold.
- 2026-10-08 (designer, the same page: "theres also a starter cue ... also actually increase
  starter pack to 29"): the Starter Pack is 29 R$ (was 19) and gives the Starter Cue again,
  everywhere (the cue is not random), with its block, $25,000 and the hour of 2x money. The
  shop's Starter Pack and VIP cards list the Starter Cue and the VIP Cue.
- 2026-10-08: **fixed: every Robux lucky block was refused at the receipt** (Mystery 1/10, the
  Grand Opening packs, the Starter Pack): PlayerData's list of grant fields still said `drops`
  (the cases era), not `blocks`, so applyPurchase refused the grant and the receipt was never
  granted. The list is now `Shop.GrantFields`, beside the Grant type, and a test checks every
  product's grant against it.
- 2026-10-08 (designer's picks on the mock page): Mystery A, Restock B, Starter Pack and VIP A
  (under the Restock, in the Blocks group), Money B, Passes B, the HUD win track A, Daily A in
  one Free Reward menu (merged with Rewards; Playtime A), Ranked A, Abilities A, the Mystery
  upgrade screen B, Settings A. Trade is not in the release: not built now. No animatics: each
  screen is shown at its Studio first look, with the Shop's open timings.
- 2026-10-08 (Shop, the Blocks tab, built from the picks): the locked VIP restock slot shows
  "VIP only" and one Get VIP button between its two button rows (the mock had a VIP slot
  label). On a phone the words never go under 12 px, so stacked words (a slot's name and
  stock, an offer's timer) move up to make room, and the Mystery block's climb note shortens
  to "5 presses to climb" where the long one does not fit.
- 2026-10-08 (designer, in chat): on the Passes page (pick B) a Roblox Plus member sees the
  Roblox Plus tile as "Active" (its button cannot be pressed) instead of a hidden tile, so the
  2 x 2 grid has no hole. Claim All's six Robux products may be created on Roblox when the
  Daily screen is ready.
- 2026-10-08 (Shop, the Passes tab, built from pick B): the panel's pill says "VIP & PERKS"
  (the "- PASSES -" header over it already says PASSES); VIP's card is the Blocks tab's card,
  shown to a VIP too as "Owned"; the ability slots and Roblox Plus get no gift square (game
  passes and a subscription cannot be gifted), Money Party does. The ability slots use the
  Ults icon with an orange "2" or purple "3" badge (no new art). Disabled Robux buttons (owned,
  sold out) no longer shine. The HUD's offer chips open the Shop where their card is: the
  Starter Pack on its card under the restock, VIP's offer on the Passes tab (before, both
  opened on Featured). The Starter Pack and VIP cards each get the sky-blue "i" at their top
  right with their lucky block's odds (the Starter Lucky Block; VIP's daily Rare block), as the
  v4 plan's hand-off asks (paid random items: the odds one press away), hidden where paid random
  items are restricted (the block is money there).
- 2026-10-08 (the HUD's win track, built from pick A): the bar says "Wins 3/10" as on the mock
  (the plan's "Lucky Blocks today 7/10" is kept in Strings), the time to the reset in its own
  pill, and after the tenth "10/10 · wins pay money and XP today". It shares the space over the
  hotbar with the matchmaking bar: it hides while that bar (a pad's or the spawn pill) or an
  opponent's ask is up, and during the tutorial. A step given while it is hidden (behind the
  result screen) pops its tick when it comes back.
- 2026-10-08 (the Free Reward menu, built from picks "daily A" and "free_other A"): one lively
  menu with jump buttons (Daily, Playtime, Track, Group) replaces the Rewards menu; the codes box
  stays in Settings. The jump buttons are the Shop's, now shared (`JumpRail`); after a screen
  resize both menus stay on the section being read. The menu opens on the section with
  something to claim. Days 1-6 are a 3 x 2 grid, not the mock's 2 x 3, so the Daily section
  fits a phone's first screen whole with the next header peeking in. A VIP's daily extras show
  on every day's tile (the server's DayView includes them). Every day with a lucky block wears
  the "i" with that block's odds (Claim All buys them: paid random items). A claimed day shows
  its check and not its money (the mock); day 7's extras go one to a line when they do not fit
  on one. On a phone the words keep 12 px (a picture's "+2"/"x5" chip 9 px, as the shop's
  pills), so a tile stacks from its edges: the status button keeps to the foot (its words plus
  3 px, under the buy buttons' 24 px minimum), the money sits just over it on the pictures'
  foot, the pictures shrink into the room left; the Group card's rows grow to hold their two
  lines. The column's Free tile is always shown, its rays turn while something is ready and its
  "!" comes from the reward state; the tutorial's anchor and nudge use the FreeReward name.
- 2026-10-08 (Ranked, built from pick "ranked A"): the roadmap moved into the lively frame
  (header with RANKED and the trophy, money pill with its +, X, flair, the house open). The
  subtitle line under the title is gone: the rank card and the rewards say it. The rewards card
  takes 48% of the width on a computer (53% on a phone) so its five tiles stay one size with
  their pictures centred. On a phone the panel takes 96% of the screen's width
  (`Config.UI.Ranked.PhoneWidthShare`, a new per-menu `phoneWidthShare` in `MenuFrame`), an
  exception to the frame's 66%: at 66% the tiers, the rank card and the tiles cut their words.
- 2026-10-08 (the ability spin screen, built from pick "abilities A"): today's layout in the
  kit's panels, as the mock. Kept from today though the mock leaves them out: the code box (the
  tutorial's RELEASE step points at it; under the odds bars, or on its own where there is
  room), the lock toggle on each owned slot, the rarity strip under the slot's name, the pity
  rule's line, the Auto Spin popup's stop choices. Dropped as the mock: the R$ / $ toggle, the
  struck-through "was" prices, the money pill and the BUY 5/10/50 for money: one gold money
  button buys one spin at $12,500 (`Config.UI.UltScreen.MoneyPack`; the server still accepts
  the other money packs). Words: "Back" (was BACK TO MENU), "Spins left: 16", "Buy 5",
  "Auto Spin", "Stop (3)", a slot not bought "Locked" with its price, an empty owned slot
  "Empty". No gift squares on the spin buttons (the mock has none and four buttons share one
  row). Skip got its own icon (two blue arrowheads, `Kit.Icons.Skip`). The open uses the Shop's
  timings with no animatic (the designer's answer for this hand-off).
- 2026-10-08 (the Mystery block's upgrade screen, built from pick "mystery_reveal B", the
  Track): the white pill counting the presses at the top, the tier's name, the block, its five
  dots, the white Tap! button, and the ladder of the six tiers along the bottom with its line
  filled up to the tier on show. Kept from today though the mock leaves them out: the line "The
  result is decided when you open it; the presses reveal it." and the pity counters, shown as
  they stood before this block (the server's Reveal reply now carries them) so they never give
  the result away. The screen lands as STANDARD (economy v4's climb from the bottom tier). The
  Tap! button stays through the presses, as the mock shows it at 4 / 5. The ladder's line and
  arrow take the tier's colour; its passed nodes too (the mock's are white).
- 2026-10-08 (Settings, built from pick "settings A"): the lively frame with the money pill and
  its "+", three icon rows with big switches, and the Codes strip always under them (it hid
  while the spin screen had its own box; the designer's pick shows it, and codes stay in
  Settings). Kept from today rather than the mock: the purple code icon (codes look the same
  everywhere; the mock's gold ticket is the Shop's Passes icon) and "Enter code" (the spin
  screen's word). The server's answer sits beside "Codes", so the strip never grows. The panel
  is 48% of a computer screen's width (`MenuFrame`'s new `widthShare`), so the rows have no
  empty margins. The old note under the box ("Codes give free money...") is gone, as the mock.
- 2026-10-08 (economy v4 plan section 4, the GUI hand-off item 9): the lucky block reel draws
  every card at the block's real odds (its Unique rows too, less the player's closed ones) and
  adds one showcase card per spin: a cue from Epic up out of the block's own pool, each of those
  rarities as likely (so a block's rarest cue shows as often as its Epics), with its chance as
  "1 in N" on its chip and a glow in its rarity's colour, between slot 10 and the strip's first
  two-thirds and never within 8 cards of the stop. It replaces the odds to the power 0.3
  (`WeightPower`, gone). `Config.UI.Reel.Reel.Showcase = false` turns the showcase off. "1 in N"
  is rounded up so it never looks better than true: whole numbers under 1,000, three
  significant figures above (`BlockOdds.oneIn`).
- 2026-10-08 (designer: "for the reel ... dont change it how it already is really except for the
  odds, do not put the line underneath saying that"): the reel keeps its look and effects; only
  its odds follow v4 (the real odds and the showcase card's "1 in N" chip). The plan's line
  under the reel, the showcase card's glow and "win effects only for Rare or better" (the
  landing glow, YOU GOT's rays and sting for every rarity again) are dropped.
- 2026-10-08 (economy v4 plan 18.1 item 8, the skip button's price): a press on a block still on
  its timer now asks first, in the kit's confirm dialog (the block's name, "Ready in 4:32. Skip
  the wait?", Wait and a green "Skip · 4" priced for the time left right now), instead of
  opening Roblox's purchase prompt straight away; Skip asks the server as before, which prompts
  that tier's product. A row over the hotbar was tried first and covered the bottom-centre
  prompts (Play Global, the win track) on a phone, so the dialog sits in the screen's middle.
- 2026-10-08 (economy v4 plan 3.2 and 3.3, the GUI hand-off item 13): the Mystery block's "i" in
  the Shop opens a full "Odds & Details" popup instead of the small per-rarity card: the line
  that the result is decided at the open, both pity counters with the blocks to go, the
  final-tier table, each tier block's odds and each rarity's chance per Mystery block, with
  "1 in N" beside every chance under 5%. While a guarantee is the very next block it says so in
  gold and shows the odds with pity (Roblox's rule: the guaranteed tier shows while it is
  live). It opens by a click, tap or A only: a scrolling modal on hover would get in the way.
- 2026-10-08 (designer: "instead of a word can you do a dice icon i think thats way more
  descriptive than an info pill so they should know what it means", then "no odds word just the
  dice"): every lucky block's odds badge is a sky-blue dice (`Config.UI.Kit.Icons.Dice`, drawn by
  `tools/gen_ui_art.py dice`), with no word, instead of the "i". Noted once: Roblox's
  paid-random-items rules say a standalone symbol such as the (i) icon without a descriptive
  word is not enough, and the plan (section 13) asked for a button labelled "Odds & Details";
  the popup it opens is titled "Odds & Details". The designer's call; a word can be added beside
  the dice later without moving anything.
- 2026-10-08 (economy v4 plan 13, Roblox's paid-random-items rules: each possible item's odds
  before buying, every outcome even when a category has many): every block's dice opens one
  shared "Odds & Details" popup (`OddsDetails`) listing each rarity, then its cues by name with
  each one's chance ("10 cues, 0.24% each: ..."; equal within a rarity, Roblox's "odds for each
  item listed below" form), each Unique cue on its own, and "Total: 100%". A chance that is not
  exact shows 5 significant digits (Roblox: round four places past the first non-zero digit)
  with the line "Some chances are rounded, so they may not add up to exactly 100%." The Mystery
  list adds each rarity's cues and each one's chance per Mystery block (the nested box: the
  final chance a player can work out). The old hover cards (`ShopOdds`, the Grand Opening's own)
  are gone: a list of every cue does not fit one, so odds open by a click, tap or A only.
- 2026-10-08 (Roblox's one-instance rule, economy v4 plan 18.1 item 5's per-player odds): a
  Unique cue a player owns, or whose copies are all found, shows 0% for them, on the Grand
  Opening's chips ("Owned" or 0%) and in its list with a line saying its chance went to the
  block's lowest rarity, as the server rolls it (`BlockOdds.rowFor`).
- 2026-10-08 (designer: "leave the grand opening bundle the way it is. right now its 19 robux for
  1 and 57 for 3 but its discounted so just leave it as is"): the Grand Opening's bundle buttons
  keep their struck-through prices; the plan's "57 R$ one by one" line (18.1 item 5) is not
  built.
- 2026-10-08 (economy v4 plan 13: the skip is a paid random item): the skip dialog wears the
  block's dice at its title row's right end; it steps the question aside for that block's Odds
  & Details over the screen and asks again (the price for the time left then) when that closes,
  so B and Escape never answer two layers at once.
- 2026-10-08 (designer: "on pc/tablet make the pull gui slightly wider since theres more space,
  leave phone the same"): the power bar on a big screen is 76 px wide (was 60), its cue 24 (was
  20); the phone's bar is unchanged.
- 2026-10-08 (designer: "use the bars from each of the rarities in the cues ... with just like a
  odds and a small disclaimer", then "Bars + one line only"): Odds & Details is one Cues-menu
  rarity bar (`RarityBar`) per rarity with its chance, a capped Unique cue on its own bar, and
  one line, "*Every cue in a rarity has the same odds."; the per-cue lines and the total are
  gone, and so is the Mystery list's per-tier block section (its pity and final tier stay).
  Roblox's paid random items policy asks for each item's odds; equal odds within a rarity is
  now only stated in that one line, not listed per cue, which is the one compliance risk. If
  moderation flags it, the per-cue list comes back.
- 2026-10-08 (designer: "put VIP and starter side by side ... this should actually be used mainly
  as the refernce so it can fit on one page without scrolling"): the Shop opens on the Starter
  Pack and VIP as two wide cards side by side (`ShopOffers`, `Config.UI.ShopBlocks.Pair`), one
  centred when the other is gone; each hero shows what you get (Starter: its lucky block, its
  cue and cash, no gift icon; VIP: the crown, cash and a big pulsing 2x). The Passes tab's tall
  VIP card wears the same VIP hero.
- 2026-10-08 (designer: "for every gui always start at the top not where they left off"): every
  menu opens at the top of its pages (`MenuFrame` resets its scrollers; the lucky hotbar's and
  the ability screen's lists too). The Free Reward jump buttons still open their own section.
- 2026-10-08 (designer: "emphasize more of joining the group and favoriting first", reference
  image 30): a first Free Reward visit (the group or the favorite not claimed) puts Group first
  as two heroes side by side (`FreeHeroes`), the invite card under them; once both are claimed
  the page is the old one with Group last. The order is decided as the menu opens, so a claim
  never moves the page under a finger. The reference's "TODAY" row (Lucky Shot, Lucky Rain,
  Stay bonus) is not built: those features do not exist.
- 2026-10-08 (designer: "i said for day 7 to be a legendary not epic", then "First week only"):
  the first week's day 7 stays the Legendary block; the later weeks' day 7 stays Epic.
- 2026-10-08 (designer: "these rewards are terrible ... it should give at least a legendary at
  the end ... or money", then "Money + Legendary end"): the 28-day track pays $50,000 on day 8,
  an Epic block on day 14, $150,000 on day 21 and a Legendary block on day 28 (it was a Rare, 2
  Rare, 2 Rare and an Epic); a money prize shows its amount on the track.
- 2026-10-08 (designer, abilities rework; plan in docs/prompts/ABILITIES_REWORK_PLAN.md): the
  ladder is now 13 abilities (Common: Eagle's Eye, Super Bounce; Uncommon: Magnet, everyone's
  starter, and Rewind; Rare: Catch-a-Ball, Portals; Epic: Look Over There!, Time Stop, Chain
  Lightning; Legendary: Verity, Steel Ball, Black Flash; Mythic: Black Hole, Guangdong Tiger).
  Heat Seeker and Ghost leave; a slot holding either becomes Magnet. Rare and above should
  nearly always pot a ball. Catch-a-Ball and Verity act on whatever the cue ball hits first;
  only the 8 off a legal 8 shot is spared (it breaks free, or Verity refuses it).
- 2026-10-08 (designer): Look Over There! is not a shot. Armed, it opens a Sneak phase: the
  shooter points and shouts, the opponents turn away (their camera too: just the room and a
  "?"), and the shooter has about 3 s to drag one of their own balls (never the 8) into a
  pocket. The pot counts and the turn goes on with a fresh clock. A ball dropped on the cloth
  stays there; a ball still held when time runs out drops where it is, into the pocket if it
  is over one. On an open table a sneaked ball claims its group, as a pot would. A sneaked ball
  pays no money. The voices are text-to-speech stand-ins until the designer records their own.
- 2026-10-08: Roblox's upgraded avatar joints (AnimationConstraint, no Motor6D) are what this
  place's characters use; ability looks that pose a body turn either kind of joint by its
  Transform.
- 2026-10-08 (designer: a realistic tiger "actually rigged and animated", the cut balls lingering
  like Black Flash's): Guangdong Tiger is now a skinned tiger (a Meshy mesh on a hand-built
  24-bone rig, `tools/blender/abilities/tiger_v2.py`; its actions baked data played by
  BoneAnim). It gallops in diagonally from the far side of the view, pounces, rears and slams
  its right paw down through the cut, lunging, then its left paw back across it (an X), turns
  to the camera and roars, and runs off. The shooter's camera eases in for the strike and up at
  its face for the roar, then hands back. Cut balls split into halves that open and lie face up,
  white-hot and smoking, cooling to the ball's colour, for 6.1 s. The moment's slow grows from
  0.6 s to 1 s of wall time for the longer run in. New sounds: a deeper roar, a snarl as it
  springs, a claw slash per rake.
- 2026-10-08 (designer: "actually steel shiny and glossy", spinning up "like a fidget spinner",
  the golden ratio "in yellow outline" at the hit, the guided balls spinning hard): Steel Ball's
  look is reworked. Armed, the cue ball turns mirror chrome with three dark grip dots and spins
  up about the upright over 2.7 s with a rising whine, until the dots smear into a ring of
  streaks. At the first hit the golden ratio (the golden rectangle, its squares and the spiral)
  draws itself on the cloth in yellow lines with a dark gold edge, the spiral's eye on the
  contact. Every guided ball spins hard in its own streak ring, with a yellow guide line to its
  pocket. The golden path on the cloth, the spiral pictures and the manga steel shell are
  retired.
- 2026-10-08: Catch-a-Ball's catch is a small cutscene for the shooter: their camera eases in
  beside the catch ball (70 degrees round from behind, a little above, about nine ball radii
  away) so the lid opening, the ball pulled in, the hop, the wobbles and the click fill the
  screen, and hands back over the last 0.4 s of the 4.35 s look. GOTCHA! now pops at about a
  third of the viewer's screen width (it was a fixed 3.2 studs, which would have covered the
  whole close-up). The look also honours `/hold` and `/slowmo` like the others.
- 2026-10-08 (designer: Rare and above should nearly always pot; buff Portals, Time Stop and
  Chain Lightning): the three are buffed toward a sure pot, each in its own way, and measured
  (tools/ult_value.luau, 120 tables, careful net at skills 1/2/3 and pots a use). **Chain
  Lightning**: the lightning drives the charged ball down the clear line into the pocket nearest
  its heading (a bolt drawn along it), then jumps once, not three times (with the driven charge
  three jumps measured +1.4, above the Legendaries): +0.87 / +1.07 / +1.03, pots 83-95% (was
  74-88%). **Portals**: your ball comes out lined up into the pocket nearest the exit (the
  player puts the exit by the pocket they mean; nearest its heading measured a little lower and
  is harder to read from the pick), and a ball goes in when its centre crosses the drawn ring
  (2.9 in, was 2): +0.65 / +0.71 / +0.70, pots 83-93% (was 57-84%). **Time Stop**: a ball of
  yours the stopped-time strike touches is sent (a line to its pocket) and rolls in as time
  resumes, and a shot that touches nothing freezes 1.5 s in too: +0.82 / +0.85 / +0.93, pots
  91-94% (was 47-78%). The misses left are mostly the shooter's own (no ball touched, the wrong
  ball first). The descriptions and the stopped-time hint ("HIT ONE OF YOUR BALLS") say so.
- 2026-10-08: the rework's three new abilities measured over 120 tables (careful net at skills
  1/2/3): Catch-a-Ball +0.47 / +0.66 / +0.75, pots 91-96%; Look Over There! +0.95 / +1.01 /
  +1.02, a pot every use (the harness drops the bot's ball and assumes the drag lands; a table
  with only the 8 left is no use, as the game refuses it there); Verity +0.91 / +1.10 / +1.13,
  pots 94-98%. Their catalog worths are now the measured means (Catch-a-Ball 0.63, was 0.78 from
  a 12-table quick run; Look Over There! 0.99; Verity 1.05). The rarity means are 0.34 / 0.50 /
  0.66 / 0.95 / 1.12 / 1.31, Common to Mythic.
- 2026-10-08: the rework's polish gives the two top looks a camera moment, as the tiger and the
  catch have. Black Hole: at the open the camera of each player at the table eases in to a low
  three-quarter view of the hole, drifts round it and closer while it feeds under a darker
  grade, and eases back from the pop. Black Flash: the hit-stop is 0.3 s (was 0.15), filled
  with anime impact frames (a blown-out negative, a red manga frame, the negative again) and a
  crash zoom toward the hit, rolled 7 degrees. Both looks now stop on /hold like the others.
- 2026-10-08: Chain Lightning's strike reaches the screen of players at the table: lightning's
  double flash, a quick zoom-in punch and a cold storm grade while the bolt drives the ball in
  (the rework's polish; it had only a small shake).
- 2026-10-08 (designer's second rework round): Black Hole and Guangdong Tiger lose their ball
  caps (were 4 of yours and 1 of theirs): every ball in reach goes, so a hit on a solo break,
  where practice allows them, takes all 14 and leaves the 8 to call ("like the Chinese
  TikToks"; in a match nobody has their ability on the first turn). Black Hole's cinematic
  camera is taken out again; the hole plays on the table's own view.
- 2026-10-08 (designer's second rework round): Look Over There! is reworked into a sneaky ball
  in hand. No cutscene, no activation panel and no armed label ("the joke is that they're not
  supposed to know"): the shooter points up and "OMG LOOKK AT THAT!" appears as their chat
  bubble and a chat-window line (bots too, whatever the chat settings); each opponent is locked
  in first person looking away from the table for about 3 s while the shooter moves the cue ball
  anywhere free; then they turn back in first person to the new spot, with only the vine boom.
  The old version (drag one of your balls into a pocket, the Metal Gear alert, the "?", the
  whoosh, the sneaky sting and the shout voice) is gone. It is refused on the break and when the
  shooter already has ball in hand. Bots use it too (they drag the cue ball to their best ball in
  hand spot).
- 2026-10-08 (designer's second rework round): Verity is no monster any more (its model never
  showed in the game): at the first contact the smiley ball turns evil, swells to three times a
  ball's size and eats the ball it hit, then keeps rolling along the shot line, eating up to 2
  more of your balls and bumping the rest aside ("Eats yours, bumps theirs"), with a quick
  camera push-in on her face as she bites ("highly clippable"). Two choices made here: she hops
  over the 8 rather than bumping it (a bump could sink it and lose the game), and balls inside
  her as she swells are shoved just clear (the 8 only where that cannot drop it). Your balls
  near her path are slurped in from 5.5 in (centre to centre): with only her body's touch (4.5
  in) she measured +0.99, below the old Verity's +1.05; 5.5 in gives +0.97 / +1.15 / +1.17
  (careful net at skills 1/2/3), a Legendary.
- 2026-10-08 (designer's second rework round, "Swap + buff Catch-a-Ball"): Catch-a-Ball is Epic
  and Look Over There! is Rare (it is no sure pot). Catch-a-Ball's Epic buff is a second catch:
  after the first, the catch ball leaps, flipping, to your nearest ball and catches it too
  (DOUBLE CATCH!). Its reach is 9 in, centre to centre, chosen by measurement: 20 in measured
  +1.28 (above the Legendaries), 12 in +1.04, 9 in +0.80 / +1.02 / +1.05 (careful net at skills
  1/2/3), an Epic. The hop never crosses a pocket mouth and never takes the 8. Look Over There!
  measures +0.50 / +0.63 / +0.60 (pots 75-97%), under the Rare mean, but the measure counts only
  the one shot, not the run a free ball in hand sets up.
- 2026-10-08: Black Hole and Guangdong Tiger without caps measure +1.63 / +1.87 / +1.83 and
  +1.63 / +1.86 / +1.83 (Worth 1.78 and 1.77, were 1.32 and 1.30): the Mythic mean rises from
  1.31 to 1.78, and the model still holds every rarity above the one below (Mythic beats Magnet
  56-59% at equal skill).
- 2026-10-08: an ability's slow-motion moment (Catch-a-Ball's 4 s hold, Black Flash's hit-stop,
  the Tiger's slow) is timed on the replay's own clock, and a replay frame stops where one
  begins. Before, a frame longer than the moment (any frame for Black Flash's 0.004 s hit-stop,
  a 30 fps frame for Catch-a-Ball's 0.02 s hold) ran straight through it at full speed, so the
  hold was skipped in play.
- 2026-10-08 (designer: "use this reference exactly", one image for each look): Verity's armed
  ball is the bright yellow plush smiley (black oval eyes, a grin of two rows of white teeth in a
  thick black outline) and her evil form the creepy face: dark mustard ochre, hollow dark eye
  holes, no brows, a huge open mouth with thick pale-pink ridged lips, a dark throat and a
  tongue. Both are our own Blender builds matched to the images (nothing from them ships). Her
  eyes no longer glow (they are holes), her mouth hangs open at rest (35 degrees), and, our
  choice, she lunges at the ball as she gapes: the gape alone turned her eyes skyward, out of
  the push-in camera's view at the most clippable moment.
- 2026-10-08 (designer's third rework round: "when he moves forward he shouldnt eat more he just
  pushes balls out of the way"): Verity eats only the first ball she hits; on the roll she
  bumps every ball she touches aside (still hopping over the 8). That measures +0.49 / +0.68 /
  +0.76 careful net (pots 92-96%), the Rare mean, so she moves from Legendary to Rare (the
  designer's choice of the three offered: Rare, staying Legendary weaker, or a buff). The
  Legendary mean is now 1.15 (Steel Ball, Black Flash).
- 2026-10-08 (designer's third rework round: "rework super bounce to be FIRE SHOT, which will
  actually be the new default starter"): Super Bounce is gone and Fire Shot (Common) takes its
  place. Armed, the cue ball is engulfed in flames; the shooter's aim line runs on off every
  cushion, mirrored, to the first ball it meets (its ghost ring and object line) or a pocket,
  up to about 3 table lengths, never showing where anything stops (the designer's pick of
  three); the shot leaves the cue at 2x speed (along the cloth and the spin, not a jump's
  height, as Black Flash's 3x); it leaves cosmetic scorch marks that stay until the shooter's
  next turn (the designer's pick). Fire Shot is everyone's starter: new profiles and empty or
  unusable slots get it, the tutorial's starter spin lands on it (the designer's pick), a saved
  Super Bounce becomes it, and a save holding Magnet keeps Magnet. The bots roll abilities by
  rarity as before (my question said the PC keeps Magnet; it never did), so they now roll Fire
  Shot where they rolled Super Bounce.
- 2026-10-08: Fire Shot measures about nothing: -0.08 / -0.03 / +0.03 careful net (careless
  -0.10 / +0.02 / -0.01); double speed alone neither pots nor misses more, an overhit scratching
  a little more often (fouls 2-4% careful, 5-7% careless). Its Worth is 0 and the Common mean
  0.17. The harness plays no kicks, banks, or Difficult and Challenger tables, where the line
  helps most. The bots hit at the full 2x (no power correction: it measured no better).
- 2026-10-08: Fire Shot's "longer aim line" means the guideline's own lines (the designer's
  correction, with a screenshot): after the first ball, the object ball's line and the cue
  ball's line run on until they touch the next cushion, ball or pocket. It is not a line that
  bounces round the cushions, so `Aim.bounceTrace` became `Aim.fullLines`. With Fire Shot
  armed the guideline draws every line whatever the table's difficulty.
- 2026-10-08: Fire Shot's look:
  - A river of fire flows under each guideline line. It is our own art (`fire_river.png`),
    alpha-blended: an additive glow washed out to pink on the blue cloth, and the cue trails'
    smoky art read as soot.
  - Scorch marks use our own art, bend exactly where the ball does, and glow then cool. They
    last until the shooter's next turn (in Solo, their next shot), and a new game clears them.
  - Five Pro Sound Effects library clips: ignite, crackle loop, strike roar, hit sizzle, out.
- 2026-10-08: The abilities rework is merged into `gui-v4`, the newest branch, which already
  holds `release`, `shop-lively` and `main`. The designer asked for only the new abilities and
  none of the old GUI code. The abilities branch changed no screen. In the files both sides
  changed (Config, Strings, Main, the save cleaner, docs), `gui-v4`'s GUI and economy v4 lines
  are kept and the abilities' lines added.
- 2026-10-08: The designer's test blocks are used up like a player's: `Config.LuckyBlocks.Test`
  Refill and SeedOnJoin are off (the timers still skip for them). `/giveblock` gives more.
- 2026-10-08: Odds are rounded plainly everywhere (`BlockOdds.percentText`; the designer:
  "roblox will not care"): whole from 10%, one decimal from 1%, two from 0.1%, one significant
  digit below. The "may not add up to 100%" line is gone. The Odds & Details popup takes the
  lively frame. Mystery shows its tiers first, then pity as 3/10 and 56/100 meters, with no
  description line.
- 2026-10-08: The restock stays as it is for now. The recommendation the designer took, for the
  economy pass: Mystery becomes the only roll, and the restock becomes a guaranteed shelf (an
  Epic, Legendary or Mythic block at a premium price, a small daily stock). It is part of the
  economy pass, which also looks at making Epics more common.
- 2026-10-08: VIP lives only in the Blocks tab's pair, shown until owned. The Passes tab is one
  row of four cards like the designer's reference, with new pictures. The VIP card's title is
  straight, its crown alone, its six perks in a panel.
- 2026-10-08: The win track is folded by default (a "Wins 3/10" pill with the next block). It
  opens by itself for 4 s after a match.
- 2026-10-08: Robux purchases get a rainbow THANK YOU! with an impact flash. The server now
  tells the buyer's client what landed (`PurchaseDone`). A gift thanks the giver and flies into
  the receiver's HUD. Money purchases only fly in. Both use the cue-equip sound.
- 2026-10-08: A VIP tag sits over the money pill (perks on hover or press). VIP's pots show the
  plain pay, a gold x2, then the doubled pay. `Money.shotPay` gives each grant its pay without
  VIP (`plain`).
- 2026-10-09: Pressing any Robux button plays the designer's "Gentle Metallic Bell Splash"
  (`Config.Audio.Ui.RobuxBuy`).
- 2026-10-09: The purchase thank-you is one line near the top, "Thank you! +x", in
  many-coloured letters, with a gold flash (green for a money pack). It waits for Roblox's
  purchase box to close and shows over open menus. A money pack plays the slot machine payout;
  other Robux items play the achievement chime.
- 2026-10-09: The Mystery card loses its "Starts Standard · 5 presses to climb" line (its six
  tier rows fill the box), and the Odds & Details pity head says just "Pity" (no "a sure
  thing"), the designer's notes.
- 2026-10-09: The Mystery upgrade screen gets its sounds, the designer's files: a magical
  whoosh shimmer as it opens, a rising shimmer on a press that lifts the tier (played as the
  press starts, so it rises into the impact), a soft shimmer select on a press that only shakes
  it (Config.Audio.Ui.MysteryOpen / MysteryUpgrade / MysteryKeep).
- 2026-10-09: The Mystery upgrade screen is 4 presses, not 5, and the block lands still a
  Mystery block (designer: "before you even click on it its still a mystery block ... just 4").
  The first press shows its starting tier; each of the other 3 may lift it one tier. Four
  presses can't climb Standard to Mythic one tier at a time, so the start is as low as the 3
  later presses allow: Standard for Epic and below, Uncommon for a Legendary, Rare for a Mythic
  (BlockDrop.startOf). Final odds and pity are unchanged; every block above Standard still
  visibly climbs.
- 2026-10-09: The purchase thank-you is smaller and higher (designer: "a little too big ... and
  unreadable, smaller and higher up"): 58 px (34 on a phone on its side), at most 60% of the
  screen's width, its middle 12.5% down, just under the rank badge (was 96 px, 92%, 20%).
- 2026-10-09: The power bar maps to speed through named shot speeds, not power^2.6 (designer:
  "the cue pull feels too low at like 30% and lower"; Config.Cue.PowerMode "Anchors",
  PowerAnchors, Physics/PowerShare). 10% 1.5 mph, 30% 3.4, 50% 5.7, 75% 10.2, 100% the same
  25 mph break, each in Dr. Dave's range for its shot (soft touch <1 mph, slow 1-2, medium 2-4,
  fast 4-7, power 7-10, break 25-30), straight in log speed between them. Measured in the
  game's physics, each bar level now sends a lone cue ball about that share of a full hit's
  travel (10% 9%, 30% 28%, 50% 46%, 75% 73%; the curve gave 3%, 14%, 42%, 80%), and its skid
  stays near the curve's, so balls still roll. A trial: /power old|new switches it in Studio.
  The bots invert the same mapping; the physics fixtures run on the curve they were recorded
  with (harness onRecordedCurve).
- 2026-10-09: /vip off makes the designer a regular player without VIP for the session
  (designer: "see what its like for a normal player without VIP ... everything"): the Store
  counts them as not VIP whatever the pass and the welcome offer say, so the Vip attribute every
  perk reads goes false (block timers on new blocks, no VIP money, the VIP tag gone, chat and
  name tags, rewards, the restock's VIP slot, Auto Spin) and the Shop sells them VIP. /vip on
  gives their own VIP back (or fakes the pass when they have none). A purchase still checks
  their real VIP. Blocks already held keep their timers.
- 2026-10-09: A pressed menu-column tile lingers (designer: "so you can still see the cue
  hitting the ball ... even on mobile when you click on it"): its menu hides the HUD at once, so
  the tile moves into its own ScreenGui (MenuColumnLinger, kept by the focus) at the same spot,
  stays 0.45 s over the blur playing its press (the CUES strike hits at 0.16 s, its ball is gone
  at 0.42 s), pops out and goes home (Config.UI.Menu.Column.LingerSeconds). Every tile does it.
- 2026-10-09: Opening Abilities flies the camera in instead of cutting (designer: "lerps
  smoothly but also very fast ... instead of like instantly showing them the UI"): from the
  player's camera to the stage's view in 0.45 s, 1 - (1 - t)^3 (fast off the mark, settling),
  its field of view easing 70 to 34 with it (Config.UI.UltScreen.Stage.FlySeconds, FlyPower;
  Reduce Motion still cuts). The pieces wait hidden 0.3 s (Open.LeadSeconds, a lead StageMath
  now supports for any screen) and pop in one by one as it arrives.
- 2026-10-09: Abilities: the pity rule line under the odds bars is gone; the pity pill says it,
  "Pity: 3 / 100 · Epic or better" with Epic in its purple. Free Reward's group and favorite
  cards: the line under the reward is in the reward's own style and size, and the group's reads
  "+10% Permanent Extra Money" (designer).
- 2026-10-09: Free Reward's group and favorite cards list what they give under "Reward:", each
  thing with a bullet and its words wrapping clear of it (designer: "add like a - or bullet
  point so its more clear").
- 2026-10-09: Odds & Details: the list reaches EdgePx (4) past its rows on every side, padded
  back in, so a bar's outline (drawn outside the bar) is never clipped at the list's edge
  (designer: "slightly cutoff on the left"). Every odds popup shares it.
- 2026-10-09: The Settings gear sits 12 px right of the rank HUD at its biggest (it grows about
  its badge on hover and press, 1.06 x 1.1), so the two never overlap (designer: "move the
  settings more to the right especially when the rank expands"; RankHud.grownRight).
- 2026-10-09: The Mystery Lucky Block's Odds & Details shows only its final tier chances and
  pity; the "Each Mystery block" rarity bars are gone. Each tier row on the Shop's Mystery card
  has its own small dice just after the tier's name that opens that tier block's odds (designer:
  "isnt there supposed to be odds shown for each block like a little dice icon for each"; "move
  the dice icon next to the rarity not next to the odds"). Free Reward's Mystery dice shares
  the popup.
- 2026-10-09: An empty ability slot equipped plays no ability: the Abilities screen says NONE,
  there is no ability bar in a match, the opponent's portrait shows no ability icon, and the
  server refuses an activation ("NoUlt"). An unowned or unusable slot still plays as Fire Shot
  (designer: "when an empty slot is equipped it should be NONE ... should not be fireshot by
  default on an empty slot"). A fresh save still starts with Fire Shot in slot 1.
- 2026-10-09: The Shop's Blocks jump shows the Mystery Lucky Block (it was the backpack), and
  the left column's tiles are 12 px apart (was 4) so ABILITIES no longer touches the Free
  Reward gift (designer).
- 2026-10-09: Play Global on a pad shows the moment the host steps on, friends in the server or
  not (it waited 3 s, 5 s with a friend), and the "<name> needs an opponent!" request still goes
  out on step-on to everyone free, now with friends here too. The spawn pill offers Play Global
  while nobody else is free: alone, or every other player busy at a table (a game, its result,
  a full pad); someone waiting on a pad with room is free (designer: "also suggest it if
  everyone in the server is currently busy").
- 2026-10-09: Any copy of a sellable cue can be sold from its big card, the last one too (the
  button is "Sell"; the chooser goes up to every copy). Selling the last copy always asks
  first: "You will lose it permanently. Are you sure?" The equipped cue keeps one (the server's
  rule), and the Index keeps it as found (designer: "if they just want to delete common cues
  they dont like ... for money").
- 2026-10-09: Super Bounce is back as a third Common ability beside Eagle's Eye and Fire Shot
  ("just more in the pool"), restored as it was before the third rework round (its physics,
  look, sounds, icon and tests); saves that held it on 2026-10-08 keep Fire Shot.
- 2026-10-09: Fire Shot's look: the aim is the regular guideline in orange (the rivers of fire
  under the lines are gone); low flames trail the ball along its path (and a longer ribbon);
  the scorch marks are a faint dark char line, end to end with no darker overlaps, with only a
  soft warm glow behind the ball, and each mark fades about a second after the ball burnt it
  (they stayed until the shooter's next turn). The designer: "make the aiming lines ... like
  the regular aiming lines but orange", "add a flame trail behind it", "make the scortch marks
  less noticeable ... disappear soon after they appear like 1 second".
- 2026-10-09: Verity's sounds: pressed, the designer's "Hello, I'm Verity!" (71231208892767, its
  first 1.95 s, where the words end); the monster's arrival, the designer's 135866700568043
  (was a swell); the chomp, gulp and bumps stay; her laugh and the burp are gone (designer:
  "get rid of the like laughing stock sfx ... burping sfx too its gross"). Their animations stay.
- 2026-10-09: Fire Shot's sounds: the loop while it burns is the designer's flame whoosh, very
  low (volume 0.03 of a clip eight times the old crackle's level); a ball hit plays the
  designer's bonfire burst (a cushion keeps the sizzle). Uploaded to the group
  (FireIdle 134062001061746, FireHitBall 132090886305703).
- 2026-10-09: Steel Ball pots one ball a use: the cue ball's next ball is always lined up, never guided in, however close (the designer: "its only supposed to auto for one ball and help line up another ball"; it had potted 3 in one turn). `CloseInches` removed, catalog `MaxBalls` 1, Worth 1.09 -> 0.66 measured (+0.54 / +0.68 / +0.74; the shot only, the line-up's next-shot value is not counted), which puts the Legendary mean (0.94) level with Epic's.
- 2026-10-09: Steel Ball's look is Gyro's steel ball: glossy saturated lime, a raised hexagon on each end, engraved lines corner to corner and a ring round the middle (the designer: "a simple hexagonal shape on two ends with line engravings, make sure its a lime saturated green"), replacing the chrome ball and its grip dots. PBR maps on a plain sphere (`tools/blender/abilities/steelball_v2.py`); a SurfaceAppearance cannot be built by a game script, so the template `ReplicatedStorage.AbilityLooks.SteelBall` is built in Edit (`tools/build_ability_looks.luau`) and lives in the place (a lime mirror without it).
- 2026-10-09: Catch-a-Ball's ball (and its icon) is black over white (the red is black: "the bottom is still white, but the iconic red is now black"), nothing at the seam but their edge, and an 8-ball for a button: no red, no black band, no square button (the designer: "get rid of the iconic like black lines that distinctively make it look like a pokeball"). Model 74906215963054, icon 79808360409738; the icon's ink outline comes from a plain sphere inside the shell, so no line crosses the ball.
- 2026-10-09: Guangdong Tiger plays the designer's commentator line (the Tiantian Billiards clip, 5.78-6.92 s: the voice, cut before the noise that follows) at the contact, with the swipe (`Config.Ults.Audio.TigerVoice`, 71314590570663).
- 2026-10-09: Guangdong Tiger's cut balls shatter exactly as Black Flash's ball does (the designer: "the cut effect for the balls should be exactly like black flash"): the shatter moved into `src/client/BallShards.luau` (Config.UI.BallShards, Black Flash's numbers unchanged), used by both; the tiger's two smoking halves are gone.
- 2026-10-09: Guangdong Tiger's shards stay 2.5 s (`Config.UI.GuangdongTigerFx.ShardSeconds`; the designer: they "linger for too long"); Black Flash's keep their 6.1 s.
- 2026-10-09: A lucky block still on its timer cannot be thrown (placed): the server refuses Throw with NotReady (the real timer for everyone; `Test.BypassTimer` stays for opening only), and the client shakes the block and opens the skip popup instead of the throw (the designer: "if they attempt to click it and place it anywhere (without VIP) it will give them to popup to skip timer"). Hotbar and bag tiles say READY! in green once a block is ready (a VIP's at once: VIP has no timers); the skip popup closes itself once its block is ready.
- 2026-10-09: **The ball streak** (designer's brief and interview; the mockup approved, "looks good! continue."): "STREAK x1" up to x8 for the balls a team pots in a row in its turn, in Press Start 2P just under the match popups, seen and heard by everyone seated at the table. The break is x1 however many drop; two balls in one shot step twice; a foul ends it and its ball does not raise it (designer's pick); a shot that pots none of yours or the turn passing ends it; teammates in 2v2 and 3v3 carry one team streak. Decided on the server at shot acceptance (`Rules/Streak`, in the ShotResult) so the screen and the money never disagree.
- 2026-10-09: The ball streak's look and sound: x1 white and silent, then yellow, orange, blue, purple, red, gold and a rainbow x8, a little bigger and wilder each level; pixel fire from x3 (orange, blue, purple, black-red, gold-white, rainbow; `tools/gui/streak_fire.py`); a tiny camera shake from x3 growing each level (designer's mid-brief addition). Sprays from the designer's Jet Set Radio file: the six single sprays for x2 to x7, the four-hit burst at x8, stacked over the pocket ding (designer: "keep everything as is for now, we'll see if the ding + spray mesh well together"). Uploaded to the group (Config.Audio.Ui.Streak2..8).
- 2026-10-09: The ball streak's money is a bonus, never a multiplier (the designer left the call to me): from x3 each counted ball pays a quarter of the ball pay more for each level from x3 (x3 +$25 ... x8 +$150), to the shooter only, boosted like match money, none in Solo or at a flat after-cap pay. Measured in 1,600 bot-duel games (`tools/streak_model.luau`): about +6% an hour, Classic about $7,750 (was $7,300). Chips fly in the level's colour; the result screen adds "Streak bonus (best xN)".
- 2026-10-09: The streak's flames duck under a match popup (found in the Studio check: YOUR TURN shows after every pot, and from x4 the flames sat behind its words). They shrink so their tips stay 4 px under the popup and grow back when it goes; with no popup the tallest (x7, x8) reach behind the top bar, which draws over them. The words keep the designer's spot rather than moving lower over the table.
- 2026-10-09: The ball streak moves up into the match popups' row and shrinks to about YOUR TURN's size (18 px letters, was 26; the same on a phone, as the popups are), stepping aside while a popup shows there and popping back after (the designer, on the first build: "font for all needs to be smaller and a bit higher up ... when a popup does occur ... itll briefly disappear"; it covered the far end of the table). The flames are redrawn low, hugging the words (x3's tips just peek over, x8's about a letter high; the designer's pick), new sheets uploaded; the duck under popups is gone with them.
- 2026-10-09: YOUR TURN (popup and sound) shows only when the table comes to a new shooter, not after each pot of a shooter who keeps it (the designer's pick, so a run's streak stays up instead of hiding 2 s after every ball). In 2v2 and 3v3 each rotating shooter still gets theirs.
- 2026-10-09: The ball streak sits 8 px lower than its row's middle (the designer: x8 "sort of overlaps under the top bar"; "lower it just a tiny tiny tiny bit"). Under YOU ARE SOLIDS / STRIPES it no longer hides: it slides down under the popup and back up once it fades, for everyone at the table (the designer: the break's ball then a second pot is common, and the second step was lost behind that popup). That popup now runs its full 3.5 s into the shooter's next turn (YOUR TURN no longer replaces it on a kept table).
- 2026-10-09: Past x8 the streak counts on (x9, x10; x9 is the most outside Solo, Solo goes to x15) in x8's rainbow look and size with no spray (the designer: "no extra sound effect"); it used to replay x8's burst. The money keeps its rule (x9 +$175).
- 2026-10-09: The ball streak 2 px higher: 6 px below its row's middle, not 8 (the designer, after seeing it).
- 2026-10-09: On a phone the ball streak shows only from a ball's drop until the next turn begins, then fades and stays away until the next counted ball (the designer, testing on an iPhone: it took too much of the screen and shrinking it would not help). "Phone" is the short screen the top bar already compacts for (Multiplayer.Style.ShortHeight); tablets keep it up all turn.
- 2026-10-09: The cutscenes' letterbox bars (the Legendary-and-up pulls, the 1v1 result, the Gift block) are never thinner than the HUD's rows at the screen's edges: Roblox's top row (where a phone's match top bar sits) and the hotbar, plus 6 px (`Config.Cutscenes.Letterbox`, client `Letterbox`). On a phone 12% of the height left both peeking out (the designer); in the iPhone emulator the bars are now 84 px, not 48. The result cutscene's screen also reaches the screen's very edge (it stopped at the safe area).
- 2026-10-09: The Mystery block's upgrade screen drops the line "The result is decided when you open it; the presses reveal it." and the pity counters (the designer: "get rid of the description up top"); the Shop's Odds & Details popup still says both. The block takes their room (BlockShare 0.35, was 0.32: on a phone about 23% bigger). Every tier's name has a "!" except STANDARD.
- 2026-10-09: The cutscene letterbox bars a little thinner on a phone (the designer: "a bit too much"): 90% of the way over the deeper of Roblox's top row and the hotbar, with no extra pad (`Letterbox.CoverShare`); 70 px on the iPhone emulator, was 84. The phone's match top bar still hides (it ends well inside Roblox's row).
- 2026-10-09: The coin flip shows players, not heads and tails (the designer: "no more need for heads or tails"). Each side of the coin is a token, a player's headshot on a white disc inside a drawn gold rim (coin 90 px, was 78): the side that breaks shows its breaker, the other side its first player (by slot). It starts on your side's token (a watcher: the host's side), turns 4 times or 4.5 when the other side breaks so it lands on the breaker with no jump, and reads WHO BREAKS? while it turns (YOU ARE HEADS / TAILS are gone). Landed: YOU BREAK for the breaker; everyone else NAME BREAKS, or NAME'S TEAM BREAKS in a 2v2 or 3v3 (teammates included; the designer approved the concept as drawn).
- 2026-10-09: Economy v5 steps 2-4 built (docs/prompts/ECONOMY_V5_PLAN.md 3.1-3.7): one climb ladder in `Config.BlockOdds.Climb` (Standard 50%, Uncommon 35%, Rare 18%, Epic 10%, Legendary 15%, Mythic 2.5% to the Secret; the Grand Opening Luck lifts Rare to 27% and Epic to 15% for 30 days from the deal's `StartsAt`); every climbing kind names its start (`Climb`); a block tier's row is now the climbed block (exactly that rarity); new blocks arrive unclimbed with no timer and climb on the server (save version 11); pity 10 / 40 with a 2 / 10 head start for new saves, Mystery blocks only.
- 2026-10-09: The climb's odds are worked out, not stored as rows (Claude's call): a climb from any start is a product of the ladder's steps, which is not a whole number of parts, so `BlockDrop` computes every list (`chances`, `rarityOdds`, `cueGroups`) from the steps, and each tier's `List` row is the climbed block (one rarity). No odds list can drift from the roll.
- 2026-10-09: The Sky block's own odds row is gone (Claude's call): it climbs from Standard like the plan says, so its v4 row had nothing left to roll. The Grand Opening and Starter rows stay.
- 2026-10-09: The Gift's 12-hour comeback wait is its own field, `Wait`, not its timer (Claude's call): an unclimbed block has no timer, so the Gift keeps the wait before its climb and climbs like any Uncommon block after it.
- 2026-10-09: Blocks in saves before version 11 all count as unclimbed and lose any timer left (Claude's call, the brief's "generous": pre-release test saves). Skip credits are now kept per product (`LuckyBlocks.Credits`, by product key), so a new skip product never needs a new save field; old counts move to their product (Claude's call).
- 2026-10-09: A climbed block trades as its own item, "Climbed:<tier>" (Claude's call): trading it as an unclimbed block would let it climb again. The trade window names it "Climbed Rare Lucky Block".
- 2026-10-09: The Secret reached by a climb is a cue from the top block row's Secret pool (Claude's call): the same cues the v4 Mythic block could give as its Secret.
- 2026-10-09: The tutorial's game-1 block is an Uncommon block that never climbs in the lesson (Claude's call): a Standard block now opens to Common cues only, and the lesson promises an Uncommon cue (answer 9). It arrives ready, stays Uncommon when held (the tutorial's `stay` hook) and opens as before; the funnel name "OpenedStandardBlock" is kept for the analytics.
- 2026-10-09: Until the GUI session builds the new screens, the old client keeps working through shims (Claude's call): holding an unclimbed block climbs it on the server first; the Mystery screen gets v5 odds; a Secret shows on today's Mystery screen as Mythic presses and then plays its cue's reel; the odds popups show the climb odds with the live luck; the result screen folds a win track money step into its bonus line.
- 2026-10-09: Win track money steps are counted like blocks for the anti-farm daily limit and the PC drop share (Claude's call): a money step is a track step like the others.
- 2026-10-09: Economy v5 step 5, the rewards (plan section 4): the win track pays Uncommon, $1,000, $1,000, Mystery, $1,000, $1,000, Mystery, $1,000, $1,000, Epic; the first week's days 1-6 are $5,000 + Mystery, Rare, $10,000, 2 Mystery, $15,000, 2 Mystery (day 7 is the Week One Cue, step 6); later weeks $5,000, Mystery, $10,000, Mystery, $15,000, Mystery, Rare + 2 spins; the 28-day track's day 14 a Rare and day 28 an Epic (`WeekBonus` too); VIP's daily block, ROOFTOP and invites an Uncommon block; the group 2 Mystery; playtime $1,000, Mystery, $2,500, $3,500, $5,000 + 1 spin; `Config.Planned` Lucky Shot Gold an Uncommon, Golden Shot Grey $7,500 + Mystery, Blue an Uncommon, Red $10,000 + Uncommon, Gold $25,000 + 1 Rare.
- 2026-10-09: The tutorial's Rare block line no longer says "opens in 5 minutes" (Claude's call): in v5 the first win's Rare block lands with no timer and climbs when tapped, so it now reads "You won a Rare Lucky Block! Tap it to see." (the tutorial session may reword it).
- 2026-10-09: Economy v5 step 6, the Week One Cue (plan section 5): a Legendary catalog row (`WeekOneCue`, "Week One Cue" in Strings) in no block, given on the first week's day 7 with its 2 spins (and by Claim All, as paid origin like Claim All's blocks); its copies count in existence like every cue, so its trade worth follows them.
- 2026-10-09: The Week One Cue is in the "Block" group with no odds rows (Claude's call): that group already trades, sells back, pays finder's money and fills the Index's Legendary row, so only one rule changed: the Grand Opening and Starter blocks' whole-pool rule now skips a block cue with no rows. Its effects tier is Legendary's; its look is the Classic cue's colours drawn as bands (no skin) until its art exists, and its bag card shows no drop chance.
- 2026-10-09: Daily rewards can carry cues (`Cues` in a Config row, `cues` in a reward; Claude's call): the reward words on today's Rewards screen name the cue ("Week One Cue") until the GUI session draws its card.
- 2026-10-09: Economy v5 step 7, the restock (plan 6.2): two shared slots plus VIP's; slot 1 rolls its own table (Epic 75.56%, Legendary 21.11%, Mythic 3.33%: always Epic or better), slot 2 Rare 55% / Epic 34% / Legendary 9.5% / Mythic 1.5%, VIP's 40 / 40 / 16 / 4; money prices $49,900 / $249,000 / $1,290,000 / $4,990,000; stock and Robux prices unchanged. A Legendary or better in 32.8% of restocks (46.2% with VIP's), a Mythic in 4.8% (8.6%).
- 2026-10-09: The restock's odds line reads "Slot 1: Epic or better · Slot 2: Rare 55% · ..." (Claude's call, a shim until the GUI session rebuilds the restock for two shared slots; the panel now draws three cards where it drew four).
- 2026-10-09: Economy v5 step 8, the Mystery shop (plan 6.1): $14,900 each, 5 for $66,900 (v4: $4,900, 10 for $44,100); the Robux 5-pack `Mystery5` is a Config row with Id 0 ("Coming soon") until the designer approves its price; `Mystery10` and `Mystery10Sale` are retired (never deleted: an old receipt still pays its 10 blocks); the launch bonus makes the 5-pack 6.
- 2026-10-09: The 1 R$ timer skip is live (designer, 2026-10-09: "for uncommon/rare the skip timer should be reduced to just 1 robux"): `LuckyBlockSkip1` (product 3717460488, made with tools/roblox_products.py --only LuckyBlockSkip1 after a dry run) covers 5 minutes or less left, every climbed Uncommon and Rare block; the 4 / 9 / 15 R$ rows stay. Saved credits are kept per product, so none changed price. It has no icon yet (no uploads in this run).
- 2026-10-09: The Mystery band's Robux button says "Coming soon" for a product not made yet (Claude's call: the 5-pack would otherwise show its placeholder price and refuse the press). Mystery1 stays 5 R$ on Roblox until the designer approves the Robux proposal; each v5 Mystery is worth about 8x a v4 one, so that price is in the proposal's first line.
- 2026-10-09: Economy v5 step 9, quick reveal and "Open all" (plan 3.8): `Config.LuckyBlocks.QuickReveal` (Common, Uncommon; about 1.5 s) for the GUI session's reveal, and the BlockRequest "OpenAll": every ready climbed Standard and Uncommon block in the hotbar and bag opens at once (not the one in the hands or a thrown one), oldest first, at most 50 a press, one press per 3 seconds on top of the token bucket; the answer lists each cue for a short summary.
- 2026-10-09: "Open all" opens each block exactly as a normal open does (the save, the copies in existence, the tutorial's hooks) and skips any plan that would need a Unique copy number (Claude's call: the Standard and Uncommon rows hold none, so this never happens today).
- 2026-10-09: Economy v5 step 10, the "1 in N" (plan 3.9): every Legendary-or-better unboxing message carries the chance of that exact cue from the block it started as, with the odds live at its climb ("Painicane unboxed a Legendary Cue! (1 in 2,610)"; from a Mystery block a Legendary cue is 1 in 2,610, a Mythic cue 1 in 6,510, the Eclipse Cue 1 in 84,700). The server sends the number (`oneIn`), the banner words it (`Strings.Banner.OneIn`).
- 2026-10-09: The "1 in N" rounds to the nearest 3 significant figures, not up (Claude's call, matching the plan's examples: 1 in 2,614.4 shows 2,610); a Mystery block's pity is left out of it (the natural odds), and a block that never climbs (Grand Opening, Starter) uses its own row.
- 2026-10-09: Economy v5 step 11, trade worth (plan section 8): an unclimbed block's worth comes from its climb odds and the live copies of each cue, a climbed block's from its tier (exactly one rarity); `Config.Trade.BlockExists` is refilled from the v5 model at day 30 and a new `ClimbedExists` holds the climbed blocks' fallback (Claude's call: the two are worth very different amounts, so one table would mislead the lopsided warning before the counters load).
- 2026-10-09: Economy v5 step 12, the model: `tools/economy_model.py` now does v5 natively from Config (climbs from any start with the Grand Opening Luck, money steps on the win track, the restock's own slot-1 table, the Week One Cue, the pity head start, `--sell` for finder's money, the Index rows and selling back). Its default run matches the plan's 7.1 within about a point (Epic 58.1 / 66.6 / 64.5%, Legendary 13.6 / 20.7 / 17.5%, Mythic 2.4 / 4.7 / 4.4%, Secret 0.08 / 0.14 / 0.13%, the Week One Cue 0.2 / 15.8 / 29.0%); `--compare` shows v4 from a frozen copy of its Config (`tools/economy_config_v4.json`, the export at f4e17c0) and reproduces v4's numbers exactly. New `exists` command for `Config.Trade.BlockExists`.
- 2026-10-09: The copy-number timeline under v5 (`economy_model.py copies`, reported, nothing changed): each cue's #100 is gone by about day 1 (Rare), day 1 (Epic), day 4 (Legendary), day 7 (Mythic) and day 29 (the Secret); the Week One Cue's by day 9 (v4: day 1, 4, 11, 22 and 35).
- 2026-10-09 (designer, economy v5 answer 1): a Legendary stays about one a month for a 1-hour player after the launch month ("Strict"): the ladder's Rare to Epic 18% and Epic to Legendary 10%.
- 2026-10-09 (designer, economy v5 answer 2): Mythic and the Secret are goals grinders can reach: Legendary to Mythic 15%, Mythic to the Secret 2.5%, no copy cap on the Secret.
- 2026-10-09 (designer, economy v5 answer 3): a more generous launch through the Grand Opening Luck, x1.5 on Rare to Epic and Epic to Legendary for 30 days, shown by "some clover next to the money/VIP bars in the bottom left; clicking on it says extra luck for release".
- 2026-10-09 (designer, economy v5 answer 4): if cues lose value later, add new cues each season and retire old ones from blocks; never lower printed odds.
- 2026-10-09 (designer, economy v5 answer 5): every block climbs from its name, and the name is its floor (v4: the floor was the rarity below the name); the tier a block ends on is the cue's rarity.
- 2026-10-09 (designer, economy v5 answer 6): 4 daily wins give a block: wins 1, 4, 7 and 10 (v4: all 10).
- 2026-10-09 (designer, economy v5 answer 7): win 10 gives an Epic block.
- 2026-10-09 (designer, economy v5 answer 8): no calendar Legendaries ("Neither"; keep day-7 retention high, more important than value); then in chat, day 7 of the first week is the Week One Cue ("it should be tradable"; "dont worry about that either to prevent farming, all of that will be worried about IF this game does good") and day 28 of the track an Epic block.
- 2026-10-09 (designer, economy v5 answer 9): Robux buys Mystery blocks, like today.
- 2026-10-09 (designer, economy v5 answer 10): the Mystery block's money price goes up and the bundle gets smaller ("lowering the amount you can buy for 10? like 5 or something? you let me know and make a valid decision"): $14,900, 5 for $66,900 (the plan's call 2.1).
- 2026-10-09 (designer, economy v5 answer 11): Epic pity by the 40th Mystery block (v4: the 100th).
- 2026-10-09 (designer, economy v5 answer 12): the restock's slot odds Rare 55 / Epic 34 / Legendary 9.5 / Mythic 1.5%, each block priced by what it promises.
- 2026-10-09 (designer, economy v5 answer 13): the restock banner in every server stays and one slot is always Epic or better ("is 3 restocks even too much? maybe just 2, +1 for VIP? you make an informed decision": 2 slots plus VIP's, the plan's call 2.2). This sits beside ECONOMY 11.7's "never always-on Epic blocks": a rotating 10-minute slot at a guarantee's price, the designer's newer call.
- 2026-10-09 (designer, economy v5 answer 14): quick reveal and "Open all" for Common and Uncommon results, a server message with the "1 in N" for Legendary or better, and pity bars with a head start.
- 2026-10-09 (designer, economy v5 answer 15, the vision): "Should feel special, but also at the same time to each to their own feel rewarding to own, not too common where everyone walks around with one but not impossible (achievable easier through means of robux obviously, or lots of grinding)." The plan's simulated shares (plan 7.1) are the targets now, replacing v4's ranges.
- 2026-10-09 (the v5 plan's call 2.1, approved with the plan): the Mystery bundle is 5 for $66,900 (10% off); 5 is about 1.7 days of a 1-hour player's money where 10 would be 3.4. The Robux 10-pack becomes a 5-pack in the Robux pass.
- 2026-10-09 (the v5 plan's call 2.2): the restock has 2 shared slots plus VIP's, the first always Epic or better (Epic 75.56%, Legendary 21.11%, Mythic 3.33%): the same rare stock as 3 random slots, a real Epic every restock, and each restock more of an event.
- 2026-10-09 (the v5 plan's call 2.3): Legendary to Mythic 15% (Strict had 7%) and Mythic to the Secret 2.5% (Strict had 5%): about 5% of active players own a Mythic; the Secret stays a trophy.
- 2026-10-09 (the v5 plan's call 2.4): the Week One Cue is tradable and sellable like any Legendary, with no farming limits for now.
- 2026-10-09 (the v5 plan's call 2.5): playtime keeps five gifts (the Free Reward screen shows five tiles): $1,000, a Mystery block, $2,500, $3,500, $5,000 + 1 spin.
- 2026-10-09 (the v5 plan's call 2.6): every block climbs like the Mystery today: a new block shows OPEN!, a tap opens the 4-press climb screen, and the climbed block waits on its tier's timer; the Gift keeps its 12-hour wait before its climb.
- 2026-10-09 (the v5 plan's call 2.7): a climb that reaches the Secret gives the Secret cue at once; there is no Secret block.
- 2026-10-09 (the v5 plan's call 2.8): the pity head start: a new save's bars start at 2/10 (Rare) and 10/40 (Epic), so the first Epic is guaranteed by the 30th Mystery block.
- 2026-10-09 (the v5 plan's call 2.9): the Grand Opening Luck starts with the Grand Opening's `StartsAt` and lasts 30 days on its own clock; only the two middle steps are boosted.
- 2026-10-09 (the v5 plan's call 2.10): Claim All still claims day 7, so the Week One Cue can be bought early with it; its six prices are redone in the Robux pass.
- 2026-10-09 (the v5 plan's call 2.11): Lucky 8 and the Gift climb from Uncommon, the Sky block from Standard; the Grand Opening and Starter blocks keep their approved odds and never climb.
- 2026-10-09 (the v5 plan's call 2.12): ROOFTOP gives an Uncommon block (everyone gets it); the LIKES codes stay as they are (rare celebration gifts, switched on by hand).
- 2026-10-09 (the v5 plan's call 2.13): pity is for Mystery blocks only, and gives exactly the guaranteed rarity.
- 2026-10-09 (the v5 plan's call 2.14): the "1 in N" is the chance of that exact cue from the block it started as, with the odds live at the climb, to 3 significant figures.
- 2026-10-09 (the v5 plan's call 2.15): win 10's Epic block makes grinders strong (a free 3-hour player climbs to Legendary or better about 4 times a month after the launch); if that feels too common, a Rare block on win 10 is the lever.
- 2026-10-09: Economy v5 step 13, the docs: `docs/ECONOMY.md` rewritten for v5 (the stale 28-day track in its 10.2, Rare / 2 Rare / 2 Rare / Epic, fixed to v5's $50,000 / Rare / $150,000 / Epic; the Claim All products, the retired Lucky Spins and the Starter Pack's 29 R$ caught up too), GDD sections 11 and 12 (and the tutorial lines in 14 that named the Standard block), and `docs/prompts/ECONOMY_V5_HANDOFF.md` for the GUI, tutorial, thumbnail and cue-art sessions.
- 2026-10-09 (designer, on the Robux proposal: "My proposal"): the v5 Robux prices are live. Mystery block 7 R$ (was 5), a new 5-pack `Mystery5` 29 R$ (product 3717476154; 6 blocks during the launch bonus; "35 R$ one by one"), the 10-pack `Mystery10` off sale on Roblox (never deleted; an old receipt still pays 10), restock Rare 39 R$ (was 15) and Epic 149 R$ (was 99), Legendary 599 and Mythic 1,699 unchanged, Claim All's later weeks 79 / 69 / 35 R$ (were 129 / 99 / 59), the first week's unchanged, the Golden Shot 15 R$ (planned). New texts on Roblox: VIP and the VIP offer say "an Uncommon Lucky Block every day", the first-week Claim All products name the Week One Cue, Mystery1 climbs "as high as the Secret". Made with `tools/roblox_products.py --only Mystery5`, then `--sync --only` for the changed keys, each after a dry run. The Robux route stays about 2.4-2.6x better value than money for Mystery blocks; every cheapest pull sits inside the designer's feel ranges. Until `gui-v4` is published the live game sells these prices with its older grants.
- 2026-10-09 (designer): the first week's Claim All with 1-2 days left stays 299 R$, though selling its Week One Cue ($250,000) beats the 399 R$ money pack once per player.
- 2026-10-09 (designer): the tutorial's first lucky block under v5 is a Mystery block whose climb is scripted (Standard to Uncommon on screen, ready at once), as tutorial v2 already plans; gui-v4's interim Uncommon block that skips its climb goes once the tutorial merges. The server needs a hook that forces a climb's final tier (the GUI brief's economy step).
- 2026-10-09 (designer): the Mystery block's pity bars (Rare by 10, Epic by 40) show only in Odds & Details and on the shop's Mystery card, never on the climb screen (it stays clean, as asked earlier that day).
- 2026-10-09 (designer): the economy v5 GUI run (`docs/prompts/ECONOMY_V5_GUI_PROMPT.md`) updates the screens already built rather than rebuilding them: same layouts, looks and animations, only v5's numbers, odds, prices, rewards and words, plus the few small pieces v5 needs (the Secret rung, the unclimbed/climbed mark, the quick reveal, Open all, the Grand Opening Luck clover, the win track's money tile, the result screen's track line), each shown to the designer in Studio; no concept art for this run. Trading stays out of the release, so the run leaves it alone (shim 6 stays).
- 2026-10-09 (designer): the GUI run works beside the tutorial terminal (`tutorial-v2`): it may add tutorial-facing pieces outside the tutorial's own files (the scripted climb hook is added beside `stay`, `TutorialService` untouched), checks `git merge-tree` against `tutorial-v2` after every step, and merges `tutorial-v2` into `gui-v4` once, with the designer's yes, when the tutorial is at a stopping point, keeping both sides' work.
- 2026-10-09 (designer, GUI run step 2): every unclimbed lucky block opens the climb screen from its own tier and can't be held or thrown before it climbs; the ladder's Secret rung is the Mythic block darkened with a red "?" (no Secret block art), a Secret climb slams SECRET! and goes straight to the pull cutscene and the YOU GOT card; an unclimbed block carries a small gold up-arrow mark (ink disc, white ring) at its slot's top-right in the hotbar and bag. Built on Claude's judgment at the designer's word ("use your judgment"), for review from the screenshots.
- 2026-10-09 (designer): after a second look at v4 against v5 (block names as guaranteed floors, rarity-named blocks against themed blocks with different odds), economy v5 stays as built.
- 2026-10-09 (designer, GUI run step 3): the quick reveal is the result card alone (no reel, a little smaller, its rays and sting), gone by itself after 1.5 s; "Open all" is a green button right of the hotbar's bag button, shown while a ready climbed Standard or Uncommon block can open, and its summary shows one cue card per cue with "x3" for repeats under "37 BLOCKS OPENED!". Built on Claude's judgment at the designer's word, for review from the screenshots.
- 2026-10-09 (designer, GUI run step 5): the Grand Opening Luck's clover is a small navy badge with a green rim and a rocking four-leaf clover right of the VIP tag (in its place without VIP), shown only while the luck runs; hover or tap opens a card: "Extra luck for the release!", each boosted step as "Rare to Epic: 27% instead of 18%", and "Ends in ...". Built on Claude's judgment at the designer's word, for review from the screenshots.
- 2026-10-09 (GUI run step 6, on the designer's "use your judgment"): the shop's restock shows each slot's odds under its own card (VIP's too) and slot 1 wears a tilted "Epic or better!" tag; the Mystery card's pity is two bars side by side (Rare by 10, Epic by 40); a Robux product off sale shows its price greyed instead of "Coming soon"; the Grand Opening card shows the live Robux prices like every other card, its struck-through price the single block's live price times the count.
- 2026-10-09 (GUI run step 7, on the designer's "use your judgment"): a money step of the win track is the cash bundle over "$1K" (faded under its tick once won), the folded pill shows it as the next step, and the result screen gives it its own "Win track +$1,000" line after the win bonus.
- 2026-10-09 (GUI run step 8, on the designer's "use your judgment"): the first week's day 7 card shows the Week One Cue itself (its picture over its rarity's glow, its name and "Legendary"), and a claimed cue flies to the CUES button.
- 2026-10-09 (designer's question, my recommended fix): a row's dice on the shop's Mystery card opens "Epic cues" with the line "If your Mystery block climbs to Epic, you get one of these:", never titled "Epic Lucky Block", because a real Epic block (the restock's) climbs from Epic and has different odds.

- 2026-10-09 (designer, "everything yes" on the v5.1 plan page): economy v5.1 "Lively". A Mystery turns into a real lucky block first, the same block the restock and rewards give, which then climbs from its name: its roll on the same 4-press screen steps up 30 / 25 / 10 / 5% (Standard 70%, Uncommon 22.5%, Rare 6.75%, Epic 0.7125%, Legendary 0.0375%; never past Legendary; the Grand Opening Luck boosts the climb, not the roll). The Mystery costs $19,900 or 5 for $89,900, 9 R$ or 5 for 39 R$ (45 one by one), and the 15-minute playtime gift is $2,000 instead of a Mystery. Reason: v5 made a Mystery's result final, so a Mystery that stopped on Rare had no suspense; the price and playtime pay for a Mystery worth 1.7 times v5's and keep the economy just above v5 (Legendary owners 22.2% at day 30 against 20.7%). This reverses the "Epic cues" relabel earlier the same day: a row's dice on the Mystery card opens that block's own Odds & Details again, because it is now the same block.
- 2026-10-09 (v5.1 build, Claude's call inside the approved rules): pity is checked at the Mystery's roll and counts the cue it finally gives; a roll that lands on a Rare-or-better block resets that counter at once (so two Mysteries rolled while pity is due are never both lifted), and the counters it can't settle yet ride on the block as a hidden mark (`Block.Pity`, "Rare" or "Epic") that counts when the block climbs. No save version bump (old saves have no marks; the fixer keeps a mark only on an unclimbed tier block). A traded turned block loses its mark (trading is not in the release).
- 2026-10-09 (v5.1 build, found in the Studio check): the shop's pity bars now refresh after a Mystery rolls or a marked block climbs (they used to keep the number from joining until the next ShopState), and the Mystery's Odds & Details adds "Ends with a cue that is", each rarity's chance over both steps, which the plan page promised.
- 2026-10-09 (hand-off to the tutorial session, `tutorial-v2`, not touched by this build): with v5.1 the tutorial's scripted first Mystery no longer lands on a finished Uncommon. `LuckyBlockService`'s `climbScript` / `forced` on a Mystery now names the block it turns into (an Uncommon block, unclimbed and ready, pity still counted), and that block then needs its own climb: script that climb too (`forced = "Uncommon"` on the Uncommon block gives an Uncommon cue, ready at once), or use `stay` on the Mystery (a Standard block, no pity counted). The tutorial's game-1 Uncommon block with `stay` works as before.
- 2026-10-09 (designer, "temporarily just make grand opening openable right now for soft launch with no end date"): `Config.Shop.Deals.GrandOpening.SoftLaunch` opens the Grand Opening block for money and Robux with no end date while `StartsAt` is 0; the card hides its "Ends in" timer. My call: the soft launch does not start the Grand Opening Luck or the launch bonus (both stay tied to the real `StartsAt`), and Studio no longer forces its own 30-day window while the soft launch is on, so Studio matches live.
- 2026-10-09 (designer, "only mystery lucky block is supposed to have upgrade chances", then "Reel only, same odds"): economy v5.2. Only the Mystery keeps its 4-press upgrade screen (its roll turns it into a block). Every other block is held, thrown and opened as before v5, and its climb is rolled at the open (`PlayerData.planLuckyOpen`, `BlockDrop.climbFor`, the same ladder and launch luck); the reel's strip is that climb's odds, so a Rare block's reel shows Rare and Epic cards and rarer at their real chances. The odds did not change. Reason: v5 had put every block on the upgrade screen, my presentation call in the v5 plan (section 3.5) that the designer never saw spelled out. Claude's calls: each block waits its own name's timer (v5's timer went with the tier climbed to); a block a Mystery turned into starts that block's timer at the turn; "Open all" now opens unclimbed Standard and Uncommon blocks and reels any that climb to Rare or better after its summary; the tutorial's game-1 Uncommon block lands ready (`Reward.ready`, set by Ranking) so its lesson needs no wait; blocks already climbed on v5's screen keep opening from their tier's row.
- 2026-10-09 (designer, "its supposed to go through the scroll everytime i dont remember ever saying to skip the spin"): every lucky block open spins the reel again; the quick reveal for Common and Uncommon cues (v5 plan 3.8, from answer 14 on the review page) is off (`Config.LuckyBlocks.QuickReveal` empty, the code kept). It felt new tonight because v5.2 took away the climb screen that used to play before it. My call: "Open all" keeps its one summary for Common and Uncommon cues (its own list, `OpenAll.Summary`) and reels the rest, since a reel per block would undo the button.
- 2026-10-09: (run assumption) Tutorial v2: a new save starts with 0 ability spins and its
  first spin lands on Magnet for every new player, not only on the tutorial's path; the brief
  asked for it to be logged.
- 2026-10-09: (run assumption) Tutorial v2: Bronze's Mystery block waits in Rank like every
  other rank reward (no BlocksAtOnce for it), so claiming is one rule; dropped if it breaks
  something.
- 2026-10-09: (run assumption) Tutorial v2: in game 1 the shot clock stops on the player's
  second away turn, so two timeouts in a row (Config TimeoutLimit) can never lose game 1.
- 2026-10-09: (run assumption) Tutorial v2: the tutorial's own Uncommon block is ready at once
  (a block on its timer can't be thrown since today); only that one block.
- 2026-10-09: (run assumption) Tutorial v2: the tutorial bot walks at the players' speed
  (Config.Hub.WalkSpeed), not Roblox's default 16, or it arrives late and looks slow.
- 2026-10-09: (run assumption) Tutorial v2: game 1's hidden help is one physics effect
  (Tutorial/Assist, "TutorialAssist") registered beside the abilities; on the ability turn the
  player's armed ability runs inside it.
- 2026-10-09: Tutorial v2 plan approved by the designer with every recommended pick
  (`~/Desktop/8ball-refs/tutorial/tutorial-v2-plan.html`): game 1's hidden help is today's
  Magnet pull only on the two lesson shots (turn 2, the ability turn) and an invisible pull
  (at most 10 degrees, no braking) everywhere else, with a 10-degree scratch guard; turn 2 at
  the player's own power; the ricochet is honest luck (about 1%); game 1's length target is
  about 4 minutes (median); the bot waits in a closed kiosk at (0, 36) (Plan B); Max Players
  24 with the team-table backup; the tutorial block's Uncommon is the Cosmo Cue; arrow look A;
  the like reward is removed (a polite ask stays); in-server rank windows 2/4/7/12 divisions.
- 2026-10-09: (run assumption) Tutorial v2: a fair first game (path R) that is won leads into
  the same guided chain as the rigged game (Result, Rank, Mystery, Place, Cues, Abilities,
  Soft), without the bot's line; a lost fair game goes back to the arrow (the rigged game comes
  the next time they sit alone).
- 2026-10-09: (run assumption) Tutorial v2: Rank and the money pill come back at the Rank step
  (the claim's money flies to the pill); the other icons pop in with the soft part.
- 2026-10-09: (run assumption) Tutorial v2: an error in tutorial code ends the tutorial as
  Skipped (the first-time hints still come) and logs TutorialError; the soft part ends at the
  next finished match (game 2), win or lose.
- 2026-10-09: Controller shooting (tutorial v2 4.10, the approved default): hold R2 or A to fill
  the power bar over 1.4 s with a slow start (power = (time / 1.4 s)^2), held at full; a tap under
  0.1 s does nothing; B during a pull calls it off (B leaves the table only when nothing is
  pulled). Versions B (trigger depth) and C (freeze, press again) sit behind
  `Config.Input.Gamepad.Shoot.Mode` for the designer to try with a real controller.
- 2026-10-09: Tutorial v2 game 1's bot (designer): no hiding place and no lift on the roof (the
  plan's Plan B kiosk is dropped). The bot joins the server when the player does, out of their
  view, and strolls round the roof near the tables like any player, then walks over and steps
  onto their pad 0.5-2 s after them. It stays within reach of every table the player is likely
  to pick (`Config.Tutorial.Bot.RoamReachStuds`).
- 2026-10-09: Tutorial v2 game 1's second ball (designer): no ricochet. Where two balls in one
  shot can't be set up, two of the player's balls sit lined up with a corner pocket and the
  player is encouraged to play the combination (one ball into the other, which drops); it earns
  NICE SHOT!. (Run assumption, until the designer says otherwise: it is the shot right after
  the aim lesson's pot, with a short pointer prompt; "x2!" stays as a match feature.)
- 2026-10-09: Tutorial v2 game 1's lessons are read from the table at each of the player's turns
  (Tutorial/Plan; Tutorial/Rig picks them inside the match engine): the break, the aim lesson
  (turn 2), the combination (when two of their balls are lined up with a corner pocket and the
  cue ball has a clear line; it waits up to three turns, then is dropped), the ability lesson
  (it waits up to two turns for a close setup). Their ability bar fills when the ability lesson starts (not
  after the aim shot), and "use your ability" shows on at most two turns they ignore it. (Run
  assumptions.)
- 2026-10-09: Tutorial v2 game 1's clock (run assumption for "the clock pauses while a lesson
  prompt is on screen"): no clock on a turn with a lesson (the break, the aim lesson, the
  combination, the ability lesson), on SELECT WHICH POCKET and on the first ball in hand; none on
  the player's turn after one they let run out (away: two timeouts in a row can never lose game
  1, and "Your turn!" shows). Every other turn has the usual 20-second clock.
- 2026-10-09: The tutorial bot never uses its ability in game 1 (a v1 bug: it could arm Fire Shot,
  which doubles the cue ball's speed and spoils its worked-out shots). The ricochet steer is gone
  from the hidden help (the combination replaced the ricochet).
- 2026-10-09: Tutorial v2's rigged break deals its own rack order (`Config.Tutorial.Break.Layout`,
  used only for game 1 through `Rack.newGame`'s layout): the numbers are chosen after the break's
  physics (a break's motion changes only a little with which number sits where; each deal is
  replayed and kept only when it still does the job), so the same invisible break can drop two
  solids and leave a combination pair. The rack keeps the real rules: the 8 in
  the middle, one solid and one stripe in the back corners. Every other game keeps the standard
  order.
- 2026-10-09: Tutorial v2's glowing pocket (the aim lesson's target, the combination's pocket) is
  a gold neon disc over the hole plus a gold ring drawn on the tutorial's screen layer at the
  pocket's spot, at least a fixed size on screen so a far corner still shows; while a pocket
  glows, the instruction line moves just under it when it would cover it.
- 2026-10-09: Tutorial v2's hidden help bends the cue ball toward the lesson's ghost point on the
  aim lesson and the combination (when the shot is within 10 degrees of the lesson's line; the
  same aim help that used to start only after six misses). A combination is unforgiving: 2
  degrees off onto the back ball sends it about 30 degrees wide, which no invisible bend on the
  balls could save; with the cue ball's bend it drops from 6 degrees off either way.
- 2026-10-09: Tutorial v2's combination has a second way in (run assumption): while it waits
  (up to three turns after the aim lesson), ball in hand starts lined up straight behind the
  pair's back ball (after "drag the white ball", the combination's pointer shows), and the bot's
  later visits prefer to leave the player a line onto the pair. Dragging the ball elsewhere moves
  the plan with it (or drops the lesson when no line is left).
- 2026-10-09: Tutorial v2 game 1's 8 gets the aim lesson's hidden help (the brief's "help on the
  8 toward the called pocket"): on its line into the called pocket the cue ball bends toward its
  ghost point, and the 8 rolls a little farther on its way in. Without it an easy 8 (a small cut,
  under 30 inches) dropped only about half the time in the simulations, and each miss costs a bot
  visit.
- 2026-10-09: Tutorial v2's bot never parks one of its balls where the 8 must be hit from, and
  when even ball in hand could not line up any of the player's balls (a simulated game looped
  forever: their last ball by a corner whose jaws held the 8), its next shot nudges one of their
  balls into the open with a soft foul (it looks like a bot blunder and hands them ball in hand).
  The one exception to "the bot never touches the player's balls".
- 2026-10-09: Tutorial v2's chain (the brief's 4.5, steps 1-9). The Mystery block's upgrade
  screen is rigged on the server for that one block: the bottom tier until the third press, then
  Uncommon (`Config.Tutorial.MysteryReveal`), and it is ready at once (a block on its timer cannot
  be placed, so "Place it!" could not happen). The open lands Cosmo Cue (the designer's pick).
- 2026-10-09: Every lucky block reel now holds still about 1.2 s on its cards before it spins
  (`Config.UI.Reel.Reel.StillSeconds`; the brief's 4.11, for everyone). The tutorial's reel also
  opens on a fixed spread of tiers, one card each (Uncommon, Rare, Epic, Rare, Legendary under
  the marker, Uncommon, Epic, Mythic, Rare: `Config.Tutorial.ReelOpening`, a different cue of the
  tier each time; every one is in the Uncommon block's own pool), and its Secret card (Eclipse
  Cue, "1 in 500,000") flashes past once at the latest place the reel's showcase safeguard
  allows, nine cards before the stop. Run assumption: the brief says "a glimpse while spinning"
  without a place.
- 2026-10-09: Tutorial v2's Abilities step fills the code box in by itself on a controller (no
  typing there) and for anyone still on it after 30 s; after 60 s the server redeems RELEASE for
  them once, so nobody is stuck at a text box. Codes are matched in any case ("release" works).
- 2026-10-09: The tutorial's pointing hand turns upside down (pointing down from above) when
  pointing up from below would put 40% of it off the screen's bottom (the hotbar slots).
  Button pictures in its lines sit on a dark disc, so Roblox's light pictures read on a white
  background. Its line drops under the top banner while one shows ("New in your Index: ..."
  sat on top of it).
- 2026-10-09: Bug fixes found while testing the chain, for every player: the spin screen's count
  did not update after claiming a rank reward with spins (`claimRank` was not one of the changes
  that resend it); the Block funnel never logged "Opened" for a Mystery block (its upgrade
  changes its kind; the funnel now follows the new kind), and its /funnel lines name the kind.
  The two "Block 1 Got" lines after game 1 were two real blocks (Bronze's Mystery block, paid at
  once today, and the first win's Rare).
- 2026-10-09: Tutorial v2's soft part (4.5 steps 10-14): after the chain the remaining icons pop
  in one after another (0.15 s apart, about 1 s). A click-once red "!" sits on the Shop, Free
  Reward, the offer tile and the money "+" until each is clicked once (the Daily Challenge's waits
  for `Config.Tutorial.Soft.ChallengeBuilt`); Free Reward also glows (the house gold rays round a
  breathing glow, on the column's rays layer so they never cover the next tile) and bounces;
  after game 2 the Shop gets the same glow until it is opened. Only players whose soft part began
  get them (not skippers so far; step 12 decides theirs).
- 2026-10-09: "Win a Match 0/1" sits top centre (under the top banner while one shows), only in a
  quiet lobby. A win since the soft part began (counted on the server, even after game 2 was
  lost) shows "1/1", then "Done!", and the daily win track, which waits while the quest is open,
  takes over. The onboarding funnel logs QuestDone.
- 2026-10-09: The invite popup, once: a small card 2.5 s after the icons are out in a quiet lobby:
  "Invite a friend?", the Rare block, "You both get a free Rare Lucky Block!", when it comes (the
  friend's first win), Invite and a big X on its corner (B on a controller). Any Invite press
  logs the Social funnel's Invited.
- 2026-10-09: Play Global wears a pulsing gold ring in the soft part (a round glow hardly shows
  round a wide pill), and the spawn pill stays up off the pads in a public lobby until Play
  Global is pressed or its X. Free Reward's first open lands on Daily; its join and favorite get
  the gold ring and a light sweeping over them until each is pressed (or claimed). After game 2
  the first-win Rare block's hotbar slot gets the gold ring once it is ready, until it is taken in
  hand (its own READY! is the word; no second "Ready!").
- 2026-10-09: Free Reward shows "Enjoying it? Leave a like!" under the invite card for everyone,
  with no reward (decision 7: a server can't check a like). In the soft part it gets the ring
  once; it counts as seen when the menu closes after it was on the page.
- 2026-10-09: The hub's offers share one tile: the Starter Pack and the VIP offer, each while its
  window is open and it is not owned, flipping every 4 s like a card turning when both are open;
  the Daily Challenge corner is bigger (84 px, 56 on a phone). During the guided part the money
  pill, Daily Challenge, the offer, Invite and Roblox Plus hide (the Social funnel follows only
  players whose soft part began; DailyClaimed is logged by the daily claim).
- 2026-10-09: The new search, for everyone (tutorial v2 4.7): every 1v1 search (a pad's Play
  Global, the spawn pill's) looks in its own server first and all the while, for anyone near
  its rank searching or waiting alone on a 1v1 pad (one of the two must be searching). This
  server's windows widen fast and never reach "anyone": 2 divisions at once, 4 after 1 s, 7
  after 2 s, 12 after 3.5 s (`Config.GlobalQueue.LocalWindow`). A match here takes both out of
  the global queue, shows "MATCH FOUND" for 0.9 s (with "Heading to your table..." for whoever
  moves) and stands both on one pad: one of theirs, else the free table nearest the one who
  searched first. The global queue runs as before at the same time.
- 2026-10-09: 5 s at most, "no matter what": a 1v1 search still waiting after 5 s plays a
  disguised bot of the player's tier in this server, at their pad or the nearest free table
  (no teleport); today's arena bot only when this server has no free table. Team searches get
  their bots after 5 s too (was 25 s). Lobby bots stay off.
- 2026-10-09: A lobby 1v1 search no longer fails when MemoryStore is down: it stands in its
  server (this server's people, then the bot here at 5 s) and keeps trying to post itself to
  the global queue. Team searches and an arena's Play another still say the queue is down.
- 2026-10-09: Bug fix for everyone: an arena reading a bot match's record live (its second
  side all bots) refused it (`Ticket.isRecord` wanted a person on both sides).
- 2026-10-09: The Game2 funnel records what game 2 was (Server: a person here, Global, Bot: a
  bot here, Arena: the arena bot, Table: they stepped onto someone's pad with no search) and
  how it ended (Won or Lost; plus the custom event Game2Result with the kind and device).
- 2026-10-09: First-time hints, for everyone new (tutorial v2 4.8): the ability bar full (how
  to use it on this device), the first rank-up (claim it in Rank), the first lucky block and the
  first Mystery block in the hotbar, the first cue won (equip it in Cues), the first visit to
  Abilities (RELEASE, then SPIN), the first ball in hand and the first 8 call. Each is a hand and
  one short line with no dim, once, saved; it goes when done, is ignored after 20 s or when its
  moment passes undone, and may come back once 2 minutes later. In a match it never pauses the
  clock and keeps off the table's middle (the line at the top, the hand on the power bar or the
  ability button). Never in the rigged game 1 (also after a skip there).
- 2026-10-09 (run assumption): the hints are for players new since tutorial v2. A save from
  before (any match, no v2 start) gets them all marked done once, so veterans see none.
- 2026-10-09: Path R (a fair first game with a real person) is taught by the same hints: "Drag to
  aim, then pull the power bar to shoot!" from the break, zoom on a later turn, ball in hand,
  the 8 call and the ability, with the clock running as in any fair game. The guided steps mark
  the hints they teach done (game 1 on path S: the pool controls and the ability; Rank, Mystery,
  Place, Cues, Abilities: theirs).
- 2026-10-09: Skipping: in game 1 the rigged game plays on with no guidance (the bot keeps its
  script); in the chain everything shows at once; the first-time hints still come. A skipper
  keeps only the icons' click-once "!" (the first click on each new icon is a hint for
  everyone); the quest, the invite popup and the glows are the soft tutorial they skipped (run
  assumption). While the Abilities screen is open the Skip button sits top left (its odds list
  is top right).
- 2026-10-09 (run assumption): Bronze's Mystery block waits in Rank like every other rank reward
  (`Config.Tutorial.RankClaim.BlocksAtOnce` is empty): the first win's result lists only the Rare
  block, and the chain's Rank claim brings the Mystery block to the hotbar before its step.
- 2026-10-09: "x2!" (x3! and up) for everyone: a small gold pop just right of NICE SHOT! (or alone
  over the pocket) when the shooter's second, third ... ball drops in one shot; never on the
  break or in a late joiner's catch-up.
- 2026-10-09 (designer): a new player has 0 ability spins until the code RELEASE gives 3: no
  starter spin (`Config.Ults.Earn.Starter` 0), no spin for reaching Bronze (`RankUp.Bronze` 0;
  Silver, Gold and up keep theirs), and a brand-new save's daily free spin starts the next UTC
  day. The tutorial's Abilities step reads 0, then 3; its spin lands on Magnet and 2 are left.
- 2026-10-09: Tutorial v2 telemetry: the invite popup gets its own event (InvitePopup: Shown,
  then Invited or Closed, once), and failures that do not end the tutorial (the bot falling back
  to the plain way, the first-time hints turning off) log a TutorialError too, once per code per
  player per server. `docs/TUTORIAL_FUNNELS.md` lists every funnel and event.
- 2026-10-09 (designer): the tutorial v2 run checks only the main happy path of each remaining
  step in Studio, with one screenshot; lint and the tests cover the rest. Step 14's target drops
  from 20 clean automated runs to 3.
- 2026-10-09: Tutorial v2 bug-proofing (two review agents): only a 1v1 pad starts the
  tutorial's Pad step (a team pad leaves them at the arrow); pressing Next at the Rank step
  claims the reward for them (the Mystery block must exist for the next steps); only the first
  spin at the Abilities step is forced to Magnet; the tutorial player's reset in game 1 is not a
  foul (the rigged break stays); a save left at Pad or Game1 with a win resumes at Rank, and a
  v1 save from before game 1 that has played since never starts the tutorial.
- 2026-10-09 (designer): the tutorial's team-table backup is built: when every 1v1 table is
  busy, the nearest free 2v2 or 3v3 table plays game 1 as a 1v1 and goes back to its own mode
  once free (a table switches mode only while nobody is on it). The server model showed spare
  1v1 tables alone (the in-server bot and pairs leaving the last 2 free) leave 13% of new
  players without a table at 20 players, against 0% with the backup; the spare-table lever
  (`Config.GlobalQueue.SpareTables`) stays at 0. Max Players stays the plan's 24 (0.13% of new
  players wait for a table in a full server; 20 makes it 0% and halves arena teleports).
- 2026-10-09 (designer, live test notes): the tutorial's combination is shown as a ghost replay
  on the table (a see-through cue strikes, the cue ball rolls into the first ball, it into the
  second, that one into the glowing pocket, on a loop) instead of the pointer hand. The Rank
  claim keeps the rewards in view: no dim, only CLAIM ringed, the hand from its side. The Cues
  step waits until the lucky block's reel and reveal are done. Every lucky block reel's still
  before it spins goes back to 0.2 s (1.2 s was too long). Free Reward's soft-part bounce is a
  slow breath (1.1x over 0.9 s), and its first open lands on the group to join.
- 2026-10-09 (designer): the Daily Rewards popup ("daily A" in its own lively frame, the same
  section as the Free Reward menu's Daily) comes up once at the tutorial's soft part, before
  the invite popup, which follows a second after it closes; Play Global glows after the invite
  is answered. This is the one exception to the 2026-10-04 "no reward popups" rule; returning
  players get no daily popup (say if they should).
- 2026-10-09 (designer): the Starter Pack tile shows the Shop card's picture (the Starter Lucky
  Block, the Starter Cue behind it, money in front) on a blue halo; the rank HUD always shows the
  next goal under its bar: "N WINS TO <next division>!" (wins against an equal player), "ONE
  MORE WIN!" with the wiggle at one ("N WINS TO GO!" in a phone's short row).
- 2026-10-09: the rank HUD follows XP changes again (since 2026-10-03 the claim dot's field
  shadowed its pending-changes flag, so it only redrew when shown again and "ONE MORE WIN!"
  never appeared).
- 2026-10-09 (designer): the test place's saves live in their own store
  (`Config.Save.TestPlace`), renamed to start everyone there over; the real game's store is
  untouched.
- 2026-10-09 (designer, for economy v5.1 at the merge; nothing changed now): after the tutorial
  plus the group and playtime rewards a new player had about $32,000 and 5+ lucky blocks, which
  reads as a lot and misleads about the pace after; the buildup should be slower. The next win
  reward (Mystery, wins 2/10) is not appetizing after so many Mystery blocks: maybe an Epic, if
  the economy allows.
- 2026-10-09 (designer): the right side's Starter Pack / VIP tile and the Daily Challenge are
  bigger than the left column's tiles, words too, and the offer reads as a deal: rainbow sun
  rays turning behind it, "x2 VALUE!" for the Starter Pack (its money at the smallest money
  pack's rate plus a Rare block's restock price, over its live price; the cue and the hour of
  2x money not counted) or "50% OFF!" for VIP's welcome offer, then "ONLY" and the live Robux
  price. The Daily Challenge itself is untouched (not built) but wears a "!" until pressed. The
  Starter Pack's price stays 29 R$ (the designer's "ONLY 19R$" note is a reprice for them to
  decide; at 19 the same sum reads "x4 VALUE!").
- 2026-10-09 (designer): game 1 shows no group colour until the first legal pot after the break
  (the break assigns none, so the open table dims and outlines nothing); the aim lesson still
  outlines the one ball to pot. Ball in hand after a scratch starts on the head spot as in any
  game, not lined up behind a ball: they drag it themselves, and where they drop it picks the
  turn's aim or combination lesson again.
- 2026-10-09 (designer): the zoom lesson's gestures are animations, not a hand: a computer
  shows the mouse with an up-and-down sign (arrowheads bobbing apart, dashes running), a phone
  two fingertips pinching in with an arrow by each (closing zooms out: spreading would zoom in),
  a controller the right stick pushed up and down with the same sign.
- 2026-10-09 (designer): the ability lesson's hand is small and points at PRESS G TO ACTIVATE
  from its right end, so the key stays in sight; that prompt is bigger in every match and
  breathes while it waits for the press (`Config.UI.Ults.PromptPx`, `PromptPulseScale`).
- 2026-10-09 (designer): the right side's Daily Challenge and offer tile are a little smaller
  (94 px, 62 on a phone; 108 and 70 were "a bit big"), the offer's picture wiggles, and a small
  red X on its corner hides the tile for the rest of the visit (it comes back on the next join
  while still open; the Shop keeps selling it; no X on a controller, where the corners are not
  stops). The Starter Pack's window is one day from the first join (was 7 days).
- 2026-10-09 (designer, for economy v5 at the merge): the Daily Rewards' seven login days (and
  Claim All) must be rescaled to the new economy; their amounts are v4's today.
- 2026-10-10 (designer): a skipper's "A new cue! Equip it in Cues." hint waits until a lucky
  block's reel and reveal are over (the cue is granted at the open), and so does the CUES
  tile's NEW count, for everyone: neither tells what the reel lands on.
- 2026-10-10 (designer): the tutorial merges into the economy line this way: the tutorial
  session merges `gui-v4` (economy v5 to v5.2) into `tutorial-v2` and keeps every economy rule;
  `8ball-0d` fast-forwards `gui-v4` to it; the economy sessions own every number and bring the
  designer a first-session rescale (measured on the merged branch: a VIP account $43,525 before
  playtime, over half of it finder's money; hand-off section 3a). The tutorial's Uncommon block
  reel that passes Legendary, Mythic and the Secret stays (designer); it now comes from the
  first Mystery's scripted roll.
- 2026-10-10 (designer): economy v5's "Open all" is removed: every lucky block opens one at a
  time through its reel ("assuming they dont get to open many lucky blocks anyway"). It had
  shown beside the tutorial's Place step and would have skipped the reel lesson.
- 2026-10-10 (designer): tutorial v2 is approved and closed. Everything after it (the economy
  rescale of the first session, the phone and controller checks, Max Players, the controller's
  shooting mode) goes on in the main folder (`~/Desktop/8ball`, `gui-v4`).
- 2026-10-10 (designer, "instead of roman numerals for ranks like Silver II Silver III just do Silver 2 silver 3 for everything from now on and all ranks in every gui and hud"): rank divisions are digits everywhere ("Silver 2"). One list (`Strings.Ranks.Numerals`) feeds every screen through `Ranks.name`, so every GUI, HUD, popup, leaderboard and dev reply changes together. Older docs still say "Bronze I" in places; read them as "Bronze 1".
- 2026-10-10 (designer, "why everyday gives three things, should be like different things each
  day ... each reward better than the next"): each login day gives one thing. First week: $5,000,
  a Mystery block, 3 ability spins, a Rare block, $50,000, 3 Mystery blocks, then the Week One
  Cue on day 7 **only for 7 days claimed in a row**; one missed day turns day 7 into an Epic
  block (`Config.Daily.FirstWeekMissed`, the save's `Login.FirstMissed`), shown by a "7 IN A
  ROW!" tag while the row holds and a line under the days after a miss. Later weeks: $5,000, 1
  spin, a Mystery, $25,000, 2 Mystery, $45,000, a Rare block. The model: Epic by day 7 / 30
  about 4-5 points lower (the start is leaner on purpose), the Week One Cue much rarer (15.8% to
  1.6% by day 7), daily players unchanged.
- 2026-10-10 (designer's pick): the first week's Claim All 499 / 449 / 399 R$ (was 399 / 349 /
  299) and the later weeks' 99 / 79 / 49 (was 79 / 69 / 35), synced on Roblox; the first week's
  Claim All is offered only while its days are still in a row (it buys the Week One Cue).
- 2026-10-10 (designer's pick): playtime gifts $500 / $1,000 / $1,500 / $2,000 / $2,500 + 1 spin
  ($7,500 a day, was $12,000; a match hour pays about $7,750, so the gifts no longer pay more
  than playing).
- 2026-10-10 (designer, "would instead making VIP give a free mystery instead of uncommon be
  fair?"): yes, about the same worth; VIP's daily block is a Mystery block. The Daily screen
  shows the VIP part once under the days, not on every tile.
- 2026-10-10 (designer, "way too much text ... going left to right from least rare to
  rarest"): the restock's odds line is gone (each card's dice opens its odds) and its cards
  sort least rare to rarest. On a phone the rank HUD's "N wins to go" sits bigger, between the
  bar and the panel's top edge, right of the rank name.
- 2026-10-10 (designer, "text is a little too big ... might be better to move it underneath
  the rank since longer text like platinum or grandmaster will get covered"): on a phone the
  rank HUD's "3 WINS TO GO!" is back to 12 px, under the pill and centred under the XP bar
  (clear of the menu column under the badge), no longer in the name row.
- 2026-10-10 (designer, after the tutorial on an Android phone: "for ALL of the darken and
  highlight screens they are offset ... come up with a foolproof solution"): the tutorial layer
  places everything in its own pixels (a target's AbsolutePosition minus the layer's own, a
  world point through WorldToScreenPoint), never Roblox's inset added; that inset is why every
  hole sat beside its button on a notched phone. The line, big text, Skip, Next and gestures
  are laid out on the measured play area (inside the notch, under Roblox's top bar) by
  `src/shared/Tutorial/ScreenLayout.luau`, tested across iPhone, Android, iPhone SE, iPad and
  laptop shapes. The line also keeps off the lit hole and off a screen's own words (it tries
  over or under the hole, its own place, a few steps lower), and so does Next.
- 2026-10-10 (designer, "skip tutorial button is way too big should be very very small ... for
  mobile put it on the left top right under the roblox menu"; "make skip tutorial smaller so it
  fits inside the text box"): Skip is 22 px tall on a phone (26 elsewhere) with 12 px words
  (15) and as wide as they need, under Roblox's menu on a phone and top right on a computer or
  tablet (designer's pick); when one of our panels covers its spot it moves to the next free
  one along the top bar row. The old "top left while Abilities is open" switch is gone; on a
  phone the spin screen's slot cards are centred top to bottom so Skip clears them.
- 2026-10-10 (designer): the line is smaller (phone 24 px), at most 70% of the play area
  wide, centred on it; the big text is smaller and higher. The pinch demo is two hands
  sliding apart (no circles); the zoom lesson ends on any pinch or wheel notch either way,
  and the HUD's zoom hint stays hidden during the guided tutorial.
- 2026-10-10 (designer, "what if the player gets a lucky block earlier in the hotbar"): a
  block step finds the block by its kind; one past a phone's visible slots is pinned into the
  first slot for the step. The ability lesson lights the bar and its prompt (not the HUD's
  padded canvas, which ran off a phone's foot).
- 2026-10-10 (designer, "get rid of auto spin and only keep in skip but rename it to just Fast
  spin"; "VIP only" picked): Auto Spin is removed from the game (client, server, remote,
  Config, Strings); Skip is now **Fast spin**, still VIP only. VIP's product text says "Adds
  Fast spin to Ability Spins." On a phone the spin screen shows the odds list with every rarity
  (no Odds button) and the code box right there under it; Fast spin sits by Back.
- 2026-10-10: the top banner ("New in your Index ...") keeps under the rank HUD's goal line
  as well as its pill (on a phone the line sits under the pill).
- 2026-10-10 (designer's controller pass with a PS4 pad: "instead of using r2 to set the
  amount to shoot ... (x) on ps4 or (a) on xbox ... to increase power, the triangle or Y ... to
  decrease the power, and then use r2 to release"; "the pull ... should just be constant and
  faster"): one button map for the whole game (GDD section 5). The Hold / Depth / Freeze
  shooting modes are gone: hold A to raise the power and Y to lower it, linear, full in 1 s;
  R2 shoots; B zeroes it; the power stays while aiming. The 8's pocket: the stick points, A
  picks (no GUI selection, which never landed and stuck the tutorial). Y is Rank only (it was
  also the queue and Join): Play Global and Join moved to L2. D-pad left (the designer's
  pick) jumps to the right side (Daily Challenge, offer, Settings, Invite, Plus, player list),
  outlined in gold; View is Skip tutorial and R3 the tutorial's Next. "Add the cue on the right
  side back": the power bar's cue shows on a pad too. Stuck after Rank: lobby HUD buttons are
  never controller stops (the Rank badge was, and Menus handed its selection back, so the stick
  hopped between Rank and money); Menus only hands back a selection still on screen, HubPad
  drops stray ones, and the tutorial's Next no longer takes the selection. Every button's
  picture is Roblox's own on an ink disc (PlayStation's white art), on the Rank badge, the
  Daily Challenge, Play Global, Join, Skip, Next, the ability prompt and the guide strip. The
  tutorial's controller lines name the new buttons (A fills, R2 shoots, D-pad fine aim, Y
  Rank, LB / RB then R2 for the Mystery block, R2 to place), and its pointing selects what
  the line names (CLAIM, the new cue, Redeem, SPIN) once it is on screen.
- 2026-10-10 (designer, "it spawns in ONLY the first time a player tabs out of the game to give
  them a reward before they leave the game ... if they leave the game anyway the second time
  they come back add the cutscene again ... 'Wait... what is this?'"; picks: right away, line
  then title, 12 h from the tab-out, the first leave kept as a backup): the Gift lucky block is
  earned the first time a player tabs out after the tutorial (the client tells the server when
  its window loses focus; the server decides, once per 5 s at most) and falls at once while
  they are away; never mid-game at their table or over a menu (it waits). A player who never
  tabbed out earns it on their first leave, as before. Not picked up: the cutscene plays again
  every visit. The bottom bar reads "Wait... what is this?" while it falls, then "A GIFT FELL
  FROM THE SKY!" and "Pick it up!" ("Thanks for coming back" dropped). The save keeps its key
  (GiftLeftAt, now "earned at"), so a Gift owed under the old rule still falls. /giftdrop forgets
  it (the next tab-out drops it); /giftdrop now drops it at once.
- 2026-10-10 (designer, "when i say tab out i meant when the person in game clicks escape or
  presses the roblox menu ... whenever the player attempts to leave the game the goal is to
  hopefully retain them"): the Gift is earned the first time a player opens Roblox's own menu
  after the tutorial (Escape, the Roblox button, a controller's Start: `GuiService.MenuOpened`),
  not when the window loses focus; it falls at once, behind the menu. The first leave stays the
  backup. "Wait... what is this?" moved from the bottom bar to the top of the screen, just under
  the top bar, and grew (46 px, 30 px on a phone), like the tutorial's line; the title and "Pick
  it up!" stay in the bottom bar after the crash. /giftdrop now means "the next opening of the
  menu drops it".
- 2026-10-10 (designer, economy v6: "yes to all of those, build this economy now"): the economy
  is rebuilt from scratch (docs/ECONOMY.md, docs/prompts/ECONOMY_V6_PLAN.md, the plan page
  https://claude.ai/artifact/LngEA3qwDYZBZ7iPQkHkBK). Yes to A (the Sky Lucky Block at most 1 a
  day), B (a duplicate Common or Uncommon pays its sell money instead of a copy) and C (trading
  after 10 real wins). Interview answers: the launch bonus is +30% on money packs only (no 6th
  Mystery); reset everything (saves and every game-wide store to `_v2` names, the `_v1` stores
  kept); the Grand Opening runs 45 days from the moment the designer publishes v6 (StartsAt set
  then).
- 2026-10-10 (economy v6, assumptions made while building): the Candy Cue's player name is now
  "Candy Cane Cue" (the designer's name for it); the Week One Cue is removed (the wipe means no
  save holds it); practice against PC no longer counts as a real match (no login day, Sky clock,
  trade-gate win or XP) and pays the solo rows under one shared $3,000 cap, disguised bots past
  20 wins included; the tutorial's Place step points at whatever block the real Mystery became
  (the TutorialBlock attribute; Bronze's Uncommon block after a rejoin) and its Cues step at the
  cue its block gave; finder's money is collected all at once from a "New cues found!" card at
  the top of the Index (a "!" on the Cues button); the VIP Cue's finder's money waits there too
  (closes the open question). The trade warning's fallback worths and the bots' cue shares were
  refit to v6.
- 2026-10-10 (designer): the Daily Challenge is off for the release (not built in time):
  `Config.UI.Corners.ChallengeOn = false` hides its target and moves the Starter / VIP offer
  tile up into its place, which also takes it off the phone's jump button.
- 2026-10-10 (designer): Solo and Practice get glowing portal arches in the lobby; their look
  (a Blender model with particles and animation) and placement (the front of the lobby in place
  of some plants, or the sides) are to be planned together and shown before building.
- 2026-10-10: the server size is 24 (GDD's Max Players), set in the Creator Dashboard.
- 2026-10-10 (designer, "only standards you can click to skip the roll, for uncommon+ do not
  make add click to skip"): tapping the reel to skip its spin works only on a block whose climb
  starts at Standard (`Config.LuckyBlocks.SkipFloor`); every other block plays its full spin and
  shows no "tap to skip" hint.
- 2026-10-10 (designer, "for the first ever mystery block someone ever opens, i want the spin
  card to always be one off from a legendary card"): the tutorial's reel puts a Legendary on the
  card just past the stop (`Config.Tutorial.ReelNearMiss`), even when the prize is a Legendary
  too (two side by side). The opening spread (Mythic and Legendary at the start) and the Secret
  flashing past just before it slows stay.
- 2026-10-10 (designer): day 7's Chroma Cue and the invite's Candy Cane Cue show as their own
  cue cards (the rarity's frame, name and bar, as in Cues and the Index), day 7's filling the
  tile; day 7's sticker says "RARE!" (OP! was misleading). The Sky banner shows nothing before
  the day's first finished match (no "Finish a match..." line) and sits in Roblox's top bar row,
  centred on the screen (just under the row when the row's HUD leaves no room). The match top
  bar is centred on the screen (the clock in the middle) whenever that clears Roblox's buttons
  (computers, tablets); a phone keeps it in the room beside them.
- 2026-10-10 (designer, "start it now but make it 46 days"): the Grand Opening's clock started
  at 08:15 EDT (StartsAt 1791634500) and runs 46 days (45 plus a grace day); the launch bonus
  follows it. Its Shop card says how limited it is under the block: a red "ENDS IN 45d 23h"
  pill and "THEN GONE FOREVER!" in flowing rainbow words. The Abilities code box's "NEXT CODE
  AT 100 LIKES" has the kit's ink outline like the line above it.
- 2026-10-10 (designer, phone pass): on a phone the Sky banner sits in the top row just right
  of the Settings gear ("Sky Block in 14:29" when the full words do not fit). The ability
  cutscene's band draws past a phone's safe area (Letterbox.screen), edge to edge, and each
  seated player's avatar copy is made when they sit down, not in the frame an ability fires
  (the activation hitch). The hotbar keeps the tiles of unchanged blocks on each update instead
  of rebuilding the hotbar and the whole bag in one frame (the choppy Mystery jump and block
  arrivals), and stops each Mystery tile's OPEN! pulse with its tile. A match whose summary
  has arrived counts as over even before its Result snapshot does, so a slow connection no
  longer stops the result cutscene before the result screen opens (the tutorial's missing
  results), and the tutorial's Result step waits for that cutscene.
- 2026-10-10 (designer, "unless trading is actually fully functional already just leave it in,
  otherwise id get rid of it"): trading is off for the release (`Config.Trade.Enabled = false`:
  the player list's card has no Trade button and the server refuses every trade request). It had
  been live by mistake (the 2026-10-08 and 10-09 decisions had taken it out of the release, with
  no switch), and a trade between two players was never checked after economy v5 and v6 changed
  the blocks it trades. The code, the 10-win gate and the tests stay for when it comes back.
