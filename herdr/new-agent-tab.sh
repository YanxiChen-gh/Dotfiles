#!/usr/bin/env bash
# new-agent-tab.sh - Herdr development-tab launcher (bound to prefix+a/shift+a).
#
# By default, opens a new Herdr tab in a fresh Treehouse worktree with OpenCode.
# --select asks for the checkout, primary pane, and optional nvim split first.
#
# We lean on Treehouse's own pool lifecycle rather than manage worktrees
# ourselves: the LEFT pane runs `treehouse get` (NOT --lease), so treehouse owns
# the worktree and auto-returns it to the pool when the tab's processes exit - no
# cleanup/reaper needed. Because an unleased `get` prints no scriptable path (and
# herdr doesn't expose a pane's cwd), the left subshell publishes its path to a
# per-invocation handoff file when the editor pane needs to join the same worktree.
set -euo pipefail

# herdr runs custom commands via a non-interactive shell that inherits the
# server's PATH, not a login shell's, so ensure our tools are searchable.
export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

herdr="${HERDR_BIN_PATH:-herdr}"
src_cwd="${HERDR_ACTIVE_PANE_CWD:-$PWD}"
workspace="${HERDR_ACTIVE_WORKSPACE_ID:-}"

# Left pane = coding agent, right pane = editor; change these two lines to taste.
agent_cmd="opencode --auto"
editor_cmd="nvim"
with_worktree=true
with_agent=true
with_editor=false
select_setup=false
requested_label=""

# Detached shells have no visible stderr, so surface failures as a herdr toast,
# and - once the panes exist - in the panes too, so a failure never leaves them
# frozen on the "preparing" line.
toast() { "$herdr" notification show "$1" ${2:+--body "$2"} >/dev/null 2>&1 || true; }
report() {
  [ -n "$1" ] || return 0
  "$herdr" pane run "$1" "clear; echo '✗ new agent tab: $2'" >/dev/null 2>&1 || true
}
die() { report "${left:-}" "$1"; report "${right:-}" "$1"; toast "New development tab failed" "$1"; echo "$1" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --select) select_setup=true ;;
    --with-worktree | --worktree) with_worktree=true ;;
    --without-worktree | --current) with_worktree=false ;;
    --with-agent | --agent) with_agent=true ;;
    --without-agent | --shell) with_agent=false ;;
    --with-editor | --editor) with_editor=true ;;
    --without-editor | --no-editor) with_editor=false ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

choose() {
  prompt="$1"
  shift
  printf '%s\n' "$@" | fzf \
    --height=100% \
    --layout=reverse \
    --border \
    --no-multi \
    --prompt="$prompt > "
}

if [ "$select_setup" = true ]; then
  command -v fzf >/dev/null 2>&1 || die "fzf not installed"

  checkout=$(choose "Checkout" "Fresh Treehouse worktree" "Current checkout") || exit 0
  primary=$(choose "Primary pane" "OpenCode" "Shell") || exit 0
  editor=$(choose "Editor" "No editor" "nvim right split") || exit 0
  printf '\033[2J\033[HTab name (leave blank for Herdr default): '
  IFS= read -r requested_label || exit 0

  [ "$checkout" = "Fresh Treehouse worktree" ] || with_worktree=false
  [ "$primary" = "OpenCode" ] || with_agent=false
  [ "$editor" = "nvim right split" ] && with_editor=true
fi

command -v jq >/dev/null 2>&1 || die "jq not installed"
if [ "$with_worktree" = true ]; then
  command -v treehouse >/dev/null 2>&1 \
    || die "treehouse not installed (go install github.com/kunchenguid/treehouse@latest)"
fi
if [ "$with_agent" = true ]; then
  command -v opencode >/dev/null 2>&1 || die "opencode not installed"
fi
if [ "$with_editor" = true ]; then
  command -v nvim >/dev/null 2>&1 || die "nvim not installed"
fi

repo_root=$(git -C "$src_cwd" rev-parse --show-toplevel 2>/dev/null) \
  || die "Not a git repo: $src_cwd - open an agent tab from a repo workspace."

