#!/bin/bash
# A page presented with --site runs as part of that site: it imports the site's
# modules and reaches into its frames, and images from disk still load, also
# after a live edit. Files beside the page load from disk, also over https; a
# frame's scrollIntoView scrolls the frame, not the page around it; and a file
# the page never named stays out of reach.
source "$(dirname "$0")/../lib.sh"
site="$CASE_DIR/site"; mkdir -p "$site/assets/js"
echo 'export const answer = "from the site";' > "$site/assets/js/menu.js"
printf '<!doctype html><title>Site</title><p id="menu">real menu</p>' > "$site/index.html"
printf '<!doctype html><style>html,body{margin:0;height:100%%;background:rgb(255,0,0)}</style>' > "$site/red.html"
echo '#tone { color: rgb(255, 0, 0) }' > "$site/theme.css"
printf '<!doctype html><link rel="stylesheet" href="/theme.css"><p id="tone">tone</p>' > "$site/tone.html"
printf '<!doctype html><body style="height:3000px"><p id="far" style="margin-top:2000px">far</p><script>window.go = () => document.getElementById("far").scrollIntoView()</script></body>' > "$site/far.html"
port=$((20000 + RANDOM % 20000)); sport=$((port + 1))
python3 - "$port" "$site" >/dev/null 2>&1 <<'PY' &
import functools, http.server, sys, time
class Site(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/red.html': time.sleep(1)
        super().do_GET()
    def end_headers(self):
        if self.path.endswith('.css'): self.send_header('Cache-Control', 'max-age=3600')
        super().end_headers()
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), functools.partial(Site, directory=sys.argv[2])).serve_forever()
PY
server=$!
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "$CASE_DIR/key.pem" -out "$CASE_DIR/cert.pem" -subj "/CN=127.0.0.1" -addext "subjectAltName=IP:127.0.0.1" >/dev/null 2>&1
python3 "$ROOT/harness/tls-server.py" "$sport" "$CASE_DIR/cert.pem" "$CASE_DIR/key.pem" "$site" >/dev/null 2>&1 &
secure=$!
trap 'kill $server $secure 2>/dev/null; bridge --quit >/dev/null 2>&1 || true' EXIT
for p in "$port" "$sport"; do for i in $(seq 1 50); do nc -z 127.0.0.1 "$p" 2>/dev/null && break; sleep 0.1; done; done
img="$CASE_DIR/pages/shot.png"; cp "$ROOT/.github/icon.png" "$img"
page="$CASE_DIR/pages/learn.html"
cat > "$page" <<HTML
<!doctype html><html><head><title>Learn</title></head><body>
<img id="one" src="$img">
<iframe id="f" src="/index.html"></iframe>
<script type="module">import { answer } from '/assets/js/menu.js'; window.imported = answer;</script>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge learn.html --site "http://127.0.0.1:$port/"); wait_ready; settle 1
js() { bridge --js "$page" "$1"; }
check_json "the page has the site's origin" "$(js "return location.origin")" '.' "http://127.0.0.1:$port"
check_json "it imports the site's module" "$(js "return window.imported")" '.' "from the site"
check_json "and reaches into the site's frame" "$(js "return document.getElementById('f').contentDocument.getElementById('menu').textContent")" '.' "real menu"
check_json "an image from disk loads" "$(js "return document.getElementById('one').naturalWidth > 0")" '.' "true"
sed -i '' "s|<iframe|<img id=\"two\" src=\"file://$img\"><iframe|" "$page"; settle 1
check_json "an image added by a live edit loads too" "$(js "return document.getElementById('two')?.naturalWidth > 0")" '.' "true"
check_json "the edit patched rather than reloaded" "$(js "return window.imported")" '.' "from the site"
printf '# x' > "$CASE_DIR/pages/notes.md"
check "--site refuses a page that is not html" "$(cd "$CASE_DIR/pages" && bridge notes.md --site "http://127.0.0.1:$port/" 2>&1)" "--site is for .html pages: $CASE_DIR/pages/notes.md"
beside="$CASE_DIR/pages/beside.html"
echo 'window.helper = "beside";' > "$CASE_DIR/pages/helper.js"
echo '#styled { color: rgb(1, 2, 3) }' > "$CASE_DIR/pages/style.css"
cat > "$beside" <<HTML
<!doctype html><html><head><title>Beside</title><link rel="stylesheet" href="style.css"><script src="helper.js"></script></head><body>
<p id="styled">styled</p><img id="rel" src="shot.png"><a id="out" href="notes.md">notes</a>
<div style="height:300px"></div><iframe id="f" src="/far.html" style="width:300px;height:200px"></iframe><div style="height:3000px"></div>
</body></html>
HTML
for base in "http://127.0.0.1:$port/" "https://127.0.0.1:$sport/"; do
  (cd "$CASE_DIR/pages" && bridge beside.html --site "$base"); wait_ready; settle 1
  b() { bridge --js "$beside" "$1"; }
  check_json "$base: a script beside the page runs" "$(b "return window.helper")" '.' "beside"
  check_json "$base: a stylesheet beside it applies" "$(b "return getComputedStyle(document.getElementById('styled')).color")" '.' "rgb(1, 2, 3)"
  check_json "$base: an image beside it loads" "$(b "return document.getElementById('rel').naturalWidth > 0")" '.' "true"
