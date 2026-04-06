# Contributing to Dotfiles

## Before you open a PR

1. From the repo root, run **`./scripts/verify-dotfiles.sh`** and fix anything it reports. This is the same command CI runs (syntax, optional shellcheck, fixture integration, and e2e tests under `tests/e2e/`).
2. For a faster loop while iterating: **`./scripts/verify-dotfiles.sh --quick`** (skips integration and e2e; still catches shell syntax errors).

## CI

The **[`ci` workflow](.github/workflows/ci.yml)** must stay green before merging. It runs `./scripts/verify-dotfiles.sh` with `python3` available.

When you add or change:

- **Shell entrypoints** used by installers or sync — extend `scripts/verify-dotfiles.sh` (`sh -n` / shellcheck lists) if you introduce a new top-level script.
- **Behavior covered by e2e** — add or update cases under `tests/e2e/test_*.sh` and ensure `tests/e2e/run.sh` still passes.
- **New Python helpers** invoked from shell — add a `py_compile` line in `verify-dotfiles.sh` (or fold them into e2e) so broken syntax fails locally and in CI.

Keep **one** primary verify entrypoint (`verify-dotfiles.sh`) so local runs and CI stay aligned.
