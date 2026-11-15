#!/usr/bin/env bash
# run_vectors.sh CHIP [MODE] -- replay a chip's vector files through its
# harness; write results/<out>.txt and print the summary.
#
#   CHIP: cpu | mmu | scc | cio | fpu | cpu-fpu | fastd | slowd | alu
#   fastd: every FPU and CPU+FPU vector with CLK.D rising every master clock,
#   at --mclk 1 and 1,2,1,3; final state, memory and driven words compared.
#   slowd: the same with CLK.D rising every 8th and every 12th CLK.I rise.
#   (none)                 full run + summary
#   --ladder               shortest-first list with status; reuses the last
#                          results unless a binary or vector is newer
#   --combined             cpu only: CLK rise and fall in one master clock
#   --mclk P               full run at master-clock pattern P (results/<out>_mclkP.txt)
#   --one NAME [--vcd] [--context N] [--mclk P] [--fclk P]   one vector, verbose
#
# Fails unless every vector file gives PASS or SKIP, the SKIP count is the
# mode's expected one, and every vector directory has files. A harness that
# exits without a RESULT line, or prints a RESULT FAIL line anywhere,
# counts as FAIL.
#
#   OBJ, RESULTS     build and results directories (obj_dir, results)
#   K8000_TB_FLAGS   extra harness flags, e.g. "--strict-out", for every mode
#                    but alu; a flag the mode sets itself (--mclk, --combined,
#                    --fastd, --slowd) is rejected
#   K8000_MCLK       the harnesses' default master-clock pattern (1,2,1,3)
#   K8000_JOBS       parallel replays, a cap shared by the replay targets a
#                    make -jN runs at once (half of nproc, divided by N)
#   K8000_TIMEOUT    seconds per replay (120)
set -u
cd "$(dirname "$0")/.."
OBJ=${OBJ:-obj_dir}; RES=${RESULTS:-results}; mkdir -p "$RES"
JOBS=${K8000_JOBS:-$(( ($(nproc) + 1) / 2 ))}
# Under make -jN up to N replay targets run at once: share the cap.
mj=$(printf '%s\n' "${MAKEFLAGS:-}" | grep -o -- '-j *[0-9][0-9]*' | head -1 | tr -dc 0-9)
[ -n "$mj" ] && [ "$mj" -gt 1 ] && JOBS=$(( JOBS / mj > 0 ? JOBS / mj : 1 ))
TBFLAGS=${K8000_TB_FLAGS:-}
CHIP=${1:?usage: run_vectors.sh CHIP [--ladder|--combined|--mclk P|--one NAME ...]}; shift

lc() { echo "$1" | tr 'A-Z' 'a-z'; }
ticks_of() { grep -m1 '^F TICKS' "$1" | awk '{print $3}'; }

# Per chip: vector files, binary per file, results name.
MODE=(); HEAD=ticks; LADDER=1; SKIPNOTE=""
case $CHIP in
  cpu)     DIR=vectors/k800x_cpu/cpu; OUT=cpu; SKIPNOTE=" (snapshot-restore vectors)"
           bin_of() { local v; v=$(lc "$(sed -n '2s/^variant //p' "$1")"); echo "$OBJ/tb_cpu_$v/tb_cpu_$v"; } ;;
  mmu)     DIR=vectors/k8010_mmu; OUT=mmu; bin_of() { echo "$OBJ/tb_mmu/tb_mmu"; } ;;
  scc)     DIR=vectors/k8030_scc; OUT=scc; HEAD=pokes; bin_of() { echo "$OBJ/tb_scc/tb_scc"; } ;;
  cio)     DIR=vectors/k8036_cio; OUT=cio; bin_of() { echo "$OBJ/tb_cio/tb_cio"; } ;;
  fpu)     DIR=vectors/k8070_fpu/fpu; OUT=fpu; bin_of() { echo "$OBJ/tb_fpu/tb_fpu"; } ;;
  cpu-fpu) DIR=vectors/k8070_fpu/system; OUT=cpu_fpu; LADDER=""; HEAD=none
           bin_of() { local v; v=$(lc "$(basename "$1" | cut -d. -f2)"); echo "$OBJ/tb_cpu_fpu_$v/tb_cpu_fpu_$v"; } ;;
  fastd|slowd) DIR="vectors/k8070_fpu/fpu vectors/k8070_fpu/system"; OUT=$CHIP; LADDER=""
           bin_of() { case $1 in *.Z8001.*|*.Z8002.*) echo "$OBJ/tb_cpu_fpu_$(lc "$(basename "$1" | cut -d. -f2)")/tb_cpu_fpu_$(lc "$(basename "$1" | cut -d. -f2)")";;
                                 *) echo "$OBJ/tb_fpu/tb_fpu";; esac; } ;;
  alu)     DIR="vectors/k800x_cpu/alu vectors/k800x_cpu/alu_from_cpu"; OUT=alu; LADDER=""
           bin_of() { echo "$OBJ/tb_alu/tb_alu"; } ;;
  *) echo "unknown chip $CHIP"; exit 4 ;;
