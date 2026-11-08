# The ladder -- the execution plan

The order to make the tests pass. Each step gives what to implement, the
command that judges it, and the known traps.

Layout is by DEVICE: `rtl/k800x_cpu` (the CPU, x = the 8001/2/3/4 variant;
generated `gen/` inside), `rtl/k8010_mmu`, `rtl/k8030_scc`, `rtl/k8036_cio`.
`tb/`, `vectors/` and `mk/` mirror them; `tb/common` holds DUT-independent
checkers. Ledgers: `docs/K800X_CPU_TESTS.md`, `K8010_MMU_TESTS.md`,
`K8030_SCC_TESTS.md`, `K8036_CIO_TESTS.md`. Make targets use short names:
`make test-cio`, `make cio ONLY=...`.

Rules:

* **Never hand-edit `rtl/k800x_cpu/gen/*` or `vectors/*`.** They are
  derived from the Go golden model but COMMITTED: `make lint build test`
  reads nothing outside k8000 and needs no Go. Only the maintainer targets
  `make refresh-rtl` / `make refresh-vectors` read the Go model, and they
  fail with an explanation if it is absent. Refresh, review, commit. Review
  decoder changes in `rtl/k800x_cpu/z8000_decode_table.txt` (the same ROM,
  fields named); `make test-decode-table` proves the .sv matches it.
* **Never change the Go model to make RTL pass**, unless the DATASHEET says
  the model is wrong: then fix the model, add the cited regression test
  there, `make refresh-vectors`, and add a row to `docs/<DEVICE>_TESTS.md`.
* **RTL has zero lint suppressions** (`make lint`, `RTL_W`). Only
  testbenches get relaxations.
* Cycle counts EMERGE from the sequencer doing real work each clock. No
  stored totals, no calibration constants.

The loop:

```
make test-<bench>              # or make ladder / ladder-<chip> for the list
make cpu ONLY=TestNOP          # one vector, full divergence context
make cpu ONLY=TestNOP VCD=1    # ... and obj_dir/.../TestNOP.000.vcd
make cio ONLY=TestResetState   # same for mmu / cio / scc
```

Current results: `docs/STATUS.md`.

---

# Part A -- the datapath unit benches (`rtl/k800x_cpu`)

These gate every CPU vector: a sequencer cannot be debugged against a
broken register file. Self-contained (no bus, no sequencer); do them first,
in order.

## A1. `z8000_regfile.sv` -- `make test-regfile`

**Implement.** 16 x 16-bit storage with overlapping views: RH0-RH7/RL0-RL7
bytes, R0-R15 words, RR0..RR14 longs (even pairs), RQ0/RQ4/RQ8/RQ12 quads.
Ports: `we`, `wwidth` (0=byte 1=word 2=long 3=quad), `wsel`, `wdata[63:0]`,
and a combinational read port `rwidth`/`rsel`/`rdata[63:0]`, right-aligned.
Byte select: `wsel[3]` picks the half (Go `registers.File`), so RH0 is
`wsel=0`, RL0 is `wsel=8`.

**Acceptance.** `make test-regfile`: the 8 ported Go tests plus a 4000-case
seeded soak against an independent inline reference model.

**Watch out.** RR0 is R0:R1 with R0 HIGH. A byte write must not disturb the
other half. The read port is combinational: the CPU reads operands in the
clock it decodes.

## A2. `z8000_alu.sv` -- `make test-alu`

**Implement.** One `always_comb`, 16 bits wide, over `op` (`ALUOP_W` bits,
enum in `rtl/k800x_cpu/gen/z8000_ctrl_pkg.sv`), `width` (byte or word),
`a`, `b`, `cin` -> `value`, `flags[15:0]`, `flags_mask[15:0]`. Plain `+`,
not a ripple carry chain. `flags_mask` (which flags the op writes) is
compared EXACTLY: right value, wrong mask fails. Only what the CPU issues:
multi-bit shifts and EXTS live in `z8000_serial` / the EXTS class, rotates
take a count of 1 or 2, bit numbers are 0-15. Long ADD/SUB/CP/TEST/LD are
two word passes; the composition rule is in the module header.

