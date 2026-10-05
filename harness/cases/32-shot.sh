#!/bin/bash
# A photograph of the window as the window server has it, with and without the
# notes popover; with BRIDGE_FRONT=1 also the active state, window key.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/shot.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Shot</title><style>body{margin:0;padding:8px 24px;font:17px/1.5 system-ui} mark{background:#cfe3ff}</style></head><body>
<p id="a">Text right under where the notes list opens, with a <mark>blue highlight</mark>, long enough to run under the popover's area at the top right of the window.</p>
</body></html>
HTML
python3 - "$page.bridge.json" <<'PY'
import json, sys, datetime
now = datetime.datetime.now(datetime.UTC).strftime('%Y-%m-%dT%H:%M:%SZ')
c = lambda i, t: {"id": f"n{i}", "text": t, "target": 'p "Text"', "state": "open", "at": now, "version": 1, "anchor": {"selector": "#a", "x": 0.5, "y": 0.5}, "said": []}
json.dump({"status": "open", "version": 1, "questions": [], "answers": {}, "comments": [c(1, "Too heavy"), c(2, "This paragraph is far too long for a panel")], "history": []}, open(sys.argv[1], "w"))
PY
repo
(cd "$CASE_DIR/pages" && bridge shot.html); wait_ready; settle 0.5
state=$(bridge --state)
check_json "state carries the window number and both frames" "$state" '(.windowNumber > 0) and (.windowFrame.width > 0) and (.screenFrame.height > 0) and (.backingScale >= 1)' "true"
w=$(printf '%s' "$state" | jq -r '(.windowFrame.width * .backingScale) | round')
r=$(shot window); check_json "a shot is written at the window's size" "$r" "(.width == $w) and (.height > 100)" "true"
check_json "and it is a real picture, not a blank" "$r" '.colours > 8' "true"
bridge --do notes >/dev/null; settle 1.5
r=$(shot popover)
check_json "with the popover open, the popover window is in frame, whole" "$r" '(.windows | length >= 2) and (.missing | length == 0) and (.clipped | not)' "true"
check_json "and still a real picture" "$r" '.colours > 8' "true"
bridge --do notes >/dev/null; settle 0.3
if [ "${BRIDGE_FRONT:-0}" = 1 ]; then
  front
  check_json "fronted: the window is key" "$(bridge --state)" '.windowKey' "true"
  check_json "and the selected row is emphasized" "$(bridge --state)" '.sidebarGeometry.emphasized' "true"
  shot active >/dev/null
else
  echo "  skip active-state shot (set BRIDGE_FRONT=1; it takes focus)"
fi
finish
