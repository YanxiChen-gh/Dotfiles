#!/usr/bin/env python3
"""Exercise the real adapter and launcher against disposable Herdr/Treehouse fixtures."""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "herdr/session-hub-adapter.py"
LAUNCHER = ROOT / "herdr/new-agent-tab.sh"

HERDR_FIXTURE = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
root = pathlib.Path(os.environ["FIXTURE"])
with (root / "herdr.jsonl").open("a") as stream:
    stream.write(json.dumps(args) + "\n")
operation = args[:2]
def emit(value):
    print(json.dumps({"result": value}))
if operation == ["workspace", "list"]:
    emit({"workspaces": [{"workspace_id": "w-existing", "name": "Existing task"}]})
elif operation == ["pane", "list"]:
    if args != ["pane", "list", "--workspace", "w-existing"]:
        sys.exit(2)
    emit({"panes": [{"pane_id": "w-existing:p1", "cwd": str(root / "existing cwd")} ]})
elif operation == ["workspace", "create"]:
    (root / "workspace-open").touch()
    emit({"workspace": {"workspace_id": "w-created"}, "tab": {"tab_id": "w-created:t1"}, "root_pane": {"pane_id": "w-created:p1"}})
elif operation == ["tab", "create"]:
    emit({"tab": {"tab_id": "w-existing:t2"}, "root_pane": {"pane_id": "w-existing:p2"}})
elif operation == ["workspace", "get"]:
    if (root / "workspace-open").exists():
        emit({"workspace": {"workspace_id": "w-created"}})
    else:
        print(json.dumps({"error": {"code": "workspace_not_found"}}))
        sys.exit(1)
elif operation == ["workspace", "close"]:
    (root / "workspace-open").unlink(missing_ok=True)
elif operation == ["pane", "split"]:
    emit({"pane": {"pane_id": "w-created:p2"}})
elif operation == ["pane", "run"] and (root / "fail-pane").exists():
    print("SECRET_PRIVATE_DIAGNOSTIC", file=sys.stderr)
    sys.exit(1)
else:
    emit({})
'''

TREEHOUSE_FIXTURE = r'''#!/usr/bin/env python3
import os, pathlib, subprocess, sys
root = pathlib.Path(os.environ["FIXTURE"])
(root / "treehouse-owned").touch()
env = os.environ.copy()
env["TREEHOUSE_DIR"] = str(root / "pool/1/repository")
status = subprocess.call([env["SHELL"]], cwd=env["TREEHOUSE_DIR"], env=env)
(root / "treehouse-returned").write_text(str(status))
sys.exit(status)
'''

CLOSE_HERDR_FIXTURE = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["FIXTURE"])
args = sys.argv[1:]
with (root / "herdr.jsonl").open("a") as stream:
    stream.write(json.dumps(args) + "\n")
path = root / "close-state.json"
state = json.loads(path.read_text())
snapshot = state["snapshot"]
if args == ["api", "snapshot"]:
    count = state["snapshot_reads"] = state.get("snapshot_reads", 0) + 1
    snapshot.update(state.get("snapshot_changes", {}).get(str(count), {}))
    result = {"snapshot": snapshot}
elif len(args) == 4 and args[:3] == ["pane", "process-info", "--pane"]:
    count = state["process_reads"] = state.get("process_reads", 0) + 1
    state["foreground"].update(state.get("process_changes", {}).get(str(count), {}))
    result = {"process_info": {"pane_id": args[3], "shell_pid": 100,
                              "foreground_process_group_id": 200,
                              "foreground_processes": state["foreground"].get(args[3], [])}}
elif len(args) == 3 and args[:2] == ["pane", "close"]:
    if state.get("fail_close"):
        print("PRIVATE_CLOSE_DIAGNOSTIC", file=sys.stderr)
        print(json.dumps({"error": {"code": "close_failed"}}))
        sys.exit(1)
    matches = [pane for pane in snapshot["panes"] if pane["pane_id"] == args[2]]
    if len(matches) != 1:
        sys.exit(1)
    pane = matches[0]
    snapshot["panes"].remove(pane)
    snapshot["agents"] = [agent for agent in snapshot["agents"] if agent["pane_id"] != args[2]]
    for tab in list(snapshot["tabs"]):
        tab["pane_count"] = sum(row["tab_id"] == tab["tab_id"] for row in snapshot["panes"])
        if not tab["pane_count"]:
            snapshot["tabs"].remove(tab)
    for workspace in list(snapshot["workspaces"]):
        workspace["pane_count"] = sum(row["workspace_id"] == workspace["workspace_id"] for row in snapshot["panes"])
        workspace["tab_count"] = sum(row["workspace_id"] == workspace["workspace_id"] for row in snapshot["tabs"])
        if not workspace["pane_count"]:
            snapshot["workspaces"].remove(workspace)
    result = {"closed": True}
else:
    sys.exit(2)
path.write_text(json.dumps(state))
print(json.dumps({"result": result}))
'''

