#!/usr/bin/env bash
# PR-style eval. Simplify generation/judging use separate engines; held-out authoring is a blind
# pairwise preference task performed by AGENT_ENGINE/AGENT_MODEL with tools disabled.
#
#   ./run-eval.sh clean FILE [--flow simplify]   # run the pre-handoff cleaner on a diff/draft
#   ./run-eval.sh score FILE --flow authoring    # single-artifact rubric score
#   ./run-eval.sh simplify-calibrate [CORPUS]    # blind cleaner recall vs real human edits
#   ./run-eval.sh description-calibrate          # blind cleaner recall on PR-description revisions
#   ./run-eval.sh authoring-calibrate PAIR.json  # compare an initial PR body with its last author revision
#   ./run-eval.sh description-heldout MANIFEST --flow simplify|authoring # authoring tests AGENT_*
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
BENCHMARK="$HERE/pr-description-benchmark.sh"
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
agent_file() { style_eval_engine_file agent "$1" "${2:-}"; }
judge() { style_eval_engine judge "$1"; }
judge_file() { style_eval_engine_file judge "$1" "${2:-}"; }

capture_description_manifest_provenance() {
  local manifest="$1" flow="$2"
  DESCRIPTION_BENCHMARK_MANIFEST_PATH="$(realpath -e "$manifest")"
  DESCRIPTION_BENCHMARK_MANIFEST_SHA256="$(sha256sum "$manifest" | cut -d' ' -f1)"
  DESCRIPTION_DATA_REPO_ROOT="$(git -C "$(dirname "$manifest")" rev-parse --show-toplevel)"
  DESCRIPTION_DATA_REPO_GIT_SHA="$(git -C "$DESCRIPTION_DATA_REPO_ROOT" rev-parse HEAD)"
  if [ -n "$(git -C "$DESCRIPTION_DATA_REPO_ROOT" status --short)" ]; then
    DESCRIPTION_DATA_REPO_GIT_DIRTY=true
  else
    DESCRIPTION_DATA_REPO_GIT_DIRTY=false
  fi
  DESCRIPTION_DATA_REPO_GIT_STATE_SHA256="$(style_eval_harness_state_sha256 "$DESCRIPTION_DATA_REPO_ROOT")"
  DESCRIPTION_BENCHMARK_CASE_IDS="$(jq -r --arg flow "$flow" '[.cases[] | select(.flow == $flow) | .id] | join(",")' "$manifest")"
}

append_description_manifest_metadata() {
  local metadata="$1"
  cat >>"$metadata" <<EOF
data_repo_git_sha=$DESCRIPTION_DATA_REPO_GIT_SHA
data_repo_git_dirty=$DESCRIPTION_DATA_REPO_GIT_DIRTY
data_repo_git_state_sha256=$DESCRIPTION_DATA_REPO_GIT_STATE_SHA256
benchmark_manifest_path=$DESCRIPTION_BENCHMARK_MANIFEST_PATH
benchmark_manifest_sha256=$DESCRIPTION_BENCHMARK_MANIFEST_SHA256
benchmark_case_ids=$DESCRIPTION_BENCHMARK_CASE_IDS
EOF
}

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

