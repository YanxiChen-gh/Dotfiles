#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-workline-activity.XXXXXX")
cleanup() {
    if [ -f "$TMP/cde/reporter-pid" ]; then
        kill "$(cat "$TMP/cde/reporter-pid")" 2>/dev/null || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

fail() { echo "FAIL: $*" >&2; exit 1; }
resolve_script_dir() { printf '%s\n' "$ROOT"; }
# shellcheck source=../../install.d/60-codex.sh
. "$ROOT/install.d/60-codex.sh"

real_node=$(command -v node || true)
mkdir -p "$TMP/bin" "$TMP/personal" "$TMP/cde" "$TMP/linux" "$TMP/mac"
export PATH="$TMP/bin:$PATH"
export WORKLINE_CONFIG="$TMP/workline-account.json"
service_path=".local/share/workline-activity"

cat >"$TMP/bin/node" <<'SH'
#!/bin/sh
printf '%s\n' "$$" >"$HOME/reporter-pid"
printf '%s\n' "$CODEX_HOME|$WORKLINE_CONFIG|$*" >>"$HOME/reporter-starts"
exec sleep 60
SH
cat >"$TMP/bin/systemctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$HOME/service-calls"
if [ "${SERVICE_MANAGER:-}" != systemd ]; then
    printf '%s\n' 'systemd is not running in this container'
    exit 0
fi
case "$2" in
    show) printf '%s\n' 'Version=fixture' ;;
    is-active) test -f "$HOME/service-loaded" ;;
    enable) touch "$HOME/service-loaded" ;;
esac
SH
cat >"$TMP/bin/launchctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$HOME/service-calls"
case "$1:$2" in
    print:*/com.dotfiles.workline-activity) test -f "$HOME/service-loaded" ;;
    bootstrap:*) touch "$HOME/service-loaded" ;;
    bootout:*) rm -f "$HOME/service-loaded" ;;
esac
SH
chmod +x "$TMP/bin/"*

HOME="$TMP/personal" WORK_MACHINE=0 OS=linux setup_workline_activity
[ ! -e "$TMP/personal/$service_path" ] || fail "installed on a personal machine"

count_starts() {
    [ -f "$TMP/cde/reporter-starts" ] && grep -c . "$TMP/cde/reporter-starts" || true
}
wait_for_starts() {
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ "$(count_starts)" = "$1" ] && return 0
        sleep 0.1
    done
    fail "expected $1 reporter starts, saw $(count_starts)"
}

export HOME="$TMP/cde"
export CODEX_HOME="$TMP/cde/codex"
WORK_MACHINE=1 OS=linux setup_workline_activity
wait_for_starts 1
grep -F "$CODEX_HOME|$WORKLINE_CONFIG|" "$HOME/reporter-starts" >/dev/null ||
    fail "reporter lost its host configuration"
WORK_MACHINE=1 OS=linux setup_workline_activity
python3 "$HOME/$service_path/activity-service.py" ensure
[ "$(count_starts)" = 1 ] || fail "reinstall or login started a duplicate"
kill "$(cat "$HOME/reporter-pid")"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    python3 "$HOME/$service_path/activity-service.py" ensure
    [ "$(count_starts)" = 2 ] && break
    sleep 0.1
done
wait_for_starts 2
[ "$(sort -u "$HOME/reporter-starts" | grep -c .)" = 1 ] ||
    fail "restart changed the reporter's source or configuration"

export HOME="$TMP/linux"
export XDG_CONFIG_HOME="$HOME/.config"
export SERVICE_MANAGER=systemd
WORK_MACHINE=1 OS=linux setup_workline_activity
WORK_MACHINE=1 OS=linux setup_workline_activity
unit="$XDG_CONFIG_HOME/systemd/user/workline-activity.service"
grep -q '^Restart=always$' "$unit" || fail "systemd does not restart the reporter"
grep -q '^WantedBy=default.target$' "$unit" || fail "systemd service does not start at login"
grep -q '^--user enable --now workline-activity.service$' "$HOME/service-calls" ||
    fail "systemd service was not enabled"
if grep -q '^--user restart ' "$HOME/service-calls"; then
    fail "unchanged reinstall restarted the systemd service"
fi

export HOME="$TMP/mac"
WORK_MACHINE=1 OS=macos setup_workline_activity
WORK_MACHINE=1 OS=macos setup_workline_activity
python3 - "$HOME/Library/LaunchAgents/com.dotfiles.workline-activity.plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "rb") as stream:
    config = plistlib.load(stream)
assert config["RunAtLoad"] and config["KeepAlive"]
assert config["ProgramArguments"][-1] == "run"
PY
[ "$(grep -c '^bootstrap ' "$HOME/service-calls")" = 1 ] ||
    fail "the launch agent did not load once across repeat installs"

if [ -n "$real_node" ]; then
    mkdir -p "$TMP/native" "$TMP/transport"
    cat >"$TMP/native/server.mjs" <<'JS'
globalThis.WebSocket = class extends EventTarget {
  constructor() {
    super();
    queueMicrotask(() => this.dispatchEvent(new Event("open")));
  }
  send(message) {
    const { id, method, params } = JSON.parse(message);
    if (id === undefined) return;
    let result;
    let error;
    if (method === "thread/loaded/list") result = { data: ["active"] };
    else if (method === "thread/read") {
      const status = { active: "active", saved: "notLoaded" }[params.threadId];
      if (status) result = { thread: { id: params.threadId, status: { type: status } } };
      else error = { message: "Thread not found" };
    } else result = {};
    queueMicrotask(() => this.dispatchEvent(new MessageEvent("message", {
      data: JSON.stringify({ id, result, error }),
    })));
  }
  close() {}
};
JS
    cat >"$TMP/transport/api.py" <<'PY'
import json
import os
import sys

def request(path, key):
    if path == "/api/work":
        linked = [{"id": "saved", "hostId": "saved-codex-host"},
                  {"id": "not-on-this-host", "hostId": "another-host"}]
        if os.environ.get("AMBIGUOUS"):
            linked.append({"id": "active", "hostId": "another-host"})
        return {"work": [{"stage": "Building", "sessions": linked}]}
    assert path == "/api/session-activity" and key
    body = json.load(sys.stdin)
    assert body["working"] == ["active"]
    assert body.get("host_id") == (None if os.environ.get("AMBIGUOUS") else "saved-codex-host")
    return {"accepted": True}
PY
    unset WORKLINE_CODEX_HOST_ID
    export CODEX_HOME="$TMP/native"
    reporter="$ROOT/shared-skills/workline/scripts/report-session-activity.mjs"
    "$real_node" --import "$TMP/native/server.mjs" "$reporter" --once --helper "$TMP/transport"
    AMBIGUOUS=1 "$real_node" --import "$TMP/native/server.mjs" "$reporter" --once --helper "$TMP/transport"
fi

echo "Workline activity install, single-worker lock, and startup recovery passed."
