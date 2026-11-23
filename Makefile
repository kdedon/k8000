# k8000 -- Z8000 CPU and peripherals in SystemVerilog, verified in lockstep
# against the committed vectors under vectors/.
#
#   make lint       verilator -Wall on every RTL module and fit wrapper
#   make build      build every testbench: CPU units and variants, MMU, SCC, CIO, FPU, CPU+FPU
#   make test       run everything, print the pass/fail ladder
#   make gen        rebuild the generated RTL from its sources (tools/)
#   make check-gen  fail if a generated RTL file differs from its source
#   make test-<x>   one bench: decode | decode-table | mc-table | alu | regfile | serial | refresh | cpu |
#                   cpu-combined (also gapped: --mclk 2, 1,2,1,3) | cpu-timing | cpu-cycles | cpu-silicon | cpu-programs | cpu-late-read | seq-words | seq-paths | cond |
#                   mmu | scc | cio | fpu | fpu-dp | fpu-enc | fpu-fastd | fpu-slowd | cpu-fpu | <chip>-timing
#   make test-timing        spec TIMING benches (CPU Z-Bus monitor + MMU/CIO/SCC/FPU strobes)
#   make test-mclk          peripheral and FPU vectors at master-clock patterns 1, 2, 1,3, 3,1,2 (FPU also 3, 4)
#   make cpu ONLY=TestNOP        replay one CPU vector with full divergence context
#   make cpu ONLY=TestNOP VCD=1  ... and write obj_dir/vcd/cpu/TestNOP.000.vcd
#   make ladder     list CPU vectors shortest-first with PASS/FAIL status (ladder-<chip> likewise)
#   make -jN        N builds at once, each VERILATOR_JOBS (1) wide; replays share
#                   K8000_JOBS (half of nproc) across the N targets
#   Overrides: OBJ, RESULTS, K8000_MCLK, K8000_TB_FLAGS, K8000_JOBS, K8000_TIMEOUT,
#              VERILATOR_JOBS (README)
#
# Layout is BY DEVICE: rtl/k800x_cpu (the CPU, with its generated gen/ inside),
# rtl/k8010_mmu, rtl/k8030_scc, rtl/k8036_cio, rtl/k8070_fpu; tb/, vectors/ and mk/ mirror
# those names and tb/common holds DUT-independent checkers. Target names stay
# short (test-cio, cio ONLY=...).
#
# Requires: verilator >= 5.020, python3, gtkwave (optional).

VERILATOR ?= verilator
OBJ       := obj_dir
RESULTS   := results
export OBJ RESULTS

# ---- sources ---------------------------------------------------------------
PKG_SRCS  := rtl/k800x_cpu/gen/z8000_ctrl_pkg.sv rtl/k800x_cpu/gen/z8000_zbus_pkg.sv
GEN_SRCS  := rtl/k800x_cpu/gen/z8000_decode_rom_gen.sv
# The machine-cycle program ROM, for the units that walk programs.
MC_SRCS   := rtl/k800x_cpu/gen/z8000_mc_pkg.sv rtl/k800x_cpu/gen/z8000_mc_rom_gen.sv
RTL_UNITS := z8000_regfile z8000_alu z8000_serial z8000_decode \
             z8000_bus_unit z8000_sequencer z8000_cond z8000_execute z8000_int_unit z8000_refresh z8000_cpu
# Modules the CPU top currently instantiates (extend as z8000_cpu.sv grows).
CPU_MODS  := rtl/k800x_cpu/z8000_regfile.sv rtl/k800x_cpu/z8000_decode.sv rtl/k800x_cpu/z8000_bus_unit.sv \
             rtl/k800x_cpu/z8000_sequencer.sv rtl/k800x_cpu/z8000_cond.sv rtl/k800x_cpu/z8000_refresh.sv \
             rtl/k800x_cpu/z8000_alu.sv rtl/k800x_cpu/z8000_execute.sv rtl/k800x_cpu/z8000_serial.sv \
             rtl/k800x_cpu/z8000_int_unit.sv
CPU_SRCS  := $(PKG_SRCS) $(MC_SRCS) $(GEN_SRCS) $(CPU_MODS) rtl/k800x_cpu/z8000_cpu.sv

