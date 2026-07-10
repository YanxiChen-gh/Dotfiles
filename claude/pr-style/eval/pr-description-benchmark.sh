#!/usr/bin/env bash
# Validate and materialize frozen PR-description benchmark manifests without network access.
set -euo pipefail

usage() {
  echo "usage: pr-description-benchmark.sh {validate MANIFEST | materialize MANIFEST OUTPUT_DIR [simplify|authoring]}" >&2
}

require_tools() {
  local tool
  for tool in git jq realpath sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || {
      echo "$tool is required" >&2
      return 1
    }
  done
}

manifest_root() {
  git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null || {
    echo "manifest is not inside a git worktree: $1" >&2
    return 1
  }
}

validate_structure() {
  jq -e '
    def nonempty_string: type == "string" and length > 0;
    def sha256: type == "string" and test("^[0-9a-f]{64}$");
    def safe_id: nonempty_string and test("^[A-Za-z0-9][A-Za-z0-9._-]*$");
    def safe_evidence_path:
      nonempty_string and
      startswith("pr-style/corpus/evidence/pr-description-revisions/") and
      (startswith("/") | not) and
      (test("(^|/)\\.\\.?(/|$)") | not) and
      (test("[[:cntrl:]]") | not);
    def revision:
      type == "object" and
      (.author_revision | type == "number" and . >= 1 and . == floor) and
      (.edited_at | nonempty_string) and
      (.body_sha256 | sha256);
    def string_array:
      type == "array" and length > 0 and
      all(.[]; nonempty_string) and
      length == (unique | length);
    .schema_version == 1 and
    (.benchmark | type == "object") and
    (.benchmark.id | safe_id) and
    (.benchmark.version | type == "number" and . >= 1 and . == floor) and
    (.benchmark.split | nonempty_string) and
    (.benchmark.frozen_at | nonempty_string) and
    (.benchmark.repository | nonempty_string) and
    (.benchmark.author | nonempty_string) and
    (.benchmark.selection_note | nonempty_string) and
    (.cases | type == "array" and length > 0) and
    all(.cases[];
      (.id | safe_id) and
      (.flow == "simplify" or .flow == "authoring") and
      (.pr_number | type == "number" and . >= 1 and . == floor) and
      (.evidence_path | safe_evidence_path) and
      (.evidence_sha256 | sha256) and
      (.before | revision) and
      (.after | revision) and
      (.after.author_revision == .before.author_revision + 1) and
      (if .flow == "simplify" then
        (.scoring | type == "object") and
        (.scoring.expected_edits | string_array) and
        (.scoring.must_preserve | string_array)
      else
        (.scoring | type == "object") and
        (.scoring.reference == "after") and
        (.scoring.reasons | string_array)
      end)
    ) and
    ([.cases[].id] | length == (unique | length)) and
    ([.cases[] | [.pr_number, .before.author_revision, .after.author_revision] | @json]
      | length == (unique | length))
  ' "$1" >/dev/null || {
    echo "invalid benchmark manifest structure: $1" >&2
    return 1
  }
}

