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
