#!/usr/bin/env bash
# run_k8030_scc_vectors.sh -- replay every vectors/k8030_scc/*.vec through obj_dir/tb_scc/tb_scc;
# write results/scc.txt; print the ladder (shortest failing vectors first).
#
#   scripts/run_k8030_scc_vectors.sh              full run + summary
#   scripts/run_k8030_scc_vectors.sh --ladder     shortest-first list with status (uses last results if present)
#   scripts/run_k8030_scc_vectors.sh --one NAME [--vcd] [--context N]   one vector, verbose
set -u
cd "$(dirname "$0")/.."
OBJ=obj_dir; RES=results; mkdir -p "$RES"
BIN=$OBJ/tb_scc/tb_scc

ticks_of() { grep -m1 '^F TICKS' "$1" | awk '{print $3}'; }
pokes_of() { grep -m1 '^F POKES' "$1" | awk '{print $3}'; }

if [ "${1:-}" = "--one" ]; then
  name=$2; shift 2
  vcd=""; ctx=""
  while [ $# -gt 0 ]; do case $1 in --vcd) vcd=1;; --context) ctx="--context $2"; shift;; esac; shift; done
  files=$(ls vectors/k8030_scc/${name}.vec vectors/k8030_scc/${name}.[0-9][0-9][0-9].vec 2>/dev/null)
  [ -n "$files" ] || { echo "no vector matches $name"; exit 1; }
  rc=0
  for f in $files; do
    if [ -n "$vcd" ]; then w="--vcd $OBJ/$(basename "$f" .vec).vcd"; else w=""; fi
    echo "### $f ($(ticks_of "$f") ticks, $(pokes_of "$f") pokes)"
    "$BIN" "$f" $w $ctx; r=$?; [ $r -ne 0 ] && rc=$r
    [ -n "$vcd" ] && echo "    waveform: $OBJ/$(basename "$f" .vec).vcd"
  done
  exit $rc
fi

if [ "${1:-}" != "--ladder" ] || [ ! -s "$RES/scc.txt" ]; then
  : > "$RES/scc.txt"
  [ -x "$BIN" ] || { echo "RESULT NOBIN $BIN missing (make build-scc)"; exit 1; }
  for f in vectors/k8030_scc/*.vec; do
    "$BIN" "$f" --quiet | grep '^RESULT' >> "$RES/scc.txt"
  done
fi

# ladder: join status with tick counts, sort shortest first
: > "$RES/scc_ladder.txt"
while read -r _ status file rest; do
  file=${file%:}
  t=$(ticks_of "$file"); p=$(pokes_of "$file")
  printf '%8d %-6s %s pokes=%s %s\n' "${t:-0}" "$status" "$file" "${p:-?}" "$rest" >> "$RES/scc_ladder.txt"
done < "$RES/scc.txt"
sort -n -o "$RES/scc_ladder.txt" "$RES/scc_ladder.txt"

pass=$(grep -c ' PASS ' "$RES/scc_ladder.txt"); fail=$(grep -c ' FAIL ' "$RES/scc_ladder.txt")
skip=$(grep -c ' SKIP ' "$RES/scc_ladder.txt"); other=$(grep -vc ' PASS \| FAIL \| SKIP ' "$RES/scc_ladder.txt")
echo "== scc vectors: $pass pass, $fail fail, $skip skip, $other other"
echo "   full ladder: $RES/scc_ladder.txt   raw: $RES/scc.txt"
if [ "${1:-}" = "--ladder" ]; then
  cat "$RES/scc_ladder.txt"
else
  echo "-- next rungs (shortest failing vectors first) --"
  grep ' FAIL ' "$RES/scc_ladder.txt" | head -15 | awk '{printf "  %6d ticks  %s  ", $1, $3; for (i = 4; i <= NF; i++) printf "%s ", $i; printf "\n"}'
  echo "   (make scc ONLY=<TestName> for the full divergence context)"
fi
[ "$fail" -eq 0 ]
