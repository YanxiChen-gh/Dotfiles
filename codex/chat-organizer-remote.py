#!/usr/bin/env python3
"""Spool remote lifecycle metadata and carry it over authenticated SSH stdio."""

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import select
import shlex
import signal as signals
import subprocess
import shutil
import sys
import time
import uuid

MARKER = ": dotfiles-codex-chat-organizer-remote; "
EVENTS = ("SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest")
LIMIT = 65536


def approved_handler(config):
    command = MARKER + "exec " + shlex.join([
        sys.executable, str(Path(__file__).resolve()), "signal", "--config", str(config),
    ])
    return {"type": "command", "command": command, "async": True, "timeout": 10}


def reviewed_definitions(config):
    expected = approved_handler(config)
    found = []
    for event, groups in read_json(config.parent.parent / "hooks.json", {}).get("hooks", {}).items():
        for group in groups:
            for handler in group.get("hooks", []):
                if handler.get("command", "").startswith(MARKER):
                    if event not in EVENTS or group != {"hooks": [expected]}:
                        raise ValueError("Organizer hook definition differs from the approved implementation")
                    found.append(event)
    if sorted(found) != sorted(EVENTS):
        raise ValueError("Exactly four approved organizer definitions are required")
    return expected


def read_json(path, default=None):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        if default is None:
            raise
        return default


def write_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    os.chmod(temporary, 0o600)
    temporary.replace(path)


@contextlib.contextmanager
def locked(config):
    with config.with_name("events.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def install(args):
    args.config.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    hooks_path = args.config.parent.parent / "hooks.json"
    with locked(args.config):
        hooks = read_json(hooks_path, {})
        expected = approved_handler(args.config)
        for event, groups in hooks.get("hooks", {}).items():
            kept = []
            for group in groups:
                handlers = group.get("hooks", [])
                if any(h.get("command", "").startswith(MARKER) for h in handlers):
                    if event not in EVENTS or group != {"hooks": [expected]}:
                        raise ValueError("Preserving a modified organizer hook; review is required")
                remaining = [h for h in handlers if not h.get("command", "").startswith(MARKER)]
                if len(remaining) == len(handlers):
                    kept.append(group)
                elif remaining:
                    kept.append(dict(group, hooks=remaining))
            hooks["hooks"][event] = kept
        config = read_json(args.config, {})
        if args.action == "install":
            if not args.host_id or args.host_id == "local":
                raise ValueError("A saved remote host identity is required")
            if config.get("hostId") not in (None, args.host_id):
                raise ValueError("Remote helper is bound to another saved host; preserving its pending identities")
            excluded = set(config.get("excludedThreadIds", []))
            excluded.update(str(uuid.UUID(value)) for value in args.exclude)
            config.update(hostId=args.host_id, enabled=True, excludedThreadIds=sorted(excluded))
            for event in EVENTS:
                hooks.setdefault("hooks", {}).setdefault(event, []).append({"hooks": [expected]})
        else:
            config["enabled"] = False
        write_json(args.config, config)
        write_json(hooks_path, hooks)
    print("Remote hooks installed; native /hooks review is required for new definitions."
          if args.action == "install" else "Remote organizer hooks disabled; other hooks preserved.")


class NativeClient:
    def __init__(self, executable):
        self.process = subprocess.Popen([str(executable), "app-server", "--stdio"],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, bufsize=0)
        self.identifier = 0

    def request(self, method, params):
        self.identifier += 1
        self.process.stdin.write(json.dumps({"id": self.identifier, "method": method, "params": params}).encode() + b"\n")
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            if not select.select([self.process.stdout], [], [], 1)[0]:
                continue
            line = self.process.stdout.readline(4 * 1024 * 1024)
            if not line:
                raise ValueError("Native app-server exited before replying")
            response = json.loads(line)
            if response.get("id") != self.identifier:
                continue
            if "error" in response:
                raise ValueError("Native " + method + " rejected: " + str(response["error"]))
            return response["result"]
        raise TimeoutError("Native " + method + " timed out")

    def __enter__(self):
        try:
            self.request("initialize", {"clientInfo": {"name": "dotfiles_organizer_enrollment", "version": "1"},
                                        "capabilities": {"experimentalApi": True}})
            self.process.stdin.write(b'{"method":"initialized"}\n')
        except BaseException:
            self.__exit__()
            raise
        return self

    def __exit__(self, *_):
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)
        self.process.stdin.close()
        self.process.stdout.close()


