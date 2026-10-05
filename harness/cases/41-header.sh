#!/bin/bash
# The middle column's header names the list (Waiting, All, or the project),
# and the document's title, with no icon, stands over the page column where
# the document is. The window's own title would have sat over the list. Positions
# from the frame's pixels as well as from the state.
source "$(dirname "$0")/../lib.sh"
mkdir -p "$CASE_DIR/pages/sample"
cp "$ROOT/harness/fixtures/editor-map.html" "$CASE_DIR/pages/sample/"
repo; (cd "$CASE_DIR/pages/sample" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm f)
(cd "$CASE_DIR/pages/sample" && bridge editor-map.html 2>"$CASE_DIR/present.err"); wait_ready; settle 0.5
check "presenting prints nothing but the page's own diagnostics" "$(grep -v '^bridge-dev: ' "$CASE_DIR/present.err")" ""
check_json "with nothing waiting at launch the column is All, and the header says so" "$(bridge --state)" '.listHeader' "All"
bridge --do project "project:$(cd "$CASE_DIR/pages/sample" && pwd -P)" >/dev/null; settle 0.4
state=$(bridge --state)
check_json "in a project the header is the project's name" "$state" '.listHeader' "sample"
check_json "the document over the page is the page's title alone, no icon before it" "$state" '.documentTitle' "Demo: script"
check_json "the header sits over the list column and the document over the page column" "$state" '(.listHeaderX > .columnWidths[0]) and (.listHeaderX < .columnWidths[0] + .columnWidths[1]) and (.documentTitleX >= .pageX)' "true"
r=$(shot header) || true
scale=$(printf '%s' "$state" | jq -r .backingScale); tb=$(printf '%s' "$state" | jq -r .titlebarHeight)
band() { python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/header.png" region $(awk -v v=$1 -v s=$scale 'BEGIN {print int(v * s)}') $(awk -v t=$tb -v s=$scale 'BEGIN {print int((t / 2 - 10) * s)}') $(awk -v v=$2 -v s=$scale 'BEGIN {print int(v * s)}') $(awk -v t=$tb -v s=$scale 'BEGIN {print int((t / 2 + 10) * s)}') | awk '{print ($2 > 6) ? "ink" : "blank"}'; }
hx=$(printf '%s' "$state" | jq -r .listHeaderX); dx=$(printf '%s' "$state" | jq -r .documentTitleX)
check "the header's words are drawn in the titlebar over the list, from pixels" "$(band $hx $(awk -v v=$hx 'BEGIN {print v + 30}'))" "ink"
check "the document's words are drawn over the page, from pixels" "$(band $dx $(awk -v v=$dx 'BEGIN {print v + 60}'))" "ink"
for scope in waiting all; do bridge --do project $scope >/dev/null; settle 0.3; check_json "in $scope the header says so" "$(bridge --state)" '.listHeader' "$(printf '%s' "$scope" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"; done
finish
