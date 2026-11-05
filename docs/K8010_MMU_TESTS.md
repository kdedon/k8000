# k8010_mmu (Z8010 MMU) -- vectors, harness, and the ladder

Golden model: Go `sim/mmu` (mmu.go Inputs/Outputs + Tick,
mmu_test.go, snapshot.go). RTL: `rtl/k8010_mmu/z8010_mmu.sv`. Harness: `tb/k8010_mmu/tb_mmu.cpp` +
`tb/k8010_mmu/mmu_access.h`. Fragment: `mk/k8010_mmu.mk`. Vectors: `vectors/k8010_mmu/*.vec`
(GENERATED -- `make vectors-mmu`).

```
make vectors-mmu   # record 71 vectors from 48 of the 49 Go tests, then Go self-check (mmuvecverify)
make lint-mmu      # verilator -Wall on rtl/k8010_mmu/z8010_mmu.sv (zero suppressions)
make build-mmu     # obj_dir/tb_mmu/tb_mmu
make test-mmu      # replay everything, ladder summary (shortest failing first)
make mmu ONLY=TestBasicTranslation [VCD=1] [CONTEXT=20]   # one vector, divergence table
make ladder-mmu    # every vector shortest-first with PASS/FAIL/SKIP
```

The top-level `refresh-vectors`, `lint`, `build` and `test` include these
via `CHIP_VECTORS/CHIP_LINT/CHIP_BUILD/CHIP_TEST`.

## Vector format (`K8000VEC 1 mmu`)

