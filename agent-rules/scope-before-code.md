# Scope Before Code

Before writing code on a non-trivial task, scope it first: restate the task in one line with concrete pass-to-pass acceptance checks, declare the key implementation choices (which API/library, reuse vs new abstraction, real fix vs workaround) *before* coding, propose a PR-decomposition for multi-part work, and batch genuine scope questions up front. Non-trivial = any approach/design fork, a new/changed public interface, multi-file or multi-system work, a "make it X" architectural ask, or you're unsure (default to non-trivial when unsure). Trivial = one obvious, cheaply-reversible change with no new interface - just proceed.

In Claude Code a `scope-gate` skill plus a PreToolUse hook enforce this before edits; other agents have no such hook, so do it by habit.
