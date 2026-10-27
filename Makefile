# k8000 -- Z8000 CPU in SystemVerilog, verified in lockstep against the Go
# golden model in ~/git/z8000 (FPGA_BIBLE.md Ch.6).
#
# SELF-CONTAINED: everything under rtl/ and vectors/ is a COMMITTED artifact.
# lint, build and test read nothing outside this repo -- a fresh clone with no
# ~/git/z8000 and no Go toolchain runs the whole suite. Only the two REFRESH
# targets below reach into the golden model, and only a maintainer runs them.
#
#   make lint       verilator -Wall on every RTL module (zero suppressions policy)
#   make build      build every testbench (decode, alu, regfile, serial, cpu x4 variants)
#   make test       run everything, print the pass/fail ladder
#   make test-<x>   one bench: decode | decode-table | alu | regfile | serial | cpu
#   make test-timing        spec TIMING benches (CPU Z-Bus monitor + MMU/CIO/SCC strobes)
#   make test-cpu-cycles    instruction CYCLE COUNTS vs Mar81 sec 6.7
#   make cpu ONLY=TestNOP        replay one CPU vector with full divergence context
#   make cpu ONLY=TestNOP VCD=1  ... and write obj_dir/TestNOP.000.vcd
#   make ladder     list CPU vectors shortest-first with PASS/FAIL status
#
#   MAINTAINER ONLY (needs ~/git/z8000 + Go; refreshes committed artifacts):
#   make refresh-rtl        rtl/k800x_cpu/gen/*.sv + the decode vectors
#   make refresh-vectors    re-record every vectors/<device>/ from the Go suite
#
# Layout is BY DEVICE: rtl/k800x_cpu (the CPU, with its generated gen/ inside),
# rtl/k8010_mmu, rtl/k8030_scc, rtl/k8036_cio; tb/, vectors/ and mk/ mirror
# those names and tb/common holds DUT-independent checkers. Target names stay
# short (test-cio, cio ONLY=...).
#
# Requires: verilator >= 5.020, go (only for gen/vectors), gtkwave (optional).

VERILATOR ?= verilator
Z8000     ?= $(HOME)/git/z8000
GEN       := $(Z8000)/hdl/gen
OBJ       := obj_dir
RESULTS   := results

# ---- sources ---------------------------------------------------------------
PKG_SRCS  := rtl/k800x_cpu/gen/z8000_ctrl_pkg.sv rtl/k800x_cpu/gen/z8000_zbus_pkg.sv
GEN_SRCS  := rtl/k800x_cpu/gen/z8000_decode_rom_gen.sv
RTL_UNITS := z8000_regfile z8000_alu z8000_mult z8000_div z8000_shift z8000_decode \
             z8000_bus_unit z8000_sequencer z8000_prefetch z8000_int_unit z8000_refresh z8000_cpu
# Modules the CPU top currently instantiates (extend as z8000_cpu.sv grows).
CPU_SRCS  := $(PKG_SRCS) $(GEN_SRCS) rtl/k800x_cpu/z8000_regfile.sv rtl/k800x_cpu/z8000_bus_unit.sv \
             rtl/k800x_cpu/z8000_sequencer.sv rtl/k800x_cpu/z8000_cpu.sv

# ---- lint policy -----------------------------------------------------------
# RTL: -Wall, no suppressions (FPGA_BIBLE 0.4). Testbenches: -Wall minus the
# width/unused nits that $sscanf-driven benches accumulate.
RTL_W  := -Wall -Wno-DECLFILENAME
TB_W   := -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-BLKSEQ
VFLAGS := --timescale 1ns/1ps -O2 --x-assign fast --x-initial fast

.PHONY: all gen vectors refresh-rtl refresh-vectors require-z8000 \
        lint build test test-decode test-decode-table test-alu test-regfile test-serial test-cpu \
        test-cpu-timing test-cpu-cycles test-timing cpu ladder clean help
all: build

