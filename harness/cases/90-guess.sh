#!/bin/bash
source "$(dirname "$0")/../lib.sh"
# serial
alpha="test-$CASE_NAME-alpha"
beta="test-$CASE_NAME-beta"
for d in alpha beta; do mkdir -p "$CASE_DIR/$d"; git -C "$CASE_DIR/$d" init -q; done
page="$CASE_DIR/alpha/plan.html"
write() { printf '<!doctype html><title>%s</title><h2 style="margin:40px">Abschnitt IX</h2>' "$1" > "$page"; }
write "Lorem ipsum"
(cd "$CASE_DIR/alpha" && claude_session "$alpha" idle)
(cd "$CASE_DIR/beta" && claude_session "$beta" idle)
(cd "$CASE_DIR/alpha" && BRIDGE_SESSION="$alpha" bridge plan.html); wait_ready; settle 0.3
js() { bridge --js "$page" "$1"; }
note() { bridge --do freeze-mark "$1" >/dev/null; settle 0.3; bridge --do freeze-note "$2" >/dev/null; settle 0.5; }
picked() { bridge --state | jq -r '.freeze.picked'; }
toolbar() { bridge --state | jq -r '.freeze.screenFrame as $s | "\(.windowFrame.x - $s[0] + .windowFrame.width - 140) \(($s[1] + $s[3]) - (.windowFrame.y + .windowFrame.height) + 26)"'; }
chips() { bridge --js "$XDG_STATE_HOME/bridge-dev/freeze/screen.html" "@bridge return [...document.querySelectorAll('.bridge-agents-list button')].map((b) => (b.hasAttribute('data-picked') ? '*' : '') + b.querySelector('small').textContent).join(' | ')" | jq -r .; }

bridge --do freeze >/dev/null; settle 1
check "opened outside Bridge, no agent is picked" "$(picked)" "null"
note "$(freeze_at "$(js "const r = document.querySelector('h2').getBoundingClientRect(); return (r.left + 20) + ' ' + (r.top + r.height / 2)" | jq -r .)")" "Lorem"
check "a pin on a Bridge page picks the agent of that page" "$(picked) $(chips)" "$alpha *alpha | beta"
bridge --do freeze-cancel >/dev/null; settle 0.3

bridge --do freeze >/dev/null; settle 1
note "$(toolbar)" "Dolor"
check "a window Bridge knows nothing about picks no one" "$(picked)" "null"
bridge --do freeze-send 0 >/dev/null
for i in $(seq 1 30); do [ "$(inbox "$alpha" | grep -c 'sent you notes')" = 1 ] && break; settle 0.1; done
check "sent to an agent by hand" "$(inbox "$alpha" | grep -c 'sent you notes')" "1"

bridge --do freeze >/dev/null; settle 1
note "$(toolbar)" "Sit amet"
check "next time, a pin on the same app picks the agent it went to last" "$(picked) $(chips)" "$alpha *alpha | beta"
note "$(freeze_at "200 200")" "Consectetur"
check "a later pin elsewhere doesn't change the pick" "$(picked)" "$alpha"
bridge --do freeze-cancel >/dev/null; settle 0.3

printf '<!doctype html><title>Plan for beta</title><p>Lorem ipsum</p>' > "$CASE_DIR/beta/plan.html"
(cd "$CASE_DIR/beta" && BRIDGE_SESSION="$beta" bridge plan.html); wait_ready; settle 0.3
bridge --do select "$CASE_DIR/beta/plan.html" >/dev/null; wait_ready; settle 0.3
bridge --do freeze >/dev/null; settle 1
bridge --do freeze-mark "$(toolbar)" >/dev/null; settle 0.5
check "a window whose title names a project picks its agent as soon as you click, before what was sent last" "$(picked) $(chips)" "$beta alpha | *beta"
bridge --do freeze-note "Lorem" >/dev/null; settle 0.5
bridge --do freeze-cancel >/dev/null; settle 0.3

finish
