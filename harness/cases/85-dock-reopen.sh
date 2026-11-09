#!/bin/bash
source "$(dirname "$0")/../lib.sh"
# serial
printf '<!doctype html><title>Page</title><p>Page</p>' > "$CASE_DIR/pages/p.html"
(cd "$CASE_DIR/pages" && bridge p.html); wait_ready; settle 0.3
bridge --do close >/dev/null; settle 0.3
check_json "closed, the window is off screen" "$(bridge --state)" '.windowVisible' "false"
open -g -a "$BRIDGE_DEV_APP"
for i in $(seq 1 30); do [ "$(bridge --state | jq '.windowVisible')" = true ] && break; settle 0.1; done
check_json "opening the app again shows the window" "$(bridge --state)" '.windowVisible' "true"
finish
