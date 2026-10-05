#!/bin/bash
# bridge.set / get / ready: an editor's state recorded from a script, restored
# on reopen before the page needs it, versioned like any question, and a
# sidecar from before the API existed adopted without a version bump.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/editor.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Editor script</title></head><body>
<h1>Editor script</h1>
<textarea id="script"></textarea>
<p id="restored"></p>
<script>
  const box = document.getElementById("script");
  bridge.ready(() => {
    box.value = bridge.get("script") || "";
    document.getElementById("restored").textContent = "restored: " + JSON.stringify(bridge.get("script") ?? null);
  });
  box.addEventListener("input", () => bridge.set("script", box.value, "The script"));
</script>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge editor.html)
wait_ready
js() { bridge --js "$page" "$1"; }
check_json "window.bridge exists in the page" "$(js "return typeof window.bridge + ',' + typeof bridge.set + ',' + typeof bridge.get + ',' + typeof bridge.ready")" '.' "object,function,function,function"
check_json "ready fired with nothing recorded yet" "$(js "return document.getElementById('restored').textContent")" '.' "restored: null"
js "const b = document.getElementById('script'); b.value = 'Guten Abend — die erste Zeile'; b.dispatchEvent(new Event('input', {bubbles: true})); return 1" >/dev/null; settle 0.5
read=$(bridge --read "$page")
check_json "set records under its key" "$read" '.answers.script' "Guten Abend — die erste Zeile"
check_json "a key touched by the script is a question" "$(cat "$(sidecar "$page")")" '.questions | join(",")' "script"
check_json "still version 1" "$read" '.version' "1"

bridge --quit; sleep 0.4
(cd "$CASE_DIR/pages" && bridge editor.html); wait_ready; settle 0.3
check_json "on reopen, get had the value inside ready" "$(js "return document.getElementById('restored').textContent")" '.' 'restored: "Guten Abend — die erste Zeile"'
check_json "and the editor shows it" "$(js "return document.getElementById('script').value")" '.' "Guten Abend — die erste Zeile"
check_json "reopening is not a new version" "$(bridge --read "$page")" '.version' "1"

# A key first touched later in a session (an item order, after a reorder) must
# survive a reopen: the page hashes before it touches that key again.
js "bridge.set('rev', 2); return 1" >/dev/null; settle 0.5
check_json "a key set later joins the questions" "$(cat "$(sidecar "$page")")" '.questions | join(",")' "rev,script"
bridge --quit; sleep 0.4
(cd "$CASE_DIR/pages" && bridge editor.html); wait_ready; settle 0.8
read=$(bridge --read "$page")
check_json "reopened before the page touches it again: still version 1" "$read" '.version' "1"
check_json "and still its question" "$(cat "$(sidecar "$page")")" '.questions | join(",")' "rev,script"
check_json "no banner about a question dropped" "$(bridge --state)" '.banner // "none"' "none"
check_json "the late key reads back" "$(js "return bridge.get('rev')")" '.' "2"

sed -i '' 's/<h1>Editor script<\/h1>/<h1>Editor script, revised<\/h1>/' "$page"; settle 0.6; wait_ready
check_json "a prose rewrite keeps the version" "$(bridge --read "$page")" '(.version | tostring) + " " + .answers.script' "1 Guten Abend — die erste Zeile"

# A sidecar written before the API existed (no questions, empty fingerprint) is adopted, not bumped
old="$CASE_DIR/pages/legacy.html"; cp "$page" "$old"
cat > "$old.bridge.json" <<'JSON'
{"status":"sent","version":1,"fingerprint":"4f53cda18c2b","questions":[],"answers":{"script":"Der alte Text"},"comments":[],"history":[],"sentAt":"2026-09-19T20:00:00Z"}
JSON
(cd "$CASE_DIR/pages" && bridge legacy.html); wait_ready; settle 0.3
read=$(bridge --read "$old")
check_json "a pre-API sidecar keeps its version" "$read" '.version' "1"
check_json "and its Send" "$read" '.status' "sent"
check_json "and its text is restored" "$(bridge --js "$old" "return document.getElementById('script').value")" '.' "Der alte Text"
finish