# Per-device fragments (k8010_mmu / k8036_cio / k8030_scc ...) live in
# mk/<device>.mk and hook the
# gen/vectors/lint/build/test targets via the *_EXTRA variables and
# double-colon-free convention: each fragment defines gen-<chip>,
# vectors-<chip>, lint-<chip>, build-<chip>, test-<chip>, and appends them
# to CHIP_GEN / CHIP_VECTORS / CHIP_LINT / CHIP_BUILD / CHIP_TEST.
CHIP_GEN :=
CHIP_VECTORS :=
CHIP_LINT :=
CHIP_BUILD :=
CHIP_TEST :=
CHIP_TIMING_TEST :=
-include mk/*.mk

help:
	@sed -n '2,26p' Makefile | sed 's/^# \{0,1\}//'

# ---- MAINTAINER: refresh the committed artifacts ---------------------------
# These are the ONLY targets that read $(Z8000). Nothing in lint/build/test
# depends on them: rtl/k800x_cpu/gen/*.sv and vectors/** are checked in, and
# tb_decode proves the committed ROM against the committed decode vectors
# without any external repo. Run these when the golden model changes, then
# commit the diff here.
#
# `gen` and `vectors` remain as aliases for the fingers that already know them.
require-z8000:
	@[ -d "$(GEN)" ] || { \
	  echo "make: this target refreshes generated artifacts from the Z8000 Go"; \
	  echo "      golden model, which is not present at $(Z8000)."; \
	  echo ""; \
	  echo "      You do not need it to work on the RTL: rtl/ and vectors/ are"; \
	  echo "      committed, and 'make lint build test' uses only this repo."; \
	  echo "      Set Z8000=<path> if you have the model somewhere else."; \
	  exit 1; }

gen refresh-rtl: require-z8000 $(CHIP_GEN)
	cd $(GEN) && go run ./cmd/decoderom -root $(CURDIR)
	cd $(GEN) && go run ./cmd/aluvec -root $(CURDIR)
	cd $(GEN) && go run ./cmd/serialvec -root $(CURDIR)

vectors refresh-vectors: require-z8000 $(CHIP_VECTORS)
	rm -rf vectors/k800x_cpu/cpu vectors/k800x_cpu/alu vectors/k800x_cpu/alu_from_cpu
	cd $(Z8000)/sim && K8000_VEC_DIR=$(CURDIR)/vectors go test -count=1 ./cpu/...
	cd $(GEN) && go run ./cmd/aluvec -root $(CURDIR)
	cd $(GEN) && go run ./cmd/serialvec -root $(CURDIR)
	cd $(GEN) && go run ./cmd/vecverify $(CURDIR)/vectors/k800x_cpu/cpu/*.vec
	cd $(GEN) && go run ./cmd/cyclevec -root $(CURDIR)
	@echo "cpu vectors: $$(ls vectors/k800x_cpu/cpu | wc -l)  alu: $$(ls vectors/k800x_cpu/alu | wc -l)  alu_from_cpu: $$(ls vectors/k800x_cpu/alu_from_cpu | wc -l)"

# ---- lint ------------------------------------------------------------------
lint: $(CHIP_LINT)
	@for m in $(RTL_UNITS); do \
	  extra=""; [ $$m = z8000_cpu ] && extra="rtl/k800x_cpu/z8000_regfile.sv rtl/k800x_cpu/z8000_bus_unit.sv rtl/k800x_cpu/z8000_sequencer.sv"; \
	  out=$$($(VERILATOR) --lint-only $(RTL_W) $(PKG_SRCS) $(GEN_SRCS) rtl/k800x_cpu/$$m.sv $$extra --top-module $$m 2>&1 | grep -v MULTITOP); \
	  if [ -z "$$out" ]; then echo "lint  $$m: clean"; else echo "lint  $$m:"; echo "$$out"; fail=1; fi; \
	done; [ -z "$$fail" ]

# ---- testbench builds ------------------------------------------------------
build: $(CHIP_BUILD) $(OBJ)/tb_decode/tb_decode $(OBJ)/tb_decode_table/tb_decode_table $(OBJ)/tb_alu/tb_alu $(OBJ)/tb_regfile/tb_regfile $(OBJ)/tb_serial/tb_serial \
       $(OBJ)/tb_cpu_z8001/tb_cpu_z8001 $(OBJ)/tb_cpu_z8002/tb_cpu_z8002 \
       $(OBJ)/tb_cpu_z8003/tb_cpu_z8003 $(OBJ)/tb_cpu_z8004/tb_cpu_z8004 \
       $(OBJ)/tb_cpu_timing/tb_cpu_timing $(OBJ)/tb_cpu_cycles/tb_cpu_cycles

$(OBJ)/tb_decode/tb_decode: $(PKG_SRCS) $(GEN_SRCS) rtl/k800x_cpu/z8000_decode.sv tb/k800x_cpu/tb_decode.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_decode \
	  $(PKG_SRCS) $(GEN_SRCS) rtl/k800x_cpu/z8000_decode.sv tb/k800x_cpu/tb_decode.sv -o tb_decode >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

# The decode TABLE bench: proves the committed ROM against the committed
# rtl/k800x_cpu/z8000_decode_table.txt -- the reviewable, repo-local source of
# the decoder. Reads no vectors and no other repo.
$(OBJ)/tb_decode_table/tb_decode_table: $(PKG_SRCS) $(GEN_SRCS) tb/k800x_cpu/tb_decode_table.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_decode_table \
	  $(PKG_SRCS) $(GEN_SRCS) tb/k800x_cpu/tb_decode_table.sv -o tb_decode_table >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_alu/tb_alu: $(PKG_SRCS) rtl/k800x_cpu/z8000_alu.sv tb/k800x_cpu/tb_alu.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_alu \
	  $(PKG_SRCS) rtl/k800x_cpu/z8000_alu.sv tb/k800x_cpu/tb_alu.sv -o tb_alu >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_regfile/tb_regfile: rtl/k800x_cpu/z8000_regfile.sv tb/k800x_cpu/tb_regfile.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_regfile \
	  rtl/k800x_cpu/z8000_regfile.sv tb/k800x_cpu/tb_regfile.sv -o tb_regfile >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_serial/tb_serial: $(PKG_SRCS) rtl/k800x_cpu/z8000_mult.sv rtl/k800x_cpu/z8000_div.sv rtl/k800x_cpu/z8000_shift.sv tb/k800x_cpu/tb_serial.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_serial \
	  $(PKG_SRCS) rtl/k800x_cpu/z8000_mult.sv rtl/k800x_cpu/z8000_div.sv rtl/k800x_cpu/z8000_shift.sv tb/k800x_cpu/tb_serial.sv -o tb_serial >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

# Spec-timing benches: the Z-Bus protocol monitor driven by a real program,
# and the instruction cycle-count replay.  Both are pure SystemVerilog.
$(OBJ)/tb_cpu_timing/tb_cpu_timing: $(CPU_SRCS) tb/common/z8000_bus_monitor.sv tb/k800x_cpu/tb_cpu_timing.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_cpu_timing \
	  $(CPU_SRCS) tb/common/z8000_bus_monitor.sv tb/k800x_cpu/tb_cpu_timing.sv -o tb_cpu_timing >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

$(OBJ)/tb_cpu_cycles/tb_cpu_cycles: $(CPU_SRCS) tb/k800x_cpu/tb_cpu_cycles.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_cpu_cycles \
	  $(CPU_SRCS) tb/k800x_cpu/tb_cpu_cycles.sv -o tb_cpu_cycles >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

# CPU replay harness: one build per variant (SEGMENTED / VMPU parameters).
define CPU_BUILD
$(OBJ)/tb_cpu_$(1)/tb_cpu_$(1): $(CPU_SRCS) tb/k800x_cpu/tb_cpu.cpp tb/k800x_cpu/dut_access.h
	@mkdir -p $$(dir $$@)
	$(VERILATOR) --cc --exe --build -j 4 $(VFLAGS) $(RTL_W) --public-flat-rw --trace \
	  --Mdir $$(dir $$@) -GSEGMENTED=1\'b$(2) -GVMPU=1\'b$(3) \
	  -CFLAGS '-DK8000_VARIANT=\"$(4)\" -DK8000_SEGMENTED=$(2) -std=c++14 -O2' \
	  --top-module z8000_cpu $(CPU_SRCS) $(CURDIR)/tb/k800x_cpu/tb_cpu.cpp -o tb_cpu_$(1) >$$(dir $$@)build.log 2>&1 || (cat $$(dir $$@)build.log; exit 1)
endef
$(eval $(call CPU_BUILD,z8001,1,0,Z8001))
$(eval $(call CPU_BUILD,z8002,0,0,Z8002))
$(eval $(call CPU_BUILD,z8003,1,1,Z8003))
$(eval $(call CPU_BUILD,z8004,0,1,Z8004))

# ---- run -------------------------------------------------------------------
test: test-decode test-decode-table test-alu test-regfile test-serial test-cpu test-cpu-timing test-cpu-cycles $(CHIP_TEST)

# Spec-timing ladder: everything that checks the datasheet's timing rather than
# equality with the Go model.
test-timing: test-cpu-timing test-cpu-cycles $(CHIP_TIMING_TEST)

test-decode: $(OBJ)/tb_decode/tb_decode
	@$(OBJ)/tb_decode/tb_decode +vec=vectors/k800x_cpu/decode/decode.vec | grep -v '\$$finish'

test-decode-table: $(OBJ)/tb_decode_table/tb_decode_table
	@$(OBJ)/tb_decode_table/tb_decode_table +table=rtl/k800x_cpu/z8000_decode_table.txt | grep -v '\$$finish'

test-alu: $(OBJ)/tb_alu/tb_alu
	@mkdir -p $(RESULTS); : > $(RESULTS)/alu.txt
	@for v in vectors/k800x_cpu/alu/*.vec vectors/k800x_cpu/alu_from_cpu/*.vec; do \
	  $(OBJ)/tb_alu/tb_alu +vec=$$v | grep '^RESULT' >> $(RESULTS)/alu.txt; done
	@scripts/summarize.sh alu $(RESULTS)/alu.txt

test-regfile: $(OBJ)/tb_regfile/tb_regfile
	@$(OBJ)/tb_regfile/tb_regfile | grep -v '\$$finish'

test-serial: $(OBJ)/tb_serial/tb_serial
	@$(OBJ)/tb_serial/tb_serial +vec=vectors/k800x_cpu/serial/random.vec | grep -v '\$$finish' | tail -25

test-cpu: $(OBJ)/tb_cpu_z8001/tb_cpu_z8001 $(OBJ)/tb_cpu_z8002/tb_cpu_z8002 $(OBJ)/tb_cpu_z8003/tb_cpu_z8003 $(OBJ)/tb_cpu_z8004/tb_cpu_z8004
	@scripts/run_k800x_cpu_vectors.sh

test-cpu-timing: $(OBJ)/tb_cpu_timing/tb_cpu_timing
	@$(OBJ)/tb_cpu_timing/tb_cpu_timing | grep -v '\$$finish'

test-cpu-cycles: $(OBJ)/tb_cpu_cycles/tb_cpu_cycles
	@$(OBJ)/tb_cpu_cycles/tb_cpu_cycles +vec=vectors/k800x_cpu/cycles/cycles.vec | grep -v '\$$finish' | tail -40

ladder:
	@scripts/run_k800x_cpu_vectors.sh --ladder

# One vector, full context. ONLY=TestNOP or ONLY=TestNOP.000 ; VCD=1 for a waveform.
cpu: $(OBJ)/tb_cpu_z8001/tb_cpu_z8001 $(OBJ)/tb_cpu_z8002/tb_cpu_z8002 $(OBJ)/tb_cpu_z8003/tb_cpu_z8003 $(OBJ)/tb_cpu_z8004/tb_cpu_z8004
	@[ -n "$(ONLY)" ] || (echo "usage: make cpu ONLY=TestName[.NNN] [VCD=1] [CONTEXT=N]"; exit 1)
	@scripts/run_k800x_cpu_vectors.sh --one "$(ONLY)" $(if $(VCD),--vcd,) $(if $(CONTEXT),--context $(CONTEXT),)

clean:
	rm -rf $(OBJ) $(RESULTS)
