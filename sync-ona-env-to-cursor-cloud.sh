#!/bin/sh
set -eu

REPOSITORY_URL="${REPOSITORY_URL:-https://github.com/VantaInc/obsidian.git}"
BRANCH="${BRANCH:-main}"
OUTPUT_FILE="${OUTPUT_FILE:-$HOME/.ona_env}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
REQUIRED_VARS="${REQUIRED_VARS:-GH_TOKEN NPM_TASKFORCESH_TOKEN NPM_LEVEL_CI_TOKEN CLOUDSMITH_NPM_TOKEN LANGSMITH_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY}"

usage() {
    cat <<'EOF'
Usage: sync-ona-env-to-cursor-cloud.sh [options]

Sync Cursor Cloud environment variables from the latest running Ona environment
without printing secret values.

Options:
  --env-id ID          Use a specific Ona environment instead of auto-selecting.
  --repository URL     Repository URL to match when auto-selecting.
  --branch NAME        Branch name to match when auto-selecting.
  --output FILE        Env file to write. Defaults to ~/.ona_env.
  --timeout SECONDS    Ona exec timeout. Defaults to 120.
  --help               Show this help.

Environment:
  REQUIRED_VARS        Space-separated vars to validate after writing.
EOF
}

ENV_ID=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --env-id)
            ENV_ID="${2:-}"
            shift 2
            ;;
        --repository)
            REPOSITORY_URL="${2:-}"
            shift 2
            ;;
        --branch)
            BRANCH="${2:-}"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="${2:-}"
            shift 2
            ;;
        --timeout)
            TIMEOUT_SECONDS="${2:-}"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Missing required command: %s\n' "$1" >&2
        exit 1
    fi
}

require_command ona
require_command python3
require_command mktemp

TMPDIR="${TMPDIR:-/tmp}"
WORKDIR=$(mktemp -d "$TMPDIR/ona-env-sync.XXXXXX")
cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT INT TERM
chmod 700 "$WORKDIR"

if [ -n "${GITPOD_PAT:-}" ]; then
    # Ona login is idempotent; keep output quiet to avoid token-adjacent logs.
    ona login --token "$GITPOD_PAT" >/dev/null 2>&1 || true
fi

if [ -z "$ENV_ID" ]; then
    ENV_LIST="$WORKDIR/environments.json"
    ona environment list --running-only -o json >"$ENV_LIST"
    ENV_ID=$(python3 - "$ENV_LIST" "$REPOSITORY_URL" "$BRANCH" <<'PY'
import json
import sys

path, repository_url, branch = sys.argv[1:4]
with open(path, encoding="utf-8") as f:
    environments = json.load(f)

matches = []
for environment in environments:
    status = environment.get("status") or {}
    content = status.get("content") or {}
    git = content.get("git") or {}
    if git.get("cloneUrl") != repository_url or git.get("branch") != branch:
        continue

    metadata = environment.get("metadata") or {}
    started_at = metadata.get("lastStartedAt") or metadata.get("createdAt") or ""
    matches.append((started_at, environment.get("id")))

if not matches:
    raise SystemExit(
        f"No running Ona environment found for {repository_url} branch {branch}"
    )

matches.sort(reverse=True)
print(matches[0][1])
PY
)
fi

REMOTE_ENV="$WORKDIR/remote.env"
ona environment exec "$ENV_ID" --timeout "$TIMEOUT_SECONDS" -- bash -lc env >"$REMOTE_ENV"
chmod 600 "$REMOTE_ENV"

OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_DIR"

python3 - "$REMOTE_ENV" "$OUTPUT_FILE" "$ENV_ID" <<'PY'
import os
import shlex
import sys
from pathlib import Path

remote_env_path, output_path, env_id = sys.argv[1:4]
output = Path(output_path).expanduser()

denylist_exact = {
    "HOME",
    "OLDPWD",
    "PATH",
    "PWD",
    "SHELL",
    "SHLVL",
    "TERM",
    "USER",
    "USERNAME",
    "LOGNAME",
    "_",
}
denylist_prefixes = ("SSH_",)

secret_markers = (
    "TOKEN",
    "API_KEY",
    "APP_KEY",
    "SECRET",
    "PASSWORD",
    "CREDENTIAL",
)
tooling_prefixes = (
    "ANTHROPIC_",
    "CLOUDSMITH_",
    "CURSOR_",
    "DATADOG_",
    "DD_",
    "GH_",
    "GITHUB_",
    "JIRA_",
    "KERNEL_",
    "LANGSMITH_",
    "NETLIFY_",
    "NPM_",
    "OPENAI_",
    "OSO_",
    "TURBO_",
)


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(errors="replace").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key:
            values[key] = value
    return values


def parse_existing_keys(path: Path) -> set[str]:
    if not path.exists():
        return set()
    keys: set[str] = set()
    for line in path.read_text(errors="replace").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        candidate = stripped
        if candidate.startswith("export "):
            candidate = candidate[len("export ") :].strip()
        if "=" in candidate:
            key = candidate.split("=", 1)[0].strip()
            if key:
                keys.add(key)
    return keys


remote = parse_env_file(Path(remote_env_path))
existing_keys = parse_existing_keys(output)


def should_sync(key: str) -> bool:
    if key in denylist_exact or any(key.startswith(prefix) for prefix in denylist_prefixes):
        return False
    if key in existing_keys:
        return True
    if any(marker in key for marker in secret_markers):
        return True
    return any(key.startswith(prefix) for prefix in tooling_prefixes)


synced = {key: value for key, value in remote.items() if value and should_sync(key)}
if "GH_TOKEN" not in synced:
    raise SystemExit("GH_TOKEN was not available in the selected Ona environment")

old_lines = output.read_text(errors="replace").splitlines() if output.exists() else []
new_lines: list[str] = []
for line in old_lines:
    stripped = line.strip()
    candidate = stripped
    if candidate.startswith("export "):
        candidate = candidate[len("export ") :].strip()
    key = candidate.split("=", 1)[0].strip() if "=" in candidate else ""
    if key in synced:
        continue
    new_lines.append(line)

if new_lines and new_lines[-1] != "":
    new_lines.append("")
new_lines.append(f"# Synced from Ona environment {env_id} for Cursor Cloud.")
for key in sorted(synced):
    new_lines.append(f"export {key}={shlex.quote(synced[key])}")

tmp_path = output.with_name(f".{output.name}.tmp")
tmp_path.write_text("\n".join(new_lines) + "\n")
os.chmod(tmp_path, 0o600)
tmp_path.replace(output)
os.chmod(output, 0o600)

print("SELECTED_ONA_ENV=" + env_id)
print("SYNCED_ENV_VAR_COUNT=" + str(len(synced)))
print("SYNCED_GH_TOKEN=SET")
PY

printf 'VALIDATION\n'
for var_name in $REQUIRED_VARS; do
    if env -i HOME="$HOME" OUTPUT_FILE="$OUTPUT_FILE" VAR_NAME="$var_name" sh -c '. "$OUTPUT_FILE"; eval "value=\${'"$var_name"':-}"; if [ -n "$value" ]; then exit 0; fi; exit 1'; then
        printf '%s=SET\n' "$var_name"
    else
        printf '%s=MISSING\n' "$var_name"
    fi
done