**Acceptance.** `make test-alu` replays `vectors/k800x_cpu/alu/random.vec`
(78000 constrained-random cases, reachable set only) and
`vectors/k800x_cpu/alu_from_cpu/*.vec` (every `alu.Execute` call the CPU
suite made). Long records run as two passes and must match bit-exactly.
Out-of-contract records (shift/EXTS unit tests, synthetic long logic ops)
are skipped and the tally is printed. Clean before rung 3.

**Watch out.** Flags C/Z/S/PV/D/H at bits 7/6/5/4/3/2. PV is overflow for
arithmetic, parity for byte logicals; DAB and the BCD rotates read D and H.
Source of truth: Go `sim/cpu/alu/alu.go` and its `FlagWritesFor` PLA.

## A3. `z8000_serial.sv` -- `make test-serial`

**Implement.** One serial unit (multiply, divide, shifts) on one adder and
rotate, one protocol: `start` pulse, the second operand `delay` ticks later
with `src_valid` (a long's high word first, with `src_hi`), `done` after an EXACT tick
count, `remaining` decrementing every tick (recorded in the serial
vectors, so it is contract).

**Acceptance.** `make test-serial` (`vectors/k800x_cpu/serial/random.vec`).
`+only=M|D|S` selects one operation class.

**Watch out.** The units step on the CPU's machine-cycle cadence: one step
per internal cycle, its work on the cycle's last clock. MULT: setup 3, 16
steps of 4; MULTL: setup 4, 32 steps of 8, one 7-clock add per 1 bit
(n = set bits in the absolute value of the multiplicand's low 16 bits read
as a signed word), finish 19; DIV: setup 2, trial 6, 16 steps of 6; DIVL:
setup 2, trial 67, 32 steps of 21; shifts one 3-clock step per position.
Multiplier 0 replaces the steps with 12 (MULT) / 23 (MULTL); divisor 0
with 8 / 25, overflow with 20 / 46. An operand arriving after setup picks
the path then, the clocks waited counting toward it while the work left
after the arrival fits; each clock past that adds one. Every path needs
1 clock from the arrival. Latest free arrival, in ticks: MULT 6,
multiplier 0 14; MULTL 11, multiplier 0 26; DIV trial 7, divisor 0 9,
overflow 21; DIVL trial 68, divisor 0 26, overflow 47. Overflow is case 3
alone; case 4 takes the trial and the quotient bits. No CPU program
reaches a bound.
With the IF1 these give the table totals: MULT 70, MULTL 282+7n, DIV 107,
DIVL 744, shifts 13+3n static and 15+3n dynamic (ledger items 49, 50).

Division outputs `dbz`, `ovf`, `wide`, `qneg`, `qzero` are each checked.

---

# Part B -- the CPU (`rtl/k800x_cpu`)

`make test-cpu` replays every vector x 4 variants, shortest failures first;
`make ladder` writes the full list to `results/cpu_ladder.txt`. Fix the top
failure, repeat. Rungs are the order the RTL grows in.

## Rung 0 -- reset pin state

AD 3-stated, /AS //DS //MREQ //BUSACK //MO High, SN Low, ST=1111 while
/RESET is Low (Ref Manual 7.4; Product Spec Fig 19). Checked by
`make test-cpu-timing` section [1].

## Rung 1 -- bus unit + the reset PSA reads

**Implement.** The transaction FSM in `z8000_bus_unit.sv`, driven by the
sequencer, per rising edge:

| clock | pins after the edge |
|---|---|
| T1 | /AS Low, address on AD, `ad_drive`=1, ST valid, /MREQ + /DS High |
| T2 | /AS High; /MREQ Low; read: /DS Low and AD released; write: AD holds data, /DS still High |
| T3 | read data captured at this edge; /DS + /MREQ (and write data) STILL asserted |
| next | /DS + /MREQ released -- possibly the same edge as the next T1 (Fig 19) |

Plus the reset sequence: three PSA reads on the Z8001 (FCW, PC segment, PC
offset), two on the Z8002, all `ST=1100` and in SYSTEM mode (`n_s` Low)
before FCW is loaded.

**Acceptance.**
```
make cpu ONLY=TestResetSequenceZ8002     # 26 ticks, the shortest real vector
make cpu ONLY=TestResetPinState          # 22 ticks
make cpu ONLY=TestBusStatusCodes_SpecConformance
make test-cpu-timing                     # section [2] starts producing transactions
```
From here on, `test-cpu-timing`'s monitor is the main debugging tool: it
fires on the clock a strobe first goes wrong, with the Product Spec
citation.

**Watch out.** WRITE /DS falls one clock after a read's (TdC(DSW) is
referenced to the T2 falling edge). /AS and /DS must NEVER be Low in the
same clock: that is the Z8036/Z8030 hardware reset, and the monitor fails
it. The address is stable for all of T1; the /AS rise is the external
latch point.