esac
files() { for d in $DIR; do ls "$d"/*.vec 2>/dev/null; done; }
for d in $DIR; do
  [ -n "$(ls "$d"/*.vec 2>/dev/null)" ] || { echo "RESULT FAIL $d: no vector files"; exit 1; }
done
# The flags a mode sets itself; K8000_TB_FLAGS may not repeat them.
own_flag() {
  local f
  for f in $TBFLAGS; do case $f in "$@") echo "K8000_TB_FLAGS $f conflicts with the mode's own"; exit 4;; esac; done
}
[ "$CHIP" = alu ] && [ -n "$TBFLAGS" ] && { echo "K8000_TB_FLAGS: the alu bench takes none"; exit 4; }
case $CHIP in fastd|slowd) own_flag --mclk --fastd --slowd --combined;; esac

if [ "${1:-}" = "--one" ]; then
  name=$2; shift 2
  vcd=""; extra=""
  while [ $# -gt 0 ]; do
    case $1 in
      --vcd) vcd=1;;
      --mclk) own_flag --mclk; extra="$extra $1 ${2:?--mclk needs a value}"; shift;;
      --context|--fclk) extra="$extra $1 ${2:?$1 needs a value}"; shift;;
      *) echo "--one: unknown argument $1"; exit 4;;
    esac
    shift
  done
  list=""
  for d in $DIR; do list="$list $(ls "$d/$name.vec" "$d/$name".[0-9][0-9][0-9].vec "$d/$name".Z800[12].*.vec 2>/dev/null)"; done
  [ -n "${list// /}" ] || { echo "no vector matches $name"; exit 1; }
  mkdir -p "$OBJ/vcd/$CHIP"
  rc=0
  for f in $list; do
    w=""; [ -n "$vcd" ] && w="--vcd $OBJ/vcd/$CHIP/$(basename "$f" .vec).vcd"
    case $HEAD in
      ticks) echo "### $f ($(ticks_of "$f") ticks)";;
      pokes) echo "### $f ($(ticks_of "$f") ticks, $(grep -m1 '^F POKES' "$f" | awk '{print $3}') pokes)";;
      *)     echo "### $f";;
    esac
    # shellcheck disable=SC2086
    "$(bin_of "$f")" "$f" $w $TBFLAGS $extra; r=$?; [ $r -ne 0 ] && rc=$r
    [ -n "$vcd" ] && echo "    waveform: $OBJ/vcd/$CHIP/$(basename "$f" .vec).vcd"
  done
  exit $rc
fi

ladder_only=""; nargs=1
case ${1:-} in
  --ladder)   ladder_only=1 ;;
  --combined) [ "$CHIP" = cpu ] || { echo "--combined is cpu only"; exit 4; }
              own_flag --mclk --combined
              OUT=cpu_combined; MODE=(--combined --mclk 1) ;;
  --mclk)     own_flag --mclk; MODE=(--mclk "${2:?--mclk needs a value}"); OUT=${OUT}_mclk${2//,/_}; nargs=2 ;;
  "")         nargs=0 ;;
  *) echo "unknown mode $1"; exit 4 ;;
esac
[ $# -le $nargs ] || { shift $nargs; echo "unexpected arguments: $*"; exit 4; }
RAW=$RES/$OUT.txt
# The run's settings head the results; a ladder reuses them only when equal.
HDR="# run $CHIP ${MODE[*]:-} flags=[$TBFLAGS] mclk=${K8000_MCLK:-default}"

# One replay: exactly one RESULT line per job, FAIL when the harness
# printed none, printed a FAIL anywhere, or exited non-zero after a PASS.
run_one() {
  local b=$1 f=$2 tag=$3 flags=$4 out rc r
  if [ "$b" = timed ]; then echo "RESULT SKIP $f: outcome depends on the Data Processor's speed$tag"; return; fi
  if [ ! -x "$b" ]; then echo "RESULT NOBIN $f: $b missing$tag"; return; fi
  # shellcheck disable=SC2086
  if [ "$CHIP" = alu ]; then out=$(timeout "$TMO" "$b" +vec="$f"); rc=$?
  else out=$(timeout "$TMO" "$b" "$f" --quiet $flags); rc=$?; fi
  r=$(printf '%s\n' "$out" | grep -m1 '^RESULT FAIL')
  [ -n "$r" ] || r=$(printf '%s\n' "$out" | grep -m1 '^RESULT')
  if [ -z "$r" ]; then r="RESULT FAIL $f: exit $rc, no result"
  elif [ $rc -ne 0 ] && [ "${r#RESULT PASS}" != "$r" ]; then r="RESULT FAIL $f: exit $rc after PASS"; fi
  printf '%s%s\n' "$r" "$tag"
}
TMO=${K8000_TIMEOUT:-120}
export -f run_one; export CHIP TMO

# The jobs: bin, file, tag, flags. fastd and slowd skip the files whose
# outcome depends on how fast the Data Processor runs. Fast: a store word
# taken before it is ready, /ABORT a set time after a start, an interrupt
# taken between two given instructions, a store without the /WAIT gate, a
# trap with instructions queued and held.
# Slow: a snapshot taken mid-operation.
TIMED_FAST="TestLostStoreWord TestQueueAbortAtStart TestFPUSystemInterrupt TestFPUSystemStoreWithoutWait TestFPUSystemQueueHoldTrap"
TIMED_SLOW="TestSnapshotMidOperation.000"
jobs() {
  local f m n b d
  for f in $(files); do
    if [ "$CHIP" = fastd ]; then
      n=$(basename "$f"); n=${n%%.*}; b=$(bin_of "$f")
      case " $TIMED_FAST " in *" $n "*) b=timed;; esac
      for m in 1 1,2,1,3; do printf '%s\0%s\0%s\0%s\0' "$b" "$f" " (mclk $m)" "$TBFLAGS --fastd --mclk $m"; done
    elif [ "$CHIP" = slowd ]; then
      n=$(basename "$f" .vec); b=$(bin_of "$f")
      case " $TIMED_SLOW " in *" $n "*) b=timed;; esac
      for d in 8 12; do for m in 1 1,2,1,3; do
        printf '%s\0%s\0%s\0%s\0' "$b" "$f" " (slowd $d mclk $m)" "$TBFLAGS --slowd $d --mclk $m"
      done; done
    else
      printf '%s\0%s\0\0%s\0' "$(bin_of "$f")" "$f" "$TBFLAGS ${MODE[*]:-}"
    fi
  done
}
# SKIPs each mode expects at every master-clock pattern: a vector that
# stops running fails the run. fpu: a poke of internal state; fastd and
# slowd: that poke where it runs and the TIMED_ files, at each setting.
skip_expected() {
  case ${OUT%_mclk*} in
    fpu) echo 1 ;; fastd) echo 18 ;; slowd) echo 8 ;; *) echo 0 ;;
  esac
}
expected() { local n; n=$(files | wc -l); [ "$CHIP" = fastd ] && n=$((2 * n)); [ "$CHIP" = slowd ] && n=$((4 * n)); echo "$n"; }

# Stale: other settings, a binary built since the run started, a vector
# added, changed or deleted since, or a result that is not PASS, FAIL or SKIP.
fresh() {
  [ -s "$RAW" ] || return 1
  local f start
  [ "$(head -1 "$RAW" | sed 's/ start=.*//')" = "$HDR" ] || return 1
  start=$(head -1 "$RAW" | sed -n 's/.* start=//p')
  [ -n "$start" ] || return 1
  for f in $(files | while read -r v; do bin_of "$v"; done | sort -u); do
    [ -e "$f" ] && [ "$(stat -c %Y "$f")" -lt "$start" ] || return 1
  done
  # shellcheck disable=SC2086
  [ -z "$(find $DIR -name '*.vec' -newer "$RAW" | head -1)" ] || return 1
  [ -z "$(grep '^RESULT' "$RAW" | grep -v '^RESULT \(PASS\|FAIL\|SKIP\) ')" ] || return 1
  [ "$(files | sort)" = "$(grep '^RESULT' "$RAW" | awk '{print $3}' | tr -d : | sort -u)" ]
}

