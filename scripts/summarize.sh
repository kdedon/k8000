#!/usr/bin/env bash
# summarize.sh <label> <results-file>: count RESULT lines and list failures.
label=$1; file=$2
pass=$(grep -c '^RESULT PASS' "$file"); fail=$(grep -c '^RESULT FAIL' "$file")
echo "== $label: $pass pass, $fail fail  (details: $file)"
grep '^RESULT FAIL' "$file" | sed 's/^RESULT //' | head -40