## Rung 2 -- IF1 fetch, decode hookup, HALT

**Implement.** The fetch FSM issuing IF1 (`ST=1101`) at PC, feeding
`z8000_decode`, and `ClsHalt`. HALT runs ST=0000 internal-operation cycles
with refresh interspersed (Fig 17, Product Spec p.155); the clock keeps
running.

**Acceptance.** `make cpu ONLY=TestNOP` (46 ticks). The 32-tick
`TestCycleAudit*.NNN` files share this HALT baseline, so a block of the
ladder shortens at once.

## Rung 3 -- ClsUnified register and immediate forms

**Implement.** The sequencer walks each instruction's program from the
generated program ROM (`rtl/k800x_cpu/z8000_mc_table.txt`); regfile read
-> ALU -> regfile write on the program's last clocks, for
register/immediate modes.

**Acceptance.** `TestLDImmediate`, `TestLD_R_R`, `TestADD_R_R`,
`TestLDB_IMM8`, `TestLogicalOps_PreserveCarry`, `TestBIT_SET_RES`,
`TestINC_DEC_register`, `TestAddlImm`, `TestLongRegROM.*`, `TestTESTL_R`. First
`make test-cpu-cycles` rows: `ld_r_imm` (7), `ldb_r_imm` (5), `ld_r_r` (3),
`add_r_r` (4), `inc_r`, `dec_r`, `cp_r_imm`.

Held elsewhere: `TestShiftRegister` needs the shifter driven by the
sequencer (the MULT/DIV hookup).

**Watch out.** Every instruction is its machine-cycle program (Go
`sim/cpu` `cycle_program.go`; ledger items 41, 42, 46): the next IF1
starts only after the last cycle, tail included, and nothing is fetched
ahead. Long ops: the ALU is 16 bits, so a long op is two word passes, low
then high for ADD/SUB/CP, placed in the clocks the program names: the low
pass on the second last clock, the high pass on the last. ADDL/SUBL/CPL
RR,RR `F1+2 I3`: the I3's second and third clocks. ADDL #imm
`F1+1 Fn Fn+4`: the low word's fetch's fourth and fifth clocks after its
T3 edge. LDL RR,RR `F1+2`: the two tail clocks. TESTL RR `F1+2 I8`: the
I8's last two. LDL RR,#imm `F1+1 Fn Fn+1` is the tight case: the low word
arrives at its fetch's T3 edge, leaving exactly its T3 clock and the
tail. The low word always arrives last, so no long form can start sooner.
Nothing reads the result before the next instruction's IF1 T3: the
passes do not show on the pins, only the program's length does.

## Rung 4 -- memory operands, stores, RMW

**Implement.** `execReadOp` / `execWriteOp` / long variants for IR, DA, X,
BA, BX, RA; byte lanes (even address -> AD15:8, odd -> AD7:0); a byte
WRITE puts the byte on BOTH halves (Ref Manual 9.4.2 p.234, R-CPU-513; the
monitor checks it).

