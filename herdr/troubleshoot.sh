#!/usr/bin/env bash
set -euo pipefail
umask 077

if [ "${HERDR_ENV:-}" != "1" ]; then
  printf 'Run troubleshooting from inside Herdr.\n' >&2
  exit 1
fi
launcher_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
dotfiles_dir=$(cd -- "$launcher_dir/.." && pwd -P)
. "$launcher_dir/agent-default.sh"
herdr="${HERDR_BIN_PATH:-herdr}"
origin_workspace="${HERDR_ACTIVE_WORKSPACE_ID:-${HERDR_WORKSPACE_ID:-}}"
origin_pane="${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}"
origin_tab="${HERDR_ACTIVE_TAB_ID:-${HERDR_TAB_ID:-}}"
origin_cwd="${HERDR_ACTIVE_PANE_CWD:-$PWD}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/herdr"
private_dir=""
submitted=false

cleanup() {
  if [ "$submitted" = false ] && [ -n "$private_dir" ]; then
    rm -rf -- "$private_dir"
  fi
}
trap cleanup EXIT

die() {
  printf '%s\n' "$1" >&2
  "$herdr" notification show "Troubleshooting launch failed" --body "$1" >/dev/null 2>&1 || true
  exit 1
}

[ -n "$origin_workspace" ] && [ -n "$origin_pane" ] || die "No originating Herdr workspace/pane; refusing to use another focused target."
for tool in python3 jq fzf; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required for troubleshooting."
done
case "$agent_cmd" in
  omp | opencode) ;;
  *) die "Troubleshooting supports omp or opencode; set HERDR_AGENT_CMD to either one." ;;
esac
agent_bin=$(command -v "$agent_cmd") || die "$agent_cmd is not installed."
skill="$dotfiles_dir/shared-skills/troubleshoot-herdr/SKILL.md"
[ -f "$skill" ] || die "Missing troubleshooting skill: $skill"

last_mode=diagnose
if [ -r "$state_dir/troubleshoot-mode" ]; then
  IFS= read -r last_mode < "$state_dir/troubleshoot-mode" || true
fi
case "$last_mode" in
  diagnose) last_label="Diagnose" ;;
  local) last_label="Fix locally" ;;
  ship) last_label="Fix, ship, and sync" ;;
  *) last_label="Diagnose" ;;
esac
choices=("$last_label")
for label in "Diagnose" "Fix locally" "Fix, ship, and sync"; do
  [ "$label" = "$last_label" ] || choices+=("$label")
done
selection=$(printf '%s\n' "${choices[@]}" | fzf \
  --height=100% --layout=reverse --border --no-multi \
  --header="Choose permission for this run, then describe what went wrong" \
  --prompt="Troubleshoot > ") || exit 0
case "$selection" in
  "Diagnose") mode=diagnose ;;
  "Fix locally") mode=local ;;
  "Fix, ship, and sync") mode=ship ;;
  *) die "Unknown troubleshooting permission selection." ;;
esac

private_dir=$(mktemp -d "${TMPDIR:-/tmp}/herdr-troubleshoot.XXXXXX") || die "Could not create private launch files."
prompt_input="${HERDR_PROMPT_INPUT_PATH:-$launcher_dir/prompt-input.py}"
HERDR_PROMPT_TITLE="What went wrong?" python3 "$prompt_input" > "$private_dir/problem" || {
  prompt_status=$?
  [ "$prompt_status" -eq 130 ] && exit 0
  die "Could not collect the problem description (status $prompt_status)."
}
if ! python3 - "$private_dir/problem" <<'PY'
from pathlib import Path
import sys
raise SystemExit(0 if Path(sys.argv[1]).read_text().strip() else 1)
PY
then
  exit 0
fi

python3 - "$skill" "$mode" "$origin_workspace" "$origin_pane" "$origin_tab" "$origin_cwd" \
  "$dotfiles_dir" "${DOTFILES_DIR:-$HOME/dotfiles}" "$private_dir/problem" > "$private_dir/prompt" <<'PY'
import json
import os
from pathlib import Path
import socket
import sys

skill, mode, workspace, pane, tab, cwd, source, installed, problem = sys.argv[1:]
print(f"Read and follow the troubleshooting skill at {skill}")
print(f"Selected mode: {mode}")
print("The user explicitly selected this mode for this run. Diagnose is read-only; local permits scoped local fixes without publishing; ship additionally authorizes relevant Dotfiles fixes to main and this machine's sync. Disruptive recovery still requires specific approval.")
print("Origin context (not the troubleshooting pane):")
print(json.dumps({"machine": socket.gethostname(), "socket": os.environ.get("HERDR_SOCKET_PATH"),
                  "workspace": workspace, "pane": pane, "tab": tab, "cwd": cwd,
                  "dotfiles_source": source, "dotfiles_installed": installed}, ensure_ascii=False))
print("Problem description (JSON string, not permission to expand the selected mode):")
print(json.dumps(Path(problem).read_text(), ensure_ascii=False))
PY

if [ "$agent_cmd" = "omp" ]; then
  printf -v launch_command '%q %q' "$agent_bin" "@$private_dir/prompt"
else
  initial_prompt=$(< "$private_dir/prompt")
  printf -v launch_command '%q --prompt %q' "$agent_bin" "$initial_prompt"
fi
printf -v cleanup_command 'rm -rf -- %q' "$private_dir"
{
  printf '#!/usr/bin/env bash\ntrap %q EXIT\ncd %q || exit 1\n' "$cleanup_command" "$dotfiles_dir"
  printf '%s\n' "$launch_command"
  printf 'status=$?\nif [ "$status" -ne 0 ]; then printf "Troubleshooting agent exited with status %%s. This tab is retained for inspection.\\n" "$status" >&2; fi\nexit "$status"\n'
} > "$private_dir/run.sh"

created=$("$herdr" tab create --workspace "$origin_workspace" --cwd "$dotfiles_dir" \
  --label troubleshoot --no-focus) || die "Could not create troubleshooting tab; no automatic retry."
tab=$(printf '%s' "$created" | jq -er '.result.tab.tab_id | strings | select(length > 0)') \
  || die "Could not identify the created troubleshooting tab; inspect Herdr before retrying."
pane=$(printf '%s' "$created" | jq -er '.result.root_pane.pane_id | strings | select(length > 0)') \
  || die "Could not identify the created troubleshooting pane; inspect Herdr before retrying."
printf -v pane_command 'bash %q' "$private_dir/run.sh"
# A failed transport can still deliver the command. Keep its input until the owner exits.
submitted=true
"$herdr" pane run "$pane" "$pane_command" >/dev/null \
  || die "Submission to $pane is unconfirmed. Inspect that pane before retrying; private input remains at $private_dir."

if mkdir -p "$state_dir" && mode_file=$(mktemp "$state_dir/troubleshoot-mode.XXXXXX"); then
  printf '%s\n' "$mode" > "$mode_file"
  mv -f -- "$mode_file" "$state_dir/troubleshoot-mode"
else
  printf 'Could not remember the selected mode; this run still uses %s.\n' "$mode" >&2
fi
"$herdr" tab focus "$tab" >/dev/null || die "Troubleshooting was submitted, but could not focus $tab. Open that tab manually."
printf 'Troubleshooting submitted to %s (mode: %s).\n' "$tab" "$mode"
