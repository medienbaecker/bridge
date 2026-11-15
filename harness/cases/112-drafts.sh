#!/bin/bash
source "$(dirname "$0")/../lib.sh"
export BRIDGE_ENDED_AFTER=0
work="test-$CASE_NAME-work"
printf '<!doctype html><title>Lorem ipsum</title><p>Lorem ipsum</p>' > "$CASE_DIR/pages/page.html"
repo
(cd "$CASE_DIR/pages" && claude_session "$work" idle)
(cd "$CASE_DIR/pages" && BRIDGE_SESSION="$work" bridge page.html); wait_ready; settle 0.3

bridge --do new >/dev/null; wait_ready; settle 0.5
draft=$(bridge --state | jq -r .selected)
js() { bridge --js "$draft" "$1"; }
check_json "a new bridge takes the keyboard: the page is the first responder" "$(bridge --state)" '.pageFocused' "true"
check_json "and the cursor is in its text" "$(js "return document.activeElement.id")" '.' "text"
bridge --do select "$CASE_DIR/pages/page.html" >/dev/null; settle 0.3
js "document.activeElement.blur()" >/dev/null
bridge --do new >/dev/null; settle 0.5
check_json "an empty draft that is reused takes it again" "$(js "return document.activeElement.id")" '.' "text"

bridge --do window >/dev/null; settle 0.4
check_json "in a window of its own a blank draft cannot be sent either" "$(bridge --state)" '.pageWindows[0] | [.sendEnabled, .sendToolTip] | map(tostring) | join(",")' "false,Pick the agent it goes to"
long="Donaudampfschifffahrtsgesellschaftskapitänswitwenrentenantragsformular bitte prüfen"
js "const t = document.getElementById('text'); t.value = '$long'; t.dispatchEvent(new Event('input', { bubbles: true }))" >/dev/null
for i in $(seq 1 40); do [ "$(bridge --state | jq -r .title)" = "$long" ] && break; sleep 0.1; done
settle 0.3
check_json "with words it can" "$(bridge --state)" '.pageWindows[0].sendEnabled' "true"
bridge --do closewindow "$draft" >/dev/null; settle 0.3
check_json "the main window agrees" "$(bridge --state)" '[.toolbar[] | select(.id == "send")][0].enabled' "true"

bridge --do sendto "$work" >/dev/null; settle 0.5
s=$(bridge --state)
check_json "a sent draft takes the list to the agent's project" "$s" '.projects.scope' "project:$CASE_DIR/pages"
check_json "and stays selected there" "$s" '[.selected == "'"$draft"'", (.bridgesColumn | index("'"$draft"'") != null), .sidebarGeometry.selectionVisible] | map(tostring) | join(",")' "true,true,true"
shot sent >/dev/null
finish
