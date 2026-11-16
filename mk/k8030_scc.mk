# mk/k8030_scc.mk -- Z8030 SCC. Hooked into the top Makefile via
# CHIP_LINT / CHIP_BUILD / CHIP_TEST.
#
#   make lint-scc      verilator -Wall on rtl/k8030_scc/*.sv (zero suppressions)
#   make build-scc     build obj_dir/tb_scc/tb_scc
#   make test-scc      replay every SCC vector; per-vector PASS/FAIL/SKIP + ladder
#   make scc ONLY=TestPins_TX_8N1_x16 [VCD=1] [CONTEXT=20]   one vector, verbose
#   make ladder-scc    every SCC vector shortest first with status
#   make test-scc-async-rx   async receive against a fast or slow sender

SCC_SRCS := rtl/k8030_scc/z8030_scc_channel.sv rtl/k8030_scc/z8030_scc.sv
SCC_TB   := $(OBJ)/tb_scc/tb_scc

.PHONY: lint-scc build-scc test-scc scc ladder-scc test-scc-timing test-scc-iack test-scc-async-rx
CHIP_LINT    += lint-scc
CHIP_BUILD   += build-scc $(OBJ)/tb_scc_timing/tb_scc_timing $(OBJ)/tb_scc_iack/tb_scc_iack $(OBJ)/tb_scc_async_rx/tb_scc_async_rx
CHIP_TEST    += test-scc test-scc-timing test-scc-iack test-scc-async-rx
CHIP_TIMING_TEST += test-scc-timing test-scc-iack

lint-scc:
	@out=$$($(VERILATOR) --lint-only $(RTL_W) $(SCC_SRCS) --top-module z8030_scc 2>&1 | grep -v MULTITOP); \
	  if [ -z "$$out" ]; then echo "lint  z8030_scc: clean"; else echo "lint  z8030_scc:"; echo "$$out"; exit 1; fi
	@out=$$($(VERILATOR) --lint-only $(RTL_W) rtl/k8030_scc/z8030_scc_channel.sv --top-module z8030_scc_channel 2>&1 | grep -v MULTITOP); \
	  if [ -z "$$out" ]; then echo "lint  z8030_scc_channel: clean"; else echo "lint  z8030_scc_channel:"; echo "$$out"; exit 1; fi

build-scc: $(SCC_TB)

$(SCC_TB): $(SCC_SRCS) tb/k8030_scc/tb_scc.cpp tb/k8030_scc/scc_access.h
	@mkdir -p $(dir $@)
	$(VBUILD) --cc --exe --build $(VFLAGS) $(RTL_W) --public-flat-rw --trace \
	  --Mdir $(dir $@) -CFLAGS '-std=c++14 -O2' \
	  --top-module z8030_scc $(SCC_SRCS) $(CURDIR)/tb/k8030_scc/tb_scc.cpp -o tb_scc >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-scc: $(SCC_TB)
	@scripts/run_vectors.sh scc

ladder-scc: $(SCC_TB)
	@scripts/run_vectors.sh scc --ladder

scc: $(SCC_TB)
	@[ -n "$(ONLY)" ] || (echo "usage: make scc ONLY=TestName[.NNN] [VCD=1] [CONTEXT=N]"; exit 1)
	@scripts/run_vectors.sh scc --one "$(ONLY)" $(if $(VCD),--vcd,) $(if $(CONTEXT),--context $(CONTEXT),)

# ---- spec TIMING bench (SystemVerilog, datasheet strobe protocol) ----------
# Not a vector replay: tb/k8030_scc/tb_scc_timing.sv drives the figures' strobe patterns
# and asserts what the datasheet says the chip must do.  See docs/TIMING_TESTS.md.
$(OBJ)/tb_scc_timing/tb_scc_timing: $(SCC_SRCS) tb/k8030_scc/tb_scc_timing.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_scc_timing \
	  $(SCC_SRCS) tb/k8030_scc/tb_scc_timing.sv -o tb_scc_timing >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-scc-timing: $(OBJ)/tb_scc_timing/tb_scc_timing
	@scripts/run_sv_bench.sh $(OBJ)/tb_scc_timing/tb_scc_timing

# Daisy-chain acknowledge bench: two chips, the first's IEO into the second's IEI.
$(OBJ)/tb_scc_iack/tb_scc_iack: $(SCC_SRCS) tb/k8030_scc/tb_scc_iack.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_scc_iack \
	  $(SCC_SRCS) tb/k8030_scc/tb_scc_iack.sv -o tb_scc_iack >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-scc-iack: $(OBJ)/tb_scc_iack/tb_scc_iack
	@scripts/run_sv_bench.sh $(OBJ)/tb_scc_iack/tb_scc_iack

# Asynchronous receive against a sender a few percent fast or slow.
$(OBJ)/tb_scc_async_rx/tb_scc_async_rx: $(SCC_SRCS) tb/k8030_scc/tb_scc_async_rx.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_scc_async_rx \
	  $(SCC_SRCS) tb/k8030_scc/tb_scc_async_rx.sv -o tb_scc_async_rx >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-scc-async-rx: $(OBJ)/tb_scc_async_rx/tb_scc_async_rx
	@scripts/run_sv_bench.sh $(OBJ)/tb_scc_async_rx/tb_scc_async_rx
