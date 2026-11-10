# k8000 -- the Z8000 family in SystemVerilog

RTL for the Zilog Z8001/Z8002 CPU (parameterized for the Z8003/Z8004
VMPU parts), the Z8010 MMU, the Z8030 SCC, the Z8036 CIO and the Z8070
FPU, for Cyclone V (5CSEBA6U23I7) at 48 MHz. Each chip is checked pin for
pin against recorded vectors and against Zilog's datasheet timing.

The repo holds **only SystemVerilog, Verilator testbenches and the
vectors** and is **self-contained**: `make lint build test` reads nothing
outside it. Everything under `rtl/` and `vectors/` is committed source.

Some of it is *derived*: the packages, the decode and program ROMs and the
vectors are emitted by the vector generator, currently a Go model of each
chip kept outside this repo. Only `make refresh-rtl` / `make refresh-vectors`
run it; they regenerate the committed files so the diffs can be reviewed
here. Each derived file has a local proof: `tb_decode_table` checks the ROM
against `rtl/k800x_cpu/z8000_decode_table.txt` (the decoder written out
symbolically), `tb_decode` checks it against the decode vectors, and each
chip's replay bench checks its RTL against its vectors.

**Direction:** the reference is to move from the external generator to an in-repo
document format.

## Layout

```
rtl/k800x_cpu/        the CPU -- Z8001/2/3/4 in one core
  z8000_cpu.sv          top: the chip's pins; SEGMENTED / VMPU params
  z8000_regfile.sv      16x16 register file
  z8000_alu.sv          combinational ALU
  z8000_serial.sv       serial unit: multiply, divide, shifts on one adder and rotate
  z8000_decode.sv       decode wrapper around the generated ROM
  z8000_decode_table.txt  the decode ROM symbolically: 478 control words,
                        every field named, over 8446 range records
                        (make test-decode-table)
  z8000_mc_table.txt    the machine-cycle program ROM: 434 forms, 206 programs
                        (make test-mc-table)
  z8000_bus_unit.sv     Z-Bus machine cycles: T-states, tails, internal operations
  z8000_sequencer.sv    reset sequence, then each instruction's program
  z8000_execute.sv      operand select and the ALU passes
  z8000_cond.sv         condition codes
  z8000_int_unit.sv     interrupt/trap unit
  z8000_refresh.sv      refresh prescaler / row counter
  gen/                  DERIVED, COMMITTED -- do not hand-edit (make refresh-rtl)
    z8000_ctrl_pkg.sv       ctrl_word_t and every enum
    z8000_zbus_pkg.sv       the 16 ST codes
    z8000_decode_rom_gen.sv decoder f(w0, w1[3:0]) -> ctrl_word_t
    z8000_mc_pkg.sv         machine-cycle program ROM types
    z8000_mc_rom_gen.sv     program ROM: first word -> form -> program -> cycles
rtl/k8010_mmu/        z8010_mmu.sv           memory management unit
rtl/k8030_scc/        z8030_scc[_channel].sv serial communications controller
rtl/k8036_cio/        z8036_cio.sv           counter/timer and parallel I/O
rtl/k8070_fpu/        z8070_fpu.sv           floating-point unit: z8070_ip.sv (Interface
                                             Processor), z8070_dp.sv (Data Processor),
                                             z8070_dec.sv, z8070_dp_ucode.txt; gen/ DERIVED

tb/k800x_cpu/         tb_cpu.cpp (per-edge pin replay) + dut_access.h (the harness
                      contract); tb_decode, decode_table, mc_table, alu, regfile,
                      serial, refresh, seq_words, seq_paths, cond, cpu_timing, cpu_cycles
tb/k8010_mmu/         tb_mmu.cpp + mmu_access.h, tb_mmu_timing.sv, tb_cpu_mmu_clk.sv
tb/k8030_scc/         tb_scc.cpp + scc_access.h, tb_scc_timing.sv, tb_scc_iack.sv
tb/k8036_cio/         tb_cio.cpp, tb_cio_timing.sv, tb_cio_iack.sv
tb/k8070_fpu/         tb_fpu.cpp, tb_fpu_dp.cpp, tb_fpu_enc.sv, tb_fpu_timing.sv,
                      tb_cpu_fpu.{sv,cpp} (CPU and FPU on one board)
tb/common/            z8000_bus_monitor.sv   Z-Bus protocol checker, any DUT

mk/                   per-chip Makefile fragments (k8010_mmu, k8030_scc, k8036_cio,
                      k8070_fpu) hooked into gen/vectors/lint/build/test
vectors/              DERIVED, COMMITTED (make refresh-vectors), by chip:
                      k800x_cpu/{cpu,alu,alu_from_cpu,serial,decode,cycles},
                      k8010_mmu, k8030_scc, k8036_cio, k8070_fpu/{fpu,dp,enc,system}
docs/                 STATUS.md (results), LADDER.md (build order and acceptance),
                      DECISIONS.md, RESEARCH.md, VECTOR_FORMAT.md, TIMING_TESTS.md,
                      K800X_CPU_TESTS.md, K8010_MMU_TESTS.md, K8030_SCC_TESTS.md,
                      K8036_CIO_TESTS.md, K8070_FPU_TESTS.md
                      theory/ (Theory of Operation, one per chip)
quartus/              build.sh <unit>: fit one unit on Cyclone V at 48 MHz;
                      measure/ wraps it in boundary flops
scripts/              run_k{800x_cpu,8010_mmu,8030_scc,8036_cio,8070_fpu,8070_cpu_fpu}_vectors.sh,
                      summarize.sh
```

