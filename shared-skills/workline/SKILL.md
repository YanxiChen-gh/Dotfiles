---
name: workline
description: Retrieve shared PR/session context and register or report engineering work in Workline when this host has configured access.
---

Workline is at https://workline-bice.vercel.app. Use the bundled `scripts/api.py` with Python 3 from any working directory. It reads `~/.config/workline/config.json` (override with `WORKLINE_CONFIG`) and launches Vercel from the config file's directory. Keep the config outside project checkouts so Vercel launchers such as `pnpm dlx` use host settings. If access is missing or expired, explain the gap once and continue the user's task.

Start with `/api/me` and `/api/work`. Reuse the work item containing the current native session ID or the PR delivering the user's request. A contextual PR reference does not establish an association. If neither identity is known, retrieve native session metadata from available tools; leave unavailable facts unknown. Register significant engineering work once, then report meaningful progress, blockers, and handoff. Reading or brainstorming alone need not create work.

```sh
python3 <skill-directory>/scripts/api.py /api/me
python3 <skill-directory>/scripts/api.py /api/work
python3 <skill-directory>/scripts/api.py /api/work/WORK_ID
python3 <skill-directory>/scripts/api.py /api/work --key STABLE_OPERATION_KEY < registration.json
python3 <skill-directory>/scripts/api.py /api/work/WORK_ID/commands --key STABLE_OPERATION_KEY < command.json
```

The helper writes JSON results to stdout and `workline.client.*` diagnostic events to stderr. Search Vercel Runtime Logs for the event's `requestId` to find the matching Workline API calls. If an attempt never reaches Workline, use the local transport, status, and exit code. Keep diagnostic captures private.

Registration JSON is `{"title":"...","purpose":"..."}` with optional `pr: {"repository":"OWNER/REPO","number":123}` and `session`. Retrieve the item before a command. Command JSON is `{"action":"progress","version":CURRENT_VERSION,"expected_heads":HEADS,"data":{"message":"..."}}`; optional `data.blocker` reports a blocker. Build `HEADS` from every current PR using `"OWNER/REPO#NUMBER": head`, preserving null values. Other reporter actions are `associate` with `{repository,number}` and `session` with the complete session object.

Session fields: `id`, `hostId`, `host`, `environment` (`local`, `ssh`, `cloud`, or `unknown`), `status`, `reported_at` (Unix seconds; divide native millisecond timestamps by 1000), `title`, `archived`, `project` (string or null), and `hostAliases` (array). Use the actual native session and host identities, not a fabricated substitute.

Reuse the same key and payload after an uncertain write. On HTTP 409, retrieve current context before choosing another operation. Report metadata only, never transcripts, source code, or secrets. Reporter access cannot queue, pause, share, change prerequisites or reviewers, publish trusted observations, or grant permissions. Preserve existing organizer hooks, relays, pins, and manual placements. Reporting does not prove that a session started or a PR merged.

When the author asks to queue one or more Obsidian drafts for review, verify each open draft's author, head repository, head branch, base branch, and published contents with `gh pr view` or the GitHub API. Report local-only changes before queuing. Reuse the work item linked to the coding session or the delivering PRs. Associate the selected drafts with that item and retrieve its current version and heads. Leave PRs already in review on their existing items.

With a coding-session credential or the item's controller, submit one versioned `queue-reviews` command to `/api/work/WORK_ID/commands`. Put every selected draft in `data.pull_requests` with `number`, `head_ref`, and `base_ref`. Workline derives a merge prerequisite when a draft's base branch matches another selected draft's head branch. When the base is an open PR outside the selection, verify the parent with GitHub and send its PR number in `parent`. Match the repository and branch when resolving a parent. Use `gh stack view --json` when available.

