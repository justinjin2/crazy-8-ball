# Halloween, the evening release (brief, 2026-10-29 ~07:30)

Replaces the "To build" list of `HW_MENU_V4_PROMPT.md` (read it for the background). Release
tonight, Oct 29, about 19:00 EDT; the event ends Nov 3 19:00 EST (5 days). The designer is away:
build, test, commit; the coordinator (`~/Desktop/8ball`, branch `halloween`) merges the lanes and
does the Studio checks. **Spend cap: the whole job, every lane together, at most $200 of API
credit; 2-4 hours.** Keep each lane lean: no sub-agents, no multi-agent workflows.

## Decided (designer, 2026-10-29 ~07:20)

- **Prices** (the base commit d7ebf89d put them in Config): Pitchfork 300 Candy or 49 R$, Witch's
  Broom 2,500 or 249 R$, Halloween Sword 7,500 or 599 R$; Candy packs 300 Candy for 49 R$
  (`Candy500`) and 1,200 for 149 R$ (`Candy2000`). Products made: HwPitchfork 3723520924,
  HwBroom 3723520925, HwSword 3723520926; the packs renamed on Roblox.
- **Candy on the ground about half of all Candy**: 5 Candy a pickup, about 3x as often, and players
  in a match collect it while they roam waiting for their turn.
- **The Pumpkin King's rise cutscene** every visit, for players free in the lobby; a tap skips.
- **The King's cape**: smooth and swaying like cloth, also while he shoots.
- **"One of a Kind" counts the Halloween cues**; the Witch's Broom badge says "Get", not "Earn".
- **The menu** is built straight to mock A (`~/Desktop/8ball-refs/halloween/mocks/v4/A.png`), no
  art-sheet stop; real cue pictures (the skins' Thumbs).
- **The Pitchfork**: a compact fork at the TIP (about half as wide, flat, the middle prong is the
  tip; outer prongs fade while aiming; the flames on the outer points; new card picture).
- **The Witch's Broom**: a bit thinner, it is too bulky.
- Quests: only today's board takes progress and shows (4 rows); a finished but unclaimed quest of
  an older board is paid automatically when the next board opens.

## The contract between lanes

1. `Config.Halloween.Cues = { Enabled, List = { {Cue, Candy, Product}, ... } }` (in the base).
   `Config.Products.List.HwPitchfork/HwBroom/HwSword` have `Cue = <cue id>`.
2. **Balance** = `Earned + Bought - Spent` (`Ledger.balance`); `Earned`/`Bought` stay lifetime
   totals. The `Candy` player attribute and `view.candy` are the balance.
3. **Buy with Candy**: `State.send({ buy = cueId })`. The server answers with a moment
   `{ bought = { cue = cueId, ok = boolean, reason = string? } }` (reasons: "Poor", "Owned",
   "Closed", "Busy") and pushes the view and the attribute at once.
4. **View** (`CandyService.viewOf`): `candy, earned, bought, spent, open, today (the current board
   index), boards, hooks, seen, kingReadyAt, converted, convertedMoney, endSeen, owned ({[cueId] =
   true} for the 3 shop cues and the Jack), on = { quests, packs, cues }`. No `given`, `active`,
   `spider`.
5. **Buy with Robux**: `ItemState.request("StoreRequest", "Buy", productKey)`, gift through
   `ShopGift` (`StoreRequest "Gift"`). `ItemState.shop().products[key]` = `{ robux, available,
   owned, canBuy, reason }`; `owned` is true when the player owns the product's `Cue`.
6. Analytics: `HwBuy` (cue, Candy / Robux / Gift), `CandyPickups` with the Candy amount,
   `KingCutscene` (Shown / Skipped / Cut / Done).

## Lanes (each its own worktree and branch; one commit per change; lint + tests green)

| Lane | Owns | Does not touch |
|---|---|---|
| buy | src/shared/Halloween/*, src/server/Halloween/*, PlayerData, Store, Shop, ShopView, SaveSchema, Purchased, Progression/Badges rules, Config.Halloween (not Pickup), Config.Badges, Tutorial/Steps funnel, client Halloween/State, CandyToast, EndScreen, tools/products_spec.json, their tests | EventMenu, EventButton, Config.UI.Halloween |
| menu | client Halloween/EventMenu, EventButton, Config.UI.Halloween, the menu's Strings, menu tests | server files |
| drops | HalloweenMap/CandyDrop, HalloweenMap/Rules (eligibility), MapFx (pickup text), Config.HalloweenMap.Candy, Config.Halloween.Pickup and the Pickups quest needs, Items quiet list, Badges SKIP_OPS, their tests | Ledger, PlayerData |
| king | BossService, KingLook, new client KingEntrance + KingCape, MapClient, the cutscene busy checks, Config.HalloweenMap.Boss/King additions, their tests | CandyDrop |
| cues | assets/cue/*, the generated src/shared/CueSkins/**, Catalog (Spider row), Strings.Items.Cues.SpiderCue, cue tests, uploads | Config.UI.Halloween |

No lane uses the Studio MCP except the menu lane (it works in `~/Desktop/8ball`, where Rojo
serves Studio). Templates in Team Create (`tools/build_cue_templates.luau`) are rebuilt by the
coordinator after the merge.
