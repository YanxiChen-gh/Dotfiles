# Contributing to Dotfiles

## Before handing off a change

1. From the repo root, run **`./scripts/verify-dotfiles.sh`** before handing off or pushing a change. This is the same command CI runs (syntax, optional shellcheck, fixture integration, and e2e tests under `tests/e2e/`). Fix related failures and report any remaining unrelated failures.
2. For a faster loop while iterating: **`./scripts/verify-dotfiles.sh --quick`** (skips integration and e2e; still catches shell syntax errors). `--quick` is not final verification.

## CI

The **[`ci` workflow](.github/workflows/ci.yml)** must stay green before merging. It runs `./scripts/verify-dotfiles.sh` with `python3` available.

When you add or change:

- **Shell entrypoints** used by installers or sync - extend `scripts/verify-dotfiles.sh` (`sh -n` / shellcheck lists) if you introduce a new top-level script.
- **Behavior covered by e2e** - update affected cases under `tests/e2e/test_*.sh` in the same change, including when behavior is intentionally removed. Delete obsolete assertions rather than restoring removed behavior to satisfy a stale test.
- **New Python helpers** invoked from shell - add a `py_compile` line in `verify-dotfiles.sh` (or fold them into e2e) so broken syntax fails locally and in CI.

Keep **one** primary verify entrypoint (`verify-dotfiles.sh`) so local runs and CI stay aligned.

## Test quality

Keep tests focused on observable behavior, scope isolation, error handling, and preservation of user files. Avoid assertions on exact documentation wording, headings, or implementation source text.

Run mutating generator and installer scenarios in disposable fixtures or temporary homes, not against the working checkout or real user configuration.

## Generated agent instructions

Never hand-edit generated Claude, Codex, OpenCode, or Cursor instruction files. Change the sources under `agent-rules/`, run `python3 agent-rules/build.py`, and include the regenerated outputs in the same change.
