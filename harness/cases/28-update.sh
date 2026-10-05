#!/bin/bash
# A newer build installed under the running app: a quiet row says so, relaunch
# refuses while a note is half-written, and comes back to the same bridge.
source "$(dirname "$0")/../lib.sh"
page=$(fixture decision.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html); wait_ready
js() { bridge --js "$page" "$1"; }
exe="$BRIDGE_DEV_APP/Contents/MacOS/$(ls "$BRIDGE_DEV_APP/Contents/MacOS" | head -1)"
trap 'touch "$exe"; bridge --quit >/dev/null 2>&1 || true' EXIT
check_json "a fresh launch reports no update" "$(bridge --state)" '.updateReady' "false"
sleep 1; touch "$exe"
state=$(bridge --state)
check_json "the executable newer than the process: an update is ready" "$state" '.updateReady' "true"
check_json "and the row says so" "$state" '.updateText' "Update ready"
snap update "The update row at the foot of the sidebar"

bridge --do point >/dev/null
js "const el = document.querySelector('[data-value=list] strong'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: r.left + 10, clientY: r.top + 5}))" >/dev/null; settle 0.3
js "document.querySelector('.bridge-thread:popover-open textarea').value = 'half a thought'; return 1" >/dev/null
bridge --do relaunch >/dev/null; settle 0.5
state=$(bridge --state)
check_json "relaunch refuses while a note is half-written" "$state" '.ready' "true"
check_json "and says why" "$state" '.updateText' "Finish your note first"

js "document.querySelector('.bridge-thread:popover-open textarea').value = ''; return 1" >/dev/null
bridge --do relaunch >/dev/null 2>&1 || true
for i in $(seq 1 100); do [ "$(bridge --state 2>/dev/null | jq -r '.ready // false')" = "true" ] && [ "$(bridge --state 2>/dev/null | jq -r '.updateReady')" = "false" ] && break; sleep 0.1; done
state=$(bridge --state)
check_json "the app came back in the new build: no update pending" "$state" '.updateReady' "false"
check_json "on the same bridge" "$state" '.selected | endswith("decision.html")' "true"
check_json "page ready" "$state" '.ready' "true"
finish
