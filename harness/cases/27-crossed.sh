#!/bin/bash
# Crossed is list hygiene and never gates delivery. A sent, read and crossed
# bridge gets a second note, a changed answer and a Send: each reaches the
# presenting session's inbox, and the row stays crossed.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/crossed.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Crossed</title></head><body>
<fieldset class="options"><legend>Where?</legend>
  <div><input type="radio" name="w" id="w-a" value="pool" data-record="where"><label for="w-a">Pool</label><span>desc</span></div>
  <div><input type="radio" name="w" id="w-b" value="page" data-record="where"><label for="w-b">Page</label><span>desc</span></div>
</fieldset>
<p id="para">A paragraph the user pins after the agent has read and crossed this.</p>
</body></html>
HTML
repo
claude_session "$BRIDGE_SESSION"
(cd "$CASE_DIR/pages" && bridge crossed.html); wait_ready
js() { bridge --js "$page" "$1"; }
told() { settle 0.5; inbox "$BRIDGE_SESSION" | grep -c "$1"; }
note() { bridge --do point >/dev/null; js "const el = document.querySelector('#para'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: r.left + 20, clientY: r.top + 8}))" >/dev/null; settle 0.3; js "const t = document.querySelector('.bridge-thread:popover-open textarea'); t.value = '$1'; t.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true}))" >/dev/null; settle 0.4; }
crossed() { bridge --state | jq -r '[.sidebar[].bridges[] | select(.location | endswith("crossed.html")) | .crossed][0]'; }

js "document.querySelector('#w-b').click(); return 1" >/dev/null; settle 0.3
note "first note"
bridge --do send >/dev/null; settle 0.3
check "sent: it is delivered" "$(told 'The user answered')" "1"
settle 2.5
check "once" "$(told 'Bridge:')" "1"
bridge --cross "$page" >/dev/null; settle 0.3
check "the agent crossed it" "$(crossed)" "true"

note "second note, after crossing"
check_json "the note is on the page" "$(bridge --pins "$page")" 'length' "2"
check "a note after crossing reaches the session: wrote more since you read it" "$(told 'wrote more.*2 notes')" "1"
check "still crossed" "$(crossed)" "true"
settle 2.5
check "delivered once, then quiet" "$(told 'Bridge:')" "2"

js "document.querySelector('#w-a').click(); return 1" >/dev/null; settle 0.3
check_json "a changed answer reopens it" "$(bridge --read "$page")" '.status' "open"
bridge --do send >/dev/null; settle 0.3
check "Send on a crossed bridge delivers the new answer" "$(told '"where":"pool"')" "1"
check "and it is still crossed" "$(crossed)" "true"
check_json "--read works on it" "$(bridge --read "$page")" '.status + " " + .answers.where' "sent pool"
check_json "--pins works on it" "$(bridge --pins "$page")" 'length' "2"
check_json "--wait returns at once, it is sent" "$(bridge --wait "$page" --timeout 2)" '.status' "sent"
finish
