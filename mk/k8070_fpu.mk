# mk/k8070_fpu.mk -- Z8070 FPU: lint, build, test.
#
#   make lint-fpu             verilator -Wall on rtl/k8070_fpu (top, decoder, Interface Processor, Data Processor)
#   make build-fpu            build obj_dir/tb_fpu/tb_fpu
#   make test-fpu             replay every vectors/k8070_fpu/fpu/*.vec, print the ladder
#   make fpu ONLY=TestName    one vector with full divergence context (VCD=1, CONTEXT=N, MCLK=P)
#   make ladder-fpu           every FPU vector shortest-first with status
#   make test-fpu-timing      the specification bench
#   make test-fpu-enc         the RTL decode against the decode digests, every input
#   make test-fpu-dp [ONLY=g,...]  the Data Processor alone against vectors/k8070_fpu/dp (groups: add load sign cmp mul div sqrt fint rem conv bcd)
#
# Hooked into the top-level lint/build/test via CHIP_*.

FPU_TOP  := z8070_fpu
FPU_ENC  := rtl/k8070_fpu/gen/z8070_enc_pkg.sv
FPU_UROM := rtl/k8070_fpu/gen/z8070_dp_rom_pkg.sv rtl/k8070_fpu/gen/z8070_dp_rom.sv
FPU_PKG  := $(FPU_ENC) $(FPU_UROM)
FPU_MODS := z8070_dec z8070_ip z8070_dp
FPU_SRCS := $(FPU_PKG) $(patsubst %,rtl/k8070_fpu/%.sv,$(FPU_MODS)) rtl/k8070_fpu/z8070_fpu.sv
FPU_TB   := $(OBJ)/tb_fpu/tb_fpu
FPU_DP_SRCS := $(FPU_UROM) rtl/k8070_fpu/z8070_dp.sv
FPU_DP_TB   := $(OBJ)/tb_fpu_dp/tb_fpu_dp

.PHONY: lint-fpu build-fpu test-fpu fpu ladder-fpu test-fpu-timing test-fpu-enc test-fpu-dp
CHIP_LINT    += lint-fpu
CHIP_BUILD   += build-fpu $(OBJ)/tb_fpu_timing/tb_fpu_timing $(OBJ)/tb_fpu_enc/tb_fpu_enc $(FPU_DP_TB)
CHIP_TEST    += test-fpu-enc test-fpu test-fpu-timing test-fpu-dp
CHIP_TIMING_TEST += test-fpu-timing

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
	$(VBUILD) --cc --exe --build $(VFLAGS) $(RTL_W) --public-flat-rw --trace \
	  --Mdir $(dir $@) -CFLAGS '-std=c++14 -O2' \
	  --top-module $(FPU_TOP) $(FPU_SRCS) $(CURDIR)/tb/k8070_fpu/tb_fpu.cpp -o tb_fpu >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-fpu: $(FPU_TB)
	@scripts/run_vectors.sh fpu

ladder-fpu: $(FPU_TB)
	@scripts/run_vectors.sh fpu --ladder

fpu: $(FPU_TB)
	@[ -n "$(ONLY)" ] || (echo "usage: make fpu ONLY=TestName[.NNN] [VCD=1] [CONTEXT=N] [MCLK=P]"; exit 1)
	@scripts/run_vectors.sh fpu --one "$(ONLY)" $(if $(VCD),--vcd,) $(if $(CONTEXT),--context $(CONTEXT),) $(if $(MCLK),--mclk $(MCLK),)

# ---- decode table bench (SystemVerilog) -----------------------------------
$(OBJ)/tb_fpu_enc/tb_fpu_enc: $(FPU_ENC) rtl/k8070_fpu/z8070_dec.sv tb/k8070_fpu/tb_fpu_enc.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_fpu_enc \
	  $(FPU_ENC) rtl/k8070_fpu/z8070_dec.sv tb/k8070_fpu/tb_fpu_enc.sv -o tb_fpu_enc >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-fpu-enc: $(OBJ)/tb_fpu_enc/tb_fpu_enc
	@scripts/run_sv_bench.sh $(OBJ)/tb_fpu_enc/tb_fpu_enc

# ---- spec TIMING bench (SystemVerilog) -------------------------------------
$(OBJ)/tb_fpu_timing/tb_fpu_timing: $(FPU_SRCS) tb/k8070_fpu/tb_fpu_timing.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) --Mdir $(dir $@) --top-module tb_fpu_timing \
	  $(FPU_SRCS) tb/k8070_fpu/tb_fpu_timing.sv -o tb_fpu_timing >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-fpu-timing: $(OBJ)/tb_fpu_timing/tb_fpu_timing
	@scripts/run_sv_bench.sh $(OBJ)/tb_fpu_timing/tb_fpu_timing

