#!/bin/bash
# The skill is the fixture: every html sample in pages.md is a page the
# harness lints, presents, drives and reads back, so a promise cannot exist
# without a test. Each sample: lint has no error, presenting prints nothing
# on stderr (no unknown or colliding class on the live DOM), the page becomes
# ready, and every data-record key it declares records when its control is
# driven the way its kind is driven. A key no driver knows is named, not hidden.
source "$(dirname "$0")/../lib.sh"
python3 - "$ROOT/skills/bridge/pages.md" "$CASE_DIR/pages" <<'PY'
import re, sys, pathlib
md, out = pathlib.Path(sys.argv[1]).read_text(), pathlib.Path(sys.argv[2])
for i, b in enumerate(re.findall(r'```html\n(.*?)```', md, re.S)):
    title = re.search(r'<title>([^<]*)</title>', b)
    page = b if b.lstrip().startswith('<!doctype') else f'<!doctype html><html><head><title>Sample {i}</title></head><body>\n{b}\n</body></html>\n'
    (out / f'sample-{i:02d}.html').write_text(page)
PY
repo
n=$(ls "$CASE_DIR/pages"/sample-*.html | wc -l | tr -d ' ')
check "pages.md has html samples to test" "$([ "$n" -ge 10 ] && echo many)" "many"
driver=$(cat "$ROOT/harness/cases/46-driver.js")
for page in "$CASE_DIR/pages"/sample-*.html; do
  name=$(basename "$page" .html)
  errors=$(bridge --lint "$page" | grep -c ': error: ')
  check "$name: lint has no error ($(bridge --lint "$page" | grep ': error: ' | head -1 | cut -d: -f3- | cut -c1-90))" "$errors" "0"
  (cd "$CASE_DIR/pages" && bridge "$(basename "$page")" 2> "$CASE_DIR/$name.err"); wait_ready; settle 0.6
  check "$name: presenting prints nothing on stderr" "$(grep -v WARNING "$CASE_DIR/$name.err" | cut -c1-120)" ""
  driven=$(bridge --js "$page" "$driver")
  keys=$(printf '%s' "$driven" | jq -r '.keys | join(",")'); undriven=$(printf '%s' "$driven" | jq -r '.undriven | join(",")')
  if [ -n "$keys" ]; then
    settle 0.6
    got=$(bridge --read "$page" | jq -r '[.answers | keys[]] | sort | join(",")')
    check "$name: every key it declares records when driven ($keys)" "$got" "$keys"
    check "$name: no key without a driver" "$undriven" ""
  fi
  bridge --remove "$page" >/dev/null 2>&1
done
finish
