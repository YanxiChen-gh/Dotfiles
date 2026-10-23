#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-herdr-opener-$$"
SERVER_PID=""
PROXY_PID=""
trap 'if [ -n "$PROXY_PID" ]; then kill "$PROXY_PID" 2>/dev/null || true; fi; if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null || true; fi; rm -rf "$TMP"' EXIT INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_log() {
    grep -F -- "$1" "$2" >/dev/null || fail "missing '$1' in $2"
}

mkdir -p "$TMP/bin" "$TMP/home"

RELAY_READY="$TMP/relay-ready"
RELAY_PAYLOAD="$TMP/relay-payload"
python3 - "$RELAY_READY" "$RELAY_PAYLOAD" <<'PY' &
import socket
import sys

ready_path, payload_path = sys.argv[1:]
with socket.socket() as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    with open(ready_path, "w", encoding="utf-8") as ready:
        ready.write(str(server.getsockname()[1]))
    connection, _ = server.accept()
    with connection, open(payload_path, "wb") as payload:
        while data := connection.recv(4096):
            payload.write(data)
PY
SERVER_PID=$!
for _ in $(seq 1 100); do
    [ -e "$RELAY_READY" ] && break
    sleep 0.01
done
[ -e "$RELAY_READY" ] || fail "relay did not start"
HERDR_REMOTE_OPENER_TEST_PORT=$(cat "$RELAY_READY")
export HERDR_REMOTE_OPENER_TEST_PORT

url='https://example.com/a/long/path?value=one%20two#result'
HERDR_PLUGIN_CLICKED_URL="$url" python3 "$ROOT/herdr/remote-opener/open_url.py"
wait "$SERVER_PID"
SERVER_PID=""
[ "$(cat "$RELAY_PAYLOAD")" = "$url" ] || fail "relay changed the URL"
[ "$(python3 "$ROOT/herdr/remote-opener/open_url.py" --print-port)" = "$HERDR_REMOTE_OPENER_TEST_PORT" ] \
    || fail "wrapper and plugin port contract changed"
if HERDR_PLUGIN_CLICKED_URL='file:///tmp/private' python3 "$ROOT/herdr/remote-opener/open_url.py" 2>/dev/null; then
    fail "non-HTTP URL was accepted"
fi
if HERDR_PLUGIN_CLICKED_URL="https://example.com/line
break" python3 "$ROOT/herdr/remote-opener/open_url.py" 2>/dev/null; then
    fail "URL with control characters was accepted"
fi
PROXY_BACKEND="$TMP/proxy-backend.sock"
PROXY_SOCKET="$TMP/proxy.sock"
PROXY_READY="$TMP/proxy-ready"
PROXY_PAYLOAD="$TMP/proxy-payload"
python3 - "$PROXY_BACKEND" "$PROXY_READY" "$PROXY_PAYLOAD" <<'PY' &
import socket
import sys

socket_path, ready_path, payload_path = sys.argv[1:]
with socket.socket(socket.AF_UNIX) as server:
    server.bind(socket_path)
    server.listen(1)
    open(ready_path, "w", encoding="utf-8").close()
    connection, _ = server.accept()
    with connection, open(payload_path, "wb") as payload:
        while data := connection.recv(4096):
            payload.write(data)
PY
SERVER_PID=$!
for _ in $(seq 1 100); do
    [ -e "$PROXY_READY" ] && break
    sleep 0.01
done
python3 "$ROOT/herdr/remote-opener/open_url.py" --proxy "$PROXY_SOCKET" "$PROXY_BACKEND" &
PROXY_PID=$!
for _ in $(seq 1 100); do
    [ -S "$PROXY_SOCKET" ] && break
    sleep 0.01
done
[ -S "$PROXY_SOCKET" ] || fail "validating proxy did not start"
python3 - "$PROXY_SOCKET" "$url" <<'PY'
import socket
import sys
import time

socket_path, valid_url = sys.argv[1:]

def request(value: str) -> bytes:
    with socket.socket(socket.AF_UNIX) as client:
        client.connect(socket_path)
        client.sendall(value.encode("utf-8") + b"\n")
        client.shutdown(socket.SHUT_WR)
        response = bytearray()
        while chunk := client.recv(4096):
            response.extend(chunk)
    return bytes(response)

with socket.socket(socket.AF_UNIX) as malformed_client:
    malformed_client.connect(socket_path)
    malformed_client.sendall(b"file:///tmp/private\n")

with socket.socket(socket.AF_UNIX) as stalled_client:
    stalled_client.connect(socket_path)
    time.sleep(2.2)

assert request(valid_url) == b""
assert b"only absolute HTTP(S) URLs" in request("file:///tmp/private")
PY
wait "$SERVER_PID"
SERVER_PID=""
kill "$PROXY_PID"
wait "$PROXY_PID" 2>/dev/null || true
PROXY_PID=""
[ "$(cat "$PROXY_PAYLOAD")" = "$url" ] || fail "proxy changed the validated URL"

