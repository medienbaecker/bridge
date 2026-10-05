#!/bin/bash
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/broken.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Broken</title></head><body>
<p>Pick one</p>
<script>
document.getElementById('missing').textContent = 'x';
</script>
<script>
Promise.reject(new Error('fetch failed'));
bridge.ready(() => { throw new Error('ready blew up'); });
</script>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge broken.html 2> "$CASE_DIR/present.err"); wait_ready; settle 0.4
err=$(sed 's/^bridge-dev: //' "$CASE_DIR/present.err")
check "an uncaught error in a top-level script is named with its line" "$(printf '%s\n' "$err" | grep -c "^broken.html threw: TypeError: null is not an object .*(broken.html:4)$")" "1"
check "an unhandled rejection is named" "$(printf '%s\n' "$err" | grep -c "^broken.html threw: Unhandled rejection: fetch failed$")" "1"
check "a throw inside bridge.ready is named with its line" "$(printf '%s\n' "$err" | grep -c "^broken.html threw: in bridge.ready: ready blew up (broken.html:8)$")" "1"

hook() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$CASE_DIR/pages" | bridge --hook post-write; }
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Broken</title></head><body>
<p>Pick one</p>
<script>document.body.dataset.fine = '1';</script>
</body></html>
HTML
check "a rewrite that fixed it says nothing" "$(hook "$page")" ""

cat > "$page" <<'HTML'
<!doctype html><html><head><title>Broken</title></head><body>
<p>Pick one</p>
<script>bridge.ready(() => undefinedThing());</script>
</body></html>
HTML
check_json "a rewrite that throws says so in the tool result" "$(hook "$page")" '.hookSpecificOutput.additionalContext' "Bridge: broken.html threw in their window: in bridge.ready: Can't find variable: undefinedThing (broken.html:3)."

clean="$CASE_DIR/pages/clean.html"
printf '<!doctype html><html><head><title>Clean</title></head><body><p>fine</p><script>1;</script></body></html>' > "$clean"
(cd "$CASE_DIR/pages" && bridge clean.html 2> "$CASE_DIR/clean.err"); wait_ready; settle 0.4
check "a clean page prints nothing" "$(cat "$CASE_DIR/clean.err")" ""
finish
