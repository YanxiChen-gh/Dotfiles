#!/bin/sh
# E2E: native history remains isolated to the explicit origin and active branch.
# Synthetic CLI boundaries only; every case runs the real helper.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
exec python3 - "$ROOT" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

HELPER = Path(sys.argv[1]) / "herdr/troubleshoot-context.py"
PANE = "w-origin:p-source"

CLI = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time
root = Path(os.environ["FIXTURE"])
args = sys.argv[1:]
name = Path(sys.argv[0]).name
with (root / "calls").open("a") as out:
    out.write(json.dumps({"name": name, "args": args, "cwd": os.getcwd()}) + "\n")
if name == "herdr-fixture" and args == ["agent", "get", "w-origin:p-source"]:
    target = "agent"
elif name == "herdr-fixture" and args == ["pane", "read", "w-origin:p-source", "--source", "recent-unwrapped", "--lines", "200"]:
    target = "terminal"
elif name == "opencode" and args == ["export", "ses_origin", "--pure"]:
    target = "export"
else:
    (root / "forbidden").write_text(json.dumps({"name": name, "args": args}))
    sys.exit(96)
if os.environ.get("HANG") == target:
    time.sleep(30)
if os.environ.get("FAIL") == target:
    print("PRIVATE RAW FAILURE SHOULD NOT ESCAPE", file=sys.stderr)
    sys.exit(1)
