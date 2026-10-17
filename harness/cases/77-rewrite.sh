#!/bin/bash
source "$(dirname "$0")/../lib.sh"

mkdir -p "$CASE_DIR/elsewhere"
pair_with_b
python3 -c "import struct,zlib,sys; c=lambda t,d: struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)); open(sys.argv[1],'wb').write(b'\x89PNG\r\n\x1a\n'+c(b'IHDR',struct.pack('>IIBBBBB',2,1,8,2,0,0,0))+c(b'IDAT',zlib.compress(b'\0'+b'\xff\0\0'*2))+c(b'IEND',b''))" "$CASE_DIR/elsewhere/shot.png"
cp "$ROOT/harness/fixtures/decision.html" "$CASE_DIR/pages/decision.html"
sed -i '' "s|<h2>Layout</h2>|<img id=\"shot\" src=\"$CASE_DIR/elsewhere/shot.png\">\n<h2>Layout</h2>|" "$CASE_DIR/pages/decision.html"
page="$CASE_DIR/pages/decision.html"
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
id=$(bridge --share "$page" | jq -r '.share')
there="$CASE_DIR/state-b/bridge-dev/shared/$id/page.html"
for i in $(seq 1 80); do [ -f "$there" ] && break; sleep 0.25; done
b --do select "$there" >/dev/null
for i in $(seq 1 60); do [ "$(b --state | jq -r '.ready')" = "true" ] && break; sleep 0.25; done
b --js "$there" "document.querySelector('[data-value=list]').click(); window.__marker = 'alive'; return 1" >/dev/null
sleep 0.3

until_is() { for i in $(seq 1 80); do [ "$(eval "$1")" = "$2" ] && return; sleep 0.1; done; }
h1() { "$1" --js "$2" "return document.querySelector('h1').textContent" | jq -r .; }

sed -i '' 's|<h1>Card layout for the archive</h1>|<h1>Card layout, take two</h1>|' "$page"
until_is "h1 b '$there'" "Card layout, take two"
check "his agent's rewrite shows on her Mac" "$(h1 b "$there")" "Card layout, take two"
check "patched in place, not reloaded" "$(b --js "$there" "return window.__marker" | jq -r .)" "alive"
check "the heading the agent changed is outlined on her page" "$(b --js "$there" "return document.querySelector('h1').hasAttribute('data-bridge-changed')")" "true"
check "and nothing else is" "$(b --js "$there" "return document.querySelectorAll('[data-bridge-changed]').length")" "1"
check "her pick survived it" "$(b --read "$there" | jq -r '.answers.layout')" "list"

cp "$CASE_DIR/elsewhere/shot.png" "$(dirname "$there")/files/hers.png"
python3 - "$there" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('<h1>Card layout, take two</h1>','<h1>Her version</h1>\n<img id="hers" src="files/hers.png">')
open(p,'w').write(s)
PY
until_is "grep -c '<h1>Her version</h1>' '$page'" 1
check "her agent's rewrite reaches his file" "$(grep -c '<h1>Her version</h1>' "$page")" "1"
check "his image still points where it always did" "$(grep -c "src=\"$CASE_DIR/elsewhere/shot.png\"" "$page")" "1"
new=$(grep -o 'id="hers" src="[^"]*"' "$page" | sed 's/.*src="//; s/"$//')
check "her new image is kept on his Mac and referenced" "$([ -f "$new" ] && echo yes)" "yes"
until_is "h1 bridge '$page'" "Her version"
check "and his window shows it" "$(h1 bridge "$page")" "Her version"

a=$(shasum "$page" | cut -c1-12); c=$(shasum "$there" | cut -c1-12); sleep 2
check "nothing bounces back and forth" "$(shasum "$page" | cut -c1-12) $(shasum "$there" | cut -c1-12)" "$a $c"
sed -i '' 's|<h1>Her version</h1>|<h1>His at the same time</h1>|' "$page" & sed -i '' 's|<h1>Her version</h1>|<h1>Hers at the same time</h1>|' "$there" & wait
sleep 3
h_page=$(grep -o '<h1>[^<]*</h1>' "$page"); h_there=$(grep -o '<h1>[^<]*</h1>' "$there")
check "two rewrites at the same moment end up the same on both Macs" "$h_page" "$h_there"
finish
