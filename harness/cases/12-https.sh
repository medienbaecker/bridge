#!/bin/bash
# Local development hosts with self-signed certificates load; anything else keeps
# normal certificate validation.
source "$(dirname "$0")/../lib.sh"

site="$CASE_DIR/site"; mkdir -p "$site"
printf '<!doctype html><html><head><meta charset="utf-8"><title>Sicher</title></head><body><h1>Über https</h1></body></html>' > "$site/index.html"
other="$(hostname -s).local"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "$CASE_DIR/key.pem" -out "$CASE_DIR/cert.pem" -subj "/CN=127.0.0.1" -addext "subjectAltName=IP:127.0.0.1,DNS:localhost,DNS:$other" >/dev/null 2>&1
port=$((20000 + RANDOM % 20000))
python3 "$ROOT/harness/tls-server.py" "$port" "$CASE_DIR/cert.pem" "$CASE_DIR/key.pem" "$site" >"$CASE_DIR/server.log" 2>&1 &
server=$!
# Wait for the port to listen rather than race it: three full runs presented the
# page first. Waiting and then carrying on regardless is not a guard, though: a
# server that never came up reported "https does not load" instead of naming
# itself, which is what this case's flake has looked like every time.
for i in $(seq 1 100); do nc -z 127.0.0.1 "$port" 2>/dev/null && break; sleep 0.1; done
check "the test server is listening before anything is presented" "$(nc -z 127.0.0.1 "$port" 2>/dev/null && echo listening)$(head -c 120 "$CASE_DIR/server.log")" "listening"
trap 'kill $server 2>/dev/null; bridge --quit >/dev/null 2>&1 || true' EXIT
sleep 0.6

url="https://127.0.0.1:$port/"
(cd "$CASE_DIR" && bridge "$url")
wait_ready
check_json "a self-signed local host loads over https" "$(bridge --js "$url" "return [location.protocol, document.title].join(' ')")" '.' "https: Sicher"

bad="https://$other:$port/"
(cd "$CASE_DIR" && bridge "$bad")
sleep 2
check_json "the same certificate on an out-of-scope host is refused" "$(bridge --js "$bad" "return location.href")" '.' "about:blank"
check "refused pages never become ready" "$(bridge --state | jq -r '.ready')" "false"
finish
