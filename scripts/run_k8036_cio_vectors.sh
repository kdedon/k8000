#!/usr/bin/env bash
# run_k8036_cio_vectors.sh -- replay every vectors/k8036_cio/*.vec through obj_dir/tb_cio/tb_cio;
# write results/cio.txt; print the ladder (shortest failing vectors first).
#
#   scripts/run_k8036_cio_vectors.sh              full run + summary
#   scripts/run_k8036_cio_vectors.sh --ladder     shortest-first list with status
#   scripts/run_k8036_cio_vectors.sh --one NAME [--vcd] [--context N] [--fclk N]   one vector, verbose
#
# K8000_TB_FLAGS (e.g. "--fclk 3 --strict-out") is passed to every tb_cio run.
set -u
cd "$(dirname "$0")/.."
OBJ=obj_dir; RES=results; mkdir -p "$RES"
BIN=$OBJ/tb_cio/tb_cio
TBFLAGS=${K8000_TB_FLAGS:-}

ticks_of() { grep -m1 '^F TICKS' "$1" | awk '{print $3}'; }

if [ "${1:-}" = "--one" ]; then
  name=$2; shift 2
  vcd=""; extra=""
  while [ $# -gt 0 ]; do case $1 in --vcd) vcd=1;; --context|--fclk) extra="$extra $1 $2"; shift;; esac; shift; done
  files=$(ls vectors/k8036_cio/${name}.vec vectors/k8036_cio/${name}.[0-9][0-9][0-9].vec 2>/dev/null)
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

if [ "${1:-}" != "--ladder" ] || [ ! -s "$RES/cio.txt" ]; then
  : > "$RES/cio.txt"
  [ -x "$BIN" ] || { echo "RESULT NOBIN $BIN missing (make build-cio)"; exit 1; }
  for f in vectors/k8036_cio/*.vec; do
    "$BIN" "$f" --quiet $TBFLAGS | grep '^RESULT' >> "$RES/cio.txt"
  done
fi

: > "$RES/cio_ladder.txt"
while read -r _ status file rest; do
  file=${file%:}
  t=$(ticks_of "$file")
  printf '%8d %-6s %s %s\n' "${t:-0}" "$status" "$file" "$rest" >> "$RES/cio_ladder.txt"
done < "$RES/cio.txt"
sort -n -o "$RES/cio_ladder.txt" "$RES/cio_ladder.txt"

pass=$(grep -c ' PASS ' "$RES/cio_ladder.txt"); fail=$(grep -c ' FAIL ' "$RES/cio_ladder.txt")
skip=$(grep -c ' SKIP ' "$RES/cio_ladder.txt"); part=$(grep -c '(partial)' "$RES/cio_ladder.txt")
echo "== cio vectors: $pass pass, $fail fail, $skip skip ($part partial: compared up to the Go test's first non-pin poke)"
echo "   full ladder: $RES/cio_ladder.txt   raw: $RES/cio.txt"
if [ "${1:-}" = "--ladder" ]; then
  cat "$RES/cio_ladder.txt"
else
  echo "-- next rungs (shortest failing vectors first) --"
  grep ' FAIL ' "$RES/cio_ladder.txt" | head -15 | awk '{printf "  %6d ticks  %s  %s %s %s\n", $1, $3, $5, $6, $7}'
  echo "   (make cio ONLY=<TestName> for the full divergence context)"
fi
