#!/usr/bin/env python3
"""Install and start the user-owned Workline activity reporter."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
from uuid import uuid4


HOME = Path.home()
ROOT = HOME / ".local/share/workline-activity"
LABEL = "com.dotfiles.workline-activity"
UNIT = "workline-activity.service"
FILES = ("activity-service.py", "report-session-activity.mjs", "api.py")


def write_if_changed(path, contents):
    if path.exists() and path.read_bytes() == contents:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(contents)
    temporary.replace(path)
    return True


def available(command):
    return subprocess.run(
        command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    ).returncode == 0


def has_user_systemd():
    if not shutil.which("systemctl"):
        return False
    result = subprocess.run(
        ["systemctl", "--user", "show", "--property=Version"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=False,
    )
    # Some containers install a systemctl shim that exits zero without a manager.
    return result.returncode == 0 and result.stdout.startswith("Version=")


def launch(config, detach):
    with (ROOT / "reporter.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        executable = config["node"]
        command = [executable, str(ROOT / "report-session-activity.mjs"),
                   "--source", config["source"], "--helper", str(ROOT)]
        env = dict(os.environ, PATH=config["path"], CODEX_HOME=config["codex_home"])
        if config.get("workline_config"):
            env["WORKLINE_CONFIG"] = config["workline_config"]
        if config.get("host_id"):
            command += ["--host-id", config["host_id"]]
        if detach:
            with (ROOT / "reporter.log").open("ab") as log:
                subprocess.Popen(
                    command, env=env, start_new_session=True, pass_fds=(lock.fileno(),),
                    stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                )
        else:
            os.set_inheritable(lock.fileno(), True)
            os.execve(executable, command, env)


def systemd_service(command, changed):
    argv = " ".join(json.dumps(arg.replace("%", "%%").replace("$", "$$"), ensure_ascii=False)
                    for arg in command)
    contents = (
        "[Unit]\nDescription=Workline Codex activity reporter\n"
        "[Service]\nType=simple\n"
        f"ExecStart={argv}\nRestart=always\nRestartSec=15\n"
        "[Install]\nWantedBy=default.target\n"
    )
    unit_dir = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "systemd/user"
    updated = write_if_changed(unit_dir / UNIT, contents.encode())
    ctl = ["systemctl", "--user"]
    if updated:
        subprocess.run([*ctl, "daemon-reload"], check=True)
    running = available([*ctl, "is-active", "--quiet", UNIT])
    subprocess.run([*ctl, "enable", "--now", UNIT], check=True)
    if running and (changed or updated):
        subprocess.run([*ctl, "restart", UNIT], check=True)


def launchd_service(command, changed):
    domain = f"gui/{os.getuid()}"
    target = f"{domain}/{LABEL}"
    path = HOME / "Library/LaunchAgents" / f"{LABEL}.plist"
    updated = write_if_changed(path, plistlib.dumps({
        "Label": LABEL, "ProgramArguments": command,
        "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 15,
        "StandardErrorPath": str(ROOT / "reporter.log"),
    }))
    if not available(["launchctl", "print", domain]):
        return
    if available(["launchctl", "print", target]):
        if not changed and not updated:
            return
        subprocess.run(["launchctl", "bootout", target], check=True)
    subprocess.run(["launchctl", "bootstrap", domain, str(path)], check=True)


def install(platform):
    config_path = ROOT / "config.json"
    previous = json.loads(config_path.read_text()) if config_path.exists() else {}
    node = shutil.which("node")
    if not node:
        raise ValueError("Node.js is required to start the Workline reporter")
    manager = "login"
    if platform == "macos" and shutil.which("launchctl"):
        manager = "launchd"
    elif platform == "linux" and has_user_systemd():
        manager = "systemd"
    config = {
        "node": node, "source": previous.get("source") or str(uuid4()),
        "path": os.environ["PATH"], "codex_home": os.environ.get("CODEX_HOME", str(HOME / ".codex")),
        "host_id": os.environ.get("WORKLINE_CODEX_HOST_ID") or previous.get("host_id"),
        "workline_config": os.environ.get("WORKLINE_CONFIG") or previous.get("workline_config"),
        "manager": manager,
    }
    source = Path(__file__).resolve().parent
    changed = write_if_changed(config_path, json.dumps(config, indent=2).encode() + b"\n")
    for name in FILES:
        changed = write_if_changed(ROOT / name, (source / name).read_bytes()) or changed
    command = [sys.executable, str(ROOT / "activity-service.py"), "run"]
    if manager == "systemd":
        systemd_service(command, changed)
    elif manager == "launchd":
        launchd_service(command, changed)
    else:
        launch(config, detach=True)
    print(f"Workline activity reporter installed ({manager})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "ensure", "run"))
    parser.add_argument("--platform", choices=("linux", "macos", "unknown"))
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.action == "install":
            ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
            with (ROOT / "install.lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                install(args.platform)
        else:
            config = json.loads((ROOT / "config.json").read_text())
            if args.action == "run":
                launch(config, detach=False)
            elif config["manager"] == "login" and os.access(ROOT, os.W_OK):
                launch(config, detach=True)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(f"Workline reporter setup failed: {error}")


if __name__ == "__main__":
    main()