**Acceptance.** `TestLD_R_IR`, `TestLD_IR_R`, `TestLD_R_ADDR`,
`TestLD_ADDR_R`, `TestLD_ADDR_IMM`, `TestCP_ADDR_IMM`; byte lanes
`TestLDB_ByteStore_EvenAddr`, `TestLDB_ByteStore_OddAddr`,
`TestNEGB_OddAddr`, `TestBusSpec_ByteWriteDuplicatesData`;
`TestADDL_ADDR`, `TestSUBL_ADDR`, `TestCPL_ADDR`, `TestTESTL_ADDR`, `TestLDL_*`,
`TestLongRegROM.*`; addressing modes `TestLD_indexed`, `TestLD_BX`,
`TestLDL_BX`, `TestLDB_R_BASED`, `TestLDR_PCRel_BaseIsUpdatedPC`,
`TestALUDirectAddressROM`, `TestALUIndexedROM`,
`TestZ8001_LD_DA_Imm_LongForm`, `TestZ8001_LDB_DA_Imm_LongForm`;
`TestBusTimingMemory*`, `TestBusSpec_MemoryWriteStrobes`. Cycle rows: `ld_r_ind` (7), `ld_ind_r`
(8), `ldb_r_ind`, `ldb_ind_r`, `ld_r_da` (9), `ld_da_r` (11), `add_r_ind`.

## Rung 5 -- branch, stack, call/return

**Implement.** `ClsBranch` (JP/JR/CALL/CALR/RET/DJNZ) and `ClsStack`
(PUSH/POP, long and addressed forms).

**Acceptance.** `TestJR`, `TestCALR_RET`, `TestPUSH_POP`, `TestNonSeg*`,
`TestDJNZ*`, `TestCycleAuditBranch`, `TestCycleAuditStack`. Cycle rows:
`jr_taken`, `jr_nottaken`, `djnz`, `push_ind_r`, `pop_r_ind`.

**Watch out.** CALR SUBTRACTS its displacement (PC - 2*disp); the 1982+
manuals misprint it as an add.

## Rung 6 -- the small classes

FcwOp (DI/EI/SETFLG/RESFLG/COMFLG), Exts, TCC, DAB, Exchange, BCDRotate,
LEA, LDCTL, LDPS, IRET, Translate, LDM. Acceptance: `TestDI_EI`,
`TestLDCTL`, `TestEX*`, `TestEXTS*`, `TestTCC*`, `TestDAB*`, `TestRLDB*`,
`TestLDM*`, `TestLDPS*`, `TestIRET*`, `TestTR*`.

## Rung 7 -- MULT / DIV hookup

Drive the A3 sequencers from the program's internal cycles. With a memory
or immediate operand the setup and first steps run during the operand
transactions (ledger item 49).

**Acceptance.** `TestMULT*`, `TestDIV*`, `TestMultDivROM`, and
`TestArithmeticSpecGap`, which alone gates mul/div cycles and flags
(`enforceArithSpec`); `cycle_audit_test.go` covers the other classes.

Cycle rows: `mult_r_r_x1` and `mult_r_r_xffff` (70; if they differ, the FSM
has a per-bit term), `multl_rq_rr_n3` (303) and `multl_rq_rr_n5` (317),
which prove the 282+7n slope emerges, `div_r_r_by1` (107),
`divl_rq_rr_by1` (744).

## Rung 8 -- block operations and I/O

**Implement.** `ClsBlockTransfer` / `Compare` / `String` / `IO`, and the
I/O bus cycle: 4 clocks minimum, /MREQ never asserted, /DS Low from TWA
through T3 (Fig 13). A byte I/O write repeats the byte on both halves
of AD; a byte read takes the half the port's A0 picks, as memory.

**Acceptance.** The 41 tests in `cpu_block_test.go` (`TestLDIR*`,
`TestCPIR*`, `TestCPSD*`, `TestINIR*`...), `cpu_io_bytelane_test`,
`cpu_blockio_bytelane_test`, `TestCycleAuditBlockOps`,
`TestCycleAuditBlockCompare`, `TestBusSpec_IOCycleDS`,
`TestMachineCycleBlock`. Cycle rows: `inb` (12), `outb` (12), `ldi_1` (20),
and 11+9n: `ldir_n4` and `lddr_n4` (47), `ldir_n64` (587), `cpir_n3` (38),
`cpir_n8` (83).

Those five are **group records**: a repeat block instruction consumes its
count, so the vector repeats a self-restoring group (reload dst, src,
count, block instruction) and times the block instruction's own interval.
The 11 are 7 before the first element and an `I4` after the last (ledger
item 48).

