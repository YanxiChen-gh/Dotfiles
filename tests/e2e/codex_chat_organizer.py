import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

SCRIPT = Path(__file__).resolve().parents[2] / "codex/chat-organizer.py"


class OrganizerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.codex_home = self.home / ".codex"
        self.codex_home.mkdir()
        self.config = self.codex_home / "chat-organizer/config.json"
        self.events = self.config.with_name("events.json")
        self.log = self.home / "queue.jsonl"
        self.fake = self.home / "codex"
        self.fake.write_text(
            "#!" + sys.executable + "\nimport json, os, sys\n"
            "with open(os.environ['QUEUE_LOG'], 'a') as f: f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "sys.exit(int(os.environ.get('QUEUE_EXIT', '0')))\n"
        )
        self.fake.chmod(0o700)
        self.env = dict(os.environ, HOME=str(self.home), CODEX_HOME=str(self.codex_home),
                        QUEUE_LOG=str(self.log))
        self.discussion, self.dispatcher, self.excluded = [str(uuid.uuid4()) for _ in range(3)]
        self.ledger = self.home / "ledger.json"
        self.ledger.write_text('{"chats": []}\n')
        self.policy = self.home / "policy.md"
        self.policy.write_text("Canonical classification policy\n")

    def run_script(self, action, *args, event=None, check=True):
        return subprocess.run(
            [sys.executable, str(SCRIPT), action, "--config", str(self.config), *args],
            input=json.dumps(event) if event else None, env=self.env,
            text=True, capture_output=True, check=check,
        )

    def install(self):
        self.run_script("install", "--dispatcher", self.dispatcher, "--discussion", self.discussion,
                        "--ledger", str(self.ledger), "--policy", str(self.policy),
                        "--exclude", self.excluded, "--codex", str(self.fake))

    def event(self, session=None, **fields):
        return dict(hook_event_name="Stop", session_id=session or str(uuid.uuid4()),
                    turn_id=str(uuid.uuid4()), **fields)

    def start(self, prepared, run_id):
        self.run_script("begin", "--run-id", run_id, "--token", prepared["token"])

    def test_install_and_disable_preserve_other_hooks_and_stop_loaded_handlers(self):
        hooks = self.codex_home / "hooks.json"
        original = {"description": "User hooks", "hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": "existing-hook"}]}]}}
        hooks.write_text(json.dumps(original))
        self.install()
        once = json.loads(hooks.read_text())
        self.install()
        self.assertEqual(json.loads(hooks.read_text()), once)
        for session in (self.discussion, self.dispatcher, self.excluded):
            self.run_script("signal", event=self.event(session=session))
        self.assertFalse(self.log.exists())
        self.run_script("uninstall")
        restored = json.loads(hooks.read_text())
        self.assertEqual(restored["description"], original["description"])
        self.assertEqual(restored["hooks"]["Stop"], original["hooks"]["Stop"])
        self.assertTrue(all(not groups for event, groups in restored["hooks"].items() if event != "Stop"))
        self.run_script("signal", event=self.event())
        self.assertFalse(self.log.exists())

    def test_signals_coalesce_runs_exclude_their_first_event_and_followup_is_preserved(self):
        self.install()
        events = [self.event() for _ in range(8)]
        processes = [subprocess.Popen(
            [sys.executable, str(SCRIPT), "signal", "--config", str(self.config)],
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            text=True, env=self.env,
        ) for _ in events]
        for process, event in zip(processes, events):
            process.stdin.write(json.dumps(event))
            process.stdin.close()
        for process in processes:
            self.assertEqual(process.wait(timeout=10), 0)
        self.assertEqual(len(self.log.read_text().splitlines()), 1)
        self.assertEqual(json.loads(self.log.read_text().splitlines()[0])[:3],
                         ["queue", "--thread", self.dispatcher])
        for event in events:
            self.run_script("signal", event=event)
        prepared = json.loads(self.run_script("prepare").stdout)
        run_id = str(uuid.uuid4())
        self.run_script("signal", event=dict(
            hook_event_name="SessionStart", session_id=run_id, source="startup",
            cwd=str(self.home / prepared["directoryName"])))
        state = json.loads(self.events.read_text())
        self.assertIn(run_id, state["runs"])
        self.assertEqual(len(self.log.read_text().splitlines()), 1)
        self.start(prepared, run_id)
        self.assertEqual(len(json.loads(self.events.read_text())["runs"][run_id]["events"]), 8)
        self.run_script("bind", "--run-id", run_id, "--token", prepared["token"])
        self.run_script("signal", event=self.event(session=run_id))
        later = self.event()
        self.run_script("signal", event=later)
        self.assertFalse(json.loads(self.run_script("prepare").stdout)["launch"])
        self.assertEqual(len(self.log.read_text().splitlines()), 1)
        wrong = self.run_script("finish", "--run-id", str(uuid.uuid4()), check=False)
        self.assertNotEqual(wrong.returncode, 0)
        self.run_script("finish", "--run-id", run_id, "--message", "No changes")
        self.assertEqual(len(self.log.read_text().splitlines()), 2)
        followup = json.loads(self.run_script("prepare").stdout)
        self.assertNotEqual(prepared["token"], followup["token"])
        self.start(followup, str(uuid.uuid4()))
        state = json.loads(self.events.read_text())
        self.assertEqual(len(state["runs"][state["activeRun"]]["events"]), 1)
        self.assertEqual(self.ledger.read_text(), '{"chats": []}\n')

    def test_concurrent_prepare_reserves_one_launch_and_recovery_checks_owner(self):
        self.install()
        processes = [subprocess.Popen(
            [sys.executable, str(SCRIPT), "prepare", "--config", str(self.config)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=self.env,
        ) for _ in range(8)]
        results = []
        for process in processes:
            output, error = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, error)
            results.append(json.loads(output))
        reservations = [r for r in results if r["launch"]]
        self.assertEqual(len(reservations), 1)
        run_id = str(uuid.uuid4())
        self.start(reservations[0], run_id)
        wrong = self.run_script("recover", "--run-id", str(uuid.uuid4()), check=False)
        self.assertNotEqual(wrong.returncode, 0)
        self.assertEqual(json.loads(self.run_script("status").stdout)["activeRun"], run_id)
        self.run_script("recover", "--run-id", run_id, "--message", "Verified interrupted via app read_thread")
        self.assertTrue(json.loads(self.run_script("prepare").stdout)["launch"])

    def test_failed_delivery_remains_pending_for_the_scheduled_launcher(self):
        self.install()
        self.env["QUEUE_EXIT"] = "1"
        self.run_script("signal", event=self.event())
        self.run_script("signal", event=self.event())
        self.assertEqual(len(self.log.read_text().splitlines()), 1)
        prepared = json.loads(self.run_script("prepare").stdout)
        self.assertTrue(prepared["launch"])
        self.start(prepared, str(uuid.uuid4()))
        state = json.loads(self.events.read_text())
        self.assertEqual(len(state["runs"][state["activeRun"]]["events"]), 2)

    def test_error_is_reported_without_requesting_an_automatic_retry(self):
        self.install()
        prepared = json.loads(self.run_script("prepare").stdout)
        run_id = str(uuid.uuid4())
        self.start(prepared, run_id)
        self.run_script("finish", "--run-id", run_id, "--outcome", "error", "--message", "Host unavailable")
        status = json.loads(self.run_script("status").stdout)
        self.assertIsNone(status["activeRun"])
        self.assertEqual(status["lastFailure"]["message"], "Host unavailable")
        queued = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(len(queued), 1)
        self.assertIn("status-only report", queued[0][-1])
        self.run_script("ack-error", "--run-id", run_id)
        self.assertTrue(json.loads(self.run_script("status").stdout)["lastFailure"]["acknowledged"])


if __name__ == "__main__":
    unittest.main()
