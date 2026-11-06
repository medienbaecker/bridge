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
check_json "mantine rendered" "$(js "return document.querySelectorAll('.mantine-Card-root').length")" '.' "2"
snap built "A Mantine page"

js "document.querySelector('[data-value=grid]').click(); window.__marker = 'alive'; return 1" >/dev/null
settle
read=$(bridge --read "$page")
check_json "a Card with data-record records on click" "$read" '.answers.layout' "grid"
snap answered "Grid picked on the Mantine page"

# Data changes push into the running page
sed -i '' 's/Two layouts survive the content; pick one./Two layouts survive the content. Pick one./' "$data"
settle 0.5
check_json "data change re-rendered without reload" "$(js "return window.__marker")" '.' "alive"
check_json "new prose is on screen" "$(js "return document.querySelector('.mantine-Text-root').textContent")" '.' "Two layouts survive the content. Pick one."
check_json "same questions, same version" "$(bridge --read "$page")" '.version' "1"

python3 - "$data" <<'PY'
import json, sys; p=sys.argv[1]; d=json.load(open(p)); d['options'].append({"value": "masonry", "label": "Masonry", "evidence": "Pinterest-style."}); json.dump(d, open(p, 'w'))
PY
settle 0.5
check_json "a new option is a new version" "$(bridge --read "$page")" '.version' "2"

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
check_json "and the banner says so" "$(bridge --state)" '.banner | startswith("Build failed")' "true"
snap broken "A build failure, reported as one"
sed -i '' 's/<Group$/<Group>/' "$page"
settle 0.8
wait_ready
check_json "fixing the file recovers" "$(js "return document.querySelectorAll('.mantine-Card-root').length")" '.' "3"
finish