# ---- Data Processor bench (C++) --------------------------------------------
$(FPU_DP_TB): $(FPU_DP_SRCS) tb/k8070_fpu/tb_fpu_dp.cpp
	@mkdir -p $(dir $@)
	$(VBUILD) --cc --exe --build $(VFLAGS) $(RTL_W) \
	  --Mdir $(dir $@) -CFLAGS '-std=c++14 -O2' \
	  --top-module z8070_dp $(FPU_DP_SRCS) $(CURDIR)/tb/k8070_fpu/tb_fpu_dp.cpp -o tb_fpu_dp >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-fpu-dp: $(FPU_DP_TB)
	@timeout $${K8000_TIMEOUT:-1800} $(FPU_DP_TB) $(if $(ONLY),--only $(ONLY),) $(if $(MCLK),--mclk $(MCLK),) vectors/k8070_fpu/dp/*.vec

# ---- CPU + FPU system bench (C++) ------------------------------------------
#   make test-cpu-fpu     replay every system vector through tb/k8070_fpu/tb_cpu_fpu.sv (z8000_cpu + z8070_fpu), Z8001 then Z8002
#   make cpu-fpu ONLY=TestName[.Z8001.000] [VCD=1] [CONTEXT=N] [MCLK=P]   one vector, full context
CHIP_BUILD   += $(OBJ)/tb_cpu_fpu_z8001/tb_cpu_fpu_z8001 $(OBJ)/tb_cpu_fpu_z8002/tb_cpu_fpu_z8002
CHIP_TEST    += test-cpu-fpu
.PHONY: test-cpu-fpu cpu-fpu

# SYNCASYNCNET: one board /RESET into the CPU's asynchronous and the FPU's
# synchronous reset.
define CPU_FPU_BUILD
$(OBJ)/tb_cpu_fpu_$(1)/tb_cpu_fpu_$(1): $(CPU_SRCS) $(FPU_SRCS) tb/k8070_fpu/tb_cpu_fpu.sv tb/k8070_fpu/tb_cpu_fpu.cpp tb/k8070_fpu/cpu_fpu_access.h
	@mkdir -p $$(dir $$@)
	$(VBUILD) --cc --exe --build $(VFLAGS) $(RTL_W) --public-flat-rw --trace \
	  -Wno-SYNCASYNCNET --Mdir $$(dir $$@) -GSEGMENTED=1\'b$(2) \
	  -CFLAGS '-DK8000_VARIANT=\"$(3)\" -DK8000_SEGMENTED=$(2) -std=c++14 -O2' \
	  --top-module tb_cpu_fpu $(CPU_SRCS) $(FPU_SRCS) tb/k8070_fpu/tb_cpu_fpu.sv $(CURDIR)/tb/k8070_fpu/tb_cpu_fpu.cpp -o tb_cpu_fpu_$(1) >$$(dir $$@)build.log 2>&1 || (cat $$(dir $$@)build.log; exit 1)
endef
$(eval $(call CPU_FPU_BUILD,z8001,1,Z8001))
$(eval $(call CPU_FPU_BUILD,z8002,0,Z8002))

test-cpu-fpu: $(OBJ)/tb_cpu_fpu_z8001/tb_cpu_fpu_z8001 $(OBJ)/tb_cpu_fpu_z8002/tb_cpu_fpu_z8002
	@scripts/run_vectors.sh cpu-fpu

cpu-fpu: $(OBJ)/tb_cpu_fpu_z8001/tb_cpu_fpu_z8001 $(OBJ)/tb_cpu_fpu_z8002/tb_cpu_fpu_z8002
	@[ -n "$(ONLY)" ] || (echo "usage: make cpu-fpu ONLY=TestName[.Z8001.000] [VCD=1] [CONTEXT=N] [MCLK=P]"; exit 1)
	@scripts/run_vectors.sh cpu-fpu --one "$(ONLY)" $(if $(VCD),--vcd,) $(if $(CONTEXT),--context $(CONTEXT),) $(if $(MCLK),--mclk $(MCLK),)

# ---- fast CLK.D pass ---------------------------------------------------------
#   make test-fpu-fastd   every FPU and CPU+FPU vector with CLK.D rising every master clock
CHIP_TEST += test-fpu-fastd
.PHONY: test-fpu-fastd

test-fpu-fastd: $(FPU_TB) $(OBJ)/tb_cpu_fpu_z8001/tb_cpu_fpu_z8001 $(OBJ)/tb_cpu_fpu_z8002/tb_cpu_fpu_z8002
	@scripts/run_vectors.sh fastd

# ---- slow CLK.D pass ---------------------------------------------------------
#   make test-fpu-slowd   every FPU and CPU+FPU vector with CLK.D at 1/8 and 1/12 of CLK.I
CHIP_TEST += test-fpu-slowd
.PHONY: test-fpu-slowd

test-fpu-slowd: $(FPU_TB) $(OBJ)/tb_cpu_fpu_z8001/tb_cpu_fpu_z8001 $(OBJ)/tb_cpu_fpu_z8002/tb_cpu_fpu_z8002
	@scripts/run_vectors.sh slowd
