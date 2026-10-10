# Tutorial funnels and events

What the game sends to Roblox's analytics about new players, where each piece is sent from,
and how to read it on the Creator Dashboard. Code: `src/server/Funnel.luau` (the only place
that talks to `AnalyticsService`), the step lists in `src/shared/Tutorial/Steps.luau`
(`Steps.Funnel`, `Steps.Funnels`) and `Config.Tutorial.Funnel`.

## The words, in one minute

- A **funnel** is a list of steps in order. The dashboard shows how many players reached each
  step, so you can see where people drop off.
- A **custom event** is one named moment with a number and up to three labels ("fields"), for
  example `Hint` with the labels `Aim`, `Done`, `PC`. The dashboard adds them up and splits them
  by a label.
- A **field** is one of those labels. Ours are always from a short fixed list (a device, a step
  name, a path), never a player's name or id.

## Roblox's limits (and our budget)

| Limit | Roblox allows | We use |
| --- | --- | --- |
| Funnels | 10 | 8: Onboarding, PathS, PathR, Game2, Social, Shop, Block, AbilitySpins |
| Steps per funnel | 100 | at most 16 (Onboarding) |
| Custom event names | 100 | 7: Hint, TutorialSkipped, StepTime, TutorialError, Game2Result, InvitePopup, BotMatch |
| Fields per event | 3 | at most 3 |

Rules we keep so the charts stay right:

- **Never renumber or reorder a funnel's steps after it ships.** New steps go on the end.
  The numbers are the positions in `Steps.Funnel` and `Steps.Funnels`.
- One-time funnels log each step once per player ever (a bit in the save's `Flags`), so
  replays and rejoins never count twice.
- Studio never sends anything to Roblox. Each event prints in the Studio output instead
  (`[8ball] Funnel: ...`), and `/funnel` shows them (below).

## The funnels

### 1. Onboarding (Roblox's onboarding funnel)

Only for brand-new saves: step 1 is logged for a new save, and no later step is logged for a
player who never had step 1. Fields on every step: **device** (PC, Phone, Tablet, Console) and
**path** (S, R, or None before game 1). The dashboard splits a funnel by the first step's
fields, and at step 1 the path is not known yet, so to compare paths use the PathS and PathR
funnels instead.

| # | Step | Logged when | Where |
| --- | --- | --- | --- |
| 1 | Joined | a new save's client has said its device | TutorialService `logJoined` |
| 2 | ArrowShown | the arrow to a table is up | TutorialService |
| 3 | OnTable | they stand on a table's pad | TutorialGames |
| 4 | Game1Started | game 1 begins (bot or real person) | TutorialGames |
| 5 | Game1Ended | game 1 is over | TutorialGames |
| 6 | FirstWin | they won game 1 | TutorialGames |
| 7 | RankClaimed | they claimed their first rank reward | RankClaimService |
| 8 | BlockOpened | they opened the tutorial's lucky block | TutorialService |
| 9 | CueEquipped | they equipped the cue it gave | TutorialService |
| 10 | AbilitySpun | their first ability spin | TutorialService |
| 11 | ChainDone | the guided part is over (the soft part begins) | TutorialService |
| 12 | Game2Searched | they searched for game 2 | TutorialService |
| 13 | Game2Started | game 2 began | TutorialService |
| 14 | Game2Ended | game 2 is over | TutorialService |
| 15 | QuestDone | they won the "Win a Match" quest | TutorialService |
| 16 | ThirdMatch | they have played `Config.Tutorial.Funnel.ThirdMatch` matches | TutorialService |

A skipper's later steps (CueEquipped, AbilitySpun ...) still log when they do them on their own.

### 2. PathS: the rigged game 1 against the bot

Field: device. Steps in order: Seated, BotArrived, Break, Aimed, Zoomed, AimPotted, ComboShown,
ComboPotted, AbilityUsed, AbilityPotted, BallInHand, EightCalled, Won. Aimed and Zoomed come
from the player's screen (the client reports them; the server only accepts them during game 1
on path S); the rest come from the game itself (TutorialGames).

### 3. PathR: a fair first game with a real person or a friend

Field: device. Steps: Seated, OpponentArrived, Started, Ended, Won (TutorialGames).

### 4. Game2: the first game after the tutorial

Fields: device, and for Found the kind of match (Server: someone in this server; Global: the
global search; Bot: a bot in this server; Arena; Table: someone sat at their table), for Ended
Won or Lost. Steps: Searched, Found, Started, Ended (TutorialService).

### 5. Social: the soft part's asks

