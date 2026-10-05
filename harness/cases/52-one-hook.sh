#!/bin/bash
# Every turn that ends starts another Stop hook; the earlier ones must not keep
# waiting beside it, or a long session piles up hooks and their memory. The
# memory each one gained is not reproducible here: it came from resolving the
# home directory when XDG_STATE_HOME is unset, and every case sets it.
source "$(dirname "$0")/../lib.sh"
CLI="$ROOT/build.noindex/bridge-dev"
S="test-52-one-hook"

printf '<!doctype html><title>p</title><h1>p</h1>' > "$CASE_DIR/pages/p.html"
repo
python3 - "$XDG_STATE_HOME/bridge-dev" "$CASE_DIR/pages" "$S" <<'PY'
import json, os, sys
state, pages, session = sys.argv[1:]
os.makedirs(state, exist_ok=True)
json.dump({"bridges": [{"id": "000000000001", "kind": "html", "location": f"{pages}/p.html", "project": pages, "session": session,
           "presentedAt": "2026-09-28T10:00:00Z", "title": "p", "crossed": False, "unread": False}]}, open(f"{state}/list.json", "w"))
PY

hook() { (cd "$CASE_DIR/pages" && printf '{"session_id":"%s"}' "$S" | "$CLI" --hook stop --timeout 120 >/dev/null 2>&1) & }

hook; first=$!
settle 3
check_json "the hook waits, registered" "$("$CLI" --waiters)" 'length' "1"
hp=$("$CLI" --waiters | jq -r '.[0].pid')

# A second turn ends: the newer hook does the whole job and the older one steps aside.
hook
settle 2
check_json "a newer hook for the same session leaves one waiting" "$("$CLI" --waiters)" 'length' "1"
check "and it is the newer one" "$("$CLI" --waiters | jq -r '.[0].pid == '"$hp"' | not')" "true"
check "the older one has exited" "$(kill -0 "$hp" 2>/dev/null && echo running || echo gone)" "gone"
"$CLI" --waiters | jq -r '.[].pid' | xargs kill 2>/dev/null
finish
