#!/bin/bash
# A page whose script builds its content must survive a prose-only rewrite:
# the runtime reloads it rather than morphing its content away. A page whose
# script only enhances the markup still patches.
source "$(dirname "$0")/../lib.sh"
built="$CASE_DIR/pages/built.html"
cat > "$built" <<'HTML'
<!doctype html><html><head><title>Built by script</title></head><body>
<h1>Placeholder list</h1>
<div class="options"><div><input type="radio" name="l" id="l-y" value="yes" data-record="lock"><label for="l-y">Lock</label></div></div>
<ul id="pools"></ul>
<script>
  const POOLS = ["Item 1", "Item 2", "Item 3", "Item 4", "Item 5", "Item 6"];
  document.getElementById("pools").innerHTML = POOLS.map((p) => `<li><b>${p}</b><span>lorem ipsum</span></li>`).join("");
</script>
</body></html>
HTML
enhanced="$CASE_DIR/pages/enhanced.html"
cat > "$enhanced" <<'HTML'
<!doctype html><html><head><title>Enhanced by script</title></head><body>
<h1>Plain markup</h1>
<ul id="pools"><li>Item 1</li><li>Item 2</li></ul>
<script>for (const li of document.querySelectorAll("li")) li.dataset.seen = "yes";</script>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge built.html enhanced.html)
wait_ready
js() { bridge --js "$1" "$2"; }
js "$built" "document.querySelector('#l-y').click(); window.__marker = 'alive'; return 1" >/dev/null; settle 0.3
check_json "the script built its list" "$(js "$built" "return document.querySelectorAll('#pools li').length")" '.' "6"
sed -i '' 's/Placeholder list/Placeholder list /' "$built"; settle 0.8; wait_ready
check_json "after a prose rewrite the list is still there" "$(js "$built" "return document.querySelectorAll('#pools li').length")" '.' "6"
check_json "because the page was reloaded, honestly" "$(js "$built" "return window.__marker || 'gone'")" '.' "gone"
check_json "and the banner says why" "$(bridge --state)" '.banner' "This page builds itself with a script, so it was reloaded rather than patched."
read=$(bridge --read "$built")
check_json "version unchanged" "$read" '.version' "1"
check_json "answer stands" "$read" '.answers.lock' "yes"
check_json "the answer is shown again" "$(js "$built" "return document.querySelector('#l-y').checked")" '.' "true"

bridge --do select "$enhanced" >/dev/null; wait_ready
js "$enhanced" "window.__marker = 'alive'; return 1" >/dev/null
sed -i '' 's/Plain markup/Plain markup, edited/' "$enhanced"; settle 0.6
check_json "a page whose script only enhances still patches" "$(js "$enhanced" "return window.__marker")" '.' "alive"
check_json "with the new prose" "$(js "$enhanced" "return document.querySelector('h1').textContent")" '.' "Plain markup, edited"
finish