## Rung 9 -- machine-cycle programs suite-wide

Now every machine cycle's position matters: `TestMachineCycle*`,
`TestFetchRedirect`, `TestNoFetchAhead`, `TestCycleTableMemoryForms` and
all `TestCycleAudit*` groups on Z8001 and Z8002 -- the hard gate. Each instruction fetches only
its own words.

`sla_1` (16) and `sla_8` (37) are 13+3n: one 3-clock internal cycle per
position.

## Rung 10 -- interrupts, traps, refresh, STOP, BUSREQ, VMPU

`cpu_interrupt_test.go` (16 tests), `intack_ds_test` (/DS falls at the
fourth automatic wait, Low 3 clocks), `epu_test`, `stop_test` (fetch FIRST,
then refresh until STOP samples High), `TestRefresh*` (refresh keeps R/W,
B/W, N/S from the previous transaction, never asserts /DS), `TestG78_*`,
`TestBusReq*` + `TestBusSpec_BusRequestTiming` (sampled at a machine-cycle
boundary, /BUSACK High one clock after release, CPU resumes two after),
`TestBusSpec_HaltInternalOpsAndTwoSampleExit`,
`TestBusSpec_AbortedIF1RunsInProgramMode`, `cpu_vmpu_test.go`
(Z8003/Z8004 ABORT/SAT/TSET), `TestSysCall*`, `TestPrivTrap*`.

Green here means `make test-cpu-timing` 12/12 and `make test-cpu-cycles`
45/45.

## Skipped forever (`X unsupported`)

`TestSaveRestore*` restore Go snapshots, and some `TestMachineCycle*`
files set a refresh pending directly; they test the Go model's internals,
not the CPU's pins.

---

# Part C -- Z8010 MMU, `rtl/k8010_mmu` (`make test-mmu`, `make test-mmu-timing`)

Rungs follow the header of `rtl/k8010_mmu/z8010_mmu.sv`.

## M1. Reset final state
Fix the reset values (`mode_reg`, `sar`, `dsc`, `viol_*`, `bcsr`, `isn`,
`ioffset`, the 64 descriptors) against `tb/k8010_mmu/mmu_access.h`.
Acceptance: `make mmu ONLY=TestReset`.

## M2. Strobe capture + translate comparator
Latch `sn`/`ad`/`st`/`r_w`/`n_s` at the /AS fall; drive `pa` and
`pa_drive` from the /AS RISE; float `pa` at the /DS rise (AC #6 TdDS(Af)).
`pa = {base,8'h00} + offset`, one comparator tree.
Acceptance: `make mmu ONLY=TestBasicTranslation`, then `TestChangedFlag`,
`TestPhysicalAddress16BitBase`; `make test-mmu-timing` section [2].

## M3. Command engine (Special I/O)
`executeCommand`'s 22-entry table: command latched at the /AS rise (`cs_n`
sampled THERE only), executed at the first /DS Low sample, read data driven
ONLY while /DS is Low and only on AD15:8 (no AD0-7 pins). 0x0D = Limit,
0x0E = Attribute (UM010401 Table 3-6); easy to swap.
Acceptance: `make test-mmu-timing` section [1] (five checks), then
`TestCmd_*`.

## M4. Violation / trap FSM
`segt_n` while `trap_pending`; `sup_n` per cycle plus the
until-end-of-instruction hold; SEGT acknowledge (at the /AS-rise sample of
a latched `ST=0100` cycle drive AD line 8+ID with `ack_pending`, clear at
the /DS rise); ignore dummy fetches while a trap is pending. Acceptance:
`TestOutOfBounds`, `TestSROProtection`, `TestCPUInhibit`,
`TestSEGTInvariant_TrapPendingMirror`.

## M5. DMASYNC path and the back-to-back rule
Two or more Low samples then a rising edge -> DMA translate, suppress-only,
no SEGT, no violation capture. **Apply the /DS-rise teardown BEFORE the
/AS-fall latch** when both land in one sample (Fig 19). Acceptance:
`TestDMASYNC_*`, `make test-mmu-timing` section [3].

