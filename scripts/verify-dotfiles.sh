#!/bin/sh
set -e

usage() {
    printf '%s\n' "Usage: $0 [--quick]

Run cheap checks on this Dotfiles repo:
  - sh -n on shell entrypoints
  - node --check on OpenCode plugins (when node is available)
  - shellcheck on those files (if shellcheck is on PATH)
  - sync-claude-skills-to-repo.sh on a temp copy of test-fixtures/minimal-claude-workspace

--quick   Skip integration sync and e2e (syntax + shellcheck + py_compile only)"
}

QUICK=0
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        --quick) QUICK=1 ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; usage >&2; exit 1 ;;
    esac
done

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

errors=0
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    errors=$((errors + 1))
}

pass() {
    printf 'OK:  %s\n' "$*"
}

printf '\n== sh -n (syntax) ==\n'
for f in \
    install.sh \
    install.d/*.sh \
    sync-claude-skills-to-repo.sh \
    sync-cursor-app-to-dotfiles.sh \
    sync-ona-env-to-cursor-cloud.sh \
    scripts/setup_work_github_auth.sh \
    shell/work.sh \
    scripts/verify-dotfiles.sh
do
    if ! sh -n "$f"; then
        fail "sh -n $f"
    else
        pass "sh -n $f"
    fi
done

printf '\n== bash -n (syntax) ==\n'
for f in claude/style-eval-engine.sh claude/*-style/eval/run-eval.sh; do
    if ! bash -n "$f"; then
        fail "bash -n $f"
    else
        pass "bash -n $f"
    fi
done

if command -v node >/dev/null 2>&1; then
    printf '\n== node --check ==\n'
    for f in opencode/plugins/*.js; do
        if ! node --check "$f"; then
            fail "node --check $f"
        else
            pass "node --check $f"
        fi
    done
fi

printf '\n== python3 -m py_compile ==\n'
for f in scripts/sync_cursor_mcp_from_claude.py scripts/sync_opencode_mcp_from_claude.py agent-rules/build.py; do
    if [ -f "$f" ]; then
        if ! python3 -m py_compile "$f"; then
            fail "py_compile $f"
        else
            pass "py_compile $f"
        fi
    fi
done

printf '\n== agent-rules generator (no drift) ==\n'
if [ -f agent-rules/build.py ]; then
    if out=$(python3 agent-rules/build.py --check 2>&1); then
        pass "agent-rules up to date"
    else
        printf '%s\n' "$out"
        fail "agent-rules drift (run: python3 agent-rules/build.py)"
    fi
fi

if command -v shellcheck >/dev/null 2>&1; then
    printf '\n== shellcheck (-S error) ==\n'
    for f in install.sh install.d/*.sh sync-claude-skills-to-repo.sh sync-cursor-app-to-dotfiles.sh sync-ona-env-to-cursor-cloud.sh claude/style-eval-engine.sh claude/*-style/eval/run-eval.sh scripts/setup_work_github_auth.sh shell/work.sh scripts/verify-dotfiles.sh; do
        if out=$(shellcheck -S error -x "$f" 2>&1); then
            pass "shellcheck $f"
        else
            printf '%s\n' "$out" >&2
            fail "shellcheck $f"
        fi
    done
else
    printf '\n== shellcheck (skipped, not installed) ==\n'
    printf '  Install shellcheck for stronger checks: https://github.com/koalaman/shellcheck\n'
fi

if [ "$QUICK" -eq 1 ]; then
    printf '\n== integration (skipped --quick) ==\n'
    printf '\n== e2e (skipped --quick) ==\n'
elif [ "$errors" -ne 0 ]; then
    printf '\n== integration (skipped: fix syntax/shellcheck failures first) ==\n'
    printf '\n== e2e (skipped: fix failures above first) ==\n'
else
    printf '\n== integration (sync-claude-skills-to-repo on fixture copy) ==\n'
    FIXTURE="$ROOT/test-fixtures/minimal-claude-workspace"
    if ! command -v python3 >/dev/null 2>&1; then
        fail "python3 required for integration (SKILL.md @-transform)"
    elif [ ! -d "$FIXTURE/.claude/skills/demo-skill" ]; then
        fail "missing fixture $FIXTURE"
    else
        WORK=$(mktemp -d)
        trap 'rm -rf "$WORK"' EXIT INT TERM
        cp -R "$FIXTURE/." "$WORK/"
        if ! "$ROOT/sync-claude-skills-to-repo.sh" "$WORK" >/tmp/sync-claude-skills-verify.log 2>&1; then
            cat /tmp/sync-claude-skills-verify.log >&2
            fail "sync-claude-skills-to-repo.sh $WORK"
        else
            OUT="$WORK/.cursor/skills/_cc_sync/skills-demo-skill/SKILL.md"
            if [ ! -f "$OUT" ]; then
                fail "expected $OUT"
            elif ! grep -q '## Required context' "$OUT"; then
                fail "transform missing ## Required context in $OUT"
            elif ! grep -q '`README.md`' "$OUT"; then
                fail "transform missing backticked README.md in $OUT"
            else
                pass "cc-sync fixture -> _cc_sync/skills-demo-skill/SKILL.md"
            fi
        fi
        rm -rf "$WORK"
        trap - EXIT INT TERM
    fi

    if [ "$errors" -eq 0 ]; then
        printf '\n== e2e (tests/e2e/run.sh) ==\n'
        if ! sh "$ROOT/tests/e2e/run.sh"; then
            fail "tests/e2e/run.sh"
        else
            pass "tests/e2e/run.sh"
        fi
    fi
fi

printf '\n'
if [ "$errors" -eq 0 ]; then
    printf 'All checks passed.\n'
    exit 0
fi
printf '%d check(s) failed.\n' "$errors"
exit 1
