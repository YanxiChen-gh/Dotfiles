#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-e2e-orca.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
HOME="$TMP/home"
PATH="$TMP/bin:/usr/bin:/bin"
FAKE_LOG="$TMP/invocations"
export HOME PATH FAKE_LOG
mkdir -p "$TMP/bin" "$HOME/.orca/cli/bin"
OS=linux
. "$ROOT/install.d/81-orca.sh"

cat >"$TMP/orca-cli" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
    'skills list') exit 0 ;;
    --version) echo 1.4.242 ;;
    'skills install --skill orca-cli --skill orchestration --skill orca-per-workspace-env --agent claude,codex,cursor,opencode,omp')
        echo skills-install >>"$FAKE_LOG"
        exit "${FAKE_SKILL_STATUS:-0}"
        ;;
    *) exit 9 ;;
esac
EOF
chmod +x "$TMP/orca-cli"
cp "$TMP/orca-cli" "$HOME/.orca/cli/bin/orca"

# Managed remote installs must be found even outside an Orca terminal's PATH.
install_orca
[ "$(readlink "$HOME/.local/bin/orca")" = "$HOME/.orca/cli/bin/orca" ]
"$HOME/.local/bin/orca" --version
install_orca
[ "$(wc -l <"$FAKE_LOG")" -eq 2 ]
FAKE_SKILL_STATUS=17
export FAKE_SKILL_STATUS
if install_orca; then
    echo 'Expected skill installation failure' >&2
    exit 1
fi
unset FAKE_SKILL_STATUS

rm "$HOME/.local/bin/orca"
printf 'user command\n' >"$HOME/.local/bin/orca"
if install_orca; then
    echo 'Expected unmanaged command protection' >&2
    exit 1
fi
[ "$(cat "$HOME/.local/bin/orca")" = 'user command' ]
rm "$HOME/.local/bin/orca" "$HOME/.orca/cli/bin/orca"

FAKE_CLI="$TMP/orca-cli"
export FAKE_CLI
cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = -fSL ] && [ "$2" = --retry ] && [ "$3" = 3 ]
case "$4" in
    https://github.com/stablyai/orca/releases/latest/download/orca-linux.AppImage|https://github.com/stablyai/orca/releases/latest/download/orca-linux-arm64.AppImage) ;;
    *) exit 8 ;;
esac
[ "$5" = -o ]
echo download >>"$FAKE_LOG"
[ "${FAKE_DOWNLOAD_STATUS:-0}" = 0 ] || exit 22
cat >"$6" <<'APPIMAGE'
#!/bin/sh
set -eu
[ "$1" = --appimage-extract ]
mkdir -p squashfs-root/resources/bin
cp "$FAKE_CLI" squashfs-root/resources/bin/orca-ide
APPIMAGE
EOF
chmod +x "$TMP/bin/curl"

FAKE_DOWNLOAD_STATUS=22
export FAKE_DOWNLOAD_STATUS
if install_orca; then
    echo 'Expected download failure' >&2
    exit 1
fi
[ ! -e "$HOME/.local/share/orca" ]
[ ! -e "$HOME/.local/bin/orca" ]
[ -z "$(find "$HOME/.local/share" -name '.orca-install.*' -print)" ]
unset FAKE_DOWNLOAD_STATUS
install_orca
[ "$(readlink "$HOME/.local/bin/orca")" = "$HOME/.local/share/orca/squashfs-root/resources/bin/orca-ide" ]
"$HOME/.local/bin/orca" --version
install_orca
[ "$(sed -n '/^download$/p' "$FAKE_LOG" | wc -l)" -eq 2 ]

rm "$HOME/.local/bin/orca"
rm -r "$HOME/.local/share/orca/squashfs-root"
printf 'user data\n' >"$HOME/.local/share/orca/keep"
if install_orca; then
    echo 'Expected existing installation protection' >&2
    exit 1
fi
[ "$(cat "$HOME/.local/share/orca/keep")" = 'user data' ]
echo 'Orca setup checks passed.'
