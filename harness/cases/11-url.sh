#!/bin/bash
# A live site presented by URL: it loads over plain http, the runtime attaches
# (pins, notes), and a pin anchors to one of the site's own elements.
source "$(dirname "$0")/../lib.sh"

site="$CASE_DIR/site"; mkdir -p "$site"
cat > "$site/index.html" <<'HTML'
<!doctype html><html lang="de"><head><meta charset="utf-8"><title>Beispielseite für Umlaute</title>
<style>body{font-family:Georgia;margin:40px}a.more{color:#a33}</style></head>
<body><h1>Beispielseite für Umlaute</h1><p>Lorem ipsum mit Umlauten: äöü.</p><p><a class="more" href="/more">Link text</a></p></body></html>
HTML
port=$((20000 + RANDOM % 20000))
(cd "$site" && python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) &
server=$!
trap 'kill $server 2>/dev/null; bridge --quit >/dev/null 2>&1 || true' EXIT
sleep 0.5
url="http://127.0.0.1:$port/"
(cd "$CASE_DIR" && bridge "$url")
wait_ready
js() { bridge --js "$url" "$1"; }

check_json "the site loaded over http" "$(js "return location.href")" '.' "$url"
check_json "its title is the row title" "$(bridge --state)" '.title' "Beispielseite für Umlaute"
check_json "its own styles are untouched" "$(js "return getComputedStyle(document.body).fontFamily")" '.' "Georgia"
check_json "the page stylesheet was not injected into a site" "$(js "return getComputedStyle(document.body).maxWidth")" '.' "none"
check_json "point is available" "$(bridge --state)" '[.toolbar[] | select(.id=="point") | .enabled][0]' "false"
snap site "A live site by URL"

# Pins on a site: allowed through the page, even though the toolbar hides Point for URLs
js "@bridge __bridge.point(true); return 1" >/dev/null
js "const el = document.querySelector('a.more'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true, clientX: r.left + 5, clientY: r.top + 5}))" >/dev/null
settle
check_json "the pending note still names the site's element for an agent, though the composer does not show it" "$(js "@bridge return __bridgeNotes.pending?.target")" '. | startswith("a.")' "true"
js "const t = document.querySelector('.bridge-thread textarea'); t.value = 'zu klein'; t.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true}))" >/dev/null
settle 0.3
pins=$(bridge --pins "$url")
check_json "the note is recorded against the URL" "$pins" '.[0].target' 'a.more "Link text"'
check_json "and anchored" "$pins" '.[0].lost' "false"
snap pinned "A pin on a live site"
check "a site's record lives in the app's store, not on the site" "$(ls "$XDG_STATE_HOME/bridge-dev/answers" | wc -l | tr -d ' ')" "1"
finish
