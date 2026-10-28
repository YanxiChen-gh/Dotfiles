#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
export ROOT
python3 - <<'PY'
import os
from pathlib import Path
import subprocess
import tempfile

source = Path(os.environ['ROOT']) / 'install.d/30-system.sh'
with tempfile.TemporaryDirectory(prefix='ona-shell-') as directory:
    fixture = Path(directory)
    home = fixture / 'home'
    home.mkdir()
    binaries = fixture / 'bin'
    binaries.mkdir()
    account = fixture / 'account-shell'
    calls = fixture / 'sudo-calls'
    zsh = binaries / 'zsh'
    scripts = {
        'zsh': '#!/bin/sh\nexit 97\n',
        'getent': '#!/bin/sh\nprintf "test:x:1000:1000::/home/test:%s\\n" "$(cat "$ACCOUNT")"\n',
        'sudo': '''#!/bin/sh
[ "${DENY_SUDO:-}" != 1 ] || exit 1
[ "$1" = -n ] && [ "$2" = chsh ] && [ "$4" = --shell ] || exit 2
printf '%s\n' "$*" >> "$CALLS"
printf '%s\n' "$5" > "$ACCOUNT"
''',
    }
    for name, content in scripts.items():
        path = binaries / name
        path.write_text(content)
        path.chmod(0o755)
    env = dict(os.environ, HOME=str(home), PATH=f'{binaries}:/usr/bin:/bin',
               IS_ON_ONA='true', SHELL=str(zsh), ACCOUNT=str(account), CALLS=str(calls))
    command = ['sh', '-c', '. "$1"; OS=linux; setup_ona_default_shell', 'sh', str(source)]

    def install(**overrides):
        return subprocess.run(command, env=dict(env, **overrides), capture_output=True, text=True)

    account.write_text('/bin/bash\n')
    bashrc = home / '.bashrc'
    assert install().returncode == 0
    assert not bashrc.exists(), 'fresh environments must not acquire a shell replacement hook'
    assert account.read_text().strip() == str(zsh)
    calls.unlink()
    account.write_text('/bin/bash\n')
    bashrc.write_text('''export BEFORE=before
# >>> dotfiles: default to zsh on Ona >>>
exec zsh -l
# <<< dotfiles: default to zsh on Ona <<<
export AFTER=after
''')
    assert install().returncode == 0
    assert account.read_text().strip() == str(zsh), 'account shell must change even when SHELL already says zsh'
    expected = 'export BEFORE=before\nexport AFTER=after\n'
    assert bashrc.read_text() == expected, 'migration must preserve surrounding user configuration'
    probe = subprocess.run(['bash', '--noprofile', '--rcfile', str(bashrc), '-ic',
                            'printf "%s:%s:ready" "$BEFORE" "$AFTER"'],
                           env=env, capture_output=True, text=True, timeout=5)
    assert probe.returncode == 0 and probe.stdout == 'before:after:ready', 'interactive command must finish'

    assert install().returncode == 0
    assert len(calls.read_text().splitlines()) == 1, 'an already configured account must not be changed again'
    assert bashrc.read_text() == expected

    account.write_text('/bin/bash\n')
    assert install(DENY_SUDO='1').returncode != 0, 'permission failures must be reported'
    assert account.read_text() == '/bin/bash\n'

    assert install(IS_ON_ONA='').returncode == 0
    assert len(calls.read_text().splitlines()) == 1, 'other machines must keep their login shell'

    malformed = 'export BEFORE=before\n# >>> dotfiles: default to zsh on Ona >>>\nuser content\n'
    bashrc.write_text(malformed)
    assert install().returncode != 0
    assert bashrc.read_text() == malformed, 'an incomplete managed block must not truncate user configuration'

print('Ona login shell and SSH startup tests passed.')
PY