```json
{
  "action": "queue-reviews",
  "version": 4,
  "expected_heads": {"vantainc/obsidian#123": null, "vantainc/obsidian#124": null},
  "data": {
    "pull_requests": [
      {"number": 123, "head_ref": "foundation", "base_ref": "main"},
      {"number": 124, "head_ref": "follow-up", "base_ref": "foundation"}
    ]
  }
}
```

For dependencies GitHub branches cannot express, use the session's implementation context and existing Workline prerequisites. Put a PR-specific prerequisite in that draft's `dependencies` array. A merge prerequisite is `{"kind":"merged","scope":"review","target":"vantainc/obsidian#NUMBER","label":"..."}`. For a rollout, use `kind: "deployed"` and include the exact `environment`, `service`, and `region`. A prerequisite PR can already be in review and can live outside Workline. Omit `dependencies` to preserve the draft's saved explicit prerequisites. When adding a prerequisite, carry forward the saved explicit prerequisites and leave out the generated review-scope merge gate for `inferred_parent`. Ask only when a required dependency or its release condition is ambiguous.

Read the item back and report the status of each selected PR in `review_queue`. Workline releases each draft when its own prerequisites and required CI clear. With reporter access, direct the owner to the account menu to create a coding-session credential for this host.

When the owner explicitly asks to mark a Workline item done, abandon it, or reopen it, use the versioned `complete`, `abandon`, or `reopen` command with `data: {}` and the item's current expected heads. Use a coding-session credential or that item's controller. Done and abandoned items move to Closed and exit Workline's review queue. Reopening returns them to unfinished work. Read the item back and report its status. These commands update Workline metadata. Manage PR and coding session state separately.

When the author explicitly asks to queue a particular Obsidian draft targeting `main` and merge when ready, check that `/api/me` returns `can_set_merge_intent: true`. Verify the requested PR is linked to the item, then use the `queue` command with `data: {"merge_when_ready": true, "merge_pr": "vantainc/obsidian#NUMBER"}`. Read the item back to verify the exact PR key. Workline keeps the opt-in pending while merge prerequisites clear. GitHub enforces approvals, CI, and its merge queue. With a credential that lacks merge access, use the signed-in owner's **Merge when ready** control.

For a stack whose layers already have separate work items, or when the author asks for a separate item per layer, use `/api/work/stack --key STABLE_OPERATION_KEY` with a bottom-to-top `layers` array. Each layer has `number`, `title`, `head_ref`, and `base_ref`. Use the returned item IDs to report the queue. For layers linked together on one work item, use `queue-reviews` on that item.

Use the same queue request with one layer for a standalone Obsidian draft with prerequisites. Put external prerequisites in the affected layer's `dependencies`. If the bottom draft targets another PR's branch, identify that parent in GitHub and add its merge as a review prerequisite. Link any missing predecessor to Workline before submitting. A merge prerequisite uses `{"kind":"merged","scope":"review","target":"vantainc/obsidian#NUMBER","label":"..."}`. A rollout prerequisite uses `kind: "deployed"`, the same target and label, `environment: "prod"` or `"staging"`, `service: "app"` or an exact `"infra-<project>"` slug, and `region: "all"`. Use `scope: "activation"` when the rollout only blocks merge, and `scope: "review"` when it must block review. Set `merge_when_ready: true` on a layer only when the author explicitly authorized it for that PR. Plain stack queueing leaves merge opt-ins unchanged.

Trusted Ona CDEs use their short-lived environment identity automatically. Ona CDEs outside a trusted project can use an existing authenticated Vercel CLI to reach Workline with the same identity. On other hosts, the signed-in owner creates a 24-hour coding-session or reporter credential in Workline's account menu. Save it in a private file outside Git. Set config to `{"credential_file":"/absolute/private/workline.key","vercel_command":["vercel"]}` with mode 600. The authenticated Vercel CLI supplies deployment-protection access in addition to the app credential. An existing host-local Vercel token file may be referenced with `vercel_token_file`. An explicit `WORKLINE_CONFIG` uses that local configuration. Existing sessions may need to reload their skills and instructions.
