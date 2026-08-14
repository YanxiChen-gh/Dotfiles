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
python3 - "$ROOT/herdr/remote-opener/herdr-plugin.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as manifest_file:
    manifest = tomllib.load(manifest_file)
assert manifest["id"] == "dotfiles.remote-opener"
assert manifest["actions"][0]["command"] == ["python3", "open_url.py"]
assert manifest["link_handlers"][0]["action"] == "open"
PY


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
chmod +x "$TMP/bin/ssh" "$TMP/bin/herdr" "$TMP/bin/lsof" "$TMP/bin/ss"
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

INSTALL_LOG="$TMP/install.log"
cat >"$TMP/bin/brew" <<'EOF'
#!/bin/sh
printf 'brew %s\n' "$*" >>"$FAKE_INSTALL_LOG"
EOF
chmod +x "$TMP/bin/brew"
FAKE_INSTALL_LOG="$INSTALL_LOG"
export FAKE_INSTALL_LOG

# shellcheck source=../../install.d/10-helpers.sh
. "$ROOT/install.d/10-helpers.sh"
# shellcheck source=../../install.d/36-herdr-opener.sh
. "$ROOT/install.d/36-herdr-opener.sh"
resolve_script_dir() {
    printf '%s\n' "$ROOT"
}

: >"$INSTALL_LOG"
OS=macos setup_herdr_opener_client >/dev/null
[ "$(readlink "$HOME/.local/bin/herdr-remote")" = "$ROOT/herdr/herdr-remote.sh" ] \
    || fail "installer did not expose herdr-remote"
assert_log "brew install superbrothers/opener/opener" "$INSTALL_LOG"
assert_log "brew services start opener" "$INSTALL_LOG"

cat >"$TMP/bin/opener" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TMP/bin/opener"
: >"$INSTALL_LOG"
OS=macos setup_herdr_opener_client >/dev/null
if grep -F "brew install" "$INSTALL_LOG" >/dev/null; then
    fail "idempotent client setup reinstalled opener"
fi
assert_log "brew services start opener" "$INSTALL_LOG"
: >"$HERDR_LOG"
IS_ON_ONA= HERDR_REMOTE_OPENER_SERVER= OS=linux setup_herdr_opener_plugin >/dev/null
[ ! -s "$HERDR_LOG" ] || fail "plugin was linked outside a remote opener server"


: >"$HERDR_LOG"
IS_ON_ONA=true OS=linux setup_herdr_opener_plugin >/dev/null
assert_log "plugin link $ROOT/herdr/remote-opener" "$HERDR_LOG"

printf '%s\n' "Herdr remote opener tests passed."
