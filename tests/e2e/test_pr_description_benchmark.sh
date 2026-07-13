#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BENCHMARK="$ROOT/claude/pr-style/eval/pr-description-benchmark.sh"
HARVEST="$ROOT/claude/pr-style/eval/harvest-pr-description-data.sh"
TMP="${TMPDIR:-/tmp}/dotfiles-e2e-pr-description-benchmark-$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/repo/pr-style/corpus/evidence/pr-description-revisions" "$TMP/bodies" "$TMP/home"
git -C "$TMP/repo" init -q

printf '## Changes\r\n\r\nIn foo.ts, add cache.\r\n' >"$TMP/bodies/revision-1.md"
printf '## Changes\n\nCache policy changes now fail type checking.\n' >"$TMP/bodies/revision-2.md"
printf '## Changes\n\nMake cache policy structural so renames fail type checking.\n' >"$TMP/bodies/revision-3.md"
printf '## Changes\n\nMake cache policy structural. Renames now fail type checking.\n' >"$TMP/bodies/revision-4.md"

EVIDENCE_REL=pr-style/corpus/evidence/pr-description-revisions/42.json
EVIDENCE="$TMP/repo/$EVIDENCE_REL"
jq -n \
  --rawfile one "$TMP/bodies/revision-1.md" \
  --rawfile two "$TMP/bodies/revision-2.md" \
  --rawfile three "$TMP/bodies/revision-3.md" \
  --rawfile four "$TMP/bodies/revision-4.md" '
  {
    schema_version: 1,
    repository: "Example/widgets",
    number: 42,
    title: "Make cache policy structural",
    url: "https://example.invalid/42",
    state: "MERGED",
    is_draft: false,
    created_at: "2026-01-01T00:00:00Z",
    closed_at: "2026-01-03T00:00:00Z",
    merged_at: "2026-01-03T00:00:00Z",
    candidate: {source: "earliest_author_revision", edited_at: "2026-01-01T00:00:00Z", body: $one, is_creation_revision: true, agent_authorship: "unverified"},
    reference: {source: "last_author_revision", edited_at: "2026-01-04T00:00:00Z", body: $four},
    author_revisions: [
      {edited_at: "2026-01-01T00:00:00Z", body: $one},
      {edited_at: "2026-01-02T00:00:00Z", body: $two},
      {edited_at: "2026-01-03T00:00:00Z", body: $three},
      {edited_at: "2026-01-04T00:00:00Z", body: $four}
    ],
    all_revisions: [
      {edited_at: "2026-01-01T00:00:00Z", editor: "writer", body: $one},
      {edited_at: "2026-01-02T00:00:00Z", editor: "writer", body: $two},
      {edited_at: "2026-01-03T00:00:00Z", editor: "writer", body: $three},
      {edited_at: "2026-01-04T00:00:00Z", editor: "writer", body: $four}
    ],
    current_body: $four,
    non_author_editors: [],
    current_body_matches_reference: true,
    history_complete: true
  }
' >"$EVIDENCE"

