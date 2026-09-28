# Morning report: the economy build (overnight, 2026-09-28)

Branch **`economy`** (made from `ranks-money`). Nothing was merged into `main`. The brief was
`docs/prompts/ECONOMY_UI_PROMPT.md`; its Progress list and Notes have the step-by-step log.

In one line: the whole economy works in Studio. You can win cases, buy cases with money, open
them on a spinning reel, keep and sell cues, equip them, claim daily and playtime rewards,
redeem codes and see every Robux item in the Shop. Robux itself only needs the product numbers
from the Creator Hub (section 6 below).

---

## 1. What to try first (about 15 minutes)

1. **Open the project.** In Terminal, in the `8ball` folder, run `git checkout economy` (you
   are probably on it already), then `rojo serve default.project.json`. In Studio open
   Crazy 8 Ball and click **Connect** in the Rojo plugin.
2. **Start fresh.** Click **Play**. Press `/` to chat and type `/resetdata` (your save goes
   back to a brand-new player), then stop and Play again.
3. **The left column.** Four buttons on the left: Shop, Inventory, Rewards, Trade. The red dot
   on Rewards means something can be claimed.
4. **Rewards.** Open it, press **Claim** on Day 1 (the money flies to your total). Look at
   Playtime (gifts at 10, 30 and 60 minutes) and try the code **WELCOME** in Codes.
5. **Your first win.** Walk onto a 1v1 pad and play a real match against a second player (or
   use the QA fixture in `docs/STUDIO_NOTES.md`). On your first win the result screen opens a
   **Rare Case** on the reel, then shows your XP with the ROOKIE and FIRST WIN boosts, then
   NEW RANK! with Bronze I's rewards (money, 2 Standard Cases, the Bronze Cue, [BRONZE]).
   Short of a second player: `/result firstwin` previews the result screen and
   `/newrank bronze 1` previews NEW RANK!.
6. **Open cases.** Type `/givecase rare 3`, open **Inventory > Cases** and press **Open**: the
   reel spins and stops on your cue; press **Open next**. Type `/fastopen on`, give yourself
   ten cases (`/givecase standard 10`) and press **Open 10** for the grid.
7. **Your cues.** Inventory > **Cues**: tap a cue, press **Equip**, then play a solo game: the
   stick, the power cue and the trail take its colours. Type `/dupes` and press
   **Sell all duplicates**.
8. **The Index.** Inventory > **Index**: cues you never owned are dark with "?".
9. **The Shop.** `/money 60000`, then Shop > **Cases**: **Buy** and **Buy 10** (pay for 9),
   the **Odds** button. Shop > **Limited**: buy the Beta Cue and see its copy number. Shop >
   **Money** and **VIP**: every Robux item with its price and a small "Soon" tag.
10. **Robux grants without Robux.** `/buy pack1` twice (the first gives double), `/vip on`
    (then win a match: 2x money and +50% XP), `/party` (the Money Party banner).
11. **Everything else:** `/econhelp` lists all 17 economy commands.

Phone check: in Studio's **Test** tab pick a phone in the device list before pressing Play.

---

## 2. What was built, in plain words

**Ranks and money (phase A).** Every number now comes from `docs/ECONOMY.md`: the ten tiers
with growing divisions, how much XP each win and loss gives per tier and difficulty, the
Classic fade, XP never lost, less XP for beating much weaker players, and the boosts (Rookie
+100% for 25 matches, first win of the day x2, VIP +50%, the win streak +25% from the 3rd
win). Money: PC pay and its daily limit, team pay, win-streak money, the anti-farm rules
against the same opponent, short matches and solo.

**The save (phase B).** Save version 2 holds your cues (a count per cue, and copy numbers for
numbered cues), unopened cases, the equipped cue, daily streak, playtime, codes used, Index
rows claimed, titles, and the Robux purchases. Old test saves are upgraded once and keep the
rank they show, plus the cases and cues of tiers they already reached.

**Cues, cases and the inventory (phase C).** 44 cues plus the Classic cue. All names and looks
are **placeholders** (coloured sticks, a trail and pocket burst per rarity):
- Common: Chalk Dust, Corner Pocket, Rooftop Breeze, Rack Runner, Side Spin, Felt Green,
  Bank Shot.
