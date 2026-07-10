#!/usr/bin/env bash
# PR-style eval. Candidate generation and judging use separate engines.
#
#   ./run-eval.sh clean FILE [--flow simplify]   # run the pre-handoff cleaner on a diff/draft
#   ./run-eval.sh score FILE --flow authoring    # single-artifact rubric score
#   ./run-eval.sh simplify-calibrate [CORPUS]    # blind cleaner recall vs real human edits
#   ./run-eval.sh description-calibrate          # blind cleaner recall on PR-description revisions
#   ./run-eval.sh authoring-calibrate PAIR.json  # compare an initial PR body with its last author revision
#
# The style specs are authoritative: ../pr-authoring.md and ../review-tone.md. The judge/cleaner
# read them plus rubric.md. Calibration uses real before->after cleanup commits as the answer key.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/.."
JUDGE="$HERE/judge.md"
# The cleaner IS the real simplify-pr skill agents use - the eval validates that, not a stand-in.
CLEANER="${SIMPLIFY_PR_SKILL:-$HOME/dotfiles/claude/skills/simplify-pr/SKILL.md}"
RUBRIC="$ROOT/rubric.md"
AUTHOR_GUIDE="$ROOT/../pr-authoring.md"
AUTHOR_EXAMPLES="$ROOT/../pr-examples.md"
ENGINE="$HERE/../../style-eval-engine.sh"
# Corpus + results hold internal content and live in the PRIVATE data repo, not here.
DATA="${STYLE_HARNESS_DATA:-$HOME/style-harness-data}"
CORPUS="$DATA/pr-style/corpus"
RESULTS="$DATA/pr-style/results"
if [ ! -d "$CORPUS" ]; then
  echo "corpus not found at $CORPUS - clone the private data repo (see ../rubric.md) or set STYLE_HARNESS_DATA" >&2
  exit 1
fi
mkdir -p "$RESULTS"
# shellcheck source=claude/style-eval-engine.sh
source "$ENGINE"

agent() { style_eval_engine agent "$1" "${2:-}"; }
judge() { style_eval_engine judge "$1"; }

clean() { # $1 = file (diff or draft)
  agent "$(cat "$CLEANER")

rubric:
$(cat "$RUBRIC")

pr-authoring guide:
$(cat "$AUTHOR_GUIDE")

=== DRAFT / DIFF TO CLEAN ===
$(cat "$1")"
}

score() { # $1 = file, $2 = flow
  judge "$(cat "$JUDGE")

Flow: $2
rubric:
$(cat "$RUBRIC")

=== ARTIFACT ===
$(cat "$1")

Run Mode B for flow '$2'. Output ONLY the JSON."
}

# Generate the cleaner output first, freeze it, then let the judge compare it with AFTER.
# Optional $1: corpus file (default seed set); use a held-out batch for generalization.
simplify_calibrate() {
  local ex="${1:-$CORPUS/simplify/human/cleanup-examples.md}"
  local benchmark="${2:-simplify}"
  [ -f "$ex" ] || ex="$CORPUS/simplify/human/$ex"
  [ -f "$ex" ] || { echo "corpus file not found: $ex" >&2; return 1; }
  style_eval_require_jq

  local run_dir blind_file candidate_file judgment_file answer_key_file
  run_dir="$(style_eval_run_dir "$RESULTS" "$benchmark")"
  blind_file="$run_dir/blind-input.md"
  candidate_file="$run_dir/candidate.md"
  judgment_file="$run_dir/judgment.json"
  answer_key_file="$run_dir/answer-key.md"
  cp "$ex" "$answer_key_file"
  style_eval_blind_before "$answer_key_file" >"$blind_file"
  style_eval_write_metadata "$run_dir" "$benchmark" "$answer_key_file" "$CLEANER" "$AUTHOR_GUIDE" "$AUTHOR_EXAMPLES" "$RUBRIC" "$JUDGE"

  if [ -n "${EVAL_CANDIDATE:-}" ]; then
    [ -f "$EVAL_CANDIDATE" ] || { echo "candidate not found: $EVAL_CANDIDATE" >&2; return 1; }
    cp "$EVAL_CANDIDATE" "$candidate_file"
    printf 'candidate_source=%s\n' "$EVAL_CANDIDATE" >>"$run_dir/metadata.txt"
    printf 'candidate_source_sha256=%s\n' "$(sha256sum "$EVAL_CANDIDATE" | cut -d' ' -f1)" >>"$run_dir/metadata.txt"
  else
    agent "$(cat "$CLEANER")

pr-authoring guide:
$(cat "$AUTHOR_GUIDE")

worked examples:
$(cat "$AUTHOR_EXAMPLES")

You are the cleaner under evaluation. For every numbered example below, inspect only its BEFORE
material and propose the exact cuts or tightening you would make. Do not use tools or read files;
the text below is the complete allowed input. Return a numbered, concrete edit report. Do not grade
yourself and do not speculate about an unseen answer key.

=== BLIND INPUT ===
$(cat "$blind_file")" "$run_dir/agent-trace.jsonl" >"$candidate_file"
  fi

  judge "$(cat "$JUDGE")

You are the evaluator, not the cleaner. The candidate was frozen before this call and did not see
the answer key. Run Mode C for every numbered example. Only edits whose BEFORE material appears in
the blind input are scoreable; put answer-key edits without corresponding BEFORE material in an
unscored array, not missed. Enforce recall = caught / (caught + missed). Output one JSON object with
an examples array of Mode C objects (each also has an example number and unscored array) plus
mean_recall and load_bearing_overreach_count. Output JSON only.

rubric:
$(cat "$RUBRIC")

pr-authoring guide (Comments / Tests / PR Descriptions):
$(cat "$AUTHOR_GUIDE")

=== FROZEN CLEANER OUTPUT ===
$(cat "$candidate_file")

=== ANSWER KEY (BEFORE + AFTER) ===
$(cat "$answer_key_file")" | style_eval_normalize_json >"$judgment_file"
  style_eval_validate_simplify_json "$judgment_file"

  printf 'candidate: %s\njudgment: %s\n' "$candidate_file" "$judgment_file"
}

