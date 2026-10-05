#!/bin/bash
# Sidecars in older record shapes open with answers, notes and version
# intact; one from a later build keeps what this build does not know; one this
# build cannot read is refused, never replaced.
source "$(dirname "$0")/../lib.sh"
map=$(fixture editor-map.html); fixture editor-map.html.bridge.json >/dev/null
four=$(fixture editor-columns.html); fixture editor-columns.html.bridge.json >/dev/null
script=$(fixture editor-script.html); fixture editor-script.html.bridge.json >/dev/null
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
sig() { jq -c '{version, fingerprint, status, hist: (.history|length), notes: (.comments|length), script: (.answers.script|length)}' "$(sidecar "$1")"; }
loose() { jq -c '{version, status, hist: (.history|length), notes: (.comments|length), script: (.answers.script|length)}' "$(sidecar "$1")"; }
open_it() { (cd "$CASE_DIR/pages" && bridge "$1"); wait_ready; settle 1.5; }
exe="$BRIDGE_DEV_APP/Contents/MacOS/$(ls "$BRIDGE_DEV_APP/Contents/MacOS" | head -1)"
relaunch() { bridge --quit >/dev/null 2>&1; sleep 0.5; "$exe" >/dev/null 2>&1 & sleep 0.3; wait_ready; settle 2; }

# The older-shape pages record through the API too, so the first open under this
# build adopts their fingerprint (their keys become questions) without a version.
# The editor map also repairs its own script on load ([NaN] -> [D2]) and saves it:
# the page's doing, so its script is not part of what opening must leave alone.
loosest() { jq -c '{version, status, hist: (.history|length), notes: (.comments|length)}' "$(sidecar "$1")"; }
before=$(loosest "$map"); open_it editor-map.html
check "an older shape with notes: version, history and notes untouched by opening" "$(loosest "$map")" "$before"
check_json "its keys are its questions now, still version 1" "$(cat "$(sidecar "$map")")" '(.questions | join(",")) + " v" + (.version|tostring)' "items-in-order,script v1"
before=$(loose "$four"); open_it editor-columns.html
check "an older shape without notes opens unchanged" "$(loose "$four")" "$before"
before=$(sig "$script"); open_it editor-script.html; settle 1.5
check "a pre-API shape opens unchanged, fingerprint included" "$(sig "$script")" "$before"
adopted=$(sig "$map"); relaunch
check "relaunched, the adopted older shape is left alone" "$(sig "$map")" "$adopted"
check "and so is the pre-API one" "$(sig "$script")" "$before"

open_it future.html
check_json "a field from a later build is still there after the first save" "$(cat "$(sidecar "$CASE_DIR/pages/future.html")")" '.future.kept' "true"
bridge --js "$CASE_DIR/pages/future.html" "const i = document.querySelector('input'); i.value = 'Grace'; i.dispatchEvent(new Event('input', {bubbles: true})); return 1" >/dev/null; settle 0.6
read=$(cat "$(sidecar "$CASE_DIR/pages/future.html")")
check_json "recording keeps it too" "$read" '[.future.kept, .mood, .answers.name] | join(",")' "true,blue,Grace"

open_it bare.html
check_json "a sidecar with only answers restores them" "$(bridge --js "$CASE_DIR/pages/bare.html" "return document.querySelector('input').value")" '.' "Bare"
check_json "and reads as version 1, open" "$(bridge --read "$CASE_DIR/pages/bare.html")" '(.version|tostring) + " " + .status' "1 open"

sum=$(shasum "$(sidecar "$CASE_DIR/pages/broken.html")" | cut -d' ' -f1)
open_it broken.html
check_json "a sidecar this build cannot read: the page says nothing will be saved" "$(bridge --state)" '.banner | test("Nothing here will be saved")' "true"
bridge --js "$CASE_DIR/pages/broken.html" "const i = document.querySelector('input'); i.value = 'Typed'; i.dispatchEvent(new Event('input', {bubbles: true})); return 1" >/dev/null; settle 0.6
check "typing into it leaves the file byte-identical" "$(shasum "$(sidecar "$CASE_DIR/pages/broken.html")" | cut -d' ' -f1)" "$sum"
out=$(bridge --read "$CASE_DIR/pages/broken.html" 2>&1); code=$?
check "--read refuses with the reason" "$code $(printf '%s' "$out" | grep -c 'could not be read')" "1 1"
check "--reply refuses too" "$(bridge --reply "$CASE_DIR/pages/broken.html" x "hi" >/dev/null 2>&1; echo $?)" "1"
check "still byte-identical" "$(shasum "$(sidecar "$CASE_DIR/pages/broken.html")" | cut -d' ' -f1)" "$sum"
finish
