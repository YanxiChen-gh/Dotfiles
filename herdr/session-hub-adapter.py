#!/usr/bin/env python3
"""Bridge the session hub to the desktop launcher, not to Treehouse directly."""
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time

LAUNCHER = Path(__file__).resolve().with_name("new-agent-tab.sh")
MAX_INPUT = 65536
HOST_FIELDS = {"instanceId", "generation", "pid", "sessionId", "access"}
TARGET_FIELDS = {"paneId", "terminalId", "tabId", "workspaceId", "closesTab", "closesWorkspace"}
HOST_ID = re.compile(r"^[a-z0-9-]{8,64}$")
NATIVE_SESSION_REFERENCE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z_"
    r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$"
)


class CloseError(ValueError):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


def command_json(argv, deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError("Herdr inventory timed out")
    try:
        completed = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, timeout=min(15, remaining), check=True)
        return json.loads(completed.stdout)
    except (subprocess.SubprocessError, ValueError, OSError) as error:
        raise ValueError("Could not read Herdr inventory") from error


def workspace_inventory(deadline):
    search_path = str(Path.home() / ".local/bin") + os.pathsep + os.environ.get("PATH", "")
    herdr = os.environ.get("HERDR_BIN_PATH") or shutil.which("herdr", path=search_path) or "herdr"
    data = command_json([herdr, "workspace", "list"], deadline)
    workspaces = []
    for workspace in data["result"]["workspaces"]:
        identifier = workspace["workspace_id"]
        panes = command_json([herdr, "pane", "list", "--workspace", identifier], deadline)["result"]["panes"]
        cwd = next((pane["cwd"] for pane in panes if isinstance(pane.get("cwd"), str) and pane["cwd"]), "")
        workspaces.append({"id": identifier, "name": workspace.get("name") or workspace.get("label") or identifier,
                           "cwd": cwd})
    return workspaces


def inventory():
    deadline = time.monotonic() + 24
    return {"repositories": command_json(["bash", str(LAUNCHER), "--inventory"], deadline),
            "workspaces": workspace_inventory(deadline)}


def validate(spec):
    if not isinstance(spec, dict):
        raise ValueError("Creation request must be an object")
    allowed = {"repository", "checkout", "agent", "editor", "prompt", "workspaceId", "cloneRepository", "cloneRoot"}
    if spec.keys() - allowed:
        raise ValueError("Unknown creation field")
    for key in ("repository", "checkout", "prompt", "workspaceId", "cloneRepository", "cloneRoot"):
        if key in spec and (not isinstance(spec[key], str) or "\x00" in spec[key]):
            raise ValueError(key + " must be a string without NUL bytes")
    for key in ("agent", "editor"):
        if key in spec and type(spec[key]) is not bool:
            raise ValueError(key + " must be a boolean")
    if spec.get("checkout", "fresh") not in ("fresh", "primary"):
        raise ValueError("checkout must be fresh or primary")
    workspace = spec.get("workspaceId")
    if workspace is not None and (not workspace or workspace.startswith("-")):
        raise ValueError("workspaceId must identify an existing workspace")
    if workspace and (spec.get("cloneRepository") or spec.get("cloneRoot")):
        raise ValueError("An existing workspace cannot clone a repository")
    if workspace and (spec.get("agent", True) is not True or spec.get("editor", False)):
        raise ValueError("An existing workspace creates an OMP tab without an editor split")
    if not workspace and not (spec.get("repository") or spec.get("cloneRepository")):
        raise ValueError("Choose a repository or an existing workspace")
    if spec.get("cloneRoot") and not spec.get("cloneRepository"):
        raise ValueError("cloneRoot requires cloneRepository")
    clone = spec.get("cloneRepository", "")
    if clone and (clone.startswith("-") or any(character.isspace() for character in clone)):
        raise ValueError("Invalid GitHub repository reference")
    if not spec.get("agent", True) and spec.get("prompt"):
        raise ValueError("A shell workspace cannot receive an agent prompt")
    return spec