---

# Part D -- Z8036 CIO, `rtl/k8036_cio` (`make test-cio`, `make test-cio-timing`)

## C1. Strobe capture, cycle ownership, reset
* Latch `ad_in`, `cs0_n`, `intack_n` while /AS is Low (R-CIO-401).
* `cs1` and `r_w` are LEVELS at the /DS fall, not /AS-latched (R-CIO-402).
* /AS + /DS Low together = hardware reset: registers 0, MICR bit 0 set,
  ports and catchers cleared.
* **Teardown before latch** (R-CIO-409): in the same `always_ff`, the
  /DS-rise clear of `ad_drive`/cycle ownership runs BEFORE the /AS-fall
  latch. Backwards, every back-to-back write is dropped and the chip stays
  in power-on reset.

Acceptance: `make test-cio-timing` sections [1], [3], [4], [5] (8 of 11
checks), `make cio ONLY=TestResetState`.

## C2. Register file + reset gating
`regs[0:47]`; reads return 0 in reset except MICR=0x01; only MICR bit 0
writable in reset; RJA address decode. Read data on `ad_out`/`ad_drive`
from the /DS-Low level with NO PCLK enable in the path (AC rows 13/14;
p.695 Note 1 -- the timing bench holds PCLK Low to prove it), floating at
the /DS rise alone.
Acceptance: `TestAddressDecoding`, `TestRegisterReadWrite*`,
`TestStrobeServiceWriteNoPCLK`, timing section [2].

## C3. Ports A/B/C
Mode/direction/polarity, OE masks, input sampling, 1's catchers,
`effectiveInput`. Acceptance: `TestPortCData`, `TestPortData`,
`TestSetPortBInputLatch`, `TestPortDirection*`.

## C4. Counter/timers
PCLK/2 prescaler toggling on PCLK FALLING edges (R-CIO-403), TC -> reload
gap, TC=0 = 65536, compute-then-commit in `advance()`, gate/trigger in the
PCLK domain, counter-mode count input sampled asynchronously on every
`clk` (R-CIO-404). Acceptance: `TestCounter*`, `TestTimer*`, `TestCT3*`.

## C5. Pattern match, handshake, interrupts
LPM latch and deferred ERR; handshake unit and REQUEST/WAIT on Port C;
priority encoder, `int_n` level, `ieo = !DLC && iei && !anyIUS &&
!pendingDuringIntack`, INTACK vector driven at the /DS fall, NV=1
inhibiting it (R-CIO-407). Acceptance: `TestPatternMatch*`,
`TestHandshake*`, `TestIntACK*`, `TestG80_13_IEOIntackAndDLC`.

**The /AS domain (R-CIO-405).** Port sampling, pattern match, handshake
and IP->INT are clocked by **/AS**, not PCLK, in silicon and model. Build
C1/C3/C5 that way: `as_rise = ~as_q & as_n` clocks the input register, the
catchers, the pattern comparison (both synchroniser stages) and the /INT
request latch; `int_n` is that latch inverted. PCLK (falling-edge enable)
keeps only the timer-mode counters, deskew counters and REQUEST/WAIT.
Check: `make test-cio-timing` section [6] -- with /AS stopped the pattern
never matches, and two /AS cycles set IP and pull /INT Low.

---

# Part E -- Z8030 SCC, `rtl/k8030_scc` (`make test-scc`, `make test-scc-timing`)

The interrupt latch and IEO come before anything serial: the shortest
vectors check them within 3 ticks.

## S1. Strobe capture + the /AS-clocked interrupt latch
AD/CS0/INTACK latch transparent while Low, frozen at the /AS RISE;
`int_latch <= int_pending` at every /AS rise AND at the INTACK /DS fall
(UM010903 p.21, TdAS(INT)); `int_n = ~int_latch`; `ieo = ~DLC & iei &
(ius==0) & ~(as_intack & int_latch)` with the /AS-LATCHED intack.
Acceptance: `make scc ONLY=TestW2_19_NVFloatsADDuringINTACK`,
`TestG81_12_IEOIntackAndDLC`, `TestTickPinsINTOnRxAvailable`.

