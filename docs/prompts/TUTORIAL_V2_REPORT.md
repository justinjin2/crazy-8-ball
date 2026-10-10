# Tutorial v2: the report (2026-10-09, closed 2026-10-10)

**Approved by the designer on 2026-10-10 and closed.** It is in `gui-v4` (the main folder,
`~/Desktop/8ball`); everything still open goes on there (the last section).

Branch `tutorial-v2` (worktree `~/Desktop/8ball-tutorial`), forked from `gui-v4` at `19d27d4`.
`gui-v4` (economy v5 to v5.2) merged in on 2026-10-10 (f1549ae); `8ball-0d` fast-forwards
`gui-v4` to it. The full record is the brief's Notes
(`docs/prompts/TUTORIAL_V2_PROMPT.md`); the design is GDD section 14; the funnels are
`docs/TUTORIAL_FUNNELS.md`.

## What changed: the first session, step by step

1. **Join.** A new player lands in the normal public server. No menu icons yet, a small
   **Skip tutorial** button, and a big white arrow from their chest to the nearest empty 1v1
   table's pad (an arrow at the screen's edge when the pad is off screen).
2. **Any table.** Stepping onto any empty 1v1 table makes it their tutorial table. If every 1v1
   table is busy, a free 2v2 or 3v3 table becomes a 1v1 for them and goes back to its own mode
   after (new; the server model showed it is needed in a full server).
3. **The bot walks in.** A disguised "player" (real avatar and name) that waited out of sight
   walks over like a person (stop-and-go, looking around, the odd jump) and steps on the pad
   0.5 to 2 s after them.
4. **Game 1 (rigged, path S):** the break (aim locked; a weak pull springs back; a real pull
   pots 2 solids, the second creeping in), the aim lesson with the zoom and a glowing pocket,
   the combination (a ghost replay shows the shot; NICE SHOT!), the ability lesson (Fire Shot's long line), the bot's visit
   that pots then scratches (ball in hand), and SELECT WHICH POCKET. They can't lose game 1.
   About 4 minutes.
5. **A fair first game (path R):** if a real person is at their table, it's a normal game; the
   pool controls are taught by first-time hints instead. Won: the same chain follows. Lost:
   back to the arrow, and the bot game comes the next time they sit alone.
6. **The chain:** Result (Continue, the Rare block) → NEW RANK! Bronze → the bot says one
   casual line and leaves → Rank: CLAIM (the Mystery block arrives) → the Mystery block's
   roll screen (economy v5.1, 4 presses) lands on Uncommon → "Place it!", open it, the reel
   passes Legendary, Mythic and the Secret and lands on the Cosmo Cue → Cues: Equip → Abilities: 0 spins, "Type RELEASE for 3 free spins!", the first spin
   lands on Magnet, 2 left.
7. **The soft part:** every icon pops in with a "!" until clicked once, "Win a Match 0/1", the
   Daily Rewards popup once, then the invite popup once, Free Reward's frames lit once (its
   first open on Group), Play Global glowing. Game 2 is a real game
   through the new search; after it the tutorial is done.
8. **For everyone after:** first-time hints (one each, ever) the first time something happens:
   the full ability bar, a rank-up, a lucky block, a Mystery block, a new cue, Abilities, and
   aim, zoom, ball in hand and the 8 for players whose first game was fair.

**Skip** at any time: in game 1 the game goes on without guidance; elsewhere everything shows
at once. Skippers keep the icons' "!" dots, and the first-time hints still come.

## What changed for every player

- **Spins:** a new save has 0 ability spins until RELEASE gives 3 (no starter spin, no spin
  for Bronze; Silver and up keep theirs; the first daily free spin is the next day).
- **Bronze's Mystery block waits in Rank** like every other rank reward.
- **Every lucky block reel** holds still 0.2 s on its cards before it spins (your note).
- **The rank HUD's next goal** under its bar: "2 WINS TO BRONZE II!", "ONE MORE WIN!". On the
  way I found the HUD had stopped following XP changes since 2026-10-03 (a name clash): fixed.
