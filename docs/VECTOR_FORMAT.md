# k8000 vector file formats (v1)

The committed vectors are the specification the benches judge against.
They are generated, never hand-written. `vectors/` is laid out by device, like `rtl/` and `tb/`:

| directory                         | content                                   | consumer                        |
|-----------------------------------|-------------------------------------------|---------------------------------|
| `vectors/k800x_cpu/cpu/*.vec`     | CPU pins, per CLK level                   | `tb/k800x_cpu/tb_cpu.cpp`       |
| `vectors/k800x_cpu/alu/*.vec`     | constrained-random ALU cases              | `tb/k800x_cpu/tb_alu.sv`        |
| `vectors/k800x_cpu/alu_from_cpu/` | every ALU pass the CPU vectors make       | `tb/k800x_cpu/tb_alu.sv`        |
| `vectors/k800x_cpu/serial/`       | multiply, divide, shift operations        | `tb/k800x_cpu/tb_serial.sv`     |
| `vectors/k800x_cpu/decode/`       | the decode ROM, every first word          | `tb/k800x_cpu/tb_decode.sv`     |
| `vectors/k800x_cpu/cycles/`       | instruction cycle counts                  | `tb/k800x_cpu/tb_cpu_cycles.sv` |
| `vectors/k8010_mmu/*.vec`         | MMU pins                                  | `tb/k8010_mmu/tb_mmu.cpp`       |
| `vectors/k8030_scc/*.vec`         | SCC pins                                  | `tb/k8030_scc/tb_scc.cpp`       |
| `vectors/k8036_cio/*.vec`         | CIO pins                                  | `tb/k8036_cio/tb_cio.cpp`       |
| `vectors/k8070_fpu/fpu/*.vec`     | FPU pins                                  | `tb/k8070_fpu/tb_fpu.cpp`       |
| `vectors/k8070_fpu/dp/*.vec`      | Data Processor operations                 | `tb/k8070_fpu/tb_fpu_dp.cpp`    |
| `vectors/k8070_fpu/enc/`          | FPU decode digests                        | `tb/k8070_fpu/tb_fpu_enc.sv`    |
| `vectors/k8070_fpu/system/*.vec`  | CPU and FPU programs on one board         | `tb/k8070_fpu/tb_cpu_fpu.cpp`   |

The `K8000VEC 1 <kind>` magic on line 1 uses the short kind name (`cpu`,
`mmu`, `scc`, `cio`, `fpu`, `fpudp`): it names the record schema, not the
folder.

The files are committed sources, not build products, so a clone runs the
whole suite.

ASCII text, one record per line. Hex is upper-case, unprefixed. `#` starts
a comment; `END` ends the file.

## CPU vectors (`K8000VEC 1 cpu`)

```
K8000VEC 1 cpu
variant Z8002                 Z8001 | Z8002 | Z8003 | Z8004
test TestNOP 0                test name, CPU instance index
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
F CYCLES 18                   rising CLK edges seen -- informational
F TICKS 46                    number of T records -- informational
# hint: NOP; HALT             disassembly of the first program words fetched
END
```

