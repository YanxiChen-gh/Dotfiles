#!/usr/bin/env bash
# Preserve complete PR-description revision evidence in the private style data repo.
set -euo pipefail

OWNER="${OWNER:-VantaInc}"
REPO="${REPO:-obsidian}"
AUTHOR="${AUTHOR:-$(gh api user --jq .login)}"
LIMIT="${1:-500}"
DATA="${STYLE_HARNESS_DATA:-$HOME/style-harness-data}"
OUTPUT_DIR="${2:-$DATA/pr-style/corpus/authoring/revisions}"
OUTPUT_PARENT="$(dirname "$OUTPUT_DIR")"
mkdir -p "$OUTPUT_PARENT"
TEMP_DIR="$(mktemp -d "$OUTPUT_PARENT/.revisions.XXXXXX")"
cleanup() { [ -n "${TEMP_DIR:-}" ] && rm -rf "$TEMP_DIR"; }
trap cleanup EXIT INT TERM

count=0
for number in $(gh pr list --repo "$OWNER/$REPO" --author "$AUTHOR" --state all --limit "$LIMIT" --json number --jq '.[].number'); do
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
  count=$((count + 1))
done

shopt -s nullglob
pair_files=("$TEMP_DIR"/[0-9]*.json)
if [ "${#pair_files[@]}" -eq 0 ]; then
  jq -n --arg repository "$OWNER/$REPO" --arg author "$AUTHOR" \
    '{schema_version: 1, repository: $repository, author: $author, pairs: []}' \
    >"$TEMP_DIR/manifest.json"
else
  jq -s --arg repository "$OWNER/$REPO" --arg author "$AUTHOR" '
    {
      schema_version: 1,
      repository: $repository,
      author: $author,
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
fi

BACKUP_DIR="$OUTPUT_PARENT/.revisions.previous.$$"
[ ! -e "$OUTPUT_DIR" ] || mv "$OUTPUT_DIR" "$BACKUP_DIR"
mv "$TEMP_DIR" "$OUTPUT_DIR"
TEMP_DIR=""
rm -rf "$BACKUP_DIR"

printf 'replaced %s with %d PR revision pairs\n' "$OUTPUT_DIR" "$count"
