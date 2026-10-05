#!/bin/bash
source "$(dirname "$0")/../lib.sh"
export BRIDGE_TOOLKIT="$ROOT/toolkit"

page=$(fixture pick.jsx)
data=$(fixture pick.data.json)
repo
(cd "$CASE_DIR/pages" && bridge pick.jsx)
wait_ready
js() { bridge --js "$page" "$1"; }

state=$(bridge --state)
check_json "built page shows the data title" "$state" '.title' "Card layout for the archive"
check_json "build took under 400 ms" "$state" '.buildMs < 400' "true"
check_json "mantine rendered" "$(js "return document.querySelectorAll('.mantine-Card-root').length")" '.' "2"
snap built "A Mantine page"

js "document.querySelector('[data-value=grid]').click(); window.__marker = 'alive'; return 1" >/dev/null
js "document.documentElement.dataset.bridgeRecord = JSON.stringify({key: 'radius', value: 12}); document.dispatchEvent(new Event('bridge:record')); return 1" >/dev/null
js "const t = document.querySelector('textarea[data-record], [data-record] textarea'); t.value = 'fine'; t.dispatchEvent(new Event('change', {bubbles: true})); return 1" >/dev/null
settle
read=$(bridge --read "$page")
check_json "a Card with data-record records on click" "$read" '.answers.layout' "grid"
check_json "useRecord reaches the sidecar" "$read" '.answers.radius' "12"
check_json "a Textarea records through data-record" "$read" '.answers.note' "fine"
check_json "selected card is marked" "$(js "return document.querySelector('[data-value=grid]').hasAttribute('data-selected')")" '.' "true"
snap answered "Grid picked on the Mantine page"

# Data changes push into the running page
sed -i '' 's/Two layouts survive the content; pick one./Two layouts survive the content. Pick one./' "$data"
settle 0.5
check_json "data change re-rendered without reload" "$(js "return window.__marker")" '.' "alive"
check_json "new prose is on screen" "$(js "return document.querySelector('.mantine-Text-root').textContent")" '.' "Two layouts survive the content. Pick one."
check_json "same questions, same version" "$(bridge --read "$page")" '.version' "1"
check_json "answers stand" "$(bridge --read "$page")" '.answers.layout' "grid"

python3 - "$data" <<'PY'
import json, sys; p=sys.argv[1]; d=json.load(open(p)); d['options'].append({"value": "masonry", "label": "Masonry", "evidence": "Pinterest-style."}); json.dump(d, open(p, 'w'))
PY
settle 0.5
check_json "a new option is a new version" "$(bridge --read "$page")" '.version' "2"
check_json "still no reload" "$(js "return window.__marker")" '.' "alive"

# Code changes rebuild and reload, honestly
sed -i '' 's/Corner radius/Radius/' "$page"
settle 0.8
wait_ready
check_json "code change reloaded" "$(js "return window.__marker || 'gone'")" '.' "gone"
check_json "new code is on screen" "$(js "return [...document.querySelectorAll('h2')].map(h => h.textContent).join(',')")" '.' "Layout,Radius"

# A broken build is reported as a build failure, in the window
sed -i '' 's/<Group>/<Group/' "$page"
settle 0.8
wait_ready
check_json "build failure is shown as such" "$(js "return document.querySelector('h1').textContent")" '.' "Build failed"
check_json "with the compiler's message" "$(js "return document.querySelector('.evidence strong').textContent")" '.' 'Expected ">" but found "<"'
check_json "and the banner says so" "$(bridge --state)" '.banner | startswith("Build failed")' "true"
check_json "the version did not change" "$(bridge --read "$page")" '.version' "2"
snap broken "A build failure, reported as one"
sed -i '' 's/<Group$/<Group>/' "$page"
settle 0.8
wait_ready
check_json "fixing the file recovers" "$(js "return document.querySelectorAll('.mantine-Card-root').length")" '.' "3"
check_json "answers survived the round trip" "$(bridge --read "$page")" '.version' "2"
finish
