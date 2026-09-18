#!/usr/bin/env bash
# Auto-format all Luau with StyLua.
set -euo pipefail
cd "$(dirname "$0")/.."
stylua src tests