authoring_calibrate() {
  local pair="${1:?usage: run-eval.sh authoring-calibrate PAIR.json}"
  [ -f "$pair" ] || { echo "pair not found: $pair" >&2; return 1; }
  style_eval_require_jq

  local number candidate reference A B reference_slot prompt out winner run_dir pair_snapshot
  number="$(jq -er '.number' "$pair")"
  run_dir="$(style_eval_run_dir "$RESULTS" "authoring-revision-$number")"
  pair_snapshot="$run_dir/pair.json"
  cp "$pair" "$pair_snapshot"
  candidate="$(jq -er '.candidate.body' "$pair_snapshot")"
  reference="$(jq -er '.reference.body' "$pair_snapshot")"
  if [ $((10#$number % 2)) -eq 0 ]; then
    A="$reference"; B="$candidate"; reference_slot=A
  else
    A="$candidate"; B="$reference"; reference_slot=B
  fi
  style_eval_write_metadata "$run_dir" "authoring-revision-$number" "$pair_snapshot" "$AUTHOR_GUIDE" "$RUBRIC" "$JUDGE"
  printf 'reference_slot=%s\n' "$reference_slot" >>"$run_dir/metadata.txt"

  prompt="$(cat "$JUDGE")

Flow: authoring
rubric:
$(cat "$RUBRIC")

pr-authoring guide:
$(cat "$AUTHOR_GUIDE")

=== ARTIFACT A ===
$A

=== ARTIFACT B ===
$B

Run Mode A. Output ONLY the JSON."
  out="$(judge "$prompt" | style_eval_normalize_json)"
  winner="$(printf '%s\n' "$out" | jq -er '.winner')"
  if [ "$winner" = "$reference_slot" ]; then
    echo "PR $number: PASS (chose last author revision)"
  else
    echo "PR $number: FAIL (chose initial revision)"
  fi
  printf '%s\n' "$out" >"$run_dir/judgment.json"
  style_eval_validate_pairwise_json "$run_dir/judgment.json"
  printf 'judgment: %s\n' "$run_dir/judgment.json"
}

case "${1:-}" in
  clean) clean "${2:?usage: run-eval.sh clean FILE}" ;;
  score)
    file="${2:?usage: run-eval.sh score FILE --flow FLOW}"; flow="authoring"
    [ "${3:-}" = "--flow" ] && flow="${4:?flow required}"
    score "$file" "$flow" ;;
  simplify-calibrate) simplify_calibrate "${2:-}" ;;
  description-calibrate) simplify_calibrate "$CORPUS/simplify/human/description-pairs.md" simplify-description ;;
  authoring-calibrate) authoring_calibrate "${2:?usage: run-eval.sh authoring-calibrate PAIR.json}" ;;
  *) echo "usage: run-eval.sh {clean FILE | score FILE --flow FLOW | simplify-calibrate [CORPUS] | description-calibrate | authoring-calibrate PAIR.json}"; exit 1 ;;
esac