- **"x2!"** (and up) beside NICE SHOT! when two or more of your balls drop in one shot.
- **The new search** (Play Global, a pad's Play Global, the spawn pill): someone near your rank
  in this server first, then the global queue, and at 5 s a bot of your tier in this server (an
  arena bot only when no table is free). Team searches fill with bots after 5 s.
- **Controller shooting:** hold R2 (or A) to fill the bar, let go to shoot, B cancels. Two
  other modes to try (below).
- **VIP and the Starter Pack** share one tile; it and Daily Challenge are bigger. The Starter
  Pack shows the Shop card's picture (block, cue, money) on a blue halo.
- **The new arrow look** wherever the arrow shows.

## What was checked, and on what

- **Studio, PC (my window):** every step built and checked by hand as it was made; then 3 full
  first sessions in a row from fresh saves by script (PC; a skip partway; the controller's
  scenes), a 4th with 0.3 s of fake lag, and one more after the fixes: no errors from our code,
  every funnel step in order.
- **Two review agents** (a code reviewer and an adversarial tester) read every changed file;
  all 11 problems they found are fixed (the list is in the brief's step 14 notes).
- **The team-table backup** in Studio: all 1v1 tables held, a 2v2 table lent as a 1v1, the bot
  came, game 1 began; the table went back to 2v2 after.
- **Lune tests:** 1185 pass at the close (rigged layouts, the step machine and old-save
  migration, the rank claim, spins, the search, and gui-v4's economy tests). Lint is clean.
- **Not checked:** a real phone, a real controller, two real players (paths R, same-server and
  global pairing). Those need you: see below.

## What you need to try by hand

**On the test place** (Crazy 8 Test Place; every account starts as a brand-new player there,
and `/tutorial reset` starts you over). You need a second account or a friend for some:

1. Path S end to end on **PC**, then **phone**, then **controller**.
2. A friend joins your table **during** the bot game (it should finish the bot game first).
3. Two players sit at one table before the bot comes (path R: a fair game, no help).
4. Two accounts press Play Global in the **same server** (they should meet here, no teleport).
5. Two accounts in **different servers** press Play Global (the global queue).
6. Play Global alone: a bot **in this server** at 5 s.
7. A teleport back from an arena game.
8. A day later: the funnels in the Creator Dashboard (`docs/TUTORIAL_FUNNELS.md` says where).

**The controller's three shooting modes** (`Config.Input.Gamepad.Shoot.Mode`): **Hold** (the
default: hold R2 or A, let go to shoot), **Depth** (how far R2 is pressed, smoothed), and
**Freeze** (let go to freeze the bar, press again to shoot). Try each with a real pad and pick.

**The test place's settings** (Creator Hub → Creations → Crazy 8 Test Place → Configure):
Max Players as below (and Studio access to API services on, only if you test it in Studio).

## Max Players to set

- **24** is the approved plan: in a full server about 1 new player in 450 waits for a table.
- **20** means no new player ever waits, and about half as many in-server matches teleport to
  an arena.
- **How:** create.roblox.com → Creations → the game → Configure → Places → the start place (the
  star) → Access (server size) → set it → Save. Servers already running keep their old size.

## The funnels

`docs/TUTORIAL_FUNNELS.md`: every funnel and event, where each fires, and how to read them on
the dashboard. Studio sends nothing; on the test place type `/funnel` to see what was logged
for you.

## Open questions

- Which controller shooting mode (above).
- Max Players: 24 or 20 (above).
- The ability lesson's hand covers part of "PRESS G TO ACTIVATE" (your reference puts it on the
  bar): keep, or move it.
- The result screen's total counts the held rank reward's money although it waits in Rank (an
  older behaviour, not from this branch).
- The "equip your new cue" hint forgets the cue after a rejoin (it waits for the next cue won).
- The merge back: done the other way round (2026-10-10, below).

All of these move to the main folder with the tutorial (the last section).

## Your live notes of 2026-10-09: done

Checked in Studio on PC, the main path, one screenshot each:

1. **The combination:** a ghost replay on the table instead of the big hand (a see-through cue
   strikes, the cue ball rolls into the first ball, it into the second, that one into the
   glowing pocket; each with a trail, on a loop).
2. **Rank claim:** no dim; only CLAIM is ringed; the hand points from its side, so the rewards
   stay in view.
3. **Cues waits for the reel:** its icon and hand come only after the reel and the YOU GOT
   screen.
4. **The invite popup comes sooner:** a second after the Daily Rewards popup closes, and Play
   Global glows only after the invite is answered.
5. **The reel's pause** is 0.2 s again, for every lucky block.
6. **Free Reward's bounce** is a slow breath now.
7. **Free Reward's first open** lands on the group to join.
8. **The Daily Rewards popup** (your "daily A") comes up once at the soft part: day 1 to
   claim, day 7's prize on show. Returning players don't get it each day; say if they should.
9. **The Starter Pack tile** shows the block, the Starter Cue and money, as in the Shop.
10. **"2 WINS TO BRONZE II!"** under the rank bar; "ONE MORE WIN!" with the wiggle when one
    win ranks up.

Also: **everyone on the test place starts over** as a new player (its saves moved to a fresh
store; the real game's saves are untouched).

Then the offer corner (test place version 8): the Starter Pack / VIP tile and the Daily
Challenge bigger than the left column, rainbow sun rays behind the offer, "x2 VALUE!" or "50%
OFF!", then "ONLY" and the live price; the Daily Challenge wears a "!" until pressed.

## Your second notes of 2026-10-09: done

1. **No colours until a ball is legally potted:** the break shows nothing; the aim lesson still
   outlines the one ball to pot.
2. **Zoom animations:** the mouse with a moving up-and-down sign (computer); two fingertips
   pinching in with arrows (phone; pinching in zooms out, spreading would zoom in); the right
   stick pushed up and down with the sign (controller).
3. **Ball in hand after a scratch** starts on the break spot; they drag it where they like,
   and the lesson follows where they drop it.
4. **The ability lesson:** a small hand at the right end of PRESS G TO ACTIVATE (the G stays in
   sight); the prompt is bigger and breathes, in every match.
5. **The offer tile:** a bit smaller (the Daily Challenge too), its picture wiggles, a small
   red X hides it for the rest of the visit, and the Starter Pack's window is 1 day.
6. **Economy note** for the merge: below.

## Economy notes for v5.1 (your notes; nothing changed)

- After the tutorial plus the group and playtime rewards you had about **$32,000 and 5+
  lucky blocks**. That reads as a lot and misleads about the pace after the tutorial: the
  buildup should be slower.
- **The next win reward** (Mystery, Wins 2/10) isn't exciting after opening so many Mystery
  blocks: maybe an **Epic** block, if the economy allows.
- A next goal should always be in sight; the rank HUD's line is the first piece (above).
- **The Daily Rewards' rewards** (the seven login days and Claim All) definitely need rescaling
  to economy v5 at the merge: since the merge the popup shows v5's first week (below).

## Run assumptions (my calls where the brief left room; all in DECISIONS)

- A new save's first spin lands on Magnet for every new player, not only on the tutorial's path.
- Bronze's Mystery block waits in Rank (the first win's result lists only the Rare block).
- Game 1 has no clock on a lesson turn, on SELECT WHICH POCKET and on the first ball in hand,
  and none after a turn they let run out (two timeouts can't lose game 1).
- The tutorial's own Uncommon block is ready at once (only that one block).
- The bot walks at the players' speed.
- Game 1's hidden help is one physics effect beside the abilities.
- A won fair first game leads into the same chain; a lost one goes back to the arrow.
- Rank and the money pill come back at the Rank step; the other icons with the soft part.
- An error in tutorial code ends it as Skipped (the hints still come) and logs TutorialError;
  the soft part ends at the next finished match.
- First-time hints are for players new since v2 (older saves have them all marked done).
- Only a 1v1 pad (or a team table lent as one) starts the tutorial's game 1.
- Pressing Next at the Rank step claims the reward for them; only the first Abilities spin is
  forced to Magnet; a reset during game 1 is not a foul.
- Studio checks were the main happy path with one screenshot per step from step 13 on (your
  call), and 3 automated runs instead of 20.

## The merge with economy v5 to v5.2 (2026-10-10)

You chose: the tutorial session merges `gui-v4` into `tutorial-v2` here, messages the economy
sessions (`8ball-0d`, `8ball-2c`) directly, and `8ball-0d` fast-forwards `gui-v4` in the main
folder at a quiet moment. The hand-off is `docs/prompts/TUTORIAL_V2_ECONOMY_HANDOFF.md`.

- **Before the merge:** after a skip, the "new cue" hint and the CUES count waited for nothing
  and showed during the lucky block's reel; both now wait until the reel and YOU GOT are done
  (the same as on the tutorial's path).
- **The merge** (f1549ae; 16 files had conflicts): every v5, v5.1 and v5.2 rule stays. The
  tutorial's first Mystery uses v5.1's roll screen, scripted to land on Uncommon; that
  Uncommon block opens at once with the reel that passes Legendary, Mythic and the Secret
  (kept, your call) and gives the tutorial's cue. The Daily Rewards popup shows v5's first week
  (the Week One Cue on day 7); the invite now gives an Uncommon block (v5); the Starter Pack
  stays one day. Lint and all tests pass; the whole session was played in Studio on PC.
- **What a first session gives now** (measured on the merged branch; the Studio account is
  VIP): **$43,525** before playtime: 53% finder's money (each new cue pays once), 40% rewards
  (Favorite $10,000, Daily $5,000, Bronze $2,500), 7% match money. A non-VIP: about $35,000
  before playtime, $41,000 at 30 minutes, $49,000 at 60; 6 lucky blocks, 7 new cues. That is
  more than v4's $32,000, mostly from finder's money. The next win pays $1,000 (v5's track).
  `8ball-0d` brings you a rescale to approve; the tutorial changes no number.
- **Open all is gone** (your call, 2026-10-10): `8ball-2c` found it lit beside the "Place it!"
  hand, where a press would have skipped the reel lesson. Every block now opens one at a time
  through its reel, for everyone. Checked in Studio on PC.

## Handed to the main folder (2026-10-10)

`gui-v4` holds the whole tutorial. Nothing is left in `~/Desktop/8ball-tutorial`. Still open,
for sessions in the main folder:

- **The first session's money** (`8ball-0d`, with you): the rescale from the hand-off's section
  3a; the next win's reward; whether the VIP Cue pays its finder's money at join.
- **A real phone and a real controller** on the whole first session (the zoom animations, the
  pinch, ball in hand, PRESS G, the offer tile's X); the controller's shooting mode.
- **Two players**: a friend at the bot's table, two at one table, Play Global in one server and
  across servers (the list under "What you need to try by hand").
- **Max Players** (24 or 20) on the real game.
- **The funnels** in the Creator Dashboard a day after a publish (`docs/TUTORIAL_FUNNELS.md`).
- **The notification icon** under the target is hard to see; you said to leave it (the icon
  will likely change).

