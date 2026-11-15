#!/bin/bash
source "$(dirname "$0")/../lib.sh"
export BRIDGE_ENDED_AFTER=1

for i in 1 2 3 4 5 6 7; do
  printf '<!doctype html><title>Page %s</title><h1>Page %s</h1><fieldset class="options"><div><input type="radio" name="w" id="a" value="x" data-record="k" checked><label for="a">x</label></div></fieldset>' "$i" "$i" > "$CASE_DIR/pages/p$i.html"
done
repo
claude_session alive-agent
for i in 1 2 3 4 5 6; do (cd "$CASE_DIR/pages" && BRIDGE_SESSION=ended-agent bridge "p$i.html") >/dev/null 2>&1; done
wait_ready
bridge --do project all >/dev/null; bridge --do crossed show >/dev/null

counts() { bridge --state | jq -r '"\(.listSaves) \(.refreshes)"'; }
since() { local now; now=$(counts); echo "$(( ${now% *} - ${1% *} )) save, $(( ${now#* } - ${1#* } )) redraw"; }
crossed() { bridge --state | jq '[.sidebar[].bridges[] | select(.crossed)] | length'; }

sleep 1.5
before=$(counts)
bridge --do cleanup >/dev/null
check "six ended bridges cross themselves off" "$(crossed)" "6"
check "in one save and one redraw" "$(since "$before")" "1 save, 1 redraw"

bridge --do select "$CASE_DIR/pages/p1.html" >/dev/null
for i in 2 3 4 5 6; do bridge --do select-add "$CASE_DIR/pages/p$i.html" >/dev/null; done
before=$(counts)
bridge --do uncross >/dev/null
check "six selected rows uncross" "$(crossed)" "0"
check "in one save and one redraw" "$(since "$before")" "1 save, 1 redraw"
before=$(counts)
bridge --do cross >/dev/null
check "and cross" "$(crossed)" "6"
check "in one save and one redraw" "$(since "$before")" "1 save, 1 redraw"
before=$(counts)
bridge --do remove >/dev/null
check "and leave the list" "$(bridge --state | jq '[.sidebar[].bridges[]] | length')" "0"
check "in one save and one redraw" "$(since "$before")" "1 save, 1 redraw"

before=$(counts)
(cd "$CASE_DIR/pages" && BRIDGE_SESSION=alive-agent bridge p7.html) >/dev/null 2>&1; wait_ready; settle 0.6
check_json "a new page arrives with its title" "$(bridge --state)" '.title' "Page 7"
check "in a save and a redraw for the present and one each for the title" "$(since "$before")" "2 save, 2 redraw"
before=$(counts)
(cd "$CASE_DIR/pages" && BRIDGE_SESSION=alive-agent bridge p7.html) >/dev/null 2>&1; settle 0.6
check "presenting it again takes one" "$(since "$before")" "1 save, 1 redraw"
finish
