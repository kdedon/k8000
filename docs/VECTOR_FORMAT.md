# k8000 vector file formats (v1)

All vectors are recorded from the Go golden model, never hand-written.
`vectors/` is laid out by device, like `rtl/` and `tb/`; the CPU's are split
by bench under `vectors/k800x_cpu/`:

| directory                         | producer                                                    | consumer                    |
|-----------------------------------|-------------------------------------------------------------|-----------------------------|
| `vectors/k800x_cpu/cpu/*.vec`     | `sim/cpu/vecdump_test.go` (env `K8000_VEC_DIR`)             | `tb/k800x_cpu/tb_cpu.cpp`   |
| `vectors/k800x_cpu/alu/*.vec`     | `sim/cpu/alu/vecdump_test.go` + `hdl/gen/cmd/aluvec`        | `tb/k800x_cpu/tb_alu.sv`    |
| `vectors/k800x_cpu/alu_from_cpu/` | every `alu.Execute` the CPU tests made (`vecdump_test.go`)  | `tb/k800x_cpu/tb_alu.sv`    |
| `vectors/k800x_cpu/serial/`       | `hdl/gen/cmd/serialvec`                                     | `tb/k800x_cpu/tb_serial.sv` |
| `vectors/k800x_cpu/decode/`       | `hdl/gen/cmd/decoderom`                                     | `tb/k800x_cpu/tb_decode.sv` |
| `vectors/k800x_cpu/cycles/`       | `hdl/gen/cmd/cyclevec`                                      | `tb/k800x_cpu/tb_cpu_cycles.sv` |
| `vectors/k8010_mmu/*.vec`         | `sim/mmu/vecdump_test.go`                                   | `tb/k8010_mmu/tb_mmu.cpp`   |
| `vectors/k8030_scc/*.vec`         | `sim/scc/vecdump_test.go`                                   | `tb/k8030_scc/tb_scc.cpp`   |
| `vectors/k8036_cio/*.vec`         | `sim/cio/vecdump_test.go`                                   | `tb/k8036_cio/tb_cio.cpp`   |

The `K8000VEC 1 <kind>` magic on line 1 uses the short kind name (`cpu`,
`mmu`, `scc`, `cio`): it names the record schema, not the folder, and the
`*vecverify` self-checks match on it.

The files are committed sources, not build products, so a clone without
the Go model runs the whole suite. Refresh them with the maintainer targets
`make refresh-vectors` (test-suite dumps) and `make refresh-rtl` (codegen),
then commit the diff. `make refresh-vectors` first runs `vecverify`, which
replays every CPU vector into a fresh Go CPU: if the model fails its own
vectors, the RTL never will pass them. Before committing a refresh,
`hdl/gen/cmd/vecdiff <committed vectors> <fresh vectors>` classifies every
changed file (length, machine-cycle boundaries, other pins, final state)
and names the cause; a change it cannot explain exits 1.

ASCII text, one record per line. Hex is upper-case, unprefixed. `#` starts
a comment; `END` ends the file.

## CPU vectors (`K8000VEC 1 cpu`)

```
K8000VEC 1 cpu
variant Z8002                 Z8001 | Z8002 | Z8003 | Z8004
test TestNOP 0                Go test function name, CPU instance index
P R3 1234                     poke: the test wrote state directly before the next Tick
T 1FF 0000 0F3 FFFF 00 0      one Tick(Inputs) -> Outputs call
...
F REGS 0000 ... (16 words)    final architectural state after the last Tick
F FCW 4000
F PC 00000104
F PSAP 00000000
F REFRESH 0000
F NSPOFF 0000
F NSPSEG 0000
F HALTED 1
F CYCLES 18                   Go c.Cycles (rising edges seen) -- informational
F TICKS 46                    number of T records -- informational
# hint: NOP; HALT             disassembly of the first program words fetched
END
```

The Go tests that sweep every form, column or snapshot point
(`TestCycleTotalsMatchModel`, `TestMachineCyclePins`,
`TestSnapshotMidProgram*`, `TestFetchSnapshotRoundTrip`,
`TestEPADirections`) are not recorded (`vecNotRecorded` in the recorder);
they stay checks of the model.

