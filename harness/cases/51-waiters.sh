#!/bin/bash
# An open bridge with no
# agent process waiting on it says so in its subtitle, the notes of a bridge show
# as resolved of total beside its time, and past a limit the projects column says
# how many agent processes are waiting and what they hold, so a pile-up of
# waiting CLIs is visible before it exhausts memory.
source "$(dirname "$0")/../lib.sh"
export BRIDGE_PILEUP_COUNT=2
CLI="$ROOT/build.noindex/bridge-dev"

page=$(fixture decision.html)
notes=$(fixture decision.html notes.html)
repo
# Two notes on the second page before it opens, one resolved.
cat > "$(sidecar "$notes")" <<'JSON'
{"status":"open","comments":[
 {"id":"a1","text":"first","target":"h1","state":"done","at":"2026-09-28T10:00:00Z","version":1,"anchor":{},"said":[]},
 {"id":"b2","text":"second","target":"h1","state":"open","at":"2026-09-28T10:01:00Z","version":1,"anchor":{},"said":[]}]}
JSON
(cd "$CASE_DIR/pages" && bridge notes.html && bridge decision.html) >/dev/null; wait_ready
bridge --do project all >/dev/null; settle 0.4
bridge --do select "$page" >/dev/null; settle 0.4

row() { bridge --state | jq -r --arg l "$1" "[.sidebar[].bridges[] | select(.location == \$l)][0].$2"; }
waiters() { "$CLI" --waiters; }

# The rightmost dark ink of the selected row between two fractions of its height,
# in points from the column's edge.
right_ink() {  # <shot> <from fraction> <to fraction>
  local state; state=$(bridge --state)
  python3 -c '
import sys; sys.path.insert(0, "'"$ROOT"'/harness"); import measure
path, scale, col, top, h, f0, f1 = sys.argv[1], *map(float, sys.argv[2:8])
y0, y1 = int((top + h * f0) * scale), int((top + h * f1) * scale)
right = None
for r, width, px in measure.rows(path, y1):
    if r < y0: continue
    for i in range(len(px) - 1, int(col * scale), -1):
        if i < len(px) and sum(px[i][:3]) < 600 and i < int((col + 260) * scale):
            right = i if right is None else max(right, i); break
if right is None: sys.exit(1)
print(round(right / scale - col))' "$CASE_DIR/shots/$1.png" \
    "$(printf '%s' "$state" | jq -r .backingScale)" "$(printf '%s' "$state" | jq -r .sidebarGeometry.columnX)" \
    "$(printf '%s' "$state" | jq -r .sidebarGeometry.rowInWindow.top)" "$(printf '%s' "$state" | jq -r .sidebarGeometry.rowInWindow.height)" "$2" "$3"
}

# Nobody waits: the subtitle says so, drawn.
check "an open bridge nobody waits on says so under its title" "$(row "$page" subtitle)" "pages · no agent waiting"
check "and is not listening" "$(row "$page" listening)" "false"
shot alone >/dev/null
alone=$(ink "the subtitle with nobody waiting" right_ink alone 0.62 0.95)

# A `--wait` on it registers, and the subtitle is the project again.
"$CLI" --wait "$page" --timeout 60 >/dev/null & w1=$!
settle 0.6
check_json "--waiters lists the waiting process" "$(waiters)" "[.[] | select(.pid == $w1)] | length" "1"
check_json "as a wait, for this session, holding memory" "$(waiters)" "[.[] | select(.pid == $w1)][0] | \"\(.kind) \(.session) \(.megabytes > 0)\"" "wait test-51-waiters true"
check "the subtitle is the project alone while it waits" "$(row "$page" subtitle)" "pages"
shot heard >/dev/null
heard=$(ink "the subtitle while an agent waits" right_ink heard 0.62 0.95)
check "the words are drawn: the subtitle's ink ends further right with them ($alone vs $heard pt)" \
  "$(awk "BEGIN {print ($alone - $heard > 40) ? \"longer\" : \"not\"}")" "longer"

