#!/bin/bash
# Where links open. A URL bridge keeps same-host links and hands other hosts to
# the browser; --links window and --links browser change that, and the mode
# survives a relaunch. An iframe follows its data-links, external by default.
# A target=_blank link always goes to the browser. In test mode the app records
# what it would open instead of opening it.
source "$(dirname "$0")/../lib.sh"

free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
one=$(free_port); two=$(free_port)
site="$CASE_DIR/site"; mkdir -p "$site"
cat > "$site/index.html" <<HTML
<!doctype html><html><head><meta charset="utf-8"><title>Start</title></head><body>
<a class="same" href="/next.html">Same host</a>
<a class="other" href="http://127.0.0.1:$two/next.html">Other host</a>
<a class="blank" href="/next.html" target="_blank">New window</a>
<a class="anchor" href="#end">Further down</a><p id="end">End</p>
</body></html>
HTML
echo '<!doctype html><html><head><title>Next</title></head><body><p>Next</p></body></html>' > "$site/next.html"
(cd "$site" && python3 -m http.server "$one" --bind 127.0.0.1 >/dev/null 2>&1) &
s1=$!
(cd "$site" && python3 -m http.server "$two" --bind 127.0.0.1 >/dev/null 2>&1) &
s2=$!
trap 'kill $s1 $s2 2>/dev/null; bridge --quit >/dev/null 2>&1 || true' EXIT
sleep 0.5
url="http://127.0.0.1:$one/"
next="http://127.0.0.1:$one/next.html"
other="http://127.0.0.1:$two/next.html"
js() { bridge --js "$url" "$1"; }
click() { js "document.querySelector('$1').click(); return 1" >/dev/null; settle 0.6; }
home() { js "location.href = '$url'; return 1" >/dev/null; settle 0.6; }
opened() { bridge --state | jq -c '.openedExternally'; }

(cd "$CASE_DIR" && bridge "$url")
wait_ready
check_json "a URL bridge defaults to external" "$(bridge --state)" '.links' "external"
click a.other
check_json "external: a link to another host leaves the page alone" "$(js "return location.href")" '.' "$url"
check "and is handed to the browser" "$(opened)" "[\"$other\"]"
click a.blank
check_json "a target=_blank link leaves the page alone" "$(js "return location.href")" '.' "$url"
check "and is handed to the browser" "$(opened)" "[\"$other\",\"$next\"]"
click a.same
check_json "external: a same-host link navigates in Bridge" "$(js "return location.href")" '.' "$next"
check "and opens nothing" "$(opened | jq length)" "2"

(cd "$CASE_DIR" && bridge --links window "$url")
check_json "--links window is the page's mode" "$(bridge --state)" '.links' "window"
home
click a.other
check_json "window: a link to another host navigates in Bridge" "$(bridge --js "$url" "return location.href")" '.' "$other"
check "and opens nothing" "$(opened | jq length)" "2"

exe="$BRIDGE_DEV_APP/Contents/MacOS/$(ls "$BRIDGE_DEV_APP/Contents/MacOS" | head -1)"
bridge --quit >/dev/null 2>&1; sleep 0.5; "$exe" >/dev/null 2>&1 & sleep 0.3; wait_ready
check_json "the mode survives a relaunch" "$(bridge --state)" '.links' "window"

(cd "$CASE_DIR" && bridge --links browser "$url")
wait_ready
home
click a.anchor
check_json "browser: an in-page anchor still moves within the page" "$(js "return location.href")" '.' "${url}#end"
click a.same
check_json "browser: a same-host link leaves the page alone" "$(js "return location.href")" '.' "${url}#end"
check "and is handed to the browser" "$(opened)" "[\"$next\"]"

(cd "$CASE_DIR" && bridge "$url")
check_json "presenting again without --links goes back to the default" "$(bridge --state)" '.links' "external"
check "an unknown mode is refused" "$( (cd "$CASE_DIR" && bridge --links sideways "$url") 2>&1)" "--links window|browser|external <file|url>"

frames() {  # frames <name> [iframe attributes]
  page="$CASE_DIR/pages/$1.html"
  cat > "$page" <<HTML
<!doctype html><html><head><title>Frames</title></head><body>
<a href="$other">A link on the page itself</a>
<iframe src="$url" $2 style="width:100%;height:200px"></iframe>
</body></html>
HTML
  (cd "$CASE_DIR/pages" && bridge "$1.html")
  wait_ready; settle 0.8
}
fjs() { bridge --js "$page" "$1"; }
fclick() { fjs "@frame document.querySelector('$1').click(); return 1" >/dev/null; settle 0.8; }

frames plain
fjs "document.querySelector('body > a').click(); return 1" >/dev/null; settle 0.6
check "a local page's own links still open in the browser" "$(opened | jq -r last)" "$other"
fclick a.other
check_json "iframe default external: a link to another host leaves the frame alone" "$(fjs "@frame return location.href")" '.' "$url"
check "and is handed to the browser" "$(opened | jq -r last)" "$other"
fclick a.anchor
check_json "an in-page anchor stays in the frame" "$(fjs "@frame return location.href")" '.' "${url}#end"
fclick a.blank
check "a target=_blank link in a frame is handed to the browser" "$(opened | jq -r last)" "$next"
fclick a.same
check_json "a same-host link navigates inside the frame" "$(fjs "@frame return location.href")" '.' "$next"
check_json "while the page around it stays" "$(fjs "return document.title")" '.' "Frames"

frames window 'data-links="window"'
before=$(opened | jq length)
fclick a.other
check_json "data-links=window: a link to another host navigates inside the frame" "$(fjs "@frame return location.href")" '.' "$other"
check "and opens nothing" "$(opened | jq length)" "$before"

frames browser 'data-links="browser"'
fclick a.same
check_json "data-links=browser: a same-host link leaves the frame alone" "$(fjs "@frame return location.href")" '.' "$url"
check "and is handed to the browser" "$(opened | jq -r last)" "$next"
finish
