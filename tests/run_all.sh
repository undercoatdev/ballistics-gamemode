#!/bin/sh
# Runs every luajit test in tests/. Exits non-zero if any of them fails.
# Run from anywhere: sh tests/run_all.sh
cd "$(dirname "$0")/.." || exit 2

if ! command -v luajit >/dev/null 2>&1; then
	echo "luajit not found"
	exit 2
fi

log=$(mktemp) || exit 2
pass=0
failed=""
for f in tests/*.lua; do
	if luajit "$f" >"$log" 2>&1; then
		pass=$((pass + 1))
	else
		echo "=== FAIL $f ==="
		grep -v '^ok ' "$log"
		failed="$failed $f"
	fi
done
rm -f "$log"

echo "luajit: $pass passed$( [ -n "$failed" ] && echo ", failed:$failed" )"
[ -z "$failed" ]
