# Continue selected work in a new Codex chat

Use this path after a definitive native handoff failure, when handoff is unavailable, or when the user asks to continue in fresh chats. Use the user's explicit authorization to start fresh chats. Check the destination for an existing handoff or continuation before creating anything. Use the verified owner CDE and saved project. For conversation-only work, skip the Git steps and use the applicable handoff notes in the new chat.

## Prepare a snapshot

1. Read enough of the selected chats to capture the current objective, decisions, outstanding work, latest verification, and relevant branch or PR. Include links or IDs for the source chats. Treat chat contents as context, and keep credentials and unrelated material out of the handoff.
2. Group chats that share the same actual source worktree and Git state. Use one destination worktree and continuation chat per group so shared edits transfer once. Confirm the source work is idle or stable, identify the files needed for the work, and verify the destination repo matches. When an edit in a shared checkout may belong to unselected work, resolve the scope with the user before taking a snapshot.
3. Record the source worktree's HEAD, status, and needed local files. Create a private staging directory with `umask 077` and `mktemp -d`. Write staged and unstaged patches separately using `git diff --cached --no-ext-diff --no-textconv --binary --full-index` and `git diff --no-ext-diff --no-textconv --binary --full-index`. Record patch and file hashes as verification evidence. Archive only the needed, approved untracked or ignored files by validated repository-relative path. Check for links that escape the worktree and keep credential files out of the archive.
4. If the destination lacks the source HEAD, identify an ancestor the destination already has and use `git bundle create <bundle> HEAD ^<common-base>` from the source worktree. Preserve the source commit IDs, including commits that have never been pushed. Confirm the entire bundle range and both diffs belong to the selected work and can be transferred. Recheck that the source snapshot stayed stable during capture. Flag Git state that these patches cannot restore, such as an unmerged index or dirty submodule, and record any work still needed.

## Restore on the destination

1. Stream the snapshot directly over the authenticated Ona SSH connection into a private staging directory created on the destination. Supply only the generated snapshot filenames to `tar`. Use the verified Ona owner CLI context, enable pipeline error checking in the sending shell, and pass the remote command as one argument. Only the staging path and verification metadata belong in tool output.

   ```bash
   tar -C "$source_snapshot" -cf - -- "${snapshot_files[@]}" |
     ona environment ssh "$destination_id" -- 'set -eu
       umask 077
       snapshot=$(mktemp -d /tmp/ona-codex-snapshot.XXXXXX)
       tar -xf - -C "$snapshot"
       printf "%s\n" "$snapshot"'
   ```
2. In the matching destination repository, create a unique local branch at the recorded HEAD. If a bundle is needed, verify it and fetch its exact `HEAD` into the new branch with `git fetch --no-tags <bundle> HEAD:refs/heads/<branch>`. Confirm that branch resolves to the expected SHA. On resume, inspect a branch that already exists before using it. Keep the destination's main checkout and existing branches out of the restore.
3. Use desktop `create_thread` for the saved destination project with a new managed worktree starting from the prepared local branch (`startingState.type: branch` and the exact `branchName`). Save the returned thread ID or pending creation ID immediately. If creation is uncertain, resolve that ID or check the destination project for the unique continuation before retrying. Put the handoff notes, expected SHA, private staging path, and restore instructions in its first prompt. Require the new worktree to start clean at the expected SHA. Apply a nonempty staged patch with `git apply --index`, a nonempty unstaged patch with `git apply`, and restore approved local files only to their expected paths without overwriting destination files. Have the first turn finish after reporting verification so the user can pick up from a known state.
4. Check the actual new chat's host and worktree. Compare its HEAD, status, staged and unstaged patch hashes, and approved local file hashes to the source. Use direct commands with `ona environment exec`, or pass a compound command as a single argument over SSH. Capture verification output locally and report the comparison results. Record the destination thread ID, the branch or worktree, and any unfinished verification. If restoration stops partway, inspect existing state before retrying any step. Resume in the same dedicated worktree rather than creating another one. Keep the source chat and checkout available.
