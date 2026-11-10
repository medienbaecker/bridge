#!/bin/bash
# Sidecars in older record shapes open with answers, notes and version
# intact; one from a later build keeps what this build does not know; one this
# build cannot read is refused, never replaced.
source "$(dirname "$0")/../lib.sh"
map=$(fixture editor-map.html); fixture editor-map.html.bridge.json >/dev/null
mk() { cat > "$CASE_DIR/pages/$1.html" <<'HTML'
<!doctype html><html><head><title>Name</title></head><body>
<div data-record="name"><span>Name</span> <input type="text" value=""></div>
</body></html>
HTML
}
mk future; mk bare; mk broken
cat > "$CASE_DIR/pages/future.html.bridge.json" <<'JSON'
{"status":"open","version":1,"questions":["name"],"answers":{"name":"Ada"},"comments":[],"history":[],"future":{"kept":true},"mood":"blue"}
JSON
printf '%s' '{"answers":{"name":"Bare"}}' > "$CASE_DIR/pages/bare.html.bridge.json"
printf '%s' '{"status":"open","version":1,"answers":{"name":"Lost' > "$CASE_DIR/pages/broken.html.bridge.json"
repo
open_it() { (cd "$CASE_DIR/pages" && bridge "$1"); bridge --do select "$CASE_DIR/pages/$1" >/dev/null; wait_ready; settle 1.5; }

# The editor map repairs its own script on load ([NaN] -> [D2]) and saves it:
# the page's doing, so its script is not part of what opening must leave alone.
shape() { jq -c '{version, status, hist: (.history|length), notes: (.comments|length)}' "$(sidecar "$1")"; }
before=$(shape "$map"); open_it editor-map.html
check "an older shape with notes: version, history and notes untouched by opening" "$(shape "$map")" "$before"

open_it future.html
bridge --js "$CASE_DIR/pages/future.html" "const i = document.querySelector('input'); i.value = 'Grace'; i.dispatchEvent(new Event('input', {bubbles: true})); return 1" >/dev/null; settle 0.6
read=$(cat "$(sidecar "$CASE_DIR/pages/future.html")")
check_json "a field from a later build survives a save" "$read" '[.future.kept, .mood, .answers.name] | join(",")' "true,blue,Grace"

open_it bare.html
check_json "a sidecar with only answers restores them" "$(bridge --js "$CASE_DIR/pages/bare.html" "return document.querySelector('input').value")" '.' "Bare"

sum=$(shasum "$(sidecar "$CASE_DIR/pages/broken.html")" | cut -d' ' -f1)
open_it broken.html
check_json "a sidecar this build cannot read: the page says nothing will be saved" "$(bridge --state)" '.banner | test("Nothing here will be saved")' "true"
bridge --js "$CASE_DIR/pages/broken.html" "const i = document.querySelector('input'); i.value = 'Typed'; i.dispatchEvent(new Event('input', {bubbles: true})); return 1" >/dev/null; settle 0.6
out=$(bridge --read "$CASE_DIR/pages/broken.html" 2>&1); code=$?
check "--read and --done refuse with the reason" "$code $(printf '%s' "$out" | grep -c 'could not be read') $(bridge --done "$CASE_DIR/pages/broken.html" x >/dev/null 2>&1; echo $?)" "1 1 1"
check "typing into it and asking the CLI leave the file byte-identical" "$(shasum "$(sidecar "$CASE_DIR/pages/broken.html")" | cut -d' ' -f1)" "$sum"
finish
