# RTK - Rust Token Killer

**Usage**: Token-optimized CLI proxy (60-90% savings on dev operations)

## Meta Commands (always use rtk directly)

```bash
rtk gain              # Show token savings analytics
rtk gain --history    # Show command usage history with savings
rtk discover          # Analyze agent history for missed opportunities
rtk proxy <cmd>       # Execute raw command without filtering (for debugging)
```

## Installation Verification

```bash
rtk --version         # Should show: rtk X.Y.Z
rtk gain              # Should work (not "command not found")
which rtk             # Verify correct binary
```

**Name collision**: If `rtk gain` fails, you may have reachingforthejack/rtk (Rust Type Kit) installed instead. Reinstall from https://github.com/rtk-ai/rtk.

## Hook-Based Usage

Shell commands are automatically rewritten by the agent hook.
Example: `git status` → `rtk git status` (transparent, zero instruction overhead)

Built-in Read/Grep/Glob tools are not rewritten — prefer shell commands or explicit `rtk read` / `rtk grep` when compact output matters.