evidence_sha=$(sha256sum "$EVIDENCE" | cut -d' ' -f1)
one_sha=$(sha256sum "$TMP/bodies/revision-1.md" | cut -d' ' -f1)
two_sha=$(sha256sum "$TMP/bodies/revision-2.md" | cut -d' ' -f1)
three_sha=$(sha256sum "$TMP/bodies/revision-3.md" | cut -d' ' -f1)
four_sha=$(sha256sum "$TMP/bodies/revision-4.md" | cut -d' ' -f1)
MANIFEST="$TMP/repo/manifest.json"
jq -n \
  --arg evidence_path "$EVIDENCE_REL" \
  --arg evidence_sha "$evidence_sha" \
  --arg one_sha "$one_sha" \
  --arg two_sha "$two_sha" \
  --arg three_sha "$three_sha" \
  --arg four_sha "$four_sha" '
  {
    schema_version: 1,
    benchmark: {
      id: "pr-description-heldout",
      version: 1,
      split: "heldout",
      frozen_at: "2026-01-05T00:00:00Z",
      repository: "Example/widgets",
      author: "writer",
      selection_note: "Consecutive revisions with independently reviewable style edits."
    },
    cases: [
      {
        id: "simplify-42-r1-r2",
        flow: "simplify",
        pr_number: 42,
        evidence_path: $evidence_path,
        evidence_sha256: $evidence_sha,
        before: {author_revision: 1, edited_at: "2026-01-01T00:00:00Z", body_sha256: $one_sha},
        after: {author_revision: 2, edited_at: "2026-01-02T00:00:00Z", body_sha256: $two_sha},
        scoring: {expected_edits: ["remove file-by-file narration"], must_preserve: ["cache policy behavior"]}
      },
      {
        id: "authoring-42-r2-r3",
        flow: "authoring",
        pr_number: 42,
        evidence_path: $evidence_path,
        evidence_sha256: $evidence_sha,
        before: {author_revision: 2, edited_at: "2026-01-02T00:00:00Z", body_sha256: $two_sha},
        after: {author_revision: 3, edited_at: "2026-01-03T00:00:00Z", body_sha256: $three_sha},
        scoring: {reference: "after", reasons: ["states the behavior directly"]}
      },
      {
        id: "authoring-42-r3-r4",
        flow: "authoring",
        pr_number: 42,
        evidence_path: $evidence_path,
        evidence_sha256: $evidence_sha,
        before: {author_revision: 3, edited_at: "2026-01-03T00:00:00Z", body_sha256: $three_sha},
        after: {author_revision: 4, edited_at: "2026-01-04T00:00:00Z", body_sha256: $four_sha},
        scoring: {reference: "after", reasons: ["tightens the sentence structure"]}
      }
    ]
  }
' >"$MANIFEST"

git -C "$TMP/repo" add .
GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com \
  git -C "$TMP/repo" commit -qm fixture

expect_invalid() {
  name=$1
  if "$BENCHMARK" validate "$TMP/repo/$name.json" >/dev/null 2>&1; then
    echo "FAIL: accepted invalid benchmark manifest: $name" >&2
    exit 1
  fi
}

mutate_invalid() {
  name=$1
  filter=$2
  jq "$filter" "$MANIFEST" >"$TMP/repo/$name.json"
  expect_invalid "$name"
}

"$BENCHMARK" validate "$MANIFEST"
"$BENCHMARK" materialize "$MANIFEST" "$TMP/materialized"
cmp "$TMP/bodies/revision-1.md" "$TMP/materialized/simplify/simplify-42-r1-r2/before.md"
cmp "$TMP/bodies/revision-2.md" "$TMP/materialized/simplify/simplify-42-r1-r2/after.md"
cmp "$TMP/bodies/revision-2.md" "$TMP/materialized/authoring/authoring-42-r2-r3/before.md"
cmp "$TMP/bodies/revision-3.md" "$TMP/materialized/authoring/authoring-42-r2-r3/after.md"
cmp "$TMP/bodies/revision-3.md" "$TMP/materialized/authoring/authoring-42-r3-r4/before.md"
cmp "$TMP/bodies/revision-4.md" "$TMP/materialized/authoring/authoring-42-r3-r4/after.md"
cmp "$MANIFEST" "$TMP/materialized/manifest.json"
grep -q '## Case simplify-42-r1-r2' "$TMP/materialized/simplify/blind-input.md"
grep -q 'EXPECTED EDITS:' "$TMP/materialized/simplify/answer-key.md"
if grep -q 'style_eval_blind_before' "$TMP/materialized/simplify/blind-input.md"; then
  echo "FAIL: materialized blind input contains a legacy extractor marker" >&2
  exit 1