# Killed without a chance to clean up: its file is left behind and must not count.
kill -9 "$w1" 2>/dev/null; wait "$w1" 2>/dev/null
check "a killed waiter leaves its file" "$(ls "$XDG_STATE_HOME/bridge-dev/waiters" | grep -c "^$w1.json$")" "1"
check_json "and a reader drops it" "$(waiters)" "[.[] | select(.pid == $w1)] | length" "0"
check "the file is gone" "$(ls "$XDG_STATE_HOME/bridge-dev/waiters" | grep -c "^$w1.json$")" "0"
check "the subtitle says so again" "$(row "$page" subtitle)" "pages · no agent waiting"

# The Stop hook registers too, as a hook, and takes its file back when it exits.
printf '{"session_id":"test-51-waiters"}' | "$CLI" --hook stop --timeout 3 >/dev/null 2>&1 & h=$!
settle 0.6
check_json "the Stop hook registers while it waits" "$(waiters)" "[.[] | select(.pid == $h)][0].kind" "hook"
wait "$h" 2>/dev/null
check_json "and leaves nothing behind when it exits" "$(waiters)" "length" "0"

# Past the limit (2 here, 10 by default) the projects column says how many and how much.
check_json "no pile-up row under the limit" "$(bridge --state)" '.pileupRow | length' "0"
"$CLI" --wait "$page" --timeout 60 >/dev/null & w2=$!
"$CLI" --wait "$notes" --timeout 60 >/dev/null & w3=$!
settle 0.6
state=$(bridge --state)
check_json "at the limit the row names the count and the memory" "$state" '.pileupRow.text | test("^2 agents waiting · [0-9.]+ (MB|GB)$")' "true"
shot pileup >/dev/null
scale=$(printf '%s' "$state" | jq -r .backingScale)
ptop=$(printf '%s' "$state" | jq -r .pileupRow.top); ph=$(printf '%s' "$state" | jq -r .pileupRow.height); px=$(printf '%s' "$state" | jq -r .pileupRow.x)
pink=$(ink "the pile-up row" python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/pileup.png" "$(awk "BEGIN {print int(($ptop + $ph / 2) * $scale)}")" 1 \
  | awk -v from="$(awk "BEGIN {print ($px + 40) * $scale}")" '$1 > from && $3 + $4 + $5 < 500 {n++} END {if (n) print n}')
check "and it is drawn ($pink runs of ink across its middle)" "$(awk "BEGIN {print ($pink > 10) ? \"drawn\" : \"blank\"}")" "drawn"
kill "$w2" "$w3" 2>/dev/null; wait 2>/dev/null
check_json "a clean exit takes the files back and the row goes" "$(bridge --state)" '.pileupRow | length' "0"

# Resolved of total, beside the time, only on a bridge with notes.
check "a bridge with notes shows resolved of total" "$(row "$notes" resolved)" "1/2"
check "one without notes shows nothing" "$(row "$page" resolved)" "null"
shot plain >/dev/null
bridge --do select "$notes" >/dev/null; settle 0.4
shot counted >/dev/null
count_ink() {  # dark ink in the 44 pt before the time on the title's line of the selected row
  local state; state=$(bridge --state); local s t h tx
  s=$(printf '%s' "$state" | jq -r .backingScale); t=$(printf '%s' "$state" | jq -r .sidebarGeometry.rowInWindow.top)
  h=$(printf '%s' "$state" | jq -r .sidebarGeometry.rowInWindow.height); tx=$(printf '%s' "$state" | jq -r .sidebarGeometry.timeX)
  python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/$1.png" "$(awk "BEGIN {print int(($t + $h / 2) * $s)}")" 1 \
    | awk -v a="$(awk "BEGIN {print ($tx - 44) * $s}")" -v b="$(awk "BEGIN {print ($tx - 2) * $s}")" '$1 > a && $2 < b && $3 + $4 + $5 < 600 {n++} END {print n + 0}'
}
counted=$(count_ink counted)
check "the count is drawn beside the time ($counted runs of ink)" "$(awk "BEGIN {print ($counted > 3) ? \"drawn\" : \"blank\"}")" "drawn"
bridge --do select "$page" >/dev/null; settle 0.4
plain=$(count_ink plain)
check "and the row without notes has none there ($plain runs, against $counted)" "$(awk "BEGIN {print ($plain == 0 && $counted > 3) ? \"none\" : \"some\"}")" "none"
snap waiters "No agent waiting, and resolved of total"
finish
