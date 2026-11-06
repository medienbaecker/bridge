#!/bin/bash
# A newer build installed under the running app: a quiet row says so, and a
# relaunch comes back to the same bridge.
source "$(dirname "$0")/../lib.sh"
page=$(fixture decision.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html); wait_ready
exe="$BRIDGE_DEV_APP/Contents/MacOS/$(ls "$BRIDGE_DEV_APP/Contents/MacOS" | head -1)"
trap 'touch "$exe"; bridge --quit >/dev/null 2>&1 || true' EXIT
check_json "a fresh launch reports no update" "$(bridge --state)" '.updateReady' "false"
sleep 1; touch "$exe"
check_json "the executable newer than the process: the row says an update is ready" "$(bridge --state)" '.updateText' "Update ready"
snap update "The update row at the foot of the sidebar"
bridge --do sidebarwidth 160 >/dev/null; settle 0.5
check_json "at the narrowest sidebar the whole text fits: nothing is cut" "$(bridge --state)" '.updateRow | .labelX + .textWidth <= .x + .width' "true"

bridge --do relaunch >/dev/null 2>&1 || true
for i in $(seq 1 100); do [ "$(bridge --state 2>/dev/null | jq -r '.ready // false')" = "true" ] && [ "$(bridge --state 2>/dev/null | jq -r '.updateReady')" = "false" ] && break; sleep 0.1; done
state=$(bridge --state)
check_json "the app came back in the new build: no update pending" "$state" '.updateReady' "false"
check_json "on the same bridge, ready" "$state" '(.selected | endswith("decision.html")) and .ready' "true"
finish
