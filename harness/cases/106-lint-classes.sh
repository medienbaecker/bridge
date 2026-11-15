#!/bin/bash
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/quoted.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Menu</title></head><body>
<h1>Menu</h1>
<pre><code class="language-js">menu.classList.add('open');
menu.className = "shut";</code></pre>
</body></html>
HTML
out=$(bridge --lint "$page"); code=$?
check "script quoted in a pre is not the page's own classes" "$code $(printf '%s' "$out" | wc -l | tr -d ' ')" "0 0"

page="$CASE_DIR/pages/quotes.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Menu</title></head><body>
<p class='lone'>Lorem</p>
<p class=bare>Ipsum</p>
<p class='muted'>Dolor</p>
<p class=muted>Sit</p>
<script>document.body.classList.add('open')</script>
</body></html>
HTML
out=$(bridge --lint "$page"); code=$?
check "a class in single quotes, one without quotes and one set by the page's script are all read" "$code $(printf '%s\n' "$out" | cut -d: -f2-4 | cut -d' ' -f1-3 | tr '\n' '|')" '1 2: error: `.lone`|3: error: `.bare`|6: error: `.open`|'
finish
