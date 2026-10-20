# A stand-in for a Claude Code session: its entry in the session registry and an
# inbox socket that writes each message it is sent to a file, one JSON string a line.
# Usage: fake-claude.py <registry dir> <session id> <inbox file> <socket> [idle|busy]
import json, os, signal, socket, sys

registry, session, inbox, path = sys.argv[1:5]
status = sys.argv[5] if len(sys.argv) > 5 else "idle"
entry = os.path.join(registry, "%d.json" % os.getpid())

def leave(*_):
    for f in (entry, path):
        try: os.remove(f)
        except OSError: pass
    sys.exit(0)

signal.signal(signal.SIGTERM, leave)
signal.signal(signal.SIGALRM, leave)
signal.alarm(600)
os.makedirs(registry, exist_ok=True)
try: os.remove(path)
except OSError: pass
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(path)
server.listen()
open(inbox, "a").close()
with open(entry + ".tmp", "w") as f:
    json.dump({"pid": os.getpid(), "sessionId": session, "cwd": os.getcwd(), "name": session, "status": status, "messagingSocketPath": path}, f)
os.rename(entry + ".tmp", entry)
while True:
    conn, _ = server.accept()
    data = b""
    while chunk := conn.recv(65536): data += chunk
    conn.close()
    with open(inbox, "a") as f:
        for line in data.decode().splitlines():
            if line.strip(): f.write(json.dumps(json.loads(line)["message"]["content"]) + "\n")
