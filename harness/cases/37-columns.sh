#!/bin/bash
# Three columns: projects on the left with Waiting and All above them, the
# bridges of the selection in the middle, the page on the right. Selection
# flows left to right, crossed bridges sit at the foot and hide on request, a
# relaunch comes back to the same column and bridge, and at the narrowest
# sidebar the projects' names are whole, read from pixels.
source "$(dirname "$0")/../lib.sh"
# Each project is its own repo: the harness's out dir lies inside this repo, and a
# folder without one would be grouped under the repo's root.
mk() { mkdir -p "$CASE_DIR/$1"; printf '<!doctype html><title>%s</title><fieldset class="options"><div><input type="radio" name="w" id="a" value="x" data-record="k"><label for="a">x</label></div></fieldset>' "$2" > "$CASE_DIR/$1/$3.html"; [ -d "$CASE_DIR/$1/.git" ] || (cd "$CASE_DIR/$1" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm x); }
mk Sampleproject "Sample 1" k1; mk Sampleproject "Sample 2" k2; mk inbox "Inbox 1" i1
(cd "$CASE_DIR/Sampleproject" && bridge k1.html && bridge k2.html); (cd "$CASE_DIR/inbox" && bridge i1.html); wait_ready; settle 0.5
state=$(bridge --state)
check_json "Waiting and All head the projects column, then the projects, newest first" "$state" '[.projects.rows[].name] | join(",")' "Waiting,All,inbox,Sampleproject"
check_json "counts: three waiting, three in all, one and two in the projects" "$state" '[.projects.rows[].count] | join(",")' "3,3,1,2"
check_json "a fresh launch had nothing waiting, so the column was All; presents stayed in it" "$state" '.projects.scope' "all"
bridge --do project "$(printf '%s' "$state" | jq -r '.projects.rows[3].key')" >/dev/null; settle 0.3
check_json "selecting a project shows only its bridges, newest first" "$(bridge --state)" '[.bridgesColumn[] | split("/") | last] | join(",")' "k2.html,k1.html"
check_json "the selected bridge, out of that project, gave way to the project's first" "$(bridge --state)" '.selected | endswith("k2.html")' "true"
bridge --js "$CASE_DIR/Sampleproject/k2.html" "document.querySelector('#a').click(); return 1" >/dev/null; settle 0.3; bridge --do send >/dev/null; settle 0.3
bridge --do project waiting >/dev/null; settle 0.3
check_json "Waiting excludes the sent one" "$(bridge --state)" '[.bridgesColumn[] | split("/") | last] | join(",")' "i1.html,k1.html"
bridge --do project all >/dev/null; settle 0.3
bridge --cross "$CASE_DIR/inbox/i1.html" >/dev/null; settle 0.4
check_json "crossed, it sits at the foot of All, still shown" "$(bridge --state)" '[.bridgesColumn[] | split("/") | last] | join(",")' "k2.html,k1.html,i1.html"
check_json "and All counts only the live ones" "$(bridge --state)" '[.projects.rows[] | select(.key == "all") | .count][0]' "2"
bridge --do crossed hide >/dev/null; settle 0.3
check_json "hidden on request" "$(bridge --state)" '(.crossedShown | not) and ([.bridgesColumn[] | split("/") | last] | join(",") == "k2.html,k1.html")' "true"
bridge --do crossed show >/dev/null; settle 0.3
bridge --do select "$CASE_DIR/Sampleproject/k1.html" >/dev/null; settle 0.3
echo "  debug before relaunch: selected=$(bridge --state | jq -r '.selected | split("/") | last') ui=$(cat "$XDG_STATE_HOME/bridge-dev/ui.json" 2>/dev/null | jq -c '{selected: (.selected | split("/") | last), scope}')" >&2
exe="$BRIDGE_DEV_APP/Contents/MacOS/$(ls "$BRIDGE_DEV_APP/Contents/MacOS" | head -1)"
bridge --quit >/dev/null 2>&1; sleep 0.5; "$exe" >/dev/null 2>&1 & sleep 0.3; wait_ready; settle 0.8
check_json "a relaunch comes back to the same column and bridge" "$(bridge --state)" '.projects.scope + " " + (.selected | split("/") | last)' "all k1.html"
mk drafts "Draft 1" d1; (cd "$CASE_DIR/drafts" && bridge d1.html); wait_ready; settle 0.4
check_json "a bridge presented into a project All shows stays in All and heads it" "$(bridge --state)" '(.projects.scope == "all") and (.bridgesColumn[0] | endswith("d1.html"))' "true"
bridge --do project "$(bridge --state | jq -r '[.projects.rows[] | select(.name == "inbox") | .key][0]')" >/dev/null; settle 0.3
mk drafts "Draft 2" d2; (cd "$CASE_DIR/drafts" && bridge d2.html); wait_ready; settle 0.4
check_json "presented into a project the column does not show, the column moves to it" "$(bridge --state)" '(.projects.scope | endswith("/drafts")) and (.bridgesColumn[0] | endswith("d2.html"))' "true"
# At the narrowest sidebar, the longest project name is whole: its ink ends inside the column.
bridge --do sidebarwidth 180 >/dev/null; settle 0.5
r=$(shot narrow) || true
state=$(bridge --state); scale=$(printf '%s' "$state" | jq -r '.backingScale'); tb=$(printf '%s' "$state" | jq -r '(.titlebarHeight * .backingScale) | floor')
# The Sampleproject row's middle, from where the column says it drew it.
y=$(printf '%s' "$state" | jq -r '[.projects.rows[] | select(.name == "Sampleproject")][0] | ((.top + .height / 2) * '"$scale"') | floor')
ink=$(python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/narrow.png" "$y" 1 | awk -v lim=$((180 * 2)) '$1 < lim && $3 + $4 + $5 < 400 {last = $2} END {print last / 2}')
check "the longest project name ends inside a 180 pt sidebar (ink to $ink pt)" "$(printf '%s' "$ink" | awk '{print ($1 > 60 && $1 <= 170) ? "whole" : "cut"}')" "whole"
snap columns "Three columns at the narrowest sidebar"
finish
