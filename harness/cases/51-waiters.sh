#!/bin/bash
# An open bridge with no
# agent process waiting on it says so in its subtitle, and past a limit the projects column says
# how many agent processes are waiting and what they hold, so a pile-up of
# waiting CLIs is visible before it exhausts memory.
source "$(dirname "$0")/../lib.sh"
export BRIDGE_PILEUP_COUNT=2
CLI="$ROOT/build.noindex/bridge-dev"

page=$(fixture decision.html)
notes=$(fixture decision.html notes.html)
repo
(cd "$CASE_DIR/pages" && bridge notes.html && bridge decision.html) >/dev/null; wait_ready
bridge --do project all >/dev/null; settle 0.4
bridge --do select "$page" >/dev/null; settle 0.4

row() { bridge --state | jq -r --arg l "$1" "[.sidebar[].bridges[] | select(.location == \$l)][0].$2"; }
waiters() { "$CLI" --waiters; }

check "an open bridge nobody waits on says so under its title, not listening" "$(row "$page" subtitle) $(row "$page" listening)" "pages · no agent waiting false"

# A `--wait` on it registers, and the subtitle is the project again.
"$CLI" --wait "$page" --timeout 60 >/dev/null & w1=$!
settle 0.6
check_json "--waiters lists the waiting process as a wait, for this session, holding memory" "$(waiters)" "[.[] | select(.pid == $w1)] | map(\"\(.kind) \(.session) \(.megabytes > 0)\") | join(\",\")" "wait test-51-waiters true"
check "the subtitle is the project alone while it waits" "$(row "$page" subtitle)" "pages"

# Killed without a chance to clean up: its file is left behind and must not count.
kill -9 "$w1" 2>/dev/null; wait "$w1" 2>/dev/null
check_json "a reader drops a killed waiter" "$(waiters)" "[.[] | select(.pid == $w1)] | length" "0"
check "the subtitle says so again" "$(row "$page" subtitle)" "pages · no agent waiting"

# Past the limit (2 here, 10 by default) the projects column says how many and how much.
check_json "no pile-up row under the limit" "$(bridge --state)" '.pileupRow | length' "0"
"$CLI" --wait "$page" --timeout 60 >/dev/null & w2=$!
"$CLI" --wait "$notes" --timeout 60 >/dev/null & w3=$!
settle 0.6
check_json "at the limit the row names the count and the memory" "$(bridge --state)" '.pileupRow.text | test("^2 agents waiting · [0-9.]+ (MB|GB)$")' "true"
kill "$w2" "$w3" 2>/dev/null; wait 2>/dev/null
check_json "a clean exit takes the files back and the row goes" "$(bridge --state)" '.pileupRow | length' "0"

snap waiters "No agent waiting"
finish