def find_codex(home):
    candidates = []
    if Path("/proc").is_dir():
        for process in Path("/proc").glob("[0-9]*"):
            try:
                executable = (process / "exe").resolve()
                if executable.name == "codex" and home in executable.parents:
                    candidates.append(executable)
            except OSError:
                pass
    candidates += [home / "packages/app-server-daemon/current/bin/codex",
                   home / "packages/standalone/current/bin/codex"]
    path = shutil.which("codex")
    if path:
        candidates.append(Path(path))
    return next((p for p in candidates if p.is_file() and os.access(p, os.X_OK)), None)


def approve(args):
    if hashlib.sha256(Path(__file__).read_bytes()).hexdigest() != args.expected_source_sha256:
        raise ValueError("Installed organizer source does not match the reviewed source fingerprint")
    expected = reviewed_definitions(args.config)
    executable = Path(args.codex_binary) if args.codex_binary else find_codex(args.config.parent.parent)
    if not executable:
        return {"state": "waiting-for-native-codex"}
    version = subprocess.run([str(executable), "--version"], capture_output=True, text=True, timeout=10)
    match = re.fullmatch(r"codex-cli (\d+)\.(\d+)\.(\d+)\s*", version.stdout)
    if version.returncode or not match or tuple(map(int, match.groups())) < (0, 169, 0):
        return {"state": "waiting-for-compatible-native-api"}
    with NativeClient(executable) as client:
        def inventory():
            result = client.request("hooks/list", {"cwds": [str(Path.home())]})
            hooks = [h for e in result["data"] for h in e["hooks"]
                     if h.get("command", "").startswith(MARKER)]
            names = {"SessionStart": "sessionStart", "UserPromptSubmit": "userPromptSubmit",
                     "Stop": "stop", "PermissionRequest": "permissionRequest"}
            if len(hooks) != 4 or {h["eventName"] for h in hooks} != set(names.values()):
                raise ValueError("Native inventory does not contain the four reviewed hooks")
            for hook in hooks:
                if (Path(hook["sourcePath"]).resolve() != (args.config.parent.parent / "hooks.json").resolve()
                        or hook.get("source") != "user" or hook.get("isManaged")
                        or hook.get("command") != expected["command"] or hook.get("async") is not True
                        or hook.get("timeoutSec") != 10 or hook.get("matcher") is not None
                        or not hook.get("enabled")
                        or not re.fullmatch(r"sha256:[0-9a-f]{64}", hook["currentHash"])):
                    raise ValueError("Native hook identity differs from the reviewed definition")
            return hooks
        hooks = inventory()
        updates = {h["key"]: {"trusted_hash": h["currentHash"]} for h in hooks if h["trustStatus"] != "trusted"}
        if updates:
            client.request("config/batchWrite", {
                "edits": [{"keyPath": "hooks.state", "value": updates, "mergeStrategy": "upsert"}],
                "filePath": None, "expectedVersion": None, "reloadUserConfig": True,
            })
        hooks = inventory()
        if not all(h["trustStatus"] == "trusted" and h["enabled"] for h in hooks):
            raise ValueError("Native approval did not establish enabled, trusted organizer hooks")
    return {"state": "trusted", "nativeVersion": version.stdout.strip(),
            "approvedCount": len(updates), "hooks": [{"event": h["eventName"], "trust": h["trustStatus"],
                                                      "enabled": h["enabled"], "async": h["async"]} for h in hooks]}


def stage(args):
    root = args.config.parent
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    destination = root / "remote.py"
    source = Path(__file__).read_bytes()
    if destination.exists() and destination.read_bytes() != source:
        print("Existing organizer runtime preserved; pinned Mac enrollment owns updates.")
        return
    destination.write_bytes(source)
    destination.chmod(0o600)
    write_json(root / "bootstrap.json", {"sourceSha256": hashlib.sha256(source).hexdigest(),
                                        "state": "waiting-for-mac-enrollment"})
    print("Organizer helper staged; saved-host discovery completes native enrollment.")


def state_path(config):
    return config.with_name("remote-events.json")


