#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-fzf-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

BIN="$TMP/bin"
LOG="$TMP/package-manager.log"
mkdir -p "$BIN"
: >"$LOG"
export BIN LOG

cat >"$BIN/brew" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$LOG"
[ "$*" = "install fzf" ] || exit 1
: >"$BIN/fzf"
chmod +x "$BIN/fzf"
EOF
chmod +x "$BIN/brew"

for util in cat chmod rm tr wc; do
    ln -s "$(command -v "$util")" "$BIN/$util"
done
PATH="$BIN"
export PATH

# shellcheck source=../../install.d/10-helpers.sh
. "$ROOT/install.d/10-helpers.sh"
# shellcheck source=../../install.d/80-tools.sh
. "$ROOT/install.d/80-tools.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

OS="macos"
install_fzf >/dev/null
[ "$(cat "$LOG")" = "install fzf" ] || fail "macOS did not install fzf with Homebrew"
command -v fzf >/dev/null 2>&1 || fail "macOS install did not expose fzf"

install_fzf >/dev/null
[ "$(wc -l <"$LOG" | tr -d ' ')" -eq 1 ] || fail "existing fzf was reinstalled"

rm -f "$BIN/fzf"
: >"$LOG"
install_from_apt() {
    printf 'apt %s\n' "$1" >>"$LOG"
    : >"$BIN/fzf"
    chmod +x "$BIN/fzf"
}
OS="linux"
install_fzf >/dev/null
[ "$(cat "$LOG")" = "apt fzf" ] || fail "Linux did not install fzf with apt"
command -v fzf >/dev/null 2>&1 || fail "Linux install did not expose fzf"

rm -f "$BIN/fzf"
install_from_apt() { return 0; }
if install_fzf >/dev/null; then
    fail "installer accepted a missing fzf executable"
fi

echo "fzf installer tests passed."
