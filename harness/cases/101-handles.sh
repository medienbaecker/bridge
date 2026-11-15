#!/bin/bash
source "$(dirname "$0")/../lib.sh"
ulimit -Sn 256

count=70
for i in $(seq 1 $count); do
  printf '<!doctype html><title>Page %s</title><h1>Page %s</h1><fieldset class="options"><div><input type="radio" name="w" id="a" value="x" data-record="k"><label for="a">x</label></div></fieldset>' "$i" "$i" > "$CASE_DIR/pages/p$i.html"
done
repo
present() { (cd "$CASE_DIR/pages" && bridge "p$1.html") >/dev/null 2>&1; }

for i in $(seq 1 10); do present "$i" || break; done
wait_ready
early=$(bridge --state | jq '.handles')
first=$(bridge --state | jq -r '.webProcesses | join(" ")')
for i in $(seq 11 $count); do present "$i" || break; done
state=$(bridge --state)
late=$(printf '%s' "$state" | jq '.handles')

check_json "after $count presents the app still answers" "$state" '.running' "true"
check_json "and lists every one" "$state" '[.sidebar[].bridges[]] | length' "$count"
check_json "it may hold more file handles than the 256 it was started with" "$state" '.handleLimit > 256' "true"
check "and holds no more than after 10" "$([ "${early:-0}" -gt 0 ] && [ "${late:-0}" -gt 0 ] && [ "$late" -le $((early + 5)) ] && echo flat || echo "$early then $late")" "flat"
check_json "the page on show is loaded" "$state" '.selected as $shown | .ready and (.loadedPages | index($shown) != null)' "true"
check_json "with at most five more behind it" "$state" '.loadedPages | length | . >= 1 and . <= 6' "true"
running() { local n=0 pid; for pid in $1; do ps -p "$pid" >/dev/null 2>&1 && n=$((n + 1)); done; echo "$n"; }
kept=$(printf '%s' "$state" | jq -r '.webProcesses | join(" ")')
check "the loaded pages' web content processes run" "$(running "$kept")" "$(printf '%s' "$state" | jq '.loadedPages | length')"
closed=$(for pid in $first; do [[ " $kept " == *" $pid "* ]] || echo "$pid"; done)
check "the first ten had processes of their own" "$([ "$(echo $closed | wc -w)" -ge 4 ] && echo yes || echo "only: $closed")" "yes"
check "and those of the closed pages are gone" "$(running "$closed")" "0"

calls() { bridge --state | jq '.watcherCalls'; }
before=$(calls)
echo "a note" > "$CASE_DIR/pages/unrelated.txt"; settle 0.6
check "a file no page shows wakes no watcher" "$(( $(calls) - before ))" "0"
sed -i '' 's/<h1>Page 1</<h1>Page one</' "$CASE_DIR/pages/p1.html"; settle 0.6
check "the file of the page on show wakes its own" "$([ "$(calls)" -gt "$before" ] && echo woke || echo slept)" "woke"
check "and the page shows the change" "$(bridge --js "$CASE_DIR/pages/p1.html" "return document.querySelector('h1').textContent")" '"Page one"'
finish