validate_evidence_case() {
  local manifest="$1" root="$2" case_json="$3"
  local case_id evidence_path expected_evidence_sha evidence_file resolved_evidence
  local repository author pr_number before_index after_index before_edited_at after_edited_at
  local before_body_sha after_body_sha actual_sha actual_before_sha actual_after_sha

  case_id="$(jq -r '.id' <<<"$case_json")"
  evidence_path="$(jq -r '.evidence_path' <<<"$case_json")"
  expected_evidence_sha="$(jq -r '.evidence_sha256' <<<"$case_json")"
  evidence_file="$root/$evidence_path"
  [ -f "$evidence_file" ] || {
    echo "case $case_id evidence not found: $evidence_path" >&2
    return 1
  }
  resolved_evidence="$(realpath -e "$evidence_file")"
  case "$resolved_evidence" in
    "$root"/pr-style/corpus/evidence/pr-description-revisions/*) ;;
    *) echo "case $case_id evidence escapes the allowed directory: $evidence_path" >&2; return 1 ;;
  esac

  actual_sha="$(sha256sum "$resolved_evidence" | cut -d' ' -f1)"
  [ "$actual_sha" = "$expected_evidence_sha" ] || {
    echo "case $case_id evidence SHA-256 mismatch" >&2
    return 1
  }

  repository="$(jq -r '.benchmark.repository' "$manifest")"
  author="$(jq -r '.benchmark.author' "$manifest")"
  pr_number="$(jq -r '.pr_number' <<<"$case_json")"
  before_index="$(jq -r '.before.author_revision' <<<"$case_json")"
  after_index="$(jq -r '.after.author_revision' <<<"$case_json")"
  before_edited_at="$(jq -r '.before.edited_at' <<<"$case_json")"
  after_edited_at="$(jq -r '.after.edited_at' <<<"$case_json")"
  before_body_sha="$(jq -r '.before.body_sha256' <<<"$case_json")"
  after_body_sha="$(jq -r '.after.body_sha256' <<<"$case_json")"

  jq -e \
    --arg repository "$repository" \
    --arg author "$author" \
    --argjson pr_number "$pr_number" \
    --argjson before_index "$before_index" \
    --argjson after_index "$after_index" \
    --arg before_edited_at "$before_edited_at" \
    --arg after_edited_at "$after_edited_at" '
      . as $record |
      .schema_version == 1 and
      .repository == $repository and
      .number == $pr_number and
      .state == "MERGED" and
      .history_complete == true and
      (.author_revisions | type == "array" and length >= $after_index) and
      (.all_revisions | type == "array") and
      (.author_revisions[$before_index - 1].body | type == "string") and
      (.author_revisions[$after_index - 1].body | type == "string") and
      .author_revisions[$before_index - 1].edited_at == $before_edited_at and
      .author_revisions[$after_index - 1].edited_at == $after_edited_at and
      any(.all_revisions[];
        .editor == $author and .edited_at == $before_edited_at and
        .body == $record.author_revisions[$before_index - 1].body) and
      any(.all_revisions[];
        .editor == $author and .edited_at == $after_edited_at and
        .body == $record.author_revisions[$after_index - 1].body) and
      .author_revisions[$before_index - 1].body != .author_revisions[$after_index - 1].body
    ' "$resolved_evidence" >/dev/null || {
      echo "case $case_id does not match its frozen revision evidence" >&2
      return 1
    }

  actual_before_sha="$(jq -j --argjson index "$before_index" '.author_revisions[$index - 1].body' "$resolved_evidence" | sha256sum | cut -d' ' -f1)"
  actual_after_sha="$(jq -j --argjson index "$after_index" '.author_revisions[$index - 1].body' "$resolved_evidence" | sha256sum | cut -d' ' -f1)"
  [ "$actual_before_sha" = "$before_body_sha" ] || {
    echo "case $case_id before body SHA-256 mismatch" >&2
    return 1
  }
  [ "$actual_after_sha" = "$after_body_sha" ] || {
    echo "case $case_id after body SHA-256 mismatch" >&2
    return 1
  }
}

validate_manifest() {
  local manifest="${1:?manifest required}" root case_json
  require_tools
  [ -f "$manifest" ] || { echo "manifest not found: $manifest" >&2; return 1; }
  root="$(manifest_root "$manifest")"
  root="$(realpath -e "$root")"
  validate_structure "$manifest"
  while IFS= read -r case_json; do
    validate_evidence_case "$manifest" "$root" "$case_json"
  done < <(jq -c '.cases[]' "$manifest")
}

write_body() {
  local evidence_file="$1" revision="$2" output="$3"
  jq -j --argjson revision "$revision" '.author_revisions[$revision - 1].body' "$evidence_file" >"$output"
}

materialize_manifest() (
  local manifest="${1:?manifest required}" target_dir="${2:?output directory required}" flow="${3:-all}"
  local output_parent output_dir root case_json case_id case_flow case_dir evidence_file before_index after_index
  case "$flow" in
    all|simplify|authoring) ;;
    *) echo "invalid flow: $flow (expected simplify or authoring)" >&2; return 1 ;;
  esac
  [ ! -e "$target_dir" ] || { echo "output already exists: $target_dir" >&2; return 1; }
  validate_manifest "$manifest"
  root="$(realpath -e "$(manifest_root "$manifest")")"
  output_parent="$(dirname "$target_dir")"
  mkdir -p "$output_parent"
  output_dir="$(mktemp -d "$output_parent/.pr-description-benchmark.XXXXXX")"
  trap 'rm -rf "$output_dir"' EXIT INT TERM
  cp "$manifest" "$output_dir/manifest.json"

  while IFS= read -r case_json; do
    case_flow="$(jq -r '.flow' <<<"$case_json")"
    [ "$flow" = all ] || [ "$flow" = "$case_flow" ] || continue
    case_id="$(jq -r '.id' <<<"$case_json")"
    case_dir="$output_dir/$case_flow/$case_id"
    evidence_file="$root/$(jq -r '.evidence_path' <<<"$case_json")"
    before_index="$(jq -r '.before.author_revision' <<<"$case_json")"
    after_index="$(jq -r '.after.author_revision' <<<"$case_json")"
    mkdir -p "$case_dir"
    jq . <<<"$case_json" >"$case_dir/case.json"
    write_body "$evidence_file" "$before_index" "$case_dir/before.md"
    write_body "$evidence_file" "$after_index" "$case_dir/after.md"
  done < <(jq -c '.cases[]' "$manifest")

  if [ -d "$output_dir/simplify" ]; then
    {
      printf '# PR Description Simplify Benchmark\n\n'
      printf 'For each case, propose the cuts or tightening you would make to the complete BEFORE body. Identify every case by its case ID.\n'
    } >"$output_dir/simplify/blind-input.md"
    printf '# PR Description Simplify Answer Key\n' >"$output_dir/simplify/answer-key.md"
    while IFS= read -r case_json; do
      [ "$(jq -r '.flow' <<<"$case_json")" = simplify ] || continue
      case_id="$(jq -r '.id' <<<"$case_json")"
      case_dir="$output_dir/simplify/$case_id"
      {
        printf '\n## Case %s\n\nBEFORE:\n' "$case_id"
        cat "$case_dir/before.md"
        printf '\n'
      } >>"$output_dir/simplify/blind-input.md"
      {
        printf '\n## Case %s\n\nBEFORE:\n' "$case_id"
        cat "$case_dir/before.md"
        printf '\n\nAFTER:\n'
        cat "$case_dir/after.md"
        printf '\n\nEXPECTED EDITS:\n'
        jq -r '.scoring.expected_edits[] | "- " + .' <<<"$case_json"
        printf '\nMUST PRESERVE:\n'
        jq -r '.scoring.must_preserve[] | "- " + .' <<<"$case_json"
      } >>"$output_dir/simplify/answer-key.md"
    done < <(jq -c '.cases[]' "$manifest")
  fi
  [ ! -e "$target_dir" ] || { echo "output already exists: $target_dir" >&2; return 1; }
  mv "$output_dir" "$target_dir"
  output_dir=""
  trap - EXIT INT TERM
)

case "${1:-}" in
  validate)
    [ "$#" -eq 2 ] || { usage; exit 1; }
    validate_manifest "$2"
    ;;
  materialize)
    if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
      usage
      exit 1
    fi
    if [ "$#" -eq 4 ] && [ "$4" != simplify ] && [ "$4" != authoring ]; then
      echo "invalid flow: $4 (expected simplify or authoring)" >&2
      exit 1
    fi
    materialize_manifest "$2" "$3" "${4:-all}"
    ;;
  *) usage; exit 1 ;;
esac
