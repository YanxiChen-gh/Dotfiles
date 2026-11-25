---
name: workline
description: Retrieve shared PR/session context, report work, and queue Obsidian drafts with prerequisites and lifecycle notes in Workline.
---

Workline is at https://workline-bice.vercel.app. Use the bundled `scripts/api.py` with Python 3 from any working directory. Start with `/api/me` to verify access. When `WORKLINE_CONFIG` is unset, the helper tries Ona identity first and falls back to `~/.config/workline/config.json` if needed. Setting `WORKLINE_CONFIG` selects a local config file and skips Ona identity. Keep the config outside project checkouts. The helper launches Vercel from the config file's directory so launchers such as `pnpm dlx` use host settings. If access is missing or expired, explain the gap once and continue the user's task.

Start with `/api/me` and `/api/work`. Reuse the work item containing the current native session ID or the PR delivering the user's request. A contextual PR reference does not establish an association. If neither identity is known, retrieve native session metadata from available tools; leave unavailable facts unknown. Register significant engineering work once. Include the current native `session` in registration when available. When resuming or reusing an item, check `sessions` for the current native session and host IDs. Attach a missing link with the `session` command and verify it on readback. Then report meaningful progress, blockers, and handoff. Reading or brainstorming alone need not create work.

When creating or resuming work, read its saved prerequisites. As soon as implementation reveals a review or merge dependency, capture the condition and why it matters. Before a PR exists, include it in progress with the intended change and retain it in subsequent progress updates until recorded on the draft. Once the draft is linked, use the versioned `record-prerequisite` command with `data: {"review_pr":"vantainc/obsidian#123","dependency":GATE}` and verify `draft_prerequisites` on readback. This records one gate without queueing or opting into merge. To withdraw a superseded draft gate, send the saved dependency with `remove: true` in the same command. A reporter can use progress until an owner connection records the gate. For an already queued PR use the queue update below. Resume existing items in place.

```sh
python3 <skill-directory>/scripts/api.py /api/me
python3 <skill-directory>/scripts/api.py /api/work
python3 <skill-directory>/scripts/api.py /api/work/WORK_ID
python3 <skill-directory>/scripts/api.py /api/work --key STABLE_OPERATION_KEY < registration.json
python3 <skill-directory>/scripts/api.py /api/work/WORK_ID/commands --key STABLE_OPERATION_KEY < command.json
```

The helper writes JSON results to stdout and `workline.client.*` diagnostic events to stderr. Search Vercel Runtime Logs for the event's `requestId` to find the matching Workline API calls. If an attempt never reaches Workline, use the local transport, status, and exit code. Keep diagnostic captures private.

Registration JSON is `{"title":"...","purpose":"..."}` with optional `pr: {"repository":"OWNER/REPO","number":123}` and `session`. Retrieve the item before a command. Command JSON is `{"action":"progress","version":CURRENT_VERSION,"expected_heads":HEADS,"data":{"message":"..."}}`; optional `data.blocker` reports a blocker. Build `HEADS` from every current PR using `"OWNER/REPO#NUMBER": head`, preserving null values. Other reporter actions are `associate` with `{repository,number}` and `session` with the complete session object.

When handing a linked, unqueued draft back to the owner with a specific next step, send a versioned `progress` command with `data: {"draft_handoff":{"review_pr":"vantainc/obsidian#123","handoff":"finish"}}`. Use `"finish"` when the owner needs to make changes and `"approve"` when an Obsidian draft is ready for owner sign-off. Read back `draft_handoffs` and the PR’s owner action. Use `null` to clear a handoff that no longer applies. Queueing clears the selected PR’s handoff. Verified unqueued drafts already appear under **Drafts to pick up**, including drafts with saved prerequisites. Reserve explicit handoffs for a concrete request to finish or approve the draft.

When the owner has a concrete work-item action, use a coding-session credential to send `progress` with `message`, the action in `blocker`, and `blocker_needs_owner: true`. Verify **Needs me** on readback. Omit the blocker fields for routine updates to preserve an existing handoff. Clear it with an empty `blocker` once the action is resolved. If the work is waiting on another person or event, record that in progress.

Session fields: `id`, `hostId`, `host`, `environment` (`local`, `ssh`, `cloud`, or `unknown`), `status`, `reported_at` (Unix seconds; divide native millisecond timestamps by 1000), `title`, `archived`, `project` (string or null), and `hostAliases` (array). Use the actual native session and host identities, not a fabricated substitute.

Reuse the same key and payload after an uncertain write. On HTTP 409, retrieve current context before choosing another operation. Report metadata only, never transcripts, source code, or secrets. Reporter access cannot queue, pause, share, change prerequisites or reviewers, publish trusted observations, or grant permissions. Preserve existing organizer hooks, relays, pins, and manual placements. Reporting does not prove that a session started or a PR merged.