if [ -z "$ladder_only" ] || ! fresh; then
  start=$(date +%s)
  { echo "$HDR start=$start"
    jobs | xargs -0 -n4 -P "$JOBS" bash -c 'run_one "$@"' _ | sort -k3,3; } > "$RAW.tmp"
  mv "$RAW.tmp" "$RAW"
fi

n_exp=$(expected); n_got=$(grep -c '^RESULT' "$RAW")
pass=$(grep -c '^RESULT PASS ' "$RAW"); fail=$(grep -c '^RESULT FAIL ' "$RAW")
skip=$(grep -c '^RESULT SKIP ' "$RAW"); other=$((n_got - pass - fail - skip))

if [ -n "$LADDER" ]; then
  LAD=$RES/${OUT}_ladder.txt
  while read -r _ status file rest; do
    file=${file%:}
    t=$(ticks_of "$file")
    if [ "$HEAD" = pokes ]; then
      printf '%8d %-6s %s pokes=%s %s\n' "${t:-0}" "$status" "$file" "$(grep -m1 '^F POKES' "$file" | awk '{print $3}')" "$rest"
    else
      printf '%8d %-6s %s %s\n' "${t:-0}" "$status" "$file" "$rest"
    fi
  done < <(grep '^RESULT' "$RAW") | sort -n > "$LAD"
