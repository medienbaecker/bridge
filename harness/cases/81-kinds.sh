#!/bin/bash
source "$(dirname "$0")/../lib.sh"

mkdir -p "$CASE_DIR/elsewhere"
with_b
python3 -c "import struct,zlib,sys; c=lambda t,d: struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)); open(sys.argv[1],'wb').write(b'\x89PNG\r\n\x1a\n'+c(b'IHDR',struct.pack('>IIBBBBB',2,1,8,2,0,0,0))+c(b'IDAT',zlib.compress(b'\0'+b'\xff\0\0'*2))+c(b'IEND',b''))" "$CASE_DIR/elsewhere/shot.png"
cp "$CASE_DIR/elsewhere/shot.png" "$CASE_DIR/pages/picture.png"
printf '# Plan\n\nFirst step.\n\n<img src="%s">\n' "$CASE_DIR/elsewhere/shot.png" > "$CASE_DIR/pages/plan.md"
printf 'a draft to paste\n' > "$CASE_DIR/pages/reply.txt"
(cd "$CASE_DIR/pages" && bridge plan.md picture.png reply.txt)
wait_ready

there() { echo "$CASE_DIR/state-b/bridge-dev/shared/$1/page.$2"; }
for kind in md png txt; do
  case $kind in md) f=plan.md;; png) f=picture.png;; txt) f=reply.txt;; esac
  bridge --do select "$CASE_DIR/pages/$f" >/dev/null; sleep 0.3
  check "the Share button is offered for a .$kind page" "$(bridge --state | jq -r '[.toolbar[] | select(.id == "share")][0].enabled')" "true"
  id=$(bridge --share "$CASE_DIR/pages/$f" | jq -r '.share')
  eval "id_$kind=$id"
  for i in $(seq 1 80); do [ -f "$(there "$id" "$kind")" ] && break; sleep 0.25; done
  check "a .$kind page arrives as a .$kind page" "$([ -f "$(there "$id" "$kind")" ] && echo yes)" "yes"
done
check "the picture arrives byte for byte" "$(cmp -s "$CASE_DIR/pages/picture.png" "$(there "$id_png" png)" && echo same)" "same"
check "the plan's image travels with it" "$(grep -c 'src="files/' "$(there "$id_md" md)")" "1"
check "the text arrives as it was" "$(cat "$(there "$id_txt" txt)")" "a draft to paste"

b --do select "$(there "$id_md" md)" >/dev/null; sleep 0.5
sed -i '' 's/First step./First step, then the second./' "$(there "$id_md" md)"
for i in $(seq 1 80); do grep -q 'then the second' "$CASE_DIR/pages/plan.md" && break; sleep 0.1; done
check "her agent's rewrite of the plan reaches his file" "$(grep -c 'then the second' "$CASE_DIR/pages/plan.md")" "1"
check "with his image path as it was" "$(grep -c "src=\"$CASE_DIR/elsewhere/shot.png\"" "$CASE_DIR/pages/plan.md")" "1"
finish
