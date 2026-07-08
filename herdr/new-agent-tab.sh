#!/usr/bin/env bash
# new-agent-tab.sh - herdr custom-command handler (bound to prefix+a).
#
# Opens a new herdr tab split left/right in a fresh treehouse worktree - the
# coding agent (OpenCode, auto mode) on the left, the editor (nvim) on the
# right. herdr runs this as a `type = "shell"` command and exports the
# HERDR_ACTIVE_* context vars we read below.
#
# We lean on treehouse's own pool lifecycle rather than manage worktrees
# ourselves: the LEFT pane runs `treehouse get` (NOT --lease), so treehouse owns
# the worktree and auto-returns it to the pool when the tab's processes exit - no
# cleanup/reaper needed. Because an unleased `get` prints no scriptable path (and
# herdr doesn't expose a pane's cwd), the left subshell publishes its path to a
# per-invocation handoff file so the RIGHT pane can join the SAME worktree.
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

# Detached shells have no visible stderr, so surface failures as a herdr toast,
# and - once the panes exist - in the panes too, so a failure never leaves them
# frozen on the "preparing" line.
toast() { "$herdr" notification show "$1" ${2:+--body "$2"} >/dev/null 2>&1 || true; }
report() {
  [ -n "$1" ] || return 0
  "$herdr" pane run "$1" "clear; echo '✗ new agent tab: $2'" >/dev/null 2>&1 || true
}
die() { report "${left:-}" "$1"; report "${right:-}" "$1"; toast "New agent tab failed" "$1"; echo "$1" >&2; exit 1; }

command -v treehouse >/dev/null 2>&1 \
  || die "treehouse not installed (go install github.com/kunchenguid/treehouse@latest)"
command -v jq >/dev/null 2>&1 || die "jq not installed"

repo_root=$(git -C "$src_cwd" rev-parse --show-toplevel 2>/dev/null) \
  || die "Not a git repo: $src_cwd - open an agent tab from a repo workspace."

# Self-heal any stale worktree registrations (a pool dir removed out-of-band)
# so `treehouse get` can't wedge on a "missing but already registered worktree".
git -C "$repo_root" worktree prune 2>/dev/null || true

# Create the tab + split up front, rooted at the repo, so they appear instantly
# instead of after the multi-second worktree setup. --direction right = side by
# side; --no-focus keeps focus on the left pane.
tab_json=$("$herdr" tab create ${workspace:+--workspace "$workspace"} \
  --cwd "$repo_root" --label "agent" --focus) || die "herdr tab create failed"
left=$(printf '%s' "$tab_json" | jq -r '.result.root_pane.pane_id')
if [ -z "$left" ] || [ "$left" = "null" ]; then die "could not read new pane id from tab create"; fi
split_json=$("$herdr" pane split "$left" --direction right --ratio 0.5 \
  --cwd "$repo_root" --no-focus) || die "herdr pane split failed"
right=$(printf '%s' "$split_json" | jq -r '.result.pane.pane_id')
if [ -z "$right" ] || [ "$right" = "null" ]; then die "could not read split pane id"; fi

"$herdr" pane run "$right" "clear; echo '🌳 preparing treehouse worktree...'" || true

# Left pane acquires and owns the worktree via `treehouse get`; its own
# "Setting up worktree..." output is the progress the user sees there.
handoff=$(mktemp -u "${TMPDIR:-/tmp}/herdr-agent-wt.XXXXXX")
"$herdr" pane send-keys "$left" ctrl+u >/dev/null 2>&1 || true
"$herdr" pane run "$left" "cd '$repo_root' && treehouse get" || die "failed to start treehouse in left pane"

# Wait for treehouse to enter a worktree (it reports one in-use), then have the
# subshell publish its path to the handoff file and launch the agent. Running the
# agent as a child (not exec) keeps the get subshell alive as the worktree's
# owner until the tab closes, at which point treehouse returns it to the pool.
for _ in $(seq 1 60); do treehouse status 2>/dev/null | grep -q 'in-use' && break; sleep 1; done
"$herdr" pane run "$left" "pwd > '$handoff'; clear; $agent_cmd" || die "failed to launch agent in left pane"

# Read the worktree path the left subshell published, then join the right pane.
wt=""
for _ in $(seq 1 30); do [ -s "$handoff" ] && wt=$(cat "$handoff") && break; sleep 1; done
rm -f "$handoff"
if [ -z "$wt" ] || [ ! -d "$wt" ]; then die "timed out waiting for the worktree to be ready"; fi

"$herdr" pane send-keys "$right" ctrl+u >/dev/null 2>&1 || true
"$herdr" pane run "$right" "cd '$wt' && clear; $editor_cmd" || die "failed to launch editor in right pane"