- Uncommon: Skyline, Tiki Torch, Palm Shade, Sunset Rail, Kick Shot, Cushion Crusher.
- Rare: Harbor Lights, Massé, Neon Pocket, Ocean Break, Rail Rider, Tidewater.
- Epic: Thunder Break, Violet Vortex, Penthouse, Nightcap, Jump Jet.
- Legendary: Golden Break, Solar Flare, Crown Jewel. Mythic: Starfall, Nebula. Secret:
  Eclipse.
- Exclusive (never in cases): Bronze Cue ... Reyes Cue (one per tier), VIP Cue, Starter Cue.
- Unique (numbered): Founder's Cue (Robux, 50 copies), Beta Cue ($40,000, 1,000 copies).

Four cases bought with money (Standard, Rare, Epic, Legendary) roll from the real odds, and
every win of a real match drops a free Standard Case within ECONOMY's limits. Duplicates sell
back for a little money. Every cue shows how many copies exist in the whole game, from a
shared counter. A Mythic or Secret unboxing is announced to the server.

**Rank-up rewards (phase D).** Reaching a division pays its money once; a new tier also gives
its cases, its cue and the [TIER] chat tag.

**Icons (phase E).** The column tiles, the five case chests, the money packs, VIP, Fast Open,
Money Party, the Starter Pack and the Limited shelf, drawn by `tools/gen_ui_art.py` after
references 06 and 07, uploaded, ids in Config.

**The menus (phase F).** The left column; Inventory (Cues, Cases, Index), Shop (Cases,
Limited, Money, VIP), Rewards (Daily, Playtime, Codes) and Trade ("Soon"). Cases open on a
spinning reel with sounds, rays and confetti by rarity; Fast Open shows a grid of ten.

**Robux (phase G).** Every product and pass is in `Config.Products` with id 0. The code for
receipts (each purchase granted exactly once), the first-purchase double, the VIP pass, the
welcome offer, the Starter Pack, Fast Open and Money Party is done and tested with fake
purchases.

**Existing screens (phase H).** The result screen shows the boosts and the free case; the
first win's reveal; NEW RANK! shows its rewards; the roadmap shows the real cases and cue; a
ROOKIE pill under the XP bar; [VIP] in rainbow in chat and a shine on VIP names; the top
banner.

**Dev commands and tests (phase I).** 17 economy commands (`/econhelp`), 622 Lune tests.

---

## 3. What was verified, and how

- **Automatic:** `tools/lint.sh` clean and `tools/test.sh` 622 passed before every commit.
- **Studio, with the real save stores:** an old save upgraded; buying, Buy 10, opening, Fast
  Open, selling, and every refusal (not enough money, too fast, the equipped last copy,
  restricted region); fake Robux grants given once per purchase id; daily, codes, playtime;
  a fresh save's first real win (reel, chips, NEW RANK!); a VIP win and a streak win;
  equipping a cue and playing with it.
- **Every new screen** on the PC window, phone sizes (750 x 361 and 844 x 390) and a tablet
  (1024 x 700), with screenshots. The phone sizes were checked by resizing each menu inside
  Studio's window, not on a real phone.
- **Gamepad in Studio:** D-pad down and right open Rewards and Inventory, RB switches tabs.
- **Two fresh reviewers** (agents that did not write the code): a security audit of
  everything that pays, and a bug review of the whole branch. What they found and what was
  fixed: section 5.

