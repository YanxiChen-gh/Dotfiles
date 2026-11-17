#!/usr/bin/env python3
"""Coalesce organizer triggers and serialize fresh desktop runs."""

import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time
import uuid

MARKER = ": dotfiles-codex-chat-organizer; "
EVENTS = ("SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest")
RUN_PREFIX = "codex-organizer-run-"


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
def locked(config_path):
    with config_path.with_name("events.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def load_state(config_path):
    state = read_json(config_path.with_name("events.json"), {})
    for key, value in {"seen": [], "pending": {}, "notified": False,
                       "activeRun": None, "launch": None, "runs": {},
                       "directories": {}, "sweepPending": False}.items():
        state.setdefault(key, value)
    return state


def save_state(config_path, state):
    write_json(config_path.with_name("events.json"), state)


def remove_handlers(document):
    for event, groups in document.get("hooks", {}).items():
        kept = []
        for group in groups:
            handlers = group.get("hooks", [])
            remaining = [h for h in handlers if not h.get("command", "").startswith(MARKER)]
            if len(remaining) == len(handlers):
                kept.append(group)
            elif remaining:
                kept.append(dict(group, hooks=remaining))
        document["hooks"][event] = kept


def install(args):
    config_path = args.config
    config_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    hooks_path = config_path.parent.parent / "hooks.json"
    with locked(config_path):
        document = read_json(hooks_path, {})
        remove_handlers(document)
        config = read_json(config_path, {})
        if args.action == "install":
            dispatcher = str(uuid.UUID(args.dispatcher))
            discussion = str(uuid.UUID(args.discussion))
            if dispatcher == discussion:
                raise ValueError("The launcher must be separate from the discussion")
            if not args.ledger.is_file() or not args.policy.is_file():
                raise ValueError("The existing ledger and canonical policy must exist")
            codex = shutil.which(args.codex)
            if not codex:
                raise ValueError("codex is not on PATH")
            excluded = set(config.get("excludedThreadIds", []))
            excluded.update(str(uuid.UUID(value)) for value in args.exclude)
            excluded.update((dispatcher, discussion))
            config.update(enabled=True, dispatcherThreadId=dispatcher,
                          discussionThreadId=discussion, hostId="local",
                          excludedThreadIds=sorted(excluded), ledger=str(args.ledger.resolve()),
                          policy=str(args.policy.resolve()), codex=codex)
            config.pop("coordinatorThreadId", None)
            config.pop("automation", None)
            command = MARKER + "exec " + shlex.join([
                sys.executable, str(Path(__file__).resolve()), "signal",
                "--config", str(config_path),
            ])
            for event in EVENTS:
                document.setdefault("hooks", {}).setdefault(event, []).append({"hooks": [{
                    "type": "command", "command": command, "async": True, "timeout": 30,
                }]})
        else:
            config["enabled"] = False
        write_json(config_path, config)
        write_json(hooks_path, document)
    print("Organizer hooks installed. New or changed definitions require /hooks review."
          if args.action == "install" else "Organizer hooks disabled; other hooks preserved.")


def deliver(config, prompt):
    target = config["dispatcherThreadId"]
    if target == config["discussionThreadId"]:
        raise ValueError("Refusing to queue organization into the discussion")
    try:
        result = subprocess.run([config["codex"], "queue", "--thread", target,
                                 "--message", prompt], capture_output=True, text=True, timeout=20)
        return result.returncode
    except (OSError, subprocess.TimeoutExpired):
        return None


def notify(config_path, config, state):
    if state["notified"]:
        return
    # A timeout can still have delivered. Persist first and let the next
    # scheduled launcher recover uncertain delivery without duplicate retries.
    state["notified"] = True
    save_state(config_path, state)
    prompt = ("Launch one fresh organizer run by following "
              + str(Path(config["policy"]).with_name("dispatcher.md"))
              + ". Do not organize in this launcher or send anything into the discussion.")
    code = deliver(config, prompt)
    state["lastDelivery"] = {"returnCode": code, "targetThreadId": config["dispatcherThreadId"], "at": time.time()}
    if code != 0:
        print("Organizer launch delivery failed or is uncertain; the scheduled launcher will recover pending work.",
              file=sys.stderr)


def register(state, run_id, token):
    directory = RUN_PREFIX + token
    if directory not in state["directories"]:
        raise ValueError("Unknown organizer launch reservation")
    existing = state["directories"][directory]
    if existing not in (None, run_id):
        raise ValueError("Launch reservation already belongs to another run")
    record = state["runs"].get(run_id)
    if record and record["token"] != token:
        raise ValueError("Run belongs to another reservation")
    state["directories"][directory] = run_id
    if state["launch"] and state["launch"]["token"] == token:
        state["launch"]["threadId"] = run_id
    return state["runs"].setdefault(run_id, {
        "token": token, "status": "starting", "createdAt": time.time(),
    })


def signal(args):
    event = json.load(sys.stdin)
    if not isinstance(event, dict):
        raise ValueError("Expected a lifecycle event object")
    session = str(uuid.UUID(event["session_id"]))
    name = event.get("hook_event_name")
    with locked(args.config):
        config = read_json(args.config)
        if not config.get("enabled"):
            return
        state = load_state(args.config)
        if session in config["excludedThreadIds"]:
            return
        directory = Path(event.get("cwd", "")).name
        if directory in state["directories"]:
            register(state, session, directory[len(RUN_PREFIX):])
            save_state(args.config, state)
            return
        if session in state["runs"] or name not in EVENTS:
            return
        if name == "SessionStart" and event.get("source") not in ("startup", "resume", "fork", "clear"):
            return
        turn = str(event.get("turn_id", ""))
        if len(turn) > 100:
            raise ValueError("Invalid turn id")
        key = ":".join((session, turn, name, str(event.get("source", ""))))
        if key in state["seen"]:
            return
        state["seen"] = (state["seen"] + [key])[-2048:]
        state["pending"][session + ":" + name] = {
            "hostId": config["hostId"], "threadId": session,
            "turnId": turn, "event": name, "receivedAt": time.time(),
        }
        save_state(args.config, state)
        if not state["activeRun"] and not state["launch"]:
            notify(args.config, config, state)
        save_state(args.config, state)


def coordinate(args):
    if args.action == "status":
        state = load_state(args.config)
        print(json.dumps({"activeRun": state["activeRun"], "launch": state["launch"],
                          "pendingCount": len(state["pending"]), "runCount": len(state["runs"]),
                          "lastDelivery": state.get("lastDelivery"), "lastFailure": state.get("lastFailure")}))
        return
    with locked(args.config):
        config = read_json(args.config)
        state = load_state(args.config)
        run_id = str(uuid.UUID(args.run_id)) if args.run_id else None
        if run_id in config["excludedThreadIds"]:
            raise ValueError("Protected chat cannot become an organizer run")
        result = {}
        if args.action == "prepare":
            if state["activeRun"]:
                state["sweepPending"] = True
                result = {"launch": False, "activeRun": state["activeRun"]}
            elif state["launch"]:
                result = {"launch": False, "reservation": state["launch"]}
            else:
                token = str(uuid.uuid4())
                directory = RUN_PREFIX + token
                state["directories"][directory] = None
                state["launch"] = {"token": token, "createdAt": time.time()}
                state["notified"] = False
                result = {"launch": True, "token": token, "directoryName": directory,
                          "prompt": "This is a temporary organizer run authorized by Yanxi. Read and execute the full canonical policy at "
                          + config["policy"] + ". Your launch token is " + token
                          + ". Register and acquire the shared writer before reading work chats or changing the ledger/sidebar. Persist the outcome, release the writer, then archive only this run with the supported app tool. Do not send anything into the discussion."}
        elif args.action == "bind":
            register(state, run_id, args.token)
            result = {"registered": run_id}
        elif args.action == "begin":
            record = register(state, run_id, args.token)
            if state["activeRun"] not in (None, run_id):
                raise ValueError("Another organizer owns the writer")
            if record["status"] == "running":
                result = {"acquired": True, "events": record["events"]}
            else:
                if record["status"] != "starting" or not state["launch"] or state["launch"]["token"] != args.token:
                    raise ValueError("Only a fresh reserved run can acquire the writer")
                pending = list(state["pending"].values())
                state.update(activeRun=run_id, launch=None, pending={}, notified=False, sweepPending=False)
                record.update(status="running", events=pending, startedAt=time.time())
                result = {"acquired": True, "events": pending}
        elif args.action == "finish":
            if state["activeRun"] != run_id:
                raise ValueError("Only the current writer can finish")
            state["runs"][run_id].update(status=args.outcome, message=args.message, finishedAt=time.time())
            state["activeRun"] = None
            if args.outcome == "error":
                state["lastFailure"] = {"runId": run_id, "message": args.message, "acknowledged": False}
            save_state(args.config, state)
            if args.outcome == "error":
                state["lastFailure"]["deliveryReturnCode"] = deliver(config,
                    "Report the unacknowledged organizer failure using helper status and the error-report protocol in "
                    + str(Path(config["policy"]).with_name("dispatcher.md"))
                    + ". This is a status-only report: do not launch a pass for this message or send anything into the discussion.")
            if state["pending"] or state["sweepPending"]:
                notify(args.config, config, state)
            result = {"finished": run_id, "archiveRequired": True}
        elif args.action == "ack-error":
            if state.get("lastFailure", {}).get("runId") != run_id:
                raise ValueError("Failure record changed")
            state["lastFailure"]["acknowledged"] = True
            result = {"acknowledged": run_id}
        elif args.action == "cancel":
            if not state["launch"] or state["launch"]["token"] != args.token:
                raise ValueError("Launch reservation changed")
            if state["directories"][RUN_PREFIX + args.token] is not None:
                raise ValueError("A chat exists; inspect its state instead of cancelling")
            state["launchError"] = {"token": args.token, "message": args.message, "at": time.time()}
            state["launch"] = None
            state["notified"] = False
            result = {"cancelled": args.token}
        elif args.action == "recover":
            owns_launch = state["launch"] and state["launch"].get("threadId") == run_id
            if state["activeRun"] != run_id and not owns_launch:
                raise ValueError("The recorded owner changed")
            state["runs"][run_id].update(status="error", message=args.message, finishedAt=time.time())
            if owns_launch:
                state["launch"] = None
            if state["activeRun"] == run_id:
                state["activeRun"] = None
            state.update(notified=False, sweepPending=True)
            result = {"recovered": run_id}
        if args.action == "prepare" and not state.get("lastFailure", {}).get("acknowledged", True):
            result["lastFailure"] = state["lastFailure"]
        save_state(args.config, state)
    print(json.dumps(result))


def main():
    home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "uninstall", "signal", "prepare", "bind", "begin", "finish", "cancel", "recover", "ack-error", "status"))
    parser.add_argument("--config", type=Path, default=home / "chat-organizer/config.json")
    parser.add_argument("--dispatcher")
    parser.add_argument("--discussion")
    parser.add_argument("--ledger", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--exclude", action="append", default=[])
    parser.add_argument("--codex", default="codex")
    parser.add_argument("--run-id")
    parser.add_argument("--token")
    parser.add_argument("--outcome", choices=("success", "error"), default="success")
    parser.add_argument("--message", default="")
    args = parser.parse_args()
    args.config = args.config.expanduser().resolve()
    if args.action == "install" and not all((args.dispatcher, args.discussion, args.ledger, args.policy)):
        parser.error("install requires --dispatcher, --discussion, --ledger and --policy")
    if args.action in ("bind", "begin", "finish", "recover", "ack-error") and not args.run_id:
        parser.error("this action requires --run-id")
    if args.action in ("bind", "begin", "cancel") and not args.token:
        parser.error("this action requires --token")
    try:
        if args.action in ("install", "uninstall"):
            install(args)
        elif args.action == "signal":
            signal(args)
        else:
            coordinate(args)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("Organizer: " + str(error), file=sys.stderr)
        return 0 if args.action == "signal" else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
