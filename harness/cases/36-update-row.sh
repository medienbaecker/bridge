#!/bin/bash
# The update row at the sidebar's narrowest: the whole text drawn, in the
# list's own column, read from the pixels of a real shot rather than from the
# text the state reports.
source "$(dirname "$0")/../lib.sh"
page=$(fixture decision.html)
repo
export BRIDGE_UPDATE_READY=1
(cd "$CASE_DIR/pages" && bridge decision.html); wait_ready; settle 0.4
bridge --do sidebarwidth 160 >/dev/null; settle 0.5
state=$(bridge --state)
check_json "the row is there, saying Update ready" "$state" '.updateRow.text' "Update ready"
check_json "the projects column is at its narrowest, where the row lives" "$state" '.updateRow.width' "160"
png="$CASE_DIR/shots/narrow.png"; r=$(shot narrow) || true
scale=$(printf '%s' "$state" | jq -r '.backingScale')
y=$(printf '%s' "$state" | jq -r '((.updateRow.top + .updateRow.height / 2) * .backingScale) | floor')
clip=$(printf '%s' "$state" | jq -r '(.updateRow.width * .backingScale) | floor')
# Ink on the row's middle scanline: the first run is the icon, the label follows;
# the last ink must end before the clip, and the label's ink must be as wide as
# the text wants, so nothing was cut.
ink=$(python3 "$ROOT/harness/measure.py" "$png" "$y" 1 2>&1 | python3 -c '
import sys, json
clip, scale, labelx, textw = int(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
runs = [l.split() for l in sys.stdin]; runs = [(int(a), int(b), int(c) + int(d) + int(e)) for a, b, c, d, e in runs]
side = next(r for r in runs if r[1] - r[0] > 8)[2]
ink = [r for r in runs if r[0] < clip and abs(r[2] - side) > 60]
first = ink[0][0] / scale; last = ink[-1][1] / scale
label_ink = [r for r in ink if r[0] >= labelx * scale]
print(json.dumps({"first": round(first, 1), "last": round(last, 1), "labelInk": round((label_ink[-1][1] - label_ink[0][0]) / scale, 1), "textWidth": round(textw, 1), "clip": clip / scale}))' "$clip" "$scale" "$(printf '%s' "$state" | jq -r '.updateRow.labelX')" "$(printf '%s' "$state" | jq -r '.updateRow.textWidth')" 2>&1)
echo "  ink: $ink"
check "the row starts in the list's column, where the dots are" "$(printf '%s' "$ink" | jq -r '.first >= 19 and .first <= 26')" "true"
check "the whole text is drawn: its ink is as wide as the text wants (within 3 pt)" "$(printf '%s' "$ink" | jq -r '(.labelInk - .textWidth) | fabs <= 3')" "true"
check "and it ends inside the sidebar with room to spare" "$(printf '%s' "$ink" | jq -r '.last <= .clip - 8')" "true"
snap narrow "The update row at the narrowest sidebar"
finish
