#!/bin/bash
source "$(dirname "$0")/../lib.sh"

a=$(fixture decision.html)
b=$(fixture plan.html)
mkdir -p "$CASE_DIR/other" && cp "$ROOT/harness/fixtures/plan.html" "$CASE_DIR/other/notes.html"
c="$CASE_DIR/other/notes.html"
repo
(cd "$CASE_DIR/other" && git init -q .)
(cd "$CASE_DIR/pages" && bridge decision.html && bridge plan.html)
wait_ready
(cd "$CASE_DIR/other" && bridge notes.html)
wait_ready

state=$(bridge --state)
check_json "most recent project first" "$state" '[.sidebar[].project] | join(",")' "other,pages"
check_json "newest bridge on top of its project" "$state" '.sidebar[1].bridges[0].title' "Plan: move the archive to static pages"
check_json "the presented bridge is selected" "$state" '.selected' "$c"
check_json "three rows, all unread" "$state" '[.sidebar[].bridges[] | select(.unread)] | length' "3"

state=$(bridge --do cross)
check_json "crossing marks the row" "$state" '.sidebar[0].bridges[0].crossed' "true"
check_json "crossed row text" "$state" '.sidebar[0].bridges[0].row' "Plan: move the archive to static pages · now · crossed"
snap crossed "notes crossed"
state=$(bridge --do uncross)
check_json "uncross brings it back" "$state" '.sidebar[0].bridges[0].crossed' "false"

bridge --cross "$a"
state=$(bridge --state)
check_json "CLI --cross works on any bridge" "$state" '[.sidebar[1].bridges[] | select(.crossed) | .title][0]' "Card layout for the archive"

# Presenting again revives it, moves it to the top and marks it unread
bridge --do select "$b" >/dev/null
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
state=$(bridge --state)
check_json "re-presenting uncrosses" "$state" '.sidebar[0].bridges[0].crossed' "false"
check_json "re-presenting moves the project up" "$state" '.sidebar[0].project' "pages"
check_json "re-presenting moves the bridge up" "$state" '.sidebar[0].bridges[0].title' "Card layout for the archive"
check_json "and marks it unread" "$state" '.sidebar[0].bridges[0].unread' "true"

# Closing the window means no, or not now
state=$(bridge --do close)
check_json "closing the window closes the selected bridge" "$(bridge --read "$a")" '.status' "closed"
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
check_json "presenting again reopens it" "$(bridge --read "$a")" '.status' "open"

bridge --remove "$b"
state=$(bridge --state)
check_json "remove takes it off the list" "$state" "[.sidebar[].bridges[].location] | index(\"$b\")" "null"

# Listing survives a restart
bridge --quit; sleep 0.3
(cd "$CASE_DIR/other" && bridge notes.html)
wait_ready
state=$(bridge --state)
check_json "list persisted across restart" "$state" '[.sidebar[].bridges[].title] | length' "2"

# A session whose cwd is its own scratchpad is in no repo, so the project used to be
# the last path component and bridges were filed under one called `scratchpad`.
# The project it came from is in the path, with every separator turned into a
# dash, which a dash in a directory name looks exactly like, so `test-alter`
# beside a real `test` decodes to a plausible wrong answer unless the walk is checked
# against the filesystem.
projects="$CASE_DIR/Work/Projects"
mkdir -p "$projects/Project-A" "$projects/test-alter" "$projects/test" "$projects/plain"
real=$(cd "$projects" && pwd -P)
# The scratchpad has to sit outside every repo, as a real one does: under the repo
# the git root answers first and the fallback is never reached.
scratch="${TMPDIR:-/tmp}/bridge-02-$$"
present_from() {
  local enc pad page="$CASE_DIR/other/notes.html"
  enc=$(printf '%s' "$1" | tr '/' '-')
  pad="$scratch/claude-501/$enc/$(uuidgen)/scratchpad"
  mkdir -p "$pad"
  (cd "$pad" && bridge "$page" >/dev/null 2>&1); settle 0.3
  # --state reports the project as the sidebar shows it: the name, not the path.
  bridge --state | jq -r --arg l "$page" '[.sidebar[] | select([.bridges[].location] | index($l)) | .project][0]'
}
check "a plain project name" "$(present_from "$real/plain")" "plain"
check "a project whose name has a dash in it" "$(present_from "$real/Project-A")" "Project-A"
check "a project with a dash whose sibling is its prefix" "$(present_from "$real/test-alter")" "test-alter"
# A folder that has since been deleted: nothing on disk confirms this one.
check "a project whose folder is gone is named, not guessed" "$(present_from "$real/gone-project")" "gone-project"
check "and never a project called scratchpad" "$(bridge --state | jq -r '[.sidebar[].project | select(. == "scratchpad")] | length')" "0"
rm -rf "$scratch"
finish
