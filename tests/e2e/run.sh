#!/bin/sh
# Run all e2e tests in this directory (test_*.sh).
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

failed=0
for t in "$ROOT/tests/e2e"/test_*.sh; do
	[ -f "$t" ] || continue
	echo "==> $(basename "$t")"
	if sh "$t"; then
		echo "    ok"
	else
		failed=$((failed + 1))
		echo "    FAILED" >&2
	fi
done

if [ "$failed" -ne 0 ]; then
	echo "" >&2
	echo "$failed test file(s) failed." >&2
	exit 1
fi

echo ""
echo "All e2e tests passed."