if [ "$with_worktree" = true ]; then
  # Prevent a pool directory removed out-of-band from wedging `treehouse get`.
  git -C "$repo_root" worktree prune 2>/dev/null || true
fi

if [ "$select_setup" = false ]; then
  requested_label="shell"
  if [ "$with_agent" = true ]; then
    requested_label="agent"
  elif [ "$with_editor" = true ]; then
    requested_label="editor"
  fi
fi

# Create the tab up front, rooted at the repo, so it appears instantly instead
# of after the multi-second worktree setup.
tab_args=(tab create --cwd "$repo_root" --focus)
if [ -n "$workspace" ]; then
  tab_args+=(--workspace "$workspace")
fi
if [ -n "$requested_label" ]; then
  tab_args+=(--label "$requested_label")
fi
tab_json=$("$herdr" "${tab_args[@]}") || die "herdr tab create failed"
left=$(printf '%s' "$tab_json" | jq -r '.result.root_pane.pane_id')
if [ -z "$left" ] || [ "$left" = "null" ]; then die "could not read new pane id from tab create"; fi

if [ "$with_editor" = true ]; then
  split_json=$("$herdr" pane split "$left" --direction right --ratio 0.5 \
    --cwd "$repo_root" --no-focus) || die "herdr pane split failed"
  right=$(printf '%s' "$split_json" | jq -r '.result.pane.pane_id')
  if [ -z "$right" ] || [ "$right" = "null" ]; then die "could not read split pane id"; fi
  if [ "$with_worktree" = true ]; then
    "$herdr" pane run "$right" "clear; echo '🌳 preparing Treehouse worktree...'" || true
  fi
fi

if [ "$with_worktree" = false ]; then
  if [ "$with_editor" = true ]; then
    "$herdr" pane run "$right" "cd '$repo_root' && clear; $editor_cmd" \
      || die "failed to launch editor in right pane"
  fi
  if [ "$with_agent" = true ]; then
    "$herdr" pane run "$left" "clear; $agent_cmd" || die "failed to launch agent in left pane"
  fi
  exit 0
fi

# Left pane acquires and owns the worktree via `treehouse get`; its own
# "Setting up worktree..." output is the progress the user sees there.
"$herdr" pane send-keys "$left" ctrl+u >/dev/null 2>&1 || true
"$herdr" pane run "$left" "cd '$repo_root' && treehouse get" || die "failed to start treehouse in left pane"

# Wait for treehouse to enter a worktree (it reports one in-use), then have the
# subshell launch the agent. Running the agent as a child (not exec) keeps the
# get subshell alive as the worktree's owner until the tab closes, at which point
# treehouse returns it to the pool.
worktree_ready=false
for _ in $(seq 1 60); do
  if treehouse status 2>/dev/null | grep -q 'in-use'; then
    worktree_ready=true
    break
  fi
  sleep 1
done
if [ "$worktree_ready" = false ]; then die "timed out waiting for the worktree to be ready"; fi

if [ "$with_editor" = false ]; then
  if [ "$with_agent" = true ]; then
    "$herdr" pane run "$left" "clear; $agent_cmd" || die "failed to launch agent in left pane"
  fi
  exit 0
fi

handoff=$(mktemp "${TMPDIR:-/tmp}/herdr-agent-wt.XXXXXX")
left_command="pwd > '$handoff'"
if [ "$with_agent" = true ]; then
  left_command="$left_command; clear; $agent_cmd"
fi
"$herdr" pane run "$left" "$left_command" || die "failed to prepare left pane"

# Read the worktree path the left subshell published, then join the right pane.
wt=""
for _ in $(seq 1 30); do [ -s "$handoff" ] && wt=$(cat "$handoff") && break; sleep 1; done
rm -f "$handoff"
if [ -z "$wt" ] || [ ! -d "$wt" ]; then die "timed out waiting for the worktree to be ready"; fi

"$herdr" pane send-keys "$right" ctrl+u >/dev/null 2>&1 || true
"$herdr" pane run "$right" "cd '$wt' && clear; $editor_cmd" || die "failed to launch editor in right pane"
