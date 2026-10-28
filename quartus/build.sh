#!/usr/bin/env bash
# Fit one unit on Cyclone V and summarize area and timing.
#   quartus/build.sh <unit> [period_ns]     unit: regfile | alu | mult | div | shift | execute | cpu
# Default period is 48 MHz, an exact multiple of every C900 clock.
# Uses quartus_sh on PATH, else the pinned Quartus Lite 17.0.2 image.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
image="${QUARTUS_IMAGE:-theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70}"
unit="${1:?usage: $0 <unit> [period_ns]}"
period="${2:-20.833}"

case "${unit}" in
  regfile) srcs=(rtl/k800x_cpu/z8000_regfile.sv) ;;
  alu)     srcs=(rtl/k800x_cpu/gen/z8000_ctrl_pkg.sv rtl/k800x_cpu/z8000_alu.sv) ;;
  mult)    srcs=(rtl/k800x_cpu/z8000_mult.sv) ;;
  div)     srcs=(rtl/k800x_cpu/z8000_div.sv) ;;
  shift)   srcs=(rtl/k800x_cpu/gen/z8000_ctrl_pkg.sv rtl/k800x_cpu/z8000_shift.sv) ;;
  execute) srcs=(rtl/k800x_cpu/gen/z8000_ctrl_pkg.sv
                 rtl/k800x_cpu/z8000_{regfile,alu,execute}.sv) ;;
  cpu)     srcs=(rtl/k800x_cpu/gen/z8000_ctrl_pkg.sv rtl/k800x_cpu/gen/z8000_zbus_pkg.sv
                 rtl/k800x_cpu/gen/z8000_mc_pkg.sv rtl/k800x_cpu/gen/z8000_decode_rom_gen.sv rtl/k800x_cpu/gen/z8000_mc_rom_gen.sv
                 rtl/k800x_cpu/z8000_{regfile,decode,bus_unit,sequencer,cond,refresh,alu,execute,cpu}.sv) ;;
  *) echo "unknown unit: ${unit}" >&2; exit 2 ;;
esac
top="z8000_${unit}_measure"
srcs+=("quartus/measure/${top}.sv")

work="obj_dir/quartus/${unit}"
rm -rf "${repo:?}/${work}"
mkdir -p "${repo}/${work}" "${repo}/results/quartus"

{
  echo 'set_global_assignment -name FAMILY "Cyclone V"'
  echo 'set_global_assignment -name DEVICE 5CSEBA6U23I7'
  echo "set_global_assignment -name TOP_LEVEL_ENTITY ${top}"
  echo 'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files'
  echo 'set_global_assignment -name SEED 1'
  echo 'set_global_assignment -name NUM_PARALLEL_PROCESSORS 4'
  echo 'set_global_assignment -name SDC_FILE unit.sdc'
  for s in "${srcs[@]}"; do echo "set_global_assignment -name SYSTEMVERILOG_FILE ../../../${s}"; done
  echo 'set_location_assignment PIN_V11 -to clk'
  echo 'set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk'
  for p in 'in_i[*]' 'out_o[*]'; do echo "set_instance_assignment -name VIRTUAL_PIN ON -to ${p}"; done
} > "${repo}/${work}/unit.qsf"
echo 'PROJECT_REVISION = "unit"' > "${repo}/${work}/unit.qpf"
cat > "${repo}/${work}/unit.sdc" <<EOF
create_clock -name clk -period ${period} [get_ports {clk}]
derive_clock_uncertainty
# Boundary flops stand in for neighbours; only paths between them are timed.
set_false_path -from [get_ports {in_i[*]}]
set_false_path -to   [get_ports {out_o[*]}]
EOF

# The three worst setup paths in each slow corner, cell by cell.
cat > "${repo}/${work}/paths.tcl" <<'EOF'
project_open unit
create_timing_netlist
read_sdc
foreach cond [get_available_operating_conditions] {
  if {![string match *slow* $cond]} { continue }
  set_operating_conditions $cond
  update_timing_netlist
  report_timing -setup -npaths 3 -detail full_path -append -file paths.txt
}
EOF

# quartus <tool> <args...>: run a Quartus tool in the unit's work directory.
quartus() {
  if command -v "$1" >/dev/null 2>&1; then
    (cd "${repo}/${work}" && "$@")
  else
    docker run --rm --user "$(id -u):$(id -g)" --volume "${repo}:/work" --workdir "/work/${work}" \
      "${image}" "/opt/intelFPGA_lite/quartus/bin/$1" "${@:2}"
  fi
}

quartus quartus_sh --flow compile unit -c unit > "${repo}/${work}/flow.log" 2>&1 ||
  { tail -40 "${repo}/${work}/flow.log"; exit 1; }
quartus quartus_sta -t paths.tcl > "${repo}/${work}/paths.log" 2>&1 ||
  { tail -20 "${repo}/${work}/paths.log"; exit 1; }

out="${repo}/${work}/output_files"
if ! grep -Eq 'Implemented 1 input pins' "${out}/unit.map.rpt" ||
   ! grep -Eq 'Implemented 0 output pins' "${out}/unit.map.rpt"; then
  echo "ERROR: physical pins used; check the VIRTUAL_PIN assignments" >&2; exit 1
fi

summary="${repo}/results/quartus/${unit}.txt"
{
  echo "unit ${unit}  period ${period} ns  $(date -I)"
  grep -E 'Logic utilization|Total registers|Total block memory bits|Total DSP Blocks' "${out}/unit.fit.summary"
  grep -E 'Worst-case (setup|hold) slack|Timing requirements (not )?met' "${out}/unit.sta.rpt" | sort -u
  grep -A3 '; Fmax' "${out}/unit.sta.rpt" | grep -E '^; [0-9]' | head -4
  grep -E '^(Critical )?Warning' "${out}"/unit.{map,fit,sta}.rpt | sed 's/^/  /'
  echo "worst setup paths (slack from -> to; detail in ${unit}_paths.txt):"
  grep -E '^; -?[0-9.]+ +; ' "${repo}/${work}/paths.txt" |
    awk -F';' 'NF >= 10 && $5 ~ /[a-z]/ {gsub(/ +/, "", $2); gsub(/ +/, "", $3); gsub(/ +/, "", $4); print $2, $3, "->", $4}' |
    sort -n | head -3 | sed 's/^/  /'
} > "${summary}"
cp "${repo}/${work}/paths.txt" "${repo}/results/quartus/${unit}_paths.txt"
cat "${summary}"
