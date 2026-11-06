#!/bin/bash
# Crossed is list hygiene and never gates delivery. A sent, read and crossed
# bridge gets a changed answer and a Send: it reaches the presenting session's
# inbox, and the row stays crossed.
source "$(dirname "$0")/../lib.sh"
# serial
page="$CASE_DIR/pages/crossed.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Crossed</title></head><body>
<fieldset class="options"><legend>Where?</legend>
  <div><input type="radio" name="w" id="w-a" value="pool" data-record="where"><label for="w-a">Pool</label><span>desc</span></div>
  <div><input type="radio" name="w" id="w-b" value="page" data-record="where"><label for="w-b">Page</label><span>desc</span></div>
</fieldset>
</body></html>
HTML
repo
claude_session "$BRIDGE_SESSION"
(cd "$CASE_DIR/pages" && bridge crossed.html); wait_ready
js() { bridge --js "$page" "$1"; }
told() { settle 0.5; inbox "$BRIDGE_SESSION" | grep -c "$1"; }
crossed() { bridge --state | jq -r '[.sidebar[].bridges[] | select(.location | endswith("crossed.html")) | .crossed][0]'; }

js "document.querySelector('#w-b').click(); return 1" >/dev/null; settle 0.3
bridge --do send >/dev/null; settle 3
bridge --cross "$page" >/dev/null; settle 0.3

js "document.querySelector('#w-a').click(); return 1" >/dev/null; settle 0.3
bridge --do send >/dev/null; settle 0.3
check "Send on a crossed bridge delivers the new answer" "$(told '"where":"pool"')" "1"
check "and it is still crossed" "$(crossed)" "true"
finish
