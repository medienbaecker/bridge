#!/bin/bash
# Delivery: a Send or a close is posted to the inbox of the session holding the
# page, once, and never to another session. A session that was gone gets it
# when it comes back, as a resumed session does.
source "$(dirname "$0")/../lib.sh"

page=$(fixture decision.html)
repo
claude_session "$BRIDGE_SESSION"
claude_session someone-else
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready

bridge --js "$page" "document.querySelector('[data-value=grid]').click(); document.querySelector('[data-send]').click()" >/dev/null
got=$(inbox "$BRIDGE_SESSION")
check "the Send reaches the holding session's inbox" "$(printf '%s' "$got" | grep -c 'Bridge: The user answered')" "1"
check "with the answer" "$(printf '%s' "$got" | grep -c '"layout":"grid"')" "1"
check "and the file" "$(printf '%s' "$got" | grep -c "$page")" "1"
check_json "the answer is marked collected" "$(cat "$(sidecar "$page")")" '.collectedBy' "$BRIDGE_SESSION"
settle 2.5
check "it is posted once" "$(inbox "$BRIDGE_SESSION" | grep -c 'Bridge:')" "1"
check "another session hears nothing" "$(inbox someone-else 1 | wc -l | tr -d ' ')" "0"

# A new version reopens the bridge; closing the window is delivered too.
python3 - "$page" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
open(p,'w').write(s.replace('<h2>Corner radius</h2>', '<h2>Density</h2><div class="options"><div data-record="density" data-value="cosy"><strong>Cosy</strong></div></div><h2>Corner radius</h2>'))
PY
for i in $(seq 1 60); do [ "$(bridge --read "$page" 2>/dev/null | jq -r .status)" = open ] && break; sleep 0.1; done
bridge --do close >/dev/null; settle 0.5
check "closing the window is delivered too" "$(inbox "$BRIDGE_SESSION" | grep -c 'closed .* without answering')" "1"

# The session ends before the user answers; it gets the answer when it is resumed.
gone=$(fixture decision.html gone.html)
(cd "$CASE_DIR/pages" && bridge gone.html); wait_ready
end_session "$BRIDGE_SESSION"
: > "$CASE_DIR/inbox-$BRIDGE_SESSION"
bridge --js "$gone" "document.querySelector('[data-value=list]').click(); document.querySelector('[data-send]').click()" >/dev/null
settle 0.5
check_json "nobody to deliver to: it stays uncollected" "$(cat "$(sidecar "$gone")")" '.collectedBy // "nobody"' "nobody"
claude_session "$BRIDGE_SESSION"
check "resumed, the session gets the answer" "$(inbox "$BRIDGE_SESSION" 50 | grep -c "answered $gone")" "1"
check_json "and it is collected" "$(cat "$(sidecar "$gone")")" '.collectedBy' "$BRIDGE_SESSION"

# An agent that reads its answer first is not told again.
read=$(fixture decision.html read.html)
(cd "$CASE_DIR/pages" && bridge read.html); wait_ready
end_session "$BRIDGE_SESSION"
: > "$CASE_DIR/inbox-$BRIDGE_SESSION"
bridge --js "$read" "document.querySelector('[data-value=list]').click(); document.querySelector('[data-send]').click()" >/dev/null
settle 0.3
bridge --read "$read" >/dev/null
claude_session "$BRIDGE_SESSION"
settle 2.5
check "an answer already read is not posted" "$(inbox "$BRIDGE_SESSION" 1 | grep -c "$read")" "0"

check "the old Stop hook does nothing now" "$(printf '{"session_id":"x"}' | bridge --hook stop --timeout 5; echo "exit=$?")" "exit=0"
finish
