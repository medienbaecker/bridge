#!/bin/bash
# `bridge --lint` on the command line: one line per finding, errors exit 1,
# warnings 0; the gallery and the editor script are clean.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/lint.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Estimate for Alex</title>
<style>
  .th { color: #333; border-radius: 3px; }
  .th.draft { border: 1px dashed red; }
</style></head><body>
<div class="card row between"><span class="faint">Item 1</span><span class="num">4 h</span></div>
<figure class="th draft"></figure>
<p style="color: rgb(200, 0, 0)">red</p>
<pre><code class="language-html">#item-a       "Lorem ipsum dolor sit amet ut"      fallback A
#item-b       …                                     fallback A</code></pre>
<pre><code class="language-bash">bridge --read page.html</code></pre>
</body></html>
HTML
out=$(bridge --lint "$page"); code=$?
check "errors exit 1" "$code" "1"
check "one line per finding, in line order, with the file and the level" "$(printf '%s\n' "$out" | cut -d: -f1-3 | tr '\n' '|')" "lint.html:3: warning|lint.html:6: error|lint.html:7: error|lint.html:8: warning|lint.html:9: warning|"
bridge --lint "$ROOT/harness/fixtures/gallery.html" > "$CASE_DIR/gallery.out"; check "the gallery is clean, exit 0" "$? $(wc -l < "$CASE_DIR/gallery.out" | tr -d ' ')" "0 0"
bridge --lint "$ROOT/harness/fixtures/editor-script.html" > "$CASE_DIR/editor.out"; code=$?
check "the editor script has no errors (exit $code)" "$code $(grep -c ': error: ' "$CASE_DIR/editor.out")" "0 0"
# A page that loads a stylesheet from elsewhere cannot be checked for unknown classes: nothing is called unknown.
printf '<title>x</title><link rel="stylesheet" href="https://example.com/a.css"><div class="wa-card">y</div>' > "$CASE_DIR/pages/ext.html"
check "a page on another stylesheet raises no unknown class" "$(bridge --lint "$CASE_DIR/pages/ext.html" | wc -l | tr -d ' ')" "0"
finish
