# Morning report: saves, ranks and money

Written 2026-09-27 at the end of the overnight run. Everything is on the branch
**`ranks-money`** (pushed to GitHub). `main` was not touched.

## 1. What to try first

1. Open Studio on the Crazy 8 Ball place. The Rojo plugin must be connected, as usual.
2. The project folder is already on the branch `ranks-money`, so Rojo is serving tonight's
   code. (To go back to the old version, type `git checkout main` in a terminal in the project
   folder; `git checkout ranks-money` comes back. Rojo picks it up by itself.)
3. Press **Play**. Look for:
   - **Top left**, beside Roblox's buttons: your rank badge (it shines), "Unranked" or your
     rank, and an XP bar.
   - **Bottom left**: the cash stack and your money.
   - **Over your head**: the small badge, then your username.
   - Press **Esc**, then the **Players** list: new **Rank** and **Money** columns.
4. **Click the rank badge** (top left). The **Ranked** roadmap opens: swipe or drag the road
   sideways, click a tier at the bottom to jump there, and close it with the red X.
5. Type these in the **chat box** (only you can use them; they work in Studio and for you in a
   live server). `/rankhelp` lists them all:
   - `/rank gold 3` then `/rank reyes` then `/rank unranked`: look at each badge in the HUD and
     over your head. `/rank gold 3 520` also sets the XP inside the division.
   - `/xp 250`: XP through the real rules. From Unranked it makes you **Bronze I** with the
     NEW RANK! popup and $100. `/rank gold 5 900` then `/xp 250` shows the big **PLATINUM!**
     popup and flies $1,000 into your money.
   - `/rank expert 2 100` then `/xp -150`: the small "Rank down" card. `/xp -5000` shows the
     floor: you stop at Expert I, never Diamond.
   - `/addmoney 100`: a "+$100" flies into the money in the bottom left.
   - `/money 5000`: sets your money.
   - `/result win`, `/result lose`, `/result draw`: preview the end-of-match screen (nothing is
     saved).
   - `/newrank` or `/newrank platinum 1`: preview the NEW RANK! popup.
   - `/resetdata`: your save back to a fresh one (Unranked, $0).
6. **Play solo** at a 1v1 table: every ball you pot pops a "+$3" (solo pays 30%) that flies
   into your money; a bank or combo adds a gold chip. When you leave, the solo end screen shows
   what you made.
7. **Rejoin**: stop Play and press Play again. Your money and rank are still there (Studio saves
   to its own test store, never the real one).

## 2. What was built, phase by phase

- **Saves.** Roblox's DataStores only store data; they don't stop two servers writing one
  player at once, retry, or save on shutdown. **ProfileStore** (loleris, used by the biggest
  games) does, so it is copied into `src/server/Vendor/` (pinned, with its license, never
  edited) and wrapped by `PlayerData`, the only code that touches saves. Each player's save:
  money, rank XP, peak division, rated matches, stats (matches, wins, losses, wins and losses
  vs PC, balls pocketed, nice shots, money earned, win streaks), the solo daily counter, and
  empty slots for cues, settings and flags. The layout has a version number and migrations, and
  every load is checked and repaired (NaN, negative, huge numbers, wrong types). If a save
  can't load, the player is kicked with "Couldn't load your save. Please rejoin." instead of
  playing on unsaved data.
- **Ranks.** Unranked, then Bronze to Grandmaster with divisions I to V, then Reyes: 46 steps,
  each 1,000 XP for now. Win +250 (4 wins a division). Loss: Bronze to Gold +50, Platinum and
  Diamond 0 ("No XP lost"), Expert and up -150, but **you never drop out of a tier** (your
  answer). Money for each new division, paid once (your placeholder list). Forfeits and
  leaving give a loss with 0 XP at best (-150 from Expert); the winner is paid only if the
  match ran at least a minute from the break. Solo never gives XP. Rank and Money are also in
  Roblox's player list.