fi
"$BENCHMARK" materialize "$MANIFEST" "$TMP/materialized-simplify" simplify
[ -d "$TMP/materialized-simplify/simplify" ] && [ ! -e "$TMP/materialized-simplify/authoring" ]
"$BENCHMARK" materialize "$MANIFEST" "$TMP/materialized-authoring" authoring
[ -d "$TMP/materialized-authoring/authoring" ] && [ ! -e "$TMP/materialized-authoring/simplify" ]
if "$BENCHMARK" materialize "$MANIFEST" "$TMP/materialized" >/dev/null 2>&1; then
  echo "FAIL: materialization overwrote an existing output directory" >&2
  exit 1
fi

mutate_invalid evidence-hash '.cases[0].evidence_sha256 = ("0" * 64)'
mutate_invalid body-hash '.cases[0].before.body_sha256 = ("0" * 64)'
mutate_invalid timestamp '.cases[0].before.edited_at = "2025-12-31T00:00:00Z"'
mutate_invalid index '.cases[0].before.author_revision = 3 | .cases[0].after.author_revision = 4'
mutate_invalid duplicate-id '.cases[1].id = .cases[0].id'
mutate_invalid duplicate-transition '.cases += [(.cases[0] | .id = "simplify-duplicate")]'
mutate_invalid cross-flow '.cases += [(.cases[0] | .id = "authoring-duplicate" | .flow = "authoring" | .scoring = {reference: "after", reasons: ["duplicate"]})]'
mutate_invalid non-consecutive '.cases[0].after.author_revision = 3 | .cases[0].after.edited_at = "2026-01-03T00:00:00Z" | .cases[0].after.body_sha256 = .cases[1].after.body_sha256'
mutate_invalid unsafe-path '.cases[0].evidence_path = "pr-style/corpus/evidence/pr-description-revisions/../42.json"'

mkdir -p "$TMP/fake-bin" "$TMP/harvest"
cat >"$TMP/fake-bin/claude" <<'EOF'
#!/bin/sh
set -eu
prompt=
json_output=false
for arg in "$@"; do
  [ "$arg" != json ] || json_output=true
  prompt=$arg
done
if [ -n "${FAKE_CAPTURE_DIR:-}" ] && [ "$json_output" = true ]; then
  capture_count=1
  [ ! -f "$FAKE_CAPTURE_DIR/count" ] || capture_count=$(($(cat "$FAKE_CAPTURE_DIR/count") + 1))
  printf '%s\n' "$capture_count" >"$FAKE_CAPTURE_DIR/count"
  cat >"$FAKE_CAPTURE_DIR/prompt-$capture_count.md"
  prompt=$(cat "$FAKE_CAPTURE_DIR/prompt-$capture_count.md")
  printf '%s\0' "$@" >"$FAKE_CAPTURE_DIR/args-$capture_count.bin"
fi
if [ "$prompt" = text ]; then
  if [ -n "${FAKE_CAPTURE_DIR:-}" ]; then
    capture_count=1
    [ ! -f "$FAKE_CAPTURE_DIR/count" ] || capture_count=$(($(cat "$FAKE_CAPTURE_DIR/count") + 1))
    printf '%s\n' "$capture_count" >"$FAKE_CAPTURE_DIR/count"
    cat >"$FAKE_CAPTURE_DIR/prompt-$capture_count.md"
    prompt=$(cat "$FAKE_CAPTURE_DIR/prompt-$capture_count.md")
    printf '%s\0' "$@" >"$FAKE_CAPTURE_DIR/args-$capture_count.bin"
  else
    prompt=$(cat)
  fi
fi
case "$prompt" in
  *'aggregate fields below'*)
    result='{"examples":[{"case_id":"simplify-42-r1-r2","caught":["remove file-by-file narration"],"missed":[],"overreach":[],"load_bearing_overreach":[],"unscored":[],"recall":1,"cited_right_rule":true}],"mean_recall":1,"load_bearing_overreach_count":0}'
    ;;
  *'Run Mode A.'*)
    result='{"winner":"A","confidence":1,"reasons":["direct"],"anti_tells_in_loser":["narration"]}'
    ;;
  *'--version'*) result='fake-claude 1.0' ;;
  *) result='simplify-42-r1-r2: remove file-by-file narration' ;;