def create(spec):
    spec = validate(spec)
    args = ["bash", str(LAUNCHER), "--omp"]
    if spec.get("workspaceId"):
        args += ["--workspace-id", spec["workspaceId"]]
    else:
        if spec.get("cloneRepository"):
            root = spec.get("cloneRoot") or os.environ.get("HERDR_REPO_HOME")
            if not root:
                root = "/workspaces" if os.environ.get("IS_ON_ONA") == "true" or os.environ.get("CURSOR_CLOUD") == "1" else str(Path.home() / "workspaces")
            args += ["--clone-repository", spec["cloneRepository"], "--clone-root", str(Path(root).expanduser().absolute())]
        else:
            args += ["--repo-root", str(Path(spec["repository"]).expanduser().absolute())]
        args += ["--with-worktree" if spec.get("checkout", "fresh") == "fresh" else "--without-worktree"]
    args += ["--with-agent" if spec.get("agent", True) else "--without-agent",
             "--with-editor" if spec.get("editor", False) else "--without-editor"]
    state = Path(tempfile.mkdtemp(prefix="omp-hub-launch-"))
    result = state / "result.json"
    args += ["--result-file", str(result)]
    if spec.get("prompt"):
        prompt = state / "prompt.txt"
        descriptor = os.open(str(prompt), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            stream.write(spec["prompt"])
        args += ["--initial-prompt-file", str(prompt)]
    # Only this detached launcher owns Treehouse's lifetime, never an HTTP job.
    environment = os.environ.copy()
    environment.pop("DOTFILES_HERDR_RESULT_FILE", None)
    with (state / "launcher.log").open("xb") as log:
        os.chmod(str(state / "launcher.log"), 0o600)
        process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                   start_new_session=True, env=environment)
    deadline = time.monotonic() + 150
    ready = False
    try:
        while time.monotonic() < deadline:
            exited = process.poll() is not None
            if result.is_file():
                with result.open() as stream:
                    payload = json.load(stream)
                if payload.get("status") != "ready":
                    message = "Workspace setup failed"
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        message += "; launcher cleanup is still running, inspect Herdr before retrying"
                    raise ValueError(message + "; private log: " + str(state / "launcher.log"))
                value = payload["result"]
                if not all(isinstance(value.get(key), str) and value[key] for key in ("workspaceId", "paneId", "cwd")):
                    raise ValueError("Launcher returned an invalid creation result")
                ready = True
                return value
            if exited:
                raise ValueError("Workspace launcher exited before readiness; private log: " + str(state / "launcher.log"))
            time.sleep(0.1)
        raise ValueError("Workspace setup is still running; inspect Herdr before retrying. Private log: " + str(state / "launcher.log"))
    finally:
        # Keep timed-out setup inputs until the detached owner has consumed them.
        if ready:
            shutil.rmtree(str(state), ignore_errors=True)


def native_id(value):
    return (isinstance(value, str) and 0 < len(value) <= 256
            and not value.startswith("-") and not any(character.isspace() or ord(character) < 32
                                                       for character in value))


def close_spec(spec, closing):
    fields = {"host", "target"} if closing else {"host"}
    if not isinstance(spec, dict) or spec.keys() != fields:
        raise CloseError(400, "Invalid close request")
    host = spec["host"]
    if (not isinstance(host, dict) or host.keys() != HOST_FIELDS
            or not isinstance(host.get("instanceId"), str) or not HOST_ID.fullmatch(host["instanceId"])
            or type(host.get("generation")) is not int
            or type(host.get("pid")) is not int or host["pid"] < 1
            or not isinstance(host.get("sessionId"), str) or not host["sessionId"].strip()
            or len(host["sessionId"]) > 4096 or "\x00" in host["sessionId"]
            or host.get("access") not in ("control", "view")):
        raise CloseError(400, "Invalid session identity")
    if host["access"] != "control":
        raise CloseError(403, "View-only sessions cannot be closed")
    if closing:
        target = spec["target"]
        if (not isinstance(target, dict) or target.keys() != TARGET_FIELDS
                or not all(native_id(target[key]) for key in ("paneId", "terminalId", "tabId", "workspaceId"))
                or not all(type(target[key]) is bool for key in ("closesTab", "closesWorkspace"))):
            raise CloseError(400, "Invalid close confirmation target")
    return host


def close_command(argv, deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise CloseError(504, "Session close timed out. Refresh and inspect Herdr before retrying.")
    try:
        result = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, timeout=min(15, remaining), check=True)
        value = json.loads(result.stdout)
    except subprocess.TimeoutExpired as error:
        raise CloseError(504, "Session close timed out. Refresh and inspect Herdr before retrying.") from error
    except (subprocess.SubprocessError, ValueError, OSError) as error:
        raise CloseError(502, "Could not complete the session close request. Refresh and inspect Herdr before retrying.") from error
    if not isinstance(value, dict) or "error" in value:
        raise CloseError(502, "Unsupported session close response")
    return value


