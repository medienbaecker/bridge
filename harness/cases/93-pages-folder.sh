#!/bin/bash
source "$(dirname "$0")/../lib.sh"
agent="test-$CASE_NAME-agent"
printf '<!doctype html><title>Lorem</title><p>x</p>' > "$CASE_DIR/pages/page.html"
repo
(cd "$CASE_DIR/pages" && claude_session "$agent" idle)
folder="$XDG_STATE_HOME/bridge/pages/$(basename "$CASE_DIR")"
mkdir -p "$folder"
printf '<!doctype html><title>Ipsum</title><p>x</p>' > "$folder/plan.html"
(cd "$folder" && BRIDGE_SESSION="$agent" bridge plan.html); wait_ready; settle 0.3
check "a page presented from inside the pages folder joins its agent's repository, not a project named after the folder" "$(jq -r --arg l "$folder/plan.html" '.bridges[] | select(.location == $l) | .project' "$XDG_STATE_HOME/bridge-dev/list.json")" "$(cd "$CASE_DIR/pages" && git rev-parse --show-toplevel)"
end_session "$agent"
finish