fi

case $CHIP in
  cio) part=$(grep -c '(partial)' "$RAW")
       echo "== cio vectors: $pass pass, $fail fail, $skip skip ($part partial: compared up to the first non-pin poke)" ;;
  fpu) unc=$(grep -c 'unchecked=' "$RAW")
       echo "== fpu vectors: $pass pass, $fail fail, $skip skip ($unc with final registers the RTL does not hold yet unchecked)" ;;
  cpu-fpu)
       for v in Z8001 Z8002; do
         echo "== cpu+fpu $v: $(grep -c "^RESULT PASS [^ ]*\.$v\." "$RAW") pass, $(grep -c "^RESULT FAIL [^ ]*\.$v\." "$RAW") fail, $(grep -c "^RESULT SKIP [^ ]*\.$v\." "$RAW") skip"
       done ;;
  fastd)
       for g in fpu system; do for m in 1 1,2,1,3; do
         c() { grep "^RESULT $1 vectors/k8070_fpu/$g/" "$RAW" | grep -c "(mclk $m)\$"; }
         echo "== fast CLK.D $g vectors, mclk $m: $(c PASS) pass, $(c FAIL) fail, $(c SKIP) skip"
       done; done ;;
  slowd)
       for g in fpu system; do for d in 8 12; do for m in 1 1,2,1,3; do
         c() { grep "^RESULT $1 vectors/k8070_fpu/$g/" "$RAW" | grep -c "(slowd $d mclk $m)\$"; }
         echo "== slow CLK.D $g vectors, CLK.D 1/$d, mclk $m: $(c PASS) pass, $(c FAIL) fail, $(c SKIP) skip"
       done; done; done ;;
  alu) echo "== alu: $pass pass, $fail fail  (details: $RAW)"
       awk '{for (i = 1; i < NF; i++) { if ($(i+1) == "checks") c += $i; if ($(i+1) == "two-pass),") t += substr($i, 2); if ($(i+1) == "out-of-contract") s += $i }}
         END {printf "   alu: %d records checked (%d in two passes: longs as two words, rotates by 2 as two by 1), %d out-of-contract skipped\n", c, t, s}' "$RAW" ;;
  *)   echo "== ${OUT%_mclk*} vectors: $pass pass, $fail fail, $skip skip$SKIPNOTE, $other other" ;;
esac
[ "$n_got" -eq "$n_exp" ] || echo "   $n_got results for $n_exp vector runs"
[ "$other" -eq 0 ] || grep '^RESULT' "$RAW" | grep -v '^RESULT \(PASS\|FAIL\|SKIP\) ' | sed 's/^/  /'

if [ -n "$LADDER" ]; then
  echo "   full ladder: $LAD   raw: $RAW"
  if [ -n "$ladder_only" ]; then
    cat "$LAD"
  else
    echo "-- next rungs (shortest failing vectors first) --"
    grep ' FAIL ' "$LAD" | head -15 | awk '{printf "  %6d ticks  %s  ", $1, $3; for (i = 4; i <= NF; i++) printf "%s ", $i; printf "\n"}'
    echo "   (make $CHIP ONLY=<TestName> for the full divergence context)"
  fi
elif [ "$CHIP" = alu ]; then
  grep '^RESULT FAIL' "$RAW" | sed 's/^RESULT //' | head -40
else
  grep '^RESULT' "$RAW" | grep -v '^RESULT PASS' | sed 's/^/  /'
  [ "$CHIP" = cpu-fpu ] && echo "   raw: $RAW   (make cpu-fpu ONLY=<TestName> for the divergence context)"
fi
skip_exp=$(skip_expected)
[ "$skip" -eq "$skip_exp" ] || echo "   $skip skipped, $skip_exp expected"
[ "$fail" -eq 0 ] && [ "$other" -eq 0 ] && [ $((pass + skip)) -eq "$n_exp" ] && [ "$n_got" -eq "$n_exp" ] &&
  [ "$skip" -eq "$skip_exp" ]