- **Money.** $10 for every ball that counts for you (your group, anything on a legal open-table
  pot, the break's balls, the 8 when it wins), nothing on a foul or for the other side's balls.
  Bank or kick +$15, combo or carom +$20. Win +$50, loss +$15. Solo: $3 a ball until $300 in a
  day, then $1. Every table is Classic, so 1x.
- **Pictures.** All 95 rank images uploaded (47 badges, 47 shine masks, the sparkle). Two new
  cash icons drawn after your reference (the single bundle flies, the three-bundle stack is the
  money icon everywhere now).
- **Screens.** The rank HUD, the money HUD, nameplates, badges under the portraits in the match
  bar, the flying cash, one end-of-match screen for both players (replacing YOU WIN / YOU
  LOSE), NEW RANK! (division, new tier, rank down), the roadmap.
- **Sounds.** Nine placeholder interface sounds from Roblox's own library and APM Music (the
  licensed library): chip landing, money tick, XP tick, XP full, rank up, new tier, rank down,
  badge hover, button click. Listed in `assets/audio/README.md` so you can swap any.

## 3. What was verified, and how

- **Automatic checks:** lint clean; all Lune tests pass (new ones for the save layout with a
  fuzz test, ranks, money, formatting, nice-shot kinds, the match result).
- **Studio, API access on** (thank you for turning it on):
  - Saves: a new player gets a fresh save; money, rank and stats stick and show; bad amounts
    are refused; 1,000 grants in a row made no DataStore requests of their own (ProfileStore
    saves on its own clock); stopping and restarting Play kept the money; a forced failed load
    kicked with the message.
  - Every chat command, through a Studio-only test hook (a script can't type into Roblox's
    chat box).
  - Matches through the Studio test fixture: a combo paid $30 and flew two chips; a win after a
    minute made an Unranked player Bronze I with $150; forfeits under a minute paid nobody (and
    only cost XP from Expert up); a Gold player's forfeit after a minute is a loss with 0 XP;
    the rank-up across a tier, the demotion and its floor; solo paid $3 + $6.
  - Every new screen captured on a PC-sized window and at phone size (750 x 361), including a
    2v2 end screen. Sounds load and play. Console clean.
