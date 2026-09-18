#!/usr/bin/env bash
# Static checks: formatting (StyLua), lints (Selene), types (luau-lsp).
# Run from anywhere: tools/lint.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.aftman/bin:$PATH"

echo "== StyLua (format check)"
stylua --check src tests

echo "== Selene (lints)"
selene src tests

echo "== luau-lsp (type check)"
DEFS="tools/globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
	echo "   skipped: $DEFS is missing."
	echo "   Download it once with tools/get-types.sh (see docs/MVP_PLAN.md, M0)."
elif ! command -v luau-lsp >/dev/null; then
	echo "   skipped: luau-lsp not installed. Run: aftman install"
else
	rojo sourcemap default.project.json -o sourcemap.json
	luau-lsp analyze \
		--definitions="$DEFS" \
		--sourcemap=sourcemap.json \
		--base-luaurc=.luaurc \
		src
fi
echo "== lint OK"