def spool(args):
    config = read_json(args.config)
    if not config.get("enabled"):
        return
    event = json.load(sys.stdin)
    name = event.get("hook_event_name")
    session = str(uuid.UUID(event["session_id"]))
    source = event.get("source", "") if name == "SessionStart" else ""
    if name not in EVENTS or session in config["excludedThreadIds"]:
        return
    if name == "SessionStart" and source not in ("startup", "resume", "fork", "clear"):
        return
    turn = event.get("turn_id") or ""
    if not isinstance(turn, str) or len(turn) > 100 or any(ord(c) < 32 for c in turn):
        raise ValueError("Invalid lifecycle turn identity")
    payload = {"hostId": config["hostId"], "threadId": session,
               "turnId": turn, "event": name, "source": source}
    key = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    with locked(args.config):
        state = read_json(state_path(args.config), {"seen": [], "pending": {}})
        if key in state["seen"]:
            return
        state["seen"] = (state["seen"] + [key])[-2048:]
        state["pending"][key] = payload
        write_json(state_path(args.config), state)


def input_line(timeout):
    if not select.select([sys.stdin], [], [], timeout)[0]:
        return None
    line = sys.stdin.readline(LIMIT + 1)
    if not line:
        raise EOFError()
    if len(line.encode()) > LIMIT:
        raise ValueError("Acknowledgement is too large")
    return json.loads(line)


def stream(args):
    config = read_json(args.config)
    if not config.get("enabled"):
        return
    print(json.dumps({"ready": config["hostId"], "protocol": 1}), flush=True)
    while True:
        with locked(args.config):
            state = read_json(state_path(args.config), {"seen": [], "pending": {}})
            batch = [dict(payload, id=key) for key, payload in list(state["pending"].items())[:128]]
        if not batch:
            input_line(1)
            continue
        print(json.dumps({"events": batch}, separators=(",", ":")), flush=True)
        ack = input_line(30)
        if ack is None:
            raise TimeoutError("Local acknowledgement timed out")
        sent = {item["id"] for item in batch}
        if not isinstance(ack, dict) or set(ack) != {"ack"} or not isinstance(ack["ack"], list) or not set(ack["ack"]) <= sent:
            raise ValueError("Invalid event acknowledgement")
        with locked(args.config):
            state = read_json(state_path(args.config), {"seen": [], "pending": {}})
            for key in ack["ack"]:
                state["pending"].pop(key, None)
            state["lastAckAt"] = time.time()
            write_json(state_path(args.config), state)


def relay_status_path(config, host):
    return config.with_name("remote-" + hashlib.sha256(host.encode()).hexdigest()[:12] + ".json")


def relay(args):
    status_path = relay_status_path(args.config, args.host_id)
    delay = 1
    while True:
        route = read_json(args.config).get("remoteHosts", {}).get(args.host_id, {})
        if not route.get("enabled"):
            return
        remote_command = shlex.join([route["remotePython"], route["remoteHelper"],
                                     "stream", "--config", route["remoteConfig"]])
        command = ["/usr/bin/ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=20",
                   "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2",
                   "--", route["sshAlias"], remote_command]
        write_json(status_path, {"hostId": args.host_id, "connected": False,
                                "state": "connecting", "at": time.time()})
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
        ready = False
        try:
            while True:
                current = read_json(args.config).get("remoteHosts", {}).get(args.host_id, {})
                if current != route:
                    break
                if not select.select([process.stdout], [], [], 1)[0]:
                    continue
                line = process.stdout.readline(LIMIT + 1)
                if not line or len(line) > LIMIT:
                    raise ValueError("SSH stream ended or exceeded its metadata limit")
                message = json.loads(line)
                if not ready:
                    if message != {"ready": args.host_id, "protocol": 1}:
                        raise ValueError("SSH source identity does not match the saved host")
                    ready = True
                    delay = 1
                    write_json(status_path, {"hostId": args.host_id, "connected": True, "at": time.time()})
                    continue
                result = subprocess.run([sys.executable, route["localHelper"], "receive",
                                         "--config", str(args.config), "--host-id", args.host_id],
                                        input=line, capture_output=True, timeout=30)
                if result.returncode:
                    raise ValueError("Local event receiver rejected the batch")
                ack = json.loads(result.stdout)
                if not isinstance(ack, dict) or set(ack) != {"ack"}:
                    raise ValueError("Local receiver did not acknowledge the batch")
                process.stdin.write(json.dumps(ack).encode() + b"\n")
                process.stdin.flush()
                write_json(status_path, {"hostId": args.host_id, "connected": True,
                                        "lastAckAt": time.time(), "batchCount": len(ack["ack"])})
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            write_json(status_path, {"hostId": args.host_id, "connected": False,
                                    "error": str(error), "at": time.time()})
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            process.stdin.close()
            process.stdout.close()
        time.sleep(delay)
        delay = min(delay * 2, 30)


