---
name: ona-session-migration
description: Create a fresh Ona owner environment and move selected Codex desktop chats and their Git state from the current Ona environment. Use when the user asks to move to a new Ona environment or resume an interrupted Codex migration.
---

# Move selected Codex chats to a fresh Ona environment

Run from a Codex desktop chat on the source Ona host. Use the Ona CLI for provisioning and the desktop app's native project, history, and handoff tools for chats. Discover the actual tools first. If native handoff is unavailable, surface that before creating an environment.

## Pick the chats

- Use Codex `list_threads` in history mode on the source host. Show up to 10 eligible chats by `updatedAt`, newest first, with their original titles, project names, times, and a running indicator. Page beyond the shortlist only on request or to resolve a named chat. Include archived history only when requested. Exclude the coordinator chat, which cannot hand itself off.
- Resolve the user's selection to exact thread IDs and saved Git projects. If they already supplied an unambiguous list, use it. Wait for the selection before provisioning. Handoff interrupts an active turn, so distinguish waiting for an idle chat from permission to interrupt it.

## Provision and connect

1. Resolve the source Ona environment ID from its confirmed Codex host or the Ona CLI's current environment. Use `ona environment get <source-id> -o json` and project only `metadata.projectId`, `metadata.organizationId`, and `metadata.creator.id` before displaying output. Compare that organization and owner to the account ID and organization ID from `ona whoami -o json`. If an injected token is rejected or resolves to an environment identity, check the signed-in CLI context with `env -u ONA_TOKEN -u GITPOD_TOKEN ona whoami -o json`. Use the verified owner context consistently for subsequent calls. If needed, ask the user to complete `env -u ONA_TOKEN -u GITPOD_TOKEN ona login` in their terminal.
2. Create one destination from the source project with `ona environment create <project-id> --name <unique-name> --dont-wait`. Keep the destination ID and selected chat IDs in the conversation. If the response is uncertain, look up the exact chosen name and verify the project and owner before retrying. On resume, reuse the recorded destination and continue from each chat's last verified step. Verify that the destination has the expected creator and project, and wait for `status.phase` to reach `ENVIRONMENT_PHASE_RUNNING` using `ona environment get <destination-id> -o json`.
3. Allow the existing Ona SSH importer time to discover the host, then refresh Codex `list_projects`. Match the actual destination environment ID to a saved host and verify a saved project for the same Git repository and repository-relative subdirectory as each source project. The handoff tool must also expose that destination host ID. If discovery is still pending after a few minutes, give the user the destination ID and the desktop step to add or enable the Ona SSH host and save the matching project folder. Resume from the existing destination when it becomes visible. If a host is discovered but the handoff tool still omits it, report that separately. For an existing SSH alias on the user's desktop, the [Codex add-host link](https://learn.chatgpt.com/docs/reference/commands#settings) can open the connection setup.

## Move and verify

- Immediately before each move, recheck the source chat's activity and working directory. Record Git HEAD, status, and hashes of the staged and unstaged diffs and any needed untracked files. Flag dependencies on ignored files or local artifacts for separate handling. If a shared checkout contains changes outside the selection, resolve that with the user before transferring its Git state.
- Call native `handoff_thread` with the exact destination host ID. Keep the returned operation ID and revision, then wait with `get_handoff_status`. If a status response is lost, read the same operation again. If the dispatch response is lost, check source and destination history and leave the outcome uncertain if it cannot be established. Avoid redispatching an unresolved move. Never use a same-host handoff or a new chat as a substitute for a cross-host move.
- Verify the moved conversation in the destination host's chat history. Compare its worktree against the source snapshot using an authorized route such as `ona environment exec <destination-id> --working-dir <destination-cwd> -- git status --short`. Report any Git state or files that need attention, and distinguish an available chat from pending Git verification.
- Report the new environment ID and each selected chat's destination and verification result, including any pending or failed moves. Leave retirement of the old environment to a separate request.
