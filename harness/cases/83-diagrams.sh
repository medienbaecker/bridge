#!/bin/bash
source "$(dirname "$0")/../lib.sh"

cat > "$CASE_DIR/pages/plan.md" <<'MD'
# Sending a page

```flow
LR
(Agent writes page) -> Bridge -> {Shared?}
{Shared?} -> *Link: yes
{Shared?} --> Stays here: no
*Link -> *Ben's Bridge
Bridge -> [(shares.json)]
```

Then the two Macs talk:

```sequence
Ana -> *Link: page + record
*Link -> Ben: page + record
Ben --> *Link: her picks
*Link --> Ana: her picks
note Ana, Ben: both show the same answers
Ana -> Ana: redraw
```
MD
page="$CASE_DIR/pages/plan.md"
err=$( (cd "$CASE_DIR/pages" && bridge plan.md) 2>&1 >/dev/null)
wait_ready
js() { bridge --js "$page" "$1"; }
check "a correct draft reports nothing" "$err" ""
check "both blocks are drawn" "$(js "@bridge return document.querySelectorAll('.bridge-diagram svg').length")" "2"
check "and their source is hidden" "$(js "@bridge return [...document.querySelectorAll('pre')].filter((p) => p.checkVisibility()).length")" "0"
check "the flow has every node once" "$(js "@bridge return [...document.querySelectorAll('.bridge-diagram:first-of-type [data-node]')].map((n) => n.dataset.node).sort().join('|')" | jq -r .)" "Agent writes page|Ben's Bridge|Bridge|Link|Shared?|Stays here|shares.json"
check "and every edge" "$(js "@bridge return document.querySelector('.bridge-diagram').querySelectorAll('path.edge').length")" "6"
check "the decision is a diamond" "$(js "@bridge return document.querySelector('[data-node=\"Shared?\"] > :first-child').localName" | jq -r .)" "polygon"
check "a starred node stands out" "$(js "@bridge return document.querySelector('[data-node=\"Link\"]').classList.contains('hot')")" "true"
check "the sequence has its three people" "$(js "@bridge return [...document.querySelectorAll('.bridge-diagram')][1].querySelectorAll('[data-node]').length")" "3"
check "and its messages and note" "$(js "@bridge const f = [...document.querySelectorAll('.bridge-diagram')][1]; return f.querySelectorAll('.message').length + ' ' + f.querySelectorAll('.note').length" | jq -r .)" "5 1"
check "the drawing fits the page" "$(js "@bridge return [...document.querySelectorAll('.bridge-diagram svg')].every((s) => s.getBoundingClientRect().right <= document.body.getBoundingClientRect().right + 1)")" "true"
snap diagrams "A flow chart and a sequence diagram from a plan"

python3 - "$page" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('Bridge -> [(shares.json)]', 'Bridge -> [(shares.json)]\nBridge -> Notification')
open(p,'w').write(s)
PY
for i in $(seq 1 30); do [ "$(js "@bridge return document.querySelectorAll('[data-node=Notification]').length")" = "1" ] && break; sleep 0.1; done
check "an edit redraws the diagram in place" "$(js "@bridge return document.querySelectorAll('[data-node=Notification]').length + ' ' + document.querySelectorAll('.bridge-diagram').length" | jq -r .)" "1 2"
check "without reloading" "$(bridge --state | jq -r '.banner')" "null"

bridge --do point >/dev/null; settle 0.3
js "@bridge const r = document.querySelector('[data-node=Link] rect').getBoundingClientRect(); document.querySelector('[data-node=Link] rect').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, clientX: r.left + 4, clientY: r.top + 4 })); return 1" >/dev/null
settle 0.3
check "pointing at a node pins the node" "$(js "@bridge return __bridgeNotes.pending?.target" | jq -r .)" 'g.node.hot "Link"'

printf '# Broken\n\n```flow\nA -> B\nA => C\n```\n' > "$CASE_DIR/pages/broken.md"
err=$( (cd "$CASE_DIR/pages" && bridge broken.md) 2>&1 >/dev/null)
check "a line that is not a step is reported to the agent" "${err#*: }" 'broken.md threw: flow diagram, line 2: "A => C" is not a step; write A -> B, A --> B (dashed) or A -> B: label'
finish
