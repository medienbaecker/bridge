#!/bin/bash
# Dials and colour: tuning by feel, recorded and driving like any control.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/tune.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Tune</title><style>.tune-card{border-radius:var(--radius,4px);background:var(--accent,gray)}</style></head>
<body>
<div class="dials">
  <label class="dial"><span>Radius</span><input type="range" data-record="radius" data-drive="--radius" data-unit="px" data-target=".tune-card" min="0" max="24" step="0.5" value="8"><output></output></label>
  <label class="dial"><span>Ease</span><input type="range" data-record="ease" min="0" max="1" step="0.001" value="0.35"><output></output></label>
</div>
<div class="color" data-record="accent" data-drive="--accent" data-target=".tune-card" value="oklch(0.7 0.1 250)"></div>
<div class="tune-card">Card</div>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge tune.html)
wait_ready
js() { bridge --js "$page" "$1"; }

check_json "readout carries value and unit" "$(js "return document.querySelector('[data-record=radius]').closest('.dial').querySelector('output').textContent")" '.' "8px"

check_json "the colour control is built" "$(js "return document.querySelectorAll('.color .dial').length")" '.' "3"
check_json "gamut readout" "$(js "return document.querySelector('.color .bridge-color-read small').textContent")" '.' "sRGB"
js "const h = document.querySelector('.color .bridge-hex'); h.value = '#ff0000'; h.dispatchEvent(new Event('change', {bubbles: true})); return 1" >/dev/null
settle 0.3
read=$(bridge --read "$page")
check_json "a hex typed in records as oklch" "$read" '.answers.accent' "oklch(0.628 0.258 29.2)"
check_json "and drives the property" "$(js "return getComputedStyle(document.querySelector('.tune-card')).getPropertyValue('--accent')")" '.' "oklch(0.628 0.258 29.2)"
js "for (const [n, v] of [['l', 0.85], ['c', 0.31], ['h', 143]]) document.querySelector('.color input[name=' + n + ']').value = v; document.querySelector('.color input[name=c]').dispatchEvent(new Event('input', {bubbles: true})); return 1" >/dev/null
settle 0.3
check_json "a P3 green outside sRGB says so" "$(js "return document.querySelector('.color .bridge-color-read small').textContent")" '.' "P3"
js "for (const [n, v] of [['l', 0.628], ['c', 0.35], ['h', 29.2]]) document.querySelector('.color input[name=' + n + ']').value = v; document.querySelector('.color input[name=c]').dispatchEvent(new Event('input', {bubbles: true})); return 1" >/dev/null
settle 0.3
check_json "the readout is the oklch string" "$(js "return document.querySelector('.color .bridge-color-read code').textContent")" '.' "oklch(0.628 0.350 29.2)"
snap tune "Dials and an OKLCH colour"

# Reopening restores the colour from the sidecar
bridge --quit; sleep 0.4
(cd "$CASE_DIR/pages" && bridge tune.html)
wait_ready
settle 0.4
check_json "colour restored" "$(js "return document.querySelector('.color').dataset.value")" '.' "oklch(0.628 0.350 29.2)"
finish
