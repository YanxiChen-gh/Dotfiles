#!/usr/bin/env bash
# Doc-style eval. Candidate generation and judging use separate engines.
#
#   ./run-eval.sh calibrate   # blind pairwise: does the judge prefer the human doc?
#   ./run-eval.sh score FILE  # single-doc rubric score
#   ./run-eval.sh rewrite     # rewrite the golden agent doc, then compare with the human doc
#
# calibrate pairs corpus/agent/NN-*.md against corpus/human/NN-*.md by number.
# A correct judge picks the human doc AND names the seeded anti-tells (see rubric.md).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUBRIC="$HERE/../rubric.md"
JUDGE="$HERE/judge.md"
ENGINE="$HERE/../../style-eval-engine.sh"
AUTHOR_SKILL="$HERE/../../skills/doc-authoring/SKILL.md"
# Corpus + results hold internal content and live in the PRIVATE data repo, not here.
DATA="${STYLE_HARNESS_DATA:-$HOME/style-harness-data}"
CORPUS="$DATA/doc-style/corpus"
RESULTS="$DATA/doc-style/results"
SOURCES="$CORPUS/SOURCES.md"
SYNTHETIC_GENERATION="$CORPUS/synthetic-generation.json"
if [ ! -d "$CORPUS" ]; then
  echo "corpus not found at $CORPUS - clone the private data repo (see ../README.md) or set STYLE_HARNESS_DATA" >&2
  exit 1
fi
mkdir -p "$RESULTS"
# shellcheck source=claude/style-eval-engine.sh
source "$ENGINE"

judge() { style_eval_engine judge "$1"; }
agent() { style_eval_engine agent "$1" "$2"; }

calibrate() {
  style_eval_require_jq
  local pass=0 total=0
  for agent_doc in "$CORPUS"/agent/*.md; do
    local num human_doc
    local human_docs
    num="$(basename "$agent_doc" | grep -oE '^[0-9]+')"
    human_docs=("$CORPUS"/human/"${num}"-*.md)
    human_doc="${human_docs[0]}"
    [ -f "$human_doc" ] || { echo "skip $num: no human counterpart"; continue; }
    total=$((total+1))

    # Assign A/B by parity so the human isn't always the same slot.
    local A B human_slot
    if [ $((10#$num % 2)) -eq 0 ]; then A="$human_doc"; B="$agent_doc"; human_slot=A
    else A="$agent_doc"; B="$human_doc"; human_slot=B; fi

    local prompt out winner run_dir
    run_dir="$(style_eval_run_dir "$RESULTS" "calibrate-$num")"
    cp "$A" "$run_dir/artifact-a.md"
    cp "$B" "$run_dir/artifact-b.md"
    style_eval_write_metadata "$run_dir" "calibrate-$num" "$run_dir/artifact-a.md" "$run_dir/artifact-b.md" "$SOURCES" "$SYNTHETIC_GENERATION" "$RUBRIC" "$JUDGE"
    printf 'human_slot=%s\n' "$human_slot" >>"$run_dir/metadata.txt"
    prompt="$(cat "$JUDGE")

Rubric:
$(cat "$RUBRIC")

=== DOC A ===
$(cat "$run_dir/artifact-a.md")

=== DOC B ===
$(cat "$run_dir/artifact-b.md")

Run Mode A. Output ONLY the JSON."
    out="$(judge "$prompt" | style_eval_normalize_json)"
    winner="$(echo "$out" | grep -oE '"winner"[^,}]*' | grep -oE '[AB]' | head -1)"
    if [ "$winner" = "$human_slot" ]; then pass=$((pass+1)); echo "pair $num: PASS (chose human)"; else echo "pair $num: FAIL (chose agent)"; fi
    printf '%s\n' "$out" >"$run_dir/judgment.json"
    style_eval_validate_pairwise_json "$run_dir/judgment.json"
  done
  echo "calibration: $pass/$total pairs preferred the human doc"
}

rewrite() {
  style_eval_require_jq
  local source_doc="$CORPUS/agent/01-day1-playbook.md"
  local human_doc="$CORPUS/human/01-day1-playbook.md"
  local run_dir candidate_file judgment_file source_snapshot reference_file
  run_dir="$(style_eval_run_dir "$RESULTS" rewrite-01)"
  candidate_file="$run_dir/candidate.md"
  judgment_file="$run_dir/judgment.json"
  source_snapshot="$run_dir/source.md"
  reference_file="$run_dir/reference.md"
  cp "$source_doc" "$source_snapshot"
  cp "$human_doc" "$reference_file"
  style_eval_write_metadata "$run_dir" rewrite-01 "$source_snapshot" "$reference_file" "$SOURCES" "$RUBRIC" "$JUDGE" "$AUTHOR_SKILL"

  if [ -n "${EVAL_CANDIDATE:-}" ]; then
    [ -f "$EVAL_CANDIDATE" ] || { echo "candidate not found: $EVAL_CANDIDATE" >&2; return 1; }
    cp "$EVAL_CANDIDATE" "$candidate_file"
    printf 'candidate_source=%s\n' "$EVAL_CANDIDATE" >>"$run_dir/metadata.txt"
    printf 'candidate_source_sha256=%s\n' "$(sha256sum "$EVAL_CANDIDATE" | cut -d' ' -f1)" >>"$run_dir/metadata.txt"
  else
    agent "$(cat "$AUTHOR_SKILL")

Rubric:
$(cat "$RUBRIC")

Rewrite the document below using the doc-authoring harness. Preserve its verified factual content,
but fix its structure, stance, and bloat. For this blind evaluation, do not use tools or read any
files: all allowed context is included in this prompt, and the human counterpart is the withheld
answer key. Return only the complete rewritten Markdown document.

=== DOCUMENT TO REWRITE ===
$(cat "$source_snapshot")" "$run_dir/agent-trace.jsonl" >"$candidate_file"
  fi

  judge "$(cat "$JUDGE")

Rubric:
$(cat "$RUBRIC")

=== DOC A ===
$(cat "$candidate_file")

=== DOC B ===
$(cat "$reference_file")

Run Mode A. Output ONLY the JSON." | style_eval_normalize_json >"$judgment_file"
  style_eval_validate_pairwise_json "$judgment_file"

  printf 'candidate: %s\njudgment: %s\n' "$candidate_file" "$judgment_file"
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
  rewrite) rewrite ;;
  *) echo "usage: run-eval.sh {calibrate | score FILE | rewrite}"; exit 1 ;;
esac