def current_close_host(host, deadline):
    registry = close_command(["omp", "collab", "list", "--json"], deadline)
    if registry.get("version") != 1 or not isinstance(registry.get("hosts"), list):
        raise CloseError(502, "Unsupported OMP collaboration registry")
    if not all(isinstance(item, dict) for item in registry["hosts"]):
        raise CloseError(502, "Invalid OMP collaboration registry")
    matches = [item for item in registry["hosts"] if item.get("instanceId") == host["instanceId"]]
    if not matches:
        raise CloseError(404, "Session is no longer available. Refresh the list.")
    if len(matches) != 1:
        raise CloseError(409, "Session identity is ambiguous. Refresh the list.")
    current = matches[0]
    if current.get("access") == "view":
        raise CloseError(403, "View-only sessions cannot be closed")
    if any(type(current.get(key)) is not type(host[key]) or current.get(key) != host[key]
           for key in HOST_FIELDS):
        raise CloseError(409, "Session changed. Refresh the list before closing it.")


def metadata_session_id(agent):
    session = agent.get("agent_session")
    if (agent.get("agent") != "omp" or not isinstance(session, dict)
            or session.get("agent") != "omp" or session.get("source") != "herdr:omp"):
        return None
    value = session.get("value")
    if not isinstance(value, str) or not value:
        return None
    if session.get("kind") == "id":
        return value
    if session.get("kind") != "path" or not Path(value).is_absolute():
        return None
    try:
        descriptor = os.open(value, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "rb") as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                return None
            remaining = 16384
            for index in range(2):
                line = stream.readline(remaining + 1)
                remaining -= len(line)
                if remaining < 0:
                    return None
                entry = json.loads(line)
                if not isinstance(entry, dict):
                    return None
                if entry.get("type") == "session":
                    identifier = entry.get("id")
                    return identifier if isinstance(identifier, str) and identifier else None
                if index != 0 or entry.get("type") != "title":
                    return None
    except FileNotFoundError:
        # OMP publishes this canonical resume reference before an empty session is persisted.
        match = NATIVE_SESSION_REFERENCE.fullmatch(Path(value).name)
        return match.group(1) if match else None
    except (OSError, ValueError):
        return None
    return None


def snapshot_rows(snapshot, key, identifier):
    rows = snapshot.get(key)
    if not isinstance(rows, list):
        raise CloseError(409, "Herdr does not expose supported close metadata")
    indexed = {}
    for row in rows:
        if not isinstance(row, dict) or not native_id(row.get(identifier)) or row[identifier] in indexed:
            raise CloseError(409, "Herdr close target is ambiguous or unsupported")
        indexed[row[identifier]] = row
    return indexed


