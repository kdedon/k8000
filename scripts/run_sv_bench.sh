#!/usr/bin/env bash
# run_sv_bench.sh [-t N] BIN [ARGS...] -- run a self-checking bench, drop its
# $finish line, and fail unless it exits 0, prints a RESULT PASS line and no
# RESULT FAIL line. -t N prints only the last N lines of a passing run; a
# failing run prints everything. K8000_TIMEOUT (seconds, default 1800)
# bounds the run.
set -u
tail_n=""
if [ "${1:-}" = "-t" ]; then tail_n=$2; shift 2; fi
tmo=${K8000_TIMEOUT:-1800}
out=$(timeout "$tmo" "$@" 2>&1); rc=$?
[ $rc -eq 124 ] && out="$out
timed out after $tmo s"
out=$(printf '%s\n' "$out" | grep -v '\$finish')
ok=1
if [ $rc -ne 0 ]; then ok=""
elif printf '%s\n' "$out" | grep -q '^RESULT FAIL'; then ok=""; rc=1
elif ! printf '%s\n' "$out" | grep -q '^RESULT PASS'; then ok=""; rc=1; out="$out
no RESULT PASS line"; fi
if [ -n "$tail_n" ] && [ -n "$ok" ]; then printf '%s\n' "$out" | tail -n "$tail_n"; else printf '%s\n' "$out"; fi
exit $rc
