#!/usr/bin/env bash
# run_k8070_cpu_fpu_vectors.sh -- replay every vectors/k8070_fpu/system/*.vec through
# obj_dir/tb_cpu_fpu_<variant>/tb_cpu_fpu_<variant>; write results/cpu_fpu.txt; print
# the pass/fail count per variant (Z8001 first) and the failures.
#
#   scripts/run_k8070_cpu_fpu_vectors.sh                    full run + summary
#   scripts/run_k8070_cpu_fpu_vectors.sh --one NAME [--vcd] [--context N] [--mclk P]
#
# K8000_TB_FLAGS (e.g. "--mclk 3") is passed to every run.
set -u
cd "$(dirname "$0")/.."
OBJ=obj_dir; RES=results; mkdir -p "$RES"
DIR=vectors/k8070_fpu/system
TBFLAGS=${K8000_TB_FLAGS:-}

bin_of() {
  case $1 in
    *.Z8001.*) echo $OBJ/tb_cpu_fpu_z8001/tb_cpu_fpu_z8001;;
    *.Z8002.*) echo $OBJ/tb_cpu_fpu_z8002/tb_cpu_fpu_z8002;;
  esac
}

if [ "${1:-}" = "--one" ]; then
  name=$2; shift 2
  vcd=""; extra=""
  while [ $# -gt 0 ]; do case $1 in --vcd) vcd=1;; --context|--mclk) extra="$extra $1 $2"; shift;; esac; shift; done
  files=$(ls $DIR/${name}.vec $DIR/${name}.*.vec 2>/dev/null)
  [ -n "$files" ] || { echo "no vector matches $name"; exit 1; }
  rc=0
  for f in $files; do
    if [ -n "$vcd" ]; then w="--vcd $OBJ/$(basename "$f" .vec).vcd"; else w=""; fi
    echo "### $f"
    "$(bin_of "$f")" "$f" $w $extra $TBFLAGS; r=$?; [ $r -ne 0 ] && rc=$r
    [ -n "$vcd" ] && echo "    waveform: $OBJ/$(basename "$f" .vec).vcd"
  done
  exit $rc
fi

: > "$RES/cpu_fpu.txt"
for v in Z8001 Z8002; do
  for f in $DIR/*.$v.*.vec; do
    [ -e "$f" ] || continue
    b=$(bin_of "$f")
    [ -x "$b" ] || { echo "RESULT NOBIN $b missing"; exit 1; }
    "$b" "$f" --quiet $TBFLAGS | grep '^RESULT' >> "$RES/cpu_fpu.txt"
  done
done

for v in Z8001 Z8002; do
  pass=$(grep -c "^RESULT PASS .* $v " "$RES/cpu_fpu.txt"); fail=$(grep -c "^RESULT FAIL .* $v " "$RES/cpu_fpu.txt")
  skip=$(grep -c "^RESULT SKIP .*\.$v\." "$RES/cpu_fpu.txt")
  echo "== cpu+fpu $v: $pass pass, $fail fail, $skip skip"
done
grep -v '^RESULT PASS' "$RES/cpu_fpu.txt" | sed 's/^/  /'
echo "   raw: $RES/cpu_fpu.txt   (make cpu-fpu ONLY=<TestName> for the divergence context)"
! grep -q '^RESULT FAIL' "$RES/cpu_fpu.txt"