CLOSE_OMP_FIXTURE = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
if sys.argv[1:] != ["collab", "list", "--json"]:
    sys.exit(2)
root = pathlib.Path(os.environ["FIXTURE"])
path = root / "close-state.json"
state = json.loads(path.read_text())
count = state["registry_reads"] = state.get("registry_reads", 0) + 1
if str(count) in state.get("registry_changes", {}):
    state["hosts"] = state["registry_changes"][str(count)]
path.write_text(json.dumps(state))
with (root / "omp.jsonl").open("a") as stream:
    stream.write(json.dumps({"args": sys.argv[1:], "config": os.environ.get("PI_CODING_AGENT_DIR")}) + "\n")
print(json.dumps({"version": 1, "hosts": state["hosts"]}))
'''


class AdapterFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles-hub-test-")
        self.path = Path(self.temporary.name)
        self.home = self.path / "home"
        self.bin = self.home / ".local/bin"
        self.bin.mkdir(parents=True)
        (self.path / "existing cwd").mkdir()
        (self.path / "jobs").mkdir()
        self.repo = self.path / "repositories/repository"
        self.repo.mkdir(parents=True)
        self.git("init", "-q", cwd=self.repo)
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--allow-empty", "-qm", "fixture", cwd=self.repo)
        self.acquired = self.path / "pool/1/repository"
        self.acquired.parent.mkdir(parents=True)
        self.git("worktree", "add", "--detach", str(self.acquired), cwd=self.repo)
        self.other = self.path / "other/repository"
        self.other.mkdir(parents=True)
        self.git("init", "-q", cwd=self.other)
        (self.path / "aliases").mkdir()
        (self.path / "aliases/repository").symlink_to(self.repo)
        for name, script in (("herdr", HERDR_FIXTURE), ("treehouse", TREEHOUSE_FIXTURE),
                             ("omp", "#!/bin/sh\n[ \"$1\" != config ] || printf 'off\\n'\n"),
                             ("nvim", "#!/bin/sh\nexit 0\n")):
            self.executable(self.bin / name, script)
        self.env = {key: value for key, value in os.environ.items() if not key.startswith(("HERDR_", "DOTFILES_HERDR_", "PI_", "OMP_"))}
        self.env.update(HOME=str(self.home), PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        FIXTURE=str(self.path), TMPDIR=str(self.path / "jobs"),
                        HERDR_BIN_PATH=str(self.bin / "herdr"), HERDR_ACTIVE_PANE_CWD=str(self.acquired),
                        HERDR_REPO_HOME=str(self.path / "repositories"),
                        HERDR_REPO_ROOTS=str(self.path / "aliases") + ":" + str(self.path / "other"),
                        HERDR_TREEHOUSE_SHELL_PATH=str(ROOT / "herdr/treehouse-task-shell.sh"),
                        IS_ON_ONA="", CURSOR_CLOUD="", OMP_EXPERIMENT="0")

    def tearDown(self):
        (self.path / "workspace-open").unlink(missing_ok=True)
        if (self.path / "treehouse-owned").exists():
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline and not (self.path / "treehouse-returned").exists():
                time.sleep(0.1)
        self.temporary.cleanup()

    @staticmethod
    def executable(path, content):
        path.write_text(content)
        path.chmod(0o755)

    def git(self, *args, cwd):
        subprocess.run(["git", *args], cwd=str(cwd), check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def run_adapter(self, operation, spec=None, success=True):
        result = subprocess.run([sys.executable, str(ADAPTER), operation],
                                input=None if spec is None else json.dumps(spec), text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=self.env, cwd=str(self.path), timeout=20)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def calls(self):
        log = self.path / "herdr.jsonl"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def test_inventory_matches_desktop_and_canonicalizes_linked_checkouts(self):
        inventory = self.run_adapter("inventory")
        desktop = subprocess.run(["bash", str(LAUNCHER), "--inventory"], env=self.env,
                                 stdout=subprocess.PIPE, text=True, check=True)
        self.assertEqual(inventory["repositories"], json.loads(desktop.stdout))
        self.assertEqual([repo["path"] for repo in inventory["repositories"]], [str(self.repo), str(self.other)])
        self.assertEqual(inventory["workspaces"], [{"id": "w-existing", "name": "Existing task", "cwd": str(self.path / "existing cwd")}])
        self.env["HERDR_ACTIVE_PANE_CWD"] = str(self.path)
        self.assertEqual(len(self.run_adapter("inventory")["repositories"]), 2)

    def test_primary_agent_editor_and_prompt_are_real_launcher_operations(self):
        prompt = "literal ' ; $(touch SHOULD_NOT_EXIST)\nsecond line"
        result = self.run_adapter("create", {"repository": str(self.repo), "checkout": "primary", "editor": True, "prompt": prompt})
        self.assertEqual(result, {"workspaceId": "w-created", "tabId": "w-created:t1", "paneId": "w-created:p1", "cwd": str(self.repo)})
        self.assertIn(["agent", "prompt", "w-created:p1", prompt], self.calls())
        self.assertTrue(any(call[:2] == ["pane", "split"] for call in self.calls()))
        self.assertTrue(any(call[:2] == ["pane", "run"] and call[-1].endswith("clear; omp") for call in self.calls()))
        self.assertFalse((self.path / "SHOULD_NOT_EXIST").exists())

    def test_shell_workspace_reports_ready_without_an_agent(self):
        result = self.run_adapter("create", {"repository": str(self.repo), "checkout": "primary", "agent": False})
        self.assertEqual(result["workspaceId"], "w-created")
        self.assertFalse(any(call[:2] == ["pane", "run"] for call in self.calls()))

    def test_ready_result_published_while_observing_launcher_exit_is_not_lost(self):
        specification = importlib.util.spec_from_file_location("session_hub_adapter", ADAPTER)
        adapter = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(adapter)
        expected = {"workspaceId": "w-created", "tabId": "w-created:t1",
                    "paneId": "w-created:p1", "cwd": str(self.repo)}

        def spawn(argv, **kwargs):
            result = Path(argv[argv.index("--result-file") + 1])
            process = mock.Mock()

            def observe_exit():
                result.write_text(json.dumps({"status": "ready", "result": expected}))
                return 0

            process.poll.side_effect = observe_exit
            return process

        with mock.patch.object(adapter.subprocess, "Popen", side_effect=spawn):
            self.assertEqual(adapter.create({"repository": str(self.repo), "checkout": "primary",
                                             "agent": False}), expected)

    def test_github_clone_uses_desktop_home_when_clone_root_is_omitted(self):
        self.executable(self.bin / "gh", '''#!/usr/bin/env python3
