#!/bin/bash
# The shapes an agent reaches for when it writes an estimate or a finding:
# a .card of .row.between rows keeps its .num values on one right edge and on
# the label's first baseline (from geometry and from the pixels of a real
# frame); a table.data aligns its cells with a quiet .remark; a class nothing
# defines is named on stderr by the CLI invocation that presented the page,
# while a class the page styles itself is not; and an empty list says so.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/estimate.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Estimate</title></head><body>
<h1>Estimate</h1>
<div class="card" id="card">
  <div class="row between" id="r1"><span><strong>Item 1</strong> · 4 parts, 2 locked<br><span class="faint">lorem ipsum dolor sit amet consectetur adipiscing</span></span><span class="num">4–6 h</span></div>
  <hr>
  <div class="row between" id="r2"><span><strong>Export</strong></span><span class="num">1 h</span></div>
  <hr>
  <div class="row between zebra" id="r3"><span><strong>A much longer label that goes on and on so the value has to be pushed to the right edge regardless</strong></span><span class="num">12 h</span></div>
</div>
<table class="data" id="data">
  <tbody><tr><td><code>#item-a</code></td><td>"Lorem ipsum dolor sit amet"</td><td class="remark">fallback A</td></tr></tbody>
  <tbody><tr id="g2"><td><code>#item-a</code></td><td>"Consectetur adipiscing elit"</td><td class="remark">the second one</td></tr></tbody>
</table>
<pre><code class="language-html">&lt;a href="/"&gt;x&lt;/a&gt;</code></pre>
</body></html>
HTML
cat > "$CASE_DIR/pages/own.html" <<'HTML'
<!doctype html><html><head><title>Own</title><style>.zebra { color: red } @media (min-width: 1px) { .stripe { color: blue } }</style></head><body>
<div class="card zebra stripe">styled by the page</div>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge estimate.html 2> "$CASE_DIR/present.err"); wait_ready; settle 0.4
check "the presenting invocation names the classes nothing defines, on stderr" "$(sed 's/^bridge-dev: //' "$CASE_DIR/present.err")" "unknown classes on estimate.html: faint, zebra: see pages.md, What the base stylesheet gives you"
js() { bridge --js "$page" "$1"; }
check_json "each value sits on its row's right edge, one edge for all three" "$(js "const rs = [1,2,3].map((i) => { const r = document.getElementById('r' + i); const n = r.querySelector('.num').getBoundingClientRect(); return [Math.round(r.getBoundingClientRect().right - n.right), Math.round(n.right)] }); return { flush: rs.map((r) => r[0]), edges: new Set(rs.map((r) => r[1])).size }")" '"\(.flush | join(",")) \(.edges)"' "0,0,0 1"
check_json "a value sits on the first line of a two-line label, not between its lines" "$(js "const r = document.getElementById('r1'); const l = r.firstElementChild.getBoundingClientRect(); const n = r.querySelector('.num').getBoundingClientRect(); return { top: Math.abs(Math.round(n.top - l.top)), tall: l.height > n.height * 1.5 }")" '(.top <= 1) and .tall' "true"
check_json "the card is one bordered box with no doubled padding at its ends" "$(js "const c = getComputedStyle(document.getElementById('card')); return [c.borderTopWidth, c.paddingTop, getComputedStyle(document.getElementById('r1')).marginTop].join(' ')")" '.' "1px 12px 0px"
check_json "the data table hugs its columns, the remark is quiet and the second group has air above it" "$(js "const t = document.getElementById('data'); const rm = t.querySelector('.remark'); const g2 = document.getElementById('g2').querySelector('td'); return { hugs: t.getBoundingClientRect().width < document.body.clientWidth - 40, quiet: getComputedStyle(rm).color !== getComputedStyle(t).color, air: parseFloat(getComputedStyle(g2).paddingTop) >= 16 }")" '[.hugs, .quiet, .air] | join(",")' "true,true,true"

# The pixels: the ink of the three values ends on one right edge in a real frame.
r=$(shot rows) || true
state=$(bridge --state); scale=$(printf '%s' "$state" | jq -r .backingScale); px=$(printf '%s' "$state" | jq -r .pageX); py=$(printf '%s' "$state" | jq -r .pageY)
# The row's y in the frame, not in the page: without pageY the scanline sits a
# titlebar above the rows, and three empty answers are one distinct answer.
edge() { python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/rows.png" "$1" 1 | awk -v from=$(( (px + 10) * scale )) '$1 > from && $3 + $4 + $5 < 500 {last = $2} END {if (last) print last}'; }
edges=$(for i in 1 2 3; do
  y=$(js "const n = document.getElementById('r$i').querySelector('.num').getBoundingClientRect(); return Math.round(($py + n.top + n.height / 2) * $scale)")
  ink "the value's right edge on row $i" edge "$y"
done | sort -u | wc -l | tr -d ' ')
check "in the photograph the three values' ink ends on one x, to the pixel" "$edges" "1"

(cd "$CASE_DIR/pages" && bridge own.html 2> "$CASE_DIR/own.err"); wait_ready; settle 0.4
check "a class the page styles in its own <style>, in a media rule too, is not reported" "$(cat "$CASE_DIR/own.err")" ""

# Nothing left in Waiting: the list column says so instead of standing blank.
bridge --cross "$page" >/dev/null; bridge --cross "$CASE_DIR/pages/own.html" >/dev/null; bridge --do project waiting >/dev/null; settle 0.4
check_json "the list column names its empty state" "$(bridge --state)" '.listEmpty' "Nothing waiting"
r=$(shot empty) || true
state=$(bridge --state); w0=$(printf '%s' "$state" | jq -r '.columnWidths[0]'); w1=$(printf '%s' "$state" | jq -r '.columnWidths[1]')
read fx fy fw fh <<< "$(printf '%s' "$state" | jq -r '.listEmptyFrame | "\(.x) \(.y) \(.width) \(.height)"')"
check "the line sits inside the list column" "$(awk -v x=$fx -v w=$fw -v a=$w0 -v b=$((w0 + w1)) 'BEGIN {print (x > a && x + w < b) ? "inside" : "outside"}')" "inside"
ink=$(python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/empty.png" region $(awk -v v=$fx -v s=$scale 'BEGIN {print int(v * s)}') $(awk -v v=$fy -v s=$scale 'BEGIN {print int(v * s)}') $(awk -v v=$fx -v w=$fw -v s=$scale 'BEGIN {print int((v + w) * s)}') $(awk -v v=$fy -v h=$fh -v s=$scale 'BEGIN {print int((v + h) * s)}') | awk '{print ($2 > 4) ? "ink" : "blank"}')
check "the line is drawn there, from pixels" "$ink" "ink"
bridge --do project all >/dev/null; settle 0.3
check_json "All is not empty, so no line" "$(bridge --state)" '.listEmpty' ""
finish
