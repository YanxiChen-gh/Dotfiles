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

Registration JSON is `{"title":"...","purpose":"..."}` with optional `pr: {"repository":"OWNER/REPO","number":123}` and `session`. Retrieve the item before a command. Command JSON is `{"action":"progress","version":CURRENT_VERSION,"expected_heads":HEADS,"data":{"message":"..."}}`; optional `data.blocker` reports a blocker. Build `HEADS` from every current PR using `"OWNER/REPO#NUMBER": head`, preserving null values. Other reporter actions are `associate` with `{repository,number}` and `session` with the complete session object.

Session fields: `id`, `hostId`, `host`, `environment` (`local`, `ssh`, `cloud`, or `unknown`), `status`, `reported_at` (Unix seconds; divide native millisecond timestamps by 1000), `title`, `archived`, `project` (string or null), and `hostAliases` (array). Use the actual native session and host identities, not a fabricated substitute.

Reuse the same key and payload after an uncertain write. On HTTP 409, retrieve current context before choosing another operation. Report metadata only, never transcripts, source code, or secrets. Reporter access cannot queue, pause, share, change prerequisites or reviewers, publish trusted observations, or grant permissions. Preserve existing organizer hooks, relays, pins, and manual placements. Reporting does not prove that a session started or a PR merged.

When the author explicitly asks to queue a draft for review, verify the current GitHub PR is their open draft and contains the changes they intend to review. If intended changes are still local, report that before queuing. Reuse the linked Workline item, or register it as unfinished first. With a coding-session credential or the item's controller, submit the same versioned command with `action: "queue"` and `data: {}`. Report the observed Workline status after a successful command. With reporter access, direct the owner to the account menu to create a coding-session credential for this host. The owner can also queue the item at `https://workline-bice.vercel.app/?work=WORK_ID`.

Trusted Ona CDEs use their short-lived environment identity automatically. Ona CDEs outside a trusted project can use an existing authenticated Vercel CLI to reach Workline with the same identity. On other hosts, the signed-in owner creates a 24-hour coding-session or reporter credential in Workline's account menu. Save it in a private file outside Git. Set config to `{"credential_file":"/absolute/private/workline.key","vercel_command":["vercel"]}` with mode 600. The authenticated Vercel CLI supplies deployment-protection access in addition to the app credential. An existing host-local Vercel token file may be referenced with `vercel_token_file`. An explicit `WORKLINE_CONFIG` uses that local configuration. Existing sessions may need to reload their skills and instructions.