In `F REGS`, `----` marks a register the instruction leaves undefined
(the destination of a DIV/DIVL past the quotient's width), not written
since; it is not compared. The mark covers only `F REGS`, so a vector that
stores or uses a case-3 destination would diverge.

A CPU restored from a snapshot of another CPU in the same test starts
with that CPU's records up to the save, so the RTL reaches the state through
its pins. `X unsupported snapshot-restore` means no single recorded tick
matched; the harness reports SKIP.

### `T` record

`T <in_bits:3hex> <in_AD:4hex> <out_bits:3hex> <out_AD:4hex> <SN:2hex> <ST:1hex>`

`in_bits` (bit 10 = MSB): `CLK RESET_n STOP_n WAIT_n BUSREQ_n NMI_n NVI_n VI_n SEGT_n ABORT_n MI_n`
`out_bits` (bit 8 = MSB): `ADDrive AS_n DS_n MREQ_n R_W B_W N_S BUSACK_n MO_n`

One record per CLK level, two per clock (CLK=0 then CLK=1);
state advances on the 0->1 CLK transition. The 1->0 transition moves the
strobes timed from the CLK fall (so a CLK=0 record's outputs can differ
from the record before it) and samples WAIT_n and STOP_n. RESET_n low acts
on every Tick regardless of CLK. Replay is open loop: drive the recorded
inputs, run one or more board master clocks (`clk`), compare all outputs.
The CLK pin is two pulses: `clk_rise` High for the first master clock of a
record whose CLK level rose, `clk_fall` for one whose level fell, Low
otherwise.
`--mclk P` (or K8000_MCLK) sets the master clocks per record, cycled from
the comma list P: "1" is master:CLK 2:1, "4" is 8:1, the default
"1,2,1,3" is an uneven 3.5:1.
`--combined` (or K8000_COMBINED=1) folds each CLK=0 record into the CLK=1
record after it: one master clock with both pulses High, the CLK=1
record's inputs driven, and only CLK=1 records compared (`make
test-cpu-combined`, results in `results/cpu_combined.txt`).

`AD` is compared only when the record drives it (ADDrive=1) and the
Product Spec defines it: not during ST=0000 internal operations, only AD0-8
during ST=0001 refresh, and not while `AS_n` is low on the addressless
acknowledge (0100-0111) and EPU-transfer (1110) cycles. `B_W` is not
compared during ST=0000. `SN` is compared only on SEGMENTED variants and
only while `AS_n` is low (silicon drives it about one clock before the
address, the vectors with it). See docs/K800X_CPU_TESTS.md "Spec
conformance ledger".

### `P` record

`P <what> <hex>` where `what` is `R0..R15 | FCW | PC | PSAP | REFRESH |
NSPOFF | NSPSEG | REFRESH_EN | RFSH_PEND`, applied through
`tb/k800x_cpu/dut_access.h` before the next `T`. `RFSH_PEND 1` leaves one
refresh owed, as a prescaler underflow does; `0` clears it. `REFRESH`
sets RATE and ROW, and RE when its bit 15 is; `REFRESH_EN` sets or clears
RE; either order gives the same register. With RE set, either loads the
prescaler from RATE, as an LDCTL write does. Pokes before the first `T` set the pre-reset state (otherwise all
zeros).

## ALU vectors (`K8000VEC 1 alu`)

`A <op:2hex> <a:16hex> <b:16hex> <cin:0|1> <width:1|2|4> <value:16hex> <flags:4hex> <mask:4hex>`

`op` = the `z8000_ctrl_pkg` `OP_*` ordinal; width is byte 1, word 2,
long 4 (the RTL code is 1/2/3). `flags` count only under `mask` (the flags
the op writes); bit positions match the FCW (C=7 Z=6 S=5
P/V=4 D=3 H=2).

## Serial-unit vectors (`K8000VEC 1 serial`)

```
M <width 16|32> <dst> <src> <delay> <ticks> <product> <rem_1> ... <rem_ticks>
D <n 16|32> <dividend> <divisor> <delay> <ticks> <dbz> <ovf> <wide> <qneg> <qzero> <quot> <rem> <rem_1> ...
S <width 8|16|32> <op> <val> <count> <ticks> <result> <flags> <mask>
```

`delay` = ticks after the start before the second operand arrives (given
before tick delay+1). `ticks` = exact tick count to `done`. `rem_k` = the
unit's `remaining` after tick k. Product is
masked to 2*width bits; divisor is the low n bits of the sign-extended value.

## Decode vectors (`K8000VEC 1 decode`)

`D <w0:4hex> <w1_lo:1hex | -> <ctrl:CTRL_W bits hex>` -- `-` means word 2
is irrelevant (tb applies 0 and F). Packing per
`rtl/k800x_cpu/gen/z8000_ctrl_pkg.sv` (`ctrl_word_t`, MSB first).

## Cycle-count vectors (`K8000VEC 1 cycles`)

Replayed by `tb_cpu_cycles.sv`
(see `docs/TIMING_TESTS.md` sec 3). One record per curated instruction:

```
N <name>                                    record name
W <hex> <hex> ...                           program words, loaded at byte 0x0100
T <from_pc> <to_pc> <clocks> <pla> <exact|approx>
# hint: <disassembly>  (Mar81 6.7 <column>: N cycles; measured ...)
E
...
END <n>                                     after the last of n records
```

`T` is the measurement: count clocks from the IF1 (`ST=1101`) `/AS` fall at
`<from_pc>` to the next IF1 `/AS` fall, which must be at `<to_pc>`.
`<clocks>` is the instruction's interval; `<pla>` is the published base
total from the column the instruction runs: NS, SS or SL, or `seg` (the
segmented figure) with no address word.
`exact`: they agree. `approx`: the total is a base plus per-step clocks
(shifts 13+3n, MULTL 282+7n, block repeats 11+9n). The bench always
asserts `<clocks>`.

`variant Z8002` files run non-segmented; `variant Z8001` files run
segmented in segment 0, pointers as register pairs. The bench fails
without the variant line or the `END` count.

## FPU vectors (`K8000VEC 1 fpu`, `K8000VEC 1 fpudp`)

`fpu`: one `T` record per pin sample, `P` register pokes, `F`
final registers. `fpudp`: one `D` record per Data Processor operation
(operands, result, flags, CLK.D clocks). Records, bit orders and
comparison rules: `docs/K8070_FPU_TESTS.md`.
