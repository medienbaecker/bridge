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

bridge --do cross >/dev/null
snap crossed "notes crossed"
state=$(bridge --do uncross)
check_json "uncross brings it back" "$state" '.sidebar[0].bridges[0].crossed' "false"

bridge --cross "$a"
bridge --do select "$b" >/dev/null
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
state=$(bridge --state)
check_json "re-presenting uncrosses" "$state" '.sidebar[0].bridges[0].crossed' "false"
check_json "re-presenting moves the bridge and its project up" "$state" '.sidebar[0].project + " / " + .sidebar[0].bridges[0].title' "pages / Card layout for the archive"
check_json "and marks it unread" "$state" '.sidebar[0].bridges[0].unread' "true"

bridge --do close >/dev/null
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
check_json "presenting again reopens it" "$(bridge --read "$a")" '.status' "open"

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
rm -rf "$scratch"

dir=$(mktemp -d /tmp/bridge-remove.XXXXXX)
printf '<!doctype html><title>Remove</title><p>x</p>' > "$dir/page.html"
(cd "$dir" && bridge page.html); wait_ready
mv "$dir/page.html" "$dir/renamed.html"
listed() { bridge --state | jq -r --arg l "$1" '[.. | strings | select(. == $l)] | length > 0'; }
bridge --remove "/private$dir/page.html"; settle 0.3
check "removed through /private/tmp after the file is gone" "$(listed "$dir/page.html")" "false"
check "removing it again fails and says why" "$(bridge --remove "$dir/page.html" 2>&1; echo " exit $?")" "not in the list: $dir/page.html
 exit 1"
rm -rf "$dir"
bridge --quit >/dev/null 2>&1; sleep 0.5
check "with the app not running, it fails the same way" "$(bridge --remove "$dir/page.html" 2>&1; echo " exit $?")" "not in the list: $dir/page.html
 exit 1"
finish
