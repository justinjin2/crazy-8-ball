# Economy v4: the forgiving economy (research, proposal, then the rebuild)

Written 2026-10-08 by the designer (Justin, Roblox name Painicane) with Claude, after an
interview. You are a Claude Code session that will:

1. read how the economy works today,
2. research,
3. interview me,
4. propose a new, much more forgiving economy, with a simulation behind every number,
5. once I say "approved", rebuild the economy everywhere it lives: `docs/ECONOMY.md`,
   `src/shared/Config.luau`, the server rules and saves, the Lune tests,
   `tools/economy_model.py`, the Robux products, and every other doc or file that states an
   economy number.

I am a beginner. Explain every decision in plain words. Screens are not yours (section 7.4).

---

## 0. Two other sessions are working right now: never get in their way

- **The GUI redo session** works in `~/Desktop/8ball` on branch `shop-lively` (check with
  `git -C ~/Desktop/8ball branch --show-current`; it may move on). Its brief is
  `docs/prompts/CUES_LIVELY_PROMPT.md`. It has Studio and Rojo open and uncommitted changes in
  `src/shared/Config.luau` and `tools/economy_config.json`.
  - **That folder is read-only for you until the merge (7.5).** Read any file there freely.
  - Never edit, create, stage, stash, reset, check out or commit anything there.
  - Never run scripts inside it: `tools/economy_model.py` rewrites `tools/economy_config.json`
    when Config is newer.
  - Read other versions with `git -C ~/Desktop/8ball show <commit>:<path>`.
- **The thumbnail session** works in `~/Desktop/8ball-refs/thumbnails`. Never touch it.
- **Also leave alone:** `~/Desktop/8ball-gui-v3`, `~/Desktop/8ball-refs/gui-lively` and
  `~/Desktop/8ball-lane-backup`.
- **No Studio for the whole run:** no Rojo, no Studio MCP tools, no place file. The data
  layer is checked with Lune only (`tools/lint.sh`, `tools/test.sh`). If something truly
  needs Studio, stop and ask me.
- **Where you write:**
  - Research, the plan, the simulation and the review page go in
    `~/Desktop/8ball-refs/economy/`.
  - Code and docs go only in your own worktree, `~/Desktop/8ball-economy-v4` (branch
    `economy-v4`), which you make in step 1.
  - Before I approve the plan, nothing is committed in the worktree. You use it only to run
    the repo's tools.
- **Git:** push only `economy-v4`. Never push or change `main` or `release`, and never
  force-push.

---

## 1. Steps and gates

1. **Read** everything in section 2.
   - Make the worktree from the newest commit of the GUI session's branch, never from
     `release` (67 commits behind on 2026-10-08):
     `git -C ~/Desktop/8ball worktree add -b economy-v4 ~/Desktop/8ball-economy-v4 <that branch>`.
     This adds a folder. It does not touch the GUI session's files.
   - If lint or the tests need git-ignored tool files there, copy them over from
     `~/Desktop/8ball`.
   - Run `python3 tools/economy_model.py` and its `tables`, `shop`, `loot` and `supply`
     outputs **in the worktree**, to see today's numbers.
2. **Research** (section 5) with parallel research agents.
   - Write one sourced report per topic in `~/Desktop/8ball-refs/economy/research-2026-10-08/`,
     plus a README.
   - Then give me one screen summing up the findings that change the design.
3. **Interview me.** Cover section 6 plus whatever the research raised.
   - Ask in numbered groups. Several rounds are fine.
   - Don't ask what my notes already answer.
4. **Simulate and write the proposal** (7.1). Show it to me and revise it in rounds
   until I say "approved".
5. **After "approved": rebuild** (7.2 and 7.3) in the worktree, step by step. Commit and push
   `economy-v4` after each verified step.
6. **Hand-offs** for the other sessions (7.4).
7. **Merge only when I say** (7.5).
8. **Report** in plain words: what changed, what you checked, what I should try by hand, and
   what the GUI and thumbnail sessions need.

