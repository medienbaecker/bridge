#!/bin/bash
# Only projects with open pages are listed; the rest are reached through the
# Earlier scope, which lists their pages. The project you are in always shows.
source "$(dirname "$0")/../lib.sh"
mk() { mkdir -p "$CASE_DIR/$1"; printf '<!doctype html><title>%s</title><p>x</p>' "$2" > "$CASE_DIR/$1/$3.html"; [ -d "$CASE_DIR/$1/.git" ] || (cd "$CASE_DIR/$1" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm x); }
mk Done-one "Old 1" o1; mk Done-two "Old 2" o2; mk Live "Live 1" l1
(cd "$CASE_DIR/Done-one" && bridge o1.html); (cd "$CASE_DIR/Done-two" && bridge o2.html); (cd "$CASE_DIR/Live" && bridge l1.html); wait_ready; settle 0.4
names() { bridge --state | jq -r '[.projects.rows[].name] | join(",")'; }
titles() { bridge --state | jq -r '[.bridgesColumn[] | split("/") | last] | join(",")'; }
check "with every page open, every project is listed and there is no Earlier" "$(names)" "Waiting,All,Live,Done-two,Done-one"
bridge --do project all >/dev/null
bridge --cross "$CASE_DIR/Done-one/o1.html" >/dev/null; bridge --cross "$CASE_DIR/Done-two/o2.html" >/dev/null; settle 0.4
check "projects with nothing open leave the column for an Earlier scope" "$(names)" "Waiting,All,Earlier,Live"
bridge --do project earlier >/dev/null; settle 0.3
check_json "Earlier is selectable" "$(bridge --state)" '.projects.scope' "earlier"
check "it lists their pages, newest first, crossed ones included" "$(titles)" "o2.html,o1.html"
bridge --shot "$CASE_DIR/shots/earlier.png" >/dev/null
bridge --do project "project:$(cd "$CASE_DIR/Done-one" && pwd -P)" >/dev/null; settle 0.3
check "the quiet project you are in still shows in the column" "$(names)" "Waiting,All,Earlier,Live,Done-one"
bridge --do project all >/dev/null; settle 0.3
check "and drops out once you leave" "$(names)" "Waiting,All,Earlier,Live"
(cd "$CASE_DIR/Done-one" && bridge o1.html); wait_ready; settle 0.4
check "a new page brings its project back up" "$(names)" "Waiting,All,Earlier,Done-one,Live"
bridge --cross "$CASE_DIR/Live/l1.html" >/dev/null; bridge --cross "$CASE_DIR/Done-two/o2.html" >/dev/null; (cd "$CASE_DIR/Done-two" && bridge o2.html); wait_ready; settle 0.4
check "Earlier holds only the quiet ones" "$(bridge --do project earlier >/dev/null; settle 0.3; titles)" "l1.html"
finish
