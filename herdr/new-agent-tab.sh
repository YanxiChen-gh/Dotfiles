#!/usr/bin/env bash
# new-agent-tab.sh - Herdr task-workspace launcher (bound to prefix+a/shift+a).
#
# By default, Treehouse opens a worktree and a small shell wrapper creates the
# Herdr workspace inside it with OpenCode.
# --select asks for the checkout, primary pane, optional nvim split, and - for
# OpenCode - an initial prompt first.
#
# Treehouse remains the owner: `treehouse get` waits for its shell wrapper, the
# wrapper waits for the Herdr workspace to close, then Treehouse performs its
# normal dirty check, process cleanup, and pool return.
set -euo pipefail

# herdr runs custom commands via a non-interactive shell that inherits the
# server's PATH, not a login shell's, so ensure our tools are searchable.
export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

herdr="${HERDR_BIN_PATH:-herdr}"
src_cwd="${HERDR_ACTIVE_PANE_CWD:-$PWD}"

# Left pane = coding agent, right pane = editor; change these two lines to taste.
agent_cmd="opencode --auto"
editor_cmd="nvim"
with_worktree=true
with_agent=true
with_editor=false
select_setup=false
handoff_ready=""
treehouse_ready=false
initial_prompt_file=""

# Detached shells have no visible stderr, so surface failures as a herdr toast,
# and - once the panes exist - in the panes too, so a failure never leaves them
# frozen on the "preparing" line.
toast() { "$herdr" notification show "$1" ${2:+--body "$2"} >/dev/null 2>&1 || true; }
report() {
  [ -n "$1" ] || return 0
  "$herdr" pane run "$1" "clear; echo '✗ new task workspace: $2'" >/dev/null 2>&1 || true
}
die() {
  report "${left:-}" "$1"
  report "${right:-}" "$1"
  if [ -n "${task_workspace:-}" ]; then
    "$herdr" workspace close "$task_workspace" >/dev/null 2>&1 || true
  fi
  toast "New task workspace failed" "$1"
  echo "$1" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --select) select_setup=true ;;
    --with-worktree | --worktree) with_worktree=true ;;
    --without-worktree | --current) with_worktree=false ;;
    --with-agent | --agent) with_agent=true ;;
    --without-agent | --shell) with_agent=false ;;
    --with-editor | --editor) with_editor=true ;;
    --without-editor | --no-editor) with_editor=false ;;
    --treehouse-ready)
      treehouse_ready=true
      with_worktree=false
      with_agent="${DOTFILES_HERDR_WITH_AGENT:-true}"
      with_editor="${DOTFILES_HERDR_WITH_EDITOR:-false}"
      initial_prompt_file="${DOTFILES_HERDR_INITIAL_PROMPT_FILE:-}"
      ;;
    --initial-prompt-file)
      [ "$#" -ge 2 ] || die "--initial-prompt-file requires a path"
      initial_prompt_file="$2"
      shift
      ;;
    --handoff-ready)
      [ "$#" -ge 2 ] || die "--handoff-ready requires a path"
      handoff_ready="$2"
      shift
      ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

if [ "$select_setup" = false ] && [ -n "$initial_prompt_file" ]; then
  trap 'rm -f "$initial_prompt_file"' EXIT
fi

if [ -n "$handoff_ready" ]; then
  printf 'ready\n' > "$handoff_ready" || die "could not signal detached launcher readiness"
