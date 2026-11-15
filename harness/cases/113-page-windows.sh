#!/bin/bash
source "$(dirname "$0")/../lib.sh"
for i in 1 2 3; do printf '<!doctype html><title>Page %s</title><p>Page %s</p>' $i $i > "$CASE_DIR/pages/p$i.html"; done
p="$CASE_DIR/pages"
(cd "$p" && bridge p1.html p2.html p3.html); wait_ready; settle 0.3

bridge --do select "$p/p1.html" >/dev/null; settle 0.2
bridge --do window >/dev/null; settle 0.4
s=$(bridge --state)
window() { jq -c "[.pageWindows[] | select(.location | endswith(\"/$1\"))][0]" <<< "$s"; }
check_json "a page window never becomes a tab" "$(window p1.html)" '.tabbing' "false"
check_json "the first one opens beside the list, over the page pane" "$s" '([.pageWindows[0].topLeft[0] - (.windowFrame.x + .pageX), .pageWindows[0].topLeft[1] - (.windowFrame.y + .windowFrame.height)] | map(fabs) | max) < 2' "true"
check_json "so the list stays clear of it" "$s" '.pageWindows[0].topLeft[0] >= .windowFrame.x + .columnWidths[0] + .columnWidths[1]' "true"

bridge --do select "$p/p2.html" >/dev/null; settle 0.2
bridge --do window >/dev/null; settle 0.4
s=$(bridge --state)
dx=$(jq -n --argjson a "$(window p1.html)" --argjson b "$(window p2.html)" '$b.topLeft[0] - $a.topLeft[0]')
dy=$(jq -n --argjson a "$(window p1.html)" --argjson b "$(window p2.html)" '$a.topLeft[1] - $b.topLeft[1]')
check "the next one cascades from it, right and down ($dx, $dy)" "$(awk "BEGIN {print ($dx > 10 && $dx < 60 && $dy > 10 && $dy < 60) ? \"cascaded\" : \"not\"}")" "cascaded"
bridge --do select "$p/p3.html" >/dev/null; settle 0.2
bridge --do window >/dev/null; settle 0.4
s=$(bridge --state)
dx=$(jq -n --argjson a "$(window p2.html)" --argjson b "$(window p3.html)" '$b.topLeft[0] - $a.topLeft[0]')
check "and the third from the second ($dx)" "$(awk "BEGIN {print ($dx > 10 && $dx < 60) ? \"cascaded\" : \"not\"}")" "cascaded"
shot cascade >/dev/null
finish
