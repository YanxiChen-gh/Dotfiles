#!/usr/bin/env bash
# Collect agent-maturity evidence from Ona environments.
#
# Why: Claude Code session transcripts (~/.claude/projects) and any `li` entries logged
# inside an env (~/dotfiles/.../interventions.jsonl) live on the env's disk and vanish when
# the env is deleted. This pulls them out of every (running) Ona env into a central, durable
# place so /harvest-interventions and /maturity-review can mine across all your work.
#
# Transport: native ssh via Ona's ssh-config host alias (<id>.ona.environment). We do NOT use
# `ona environment ssh -- <cmd>` because that re-splits the remote command on spaces (so
# `bash -lc 'find /a /b ...'` becomes `bash -lc find` with the rest as positional args).
# Native ssh preserves quoting and gives clean binary stdout for tar streaming.
#
# Usage:
#   collect-ona-evidence.sh [--include-stopped] [--repo <checkoutLocation>] [--out <dir>] [--all]
#     --include-stopped   also pull from STOPPED envs (connecting STARTS them — slow & costs
#                         compute). Default: running envs only.
#     --repo <name>       only envs whose git checkoutLocation matches (e.g. "obsidian").
#     --out <dir>         evidence dir (default ~/dotfiles/claude/agent-maturity/evidence).
#     --all               include envs created by others you can see (default: only yours).
#
# Requires: `ona login` done. Evidence transcripts are gitignored (bulky, may contain code);
# the merged interventions.jsonl IS the durable artifact — commit it to the Dotfiles repo.

set -uo pipefail   # NOT -e: a single bad env must not abort the whole sweep.

MATURITY_DIR="${AGENT_MATURITY_DIR:-$HOME/dotfiles/claude/agent-maturity}"
OUT="$MATURITY_DIR/evidence"
CENTRAL_LOG="$MATURITY_DIR/interventions.jsonl"
INCLUDE_STOPPED=0; REPO_FILTER=""; LIST_ALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --include-stopped) INCLUDE_STOPPED=1 ;;
    --all)             LIST_ALL=1 ;;
    --repo)            REPO_FILTER="${2:-}"; shift ;;
    --out)             OUT="${2:-}"; shift ;;
    -h|--help)         sed -n '2,33p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v ona >/dev/null || { echo "error: ona CLI not on PATH" >&2; exit 1; }
ona whoami >/dev/null 2>&1 || { echo "error: not logged in — run 'ona login'" >&2; exit 1; }

# Ensure native-ssh host aliases (<id>.ona.environment) exist; idempotent.
grep -qs "ona.environment" "$HOME/.ssh/ona/config" 2>/dev/null || ona environment ssh-config >/dev/null 2>&1

mkdir -p "$OUT"
SOCKDIR="$(mktemp -d)"
MERGE_TMP="$(mktemp)"
trap 'rm -rf "$SOCKDIR" "$MERGE_TMP"' EXIT
[ -f "$CENTRAL_LOG" ] && cat "$CENTRAL_LOG" >> "$MERGE_TMP"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=accept-new
          -o LogLevel=ERROR -o ControlMaster=auto -o "ControlPath=$SOCKDIR/cm-%C" -o ControlPersist=60)

# Phase filter: running-only by default; running+stopped if asked.
phase_args=(--phase running)
[ "$INCLUDE_STOPPED" = 1 ] && phase_args=(--phase running --phase stopped)
[ "$LIST_ALL" = 1 ] && phase_args+=(-a)

echo "Listing Ona environments (${phase_args[*]})..."
ENV_JSON="$(ona environment list "${phase_args[@]}" -o json 2>/dev/null)" \
  || { echo "error: 'ona environment list' failed" >&2; exit 1; }

