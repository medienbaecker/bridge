#!/bin/bash
# One box is one box: a panel surface inside another paints nothing, so an
# agent composing two documented things cannot produce a doubled surface.
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
snap nest "One box is one box"
finish
