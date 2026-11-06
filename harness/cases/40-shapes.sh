#!/bin/bash
# The shapes an agent reaches for when it writes an estimate or a finding:
# a .card of .row.between rows keeps its .num values on one right edge and on
# the label's first baseline; a table.data aligns its cells with a quiet
# .remark; a class nothing defines makes presenting refuse the page and name
# it, while a class the page styles itself is not named; and an empty list says so.
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
(cd "$CASE_DIR/pages" && bridge estimate.html 2> "$CASE_DIR/present.err"); code=$?
check "presenting refuses a page with classes nothing defines, and names them (exit $code)" "$code $(grep -o '`\.[a-z]*` styles nothing' "$CASE_DIR/present.err" | tr '\n' ' ')$(grep -c 'not presented' "$CASE_DIR/present.err")" "1 \`.faint\` styles nothing \`.zebra\` styles nothing 1"
sed -i '' 's/ class="faint"/ class="muted"/; s/row between zebra/row between/' "$page"
(cd "$CASE_DIR/pages" && bridge estimate.html 2>/dev/null); wait_ready; settle 0.4
js() { bridge --js "$page" "$1"; }
check_json "each value sits on its row's right edge, one edge for all three" "$(js "const rs = [1,2,3].map((i) => { const r = document.getElementById('r' + i); const n = r.querySelector('.num').getBoundingClientRect(); return [Math.round(r.getBoundingClientRect().right - n.right), Math.round(n.right)] }); return { flush: rs.map((r) => r[0]), edges: new Set(rs.map((r) => r[1])).size }")" '"\(.flush | join(",")) \(.edges)"' "0,0,0 1"
check_json "a value sits on the first line of a two-line label, not between its lines" "$(js "const r = document.getElementById('r1'); const l = r.firstElementChild.getBoundingClientRect(); const n = r.querySelector('.num').getBoundingClientRect(); return { top: Math.abs(Math.round(n.top - l.top)), tall: l.height > n.height * 1.5 }")" '(.top <= 1) and .tall' "true"
check_json "the data table hugs its columns, the remark is quiet and the second group has air above it" "$(js "const t = document.getElementById('data'); const rm = t.querySelector('.remark'); const g2 = document.getElementById('g2').querySelector('td'); return { hugs: t.getBoundingClientRect().width < document.body.clientWidth - 40, quiet: getComputedStyle(rm).color !== getComputedStyle(t).color, air: parseFloat(getComputedStyle(g2).paddingTop) >= 16 }")" '[.hugs, .quiet, .air] | join(",")' "true,true,true"

(cd "$CASE_DIR/pages" && bridge own.html 2> "$CASE_DIR/own.err"); wait_ready; settle 0.4
check "a class the page styles in its own <style>, in a media rule too, is not reported" "$(cat "$CASE_DIR/own.err")" ""

port=$((20000 + RANDOM % 20000))
python3 -c 'import http.server, sys, time
class Slow(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(3); self.send_response(200); self.send_header("Content-Type", "text/css"); self.end_headers(); self.wfile.write(b"body {}")
    def log_message(self, *args): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Slow).serve_forever()' "$port" &
server=$!
trap 'kill $server 2>/dev/null; bridge --quit >/dev/null 2>&1 || true' EXIT
sleep 0.5
cat > "$CASE_DIR/pages/fonts.html" <<HTML
<!doctype html><html><head><title>Fonts</title><link rel="stylesheet" href="http://127.0.0.1:$port/fonts.css"><style>.zebra { color: red }</style></head><body>
<div class="card zebra">styled by the page</div>
</body></html>
HTML
(cd "$CASE_DIR/pages" && bridge fonts.html 2> "$CASE_DIR/fonts.err"); wait_ready; settle 0.4
check "a class in the page's <style> after a stylesheet still loading from elsewhere is not reported" "$(cat "$CASE_DIR/fonts.err")" ""
bridge --cross "$CASE_DIR/pages/fonts.html" >/dev/null

# Nothing left in Waiting: the list column says so instead of standing blank.
bridge --cross "$page" >/dev/null; bridge --cross "$CASE_DIR/pages/own.html" >/dev/null; bridge --do project waiting >/dev/null; settle 0.4
check_json "the list column names its empty state" "$(bridge --state)" '.listEmpty' "Nothing waiting"
bridge --do project all >/dev/null; settle 0.3
check_json "All is not empty, so no line" "$(bridge --state)" '.listEmpty' ""
finish
