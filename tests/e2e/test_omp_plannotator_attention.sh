#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OMP_BIN=${OMP_PLANNOTATOR_TEST_BIN:-$(command -v omp 2>/dev/null || true)}
PLANNOTATOR_BIN=${OMP_PLANNOTATOR_NATIVE_BIN:-$(command -v plannotator 2>/dev/null || true)}
if [ -z "$OMP_BIN" ] && [ -x "$HOME/.local/bin/omp" ]; then OMP_BIN="$HOME/.local/bin/omp"; fi
if [ -z "$PLANNOTATOR_BIN" ] && [ -x "$HOME/.local/bin/plannotator" ]; then PLANNOTATOR_BIN="$HOME/.local/bin/plannotator"; fi
if [ -z "$OMP_BIN" ] || [ -z "$PLANNOTATOR_BIN" ]; then
  echo "SKIP: Plannotator attention runtime checks require omp and native plannotator"
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/bin"
ln -s "$PLANNOTATOR_BIN" "$TMP/bin/plannotator"
cat > "$TMP/bin/plannotator-safe" <<'EOF'
#!/bin/sh
while [ ! -f "$FIXTURE_LAUNCH_GATE" ]; do sleep .1; done
exec "$FIXTURE_ROOT_SAFE" "$@"
EOF
chmod +x "$TMP/bin/plannotator-safe"
cat > "$TMP/bin/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FIXTURE_NOTIFY_LOG"
EOF
chmod +x "$TMP/bin/herdr"
cat > "$TMP/provider.ts" <<'EOF'
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent"
import { AsyncJobManager } from "@oh-my-pi/pi-coding-agent/async"
import { appendFileSync } from "node:fs"

export default function (pi: ExtensionAPI) {
  const record = (kind: string, value: unknown) => appendFileSync(process.env.FIXTURE_EVENTS!, JSON.stringify({kind, value, time: Date.now()}) + "\n")
  pi.registerProvider(process.env.FIXTURE_PROVIDER ?? "plannotator-fixture", {
    baseUrl: process.env.FIXTURE_BASE_URL,
    api: "openai-completions",
    apiKey: "fixture-only",
    models: [{id: "fixture", name: "Plannotator fixture", reasoning: false, input: ["text"],
      cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 32768, maxTokens: 1024}],
  })
  pi.events.on("herdr:blocked", value => record("blocked", value))
  pi.on("session_start", (_event, ctx) => {
    record("ready", {mode: ctx.mode, kind: ctx.agent?.kind})
    ctx.setInterval(() => {
      const snapshot = ctx.getAsyncJobSnapshot()
      record("snapshot", {idle: ctx.isIdle(), pending: ctx.hasPendingMessages(), ...snapshot,
        processes: snapshot?.running.map(job => ({id: job.id, manager: !!AsyncJobManager.instance(),
          found: !!AsyncJobManager.instance()?.getJob(job.id),
          process: !!AsyncJobManager.instance()?.getJob(job.id)?.process,
          pids: AsyncJobManager.instance()?.getJob(job.id)?.process?.pids() ?? []}))})
    }, 200)
  })
  for (const event of ["tool_execution_start", "tool_execution_end", "agent_start", "agent_end", "session_switch", "session_shutdown"] as const) {
    pi.on(event, (value) => { record(event, value) })
  }
}
EOF
python3 - "$OMP_BIN" "$ROOT/omp/agent/extensions/dotfiles-harness.ts" "$TMP" "$ROOT/scripts/plannotator-safe.sh" <<'PY'
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shlex
import signal
import socket
import struct
import subprocess
import sys
import termios
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

omp, harness, temporary, safe = sys.argv[1:]
fixture = Path(temporary)
active = None


def interrupted(_signal, _frame):
    raise KeyboardInterrupt


signal.signal(signal.SIGTERM, interrupted)


class CompletionHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        case = active
        case.requests.append(body)
        (case.path / "requests.json").write_text(json.dumps(case.requests, indent=2))
        if not case.launched:
            case.launched = True
            names = [tool["function"]["name"] for tool in body.get("tools", [])]
            name = "eval" if case.env.get("FIXTURE_PROVIDER") == "openai-codex" else "bash"
            assert name in names, f"fixture requires actual {name} tool, available: {names}"
            arguments = lambda command: {"language": "js", "code": "display(await tool.bash(" + json.dumps({"command": command, "async": True}) + "))"} if name == "eval" else {"command": command, "async": True}
            delta = {"role": "assistant", "tool_calls": [{"index": i, "id": f"fixture-{i}", "type": "function",
                "function": {"name": name, "arguments": json.dumps(arguments(command))}}
                for i, command in enumerate(case.commands)]}
            finish = "tool_calls"
        else:
            if case.hold_model:
                case.model_entered.set()
                case.model_release.wait(15)
            delta = {"role": "assistant", "content": "Fixture handoff complete."}
            finish = "stop"
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        try:
            for payload, reason in [(delta, None), ({}, finish)]:
                chunk = {"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": "fixture",
                    "choices": [{"index": 0, "delta": payload, "finish_reason": reason}]}
                self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), CompletionHandler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Case:
    def __init__(self, label, context=None):
        self.path = fixture / label
        self.path.mkdir()
        self.home = self.path / "home"
        self.home.mkdir()
        self.agent = self.path / "agent"
        self.agent.mkdir()
        (self.agent / "config.yml").write_text('''setupVersion: 2
completion:
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
''')
        self.port = free_port()
        self.url = f"http://127.0.0.1:{self.port}"
        self.env = {"PATH": str(fixture / "bin") + ":/usr/bin:/bin", "HOME": str(self.home),
            "TERM": "xterm-256color", "SHELL": "/bin/bash", "PI_CODING_AGENT_DIR": str(self.agent),
            "FIXTURE_EVENTS": str(self.path / "events.jsonl"), "FIXTURE_NOTIFY_LOG": str(self.path / "notifications.log"),
            "FIXTURE_BASE_URL": f"http://127.0.0.1:{server.server_port}/v1", "AGENT_SLACK_NOTIFICATIONS": "0",
            "FIXTURE_ROOT_SAFE": safe, "FIXTURE_LAUNCH_GATE": str(self.path / "launch"),
            "HERDR_ENV": "1", "HERDR_PANE_ID": "fixture:root", "HERDR_SOCKET_PATH": str(self.path / "herdr.sock"),
            "PLANNOTATOR_REMOTE": "0", "PLANNOTATOR_SKIP_BROWSER_OPEN": "1", "PLANNOTATOR_GLIMPSE": "0",
            "PLANNOTATOR_SHARE": "disabled", **(context or {})}
        self.provider = self.env.get("FIXTURE_PROVIDER", "plannotator-fixture")
        if self.provider == "openai-codex":
            with (self.agent / "config.yml").open("a") as config:
                config.write('providers:\n  openai-codex:\n    codeMode: "on"\n')
        (self.path / "review.txt").write_text("Finite native annotation fixture.\n")
        self.review = f"PLANNOTATOR_PORT={self.port} plannotator-safe annotate {shlex.quote(str(self.path / 'review.txt'))} --json --gate"
        self.commands = [self.review]
        self.requests = []
        self.launched = False
        self.hold_model = False
        self.model_entered = threading.Event()
        self.model_release = threading.Event()
        self.output = bytearray()
        self.process = None
        self.externals = []

    def events(self, kind=None):
        path = self.path / "events.jsonl"
        rows = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        return [row for row in rows if kind is None or row["kind"] == kind]

    def blocked(self):
        return [row["value"]["active"] for row in self.events("blocked")]

    def results(self):
        return "\n".join(part["text"] for request in self.requests for message in request.get("messages", [])
            if message.get("role") == "user" and isinstance(message.get("content"), list)
            for part in message["content"] if part.get("type") == "text"
            and part["text"].startswith("<system-notice>\nBackground job "))

    def pump(self, duration=.1):
        until = time.monotonic() + duration
        while time.monotonic() < until:
            if select.select([self.master], [], [], .05)[0]:
                try:
                    self.output.extend(os.read(self.master, 65536))
                except OSError:
                    break

    def wait(self, predicate, description, timeout=20):
        until = time.monotonic() + timeout
        while time.monotonic() < until:
            if predicate():
                return
            if self.process.poll() is not None:
                raise AssertionError(f"OMP exited during {description}: {self.process.returncode}")
            self.pump()
        raise AssertionError(f"Timed out: {description}; blocked={self.blocked()}")

    def quiet(self, duration=1.2):
        self.pump(duration)

    def start(self):
        global active
        active = self
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        self.process = subprocess.Popen([omp, "--no-session", "--tools", "bash,eval" if self.provider == "openai-codex" else "bash", "--no-lsp", "--no-skills", "--no-rules",
            "--no-extensions", "--no-title", "--model", self.provider + "/fixture", "--thinking", "off", "--auto-approve",
            "-e", harness, "-e", str(fixture / "provider.ts")], cwd=self.path, env=self.env,
            stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
        os.close(slave)
        self.wait(lambda: self.events("ready"), "extension readiness")
        self.quiet(.3)
        os.write(self.master, b"Start fixture managed review.\r")
        self.wait(lambda: self.events("agent_end"), "managed Bash handoff")
        self.quiet(.7)
        assert self.events("tool_execution_end"), "review was not launched by the runtime tool"
        snapshots = [row["value"] for row in self.events("snapshot")]
        assert any(s.get("running") and any(p["manager"] and p["found"] for p in s["processes"]) for s in snapshots), \
            "public AsyncJobManager import did not resolve the host's live managed jobs"
        assert not self.blocked(), "blocked before a native server became ready"

    def ready(self, managed=True):
        (self.path / "launch").touch()
        def listening():
            try:
                with urllib.request.urlopen(self.url, timeout=.3) as response:
                    return response.status == 200
            except (OSError, urllib.error.URLError):
                return False
        self.wait(listening, "native annotate readiness")
        records = list((self.home / ".plannotator/sessions").glob("*.json"))
        assert any(json.loads(path.read_text()).get("port") == self.port for path in records), "native readiness registry missing"
        if managed:
            self.wait(lambda: any(any(p["pids"] for p in row["value"]["processes"])
                for row in self.events("snapshot")[-5:]), "host singleton live process registration")

    def submit(self, endpoint, payload):
        request = urllib.request.Request(self.url + endpoint, json.dumps(payload).encode(), {"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=5) as response:
            assert response.status == 200

    def delivered(self, expected):
        self.wait(lambda: self.blocked() == [True, False], "balanced review attention")
        self.wait(lambda: expected in self.results(), "native stdout in async model delivery")
        self.quiet()
        assert self.blocked() == [True, False], "duplicate blocked transition"
        notices = self.path / "notifications.log"
        assert not notices.exists(), "bridge sent explicit notification instead of native Herdr attention"

    def close(self):
        self.model_release.set()
        owned_pids = {pid for row in self.events("snapshot") for job in row["value"]["processes"] for pid in job["pids"]}
        for path in (self.home / ".plannotator/sessions").glob("*.json"):
            owned_pids.add(json.loads(path.read_text())["pid"])
        if self.process is not None:
            if self.process.poll() is None:
                os.write(self.master, b"\x04")
                until = time.monotonic() + 3
                while self.process.poll() is None and time.monotonic() < until:
                    self.pump()
            # Managed jobs are descendants in the fixture's process group.
            try:
                os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.process.wait(timeout=5)
            os.close(self.master)
        for process in self.externals:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
        for pid in owned_pids:
            try:
                environment = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
                if f"HOME={self.home}".encode() in environment:
                    os.kill(pid, signal.SIGKILL)
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                pass


def run(label, exercise, context=None):
    case = Case(label, context)
    try:
        exercise(case)
        print(f"PASS: {label}")
    except Exception:
        print(case.output.decode(errors="replace")[-3000:], file=sys.stderr)
        print(json.dumps(case.events()[-12:], indent=2), file=sys.stderr)
        print(json.dumps(case.requests[-1].get("messages", []) if case.requests else [], indent=2)[-4000:], file=sys.stderr)
        raise
    finally:
        case.close()


def feedback(case):
    case.start()
    case.ready()
    case.wait(lambda: case.blocked() == [True], "review attention")
    case.quiet(1.5)
    assert case.blocked() == [True], "repeated readiness scan duplicated blocked"
    case.submit("/api/feedback", {"feedback": "fixture feedback token", "annotations": []})
    case.delivered("fixture feedback token")


def dismissal(case):
    case.start()
    case.ready()
    case.wait(lambda: case.blocked() == [True], "dismissible review attention")
    case.submit("/api/exit", {})
    case.delivered("dismissed")


def stdin_review(case):
    patch = "diff --git a/example.txt b/example.txt\n--- a/example.txt\n+++ b/example.txt\n@@ -1 +1 @@\n-old\n+fixture-stdin-token\n"
    path = case.path / "input patch.diff"
    path.write_text(patch)
    case.commands = [f"PLANNOTATOR_PORT={case.port} plannotator-safe review --patch-file - --json < {shlex.quote(str(path))}"]
    case.start()
    case.ready()
    with urllib.request.urlopen(case.url + "/api/diff", timeout=5) as response:
        data = json.load(response)
    assert data["rawPatch"] == patch, "native review did not receive redirected stdin unchanged"
    assert data["sharingEnabled"] is False, "fixture review enabled sharing"
    case.wait(lambda: case.blocked() == [True], "redirected stdin review attention")
    case.submit("/api/feedback", {"feedback": "fixture-stdin-feedback", "annotations": []})
    case.delivered("fixture-stdin-feedback")


def ordinary(case):
    case.commands.append(f"while [ ! -f {shlex.quote(str(case.path / 'finish-work'))} ]; do sleep .1; done; printf ordinary-job-complete")
    case.start()
    case.ready()
    case.quiet(1.5)
    assert not case.blocked(), "review hid concurrent ordinary work"
    case.hold_model = True
    (case.path / "finish-work").touch()
    case.wait(case.model_entered.is_set, "ordinary async result model delivery")
    case.quiet(1.2)
    assert not case.blocked(), "review requested attention during async result delivery"
    case.hold_model = False
    case.model_release.set()
    case.wait(lambda: case.blocked() == [True], "attention after unrelated work delivered")
    case.submit("/api/approve", {})
    case.delivered("approved")


def resume(case):
    case.start()
    case.ready()
    case.wait(lambda: case.blocked() == [True], "review attention before resume")
    case.hold_model = True
    os.write(case.master, b"Resume foreground fixture work.\r")
    case.wait(case.model_entered.is_set, "foreground model request")
    case.wait(lambda: case.blocked() == [True, False], "foreground resume clears attention")
    case.quiet(1.2)
    assert case.blocked() == [True, False], "reblocked during foreground model work"
    case.hold_model = False
    case.model_release.set()
    case.wait(lambda: case.blocked() == [True, False, True], "return to review-only wait")
    case.submit("/api/approve", {})
    case.wait(lambda: case.blocked() == [True, False, True, False], "feedback clears resumed review")


def composite_sibling(case):
    case.commands = [f"{case.review} & review_pid=$!; while [ ! -f {shlex.quote(str(case.path / 'finish-work'))} ]; do sleep .1; done; wait $review_pid"]
    case.start()
    case.ready()
    case.quiet(1.5)
    assert not case.blocked(), "same-job ordinary work was hidden by a ready review"
    (case.path / "finish-work").touch()
    case.quiet(1.2)
    assert not case.blocked(), "composite job was classified as a dedicated review"
    case.submit("/api/approve", {})
    case.wait(lambda: "approved" in case.results(), "composite review result delivery")
    assert not case.blocked()


def composite_followup(case):
    case.commands = [f"{case.review}; while [ ! -f {shlex.quote(str(case.path / 'finish-work'))} ]; do sleep .1; done; printf fixture-followup-done"]
    case.start()
    case.ready()
    case.quiet(1.5)
    assert not case.blocked(), "review with ordinary followup was classified as dedicated"
    case.submit("/api/approve", {})
    case.quiet(1.2)
    assert not case.blocked(), "ordinary work after review completion requested attention"
    (case.path / "finish-work").touch()
    case.wait(lambda: "fixture-followup-done" in case.results(), "post-review ordinary result delivery")


def removed_readiness(case):
    case.start()
    case.ready()
    case.wait(lambda: case.blocked() == [True], "review attention before readiness removal")
    manifest = next(path for path in (case.home / ".plannotator/sessions").glob("*.json")
        if json.loads(path.read_text())["port"] == case.port)
    content = manifest.read_bytes()
    manifest.unlink()
    case.wait(lambda: case.blocked() == [True, False], "readiness removal clears attention")
    case.quiet(1.2)
    assert case.blocked() == [True, False], "missing registry entry reblocked"
    manifest.write_bytes(content)
    case.wait(lambda: case.blocked() == [True, False, True], "restored readiness attention")
    case.submit("/api/approve", {})
    case.wait(lambda: case.blocked() == [True, False, True, False], "restored review feedback clears")


def reset(case):
    case.start()
    case.ready()
    case.wait(lambda: case.blocked() == [True], "review attention before reset")
    os.write(case.master, b"/new\r")
    case.wait(lambda: case.blocked() == [True, False], "session reset clears attention")
    case.wait(lambda: case.events("session_switch"), "actual runtime session switch")
    case.quiet(1.2)
    assert case.blocked() == [True, False], "previous session review leaked into new owner"


def no_server(case):
    case.commands = [f"PLANNOTATOR_PORT={case.port} plannotator-safe annotate {shlex.quote(str(case.path / 'missing-file.txt'))} --json --gate"]
    case.start()
    (case.path / "launch").touch()
    case.wait(lambda: "missing-file.txt" in case.results(), "native startup failure async result delivery")
    case.quiet()
    assert not case.blocked(), "failed job without server requested human attention"


def isolated(case):
    case.start()
    case.ready()
    case.quiet(1.5)
    assert not case.blocked(), "non-root scope contributed review attention"
    case.submit("/api/approve", {})
    case.wait(lambda: "approved" in case.results(), "isolated async delivery")
    assert not case.blocked()


def foreign(case):
    case.commands = [f"while [ ! -f {shlex.quote(str(case.path / 'finish-work'))} ]; do sleep .1; done"]
    case.start()
    process = subprocess.Popen(["/bin/sh", "-c", case.review], env=case.env, cwd=case.path,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    case.externals.append(process)
    case.ready(managed=False)
    case.quiet(1.5)
    assert not case.blocked(), "unrelated pane's ready review was assigned to this session"
    case.submit("/api/approve", {})
    process.wait(timeout=5)
    (case.path / "finish-work").touch()
    case.quiet()
    assert not case.blocked()


def shutdown(case):
    case.start()
    case.ready()
    case.wait(lambda: case.blocked() == [True], "review attention before shutdown")
    os.write(case.master, b"\x04")
    until = time.monotonic() + 10
    while case.process.poll() is None and time.monotonic() < until:
        case.pump()
    assert case.process.poll() == 0, "fixture OMP did not shut down cleanly"
    assert case.blocked() == [True, False], "shutdown left an unbalanced review attention state"
    assert case.events("session_shutdown"), "runtime shutdown hook not exercised"


try:
    run("feedback readiness and deduplication", feedback)
    run("Code Mode async Bash host singleton", feedback, {"FIXTURE_PROVIDER": "openai-codex"})
    run("dismissal preserves async result", dismissal)
    run("redirected stdin preserves native review", stdin_review)
    run("ordinary job prevents review-only attention", ordinary)
    run("foreground resume clears attention", resume)
    run("same-job sibling work never blocks", composite_sibling)
    run("ordinary work after review never blocks", composite_followup)
    run("readiness removal clears attention", removed_readiness)
    run("session reset clears owner attention", reset)
    run("failed job never blocks", no_server)
    run("unrelated pane review excluded", foreign)
    run("nested OMP review excluded", isolated, {"OMPCODE": "1"})
    run("standalone review excluded", isolated, {"HERDR_ENV": "0"})
    run("shutdown balances review attention", shutdown)
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)
    leftovers = []
    for line in subprocess.check_output(["ps", "-axo", "pid=,stat=,args="], text=True).splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) == 3 and str(fixture) in fields[2] and int(fields[0]) != os.getpid() and not fields[1].startswith("Z"):
            leftovers.append(int(fields[0]))
    for pid in leftovers:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    assert not leftovers, f"fixture cleanup leaked live processes: {leftovers}"
PY
