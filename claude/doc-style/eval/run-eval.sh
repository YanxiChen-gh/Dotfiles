#!/usr/bin/env bash
# Doc-style eval. Two modes, both use `claude -p` headless as the judge engine.
#
#   ./run-eval.sh calibrate   # blind pairwise: does the judge prefer the human doc?
#   ./run-eval.sh score FILE  # single-doc rubric score
#
# calibrate pairs corpus/agent/NN-*.md against corpus/human/NN-*.md by number.
# A correct judge picks the human doc AND names the seeded anti-tells (see rubric.md).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUBRIC="$HERE/../rubric.md"
JUDGE="$HERE/judge.md"
# Corpus + results hold internal content and live in the PRIVATE data repo, not here.
DATA="${STYLE_HARNESS_DATA:-$HOME/style-harness-data}"
CORPUS="$DATA/doc-style/corpus"
RESULTS="$DATA/doc-style/results"
if [ ! -d "$CORPUS" ]; then
  echo "corpus not found at $CORPUS - clone the private data repo (see ../README.md) or set STYLE_HARNESS_DATA" >&2
  exit 1
fi
mkdir -p "$RESULTS"

judge() { # $1 = full prompt text
  claude -p "$1" --output-format text
}

calibrate() {
  local pass=0 total=0
  for agent_doc in "$CORPUS"/agent/*.md; do
    local num human_doc
    num="$(basename "$agent_doc" | grep -oE '^[0-9]+')"
    human_doc="$(ls "$CORPUS"/human/${num}-*.md 2>/dev/null | head -1)" || true
    [ -z "${human_doc:-}" ] && { echo "skip $num: no human counterpart"; continue; }
    total=$((total+1))

    # Assign A/B by parity so the human isn't always the same slot.
    local A B human_slot
    if [ $((10#$num % 2)) -eq 0 ]; then A="$human_doc"; B="$agent_doc"; human_slot=A
    else A="$agent_doc"; B="$human_doc"; human_slot=B; fi

    local prompt out winner
    prompt="$(cat "$JUDGE")

Rubric:
$(cat "$RUBRIC")

=== DOC A ===
$(cat "$A")

=== DOC B ===
$(cat "$B")

Run Mode A. Output ONLY the JSON."
    out="$(judge "$prompt")"
    winner="$(echo "$out" | grep -oE '"winner"[^,}]*' | grep -oE '[AB]' | head -1)"
    if [ "$winner" = "$human_slot" ]; then pass=$((pass+1)); echo "pair $num: PASS (chose human)"; else echo "pair $num: FAIL (chose agent)"; fi
    echo "$out" > "$RESULTS/results-calibrate-$num.json"
  done
  echo "calibration: $pass/$total pairs preferred the human doc"
}

score() {
  local file="$1"
  local prompt
  prompt="$(cat "$JUDGE")

Rubric:
$(cat "$RUBRIC")

=== DOC ===
$(cat "$file")

Run Mode B. Output ONLY the JSON."
  judge "$prompt"
}

case "${1:-}" in
  calibrate) calibrate ;;
  score) score "${2:?usage: run-eval.sh score FILE}" ;;
  *) echo "usage: run-eval.sh {calibrate | score FILE}"; exit 1 ;;
esac
