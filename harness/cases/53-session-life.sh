#!/bin/bash
# Session states, and documents stamped with their commit. Whether anyone hears
# an open bridge comes from Claude Code's session registry: a live session
# hears it, busy or idle; a session that has ended says so, also when its
# registry file outlived its process; without a registry the row says only
# "no agent waiting". The window's subtitle says how far the repo has moved
# since the page was asked. Case 51 proves the row's subtitle is drawn; case 03
# the window's.
source "$(dirname "$0")/../lib.sh"
S="$BRIDGE_SESSION"

page=$(fixture decision.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html) >/dev/null; wait_ready
bridge --do project all >/dev/null; settle 0.4
sub() { bridge --state | jq -r --arg l "$page" '[.sidebar[].bridges[] | select(.location == $l)][0].subtitle'; }

check "without a registry it says only what it knows" "$(sub)" "pages · no agent waiting"
claude_session "$S" busy; settle 2.5
check "a live session hears it, even mid-turn" "$(sub)" "pages"
end_session "$S"; mkdir -p "$BRIDGE_CLAUDE_SESSIONS"; settle 2.5
check "the session ended" "$(sub)" "pages · session ended"
sleep 0 & dead=$!; wait "$dead"
printf '{"pid":%s,"sessionId":"%s","status":"idle","messagingSocketPath":"/tmp/none.sock"}' "$dead" "$S" > "$BRIDGE_CLAUDE_SESSIONS/$dead.json"
settle 2.5
check "or its process is, whatever the file says" "$(sub)" "pages · session ended"

check_json "the window says nothing while the repo is where it was" "$(bridge --state)" '.subtitle' ""
for i in 1 2; do (cd "$CASE_DIR/pages" && echo "$i" > "f$i" && git add -A && git -c user.name=t -c user.email=t@t commit -qm "c$i"); done
bridge --do select "$page" >/dev/null; settle 0.3
check_json "two commits later it says so under the title" "$(bridge --state)" '.subtitle' "2 commits since this was asked"
finish
