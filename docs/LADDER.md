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

**Implement.** One `always_comb` over `op` (`ALUOP_W` bits, enum in
`rtl/k800x_cpu/gen/z8000_ctrl_pkg.sv`), `width` (0=byte 1=word 2=long),
`a`, `b`, `cin` -> `value`, `flags[15:0]`, `flags_mask[15:0]`. Plain `+`,
not a ripple carry chain. `flags_mask` (which flags the op writes) is
compared EXACTLY: right value, wrong mask fails.

**Acceptance.** `make test-alu` replays `vectors/k800x_cpu/alu/random.vec`
(123000 constrained-random cases) and `vectors/k800x_cpu/alu_from_cpu/*.vec`
(every `alu.Execute` call the CPU suite made, 195 files). Both clean before
rung 3.

**Watch out.** Flags C/Z/S/PV/D/H at bits 7/6/5/4/3/2. PV is overflow for
arithmetic, parity for byte logicals; DAB and the BCD rotates read D and H.
Source of truth: Go `sim/cpu/alu/alu.go` and its `FlagWritesFor` PLA.

## A3. `z8000_mult.sv` / `z8000_div.sv` / `z8000_shift.sv` -- `make test-serial`

**Implement.** Three bit-serial FSMs, one protocol: `start` pulse, second
operand `delay` ticks later with `src_valid`, `done` after an EXACT tick
count, `remaining` decrementing every tick (the CPU's internal-op bus
dressing reads it, so it is contract).

**Acceptance.** `make test-serial` (`vectors/k800x_cpu/serial/random.vec`,
2800 operations). `+only=M|D|S` selects one unit.

**Watch out.** These tick totals become the MULT/DIV/shift cycle counts,
so they must emerge here for rung 7 and the mul/div rows of
`make test-cpu-cycles`. Build to the ISOLATED figures: MULT 70 flat, MULTL
282+7n (n = set bits in the low 16 of the multiplicand), DIV 107 word / 744
long, shifts 13+3n static and 15+3n dynamic, block repeats 11+9n.

The trap: `sla_8` wants 34 clocks, not the isolated 37. Static shifts are
the only multi-word instructions with a long internal phase, so only they
run back-to-back faster than isolated: the successor's second-word fetch
hides inside the shift. Those 3 clocks come from the prefetch queue at
**rung 9**, not this FSM. Don't tune the sequencer to close the gap: it
makes one measurement agree and breaks twelve enforced cycle-audit cases.

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

**Implement.** `execStart` -> regfile read -> ALU -> regfile write ->
pipe-fill, for register/immediate modes.

**Acceptance.** `TestLDImmediate`, `TestLD_R_R`, `TestADD_R_R`,
`TestLDB_IMM8`, the sweeps `TestArith*` / `TestLogic*`,
`TestConditionCodes`, `TestBIT_SET_RES`, `TestShiftRegister` (needs A3),
`TestBusTimingRegOnly*`. First `make test-cpu-cycles` rows: `ld_r_imm` (7),
`ldb_r_imm` (5), `ld_r_r` (3), `add_r_r` (4), `inc_r`, `dec_r`, `cp_r_imm`.

## Rung 4 -- memory operands, stores, RMW

**Implement.** `execReadOp` / `execWriteOp` / long variants for IR, DA, X,
BA, BX, RA; byte lanes (even address -> AD15:8, odd -> AD7:0); a byte
WRITE puts the byte on BOTH halves (Ref Manual 9.4.2 p.234, R-CPU-513; the
monitor checks it).

**Acceptance.** `TestLD_R_IR`, `TestLD_IR_R`, `TestLD_R_ADDR`,
`TestLD_ADDR_R`, `TestLD_ADDR_IMM`, `TestCP_ADDR_IMM`, `TestByteLane*`,
`TestLongOps*`, `TestEA*`, `TestBusTimingMemory*`,
`TestBusSpec_MemoryWriteStrobes`. Cycle rows: `ld_r_ind` (7), `ld_ind_r`
(8), `ldb_r_ind`, `ldb_ind_r`, `ld_r_da` (9), `ld_da_r` (11), `add_r_ind`.

## Rung 5 -- branch, stack, call/return