esac
if [ "$json_output" = true ]; then
  jq -cn --arg result "$result" '{result: $result}'
else
  printf '%s\n' "$result"
fi
EOF
chmod +x "$TMP/fake-bin/claude"
manifest_path="$(realpath -e "$MANIFEST")"
manifest_sha="$(sha256sum "$MANIFEST" | cut -d' ' -f1)"
data_git_sha="$(git -C "$TMP/repo" rev-parse HEAD)"
data_dirty=true
pre_simplify_state="$(bash -c 'source "$1"; style_eval_harness_state_sha256 "$2"' _ \
  "$ROOT/claude/style-eval-engine.sh" "$TMP/repo")"
mkdir "$TMP/simplify-captures"
HOME="$TMP/home" PATH="$TMP/fake-bin:$PATH" STYLE_HARNESS_DATA="$TMP/repo" RUN_ID=simplify-test \
  FAKE_CAPTURE_DIR="$TMP/simplify-captures" \
  "$ROOT/claude/pr-style/eval/run-eval.sh" description-heldout "$MANIFEST" --flow simplify >/dev/null
simplify_run_dir=
for run_dir in "$TMP/repo/pr-style/results/runs"/simplify-test-*; do
  [ -d "$run_dir" ] || { echo "FAIL: simplify held-out run was not written" >&2; exit 1; }
  simplify_run_dir=$run_dir
  metadata="$run_dir/metadata.txt"
  [ -f "$metadata" ] || { echo "FAIL: simplify held-out metadata was not written" >&2; exit 1; }
  grep -Fqx "data_repo_git_sha=$data_git_sha" "$metadata"
  grep -Fqx "data_repo_git_dirty=$data_dirty" "$metadata"
  grep -Fqx "data_repo_git_state_sha256=$pre_simplify_state" "$metadata"
  grep -Fqx "benchmark_manifest_path=$manifest_path" "$metadata"
  grep -Fqx "benchmark_manifest_sha256=$manifest_sha" "$metadata"
  grep -Fqx 'benchmark_case_ids=simplify-42-r1-r2' "$metadata"
  for prompt_file in "$run_dir/agent-prompt.md" "$run_dir/judge-prompt.md"; do
    [ -f "$prompt_file" ] || { echo "FAIL: simplify prompt was not persisted: $prompt_file" >&2; exit 1; }
    source_key=$(awk -F= -v path="$prompt_file" '$1 ~ /^source_[0-9]+_path$/ && $2 == path { sub(/_path$/, "", $1); print $1; exit }' "$metadata")
    [ -n "$source_key" ] || { echo "FAIL: simplify prompt was not recorded as a metadata source: $prompt_file" >&2; exit 1; }
    grep -Fqx "${source_key}_sha256=$(sha256sum "$prompt_file" | cut -d' ' -f1)" "$metadata"
  done
  cmp "$run_dir/agent-prompt.md" "$TMP/simplify-captures/prompt-1.md"
  cmp "$run_dir/judge-prompt.md" "$TMP/simplify-captures/prompt-2.md"
  grep -Fq 'Evaluate each MUST PRESERVE claim only inside the proposed rewritten description.' "$run_dir/judge-prompt.md"
  grep -Fq 'Explicitly exclude the change ledger, cuts, explanations, and all other commentary.' "$run_dir/judge-prompt.md"
  grep -Fq 'only in commentary is lost.' "$run_dir/judge-prompt.md"
done
[ -n "$simplify_run_dir" ]

frozen_candidate="$simplify_run_dir/candidate.md"
PATH="$TMP/fake-bin:$PATH" STYLE_HARNESS_DATA="$TMP/repo" RUN_ID=simplify-rerun \
  EVAL_CANDIDATE="$frozen_candidate" \
  "$ROOT/claude/pr-style/eval/run-eval.sh" description-heldout "$MANIFEST" --flow simplify >/dev/null
