#!/bin/bash
source "$(dirname "$0")/../lib.sh"

cat > "$CASE_DIR/pages/plan.md" <<'MD'
# Sending a page

```mermaid
flowchart LR
  A([Agent writes page]) --> B[Bridge] --> C{Shared?}
  C -->|yes| L[Link]:::hot
  C -.->|no| S[Stays here]
  L --> R[Ben's Bridge]:::hot
  B --> D[(shares.json)]
```

Then the two Macs talk:

```mermaid
sequenceDiagram
  Ana->>Link: page + record
  Link->>Ben: page + record
  Ben-->>Link: her picks
  Link-->>Ana: her picks
  Note over Ana,Ben: both show the same answers
```
MD
page="$CASE_DIR/pages/plan.md"
err=$( (cd "$CASE_DIR/pages" && bridge plan.md) 2>&1 >/dev/null)
wait_ready
js() { bridge --js "$page" "$1"; }
check "a correct draft reports nothing" "$err" ""
check "both blocks are drawn" "$(js "@bridge return document.querySelectorAll('.bridge-diagram svg.pele').length")" "2"
check "and their source is hidden" "$(js "@bridge return [...document.querySelectorAll('pre')].filter((p) => p.checkVisibility()).length")" "0"
check "the flow has every node" "$(js "@bridge return [...document.querySelector('.bridge-diagram').querySelectorAll('.pele-node')].map((n) => n.dataset.id).sort().join(' ')" | jq -r .)" "A B C D L R S"
check "and every edge" "$(js "@bridge return document.querySelector('.bridge-diagram').querySelectorAll('.pele-edge').length")" "6"
check "a hot node stands out" "$(js "@bridge return getComputedStyle(document.querySelector('.pele-node.hot rect')).strokeWidth" | jq -r .)" "1.5px"
check "the sequence has its three people" "$(js "@bridge return new Set([...[...document.querySelectorAll('.bridge-diagram')][1].querySelectorAll('.pele-actor')].map((n) => n.dataset.id)).size")" "3"
check "and its messages and note" "$(js "@bridge const f = [...document.querySelectorAll('.bridge-diagram')][1]; return f.querySelectorAll('.pele-message').length + ' ' + f.querySelectorAll('.pele-note').length" | jq -r .)" "4 1"
check "the drawing fits the page" "$(js "@bridge return [...document.querySelectorAll('.bridge-diagram svg')].every((s) => s.getBoundingClientRect().right <= document.body.getBoundingClientRect().right + 1)")" "true"
snap diagrams "A flowchart and a sequence diagram from a plan"

python3 - "$page" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('B --> D[(shares.json)]', 'B --> D[(shares.json)]\n  B --> N[Notification]')
open(p,'w').write(s)
PY
for i in $(seq 1 30); do [ "$(js "@bridge return document.querySelectorAll('.pele-node[data-id=N]').length")" = "1" ] && break; sleep 0.1; done
check "an edit redraws the diagram in place" "$(js "@bridge return document.querySelectorAll('.pele-node[data-id=N]').length + ' ' + document.querySelectorAll('.bridge-diagram').length" | jq -r .)" "1 2"
check "without reloading" "$(bridge --state | jq -r '.banner')" "null"

bridge --do point >/dev/null; settle 0.3
js "@bridge const r = document.querySelector('.pele-node[data-id=L] rect').getBoundingClientRect(); document.querySelector('.pele-node[data-id=L] rect').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, clientX: r.left + 4, clientY: r.top + 4 })); return 1" >/dev/null
settle 0.3
check "pointing at a node pins the node" "$(js "@bridge return __bridgeNotes.pending?.target" | jq -r .)" 'g.pele-node.pele-shape-rect.hot "Link"'

printf '# Broken\n\n```mermaid\nflowchart LR\n  A --> B\n  A => C\n```\n' > "$CASE_DIR/pages/broken.md"
err=$( (cd "$CASE_DIR/pages" && bridge broken.md) 2>&1 >/dev/null)
check "a line Pele cannot read is reported to the agent" "$(echo "${err#*: }" | head -1)" 'broken.md threw: diagram: Lexical error on line 3. Unrecognized text.'
finish