**Not verified (needs you):** a real phone; a controller's D-pad up and B (Studio's tools
cannot press them) and moving the selection inside the menus; the reminder toast (it shows
when you open Roblox's menu); two real players (team pay, the Trade list); anything that only
works in the published game (real Robux receipts, PolicyService, news across servers).

---

## 4. Every overnight assumption (overrule any of them)

Each is also a dated line in `docs/DECISIONS.md` tagged "(overnight assumption)".

- Match XP rounds half to even (as ECONOMY's own table was printed); money rounds half up.
- The Index's Legendary, Mythic and Secret rows give a title only, no money.
- Secret's colour: near-black with a red glow. Mythic's solid colour: lilac #B79CFF.
- The placeholder cue names and looks above; rank cues' effects follow their tier.
- A team's same-opponent count (anti-farm) uses the most-played opponent.
- The login streak repeats in four-week cycles (Legendary Case on day 28, then week 1).
- The Event Case exists switched off and drops the normal cues until an event has its own.
- Codes: WELCOME ($500 and a Standard Case), 8BALL ($250), ROOFTOP (a Rare Case, until
  2026-12-31).
- Robux prices use Roblox's own Robux symbol inside the text.
- Team matches: the gap uses the other side's average; the free case needs the most
  experienced loser to have played 5 real matches; a loser who gave 3 cases today blocks it.
- The first win's Rare Case is rolled when the match ends and revealed instead of a case chip.
- Leaving after the one-minute mark counts as a real loss.
- Solo money gets the VIP and Money Party boosts (under the solo limit).
- If Roblox's PolicyService never answers, the player is treated as restricted (no buying
  cases with money) for that session.
- Mythic and Secret unboxings are announced 6 s later, so the banner never spoils the reel.
- Every Reyes (not only the first) is announced in every server. Banners use usernames.
- A numbered copy taken for a purchase that then fails is skipped, never reused.
- A Founder's Cue purchase that cannot be delivered is not granted and not swapped for money
  (Roblox retries it); logged.
- A pass counts once Roblox confirms it; a VIP bought through the welcome offer shows the VIP
  pass as owned. Robux prices are read once per server.
- Playtime counts every second in the game, AFK included.
- The code box waits 2 s between tries.
- Menus reuse the roadmap's slight dim; a tap on the dim closes; one menu at a time; all close
  when a match starts. On a phone a menu takes the whole screen.
- Gamepad: the column's tiles are not selectable (so the stick keeps walking); the D-pad opens
  them in the hub (up Shop, right Inventory, down Rewards, left Trade).
- Inventory: selling asks first from Epic up; Sell all duplicates always asks; NEW tags clear
  when you leave the Cues tab.
- The reel: drawn from the true odds; 4.2 s spin (6 s for Mythic and Secret); tapping outside
  the prize card does nothing; Fast Open's grid shows the rarest last.
- Shop: no "are you sure" before buying cases with money; Buy 10 has a "Pay for 9" sticker;
  the Starter Pack stays listed as Owned until its window ends; pack names Handful to
  Fortune.
- Rewards: the seven day tiles are a 4 + 3 grid; the reminder names tomorrow's best reward;
  the toast shows at most once every 2 minutes. Trade lists everyone in the server with a grey
  Trade button ("Trading is coming soon!").
- Boosts read "ROOKIE x2" (100% or more) or "VIP +50%"; colours Rookie green, first win gold,
  streak red, VIP rainbow; NEW RANK! stays 5 s; the ROOKIE pill hangs under the XP bar.
- The case opening's backdrop over a menu is dark enough to hide the menu's title.

---

## 5. Known issues and anything BLOCKED

Nothing is BLOCKED.

- In a QA run, a shot fired in the same instant as `/vip on` paid without the VIP boost (the
  flag lands a moment later). Harmless for real players.
- RewardChips (result screen) and RewardsFlyer (Rewards menu) both fly a case to the
  Inventory tile with their own code; a later tidy could share one flight.

---

## 6. Turning on Robux (click by click)

Everything is built; only the ids are missing. While an id is 0 the Shop shows the price with
a small "Soon" tag and a press answers "Coming soon". You make each item once in the Creator
Hub, paste its number into `src/shared/Config.luau` (`Config.Products.List`), and it works.

**A. Make the developer products** (things you can buy more than once: the money packs, the
welcome offer, the Starter Pack, Money Party, the Founder's Cue).
1. Open https://create.roblox.com and sign in. Click **Creations**, then the game
   **Crazy 8 Ball**.
2. In the left menu open **Monetization** and click **Developer Products**.
3. Click **Create a Developer Product**. Fill in:
   - **Name**: as in the table below (players see it in Roblox's purchase box).
   - **Description**: the short line below.
   - **Icon**: the matching PNG from `assets/ui/icons/`.
   - **Price**: the Robux in the table.
   Click **Create Developer Product**.
4. Back on the list, click the product and copy its **Product ID** (a long number; there is a
   copy button next to it).
5. In `src/shared/Config.luau`, find `Config.Products`, find the row with that key, and
   replace `Id = 0` with `Id = <the number>`. Save the file (Rojo sends it to Studio).
6. Repeat for every row.

| Config key | Name | Price (R$) | Icon file | Description |
|---|---|---|---|---|
| Pack1 | Handful ($900) | 49 | pack_1.png | $900 to spend on cases and the Limited shelf. |
| Pack2 | Stack ($1,950) | 99 | pack_2.png | $1,950 (+7%). |
| Pack3 | Bundle ($5,250) | 249 | pack_3.png | $5,250 (+15%). |
| Pack4 | Briefcase ($11,000) | 499 | pack_4.png | $11,000 (+20%). |
| Pack5 | Vault ($23,500) | 999 | pack_5.png | $23,500 (+28%). |
| Pack6 | Bank ($62,500) | 2,499 | pack_6.png | $62,500 (+36%). |
| Pack7 | Fortune ($130,000) | 4,999 | pack_7.png | $130,000 (+42%). |
| VipOffer | VIP (welcome offer) | 299 | vip.png | VIP at half price: 2x money, +50% XP, the VIP Cue, a [VIP] tag. |
| StarterPack | Starter Pack | 79 | starter_pack.png | The Starter Cue and $3,000. |
| MoneyParty | Money Party | 199 | money_party.png | 2x money for everyone in the server for 15 minutes. |
| FoundersCue | Founder's Cue | 1,499 | limited.png | A numbered Founder's Cue (only 50 ever). |

**B. Make the game passes** (bought once: VIP and Fast Open).
1. Same page, **Monetization > Passes**, click **Create a Pass**.
2. Name, description and icon as below; click **Create Pass**.
3. Open the pass, go to **Sales**, switch **Item for Sale** on, set the price, **Save**.
4. Copy the pass's **ID** (on its page, or the number in its web address) into
   `Config.Products.List` (Vip, FastOpen) the same way.

| Config key | Name | Price (R$) | Icon file | Description |
|---|---|---|---|---|
| Vip | VIP | 599 | vip.png | 2x money, +50% XP, the VIP Cue, a [VIP] tag. Never better odds. |
| FastOpen | Fast Open | 99 | fast_open.png | Open 10 cases at once and skip the spin. Same odds. |

**C. Keep the welcome offer at half price (ECONOMY 11.3).** Roblox can change prices by
country (regional or "managed" pricing). The welcome offer must stay exactly half the VIP
pass, so open the **VipOffer** product's pricing settings and switch regional pricing **off**.
Do the same for the VIP pass if you want "50% off" to stay true everywhere.

**D. Test in Studio (no real Robux).** Press **Play**. In the Shop, press a product: Studio
shows a test purchase box ("your account will not be charged"). Buy it: the money or item
arrives, and the first money pack gives double. Buying the same pack again gives the normal
amount. Without ids you can still test every grant with `/buy <key>` (for example
`/buy pack1`, `/buy vipoffer`, `/buy starterpack`, `/buy moneyparty`).

**E. Publish.** File > Publish to Roblox. Then join the real game, buy the cheapest pack once,
and check the money arrived and the console (F9) has no errors. Receipts, passes,
PolicyService and the news across servers only fully work in the published game.

---

## 7. What needs you

1. **The product and pass ids** (section 6).
2. **A real phone and a controller:** touch in every menu (and the keyboard over the code
   box); on the controller, D-pad up opens the Shop, B closes a menu, and the selection moves
   between buttons inside the menus.
3. **Save and publish the place once** (`place/8ball.rbxl`, then File > Publish): the new
   icons and sounds are in Config, but the published game needs this code.
4. **A live check** with two players: team pay, the Trade list, a real Robux purchase,
   PolicyService (the Shop's note for restricted countries) and a Mythic banner.
5. **Merging:** when you are happy, merge `ranks-money` and then `economy` into `main`.
6. **Overrule** any assumption in section 4 you don't like: tell the next session which.
7. **Next session: trading** (ROADMAP 7.7). The save already keeps counts and copy numbers
   that can move between two saves.