for run_dir in "$TMP/repo/pr-style/results/runs"/simplify-rerun-*; do
  [ -d "$run_dir" ] || { echo "FAIL: simplify judge-only rerun was not written" >&2; exit 1; }
  metadata="$run_dir/metadata.txt"
  cmp "$frozen_candidate" "$run_dir/candidate.md"
  [ ! -e "$run_dir/agent-trace.jsonl" ]
  grep -Fqx "candidate_source=$frozen_candidate" "$metadata"
  grep -Fqx "candidate_source_sha256=$(sha256sum "$frozen_candidate" | cut -d' ' -f1)" "$metadata"
  for prompt_file in "$run_dir/agent-prompt.md" "$run_dir/judge-prompt.md"; do
    [ -f "$prompt_file" ] || { echo "FAIL: judge-only prompt was not persisted: $prompt_file" >&2; exit 1; }
    source_key=$(awk -F= -v path="$prompt_file" '$1 ~ /^source_[0-9]+_path$/ && $2 == path { sub(/_path$/, "", $1); print $1; exit }' "$metadata")
    [ -n "$source_key" ] || { echo "FAIL: judge-only prompt was not recorded as a metadata source: $prompt_file" >&2; exit 1; }
    grep -Fqx "${source_key}_sha256=$(sha256sum "$prompt_file" | cut -d' ' -f1)" "$metadata"
  done
  grep -Fq 'only in commentary is lost.' "$run_dir/judge-prompt.md"
done
pre_authoring_state="$(bash -c 'source "$1"; style_eval_harness_state_sha256 "$2"' _ \
  "$ROOT/claude/style-eval-engine.sh" "$TMP/repo")"
mkdir "$TMP/authoring-captures"
PATH="$TMP/fake-bin:$PATH" STYLE_HARNESS_DATA="$TMP/repo" RUN_ID=authoring-test \
  AGENT_MODEL=test-agent JUDGE_MODEL=test-judge \
  FAKE_CAPTURE_DIR="$TMP/authoring-captures" \
  "$ROOT/claude/pr-style/eval/run-eval.sh" description-heldout "$MANIFEST" --flow authoring >/dev/null
for metadata in "$TMP/repo/pr-style/results/runs"/authoring-test-*-agent-decision-claude-test-agent/metadata.txt; do
  [ -f "$metadata" ] || { echo "FAIL: authoring held-out metadata was not written" >&2; exit 1; }
  grep -Fqx "data_repo_git_sha=$data_git_sha" "$metadata"
  grep -Fqx "data_repo_git_dirty=$data_dirty" "$metadata"
  grep -Fqx "data_repo_git_state_sha256=$pre_authoring_state" "$metadata"
  grep -Fqx "benchmark_manifest_path=$manifest_path" "$metadata"
  grep -Fqx "benchmark_manifest_sha256=$manifest_sha" "$metadata"
  grep -Fqx 'benchmark_case_ids=authoring-42-r2-r3,authoring-42-r3-r4' "$metadata"
  grep -Fqx 'agent_model=test-agent' "$metadata"
  grep -Fqx 'judge_model=test-judge' "$metadata"
  grep -Fqx 'decision_role=agent' "$metadata"
  grep -Fqx 'decision_model=test-agent' "$metadata"
  grep -Fqx 'judge_used=false' "$metadata"
done
for summary in "$TMP/repo/pr-style/results/runs"/authoring-test-*-agent-decision-claude-test-agent/summary.json; do
  [ -f "$summary" ] || { echo "FAIL: authoring held-out summary was not written" >&2; exit 1; }
  [ "$(jq -r '.total' "$summary")" -eq 2 ]
  [ "$(jq -r '.reference_wins' "$summary")" -eq 1 ]
  [ "$(jq -r '[.cases[].reference_slot] | sort | join(",")' "$summary")" = A,B ]