---

## 2. Read first

- `~/Desktop/8ball/CLAUDE.md`. Its house rules apply in your worktree. "Commit as soon as a
  step is verified" applies to your branch only.
- In `~/Desktop/8ball/docs/`:
  - `STATUS.md`;
  - all of `ECONOMY.md` (today's economy);
  - `GDD.md` sections 11 and 12;
  - the last week of `DECISIONS.md`;
  - `prompts/CUES_LIVELY_PROMPT.md`. It covers the GUI session's work: the cue card's chance
    chip, the spin reel's "rarer cues show up more often" (concept 3), Free Reward (concept 4),
    and copy numbers on the first 100 copies of every Rare-or-rarer cue.
- In `src/shared/Config.luau`:
  - `Config.BlockOdds`: odds rows, `Drop.Weights`, `Drop.Upgrade`, pity, sell-back;
  - `Config.LuckyBlocks.Kinds` (timers);
  - `Config.Daily`: login loop, 28-day track, playtime, codes;
  - `Config.Shop`: `Deals`, `Restock`, `ReleaseSale`;
  - `Config.Products`, `Config.Social`, `Config.Index`, `Config.Trade`, `Config.BotCues`;
  - the rank rewards, and the ability spin prices in `Config.Ults`.
- The win-drop and block code: `src/shared/Progression/` (`BlockDrop`, `Restock`, `Shop`,
  `Daily`, `LuckyBlocks`), `src/server/` (`LuckyBlockService`, `Rewards`, `Store`,
  `GiftDropService`), and the server code that grants a win's block.
- In `~/Desktop/8ball-refs/economy/`:
  - `01-lucky-block-economy-plan.md` (the v3 plan);
  - `luckyblock_sim.py` (its simulation);
  - `research-2026-10-04/` (four sourced reports). Don't redo what they cover. Update
    anything that may have changed.

---

## 3. The game today (baseline from ECONOMY.md and Config, 2026-10-08; check it, the code wins)

- **Win blocks.** Every real win gives a Mystery block, forever, with no daily cap. Anti-farm
  limits still apply: the same opponent, 10 PC wins a day, 20 disguised-bot wins a day, solo
  never.
- **The Mystery block** opens on its upgrade screen in 4 presses. The first press shows the
  starting tier, so 3 presses can upgrade it.
  - Final tier: Standard 68%, Uncommon 25%, Rare 6.7%, Epic 0.28%, Legendary 0.0196%,
    Mythic 0.0004%.
  - About 1 in 3 ends above Standard. Only about 1 in 6 visibly climbs.
  - Pity: Rare at 10, Epic at 150.
- **Tier blocks** guarantee the rarity below their name. The Standard block is Common 75%,
  Uncommon 23%, Rare 1.99%, Epic 0.009%, Legendary 0.0009%, Mythic 0.0001%, and no Secret.
  In practice its reel shows only Commons and Uncommons.
- **Timers:** Standard 0, Uncommon 1 min, Rare 5 min, Epic 1 h, Legendary 6 h, Mythic 12 h,
  Gift 12 h, every other kind 0. VIP has no timers. The skip is 19 R$, Robux only.
- **Money and the Mystery block:** about $7,300 an hour of Classic play. A Mystery block
  costs $4,900 or 25 R$ (10 for 229 R$).
- **The restock shop** changes every 10 minutes and is the same in every server.
  - 3 slots: Uncommon 62%, Rare 36.6%, Epic 1.35%, Legendary 0.05%. VIP gets a fourth slot.
  - Prices: Rare $34,900 or 99 R$; Epic $349,000 or 999 R$; Legendary $3,490,000 or 4,999 R$.
  - Mythic blocks are never sold.
- **The Grand Opening block** runs for 21 days.
  - Prices: 49 / 129 / 349 R$, or $49,000 (about 6.7 hours of play).
  - Odds: Uncommon or better, plus the Firework Cue 3% and the Beta Cue 0.3%. The 400th
    block guarantees Beta.
- **Login loop, days 1-7:** $5,000 / 1 Mystery / $10,000 / 2 Mystery / $15,000 / 3 Mystery /
  a Rare block + 2 spins. The 28-day track gives Rare, 2 Rare, 2 Rare, Epic.
- **Robux items:**
  - VIP 499 R$, with a welcome offer at 249 R$.
  - Starter Pack 99 R$: a Rare-or-better Starter block, $75,000 and 1 hour of 2x money.
  - Money packs 49 to 4,999 R$. Ability spins 15 to 449 R$. Ability slots 59 and 99 R$.
  - Money Party 199 R$. A 30% release sale.
- **Old targets** (replaced by 4.6): at day 30, among active players, Epic about 5%,
  Legendary about 1%, Mythic 0.5% or less.

---

## 4. What I want (my notes, organized; interview answers marked)

### 4.1 The goal and the feel

Before we finish the rest of the shop screens, the economy gets one more rework.

- It should be **a lot more forgiving**. Legendary, Mythic and Secret get easier to get, but
  stay hard.
- **Everything in the shop gets a big discount**, especially for release. I don't want my
  prices to look greedy, even if that costs status value and revenue.
- Find the balance: hard enough that owning an Epic, and especially a Legendary or better,
  still feels valuable; easy enough that the odds never feel rigged.
- I want a fair economy that isn't expensive, where items still keep enough value to trade.

### 4.2 Mystery blocks upgrade far more often

Mystery blocks are now the main way to get blocks.

- **More of them should end above Standard** (Uncommon, Rare, Epic, Legendary). I first said
  about half. **You pick the share, somewhere between 1 in 3 and 1 in 2**, from the
  simulation and the targets, and tell me why (interview answer).
- **The upgrades should be seen happening on the presses far more often.** Today only about
  1 in 6 blocks visibly climbs.
- A block that starts as Standard can only climb 3 tiers in today's presses. Solve how
  Legendary and Mythic stay reachable: the starting tier, the number of presses, or something
  else.
- Keep the rule that the final odds are exactly the odds shown: the server rolls the final
  tier first.

### 4.3 Every block can surprise (the odds rows and the spin)

- **Standard blocks feel useless.** Today you can really only get rarer cues from upgraded
  blocks. Every block, the Standard block included, should have a real (tiny) chance at Rare,
  Epic, Legendary, Mythic and even the Secret.
- **Re-do every block's odds** for the new design. More upgraded blocks will be around, so
  every row needs a fresh look.
- **My idea, if it's balanced:** higher blocks keep the lower rarities in their pool, just
  much less, instead of cutting them out. A Rare block could still give a Common, rarely.
  Test this against today's floors (each block guarantees the rarity below its name) and
  recommend one.
- **The spin:** when a block opens, the reel should show the Epic, Legendary, Mythic and
  Secret cues it could have given, even in Standard, Uncommon and Rare blocks.
  - They can pass by more often than their real odds, so players see what exists ("you could
    have got this Secret").
  - Today a Standard block's reel shows only Commons and Uncommons. There is no "what could I
    get" moment, so there's no dopamine and no interest.
- **The reel's look belongs to the GUI session.** Its concept 3 already plans "rarer cues show
  up more often on the reel, purely visual; the real and shown odds never change". Your part
  is the numbers and the rules:
  - every block's real pool includes every rarity the reel shows;
  - check Roblox's current paid-random-items rules (updated August 2026) for anything on how
    a reel or reveal may show outcomes, and tell me what is allowed and what isn't.
    `ECONOMY.md` 11.7 says "no fake near-misses" today.

### 4.4 Ten daily win rewards (Brawl Stars style)

Like Brawl Stars' daily wins: winning gives you blocks, and a bar above the hotbar shows your
next reward.

- **10 rewards a day.** You design the 10 steps.
- **Not all Mystery.** For example, the 1st or 2nd win of the day gives a guaranteed better
  block, like a Rare, to get people playing.
- **After the 10th win of the day, wins give money and XP only** until the daily reset
  (interview answer). A quick search says Brawl Stars rewards only the 1st, 4th and 8th wins of
  the day, plus a Chaos Drop at the 6th; check it.
- **Fit it with the rules already built:** the anti-farm rules (PC wins, disguised bots, the
  same opponent) and the first session. The tutorial's first win already gives a guaranteed
  Rare block.
- VIP may add to it (4.11).

### 4.5 Login rewards: the first week hooks them

- **Day 2** of the login loop gets a good reward, for day-1 retention.
- **Day 7** gives a **guaranteed Legendary lucky block** for coming back. A Legendary block is
  Epic or better, so anyone who comes back for 7 days owns an Epic by the end of week 1.
- **Both big rewards are for a player's first week only** (interview answer). Later weeks get
  smaller day-2 and day-7 rewards (for example an Epic block on day 7), so Legendaries stay
  rare among long-time players.
- Re-check the 28-day track, playtime gifts, codes, the group, favorite and invite rewards,
  and the rank rewards against the new design.

### 4.6 How rare things should be (targets)

Epic, Legendary, Mythic and Secret stay very hard to get, just not as hard as today.

- **One week after release**, counting players active in the last 7 days (interview answer):
  - about **2-3% own a Legendary**;
  - **1% or less own a Mythic**;
  - the **Secret is far rarer** still.
- Propose a week-1 Epic number, and matching day-30 and day-60 targets.
- These replace the old day-30 targets.

### 4.7 Timers and the skip

- **Timers:**
  - Standard: opens at once.
  - Uncommon: 1 minute.
  - Rare: 5 minutes.
  - Epic: **30 minutes** (1 hour today).
  - Legendary: 6 hours.
  - Mythic: 12 hours.
  - The Gift block stays 12 hours.
  - Every other kind opens at once: Starter, Sky, Lucky 8, Grand Opening and Mystery.
- **The timer skip: about 4 R$** (19 today). Roblox allows prices down to 1 R$.
  - If one flat price for every block (even a 12-hour Mythic) is a bad idea, say why and
    propose something close.

### 4.8 Prices: cheaper everywhere, and Robux is the smart route

- **Every Robux item gets cheaper.** The most expensive single item should be about
  2,000 R$, probably less (4,999 today).
- **Robux should look far more appealing than grinding.** Use about 3x the value of the money
  route as a starting point; you set the final ratio from the research and the simulation
  (interview answer). Example: a Grand Opening block for about 19 R$, against about an hour or
  more of play to afford it with money.
- **Buying money with Robux** should be a clearly better deal, and much faster, than grinding.
- **Review every Robux item:**
  - money packs, VIP and the VIP offer, the Starter Pack;
  - Mystery, Grand Opening and restock blocks, the skip;
  - Money Party, ability spins, ability slots;
  - the first-pack double, and the release sale (does 30% off still make sense on lower
    prices?).

### 4.9 The Grand Opening block

- **Much more rewarding: Rare or better.** You should almost never pull a Common or Uncommon
  from it, so dropping Uncommon entirely is fine.
- **About 19 R$ for one** (49 today), with matching 3 and 10 bundles.
- **Buying it with money stays hard** (freemium). Grinding an hour or more for one block
  should feel worse than spending 19 R$.
- **More Firework and Beta Cues are fine as a launch gift** (interview answer): around
  **1,000 Firework Cues and 100 Beta Cues** after the 21 days. The old plan made about 200
  and 20.
- Keep the Beta Cue the rarest cue in the game, and re-check the 400-block Beta guarantee.

### 4.10 The restock shop and Mystery blocks: both worth buying

- **Keep the restock shop**, but buying its blocks with money must cost far more than with
  Robux.
- **Its slots should show Rare-or-better more often**, with the occasional Legendary and even
  a Mythic block. Today Mythic blocks are never sold; that rule goes.
- Mystery and restock blocks both sell for money or Robux.
- **Balance them so both are worth buying:**
  - a restock block is a known block (you know which tier you get), so it costs more;
  - a Mystery block is cheaper but a gamble, with its upgrade chances and a good chance to
    end above Standard.
- If they can't both be worth it, tell me and recommend which one to keep.

### 4.11 VIP and the Starter Pack

- **VIP stays about the same price** (499 R$) with better perks. It already opens every block
  at once.
- **Extra block perks are now allowed** (interview answer), for example more daily win rewards
  or a daily VIP block. **Never better odds.** Block perks become paid random items, so they
  are off wherever PolicyService restricts paid random items, like the timer perk is today.
- **Starter Pack: under 20 R$** (99 today), to get people's first purchase. You pick what goes
  in it.

### 4.12 What things are worth, and trading

- **My feel for real-money worth:** most cues are worth at most a few dollars, Mythic tens of
  dollars, and the Secret $100 or more.
- Turn this into a **Robux value ladder per rarity**: what it costs, on average, to pull one
  with Robux. Check every price and odds row against it.
- The game never supports real-money trading. These values are only for pricing.
- Re-check against the new supply:
  - sell-back money, finder's money and the Index row rewards;
  - the trade warning's block values (`Config.Trade.BlockExists`);
  - the bots' cue table (`Config.BotCues`).

---

## 5. Research (do it before proposing numbers)

Roblox's players are younger than most big games' players, so copy what works on Roblox. Every
number in a report needs a link. Mark anything you couldn't verify.

1. **Purchase psychology in the most successful Roblox games of 2025-2026:** Grow a Garden,
   Steal a Brainrot, Steal an Egg, Pet Simulator 99, Murder Mystery 2, Adopt Me, Blox Fruits,
   and whatever tops the charts now.
   - Roblox removed Steal an Egg in August 2026 because it rewarded players for watching a
     video feed. Copy its shop, not that.
   - Cover:
     - what gets a first purchase (tiny starter packs);
     - price anchoring, decoy and bundle ladders, "best value" tags;
     - honest limited-time windows;
     - restock shops (Grow a Garden's seed and gear shops);
     - how these games price Robux against grind time;
     - which Robux price points kids and teens actually buy.
2. **Brawl Stars and Clash Royale:**
   - Brawl Stars' daily wins, Starr Drops and Chaos Drops, and Clash Royale's daily win
     rewards;
   - the "next reward" display;
   - the upgrade reveal, its odds, and how often a drop climbs.
3. **Login rewards and retention:** day-2 and day-7 hooks, first-week-only rewards, and D1 and
   D7 benchmarks on Roblox.
4. **Value and trading:**
   - how games keep rare items valuable when they get easier to get;
   - value lists;
   - how serial numbers and limited copies affect value.
5. **Roblox's current rules:**
   - the paid random items policy (updated August 2026): odds, pity and luck modifiers, and
     how outcomes may be shown;
   - the 26 August 2026 policy;
   - PolicyService and honest discounts;
   - anything for Roblox Kids (ages 5-8) or Roblox Select (ages 9-15) accounts that could hide
     our game, or our shop, from them.

---

## 6. Open questions (ask me, or test and recommend)

1. **The Mystery block:** the share that ends above Standard (1 in 3 to 1 in 2), the press
   structure, and pity.
2. **Floors:** keep today's floors, or allow small lower-rarity chances in higher blocks.
3. **The 10 daily win rewards:**
   - which block goes at each step;
   - VIP's extra steps, if any;
   - how they meet the anti-farm rules and the tutorial;
   - when the day resets (UTC midnight like the other daily things, unless you see a reason).
4. **Login:** day 2 and day 7 of the first week, the later weeks, and the 28-day track.
5. **Targets:** a week-1 Epic target, and the day-30 and day-60 targets.
6. **Robux and money:** the Robux-to-money ratio (3x to start).
7. **Robux prices:**
   - every price, with the top near 2,000 R$;
   - the Starter Pack under 20 R$, and what goes in it;
   - the skip near 4 R$ (flat or not).
8. **The restock shop:**
   - its odds (how often a Legendary and a Mythic show), its prices in money and Robux, its
     stock and the VIP slot;
   - the Mystery block's price beside it;
   - keep both, or only one.
9. **VIP:** its new block perks.
10. **The Grand Opening block:** its odds and prices, aiming for about 1,000 Firework and 100
    Beta Cues.
11. **The value ladder** per rarity, in Robux.
12. **Match money per hour:** keep it at about $7,300 unless you find a reason.
13. **Copy numbers.** The GUI session numbers the first 100 copies of every Rare-or-rarer cue
    (approved 2026-10-08, timed with the old model).
    - Re-run that timeline with the new economy and tell me.
    - Change nothing without my say.
14. **The thumbnails' odds.** They show odds like "1 IN 450,000" and "1 IN 6,000" (today's
    chance per Mystery block of the Secret and of a Legendary). List every shown odd that
    changes, for the thumbnail session.

---

## 7. The proposal, then the rebuild

### 7.1 The proposal

Write it to `~/Desktop/8ball-refs/economy/02-economy-v4-plan.md`. It contains:

- **The short version first**, on one screen. Then every number with its reason and source.
- **How odds are written:**
  - as percentages everywhere;
  - every table adds up to exactly 100;
  - tiny odds keep enough decimals to stay above zero;
  - "1 in N" goes next to the rare ones.
- **A "today -> new" table** for every number that changes.
- **What a player gets:**
  - at each point: the first session, day 1, day 2, day 7 and day 30;
  - for free players at 30 minutes, 1 hour and 3 hours a day, with VIP, and as a small and a
    big spender.
- **The simulation** (`economy_v4_sim.py`, built on the population model of
  `luckyblock_sim.py` and `tools/economy_model.py`):
  - week-1, day-30 and day-60 ownership of each rarity among active players;
  - cues entering the game per day;
  - the Grand Opening Uniques;
  - where the Epic-and-up copies come from (no single source should be a leak);
  - the value-ladder check.
- **The research** in 6 to 10 rules, with links.
- **Every place the change lands:** docs, Config, code, saves, products, tests, and the GUI
  hand-off.
- **Clashes with past decisions**, each with a recommendation:
  - no Mystery block on every win any more;
  - VIP block perks;
  - Mythic blocks in the restock;
  - the reel showing rare cues against "no fake near-misses";
  - the copy-number timeline;
  - anything else you find.
- **If you can, a private review page** (an Artifact) with the same content and charts, for me
  to read. The plan file stays the source of truth.

### 7.2 Before the rebuild (only after I say "approved")

- In your worktree only, merge in the newest commit of the GUI session's branch, so you build
  on the latest.
- Copy this file to `docs/prompts/ECONOMY_V4_PROMPT.md` in the worktree, and add a Progress
  list (`- [ ]` per step) from the approved plan's build order.
- Copy the approved plan next to it. Commit.

### 7.3 What changes (everywhere the economy lives)

- **`src/shared/Config.luau`**: every table in section 2.
- **The server:**
  - the 10-step daily win track;
  - the first-week login rewards;
  - VIP's block perks (with PolicyService);
  - Mythic blocks in the restock, and their announcement;
  - the Starter Pack and the Grand Opening block;
  - the timers and the skip.
- **Saves:** new fields and a migration.
  - The GUI session also plans a save change, for copy numbers.
  - Check the save version on its branch right before you write yours, and tell me if both
    need a bump.
- **The Lune tests**, and player-facing words in the Strings module.
- **`tools/economy_model.py`**, and `tools/economy_config.json` through
  `tools/export_economy.luau`.
- **Robux products**, in `tools/products_spec.json` and through `tools/roblox_products.py`
  (it can PATCH prices).
  - Read its header. Run `--dry-run` first, then for real.
  - The key is in the Keychain. Never print it.
  - Never delete a product.
  - Do this as the last build step, right before the merge: a price change goes live in every
    server at once.
- **The docs:**
  - `docs/ECONOMY.md`, rewritten: today's state, with the designer's answers dated;
  - GDD sections 11 and 12;
  - a dated `docs/DECISIONS.md` line for each decision;
  - a `docs/ROADMAP.md` box;
  - `docs/STATUS.md` at the merge.
- **After each step:** run `tools/lint.sh` and `tools/test.sh`, re-run the model, then commit
  and push `economy-v4`. Keep the plan, the model, Config and ECONOMY.md in sync.

### 7.4 Hand-offs

Put these in your report, and as a section in the plan.

- **For the GUI session**, every screen that changes:
  - the next-reward bar above the hotbar (it shares that space with the matchmaking bar);
  - the result screen's block chip;
  - Free Reward;
  - the shop's Blocks, Money and Passes pages, and the restock with Mythic;
  - the skip price and the VIP perk text;
  - each block's reel pool, and YOU GOT;
  - anything else.

  Where a screen reads a field you removed, keep a small shim so the game, lint and tests
  still work until the GUI rebuilds it. List each shim.
- **For the thumbnail session:** every odds label that changes.

### 7.5 The merge

Merge only when I say the GUI session is paused with its work committed.

1. Merge `economy-v4` into its branch: `git -C ~/Desktop/8ball merge economy-v4`.
2. Resolve conflicts keeping both sides; `Config.luau` will clash.
3. Run lint and the tests there, then push.
4. Remove the worktree.

Then the main place gets a short Studio check: the shop prices, the Mystery screen, the
rewards, the timers and the skip. I do it, or you do it if I say so.

---

## 8. How to work with me

- I'm a beginner. Use plain words, keep reports short, and explain every decision simply.
- **Push back.** If something I asked for is bad for the game or the players, or breaks a
  Roblox rule, say so with the reason and a better option. Don't quietly build around it.
- Ask me about big decisions. For small ones, decide, log a dated line in `DECISIONS.md` and
  in your report, and keep going.
- Never start building before I say "approved".

---

## Progress (approved 2026-10-08; the plan: `docs/prompts/ECONOMY_V4_PLAN.md`)

Approved by the designer on 2026-10-08 with the two open calls at their defaults (copy numbers
keep #1-100; alts: a login day counts after a finished match, no trade hold yet). The designer
also allowed the price update and the merge at the end if `~/Desktop/8ball` has no uncommitted
changes then.

- [x] 1. Merge the newest `shop-lively` commit; this brief, the Progress list and the plan in `docs/prompts/`
- [x] 2. Config: every table of plan section 17, with Strings
- [x] 3. The Mystery block: tier weights, the 5-press path from Standard, pity for bought blocks
- [x] 4. The 10-step daily win track and the 08:00 UTC reset for every daily thing
- [x] 5. Login: the first week (7 days within 14, the match rule), later weeks, the 28-day track, playtime
- [x] 6. VIP's daily Rare block with PolicyService
- [x] 7. The restock: Rare-or-better slots, the Mythic block and its announcement
- [x] 8. The Grand Opening (caps, guarantee, per-player odds), the launch bonus, the Starter Pack, the first-pack double off
- [x] 9. Timers and the skip by time left
- [x] 10. Trading: live block worth; no paid blocks to restricted players
- [x] 11. Saves and the migration (check the GUI branch's version first)
- [x] 12. `tools/economy_model.py` and `economy_config.json`
- [x] 13. Docs: `ECONOMY.md`, GDD 11-12, `DECISIONS.md`, `ROADMAP.md`
- [x] 14. Products: `products_spec.json`, `roblox_products.py --dry-run`, then for real (right before the merge)
- [ ] 15. The merge, `STATUS.md`
