#!/bin/bash
# A recording control drives the preview: a CSS custom property on the page's
# own elements, and the same property inside an embedded live site.
source "$(dirname "$0")/../lib.sh"

site="$CASE_DIR/site"; mkdir -p "$site"
cat > "$site/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Live</title>
<style>.hero{padding:var(--pad, 10px);border-radius:var(--radius, 0px);background:#eee}</style></head>
<body><div class="hero">Hero</div></body></html>
HTML
port=$((20000 + RANDOM % 20000))
(cd "$site" && python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) &
server=$!
trap 'kill $server 2>/dev/null; bridge --quit >/dev/null 2>&1 || true' EXIT
sleep 0.5

page="$CASE_DIR/pages/tune.html"
cat > "$page" <<HTML
<!doctype html><html><head><title>Tune the hero</title>
<style>.card{border-radius:var(--radius, 4px);padding:var(--pad, 8px);border:1px solid #ccc}</style></head>
<body>
<h1>Tune the hero</h1>
<label>Radius <input type="range" data-record="radius" data-drive="--radius" data-unit="px" data-target=".card" min="0" max="24" value="4"></label>
<label>Padding <input type="range" data-record="pad" data-drive="--pad" data-unit="px" min="0" max="48" value="10"></label>
<div class="card">A card on this page</div>
<iframe src="http://127.0.0.1:$port/" style="width:100%;height:200px"></iframe>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge tune.html)
wait_ready
js() { bridge --js "$page" "$1"; }
set_range() { js "const r = document.querySelector('[data-record=$1]'); r.value = $2; r.dispatchEvent(new Event('input', {bubbles: true})); return 1" >/dev/null; }

check_json "initial values are applied on load" "$(js "return getComputedStyle(document.querySelector('.card')).borderRadius")" '.' "4px"
set_range radius 16
check_json "a slider drives the page's element live" "$(js "return getComputedStyle(document.querySelector('.card')).borderRadius")" '.' "16px"
settle 0.3
check_json "and records the value" "$(bridge --read "$page")" '.answers.radius' "16"

set_range pad 32
settle 0.4
check_json "the same control drives the embedded live site" "$(js "@frame return getComputedStyle(document.querySelector('.hero')).padding")" '.' "32px"
check_json "the frame received the earlier value too" "$(js "@frame return getComputedStyle(document.querySelector('.hero')).borderRadius")" '.' "16px"
snap driven "Radius 16 and padding 32, on the card and inside the live site"

# Reopening the page applies the recorded values before the user touches anything
bridge --quit; sleep 0.4
(cd "$CASE_DIR/pages" && bridge tune.html)
wait_ready
settle 0.5
check_json "recorded values drive the page after a restart" "$(js "return getComputedStyle(document.querySelector('.card')).borderRadius")" '.' "16px"
check_json "and the frame" "$(js "@frame return getComputedStyle(document.querySelector('.hero')).padding")" '.' "32px"
finish
