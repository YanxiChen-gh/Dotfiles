#!/usr/bin/env python3
"""Call Workline through this host's authenticated Vercel CLI."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from time import monotonic
from urllib.error import HTTPError
from urllib.request import HTTPRedirectHandler, Request, build_opener
from uuid import uuid4


ORIGIN = "https://workline-bice.vercel.app"
QUEUE_COMMANDS = ("queue", "queue-reviews", "review-notes", "complete", "abandon", "reopen")
REQUEST_ID = str(uuid4())
REQUEST_ID_HEADER = "x-workline-request-id"


@contextmanager
def trace(event, path, key, **fields):
    route = re.sub(r"^/api/work/(?!(?:stack|refresh)$)[a-zA-Z0-9-]+", "/api/work/:id", path.partition("?")[0])
    route = re.sub(r"(/runs)/[a-f0-9-]+$", r"\1/:id", route)
    started = monotonic()
    outcome = "ok"
    try:
        yield fields
    except HTTPError as error:
        fields["status"] = error.code
        outcome = "http-error"
        raise
    except (TimeoutError, subprocess.TimeoutExpired):
        outcome = "timeout"
        raise
    except Exception:
        outcome = "error"
        raise
    finally:
        record = {
            "event": f"workline.client.{event}",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "requestId": REQUEST_ID,
            "method": "POST" if key else "GET",
            "route": route,
            "outcome": outcome,
            "durationMs": round((monotonic() - started) * 1000),
            **fields,
        }
        try:
            print(json.dumps(record), file=sys.stderr, flush=True)
        except OSError:
            pass


def private_text(path):
    source = Path(path).expanduser()
    if source.stat().st_mode & 0o077:
        raise ValueError("Credential and config files must have mode 600")
    return source.read_text().strip()


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


def ona_token():
    cli = shutil.which("gitpod") or shutil.which("ona")
    if cli is None:
        return None
    for timeout in (15, 25):
        try:
            result = subprocess.run(
                [cli, "--context", "environment", "idp", "token", "--audience", ORIGIN],
                capture_output=True, text=True, timeout=timeout, check=False,
            )
        except subprocess.TimeoutExpired:
            continue
        except OSError:
            return None
        token = result.stdout.strip()
        if result.returncode == 0 and re.fullmatch(r"[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+){2}", token):
            return token
        if "deadline exceeded" not in result.stderr.lower():
            return None
    return None


def ona_request(token, path, key=None, payload=None):
    headers = {
        "Authorization": f"Bearer ona_{token}",
        "x-vercel-trusted-oidc-idp-token": token,
        "Content-Type": "application/json",
        REQUEST_ID_HEADER: REQUEST_ID,
    }
    if key:
        headers["Idempotency-Key"] = key
    body = json.dumps(payload).encode() if key else None
    request = Request(ORIGIN + path, data=body, headers=headers)
    with trace("request", path, key, transport="ona-direct") as fields:
        with build_opener(NoRedirect()).open(request, timeout=60) as response:
            fields["status"] = response.status
            return json.load(response)


def ona_via_vercel(token, path, key=None, payload=None):
    return configured_request(path, key, payload, ona=token)


def request(path, key):
    payload = json.load(sys.stdin) if key else None
    action = payload.get("action") if key and path.endswith("/commands") else None
    if key and path.endswith("/commands") and action not in ("progress", "associate", "session", *QUEUE_COMMANDS):
        raise ValueError("Use the owner browser for author-intent commands")

    if action == "queue-reviews":
        for pr in payload.get("data", {}).get("pull_requests", []):
            if pr.get("reviewers") and pr.get("merge_when_ready") is False and not pr.get("review_only_reason"):
                raise ValueError("Named reviewers keep the normal merge preference. For explicit review only, "
                                 "quote the owner's request in review_only_reason.")

    token = ona_token() if "WORKLINE_CONFIG" not in os.environ else None
    if token:
        transport = ona_request
        try:
            identity = ona_request(token, "/api/me")
        except HTTPError as error:
            if error.code not in (302, 401, 403):
                raise ValueError(f"Workline HTTP {error.code}") from None
            transport = ona_via_vercel
            try:
                identity = transport(token, "/api/me")
            except (OSError, ValueError):
                identity = None
        if identity is not None:
            if path == "/api/me" and not key:
                return identity
            if path == "/api/work/stack" and identity.get("can_queue_stack") is not True:
                raise ValueError("This Ona session cannot queue an Obsidian stack")
            try:
                return transport(token, path, key, payload)
            except HTTPError as error:
                raise ValueError(f"Workline HTTP {error.code}") from None
    if path == "/api/work/stack":
        raise ValueError("Queue an Obsidian stack from a trusted Ona session")
    return configured_request(path, key, payload, action)


def configured_request(path, key, payload, action=None, ona=None):
    config_path = Path(
        os.environ.get("WORKLINE_CONFIG", "~/.config/workline/config.json")
    ).expanduser()
    config = {} if ona and not config_path.is_file() else json.loads(private_text(config_path))
    if ona:
        token = f"ona_{ona}"
    else:
        token = private_text(config["credential_file"])
        if re.fullmatch(r"wk_[A-Za-z0-9_-]+", token) is None:
            raise ValueError("Configure an owner-issued Workline credential")
    command = config.get("vercel_command", ["vercel"])
    if not isinstance(command, list) or not command or not all(
        isinstance(part, str) and part for part in command
    ):
        raise ValueError("vercel_command must be a nonempty argv array")
    environment = dict(
        os.environ, VERCEL_TELEMETRY_DISABLED="1",
        VERCEL_PROJECT_ID="prj_DEbVHeehJbWoZNOMfdzTiy4RKJx7",
        VERCEL_ORG_ID="team_KRqbmQkHbHxnlqEnmBn8oWxr",
    )
    if config.get("vercel_token_file"):
        environment["VERCEL_TOKEN"] = private_text(config["vercel_token_file"])
    with tempfile.TemporaryDirectory(prefix="workline-") as directory:
        root = Path(directory)
        headers = root / "headers"
        headers.write_text(
            f"Authorization: Bearer {token}\nContent-Type: application/json\n"
            f"{REQUEST_ID_HEADER}: {REQUEST_ID}\n"
            + (f"Idempotency-Key: {key}\n" if key else "")
        )
        headers.chmod(0o600)
        output = root / "response"
        argv = command + [
            "curl", path, "--deployment", ORIGIN, "--scope", "vantacom", "--",
            "--silent", "--header", f"@{headers}", "--output", str(output),
            "--write-out", "%{http_code}",
        ]
        if key:
            if action in QUEUE_COMMANDS and configured_request("/api/me", None, None).get("scope") not in ("queue", "controller"):
                raise ValueError("Configure a coding-session credential or use the item's controller credential")
            body = root / "body"
            body.write_text(json.dumps(payload))
            body.chmod(0o600)
            argv += ["--request", "POST", "--data-binary", f"@{body}"]
        with trace("request", path, key, transport="ona-vercel" if ona else "vercel") as fields:
            result = subprocess.run(
                argv, cwd=config_path.parent if config_path.parent.is_dir() else root,
                env=environment, capture_output=True,
                text=True, timeout=60, check=False,
            )
            fields["exitCode"] = result.returncode
            if result.returncode:
                raise ValueError("Vercel request failed; check this host's Vercel access")
            match = re.search(r"(\d{3})\s*$", result.stdout)
            if match is None:
                raise ValueError("Vercel did not return an HTTP status")
            status = int(match[1])
            fields["status"] = status
            if not 200 <= status < 300:
                raise ValueError(f"Workline HTTP {status}; refresh context or renew access")
            return json.loads(output.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path")
    parser.add_argument("--key", help="Stable idempotency key; POST JSON from stdin")
    args = parser.parse_args()
    pattern = (
        r"/api/work(?:/stack|/refresh|/[a-zA-Z0-9-]+/(?:commands|runs))?"
        if args.key is not None else (
            r"/api/(?:me|sessions|work(?:/[a-zA-Z0-9-]+(?:/timeline\?pr="
            r"[a-zA-Z0-9-]+/[a-zA-Z0-9_.-]+%23[1-9][0-9]*|/runs/[a-f0-9-]{36})?)?)"
        )
    )
    if re.fullmatch(pattern, args.path) is None:
        parser.error("Use a supported Workline API path")
    if args.key is not None and re.fullmatch(r"[a-zA-Z0-9:_-]{8,100}", args.key) is None:
        parser.error("Use an 8-100 character operation key (letters, digits, : _ -)")
    try:
        with trace("invocation", args.path, args.key):
            print(json.dumps(request(args.path, args.key), indent=2))
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        # Paths, CLI output, and server error bodies can contain private material.
        if type(error) is ValueError and not isinstance(error, json.JSONDecodeError):
            print(str(error), file=sys.stderr)
        else:
            print("Workline configuration or response is unavailable", file=sys.stderr)
        return 1
    except subprocess.TimeoutExpired:
        print("Workline request timed out; reuse the same write key and payload", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
