#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OMP_BIN=${OMP_NOTIFICATION_TEST_BIN:-$(command -v omp 2>/dev/null || true)}
if [ -z "$OMP_BIN" ] && [ -x "$HOME/.local/bin/omp" ]; then
  OMP_BIN="$HOME/.local/bin/omp"
fi
if [ -z "$OMP_BIN" ]; then
  echo "SKIP: OMP notification runtime checks require omp"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/agent"
cat > "$TMP/bin/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FIXTURE_NOTIFY_LOG"
EOF
chmod +x "$TMP/bin/herdr"
cat > "$TMP/agent/config.yml" <<'EOF'
setupVersion: 2
completion:
  notify: "on"
ask:
  notify: "on"
error:
  notify: "on"
startup:
  quiet: true
  setupWizard: false
  checkUpdate: false
dev:
  autoqa: false
recap:
  enabled: false
power:
  sleepPrevention: "off"
EOF
cat > "$TMP/off.yml" <<'EOF'
completion:
  notify: "off"
EOF
cat > "$TMP/provider.ts" <<'EOF'
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent"
import { lookup } from "@oh-my-pi/pi-coding-agent/config/registry"

export default function (pi: ExtensionAPI) {
  pi.registerProvider("notification-fixture", {
    baseUrl: process.env.FIXTURE_BASE_URL,
    api: "openai-completions",
    apiKey: "fixture-only",
    models: [{
      id: "fixture",
      name: "Notification fixture",
      reasoning: false,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 32768,
      maxTokens: 128,
    }],
  })
  pi.on("session_start", async () => {
    const readyPath = process.env.FIXTURE_READY
    if (!readyPath) throw new Error("Missing fixture readiness path")
    pi.setSessionName("Notification fixture")
    await Bun.write(readyPath, JSON.stringify({
      completion: lookup("completion.notify")?.get(pi.pi.settings),
      ask: lookup("ask.notify")?.get(pi.pi.settings),
      error: lookup("error.notify")?.get(pi.pi.settings),
    }))
  })
  pi.on("agent_end", async () => {
    const donePath = process.env.FIXTURE_DONE
    if (!donePath) throw new Error("Missing fixture completion path")
    await Bun.write(donePath, "complete")
  })
}
EOF

python3 - "$OMP_BIN" "$ROOT/omp/agent/extensions/dotfiles-harness.ts" "$TMP" <<'PY'
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import sys
import termios
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

omp, harness, fixture_path = sys.argv[1:]
fixture = Path(fixture_path)
config = fixture / "agent/config.yml"
persisted_config = config.read_bytes()


class CompletionHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for delta, finish_reason in [
            ({"role": "assistant", "content": "Fixture complete."}, None),
            ({}, "stop"),
        ]:
            chunk = {
                "id": "fixture",
                "object": "chat.completion.chunk",
                "created": 1,
                "model": "fixture",
                "choices": [{"index": 0, "delta": delta, "finish_reason": finish_reason}],
            }
            self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    def log_message(self, *args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), CompletionHandler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()


def complete(label, context, expected_setting, expected_delivery, overlay=None):
    case = fixture / label
    case.mkdir()
    env = {
        "PATH": str(fixture / "bin") + ":/usr/bin:/bin",
        "HOME": str(fixture / "home"),
        "TERM": "xterm-256color",
        "TERM_PROGRAM": "WezTerm",
        "PI_CODING_AGENT_DIR": str(fixture / "agent"),
        "FIXTURE_BASE_URL": f"http://127.0.0.1:{server.server_port}/v1",
        "FIXTURE_READY": str(case / "ready.json"),
        "FIXTURE_DONE": str(case / "done"),
        "FIXTURE_NOTIFY_LOG": str(case / "notifications.log"),
        "AGENT_SLACK_NOTIFICATIONS": "0",
        "PI_NOTIFICATIONS": "on",
        **context,
    }
    command = [
        omp, "--no-session", "--no-tools", "--no-lsp", "--no-skills", "--no-rules",
        "--no-extensions", "--no-title", "--model", "notification-fixture/fixture",
        "--thinking", "off", "-e", harness, "-e", str(fixture / "provider.ts"),
    ]
    if overlay:
        command.extend(["--config", str(overlay)])
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    process = subprocess.Popen(
        command, cwd=case, env=env, stdin=slave, stdout=slave, stderr=slave,
        start_new_session=True,
    )
    os.close(slave)
    output = bytearray()
    submitted = False
    deadline = time.monotonic() + 30
    exit_requested = False
    settled_at = None
    try:
        while process.poll() is None and time.monotonic() < deadline:
            if (case / "ready.json").exists() and not submitted:
                time.sleep(0.3)
                os.write(master, b"Please respond with fixture completion.\r")
                submitted = True
            if (case / "done").exists() and settled_at is None:
                settled_at = time.monotonic()
            if settled_at is not None and time.monotonic() - settled_at > 1 and not exit_requested:
                os.write(master, b"\x04")
                exit_requested = True
            if select.select([master], [], [], 0.1)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError:
                    break
        if exit_requested:
            process.wait(timeout=5)
        if process.poll() is None:
            raise AssertionError(f"{label}: OMP did not complete within 30 seconds")
        if process.returncode != 0 or b"Fixture complete." not in output:
            raise AssertionError(f"{label}: OMP did not finish its fixture turn")
        settings = json.loads((case / "ready.json").read_text())
        assert settings == {"completion": expected_setting, "ask": "on", "error": "on"}, settings
        log = case / "notifications.log"
        notices = log.read_text().splitlines() if log.exists() else []
        terminal_notice = b"\x1b]9;Notification fixture: Complete\x1b\\" in output
        if expected_delivery == "herdr":
            assert notices == ["notification show Notification fixture --body Complete --sound done"], notices
            assert not terminal_notice
        elif expected_delivery == "terminal":
            assert not notices, notices
            assert terminal_notice, "standalone completion notification was lost"
        else:
            assert not notices and not terminal_notice, "OMP emitted a duplicate completion notification"
        assert config.read_bytes() == persisted_config, "runtime override changed persisted settings"
        print(f"PASS: {label}")
    except Exception:
        print(bytes(output).decode(errors="replace"), file=sys.stderr)
        raise
    finally:
        if process.poll() is None:
            process.kill()
        process.wait(timeout=5)
        os.close(master)


try:
    root = {"HERDR_ENV": "1", "HERDR_PANE_ID": "fixture:p1", "HERDR_SOCKET_PATH": str(fixture / "herdr.sock")}
    complete("Herdr root delegates completion", root, "off", "none")
    complete("Standalone completion remains enabled", {}, "on", "terminal")
    complete("Standalone opt-out is preserved", {}, "off", "none", fixture / "off.yml")
    complete("Incomplete Herdr context keeps OMP notification", {"HERDR_ENV": "1", "HERDR_PANE_ID": "fixture:p1"}, "on", "herdr")
    complete("Nested OMP keeps its own completion policy", {**root, "OMPCODE": "1"}, "on", "herdr")
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)
PY
