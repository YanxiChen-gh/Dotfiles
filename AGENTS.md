# Dotfiles repository instructions

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing this repository. It defines the CI, test-quality, and generated-file policies.

Keep affected CI checks and tests aligned with behavior changes, including intentional removals. Run `./scripts/verify-dotfiles.sh` before handoff or push; `--quick` is only for iteration.

For generated agent instructions, edit `agent-rules/` sources and regenerate rather than editing the outputs.
