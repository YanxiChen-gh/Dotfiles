#!/usr/bin/env python3

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import tempfile
import tomllib


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Configure the local Snowflake profile used by Vanta data apps."
    )
    parser.add_argument("--user", required=True)
    parser.add_argument("--connection-name", default="JYFRXUC-VANTA")
    parser.add_argument("--account", default="JYFRXUC-VANTA")
    parser.add_argument("--role", default="EPDVIEWER")
    parser.add_argument("--warehouse", default="DEV")
    parser.add_argument("--database", default="APPS")
    parser.add_argument("--schema", default="STREAMLIT_APPS")
    return parser.parse_args()


def read_toml(path: Path) -> tuple[str, dict]:
    if not path.exists():
        return "", {}

    text = path.read_text()
    try:
        return text, tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise SystemExit(f"Refusing to modify invalid TOML at {path}: {error}") from error


def write_secure(path: Path, text: str) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w") as temporary_file:
            temporary_file.write(text)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)
    os.chmod(path, 0o600)


def toml_value(value: str | bool) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return json.dumps(value)


def add_missing_profile_fields(
    text: str, connection_name: str, missing: dict[str, str | bool]
) -> str:
    lines = text.splitlines(keepends=True)
    header = re.compile(rf"^\s*\[{re.escape(connection_name)}\]\s*(?:#.*)?$")
    start = next((index for index, line in enumerate(lines) if header.match(line.rstrip("\n"))), None)
    if start is None:
        raise SystemExit(
            f"Connection {connection_name} exists but its table syntax cannot be updated safely."
        )

    end = len(lines)
    for index in range(start + 1, len(lines)):
        if lines[index].lstrip().startswith("["):
            end = index
            break

    if end > 0 and lines[end - 1] and not lines[end - 1].endswith("\n"):
        lines[end - 1] += "\n"
    addition = "".join(f"{key} = {toml_value(value)}\n" for key, value in missing.items())
    lines.insert(end, addition)
    return "".join(lines)


def ensure_connection(path: Path, connection_name: str, expected: dict[str, str | bool]) -> None:
    text, document = read_toml(path)
    existing = document.get(connection_name)

    if existing is None:
        separator = "" if not text else ("\n" if text.endswith("\n") else "\n\n")
        body = "".join(f"{key} = {toml_value(value)}\n" for key, value in expected.items())
        write_secure(path, f"{text}{separator}[{connection_name}]\n{body}")
        return

    if not isinstance(existing, dict):
        raise SystemExit(f"Connection {connection_name} is not a TOML table; refusing to replace it.")

    conflicts = sorted(
        key for key, value in expected.items() if key in existing and existing[key] != value
    )
    if conflicts:
        raise SystemExit(
            f"Connection {connection_name} conflicts on: {', '.join(conflicts)}. "
            "Resolve those fields explicitly before retrying."
        )

    missing = {key: value for key, value in expected.items() if key not in existing}
    if missing:
        text = add_missing_profile_fields(text, connection_name, missing)
        write_secure(path, text)
    else:
        os.chmod(path, 0o600)


def validate_connection(path: Path, connection_name: str, expected: dict[str, str | bool]) -> None:
    text, document = read_toml(path)
    existing = document.get(connection_name)
    if existing is None:
        return
    if not isinstance(existing, dict):
        raise SystemExit(f"Connection {connection_name} is not a TOML table; refusing to replace it.")

    conflicts = sorted(
        key for key, value in expected.items() if key in existing and existing[key] != value
    )
    if conflicts:
        raise SystemExit(
            f"Connection {connection_name} conflicts on: {', '.join(conflicts)}. "
            "Resolve those fields explicitly before retrying."
        )

    missing = {key: value for key, value in expected.items() if key not in existing}
    if missing:
        add_missing_profile_fields(text, connection_name, missing)


def ensure_default(path: Path, connection_name: str) -> None:
    text, document = read_toml(path)
    current = document.get("default_connection_name")
    if current is not None and current != connection_name:
        raise SystemExit(
            "default_connection_name already points elsewhere; refusing to replace it."
        )

    if current is None:
        suffix = "" if not text else f"\n{text}"
        text = f"default_connection_name = {toml_value(connection_name)}\n{suffix}"
        write_secure(path, text)
    else:
        os.chmod(path, 0o600)


def validate_default(path: Path, connection_name: str) -> None:
    _, document = read_toml(path)
    current = document.get("default_connection_name")
    if current is not None and current != connection_name:
        raise SystemExit(
            "default_connection_name already points elsewhere; refusing to replace it."
        )


def main() -> None:
    args = parse_args()
    if not re.fullmatch(r"[^@\s]+@vanta\.com", args.user, re.IGNORECASE):
        raise SystemExit("Snowflake user must be a @vanta.com email address.")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.connection_name):
        raise SystemExit("Connection name contains unsupported characters.")

    snowflake_dir = Path.home() / ".snowflake"
    snowflake_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(snowflake_dir, 0o700)
    expected: dict[str, str | bool] = {
        "account": args.account,
        "user": args.user,
        "authenticator": "externalbrowser",
        "client_store_temporary_credential": True,
        "role": args.role,
        "warehouse": args.warehouse,
        "database": args.database,
        "schema": args.schema,
    }
    lock_path = snowflake_dir / ".vanta-data-apps.lock"
    with lock_path.open("a") as lock_file:
        os.chmod(lock_path, 0o600)
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        connections_path = snowflake_dir / "connections.toml"
        config_path = snowflake_dir / "config.toml"
        validate_connection(connections_path, args.connection_name, expected)
        validate_default(config_path, args.connection_name)
        ensure_connection(connections_path, args.connection_name, expected)
        ensure_default(config_path, args.connection_name)

    cache_dir = Path.home() / ".cache" / "snowflake"
    cache_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(cache_dir, 0o700)
    print(f"Snowflake connection {args.connection_name} is configured without stored credentials.")


if __name__ == "__main__":
    main()
