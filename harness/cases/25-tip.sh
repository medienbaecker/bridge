#!/bin/bash
# The pin's tip is the part that points: it lands on the click, mid-page and at the top edge.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/tip.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Tip</title><style>body{margin:0} h1{margin:0;padding:2px 16px;font:600 20px system-ui} p{margin:240px 16px 0;font:16px/1.5 system-ui}</style></head><body>
<h1>At the very top</h1>
<p>A paragraph well down the page, long enough to point at somewhere in the middle of a line.</p>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge tip.html); wait_ready
js() { bridge --js "$page" "$1"; }
pin_at() {  # $1 selector, $2 dx, $3 dy: point, click there, write a note; prints "dx dy gap": the pin's tip against the click, and the composer's top below it
  bridge --do point >/dev/null
  js "const el = document.querySelector('$1'); const r = el.getBoundingClientRect(); window.__click = [r.left + $2, r.top + $3]; el.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: r.left + $2, clientY: r.top + $3}))" >/dev/null
  settle 0.3
  gap=$(js "const t = document.querySelector('.bridge-thread:popover-open').getBoundingClientRect(); return Math.round(t.top - window.__click[1])")
  js "const t = document.querySelector('.bridge-thread:popover-open textarea'); t.value = 'here'; t.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true}))" >/dev/null
  settle 0.4
  tip=$(js "const pins = document.querySelectorAll('.bridge-pin'); const r = pins[pins.length - 1].getBoundingClientRect(); const tip = [(r.left + r.right) / 2, r.bottom]; return [tip[0] - window.__click[0], tip[1] - window.__click[1]].map(v => Math.round(v * 10) / 10).join(' ')" | tr -d '"')
  printf '%s %s' "$tip" "$gap"
}
off=$(pin_at p 60 12)
check "mid-page: the tip is on the click (dx dy within a pixel)" "$(printf '%s' "$off" | jq -R -r 'split(" ") | .[0:2] | map(tonumber | fabs) | max <= 1.5')" "true"
check "the composer opened below the spot, clear of it (gap in px > 12)" "$(printf '%s' "$off" | jq -R -r 'split(" ") | .[2] | tonumber > 12')" "true"
snap tip-mid "Pin tip on the spot, mid-page"
off=$(pin_at h1 40 4)
check "top edge: the tip is on the click too" "$(printf '%s' "$off" | jq -R -r 'split(" ") | .[0:2] | map(tonumber | fabs) | max <= 1.5')" "true"
check_json "two pins, both anchored" "$(bridge --pins "$page")" '[.[] | .lost] | join(",")' "false,false"
snap tip-top "Pin tip at the top edge"
finish
