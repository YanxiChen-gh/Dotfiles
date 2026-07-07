#!/usr/bin/env bash
# PR-style eval. Uses `claude -p` headless as the engine. Three flows: authoring, review, simplify.
#
#   ./run-eval.sh clean FILE [--flow simplify]   # run the pre-handoff cleaner on a diff/draft
#   ./run-eval.sh score FILE --flow authoring     # single-artifact rubric score
#   ./run-eval.sh simplify-calibrate              # recall of the cleaner vs real human edits
#
# The style specs are authoritative: ../pr-authoring.md and ../review-tone.md. The judge/cleaner
# read them plus rubric.md. Calibration uses corpus/simplify/human/cleanup-examples.md (real
# before->after cleanup commits) as the answer key.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/.."
JUDGE="$HERE/judge.md"
CLEANER="$ROOT/simplify-cleaner.md"
RUBRIC="$ROOT/rubric.md"
CORPUS="$HERE/corpus"

ask() { claude -p "$1" --output-format text; }

clean() { # $1 = file (diff or draft)
  ask "$(cat "$CLEANER")

rubric:
$(cat "$RUBRIC")

pr-authoring guide:
$(cat "$ROOT/pr-authoring.md")

=== DRAFT / DIFF TO CLEAN ===
$(cat "$1")"
}

score() { # $1 = file, $2 = flow
  ask "$(cat "$JUDGE")

Flow: $2
rubric:
$(cat "$RUBRIC")

=== ARTIFACT ===
$(cat "$1")

Run Mode B for flow '$2'. Output ONLY the JSON."
}

# Feed each cleanup example's BEFORE to the cleaner, then grade recall against its AFTER.
simplify_calibrate() {
  local ex="$CORPUS/simplify/human/cleanup-examples.md"
  ask "$(cat "$JUDGE")

You are running Mode C over every example in the calibration set below. For each example: read its
BEFORE, imagine a cleaner pass guided by the rubric + pr-authoring.md, then score recall against
the example's AFTER (the answer key). Output a JSON array, one object per example, plus a final
{\"mean_recall\": N}.

rubric:
$(cat "$RUBRIC")

pr-authoring guide (Comments / Tests / PR Descriptions):
$(cat "$ROOT/pr-authoring.md")

calibration set (BEFORE + AFTER + rule per example):
$(cat "$ex")"
}

case "${1:-}" in
  clean) clean "${2:?usage: run-eval.sh clean FILE}" ;;
  score)
    file="${2:?usage: run-eval.sh score FILE --flow FLOW}"; flow="authoring"
    [ "${3:-}" = "--flow" ] && flow="${4:?flow required}"
    score "$file" "$flow" ;;
  simplify-calibrate) simplify_calibrate ;;
  *) echo "usage: run-eval.sh {clean FILE | score FILE --flow FLOW | simplify-calibrate}"; exit 1 ;;
esac
