# mk/k8010_mmu.mk -- Z8010 MMU fragment (FPGA_BIBLE Ch.3). Included by the top
# Makefile via -include mk/*.mk; hooks gen/vectors/lint/build/test through
# the CHIP_* lists. Uses the top Makefile's VERILATOR / Z8000 / GEN / OBJ /
# RESULTS / RTL_W / VFLAGS.
#
#   make vectors-mmu   [MAINTAINER, needs ~/git/z8000] record vectors/k8010_mmu from ~/git/z8000/sim/mmu tests + Go self-check
#   make lint-mmu      verilator -Wall on rtl/k8010_mmu/z8010_mmu.sv
#   make build-mmu     build obj_dir/tb_mmu/tb_mmu
#   make test-mmu      replay every vectors/k8010_mmu/*.vec, ladder summary
#   make mmu ONLY=TestBasicTranslation [VCD=1] [CONTEXT=N]   one vector, full context
#   make ladder-mmu    every MMU vector, shortest first, with PASS/FAIL/SKIP

MMU_TOP  := z8010_mmu
MMU_SRCS := rtl/k8010_mmu/z8010_mmu.sv
MMU_BIN  := $(OBJ)/tb_mmu/tb_mmu

.PHONY: gen-mmu vectors-mmu lint-mmu build-mmu test-mmu mmu ladder-mmu test-mmu-timing

CHIP_GEN     += gen-mmu
CHIP_VECTORS += vectors-mmu
CHIP_LINT    += lint-mmu
CHIP_BUILD   += build-mmu $(OBJ)/tb_mmu_timing/tb_mmu_timing
CHIP_TEST    += test-mmu test-mmu-timing
CHIP_TIMING_TEST += test-mmu-timing

# Nothing is code-generated for the MMU (no ROMs); the command table is a
# hand-written case statement transcribed from mmu.go executeCommand.
gen-mmu: require-z8000
	@:

vectors-mmu: require-z8000
	rm -rf vectors/k8010_mmu
	cd $(Z8000)/sim && K8000_VEC_DIR=$(CURDIR)/vectors go test -count=1 ./mmu/...
	cd $(GEN) && go run ./cmd/mmuvecverify $(CURDIR)/vectors/k8010_mmu/*.vec
	@echo "mmu vectors: $$(ls vectors/k8010_mmu | wc -l)"

lint-mmu:
	@out=$$($(VERILATOR) --lint-only $(RTL_W) $(MMU_SRCS) --top-module $(MMU_TOP) 2>&1); \
	if [ -z "$$out" ]; then echo "lint  $(MMU_TOP): clean"; else echo "lint  $(MMU_TOP):"; echo "$$out"; exit 1; fi

build-mmu: $(MMU_BIN)

$(MMU_BIN): $(MMU_SRCS) tb/k8010_mmu/tb_mmu.cpp tb/k8010_mmu/mmu_access.h
	@mkdir -p $(dir $@)
	$(VERILATOR) --cc --exe --build -j 4 $(VFLAGS) $(RTL_W) --public-flat-rw --trace \
	  --Mdir $(dir $@) -CFLAGS '-std=c++14 -O2' \
	  --top-module $(MMU_TOP) $(MMU_SRCS) $(CURDIR)/tb/k8010_mmu/tb_mmu.cpp -o tb_mmu >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-mmu: $(MMU_BIN)
	@scripts/run_k8010_mmu_vectors.sh

ladder-mmu: $(MMU_BIN)
	@scripts/run_k8010_mmu_vectors.sh --ladder

mmu: $(MMU_BIN)
	@[ -n "$(ONLY)" ] || (echo "usage: make mmu ONLY=TestName[.NNN] [VCD=1] [CONTEXT=N]"; exit 1)
	@scripts/run_k8010_mmu_vectors.sh --one "$(ONLY)" $(if $(VCD),--vcd,) $(if $(CONTEXT),--context $(CONTEXT),)

# ---- spec TIMING bench (SystemVerilog, datasheet strobe protocol) ----------
# Not a vector replay: tb/k8010_mmu/tb_mmu_timing.sv drives the figures' strobe patterns
# and asserts what the datasheet says the chip must do.  See docs/TIMING_TESTS.md.
$(OBJ)/tb_mmu_timing/tb_mmu_timing: $(MMU_SRCS) tb/k8010_mmu/tb_mmu_timing.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_mmu_timing \
	  $(MMU_SRCS) tb/k8010_mmu/tb_mmu_timing.sv -o tb_mmu_timing >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-mmu-timing: $(OBJ)/tb_mmu_timing/tb_mmu_timing
	@$(OBJ)/tb_mmu_timing/tb_mmu_timing | grep -v '\$$finish'
