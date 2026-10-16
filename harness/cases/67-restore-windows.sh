#!/bin/bash
# A bridge torn off into its own window is still in its own window after a
# relaunch, where it was. One closed before quitting stays closed.
source "$(dirname "$0")/../lib.sh"
for i in 1 2; do printf '<!doctype html><title>Page %s</title><p>Page %s</p>' $i $i > "$CASE_DIR/pages/p$i.html"; done
p1="$CASE_DIR/pages/p1.html"
exe="$BRIDGE_DEV_APP/Contents/MacOS/$(ls "$BRIDGE_DEV_APP/Contents/MacOS" | head -1)"
relaunch() { bridge --quit >/dev/null 2>&1; sleep 0.5; "$exe" >/dev/null 2>&1 & sleep 0.3; wait_ready; settle 1; }

(cd "$CASE_DIR/pages" && bridge p1.html p2.html); wait_ready; settle 0.3
bridge --do select "$p1" >/dev/null; settle 0.2
bridge --do window >/dev/null; settle 0.4
before=$(bridge --state | jq -c '.pageWindows[0].topLeft')

relaunch
s=$(bridge --state)
check_json "after a relaunch the bridge has its window again" "$s" '[.pageWindows[] | select(.location | endswith("/p1.html"))] | length' "1"
check_json "that window shows the page" "$s" '.pageWindows[0] | .showsPage and .visible' "true"
check "where it was" "$(jq -c '.pageWindows[0].topLeft' <<< "$s")" "$before"

bridge --do closewindow "$p1" >/dev/null; settle 0.3
relaunch
check_json "a window closed before quitting stays closed" "$(bridge --state)" '.pageWindows | length' "0"
finish
