#!/usr/bin/env bash
# run_k8070_fastd.sh -- every FPU and CPU+FPU vector with CLK.D rising every
# master clock (--fastd), at --mclk 1 and 1,2,1,3; results/fastd.txt. Pins are
# not compared, the final state, memory and driven words are. The six files
# whose outcome depends on how fast the Data Processor runs are skipped; at 5
# or more master clocks a level, TestQueueAbort and TestSnapshotMidOperation.000
# depend on it too.
set -u
cd "$(dirname "$0")/.."
OBJ=obj_dir; RES=results; mkdir -p "$RES"
# A store word taken before it is ready, /ABORT a set time after a start, an
# interrupt taken between two given instructions, a store without the /WAIT gate.
TIMED="TestLostStoreWord TestQueueAbortAtStart TestFPUSystemInterrupt TestFPUSystemStoreWithoutWait"

timed() {
  local n; n=$(basename "$1"); n=${n%%.*}
  for t in $TIMED; do [ "$n" = "$t" ] && return 0; done
  return 1
}

: > "$RES/fastd.txt"
for m in 1 1,2,1,3; do
  for f in vectors/k8070_fpu/fpu/*.vec vectors/k8070_fpu/system/*.vec; do
    if timed "$f"; then echo "RESULT SKIP $f: outcome depends on the Data Processor's speed (mclk $m)" >> "$RES/fastd.txt"; continue; fi
    case $f in
      *.Z8001.*) b=$OBJ/tb_cpu_fpu_z8001/tb_cpu_fpu_z8001;;
      *.Z8002.*) b=$OBJ/tb_cpu_fpu_z8002/tb_cpu_fpu_z8002;;
      *)         b=$OBJ/tb_fpu/tb_fpu;;
    esac
    [ -x "$b" ] || { echo "RESULT NOBIN $b missing"; exit 1; }
    "$b" "$f" --quiet --fastd --mclk $m | grep '^RESULT' | sed "s/\$/ (mclk $m)/" >> "$RES/fastd.txt"
  done
done

for g in fpu system; do
  for m in 1 1,2,1,3; do
    pass=$(grep "^RESULT PASS vectors/k8070_fpu/$g/" "$RES/fastd.txt" | grep -c "(mclk $m)\$")
    fail=$(grep "^RESULT FAIL vectors/k8070_fpu/$g/" "$RES/fastd.txt" | grep -c "(mclk $m)\$")
    skip=$(grep "^RESULT SKIP vectors/k8070_fpu/$g/" "$RES/fastd.txt" | grep -c "(mclk $m)\$")
    echo "== fast CLK.D $g vectors, mclk $m: $pass pass, $fail fail, $skip skip"
  done
done
grep -v '^RESULT PASS' "$RES/fastd.txt" | sed 's/^/  /'
! grep -q '^RESULT FAIL' "$RES/fastd.txt"
