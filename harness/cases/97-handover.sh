#!/bin/bash
source "$(dirname "$0")/../lib.sh"
# serial
alpha="test-$CASE_NAME-alpha"
beta="test-$CASE_NAME-beta"
for d in alpha beta; do mkdir -p "$CASE_DIR/$d"; git -C "$CASE_DIR/$d" init -q; done
page="$CASE_DIR/alpha/plan.html"
printf '<!doctype html><title>Lorem ipsum</title><h2 style="margin:40px">Abschnitt IX</h2>' > "$page"
(cd "$CASE_DIR/alpha" && claude_session "$alpha" idle)
(cd "$CASE_DIR/beta" && claude_session "$beta" idle)
(cd "$CASE_DIR/alpha" && BRIDGE_SESSION="$alpha" bridge plan.html); wait_ready; settle 0.3
screen="$XDG_STATE_HOME/bridge-dev/freeze/screen.html"
drafts="$XDG_STATE_HOME/bridge-dev/drafts"
on_screen() { bridge --js "$screen" "@bridge $1"; }
note() { bridge --do freeze-mark "$1" >/dev/null; settle 0.3; bridge --do freeze-note "$2" >/dev/null; settle 0.5; }
draft_count() { jq '[.bridges[] | select(.location | contains("/drafts/"))] | length' "$XDG_STATE_HOME/bridge-dev/list.json"; }

lower=$(printf '%s' "$page" | tr '[:upper:]' '[:lower:]')
check "select finds a page whatever the path's case" "$(bridge --do select "$lower" | jq -r .selected)" "$page"

bridge --do freeze >/dev/null; settle 1
bridge --do freeze-mark "200 200" >/dev/null; settle 0.3
on_screen "const box = document.querySelector('.bridge-composer:popover-open textarea'); box.value = 'Lorem ipsum'; box.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', metaKey: true, bubbles: true }))" >/dev/null; settle 0.1
check "⌘↩ with no agent picked saves the note, stays open and shakes the agents" "$(on_screen "return [document.querySelectorAll('.bridge-pin').length, document.querySelector('.bridge-agents-list').getAnimations().length > 0].join()" | jq -r .) $(bridge --state | jq '.freeze != null')" "1,true true"

mkdir -p "$drafts"
touch -t 202601010000 "$drafts/2026-01-01-000000.1.png"
touch "$drafts/2026-11-01-000000.1.png"
bridge --do freeze-send 0 >/dev/null
bridge --do freeze >/dev/null; settle 1
check "reopened at once, the notes still reach the agent" "$(inbox "$alpha" | grep -c '^1\. "Lorem ipsum"')" "1"
check "and a note with nothing named under it has no empty \"on\"" "$(inbox "$alpha" | grep -c ' on \.')" "0"
check "the new pin mode starts empty" "$(on_screen "return document.querySelectorAll('.bridge-pin').length" | jq -r .)" "0"
check "a picture older than a week that nothing uses is swept, a newer one stays" "$(ls "$drafts" | grep -c '^2026-01-01') $(ls "$drafts" | grep -c '^2026-11-01')" "0 1"

rm -f "/tmp/bh-$$-$beta.sock"
before=$(draft_count)
note "200 200" "Dolor sit"
bridge --do freeze-send 1 >/dev/null; settle 1.5
check "notes for an agent that cannot be reached become a draft" "$(draft_count) $(inbox "$beta" 5 | grep -c 'Dolor sit')" "$((before + 1)) 0"

bridge --do select "$page" >/dev/null
bridge --do window >/dev/null; settle 0.5
bridge --do close >/dev/null; settle 0.3
check "closing the main window leaves a page open in its own window unanswered" "$(bridge --read "$page" | jq -r .status)" "open"

finish
