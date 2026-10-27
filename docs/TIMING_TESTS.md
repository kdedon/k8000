# Timing and cycle-accuracy benches

Three questions, three kinds of bench:

| question | bench | golden source |
|---|---|---|
| does it behave like the audited model, edge for edge? | `tb/<device>/tb_{cpu,mmu,scc,cio}.cpp` (vector replay) | recorded `vectors/<device>/*.vec` |
| is what it does **legal per the datasheet**? | `tb/<device>/tb_*_timing.sv` + `tb/common/z8000_bus_monitor.sv` | Zilog product specs, cited per check |
| does each instruction take the **documented number of clocks**? | `tb/k800x_cpu/tb_cpu_cycles.sv` | `vectors/k800x_cpu/cycles/cycles.vec` from Mar81 sec 6.7 via `cyclesPLA` |

`<device>` is `k800x_cpu`, `k8010_mmu`, `k8030_scc` or `k8036_cio`; bench
modules keep the short `tb_<chip>_timing` names, like the make targets.
`z8000_bus_monitor.sv` is in `tb/common/` because it checks any Z-Bus DUT.

`make test-timing` runs every spec bench plus the cycle bench; individually:
`make test-cpu-timing`, `make test-cpu-cycles`, `make test-mmu-timing`,
`make test-cio-timing`, `make test-scc-timing`. `make test` runs them too.

A failing check prints its spec citation (figure or AC row). Results:
`docs/STATUS.md`.

---

## 1. `z8000_bus_monitor.sv` -- continuous Z-Bus protocol checker

Watches the CPU's pins every clock and flags anything the Z8001/2 Product
Spec (1988 Data Book pp.150-160) forbids, on the clock it first happens.
Instantiate it next to the DUT in any bench.

