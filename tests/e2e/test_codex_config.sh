#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
export ROOT
codex_python=python3
if ! "$codex_python" -c 'import tomllib' >/dev/null 2>&1; then
    codex_python=/opt/homebrew/bin/python3
fi
"$codex_python" - <<'PY'
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib

root = Path(os.environ["ROOT"])
command = ["sh", "-eu", "-c", '''
resolve_script_dir() { printf '%s\\n' "$ROOT"; }
. "$ROOT/install.d/10-helpers.sh"
. "$ROOT/install.d/60-codex.sh"
WORK_MACHINE=0
setup_codex_config
''']
expected = {
    "model": "gpt-6.1-sol",
    "model_reasoning_effort": "high",
    "approval_policy": "on-request",
    "approvals_reviewer": "auto_review",
    "sandbox_mode": "workspace-write",
}
with tempfile.TemporaryDirectory(prefix="codex-defaults-") as directory:
    home = Path(directory)
    env = dict(os.environ, HOME=str(home))
    env.pop("CODEX_HOME", None)

    def install():
        return subprocess.run(command, env=env, capture_output=True, text=True)

    result = install()
    assert result.returncode == 0, result.stderr
    config = home / ".codex/config.toml"
    assert tomllib.loads(config.read_text()) == expected
    assert config.stat().st_mode & 0o777 == 0o600
    before = config.stat().st_mtime_ns
    assert install().returncode == 0
    assert config.stat().st_mtime_ns == before, "unchanged defaults must not rewrite the config"

    original = '''# Host settings
"model" = "old"
'model_reasoning_effort' = "medium"
approval_policy = "never"
approvals_reviewer = "user"
sandbox_mode = "danger-full-access"
instructions = """Keep these examples:
[example]
model = "example"
"""
[mcp_servers.example]
command = "custom-tool"
[profiles.custom]
model = "custom-model"
model_reasoning_effort = "low"
'''
    config.write_text(original)
    unrelated = {key: value for key, value in tomllib.loads(original).items() if key not in expected}
    assert install().returncode == 0
    assert tomllib.loads(config.read_text()) == dict(unrelated, **expected)
    assert '# Host settings\n' in config.read_text()
    assert '[mcp_servers.example]\ncommand = "custom-tool"\n' in config.read_text()

    malformed = 'model = "unterminated\n'
    config.write_text(malformed)
    assert install().returncode != 0
    assert config.read_text() == malformed

    custom_home = home / "custom-codex"
    env["CODEX_HOME"] = str(custom_home)
    assert install().returncode == 0
    assert tomllib.loads((custom_home / "config.toml").read_text()) == expected
    assert config.read_text() == malformed, "CODEX_HOME must isolate the active configuration"

print("Codex host defaults and configuration preservation passed.")
PY
