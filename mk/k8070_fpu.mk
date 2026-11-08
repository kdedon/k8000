# mk/k8070_fpu.mk -- Z8070 FPU: vectors, lint, build, test.
#
#   make gen-fpu             [MAINTAINER, needs ~/git/z8000] the decode table package and its digests from the Go model,
#                            and the Data Processor microcode package from rtl/k8070_fpu/z8070_dp_ucode.txt
#   make vectors-fpu          [MAINTAINER, needs ~/git/z8000] record vectors/k8070_fpu/fpu (pins) and dp (Data Processor) from the Go fpu suite (+ Go self-check)
#   make lint-fpu             verilator -Wall on rtl/k8070_fpu (top, decoder, Interface Processor, Data Processor)
#   make build-fpu            build obj_dir/tb_fpu/tb_fpu
#   make test-fpu             replay every vectors/k8070_fpu/fpu/*.vec, print the ladder
#   make fpu ONLY=TestName    one vector with full divergence context (VCD=1, CONTEXT=N, MCLK=P)
#   make ladder-fpu           every FPU vector shortest-first with status
#   make test-fpu-timing      the specification bench
#   make test-fpu-enc         the RTL decode against the Go decode digests, every input
#   make test-fpu-dp [ONLY=g,...]  the Data Processor alone against vectors/k8070_fpu/dp (groups: add load sign cmp mul div sqrt fint rem conv bcd)
#
# Hooked into the top-level gen/vectors/lint/build/test via CHIP_*.

FPU_TOP  := z8070_fpu
FPU_ENC  := rtl/k8070_fpu/gen/z8070_enc_pkg.sv
FPU_UROM := rtl/k8070_fpu/gen/z8070_dp_rom_pkg.sv rtl/k8070_fpu/gen/z8070_dp_rom.sv
FPU_PKG  := $(FPU_ENC) $(FPU_UROM)
FPU_MODS := z8070_dec z8070_ip z8070_dp
FPU_SRCS := $(FPU_PKG) $(patsubst %,rtl/k8070_fpu/%.sv,$(FPU_MODS)) rtl/k8070_fpu/z8070_fpu.sv
FPU_TB   := $(OBJ)/tb_fpu/tb_fpu
FPU_DP_SRCS := $(FPU_UROM) rtl/k8070_fpu/z8070_dp.sv
FPU_DP_TB   := $(OBJ)/tb_fpu_dp/tb_fpu_dp

.PHONY: gen-fpu vectors-fpu lint-fpu build-fpu test-fpu fpu ladder-fpu test-fpu-timing test-fpu-enc test-fpu-dp
CHIP_GEN     += gen-fpu
CHIP_VECTORS += vectors-fpu
CHIP_LINT    += lint-fpu
CHIP_BUILD   += build-fpu $(OBJ)/tb_fpu_timing/tb_fpu_timing $(OBJ)/tb_fpu_enc/tb_fpu_enc $(FPU_DP_TB)
CHIP_TEST    += test-fpu-enc test-fpu test-fpu-timing test-fpu-dp
CHIP_TIMING_TEST += test-fpu-timing

# The decode table (rtl/k8070_fpu/gen) and its digests (vectors/k8070_fpu/enc).
gen-fpu: require-z8000
	cd $(GEN) && go run ./cmd/fpuenc -root $(CURDIR)
	cd $(GEN) && go run ./cmd/fpuucode -root $(CURDIR)

