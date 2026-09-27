# Vendored code: never edit by hand

## ProfileStore

- **What:** `ProfileStore.luau`, loleris' session-locked DataStore library (successor of
  ProfileService). `src/server/PlayerData.luau` is the only module that requires it.
- **Source:** https://github.com/MadStudioRoblox/ProfileStore, file `ProfileStore.luau` on
  `main`, at commit `45c9847cbcf1fc260369c50eb335aba7c35aecdd` (downloaded 2026-09-27).
- **License:** Apache-2.0, in `LICENSE` next to it.
- **Rules:** never edit it. To update, download the new raw file and LICENSE, record the new
  SHA here (`git ls-remote https://github.com/MadStudioRoblox/ProfileStore HEAD`), and re-run
  the save-layer tests. StyLua, Selene and luau-lsp skip this folder (`.styluaignore`,
  `selene.toml`, `tools/lint.sh`).
