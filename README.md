# k8000 -- the Z8000 family in SystemVerilog

RTL for the Zilog Z8001/Z8002 CPU (parameterized for the
Z8003/Z8004 VMPU parts) and the Z8010 MMU, Z8036 CIO and Z8030 SCC,
derived from Golang golden models and verified against them in lockstep.

The repo holds **only SystemVerilog and Verilator testbenches** and is
**self-contained**: `make lint build test` reads nothing outside it and
needs no Go toolchain. Everything under `rtl/` and `vectors/` is committed
source.

Some of it is *derived*: the packages, the reference decode ROM and the
vectors are emitted from the Go model. Only `make refresh-rtl` /
`make refresh-vectors` read the model; they regenerate the committed files
so the diffs can be reviewed here. Each derived file has a local proof:
`tb_decode_table` checks the ROM against
`rtl/k800x_cpu/z8000_decode_table.txt` (the decoder written out
symbolically for review), `tb_decode` checks it against the decode vectors,
and each device's replay bench checks its RTL against its vectors.

## Layout

```
rtl/k800x_cpu/        the CPU -- Z8001/2/3/4 in one core
  z8000_cpu.sv          top: pins == sim/cpu/pins.go; SEGMENTED / VMPU params
  z8000_regfile.sv      16x16 register file (registers.File)
  z8000_alu.sv          combinational ALU (alu.GoALU.Execute)
  z8000_mult.sv         bit-serial multiplier (alu.MultState)
  z8000_div.sv          bit-serial divider (alu.DivState)
  z8000_shift.sv        bit-serial shifter (alu.ShiftState)
  z8000_decode.sv       decode wrapper around the generated ROM
  z8000_decode_table.txt  the decode ROM symbolically: 476 control words,
                        every field NAMED, over 8446 first-word ranges.
                        Review decoder diffs here (make test-decode-table)
  z8000_mc_table.txt    the machine-cycle program ROM: every form's program
                        per column and path (make test-mc-table)
  z8000_bus_unit.sv     Z-Bus machine cycles: T-states, tails, internal operations
  z8000_sequencer.sv    reset sequence, then each instruction's program
  z8000_execute.sv      operand select and the ALU passes
  z8000_int_unit.sv     interrupt/trap unit
  z8000_refresh.sv      refresh prescaler / row counter
  gen/                  DERIVED, COMMITTED -- do not hand-edit (make refresh-rtl)
    z8000_ctrl_pkg.sv       ctrl_word_t + every enum (InstrClass, SrcSel, alu.Op ...)
    z8000_zbus_pkg.sv       the 16 ST codes
    z8000_decode_rom_gen.sv reference decoder f(w0, w1[3:0]) -> ctrl_word_t
    z8000_mc_pkg.sv         machine-cycle program ROM types
    z8000_mc_rom_gen.sv     program ROM: first word -> form -> program -> cycles
rtl/k8010_mmu/        z8010_mmu.sv           memory management unit
rtl/k8030_scc/        z8030_scc[_channel].sv serial communications controller
rtl/k8036_cio/        z8036_cio.sv           counter/timer + parallel I/O

tb/k800x_cpu/         tb_cpu.cpp (per-edge pin replay) + dut_access.h (the harness
                      contract), tb_decode/decode_table/mc_table/alu/regfile/serial.sv, tb_cpu_timing.sv,
                      tb_cpu_cycles.sv
tb/k8010_mmu/         tb_mmu.cpp + mmu_access.h, tb_mmu_timing.sv
tb/k8030_scc/         tb_scc.cpp + scc_access.h, tb_scc_timing.sv
tb/k8036_cio/         tb_cio.cpp, tb_cio_timing.sv
tb/common/            z8000_bus_monitor.sv   Z-Bus protocol checker, any DUT

mk/                   per-device Makefile fragments (k8010_mmu.mk, k8030_scc.mk,
                      k8036_cio.mk) hooked into gen/vectors/lint/build/test
vectors/              DERIVED, COMMITTED (make refresh-vectors), by device:
                      k800x_cpu/{cpu,alu,alu_from_cpu,serial,decode,cycles},
                      k8010_mmu, k8030_scc, k8036_cio
docs/                 LADDER.md (the execution plan), STATUS.md, VECTOR_FORMAT.md,
                      TIMING_TESTS.md, K800X_CPU_TESTS.md, K8010_MMU_TESTS.md,
                      K8030_SCC_TESTS.md, K8036_CIO_TESTS.md
quartus/              build.sh <unit>: fit one unit on Cyclone V at 48 MHz;
                      measure/ wraps it in boundary flops
scripts/              run_k{800x_cpu,8010_mmu,8030_scc,8036_cio}_vectors.sh,
                      summarize.sh
bench/c900/           NOT RTL: K&R C and Z8000 assembly programs for a REAL
                      Commodore 900 under Coherent, to check the datasheet
                      cycle counts against hardware. Not built by
                      `make lint build test`. See bench/c900/README.md;
                      expected/expected.txt is generated from the Go model.
```

`obj_dir/`, `results/`, `*.vcd` are build products.

## Workflow

```
make lint       # verilator -Wall on every RTL module, zero suppressions
make test       # decode, alu, regfile, serial, then the CPU ladder
make cpu ONLY=TestNOP [VCD=1] [CONTEXT=20]   # one vector, full divergence report
make ladder     # every CPU vector, shortest first, with PASS/FAIL/SKIP
make test-mmu | test-cio | test-scc          # peripherals (also: mmu/cio/scc ONLY=..., ladder-<chip>)
quartus/build.sh regfile|alu|mult|div|shift|execute|cpu [period_ns]  # area and Fmax; Docker if no quartus_sh
```

Only two maintainer targets leave the repo. They refresh the committed
files from the Go model and fail with an explanation if it is absent:

```
make refresh-rtl        # re-emit rtl/k800x_cpu/gen/*.sv + the decode vectors
make refresh-vectors    # re-record vectors/<device>/ from the Go test suites
```

`make test-cpu` prints pass/fail counts and the shortest failing vectors.

**Start with `docs/LADDER.md`**, the execution plan: for each datapath
bench, CPU rung and MMU / CIO / SCC step, what to implement, the acceptance
command and the traps. Results: `docs/STATUS.md`.

## The contract

Per-edge pin equality: every output pin after every Tick the Go test made,
low and high samples alike. Cycle counts EMERGE from the FSMs; the cycle
PLA is a checker in the Go tests, never RTL logic. `AD` is compared only
while the Go model drives it; `SN` only on SEGMENTED builds. Final
architectural state is compared too (`F` records). The Go tests' register
pokes go through `tb/k800x_cpu/dut_access.h`: renaming `u_regfile.r`,
`fcw`, `pc`, `psap`, `refresh`, `nspoff`, `nspseg`, `refresh_en` or
`halted` means updating that file.

## Rules

- SystemVerilog synthesizable subset; `always_comb` next-state /
  `always_ff` commit; no internal tri-state (in/out/oe triplets); one
  clock, clock ENABLES; every flop reset unless a comment says why not;
  ASCII only.
- ALU: plain `+`, C/H/V from operand/result bits -- do NOT port the Go
  ripple carryChain.
- `bus_done` reaches the sequencer combinationally in the same cycle
  (T3/T1 overlap is real pipelining).
- A deliberate divergence from the Go model is fixed IN THE GO MODEL in the
  same change, then `make refresh-vectors`.
- RTL lints clean under `-Wall` with no suppressions. The `unused_ok`
  waivers in unfinished modules are placeholders: delete each as its inputs
  gain consumers.