# One go test run records both kinds: fpu/ from the chip tests, dp/ from
# the Data Processor tests.
vectors-fpu: require-z8000
	rm -rf vectors/k8070_fpu/fpu vectors/k8070_fpu/dp vectors/k8070_fpu/enc
	cd $(Z8000)/sim && K8000_VEC_DIR=$(CURDIR)/vectors go test -count=1 ./fpu/...
	cd $(GEN) && go run ./cmd/fpuenc -root $(CURDIR)
	cd $(GEN) && go run ./cmd/fpuvecverify $(CURDIR)/vectors/k8070_fpu/fpu/*.vec $(CURDIR)/vectors/k8070_fpu/dp/*.vec
	@echo "fpu vectors: $$(ls vectors/k8070_fpu/fpu | wc -l)  dp: $$(ls vectors/k8070_fpu/dp | wc -l)  unsupported: $$(grep -l '^X unsupported' vectors/k8070_fpu/fpu/*.vec | wc -l)"

lint-fpu:
	@for m in $(FPU_MODS); do \
	  extra=""; [ $$m = z8070_ip ] && extra=rtl/k8070_fpu/z8070_dec.sv; \
	  pkg="$(FPU_ENC)"; [ $$m = z8070_dp ] && pkg="$(FPU_UROM)"; \
	  out=$$($(VERILATOR) --lint-only $(RTL_W) $$pkg rtl/k8070_fpu/$$m.sv $$extra --top-module $$m 2>&1); \
	  if [ -z "$$out" ]; then echo "lint  $$m: clean"; else echo "lint  $$m:"; echo "$$out"; fail=1; fi; \
	done; \
	out=$$($(VERILATOR) --lint-only $(RTL_W) $(FPU_SRCS) --top-module $(FPU_TOP) 2>&1); \
	if [ -z "$$out" ]; then echo "lint  $(FPU_TOP): clean"; else echo "lint  $(FPU_TOP):"; echo "$$out"; fail=1; fi; \
	[ -z "$$fail" ]

build-fpu: $(FPU_TB)

$(FPU_TB): $(FPU_SRCS) tb/k8070_fpu/tb_fpu.cpp tb/k8070_fpu/fpu_access.h
	@mkdir -p $(dir $@)
	$(VERILATOR) --cc --exe --build -j 4 $(VFLAGS) $(RTL_W) --public-flat-rw --trace \
	  --Mdir $(dir $@) -CFLAGS '-std=c++14 -O2' \
	  --top-module $(FPU_TOP) $(FPU_SRCS) $(CURDIR)/tb/k8070_fpu/tb_fpu.cpp -o tb_fpu >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-fpu: $(FPU_TB)
	@scripts/run_k8070_fpu_vectors.sh

ladder-fpu: $(FPU_TB)
	@scripts/run_k8070_fpu_vectors.sh --ladder

fpu: $(FPU_TB)
	@[ -n "$(ONLY)" ] || (echo "usage: make fpu ONLY=TestName[.NNN] [VCD=1] [CONTEXT=N] [MCLK=P]"; exit 1)
	@scripts/run_k8070_fpu_vectors.sh --one "$(ONLY)" $(if $(VCD),--vcd,) $(if $(CONTEXT),--context $(CONTEXT),) $(if $(MCLK),--mclk $(MCLK),)

# ---- decode table bench (SystemVerilog) -----------------------------------
$(OBJ)/tb_fpu_enc/tb_fpu_enc: $(FPU_ENC) rtl/k8070_fpu/z8070_dec.sv tb/k8070_fpu/tb_fpu_enc.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_fpu_enc \
	  $(FPU_ENC) rtl/k8070_fpu/z8070_dec.sv tb/k8070_fpu/tb_fpu_enc.sv -o tb_fpu_enc >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-fpu-enc: $(OBJ)/tb_fpu_enc/tb_fpu_enc
	@$(OBJ)/tb_fpu_enc/tb_fpu_enc | grep -v '\$$finish'

# ---- spec TIMING bench (SystemVerilog) -------------------------------------
$(OBJ)/tb_fpu_timing/tb_fpu_timing: $(FPU_SRCS) tb/k8070_fpu/tb_fpu_timing.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_fpu_timing \
	  $(FPU_SRCS) tb/k8070_fpu/tb_fpu_timing.sv -o tb_fpu_timing >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-fpu-timing: $(OBJ)/tb_fpu_timing/tb_fpu_timing
	@$(OBJ)/tb_fpu_timing/tb_fpu_timing | grep -v '\$$finish'

# ---- Data Processor bench (C++) --------------------------------------------
$(FPU_DP_TB): $(FPU_DP_SRCS) tb/k8070_fpu/tb_fpu_dp.cpp
	@mkdir -p $(dir $@)
	$(VERILATOR) --cc --exe --build -j 4 $(VFLAGS) $(RTL_W) \
	  --Mdir $(dir $@) -CFLAGS '-std=c++14 -O2' \
	  --top-module z8070_dp $(FPU_DP_SRCS) $(CURDIR)/tb/k8070_fpu/tb_fpu_dp.cpp -o tb_fpu_dp >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

# With ONLY the exit status is the rung's; without, the whole ladder prints
# and the run does not stop `make test`.
test-fpu-dp: $(FPU_DP_TB)
	@$(FPU_DP_TB) $(if $(ONLY),--only $(ONLY),) $(if $(MCLK),--mclk $(MCLK),) vectors/k8070_fpu/dp/*.vec $(if $(ONLY),,|| true)

# ---- CPU + FPU system bench (C++) ------------------------------------------
#   make vectors-cpu-fpu  [MAINTAINER, needs ~/git/z8000] record vectors/k8070_fpu/system from the Go sim/system FPU tests
#   make test-cpu-fpu     replay every system vector through tb/k8070_fpu/tb_cpu_fpu.sv (z8000_cpu + z8070_fpu), Z8001 then Z8002
#   make cpu-fpu ONLY=TestName[.Z8001.000] [VCD=1] [CONTEXT=N] [MCLK=P]   one vector, full context
CHIP_VECTORS += vectors-cpu-fpu
CHIP_BUILD   += $(OBJ)/tb_cpu_fpu_z8001/tb_cpu_fpu_z8001 $(OBJ)/tb_cpu_fpu_z8002/tb_cpu_fpu_z8002
CHIP_TEST    += test-cpu-fpu
.PHONY: vectors-cpu-fpu test-cpu-fpu cpu-fpu

vectors-cpu-fpu: require-z8000
	mkdir -p vectors/k8070_fpu/system
	rm -f vectors/k8070_fpu/system/*.vec
	cd $(Z8000)/sim && K8000_VEC_DIR=$(CURDIR)/vectors go test -count=1 -run '^TestFPUSystem' ./system/
	@echo "cpu+fpu system vectors: $$(ls vectors/k8070_fpu/system | wc -l)"

# SYNCASYNCNET: one board /RESET into the CPU's asynchronous and the FPU's
# synchronous reset.
define CPU_FPU_BUILD
$(OBJ)/tb_cpu_fpu_$(1)/tb_cpu_fpu_$(1): $(CPU_SRCS) $(FPU_SRCS) tb/k8070_fpu/tb_cpu_fpu.sv tb/k8070_fpu/tb_cpu_fpu.cpp tb/k8070_fpu/cpu_fpu_access.h
	@mkdir -p $$(dir $$@)
	$(VERILATOR) --cc --exe --build -j 4 $(VFLAGS) $(RTL_W) --public-flat-rw --trace \
	  -Wno-SYNCASYNCNET --Mdir $$(dir $$@) -GSEGMENTED=1\'b$(2) \
	  -CFLAGS '-DK8000_VARIANT=\"$(3)\" -DK8000_SEGMENTED=$(2) -std=c++14 -O2' \
	  --top-module tb_cpu_fpu $(CPU_SRCS) $(FPU_SRCS) tb/k8070_fpu/tb_cpu_fpu.sv $(CURDIR)/tb/k8070_fpu/tb_cpu_fpu.cpp -o tb_cpu_fpu_$(1) >$$(dir $$@)build.log 2>&1 || (cat $$(dir $$@)build.log; exit 1)
endef
$(eval $(call CPU_FPU_BUILD,z8001,1,Z8001))
$(eval $(call CPU_FPU_BUILD,z8002,0,Z8002))

test-cpu-fpu: $(OBJ)/tb_cpu_fpu_z8001/tb_cpu_fpu_z8001 $(OBJ)/tb_cpu_fpu_z8002/tb_cpu_fpu_z8002
	@scripts/run_k8070_cpu_fpu_vectors.sh

cpu-fpu: $(OBJ)/tb_cpu_fpu_z8001/tb_cpu_fpu_z8001 $(OBJ)/tb_cpu_fpu_z8002/tb_cpu_fpu_z8002
	@[ -n "$(ONLY)" ] || (echo "usage: make cpu-fpu ONLY=TestName[.Z8001.000] [VCD=1] [CONTEXT=N] [MCLK=P]"; exit 1)
	@scripts/run_k8070_cpu_fpu_vectors.sh --one "$(ONLY)" $(if $(VCD),--vcd,) $(if $(CONTEXT),--context $(CONTEXT),) $(if $(MCLK),--mclk $(MCLK),)
