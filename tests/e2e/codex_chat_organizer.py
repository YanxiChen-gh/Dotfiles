import json
import hashlib
import os
from pathlib import Path
import subprocess
import select
import sys
import tempfile
import unittest
import uuid

SCRIPT = Path(__file__).resolve().parents[2] / "codex/chat-organizer.py"
REMOTE_SCRIPT = SCRIPT.with_name("chat-organizer-remote.py")


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
        return json.loads(self.run_script("begin", "--run-id", run_id, "--token", prepared["token"]).stdout)

    def test_event_scope_selects_sources_once_and_keeps_later_work(self):
        self.install()
        self.allow_remote("remote-a")
        source = str(uuid.uuid4())
        self.run_script("signal", event=self.event(session=source))
        self.run_script("signal", event=self.event(session=source))
        remote = self.wire_event("remote-a", source)
        self.run_script("receive", "--host-id", "remote-a", event={"events": [remote]})
        state = json.loads(self.events.read_text())
        state["pending"]["legacy-internal"] = {"hostId": "local", "threadId": self.excluded,
                                                "turnId": "", "event": "Stop", "receivedAt": 0}
        self.events.write_text(json.dumps(state))
        prepared = json.loads(self.run_script("prepare", "--trigger", "event").stdout)
        self.assertEqual(prepared["scope"], "events")
        run_id = str(uuid.uuid4())
        started = self.start(prepared, run_id)
        self.assertEqual(started["scope"], "events")
        self.assertEqual({(p["hostId"], p["threadId"]) for p in started["affectedChats"]},
                         {("local", source), ("remote-a", source)})
        later = self.event()
        self.run_script("signal", event=later)
        self.assertEqual(self.start(prepared, run_id), started)
        self.assertEqual(json.loads(self.run_script("status").stdout)["pendingCount"], 1)
        self.run_script("finish", "--run-id", run_id)
        followup = json.loads(self.run_script("prepare", "--trigger", "event").stdout)
        next_id = str(uuid.uuid4())
        selected = self.start(followup, next_id)
        self.assertEqual(selected["affectedChats"], [{"hostId": "local", "threadId": later["session_id"]}])
        self.run_script("finish", "--run-id", next_id)
        self.assertFalse(json.loads(self.run_script("prepare", "--trigger", "event").stdout)["launch"])

    def test_scheduled_intent_upgrades_a_pending_event_and_survives_active_overlap(self):
        self.install()
        self.run_script("signal", event=self.event())
        prepared = json.loads(self.run_script("prepare", "--trigger", "event").stdout)
        upgraded = json.loads(self.run_script("prepare", "--trigger", "full").stdout)
        self.assertFalse(upgraded["launch"])
        self.assertEqual(upgraded["reservation"]["scope"], "full")
        run_id = str(uuid.uuid4())
        self.assertEqual(self.start(prepared, run_id)["scope"], "full")
        self.run_script("prepare", "--trigger", "full")
        self.start(prepared, run_id)
        self.assertTrue(json.loads(self.run_script("status").stdout)["fullSweepPending"])
        self.run_script("finish", "--run-id", run_id)
        self.assertEqual(json.loads(self.run_script("prepare", "--trigger", "event").stdout)["scope"], "full")

    def test_failed_event_scope_restores_metadata_without_immediate_retry(self):
        self.install()
        self.run_script("signal", event=self.event())
        prepared = json.loads(self.run_script("prepare", "--trigger", "event").stdout)
        initial_notifications = len(self.log.read_text().splitlines())
        self.run_script("cancel", "--token", prepared["token"])
        self.assertEqual(len(self.log.read_text().splitlines()), initial_notifications)
        prepared = json.loads(self.run_script("prepare", "--trigger", "event").stdout)
        run_id = str(uuid.uuid4())
        self.start(prepared, run_id)
        self.run_script("finish", "--run-id", run_id, "--outcome", "error", "--message", "Unavailable evidence")
        status = json.loads(self.run_script("status").stdout)
        self.assertEqual(status["pendingCount"], 1)
        self.assertFalse(status["fullSweepPending"])
        self.assertEqual(len(self.log.read_text().splitlines()), initial_notifications + 1)
        retry = json.loads(self.run_script("prepare", "--trigger", "event").stdout)
        self.assertEqual(retry["scope"], "events")
        retry_id = str(uuid.uuid4())
        self.run_script("bind", "--run-id", retry_id, "--token", retry["token"])
        self.run_script("recover", "--run-id", retry_id, "--message", "Verified terminal before begin")
        self.assertEqual(json.loads(self.events.read_text())["runs"][retry_id]["scope"], "events")
        self.assertEqual(json.loads(self.run_script("prepare", "--trigger", "event").stdout)["scope"], "events")

    def test_failed_full_pass_retains_quiet_sweep_intent(self):
        self.install()
        prepared = json.loads(self.run_script("prepare", "--trigger", "full").stdout)
        run_id = str(uuid.uuid4())
        self.start(prepared, run_id)
        self.run_script("finish", "--run-id", run_id, "--outcome", "error", "--message", "Incomplete scan")
        self.assertTrue(json.loads(self.run_script("status").stdout)["fullSweepPending"])
        self.assertEqual(len(self.log.read_text().splitlines()), 1)
        self.assertEqual(json.loads(self.run_script("prepare", "--trigger", "event").stdout)["scope"], "full")

    def test_legacy_reservation_and_recovery_remain_full_and_keep_newer_metadata(self):
        self.install()
        source = str(uuid.uuid4())
        self.run_script("signal", event=self.event(session=source))
        prepared = json.loads(self.run_script("prepare").stdout)
        state = json.loads(self.events.read_text())
        state["launch"].pop("scope")
        state["launch"].pop("eventRevision")
        state.pop("eventRevision")
        self.events.write_text(json.dumps(state))
        run_id = str(uuid.uuid4())
        self.assertEqual(self.start(prepared, run_id)["scope"], "full")
        state = json.loads(self.events.read_text())
        state["runs"][run_id].pop("scope")
        state["runs"][run_id].pop("affectedChats")
        self.events.write_text(json.dumps(state))
        newer = self.event(session=source)
        self.run_script("signal", event=newer)
        self.assertEqual(self.start(prepared, run_id)["scope"], "full")
        self.run_script("recover", "--run-id", run_id, "--message", "Verified legacy run terminal")
        state = json.loads(self.events.read_text())
        self.assertEqual(next(iter(state["pending"].values()))["turnId"], newer["turn_id"])
        self.assertEqual(json.loads(self.run_script("prepare", "--trigger", "event").stdout)["scope"], "full")

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

    def allow_remote(self, host):
        config = json.loads(self.config.read_text())
        config.setdefault("remoteHosts", {})[host] = {"enabled": True}
        self.config.write_text(json.dumps(config))

    def wire_event(self, host, session=None, **fields):
        payload = dict(hostId=host, threadId=session or str(uuid.uuid4()),
                       turnId=str(uuid.uuid4()), event="Stop", source="")
        payload.update(fields)
        key = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        return dict(payload, id=key)

    def test_remote_identity_is_pinned_and_only_metadata_is_accepted(self):
        self.install()
        self.allow_remote("remote-a")
        event = self.wire_event("remote-b")
        rejected = self.run_script("receive", "--host-id", "remote-a", event={"events": [event]}, check=False)
        self.assertNotEqual(rejected.returncode, 0)
        event = self.wire_event("remote-a", prompt="must not be transported")
        rejected = self.run_script("receive", "--host-id", "remote-a", event={"events": [event]}, check=False)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_remote_namespaces_and_pending_followups_use_the_same_writer(self):
        self.install()
        self.allow_remote("remote-a")
        self.allow_remote("remote-b")
        prepared = json.loads(self.run_script("prepare").stdout)
        run_id = str(uuid.uuid4())
        self.start(prepared, run_id)
        session = str(uuid.uuid4())
        batches = [(host, {"events": [self.wire_event(host, session)]}) for host in ("remote-a", "remote-b")]
        for host, batch in batches:
            first = self.run_script("receive", "--host-id", host, event=batch)
            again = self.run_script("receive", "--host-id", host, event=batch)
            self.assertEqual(json.loads(first.stdout), json.loads(again.stdout))
        self.assertFalse(self.log.exists())
        pending = json.loads(self.events.read_text())["pending"]
        self.assertEqual({e["hostId"] for e in pending.values()}, {"remote-a", "remote-b"})
        self.run_script("finish", "--run-id", run_id)
        self.assertEqual(len(self.log.read_text().splitlines()), 1)

    def test_remote_spool_retries_without_ack_and_drops_prompt_content(self):
        self.install()
        self.allow_remote("remote-a")
        remote_config = self.home / "remote/.codex/chat-organizer/remote-config.json"
        remote_config.parent.mkdir(parents=True)
        remote_hooks = remote_config.parent.parent / "hooks.json"
        original_hooks = {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "existing-remote-hook"}]}]}}
        remote_hooks.write_text(json.dumps(original_hooks))
        def remote(action, event=None):
            return subprocess.run([sys.executable, str(REMOTE_SCRIPT), action,
                                   "--config", str(remote_config), "--host-id", "remote-a"],
                                  input=json.dumps(event) if event else None,
                                  text=True, capture_output=True, check=True)
        remote("install")
        native = self.event()
        native.update(prompt="private prompt", transcript_path="private transcript", credentials="private token")
        remote("signal", native)
        spool = remote_config.with_name("remote-events.json")
        first_pending = json.loads(spool.read_text())["pending"]
        self.assertNotIn("private", json.dumps(first_pending))
        def read_line(process):
            self.assertTrue(select.select([process.stdout], [], [], 5)[0], "stream did not produce a line")
            return json.loads(process.stdout.readline())
        for acknowledge in (False, True):
            process = subprocess.Popen([sys.executable, str(REMOTE_SCRIPT), "stream",
                                        "--config", str(remote_config)], stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
            try:
                self.assertEqual(read_line(process), {"ready": "remote-a", "protocol": 1})
                batch = read_line(process)
                self.assertEqual({e["id"] for e in batch["events"]}, set(first_pending))
                if acknowledge:
                    received = self.run_script("receive", "--host-id", "remote-a", event=batch)
                    process.stdin.write(received.stdout.encode())
                    process.stdin.flush()
                process.stdin.close()
                self.assertEqual(process.wait(timeout=5), 0)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=5)
                if not process.stdin.closed:
                    process.stdin.close()
                process.stdout.close()
            self.assertEqual(bool(json.loads(spool.read_text())["pending"]), not acknowledge)
        remote("signal", native)
        self.assertFalse(json.loads(spool.read_text())["pending"])
        remote("uninstall")
        self.assertEqual(json.loads(remote_hooks.read_text())["hooks"]["Stop"], original_hooks["hooks"]["Stop"])
        remote("signal", self.event())
        self.assertFalse(json.loads(spool.read_text())["pending"])

    def test_cancelled_launch_releases_pending_remote_work(self):
        self.install()
        self.allow_remote("remote-a")
        prepared = json.loads(self.run_script("prepare").stdout)
        batch = {"events": [self.wire_event("remote-a")]}
        self.run_script("receive", "--host-id", "remote-a", event=batch)
        self.assertFalse(self.log.exists())
        self.run_script("cancel", "--token", prepared["token"], "--message", "Launch failed before chat creation")
        self.assertEqual(len(self.log.read_text().splitlines()), 1)
        status = json.loads(self.run_script("status").stdout)
        self.assertIsNone(status["launch"])
        self.assertEqual(status["pendingCount"], 1)


if __name__ == "__main__":
    unittest.main()
