import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "codex/chat-organizer-remote.py"
spec = importlib.util.spec_from_file_location("organizer_enroll", ROOT / "codex/chat-organizer-enroll.py")
enrollment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(enrollment)


class EnrollmentTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.config = self.home / ".codex/chat-organizer/remote-config.json"
        self.helper = self.config.with_name("remote.py")
        self.native_state = self.home / "native-state.json"
        self.env = dict(os.environ, HOME=str(self.home), CODEX_HOME=str(self.home / ".codex"), PATH="/usr/bin:/bin")
        self.digest = hashlib.sha256(SOURCE.read_bytes()).hexdigest()

    def remote(self, action, *args, check=True):
        helper = self.helper if self.helper.exists() else SOURCE
        return subprocess.run([sys.executable, str(helper), action, "--config", str(self.config), *args],
                              env=self.env, text=True, capture_output=True, check=check)

    def fake_native(self):
        binary = self.home / ".codex/packages/standalone/current/bin/codex"
        binary.parent.mkdir(parents=True)
        self.native_state.write_text(json.dumps({"trust": {"unrelated-hook": {"trusted_hash": "unchanged"}}, "writes": []}))
        program = '''
import hashlib,json,pathlib,sys
if '--version' in sys.argv:
 print('codex-cli 0.169.0');sys.exit(0)
home=pathlib.Path.home()/'.codex'
state_path=pathlib.Path(STATE)
events={'SessionStart':'sessionStart','UserPromptSubmit':'userPromptSubmit','Stop':'stop','PermissionRequest':'permissionRequest'}
for line in sys.stdin:
 request=json.loads(line)
 if 'id' not in request:continue
 state=json.loads(state_path.read_text())
 method=request['method'];result={}
 if method=='hooks/list':
  hooks=[]
  for event,groups in json.loads((home/'hooks.json').read_text())['hooks'].items():
   for i,group in enumerate(groups):
    for j,handler in enumerate(group['hooks']):
     key=str(home/'hooks.json')+':'+event+':'+str(i)+':'+str(j)
     digest='sha256:'+hashlib.sha256((key+handler['command']).encode()).hexdigest()
     hooks.append(dict(key=key,eventName=events.get(event,event),sourcePath=str(home/'hooks.json'),source='user',isManaged=False,command=handler['command'],async_=True,timeoutSec=handler.get('timeout',10),matcher=group.get('matcher'),currentHash=digest,enabled=True,trustStatus='trusted' if state['trust'].get(key,{}).get('trusted_hash')==digest else 'untrusted'))
  for h in hooks:h['async']=h.pop('async_')
  result={'data':[{'hooks':hooks}]}
 elif method=='config/batchWrite':
  params=request['params'];state['writes'].append(params)
  for edit in params['edits']:state['trust'].update(edit['value'])
  state_path.write_text(json.dumps(state))
 print(json.dumps({'id':request['id'],'result':result}),flush=True)
'''.replace("STATE", repr(str(self.native_state)))
        binary.write_text("#!" + sys.executable + "\n" + program)
        binary.chmod(0o700)

    def stage_and_install(self):
        self.remote("stage")
        self.remote("install", "--host-id", "remote-new")

    def test_bootstrap_defers_then_native_approval_is_scoped_and_idempotent(self):
        self.remote("stage")
        self.assertFalse((self.home / ".codex/hooks.json").exists())
        self.remote("install", "--host-id", "remote-new")
        waiting = self.remote("approve", "--expected-source-sha256", self.digest)
        self.assertEqual(json.loads(waiting.stdout)["state"], "waiting-for-native-codex")
        self.fake_native()
        binary = self.home / ".codex/packages/standalone/current/bin/codex"
        original = binary.read_text()
        binary.write_text(original.replace("0.169.0", "0.168.0"))
        old = json.loads(self.remote("approve", "--expected-source-sha256", self.digest).stdout)
        self.assertEqual(old["state"], "waiting-for-compatible-native-api")
        binary.write_text(original)
        report = json.loads(self.remote("approve", "--expected-source-sha256", self.digest).stdout)
        self.assertEqual((report["state"], report["approvedCount"]), ("trusted", 4))
        again = json.loads(self.remote("approve", "--expected-source-sha256", self.digest).stdout)
        self.assertEqual(again["approvedCount"], 0)
        state = json.loads(self.native_state.read_text())
        self.assertEqual(state["trust"]["unrelated-hook"], {"trusted_hash": "unchanged"})
        self.assertEqual(len(state["writes"]), 1)
        write = state["writes"][0]
        self.assertTrue(write["reloadUserConfig"])
        self.assertEqual(write["edits"][0]["mergeStrategy"], "upsert")
        self.assertEqual(len(write["edits"][0]["value"]), 4)

    def test_modified_source_or_definition_cannot_gain_approval(self):
        self.stage_and_install()
        self.fake_native()
        rejected = self.remote("approve", "--expected-source-sha256", "0" * 64, check=False)
        self.assertNotEqual(rejected.returncode, 0)
        hooks_path = self.home / ".codex/hooks.json"
        hooks = json.loads(hooks_path.read_text())
        hooks["hooks"]["Stop"][0]["hooks"][0]["timeout"] = 11
        hooks_path.write_text(json.dumps(hooks))
        rejected = self.remote("approve", "--expected-source-sha256", self.digest, check=False)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertFalse(json.loads(self.native_state.read_text())["writes"])
        self.helper.write_text("existing runtime must not be overwritten")
        subprocess.run([sys.executable, str(SOURCE), "stage", "--config", str(self.config)],
                       env=self.env, capture_output=True, check=True)
        self.assertEqual(self.helper.read_text(), "existing runtime must not be overwritten")

    def test_fresh_native_discovery_deploys_and_registers_a_new_host(self):
        self.fake_native()
        mac_config = self.home / "mac/config.json"
        mac_config.parent.mkdir()
        mac_config.write_text(json.dumps({"excludedThreadIds": [], "remoteEnrollment": {
            "enabled": True, "sourcePath": str(SOURCE), "sourceSha256": self.digest}}))
        native_config = self.home / "connections.json"
        native_config.write_text(json.dumps({"remoteConnections": [{"sshAlias": "new-cde", "projects": [{"remotePath": "/workspaces/app"}]}]}))
        args = argparse.Namespace(config=mac_config, native_config=native_config)
        projects = [{"projectKind": "remote", "hostId": "remote-ssh-discovered:new-cde", "hostDisplayName": "new-cde", "path": "/workspaces/app"}]
        original_run = subprocess.run
        relays = []
        def transport(command, **kwargs):
            if command[0] == "/usr/bin/ssh":
                return original_run([sys.executable, "-"], input=kwargs["input"], env=self.env,
                                    text=True, capture_output=True, timeout=30)
            relays.append(command)
            return subprocess.CompletedProcess(command, 0)
        with patch.object(enrollment.subprocess, "run", side_effect=transport):
            result = enrollment.enroll(args, projects)
        self.assertEqual(result["hosts"][0]["state"], "enrolled")
        self.assertEqual(result["hosts"][0]["approvedCount"], 4)
        self.assertEqual(len(relays), 1)
        self.assertIn("configure-relay", relays[0])
        self.assertIn("remote-ssh-discovered:new-cde", relays[0])
        self.helper.write_text("modified helper must be preserved")
        with patch.object(enrollment.subprocess, "run", side_effect=transport):
            refused = enrollment.enroll(args, projects)
        self.assertEqual(refused["hosts"][0]["state"], "deferred")
        self.assertEqual(self.helper.read_text(), "modified helper must be preserved")
        self.assertEqual(len(json.loads(self.native_state.read_text())["writes"]), 1)


if __name__ == "__main__":
    unittest.main()