## S2. Address decode + register core
AD4:AD1 = register, A//B on AD5 (Shift Left) or AD0 (Shift Right); read
mux (RR0/1/2/3/8/10/12/13/15) and write core; WR2/WR9 shared between
channels; WR9 D7:D6 reset commands; hardware-reset table (WR5 -> 0x60,
WR3 -> 0xC0, WR11 -> 0x08, WR15 -> 0xF8, WR4 -> 0x04, WR2 unaffected).
Acceptance: `make test-scc-timing` sections [1], [2], [4], [5], then the
`TestPins_*` register vectors.

## S3. INTACK
Vector on AD at the /DS fall if IEI is High (never at the /INTACK fall);
IUS latch; RR2 vector modification; `ad_drive` never asserted in an
INTACK when WR9 NV=1 (`TestW2_19_*`). AD floats at the /DS rise ALONE; an
INTACK_n term there causes a bus fight.
Acceptance: timing section [3], `TestINTACK*`.

## S4. Channels
`rtl/k8030_scc/z8030_scc_channel.sv` x2: BRG; transmitter (TBR->TSR handoff
on PCLK, start bit timed off the transmit clock, not the WR8 write);
receiver; DCD/CTS sampling (ONE PCLK sample, see docs/K8030_SCC_TESTS.md
item 1); ext/status latches; deferred WR0 commands.
Acceptance: the bulk of the vector ladder, `TestPins_TX_BackToBack`,
`TestPins_RX*`, `TestPins_HardwareResetViaASDS`.

---

# Part F -- the spec benches along the way

`make test-timing` runs them all. While building Part B:

* **`make test-cpu-timing`** needs no vectors or golden model. From rung 1
  it finds a misplaced strobe fastest: clock, transaction, Product Spec
  figure.
* **`make test-cpu-cycles`** goes green in blocks (per-rung "Cycle rows").
  `approx` records carry the measured number and the base total; the RTL
  is judged against the measured one (shifts, MULTL and block repeats,
  whose total is a base plus per-step clocks).

Details and citations: `docs/TIMING_TESTS.md`.

---

# Part G -- done

A device is finished when these are clean, in order:

1. `make lint` -- zero warnings, zero RTL suppressions.
2. `make test-<chip>` -- every vector, every applicable variant.
3. `make test-<chip>-timing` -- every datasheet rule.
4. CPU only: `make test-cpu-cycles` 45/45, `make test-cpu` green on
   Z8001/Z8002/Z8003/Z8004.

Then record what the build taught you in `docs/<DEVICE>_TESTS.md`, and
update `docs/STATUS.md`.

---

# Part H -- Z8070 FPU, `rtl/k8070_fpu` (`make test-fpu`, `make test-fpu-timing`, `make test-fpu-dp`)

The datasheet where it speaks; every other choice is in the "Assumed"
section of `docs/K8070_FPU_TESTS.md`. Rungs follow the RTL headers.

## F0. Go baseline
`make vectors-fpu` records `vectors/k8070_fpu/fpu` and `dp`;
`fpuvecverify` replays them into a fresh Go FPU. Pass: Go tests green,
fpuvecverify 100% (one `X unsupported` snapshot vector).

## F1. Reset and idle pins
SC, USER, FFLAGS cleared but SC.ID from the ID pins; AD floated, /BSY and
/INT High, IEO = IEI. Pass: `make fpu ONLY=TestResetLatchesID`; timing [1].

## F2. Strobe capture, snoop, ID match, word 2, decode table
Pass: `make test-fpu-enc` (RTL decode = Go decode, every input);
`TestIDMatchTwoFPUs.000`, `TestInvalidOpcodeInterrupt`,
`TestInvalidEPUIDInterrupt`; timing [2] (1101 capture at /DS, next
non-refresh 1100, /BUSACK ignore); the F0-F7 file with pokes and checked
finals.