# ---- lint policy -----------------------------------------------------------
# RTL: -Wall, no suppressions. Testbenches: -Wall minus the
# width/unused nits that $sscanf-driven benches accumulate.
RTL_W  := -Wall -Wno-DECLFILENAME
TB_W   := -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-BLKSEQ
VFLAGS := --timescale 1ns/1ps -O2 --x-assign fast --x-initial fast
# A Verilator build runs its own make VERILATOR_JOBS wide, outside make's
# jobserver so make -n stays a dry run; make -jN runs N builds at once.
VERILATOR_JOBS ?= 1
VBUILD := MAKEFLAGS= $(VERILATOR) --build-jobs $(VERILATOR_JOBS)

.PHONY: all \
        lint lint-measure build test test-decode test-decode-table test-mc-table test-alu test-regfile test-serial test-refresh test-cpu \
        test-cpu-combined test-cpu-timing test-cpu-cycles test-cpu-late-read test-seq-words test-abort-mreq test-seq-paths test-cond test-timing test-mclk cpu ladder clean help \
        gen check-gen
all: build

# Per-device fragments mk/<device>.mk define lint-<chip>, build-<chip> and
# test-<chip>, and append them to CHIP_LINT / CHIP_BUILD / CHIP_TEST /
# CHIP_TIMING_TEST.
CHIP_LINT :=
CHIP_BUILD :=
CHIP_TEST :=
CHIP_TIMING_TEST :=
-include mk/*.mk

help:
	@sed -n '2,27p' Makefile | sed 's/^# \{0,1\}//'

# ---- generated RTL ---------------------------------------------------------
# Each tool writes its files under the root it is given, by default this repo.
PYTHON    ?= python3
GEN_TOOLS := tools/gen_dp_rom.py tools/gen_decode_rom.py tools/gen_mc_rom.py
GEN_OUTS  := rtl/k8070_fpu/gen/z8070_dp_rom_pkg.sv rtl/k8070_fpu/gen/z8070_dp_rom.sv \
             rtl/k800x_cpu/gen/z8000_decode_rom_gen.sv \
             rtl/k800x_cpu/gen/z8000_mc_pkg.sv rtl/k800x_cpu/gen/z8000_mc_rom_gen.sv
GEN_RUN   := PYTHONDONTWRITEBYTECODE=1 $(PYTHON)
GEN_CHECK := $(OBJ)/check-gen

gen:
	@for t in $(GEN_TOOLS); do $(GEN_RUN) $$t || exit 1; done

check-gen:
	@rm -rf $(GEN_CHECK)
	@for t in $(GEN_TOOLS); do $(GEN_RUN) $$t $(GEN_CHECK) || exit 1; done
	@got=$$(cd $(GEN_CHECK) && find . -type f | sed 's|^\./||' | sort); \
	want=$$(printf '%s\n' $(GEN_OUTS) | sort); \
	[ "$$got" = "$$want" ] || { echo "check-gen: the tools write"; echo "$$got"; echo "but GEN_OUTS lists"; echo "$$want"; exit 1; }; \
	fail=0; for f in $(GEN_OUTS); do \
	  cmp -s $$f $(GEN_CHECK)/$$f || { echo "check-gen: $$f differs from its source (make gen):"; diff -u $$f $(GEN_CHECK)/$$f | head -20; fail=1; }; \
	done; [ $$fail -eq 0 ] && echo "check-gen: generated RTL matches its sources"

# ---- lint ------------------------------------------------------------------
lint: $(CHIP_LINT) lint-measure
	@for m in $(RTL_UNITS); do \
	  extra=""; mc=""; [ $$m = z8000_cpu ] && extra="$(CPU_MODS)"; [ $$m = z8000_execute ] && extra="rtl/k800x_cpu/z8000_alu.sv rtl/k800x_cpu/z8000_cond.sv"; \
	  { [ $$m = z8000_cpu ] || [ $$m = z8000_sequencer ]; } && mc="$(MC_SRCS)"; \
	  out=$$($(VERILATOR) --lint-only $(RTL_W) $(PKG_SRCS) $$mc $(GEN_SRCS) rtl/k800x_cpu/$$m.sv $$extra --top-module $$m 2>&1 | grep -v MULTITOP); \
	  if [ -z "$$out" ]; then echo "lint  $$m: clean"; else echo "lint  $$m:"; echo "$$out"; fail=1; fi; \
	done; [ -z "$$fail" ]

# The fit wrappers, so a port change fails here and not in Quartus. Spare
# wrapper bits are allowed.
MEASURE_UNITS := $(patsubst quartus/measure/z8000_%_measure.sv,%,$(wildcard quartus/measure/z8000_*_measure.sv))
lint-measure:
	@for u in $(MEASURE_UNITS); do \
	  out=$$($(VERILATOR) --lint-only $(RTL_W) -Wno-UNUSEDSIGNAL $$(quartus/build.sh --srcs $$u) --top-module z8000_$${u}_measure 2>&1); \
	  if [ -z "$$out" ]; then echo "lint  z8000_$${u}_measure: clean"; else echo "lint  z8000_$${u}_measure:"; echo "$$out"; fail=1; fi; \
	done; [ -z "$$fail" ]

# ---- testbench builds ------------------------------------------------------
build: $(CHIP_BUILD) $(OBJ)/tb_decode/tb_decode $(OBJ)/tb_decode_table/tb_decode_table $(OBJ)/tb_mc_table/tb_mc_table $(OBJ)/tb_alu/tb_alu $(OBJ)/tb_regfile/tb_regfile $(OBJ)/tb_serial/tb_serial $(OBJ)/tb_refresh/tb_refresh \
       $(OBJ)/tb_cpu_z8001/tb_cpu_z8001 $(OBJ)/tb_cpu_z8002/tb_cpu_z8002 \
       $(OBJ)/tb_cpu_z8003/tb_cpu_z8003 $(OBJ)/tb_cpu_z8004/tb_cpu_z8004 \
       $(OBJ)/tb_cpu_timing/tb_cpu_timing $(OBJ)/tb_cpu_cycles/tb_cpu_cycles $(OBJ)/tb_seq_words/tb_seq_words $(OBJ)/tb_abort_mreq/tb_abort_mreq \
       $(OBJ)/tb_seq_paths/tb_seq_paths $(OBJ)/tb_cond/tb_cond \
       $(OBJ)/tb_cpu_timing_z8001/tb_cpu_timing_z8001 $(OBJ)/tb_cpu_cycles_z8001/tb_cpu_cycles_z8001 $(OBJ)/tb_seq_paths_z8001/tb_seq_paths_z8001 \
       $(OBJ)/tb_cpu_late_read/tb_cpu_late_read

$(OBJ)/tb_decode/tb_decode: $(PKG_SRCS) $(GEN_SRCS) rtl/k800x_cpu/z8000_decode.sv tb/k800x_cpu/tb_decode.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_decode \
	  $(PKG_SRCS) $(GEN_SRCS) rtl/k800x_cpu/z8000_decode.sv tb/k800x_cpu/tb_decode.sv -o tb_decode >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

# The decode TABLE bench: proves the committed ROM against the committed
# rtl/k800x_cpu/z8000_decode_table.txt -- the reviewable, repo-local source of
# the decoder. Reads no vectors and no other repo.
$(OBJ)/tb_decode_table/tb_decode_table: $(PKG_SRCS) $(GEN_SRCS) tb/k800x_cpu/tb_decode_table.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_decode_table \
	  $(PKG_SRCS) $(GEN_SRCS) tb/k800x_cpu/tb_decode_table.sv -o tb_decode_table >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

# The machine-cycle program TABLE bench: proves the committed program ROM
# against the committed rtl/k800x_cpu/z8000_mc_table.txt.
$(OBJ)/tb_mc_table/tb_mc_table: $(MC_SRCS) tb/k800x_cpu/tb_mc_table.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_mc_table \
	  $(MC_SRCS) tb/k800x_cpu/tb_mc_table.sv -o tb_mc_table >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_alu/tb_alu: $(PKG_SRCS) rtl/k800x_cpu/z8000_alu.sv tb/k800x_cpu/tb_alu.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_alu \
	  $(PKG_SRCS) rtl/k800x_cpu/z8000_alu.sv tb/k800x_cpu/tb_alu.sv -o tb_alu >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_regfile/tb_regfile: rtl/k800x_cpu/z8000_regfile.sv tb/k800x_cpu/tb_regfile.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_regfile \
	  rtl/k800x_cpu/z8000_regfile.sv tb/k800x_cpu/tb_regfile.sv -o tb_regfile >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_serial/tb_serial: $(PKG_SRCS) rtl/k800x_cpu/z8000_serial.sv tb/k800x_cpu/tb_serial.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_serial \
	  $(PKG_SRCS) rtl/k800x_cpu/z8000_serial.sv tb/k800x_cpu/tb_serial.sv -o tb_serial >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_refresh/tb_refresh: rtl/k800x_cpu/z8000_refresh.sv tb/k800x_cpu/tb_refresh.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_refresh \
	  rtl/k800x_cpu/z8000_refresh.sv tb/k800x_cpu/tb_refresh.sv -o tb_refresh >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

# Spec-timing benches: the Z-Bus protocol monitor driven by a real program,
# and the instruction cycle-count replay.  Both are pure SystemVerilog.
$(OBJ)/tb_cpu_timing/tb_cpu_timing: $(CPU_SRCS) tb/common/z8000_bus_monitor.sv tb/k800x_cpu/tb_cpu_timing.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_cpu_timing \
	  $(CPU_SRCS) tb/common/z8000_bus_monitor.sv tb/k800x_cpu/tb_cpu_timing.sv -o tb_cpu_timing >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_cpu_late_read/tb_cpu_late_read: $(CPU_SRCS) tb/k800x_cpu/tb_cpu_late_read.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_cpu_late_read \
	  $(CPU_SRCS) tb/k800x_cpu/tb_cpu_late_read.sv -o tb_cpu_late_read >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_cpu_cycles/tb_cpu_cycles: $(CPU_SRCS) tb/k800x_cpu/tb_cpu_cycles.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_cpu_cycles \
	  $(CPU_SRCS) tb/k800x_cpu/tb_cpu_cycles.sv -o tb_cpu_cycles >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_seq_words/tb_seq_words: $(CPU_SRCS) tb/k800x_cpu/tb_seq_words.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_seq_words \
	  $(CPU_SRCS) tb/k800x_cpu/tb_seq_words.sv -o tb_seq_words >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_abort_mreq/tb_abort_mreq: $(CPU_SRCS) tb/k800x_cpu/tb_abort_mreq.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_abort_mreq \
	  $(CPU_SRCS) tb/k800x_cpu/tb_abort_mreq.sv -o tb_abort_mreq >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_seq_paths/tb_seq_paths: $(CPU_SRCS) tb/k800x_cpu/tb_seq_paths.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_seq_paths \
	  $(CPU_SRCS) tb/k800x_cpu/tb_seq_paths.sv -o tb_seq_paths >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

# The same three benches on a segmented Z8001.
define SEG_BUILD
$(OBJ)/$(1)_z8001/$(1)_z8001: $(CPU_SRCS) $(2) tb/k800x_cpu/$(1).sv
	@mkdir -p $$(dir $$@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $$(dir $$@) --top-module $(1) -GSEGMENTED=1\'b1 \
	  $(CPU_SRCS) $(2) tb/k800x_cpu/$(1).sv -o $(1)_z8001 >$$(dir $$@)build.log 2>&1 || (cat $$(dir $$@)build.log; exit 1)
endef
$(eval $(call SEG_BUILD,tb_cpu_timing,tb/common/z8000_bus_monitor.sv))
$(eval $(call SEG_BUILD,tb_cpu_cycles,))
$(eval $(call SEG_BUILD,tb_seq_paths,))

$(OBJ)/tb_cond/tb_cond: rtl/k800x_cpu/z8000_cond.sv tb/k800x_cpu/tb_cond.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_cond \
	  rtl/k800x_cpu/z8000_cond.sv tb/k800x_cpu/tb_cond.sv -o tb_cond >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

# CPU replay harness: one build per variant (SEGMENTED / VMPU parameters).
define CPU_BUILD
$(OBJ)/tb_cpu_$(1)/tb_cpu_$(1): $(CPU_SRCS) tb/k800x_cpu/tb_cpu.cpp tb/k800x_cpu/dut_access.h
	@mkdir -p $$(dir $$@)
	$(VBUILD) --cc --exe --build $(VFLAGS) $(RTL_W) --public-flat-rw --trace \
	  --Mdir $$(dir $$@) -GSEGMENTED=1\'b$(2) -GVMPU=1\'b$(3) \
	  -CFLAGS '-DK8000_VARIANT=\"$(4)\" -DK8000_SEGMENTED=$(2) -std=c++14 -O2' \
	  --top-module z8000_cpu $(CPU_SRCS) $(CURDIR)/tb/k800x_cpu/tb_cpu.cpp -o tb_cpu_$(1) >$$(dir $$@)build.log 2>&1 || (cat $$(dir $$@)build.log; exit 1)
endef
$(eval $(call CPU_BUILD,z8001,1,0,Z8001))
$(eval $(call CPU_BUILD,z8002,0,0,Z8002))
$(eval $(call CPU_BUILD,z8003,1,1,Z8003))
$(eval $(call CPU_BUILD,z8004,0,1,Z8004))

# ---- run -------------------------------------------------------------------
test: check-gen test-decode test-decode-table test-mc-table test-alu test-regfile test-serial test-refresh test-cpu test-cpu-combined test-cpu-timing test-cpu-cycles test-cpu-late-read test-seq-words test-abort-mreq test-seq-paths test-cond $(CHIP_TEST) test-mclk

# Spec-timing ladder: everything that checks the datasheet's timing rather than
# equality with the vectors.
test-timing: test-cpu-timing test-cpu-cycles $(CHIP_TIMING_TEST)

test-decode: $(OBJ)/tb_decode/tb_decode
	@scripts/run_sv_bench.sh $(OBJ)/tb_decode/tb_decode +vec=vectors/k800x_cpu/decode/decode.vec

test-decode-table: $(OBJ)/tb_decode_table/tb_decode_table
	@scripts/run_sv_bench.sh $(OBJ)/tb_decode_table/tb_decode_table +table=rtl/k800x_cpu/z8000_decode_table.txt

test-mc-table: $(OBJ)/tb_mc_table/tb_mc_table
	@scripts/run_sv_bench.sh $(OBJ)/tb_mc_table/tb_mc_table +table=rtl/k800x_cpu/z8000_mc_table.txt

test-alu: $(OBJ)/tb_alu/tb_alu
	@scripts/run_vectors.sh alu

test-regfile: $(OBJ)/tb_regfile/tb_regfile
	@scripts/run_sv_bench.sh $(OBJ)/tb_regfile/tb_regfile

test-serial: $(OBJ)/tb_serial/tb_serial
	@scripts/run_sv_bench.sh -t 25 $(OBJ)/tb_serial/tb_serial +vec=vectors/k800x_cpu/serial/random.vec

test-refresh: $(OBJ)/tb_refresh/tb_refresh
	@scripts/run_sv_bench.sh $(OBJ)/tb_refresh/tb_refresh

test-cpu: $(OBJ)/tb_cpu_z8001/tb_cpu_z8001 $(OBJ)/tb_cpu_z8002/tb_cpu_z8002 $(OBJ)/tb_cpu_z8003/tb_cpu_z8003 $(OBJ)/tb_cpu_z8004/tb_cpu_z8004
	@scripts/run_vectors.sh cpu

test-cpu-combined: $(OBJ)/tb_cpu_z8001/tb_cpu_z8001 $(OBJ)/tb_cpu_z8002/tb_cpu_z8002 $(OBJ)/tb_cpu_z8003/tb_cpu_z8003 $(OBJ)/tb_cpu_z8004/tb_cpu_z8004
	@scripts/run_vectors.sh cpu --combined
	@scripts/run_vectors.sh cpu --combined-mclk 2
	@scripts/run_vectors.sh cpu --combined-mclk 1,2,1,3

test-cpu-timing: $(OBJ)/tb_cpu_timing/tb_cpu_timing $(OBJ)/tb_cpu_timing_z8001/tb_cpu_timing_z8001
	@scripts/run_sv_bench.sh $(OBJ)/tb_cpu_timing/tb_cpu_timing
	@scripts/run_sv_bench.sh $(OBJ)/tb_cpu_timing_z8001/tb_cpu_timing_z8001

test-cpu-cycles: $(OBJ)/tb_cpu_cycles/tb_cpu_cycles $(OBJ)/tb_cpu_cycles_z8001/tb_cpu_cycles_z8001
	@scripts/run_sv_bench.sh -t 50 $(OBJ)/tb_cpu_cycles/tb_cpu_cycles +vec=vectors/k800x_cpu/cycles/cycles.vec
	@scripts/run_sv_bench.sh -t 50 $(OBJ)/tb_cpu_cycles_z8001/tb_cpu_cycles_z8001 +vec=vectors/k800x_cpu/cycles/cycles_z8001.vec

# Read data late in T3, taken on the CLK fall: late at 2, 3 and 2,3,4 master
# clocks per CLK half, only in the master clock before the fall at 3 and
# 3,4,5, late for one kind of read at a time, normal memory at 1 and 1,2,
# and turbo (rise and fall in every master clock). The mixed clockings must
# fail with the CPU's check.
LATE_RUNS := +half=2 +half=3 +half=2,3,4 +edge:+half=3 +edge:+half=3,4,5 \
             +only=fetch +only=data +only=io +only=ack \
             +normal:+half=1 +normal:+half=1,2 +turbo
LATE_BAD  := +mixed:+half=2 +unmix:+half=2
test-cpu-late-read: $(OBJ)/tb_cpu_late_read/tb_cpu_late_read
	@for a in $(LATE_RUNS); do scripts/run_sv_bench.sh -t 1 $< $$(echo $$a | tr : ' ') || exit 1; done
	@for a in $(LATE_BAD); do out=$$(timeout $${K8000_TIMEOUT:-1800} $< $$(echo $$a | tr : ' ') 2>&1); \
	  if printf '%s\n' "$$out" | grep -q 'mixed at a T3' && printf '%s\n' "$$out" | grep -q '^RESULT FAIL'; then \
	    printf '%s\n' "$$out" | grep '^RESULT FAIL' | sed 's/^RESULT FAIL/RESULT EXPECTED FAIL/'; \
	  else printf '%s\n' "$$out"; echo "RESULT FAIL $$a: the mixed clocking was not flagged"; exit 1; fi; done

test-seq-words: $(OBJ)/tb_seq_words/tb_seq_words
	@scripts/run_sv_bench.sh $(OBJ)/tb_seq_words/tb_seq_words

test-abort-mreq: $(OBJ)/tb_abort_mreq/tb_abort_mreq
	@scripts/run_sv_bench.sh $(OBJ)/tb_abort_mreq/tb_abort_mreq

test-seq-paths: $(OBJ)/tb_seq_paths/tb_seq_paths $(OBJ)/tb_seq_paths_z8001/tb_seq_paths_z8001
	@scripts/run_sv_bench.sh $(OBJ)/tb_seq_paths/tb_seq_paths
	@scripts/run_sv_bench.sh $(OBJ)/tb_seq_paths_z8001/tb_seq_paths_z8001

test-cond: $(OBJ)/tb_cond/tb_cond
	@scripts/run_sv_bench.sh $(OBJ)/tb_cond/tb_cond

# The vector replays at each master-clock pattern the docs claim; CPU+FPU
# also at 3 and 4.
MCLK_PATTERNS := 1 2 1,3 3,1,2
test-mclk: $(MMU_BIN) $(SCC_TB) $(CIO_TB) $(FPU_TB) $(OBJ)/tb_cpu_fpu_z8001/tb_cpu_fpu_z8001 $(OBJ)/tb_cpu_fpu_z8002/tb_cpu_fpu_z8002
	@fail=0; for p in $(MCLK_PATTERNS) 3 4; do for c in mmu scc cio fpu cpu-fpu; do \
	  case $$p in 3|4) [ $$c = cpu-fpu ] || [ $$c = fpu ] || continue;; esac; \
	  if out=$$(scripts/run_vectors.sh $$c --mclk $$p); then \
	    printf '%s\n' "$$out" | grep '^== \|^  [^ ]' | sed "s/^/mclk $$p /"; \
	  else fail=1; printf '%s\n' "$$out" | sed "s/^/mclk $$p /"; fi; \
	done; done; [ $$fail -eq 0 ]

ladder: $(OBJ)/tb_cpu_z8001/tb_cpu_z8001 $(OBJ)/tb_cpu_z8002/tb_cpu_z8002 $(OBJ)/tb_cpu_z8003/tb_cpu_z8003 $(OBJ)/tb_cpu_z8004/tb_cpu_z8004
	@scripts/run_vectors.sh cpu --ladder

# One vector, full context. ONLY=TestNOP or ONLY=TestNOP.000 ; VCD=1 for a waveform.
cpu: $(OBJ)/tb_cpu_z8001/tb_cpu_z8001 $(OBJ)/tb_cpu_z8002/tb_cpu_z8002 $(OBJ)/tb_cpu_z8003/tb_cpu_z8003 $(OBJ)/tb_cpu_z8004/tb_cpu_z8004
	@[ -n "$(ONLY)" ] || (echo "usage: make cpu ONLY=TestName[.NNN] [VCD=1] [CONTEXT=N]"; exit 1)
	@scripts/run_vectors.sh cpu --one "$(ONLY)" $(if $(VCD),--vcd,) $(if $(CONTEXT),--context $(CONTEXT),)

clean:
	rm -rf $(OBJ) $(RESULTS)
