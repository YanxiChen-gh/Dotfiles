#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
export ROOT
python3 - <<'PY'
import os
from pathlib import Path
import subprocess
import tempfile

source = Path(os.environ['ROOT']) / 'install.d/90-work.sh'
with tempfile.TemporaryDirectory(prefix='ona-repositories-') as directory:
    fixture = Path(directory)
    binaries = fixture / 'bin'
    binaries.mkdir()
    remote = fixture / 'remote.git'
    subprocess.run(['git', 'init', '--bare', str(remote)], check=True, capture_output=True)
    gh = binaries / 'gh'
    gh.write_text('''#!/bin/sh
set -eu
[ "$1" = repo ] && [ "$2" = clone ] || exit 2
printf '%s\\n' "$3" >> "$CLONE_CALLS"
[ "${FAIL_CLONE:-}" != "$3" ] || exit 1
git clone "$LOCAL_REMOTE" "$4" || exit 1
git -C "$4" remote set-url origin "$3"
''')
    gh.chmod(0o755)
    calls = fixture / 'clones'
    workspaces = fixture / 'workspaces'
    env = dict(os.environ, PATH=f'{binaries}:{os.environ["PATH"]}',
               ONA_REPOSITORIES_DIR=str(workspaces), IS_ON_ONA='true',
               LOCAL_REMOTE=str(remote), CLONE_CALLS=str(calls))
    command = ['sh', '-c', '. "$1"; setup_ona_repositories', 'sh', str(source)]

    def install(**overrides):
        return subprocess.run(command, env=dict(env, **overrides), capture_output=True, text=True)

    for marker in ('', 'false'):
        assert install(IS_ON_ONA=marker, WORK_MACHINE='1').returncode == 0
        assert not workspaces.exists(), 'non-Ona hosts must not create repository directories'
        assert not calls.exists(), 'non-Ona hosts must not clone repositories'

    assert install().returncode == 0
    expected = ['https://github.com/YanxiChen-gh/Dotfiles.git',
                'https://github.com/VantaInc/langsmith_custom_apps.git']
    assert calls.read_text().splitlines() == expected
    dotfiles = workspaces / 'Dotfiles'
    apps = workspaces / 'langsmith_custom_apps'
    for checkout, origin in zip((dotfiles, apps), expected):
        actual = subprocess.check_output(['git', '-C', str(checkout), 'remote', 'get-url', 'origin'], text=True)
        assert actual.strip() == origin

    user_file = dotfiles / 'local-work'
    user_file.write_text('keep this work\n')
    assert install().returncode == 0
    assert calls.read_text().splitlines() == expected, 'reruns must not clone or pull existing checkouts'
    assert user_file.read_text() == 'keep this work\n'

    subprocess.run(['git', '-C', str(dotfiles), 'remote', 'set-url', 'origin',
                    'git@github.com:YanxiChen-gh/Dotfiles.git'], check=True)
    assert install().returncode == 0, 'existing SSH checkouts must be accepted'
    subprocess.run(['git', '-C', str(apps), 'remote', 'set-url', 'origin',
                    'https://github.com/example/other.git'], check=True)
    assert install().returncode != 0, 'unrelated checkouts must be rejected'
    assert user_file.read_text() == 'keep this work\n'

    occupied = fixture / 'occupied'
    occupied.mkdir()
    collision = occupied / 'Dotfiles'
    collision.write_text('user data\n')
    assert install(ONA_REPOSITORIES_DIR=str(occupied)).returncode != 0
    assert collision.read_text() == 'user data\n', 'destination collisions must preserve user data'

    failed = fixture / 'failed'
    assert install(ONA_REPOSITORIES_DIR=str(failed), FAIL_CLONE=expected[1]).returncode != 0
    assert (failed / 'Dotfiles' / '.git').is_dir()
    assert install(ONA_REPOSITORIES_DIR=str(failed)).returncode == 0
    assert (failed / 'langsmith_custom_apps' / '.git').is_dir(), 'a failed clone must be retryable'

print('Ona repository setup tests passed.')
PY
