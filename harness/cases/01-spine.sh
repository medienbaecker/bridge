#!/bin/bash
source "$(dirname "$0")/../lib.sh"

page=$(fixture decision.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready || finish

state=$(bridge --state)
check_json "window shows the page" "$state" '.title' "Card layout for the archive"
check_json "status starts open" "$state" '.status' "open"
check_json "send is enabled" "$state" '[.toolbar[] | select(.id=="send") | .enabled][0]' "true"
check_json "notes is disabled with no notes" "$state" '[.toolbar[] | select(.id=="notes") | .enabled][0]' "false"
check_json "sidebar has the project" "$state" '.sidebar[0].project' "pages"
check_json "row is title, time, waiting, unread" "$state" '.sidebar[0].bridges[0].row' "Card layout for the archive · now · waiting · unread"
snap open "Freshly presented"
state=$(bridge --do select "$page")
check_json "selecting it in the sidebar marks it read" "$state" '.sidebar[0].bridges[0].row' "Card layout for the archive · now · waiting"

read=$(bridge --read "$page")
# What the page proposed (a control's default) is named under defaults and is not the user's answer.
check_json "read: open, no answers of the user's own" "$read" '.status + " " + ((.answers | length) - (.defaults | length) | tostring)' "open 0"
check_json "the range's value is there from the start, named as the page's default" "$read" '"\(.answers.radius) \(.defaults | join(","))"' "8 radius"
check_json "read: ground has a commit" "$read" '.ground.commit | length > 0' "true"
check_json "read: head has not moved" "$read" '.ground.headMoved' "0"

bridge --js "$page" "document.querySelector('[data-value=grid]').click()" >/dev/null
bridge --js "$page" "const r = document.querySelector('[data-record=radius]'); r.value = 12; r.dispatchEvent(new Event('change', {bubbles: true}))" >/dev/null
settle
read=$(bridge --read "$page")
check_json "clicking an option records it" "$read" '.answers.layout' "grid"
check_json "a range records a number, and driven it is the user's, no longer a default" "$read" '"\(.answers.radius) \(.defaults | length)"' "12 0"
check_json "the option shows as selected" "$(bridge --js "$page" "return document.querySelector('[data-value=grid]').hasAttribute('data-selected')")" '.' "true"
snap answered "Grid chosen, radius 12"

# --wait returns once the user sends; send from the page after a beat
( sleep 0.4; bridge --js "$page" "document.querySelector('[data-send]').click()" >/dev/null ) &
waited=$(bridge --wait "$page" --timeout 5)
check_json "wait returns sent" "$waited" '.status' "sent"
check_json "wait carries the answers" "$waited" '.answers.layout' "grid"
state=$(bridge --state)
check_json "send stays a verb after sending: enabled, its icon says Sent" "$state" '[.toolbar[] | select(.id=="send") | ((.enabled|tostring) + " " + .symbol)][0]' "true Sent"
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
check_json "state reports not running" "$(bridge --state)" '.running' "false"

finish
