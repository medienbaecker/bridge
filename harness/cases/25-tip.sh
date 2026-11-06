#!/bin/bash
# The pin's tip is the part that points: it lands on the click, mid-page and at the top edge.
source "$(dirname "$0")/../lib.sh"
# serial
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
screen="$XDG_STATE_HOME/bridge-dev/freeze/screen.html"
on_screen() { bridge --js "$screen" "@bridge $1"; }
pin_at() {  # $1 selector, $2 dx, $3 dy: mark there in the freeze, write a note; prints "dx dy gap": the pin's tip against the click, and the composer's top below it
  local spot; spot=$(freeze_at "$(js "const r = document.querySelector('$1').getBoundingClientRect(); return (r.left + $2) + ' ' + (r.top + $3)" | jq -r .)")
  bridge --do freeze-mark "$spot" >/dev/null; settle 0.3
  gap=$(on_screen "return Math.round(document.querySelector('.bridge-thread:popover-open').getBoundingClientRect().top - ${spot#* })")
  bridge --do freeze-note "here" >/dev/null; settle 0.5
  tip=$(on_screen "const pins = document.querySelectorAll('.bridge-pin'); const r = pins[pins.length - 1].getBoundingClientRect(); return [(r.left + r.right) / 2 - ${spot% *}, r.bottom - ${spot#* }].map(v => Math.round(v * 10) / 10).join(' ')" | tr -d '"')
  printf '%s %s' "$tip" "$gap"
}
bridge --do freeze >/dev/null; settle 1
off=$(pin_at p 60 12)
check "mid-page: the tip is on the click (dx dy within a pixel)" "$(printf '%s' "$off" | jq -R -r 'split(" ") | .[0:2] | map(tonumber | fabs) | max <= 1.5')" "true"
check "the composer opened below the spot, clear of it (gap in px > 12)" "$(printf '%s' "$off" | jq -R -r 'split(" ") | .[2] | tonumber > 12')" "true"
off=$(pin_at h1 40 4)
check "top edge: the tip is on the click too" "$(printf '%s' "$off" | jq -R -r 'split(" ") | .[0:2] | map(tonumber | fabs) | max <= 1.5')" "true"
bridge --do freeze-mark "$(bridge --state | jq -r '.freeze.screenFrame[2] - 20') 200" >/dev/null; settle 0.3
check_json "by the right edge the composer stays inside the screen" "$(on_screen "const r = document.querySelector('.bridge-thread:popover-open').getBoundingClientRect(); return r.left >= 0 && r.right <= innerWidth && r.top >= 0")" '.' "true"
bridge --do freeze-cancel >/dev/null; settle 0.3
finish
