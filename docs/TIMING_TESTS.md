# Timing and cycle-accuracy benches

Three questions, three kinds of bench:

| question | bench | reference |
|---|---|---|
| does it match the reference vectors, edge for edge? | `tb/<device>/tb_{cpu,mmu,scc,cio,fpu}.cpp` (vector replay) | recorded `vectors/<device>/*.vec` |
| is what it does **legal per the datasheet**? | `tb/<device>/tb_*_timing.sv` + `tb/common/z8000_bus_monitor.sv` | Zilog product specs, cited per check |
| does each instruction take the **documented number of clocks**? | `tb/k800x_cpu/tb_cpu_cycles.sv` | `vectors/k800x_cpu/cycles/cycles.vec`, the cited totals (Mar81 TM 6.7) |

`<device>` is `k800x_cpu`, `k8010_mmu`, `k8030_scc`, `k8036_cio` or `k8070_fpu`; bench
modules keep the short `tb_<chip>_timing` names, like the make targets.
`z8000_bus_monitor.sv` is in `tb/common/` because it checks any Z-Bus DUT.

`make test-timing` runs every spec bench plus the cycle bench; individually:
`make test-cpu-timing`, `make test-cpu-cycles`, `make test-mmu-timing`,
`make test-cpu-mmu-clk`, `make test-cio-timing`, `make test-cio-iack`,
`make test-scc-timing`, `make test-scc-iack`, `make test-fpu-timing`.
`make test` runs them too.

A failing check prints its spec citation (figure or AC row). Results:
`docs/STATUS.md`.

---

## 1. `z8000_bus_monitor.sv` -- continuous Z-Bus protocol checker

Watches the CPU's pins on both CLK edges and flags anything the Z8001/2
Product Spec (1988 Data Book pp.150-160) forbids, on the half clock it first
happens. Instantiate it next to the DUT in any bench.

Each sample sees the pins as the previous CLK edge left them (one vector
record's outputs). Offsets are half clocks from the sample where
`/AS` first went Low (T1's first half = 0); an odd offset is a clock's
second half.

Per-sample rules:

| rule | source |
|---|---|
| `/AS` and `/DS` are never Low together | z8036_cio p.674 / z8030_scc: that combination is the peripherals' hardware-reset condition, never a transaction |
| `/AS` never stays Low across an address or status change | Fig 12: address+status are valid for the whole of T1; the `/AS` rise is the external latch point |
| the address is driven whenever `/AS` is Low | Fig 12 |
| `SN` reads zero when `SEGMENTED=0` | p.150: SN6-SN0 exist only on the Z8001/Z8003 |
| every bus output is floated while `/BUSACK` is Low | Fig 15 |

Per-transaction rules (offsets in half clocks from the `/AS` fall, external
`/WAIT` clocks discounted, two halves each; `/WAIT` counted where the CPU
samples it, on T2's fall, TWA's for I/O, and each Tw's). `/AS` rises at 1
in every class.

| cycle class | `/MREQ` | `/DS` falls | `/DS` rises | other |
|---|---|---|---|---|
| memory read | 1 | 2 | 5 | AD released while `/DS` Low |
| memory write | 1 | 3 | 5 | write data held for the whole `/DS` Low window; a BYTE write duplicates the byte on both halves of AD (Ref Manual 9.4.2 p.234) |
| I/O (0010/0011) | never | 3 | 7 | one automatic wait, Fig 13 |
| acknowledge (0100..0111) | never | 10 | 15 | five automatic waits, `/DS` falls at the fourth so the IEI/IEO chain settles, Fig 14 |
| refresh (0001) | 1 | never | -- | `R/W`, `B/W`, `N/S` unchanged from the preceding transaction (Fig 18 / Ref Manual 9.4.6) |
| internal op (0000) | never | never | -- | `/AS` pulse only, Fig 17 |

The offsets come from the AC table (1988 DB PDF p.47-48: `/AS` rise #26 and
`/MREQ` fall #18 on T1's fall, `/DS(read)` #37 on T2's rise, `/DS(write)`
#39 and `/DS(I/O)` #42 on T2's fall, `/DS(acknowledge)` #45 on a rise, both
strobes rising on T3's fall #23, #34).
These offsets hold for CLK rise and fall pulses in different master clocks,
the only clocking `tb_cpu_timing` runs. With both in one master clock the
fall's moves land on the rise and `/AS` is Low one master clock.

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

Cycle counts are datasheet facts. The generator keeps one cited total per
instruction form and reaches it with the form's machine-cycle program, so
it emits a table the RTL can be checked against from the pins alone.

Each record is a short program plus two PCs. The bench counts clocks from
the IF1 (`ST=1101`) `/AS` fall at the first PC to the next IF1 `/AS` fall,
which must land on the second PC: the only pin-observable definition of an
instruction's length.

Each instruction fetches only its own words, so an instruction's interval
is its whole cost. The generator measures between two consecutive copies
and checks that the copies SETTLE: an instruction whose operands drift (a
`DIV` leaves its quotient in the dividend) can walk into a different cost
path, and averaging that is meaningless, so the generator fails instead.

Repeat block instructions (`LDIR`, `CPIR`, `LDDR`) consume their count
register, so their records repeat a self-restoring **group** (reload
destination, source and count, then the block instruction) and time the
block instruction's own interval.

Each record is tagged:

* `exact` -- measured interval == the form's total.
* `approx` -- the total is a published base plus per-step work only the
  sequencer produces; the record carries both, and the RTL is asserted
  against the **measured** number: shifts `13 + 3n`, `MULTL` `282 + 7n`
  (n = set bits in the absolute value of the multiplicand's low 16 bits as
  a signed word), `LDIR`/`LDDR`/`CPIR` `11 + 9n`. Each measures exactly
  its formula.

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
  R/W) -- checked both ways round;
* **back-to-back cycles**: the `/DS` rise sharing a sample with the next
  `/AS` fall (Product Spec Fig 19);
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

`tb_cpu_mmu_clk.sv`: a Z8001 and a Z8010 on one CLK net, the board address
latch and memory on {A23:A8, A7:A0}; at every CLK rise while /DS is Low in a
memory cycle the physical address must be driven and equal the bench's own
translation. Runs master:CLK 2:1, 3:1, 4:1, 5:1, 7:1, 2,3,2,4 and 1:1.

`tb_cio_iack.sv`, `tb_scc_iack.sv`: two chips on one daisy chain. A chip
with IEI Low keeps /INT High, and a request arriving after an acknowledge's
/AS does not take that acknowledge (UM0109 2.4.5.1).

`tb_fpu_timing.sv` (Z8070, 1985 DB printed pp.531-558): reset and idle
pins, the IF1 and word-2 snoop, transfer drive windows, the store wait,
/BSY at the STOP samples in both overlap modes, the acknowledge (IEO,
vector window, SV, NV, DLC), Interface Processor state recovery and the
lost-word count.

### Peripheral cycle accuracy

Vector replay already enforces peripheral cycle accuracy: each record is one
fabric clock and every output pin is compared, so a counter one clock early
fails. The spec benches add the datasheet's protocol rules.

The vectors do not pin down rates no vector exercises. Not yet checked:

* Z8036 C/T: the down-counter is clocked at **half** the PCLK frequency in
  timer mode (p.683). Program a time constant, freeze the count with RCC,
  read Current Count twice N PCLK cycles apart, assert a delta of N/2.
* Z8030 BRG: rate = PCLK / (2 * (time constant + 2)) -- measure TRxC edges
  with WR11 routing the BRG out.
