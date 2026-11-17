#!/usr/bin/env python3
"""Call Workline through this host's authenticated Vercel CLI."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ORIGIN = "https://workline-bice.vercel.app"


def private_text(path):
    source = Path(path).expanduser()
    if source.stat().st_mode & 0o077:
        raise ValueError("Credential and config files must have mode 600")
    return source.read_text().strip()


def request(path, key):
    config_path = Path(
        os.environ.get("WORKLINE_CONFIG", "~/.config/workline/config.json")
    ).expanduser()
    config = json.loads(private_text(config_path))
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
            payload = json.load(sys.stdin)
            if path.endswith("/commands"):
                action = payload.get("action")
                if action == "queue":
                    if request("/api/me", None).get("scope") != "controller":
                        raise ValueError("Queue in the owner browser or use the item's controller credential")
                elif action not in ("progress", "associate", "session"):
                    raise ValueError("Use the owner browser for author-intent commands")
            body = root / "body"
            body.write_text(json.dumps(payload))
            body.chmod(0o600)
            argv += ["--request", "POST", "--data-binary", f"@{body}"]
        result = subprocess.run(
            argv, cwd=config_path.parent, env=environment, capture_output=True,
            text=True, timeout=60, check=False,
        )
        if result.returncode:
            raise ValueError("Vercel request failed; check this host's Vercel access")
        match = re.search(r"(\d{3})\s*$", result.stdout)
        if match is None:
            raise ValueError("Vercel did not return an HTTP status")
        status = int(match[1])
        if not 200 <= status < 300:
            raise ValueError(f"Workline HTTP {status}; refresh context or renew access")
        return json.loads(output.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path")
    parser.add_argument("--key", help="Stable idempotency key; POST JSON from stdin")
    args = parser.parse_args()
    pattern = (
        r"/api/work(?:/[a-zA-Z0-9-]+/commands)?"
        if args.key is not None else r"/api/(?:me|work(?:/[a-zA-Z0-9-]+)?|sessions)"
    )
    if re.fullmatch(pattern, args.path) is None:
        parser.error("Use a supported Workline API path")
    if args.key is not None and re.fullmatch(r"[a-zA-Z0-9:_-]{8,100}", args.key) is None:
        parser.error("Use an 8-100 character operation key (letters, digits, : _ -)")
    try:
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
