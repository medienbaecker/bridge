#!/bin/bash
# A live site presented by URL: it loads over plain http and keeps its own styles.
source "$(dirname "$0")/../lib.sh"
# serial

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
check_json "its own styles are untouched, no page stylesheet injected" "$(js "const s = getComputedStyle(document.body); return s.fontFamily + ' ' + s.maxWidth")" '.' "Georgia none"
snap site "A live site by URL"

finish