When the author asks to queue one or more Obsidian drafts for review, verify each open draft's author, head repository, head branch, base branch, and published contents with `gh pr view` or the GitHub API. Report local-only changes before queuing. Reuse the work item linked to the coding session or the delivering PRs. Associate the selected drafts with that item and retrieve its current version and heads. Leave PRs already in review on their existing items.

Queueing for review with named reviewers uses the normal merge preference. Pass the reviewers and `merge_when_ready: true` together for new entries. If the author explicitly requests review only with named reviewers, pass `merge_when_ready: false` and quote that instruction in `review_only_reason`. For reviewer edits on an existing entry, omit the merge choice to preserve it.

Set `merge_when_ready: true` for each newly queued PR unless the author explicitly asks for review only. Set `merge_when_ready: false` on every affected PR for that override. Preserve saved merge choices when refreshing an existing queue unless the author asks to change them. Check `/api/me` for `can_set_merge_intent: true` before recording merge intent. If the credential can only queue reviews, report the authorization gap and use the signed-in owner's Workline controls to record merge intent when available.

Prepare the selected linked PRs with `GET /api/work/WORK_ID/prepare-queue?prs=123,124`. An owner repository connection resolves GitHub heads and stack parents, including parents outside the selection. Use the returned version, expected heads and each ready entry's `input` unchanged in `queue-reviews`, adding authorized merge and reviewer choices. Workline rechecks prepared heads when applying them and carries saved draft prerequisites into the queue. For a session without the repository connection, verify heads, bases and parents directly with GitHub and use the explicit queue input below.

Process independent ready siblings. Skip closed, in-review or already submitted PRs as indicated. Retry unavailable evidence or reprepare changed heads. For an unresolved parent, inspect branch history. Ask the owner once only if the remaining ambiguity changes review or merge eligibility; save the resolved relationship. Allow the scheduled worker to recheck known merge and deployment gates.

If a draft targets a copy of another Obsidian PR's branch, verify which upstream PR supplied the copy and the exact copied commit. Send the upstream PR number as `parent`, the actual copied branch as `base_ref`, and the full copied SHA as `copied_base_sha`. Verify the copy ref still points to that SHA and the commit belongs to the upstream branch history. Workline waits for the upstream merge, replays the draft's changes onto `main`, and retargets the draft. Ask for the copy point only if the branch history leaves it ambiguous.

```json
{
  "action": "queue-reviews",
  "version": 4,
  "expected_heads": {"vantainc/obsidian#123": null, "vantainc/obsidian#124": null},
  "data": {
    "pull_requests": [
      {"number": 123, "head_ref": "foundation", "base_ref": "main", "merge_when_ready": true},
      {"number": 124, "head_ref": "follow-up", "base_ref": "foundation", "merge_when_ready": true}
    ]
  }
}
```

Before queuing, read each PR's description, relevant changes, linked predecessor PRs, and existing Workline prerequisites. Use the implementation context to identify requirements the branch topology misses, such as a configuration change that needs a runtime rollout or a feature enablement that requires post-deploy verification. Confirm the predecessor and rollout against the relevant repository or deployment configuration. A referenced PR is a dependency when the change needs it to land or roll out first.

Put each requirement in the affected PR's `dependencies` array in the same request as the merge choice. Use `scope: "activation"` for merge-only requirements and `scope: "review"` when the PR cannot be reviewed independently. A code gate uses `{"kind":"merged","scope":"activation","target":"vantainc/obsidian#NUMBER","label":"..."}`. A rollout gate uses `kind: "deployed"` with the same target and exact `environment` (`prod` or `staging`), `service` (`app` for the shared app or an exact `infra-<project>` slug), and `region` (`all`). A prerequisite PR can already be in review and can live outside Workline for `queue-reviews`.

For a required condition the runner cannot verify, such as a fresh-session check, or a prerequisite whose identity is still uncertain, add `{"kind":"prerequisite","scope":"activation","label":"<specific evidence still needed>","satisfied":false}`. Do the verification or resolve the ambiguity from available sources when possible. Keep the hold until the required evidence is verified or the owner confirms it. To update a queued gate, resubmit the explicit `dependencies` with current versions and omit `merge_when_ready` to preserve intent. Carry forward the other saved explicit gates and omit the generated review gate for `inferred_parent`. When adding a hold or changing an existing PR to review only, check GitHub for active auto-merge or merge-queue enrollment. Stop any active GitHub submission with the owner's authorization before reporting the merge as held.

Read the item back and report each selected PR's status, merge choice, and pending gates in `review_queue`. A numeric `merge_opted_in_at` means merge when ready, `null` means review only, and an absent field falls back to the item's legacy `merge_when_ready` target if present. Workline releases each draft when its review gates and required CI clear. GitHub enforces approvals, CI, and its merge queue. With reporter access, direct the owner to the account menu to create a coding-session credential for this host.

