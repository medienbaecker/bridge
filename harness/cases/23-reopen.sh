#!/bin/bash
# Opening a page must never change it. An editor script (a page recording through
# the API, sidecar from before this build) and a small editor: open,
# quit, relaunch three times; version, fingerprint and history never move, and
# the editor's sidecar stays byte-identical.
source "$(dirname "$0")/../lib.sh"
page=$(fixture editor-script.html); fixture editor-script.html.bridge.json >/dev/null
editor="$CASE_DIR/pages/editor.html"
cat > "$editor" <<'HTML'
<!doctype html><html><head><title>Editor</title></head><body>
<textarea id="script"></textarea>
<script>
  const box = document.getElementById("script");
  bridge.ready(() => { box.value = bridge.get("script") || ""; });
  box.addEventListener("input", () => bridge.set("script", box.value));
</script>
</body></html>
HTML
repo
exe="$BRIDGE_DEV_APP/Contents/MacOS/$(ls "$BRIDGE_DEV_APP/Contents/MacOS" | head -1)"
relaunch() { bridge --quit >/dev/null 2>&1; sleep 0.5; "$exe" >/dev/null 2>&1 & sleep 0.3; wait_ready; settle 2.5; }
sig() { jq -c '{version, fingerprint, status, hist: (.history|length), notes: (.comments|length), script: (.answers.script|length)}' "$(sidecar "$1")"; }

before=$(sig "$page")
check "the sidecar as staged: version 6, five notes, the script, no api field" "$before" '{"version":6,"fingerprint":"18b3d279de0f","status":"open","hist":5,"notes":5,"script":15751}'
# Presenting stamps who presented it, from where and when; apart from that stamp the record must not move.
bytes=$(jq -cS 'del(.presented, .page)' "$(sidecar "$page")" | shasum | cut -d' ' -f1)
(cd "$CASE_DIR/pages" && bridge editor-script.html); wait_ready; settle 2.5
check "opening it changes neither version, fingerprint nor history" "$(sig "$page")" "$before"
check "a pre-API sidecar comes out byte-identical apart from the presented stamp" "$(jq -cS 'del(.presented, .page)' "$(sidecar "$page")" | shasum | cut -d' ' -f1)" "$bytes"
check_json "the script came back through get inside ready" "$(bridge --js "$page" "return (bridge.get('script')||'').length")" '.' "15751"
check_json "no banner" "$(bridge --state)" '.banner // "none"' "none"
for i in 1 2 3; do
  relaunch
  check "relaunch $i: version, fingerprint and history unchanged" "$(sig "$page")" "$before"
  check_json "relaunch $i: no banner" "$(bridge --state)" '.banner // "none"' "none"
done

# The editor, alone in a fresh state: after a late second key, byte-identical across relaunches.
bridge --quit >/dev/null 2>&1; sleep 0.5
export XDG_STATE_HOME="$CASE_DIR/state2"; mkdir -p "$XDG_STATE_HOME"
(cd "$CASE_DIR/pages" && bridge editor.html); wait_ready
js() { bridge --js "$editor" "$1"; }
js "bridge.set('script', 'Erste Zeile'); return 1" >/dev/null; settle 0.5
js "bridge.set('rev', 2); return 1" >/dev/null; settle 0.5
bridge --quit >/dev/null 2>&1; sleep 0.5
sum=$(shasum "$(sidecar "$editor")" | cut -d' ' -f1)
check_json "the editor's questions are both keys" "$(cat "$(sidecar "$editor")")" '.questions | join(",")' "rev,script"
for i in 1 2 3; do
  relaunch
  check "relaunch $i: the editor's sidecar is byte-identical" "$(shasum "$(sidecar "$editor")" | cut -d' ' -f1)" "$sum"
done
check_json "the late key still reads back" "$(js "return bridge.get('rev')")" '.' "2"
check_json "and the text is in the box" "$(js "return document.getElementById('script').value")" '.' "Erste Zeile"
finish