**Implement.** `ClsBranch` (JP/JR/CALL/CALR/RET/DJNZ) and `ClsStack`
(PUSH/POP, long and addressed forms).

**Acceptance.** `TestJR`, `TestCALR_RET`, `TestPUSH_POP`, `TestNonSeg*`,
`TestDJNZ*`, `TestCycleAuditBranch`, `TestCycleAuditStack`. Cycle rows:
`jr_taken`, `jr_nottaken`, `djnz`, `push_ind_r`, `pop_r_ind` (tagged
`approx`: measured single-shot, see docs/TIMING_TESTS.md).

**Watch out.** CALR SUBTRACTS its displacement (PC - 2*disp); the 1982+
manuals misprint it as an add.

## Rung 6 -- the small classes

FcwOp (DI/EI/SETFLG/RESFLG/COMFLG), Exts, TCC, DAB, Exchange, BCDRotate,
LEA, LDCTL, LDPS, IRET, Translate, LDM. Acceptance: `TestDI_EI`,
`TestLDCTL`, `TestEX*`, `TestEXTS*`, `TestTCC*`, `TestDAB*`, `TestRLDB*`,
`TestLDM*`, `TestLDPS*`, `TestIRET*`, `TestTR*`.

## Rung 7 -- MULT / DIV hookup

Drive the A3 sequencers with the memory-operand overlap
(`AluFetchOverlap`); the internal-op bus dressing reads `remaining`.

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
through T3 (Fig 13). Special I/O (`ST=0011`) byte data rides AD15:8;
standard I/O uses AD7:0.

**Acceptance.** The 41 tests in `cpu_block_test.go` (`TestLDIR*`,
`TestCPIR*`, `TestCPSD*`, `TestINIR*`...), `cpu_io_bytelane_test`,
`cpu_blockio_bytelane_test`, `TestCycleAuditBlockOps`,
`TestCycleAuditBlockCompare`, `TestBusSpec_IOCycleDS`. Cycle rows: `inb`
(10), `outb` (12), `ldi_1` (20), and the 11+9n slope: `ldir_n4` and
`lddr_n4` (38), `ldir_n64` (578), `cpir_n3` (32), `cpir_n8` (77).

Those five are **group records**: a repeat block instruction consumes its
count, so the vector repeats a self-restoring group (reload dst, src,
count, block instruction) and times the interval AFTER the block
instruction's own IF1. That own interval is a constant 13 (the queue fills
and stalls); the loop's clocks land in the next one. Read the record's
hint line before concluding the RTL is a block's worth of clocks off.

## Rung 9 -- prefetch queue and EA cadence

Now the exact clock positions of overlapped IF1s matter suite-wide:
`prefetch_test.go`, `TestFetchAlign*`, `TestLookAhead*`, and all 12
`TestCycleAudit*` groups on Z8001 and Z8002 -- the hard gate.

**`make test-cpu-cycles` becomes meaningful in bulk here**: it measures
IF1-to-IF1 in pipeline steady state, which needs a working look-ahead
queue.

`sla_1` (13) and `sla_8` (34) belong to this rung: 3 clocks BELOW the
isolated 13+3n because the successor's second-word fetch hides inside the
shift. With a correct A3 shifter they fail until the queue exists, then
pass untouched. If they pass at A3, the sequencer bills 3 clocks too few.

Hardware check: `bench/c900`'s `sla1`/`sla8` kernels read 143/353 clocks
per iteration if the overlap is real, 170/380 if not. 170/380 would mean
this rung's queue model is wrong, and these two rows -- not the shifter --
show it.

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

## Skipped forever (92 files)

`TestSaveRestore*` and `TestPrefetchSnapshotRoundTrip*` restore Go
snapshots (`X unsupported`); they test the Go snapshot mechanism, not the
CPU.

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
Acceptance: `make mmu ONLY=TestBasicTranslation`, then `TestReadWrite*`,
`TestSegmentBoundaries`; `make test-mmu-timing` section [2].

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
  `approx` records carry the measured and the Mar81/PLA number; the RTL is
  judged against the measured one (single-shot branch/stack cases, and
  shifts whose total is base plus per-step clocks).

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
