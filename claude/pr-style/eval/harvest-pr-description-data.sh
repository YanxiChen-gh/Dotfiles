#!/usr/bin/env bash
# Refresh the additive PR-description revision discovery cache in the private style data repo.
set -euo pipefail

OWNER="${OWNER:-VantaInc}"
REPO="${REPO:-obsidian}"
AUTHOR="${AUTHOR:-}"
LIMIT="${1:-500}"
DATA="${STYLE_HARNESS_DATA:-$HOME/style-harness-data}"
OUTPUT_DIR="${2:-$DATA/pr-style/corpus/authoring/revisions}"
IMMUTABLE_EVIDENCE_DIR="$(realpath -m "$DATA/pr-style/corpus/evidence")"
IMMUTABLE_BENCHMARKS_DIR="$(realpath -m "$DATA/pr-style/corpus/benchmarks")"
RESOLVED_OUTPUT_DIR="$(realpath -m "$OUTPUT_DIR")"
LEXICAL_OUTPUT_DIR="$(realpath -ms "$OUTPUT_DIR")"
is_immutable_corpus_path() {
  case "$1" in
    "$IMMUTABLE_EVIDENCE_DIR"|"$IMMUTABLE_EVIDENCE_DIR"/*|\
      "$IMMUTABLE_BENCHMARKS_DIR"|"$IMMUTABLE_BENCHMARKS_DIR"/*|\
      */pr-style/corpus/evidence|*/pr-style/corpus/evidence/*|\
      */pr-style/corpus/benchmarks|*/pr-style/corpus/benchmarks/*) return 0 ;;
    *) return 1 ;;
  esac
}
if is_immutable_corpus_path "$RESOLVED_OUTPUT_DIR" || is_immutable_corpus_path "$LEXICAL_OUTPUT_DIR"; then
  echo "refusing to sync into immutable corpus data: $OUTPUT_DIR" >&2
  exit 1
fi
[ -n "$AUTHOR" ] || AUTHOR="$(gh api user --jq .login)"
OUTPUT_PARENT="$(dirname "$OUTPUT_DIR")"
mkdir -p "$OUTPUT_PARENT"
TEMP_DIR="$(mktemp -d "$OUTPUT_PARENT/.revisions.XXXXXX")"
cleanup() {
  [ -z "${TEMP_DIR:-}" ] || rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

validate_cache_record() {
  local file="$1"
  jq -e --arg repository "$OWNER/$REPO" --arg author "$AUTHOR" '
    . as $record |
    .repository == $repository and
    (.author_revisions | type == "array" and length >= 2) and
    (.all_revisions | type == "array") and
    all(.author_revisions[];
      . as $revision |
      (.edited_at | type == "string") and
      (.body | type == "string") and
      any($record.all_revisions[];
        .editor == $author and
        .edited_at == $revision.edited_at and
        .body == $revision.body)
    )
  ' "$file" >/dev/null || {
    echo "retained revision record does not match $OWNER/$REPO author $AUTHOR: $file" >&2
    return 1
  }
}

shopt -s nullglob
existing_files=("$OUTPUT_DIR"/[0-9]*.json)
for existing_file in "${existing_files[@]}"; do
  validate_cache_record "$existing_file"
done
[ ! -e "$OUTPUT_DIR" ] || [ -d "$OUTPUT_DIR" ] || {
  echo "output path is not a directory: $OUTPUT_DIR" >&2
  exit 1
}
if [ -d "$OUTPUT_DIR" ]; then
  cp -a "$OUTPUT_DIR/." "$TEMP_DIR/"
fi

numbers="$(gh pr list --repo "$OWNER/$REPO" --author "$AUTHOR" --state all --limit "$LIMIT" --json number --jq '.[].number')"
[ -n "$numbers" ] || {
  echo "GitHub returned no PRs; preserving the existing revision evidence" >&2
  exit 1
}

updated_count=0
for number in $numbers; do
  # GraphQL variables are expanded by GitHub, not the shell.
  # shellcheck disable=SC2016
  pair="$(gh api graphql -f query='
    query($owner:String!,$repo:String!,$number:Int!){
      repository(owner:$owner,name:$repo){
        pullRequest(number:$number){
          number title url state isDraft createdAt closedAt mergedAt body
          userContentEdits(first:100){pageInfo{hasNextPage} nodes{editedAt editor{login} diff}}
        }
      }
    }' -F owner="$OWNER" -F repo="$REPO" -F number="$number" \
    | jq -c --arg repository "$OWNER/$REPO" --arg author "$AUTHOR" '
      .data.repository.pullRequest as $pr
      | if $pr.userContentEdits.pageInfo.hasNextPage then error("more than 100 body revisions") else . end
      | [$pr.userContentEdits.nodes[] | select(.editor.login == $author)] | sort_by(.editedAt) as $authorRevisions
      | select(($authorRevisions | length) >= 2)
      | {
          schema_version: 1,
          repository: $repository,
          number: $pr.number,
          title: $pr.title,
          url: $pr.url,
          state: $pr.state,
          is_draft: $pr.isDraft,
          created_at: $pr.createdAt,
          closed_at: $pr.closedAt,
          merged_at: $pr.mergedAt,
          candidate: {
            source: "earliest_author_revision",
            edited_at: $authorRevisions[0].editedAt,
            body: $authorRevisions[0].diff,
            is_creation_revision: ($authorRevisions[0].editedAt == $pr.createdAt),
            agent_authorship: "unverified",
            ai_disclosure_present: ($authorRevisions[0].diff | test("## AI Model used"; "i"))
          },
          reference: {
            source: "last_author_revision",
            edited_at: $authorRevisions[-1].editedAt,
            body: $authorRevisions[-1].diff
          },
          author_revisions: [$authorRevisions[] | {edited_at: .editedAt, body: .diff}],
          all_revisions: [$pr.userContentEdits.nodes[] | {edited_at: .editedAt, editor: .editor.login, body: .diff}] | sort_by(.edited_at),
          current_body: $pr.body,
          non_author_editors: ([$pr.userContentEdits.nodes[] | select(.editor.login != $author) | .editor.login] | unique),
          current_body_matches_reference: ($pr.body == $authorRevisions[-1].diff),
          history_complete: true
        }')"
  [ -n "$pair" ] || continue
  printf '%s\n' "$pair" | jq . >"$TEMP_DIR/$number.json"
  updated_count=$((updated_count + 1))
done

pair_files=("$TEMP_DIR"/[0-9]*.json)
[ "${#pair_files[@]}" -gt 0 ] || {
  echo "no complete PR revision histories were available; preserving the existing evidence" >&2
  exit 1
}
for pair_file in "${pair_files[@]}"; do
  validate_cache_record "$pair_file"
done
jq -s --arg repository "$OWNER/$REPO" --arg author "$AUTHOR" --argjson discovery_limit "$LIMIT" '
  {
    schema_version: 1,
    repository: $repository,
    author: $author,
    discovery_limit: $discovery_limit,
    discovery_complete: false,
    pairs: (sort_by(.number) | map({
      number,
      title,
      url,
      state,
      is_draft,
      created_at,
      closed_at,
      merged_at,
      candidate_is_creation_revision: .candidate.is_creation_revision,
      candidate_agent_authorship: .candidate.agent_authorship,
      author_revision_count: (.author_revisions | length),
      current_body_matches_reference,
      non_author_editors,
      history_complete
    }))
  }' "${pair_files[@]}" >"$TEMP_DIR/manifest.json"

BACKUP_DIR="$OUTPUT_PARENT/.revisions.previous.$$"
[ ! -e "$OUTPUT_DIR" ] || mv "$OUTPUT_DIR" "$BACKUP_DIR"
mv "$TEMP_DIR" "$OUTPUT_DIR"
TEMP_DIR=""
rm -rf "$BACKUP_DIR"

printf 'updated %d PR revision histories; discovery cache contains %d records at %s\n' \
  "$updated_count" "${#pair_files[@]}" "$OUTPUT_DIR"
