#!/bin/bash
# The contact sheet: a scripted review pass, photographed at every step.
# Output: harness/out/sheet/index.html plus one PNG per step.
CASE_NAME=sheet
source "$(dirname "$0")/lib.sh"
SHEET="$OUT/sheet/pages-out"; SHEET_N=1
mkdir -p "$SHEET"
cat > "$SHEET/index.html" <<'HTML'
<!doctype html><meta charset="utf-8"><title>Bridge contact sheet</title>
<style>body{font:13px -apple-system,system-ui;margin:24px;background:#ececec}figure{margin:0 0 32px}img{width:100%;max-width:1080px;box-shadow:0 2px 12px rgba(0,0,0,.25);border-radius:10px}figcaption{margin:8px 0 0;color:#333}</style>
<h1>Bridge contact sheet</h1>
HTML

page=$(fixture decision.html)
plan=$(fixture plan.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
snap presented "A decision arrives: unread, waiting, selected"
bridge --js "$page" "document.querySelector('[data-value=list]').click()" >/dev/null
settle
snap chosen "The user clicks List"
bridge --do send >/dev/null
settle
snap sent "Send: the row stops waiting, Send greys out"
(cd "$CASE_DIR/pages" && bridge plan.html)
wait_ready
snap second "A second bridge arrives on top; the first stays"
bridge --do cross >/dev/null
settle
snap crossed "⌘E crosses the plan: struck through, folded under Crossed"
bridge --do select "$page" >/dev/null
settle
snap back "Back on the decision"
bridge --do sidebar >/dev/null
settle
snap nosidebar "Sidebar collapsed"
bridge --do sidebar >/dev/null

# Notes
bridge --do point >/dev/null
snap point "Point mode"
bridge --js "$page" "const el = document.querySelector('[data-value=list] strong'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: r.left + 10, clientY: r.top + 5}))" >/dev/null
settle
bridge --js "$page" "document.querySelector('.bridge-thread textarea').value = 'Too heavy at phone width, and the title wraps.'" >/dev/null
snap composer "The user clicks the List title and types"
bridge --js "$page" "document.querySelector('.bridge-thread textarea').dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true}))" >/dev/null
settle 0.3
id=$(bridge --pins "$page" | jq -r '.[0].id')
bridge --working "$page" "$id"; bridge --reply "$page" "$id" "Dropped the side padding at phone width; the title is on one line now."
settle 0.3
bridge --js "$page" "document.querySelector('.bridge-pin').click()" >/dev/null
settle
snap thread "The agent answered on the thread"
bridge --js "$page" "document.querySelector('.bridge-thread:popover-open').hidePopover()" >/dev/null
bridge --do notes >/dev/null
settle
snap notes "The Notes popover, native, one line per note"
bridge --do notes >/dev/null

# A new version
python3 - "$page" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('<h2>Corner radius</h2>', '<h2>Density</h2>\n<div class="options"><div data-record="density" data-value="cosy"><strong>Cosy</strong>More air around each card.</div><div data-record="density" data-value="compact"><strong>Compact</strong>Fits 24 on a screen.</div></div>\n<h2>Corner radius</h2>')
open(p,'w').write(s)
PY
settle 0.5
snap version2 "The agent added a question: version 2, the Send taken back, last-time hint"
bridge --do previous >/dev/null
wait_ready
snap version1 "⌘[ looks back at version 1, read-only"
bridge --do next >/dev/null
wait_ready

# Markdown and Mantine
md=$(fixture plan.md)
(cd "$CASE_DIR/pages" && bridge plan.md)
wait_ready
snap markdown "A plan as markdown"
export BRIDGE_TOOLKIT="$ROOT/toolkit"
jsx=$(fixture pick.jsx); fixture pick.data.json >/dev/null
(cd "$CASE_DIR/pages" && bridge pick.jsx)
wait_ready
bridge --js "$jsx" "document.querySelector('[data-value=grid]').click()" >/dev/null
settle
snap mantine "A Mantine page, Grid picked"
ctl=$(fixture controls.jsx); fixture controls.data.json >/dev/null
(cd "$CASE_DIR/pages" && bridge controls.jsx)
wait_ready
snap controls "Every control the cheat sheet lists"

# The plain gallery: controls with dials and colour, then evidence
g=$(fixture gallery.html)
(cd "$CASE_DIR/pages" && bridge gallery.html)
wait_ready
bridge --js "$g" "document.querySelector('h2:nth-of-type(2)').scrollIntoView(); return 1" >/dev/null; settle 0.3
snap gallery-controls "Plain controls, dials and the OKLCH colour"
bridge --js "$g" "document.querySelector('h2:nth-of-type(3)').scrollIntoView(); return 1" >/dev/null; settle 0.3
snap gallery-evidence "Evidence: code, a diff, bars"

# The other mediums
t="$CASE_DIR/pages/reply.txt"; printf 'Hallo Alex,\n\nLorem ipsum für März sit da — "alle" drei.\nViele Grüße\n' > "$t"
cp "/System/Library/Desktop Pictures/Solid Colors/Silver.png" "$CASE_DIR/pages/shot.png"
(cd "$CASE_DIR/pages" && bridge reply.txt shot.png)
wait_ready
snap text "A text draft: word count and a Copy button"
bridge --do select "$CASE_DIR/pages/shot.png" >/dev/null; wait_ready
snap image "An image, ready for a pin"
echo "sheet: $SHEET/index.html"
finish
