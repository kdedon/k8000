# mk/k8036_cio.mk -- Z8036 CIO: vectors, lint, build, test (FPGA_BIBLE Ch.4).
#
#   make vectors-cio          [MAINTAINER, needs ~/git/z8000] record vectors/k8036_cio from the Go cio test suite (+ Go self-check)
#   make lint-cio             verilator -Wall on rtl/k8036_cio/z8036_cio.sv
#   make build-cio            build obj_dir/tb_cio/tb_cio
#   make test-cio             replay every vectors/k8036_cio/*.vec, print the ladder
#   make cio ONLY=TestName    one vector with full divergence context (VCD=1, CONTEXT=N, FCLK=N)
#   make ladder-cio           every CIO vector shortest-first with status
#
# Hooked into the top-level gen/vectors/lint/build/test via CHIP_*.

CIO_SRCS := rtl/k8036_cio/z8036_cio.sv
CIO_TB   := $(OBJ)/tb_cio/tb_cio

.PHONY: gen-cio vectors-cio lint-cio build-cio test-cio cio ladder-cio test-cio-timing test-cio-iack
CHIP_GEN     += gen-cio
CHIP_VECTORS += vectors-cio
CHIP_LINT    += lint-cio
CHIP_BUILD   += build-cio $(OBJ)/tb_cio_timing/tb_cio_timing $(OBJ)/tb_cio_iack/tb_cio_iack
CHIP_TEST    += test-cio test-cio-timing test-cio-iack
CHIP_TIMING_TEST += test-cio-timing test-cio-iack

# The CIO has no generated RTL (no ROMs/PLAs to codegen).
gen-cio: require-z8000
	@true

vectors-cio: require-z8000
	rm -rf vectors/k8036_cio
	cd $(Z8000)/sim && K8000_VEC_DIR=$(CURDIR)/vectors go test -count=1 ./cio/...
	cd $(GEN) && go run ./cmd/ciovecverify $(CURDIR)/vectors/k8036_cio/*.vec
	@echo "cio vectors: $$(ls vectors/k8036_cio | wc -l)  partial: $$(grep -l '^X partial' vectors/k8036_cio/*.vec | wc -l)  unsupported: $$(grep -l '^X unsupported' vectors/k8036_cio/*.vec | wc -l)"

lint-cio:
	@out=$$($(VERILATOR) --lint-only $(RTL_W) $(CIO_SRCS) --top-module z8036_cio 2>&1); \
	  if [ -z "$$out" ]; then echo "lint  z8036_cio: clean"; else echo "lint  z8036_cio:"; echo "$$out"; exit 1; fi

build-cio: $(CIO_TB)

$(CIO_TB): $(CIO_SRCS) tb/k8036_cio/tb_cio.cpp
	@mkdir -p $(dir $@)
	$(VERILATOR) --cc --exe --build -j 4 $(VFLAGS) $(RTL_W) --trace \
	  --Mdir $(dir $@) -CFLAGS '-std=c++14 -O2' \
	  --top-module z8036_cio $(CIO_SRCS) $(CURDIR)/tb/k8036_cio/tb_cio.cpp -o tb_cio >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-cio: $(CIO_TB)
	@scripts/run_k8036_cio_vectors.sh

ladder-cio: $(CIO_TB)
	@scripts/run_k8036_cio_vectors.sh --ladder

cio: $(CIO_TB)
	@[ -n "$(ONLY)" ] || (echo "usage: make cio ONLY=TestName[.NNN] [VCD=1] [CONTEXT=N] [FCLK=N]"; exit 1)
	@scripts/run_k8036_cio_vectors.sh --one "$(ONLY)" $(if $(VCD),--vcd,) $(if $(CONTEXT),--context $(CONTEXT),) $(if $(FCLK),--fclk $(FCLK),)

# ---- spec TIMING bench (SystemVerilog, datasheet strobe protocol) ----------
# Not a vector replay: tb/k8036_cio/tb_cio_timing.sv drives the figures' strobe patterns
# and asserts what the datasheet says the chip must do.  See docs/TIMING_TESTS.md.
$(OBJ)/tb_cio_timing/tb_cio_timing: $(CIO_SRCS) tb/k8036_cio/tb_cio_timing.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_cio_timing \
	  $(CIO_SRCS) tb/k8036_cio/tb_cio_timing.sv -o tb_cio_timing >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-cio-timing: $(OBJ)/tb_cio_timing/tb_cio_timing
	@$(OBJ)/tb_cio_timing/tb_cio_timing | grep -v '\$$finish'

# Daisy-chain acknowledge bench: two chips, the first's IEO into the second's IEI.
$(OBJ)/tb_cio_iack/tb_cio_iack: $(CIO_SRCS) tb/k8036_cio/tb_cio_iack.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_cio_iack \
	  $(CIO_SRCS) tb/k8036_cio/tb_cio_iack.sv -o tb_cio_iack >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-cio-iack: $(OBJ)/tb_cio_iack/tb_cio_iack
	@$(OBJ)/tb_cio_iack/tb_cio_iack | grep -v '\$$finish'
