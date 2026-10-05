#!/bin/bash
# The notes popover on the hard case: five long notes, replies on
# every row. As tall as its rows, opaque and toned so it has an edge over white,
# every row cut at a word and fitting its label, the reply count a glyph and a
# numeral so the note keeps the width, six points above the first row and
# below the last, measured from the pixels of a real shot.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/list.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Notes list</title><style>body{margin:0;padding:8px 24px;font:17px/1.5 system-ui}</style></head><body>
<p id="a">Text right under where the notes list opens, long enough to run under the popover's area at the top right of the window.</p>
</body></html>
HTML
python3 - "$page.bridge.json" <<'PY'
import json, sys, datetime
now = datetime.datetime.now(datetime.UTC).strftime('%Y-%m-%dT%H:%M:%SZ')
notes = ["Note 1 lorem ipsum dolor sit amet consectetur adipiscing elit sed do consectetur",
         "Note 2 eiusmod tempor incididunt ut labore et dolore magna aliqua ut enim ad consectetur",
         "Note 3 minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex exercitation",
         "Note 4 ea commodo consequat duis aute irure dolor in reprehenderit in voluptate aliquip",
         "Note 5 velit esse cillum dolore eu fugiat nulla pariatur lorem exercitation"]
reps = [3, 5, 3, 2, 3]
c = lambda i, t, n: {"id": f"n{i}", "text": t, "target": 'p "Text"', "state": "open", "at": now, "version": 1, "anchor": {"selector": "#a", "x": 0.5, "y": 0.5}, "said": [{"by": "agent", "at": now, "text": f"reply {k}", "kind": "reply"} for k in range(n)]}
json.dump({"status": "open", "version": 1, "questions": [], "answers": {}, "comments": [c(i, t, n) for i, (t, n) in enumerate(zip(notes, reps))], "history": []}, open(sys.argv[1], "w"))
PY
repo
(cd "$CASE_DIR/pages" && bridge list.html); wait_ready
bridge --do notes >/dev/null; settle 1.2
state=$(bridge --state)
check_json "the popover is open" "$state" '.notesPopoverShown' "true"
check_json "five rows tall, not a fixed panel" "$state" '.notesPopoverSize.height' "132"
check_json "every row fits its label: nothing is cut by the label itself" "$state" '.notesRowsFit | all' "true"
check "every row is cut at a word, with an ellipsis" "$(printf '%s' "$state" | jq -r --slurpfile side "$(sidecar "$page")" '
  [.notesRows, ($side[0].comments | map(.text))] | transpose | map(. as [$r, $n] | ($r | endswith("…")) and ($n | startswith($r[:-1])) and ($n[($r | length) - 1 : ($r | length)] == " ")) | all')" "true"
# The real frame is named apart from the composite `snap list` below: with the
# same name the composite, cropped to the window, would overwrite the shot.
png="$CASE_DIR/shots/list-shot.png"; shotr=$(bridge --shot "$png"); W=$(printf '%s' "$shotr" | jq -r '.width')
echo "  shot: $(printf '%s' "$shotr" | jq -c '{width, windows, missing, clipped, frames}')"
check_json "the shot holds both windows whole: none missing, none cut by the display" "$shotr" '(.windows | length == 2) and (.missing | length == 0) and (.clipped | not)' "true"
# The shot is the union of the window and the popover, which overhangs it: the
# dots are 703 px in from the shot's right edge, not the window's.
# The column through the accent dots: the panel's toned fill marks its top and
# bottom, the dots mark the rows; the gap above the first equals the gap below the last.
# Nothing is fixed here: a display change mid-run can shrink the window and move the popover.
# The dots sit 34 pt into the popover's window (13 of margin around the panel,
# 10 of leading, 11 to the dot's middle): its x from the shot's own frames,
# against the union's left edge.
dotx=$(printf '%s' "$shotr" | jq -r '.frames | map(capture("\\((?<x>[0-9.]+), (?<y>[0-9.]+), (?<w>[0-9.]+), (?<h>[0-9.]+)\\)") | {x: (.x|tonumber), w: (.w|tonumber)}) | (min_by(.x).x) as $left | (min_by(.w).x - $left + 34) * 2 | floor')
echo "  dot column x=$dotx" >&2
gaps=$(python3 "$ROOT/harness/measure.py" "$png" column "$dotx" 90 480 1 | python3 -c '
import sys
runs = [l.split() for l in sys.stdin]
panel = [r for r in runs if r[2:] == ["246", "246", "246"]]
dots = [r for r in runs if int(r[4]) > 200 and int(r[2]) < 50]  # the core run of each dot, not its anti-aliased edges
top, bottom = int(panel[0][0]), int(panel[-1][1])
first = (int(dots[0][0]) + int(dots[0][1])) / 2; last = (int(dots[-1][0]) + int(dots[-1][1])) / 2
print(len(dots), round(first - top), round(bottom - last))')
check "five dots in the panel, the gap above the first equal to the gap below the last ($gaps)" "$(printf '%s' "$gaps" | awk '{print ($1 == 5 && ($2 - $3) <= 2 && ($3 - $2) <= 2) ? "yes" : "no"}')" "yes"
snap list "The notes popover on long notes"
bridge --do notes >/dev/null; settle 0.3
python3 - "$(sidecar "$page")" <<'PY'
import json, sys, datetime
now = datetime.datetime.now(datetime.UTC).strftime('%Y-%m-%dT%H:%M:%SZ')
d = json.load(open(sys.argv[1]))
d["comments"] += [{"id": f"m{i}", "text": f"Note number {i}", "target": 'p "Text"', "state": "open", "at": now, "version": 1, "anchor": {"selector": "#a", "x": 0.5, "y": 0.5}, "said": []} for i in range(30)]
json.dump(d, open(sys.argv[1], "w"))
PY
settle 0.8
bridge --do notes >/dev/null; settle 0.4
state=$(bridge --state)
check_json "thirty-five notes: capped, so it scrolls" "$state" '.notesPopoverSize.height' "420"
finish
