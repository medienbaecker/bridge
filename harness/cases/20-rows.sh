#!/bin/bash
# Acting on rows where the user's hand is: a context menu on the row under the cursor,
# ⌘⌫ to remove, and commands that act on every selected row.
source "$(dirname "$0")/../lib.sh"
a=$(fixture decision.html); b=$(fixture plan.html); c=$(fixture umlaut.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html plan.html umlaut.html)
wait_ready
state=$(bridge --do rowmenu "$b")
check_json "a row has a context menu" "$state" '.rowMenu | join(" / ")' "Cross (⌘E) / Reveal in Finder (⇧⌘R) / Remove from List (⌘⌫)"
bridge --do select "$b" >/dev/null; bridge --do cross >/dev/null
check_json "a crossed row offers Uncross" "$(bridge --do rowmenu "$b")" '.rowMenu[0]' "Uncross (⇧⌘E)"
bridge --do uncross >/dev/null
state=$(bridge --do select "$a"); state=$(bridge --do select-add "$b")
check_json "two rows selected" "$state" '.selectedRows | length' "2"
check_json "the menu names the count" "$(bridge --do rowmenu "$b")" '.rowMenu[0]' "Cross 2 Bridges (⌘E)"
state=$(bridge --do cross)
check_json "⌘E crosses every selected row" "$state" '[.sidebar[].bridges[] | select(.crossed) | .title] | length' "2"
check_json "and leaves the third alone" "$state" '[.sidebar[].bridges[] | select(.crossed | not) | .title][0]' "Umlaute — Test"
snap crossed "Two rows crossed in one go"
bridge --do select "$c" >/dev/null
state=$(bridge --do remove)
check_json "remove acts on the selected row" "$state" '[.sidebar[].bridges[].location] | index("'"$c"'")' "null"

# The seam: a right-click NSEvent at a row's location, through the override
# AppKit calls, targets the row under the cursor, not the selection; and empty
# space below the rows yields no menu.
(cd "$CASE_DIR/pages" && bridge umlaut.html); wait_ready
bridge --do select "$a" >/dev/null
state=$(bridge --do rowmenu-at "$b")
check_json "a right-click event on an unselected row targets that row" "$state" '.rowMenuTargets[0]' "$b"
check_json "and offers its menu" "$state" '.rowMenu | length > 0' "true"
check_json "a right-click in empty space yields no menu" "$(bridge --do rowmenu-at empty)" '.rowMenu | length' "0"
finish
