#!/bin/bash
source "$(dirname "$0")/../lib.sh"
export BRIDGE_ENDED_AFTER=0
exe="$BRIDGE_DEV_APP/Contents/MacOS/$(ls "$BRIDGE_DEV_APP/Contents/MacOS" | head -1)"
long="Donaudampfschifffahrtsgesellschaftskapitänswitwenrentenantragsformular"
make() {  # <project dir> <file> <title>
  local p="$CASE_DIR/$1"
  mkdir -p "$p"
  printf '<!doctype html><html><head><title>%s</title></head><body><p>Lorem ipsum</p></body></html>' "$3" > "$p/$2"
  (cd "$p" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm f 2>/dev/null)
  (cd "$p" && bridge "$2" >/dev/null 2>&1); wait_ready
}
make "kunde-a/website" "a.html" "$long"
make "kunde-b/website" "b.html" "Lorem ipsum"
make "einzeln" "c.html" "Dolor sit amet"
(cd "$CASE_DIR/kunde-b/website" && claude_session "test-$CASE_NAME-agent" idle)
settle 0.4

bridge --do project all >/dev/null; settle 0.4
s=$(bridge --state)
check_json "two projects whose folders share a name are told apart by their parent" "$s" '[.projects.rows[].name | select(endswith("website"))] | sort | join(",")' "kunde-a/website,kunde-b/website"
check_json "a name that is alone stays short" "$s" '[.projects.rows[].name | select(. == "einzeln")] | length' "1"
check_json "a project row's tooltip is its full path" "$s" '[.projects.rows[] | select(.name == "kunde-a/website") | .toolTip] | first' "$CASE_DIR/kunde-a/website"
check_json "the smart scopes have none" "$s" '[.projects.rows[] | select(.key == "all") | .toolTip] | first' ""
check_json "the row subtitles carry the same names" "$s" '[.sidebar[].bridges[].subtitle | split(" · ")[0]] | sort | join(",")' "einzeln,kunde-a/website,kunde-b/website"
check_json "and so does the Send-to menu" "$s" '.agents | join(" | ")' "No page yet · kunde-b/website · idle"
check_json "a title too long for its row truncates with an ellipsis" "$s" '[.sidebarGeometry.rows[].truncates] | all' "true"
shot twins >/dev/null

bridge --do new >/dev/null; wait_ready; settle 0.3
draft=$(bridge --state | jq -r .selected)
bridge --do project all >/dev/null; settle 0.3
check_json "an unsent draft's subtitle is the scope's name" "$(bridge --state)" "[.sidebar[].bridges[] | select(.location == \"$draft\") | .subtitle] | first" "Drafts"

bridge --do project "project:$CASE_DIR/einzeln" >/dev/null; settle 0.3
bridge --cross "$CASE_DIR/einzeln/c.html" >/dev/null; settle 0.2
bridge --do crossed hide >/dev/null; settle 0.3
check_json "an empty list says how many crossed ones are hidden" "$(bridge --state)" '.listEmpty' "No bridges
1 crossed hidden"
shot hidden >/dev/null
bridge --do crossed show >/dev/null; settle 0.2

many="$CASE_DIR/viele"; mkdir -p "$many"
for i in $(seq 1 64); do printf '<!doctype html><title>%s %s</title><p>Lorem ipsum</p>' "$long" "$i" > "$many/p$i.html"; done
(cd "$many" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm f 2>/dev/null)
(cd "$many" && bridge $(seq -f 'p%g.html' 1 64) >/dev/null 2>&1); wait_ready; settle 0.5
bridge --do project all >/dev/null; settle 0.3
last=$(bridge --state | jq -r '.bridgesColumn[-2]')
first=$(bridge --state | jq -r '.bridgesColumn[0]')
bridge --do select "$last" >/dev/null; settle 0.4
check_json "a row selected by command, far down 68 rows, is scrolled into view" "$(bridge --state)" '[.selected == "'"$last"'", .sidebarGeometry.selectionVisible] | map(tostring) | join(",")' "true,true"
shot scrolled >/dev/null
bridge --do select "$first" >/dev/null; settle 0.4
check_json "and back up to the first" "$(bridge --state)" '.sidebarGeometry.selectionVisible' "true"
bridge --do select "$last" >/dev/null; settle 0.3
bridge --quit >/dev/null 2>&1; sleep 0.5; "$exe" >/dev/null 2>&1 & sleep 0.3; wait_ready; settle 1
check_json "restored at launch, the selected row is in view" "$(bridge --state)" '[.selected == "'"$last"'", .sidebarGeometry.selectionVisible] | map(tostring) | join(",")' "true,true"

bridge --do project "project:$CASE_DIR/kunde-a/website" >/dev/null; settle 0.3
bridge --do sidebar >/dev/null; settle 0.5
bridge --do resize "880 500" >/dev/null; settle 0.5
shot narrow >/dev/null
bridge --do listwidth 220 >/dev/null; settle 0.5
shot narrowest >/dev/null
finish
