#!/usr/bin/env bash
# run_k8070_fpu_vectors.sh -- replay every vectors/k8070_fpu/fpu/*.vec through obj_dir/tb_fpu/tb_fpu;
# write results/fpu.txt; print the ladder (shortest failing vectors first).
#
#   scripts/run_k8070_fpu_vectors.sh              full run + summary
#   scripts/run_k8070_fpu_vectors.sh --ladder     shortest-first list with status
#   scripts/run_k8070_fpu_vectors.sh --one NAME [--vcd] [--context N] [--mclk P]   one vector, verbose
#
# K8000_TB_FLAGS (e.g. "--mclk 3") is passed to every tb_fpu run.
set -u
cd "$(dirname "$0")/.."
OBJ=obj_dir; RES=results; mkdir -p "$RES"
BIN=$OBJ/tb_fpu/tb_fpu
TBFLAGS=${K8000_TB_FLAGS:-}

ticks_of() { grep -m1 '^F TICKS' "$1" | awk '{print $3}'; }

if [ "${1:-}" = "--one" ]; then
  name=$2; shift 2
  vcd=""; extra=""
  while [ $# -gt 0 ]; do case $1 in --vcd) vcd=1;; --context|--mclk) extra="$extra $1 $2"; shift;; esac; shift; done
  files=$(ls vectors/k8070_fpu/fpu/${name}.vec vectors/k8070_fpu/fpu/${name}.[0-9][0-9][0-9].vec 2>/dev/null)
  [ -n "$files" ] || { echo "no vector matches $name"; exit 1; }
  rc=0
  for f in $files; do
    if [ -n "$vcd" ]; then w="--vcd $OBJ/$(basename "$f" .vec).vcd"; else w=""; fi
    echo "### $f ($(ticks_of "$f") ticks)"
    "$BIN" "$f" $w $extra $TBFLAGS; r=$?; [ $r -ne 0 ] && rc=$r
    [ -n "$vcd" ] && echo "    waveform: $OBJ/$(basename "$f" .vec).vcd"
  done
  exit $rc
fi

if [ "${1:-}" != "--ladder" ] || [ ! -s "$RES/fpu.txt" ]; then
  : > "$RES/fpu.txt"
  [ -x "$BIN" ] || { echo "RESULT NOBIN $BIN missing (make build-fpu)"; exit 1; }
  for f in vectors/k8070_fpu/fpu/*.vec; do
    "$BIN" "$f" --quiet $TBFLAGS | grep '^RESULT' >> "$RES/fpu.txt"
  done
fi

: > "$RES/fpu_ladder.txt"
while read -r _ status file rest; do
  file=${file%:}
  t=$(ticks_of "$file")
  printf '%8d %-6s %s %s\n' "${t:-0}" "$status" "$file" "$rest" >> "$RES/fpu_ladder.txt"
done < "$RES/fpu.txt"
sort -n -o "$RES/fpu_ladder.txt" "$RES/fpu_ladder.txt"

pass=$(grep -c ' PASS ' "$RES/fpu_ladder.txt"); fail=$(grep -c ' FAIL ' "$RES/fpu_ladder.txt")
skip=$(grep -c ' SKIP ' "$RES/fpu_ladder.txt"); unc=$(grep -c 'unchecked=' "$RES/fpu_ladder.txt")
echo "== fpu vectors: $pass pass, $fail fail, $skip skip ($unc with final registers the RTL does not hold yet unchecked)"
echo "   full ladder: $RES/fpu_ladder.txt   raw: $RES/fpu.txt"
if [ "${1:-}" = "--ladder" ]; then
  cat "$RES/fpu_ladder.txt"
else
  echo "-- next rungs (shortest failing vectors first) --"
  grep ' FAIL ' "$RES/fpu_ladder.txt" | head -15 | awk '{printf "  %6d ticks  %s  %s %s %s\n", $1, $3, $5, $6, $7}'
  echo "   (make fpu ONLY=<TestName> for the full divergence context)"
fi
