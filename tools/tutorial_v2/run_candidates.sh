#!/usr/bin/env bash
# Plays simulated game 1s (sim_game.luau, the production rig) on each of the best N breaks of a
# search_combo.luau deal pass (ranked by rank_combo.py) and summarises each.
#   tools/tutorial_v2/run_candidates.sh <breaks.jsonl> <N> <games> <outDir> [workers]
set -euo pipefail
cd "$(dirname "$0")/../.."
breaks="$1"; n="$2"; games="$3"; dir="$4"; workers="${5:-16}"
mkdir -p "$dir"
python3 tools/tutorial_v2/rank_combo.py "$breaks" "$dir/shortlist.jsonl" "$n" >"$dir/ranked.txt"
i=0
while IFS= read -r line; do
	i=$((i + 1))
	python3 - "$line" "$dir/opts_$i.json" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
json.dump({"breakShot": {"seed": r["seed"], "cueX": r["cx"], "cueY": r["cy"], "angle": r["angle"],
	"power": r["power"], "layout": r["layout"]}}, open(sys.argv[2], "w"))
PY
	tools/tutorial_v2/run_games.sh "$dir/opts_$i.json" "$dir/games_$i.jsonl" "$games" "$workers" >/dev/null
	echo "== candidate $i: $(head -c 160 <<<"$line")"
	python3 tools/tutorial_v2/summarize_games.py "$dir/games_$i.jsonl" | grep -E "games|won|lost|dead:|aimPotPct|combo|abilityPotPct|secondsMedian|eightBack"
done <"$dir/shortlist.jsonl"
