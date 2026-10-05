#!/bin/bash
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/speed.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Speed</title></head><body>
<p class="muted">How fast?</p>
<div class="dials">
  <label class="dial"><span>travel</span><input type="range" min="0" max="40" value="12" data-record="travel"><output></output></label>
</div>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge speed.html); wait_ready
hook() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$CASE_DIR/pages" | bridge --hook post-write; }

sed -i '' 's/How fast?/How fast, really?/' "$page"
check "a wording change says nothing" "$(hook "$page")" ""
sed -i '' 's/min="0" max="40"/min="-100" max="40"/' "$page"
told=$(hook "$page")
check_json "a changed range tells the agent the new version" "$told" '.hookSpecificOutput.additionalContext | test("made speed.html version 2")' "true"
check_json "and what changed" "$told" '.hookSpecificOutput.additionalContext | test("travel offered input:range:0-40, now input:range:-100-40")' "true"
check_json "and how to start over" "$told" '.hookSpecificOutput.additionalContext | test("--reset")' "true"
check "a file that is not a bridge says nothing" "$(hook "$CASE_DIR/pages/other.txt")" ""

port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 - "$port" <<'PY' &
import sys, http.server
class H(http.server.BaseHTTPRequestHandler):
    def head(self):
        self.send_response(200); self.send_header("Content-Type", "text/html")
        if self.path.startswith("/refuses"): self.send_header("X-Frame-Options", "SAMEORIGIN")
        self.end_headers()
    def do_HEAD(self): self.head()
    def do_GET(self): self.head(); self.wfile.write(b"<p>framed</p>")
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
server=$!
trap 'kill $server 2>/dev/null; bridge --quit >/dev/null 2>&1 || true' EXIT
sleep 0.5
frames="$CASE_DIR/pages/frames.html"
cat > "$frames" <<HTML
<!doctype html><html><head><title>Frames</title></head><body>
<iframe src="http://127.0.0.1:$port/refuses" style="width:100%;height:120px"></iframe>
<iframe src="http://localhost:$port/fine" style="width:100%;height:120px"></iframe>
</body></html>
HTML
err=$( (cd "$CASE_DIR/pages" && bridge frames.html) 2>&1 >/dev/null); wait_ready
check "presenting names the refused frame" "$(printf '%s' "$err" | grep -c "127.0.0.1:$port/refuses in frames.html refuses to be shown in a frame (X-Frame-Options: SAMEORIGIN)")" "1"
check "and only that one" "$(printf '%s' "$err" | grep -c "refuses to be shown")" "1"
settle 1
check_json "the page says so above the blank frame" "$(bridge --js "$frames" "const n = document.querySelectorAll('.bridge-frame-refused'); return n.length === 1 && n[0].nextElementSibling.src.includes('/refuses') && n[0].textContent")" '.' "127.0.0.1:$port refuses to be shown in a frame (X-Frame-Options: SAMEORIGIN). Present the URL on its own, or serve it through a proxy that drops that header."
snap refused "A refused frame says why"
finish
