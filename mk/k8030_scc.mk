# mk/k8030_scc.mk -- Z8030 SCC. Hooked into the top Makefile via
# CHIP_GEN / CHIP_VECTORS / CHIP_LINT / CHIP_BUILD / CHIP_TEST.
#
#   make vectors-scc   [MAINTAINER, needs $(Z8000)] record vectors/k8030_scc/*.vec from the model's SCC tests
#                      (K8000_VEC_DIR), then self-check them with sccvecverify
#   make lint-scc      verilator -Wall on rtl/k8030_scc/*.sv (zero suppressions)
#   make build-scc     build obj_dir/tb_scc/tb_scc
#   make test-scc      replay every SCC vector; per-vector PASS/FAIL/SKIP + ladder
#   make scc ONLY=TestPins_TX_8N1_x16 [VCD=1] [CONTEXT=20]   one vector, verbose
#   make ladder-scc    every SCC vector shortest first with status

SCC_SRCS := rtl/k8030_scc/z8030_scc_channel.sv rtl/k8030_scc/z8030_scc.sv
SCC_TB   := $(OBJ)/tb_scc/tb_scc

.PHONY: gen-scc vectors-scc lint-scc build-scc test-scc scc ladder-scc test-scc-timing test-scc-iack
CHIP_GEN     += gen-scc
CHIP_VECTORS += vectors-scc
CHIP_LINT    += lint-scc
CHIP_BUILD   += build-scc $(OBJ)/tb_scc_timing/tb_scc_timing $(OBJ)/tb_scc_iack/tb_scc_iack
CHIP_TEST    += test-scc test-scc-timing test-scc-iack
CHIP_TIMING_TEST += test-scc-timing test-scc-iack

# Nothing is code-generated for the SCC (no ROM/PLA); vectors come from the test suite.
gen-scc: require-z8000
	@:

vectors-scc: require-z8000
	rm -rf vectors/k8030_scc
	cd $(Z8000)/sim && K8000_VEC_DIR=$(CURDIR)/vectors go test -count=1 ./scc/...
	cd $(GEN) && go run ./cmd/sccvecverify $(CURDIR)/vectors/k8030_scc/*.vec
	@echo "scc vectors: $$(ls vectors/k8030_scc | wc -l)  (pure pin-seam: $$(grep -l '^F POKES 0' vectors/k8030_scc/*.vec | wc -l), with pokes: $$(grep -L '^F POKES 0' vectors/k8030_scc/*.vec | wc -l))"

lint-scc:
	@out=$$($(VERILATOR) --lint-only $(RTL_W) $(SCC_SRCS) --top-module z8030_scc 2>&1 | grep -v MULTITOP); \
	  if [ -z "$$out" ]; then echo "lint  z8030_scc: clean"; else echo "lint  z8030_scc:"; echo "$$out"; exit 1; fi
	@out=$$($(VERILATOR) --lint-only $(RTL_W) rtl/k8030_scc/z8030_scc_channel.sv --top-module z8030_scc_channel 2>&1 | grep -v MULTITOP); \
	  if [ -z "$$out" ]; then echo "lint  z8030_scc_channel: clean"; else echo "lint  z8030_scc_channel:"; echo "$$out"; exit 1; fi

build-scc: $(SCC_TB)

$(SCC_TB): $(SCC_SRCS) tb/k8030_scc/tb_scc.cpp tb/k8030_scc/scc_access.h
	@mkdir -p $(dir $@)
	$(VERILATOR) --cc --exe --build -j 4 $(VFLAGS) $(RTL_W) --public-flat-rw --trace \
	  --Mdir $(dir $@) -CFLAGS '-std=c++14 -O2' \
	  --top-module z8030_scc $(SCC_SRCS) $(CURDIR)/tb/k8030_scc/tb_scc.cpp -o tb_scc >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-scc: $(SCC_TB)
	@scripts/run_k8030_scc_vectors.sh

ladder-scc:
	@scripts/run_k8030_scc_vectors.sh --ladder

scc: $(SCC_TB)
	@[ -n "$(ONLY)" ] || (echo "usage: make scc ONLY=TestName[.NNN] [VCD=1] [CONTEXT=N]"; exit 1)
	@scripts/run_k8030_scc_vectors.sh --one "$(ONLY)" $(if $(VCD),--vcd,) $(if $(CONTEXT),--context $(CONTEXT),)

# ---- spec TIMING bench (SystemVerilog, datasheet strobe protocol) ----------
# Not a vector replay: tb/k8030_scc/tb_scc_timing.sv drives the figures' strobe patterns
# and asserts what the datasheet says the chip must do.  See docs/TIMING_TESTS.md.
$(OBJ)/tb_scc_timing/tb_scc_timing: $(SCC_SRCS) tb/k8030_scc/tb_scc_timing.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_scc_timing \
	  $(SCC_SRCS) tb/k8030_scc/tb_scc_timing.sv -o tb_scc_timing >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-scc-timing: $(OBJ)/tb_scc_timing/tb_scc_timing
	@scripts/run_sv_bench.sh $(OBJ)/tb_scc_timing/tb_scc_timing

# Daisy-chain acknowledge bench: two chips, the first's IEO into the second's IEI.
$(OBJ)/tb_scc_iack/tb_scc_iack: $(SCC_SRCS) tb/k8030_scc/tb_scc_iack.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_scc_iack \
	  $(SCC_SRCS) tb/k8030_scc/tb_scc_iack.sv -o tb_scc_iack >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-scc-iack: $(OBJ)/tb_scc_iack/tb_scc_iack
	@scripts/run_sv_bench.sh $(OBJ)/tb_scc_iack/tb_scc_iack
