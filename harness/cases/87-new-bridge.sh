#!/bin/bash
source "$(dirname "$0")/../lib.sh"
export BRIDGE_ENDED_AFTER=0
work="test-$CASE_NAME-work"; other="test-$CASE_NAME-other"
printf '<!doctype html><title>Card layout for the archive</title><p>Lorem ipsum</p>' > "$CASE_DIR/pages/cards.html"
repo
(cd "$CASE_DIR/pages" && claude_session "$work" idle && claude_session "$other" busy)
(cd "$CASE_DIR/pages" && BRIDGE_SESSION="$work" bridge cards.html); wait_ready; settle 0.3
send_enabled() { bridge --state | jq -r '.toolbar[] | select(.id=="send") | .enabled'; }

bridge --do new >/dev/null; wait_ready; settle 0.3
draft=$(bridge --state | jq -r .selected)
js() { bridge --js "$draft" "$1"; }
check "New bridge opens a draft in Drafts" "$([[ "$draft" == "$XDG_STATE_HOME"/bridge-dev/drafts/*.html ]] && echo yes || echo "$draft")" "yes"
check_json "it is called New bridge until it has words" "$(bridge --state)" '.title' "New bridge"
check_json "the projects column has Drafts, selected" "$(bridge --state)" '.projects | [.scope, (.rows | map(.name) | index("Drafts") != null)] | @tsv' "project:$XDG_STATE_HOME/bridge-dev/drafts	true"
check "an empty draft cannot be sent" "$(send_enabled)" "false"
check_json "agents are named by their last page, in the order they started" "$(bridge --state)" '.agents | join(" | ")' "No page yet · pages · busy | Card layout for the archive · pages · idle"

long="Donaudampfschifffahrtsgesellschaftskapitänswitwenrentenantragsformular bitte prüfen"
js "const t = document.getElementById('text'); t.value = '$long\nLorem ipsum dolor sit amet.'; t.dispatchEvent(new Event('input', { bubbles: true }))" >/dev/null
for i in $(seq 1 40); do [ "$(bridge --state | jq -r .title)" = "$long" ] && break; sleep 0.1; done
check_json "its first line becomes its name" "$(bridge --state)" '.title' "$long"
check "with words it can be sent" "$(send_enabled)" "true"

cp "$HOME/Test/test-1.jpg" "$CASE_DIR/pages/photo.jpg"
bridge --do attach "$CASE_DIR/pages/photo.jpg" >/dev/null; settle 0.5
check_json "an attached file is recorded" "$(bridge --read "$draft")" '.answers.files | join(",")' "$CASE_DIR/pages/photo.jpg"
check_json "and listed on the draft with its picture" "$(js "return [...document.querySelectorAll('.draft-file img')].filter(i => i.naturalWidth > 0).length")" '.' "1"
bridge --do attach "$CASE_DIR/pages/photo.jpg" >/dev/null; settle 0.3
check_json "the same file twice is listed once" "$(bridge --read "$draft")" '.answers.files | length' "1"
js "document.querySelector('.draft-file button').click()" >/dev/null; settle 0.5
check "Remove takes it off again, the record and the page" "$(bridge --read "$draft" | jq -r '.answers.files // "none"') $(js "return document.querySelectorAll('.draft-file').length")" "none 0"
bridge --do attach "$CASE_DIR/pages/photo.jpg" >/dev/null; settle 0.3

bridge --do new >/dev/null; wait_ready; settle 0.3
second=$(bridge --state | jq -r .selected)
check "a draft with words is not reused" "$([ "$second" != "$draft" ] && echo new)" "new"
bridge --do new >/dev/null; settle 0.3
check_json "an empty draft is reused rather than another made" "$(bridge --state)" '.selected' "$second"
bridge --do cleanup >/dev/null; settle 0.3
check_json "an unsent draft survives the cleanup of ended sessions" "$(cat "$XDG_STATE_HOME/bridge-dev/list.json")" "[.bridges[] | select(.location == \"$draft\") | .crossed] | first" "false"
bridge --do select "$draft" >/dev/null; wait_ready; settle 0.3

bridge --do sendto "$other-missing" >/dev/null 2>&1
check "an agent that is not running cannot be picked" "$(inbox "$work" 5 | grep -c 'wrote you a bridge')" "0"
bridge --do sendto "$work" >/dev/null; settle 0.5
got=$(inbox "$work")
check "Send hands it to the picked agent" "$(printf '%s' "$got" | grep -c 'Bridge: The user wrote you a bridge')" "1"
check "with the words" "$(printf '%s' "$got" | grep -c 'Donaudampfschifffahrts')" "1"
check "and the attached file" "$(printf '%s' "$got" | grep -c "$CASE_DIR/pages/photo.jpg")" "1"
check_json "it is sent" "$(bridge --read "$draft")" '.status' "sent"
check_json "and moves out of Drafts into the agent's project" "$(cat "$XDG_STATE_HOME/bridge-dev/list.json")" "[.bridges[] | select(.location == \"$draft\") | .project] | first" "$CASE_DIR/pages"
finish
