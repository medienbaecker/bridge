#!/bin/bash
source "$(dirname "$0")/../lib.sh"
folder="$XDG_STATE_HOME/bridge/pages/demo"
mkdir -p "$folder"
printf '<!doctype html><title>Ours</title><p>Lorem ipsum</p>' > "$folder/ours.html"
printf '<!doctype html><title>Theirs</title><p>Lorem ipsum</p>' > "$CASE_DIR/pages/theirs.html"
ours="$folder/ours.html"; theirs="$CASE_DIR/pages/theirs.html"
list="$XDG_STATE_HOME/bridge-dev/list.json"
listed() { jq -r --arg l "$1" '[.bridges[] | select(.location == $l)] | length' "$list"; }
crossed() { jq -r --arg l "$1" '[.bridges[] | select(.location == $l) | .crossed] | first' "$list"; }
(cd "$folder" && bridge ours.html); wait_ready; settle 0.3
(cd "$CASE_DIR/pages" && bridge theirs.html); wait_ready; settle 0.3
bridge --do project all >/dev/null; settle 0.2

bridge --do select "$theirs" >/dev/null; settle 0.2
check_json "with nothing done there is nothing to undo" "$(bridge --state)" '.undo' ""
bridge --do cross >/dev/null; settle 0.3
check "Cross can be undone, and says so in the Edit menu" "$(crossed "$theirs") $(bridge --state | jq -r .undo)" "true Undo Cross"
bridge --do undo >/dev/null; settle 0.3
check "undone, it is uncrossed and can be redone" "$(crossed "$theirs") $(bridge --state | jq -r .redo)" "false Redo Cross"
bridge --do redo >/dev/null; settle 0.3
check "redone, it is crossed again" "$(crossed "$theirs")" "true"
bridge --do uncross >/dev/null; settle 0.3
check "Uncross can be undone" "$(crossed "$theirs") $(bridge --state | jq -r .undo)" "false Undo Uncross"
bridge --do undo >/dev/null; settle 0.3
check "undone, it is crossed" "$(crossed "$theirs")" "true"
bridge --do undo >/dev/null; settle 0.3
check "and one more undo takes back the first cross" "$(crossed "$theirs")" "false"

bridge --do select "$theirs" >/dev/null; settle 0.2
bridge --do remove >/dev/null; settle 0.3
check "a page elsewhere leaves the list, undoably" "$(listed "$theirs") $(bridge --state | jq -r .undo)" "0 Undo Remove from List"
bridge --do undo >/dev/null; settle 0.3
check_json "undone, it is listed and selected again" "$(bridge --state)" '[.selected == "'"$theirs"'", (.bridgesColumn | index("'"$theirs"'") != null)] | map(tostring) | join(",")' "true,true"

bridge --do select "$ours" >/dev/null; wait_ready; settle 0.3
bridge --js "$ours" "return 1" >/dev/null
answers=$(sidecar "$ours")
bridge --do remove >/dev/null; settle 0.3
check "a page Bridge owns goes to the Trash with its record" "$([ -e "$ours" ] && echo file; [ -e "$answers" ] && echo answers; listed "$ours") $(bridge --state | jq -r .undo)" "0 Undo Move to Trash"
bridge --do undo >/dev/null; wait_ready; settle 0.4
check "undone, the file and its record are moved back and it is listed" "$([ -e "$ours" ] && echo file) $([ -e "$answers" ] && echo answers) $(listed "$ours")" "file answers 1"
check_json "and it shows again" "$(bridge --js "$ours" "return document.body.innerText.trim()")" '.' "Lorem ipsum"
bridge --do redo >/dev/null; settle 0.3
check "redone, it is in the Trash again" "$([ -e "$ours" ] && echo file; listed "$ours")" "0"
finish