import json, subprocess, sys
if sys.argv[1:3] == ["repo", "view"]:
    print(json.dumps({"nameWithOwner": "Example/project", "name": "project"}))
elif sys.argv[1:4] == ["repo", "clone", "Example/project"]:
    subprocess.run(["git", "init", "-q", sys.argv[4]], check=True)
else:
    sys.exit(1)
''')
        result = self.run_adapter("create", {"repository": "", "cloneRepository": "Example/project",
                                              "checkout": "primary", "agent": False})
        self.assertEqual(result["cwd"], str(self.repo.parent / "project"))
        self.assertTrue((self.repo.parent / "project/.git").is_dir())

    def test_terminal_failure_waits_for_cleanup_without_killing_a_live_owner(self):
        specification = importlib.util.spec_from_file_location("session_hub_adapter", ADAPTER)
        adapter = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(adapter)
        for running in (False, True):
            with self.subTest(cleanup_running=running):
                state = self.path / "jobs" / str(running)
                state.mkdir()
                process = mock.Mock()
                process.poll.return_value = None
                if running:
                    process.wait.side_effect = subprocess.TimeoutExpired("launcher", 5)

                def spawn(argv, **kwargs):
                    result = Path(argv[argv.index("--result-file") + 1])
                    result.write_text(json.dumps({"status": "failed", "error": "PRIVATE_DIAGNOSTIC"}))
                    return process

                with mock.patch.object(adapter.tempfile, "mkdtemp", return_value=str(state)):
                    with mock.patch.object(adapter.subprocess, "Popen", side_effect=spawn):
                        with self.assertRaises(ValueError) as failure:
                            adapter.create({"repository": str(self.repo), "agent": False})
                process.wait.assert_called_once_with(timeout=5)
                process.terminate.assert_not_called()
                process.kill.assert_not_called()
                self.assertEqual("cleanup is still running" in str(failure.exception), running)
                self.assertNotIn("PRIVATE_DIAGNOSTIC", str(failure.exception))

    def test_existing_workspace_gets_tab_and_preserves_non_git_cwd(self):
        result = self.run_adapter("create", {"workspaceId": "w-existing", "prompt": "hello"})
        self.assertEqual(result, {"workspaceId": "w-existing", "tabId": "w-existing:t2", "paneId": "w-existing:p2", "cwd": str(self.path / "existing cwd")})
        self.assertTrue(any(call[:2] == ["tab", "create"] for call in self.calls()))
        self.assertFalse(any(call[:2] in (["workspace", "create"], ["workspace", "report-metadata"]) for call in self.calls()))

    def test_failed_tab_never_closes_original_workspace_or_dumps_logs(self):
        (self.path / "fail-pane").touch()
        result = self.run_adapter("create", {"workspaceId": "w-existing"}, success=False)
        self.assertNotIn("SECRET_PRIVATE_DIAGNOSTIC", result["error"])
        self.assertIn(["tab", "close", "w-existing:t2"], self.calls())
        self.assertFalse(any(call[:2] == ["workspace", "close"] for call in self.calls()))
        logs = list((self.path / "jobs").glob("*/launcher.log"))
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0].stat().st_mode & 0o777, 0o600)

    def test_fresh_checkout_keeps_treehouse_owner_after_http_adapter_returns(self):
        result = self.run_adapter("create", {"repository": str(self.repo), "agent": False})
        self.assertEqual(result["cwd"], str(self.acquired))
        self.assertTrue((self.path / "treehouse-owned").exists())
        self.assertFalse((self.path / "treehouse-returned").exists())
        (self.path / "workspace-open").unlink()
        # Only the desktop lifecycle owner should release the checkout.
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and not (self.path / "treehouse-returned").exists():
            time.sleep(0.1)
        self.assertEqual((self.path / "treehouse-returned").read_text(), "0")

    def test_invalid_requests_never_reach_launcher(self):
        for spec in ({"repository": str(self.repo), "unknown": True},
                     {"repository": str(self.repo), "agent": "false"},
                     {"repository": str(self.repo), "checkout": "current"},
                     {"workspaceId": "-bad"}, {"cloneRepository": "--help"},
                     {"workspaceId": "w-existing", "agent": False},
                     {"workspaceId": "w-existing", "editor": True},
                     {"repository": str(self.repo), "agent": False, "prompt": "unsafe"}):
            with self.subTest(spec=spec):
                self.assertIn("error", self.run_adapter("create", spec, success=False))
        self.assertEqual(self.calls(), [])


class CloseAdapterFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles-hub-close-")
        self.path = Path(self.temporary.name)
        self.home = self.path / "home"
        self.bin = self.home / ".local/bin"
        self.bin.mkdir(parents=True)
        AdapterFixture.executable(self.bin / "herdr", CLOSE_HERDR_FIXTURE)
        AdapterFixture.executable(self.bin / "omp", CLOSE_OMP_FIXTURE)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(("HERDR_", "DOTFILES_HERDR_", "PI_", "OMP_"))}
        self.env.update(HOME=str(self.home), PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        FIXTURE=str(self.path), HERDR_BIN_PATH=str(self.bin / "herdr"),
                        HERDR_PANE_ID="w-keep:p-editor",
                        PI_CODING_AGENT_DIR=str(self.path / "custom-config"))
        self.host = {"instanceId": "fixture-host-1", "generation": 7, "pid": 321,
                     "sessionId": "f27d93a8-7f96-4dd7-b267-0fac4131a654", "access": "control"}
        self.history = self.path / "unrelated-file-name.jsonl"
        self.history.write_text(json.dumps({"type": "title", "title": "Same title"}) + "\n"
                                + json.dumps({"type": "session", "id": self.host["sessionId"]}) + "\n"
                                + json.dumps({"type": "message", "content": "saved history"}) + "\n")
        self.history_content = self.history.read_bytes()
        self.state = {"hosts": [dict(self.host)], "foreground": {
            "w-keep:p-agent": [{"pid": 321, "name": "omp", "argv": ["omp"]}],
            "w-keep:p-sibling": [{"pid": 654, "name": "omp", "argv": ["omp"]}],
            "w-keep:p-editor": [{"pid": 987, "name": "nvim", "argv": ["nvim"]}]}}
        agent = self.pane("w-keep:p-agent", "term-agent", "w-keep:t-agent", self.host["sessionId"])
        agent["agent_session"] = {"agent": "omp", "kind": "path", "source": "herdr:omp",
                                  "value": str(self.history)}
        sibling = self.pane("w-keep:p-sibling", "term-sibling", "w-keep:t-sibling", "sibling-session")
        editor = self.pane("w-keep:p-editor", "term-editor", "w-keep:t-agent")
        self.state["snapshot"] = {"panes": [agent, sibling, editor], "agents": [dict(agent), dict(sibling)],
                                  "tabs": [], "workspaces": []}
        self.update_topology()

    def tearDown(self):
        self.temporary.cleanup()

    def pane(self, identifier, terminal, tab, session=None):
        row = {"pane_id": identifier, "terminal_id": terminal, "tab_id": tab,
               "workspace_id": "w-keep", "cwd": str(self.path), "terminal_title": "Same title"}
        if session is not None:
            row.update(agent="omp", agent_session={"agent": "omp", "kind": "id",
                       "source": "herdr:omp", "value": session})
        return row

    def update_topology(self):
        snapshot = self.state["snapshot"]
        panes = snapshot["panes"]
        snapshot["tabs"] = [{"tab_id": identifier, "workspace_id": "w-keep",
                             "pane_count": sum(row["tab_id"] == identifier for row in panes)}
                            for identifier in dict.fromkeys(row["tab_id"] for row in panes)]
        snapshot["workspaces"] = [{"workspace_id": "w-keep", "pane_count": len(panes),
                                   "tab_count": len(snapshot["tabs"])}]

    def run_adapter(self, operation, target=None, success=True, spec=None):
        (self.path / "close-state.json").write_text(json.dumps(self.state))
        if spec is None:
            spec = {"host": dict(self.host)}
            if target is not None:
                spec["target"] = target
        result = subprocess.run([sys.executable, str(ADAPTER), operation], input=json.dumps(spec),
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=self.env, cwd=str(self.path), timeout=20)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        self.state = json.loads((self.path / "close-state.json").read_text())
        self.assertEqual(result.stderr, "")
        self.assertEqual(self.history.read_bytes(), self.history_content)
        return json.loads(result.stdout)

    def calls(self):
        path = self.path / "herdr.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def assert_no_close(self):
        self.assertFalse(any(call[:2] == ["pane", "close"] for call in self.calls()))

    def target(self, closes_tab=False, closes_workspace=False):
        return {"paneId": "w-keep:p-agent", "terminalId": "term-agent",
                "tabId": "w-keep:t-agent", "workspaceId": "w-keep",
                "closesTab": closes_tab, "closesWorkspace": closes_workspace}

    def test_close_matches_metadata_header_and_foreground_pid_preserving_siblings_and_history(self):
        preview = self.run_adapter("close-preview")
        self.assertEqual(preview, {"target": self.target()})
        self.assert_no_close()
        self.assertEqual(self.run_adapter("close", preview["target"]),
                         {"closed": True, "paneId": "w-keep:p-agent"})
        snapshot = self.state["snapshot"]
        self.assertEqual([pane["pane_id"] for pane in snapshot["panes"]],
                         ["w-keep:p-sibling", "w-keep:p-editor"])
        self.assertEqual(len(snapshot["tabs"]), 2)
        self.assertEqual(len(snapshot["workspaces"]), 1)
        self.assertEqual(self.calls()[-1], ["pane", "close", "w-keep:p-agent"])
        config_calls = [json.loads(line) for line in (self.path / "omp.jsonl").read_text().splitlines()]
        self.assertEqual(len(config_calls), 3)
        self.assertTrue(all(call["config"] == self.env["PI_CODING_AGENT_DIR"] for call in config_calls))

    def test_empty_session_closes_from_native_resume_identity_without_creating_history(self):
        reference = self.path / ("2026-01-01T00-00-00-000Z_" + self.host["sessionId"] + ".jsonl")
        for row in (self.state["snapshot"]["panes"][0], self.state["snapshot"]["agents"][0]):
            row["agent_session"]["value"] = str(reference)
        preview = self.run_adapter("close-preview")
        self.assertEqual(self.run_adapter("close", preview["target"]),
                         {"closed": True, "paneId": "w-keep:p-agent"})
        self.assertEqual([row["pane_id"] for row in self.state["snapshot"]["panes"]],
                         ["w-keep:p-sibling", "w-keep:p-editor"])
        self.assertFalse(reference.exists())

    def test_missing_stale_or_unrecognized_resume_identity_cannot_close_by_pid_alone(self):
        for name in ("session.jsonl", "2026-01-01T00-00-00-000Z_00000000-0000-0000-0000-000000000000.jsonl"):
            with self.subTest(name=name):
                reference = self.path / name
                for row in (self.state["snapshot"]["panes"][0], self.state["snapshot"]["agents"][0]):
                    row["agent_session"]["value"] = str(reference)
                self.assertEqual(self.run_adapter("close", self.target(), success=False)["status"], 409)
                self.assertFalse(reference.exists())
        self.assert_no_close()

    def test_last_pane_impacts_are_previewed_and_left_to_native_close(self):
        for last_workspace in (False, True):
            with self.subTest(last_workspace=last_workspace):
                self.state["snapshot"]["panes"] = [self.state["snapshot"]["panes"][0]]
                self.state["snapshot"]["agents"] = [self.state["snapshot"]["agents"][0]]
                if not last_workspace:
                    self.state["snapshot"]["panes"].append(
                        self.pane("w-keep:p-shell", "term-shell", "w-keep:t-shell"))
                self.update_topology()
                target = self.target(closes_tab=True, closes_workspace=last_workspace)
                self.assertEqual(self.run_adapter("close-preview"), {"target": target})
                self.run_adapter("close", target)
                self.assertEqual(len(self.state["snapshot"]["workspaces"]), 0 if last_workspace else 1)
                self.assertNotIn("w-keep:t-agent", [tab["tab_id"] for tab in self.state["snapshot"]["tabs"]])
                if not last_workspace:
                    agent = self.pane("w-keep:p-agent", "term-agent", "w-keep:t-agent", self.host["sessionId"])
                    self.state["snapshot"]["panes"].insert(0, agent)
                    self.state["snapshot"]["agents"] = [dict(agent)]
        self.assertTrue(all(call[:2] in (["api", "snapshot"], ["pane", "process-info"], ["pane", "close"])
                            for call in self.calls()))

    def test_same_cwd_and_title_never_substitute_for_session_identity(self):
        self.history.write_text(json.dumps({"type": "session", "id": "another-session"}) + "\n")
        self.history_content = self.history.read_bytes()
        result = self.run_adapter("close-preview", success=False)
        self.assertEqual(result["status"], 409)
        self.assert_no_close()

    def test_duplicate_exact_session_and_foreground_pid_are_ambiguous(self):
        duplicate = self.pane("w-keep:p-duplicate", "term-duplicate", "w-keep:t-agent", self.host["sessionId"])
        self.state["snapshot"]["panes"].append(duplicate)
        self.state["snapshot"]["agents"].append(dict(duplicate))
        self.state["foreground"][duplicate["pane_id"]] = [{"pid": self.host["pid"]}]
        self.update_topology()
        self.assertEqual(self.run_adapter("close", self.target(), success=False)["status"], 409)
        self.assert_no_close()

    def test_retained_or_nested_nonforeground_session_is_not_closed(self):
        self.state["foreground"]["w-keep:p-agent"] = [{"pid": 100, "name": "shell"}]
        self.assertEqual(self.run_adapter("close-preview", success=False)["status"], 409)
        self.assert_no_close()

    def test_stale_registry_identity_view_access_and_missing_host_are_refused(self):
        original = dict(self.host)
        for patch, status in (({"generation": 8}, 409), ({"pid": 654}, 409),
                              ({"sessionId": "replaced-session"}, 409), ({"access": "view"}, 403),
                              (None, 404)):
            with self.subTest(patch=patch):
                self.state["hosts"] = [] if patch is None else [dict(original, **patch)]
                self.assertEqual(self.run_adapter("close-preview", success=False)["status"], status)
        self.assert_no_close()

    def test_terminal_and_last_pane_changes_require_a_new_confirmation(self):
        target = self.run_adapter("close-preview")["target"]
        for mutation in ("terminal", "topology"):
            with self.subTest(mutation=mutation):
                if mutation == "terminal":
                    self.state["snapshot"]["panes"][0]["terminal_id"] = "term-replaced"
                    self.state["snapshot"]["agents"][0]["terminal_id"] = "term-replaced"
                else:
                    self.state["snapshot"]["panes"][0]["terminal_id"] = "term-agent"
                    self.state["snapshot"]["agents"][0]["terminal_id"] = "term-agent"
                    self.state["snapshot"]["panes"].pop()
                    self.update_topology()
                self.assertEqual(self.run_adapter("close", target, success=False)["status"], 409)
        self.assert_no_close()

    def test_final_recheck_rejects_generation_process_and_topology_races(self):
        for race in ("generation", "process", "topology"):
            with self.subTest(race=race):
                self.state.pop("registry_reads", None)
                self.state.pop("snapshot_reads", None)
                self.state.pop("process_reads", None)
                self.state.pop("registry_changes", None)
                self.state.pop("process_changes", None)
                self.state.pop("snapshot_changes", None)
                self.state["hosts"] = [dict(self.host)]
                self.state["foreground"]["w-keep:p-agent"] = [{"pid": self.host["pid"]}]
                if race == "generation":
                    self.state["registry_changes"] = {"2": [dict(self.host, generation=8)]}
                elif race == "process":
                    self.state["process_changes"] = {"2": {"w-keep:p-agent": [{"pid": 999}]}}
                else:
                    panes = self.state["snapshot"]["panes"][:-1]
                    tabs = [dict(tab, pane_count=1) for tab in self.state["snapshot"]["tabs"]]
                    self.state["snapshot_changes"] = {"2": {"panes": panes, "tabs": tabs,
                        "workspaces": [{"workspace_id": "w-keep", "pane_count": 2, "tab_count": 2}]}}
                self.assertEqual(self.run_adapter("close", self.target(), success=False)["status"], 409)
        self.assert_no_close()

    def test_missing_unknown_or_malformed_adapter_targets_are_invalid(self):
        for spec in ({"host": self.host}, {"host": self.host, "target": {}},
                     {"host": self.host, "target": dict(self.target(), unknown=True)},
                     {"host": self.host, "target": dict(self.target(), closesTab=0)},
                     {"host": self.host, "target": dict(self.target(), paneId="--current")},
                     {"host": self.host, "target": self.target(), "confirmed": True},
                     {"host": dict(self.host, pid=True), "target": self.target()}):
            with self.subTest(spec=spec):
                self.assertEqual(self.run_adapter("close", spec=spec, success=False)["status"], 400)
        self.assertEqual(self.calls(), [])

    def test_confirmation_cannot_select_a_sibling_or_unknown_pane(self):
        for pane in ("w-keep:p-sibling", "w-unknown:p1"):
            with self.subTest(pane=pane):
                target = dict(self.target(), paneId=pane)
                self.assertEqual(self.run_adapter("close", target, success=False)["status"], 409)
        self.assert_no_close()

    def test_metadata_must_be_a_bounded_regular_file_header_not_transcript_content(self):
        for content in (
                json.dumps({"type": "message", "content": "not metadata"}) + "\n"
                + json.dumps({"type": "session", "id": self.host["sessionId"]}) + "\n",
                json.dumps({"type": "title", "title": "x" * 16384}) + "\n"
                + json.dumps({"type": "session", "id": self.host["sessionId"]}) + "\n"):
            with self.subTest(content=content[:80]):
                self.history.write_text(content)
                self.history_content = self.history.read_bytes()
                self.assertEqual(self.run_adapter("close-preview", success=False)["status"], 409)
        self.state["snapshot"]["agents"][0]["agent_session"]["value"] = str(self.path)
        self.assertEqual(self.run_adapter("close-preview", success=False)["status"], 409)
        self.assert_no_close()

    def test_unsupported_metadata_refuses_closing(self):
        self.state["snapshot"]["agents"][0]["agent_session"]["kind"] = "unknown"
        self.assertEqual(self.run_adapter("close-preview", success=False)["status"], 409)
        self.assert_no_close()

    def test_native_failure_does_not_retry_or_broaden_target(self):
        self.state["fail_close"] = True
        result = self.run_adapter("close", self.target(), success=False)
        self.assertEqual(result["status"], 502)
        self.assertNotIn("PRIVATE_CLOSE_DIAGNOSTIC", result["error"])
        self.assertEqual(sum(call[:2] == ["pane", "close"] for call in self.calls()), 1)
        self.assertEqual(len(self.state["snapshot"]["panes"]), 3)


class InstallerFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles-hub-install-")
        self.path = Path(self.temporary.name)
        self.home = self.path / "home"
        self.bin = self.home / ".local/bin"
        self.bin.mkdir(parents=True)
        self.revision = "a" * 40
        self.archive = self.path / "archive.tar.gz"
        installer = '''#!/bin/sh