cat >"$TMP/bin/native-opener" <<'EOF'
#!/usr/bin/env python3
import os
import sys
import time
time.sleep(2.2)
if sys.argv[1].endswith("#permission-denied"):
    print("Allow WezTerm in Privacy & Security > Accessibility", file=sys.stderr)
    raise SystemExit(1)
with open(os.environ["NATIVE_PAYLOAD"], "w", encoding="utf-8") as output:
    output.write(sys.argv[1])
EOF
chmod +x "$TMP/bin/native-opener"
NATIVE_PAYLOAD="$TMP/native-payload"
export NATIVE_PAYLOAD
rm -f "$PROXY_SOCKET"
python3 "$ROOT/herdr/remote-opener/open_url.py" --proxy "$PROXY_SOCKET" "$TMP/bin/native-opener" --split-view &
PROXY_PID=$!
for _ in $(seq 1 100); do
    [ -S "$PROXY_SOCKET" ] && break
    sleep 0.01
done
python3 - "$PROXY_SOCKET" "$url" <<'PY'
import os
import socket
import stat
import sys
from pathlib import Path

path, url = sys.argv[1:]
assert stat.S_IMODE(os.stat(path).st_mode) == 0o600

def request(value):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(10)
        connection.connect(path)
        connection.sendall(value.encode() + b"\n")
        connection.shutdown(socket.SHUT_WR)
        return connection.recv(65536)

literal_url = url + "';$(touch%20not-a-command)"
assert request(literal_url) == b""
assert Path(os.environ["NATIVE_PAYLOAD"]).read_text() == literal_url
assert b"Accessibility" in request(url + "#permission-denied")
assert b"only absolute HTTP(S)" in request("file:///tmp/private")
assert Path(os.environ["NATIVE_PAYLOAD"]).read_text() == literal_url
PY
kill "$PROXY_PID"
wait "$PROXY_PID" 2>/dev/null || true
PROXY_PID=""

SOCKET_PATH="$TMP/opener.sock"
SOCKET_READY="$TMP/socket-ready"
python3 - "$SOCKET_PATH" "$SOCKET_READY" <<'PY' &
import socket
import sys
import time

socket_path, ready_path = sys.argv[1:]
with socket.socket(socket.AF_UNIX) as server:
    server.bind(socket_path)
    server.listen(1)
    open(ready_path, "w", encoding="utf-8").close()
    time.sleep(30)
PY
SERVER_PID=$!
for _ in $(seq 1 100); do
    [ -e "$SOCKET_READY" ] && break
    sleep 0.01
done
[ -S "$SOCKET_PATH" ] || fail "opener socket did not start"

SSH_LOG="$TMP/ssh.log"
HERDR_LOG="$TMP/herdr.log"
cat >"$TMP/bin/ssh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_SSH_LOG"
case " $* " in
    *" ss -ltnH "*)
        if [ "${FAKE_SSH_WILDCARD:-0}" = "1" ]; then
            printf '%s\n' "0.0.0.0:$HERDR_REMOTE_OPENER_TEST_PORT"
        else
            printf '%s\n' "127.0.0.1:$HERDR_REMOTE_OPENER_TEST_PORT"
        fi
        ;;
    *" -M "*) [ "${FAKE_SSH_FAIL:-0}" != "1" ] || exit 9 ;;
esac
EOF
cat >"$TMP/bin/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_HERDR_LOG"
exit "${FAKE_HERDR_STATUS:-0}"
EOF
cat >"$TMP/bin/lsof" <<'EOF'
#!/bin/sh
[ "${FAKE_LSOF_FAIL:-0}" != "1" ] || exit 1
printf '%s\n' 123
EOF
cat >"$TMP/bin/ss" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$TMP/bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "${FAKE_UNAME:-Linux}"
EOF
chmod +x "$TMP/bin/ssh" "$TMP/bin/herdr" "$TMP/bin/lsof" "$TMP/bin/ss" "$TMP/bin/uname"
ln -s "$ROOT/herdr/herdr-remote.sh" "$TMP/bin/herdr-remote"

PATH="$TMP/bin:$PATH"
HOME="$TMP/home"
OPENER_SOCKET_PATH="$SOCKET_PATH"
FAKE_SSH_LOG="$SSH_LOG"
FAKE_HERDR_LOG="$HERDR_LOG"
export PATH HOME OPENER_SOCKET_PATH FAKE_SSH_LOG FAKE_HERDR_LOG HERDR_REMOTE_OPENER_TEST_PORT

: >"$SSH_LOG"
: >"$HERDR_LOG"
herdr-remote workbox --session work
assert_log "-o ExitOnForwardFailure=yes" "$SSH_LOG"
assert_log "-o GatewayPorts=no" "$SSH_LOG"
assert_log "-R 127.0.0.1:$HERDR_REMOTE_OPENER_TEST_PORT:" "$SSH_LOG"
if grep -F ":$SOCKET_PATH" "$SSH_LOG" >/dev/null; then
    fail "remote traffic bypassed the validating proxy"