def resolve_close_target(host, herdr, deadline):
    current_close_host(host, deadline)
    response = close_command([herdr, "api", "snapshot"], deadline)
    result = response.get("result")
    snapshot = result.get("snapshot") if isinstance(result, dict) else None
    if not isinstance(snapshot, dict):
        raise CloseError(409, "Herdr does not expose supported close metadata")
    panes = snapshot_rows(snapshot, "panes", "pane_id")
    tabs = snapshot_rows(snapshot, "tabs", "tab_id")
    workspaces = snapshot_rows(snapshot, "workspaces", "workspace_id")
    agents = snapshot_rows(snapshot, "agents", "pane_id")
    terminals = set()
    for pane in panes.values():
        if (not all(native_id(pane.get(key)) for key in ("terminal_id", "tab_id", "workspace_id"))
                or pane["terminal_id"] in terminals
                or pane["tab_id"] not in tabs or pane["workspace_id"] not in workspaces
                or tabs[pane["tab_id"]].get("workspace_id") != pane["workspace_id"]):
            raise CloseError(409, "Herdr close topology is ambiguous or unsupported")
        terminals.add(pane["terminal_id"])
    matches = []
    for agent in agents.values():
        if metadata_session_id(agent) != host["sessionId"]:
            continue
        pane = panes.get(agent["pane_id"])
        if (pane is None or any(agent.get(key) != pane[key]
                                for key in ("terminal_id", "tab_id", "workspace_id"))
                or agent.get("agent_session") != pane.get("agent_session") or pane.get("agent") != "omp"):
            raise CloseError(409, "Herdr session identity changed. Refresh before closing it.")
        response = close_command([herdr, "pane", "process-info", "--pane", pane["pane_id"]], deadline)
        result = response.get("result")
        process = result.get("process_info") if isinstance(result, dict) else None
        if (not isinstance(process, dict) or process.get("pane_id") != pane["pane_id"]
                or not isinstance(process.get("foreground_processes"), list)
                or not all(isinstance(item, dict) and type(item.get("pid")) is int and item["pid"] > 0
                           for item in process["foreground_processes"])):
            raise CloseError(409, "Herdr foreground process identity is unsupported")
        if any(item["pid"] == host["pid"] for item in process["foreground_processes"]):
            matches.append(pane)
    if len(matches) != 1:
        raise CloseError(409, "No unique foreground Herdr pane matches this session")
    pane = matches[0]
    tab_panes = [item for item in panes.values() if item["tab_id"] == pane["tab_id"]]
    workspace_panes = [item for item in panes.values() if item["workspace_id"] == pane["workspace_id"]]
    workspace_tabs = [item for item in tabs.values() if item.get("workspace_id") == pane["workspace_id"]]
    tab = tabs[pane["tab_id"]]
    workspace = workspaces[pane["workspace_id"]]
    if (type(tab.get("pane_count")) is not int or tab["pane_count"] != len(tab_panes)
            or type(workspace.get("pane_count")) is not int or workspace["pane_count"] != len(workspace_panes)
            or type(workspace.get("tab_count")) is not int or workspace["tab_count"] != len(workspace_tabs)
            or any(not any(item["tab_id"] == candidate["tab_id"] for item in workspace_panes)
                   for candidate in workspace_tabs)):
        raise CloseError(409, "Herdr close topology changed or is unsupported")
    return {"paneId": pane["pane_id"], "terminalId": pane["terminal_id"], "tabId": pane["tab_id"],
            "workspaceId": pane["workspace_id"], "closesTab": len(tab_panes) == 1,
            "closesWorkspace": len(workspace_panes) == 1}


def close_session(spec, closing=False):
    host = close_spec(spec, closing)
    search_path = str(Path.home() / ".local/bin") + os.pathsep + os.environ.get("PATH", "")
    herdr = os.environ.get("HERDR_BIN_PATH") or shutil.which("herdr", path=search_path) or "herdr"
    deadline = time.monotonic() + 24
    target = resolve_close_target(host, herdr, deadline)
    if not closing:
        return {"target": target}
    if target != spec["target"]:
        raise CloseError(409, "Close target or last-pane impact changed. Preview and confirm again.")
    # Herdr accepts only a pane ID, so recheck identity and topology immediately before close.
    if resolve_close_target(host, herdr, deadline) != target:
        raise CloseError(409, "Close target or last-pane impact changed. Preview and confirm again.")
    close_command([herdr, "pane", "close", target["paneId"]], deadline)
    return {"closed": True, "paneId": target["paneId"]}


def main():
    try:
        if sys.argv[1:] == ["inventory"]:
            value = inventory()
        elif sys.argv[1:] in (["create"], ["close-preview"], ["close"]):
            raw = sys.stdin.buffer.read(MAX_INPUT + 1)
            if len(raw) > MAX_INPUT:
                if sys.argv[1] != "create":
                    raise CloseError(400, "Close request is too large")
                raise ValueError("Creation request is too large")
            try:
                spec = json.loads(raw)
            except ValueError as error:
                if sys.argv[1] != "create":
                    raise CloseError(400, "Invalid close request JSON") from error
                raise
            value = create(spec) if sys.argv[1] == "create" else close_session(spec, sys.argv[1] == "close")
        else:
            raise ValueError("Usage: session-hub-adapter.py inventory|create|close-preview|close")
        print(json.dumps(value))
        return 0
    except CloseError as error:
        print(json.dumps({"error": str(error), "status": error.status}))
        return 1
    except (ValueError, KeyError, TypeError, OSError) as error:
        message = str(error) if isinstance(error, ValueError) else "Session hub adapter could not complete the request"
        value = {"error": message[:300]}
        if sys.argv[1:] in (["close-preview"], ["close"]):
            value = {"error": "Session close could not complete. Refresh and inspect Herdr before retrying.", "status": 502}
        print(json.dumps(value))
        return 1


if __name__ == "__main__":
    sys.exit(main())