description_heldout_simplify() {
  local manifest="$1" benchmark_id benchmark_version run_dir materialized candidate_file judgment_file
  local agent_prompt_file judge_prompt_file
  benchmark_id="$(jq -er '.benchmark.id' "$manifest")"
  benchmark_version="$(jq -er '.benchmark.version' "$manifest")"
  capture_description_manifest_provenance "$manifest" simplify
  run_dir="$(style_eval_run_dir "$RESULTS" "description-heldout-$benchmark_id-v$benchmark_version-simplify")"
  materialized="$run_dir/materialized"
  candidate_file="$run_dir/candidate.md"
  judgment_file="$run_dir/judgment.json"
  agent_prompt_file="$run_dir/agent-prompt.md"
  judge_prompt_file="$run_dir/judge-prompt.md"
  "$BENCHMARK" materialize "$manifest" "$materialized" simplify
  [ -f "$materialized/simplify/blind-input.md" ] || {
    echo "manifest has no simplify cases" >&2
    return 1
  }
  {
    cat "$CLEANER"
    printf '\n\npr-authoring guide:\n'
    cat "$AUTHOR_GUIDE"
    printf '\n\nworked examples:\n'
    cat "$AUTHOR_EXAMPLES"
    cat <<'EOF'


You are the cleaner under evaluation. Inspect only the complete BEFORE bodies below. For every
case ID, propose the exact cuts or tightening you would make. Do not use tools or read files; this
prompt is the complete allowed input. Return a concrete edit report keyed by case ID. Do not grade
yourself and do not speculate about the withheld answer key.

=== BLIND INPUT ===
EOF
    cat "$materialized/simplify/blind-input.md"
  } >"$agent_prompt_file"

  if [ -n "${EVAL_CANDIDATE:-}" ]; then
    [ -f "$EVAL_CANDIDATE" ] || { echo "candidate not found: $EVAL_CANDIDATE" >&2; return 1; }
    cp "$EVAL_CANDIDATE" "$candidate_file"
  else
    agent_file "$agent_prompt_file" "$run_dir/agent-trace.jsonl" >"$candidate_file"
  fi

  {
    cat "$JUDGE"
    cat <<'EOF'


You are the evaluator, not the cleaner. The candidate was frozen before this call and did not see
the answer key. Run Mode C for every case. Output one JSON object with an examples array and the
aggregate fields below. Every example must have exactly these fields: case_id, caught, missed,
overreach, load_bearing_overreach, unscored, recall, and cited_right_rule. caught plus missed must
partition EXPECTED EDITS using those strings verbatim. load_bearing_overreach uses matching MUST
PRESERVE strings verbatim and must also appear in overreach. Other overreach and unscored entries
may be concise free text. Evaluate each MUST PRESERVE claim only inside the proposed rewritten description.
Explicitly exclude the change ledger, cuts, explanations, and all other commentary. A claim mentioned
only in commentary is lost. Count a load-bearing overreach when the claim disappears or is materially
weakened in the proposed rewritten description. Enforce recall = caught / (caught + missed), mean_recall
as the arithmetic mean, and load_bearing_overreach_count as the total number of
load_bearing_overreach entries. Output JSON only.

rubric:
EOF
    cat "$RUBRIC"
    printf '\n\npr-authoring guide (Comments / Tests / PR Descriptions):\n'
    cat "$AUTHOR_GUIDE"
    printf '\n\n=== FROZEN CLEANER OUTPUT ===\n'
    cat "$candidate_file"
    printf '\n\n=== ANSWER KEY ===\n'
    cat "$materialized/simplify/answer-key.md"
  } >"$judge_prompt_file"

  style_eval_write_metadata "$run_dir" "description-heldout-$benchmark_id-v$benchmark_version-simplify" \
    "$materialized/manifest.json" "$materialized/simplify/blind-input.md" \
    "$materialized/simplify/answer-key.md" "$CLEANER" "$AUTHOR_GUIDE" "$AUTHOR_EXAMPLES" "$RUBRIC" "$JUDGE" \
    "$agent_prompt_file" "$judge_prompt_file"
  append_description_manifest_metadata "$run_dir/metadata.txt"
  if [ -n "${EVAL_CANDIDATE:-}" ]; then
    printf 'candidate_source=%s\n' "$EVAL_CANDIDATE" >>"$run_dir/metadata.txt"
    printf 'candidate_source_sha256=%s\n' "$(sha256sum "$EVAL_CANDIDATE" | cut -d' ' -f1)" >>"$run_dir/metadata.txt"
  fi

  judge_file "$judge_prompt_file" | style_eval_normalize_json >"$judgment_file"
  style_eval_validate_manifest_simplify_json "$judgment_file" "$materialized/manifest.json"
  printf 'candidate: %s\njudgment: %s\n' "$candidate_file" "$judgment_file"
}

