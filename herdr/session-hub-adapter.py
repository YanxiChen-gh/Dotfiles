#!/usr/bin/env python3
"""Bridge the session hub to the desktop launcher, not to Treehouse directly."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

LAUNCHER = Path(__file__).resolve().with_name("new-agent-tab.sh")
MAX_INPUT = 65536


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


def main():
    try:
        if sys.argv[1:] == ["inventory"]:
            value = inventory()
        elif sys.argv[1:] == ["create"]:
            raw = sys.stdin.buffer.read(MAX_INPUT + 1)
            if len(raw) > MAX_INPUT:
                raise ValueError("Creation request is too large")
            value = create(json.loads(raw))
        else:
            raise ValueError("Usage: session-hub-adapter.py inventory|create")
        print(json.dumps(value))
        return 0
    except (ValueError, KeyError, TypeError, OSError) as error:
        message = str(error) if isinstance(error, ValueError) else "Session hub adapter could not complete the request"
        print(json.dumps({"error": message[:300]}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