# One TSV row per env: id <tab> label <tab> phase <tab> repo
mapfile -t ROWS < <(printf '%s' "$ENV_JSON" | REPO_FILTER="$REPO_FILTER" python3 -c '
import json, os, re, sys
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get("environments") or data.get("items") or []
want = os.environ.get("REPO_FILTER", "")
clean = lambda s: re.sub(r"[^A-Za-z0-9._-]", "-", s or "")
for it in items:
    eid = it.get("id", "")
    spec, status = it.get("spec", {}), it.get("status", {})
    phase = (status.get("phase") or spec.get("desiredPhase") or "").replace("ENVIRONMENT_PHASE_", "").lower()
    repo = branch = ""
    try:
        g = spec["content"]["initializer"]["specs"][0]["git"]
        repo, branch = g.get("checkoutLocation", ""), g.get("cloneTarget", "")
    except Exception:
        pass
    if want and want.lower() not in repo.lower():
        continue
    label = clean((repo or "env") + "_" + (branch or "x") + "_" + eid[:8])
    print(eid + "\t" + label + "\t" + phase + "\t" + repo)
')

[ "${#ROWS[@]}" -eq 0 ] && { echo "No matching environments."; exit 0; }
echo "Found ${#ROWS[@]} environment(s)."

# Run a remote command over native ssh (quoting preserved, binary-clean stdout).
rrun() { ssh "${SSH_OPTS[@]}" "$1.ona.environment" "$2" 2>/dev/null; }

collected=0; skipped=0
for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r eid label phase repo <<<"$row"
  echo "── $label  (phase=$phase)"
  if [ "$phase" != "running" ] && [ "$INCLUDE_STOPPED" != 1 ]; then
    echo "   skip (stopped; pass --include-stopped to start+pull)"; skipped=$((skipped+1)); continue
  fi

  # 1) Locate the transcript dir (SSH user may differ from the dev user — discover it).
  proj_dir="$(rrun "$eid" 'find /home /root -maxdepth 4 -type d -path "*/.claude/projects" 2>/dev/null' \
               | tr -d '\r' | grep -m1 '/\.claude/projects$')"
  if [ -z "$proj_dir" ]; then
    echo "   no Claude transcripts found"; skipped=$((skipped+1))
  else
    parent="$(dirname "$proj_dir")"; tgz="$(mktemp)"
    if rrun "$eid" "tar czf - -C '$parent' projects 2>/dev/null" > "$tgz" && tar tzf "$tgz" >/dev/null 2>&1; then
      rm -rf "${OUT:?}/$label"; mkdir -p "$OUT/$label"
      tar xzf "$tgz" -C "$OUT/$label"
      n=$(find "$OUT/$label/projects" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')
      echo "   transcripts: $n session file(s) → evidence/$label/"
      collected=$((collected+1))
    else
      echo "   transcript tar failed/empty"; skipped=$((skipped+1))
    fi
    rm -f "$tgz"
  fi

  # 2) Pull any interventions.jsonl logged inside this env (li writes are env-local too).
  total_lines=0
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    before=$(wc -l < "$MERGE_TMP"); rrun "$eid" "cat '$p' 2>/dev/null" >> "$MERGE_TMP"
    total_lines=$((total_lines + $(wc -l < "$MERGE_TMP") - before))
  done < <(rrun "$eid" 'find /home -maxdepth 7 -path "*/agent-maturity/interventions.jsonl" 2>/dev/null' | tr -d '\r')
  [ "$total_lines" -gt 0 ] && echo "   merged $total_lines intervention line(s) from this env's log"
done

# Merge + de-dupe interventions back into the central durable log.
if [ -s "$MERGE_TMP" ]; then
  grep -E '^\s*\{' "$MERGE_TMP" | sort -u > "$CENTRAL_LOG"
  echo "Central interventions.jsonl now holds $(wc -l < "$CENTRAL_LOG" | tr -d ' ') unique line(s)."
fi

{ echo "collected_at: $(date -u +%FT%TZ)"
  echo "envs_collected: $collected   skipped: $skipped"
  echo "filter_repo: ${REPO_FILTER:-<none>}   include_stopped: $INCLUDE_STOPPED"
} > "$OUT/_manifest.txt"

echo
echo "Done. Transcripts in $OUT/<env>/  (gitignored, ephemeral)."
echo "Durable artifact: $CENTRAL_LOG — commit it to the Dotfiles repo so it survives env deletion."
echo "Next: /harvest-interventions  then  /maturity-review"
