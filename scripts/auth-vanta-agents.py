#!/usr/bin/env python3

import argparse
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

GLEAN_MCP_URL = "https://vanta-be.glean.com/mcp/default"
GLEAN_SERVER = "glean_default"

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


def selected_profile(explicit: str | None) -> str | None:
    if explicit is not None:
        return normalize_profile(explicit)
    if "OMP_PROFILE" in os.environ:
        return normalize_profile(os.environ["OMP_PROFILE"])
    return normalize_profile(os.environ.get("PI_PROFILE"))


def config_root() -> Path:
    configured = Path(os.environ.get("PI_CONFIG_DIR", ".omp")).expanduser()
    return configured if configured.is_absolute() else Path.home() / configured


def agent_dir(profile: str | None) -> Path:
    normalized = normalize_profile(profile)
    if normalized is None:
        override = os.environ.get("PI_CODING_AGENT_DIR")
        return Path(override).expanduser().resolve() if override else config_root() / "agent"
    return config_root() / "profiles" / normalized / "agent"


def agent_database(profile: str | None) -> Path:
    normalized = normalize_profile(profile)
    if normalized is None and os.environ.get("PI_CODING_AGENT_DIR"):
        return agent_dir(normalized) / "agent.db"

    xdg_data_home = os.environ.get("XDG_DATA_HOME")
    if sys.platform in {"darwin", "linux"} and xdg_data_home:
        xdg_root = Path(xdg_data_home).expanduser() / "omp"
        xdg_profile_root = xdg_root if normalized is None else xdg_root / "profiles" / normalized
        if xdg_profile_root.exists():
            return xdg_profile_root / "agent.db"
    return agent_dir(normalized) / "agent.db"


def glean_provider(profile: str | None) -> str:
    profile_name = profile or "default"
    return f"mcp_oauth:profile:{profile_name}:{GLEAN_MCP_URL}"


def glean_ready(profile: str | None) -> bool:
    database = agent_database(profile)
    if not database.exists():
        return False
    try:
        with sqlite3.connect(f"{database.resolve().as_uri()}?mode=ro", uri=True) as connection:
            row = connection.execute(
                """
                SELECT 1
                FROM auth_credentials
                WHERE provider = ?
                  AND credential_type = 'oauth'
                  AND disabled_cause IS NULL
                LIMIT 1
                """,
                (glean_provider(profile),),
            ).fetchone()
    except sqlite3.DatabaseError as error:
        raise RuntimeError(f"could not inspect OMP credential metadata: {error}") from error
    return row is not None


def slack_ready() -> bool:
    command = shutil.which("slack-vanta")
    if command is None:
        raise RuntimeError("slack-vanta is unavailable; run `just post-pull` from the Obsidian workspace")
    result = subprocess.run(
        [command, "auth", "status"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.returncode == 0 and "read-only preset: satisfied" in result.stdout


def print_status(profile: str | None, glean: bool, slack: bool) -> None:
    profile_name = profile or "default"
    print(f"Glean MCP ({profile_name} profile): {'ready' if glean else 'missing'}")
    print(f"Vanta Slack CLI: {'ready' if slack else 'missing'}")


def require_private_terminal() -> None:
    if not all(stream.isatty() for stream in (sys.stdin, sys.stdout, sys.stderr)):
        raise RuntimeError(
            "run auth-vanta-agents yourself in a private interactive terminal; OAuth URLs must not enter an agent transcript"
        )


def ensure_glean_config(profile: str | None) -> None:
    setup = Path(__file__).resolve().parent / "ensure_omp_mcp.py"
    command = [sys.executable, str(setup)]
    if profile:
        command.extend(["--profile", profile])
    result = subprocess.run(command, check=False)
    if result.returncode != 0:
        raise RuntimeError("could not provision the OMP Glean MCP definition")


def authenticate_glean(profile: str | None) -> None:
    ensure_glean_config(profile)
    omp = shutil.which("omp")
    if omp is None:
        raise RuntimeError("omp is unavailable; run the Dotfiles installer first")

    print("\nOMP will open for Glean authentication.")
    print(f"Run `/mcp reauth {GLEAN_SERVER}`, complete SSO, then run `/quit`.")
    command = [omp, "--profile", profile or "default", "--no-session"]
    if subprocess.run(command, check=False).returncode != 0:
        raise RuntimeError("OMP exited before Glean authentication completed")
    if not glean_ready(profile):
        raise RuntimeError("Glean MCP is still missing; rerun auth-vanta-agents and complete `/mcp reauth glean_default`")


def authenticate_slack() -> None:
    slack = shutil.which("slack-vanta")
    if slack is None:
        raise RuntimeError("slack-vanta is unavailable; run `just post-pull` from the Obsidian workspace")
    if subprocess.run([slack, "auth", "login"], check=False).returncode != 0:
        raise RuntimeError("Slack authentication did not complete")
    if not slack_ready():
        raise RuntimeError("Slack authentication completed without the read-only preset")


def main() -> int:
    parser = argparse.ArgumentParser(description="Check or repair work-agent authentication without exposing credentials.")
    parser.add_argument("--status", action="store_true", help="report status without launching OAuth")
    parser.add_argument("--profile", help="OMP profile to inspect and authenticate")
    arguments = parser.parse_args()

    if os.environ.get("WORK_MACHINE") != "1":
        print("auth-vanta-agents is only available when WORK_MACHINE=1", file=sys.stderr)
        return 1

    try:
        profile = selected_profile(arguments.profile)
        glean = glean_ready(profile)
        slack = slack_ready()
        print_status(profile, glean, slack)
        if arguments.status:
            return 0 if glean and slack else 1
        if glean and slack:
            return 0

        require_private_terminal()
        if not glean:
            authenticate_glean(profile)
        if not slack:
            authenticate_slack()
        print("\nWork-agent authentication is ready.")
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(f"auth-vanta-agents: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
