#!/bin/bash
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/form.html"
cat > "$page" <<'HTML'
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Form</title></head><body>
<h1>Form</h1>
<div class="options">
  <div data-record="layout" data-value="grid"><strong>Grid</strong></div>
  <div data-record="layout" data-value="list"><strong>List</strong></div>
</div>
<label>Name <input type="text" data-record="name" id="name"></label>
<label>Font <select data-record="font" id="font"><option>Inter</option><option>Georgia</option></select></label>
<label id="agree-label"><input type="checkbox" data-record="agree" id="agree"> Agree</label>
<label><input type="checkbox" data-record="news" id="news" checked> Newsletter</label>
<label>Radius <input type="range" data-record="radius" id="radius" min="0" max="24" value="8"></label>
<div data-record="side" class="row"><label><input type="radio" name="side" value="left" id="left"> Left</label><label><input type="radio" name="side" value="right" id="right"> Right</label></div>
<fieldset data-record="days"><legend>Days</legend><label><input type="checkbox" value="mon" id="mon"> Mon</label><label><input type="checkbox" value="tue"> Tue</label></fieldset>
<label for="note">Note</label>
<textarea id="note" data-record="note"></textarea>
</body></html>
HTML
repo
claude_session "$BRIDGE_SESSION"
(cd "$CASE_DIR/pages" && bridge form.html 2>/dev/null); wait_ready; settle 0.6
js() { bridge --js "$page" "$1"; }
answers() { bridge --read "$page"; }
pick() { js "const el = document.getElementById('$1'); el.value = '$2'; el.dispatchEvent(new Event('input', {bubbles: true})); el.dispatchEvent(new Event('change', {bubbles: true})); return 1" >/dev/null; settle 0.3; }
click() { js "document.getElementById('$1').click(); return 1" >/dev/null; settle 0.3; }
shown() { js "const v = (id) => document.getElementById(id); return [v('name').value, v('font').value, v('agree').checked, v('news').checked, v('radius').value, v('right').checked, v('mon').checked, v('note').value, !!document.querySelector('[data-selected]')].join('|')" | jq -r .; }
marks() { js "return document.querySelectorAll('.bridge-answered-dot, [data-answered]').length"; }
tags() { js "return [...document.querySelectorAll('[data-default-tag]')].map(t => t.textContent.trim()).join(',') + '|' + [...document.querySelectorAll('bridge-default')].map(t => t.previousElementSibling.id).join(',')" | jq -r .; }

check_json "an untouched unchecked box proposes nothing; a checked one and a select do" "$(answers)" '.defaults | tojson' '{"font":"Inter","news":true,"radius":8}'
check "and only those carry the default tag" "$(tags)" "Newsletter|font,radius"

click agree
check_json "ticking a box is an answer" "$(answers)" '.answers.agree' "true"
click agree
check_json "unticking it again takes the answer back" "$(answers)" '.answers | has("agree")' "false"
click mon
click mon
check_json "a group with every box unticked again is no answer either" "$(answers)" '.answers | has("days")' "false"

js "document.querySelector('[data-value=grid]').click(); return 1" >/dev/null
pick name Alex
pick font Georgia
click agree
click news
pick radius 20
click right
click mon
pick note "please keep this"
check "everything answered shows as answered" "$(shown)" "Alex|Georgia|true|false|20|true|true|please keep this|true"
js "document.getElementById('name').focus(); return 1" >/dev/null
bridge --do send >/dev/null; settle 0.3
shot v1 >/dev/null

python3 - "$page" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('</div>\n<label>Name', '  <div data-record="layout" data-value="masonry"><strong>Masonry</strong></div>\n</div>\n<label>Name')
open(p,'w').write(s)
PY
settle 0.8
r=$(answers)
check_json "the rewrite is version 2 with nothing answered" "$r" '"\(.version) \(.answers | length) \(.history[0].answers.name)"' "2 0 Alex"
check "every control is back at the page's own value, the focused one too" "$(shown)" "|Inter|false|true|8|false|false||false"
check_json "no control is marked as answered" "$(marks)" '.' "0"
check "the default tags are the page's again, none on the unchecked box" "$(tags)" "Newsletter|font,radius"
check_json "the record's defaults match what is shown" "$r" '.defaults | tojson' '{"font":"Inter","news":true,"radius":8}'
check_json "a last-time hint follows the checkbox's whole label, not the box" "$(js "const hint = document.getElementById('agree-label').nextElementSibling; return hint.className + ':' + hint.textContent + ':' + document.getElementById('agree-label').textContent.trim()")" '.' "bridge-previous:true:Agree"
check_json "and every earlier answer has one" "$(js "return document.querySelectorAll('.bridge-previous').length")" '.' "9"
shot v2 >/dev/null

pick name Sam
bridge --do send >/dev/null; settle 0.4
out=$(inbox "$BRIDGE_SESSION" | tail -1)
check "the hand-over carries the new answer and points at history" "$(printf '%s' "$out" | grep -o '(version 2): {[^}]*}\. What they answered on earlier versions is under `history` in --read\.')" '(version 2): {"name":"Sam"}. What they answered on earlier versions is under `history` in --read.'
finish
