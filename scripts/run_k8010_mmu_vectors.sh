#!/usr/bin/env bash
# run_k8010_mmu_vectors.sh -- replay every vectors/k8010_mmu/*.vec through obj_dir/tb_mmu/tb_mmu;
# write results/mmu.txt; print the ladder (shortest failing vectors first).
#
#   scripts/run_k8010_mmu_vectors.sh              full run + summary
#   scripts/run_k8010_mmu_vectors.sh --ladder     shortest-first list with status (uses last results if fresh)
#   scripts/run_k8010_mmu_vectors.sh --one NAME [--vcd] [--context N]   one vector, verbose
set -u
cd "$(dirname "$0")/.."
OBJ=obj_dir; RES=results; mkdir -p "$RES"
BIN=$OBJ/tb_mmu/tb_mmu

ticks_of() { grep -m1 '^F TICKS' "$1" | awk '{print $3}'; }

if [ "${1:-}" = "--one" ]; then
  name=$2; shift 2
  vcd=""; ctx=""
  while [ $# -gt 0 ]; do case $1 in --vcd) vcd=1;; --context) ctx="--context $2"; shift;; esac; shift; done
  files=$(ls vectors/k8010_mmu/${name}.vec vectors/k8010_mmu/${name}.[0-9][0-9][0-9].vec 2>/dev/null)
  [ -n "$files" ] || { echo "no vector matches $name"; exit 1; }
  rc=0
  for f in $files; do
    if [ -n "$vcd" ]; then w="--vcd $OBJ/$(basename "$f" .vec).vcd"; else w=""; fi
    echo "### $f ($(ticks_of "$f") ticks)"
    "$BIN" "$f" $w $ctx; r=$?; [ $r -ne 0 ] && rc=$r
    [ -n "$vcd" ] && echo "    waveform: $OBJ/$(basename "$f" .vec).vcd"
  done
  exit $rc
fi

if [ "${1:-}" != "--ladder" ] || [ ! -s "$RES/mmu.txt" ]; then
  : > "$RES/mmu.txt"
  if [ ! -x "$BIN" ]; then echo "$BIN missing (make build-mmu)"; exit 1; fi
  for f in vectors/k8010_mmu/*.vec; do
    "$BIN" "$f" --quiet | grep '^RESULT' >> "$RES/mmu.txt"
  done
fi

# ladder: join status with tick counts, sort shortest first
: > "$RES/mmu_ladder.txt"
while read -r _ status file rest; do
  file=${file%:}
  t=$(ticks_of "$file")
  printf '%8d %-6s %s %s\n' "${t:-0}" "$status" "$file" "$rest" >> "$RES/mmu_ladder.txt"
done < "$RES/mmu.txt"
sort -n -o "$RES/mmu_ladder.txt" "$RES/mmu_ladder.txt"

pass=$(grep -c ' PASS ' "$RES/mmu_ladder.txt"); fail=$(grep -c ' FAIL ' "$RES/mmu_ladder.txt")
skip=$(grep -c ' SKIP ' "$RES/mmu_ladder.txt"); other=$(grep -vc ' PASS \| FAIL \| SKIP ' "$RES/mmu_ladder.txt")
echo "== mmu vectors: $pass pass, $fail fail, $skip skip, $other other"
echo "   full ladder: $RES/mmu_ladder.txt   raw: $RES/mmu.txt"
if [ "${1:-}" = "--ladder" ]; then
  cat "$RES/mmu_ladder.txt"
else
  echo "-- next rungs (shortest failing vectors first) --"
  grep ' FAIL ' "$RES/mmu_ladder.txt" | head -15 | awk '{printf "  %6d ticks  %s  %s %s %s\n", $1, $3, $5, $6, $7}'
  echo "   (make mmu ONLY=<TestName> for the full divergence context)"
fi