fi
if grep -F "ClearAllForwardings=yes" "$SSH_LOG" >/dev/null; then
    fail "wrapper cleared its explicit remote forward"
fi
assert_log "-O exit workbox" "$SSH_LOG"
assert_log "--remote workbox --remote-keybindings server --session work" "$HERDR_LOG"
: >"$SSH_LOG"
: >"$HERDR_LOG"
FAKE_LSOF_FAIL=1
export FAKE_LSOF_FAIL
if herdr-remote workbox >/dev/null 2>&1; then
    fail "wrapper accepted a stale opener socket"
fi
[ ! -s "$SSH_LOG" ] || fail "SSH started with a stale opener socket"
[ ! -s "$HERDR_LOG" ] || fail "Herdr started with a stale opener socket"
unset FAKE_LSOF_FAIL

: >"$SSH_LOG"
: >"$HERDR_LOG"
FAKE_SSH_FAIL=1
export FAKE_SSH_FAIL
if herdr-remote workbox >/dev/null 2>&1; then
    fail "wrapper continued after tunnel failure"
fi
[ ! -s "$HERDR_LOG" ] || fail "Herdr started after tunnel failure"
unset FAKE_SSH_FAIL
: >"$SSH_LOG"
: >"$HERDR_LOG"
FAKE_SSH_WILDCARD=1
export FAKE_SSH_WILDCARD
if herdr-remote workbox >/dev/null 2>&1; then
    fail "wrapper accepted a wildcard remote listener"
fi
[ ! -s "$HERDR_LOG" ] || fail "Herdr started with a wildcard remote listener"
assert_log "-O exit workbox" "$SSH_LOG"
unset FAKE_SSH_WILDCARD

: >"$SSH_LOG"
: >"$HERDR_LOG"
FAKE_HERDR_STATUS=7
export FAKE_HERDR_STATUS
if herdr-remote workbox >/dev/null 2>&1; then
    fail "wrapper hid the Herdr exit status"
else
    status=$?
fi
[ "$status" -eq 7 ] || fail "wrapper returned $status instead of Herdr status 7"
assert_log "-O exit workbox" "$SSH_LOG"
unset FAKE_HERDR_STATUS

kill "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

cat >"$TMP/bin/swiftc" <<'EOF'
#!/bin/sh
set -eu
[ "${FAKE_COMPILE_FAIL:-0}" != "1" ] || exit 1
while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
        shift
        cp /usr/bin/true "$1"
        chmod +x "$1"
        exit
    fi
    shift
done
exit 1
EOF
chmod +x "$TMP/bin/swiftc"

# shellcheck source=../../install.d/10-helpers.sh
. "$ROOT/install.d/10-helpers.sh"
# shellcheck source=../../install.d/36-herdr-opener.sh
. "$ROOT/install.d/36-herdr-opener.sh"
resolve_script_dir() {
    printf '%s\n' "$ROOT"
}

OS=macos setup_herdr_opener_client >/dev/null
[ "$(readlink "$HOME/.local/bin/herdr-remote")" = "$ROOT/herdr/herdr-remote.sh" ] \
    || fail "installer did not expose herdr-remote"
[ -x "$HOME/.local/libexec/dotfiles/herdr-split-view" ] || fail "native helper was not installed"
cp "$HOME/.local/libexec/dotfiles/herdr-split-view" "$TMP/installed-helper"
if FAKE_COMPILE_FAIL=1 OS=macos setup_herdr_opener_client >/dev/null; then
    fail "failed compilation was hidden"
fi
cmp "$TMP/installed-helper" "$HOME/.local/libexec/dotfiles/herdr-split-view" \
    || fail "failed compilation replaced the installed helper"
: >"$SSH_LOG"
: >"$HERDR_LOG"
FAKE_UNAME=Darwin FAKE_LSOF_FAIL=1 herdr-remote workbox
assert_log "--remote workbox" "$HERDR_LOG"
rm "$HOME/.local/libexec/dotfiles/herdr-split-view"
: >"$SSH_LOG"
if FAKE_UNAME=Darwin herdr-remote workbox >/dev/null 2>&1; then
    fail "wrapper started without its native helper"
fi
[ ! -s "$SSH_LOG" ] || fail "SSH started without its native helper"
: >"$HERDR_LOG"
IS_ON_ONA= HERDR_REMOTE_OPENER_SERVER= OS=linux setup_herdr_opener_plugin >/dev/null
[ ! -s "$HERDR_LOG" ] || fail "plugin was linked outside a remote opener server"


: >"$HERDR_LOG"
IS_ON_ONA=true OS=linux setup_herdr_opener_plugin >/dev/null
assert_log "plugin link $ROOT/herdr/remote-opener" "$HERDR_LOG"

printf '%s\n' "Herdr remote opener tests passed."
