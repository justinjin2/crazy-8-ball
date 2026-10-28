#!/usr/bin/env bash
# The Halloween 2026 build's lanes (docs/halloween/PLAN.md §4): worktrees, place copies, Rojo,
# Studio windows and the Claude terminals.
#
#   tools/halloween/lanes.sh setup     worktree + branch (from halloween) + git-ignored files +
#                                      place copy for every lane, then each lane's Rojo
#   tools/halloween/lanes.sh studio    open every lane's place copy in Studio
#   tools/halloween/lanes.sh launch    open one Terminal window per lane running its Claude
#   tools/halloween/lanes.sh command <lane|coordinator>   print that window's command
#   tools/halloween/lanes.sh status    every lane: folder, branch, last commit, Rojo
set -euo pipefail

MAIN="$(cd "$(dirname "$0")/../.." && pwd)"
PARENT="$(dirname "$MAIN")"
LANES=(hw-core hw-cues-a hw-cues-b hw-map hw-sys hw-gui)
SESSION="c1c2a857-6fc8-47bc-acae-b6bcdcafcb15" # the desktop planning conversation (forked, not moved)

port_of() {
	case "$1" in
		main | coordinator) echo 34872 ;;
		hw-core) echo 34883 ;;
		hw-cues-a) echo 34884 ;;
		hw-cues-b) echo 34885 ;;
		hw-map) echo 34886 ;;
		hw-sys) echo 34887 ;;
		hw-gui) echo 34888 ;;
		*) echo "unknown lane: $1" >&2 && exit 1 ;;
	esac
}
model_of() { case "$1" in hw-cues-a | hw-cues-b) echo fable ;; *) echo opus ;; esac; }
brief_of() {
	case "$1" in
		hw-core) echo HW_CORE_PROMPT.md ;; hw-cues-a) echo HW_CUES_A_PROMPT.md ;;
		hw-cues-b) echo HW_CUES_B_PROMPT.md ;; hw-map) echo HW_MAP_PROMPT.md ;;
		hw-sys) echo HW_SYS_PROMPT.md ;; hw-gui) echo HW_GUI_PROMPT.md ;;
	esac
}
hook_of() { local l="${1#hw-}"; echo "tools/overnight/hw_${l//-/_}.json"; }
dir_of() { if [ "$1" = main ] || [ "$1" = coordinator ]; then echo "$MAIN"; else echo "$PARENT/8ball-$1"; fi; }
listening() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

copy_ignored() {
	local dest="$1"
	mkdir -p "$dest/src/server/MapData"
	cp "$MAIN/src/server/MapData/GrayBox.json" "$dest/src/server/MapData/GrayBox.json"
	for f in "$MAIN"/tools/globalTypes*.d.luau; do [ -e "$f" ] && cp "$f" "$dest/tools/"; done
	return 0
}

start_rojo() {
	local lane="$1" port dir
	port="$(port_of "$lane")"
	dir="$(dir_of "$lane")"
	if listening "$port"; then echo "$lane: Rojo already on $port" && return 0; fi
	mkdir -p "$dir/.lanes"
	(cd "$dir" && nohup rojo serve default.project.json --port "$port" >"$dir/.lanes/rojo.log" 2>&1 &)
	sleep 1
	if listening "$port"; then echo "$lane: Rojo on $port"; else echo "$lane: Rojo failed, see $dir/.lanes/rojo.log" >&2; fi
}

setup() {
	for lane in "${LANES[@]}"; do
		local dir
		dir="$(dir_of "$lane")"
		if [ -d "$dir" ]; then
			echo "$lane: $dir exists (left as it is)"
		elif git -C "$MAIN" show-ref --verify --quiet "refs/heads/$lane"; then
			git -C "$MAIN" worktree add "$dir" "$lane"
		else
			git -C "$MAIN" worktree add -b "$lane" "$dir" halloween
		fi
		copy_ignored "$dir"
		mkdir -p "$dir/place"
		[ -e "$dir/place/lane-$lane.rbxl" ] || cp "$MAIN/place/8ball.rbxl" "$dir/place/lane-$lane.rbxl"
		mkdir -p "$HOME/Desktop/8ball-refs/halloween/shots/$lane"
		start_rojo "$lane"
	done
}

studio() {
	for lane in "${LANES[@]}"; do
		open -a RobloxStudio "$(dir_of "$lane")/place/lane-$lane.rbxl"
		sleep 4
	done
}

command_of() {
	local lane="$1" dir
	dir="$(dir_of "$lane")"
	if [ "$lane" = coordinator ]; then
		echo "cd '$dir' && rm -f \"\$(git rev-parse --absolute-git-dir)/overnight-stop-count\" && caffeinate -dims claude --resume $SESSION --fork-session --settings tools/overnight/hw_coordinator.json --model opus --effort ultracode --dangerously-skip-permissions"
		return
	fi
	echo "cd '$dir' && rm -f \"\$(git rev-parse --absolute-git-dir)/overnight-stop-count\" && caffeinate -dims claude --settings $(hook_of "$lane") --model $(model_of "$lane") --effort xhigh --dangerously-skip-permissions \"You are the $lane lane of the Halloween build. Read docs/halloween/PLAN.md, then docs/prompts/$(brief_of "$lane") and do everything it says, starting with section 0 and the first unticked Progress line.\""
}

launch() {
	for lane in "${LANES[@]}"; do
		local cmd
		cmd="$(command_of "$lane")"
		osascript -e "tell application \"Terminal\" to do script \"${cmd//\"/\\\"}\"" >/dev/null
		osascript -e "tell application \"Terminal\" to set custom title of front window to \"$lane\"" >/dev/null 2>&1 || true
		sleep 2
	done
	osascript -e 'tell application "Terminal" to activate' >/dev/null
}

status() {
	printf '%-12s %-6s %-5s %-12s %s\n' lane port rojo branch "last commit"
	for lane in coordinator "${LANES[@]}"; do
		local dir port rojo=off
		dir="$(dir_of "$lane")"
		port="$(port_of "$lane")"
		listening "$port" && rojo=on
		if [ -d "$dir" ]; then
			printf '%-12s %-6s %-5s %-12s %s\n' "$lane" "$port" "$rojo" "$(git -C "$dir" branch --show-current)" "$(git -C "$dir" log -1 --format='%h %ar %s' | cut -c1-60)"
		else
			printf '%-12s %-6s %-5s %s\n' "$lane" "$port" "$rojo" "(no worktree)"
		fi
	done
}

case "${1:-status}" in
	setup) setup ;;
	studio) studio ;;
	launch) launch ;;
	command) command_of "${2:?lane or coordinator}" ;;
	status) status ;;
	*) echo "usage: $0 setup|studio|launch|command <lane>|status" >&2 && exit 1 ;;
esac
