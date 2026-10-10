#!/bin/bash
# An answer can be taken back, and a default never passes for an answer: a
# second click on the chosen card or radio, a control set back to the page's
# value, an emptied field or bridge.clear withdraws it; untouched controls carry
# a "default" tag; after a Send, withdrawing reopens the page and the next Send
# names what was withdrawn.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/unanswer.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Unanswer</title></head><body>
<div class="options"><div data-record="layout" data-value="grid" id="grid">Grid</div><div data-record="layout" data-value="list">List</div></div>
<fieldset class="options">
  <div><input type="radio" name="size" id="s-m" value="m" data-record="size" checked><label for="s-m">Medium</label></div>
  <div><input type="radio" name="size" id="s-l" value="l" data-record="size"><label for="s-l">Large</label></div>
</fieldset>
<fieldset class="options">
  <div><input type="radio" name="tone" id="t-a" value="warm" data-record="tone"><label for="t-a">Warm</label></div>
  <div><input type="radio" name="tone" id="t-b" value="cool" data-record="tone"><label for="t-b">Cool</label></div>
</fieldset>
<select data-record="fit" id="fit"><option value="auto">auto</option><option value="crop">crop</option></select>
<input type="text" data-record="name" id="name">
<script>window.clearIt = () => bridge.clear('fit')</script>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge unanswer.html 2>/dev/null); wait_ready; settle 0.6
js() { bridge --js "$page" "$1"; }
read() { bridge --read "$page"; }
tags() { js "return [...document.querySelectorAll('bridge-default, [data-default-tag]')].map(t => t.matches('bridge-default') ? t.previousElementSibling.id : t.htmlFor).join(',')"; }
press() { js "const el = document.getElementById('$1'); el.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true})); el.click(); return 1" >/dev/null; settle 0.3; }
pick() { js "const el = document.getElementById('$1'); el.value = '$2'; el.dispatchEvent(new Event('input', {bubbles: true})); el.dispatchEvent(new Event('change', {bubbles: true})); return 1" >/dev/null; settle 0.4; }

check_json "untouched controls with a value carry a default tag" "$(tags)" '.' "s-m,fit"
check_json "and the select is greyed as the page's value" "$(js "return document.getElementById('fit').hasAttribute('data-default')")" '.' "true"
check_json "the record has no answers, two defaults with their values" "$(read)" '"\(.answers | length) \(.defaults | tojson)"' '0 {"fit":"auto","size":"m"}'

js "document.getElementById('grid').click(); return 1" >/dev/null; settle 0.3
check_json "a card click answers" "$(read)" '.answers.layout' "grid"
js "document.getElementById('grid').click(); return 1" >/dev/null; settle 0.3
check_json "a second click on the chosen card takes it back" "$(read)" '.answers | has("layout")' "false"
check_json "and the card is no longer selected" "$(js "return document.getElementById('grid').hasAttribute('data-selected')")" '.' "false"

press t-b
check_json "a radio with no default answers" "$(read)" '.answers.tone' "cool"
press t-b
check_json "a second click on it takes it back" "$(read)" '.answers | has("tone")' "false"
check_json "and leaves the group unchecked" "$(js "return document.querySelector('input[name=tone]:checked') === null")" '.' "true"

press s-l
check_json "choosing another radio than the page's answers" "$(read)" '"\(.answers.size) \(.defaults | has("size"))"' "l false"
check_json "and drops its default tag" "$(tags)" '.' "fit"
press s-l
check_json "a second click returns to the page's radio" "$(js "return document.getElementById('s-m').checked")" '.' "true"
check_json "as its default, not an answer" "$(read)" '"\(.answers | has("size")) \(.defaults.size)"' "false m"

pick fit crop
check_json "a select changed is an answer" "$(read)" '.answers.fit' "crop"
pick fit auto
check_json "set back to the page's value it is the default again" "$(read)" '"\(.answers | has("fit")) \(.defaults.fit)"' "false auto"
check_json "and tagged again" "$(tags)" '.' "s-m,fit"

pick name Alex
pick name ""
check_json "an emptied field is no answer" "$(read)" '.answers | has("name")' "false"

pick fit crop
js "clearIt(); return 1" >/dev/null; settle 0.4
check_json "bridge.clear takes an answer back from a script" "$(read)" '.answers | has("fit")' "false"

pick fit crop
js "document.getElementById('grid').click(); return 1" >/dev/null; settle 0.3
bridge --do send >/dev/null; settle 0.3
check_json "sent with two answers" "$(read)" '"\(.status) \(.answers | keys | join(","))"' "sent fit,layout"
js "document.getElementById('grid').click(); return 1" >/dev/null; settle 0.4
check_json "withdrawing after a Send reopens the page" "$(read)" '.status' "open"
bridge --do send >/dev/null; settle 0.3
out=$(printf '%s' "{\"session_id\":\"$BRIDGE_SESSION\"}" | bridge --hook stop --timeout 3 2>&1 >/dev/null)
check "the agent is told only the answer, the withdrawal and the defaults" "$(printf '%s' "$out" | grep -o 'version 1): .*page.s default' | head -1)" 'version 1): {"fit":"crop"}. They withdrew their answer to layout. 1 control was left at the page'"'"'s default'
check_json "the next Send names what was withdrawn" "$(read)" '"\(.status) \(.withdrawn | join(","))"' "sent layout"
finish
