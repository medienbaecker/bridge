#!/bin/bash
# The Stop hook: an idle session is woken with its own answer, never another
# session's, never when nothing is open, and never for long when it errors.
source "$(dirname "$0")/../lib.sh"

page=$(fixture decision.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
hook() { printf '%s' "$1" | bridge --hook stop --timeout "${2:-3}" 2>"$CASE_DIR/hook.err"; echo $? > "$CASE_DIR/hook.exit"; }
hook_exit() { cat "$CASE_DIR/hook.exit"; }

start=$(date +%s)
out=$(hook '{"session_id":"someone-else"}')
check "another session's hook returns at once" "$(( $(date +%s) - start < 2 ))" "1"
check "and says nothing, exit 0" "$out|$(hook_exit)|$(wc -c < "$CASE_DIR/hook.err" | tr -d ' ')" "|0|0"
out=$(hook 'not json')
check "garbage on stdin fails open" "$out" ""

# Our session has an open bridge: the hook waits, and returns when the user sends
( sleep 1; bridge --js "$page" "document.querySelector('[data-value=grid]').click(); document.querySelector('[data-send]').click()" >/dev/null ) &
out=$(hook "{\"session_id\":\"$BRIDGE_SESSION\"}" 10)
# When this misses in a full run, the diagnosis travels with the log. Read the
# record as a file: `--read` emits neither presented nor collectedBy, so both used
# to print null and read like evidence, and it collects as a side effect, which set
# the collectedBy the next check asserts.
echo "  debug: hook.err=[$(head -c 200 "$CASE_DIR/hook.err" | tr '\n' ' ')] record=$(jq -c '{status, presented: .presented.session, collectedBy}' "$(sidecar "$page")" 2>/dev/null || echo "no record yet") listing=$(jq -c '[.bridges[] | {session, crossed, location: (.location | split("/") | last)}]' "$XDG_STATE_HOME/bridge-dev/list.json") store=$(ls "$XDG_STATE_HOME/bridge-dev/answers" | tr '\n' ' ')" >&2
check_json "hook blocks the stop" "$out" '.hookSpecificOutput.decision' "block"
check "the rewake path: exit 2 with the hand-over on stderr" "$(hook_exit) $(grep -c 'Bridge: The user answered' "$CASE_DIR/hook.err")" "2 1"
check_json "reason carries the answer" "$out" '.hookSpecificOutput.reason | contains("\"layout\":\"grid\"")' "true"
check_json "reason names the file" "$out" ".hookSpecificOutput.reason | contains(\"$page\")" "true"
check_json "the answer is marked collected" "$(cat "$(sidecar "$page")")" '.collectedBy' "$BRIDGE_SESSION"
start=$(date +%s)
out=$(hook "{\"session_id\":\"$BRIDGE_SESSION\"}")
check "a collected answer is not delivered twice, and nothing open means no wait" "$out|$(( $(date +%s) - start < 2 ))" "|1"

# A new version reopens the bridge, so the hook waits again; closing the window ends the wait
python3 - "$page" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
open(p,'w').write(s.replace('<h2>Corner radius</h2>', '<h2>Density</h2><div class="options"><div data-record="density" data-value="cosy"><strong>Cosy</strong></div></div><h2>Corner radius</h2>'))
PY
# Wait for the rewrite to have reopened the bridge rather than sleep: under a
# loaded run the watcher took longer than half a second and the hook saw the
# old, collected state and returned at once.
for i in $(seq 1 60); do [ "$(bridge --read "$page" 2>/dev/null | jq -r .status)" = open ] && break; sleep 0.1; done
( sleep 1; bridge --do close >/dev/null ) &
out=$(hook "{\"session_id\":\"$BRIDGE_SESSION\"}" 10)
check_json "closing the window wakes the session too" "$out" '.hookSpecificOutput.reason | contains("closed")' "true"

# Stale: an answer nobody collected for two hours goes to whoever asks
python3 - "$(sidecar "$page")" <<'PY'
import json, sys, datetime; p=sys.argv[1]; d=json.load(open(p))
d['status']='sent'; d['closedAt']=None; d['collectedAt']=None; d['collectedBy']=None
d['sentAt']=(datetime.datetime.now(datetime.UTC)-datetime.timedelta(hours=3)).strftime('%Y-%m-%dT%H:%M:%SZ')
json.dump(d, open(p,'w'))
PY
settle 0.3
out=$(hook '{"session_id":"someone-else"}')
check_json "a stale answer is collectable by anyone" "$out" '.hookSpecificOutput.reason | contains("yours now")' "true"

# An answer that lands while the hook is deciding is still the user's answer. The hook
# reads the record to see whether anything is deliverable, then reads it again to
# see whether anything is worth waiting for; a Send between the two is seen by
# neither (not sent yet, and no longer open) and the session is never woken.
# The bridge is crossed so the hook does not wait at all and its one scan is the
# only look there is, and the listing is padded so that scan is long enough to
# land a Send inside on purpose rather than by luck.
race=$(fixture decision.html race.html)
(cd "$CASE_DIR/pages" && bridge race.html 2>/dev/null); wait_ready; settle 0.3
bridge --cross "$race" >/dev/null; settle 0.3
python3 - "$XDG_STATE_HOME/bridge-dev" "$CASE_DIR/pages" 2000 <<'PY'
import hashlib, json, os, sys
state, pages, pad = sys.argv[1], sys.argv[2], int(sys.argv[3])
listing = json.load(open(os.path.join(state, "list.json")))
row = dict(listing["bridges"][0])
rec = {"status": "open", "version": 1, "presented": {"session": "someone-else", "at": "2026-01-01T00:00:00Z", "cwd": pages}}
rows = []
for i in range(pad):
    loc = os.path.join(pages, "pad%d.html" % i)
    open(loc, "w").write("<title>pad</title>")
    key = os.path.realpath(loc)
    ident = hashlib.sha256(key.encode()).hexdigest()[:12]
    json.dump(rec, open(os.path.join(state, "answers", os.path.basename(key) + "-" + ident + ".bridge.json"), "w"))
    rows.append({**row, "id": ident, "location": loc, "session": "someone-else", "title": "pad %d" % i})
listing["bridges"] = listing["bridges"] + rows
json.dump(listing, open(os.path.join(state, "list.json"), "w"), indent=2)
PY
# The names are hand-written, so prove the CLI looks for them where they were put.
check "the padded records are where the CLI looks for them" "$([ -f "$(sidecar "$CASE_DIR/pages/pad0.html")" ] && echo there)" "there"
now() { python3 -c 'import time; print(time.time())'; }
( sleep 0.05; bridge --js "$race" "document.querySelector('[data-value=grid]').click(); document.querySelector('[data-send]').click()" >/dev/null 2>&1 ) &
t0=$(now); out=$(hook "{\"session_id\":\"$BRIDGE_SESSION\"}" 10); t1=$(now); wait
# If the scan ever became quicker than the delay, the Send would land after the
# hook rather than inside it and this would pass without exercising anything.
check "the hook was still deciding when the user pressed Send" "$(awk "BEGIN {print ($t1 - $t0 > 0.05) ? \"inside\" : \"not exercised\"}")" "inside"
check_json "an answer that lands while the hook is deciding is still delivered" "$out" ".hookSpecificOutput.reason | contains(\"$race\")" "true"
check "and it is marked collected, not left for nobody" "$(jq -r '.collectedBy // "nobody"' "$(sidecar "$race")")" "$BRIDGE_SESSION"
finish
