#!/bin/bash
source "$(dirname "$0")/../lib.sh"

check "a Mac's person defaults to a plain lowercase name" "$(bridge --name | grep -cE '^[a-z0-9-]+$')" "1"
check "setting a name folds it" "$(bridge --name 'Yoshie Ö')" "yoshieo"
check "and it is kept" "$(bridge --name)" "yoshieo"
check "a name with nothing usable is refused" "$(bridge --name '!!' 2>&1 >/dev/null)" "a name needs at least one letter or digit"

page=$(fixture decision.html)
sidecar=$(bridge --sidecar "$page")
mkdir -p "$(dirname "$sidecar")"
cat > "$sidecar" <<JSON
{ "status": "open", "version": 1, "answers": { "layout": "grid" },
  "people": { "thomas": { "layout": "grid" }, "yoshie": { "layout": "list" } },
  "comments": [ { "id": "n1", "text": "too tall", "target": "h1", "state": "open", "at": "2026-10-17T10:00:00Z",
                  "version": 1, "anchor": null, "person": "yoshie",
                  "said": [ { "by": "agent", "at": "2026-10-17T10:01:00Z", "text": "shortened", "kind": "reply", "person": "thomas" } ] } ],
  "history": [] }
JSON
read=$(bridge --read "$page")
check_json "answers stay this Mac's" "$read" '.answers.layout' "grid"
check_json "people carry everyone's picks" "$read" '.people.yoshie.layout' "list"
check_json "a note says who wrote it" "$read" '.comments[0].person' "yoshie"
check_json "a reply says whose agent wrote it" "$read" '.comments[0].said[0].person' "thomas"
check_json "pins say it too" "$(bridge --pins "$page")" '.[0].person' "yoshie"

rm "$sidecar"
check_json "an unshared page has no people" "$(bridge --read "$page")" '.people' "null"
finish