In `F REGS`, `----` marks a register the instruction leaves undefined
(the destination of a DIV/DIVL past the quotient's width), not written
since; it is not compared. The mark covers only `F REGS`, so a vector that
stores or uses a case-3 destination would diverge.

`X unsupported <reason>` means the test restored a Go snapshot or set a
refresh pending directly (micro-architectural state the RTL cannot be
poked with); the harness reports SKIP.

### `T` record

`T <in_bits:3hex> <in_AD:4hex> <out_bits:3hex> <out_AD:4hex> <SN:2hex> <ST:1hex>`

`in_bits` (bit 10 = MSB): `CLK RESET_n STOP_n WAIT_n BUSREQ_n NMI_n NVI_n VI_n SEGT_n ABORT_n MI_n`
`out_bits` (bit 8 = MSB): `ADDrive AS_n DS_n MREQ_n R_W B_W N_S BUSACK_n MO_n`

Every Tick call of the Go pin seam (`sim/cpu/pins.go`) is recorded
verbatim. The Go harness calls Tick twice per clock (CLK=0 then CLK=1);
state advances only on the 0->1 CLK transition. RESET_n low acts on every
Tick regardless of CLK. Replay is open loop: drive the recorded inputs, one
`eval()` per record (a posedge when CLK rises), compare all outputs.

`AD` is compared only when the Go model drives it (ADDrive=1) and the
Product Spec defines it: not during ST=0000 internal operations, only AD0-8
during ST=0001 refresh, and not while `AS_n` is low on the addressless
acknowledge (0100-0111) and EPU-transfer (1110) cycles. `B_W` is not
compared during ST=0000. `SN` is compared only on SEGMENTED variants and
only while `AS_n` is low (silicon drives it about one clock before the
address, the Go model with it). See docs/K800X_CPU_TESTS.md "Spec
conformance ledger".

### `P` record

`P <what> <hex>` where `what` is `R0..R15 | FCW | PC | PSAP | REFRESH |
NSPOFF | NSPSEG | REFRESH_EN`, applied through `tb/k800x_cpu/dut_access.h`
before the next `T`. Pokes before the first `T` set the pre-reset state (a
fresh Go CPU is all zeros).

## ALU vectors (`K8000VEC 1 alu`)

`A <op:2hex> <a:16hex> <b:16hex> <cin:0|1> <width:1|2|4> <value:16hex> <flags:4hex> <mask:4hex>`

`op` = Go `alu.Op` ordinal (`z8000_ctrl_pkg` `OP_*`); width is the Go value
(byte 1, word 2, long 4; the RTL code is 1/2/3). `flags` count only under
`mask` (`alu.Result.FlagsMask`); bit positions match the FCW (C=7 Z=6 S=5
P/V=4 D=3 H=2).

## Serial-unit vectors (`K8000VEC 1 serial`)

```
M <width 16|32> <dst> <src> <delay> <ticks> <product> <rem_1> ... <rem_ticks>
D <n 16|32> <dividend> <divisor> <delay> <ticks> <dbz> <ovf> <wide> <qneg> <qzero> <quot> <rem> <rem_1> ...
S <width 8|16|32> <op> <val> <count> <ticks> <result> <flags> <mask>
```

`delay` = ticks after Start before the second operand arrives
(`SetMultiplier`/`SetDivisor` before tick delay+1). `ticks` = exact Tick
count to `Done`. `rem_k` = `Remaining()` after tick k. Product is
masked to 2*width bits; divisor is the low n bits of the sign-extended value.

## Decode vectors (`K8000VEC 1 decode`)

`D <w0:4hex> <w1_lo:1hex | -> <ctrl:CTRL_W bits hex>` -- `-` means word 2
is irrelevant (tb applies 0 and F). Packing per
`rtl/k800x_cpu/gen/z8000_ctrl_pkg.sv` (`ctrl_word_t`, MSB first).

## Cycle-count vectors (`K8000VEC 1 cycles`)

Emitted by the Go model's `hdl/gen/cmd/cyclevec`, replayed by `tb_cpu_cycles.sv`
(see `docs/TIMING_TESTS.md` sec 3). One record per curated instruction:

```
N <name>                                    record name
W <hex> <hex> ...                           program words, loaded at byte 0x0100
T <from_pc> <to_pc> <clocks> <pla> <exact|approx>
# hint: <disassembly>  (Mar81 6.7 / totals: N cycles; measured ...)
E
```

`T` is the measurement: count clocks from the IF1 (`ST=1101`) `/AS` fall at
`<from_pc>` to the next IF1 `/AS` fall, which must be at `<to_pc>`.
`<clocks>` is what the Go model does; `<pla>` is the decode ROM's base
total (Go `Decode().Cycles`, from the cited totals file).
`exact`: they agree. `approx`: the total is a base plus per-step clocks
(shifts 13+3n, MULTL 282+7n, block repeats 11+9n). The bench always
asserts `<clocks>`.

The header is `variant Z8002`: non-segmented, so plain `@Rn` addressing
works. The CPU replay vectors cover segmented SN timing.
