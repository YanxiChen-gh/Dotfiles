---
name: codex-session-control
description: Coordinate Codex desktop app sessions across saved local and SSH projects. Use when the user wants to start, check, follow up on, or open a Codex task from another conversation. Requires desktop app tools; does not apply to Orca or generic terminal agents.
---

# Codex session control

Use the model's judgment to turn the user's request into the appropriate session action.
This is a capability guide, not a required sequence or planning process.

## App capabilities

Discover the tools actually available in this conversation. Prefer the desktop app tools
below when exposed; their current schemas are authoritative. Mac sessions may expose
capabilities that a cloud conversation does not. This skill does not supply missing tools,
permissions, or access to arbitrary chats. If a needed capability is unavailable, explain
the specific gap; do not build a CLI bridge or use app UI automation as an assumed fallback.

- `list_projects` returns saved project labels, paths, project IDs, and host IDs. Resolve
  names using fresh results, keeping local and SSH projects distinct. Clarify only real
  ambiguity; never guess IDs or reuse an old host mapping.
- `create_thread` starts a task with a self-contained prompt and a saved project target.
  In its project target, `environment: {type: "local"}` uses the saved project's configured
  host, including an SSH host. It does not move an SSH project onto the coordinator Mac.
  Use a worktree only when the user requests one and the tool supports it.
- A ready creation returns `threadId` and `hostId`. Retain both in the conversation so
  later actions target the same task. A pending `clientThreadId` is not a ready thread ID;
  resolve readiness through supported status/discovery before using thread operations.
- `read_thread` inspects status and recent turns. `wait_threads` waits for completion or
  attention; use bounded waits and retain returned cursors to avoid repeating old results.
  An idle runtime state alone does not establish successful task completion.
- `send_message_to_thread` submits a user-authorized follow-up to an existing task. Its
  interface does not promise a choice between immediate steering and next-turn queuing.
- `navigate_to_codex_page` opens the same thread using its returned ID. Report success
  only when confirmed. Use app-generated links when available; do not invent deep links.

## Context and scope

Launch only work the user has requested. Starting a coordinator conversation or invoking
this skill does not authorize tests, additional workers, or messages to unrelated tasks.
Authorization can cover later steps; do not ask again when the requested action is clear.

Supply the ticket's relevant requirements, acceptance criteria, constraints, and needed
artifact content or accessible references explicitly. A new session should not depend on
unspoken coordinator history. Avoid copying large transcripts. A Mac-local path is not
necessarily accessible to an SSH session; use a supported transfer only when needed and
authorized, or include the needed content in the prompt.

Assume the user has configured the saved Codex connections. Do not add SSH, Ona login,
token, or connectivity preflight. If the requested operation fails, report the operation,
target, error, and whether it failed, remains pending, or has an uncertain outcome. Leave
connection setup to the user unless they request diagnosis. Respect access denials.

Check an uncertain create or send outcome using supported metadata/status before retrying;
do not create duplicate tasks or messages. A completion receipt should identify the actual
task and distinguish launch, work completion, and navigation results.

Return the first useful result promptly. For an inventory, start with relevant project
metadata, read minimal history, and use available pagination within the requested scope.
Disclose result caps, unavailable sources, archive coverage, and unassigned sessions rather
than claiming a complete account-wide list from a bounded response.