To test the deployed review worker on demand, POST `{"mode":"rehearsal"}` to `/api/work/WORK_ID/runs` using the Workline helper and a stable operation key. Read `/api/work/WORK_ID/runs/RUN_ID` until it reports completion. For an author-requested live pass on an already queued item, use `{"mode":"live"}`. Retain the same operation key when retrying a lost response.

To verify a repair handoff, read `/api/work/WORK_ID/timeline?pr=OWNER/REPO%23NUMBER` for the linked PR. The timeline distinguishes the requested Ona execution from the commit Workline published.

For an owner-requested audit of **Needs me**, call `POST /api/work/refresh` with an empty JSON object using the authorized Workline helper and a stable operation key. Workline checks saved feedback against GitHub, preserves uncertain or actionable feedback, and updates its own records. Read back the board and inspect remaining owner actions.

When a batch is approved and a named reviewer’s GitHub login is unresolved, queue the entire batch. On the affected PR, send the intended name in `pending_reviewer` alongside its merge choice, prerequisites, and any approved comment. Workline holds that PR and processes its siblings. If the owner wants to mention the pending reviewer in an approved comment, use `{{reviewers}}` where the mentions belong. Saving the verified logins replaces that placeholder with their GitHub mentions. To resolve the hold, send the verified `reviewers` list for that PR in a versioned `queue-reviews` command. Include the current head and base refs and any required stack parent. Omit the merge choice and comment to preserve them. Check the saved entries after each command.

When the author asks to let GitHub assign reviewers, use a merge-capable coding session and send `reviewers: null` on each selected PR in `queue-reviews`. Verify that the saved PR entry in `review_queue` has `"reviewers": null`. Workline leaves reviewer assignment to GitHub and follows the PR's chosen merge policy.

When the author names reviewers, resolve their GitHub logins and include the full list in each selected PR's `reviewers` array in `queue-reviews`. A merge-capable coding session can save reviewers and merge intent in the same request. Omit `reviewers` to preserve the saved choice. Send `reviewers: []` to restore work-item or repository defaults. Verify the saved choice on readback. GitHub's approval rules determine when the PR can merge.

When the author has addressed review feedback and asks to requeue, verify the comments in GitHub. If the full observed batch was addressed, copy that PR's current `review_queue` entry's `feedback` object into `addressed_feedback` on its `queue-reviews` request with a merge-capable credential. Refresh a changed batch before acting. Omit the field while feedback is outstanding.

Use the PR's `notes` field in `queue-reviews` to save lifecycle context and preferences for the Ona repair agent. Edit notes on an existing queue entry with `action: "review-notes"` and `data: {"review_pr":"vantainc/obsidian#NUMBER","notes":"..."}`. An empty string clears the notes. Translate actionable preferences into the existing review, prerequisite, merge, or comment settings when the author authorizes them.

To schedule a review comment, confirm the exact message and destination PR with the author, then pass the confirmed text as `review_comment` on that PR in `queue-reviews`. The worker posts once after the PR is open for review and its configured review and activation gates are clear. Omit `review_comment` to preserve the action or send `null` to cancel it before delivery starts. Read back `review_queue[PR].review_comment` to confirm the approved text and check `posted_id` for delivery. Notes alone supply context to Ona.

When the owner explicitly asks to mark a Workline item done, abandon it, or reopen it, use the versioned `complete`, `abandon`, or `reopen` command with `data: {}` and the item's current expected heads. Use a coding-session credential or that item's controller. Done and abandoned items move to Closed and exit Workline's review queue. Reopening returns them to unfinished work. Read the item back and report its status. These commands update Workline metadata. Manage PR and coding session state separately.

Use `queue-reviews` for one draft, a batch on one item, or each set of drafts already grouped across multiple items. For a stack split across items, verify all layers and their parents first, then queue each item's drafts in bottom-to-top order with `parent` for parents outside its request. Create separate items only when the author asks. Keep each additional gate on its PR so the coding session can update verified prerequisites later.

Trusted Ona CDEs use their short-lived environment identity automatically. Ona CDEs outside a trusted project can use an existing authenticated Vercel CLI to reach Workline with the same identity. On other hosts, the signed-in owner creates a 24-hour coding-session or reporter credential in Workline's account menu. Save it in a private file outside Git. Set config to `{"credential_file":"/absolute/private/workline.key","vercel_command":["vercel"]}` with mode 600. The authenticated Vercel CLI supplies deployment-protection access in addition to the app credential. An existing host-local Vercel token file may be referenced with `vercel_token_file`. An explicit `WORKLINE_CONFIG` uses that local configuration. Existing sessions may need to reload their skills and instructions.

To abandon one PR in a batch, send the versioned `abandon-pr` command with `data: {"repository":"vantainc/obsidian","number":123}` using a merge-capable session. Verify it appears in `abandoned_prs` and the other PRs remain active. To restart it, send `associate` with the same PR and `restore: true`, then queue the restored link with fresh intent. Manage any existing GitHub submission separately.
