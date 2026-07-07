#!/usr/bin/env bash
# Extract the edit history of PR description bodies - the "before" data that isn't in git.
# GitHub stores every body revision in the GraphQL `userContentEdits` connection.
#
#   ./extract-pr-description-history.sh <pr-number> [pr-number...]
#
# Prints each revision oldest->newest, filtered to human edits (drops github-actions / *-app /
# atlassian template stamps), then the current (merged) body as the "after". Use consecutive
# human revisions where a tell was fixed as before->after calibration pairs for the simplify flow.
set -euo pipefail
OWNER=VantaInc REPO=obsidian
: "${AUTHOR:=YanxiChen-gh}"   # override with AUTHOR=login to filter to a different editor

for num in "$@"; do
  echo "################ PR #$num ################"
  gh api graphql -f query='
    query($owner:String!,$repo:String!,$num:Int!){
      repository(owner:$owner,name:$repo){
        pullRequest(number:$num){
          title
          body
          userContentEdits(first:50){ nodes{ editedAt editor{login} diff } }
        }
      }
    }' -F owner="$OWNER" -F repo="$REPO" -F num="$num" \
    | jq -r --arg author "$AUTHOR" '
      .data.repository.pullRequest as $pr
      | ($pr.userContentEdits.nodes | reverse
          | map(select(.editor.login == $author))
          | .[] | "\n----- revision by \(.editor.login) @ \(.editedAt) -----\n\(.diff // "(no diff)")")
      , "\n===== CURRENT / MERGED BODY (after) =====\n\($pr.body)"'
  echo ""
done