done
check_json "a frame's scrollIntoView scrolls the frame" "$(bridge --js "$beside" "scrollTo(0, 0); const f = document.getElementById('f').contentWindow; f.go(); return f.scrollY > 0")" '.' "true"
check_json "and leaves the page where it was" "$(bridge --js "$beside" "return scrollY")" '.' "0"
check_json "a file the page never named is out of reach" "$(bridge --js "$beside" "return fetch('bridge-file:///etc/hosts').then(() => 'read', () => 'refused')")" '.' "refused"
bridge --js "$beside" "document.getElementById('out').click(); return 1" >/dev/null; settle 0.5
check "a link to a file beside it opens that file, outside Bridge" "$(bridge --state | jq -c '.openedExternally')" "[\"file://$CASE_DIR/pages/notes.md\"]"
bridge --do point >/dev/null
bridge --js "$beside" "const el = document.querySelector('#styled'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: r.left + 5, clientY: r.top + 5})); return 1" >/dev/null; settle 0.3
bridge --js "$beside" "const t = document.querySelector('.bridge-thread:popover-open textarea'); t.value = 'why this colour'; t.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true})); return 1" >/dev/null; settle 0.4
check_json "a note pinned on a site page is recorded" "$(bridge --pins "$beside")" '.[0] | "\(.text) | \(.target)"' 'why this colour | p "styled"'
shotme="$CASE_DIR/pages/shotme.html"
printf '<!doctype html><title>Shot</title><style>body{margin:0}iframe{display:block;border:0;width:400px;height:150px}</style><iframe id="f"></iframe><script>document.getElementById("f").src = "/red.html"</script>' > "$shotme"
r=$(bridge --shot "$shotme" "$CASE_DIR/shots/shotme.png" --width 600 --site "http://127.0.0.1:$port/")
check_json "--shot renders a page that was never presented as part of the site" "$r" '.width' "600"
check "and waits for the frame its script loads" "$(python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/shotme.png" 100 | grep -c ' 255 0 0$' | tr -d ' ')" "1"
check "--shot refuses --site for a page that is not html" "$(bridge --shot "$CASE_DIR/pages/notes.md" "$CASE_DIR/shots/x.png" --site "http://127.0.0.1:$port/" 2>&1)" "--site is for .html pages: $CASE_DIR/pages/notes.md"
tone="$CASE_DIR/pages/tone.html"
printf '<!doctype html><title>Tone</title><iframe id="f" src="/tone.html"></iframe>' > "$tone"
(cd "$CASE_DIR/pages" && bridge tone.html --site "http://127.0.0.1:$port/"); wait_ready; settle 1
colour() { bridge --js "$tone" "return getComputedStyle(document.getElementById('f').contentDocument.getElementById('tone')).color"; }
check_json "the frame shows the site's colour" "$(colour)" '.' "rgb(255, 0, 0)"
echo '#tone { color: rgb(0, 0, 255) }' > "$site/theme.css"
bridge --reload "$tone"; wait_ready; settle 1
check_json "--reload shows the site's changed CSS" "$(colour)" '.' "rgb(0, 0, 255)"
bridge --do point >/dev/null
bridge --js "$tone" "const el = document.querySelector('iframe'); const r = el.getBoundingClientRect(); el.parentElement.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: r.left + 5, clientY: r.top + 5})); return 1" >/dev/null; settle 0.3
bridge --js "$tone" "document.querySelector('.bridge-thread:popover-open textarea').value = 'halb geschrieben'; return 1" >/dev/null
check "--reload refuses while they are writing a note" "$(bridge --reload "$tone" 2>&1)" "they are writing a note on it; reload later"
check "--reload refuses a page that is not listed" "$(bridge --reload "$CASE_DIR/pages/never.html" 2>&1)" "not in the list: $CASE_DIR/pages/never.html"
finish
