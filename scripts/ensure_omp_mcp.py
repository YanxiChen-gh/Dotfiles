#!/usr/bin/env python3

import argparse
import json
import os
import re
from pathlib import Path
import tempfile

SCHEMA_URL = "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json"
MANAGED_SERVER = "glean_default"


PROFILE_NAME = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
WINDOWS_RESERVED_BASENAME = re.compile(r"^(?:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\..*)?$", re.IGNORECASE)


def normalize_profile(profile: str | None) -> str | None:
    normalized = profile.strip() if profile is not None else None
    if not normalized or normalized == "default":
        return None
    if (
        normalized in {".", ".."}
        or normalized.endswith(".")
        or PROFILE_NAME.fullmatch(normalized) is None
        or WINDOWS_RESERVED_BASENAME.fullmatch(normalized) is not None
    ):
        raise ValueError(f'invalid OMP profile "{profile}"')
    return normalized


def config_root() -> Path:
    configured = Path(os.environ.get("PI_CONFIG_DIR", ".omp")).expanduser()
    return configured if configured.is_absolute() else Path.home() / configured


def resolve_agent_dir(profile: str | None) -> Path:
    normalized = normalize_profile(profile)
    if normalized is None:
        override = os.environ.get("PI_CODING_AGENT_DIR")
        return Path(override).expanduser().resolve() if override else config_root() / "agent"
    return config_root() / "profiles" / normalized / "agent"


def load_object(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON in {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object in {path}")
    return value


def load_existing(path: Path, legacy_managed_path: Path) -> tuple[dict[str, object], bool]:
    if path.is_symlink():
        raw_target = Path(os.readlink(path))
        target = raw_target if raw_target.is_absolute() else path.parent / raw_target
        if target.resolve(strict=False) != legacy_managed_path.resolve(strict=False):
            raise ValueError(f"refusing to replace unmanaged symlink: {path}")
        existing = load_object(target) if target.is_file() else {}
        return existing, True

    if not path.exists():
        return {}, False
    if not path.is_file():
        raise ValueError(f"expected a regular file: {path}")
    return load_object(path), False


def managed_definition(fragment: dict[str, object]) -> dict[str, object]:
    fragment_servers = fragment.get("mcpServers")
    if not isinstance(fragment_servers, dict):
        raise ValueError(f"fragment must define mcpServers.{MANAGED_SERVER}")
    definition = fragment_servers.get(MANAGED_SERVER)
    if not isinstance(definition, dict):
        raise ValueError(f"fragment must define mcpServers.{MANAGED_SERVER}")
    return definition


def merge_config(existing: dict[str, object], fragment: dict[str, object]) -> dict[str, object]:
    existing_servers = existing.get("mcpServers", {})
    if not isinstance(existing_servers, dict):
        raise ValueError("existing mcpServers must be a JSON object")

    merged = dict(existing)
    if "$schema" not in merged:
        merged = {"$schema": SCHEMA_URL, **merged}
    merged["mcpServers"] = {
        **existing_servers,
        MANAGED_SERVER: managed_definition(fragment),
    }
    return merged


def remove_config(existing: dict[str, object], fragment: dict[str, object]) -> tuple[dict[str, object], bool]:
    existing_servers = existing.get("mcpServers", {})
    if not isinstance(existing_servers, dict):
        raise ValueError("existing mcpServers must be a JSON object")
    if existing_servers.get(MANAGED_SERVER) != managed_definition(fragment):
        return existing, False

    remaining_servers = dict(existing_servers)
    del remaining_servers[MANAGED_SERVER]
    cleaned = dict(existing)
    cleaned["mcpServers"] = remaining_servers
    return cleaned, True

def write_atomic(path: Path, value: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        delete=False,
    ) as temporary:
        json.dump(value, temporary, indent=2)
        temporary.write("\n")
        temporary_path = Path(temporary.name)
    os.chmod(temporary_path, 0o600)
    os.replace(temporary_path, path)

def removal_targets() -> list[Path]:
    targets = [resolve_agent_dir(None) / "mcp.json"]
    profiles_root = config_root() / "profiles"
    if not profiles_root.is_dir():
        return targets

    for profile_root in sorted(profiles_root.iterdir()):
        try:
            profile = normalize_profile(profile_root.name)
        except ValueError:
            continue
        target = profile_root / "agent" / "mcp.json"
        if profile is not None and profile_root.is_dir() and (target.exists() or target.is_symlink()):
            targets.append(target)
    return targets


def update_target(
    target: Path,
    fragment: dict[str, object],
    legacy_managed_path: Path,
    remove: bool,
) -> str:
    existing, legacy_symlink = load_existing(target, legacy_managed_path)
    if remove:
        updated, changed = remove_config(existing, fragment)
    else:
        updated = merge_config(existing, fragment)
        changed = updated != existing

    if not changed and not legacy_symlink:
        if target.is_file():
            os.chmod(target, 0o600)
        return "not configured" if remove else "already configured"

    write_atomic(target, updated)
    if remove:
        return "removed" if changed else "migrated"
    return "configured"


def main() -> int:
    dotfiles = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description="Merge Dotfiles-managed OMP MCP definitions without replacing unrelated entries.")
    parser.add_argument("--profile")
    parser.add_argument("--fragment", type=Path, default=dotfiles / "omp" / "mcp-servers-work.json")
    parser.add_argument("--omp-mcp", type=Path)
    parser.add_argument("--legacy-managed-path", type=Path, default=dotfiles / "omp" / "agent" / "mcp.json")
    removal = parser.add_mutually_exclusive_group()
    removal.add_argument("--remove", action="store_true", help=f"remove the exact managed {MANAGED_SERVER} definition")
    removal.add_argument(
        "--remove-all-profiles",
        action="store_true",
        help=f"remove the exact managed {MANAGED_SERVER} definition from default and existing named profiles",
    )
    arguments = parser.parse_args()

    try:
        fragment = load_object(arguments.fragment.expanduser())
        legacy_managed_path = arguments.legacy_managed_path.expanduser()
        if arguments.remove_all_profiles:
            if arguments.profile is not None or arguments.omp_mcp is not None:
                raise ValueError("--remove-all-profiles cannot be combined with --profile or --omp-mcp")
            targets = removal_targets()
        else:
            target = arguments.omp_mcp.expanduser() if arguments.omp_mcp else resolve_agent_dir(arguments.profile) / "mcp.json"
            targets = [target]
    except (OSError, ValueError) as error:
        print(f"OMP MCP setup failed: {error}", file=os.sys.stderr)
        return 1

    failed = False
    remove = arguments.remove or arguments.remove_all_profiles
    for target in targets:
        try:
            action = update_target(target, fragment, legacy_managed_path, remove)
            print(f"OMP MCP: {MANAGED_SERVER} {action} in {target}")
        except (OSError, ValueError) as error:
            failed = True
            print(f"OMP MCP setup failed for {target}: {error}", file=os.sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
