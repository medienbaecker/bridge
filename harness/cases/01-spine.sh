#!/bin/bash
source "$(dirname "$0")/../lib.sh"

page=$(fixture decision.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready || finish

state=$(bridge --state)
check_json "window shows the page" "$state" '.title' "Card layout for the archive"
check_json "row is title, time, waiting, unread" "$state" '.sidebar[0].bridges[0].row' "Card layout for the archive · now · waiting · unread"
snap open "Freshly presented"
before=$(bridge --js "$page" "return innerWidth")
check "zoom in, and the page is laid out zoomed" "$(bridge --do zoom-in | jq -r '.zoom') $(bridge --js "$page" "return innerWidth < $before")" "1.1 true"
check_json "actual size" "$(bridge --do zoom-reset)" '.zoom' "1"
bridge --do select "$page" >/dev/null

read=$(bridge --read "$page")
check_json "read: open, no answers of the user's own" "$read" '.status + " " + (.answers | length | tostring)' "open 0"
check_json "read: ground has a commit" "$read" '.ground.commit | length > 0' "true"

bridge --js "$page" "document.querySelector('[data-value=grid]').click()" >/dev/null
bridge --js "$page" "const r = document.querySelector('[data-record=radius]'); r.value = 12; r.dispatchEvent(new Event('change', {bubbles: true}))" >/dev/null
settle
read=$(bridge --read "$page")
check_json "clicking an option records it" "$read" '.answers.layout' "grid"
snap answered "Grid chosen, radius 12"

# --wait returns once the user sends; send from the page after a beat
( sleep 0.4; bridge --js "$page" "document.querySelector('[data-send]').click()" >/dev/null ) &
waited=$(bridge --wait "$page" --timeout 5)
check_json "wait returns sent, with the answers" "$waited" '.status + " " + .answers.layout' "sent grid"
state=$(bridge --state)
check_json "row no longer says waiting" "$state" '.sidebar[0].bridges[0].row' "Card layout for the archive · now"
snap sent "After Send"

# Another session does not hear the answer
other=$(BRIDGE_SESSION=someone-else bridge --read "$page")
check_json "another session is told who holds it" "$other" '.heldBy' "test-01-spine"
check_json "another session gets no answers" "$other" '.answers' "null"

# Presenting again from that session hands it over
(cd "$CASE_DIR/pages" && BRIDGE_SESSION=someone-else bridge decision.html)
settle
other=$(BRIDGE_SESSION=someone-else bridge --read "$page")
check_json "re-presenting hands the answer over" "$other" '.answers.layout' "grid"

# Sidecar survives the app quitting
bridge --quit; sleep 0.3
offline=$(BRIDGE_SESSION=someone-else bridge --read "$page")
check_json "read works with the app not running" "$offline" '.answers.radius' "12"

finish