set -eu
printf '%s\\n' "$*" > "$FIXTURE/install-args"
[ "$1" = --source ] && [ "$3" = --revision ] && [ "$5" = --prefix ]
mkdir -p "$HOME/.local/bin" "$6/versions/$4"
printf 'user-state\\n' > "$6/versions/$4/installed"
cat > "$HOME/.local/bin/omp-session-hub" <<'COMMAND'
#!/bin/sh
printf '%s\\n' "$*" >> "$FIXTURE/services"
COMMAND
chmod +x "$HOME/.local/bin/omp-session-hub"
'''
        content = installer.encode()
        with tarfile.open(str(self.archive), "w:gz") as archive:
            item = tarfile.TarInfo("omp-session-hub-" + self.revision + "/install.sh")
            item.size = len(content)
            item.mode = 0o755
            archive.addfile(item, io.BytesIO(content))
        AdapterFixture.executable(self.bin / "curl", "#!/bin/sh\n[ \"$1\" = -fsSL ] && [ \"$3\" = -o ] || exit 8\nprintf '%s\\n' \"$2\" > \"$FIXTURE/url\"\ncp \"$FIXTURE/archive.tar.gz\" \"$4\"\n")
        self.env = os.environ.copy()
        self.env.update(HOME=str(self.home), PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        FIXTURE=str(self.path), OMP_SESSION_HUB_REVISION=self.revision,
                        OMP_SESSION_HUB_SHA256=hashlib.sha256(self.archive.read_bytes()).hexdigest(),
                        IS_ON_ONA="true", OMP_EXPERIMENT="1", ROOT=str(ROOT))

    def tearDown(self):
        self.temporary.cleanup()

    def install(self, os_name, success=True):
        command = '. "$ROOT/install.d/67-session-hub.sh"; resolve_script_dir() { printf "%s\\n" "$ROOT"; }; OS="$1"; setup_session_hub'
        result = subprocess.run(["sh", "-c", command, "fixture", os_name], env=self.env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_checksum_verified_install_sets_platform_services_and_preserves_user_files(self):
        prefix = self.home / ".local/share/omp-session-hub"
        prefix.mkdir(parents=True)
        user = prefix / "my-state"
        user.write_text("keep me")
        self.install("linux")
        self.assertEqual((self.path / "url").read_text().strip(), "https://codeload.github.com/YanxiChen-gh/omp-session-hub/tar.gz/" + self.revision)
        self.assertIn("--revision " + self.revision, (self.path / "install-args").read_text())
        self.assertEqual((self.path / "services").read_text().splitlines(), ["service install hub --adapter " + str(ADAPTER) + " --port 4317", "service ensure hub"])
        self.assertEqual(user.read_text(), "keep me")
        (self.path / "services").unlink()
        self.install("macos")
        self.assertEqual((self.path / "services").read_text().splitlines(), ["service install gateway --port 8787 --upstream-port 4317", "service ensure gateway"])

    def test_bad_checksum_and_non_immutable_revisions_never_execute_installer(self):
        self.env["OMP_SESSION_HUB_SHA256"] = "0" * 64
        self.install("linux", success=False)
        self.assertFalse((self.path / "install-args").exists())
        self.env["OMP_SESSION_HUB_REVISION"] = "main"
        self.install("linux", success=False)
        self.assertFalse((self.path / "install-args").exists())

    def test_resume_hook_ensures_cde_only_and_uses_absolute_adapter(self):
        AdapterFixture.executable(self.bin / "omp-session-hub", '#!/bin/sh\nprintf "%s\\n" "$*" >> "$FIXTURE/services"\n')
        subprocess.run(["sh", str(ROOT / "herdr/session-hub-ensure.sh")], env=self.env, check=True)
        self.assertEqual((self.path / "services").read_text().strip(), "service ensure hub --adapter " + str(ADAPTER))
        (self.path / "services").unlink()
        self.env["IS_ON_ONA"] = ""
        self.env["CURSOR_CLOUD"] = ""
        subprocess.run(["sh", str(ROOT / "herdr/session-hub-ensure.sh")], env=self.env, check=True)
        self.assertFalse((self.path / "services").exists())


if __name__ == "__main__":
    unittest.main()
