#!/bin/bash
# One box is one box: a panel surface inside another paints nothing, so an
# agent composing two documented things cannot produce a doubled surface.
# Asserted from computed style and from the pixels of a column through the panel.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/nest.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Nest</title></head><body>
<p>Evidence with a code block inside it, as an agent wrote it:</p>
<div class="evidence" id="ev"><pre id="pre"><code>&lt;nav&gt;
  &lt;a href="/en"&gt;EN&lt;/a&gt;
&lt;/nav&gt;</code></pre></div>
<div class="draft" id="dr"><div class="evidence">nested twice</div><input type="text" id="in" value="x"> <button id="bt">Go</button> and <code id="ic">inline</code></div>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge nest.html); wait_ready; settle 0.4
js() { bridge --js "$page" "$1"; }
check_json "the code block inside .evidence paints nothing and has no padding of its own" "$(js "const c = getComputedStyle(document.getElementById('pre')); return [c.backgroundColor, c.paddingLeft].join(' ')")" '.' "rgba(0, 0, 0, 0) 0px"
check_json "an .evidence inside a .draft paints nothing either" "$(js "return getComputedStyle(document.querySelector('#dr .evidence')).backgroundColor")" '.' "rgba(0, 0, 0, 0)"
check_json "a field inside a panel reads as a field: white on the panel, with a hairline" "$(js "const c = getComputedStyle(document.getElementById('in')); return [c.backgroundColor !== getComputedStyle(document.getElementById('dr')).backgroundColor, c.borderTopColor !== 'rgba(0, 0, 0, 0)'].join(',')")" '.' "true,true"
# Pixels: a column 6 px inside the panel's right edge, from the code block's top to its bottom, is one tone.
geo=$(js "const e = document.getElementById('ev').getBoundingClientRect(); const p = document.getElementById('pre').getBoundingClientRect(); return {x: Math.round(e.right - 6), y0: Math.round(p.top), y1: Math.round(p.bottom)}")
st=$(bridge --state); scale=$(printf '%s' "$st" | jq -r '.backingScale'); px=$(printf '%s' "$st" | jq -r '.pageX'); tb=$(printf '%s' "$st" | jq -r '.titlebarHeight')
bridge --shot "$CASE_DIR/shots/nest.png" >/dev/null
x=$(printf '%s' "$geo" | jq -r "((.x + $px) * $scale) | floor"); y0=$(printf '%s' "$geo" | jq -r "((.y0 + $tb) * $scale) | floor"); y1=$(printf '%s' "$geo" | jq -r "((.y1 + $tb) * $scale) | floor")
tones=$(python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/nest.png" column "$x" "$y0" "$y1" 2 | awk '{print $3","$4","$5}' | sort -u | grep -v "^255,255,255$" | wc -l | tr -d ' ')
check "through the panel beside the code block there is one tone, not a panel inside a panel ($tones)" "$tones" "1"
snap nest "One box is one box"
finish
