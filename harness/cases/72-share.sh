#!/bin/bash
source "$(dirname "$0")/../lib.sh"

mkdir -p "$CASE_DIR/state-b" "$CASE_DIR/elsewhere"
b() { XDG_STATE_HOME="$CASE_DIR/state-b" BRIDGE_SESSION="test-$CASE_NAME-b" bridge "$@"; }
trap 'bridge --quit >/dev/null 2>&1; b --quit >/dev/null 2>&1' EXIT
bridge --name thomas >/dev/null; bridge --colour '#e8590c' >/dev/null
b --name yoshie >/dev/null
bridge --pair >/dev/null; b --pair >/dev/null
for i in $(seq 1 60); do [ "$(b --state | jq -r '.link.words')" != "null" ] && [ "$(bridge --state | jq -r '.link.words')" != "null" ] && break; sleep 0.25; done
bridge --do pair-confirm >/dev/null; b --do pair-confirm >/dev/null
connected() { "$@" --peers | jq -r '.connected | join(",")'; }
for i in $(seq 1 60); do [ -n "$(connected bridge)" ] && [ -n "$(connected b)" ] && break; sleep 0.25; done

cp "$ROOT/harness/fixtures/decision.html" "$CASE_DIR/pages/decision.html"
python3 -c "import struct,zlib,sys; c=lambda t,d: struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)); open(sys.argv[1],'wb').write(b'\x89PNG\r\n\x1a\n'+c(b'IHDR',struct.pack('>IIBBBBB',2,1,8,2,0,0,0))+c(b'IDAT',zlib.compress(b'\0'+b'\xff\0\0'*2))+c(b'IEND',b''))" "$CASE_DIR/elsewhere/shot.png"
sed -i '' "s|<h2>Layout</h2>|<img id=\"shot\" src=\"$CASE_DIR/elsewhere/shot.png\">\n<h2>Layout</h2>|" "$CASE_DIR/pages/decision.html"
page="$CASE_DIR/pages/decision.html"
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready

check "sharing with no page path is refused" "$(bridge --share 2>&1 >/dev/null | head -1 | cut -c1-6)" "bridge"
out=$(bridge --share "$page")
check_json "the page goes to yoshie" "$out" '.to | join(",")' "yoshie"
id=$(echo "$out" | jq -r '.share')
there="$CASE_DIR/state-b/bridge-dev/shared/$id/page.html"
for i in $(seq 1 60); do [ -f "$there" ] && break; sleep 0.25; done
check "it arrives on her Mac" "$([ -f "$there" ] && echo yes)" "yes"
check "its image arrives with it" "$(grep -o 'src="files/[^"]*shot.png"' "$there" | wc -l | tr -d ' ')" "1"
for i in $(seq 1 40); do b --state | jq -e '[.sidebar[]? | select(.project == "Shared by thomas")] | length > 0' >/dev/null && break; sleep 0.25; done
check_json "her list has it under Shared by thomas" "$(b --state)" '[.sidebar[] | select(.project == "Shared by thomas") | .bridges[].title] | join(",")' "Card layout for the archive"

b --do select "$there" >/dev/null
for i in $(seq 1 60); do [ "$(b --state | jq -r '.ready')" = "true" ] && break; sleep 0.25; done
check "the image shows on her Mac" "$(b --js "$there" "const i = document.querySelector('#shot'); await new Promise(r => i.complete ? r() : i.addEventListener('load', r, { once: true })); return i.naturalWidth")" "2"

point() { "$1" --js "$2" "const el = document.querySelector('[data-value=grid]'); const r = el.getBoundingClientRect(); el.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, clientX: r.left + r.width * 0.3, clientY: r.top + r.height / 2 })); return 1" >/dev/null; }
cursor() { "$1" --js "$2" "@bridge const c = document.querySelector('.bridge-cursor'); return c && !c.hidden ? c.querySelector('span').textContent + ' ' + c.style.getPropertyValue('--bridge-cursor') : 'none'" | jq -r .; }
point bridge "$page"
for i in $(seq 1 40); do [ "$(cursor b "$there")" != "none" ] && break; sleep 0.1; done
check "his cursor shows on her Mac, in his colour" "$(cursor b "$there")" "thomas #e8590c"
check "on the same element" "$(b --js "$there" "@bridge const c = document.querySelector('.bridge-cursor'), r = document.querySelector('[data-value=grid]').getBoundingClientRect(); return Math.abs(parseFloat(c.style.left) - (r.left + r.width * 0.3)) < 2")" "true"

b --shot "$CASE_DIR/shots/her-mac.png" >/dev/null
point b "$there"
for i in $(seq 1 40); do [ "$(cursor bridge "$page")" != "none" ] && break; sleep 0.1; done
check "her cursor shows on his Mac" "$(cursor bridge "$page" | cut -d' ' -f1)" "yoshie"

b --quit >/dev/null
for i in $(seq 1 40); do [ "$(cursor bridge "$page")" = "none" ] && break; sleep 0.1; done
check "when her Mac goes away, her cursor goes" "$(cursor bridge "$page")" "none"
finish