## F3. Transfers and IP-only ops
Pass: `TestFLDCTLSystemModeWrite`, `TestFLDCTLPrivilegeViolation`,
`TestFLDCTLUser`, `TestFLDCTLBGroups`, `TestListOps`; timing [3] (memory
write AD from the /AS rise to the /DS rise, 1110 read AD while /DS is Low,
the flag byte on AD7-0, no drive or count under /BUSACK, the /BSY store
wait until the Data Processor's done). Every load, store
and compare runs through the Data Processor (load rounding, store format,
the compare itself), so those vectors pass at F7; at F3 their pins match
up to where the Data Processor would finish.

## F4. Data Processor: shared routines, add/sub, sign ops, compare
The microprogram (`z8070_dp_ucode.txt`, generated ROM) over one 68-bit
adder, one exponent adder, one shifter and one leading-zero counter: the
shared unpack (classify, renormalize), special select, align, add,
normalize, round (four modes, the operation's precision), range, pack and
hand-over; FADD, FSUB, FRVSUB, FLD rounding, FCP/FCPX/FCPZ/FCPZX, FABS,
FNEG, FCLR. `done` in the last clock's CLK.D master clock. Interface
Processor: unused state codes return to idle, the lost-word count
saturates. Pass: `make test-fpu-dp ONLY=add,load,cmp,sign` (results,
flags, reason, R bit, compare code, clocks: 18, 7, 14; 11; 4); timing:
state recovery and the saturated count.

## F5. Data Processor: multiply, divide, remainder, sqrt
Radix-4 multiply on the one adder (S accumulates, B takes the product's
low word, a 3M register), radix-4 SRT divide on an exact remainder (a
two-threshold digit table per divisor column, the quotient and the
quotient less one ulp by on-the-fly conversion), the remainder on the
same step (partial batches; FD, FZ, FS, FH), and a non-restoring square root,
one root bit a clock; all finish through the shared normalize, round,
range and pack.
FMUL, FPWR2, FDIV, FRDIV, FREM, FREMSTEP, FSQR. Pass: `make test-fpu-dp
ONLY=mul,div,rem,sqrt` (clocks: 28/42/48, 29/43/49, 17 + floor(n/2) for
n quotient bits, 37/66/77; 7 and 5 on special operands).

## F6. Data Processor: conversions, FINT, BCD
FINT and float to integer shift to the integer point and round there;
integer to float is one adder pass then the shared tail; BCD load is one
x10 shift-add per digit on the adder; BCD store divides by 10^19 on the SRT
step, then one x10 per digit. Pass: `make test-fpu-dp` all (clocks: 11,
7, 8, 27, 63; 5 on special operands).

## F7. The Data Processor behind the Interface Processor
Pass: `TestInternalFADD`, `TestIDMatchTwoFPUs.001` (FADD on the matched
FPU), `TestBUSACKForeignMasterInvisible` (the store's rounding), the loads
and stores (`TestLoadSingleFromMemory`, `TestStoreSingleToMemory`,
`TestCPUTransferExtended`, `TestStoreDriveWindow`, `TestLostStoreWord`,
`TestBSYStoreWaitIntermediate`), `TestCompareFlagsToFCW`,
`TestFCPZNFFromMemory`, `TestFOPReadback` and the pin-level arithmetic
vectors (`TestPinInternalOps`, `TestPinLoadsStores`, `TestPinConversions`,
`TestPinFlagForms`, `TestPinStoreFlags`: every operation from the pins, both CLK.D phases at
word 2, subnormal and NaN formats, integers and BCD, FOP1/FOP2, traps,
DE on a subnormal bus operand).

## F8. /BSY, overlap queue, abort, flush
Pass: `TestBSYDuringExecution`, `TestAbort*`, overlap vectors; timing [4]
(/BSY valid at the STOP sample falls before IF1 and word 2).

## F9. Interrupts and daisy chain
Pass: interrupt vectors; timing [5] (IEO rule, vector drive window, NV
float).

## F10. CPU + FPU system bench
`make test-cpu-fpu`: the Go system FPU tests with both RTL chips on one
master clock. Pass: all, Z8001 first.

## F11. Fit
Quartus 18.1, 5CSEBA6U23I7, 48 MHz, plain logic + MLAB, zero lint
suppressions. Pass: positive slack, at most 2,700 ALMs; a four-instance
fit for the quad-CPU budget.
