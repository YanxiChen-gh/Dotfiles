#!/usr/bin/env python3
"""Enroll reviewed organizer hooks from fresh native saved-project metadata."""

import argparse
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def read_json(path):
    return json.loads(path.read_text())


def write_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.chmod(0o600)
    temporary.replace(path)


def resolve_alias(host, declarations):
    identifier, display = host["hostId"], host.get("hostDisplayName")
    encoded = identifier.removeprefix("remote-ssh-discovered:") if identifier.startswith("remote-ssh-discovered:") else None
    pattern = r"^([0-9a-f-]{36})\.(?:ona|gitpod)\.(?:environment|codex)$"
    identity = re.fullmatch(pattern, display or "")
    candidates = set()
    for declaration in declarations:
        alias = declaration["sshAlias"]
        alias_identity = re.fullmatch(pattern, alias)
        paths = {p["remotePath"] for p in declaration.get("projects", [])}
        matches = alias == encoded or alias == display or (identity and alias_identity and identity[1] == alias_identity[1])
        if matches and paths.intersection(host["paths"]):
            candidates.add(alias)
    if len(candidates) != 1:
        raise ValueError("Saved host does not resolve to one declared SSH route")
    return candidates.pop()


def deployment(source, approved, host_id, excluded):
    data = {"source": base64.b64encode(source).decode(), "approved": approved,
            "hostId": host_id, "excluded": excluded}
    return "PAYLOAD=" + repr(data) + "\n" + '''
import base64,hashlib,json,os,pathlib,subprocess,sys
source=base64.b64decode(PAYLOAD['source'])
home=pathlib.Path(os.environ.get('CODEX_HOME',str(pathlib.Path.home()/'.codex')))
root=home/'chat-organizer'
root.mkdir(parents=True,exist_ok=True,mode=0o700)
helper=root/'remote.py'
config=root/'remote-config.json'
if helper.exists() and hashlib.sha256(helper.read_bytes()).hexdigest() not in PAYLOAD['approved']:
 raise ValueError('Preserving an unknown or modified remote organizer helper')
if config.exists():
 existing=json.loads(config.read_text())
 if existing.get('enabled') is False:
  print(json.dumps({'state':'disabled-by-user'}));sys.exit(0)
 if existing.get('hostId') not in (None,PAYLOAD['hostId']):
  raise ValueError('Preserving a helper bound to another saved host identity')
helper.write_bytes(source);helper.chmod(0o600)
hooks_path=home/'hooks.json'
hooks=json.loads(hooks_path.read_text()) if hooks_path.exists() else {}
owned=[h for groups in hooks.get('hooks',{}).values() for group in groups for h in group.get('hooks',[]) if h.get('command','').startswith(': dotfiles-codex-chat-organizer-remote;')]
if not owned:
 command=[sys.executable,str(helper),'install','--config',str(config),'--host-id',PAYLOAD['hostId']]
 for thread in PAYLOAD['excluded']:command+=['--exclude',thread]
 subprocess.run(command,check=True,capture_output=True)
else:
 import importlib.util
 spec=importlib.util.spec_from_file_location('reviewed_organizer',helper)
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 module.reviewed_definitions(config)
 with module.locked(config):
  existing=module.read_json(config)
  existing['excludedThreadIds']=sorted(set(existing.get('excludedThreadIds',[]))|set(PAYLOAD['excluded']))
  module.write_json(config,existing)
digest=hashlib.sha256(source).hexdigest()
result=subprocess.run([sys.executable,str(helper),'approve','--config',str(config),'--expected-source-sha256',digest],check=True,capture_output=True,text=True,timeout=100)
report=json.loads(result.stdout)
report.update(remoteHelper=str(helper),remoteConfig=str(config),remotePython=sys.executable,sourceSha256=digest)
print(json.dumps(report))
'''


