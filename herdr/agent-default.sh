# shellcheck shell=bash
# Herdr custom commands inherit the server's non-login PATH.
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

omp_ready_marker="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}/.dotfiles-ready"
if [ -n "${HERDR_AGENT_CMD:-}" ]; then
  agent_cmd="$HERDR_AGENT_CMD"
elif [ "${OMP_EXPERIMENT:-1}" != "0" ] && command -v omp >/dev/null 2>&1 \
  && omp --version >/dev/null 2>&1 && [ -f "$omp_ready_marker" ] \
  && [ -w "$omp_ready_marker" ] && [ -w "${omp_ready_marker%/*}" ]; then
  agent_cmd="omp"
else
  agent_cmd="opencode"
fi
