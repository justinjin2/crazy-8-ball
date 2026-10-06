#!/bin/bash
# Record the screen for a few seconds with the game's Studio window in front, then give focus
# back to whatever was in front before (the lively GUI's recordings, SHOP_LIVELY_PROMPT 7.5).
# The terminal app needs Screen Recording permission (System Settings, Privacy and Security).
#
#   tools/gui/record_studio.sh SECONDS OUT.mov [STUDIO_PID]
#
# STUDIO_PID: the Studio process showing the game; by default the newest RobloxStudio process
# that is not editing a local file (the LuckyBlock pack's window is opened from a file).
set -euo pipefail
seconds="$1"
out="$2"
pid="${3:-}"
if [ -z "$pid" ]; then
	for p in $(pgrep -x RobloxStudio); do
		if ! ps -o args= -p "$p" | grep -q -- "-localPlaceFile"; then
			pid="$p"
		fi
	done
fi
if [ -z "$pid" ]; then
	echo "no Studio process found" >&2
	exit 1
fi
front=$(osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true')
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true"
sleep 0.6
rm -f "$out"
screencapture -v -V"$seconds" -x "$out"
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $front) to true" || true
echo "$out"
