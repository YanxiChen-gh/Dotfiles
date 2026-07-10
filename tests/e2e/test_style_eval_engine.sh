#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-style-eval-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP"

cat >"$TMP/corpus.md" <<'EOF'
## 1. Inline input
BEFORE: keep this first line
and this continuation
AFTER: hidden

## 2. Annotated input
BEFORE (the relevant block):
keep this block
AFTER (human edit): hidden
EOF

cat >"$TMP/expected.md" <<'EOF'
## Example 1
BEFORE:
keep this first line
and this continuation
## Example 2
BEFORE:
keep this block
EOF

bash -c 'source "$1"; style_eval_blind_before "$2"' _ \
  "$ROOT/claude/style-eval-engine.sh" "$TMP/corpus.md" >"$TMP/actual.md"
cmp "$TMP/expected.md" "$TMP/actual.md"

mkdir -p "$TMP/repo"
git -C "$TMP/repo" init -q
printf 'tracked\n' >"$TMP/repo/tracked.txt"
git -C "$TMP/repo" add tracked.txt
GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com \
  git -C "$TMP/repo" commit -qm initial
clean_hash=$(bash -c 'source "$1"; style_eval_harness_state_sha256 "$2"' _ \
  "$ROOT/claude/style-eval-engine.sh" "$TMP/repo")
printf 'untracked\n' >"$TMP/repo/untracked.txt"
dirty_hash=$(bash -c 'source "$1"; style_eval_harness_state_sha256 "$2"' _ \
  "$ROOT/claude/style-eval-engine.sh" "$TMP/repo")
[ "$clean_hash" != "$dirty_hash" ] || {
  echo "FAIL: untracked file did not change harness state hash" >&2
  exit 1
}

cat >"$TMP/simplify-valid.json" <<'EOF'
{"examples":[{"example":1,"caught":["a"],"missed":["b"],"overreach":[],"unscored":[],"recall":0.5,"cited_right_rule":true},{"example":2,"caught":["a"],"missed":[],"overreach":[],"unscored":[],"recall":1.0,"cited_right_rule":true}],"mean_recall":0.75,"load_bearing_overreach_count":0}
EOF
cat >"$TMP/simplify-invalid.json" <<'EOF'
{"examples":[{"example":1,"caught":["a"],"missed":["b"],"overreach":[],"unscored":[],"recall":1.0,"cited_right_rule":true}],"mean_recall":1.0,"load_bearing_overreach_count":0.5}
EOF
bash -c 'source "$1"; style_eval_validate_simplify_json "$2"' _ \
  "$ROOT/claude/style-eval-engine.sh" "$TMP/simplify-valid.json"
if bash -c 'source "$1"; style_eval_validate_simplify_json "$2"' _ \
  "$ROOT/claude/style-eval-engine.sh" "$TMP/simplify-invalid.json"; then
  echo "FAIL: accepted invalid simplify judgment" >&2
  exit 1
fi

cat >"$TMP/benchmark-manifest.json" <<'EOF'
{"cases":[{"id":"case-a","flow":"simplify","scoring":{"expected_edits":["cut narration","remove table stakes"],"must_preserve":["rollback constraint"]}},{"id":"case-b","flow":"authoring","scoring":{"reference":"after","reasons":["states the root cause"]}}]}
EOF
cat >"$TMP/manifest-judgment-valid.json" <<'EOF'
{"examples":[{"case_id":"case-a","caught":["cut narration"],"missed":["remove table stakes"],"overreach":["rollback constraint"],"load_bearing_overreach":["rollback constraint"],"unscored":[],"recall":0.5,"cited_right_rule":true}],"mean_recall":0.5,"load_bearing_overreach_count":1}
EOF
bash -c 'source "$1"; style_eval_validate_manifest_simplify_json "$2" "$3"' _ \
  "$ROOT/claude/style-eval-engine.sh" "$TMP/manifest-judgment-valid.json" "$TMP/benchmark-manifest.json"

for mutation in duplicate extra missing recall mean load-bearing; do
  case "$mutation" in
    duplicate) filter='.examples += [.examples[0]]' ;;
    extra) filter='.examples += [(.examples[0] | .case_id = "extra")]' ;;
    missing) filter='.examples = []' ;;
    recall) filter='.examples[0].recall = 1' ;;
    mean) filter='.mean_recall = 1' ;;
    load-bearing) filter='.load_bearing_overreach_count = 0' ;;
  esac
  jq "$filter" "$TMP/manifest-judgment-valid.json" >"$TMP/manifest-judgment-$mutation.json"
  if bash -c 'source "$1"; style_eval_validate_manifest_simplify_json "$2" "$3"' _ \
    "$ROOT/claude/style-eval-engine.sh" "$TMP/manifest-judgment-$mutation.json" "$TMP/benchmark-manifest.json"; then
    echo "FAIL: accepted manifest judgment with $mutation case-set/arithmetic error" >&2
    exit 1
  fi
done

cat >"$TMP/authoring-summary-valid.json" <<'EOF'
{"flow":"authoring","total":1,"reference_wins":1,"cases":[{"case_id":"case-b","winner":"A","reference_slot":"A","reference_won":true,"expected_reasons":["states the root cause"]}]}
EOF
cat >"$TMP/pairwise-valid.json" <<'EOF'
{"winner":"A","confidence":1,"reasons":["direct"],"anti_tells_in_loser":["narration"]}
EOF
bash -c 'source "$1"; style_eval_validate_pairwise_json "$2"' _ \
  "$ROOT/claude/style-eval-engine.sh" "$TMP/pairwise-valid.json"
for field in reasons anti_tells_in_loser; do
  jq --arg field "$field" '.[$field] = [""]' "$TMP/pairwise-valid.json" >"$TMP/pairwise-invalid-$field.json"
  if bash -c 'source "$1"; style_eval_validate_pairwise_json "$2"' _ \
    "$ROOT/claude/style-eval-engine.sh" "$TMP/pairwise-invalid-$field.json"; then
    echo "FAIL: accepted malformed pairwise $field" >&2
    exit 1
  fi
done
bash -c 'source "$1"; style_eval_validate_manifest_authoring_summary "$2" "$3"' _ \
  "$ROOT/claude/style-eval-engine.sh" "$TMP/authoring-summary-valid.json" "$TMP/benchmark-manifest.json"

for mutation in duplicate extra missing total reference-wins inconsistent-winner expected-reasons malformed-expected-reasons; do
  case "$mutation" in
    duplicate) filter='.cases += [.cases[0]] | .total = 2 | .reference_wins = 2' ;;
    extra) filter='.cases += [(.cases[0] | .case_id = "extra")] | .total = 2 | .reference_wins = 2' ;;
    missing) filter='.cases = [] | .total = 0 | .reference_wins = 0' ;;
    total) filter='.total = 2' ;;
    reference-wins) filter='.reference_wins = 0' ;;
    inconsistent-winner) filter='.cases[0].winner = "B"' ;;
    expected-reasons) filter='.cases[0].expected_reasons = ["different reason"]' ;;
    malformed-expected-reasons) filter='.cases[0].expected_reasons = [""]' ;;
  esac
  jq "$filter" "$TMP/authoring-summary-valid.json" >"$TMP/authoring-summary-$mutation.json"
  if bash -c 'source "$1"; style_eval_validate_manifest_authoring_summary "$2" "$3"' _ \
    "$ROOT/claude/style-eval-engine.sh" "$TMP/authoring-summary-$mutation.json" "$TMP/benchmark-manifest.json"; then
    echo "FAIL: accepted authoring summary with $mutation case-set/arithmetic error" >&2
    exit 1
  fi
done