done
capture_index=0
for case_id in authoring-42-r2-r3 authoring-42-r3-r4; do
  capture_index=$((capture_index + 1))
  for prompt in "$TMP/repo/pr-style/results/runs"/authoring-test-*-agent-decision-claude-test-agent/judgments/"$case_id".prompt.md; do
    cmp "$prompt" "$TMP/authoring-captures/prompt-$capture_index.md"
    grep -Fq 'Do not use tools or read files' "$prompt"
  done
  for trace in "$TMP/repo/pr-style/results/runs"/authoring-test-*-agent-decision-claude-test-agent/judgments/"$case_id".agent-trace.jsonl; do
    [ -n "$(jq -er '.result' "$trace")" ]
  done
done
python3 - \
  "$TMP/authoring-captures/prompt-1.md" "$TMP/bodies/revision-3.md" "$TMP/bodies/revision-2.md" "$TMP/authoring-captures/args-1.bin" \
  "$TMP/authoring-captures/prompt-2.md" "$TMP/bodies/revision-3.md" "$TMP/bodies/revision-4.md" "$TMP/authoring-captures/args-2.bin" <<'PY'
import pathlib
import sys

def validate(prompt_path, artifact_a_path, artifact_b_path, args_path):
    prompt = prompt_path.read_bytes()
    artifact_a = artifact_a_path.read_bytes()
    artifact_b = artifact_b_path.read_bytes()
    a_start = prompt.index(b"=== ARTIFACT A ===\n") + len(b"=== ARTIFACT A ===\n")
    assert prompt[a_start:a_start + len(artifact_a)] == artifact_a
    assert prompt[a_start + len(artifact_a):].startswith(b"\n=== ARTIFACT B ===\n")
    b_start = prompt.index(b"=== ARTIFACT B ===\n") + len(b"=== ARTIFACT B ===\n")
    assert prompt[b_start:b_start + len(artifact_b)] == artifact_b
    assert prompt[b_start + len(artifact_b):].startswith(b"\nRun Mode A.")
    args = args_path.read_bytes().split(b"\0")[:-1]
    assert b"--tools" in args
    assert args[args.index(b"--tools") + 1] == b""
    assert b"test-agent" in args
    assert b"test-judge" not in args

paths = list(map(pathlib.Path, sys.argv[1:]))
validate(*paths[:4])
validate(*paths[4:])
PY

grep -Fq 'OUTPUT_DIR="${2:-$DATA/pr-style/corpus/authoring/revisions}"' "$HARVEST"
jq '.number = 100' "$EVIDENCE" >"$TMP/harvest/100.json"
printf 'keep me\n' >"$TMP/harvest/notes.txt"
mkdir "$TMP/harvest/nested"
printf 'nested\n' >"$TMP/harvest/nested/file.txt"
printf 'hidden\n' >"$TMP/harvest/.keep"
cat >"$TMP/fake-bin/gh" <<'EOF'
#!/bin/sh
set -eu
if [ "$1" = pr ] && [ "$2" = list ]; then
  [ "${GH_LIST_MODE:-records}" = empty ] || printf '200\n'
  exit 0
fi
if [ "$1" = api ] && [ "$2" = graphql ]; then
  jq -n --rawfile one "$GH_BODY_ONE" --rawfile two "$GH_BODY_TWO" '{data:{repository:{pullRequest:{number:200,title:"Fetched",url:"https://example.invalid/200",state:"MERGED",isDraft:false,createdAt:"2026-02-01T00:00:00Z",closedAt:"2026-02-02T00:00:00Z",mergedAt:"2026-02-02T00:00:00Z",body:$two,userContentEdits:{pageInfo:{hasNextPage:false},nodes:[{editedAt:"2026-02-01T00:00:00Z",editor:{login:"writer"},diff:$one},{editedAt:"2026-02-02T00:00:00Z",editor:{login:"writer"},diff:$two}]}}}}}'
  exit 0
fi
echo "unexpected fake gh invocation: $*" >&2
exit 1
EOF
chmod +x "$TMP/fake-bin/gh"
for immutable_output in \
  "$TMP/custom/pr-style/corpus/evidence" \
  "$TMP/custom/pr-style/corpus/evidence/other-cache" \
  "$TMP/custom/pr-style/corpus/benchmarks" \
  "$TMP/custom/pr-style/corpus/benchmarks/v1"
