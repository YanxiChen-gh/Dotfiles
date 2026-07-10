#!/usr/bin/env bash
# Extract the edit history of PR description bodies - the "before" data that isn't in git.
# GitHub stores every body revision in the GraphQL `userContentEdits` connection.
#
#   ./extract-pr-description-history.sh <pr-number> [pr-number...]
#
# Prints each revision oldest->newest, filtered to the author account (drops github-actions / *-app /
# atlassian template stamps). The first stored revision is the recoverable candidate; the final
# author revision is the reference. Do not use the current body as the reference because bots can
# modify it after the author is done.
set -euo pipefail
OWNER=VantaInc REPO=obsidian
: "${AUTHOR:=YanxiChen-gh}"   # override with AUTHOR=login to filter to a different editor

for num in "$@"; do
  echo "################ PR #$num ################"
  # GraphQL variables are expanded by GitHub, not the shell.
  # shellcheck disable=SC2016
  gh api graphql -f query='
    query($owner:String!,$repo:String!,$num:Int!){
      repository(owner:$owner,name:$repo){
        pullRequest(number:$num){
          title
          createdAt
          userContentEdits(first:50){ nodes{ editedAt editor{login} diff } }
        }
      }
    }' -F owner="$OWNER" -F repo="$REPO" -F num="$num" \
    | jq -r --arg author "$AUTHOR" '
      .data.repository.pullRequest as $pr
      | ($pr.userContentEdits.nodes
          | map(select(.editor.login == $author))
          | sort_by(.editedAt)) as $revisions
      | "created_at=\($pr.createdAt) author_revisions=\($revisions | length)",
        ($revisions | to_entries[]
          | "\n----- author revision \(.key + 1)/\($revisions | length) by \(.value.editor.login) @ \(.value.editedAt) -----\n\(.value.diff // "(no diff)")")'
  echo ""
done
