# shellcheck shell=sh
# Sourced by ../install.sh: function definitions only.

session_hub_revision() {
    printf '%s\n' "${OMP_SESSION_HUB_REVISION:-e970bc9eff22ba5cb97eaa1f7fe75ebc34e3c179}"
}

session_hub_archive_sha256() {
    printf '%s\n' "${OMP_SESSION_HUB_SHA256:-744cf70de30480225b98ec4b08c1e370ba7aa7a7a48220fe9347fbbf33f4ab06}"
}

setup_session_hub() {
    [ "${OMP_EXPERIMENT:-1}" != "0" ] || return 0
    case "$OS" in
        macos) session_hub_role=gateway ;;
        linux)
            if [ "${IS_ON_ONA:-}" != "true" ] && [ "${CURSOR_CLOUD:-}" != "1" ]; then
                return 0
            fi
            session_hub_role=hub
            ;;
        *) return 0 ;;
    esac
    session_hub_revision_value=$(session_hub_revision)
    session_hub_checksum=$(session_hub_archive_sha256)
    if ! python3 - "$session_hub_revision_value" "$session_hub_checksum" <<'PY'
import re
import sys

if not re.fullmatch(r"[0-9a-f]{40}", sys.argv[1]):
    sys.exit("Session hub requires an immutable 40-character commit revision")
if not re.fullmatch(r"[0-9a-f]{64}", sys.argv[2]):
    sys.exit("Session hub requires the archive's SHA-256 checksum")
PY
    then
        return 1
    fi
    session_hub_tmp=$(mktemp -d) || return 1
    session_hub_url="https://codeload.github.com/YanxiChen-gh/omp-session-hub/tar.gz/$session_hub_revision_value"
    if ! curl -fsSL "$session_hub_url" -o "$session_hub_tmp/source.tar.gz"; then
        rm -rf "$session_hub_tmp"
        return 1
    fi
    if ! python3 - "$session_hub_tmp" "$session_hub_revision_value" "$session_hub_checksum" <<'PY'
import hashlib
from pathlib import Path, PurePosixPath
import sys
import tarfile

root = Path(sys.argv[1])
archive = root / "source.tar.gz"
if hashlib.sha256(archive.read_bytes()).hexdigest() != sys.argv[3]:
    sys.exit("Session hub archive checksum mismatch")
prefix = "omp-session-hub-" + sys.argv[2]
with tarfile.open(str(archive), "r:gz") as source:
    members = source.getmembers()
    for member in members:
        parts = PurePosixPath(member.name).parts
        if not parts or parts[0] != prefix or ".." in parts or not (member.isdir() or member.isfile()):
            sys.exit("Unsafe session hub archive entry")
    source.extractall(str(root), members=members)
PY
    then
        rm -rf "$session_hub_tmp"
        return 1
    fi
    session_hub_source="$session_hub_tmp/omp-session-hub-$session_hub_revision_value"
    if ! sh "$session_hub_source/install.sh" --source "$session_hub_source" \
        --revision "$session_hub_revision_value" \
        --prefix "${OMP_SESSION_HUB_PREFIX:-$HOME/.local/share/omp-session-hub}"; then
        rm -rf "$session_hub_tmp"
        return 1
    fi
    rm -rf "$session_hub_tmp"
    session_hub_command="$HOME/.local/bin/omp-session-hub"
    if [ ! -x "$session_hub_command" ]; then
        echo "Session hub installer did not install $session_hub_command" >&2
        return 1
    fi
    if [ "$session_hub_role" = gateway ]; then
        "$session_hub_command" service install gateway --port "${OMP_SESSION_HUB_GATEWAY_PORT:-8787}" \
            --upstream-port "${OMP_SESSION_HUB_PORT:-4317}" || return 1
        "$session_hub_command" service ensure gateway || return 1
    else
        session_hub_dotfiles=$(resolve_script_dir) || return 1
        "$session_hub_command" service install hub --adapter "$session_hub_dotfiles/herdr/session-hub-adapter.py" \
            --port "${OMP_SESSION_HUB_PORT:-4317}" || return 1
        "$session_hub_command" service ensure hub || return 1
    fi
    echo "Session hub installed and $session_hub_role service ensured"
}