def configure_relay(args):
    if sys.platform != "darwin":
        raise ValueError("The launcher relay is installed on the Mac")
    label = "com.yanxi.codex-organizer.remote." + hashlib.sha256(args.host_id.encode()).hexdigest()[:12]
    with locked(args.config):
        config = read_json(args.config)
        hosts = config.setdefault("remoteHosts", {})
        if args.action == "configure-relay":
            if not all((args.ssh_alias, args.remote_helper, args.remote_config)):
                raise ValueError("SSH alias, remote helper and remote config paths are required")
            hosts[args.host_id] = {"enabled": True, "sshAlias": args.ssh_alias,
                                  "remoteHelper": args.remote_helper, "remoteConfig": args.remote_config,
                                  "remotePython": args.remote_python,
                                  "localHelper": str(Path(__file__).with_name("chat-organizer.py").resolve()),
                                  "launchAgentLabel": label}
        else:
            hosts[args.host_id]["enabled"] = False
        write_json(args.config, config)
    domain = "gui/" + str(os.getuid())
    subprocess.run(["/bin/launchctl", "bootout", domain + "/" + label], capture_output=True)
    if args.action == "uninstall-relay":
        subprocess.run(["/bin/launchctl", "disable", domain + "/" + label], check=True)
        write_json(relay_status_path(args.config, args.host_id),
                   {"hostId": args.host_id, "connected": False, "state": "disabled", "at": time.time()})
        print("Organizer SSH relay disabled; pending metadata and other connections preserved.")
        return
    folder = Path.home() / "Library/LaunchAgents"
    folder.mkdir(parents=True, exist_ok=True)
    log = args.config.with_name(label + ".log")
    log.touch(exist_ok=True)
    log.chmod(0o600)
    plist = folder / (label + ".plist")
    plist.write_bytes(plistlib.dumps({
        "Label": label, "RunAtLoad": True, "KeepAlive": {"SuccessfulExit": False},
        "ProgramArguments": [sys.executable, str(Path(__file__).resolve()), "relay",
                             "--config", str(args.config), "--host-id", args.host_id],
        "StandardErrorPath": str(log), "StandardOutPath": str(log),
    }))
    subprocess.run(["/bin/launchctl", "enable", domain + "/" + label], check=True)
    subprocess.run(["/bin/launchctl", "bootstrap", domain, str(plist)], check=True)
    print("Configured authenticated SSH metadata relay: " + label)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "uninstall", "stage", "approve", "signal", "stream", "relay", "configure-relay", "uninstall-relay", "status"))
    parser.add_argument("--config", type=Path, default=Path.home() / ".codex/chat-organizer/remote-config.json")
    parser.add_argument("--host-id")
    parser.add_argument("--exclude", action="append", default=[])
    parser.add_argument("--ssh-alias")
    parser.add_argument("--remote-helper")
    parser.add_argument("--remote-config")
    parser.add_argument("--remote-python", default="/usr/bin/python3")
    parser.add_argument("--codex-binary")
    parser.add_argument("--expected-source-sha256")
    args = parser.parse_args()
    args.config = args.config.expanduser().resolve()
    if args.action in ("relay", "configure-relay", "uninstall-relay") and (not args.host_id or args.host_id == "local"):
        parser.error("a saved remote --host-id is required")
    if args.action == "approve" and not args.expected_source_sha256:
        parser.error("approve requires a reviewed --expected-source-sha256")
    try:
        if args.action in ("install", "uninstall"):
            install(args)
        elif args.action == "stage":
            stage(args)
        elif args.action == "approve":
            print(json.dumps(approve(args)))
        elif args.action == "signal":
            spool(args)
        elif args.action == "stream":
            stream(args)
        elif args.action == "relay":
            signals.signal(signals.SIGTERM, lambda *_: sys.exit(0))
            relay(args)
        elif args.action in ("configure-relay", "uninstall-relay"):
            configure_relay(args)
        else:
            state = read_json(state_path(args.config), {"pending": {}})
            print(json.dumps({"pendingCount": len(state["pending"]), "lastAckAt": state.get("lastAckAt")}))
    except (EOFError, BrokenPipeError):
        return 0
    except (OSError, ValueError, KeyError, TypeError, TimeoutError, subprocess.SubprocessError) as error:
        print("Remote organizer: " + str(error), file=sys.stderr)
        return 0 if args.action == "signal" else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