description_heldout_authoring() {
  local manifest="$1" benchmark_id benchmark_version run_dir materialized judgments_dir
  local case_dir case_id case_index=0 artifact_a artifact_b reference_slot prompt_file trace_file
  local raw_judgment judgment_file winner expected_reasons
  benchmark_id="$(jq -er '.benchmark.id' "$manifest")"
  benchmark_version="$(jq -er '.benchmark.version' "$manifest")"
  capture_description_manifest_provenance "$manifest" authoring
  run_dir="$(style_eval_run_dir "$RESULTS" "description-heldout-$benchmark_id-v$benchmark_version-authoring" agent)"
  materialized="$run_dir/materialized"
  judgments_dir="$run_dir/judgments"
  "$BENCHMARK" materialize "$manifest" "$materialized" authoring
  [ -d "$materialized/authoring" ] || {
    echo "manifest has no authoring cases" >&2
    return 1
  }
  mkdir "$judgments_dir"
  style_eval_write_metadata "$run_dir" "description-heldout-$benchmark_id-v$benchmark_version-authoring" \
    "$materialized/manifest.json" "$AUTHOR_GUIDE" "$RUBRIC" "$JUDGE"
  append_description_manifest_metadata "$run_dir/metadata.txt"
  cat >>"$run_dir/metadata.txt" <<EOF
decision_role=agent
decision_engine=${AGENT_ENGINE:-claude}
decision_model=${AGENT_MODEL:-configured-default}
judge_used=false
EOF

  while IFS= read -r case_dir; do
    [ -d "$case_dir" ] || continue
    case_id="$(jq -er '.id' "$case_dir/case.json")"
    if [ $((case_index % 2)) -eq 0 ]; then
      artifact_a="$case_dir/after.md"
      artifact_b="$case_dir/before.md"
      reference_slot=A
    else
      artifact_a="$case_dir/before.md"
      artifact_b="$case_dir/after.md"
      reference_slot=B
    fi
    expected_reasons="$(jq -c '.scoring.reasons' "$case_dir/case.json")"
    prompt_file="$judgments_dir/$case_id.prompt.md"
    trace_file="$judgments_dir/$case_id.agent-trace.jsonl"
    raw_judgment="$judgments_dir/$case_id.raw.json"
    judgment_file="$judgments_dir/$case_id.json"
    {
      cat "$JUDGE"
      printf '\n\nFlow: authoring\nrubric:\n'
      cat "$RUBRIC"
      printf '\n\npr-authoring guide:\n'
      cat "$AUTHOR_GUIDE"
      printf '\n\nThis is a blind pairwise preference task. Do not use tools or read files; this prompt is the complete allowed input.\n'
      printf '\n=== ARTIFACT A ===\n'
      cat "$artifact_a"
      printf '\n=== ARTIFACT B ===\n'
      cat "$artifact_b"
      printf '\nRun Mode A. Output ONLY the JSON.\n'
    } >"$prompt_file"
    agent_file "$prompt_file" "$trace_file" | style_eval_normalize_json >"$raw_judgment"
    style_eval_validate_pairwise_json "$raw_judgment"
    winner="$(jq -er '.winner' "$raw_judgment")"
    jq --arg case_id "$case_id" --arg reference_slot "$reference_slot" --argjson expected_reasons "$expected_reasons" \
      --argjson reference_won "$([ "$winner" = "$reference_slot" ] && echo true || echo false)" \
      '. + {case_id: $case_id, reference_slot: $reference_slot, reference_won: $reference_won, expected_reasons: $expected_reasons}' \
      "$raw_judgment" >"$judgment_file"
    rm "$raw_judgment"
    if [ "$winner" = "$reference_slot" ]; then
      printf '%s: PASS (chose after revision)\n' "$case_id"
    else
      printf '%s: FAIL (chose before revision)\n' "$case_id"
    fi
    case_index=$((case_index + 1))
  done < <(printf '%s\n' "$materialized"/authoring/* | LC_ALL=C sort)

  jq -s --slurpfile manifest "$materialized/manifest.json" '
    {
      benchmark: $manifest[0].benchmark,
      flow: "authoring",
      total: length,
      reference_wins: (map(select(.reference_won)) | length),
      cases: map({case_id, winner, reference_slot, reference_won, expected_reasons})
    }
  ' "$judgments_dir"/*.json >"$run_dir/summary.json"
  style_eval_validate_manifest_authoring_summary "$run_dir/summary.json" "$materialized/manifest.json"
  printf 'judgments: %s\nsummary: %s\n' "$judgments_dir" "$run_dir/summary.json"
}

description_heldout() {
  local manifest="${1:?usage: run-eval.sh description-heldout MANIFEST --flow simplify|authoring}"
  local flag="${2:-}" flow="${3:-}"
  [ "$flag" = --flow ] || { echo "--flow simplify|authoring is required" >&2; return 1; }
  [ -f "$manifest" ] || { echo "manifest not found: $manifest" >&2; return 1; }
  case "$flow" in
    simplify|authoring) ;;
    *) echo "invalid flow: $flow (expected simplify or authoring)" >&2; return 1 ;;
  esac
  style_eval_require_jq
  "$BENCHMARK" validate "$manifest"
  jq -e --arg flow "$flow" '[.cases[] | select(.flow == $flow)] | length > 0' "$manifest" >/dev/null || {
    echo "manifest has no $flow cases" >&2
    return 1
  }
  case "$flow" in
    simplify) description_heldout_simplify "$manifest" ;;
    authoring) description_heldout_authoring "$manifest" ;;
  esac
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
  description-heldout) description_heldout "${2:-}" "${3:-}" "${4:-}" ;;
  *) echo "usage: run-eval.sh {clean FILE | score FILE --flow FLOW | simplify-calibrate [CORPUS] | description-calibrate | authoring-calibrate PAIR.json | description-heldout MANIFEST --flow simplify|authoring}"; exit 1 ;;
esac
