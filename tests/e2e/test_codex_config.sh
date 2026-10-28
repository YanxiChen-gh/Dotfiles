#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-e2e-codex.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

mkdir -p "$TMP/repo/codex" "$TMP/home"
cp "$ROOT/codex/config.toml" "$TMP/repo/codex/config.toml"
export HOME="$TMP/home"
unset CODEX_HOME
WORK_MACHINE=0
resolve_script_dir() { printf '%s\n' "$TMP/repo"; }

# shellcheck source=../../install.d/10-helpers.sh
. "$ROOT/install.d/10-helpers.sh"
# shellcheck source=../../install.d/60-codex.sh
. "$ROOT/install.d/60-codex.sh"

config="$HOME/.codex/config.toml"
source_config="$TMP/repo/codex/config.toml"
setup_codex_config >/dev/null
[ "$(readlink "$config")" = "$source_config" ] || fail "config was not linked"
setup_codex_config >/dev/null
[ ! -e "$config.pre-dotfiles" ] || fail "repeat setup backed up the managed link"

rm "$config"
printf 'custom host settings\n' >"$config"
setup_codex_config >/dev/null
[ "$(readlink "$config")" = "$source_config" ] || fail "existing config was not replaced with a link"
[ "$(cat "$config.pre-dotfiles")" = "custom host settings" ] || fail "existing config was not preserved"
setup_codex_config >/dev/null
[ "$(cat "$config.pre-dotfiles")" = "custom host settings" ] || fail "repeat setup changed the backup"

rm "$config"
printf 'new host settings\n' >"$config"
if setup_codex_config >/dev/null; then
    fail "setup replaced an existing config when its backup already existed"
fi
[ "$(cat "$config")" = "new host settings" ] || fail "backup collision changed the config"
[ "$(cat "$config.pre-dotfiles")" = "custom host settings" ] || fail "backup collision changed the backup"

export CODEX_HOME="$TMP/custom-codex"
setup_codex_config >/dev/null
[ "$(readlink "$CODEX_HOME/config.toml")" = "$source_config" ] || fail "CODEX_HOME config was not linked"
[ "$(cat "$config")" = "new host settings" ] || fail "CODEX_HOME changed the default config"

printf 'Codex config symlinking and backup preservation passed.\n'