`obj_dir/`, `results/`, `*.vcd` are build products.

## Workflow

```
make lint       # verilator -Wall on every RTL module, zero suppressions
make test       # every bench: datapath units, CPU, peripherals, FPU, timing
make cpu ONLY=TestNOP [VCD=1] [CONTEXT=20]   # one vector, full divergence report
make ladder     # every CPU vector, shortest first, with PASS/FAIL/SKIP
make test-mmu | test-cio | test-scc | test-fpu   # one chip (also <chip> ONLY=..., ladder-<chip>)
make test-timing                             # the datasheet timing benches
quartus/build.sh regfile|alu|serial|execute|cpu|mmu|cio|scc|fpudp|fpu [period_ns]  # area and Fmax
```

Two maintainer targets run the vector generator. They refresh the committed
files and fail with an explanation if it is absent:

```
make refresh-rtl        # re-emit the generated packages, ROMs and decode vectors
make refresh-vectors    # re-record vectors/<chip>/
```

`docs/LADDER.md` gives, for each datapath bench, CPU rung and peripheral
and FPU step, what to implement, the acceptance command and the traps.
Results: `docs/STATUS.md`.

## The contract

Per-edge pin equality: every output pin at every vector record, low and
high CLK samples alike. Cycle counts emerge from the FSMs; no stored totals.
`AD` is compared only while the vectors record it driven; `SN` only on
SEGMENTED builds. Final architectural state is compared too (`F` records).
Register pokes go through `tb/k800x_cpu/dut_access.h`: renaming
`u_regfile.r`, `fcw`, `pc`, `psap`, `refresh`, `nspoff`, `nspseg`,
`refresh_en` or `halted` means updating that file.

## Rules

- SystemVerilog synthesizable subset; `always_comb` next-state /
  `always_ff` commit; no internal tri-state (in/out/oe triplets); one
  board master clock, chip clock pins as enable pulses; every flop reset
  unless a comment says why not; ASCII only.
- Chip modules have only the chip's real pins.
- ALU: plain `+`, C/H/V from operand/result bits.
- `bus_done` reaches the sequencer combinationally in the same cycle
  (T3/T1 overlap is real pipelining).
- A behaviour change goes into the vector generator in the same change,
  then `make refresh-vectors`.
- RTL lints clean under `-Wall` with no suppressions. An `unused_ok`
  waiver is a placeholder: delete it once its inputs gain consumers.
