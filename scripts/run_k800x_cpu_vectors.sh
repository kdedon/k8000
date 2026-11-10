#!/usr/bin/env bash
# run_k800x_cpu_vectors.sh -- replay every vectors/k800x_cpu/cpu/*.vec through the matching
# tb_cpu_<variant> binary; write results/cpu.txt; print the ladder.
#
#   scripts/run_k800x_cpu_vectors.sh              full run + summary
#   scripts/run_k800x_cpu_vectors.sh --ladder     shortest-first list with status (uses last results if fresh)
#   scripts/run_k800x_cpu_vectors.sh --one NAME [--vcd] [--context N]   one vector, verbose
#   scripts/run_k800x_cpu_vectors.sh --combined   full run, rise and fall in one master clock
#                                                 (results/cpu_combined.txt)
set -u
cd "$(dirname "$0")/.."
OBJ=obj_dir; RES=results; mkdir -p "$RES"
OUT=cpu; MODE=()
if [ "${1:-}" = "--combined" ]; then OUT=cpu_combined; MODE=(--combined --mclk 1); shift; fi

variant_of() { sed -n '2s/^variant //p' "$1"; }
ticks_of()   { grep -m1 '^F TICKS' "$1" | awk '{print $3}'; }
bin_for()    { echo "$OBJ/tb_cpu_$(echo "$1" | tr 'A-Z' 'a-z')/tb_cpu_$(echo "$1" | tr 'A-Z' 'a-z')"; }

if [ "${1:-}" = "--one" ]; then
  name=$2; shift 2
  vcd=""; ctx=""
  while [ $# -gt 0 ]; do case $1 in --vcd) vcd=1;; --context) ctx="--context $2"; shift;; esac; shift; done
  files=$(ls vectors/k800x_cpu/cpu/${name}.vec vectors/k800x_cpu/cpu/${name}.[0-9][0-9][0-9].vec 2>/dev/null)
  [ -n "$files" ] || { echo "no vector matches $name"; exit 1; }
  rc=0
  for f in $files; do
    v=$(variant_of "$f"); b=$(bin_for "$v")
    if [ -n "$vcd" ]; then w="--vcd $OBJ/$(basename "$f" .vec).vcd"; else w=""; fi
    echo "### $f ($v, $(ticks_of "$f") ticks)"
    "$b" "$f" $w $ctx; r=$?; [ $r -ne 0 ] && rc=$r
    [ -n "$vcd" ] && echo "    waveform: $OBJ/$(basename "$f" .vec).vcd"
  done
  exit $rc
fi

if [ "${1:-}" != "--ladder" ] || [ ! -s "$RES/$OUT.txt" ]; then
  : > "$RES/$OUT.txt"
  for f in vectors/k800x_cpu/cpu/*.vec; do
    v=$(variant_of "$f"); b=$(bin_for "$v")
    if [ ! -x "$b" ]; then echo "RESULT NOBIN $f: $b missing" >> "$RES/$OUT.txt"; continue; fi
    "$b" "$f" --quiet "${MODE[@]}" | grep '^RESULT' >> "$RES/$OUT.txt"
  done
fi

# ladder: join status with tick counts, sort shortest first
: > "$RES/${OUT}_ladder.txt"
while read -r _ status file rest; do
  file=${file%:}
  t=$(ticks_of "$file")
  printf '%8d %-6s %s %s\n' "${t:-0}" "$status" "$file" "$rest" >> "$RES/${OUT}_ladder.txt"
done < "$RES/$OUT.txt"
sort -n -o "$RES/${OUT}_ladder.txt" "$RES/${OUT}_ladder.txt"

pass=$(grep -c ' PASS ' "$RES/${OUT}_ladder.txt"); fail=$(grep -c ' FAIL ' "$RES/${OUT}_ladder.txt")
skip=$(grep -c ' SKIP ' "$RES/${OUT}_ladder.txt"); other=$(grep -vc ' PASS \| FAIL \| SKIP ' "$RES/${OUT}_ladder.txt")
echo "== $OUT vectors: $pass pass, $fail fail, $skip skip (snapshot-restore vectors), $other other"
echo "   full ladder: $RES/${OUT}_ladder.txt   raw: $RES/$OUT.txt"
if [ "${1:-}" = "--ladder" ]; then
  cat "$RES/${OUT}_ladder.txt"
else
  echo "-- next rungs (shortest failing vectors first) --"
  grep ' FAIL ' "$RES/${OUT}_ladder.txt" | head -15 | awk '{printf "  %6d ticks  %s  %s %s %s\n", $1, $3, $5, $6, $7}'
  echo "   (make cpu ONLY=<TestName> for the full divergence context)"
fi