def enroll(args, projects):
    config = read_json(args.config)
    consent = config.get("remoteEnrollment", {})
    if not consent.get("enabled"):
        return {"enabled": False, "hosts": []}
    source_path = Path(consent["sourcePath"])
    source = source_path.read_bytes()
    digest = hashlib.sha256(source).hexdigest()
    if digest != consent["sourceSha256"]:
        raise ValueError("Enrollment source changed; review it before updating its approval pin")
    declarations = read_json(args.native_config).get("remoteConnections", [])
    grouped = {}
    for project in projects:
        if project.get("projectKind") != "remote":
            continue
        host_id = project["hostId"]
        if host_id == "local":
            raise ValueError("Remote project has a local host identity")
        host = grouped.setdefault(host_id, {"hostId": host_id, "hostDisplayName": project.get("hostDisplayName"), "paths": set()})
        if host["hostDisplayName"] != project.get("hostDisplayName"):
            raise ValueError("Native metadata disagrees about the saved host identity")
        host["paths"].add(project["path"])
    results = []
    for host_id, host in grouped.items():
        try:
            previous = config.get("remoteHosts", {}).get(host_id)
            if previous and not previous.get("enabled"):
                results.append({"hostId": host_id, "state": "disabled-by-user"})
                continue
            alias = resolve_alias(host, declarations)
            program = deployment(source, [digest, *consent.get("previousSourceSha256", [])],
                                 host_id, config["excludedThreadIds"])
            result = subprocess.run(["/usr/bin/ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=20",
                                     "--", alias, "/usr/bin/python3 -"], input=program,
                                    capture_output=True, text=True, timeout=120)
            if result.returncode:
                raise ValueError("Remote reviewed enrollment failed; existing trust/definitions were preserved")
            report = json.loads(result.stdout)
            if report["state"] == "trusted":
                desired = {"sshAlias": alias, "remoteHelper": report["remoteHelper"],
                           "remoteConfig": report["remoteConfig"], "remotePython": report["remotePython"]}
                if not previous or any(previous.get(k) != value for k, value in desired.items()):
                    command = [sys.executable, str(source_path), "configure-relay", "--config", str(args.config),
                               "--host-id", host_id, "--ssh-alias", alias,
                               "--remote-helper", report["remoteHelper"], "--remote-config", report["remoteConfig"],
                               "--remote-python", report["remotePython"]]
                    subprocess.run(command, check=True, capture_output=True, timeout=20)
                report.update(sshAlias=alias, state="enrolled")
            results.append(dict(report, hostId=host_id))
        except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
            results.append({"hostId": host_id, "state": "deferred", "reason": str(error)})
    write_json(args.config.with_name("enrollment-status.json"), {"hosts": results})
    return {"enabled": True, "hosts": results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("enable", "disable", "run"))
    parser.add_argument("--config", type=Path, default=Path.home() / ".codex/chat-organizer/config.json")
    parser.add_argument("--source", type=Path, default=Path(__file__).with_name("chat-organizer-remote.py"))
    parser.add_argument("--previous-source-sha256", action="append", default=[])
    parser.add_argument("--native-config", type=Path, default=Path.home() / ".codex/codex-app/config.json")
    args = parser.parse_args()
    try:
        if args.action == "run":
            data = json.load(sys.stdin)
            projects = data["projects"] if isinstance(data, dict) else data
            if not isinstance(projects, list):
                raise ValueError("Fresh native project metadata is required")
            result = enroll(args, projects)
        else:
            with args.config.with_name("events.lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                config = read_json(args.config)
                if args.action == "enable":
                    digest = hashlib.sha256(args.source.read_bytes()).hexdigest()
                    if not all(re.fullmatch(r"[0-9a-f]{64}", value) for value in args.previous_source_sha256):
                        raise ValueError("Invalid prior reviewed source fingerprint")
                    config["remoteEnrollment"] = {"enabled": True, "sourcePath": str(args.source.resolve()),
                                                  "sourceSha256": digest, "previousSourceSha256": args.previous_source_sha256}
                else:
                    config.setdefault("remoteEnrollment", {})["enabled"] = False
                write_json(args.config, config)
                result = {"enabled": args.action == "enable"}
        print(json.dumps(result))
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print("Organizer enrollment: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
