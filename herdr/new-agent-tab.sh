#!/usr/bin/env bash
# new-agent-tab.sh - herdr custom-command handler (bound to prefix+a).
#
# Opens a new herdr tab in a freshly-leased treehouse worktree, split left/right:
# the coding agent (Claude Code, auto-accept) on the left, the editor (nvim) on
# the right, both rooted in the worktree. herdr runs this as a `type = "shell"`
# command and exports the HERDR_ACTIVE_* context vars we read below.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
src_cwd="${HERDR_ACTIVE_PANE_CWD:-$PWD}"
workspace="${HERDR_ACTIVE_WORKSPACE_ID:-}"

# Left pane = coding agent, right pane = editor; change these two lines to taste.
agent_cmd="claude --permission-mode auto"
editor_cmd="nvim"

# Detached shells have no visible stderr, so surface failures as a herdr toast.
toast() { "$herdr" notification show "$1" ${2:+--body "$2"} >/dev/null 2>&1 || true; }
die() { toast "New agent tab failed" "$1"; echo "$1" >&2; exit 1; }

command -v treehouse >/dev/null 2>&1 \
  || die "treehouse not installed (go install github.com/kunchenguid/treehouse@latest)"
command -v jq >/dev/null 2>&1 || die "jq not installed"

repo_root=$(git -C "$src_cwd" rev-parse --show-toplevel 2>/dev/null) \
  || die "Not a git repo: $src_cwd - open an agent tab from a repo workspace."

# Lease a pre-warmed, provisioned worktree. --lease prints only the path to
# stdout (banners go to stderr) and reserves it until `treehouse return`.
wt=$(cd "$repo_root" && treehouse get --lease --lease-holder herdr) \
  || die "treehouse could not lease a worktree in $repo_root"
if [ -z "$wt" ] || [ ! -d "$wt" ]; then die "treehouse returned no usable worktree path"; fi

# A lease persists until returned, so until a tab actually holds this worktree,
# return it on any failure below - otherwise a broken run silently drains the pool.
tab_holds_worktree=0
trap '[ "$tab_holds_worktree" = 1 ] || treehouse return --force "$wt" >/dev/null 2>&1 || true' EXIT

# New tab rooted in the worktree; its root pane becomes the left (agent) pane.
tab_json=$("$herdr" tab create ${workspace:+--workspace "$workspace"} \
  --cwd "$wt" --label "agent" --focus) || die "herdr tab create failed"
tab_holds_worktree=1
left=$(printf '%s' "$tab_json" | jq -r '.result.root_pane.pane_id')
if [ -z "$left" ] || [ "$left" = "null" ]; then die "could not read new pane id from tab create"; fi

# --direction right = vertical divider (panes side by side). --no-focus keeps
# focus on the left pane so the agent is ready for input.
split_json=$("$herdr" pane split "$left" --direction right --ratio 0.5 \
  --cwd "$wt" --no-focus) || die "herdr pane split failed"
right=$(printf '%s' "$split_json" | jq -r '.result.pane.pane_id')
if [ -z "$right" ] || [ "$right" = "null" ]; then die "could not read split pane id"; fi

"$herdr" pane run "$left"  "$agent_cmd"  || die "failed to launch agent in left pane"
"$herdr" pane run "$right" "$editor_cmd" || die "failed to launch editor in right pane"
