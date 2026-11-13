#!/usr/bin/env bash
# run_sv_bench.sh [-t N] BIN [ARGS...] -- run a self-checking bench, drop its
# $finish line (last N lines only with -t), and fail unless it exits 0,
# prints a RESULT PASS line and no RESULT FAIL line.
set -u
tail_n=""
if [ "${1:-}" = "-t" ]; then tail_n=$2; shift 2; fi
out=$("$@" 2>&1); rc=$?
out=$(printf '%s\n' "$out" | grep -v '\$finish')
if [ -n "$tail_n" ]; then printf '%s\n' "$out" | tail -n "$tail_n"; else printf '%s\n' "$out"; fi
[ $rc -eq 0 ] || exit $rc
printf '%s\n' "$out" | grep -q '^RESULT FAIL' && exit 1
printf '%s\n' "$out" | grep -q '^RESULT PASS' || { echo "no RESULT PASS line"; exit 1; }
exit 0
