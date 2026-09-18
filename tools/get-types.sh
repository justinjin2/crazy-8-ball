#!/usr/bin/env bash
# Downloads the Roblox API type definitions that luau-lsp needs for `analyze`.
# Source: the luau-lsp repository (JohnnyMorganz/luau-lsp), file scripts/globalTypes.d.luau.
# Re-run occasionally to pick up new Roblox APIs.
set -euo pipefail
cd "$(dirname "$0")/.."
URL="https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
curl -fsSL "$URL" -o tools/globalTypes.d.luau
echo "saved tools/globalTypes.d.luau ($(du -h tools/globalTypes.d.luau | cut -f1))"