sys.stdout.write((root / target).read_text())
'''


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def message(id, parent, role, content):
    return dict(type="message", id=id, parentId=parent, message=dict(role=role, content=content))


def text(value):
    return dict(type="text", text=value)


class Fixture:
    def __init__(self, base, name):
        self.root = base / name
        self.bin = self.root / "bin"
        self.bin.mkdir(parents=True)
        self.cwd = self.root / "origin cwd ' exact"
        self.cwd.mkdir()
        self.home = self.root / "home"
        self.home.mkdir()
        for name in ("herdr-fixture", "opencode"):
            path = self.bin / name
            path.write_text(CLI)
            path.chmod(0o755)
        self.env = dict(HOME=str(self.home), PATH=f"{self.bin}:/usr/local/bin:/usr/bin:/bin",
                        FIXTURE=str(self.root), LANG="C.UTF-8", PYTHONDONTWRITEBYTECODE="1")
        self.path = self.root / "origin.jsonl"
        self.terminal("terminal partial evidence")
        self.origin("omp", "path", str(self.path))

    def save(self, name, value):
        (self.root / name).write_text(json.dumps(value))

    def origin(self, agent, kind, value, pane=PANE, session_agent=None):
        self.save("agent", {"result": {"agent": {"pane_id": pane, "agent": agent,
                  "agent_session": {"source": "explicit-integration", "agent": session_agent or agent,
                                    "kind": kind, "value": value}}}})

    def terminal(self, value):
        (self.root / "terminal").write_text(value)

    def omp(self, entries, trailing="", title=False):
        rows = [dict(type="session", version=3, id="origin-session", cwd=str(self.cwd))] + entries
        if title:
            rows.insert(0, dict(type="title", v=1, title="not transcript", updatedAt="now", pad=" "))
        self.path.write_text("".join(json.dumps(row) + "\n" for row in rows) + trailing)

    def opencode(self, messages, revert=None, id="ses_origin"):
        self.origin("opencode", "id", "ses_origin")
        info = dict(id=id, directory=str(self.cwd))
        if revert is not None:
            info["revert"] = revert
        self.save("export", dict(info=info, messages=messages))

    def run(self, **env):
        result = subprocess.run([sys.executable, str(HELPER), str(self.bin / "herdr-fixture"), PANE, str(self.cwd)],
                                env={**self.env, **env}, cwd=self.root, capture_output=True, text=True, timeout=20)
        require(not (self.root / "forbidden").exists(), "helper attempted an unscoped or mutating CLI command")
        require(result.returncode == 0, f"helper failed: {result.stderr}")
        require(not result.stderr, "helper leaked diagnostics to stderr")
        payload = json.loads(result.stdout)
        require(set(payload) == {"status", "text", "note", "source", "truncated"}, "invalid context response fields")
        require(payload["status"] in ("native", "terminal", "unavailable"), "invalid context status")
        require(isinstance(payload["text"], str) and len(payload["text"]) <= 24000, "context exceeded text bound")
        require(isinstance(payload["truncated"], bool), "truncation flag is not boolean")
        require("PRIVATE RAW FAILURE" not in result.stdout, "raw subprocess error escaped")
        require(not any(self.home.rglob("*")), "helper wrote private data under HOME")
        return payload

    def calls(self):
        return [json.loads(row) for row in (self.root / "calls").read_text().splitlines()]


def oc_message(id, role, parts):
    return dict(info=dict(id=id, role=role, sessionID="ses_origin"), parts=parts)


with tempfile.TemporaryDirectory(prefix="herdr-context-e2e-") as directory:
    base = Path(directory)

    # Appending on a different branch must not expose the abandoned response,
    # provider reasoning, credential identity, config, or attachment bytes.
    f = Fixture(base, "branch")
    f.omp([
        message("root", None, "user", "origin user question"),
        message("abandoned", "root", "assistant", [text("WRONG BRANCH SECRET")]),
        dict(type="branch_summary", id="branch", parentId="root", fromId="abandoned", summary="visible branch summary"),
        dict(type="compaction", id="compact", parentId="branch", firstKeptEntryId="root", summary="visible compact summary", preserveData={"frames": ["BINARY ARCHIVE"]}),
        dict(type="credential_pin", id="pin", parentId="compact", provider="test", hash="PRIVATE CREDENTIAL PIN"),
        dict(type="model_change", id="model", parentId="pin", model="PRIVATE MODEL CONFIG"),
        message("answer", "model", "assistant", [dict(type="thinking", thinking="PRIVATE THINKING"),
                dict(type="reasoning", text="PRIVATE REASONING"), text("visible assistant answer"),
                dict(type="toolCall", id="call-visible", name="bash", arguments={"command": "visible command"}),
                dict(type="image", data="BINARY IMAGE", mimeType="image/png")]),
        {**message("result", "answer", "toolResult", [text("visible tool output"), dict(type="image", data="blob:do-not-open")]),
         "message": dict(role="toolResult", toolName="bash", toolCallId="call-visible", isError=False,
                         content=[text("visible tool output"), dict(type="image", data="blob:do-not-open")], details={"private": "PRIVATE DETAILS"})},
    ], title=True)
    result = f.run()
    require(result["status"] == "native", "valid OMP branch fell back")
    for visible in ("origin user question", "visible assistant answer", "visible command", "visible tool output",
                    "visible branch summary", "visible compact summary", "user", "assistant", "bash", "call-visible"):
        require(visible in result["text"], f"native history lost visible context: {visible}")
    for hidden in ("WRONG BRANCH", "PRIVATE", "BINARY", "blob:do-not-open", "not transcript"):
        require(hidden not in result["text"], f"native history exposed excluded content: {hidden}")
    require(result["source"] == dict(agent="omp", kind="path", value=str(f.path)), "source lost exact native identity")
    require(all(call["args"][:2] != ["pane", "read"] for call in f.calls()), "native history unnecessarily read terminal output")

    f = Fixture(base, "omp-provider-error")
    recovered = message("recovered", "question", "assistant", [])
    recovered["message"].update(stopReason="error", errorMessage="HIDDEN RECOVERED ERROR",
                                retryRecovery={"status": "recovered", "note": "Retry succeeded"})
    superseded = message("superseded", "recovered", "assistant", [])
    superseded["message"].update(stopReason="error", errorMessage="HIDDEN SUPERSEDED ERROR",
                                 retryRecovery={"status": "superseded"})
    failure = message("failed", "superseded", "assistant", [])
    failure["message"].update(stopReason="error", errorMessage="Provider quota exhausted")
    f.omp([message("question", None, "user", "Investigate the failed turn"), recovered, superseded, failure])
    result = f.run()
    require(result["status"] == "native" and "Provider quota exhausted" in result["text"],
            "OMP history omitted the latest visible provider failure")
    require("HIDDEN" not in result["text"] and "Retry succeeded" in result["text"],
            "OMP retry capture exposed hidden errors or omitted the visible recovery note")

    f = Fixture(base, "version-two-visible-message")
    hook = message("hook", None, "hookMessage", [text("Visible legacy failure")])
    hook["message"]["display"] = True
    f.path.write_text(json.dumps({"type": "session", "version": 2, "id": "legacy", "cwd": str(f.cwd)})
                      + "\n" + json.dumps(hook) + "\n")
    result = f.run()
    require(result["status"] == "native" and "Visible legacy failure" in result["text"],
            "supported OMP version two omitted a visible hook message")

    # Only a torn trailing append is safely ignored; an interior corrupt record
    # or disconnected parent must not choose an arbitrary surviving branch.
    for label, trailing, expected in (("partial", '{"type":"message",', "native"),
                                      ("malformed", '{"type":"message",\n', "terminal")):
        f = Fixture(base, label)
        f.omp([message("root", None, "user", "complete persisted question")], trailing=trailing)
        result = f.run()
        require(result["status"] == expected, f"incorrect handling of {label} append")
        if expected == "native":
            require("complete persisted question" in result["text"] and result["truncated"], "partial append lost safe prefix or limitation")
    f = Fixture(base, "broken-parent")
    f.omp([message("old", None, "user", "not active"), message("new", "missing", "user", "untrusted broken branch")])
    require(f.run()["status"] == "terminal", "disconnected branch was treated as valid history")
    f = Fixture(base, "cycle")
    f.omp([message("a", "b", "user", "cycle a"), message("b", "a", "assistant", "cycle b")])
    require(f.run()["status"] == "terminal", "parent cycle was treated as valid history")
    f = Fixture(base, "invalid-header")
    f.path.write_text(json.dumps(message("a", None, "user", "not a session")) + "\n")
    require(f.run()["status"] == "terminal", "invalid header was accepted")

    # Explicit pane identity guards both native lookup and terminal fallback.
    f = Fixture(base, "wrong-pane")
    f.omp([message("a", None, "user", "FOREIGN NATIVE")])
    f.origin("omp", "path", str(f.path), pane="w-other:p-foreign")
    result = f.run()
    require(result["status"] == "terminal" and result["source"] is None and "FOREIGN" not in result["text"], "foreign pane native context leaked")
    f = Fixture(base, "non-agent")
    f.save("agent", {"result": {"agent": {"pane_id": PANE, "agent": None, "agent_session": None}}})
    result = f.run()
    require(result["status"] == "terminal" and result["source"] is None and result["truncated"], "non-agent fallback claimed native or complete context")
    f = Fixture(base, "mismatched-agent")
    f.omp([message("a", None, "user", "MISMATCHED NATIVE")])
    f.origin("opencode", "path", str(f.path), session_agent="omp")
    result = f.run()
    require(result["status"] == "terminal" and "MISMATCHED" not in result["text"], "inconsistent native agent identity accepted")
    f = Fixture(base, "native-failure")
    result = f.run(FAIL="agent")
    require(result["status"] == "terminal" and "terminal partial evidence" in result["text"], "native command error lost partial fallback")
    f = Fixture(base, "deleted-origin-cwd")
    f.omp([message("a", None, "user", "Original directory disappeared")])
    f.cwd.rmdir()
    result = f.run()
    require(result["status"] == "native" and "Original directory disappeared" in result["text"],
            "deleted origin cwd prevented pane-scoped native lookup")
    f.path.unlink()
    result = f.run()
    require(result["status"] == "terminal" and "terminal partial evidence" in result["text"],
            "deleted origin cwd prevented pane-scoped terminal fallback")
    f = Fixture(base, "unavailable")
    f.terminal("   ")
    result = f.run(FAIL="agent")
    require(result["status"] == "unavailable" and not result["text"], "empty terminal counted as usable context")

    # The newest conversation suffix is useful under the prompt size bound.
    f = Fixture(base, "bounded")
    f.omp([message("a", None, "user", "OLD PREFIX " + "x" * 30000),
           message("b", "a", "assistant", [text("RECENT SUFFIX")])])
    result = f.run()
    require(result["status"] == "native" and result["truncated"] and "RECENT SUFFIX" in result["text"] and "OLD PREFIX" not in result["text"], "bound did not preserve recent native context")
    f = Fixture(base, "bounded-terminal")
    f.terminal("OLD TERMINAL " + "x" * 30000 + "RECENT TERMINAL")
    result = f.run()
    require(result["status"] == "terminal" and "RECENT TERMINAL" in result["text"] and "OLD TERMINAL" not in result["text"], "terminal bound lost recent suffix")

    # Size and source-type limits must fall back instead of blocking or reading
    # an unbounded native file. No real session locations are involved.
    f = Fixture(base, "oversized-native")
    with f.path.open("wb") as stream:
        stream.truncate(33 * 1024 * 1024)
    require(f.run()["status"] == "terminal", "oversized native source bypassed capture bound")
    f = Fixture(base, "fifo-native")
    os.mkfifo(f.path)
    require(f.run()["status"] == "terminal", "non-regular native source blocked or was accepted")
    f = Fixture(base, "malformed-native-message")
    f.omp([message("a", None, "user", {"not": "message content"})])
    require(f.run()["status"] == "terminal", "malformed native content did not fall back")
    f = Fixture(base, "malformed-agent-shape")
    f.save("agent", {"result": {"agent": {"pane_id": PANE, "agent": [], "agent_session": {"agent": [], "kind": "path", "value": str(f.path)}}}})
    require(f.run()["status"] == "terminal", "malformed source identity bypassed terminal fallback")

    # Export must target one exact session without plugins or a native resume.
    # Its tool inputs/results are visible; reasoning/attachments are not.
    f = Fixture(base, "opencode")
    f.opencode([
        oc_message("m1", "user", [dict(id="p1", type="text", text="OpenCode user question")]),
        oc_message("m2", "assistant", [dict(id="p2", type="reasoning", text="PRIVATE OC REASONING"),
            dict(id="p3", type="text", text="OpenCode visible answer"),
            dict(id="p4", type="tool", tool="bash", callID="oc-call", state=dict(status="completed", input={"command": "OpenCode command"}, output="OpenCode output", attachments=[{"data": "BINARY OC IMAGE"}])),
            dict(id="p5", type="tool", tool="read", state=dict(status="error", input={"path": "missing.py"}, error="OpenCode failure")),
            dict(id="p6", type="file", url="file:///do-not-read", text="BINARY OC ATTACHMENT")]),
    ])
    result = f.run()
    require(result["status"] == "native", "valid OpenCode export fell back")
    for value in ("OpenCode user question", "OpenCode visible answer", "OpenCode command", "OpenCode output", "OpenCode failure", "user", "assistant", "bash"):
        require(value in result["text"], f"OpenCode visible context lost: {value}")
    require("PRIVATE" not in result["text"] and "BINARY" not in result["text"] and "file:///" not in result["text"], "OpenCode excluded payload leaked")
    exports = [call for call in f.calls() if call["name"] == "opencode"]
    require(len(exports) == 1 and exports[0]["cwd"] == str(f.cwd), "OpenCode export escaped exact origin cwd or retried")
    require(result["source"] == dict(agent="opencode", kind="id", value="ses_origin"), "OpenCode source identity changed")

    f = Fixture(base, "opencode-provider-error")
    failure = oc_message("failed", "assistant", [])
    failure["info"]["error"] = {"name": "APIError", "data": {
        "message": "Provider connection refused", "responseHeaders": {"private": "PRIVATE HEADER"}}}
    f.opencode([oc_message("question", "user", [text("Investigate the failed turn")]), failure])
    result = f.run()
    require(result["status"] == "native" and "Provider connection refused" in result["text"],
            "OpenCode history omitted the latest visible provider failure")
    require("PRIVATE HEADER" not in result["text"], "OpenCode error capture exposed raw provider metadata")

    for label, revert, kept, omitted in (
        ("revert-message", {"messageID": "m2"}, ("before revert",), ("kept part", "undone part", "undone later")),
        ("revert-part", {"messageID": "m2", "partID": "p-cut"}, ("before revert", "kept part"), ("undone part", "undone later")),
    ):
        f = Fixture(base, label)
        f.opencode([oc_message("m1", "user", [dict(id="p1", type="text", text="before revert")]),
                    oc_message("m2", "assistant", [dict(id="p-keep", type="text", text="kept part"), dict(id="p-cut", type="text", text="undone part")]),
                    oc_message("m3", "user", [dict(id="p3", type="text", text="undone later")])], revert=revert)
        result = f.run()
        require(result["status"] == "native", "valid revert cut fell back")
        require(all(value in result["text"] for value in kept) and all(value not in result["text"] for value in omitted), "OpenCode reverted branch leaked or active prefix lost")

    f = Fixture(base, "wrong-export")
    f.opencode([oc_message("m1", "user", [text("FOREIGN EXPORT")])], id="ses_foreign")
    result = f.run()
    require(result["status"] == "terminal" and "FOREIGN" not in result["text"], "foreign OpenCode export accepted")
    f = Fixture(base, "missing-revert")
    f.opencode([oc_message("m1", "user", [text("UNCERTAIN BRANCH")])], revert={"messageID": "missing"})
    result = f.run()
    require(result["status"] == "terminal" and "UNCERTAIN" not in result["text"], "unresolved revert guessed an active branch")
    f = Fixture(base, "malformed-export")
    f.opencode([])
    (f.root / "export").write_text('{"info":')
    require(f.run()["status"] == "terminal", "malformed export did not fall back")
    f = Fixture(base, "timeout-export")
    f.opencode([])
    started = time.monotonic()
    result = f.run(HANG="export")
    require(result["status"] == "terminal" and time.monotonic() - started < 15, "native timeout did not reach bounded fallback")

print("PASS: Herdr troubleshoot context behavior coverage")
PY
