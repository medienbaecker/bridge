#!/bin/bash
# A page that restores its state from the record must not put a default back
# as a choice: the failure shows on the second open, so this is present,
# drive, re-present, assert. bridge.get(key, { own: true }) is undefined for a
# value the page proposed and the user never touched; bridge.isDefault(key) says so;
# after the user drives the control, or the page sets the key, it is the user's.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/own.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Own</title></head><body>
<label><input type="radio" name="hours" value="mid" data-record="hours" checked> One number</label>
<label><input type="radio" name="hours" value="range" data-record="hours" id="range"> A range</label>
<label><input type="checkbox" data-record="money" id="money" checked> Include extras</label>
<script>
bridge.ready(function () {
  document.body.dataset.own = String(bridge.get('hours', { own: true }));
  document.body.dataset.any = String(bridge.get('hours'));
  document.body.dataset.isDefault = String(bridge.isDefault('hours'));
  document.body.dataset.moneyDefault = String(bridge.isDefault('money'));
});
</script>
</body></html>
HTML
repo
# A present right after a quit can reach the socket of an app still on its way out; wait for it to be gone.
gone() { for i in $(seq 1 60); do [ "$(bridge --state 2>/dev/null | jq -r '.running // false')" = false ] && return; sleep 0.1; done; }
open() { gone; (cd "$CASE_DIR/pages" && bridge own.html 2>/dev/null); wait_ready; settle 0.8; bridge --js "$page" "return document.body.dataset.own + ' ' + document.body.dataset.any + ' ' + document.body.dataset.isDefault + ' ' + document.body.dataset.moneyDefault" | jq -r .; }
# Seeing nothing on a first open is the designed order, not a gap to be fixed
# back. The record is empty until the page has been seen, and recordDefaults runs
# only after bridge.ready has returned, because the runtime waits for a page to
# restore itself before it hashes. So there is no proposal in the record yet and
# nothing the page could mistake for the user's answer. The confusion this whole case is
# about begins at the second open, which is where every check below lives.
check "first open: nothing in the record yet, so nothing to mistake" "$(open)" "undefined undefined false false"
bridge --quit >/dev/null 2>&1; sleep 0.4
check "second open, untouched: still a default, still nothing of the user's" "$(open)" "undefined mid true true"
bridge --js "$page" "document.getElementById('range').click()" >/dev/null; settle 0.6
bridge --quit >/dev/null 2>&1; sleep 0.4
check "after the user drives the radio, the next open sees that value, money still the page's" "$(open)" "range range false true"
# A script change reloads the page inside one app run and its ready runs again.
# The user answers the checkbox first, so what the page reads after the reload is only
# right if it is the record as it is now and not as it was when the window opened.
bridge --js "$page" "document.getElementById('money').click(); document.body.dataset.marker = 'before'" >/dev/null; settle 0.6
perl -pi -e 's/bridge\.ready\(function \(\) \{/bridge.ready(function () { void 0;/' "$page"; settle 1.5
check "the script change reloaded the page" "$(bridge --js "$page" "return String(document.body.dataset.marker)" | jq -r .)" "undefined"
check "after the reload the page reads the record as it is now, not as it opened" "$(bridge --js "$page" "return document.body.dataset.own + ' ' + document.body.dataset.any + ' ' + document.body.dataset.isDefault + ' ' + document.body.dataset.moneyDefault" | jq -r .)" "range range false false"
bridge --js "$page" "bridge.set('money', false); return bridge.isDefault('money')" >/dev/null; settle 0.6
check_json "a value the page sets is never a default" "$(bridge --read "$page")" '"\(.answers.money) \(.defaults | join(","))"' "false "
finish
