# mk/silicon.mk -- programs captured on a physical Z8001, replayed on the
# Z8001 build (vectors/k800x_cpu/silicon, docs/K800X_CPU_TESTS.md).
#
#   make test-cpu-silicon   replay z8001.vec (non-segmented) and z8001-seg.vec
#   make build-silicon      build obj_dir/tb_silicon_z8001/tb_silicon_z8001
#
# Hooked into the top-level build/test via CHIP_*.

SILICON_TB   := $(OBJ)/tb_silicon_z8001/tb_silicon_z8001
SILICON_VECS := vectors/k800x_cpu/silicon/z8001.vec vectors/k800x_cpu/silicon/z8001-seg.vec

.PHONY: build-silicon test-cpu-silicon
CHIP_BUILD += build-silicon
CHIP_TEST  += test-cpu-silicon

build-silicon: $(SILICON_TB)

$(SILICON_TB): $(CPU_SRCS) tb/k800x_cpu/tb_silicon.sv
	@mkdir -p $(dir $@)
	$(VBUILD) --binary --timing $(VFLAGS) $(TB_W) -Wno-MULTIDRIVEN --Mdir $(dir $@) --top-module tb_silicon -GSEGMENTED=1\'b1 \
	  $(CPU_SRCS) tb/k800x_cpu/tb_silicon.sv -o tb_silicon_z8001 >$(dir $@)build.log 2>&1 || (cat $(dir $@)build.log; exit 1)

test-cpu-silicon: $(SILICON_TB)
	@fail=0; for v in $(SILICON_VECS); do scripts/run_sv_bench.sh -t 1 $(SILICON_TB) +vec=$$v || fail=1; done; [ $$fail -eq 0 ]
