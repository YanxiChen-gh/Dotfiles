#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-figma-mcp-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM

HOME="$TMP/home"
XDG_CONFIG_HOME="$TMP/config"
FAKE_BIN="$TMP/bin"
UVX_LOG="$TMP/uvx.log"
mkdir -p "$HOME" "$FAKE_BIN"
export HOME XDG_CONFIG_HOME UVX_LOG

cat >"$FAKE_BIN/uvx" <<'EOF'
#!/bin/sh
printf 'args=%s\nconfig=%s\n' "$*" "${MCP2CLI_CONFIG_DIR:-}" >>"$UVX_LOG"
EOF
chmod +x "$FAKE_BIN/uvx"
PATH="$FAKE_BIN:/usr/bin:/bin"
export PATH

resolve_script_dir() {
  printf '%s\n' "$ROOT"
}

# shellcheck source=../../install.d/20-mcp.sh
. "$ROOT/install.d/20-mcp.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

setup_figma_mcp_cli >/dev/null
setup_figma_mcp_cli >/dev/null

MCP2CLI="$HOME/.local/bin/mcp2cli"
FIGMA="$HOME/.local/bin/figma-mcp-cli"
CONFIG="$XDG_CONFIG_HOME/mcp2cli-figma/baked.json"

[ -x "$MCP2CLI" ] || fail "mcp2cli wrapper is missing"
[ -x "$FIGMA" ] || fail "figma-mcp-cli wrapper is missing"
cmp -s "$ROOT/mcp2cli/figma/baked.json" "$CONFIG" || fail "Figma config was not copied"
[ ! -e "$UVX_LOG" ] || fail "setup unexpectedly started mcp2cli or OAuth"

"$MCP2CLI" --version
"$FIGMA" --list

cat >"$TMP/expected.log" <<EOF
args=--with mcp==1.22.0 mcp2cli --version
config=
args=--with mcp==1.22.0 mcp2cli @figma --list
config=$XDG_CONFIG_HOME/mcp2cli-figma
EOF
cmp -s "$TMP/expected.log" "$UVX_LOG" || fail "wrappers did not preserve the pin or Figma config path"

printf 'Figma MCP setup tests passed.\n'