One posedge = one CPU clock; pin values are those after the edge (the Go
model's per-Tick outputs). Offsets are clocks from the sample where `/AS`
first went Low (T1 = 0).

Per-sample rules:

| rule | source |
|---|---|
| `/AS` and `/DS` are never Low together | z8036_cio p.674 / z8030_scc: that combination is the peripherals' hardware-reset condition, never a transaction |
| `/AS` never stays Low across an address or status change | Fig 12: address+status are valid for the whole of T1; the `/AS` rise is the external latch point |
| the address is driven whenever `/AS` is Low | Fig 12 |
| `SN` reads zero when `SEGMENTED=0` | p.150: SN6-SN0 exist only on the Z8001/Z8003 |
| every bus output is floated while `/BUSACK` is Low | Fig 15 |

Per-transaction rules (offsets in clocks from the `/AS` fall, external `/WAIT`
clocks discounted):

| cycle class | `/MREQ` | `/DS` falls | `/DS` rises | other |
|---|---|---|---|---|
| memory read | 1 | 1 | 3 | AD released while `/DS` Low |
| memory write | 1 | 2 | 3 | write data held for the whole `/DS` Low window; a BYTE write duplicates the byte on both halves of AD (Ref Manual 9.4.2 p.234, R-CPU-513) |
| I/O (0010/0011) | never | 2 | 4 | one automatic wait, Fig 13 |
| acknowledge (0100..0111) | never | 5 | 8 | five automatic waits, `/DS` falls at the fourth so the IEI/IEO chain settles, Fig 14 |
| refresh (0001) | 1 | never | -- | `R/W`, `B/W`, `N/S` unchanged from the preceding transaction (Fig 18 / Ref Manual 9.4.6) |
| internal op (0000) | never | never | -- | `/AS` pulse only, Fig 17 |

The offsets come from the AC table (p.159-160: `/MREQ` after the T1 falling
edge, `/DS(read)` from the T2 clock, `/DS(write)` from the T2 FALLING edge,
both strobes rising after the T3 falling edge), cross-checked against every
recorded CPU vector.

## 2. `tb_cpu_timing.sv`

Layer 1 -- no program: the reset pin state
(Product Spec "Reset" + Fig 19, Ref Manual 7.4) -- ST forced High, `/AS`
`/DS` `/MREQ` `/BUSACK` `/MO` High, SN Low, AD 3-stated, all within five
clocks of `/RESET` going Low.

Layer 2 -- a behavioural RAM + I/O slave runs a Z8002 program with the
monitor armed: instruction fetch, memory word read/write, memory byte write,
standard I/O in and out (two slave `/WAIT` clocks, Fig 13) and HALT. It also
asserts the reset PSA fetch happened, each cycle class appeared, and a word
write landed at the address latched at `/AS`.

## 3. `tb_cpu_cycles.sv` -- instruction cycle counts

Cycle counts are datasheet facts (Z8000 CPU Technical Manual Mar81 sec 6.7).
The Go model reproduces them structurally (`cyclesPLA(ctrl)` is the only
place a cycle figure appears), so its `hdl/gen/cmd/cyclevec` generates a
table the RTL can be checked against from the pins alone.

Each record is a short program plus two PCs. The bench counts clocks from
the IF1 (`ST=1101`) `/AS` fall at the first PC to the next IF1 `/AS` fall,
which must land on the second PC: the only pin-observable definition of an
instruction's length.

The generator measures between two consecutive copies of an instruction,
i.e. in **pipeline steady state**: the Z8000 prefetches (2-stage
look-ahead), so a first execution borrows fetch clocks from its
predecessor. It also checks that the copies SETTLE: an instruction whose
operands drift (a `DIV` leaves its quotient in the dividend) can walk into a
different cost path, and averaging that is meaningless, so the generator
fails instead.

Repeat block instructions (`LDIR`, `CPIR`, `LDDR`) consume their count
register, so their records repeat a self-restoring **group** (reload
destination, source and count, then the block instruction) and time the
interval AFTER the block instruction's own IF1. That interval is a constant
13 whatever the count (the queue fills and stalls); the loop's clocks land
in the next one.

45 records, 34 tagged `exact` and 11 `approx`:

* `exact` -- measured interval == Mar81/`cyclesPLA`.
* `approx` -- they differ; the record carries both. Either way the RTL is
  asserted against the **measured** number. Three causes:
  - branch and stack cases are measured single-shot (repeating them changes
    what they do);
  - bit-serial classes cost a published base plus operand-dependent work
    only the FSM produces -- `MULTL` is `282 + 7n` (n = set bits in the low
    16 of the multiplicand), `LDIR`/`CPIR` are `11 + 9n`; the decode-time
    figure is the intercept;
  - static shifts are published as `13 + 3n` but measure three clocks less
    back-to-back: the successor's second-word fetch hides inside the shift's
    internal burn. They are the only multi-word instructions with a long
    internal phase, so nothing else shows this split. `bench/c900` measures
    whether the overlap is real silicon.

The generator refuses a record whose opcode does not decode to the claimed
mnemonic, so a mistyped encoding fails the build.

## 4. Peripheral timing benches

`tb_cio_timing.sv` (Z8036, z8036_cio.pdf pp.673-698):

* reset state and the reset-bit protocol -- MICR reads 0x01, everything else
  reads 0, only MICR bit 0 is writable (p.684);
* the register datapath with **PCLK held Low** throughout (AC rows 13/14/30,
  p.695 Note 1: the register read/write path has no PCLK term);
* AD driven from the `/DS` fall, floating at the `/DS` rise alone;
* what `/AS` latches (AD, `/CS0`, `/INTACK`) versus what `/DS` samples (CS1,
  R/W) -- R-CIO-401/402, checked both ways round;
* **back-to-back cycles**: the `/DS` rise sharing a sample with the next
  `/AS` fall (Product Spec Fig 19), R-CIO-409;
* the `/AS`+`/DS` hardware reset (p.674 footnote, p.684).

`tb_scc_timing.sv` (Z8030, z8030_scc.pdf pp.631-651): register round-trip
through WR12/WR13 and RR12/RR13, the A//B channel select on AD5 in Shift Left
mode (p.641), the `/AS` address latch surviving AD changing to write data, the
AD float referenced to the `/DS` rise with **no PCLK edge**, a deselected
`/AS` pulse leaving the chip alone, and the `/AS`+`/DS` hardware reset with
its reset table (WR5 -> 0x60 releasing RTS/DTR, RR15 -> 0xF8) plus the 4-5
PCLK internal stretch from UM010903 p.26.

`tb_mmu_timing.sv` (Z8010, z8010_mmu.pdf pp.559-575): the Special I/O command
protocol of Fig 11 -- command latched at the `/AS` rise, executed at the `/DS`
fall, read data driven ONLY while `/DS` is Low (AC #8) and floating at its
rise (AC #9), riding AD15:8 only because the chip has no AD0-7 pins, and
completing even when `/CS` is released before `/DS` (AC #34/#35) -- then
translation (PA = base<<8 + offset, PA floating at the `/DS` rise, AC #6) and
the same back-to-back rule as the CIO.

### Peripheral cycle accuracy

Vector replay already enforces peripheral cycle accuracy: each record is one
fabric clock and every output pin is compared, so a counter one clock early
fails. The spec benches add the datasheet's protocol rules.

The vectors do not pin down rates the Go tests never exercise. Not yet
checked:

* Z8036 C/T: the down-counter is clocked at **half** the PCLK frequency in
  timer mode (p.683). Program a time constant, freeze the count with RCC,
  read Current Count twice N PCLK cycles apart, assert a delta of N/2.
* Z8030 BRG: rate = PCLK / (2 * (time constant + 2)) -- measure TRxC edges
  with WR11 routing the BRG out.