fi

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

  [ "$checkout" = "Fresh Treehouse worktree" ] || with_worktree=false
  [ "$primary" = "OpenCode" ] || with_agent=false
  [ "$editor" = "nvim right split" ] && with_editor=true

  command -v python3 >/dev/null 2>&1 || die "python3 not installed"
  if [ "$with_agent" = true ]; then
    prompt_input="${HERDR_PROMPT_INPUT_PATH:-$HOME/dotfiles/herdr/prompt-input.py}"
    [ -f "$prompt_input" ] || die "prompt input helper does not exist: $prompt_input"
    initial_prompt_file=$(mktemp "${TMPDIR:-/tmp}/herdr-initial-prompt.XXXXXX") \
      || die "could not create initial prompt file"
    if ! python3 "$prompt_input" > "$initial_prompt_file"; then
      rm -f "$initial_prompt_file"
      exit 0
    fi
  fi
  handoff_ready=$(mktemp "${TMPDIR:-/tmp}/herdr-new-agent-tab.XXXXXX") \
    || die "could not create detached launcher handshake"
  printf 'pending\n' > "$handoff_ready"

  detached_args=(--handoff-ready "$handoff_ready")
  if [ "$with_worktree" = true ]; then
    detached_args+=(--with-worktree)
  else
    detached_args+=(--without-worktree)
  fi
  if [ "$with_agent" = true ]; then
    detached_args+=(--with-agent)
  else
    detached_args+=(--without-agent)
  fi
  if [ "$with_editor" = true ]; then
    detached_args+=(--with-editor)
  else
    detached_args+=(--without-editor)
  fi
  if [ -n "$initial_prompt_file" ]; then
    detached_args+=(--initial-prompt-file "$initial_prompt_file")
  fi

  # start_new_session isolates setup from the popup PTY on both Linux and macOS.
  python3 - "$0" "${detached_args[@]}" <<'PY' \
    || die "could not start detached launcher"
import subprocess
import sys

subprocess.Popen(
    sys.argv[1:],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    start_new_session=True,
)
PY
  for _ in $(seq 1 100); do
    if [ "$(<"$handoff_ready")" = "ready" ]; then
      rm -f "$handoff_ready"
      exit 0
    fi
    sleep 0.02
  done
  rm -f "$handoff_ready"
  die "timed out starting detached launcher"
fi

command -v jq >/dev/null 2>&1 || die "jq not installed"
if [ "$with_agent" = true ]; then
  command -v opencode >/dev/null 2>&1 || die "opencode not installed"
fi
if [ "$with_editor" = true ]; then
  command -v nvim >/dev/null 2>&1 || die "nvim not installed"
fi

if [ "$treehouse_ready" = true ]; then
  workspace_cwd="${TREEHOUSE_DIR:-$PWD}"
  if [ ! -d "$workspace_cwd" ]; then die "Treehouse checkout does not exist: $workspace_cwd"; fi
else
  repo_root=$(git -C "$src_cwd" rev-parse --show-toplevel 2>/dev/null) \
    || die "Not a git repo: $src_cwd - open a task workspace from a repo workspace."

  if [ "$with_worktree" = true ]; then
    command -v treehouse >/dev/null 2>&1 \
      || die "treehouse not installed (go install github.com/kunchenguid/treehouse@latest)"

    # A relative Treehouse root must resolve from the primary checkout, not from
    # an existing linked worktree, or each nested launch creates another pool.
    repo_root=$(git -C "$repo_root" worktree list --porcelain \
      | awk '/^worktree / { sub(/^worktree /, ""); print; exit }')
    if [ -z "$repo_root" ] || [ ! -d "$repo_root" ]; then die "could not resolve primary checkout"; fi
    git -C "$repo_root" worktree prune 2>/dev/null || true

    treehouse_shell="${HERDR_TREEHOUSE_SHELL_PATH:-$HOME/dotfiles/herdr/treehouse-task-shell.sh}"
    if [ ! -x "$treehouse_shell" ]; then die "Treehouse task shell is not executable: $treehouse_shell"; fi

    toast "Preparing task workspace" "Treehouse is provisioning a checkout in the background."
    cd "$repo_root"
    DOTFILES_HERDR_LAUNCHER="$0" \
    DOTFILES_HERDR_ORIGINAL_SHELL="${SHELL:-/bin/sh}" \
    DOTFILES_HERDR_WITH_AGENT="$with_agent" \
    DOTFILES_HERDR_WITH_EDITOR="$with_editor" \
    DOTFILES_HERDR_INITIAL_PROMPT_FILE="$initial_prompt_file" \
    SHELL="$treehouse_shell" \
      treehouse get \
      || die "Treehouse could not prepare a task checkout"
    exit 0
  fi

  workspace_cwd="$repo_root"
