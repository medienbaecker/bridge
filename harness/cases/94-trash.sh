#!/bin/bash
source "$(dirname "$0")/../lib.sh"
folder="$XDG_STATE_HOME/bridge/pages/demo"
mkdir -p "$folder"
printf '<!doctype html><title>Ours</title><p>x</p>' > "$folder/ours.html"
printf '<!doctype html><title>Theirs</title><p>x</p>' > "$CASE_DIR/pages/theirs.html"
(cd "$folder" && bridge ours.html); wait_ready; settle 0.3
sidecar_ours=$(sidecar "$folder/ours.html")
bridge --do select "$folder/ours.html" >/dev/null; settle 0.2
bridge --do remove >/dev/null; settle 0.3
check "a page in Bridge's pages folder goes with its answers when removed" "$([ -e "$folder/ours.html" ] && echo file; [ -e "$sidecar_ours" ] && echo answers; jq -r --arg l "$folder/ours.html" '[.bridges[] | select(.location == $l)] | length' "$XDG_STATE_HOME/bridge-dev/list.json")" "0"
(cd "$CASE_DIR/pages" && bridge theirs.html); wait_ready; settle 0.3
bridge --do select "$CASE_DIR/pages/theirs.html" >/dev/null; settle 0.2
bridge --do remove >/dev/null; settle 0.3
check "a page elsewhere only leaves the list, its file stays" "$([ -e "$CASE_DIR/pages/theirs.html" ] && echo file) $(jq -r --arg l "$CASE_DIR/pages/theirs.html" '[.bridges[] | select(.location == $l)] | length' "$XDG_STATE_HOME/bridge-dev/list.json")" "file 0"
finish
