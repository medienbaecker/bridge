#!/bin/bash
# Session states, and documents stamped with their commit. Why nobody waits on
# an open bridge comes from the session hook's files: a turn still running says
# "agent working" (the Stop hook starts only when it ends), a session that has
# ended says so, and without the session hook it stays "no agent waiting". The
# window's subtitle says how far the repo has moved since the page was asked.
# Case 51 proves the row's subtitle is drawn; case 03 the window's.
source "$(dirname "$0")/../lib.sh"
S="$BRIDGE_SESSION"
dir="$XDG_STATE_HOME/bridge/sessions"
file="$dir/$S.json"
event() { printf '{"session_id":"%s","hook_event_name":"%s"}' "$S" "$1"; }
hook() { event "$1" | bridge --hook session; }

page=$(fixture decision.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html) >/dev/null; wait_ready
bridge --do project all >/dev/null; settle 0.4
sub() { bridge --state | jq -r --arg l "$page" '[.sidebar[].bridges[] | select(.location == $l)][0].subtitle'; }

check "without the session hook it says only what it knows" "$(sub)" "pages · no agent waiting"
check "the session hook is silent" "$(hook SessionStart)" ""
check_json "a session starts idle, with the pid of the process it lives in" "$(cat "$file")" '"\(.state) \(.pid | type)"' "idle number"
hook UserPromptSubmit
check "a turn still running: the Stop hook has not started yet" "$(sub)" "pages · agent working"
event Stop | bridge --hook stop --timeout 0 >/dev/null 2>&1
check "the turn over and no hook waiting: nobody waits" "$(sub)" "pages · no agent waiting"
hook SessionEnd
check "the session ended: its file is gone" "$(test -e "$file" && echo there || echo gone)" "gone"
check "and the row says so" "$(sub)" "pages · session ended"
hook UserPromptSubmit
sleep 0 & dead=$!; wait "$dead"
jq --argjson p "$dead" '.pid = $p' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
check "or its process is, whatever the file says" "$(sub)" "pages · session ended"
rm -rf "$dir"
check "without the session hook again, only what it knows" "$(sub)" "pages · no agent waiting"

check_json "the window says nothing while the repo is where it was" "$(bridge --state)" '.subtitle' ""
for i in 1 2; do (cd "$CASE_DIR/pages" && echo "$i" > "f$i" && git add -A && git -c user.name=t -c user.email=t@t commit -qm "c$i"); done
bridge --do select "$page" >/dev/null; settle 0.3
check_json "two commits later it says so under the title" "$(bridge --state)" '.subtitle' "2 commits since this was asked"
finish