Producer: Go `sim/mmu/vecdump_test.go` (env `K8000_VEC_DIR`; hooks
`TracePreHook`/`TraceHook` on `Z8010.Tick`, inert otherwise). Self-check:
Go `hdl/gen/cmd/mmuvecverify` replays every file into a fresh `mmu.New()`.
One file per MMU instance per test: `<TestName>.<NNN>.vec` (subtests share
the parent's name; multi-MMU tests give `.000`, `.001`).

```
K8000VEC 1 mmu
test TestBasicTranslation 0
P DESC 05 0100 FF 80             poke: test wrote Desc[5] = {Base, Limit, Attr}
P MODE C8                        poke: ModeReg
T 72 0000 00 0 6 000000 0000     one Tick(Inputs) -> Outputs call
...
F MODE C8 / F SAR / F DSC / F VTR / F VSN / F VOFF / F VOVF / F ISN / F IOFF / F BCSR / F TRAP
F DESC 00 0000 00 00 (x64)       final descriptor store
F TICKS 6                        informational
END
```

`X unsupported <reason>` before the first `T` => SKIP. No file has one.

### `T` record

`T <in_bits:2hex> <AD:4hex> <SN:2hex> <ST:1hex> <out_bits:1hex> <PA:6hex> <Data:4hex> <DataMask:2hex>`

`in_bits` (bit 7 = MSB): `CLK RESET_n AS_n DS_n RW NS CS_n DMASYNC`
`out_bits` (bit 3 = MSB): `PADrive SEGT_n SUP_n DataDrive`
`DataMask`: which of AD15:8 are driven (bit n = AD line 8+n).

Exactly the Go pin seam (mmu.go Inputs/Outputs): every Tick call verbatim
(`clkStep` calls Tick twice per clock, CLK=0 then CLK=1).

### `P` records (applied through `tb/k8010_mmu/mmu_access.h` before the next `T`)

| poke                          | Go origin                                    | files |
|-------------------------------|----------------------------------------------|-------|
| `P MODE <2hex>`               | `m.ModeReg = ...`                            | 55    |
| `P SAR <2hex>`                | `m.SAR = ...`                                | 3     |
| `P DSC <1hex>`                | `m.DSC = ...`                                | 1     |
| `P VTR <2hex>`                | `m.ViolType = ...` (TestCmd_ResetSWWandFATL, TestCmd_UnlistedOpcodeWriteIsNoOp) | 2 |
| `P DESC <idx> <base> <limit> <attr>` | `m.Desc[i] = Descriptor{...}`, `Attr &^= ...` | 57 |
| `P ACK`                       | `m.AcknowledgeTrap()` (Go-only helper)       | 3     |
| `P LATCHED_ST <1hex>`         | `m.latchedST = ...` (accepted, unused)       | 0     |
| `P ADDR_LATCHED <0/1>`        | `m.addrLatched = ...` (same)                 | 0     |

The recorder diffs the `Snapshot` before each Tick against the state after
the previous one; a difference no poke can express becomes `X unsupported
poke of internal state (<fields>)`.

## Comparison rules (tb_mmu.cpp)

* **One record == one CLK level, then 1+ master clocks.** The RTL runs on
  the board master clock `clk`; `clk_in` is the CLK rising-edge pulse, High
  for the first master clock of a record whose CLK level rose (`--mclk P` /
  K8000_MCLK sets the master clocks per record; the ladder passes at 1, 2,3,
  4, 7 and 1,2,1,3). Each Go Tick is one sample of the pins: Go and the
  RTL both act on an /AS or /DS edge in the record that shows it, and on CLK
  rises for SN, DMASYNC and the trap-acknowledge /SEGT release (ledger row
  11). Every compared pin must equal the record's Go value exactly; there
  is no tolerance window (the `early=`/`late=` windows and `--strict` were
  removed 2026-11-02 when the Go model was fixed to the datasheet edges).
* **Pins are the Z8010's: AD15..AD8 in (`ad[7:0]`), A23..A8 out
  (`pa[15:0]`), AD15..AD8 out (`data[7:0]`).** The tb drives AD[15:8] of the
  record and compares PA[23:8], Data[15:8] and the high byte of VOFF.
* **/RESET is a level** in both Go (every Tick) and the RTL (every master
  clock); CS_n is taken with it, so the last value before the /RESET rise
  sets MSEN (AC #37/#38 p.573).
* **Compared always**: PADrive, SEGT_n, SUP_n, DataDrive, DataMask.
* **PA only while PADrive=1, Data only while DataDrive=1.** Go's `m.out`
  persists after PADrive drops; the undriven value is not a pin.
* **SEGT_n / SUP_n**: the resolved open-drain level with the board pull-up
  (0 = driven low, 1 = released), i.e. the Go bool. The RTL keeps out+oe
  pairs inside and presents the resolved level.
* **Final state** (`F` records) via `mmu_access.h`: ModeReg, SAR, DSC, VTR,
  VSN, VOFF, ViolOverflow, ISN, IOffset, BCSR, trap_pending, all 64
  descriptors. Renaming a register means updating `mmu_access.h` in the
  same change.
* No sim-only state to exclude (slog in triggerTrap is not state).
  `AcknowledgeTrap()` is a Go helper, not silicon: replayed as `P ACK`
  (clears trap_pending / ack_pending / viol_captured / addr_latched /
  viol_type / viol_overflow; SEGT released).
* Start state == `mmu.New()`: no reset, strobes high, CLK=0, prevCLK=false
  (the first CLK=1 record is a rising edge, as in Go).

## Coverage: 48 of the 49 Go tests -> 71 vectors, all vectorizable

Every test in mmu_test.go and mmu_spec_test.go drives the chip through
`Tick` (`clkStep`, `mmTick`, `sioWrite`, `sioRead`) and pokes only exported
registers, so all 48 (11 subtest groups, three dual-MMU tests) record.
Three use `AcknowledgeTrap()`, replayed as `P ACK`: TestStackSegmentBounds,
TestTrapAcknowledge, TestMSTISNFrozenAtViolation. TestSegTrapAcknowledgeID
drives a real acknowledge cycle; no file pokes internal latches.

mmu_spec_test.go (each test cites its datasheet page) covers: the READ side
of the command protocol (0x00/0x01/0x20, 0x02-0x07, 0x08-0x0F read-back
with DSC/SAR sequencing), 0x11/0x13/0x14/0x15/0x16, unlisted-opcode writes
as no-ops, CS released before DS on a write, commands with MSEN=0 (setting
MSEN after a CS-High reset), MSEN=1/TRNS=0 pass-through after a CS-Low
reset with URS gating and PA float at DS rise, DMASYNC with URS/MST+NMS
gating, SEGT-ack when the trap is not ours (drives 0) and when MSEN=0
(drives nothing), and the SEGT_n == !trapPending invariant through assert /
second violation (FATL) / acknowledge / reset.

Not covered (new Go tests record automatically): all 256 command codes x
read/write x random descriptor store (unlisted-opcode reads are OPEN, see
ledger); true open-drain wire-OR of two chips (the tb drives one chip; the
.000/.001 files replay each chip separately); simultaneous multi-flag
violations (OPEN, see ledger).

## Spec conformance ledger

Sources: z8010_mmu.pdf = Zilog Z8010 MMU Product Specification 00-2046-03
(pp.559-575; identical text and AC table in the October 1988 Z8000 Family
Data Book pp.163-177). Numbers below are z8010_mmu.pdf pages / AC-table
items. The target is the hardware: the Go model is FIXED where the spec is
unambiguous, and the vectors regenerated.

| # | item | source | verdict | change |
|---|------|--------|---------|--------|
| 1 | SEGT release point in the acknowledge cycle | p.565 "The Segment Trap line is reset during the segment trap acknowledge cycle"; p.570 "Segment Trap remains Low until a Trap Acknowledge signal is received"; Fig.12 p.570 (zoomed): CLK, /AS pulse in T1, /SEGT rises from the CLK edge that opens the second automatic wait state (TWA2), /DS falls in the fourth; AC #31 TdC(SEGT) CLK rise to /SEGT rise, 300/200/100 ns; composite p.572 draws #31 from a CLK rise after the /DS rise; Z8001 CPU (Jan83 TM 9.4.6, Fawcett ch.6, 1988 book p.151): VI/NVI/SEGT are levels sampled at the start of T3 of the last machine cycle of an instruction (HALT: every T3, two consecutive samples), 5 automatic wait states, /DS falls in the 4th, identifier taken as /DS rises | Go WRONG (released with the identifier) | **INFERRED 2026-11-02**: released at the THIRD CLK rise counted from the acknowledge's /AS rise (the T2 rise is the first, a rise in the /AS-rise sample counts; = the TWA2 rise; Go `ackReleaseRise`, RTL `ACK_RELEASE_RISE`). Whether the trap was ours is captured at the /AS rise (`ackPending`) for the identifier; a /DS rise before the third rise releases it there. Evidence for TWA2: only Fig.12 shows the acknowledge cycle's own clocks, and the drawn rise starts at that edge; #31 is CLK-referenced; #36 (/AS rises >= 10 ns before the T2 rise) means the chip cannot act on the T2 rise itself, so T2 samples /AS, TWA1 decodes ST=0100, TWA2 clocks the release. Loses: first rise (T2; the #36 margin is 10 ns, and Fig.12 shows /SEGT still Low there); second rise (TWA1; Fig.12 shows Low); the first rise after /DS rises (T4; p.572 composite, which is a generic cycle: it draws the memory-cycle /DS rise to CLK rise #41 and the ack identifier on one template; it would also leave /SEGT Low through the ack's own T3 sample, which the HALT rule samples). No CPU constraint decides it: the CPU never re-samples inside the acknowledge (next sample is the end of the first handler instruction; TsSGT(C) 70/55/40 ns is met by any edge up to TWA2 + #31). Z-BUS peers do not help: Z8030 /INT (#36 TdDSA(INT) 500/450 ns) and Z8036 /INT (840-1280 ns) release from the /DS fall, not a CLK edge; only the Fawcett text (ch.6) says a peripheral "releases the interrupt request line" on seeing the acknowledge status at /AS. CONFIRM WITH: a scope on a real Z8010 + Z8001, /SEGT and CLK in a trap acknowledge, count the CLK rise from /AS rise to /SEGT rise (expect the TWA2 rise, +TdC(SEGT)); also vary the wait states to see that it is a fixed count and not tied to /DS. Tests: Go `TestSegTrapAcknowledgeID` (third rise), `TestSegTrapAcknowledge_ShortCycle`, tb_mmu_timing [6]. |
| 2 | SEGT_n == !trapPending invariant | p.565/568/570 (asserted in T2 of the violating cycle, held until acknowledge; not driven after reset; 0x11 "returns the MMU to its initial state") | Go RIGHT everywhere incl. FATL/SWW inhibit, second violation, ack, reset, 0x11 | CONFIRMED (TestSEGTInvariant_TrapPendingMirror). SEGT asserts at the AS-rise sample of the violating cycle; Fig.9/10 draw it half a clock after SUP within T2 (TdAS(SEGT) 100 ns / TdC(SEGT) 200 ns, AC #30/#31), the same posedge. |
| 3 | Ack identifier drive window | AC #6/#7 p.573 TdDSA(RDv)/TdDSA(RDf): driven from DS fall, floats at DS rise; Fig.12 | Go WRONG on release (held until the next AS fall) | FIXED: DataDrive drops at the DS-rise sample. Every ENABLED MMU drives (1 = trapped, 0 = not); MSEN=0 drives nothing (p.565 "all enabled MMUs"). |
| 4 | Command read data window | p.566 "placed on AD8-AD15 while Data Strobe is Low"; AC #8/#9 TdDSR(RDv)/TdDSR(RDf); Fig.11 p.569 | Go WRONG (drove data from the AS-rise sample and held it to the next AS fall) | FIXED: the command executes once at the first DS-low sample after its AS rise; DataDrive only while DS is sampled low. TdC(RDv) (AC #40) lets silicon settle up to ~3 clocks after cycle start; valid data from the first DS-low sample is indistinguishable to the CPU (samples at T3). The vectors compare Data on every DS-low record, so compute the byte at AS rise like Go. |
| 5 | CS sampling for commands | AC #34/#35 p.573 (TsCS(AS) setup to AS rise, ThAS(CSn) hold from AS rise); Fig.11 shows CS High again before DS falls; p.566 | Go WRONG (also required CS low at the DS-low write sample) | FIXED: CS sampled at the AS-rise sample only (TestCmd_WriteWithCSReleasedBeforeDS). |
| 6 | Write data sample point | p.566 "data is read from AD8-AD15 while Data Strobe is Low"; p.569 "must be valid late in T2"; AC #10/#11 (TdC(WDv)/ThC(WDn) referenced to CLK) | Go RIGHT (first DS-low sample after the command AS rise) | CONFIRMED. The silicon's edge inside the DS-low window is not tabulated; first DS-low sample is the model convention. |
| 7 | PA drive window | p.568 "remain valid until the end of T3"; AC #27 TdDS(Af) DS rise -> float; #28 TdAS(Ad) driven from the AS fall, not yet valid | Go WRONG on release (held to next AS fall) | FIXED: PADrive drops at the DS-rise sample (also on the DMA path). |
| 8 | PA driven during a violation | Fig.9/10 p.567-568 draw A8-A23 valid while SUP is low (memory gates with SUP) | Go RIGHT for CPU violations, WRONG for DMA violations (translateDMA drove nothing) | FIXED: DMA violations drive the translated PA too. |
| 9 | SUP window | p.568 "asserted during the current machine cycle and terminates during T3"; AC #33 TdDS(SUP) DS rise -> SUP release; p.565 DMA "during that cycle only" | Go RIGHT for CPU (held to DS rise); WRONG for DMA (dropped one clock later regardless of DS) | FIXED: DMA suppress uses the same held-until-DS-rise envelope, no instruction hold (p.565/566). |
| 10 | SUP repeated until end of instruction; DMA cycles exempt | p.565, p.568, p.570 | Go RIGHT (supInstrHold cleared at the next ST=1101 AS fall) | CONFIRMED (TestG79_1_...). |
| 11 | Which edge samples AS/DS/CS/SN/ST/DMASYNC, and where PA is driven | p.571 Pin Description: "The rising edge of AS indicates that AD0-AD15, ST0-ST3, R/W and N/S are valid"; AC p.573 #13/#14 TsOFF(AS)/ThAS(OFFn) offset setup/hold to the AS RISE; #34/#35 CS to the AS rise; #21 TdSTNR(AS) status valid before the AS rise; #18/#19 SN setup to the T1 CLK rise, hold past the T2 CLK rise; #20/#22 DMASYNC to CLK; #28 TdAS(Ad) PA driven from the AS FALL, valid per #25/#29; #29 TdC(Av) PA valid after the T1 CLK rise; #30/#32 SEGT/SUP from the AS rise; #8/#6 data from the DS fall, #27/#9/#33 releases at the DS rise; #36 AS rises >= 10 ns BEFORE the T2 CLK rise, #15 AS falls after T1 rise, so on silicon /AS is never Low across a CLK rise | Go WAS WRONG (sampled AS/DS only at CLK rises, latched the offset/status at the first AS-low sample, drove PA/SEGT/SUP at the CLK rise after the AS rise); FIXED 2026-11-02 to the same edges as the RTL, vectors re-recorded | RTL FOLLOWS THE DATASHEET (O-26, 2026-11-02): /AS and /DS edges on the master clock; offset, ST, R/W, N/S, /CS in a latch open while /AS is Low; SN from the last CLK rise; PA combinational from the /AS rise in the same master clock, then held (OPEN: the chip starts driving at the /AS fall, #28; PA is undriven while /AS is Low here); SEGT/SUP from the /AS rise; command data and the ack identifier from the /DS fall; /SEGT released at the third CLK rise from the ack's /AS rise (row 1, INFERRED). Vectors match exactly. |
| 12 | Same-sample DS rise + next AS fall | AC #16 TdDS(AS) min 30 ns (can share a posedge sample) | Go WRONG (the DS-rise clear of addr_latched ran after the new AS-fall latch and erased it) | FIXED: `dsRisingEdge && !asFallingEdge` clears the latch. Visible only when both land in one clock (TestSegTrapAcknowledgeID). |
| 13 | DMASYNC low during CPU idle clocks in the Go tests | p.571 "It must always be High during CPU cycles"; p.566 DMA needs >= 2 low clocks | Test-input artifact (one low sample never reaches the >=2 count) | FIXED in the tests: the shared `idle` input keeps DMASYNC High; no vector has an out-of-spec input. |
| 14 | DMASYNC protocol | p.566: >= 2 clocks Low, then High before a CLK rise -> translate; "During CPU cycles, DMASYNC should always be High"; DMA in System or Normal mode; URS/MST gating shared with CPU cycles | Go RIGHT | CONFIRMED (+TestDMASYNC_URSandMSTGating). OPEN: Go ends the DMA cycle at DS rise; the text also says "After two clock cycles of DMASYNC High, the MMU assumes that the CPU has control of the bus". A DMA cycle without DS is unmodelled (no vector). |
| 15 | Reset state | p.570: hardware reset clears Mode Register, VTR and DSC; MSEN=1 if CS Low; "All other registers are undefined"; AD/PA 3-stated; SUP/SEGT not driven; MSEN=0 -> no response to addresses, commands with CS still work | Go RIGHT on everything specified; Go ALSO zeroes SAR, the 64 descriptors and the status registers, which silicon leaves undefined | CONFIRMED + OPEN(undefined): F records of TestReset / TestPassThroughMSENonlyAfterCSLowReset / TestCmd_AccessWithMSENClear encode zeros for spec-undefined registers -- the RTL's chosen reset value, not a silicon claim. A different RTL reset needs tolerance only on those files' final-state rows. Also FIXED: reset clears the internal DMA/command latches (dmaActive, dmaLowCount, cmdPending, ackPending). |
| 16 | MSEN=0 / TRNS=0 semantics | p.564: MSEN clear -> address lines 3-stated (no translation, no protection); TRNS clear -> pass-through {0,SN[6:0],offset} without protection checking; URS/MST gating still applies (address lines "remain 3-stated") | Go RIGHT | CONFIRMED (TestPassThroughMSENonlyAfterCSLowReset, TestCmd_AccessWithMSENClear). |
| 17 | SUP_n semantics | p.571 pin description "asserted during the current bus cycle when any access violation except write warning occurs"; p.564 write warning "no Suppress signal"; FATL: "Suppress signals are generated on this and subsequent CPU violations" | Go RIGHT | CONFIRMED (TestWriteWarningNoSuppress, TestMMU_FATL_*). |
| 18 | VTR bit layout and flag rules | Fig.8 p.564 (FATL SWW PWW EXCV CPUIV SLV SYSV RDV); flag definitions p.564; SWW/FATL prose p.565 | Go RIGHT on layout, capture-once, FATL/SWW rules and inhibits | CONFIRMED. |
| 19 | VTR bit PRIORITY when several conditions hold at once | p.564 defines each flag independently ("Set when ...") and says nothing about exclusivity or priority | OPEN -- Go's translate() sets ONE flag per access, early-return order CPUI > SLV > RD > SYS > EXC; parallel comparators in silicon would set every applicable flag. No test or vector has a multi-flag access, so nothing encodes the Go priority; add none until a primary source (Z8010 Technical Manual UM010401, not in the archive) settles it. |
| 20 | VSN register width | Fig.8 p.564: Violation Segment Number = 0 + 7-bit segment number ("most-significant 15 bits of the logical address") | Go WRONG (stored the 6-bit descriptor index) | FIXED: VSN = SN[6:0] (TestCmd_ReadStatusRegisters reads back 0x62). |
| 21 | BCSR layout | Fig.8 p.564: bits 3:0 status code, bit 4 R/W, bit 5 N/S, bits 7:6 = 0 | Go RIGHT | CONFIRMED (read back 0x28 for a normal-mode write with ST=1000). |
| 22 | ISN/IOFF capture | p.564 "address of the last instruction fetched before the first accessing violation", frozen once a violation is captured | Go RIGHT in spirit (captures on ST=1101 first-word fetches; freezes with violCaptured; resumes after 0x11) | CONFIRMED; "instruction fetched" is read as the first word (ST=1101), not every ST=1100 operand access (the text does not distinguish). |
| 23 | Command table (22 opcodes) | p.566 tables; UM010401 Table 3-6 for 0x0D=Limit / 0x0E=Attribute | Go RIGHT | CONFIRMED incl. read side, 0x11/0x13/0x14/0x15/0x16, SAR auto-increment "at the end of the field", DSC order base-high, base-low, limit, attribute. |
| 24 | SAR write (0x01) resets DSC | not in the datasheet (the Go model infers it from "first the high-order byte is selected and then the low-order byte", p.566) | OPEN | TestMMU_SARWrite_ResetsDSC_BaseField's F rows encode the Go reading; a different RTL reading needs tolerance on that file's F DSC/DESC rows. The Coherent kernel (md.s) writes DSC=0 before block 0x0F operations and issues base-field commands in high/low pairs, so no C900 software depends on either reading. |
| 25 | Read of a write-only / unlisted opcode | p.566 lists write-only 0x11/0x13-0x16 and read-only 0x02-0x07 | OPEN whether silicon drives AD on such a read; Go drives nothing | not vectorized (TestCmd_UnlistedOpcodeWriteIsNoOp only writes; TestCmd_ResetSWWandFATL only writes the reset opcodes). |
| 26 | Multi-MMU URS / MST+NMS / CS decode | p.564-565 (URS vs SN6; MST -> N/S must match NMS; CS selects the MMU for a command); p.565 ack: every enabled MMU drives its own line 8+ID | Go RIGHT | CONFIRMED (TestMultipleMMU_SN6Select, TestDualMMUWithMST, TestMMU_URS_SingleMMU, TestSegTrapAcknowledge_NotOurs). CS decode itself is board logic. |
| 27 | Command data lane | p.559/566: the Z8010 has AD8-AD15 only | Go RIGHT (data in/out on AD15:8; Data[7:0]=0 is a model convention for pins that do not exist) | CONFIRMED. |

## The ladder (`make test-mmu` prints the live order)

| rung | what to build | vectors that turn green |
|------|---------------|-------------------------|
| 0 | reset pin state | TestReset.001, TestMasterEnableDisabled, TestMMU_URS_SingleMMU.001/.003, TestSegTrapAcknowledge_NotOurs.001, TestCmd_UnlistedOpcodeWriteIsNoOp |
| 1 | reset: cs_n low => mode_reg MSEN=1 | TestReset.000 (2 ticks, final MODE) |
| 2 | strobe capture + AS-fall latch + AS-rise translate, MSEN/URS/MST/NMS gating, pass-through vs translate, PA = {base,8'h0}+off, pa_drive dropped at DS rise | TestBasicTranslation, TestPhysicalAddress16BitBase, TestISNCapture, TestExecOnly.001, TestMMU_URS_SingleMMU.000/.002, TestMMU_DIRWBoundsCheck.000/.001/.004/.005, TestNMSBehavior.*, TestMSTMode.*, TestMultipleMMU_SN6Select.*, TestDualMMUWithMST.*, TestPassThroughMSENonlyAfterCSLowReset |
| 3 | violation comparator tree + trap_pending/SEGT + sup_held (release at DS rise) + VTR/VSN(7-bit)/VOFF/BCSR capture, REF/CHG update, PA still driven on hard violation | TestOutOfBounds, TestCPUInhibit, TestExecOnly.000, TestSROProtection.*, TestMMU_DIRWBoundsCheck.002/.003, TestSUPnHeldUntilDSRises, TestChangedFlag, TestStackSegmentBounds (needs P ACK), TestTrapAcknowledge (P ACK) |
| 4 | write warnings (PWW no suppress), FATL/SWW rules, violCaptured-once + overflow, ISN freeze | TestWriteWarning, TestWriteWarningNoSuppress, TestViolationCapturedOnce, TestMMU_SWW_StackPushDuringTrap, TestMMU_FATL_*, TestMSTISNFrozenAtViolation |
| 5 | supInstrHold until next ST=1101; SEGT-ack: ack_pending at the AS-rise sample of ST=0100, release SEGT at the third CLK rise from it (ack_wait; row 1), drive AD line 8+ID (1/0) while ds_n low, float at DS rise | TestG79_1_SuppressUntilInstructionEnd, TestSegTrapAcknowledgeID, TestSegTrapAcknowledge_NotOurs.000, TestSEGTInvariant_TrapPendingMirror |
| 6 | DMASYNC: >=2 low samples then rising edge; suppress-only (held to DS rise), PA driven, URS/MST gating | TestDMASYNCTranslation, TestDMASYNCViolationSuppressOnly, TestDMAInhibitInDMA, TestDMASYNC_URSandMSTGating |
| 7 | command engine: cs_n + ST=0011 sampled at AS rise, cmd code from AD15:8; execute at the first DS-low sample (write byte from AD15:8; read byte driven on data (AD15:8) while ds_n low, floats at DS rise); SAR/DSC; the 22-entry case table (0x0D=Limit+inc, 0x0E=Attr+inc); 0x11 releases SEGT/SUP; 0x15/0x16 sweep all 64 attrs | TestMMU_AttrWrite_PreservesAllBits.*, TestMMU_SARWrite_ResetsDSC_BaseField, TestMMU_LimitWrite_IncSAR, TestMMU_AttrWrite_IncSAR, TestMMU_DescriptorWrite_Cmd0F_Block, TestCmd_ReadControlRegisters, TestCmd_ReadDescriptorFields, TestCmd_ReadStatusRegisters, TestCmd_ResetSWWandFATL, TestCmd_SetAllInhibitFlags, TestCmd_WriteWithCSReleasedBeforeDS, TestCmd_AccessWithMSENClear |

Rung 7's write-only vectors are judged on final state alone (the command
path drives nothing on writes); read-side vectors also compare Data while
ds_n is low. The summary always lists the shortest failing file first.

## Files

| path | role |
|------|------|
| `rtl/k8010_mmu/z8010_mmu.sv` | RTL top |
| `tb/k8010_mmu/tb_mmu.cpp` | replay harness (exit 0 PASS / 1 FAIL / 2 SKIP / 4 usage) |
| `tb/k8010_mmu/mmu_access.h` | hierarchy contract for pokes + final state |
| `mk/k8010_mmu.mk` | make fragment (gen-/vectors-/lint-/build-/test-mmu, mmu ONLY=, ladder-mmu) |
| `scripts/run_k8010_mmu_vectors.sh` | run all / `--ladder` / `--one NAME [--vcd] [--context N]` |
| `vectors/k8010_mmu/` | generated |
| Go `sim/mmu/vecdump_test.go` | recorder (env-gated) |
| Go `sim/mmu/mmu_spec_test.go` | datasheet-cited conformance tests (records like any other test) |
| Go `hdl/gen/cmd/mmuvecverify` | Go replay self-check |
