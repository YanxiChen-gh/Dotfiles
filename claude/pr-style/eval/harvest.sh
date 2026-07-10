#!/usr/bin/env bash
# Discover fresh calibration material from recent PRs for manual curation. sync-descriptions
# refreshes an additive discovery cache: it retains histories outside the latest bounded query and
# refreshes those returned by GitHub. It never writes versioned frozen benchmark evidence.
#
#   ./harvest.sh                 # both, last 20 merged PRs
#   ./harvest.sh commits [N]     # cleanup commits (comment/test before->after) in last N PRs
#   ./harvest.sh descriptions [N]# PR-body edit histories with >1 author revision (description pairs)
#   ./harvest.sh sync-descriptions [N] # merge complete histories into the discovery cache
set -euo pipefail
OWNER=VantaInc REPO=obsidian
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${AUTHOR:=$(gh api user --jq .login)}"
CLEANUP_RE='trim|drop|inline|tighten|simplif|evergreen|dedup|clean ?up|prune|remove.*(comment|test)|non-obvious'

recent_prs() { gh pr list --repo "$OWNER/$REPO" --author "$AUTHOR" --state merged --limit "${1:-20}" --json number --jq '.[].number'; }

commits() {
  local n="${1:-20}"
  echo "## Cleanup-commit candidates (author=$AUTHOR, last $n merged PRs)"
  for pr in $(recent_prs "$n"); do
    gh pr view "$pr" --repo "$OWNER/$REPO" --json commits \
      | jq -r --arg re "$CLEANUP_RE" --arg pr "$pr" \
      '.commits[] | select(.messageHeadline | test($re;"i")) | "PR #\($pr)  \(.oid[0:8])  \(.messageHeadline)"' 2>/dev/null || true
  done
  echo ""
  printf '%s\n' "# Inspect a candidate's diff:  gh api repos/$OWNER/$REPO/commits/<sha> --jq '.files[]|select(.patch!=null)|\"\(.filename)\\n\(.patch)\"'"
}

descriptions() {
  local n="${1:-20}"
  echo "## PR-description pair candidates (PRs with >1 of your body revisions)"
  for pr in $(recent_prs "$n"); do
    local c
    # GraphQL variables are expanded by GitHub, not the shell.
    # shellcheck disable=SC2016
    c=$(gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){userContentEdits(first:50){nodes{editor{login}}}}}}' \
        -F o="$OWNER" -F r="$REPO" -F n="$pr" \
        | jq -r --arg a "$AUTHOR" '[.data.repository.pullRequest.userContentEdits.nodes[]|select(.editor.login==$a)]|length' 2>/dev/null || echo 0)
    [ "${c:-0}" -gt 1 ] && echo "PR #$pr  ($c author body revisions)"
  done
  echo ""
  echo "# Dump one PR's body history:  $HERE/extract-pr-description-history.sh <pr>"
  echo "# To freeze: copy selected histories into a versioned evidence directory, then create a manifest."
}

case "${1:-both}" in
  commits) commits "${2:-20}" ;;
  descriptions) descriptions "${2:-20}" ;;
  sync-descriptions) "$HERE/harvest-pr-description-data.sh" "${2:-500}" ;;
  both) commits "${2:-20}"; echo; descriptions "${2:-20}" ;;
  *) echo "usage: harvest.sh {commits [N] | descriptions [N] | sync-descriptions [N] | both}"; exit 1 ;;
esac