fi

initial_prompt=""
if [ -n "$initial_prompt_file" ]; then
  [ -f "$initial_prompt_file" ] || die "initial prompt file does not exist"
  initial_prompt=$(<"$initial_prompt_file")
  rm -f "$initial_prompt_file"
  initial_prompt_file=""
fi

requested_label="shell"
if [ "$with_agent" = true ]; then
  requested_label="agent"
elif [ "$with_editor" = true ]; then
  requested_label="editor"
fi

workspace_args=(workspace create --cwd "$workspace_cwd" --no-focus \
  --env DOTFILES_HERDR_TASK_WORKSPACE=1)
if [ "$treehouse_ready" = true ]; then
  workspace_args+=(--env "TREEHOUSE_DIR=$workspace_cwd")
fi
workspace_json=$("$herdr" "${workspace_args[@]}") || die "herdr workspace create failed"
task_workspace=$(printf '%s' "$workspace_json" | jq -r '.result.workspace.workspace_id')
task_tab=$(printf '%s' "$workspace_json" | jq -r '.result.tab.tab_id')
left=$(printf '%s' "$workspace_json" | jq -r '.result.root_pane.pane_id')
if [ -z "$task_workspace" ] || [ "$task_workspace" = "null" ]; then die "could not read new workspace id"; fi
if [ -z "$task_tab" ] || [ "$task_tab" = "null" ]; then die "could not read new tab id"; fi
if [ -z "$left" ] || [ "$left" = "null" ]; then die "could not read new pane id"; fi
"$herdr" tab rename "$task_tab" "$requested_label" >/dev/null \
  || die "failed to label task tab"

if [ "$with_editor" = true ]; then
  split_args=(pane split "$left" --direction right --ratio 0.5 \
    --cwd "$workspace_cwd" --no-focus --env DOTFILES_HERDR_TASK_WORKSPACE=1)
  if [ "$treehouse_ready" = true ]; then
    split_args+=(--env "TREEHOUSE_DIR=$workspace_cwd")
  fi
  split_json=$("$herdr" "${split_args[@]}") || die "herdr pane split failed"
  right=$(printf '%s' "$split_json" | jq -r '.result.pane.pane_id')
  if [ -z "$right" ] || [ "$right" = "null" ]; then die "could not read split pane id"; fi
  "$herdr" pane run "$right" "cd '$workspace_cwd' && clear; $editor_cmd" \
    || die "failed to launch editor in right pane"
fi

if [ "$with_agent" = true ]; then
  "$herdr" pane run "$left" "cd '$workspace_cwd' && clear; $agent_cmd" \
    || die "failed to launch agent in left pane"
  if [ -n "$initial_prompt" ]; then
    "$herdr" wait output "$left" --match "Ask anything" --timeout 30000 >/dev/null \
      || die "timed out waiting for agent prompt input"
    "$herdr" pane run "$left" "$initial_prompt" \
      || die "failed to submit initial agent prompt"
  fi
fi

toast "Task workspace ready" "Setup finished without changing your current focus."

if [ "$treehouse_ready" = false ]; then
  exit 0
fi

missing_count=0
while true; do
  if workspace_state=$("$herdr" workspace get "$task_workspace" 2>&1); then
    missing_count=0
  else
    error_code=$(printf '%s' "$workspace_state" | jq -r '.error.code // empty' 2>/dev/null || true)
    if [ "$error_code" = "workspace_not_found" ]; then
      missing_count=$((missing_count + 1))
      if [ "$missing_count" -ge 2 ]; then break; fi
    else
      missing_count=0
    fi
  fi
  sleep 1
done

if [ -n "$(git -C "$workspace_cwd" status --porcelain 2>/dev/null)" ]; then
  toast "Task workspace preserved" "Uncommitted changes remain at $workspace_cwd"
fi
