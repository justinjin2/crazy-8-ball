#!/usr/bin/env bash
# Runs the automated tests (physics, rules) in Lune, no Studio needed.
set -euo pipefail
cd "$(dirname "$0")/.."
lune run tests/run.luau
