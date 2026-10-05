#!/bin/bash
# `bridge --lint`: the four faults that cost real damage, caught while the
# writing agent still holds the file, one line each, saying what to do. An
# unknown class with a suggestion from the real vocabulary, a class the page
# and the kit both style, a colour or radius written out, a pre that is a
# table. Errors exit 1, warnings 0; the gallery is clean; the editor script collides.
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
check "one line per finding, in line order, with the file and the level" "$(printf '%s\n' "$out" | cut -d: -f1-3 | tr '\n' '|')" "lint.html:3: warning|lint.html:3: warning|lint.html:6: error|lint.html:7: error|lint.html:8: warning|lint.html:9: warning|"
check "an unknown class gets a suggestion from the vocabulary" "$(printf '%s\n' "$out" | grep -c 'faint. styles nothing: did you mean .\.muted.?')" "1"
check "a collision names both sides and a rename from the page's title" "$(printf '%s\n' "$out" | grep -c 'draft. is styled by this page and by the kit.*\.estimate-draft')" "1"
check "a colour and a radius written out are warnings naming the tokens" "$(printf '%s\n' "$out" | grep -c 'written out.*var(--bridge-')" "3"
check "a hand-spaced pre is pointed at table.data; real code is left alone" "$(printf '%s\n' "$out" | grep -c 'columns spaced by hand')" "1"
check "the kit's own classes raise nothing" "$(printf '%s\n' "$out" | grep -c 'card\|between\|\.num')" "0"
bridge --lint "$ROOT/harness/fixtures/gallery.html" > "$CASE_DIR/gallery.out"; check "the gallery is clean, exit 0" "$? $(wc -l < "$CASE_DIR/gallery.out" | tr -d ' ')" "0 0"
bridge --lint "$ROOT/harness/fixtures/editor-script.html" > "$CASE_DIR/editor.out"; code=$?
check "the editor script: .draft and .bar collide, nothing else is an error (exit $code)" "$code $(grep -c ': error: ' "$CASE_DIR/editor.out") $(grep -o '`\.[a-z]*` is styled by this page' "$CASE_DIR/editor.out" | sort | tr '\n' ' ')" "1 2 \`.bar\` is styled by this page \`.draft\` is styled by this page "
# A page that loads a stylesheet from elsewhere cannot be checked for unknown classes: nothing is called unknown.
printf '<title>x</title><link rel="stylesheet" href="https://example.com/a.css"><div class="wa-card">y</div>' > "$CASE_DIR/pages/ext.html"
check "a page on another stylesheet raises no unknown class" "$(bridge --lint "$CASE_DIR/pages/ext.html" | wc -l | tr -d ' ')" "0"
finish