do
  if PATH="$TMP/fake-bin:$PATH" STYLE_HARNESS_DATA="$TMP/other-data" AUTHOR=writer \
    "$HARVEST" 10 "$immutable_output" >/dev/null 2>&1; then
    echo "FAIL: harvest accepted immutable corpus output path $immutable_output" >&2
    exit 1
  fi
  [ ! -e "$immutable_output" ]
done
if ! PATH="$TMP/fake-bin:$PATH" OWNER=Example REPO=widgets AUTHOR=writer \
  GH_BODY_ONE="$TMP/bodies/revision-1.md" GH_BODY_TWO="$TMP/bodies/revision-2.md" \
  "$HARVEST" 10 "$TMP/harvest" >"$TMP/harvest.log" 2>&1; then
  cat "$TMP/harvest.log" >&2
  echo "FAIL: harvest overlay failed" >&2
  exit 1
fi
[ -f "$TMP/harvest/100.json" ] && [ -f "$TMP/harvest/200.json" ]
[ "$(cat "$TMP/harvest/notes.txt")" = 'keep me' ]
[ "$(cat "$TMP/harvest/nested/file.txt")" = nested ]
[ "$(cat "$TMP/harvest/.keep")" = hidden ]
[ "$(jq '.pairs | length' "$TMP/harvest/manifest.json")" -eq 2 ]
[ "$(jq -r '.discovery_complete' "$TMP/harvest/manifest.json")" = false ]
preserved_sha=$(sha256sum "$TMP/harvest/100.json" | cut -d' ' -f1)
if PATH="$TMP/fake-bin:$PATH" OWNER=Example REPO=widgets AUTHOR=writer GH_LIST_MODE=empty \
  "$HARVEST" 10 "$TMP/harvest" >/dev/null 2>&1; then
  echo "FAIL: empty PR discovery replaced harvest evidence" >&2
  exit 1
fi
[ "$preserved_sha" = "$(sha256sum "$TMP/harvest/100.json" | cut -d' ' -f1)" ]

cp -R "$TMP/harvest" "$TMP/harvest-repository-mismatch"
jq '.repository = "Other/repository"' "$TMP/harvest-repository-mismatch/100.json" >"$TMP/mismatch.json"
mv "$TMP/mismatch.json" "$TMP/harvest-repository-mismatch/100.json"
mismatch_manifest_sha="$(sha256sum "$TMP/harvest-repository-mismatch/manifest.json" | cut -d' ' -f1)"
if PATH="$TMP/fake-bin:$PATH" OWNER=Example REPO=widgets AUTHOR=writer \
  "$HARVEST" 10 "$TMP/harvest-repository-mismatch" >/dev/null 2>&1; then
  echo "FAIL: harvest accepted retained evidence from another repository" >&2
  exit 1
fi
[ "$mismatch_manifest_sha" = "$(sha256sum "$TMP/harvest-repository-mismatch/manifest.json" | cut -d' ' -f1)" ]

cp -R "$TMP/harvest" "$TMP/harvest-author-mismatch"
jq '.all_revisions[0].editor = "other"' "$TMP/harvest-author-mismatch/100.json" >"$TMP/mismatch.json"
mv "$TMP/mismatch.json" "$TMP/harvest-author-mismatch/100.json"
mismatch_manifest_sha="$(sha256sum "$TMP/harvest-author-mismatch/manifest.json" | cut -d' ' -f1)"
if PATH="$TMP/fake-bin:$PATH" OWNER=Example REPO=widgets AUTHOR=writer \
  "$HARVEST" 10 "$TMP/harvest-author-mismatch" >/dev/null 2>&1; then
  echo "FAIL: harvest accepted an author revision without a matching author edit" >&2
  exit 1
fi
[ "$mismatch_manifest_sha" = "$(sha256sum "$TMP/harvest-author-mismatch/manifest.json" | cut -d' ' -f1)" ]