- **Audits:** a fresh subagent audited the save layer (3 fixes: prepare saves on a copy, no
  stuck sessions, errors after a change can't cause a double grant), and I added two of its
  rules: a server shutdown voids running matches (nobody gets a forfeit), and nobody takes a
  seat before their save has loaded. A second fresh subagent audited everything that grants
  money or XP and reviewed the whole branch diff. It found no way for a client to name an
  amount, no double payment and no crash or leak, and fixed two small timing holes (the
  one-minute clock no longer starts on a rejected shot; a player leaving in the instant a match
  ends can't dodge the loss). I also switched off the difficulty money multiplier until the
  difficulty lock exists (a modified client could have claimed 2x). The rest is in section 5.
- **Not verified here:** a real phone, a real controller, two real players in one match, a
  real two-server save takeover. See section 6.

## 4. Overnight assumptions (overrule any of these)

Each has a dated line in `docs/DECISIONS.md`.

1. Running out of shot-clock timeouts counts as a forfeit (no +50, no match bonus).
2. Under the one-minute mark, a forfeiter is only charged if the loss costs XP (Expert and up);
   a Bronze player who quits in 20 seconds isn't counted at all.
3. A server shutdown voids running matches: no forfeits, no match pay (the pots' money stays).
4. You can't take a seat until your save has loaded.
5. Solo has no match bonus and no XP; its end screen shows the pots' money.
6. Money is saved the moment the server accepts a shot; the flying cash is just the animation.
7. Open table: only a legal pot pays; an early 8 pays nothing for the other balls; the break
   pays $10 a ball but no nice-shot bonus; the 8 pays only when it wins.
8. A solo shot that starts under the $300 daily cap is paid in full even if it crosses it.
9. Money from 10 million is shortened: "$12.5M", "$999.99M" (cut, not rounded).
10. `/rank` moves your peak to that rank (rewards below it count as paid); `/resetdata` makes
    them payable again.
11. A draw gives 0 XP and no bonus.
12. Tier colours (roadmap bands, confetti): Bronze copper, Silver steel, Gold, Platinum pale
    blue, Diamond cyan, Expert red, Veteran green, Master purple, Grandmaster near-black, Reyes
    pink.
13. The end screen's cards show usernames. (Its dim and NEW RANK!'s were removed the next
    day: popups never darken the screen.)
14. Nameplates are drawn over the world like Roblox's names (hats and walls never cut them);
    your own plate shows too.
15. The rank HUD: Unranked shows an empty Bronze I bar; Reyes a full shimmering rainbow bar.
16. The roadmap's "Next" card shows the next reward not yet paid; on a phone the tier strip has
    badges without names.
17. Gamepad: Y selects the rank badge when nothing else wants Y; A opens the roadmap.
18. The money HUD never shows more than your saved money (previews only bump the icon).
19. The sounds were picked by name and length; nobody has heard them yet.
20. Money ignores the table's difficulty (always 1x) until the difficulty lock is built.

## 5. Known issues and anything BLOCKED

**Nothing is BLOCKED.** Every step in the brief was built; the checks that need a phone, a
controller or two players are in section 6.

Design questions the second audit raised (your call; nothing changed):
- **Pot money before the one-minute mark.** Money for each pot is paid as it happens, even in
  a match that is abandoned before a minute. Two friends' accounts could break, surrender and
  repeat for about $10 to $30 every 20 seconds with no daily cap. Options: hold pot money until
  the minute mark, or give short matches a daily cap like solo.
- **Surrender farming after the mark.** A friend who surrenders after a minute gives the winner
  +250 XP and $50 every time. GDD section 13's repeat-forfeit rule (Roadmap 6.5) is the fix.
- **Quitting before the break.** From Expert up, leaving or surrendering during the coin flip
  still costs 150 XP (the GDD says the forfeiter always loses). Say if a match that never
  started should cost nothing.
- **A second device mid-match.** If you open the game on another device mid-match, the first
  server loses your save before you "leave", so that forfeit can't be charged. Fixable later
  with a "match in progress" note in the save.

Smaller things:
- Roblox draws a nameplate's fixed-pixel part much smaller than asked in Studio, so plates are
  sized in studs (they shrink with distance and fade past 45 studs). Worth a look on a phone.
- In Team Test, Roblox counts as Studio, so every tester there can use the dev commands and the
  test store.
- Pressing B to close the roadmap while standing on a queue pad might also step you off the
  queue (depends on how Roblox reports that B). Check with a controller.
- The old win/lose card's pieces (its icon and rays) are still built in MatchHUD but never shown;
  a later clean-up can remove them.

## 6. What needs you

- **Merge the branch** when you're happy: `ranks-money` into `main`.
- **A real phone** (or Studio's phone emulator): walk from the lower left to check the
  thumbstick still starts under the money HUD (it takes no input, so it should), and look at the
  rank HUD in Roblox's top bar.
- **A controller**: Y then A on the rank badge, the roadmap's D-pad and B, A on the end screen's
  and NEW RANK!'s Continue. Studio's fake controller input can't press GUI buttons, so this
  couldn't be checked here.
- **Two players** (Studio's Test tab, Players 2, Start): play a real 1v1 to the end and check
  both players get the same end screen, the winner crowned.
- **Listen to the sounds** and swap any you don't like (`assets/audio/README.md`).
- **Live-only save checks** after publishing: join the same account on two servers (the first
  should get "Your save was opened on another server"), and "rejoin keeps my money" on a real
  server.
- **Nothing was built in Edit mode** tonight, so there is nothing new to save in the place
  file. The images and sounds are ids in Config.