Only for players whose soft part began (its icons came out), so it follows new players.
Field: device. Steps: InviteShown (the invite popup), Invited (any Invite press while the soft
part is on), FreeRewardOpened, DailyClaimed (Rewards), GroupClicked, FavoriteClicked,
LikeClicked. These are not done in order, so read each bar on its own (how many of the players
who saw the soft part did this) rather than as a drop-off line.

### 6 to 8. Shop, Block, AbilitySpins (for everyone, every visit)

These repeat: each shop visit, each free lucky block and each Abilities visit is its own
session, so they show how often a visit ends in a buy, a block in an equipped cue, a visit in a
spin.

- **Shop:** Opened, Viewed, PressedBuy, Bought (TutorialService from the client's open; Store,
  Items).
- **Block:** Got (any free block lands), Ready (its timer ended), Opened, Equipped (a cue from
  it was equipped) (Funnel's own watch, LuckyBlockService, Items).
- **AbilitySpins:** OpenedAbilities, Spun, Equipped, UsedInMatch (TutorialService, UltSpins,
  UltService). Equipped means picking a slot: a new player's first spin fills their only slot,
  so their sessions go from Spun straight to UsedInMatch. Roblox then counts Equipped as done
  too (a later step marks the earlier ones), so read that funnel as Spun to UsedInMatch.

## The custom events

| Event | Number sent | Fields | Logged when |
| --- | --- | --- | --- |
| Hint | 1 | hint name, outcome (Shown, Done, Ignored), device | each first-time hint's moments (TutorialHints) |
| TutorialSkipped | 1 | step skipped at, path, device | Skip pressed |
| StepTime | seconds on the step (capped at `Config.Tutorial.Timing.StepTimeMaxSeconds`) | step, path, device | they leave a step |
| TutorialError | 1 | step, code | a guarded failure (below) |
| Game2Result | 1 won, 0 lost | match kind, device | game 2 ends |
| InvitePopup | 1 | Shown, Invited or Closed; device | the invite popup comes up, then its answer (once) |
| BotMatch | 1 won, 0 lost | (BotService) | a match against a bot ends |

Hint names: Aim, Zoom, BallInHand, Eight, AbilityReady, RankUp, Block, Mystery, Cue,
Abilities. Ignored means the hint stayed up `Config.Tutorial.Hints.IgnoredAfterSeconds` without
being done; it may come back once later.

**TutorialError codes.** A code ending the tutorial (it ends the graceful way and the player
plays on): Joined, Load, Changed, Games, Bot, Opened, Equipped, Reveal, Spun, Redeemed, Event,
Chain, Game2, ClientScene (a guided scene on the screen), ClientSoft (the soft part). A code
that does not end it (logged once per code per player per server): ClientHints (the hints turn
off for that session), BotOut, BotRetarget, BotRoam, BotLeave, BotIdle (the bot's walk failed,
so it sits down the plain way), BotMake, BotFreed. Any TutorialError at all in the dashboard is
a bug to look at: the step field says where.

## Reading it on the Creator Dashboard

1. Go to create.roblox.com and sign in. Open **Creations**, then click Crazy 8 Ball.
2. In the left menu, open the **Analytics** section.
3. **Funnels:** open the Funnels page. Pick a funnel from the tabs (Onboarding, PathS ...). Each
   bar is a step; the drop between two bars is the players lost there. Use **Breakdown** to
   split by a field (device, path) and the date picker for the days.
4. **Custom events:** open the **Explore** page, pick the event (for example StepTime), choose
   how to add it up (Average for StepTime, Sum or Count for the others) and break it down by a
   field (for StepTime: the step, to find the slow one; for Hint: the hint name, then the
   outcome).
5. New data takes up to about a day to show in the charts. Roblox keeps events for 90 days.

Good first questions to ask the charts:

- Where do new players leave? Onboarding, step by step, split by device.
- Is the rigged game too long or too hard? PathS, and StepTime's average for Game1.
- Do players skip, and where? TutorialSkipped split by step.
- Which hints get ignored? Hint, split by name, then by outcome.
- Does the invite popup work? InvitePopup: Invited against Closed.

## Checking it yourself

- **`/funnel`** (the designer's account only) prints, for you: the onboarding steps done, each
  one-time funnel's steps done (saved, so they show in any server), then the last events this
  server logged for you (newest last; `Config.Tutorial.Funnel.LogKeep` of them).
- **`/tutorial reset`** starts you over as a new player (the funnels' marks too), so the steps
  log again.
- On the published test place, play through, then type `/funnel` to see what was sent. The
  dashboard catches up within a day.
