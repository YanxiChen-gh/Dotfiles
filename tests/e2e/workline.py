import json
import io
import os
from pathlib import Path
import subprocess
import runpy
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError


HELPER = Path(__file__).resolve().parents[2] / "shared-skills/workline/scripts/api.py"


class Workline(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.checkout = self.root / "checkout"
        self.checkout.mkdir()
        self.token = self.root / "reporter.key"
        self.vercel = self.root / "vercel.key"
        self.config = self.root / "config.json"
        self.fake = self.root / "vercel.py"
        self.token.write_text("wk_test_reporter")
        self.vercel.write_text("test_vercel_private")
        self.fake.write_text('''
import json, os, pathlib, sys
assert pathlib.Path.cwd() == pathlib.Path(__file__).resolve().parent
args = sys.argv[1:]
headers = pathlib.Path(args[args.index("--header") + 1][1:])
assert headers.stat().st_mode & 0o077 == 0
assert headers.parent.stat().st_mode & 0o077 == 0
assert "wk_test_reporter" not in " ".join(args)
assert "test_vercel_private" not in " ".join(args)
assert os.environ["VERCEL_TOKEN"] == "test_vercel_private"
assert os.environ["VERCEL_PROJECT_ID"] == "prj_DEbVHeehJbWoZNOMfdzTiy4RKJx7"
assert os.environ["VERCEL_ORG_ID"] == "team_KRqbmQkHbHxnlqEnmBn8oWxr"
assert args[args.index("--deployment") + 1] == "https://workline-bice.vercel.app"
assert "--location" not in args
assert "Authorization: Bearer wk_test_reporter" in headers.read_text()
if "--data-binary" in args:
    assert "Idempotency-Key: session-123" in headers.read_text()
    body = pathlib.Path(args[args.index("--data-binary") + 1][1:])
    assert body.stat().st_mode & 0o077 == 0
    action = json.loads(body.read_text())["action"]
    assert action == "progress" or (action == "queue" and os.environ.get("FAKE_SCOPE") in ("queue", "controller"))
if os.environ.get("FAKE_FAILURE"):
    print("wk_test_reporter test_vercel_private", file=sys.stderr)
    sys.exit(1)
pathlib.Path(args[args.index("--output") + 1]).write_text(json.dumps({"scope": os.environ.get("FAKE_SCOPE", "reporter")}))
print(os.environ.get("FAKE_STATUS", "200"), end="")
''')
        self.config.write_text(json.dumps({
            "credential_file": str(self.token),
            "vercel_token_file": str(self.vercel),
            "vercel_command": [sys.executable, str(self.fake)],
        }))
        for path in (self.token, self.vercel, self.config):
            path.chmod(0o600)
        self.environment = dict(os.environ, WORKLINE_CONFIG=str(self.config))

    def call(self, *args, payload=None):
        return subprocess.run(
            [sys.executable, str(HELPER), *args],
            input=json.dumps(payload) if payload is not None else "",
            env=self.environment, cwd=self.checkout, capture_output=True, text=True, check=False,
        )

    def test_read_and_idempotent_progress(self):
        result = self.call("/api/me")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"scope": "reporter"})
        for _ in range(2):
            result = self.call("/api/work/example/commands", "--key", "session-123",
                               payload={"action": "progress"})
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_unsupported_paths_and_intent(self):
        for path in ("https://example.com/api/me", "/api/credentials", "/api/work?x=1"):
            self.assertNotEqual(self.call(path).returncode, 0)
        result = self.call("/api/work/example/commands", "--key", "session-123",
                           payload={"action": "queue"})
        self.assertNotEqual(result.returncode, 0)

    def test_access_failures_do_not_leak_credentials(self):
        self.environment["FAKE_FAILURE"] = "1"
        result = self.call("/api/me")
        self.assertNotEqual(result.returncode, 0)
        for secret in ("wk_test_reporter", "test_vercel_private"):
            self.assertNotIn(secret, result.stdout + result.stderr)
        self.environment.pop("FAKE_FAILURE")
        self.environment["FAKE_STATUS"] = "409"
        result = self.call("/api/me")
        self.assertIn("HTTP 409", result.stderr)
        self.token.chmod(0o644)
        self.assertNotEqual(self.call("/api/me").returncode, 0)

    def test_queue_requires_an_explicit_queue_grant(self):
        args = ("/api/work/example/commands", "--key", "session-123")
        result = self.call(*args, payload={"action": "queue"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("coding-session credential", result.stderr)
        for scope in ("queue", "controller"):
            with self.subTest(scope=scope):
                self.environment["FAKE_SCOPE"] = scope
                result = self.call(*args, payload={"action": "queue"})
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_ona_session_queues_an_explicit_merge_target_without_a_local_workline_key(self):
        helper = runpy.run_path(str(HELPER))
        request = helper["request"]
        fake_token = "fake.header.signature"
        transport = Mock(side_effect=[{"scope": "queue"}, {"version": 2}])
        payload = {
            "action": "queue",
            "version": 1,
            "expected_heads": {"vantainc/obsidian#21": None, "vantainc/obsidian#22": None},
            "data": {"merge_when_ready": True, "merge_pr": "vantainc/obsidian#22"},
        }
        with patch.dict(os.environ, {}, clear=True), \
                patch.dict(request.__globals__, {"ona_token": lambda: fake_token, "ona_request": transport}), \
                patch("sys.stdin", io.StringIO(json.dumps(payload))):
            result = request("/api/work/example/commands", "test-queue-key")
        self.assertEqual(result, {"version": 2})
        self.assertEqual(transport.call_args_list[0].args, (fake_token, "/api/me"))
        self.assertEqual(transport.call_args_list[1].args, (
            fake_token, "/api/work/example/commands", "test-queue-key",
            payload,
        ))

    def test_ona_session_can_use_existing_vercel_access_for_another_project(self):
        helper = runpy.run_path(str(HELPER))
        request = helper["request"]
        unauthorized = HTTPError("https://workline-bice.vercel.app/api/me", 403, "Forbidden", None, None)
        fallback = Mock(return_value={"scope": "queue"})
        with patch.dict(os.environ, {}, clear=True), patch.dict(request.__globals__, {
            "ona_token": lambda: "fake.header.signature",
            "ona_request": Mock(side_effect=unauthorized),
            "configured_request": fallback,
        }):
            self.assertEqual(request("/api/me", None), {"scope": "queue"})
        fallback.assert_called_once_with("/api/me", None, None, ona="fake.header.signature")


if __name__ == "__main__":
    unittest.main()
