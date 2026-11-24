# k8010_mmu (Z8010 MMU) -- tests

## Scope

RTL `rtl/k8010_mmu/z8010_mmu.sv`; replay harness `tb/k8010_mmu/tb_mmu.cpp`
with `tb/k8010_mmu/mmu_access.h`; vectors `vectors/k8010_mmu/*.vec` (77
files from 54 tests); make fragment `mk/k8010_mmu.mk`.

Sources: z8010_mmu.pdf = Zilog Z8010 MMU Product Specification 00-2046-03
(pp.559-575; same text and AC table in the October 1988 Z8000 Family Data
Book pp.163-177). Page and AC-item numbers below are z8010_mmu.pdf's.

## How to run

```
make lint-mmu          # verilator -Wall on z8010_mmu.sv (zero suppressions)
make build-mmu         # obj_dir/tb_mmu/tb_mmu
make test-mmu          # replay every vector, ladder summary (shortest failing first)
make mmu ONLY=TestBasicTranslation [VCD=1] [CONTEXT=20]   # one vector, divergence table
make ladder-mmu        # every vector shortest-first with PASS/FAIL/SKIP
make test-mmu-timing   # datasheet strobe bench (22 checks; docs/TIMING_TESTS.md)
make test-mmu-dmasync  # DMASYNC pulses then a CPU cycle; DMA cycles (210 checks)
make test-cpu-mmu-clk  # CPU and MMU on one CLK net, PA valid at the CPU's next CLK rise
```

The top-level `lint`, `build` and `test` include these.

### Vector format (`K8000VEC 1 mmu`)

One file per MMU instance per test: `<TestName>.<NNN>.vec` (dual-MMU tests
give `.000` and `.001`).

```
K8000VEC 1 mmu
test TestBasicTranslation 0
P DESC 05 0100 FF 80             poke: Desc[5] = {Base, Limit, Attr}
P MODE C8                        poke: Mode Register
T 72 0000 00 0 6 000000 0000 00  one pin sample
...
F MODE C8 / F SAR / F DSC / F VTR / F VSN / F VOFF / F VOVF (not compared) / F ISN / F IOFF / F BCSR / F TRAP
F DESC 00 0000 00 00 (x64)       final descriptor store
F TICKS 6                        informational
END
```

`X unsupported <reason>` before the first `T` means SKIP. No file has one.

`T <in_bits:2hex> <AD:4hex> <SN:2hex> <ST:1hex> <out_bits:1hex> <PA:6hex> <Data:4hex> <DataMask:2hex>`

* `in_bits` (bit 7 = MSB): `CLK RESET_n AS_n DS_n RW NS CS_n DMASYNC`
* `out_bits` (bit 3 = MSB): `PADrive SEGT_n SUP_n DataDrive`
* `DataMask`: which of AD15:8 are driven (bit n = AD line 8+n).

Two records per CLK period, CLK=0 then CLK=1.

Pokes, applied through `mmu_access.h` before the next `T`:

| poke | sets | files |
|---|---|---|
| `P MODE <2hex>` | Mode Register | 60 |
| `P SAR <2hex>` | Segment Address Register | 3 |
| `P DSC <1hex>` | Descriptor Selector Counter | 1 |
| `P VTR <2hex>` | Violation Type Register | 3 |
| `P DESC <idx> <base> <limit> <attr>` | one descriptor | 62 |
| `P ACK` | trap acknowledged: clears the pending trap, the captured violation and VTR, releases /SEGT | 3 |
| `P LATCHED_ST`, `P ADDR_LATCHED` | accepted, unused | 0 |

### Comparison rules

* **One record = one CLK level, then one or more master clocks.** The RTL
  runs on the master clock `clk`; `clk_in` is the CLK rising-edge pulse,
  High for the first master clock of a record whose CLK rose. `--mclk P` /
  `K8000_MCLK` sets the master clocks per record (comma list, cycled;
  default `1,2,1,3`; the ladder passes at 1, 2, 3, 4, 7 and 1,2,1,3).
  /AS and /DS edges act in the record that shows them; SN, DMASYNC and the
  trap-acknowledge /SEGT release act on CLK rises (ledger row 11). Every
  compared pin must match exactly; there is no tolerance window.
* **Pins are the Z8010's**: AD15..AD8 in (`ad[7:0]`), A23..A8 out
  (`pa[15:0]`), AD15..AD8 out (`data[7:0]`). The tb compares PA[23:8],
  Data[15:8] and the high byte of VOFF.
* **/RESET is a level**; /CS is taken with it, so its last value before the
  /RESET rise sets MSEN (AC #37/#38 p.573).
* **Always compared**: PADrive, SEGT_n, SUP_n, DataDrive, DataMask.
* **PA only while PADrive = 1, Data only while DataDrive = 1.**
* **SEGT_n / SUP_n** are the resolved open-drain level with the board
  pull-up (0 = driven Low, 1 = released).
* **Final state** (`F`) via `mmu_access.h`: Mode, SAR, DSC, VTR, VSN, VOFF,
  overflow, ISN, IOFF, BCSR, trap pending, all 64 descriptors. Renaming a
  register means updating `mmu_access.h` in the same change.
* Start state: no reset, strobes High, CLK = 0; the first CLK = 1 record is
  a rising edge.

## What is covered

All 54 tests record (77 files). Three use `P ACK` (TestStackSegmentBounds,
TestTrapAcknowledge, TestMSTISNFrozenAtViolation); TestSegTrapAcknowledgeID
and TestSegTrapAcknowledge_ShortCycle run a real acknowledge cycle.

The datasheet-cited tests cover the read side of the command protocol
(0x00/0x01/0x20, 0x02-0x07, 0x08-0x0F read-back with DSC/SAR sequencing),
0x11/0x13/0x14/0x15/0x16, unlisted-opcode writes as no-ops, /CS released
before /DS on a write, commands with MSEN = 0, MSEN = 1/TRNS = 0
pass-through after a /CS-Low reset, URS gating, PA float at the /DS rise,
DMASYNC with URS/MST+NMS gating, TRNS pass-through and hand-back, the
segment-trap acknowledge when the trap is not ours (drives 0) and when
MSEN = 0 (drives nothing), and SEGT_n == !trap pending through assert,
second violation (FATL), acknowledge and reset.

### Ladder (`make test-mmu` prints the live order)

| rung | what to build | vectors that turn green |
|---|---|---|
| 0 | reset pin state | TestReset.001, TestMasterEnableDisabled, TestMMU_URS_SingleMMU.001/.003, TestSegTrapAcknowledge_NotOurs.001, TestCmd_UnlistedOpcodeWriteIsNoOp |
| 1 | reset: /CS Low sets MSEN | TestReset.000 |
| 2 | strobe capture, the open latch while /AS is Low, translate at the /AS rise, MSEN/URS/MST/NMS gating, pass-through vs translate, PA = {base, 8'h0} + offset, PA dropped at the /DS rise | TestBasicTranslation, TestPhysicalAddress16BitBase, TestISNCapture, TestExecOnly.001, TestMMU_URS_SingleMMU.000/.002, TestMMU_DIRWBoundsCheck.000/.001/.004/.005, TestNMSBehavior.*, TestMSTMode.*, TestMultipleMMU_SN6Select.*, TestDualMMUWithMST.*, TestPassThroughMSENonlyAfterCSLowReset |
| 3 | violation checks, trap pending and /SEGT, /SUP held to the /DS rise, VTR/VSN (7-bit)/VOFF/BCSR capture, REF/CHG update, PA still driven on a violation; while a trap is pending only the first-word fetch goes unchecked | TestOutOfBounds, TestCPUInhibit, TestExecOnly.000, TestSROProtection.*, TestMMU_DIRWBoundsCheck.002/.003, TestSUPnHeldUntilDSRises, TestChangedFlag, TestTrapPendingWordFetchStillChecked, TestStackSegmentBounds, TestTrapAcknowledge |
| 4 | write warnings (PWW without suppress), FATL/SWW rules, capture once plus overflow, ISN freeze | TestWriteWarning, TestWriteWarningNoSuppress, TestViolationCapturedOnce, TestMMU_SWW_StackPushDuringTrap, TestMMU_FATL_*, TestMSTISNFrozenAtViolation |
| 5 | suppress until the next ST = 1101; segment-trap acknowledge: decided at the /AS rise of ST = 0100, /SEGT released at the third CLK rise from it (row 1), AD line 8+ID driven 1/0 while /DS is Low, float at the /DS rise | TestG79_1_SuppressUntilInstructionEnd, TestSegTrapAcknowledgeID, TestSegTrapAcknowledge_ShortCycle, TestSegTrapAcknowledge_NotOurs.000, TestSEGTInvariant_TrapPendingMirror |
| 6 | DMASYNC: two or more Low samples, then High at a CLK rise; suppress only (held to the /DS rise), PA driven, URS/MST gating, TRNS pass-through; hand-back at the /DS rise or the second DMASYNC-High sample, releasing /SUP; a DMASYNC-Low sample frees the /AS latch for the next cycle | TestDMASYNCTranslation, TestDMASYNCViolationSuppressOnly, TestDMAInhibitInDMA, TestDMASYNC_*, tb_mmu_dmasync |
| 7 | command engine: /CS and ST = 0011 at the /AS rise, command code from AD15:8, executed at the first /DS-Low sample (write byte from AD15:8; read byte driven while /DS is Low, float at the /DS rise); SAR/DSC; the 22 commands (0x0D = Limit + increment, 0x0E = Attribute + increment); 0x11 releases /SEGT and /SUP; 0x15/0x16 set all 64 inhibit bits | TestMMU_AttrWrite_PreservesAllBits.*, TestMMU_SARWrite_ResetsDSC_BaseField, TestMMU_LimitWrite_IncSAR, TestMMU_AttrWrite_IncSAR, TestMMU_DescriptorWrite_Cmd0F_Block, TestCmd_ReadControlRegisters, TestCmd_ReadDescriptorFields, TestCmd_ReadStatusRegisters, TestCmd_ResetSWWandFATL, TestCmd_SetAllInhibitFlags, TestCmd_WriteWithCSReleasedBeforeDS, TestCmd_AccessWithMSENClear |

Rung 7's write-only vectors are judged on final state alone; read-side
vectors also compare Data while /DS is Low.

### Spec conformance ledger

Verdicts: SPEC = the source settles it and the vectors follow it;
INFERRED = read from a figure, unverified on silicon; OPEN = the source is
silent; the reading taken is stated.

| # | item | source | verdict | behaviour / vectors |
|---|---|---|---|---|
| 1 | /SEGT release in the acknowledge cycle | p.565 "The Segment Trap line is reset during the segment trap acknowledge cycle"; p.570 "Segment Trap remains Low until a Trap Acknowledge signal is received"; Fig.12 p.570: /SEGT rises from the CLK edge opening the second automatic wait state (TWA2), /DS falls in the fourth; AC #31 TdC(SEGT) CLK rise to /SEGT rise; Z8001 (1988 DB p.151, TM 9.4.6): VI/NVI/SEGT sampled at T3 of an instruction's last machine cycle, five automatic waits, identifier taken at the /DS rise | INFERRED | released at the third CLK rise from the acknowledge's /AS rise (the T2 rise is the first = the TWA2 rise), or at an earlier /DS rise. Whether the trap was ours is decided at the /AS rise. Why TWA2: only Fig.12 shows the acknowledge's own clocks and the drawn rise starts there; #31 is CLK-referenced; #36 (/AS rises >= 10 ns before the T2 rise) means T2 samples /AS, TWA1 decodes ST = 0100, TWA2 clocks the release. Rejected: T2 (Fig.12 shows Low), TWA1 (Fig.12 shows Low), the first rise after /DS rises (the p.572 composite is a generic cycle and would leave /SEGT Low through the acknowledge's own T3 sample). The CPU does not re-sample inside the acknowledge, so any edge up to TWA2 + #31 meets TsSGT(C). Confirm on silicon: count CLK rises from the acknowledge /AS rise to the /SEGT rise, with varied wait states. TestSegTrapAcknowledgeID, TestSegTrapAcknowledge_ShortCycle, tb_mmu_timing [6] |
| 2 | SEGT_n == !trap pending | p.565/568/570 (asserted in T2 of the violating cycle, held until acknowledge; not driven after reset; 0x11 "returns the MMU to its initial state") | SPEC | holds through FATL/SWW inhibit, second violation, acknowledge, reset, 0x11. Asserted at the /AS rise of the violating cycle (Fig.9/10, AC #30/#31). TestSEGTInvariant_TrapPendingMirror |
| 3 | acknowledge identifier window | AC #6/#7 p.573 TdDSA(RDv)/TdDSA(RDf); Fig.12 | SPEC | driven from the /DS fall, floats at the /DS rise. Every enabled MMU drives (1 = trapped, 0 = not); MSEN = 0 drives nothing (p.565 "all enabled MMUs") |
| 4 | command read data window | p.566 "placed on AD8-AD15 while Data Strobe is Low"; AC #8/#9; Fig.11 p.569 | SPEC | executed at the first /DS-Low sample after its /AS rise; driven only while /DS is Low. TdC(RDv) (AC #40) lets silicon settle up to about three clocks after cycle start; the CPU samples at T3, so valid data from the first /DS-Low sample is indistinguishable |
| 5 | /CS sampling for commands | AC #34/#35 p.573 (setup to and hold from the /AS rise); Fig.11 shows /CS High again before /DS falls; p.566 | SPEC | /CS taken at the /AS rise only. TestCmd_WriteWithCSReleasedBeforeDS |
| 6 | write data sample point | p.566 "data is read from AD8-AD15 while Data Strobe is Low"; p.569 "must be valid late in T2"; AC #10/#11 | OPEN | the edge inside the /DS-Low window is not given; the first /DS-Low sample is taken |
| 7 | PA drive window | p.568 "remain valid until the end of T3"; AC #27 TdDS(Af); #28 TdAS(Ad) | SPEC | driven from the /AS fall, floats at the /DS rise (CPU and DMA) |
| 8 | PA during a violation | Fig.9/10 p.567-568 draw A8-A23 valid while /SUP is Low | SPEC | translated PA driven on CPU and DMA violations |
| 9 | /SUP window | p.568 "asserted during the current machine cycle and terminates during T3"; AC #33 TdDS(SUP); p.565 DMA "asserted during that cycle only" | SPEC | held to the /DS rise, CPU and DMA alike; DMA has no instruction hold |
| 10 | /SUP repeated until the end of the instruction; DMA exempt | p.565, p.568, p.570 | SPEC | cleared at the next ST = 1101 /AS rise. TestG79_1_SuppressUntilInstructionEnd |
| 11 | which edge samples what, and where PA is driven | p.571 "The rising edge of AS indicates that AD0-AD15, ST0-ST3, R/W and N/S are valid"; AC p.573 #13/#14 offset to the /AS rise; #34/#35 /CS to the /AS rise; #21 status before the /AS rise; #18/#19 SN to the T1/T2 CLK rises; #20/#22 DMASYNC to CLK; #28 PA driven from the /AS fall, valid per #25/#29; #30/#32 /SEGT, /SUP from the /AS rise; #6/#8 data from the /DS fall, #9/#27/#33 releases at the /DS rise; #36 /AS rises >= 10 ns before the T2 rise, #15 /AS falls after the T1 rise | SPEC | /AS and /DS edges on the master clock; offset, ST, R/W, N/S, /CS in a latch open while /AS is Low; SN from the last CLK rise; PA driven from the /AS fall, following the open latch, decided again at the /AS rise and held; /SEGT and /SUP from the /AS rise; command data and identifier from the /DS fall; /SEGT release per row 1 |
| 12 | /DS rise and the next /AS fall in one sample | AC #16 TdDS(AS) min 30 ns | SPEC | the /DS-rise clear does not erase the new /AS-fall latch. Visible in TestSegTrapAcknowledgeID |
| 13 | DMASYNC during CPU cycles | p.571 "It must always be High during CPU cycles"; p.566 DMA needs >= 2 Low clocks | SPEC | no vector drives DMASYNC Low outside a DMA cycle |
| 14 | DMASYNC protocol | p.566: >= 2 clocks Low, then High before a CLK rise -> translate; "During CPU cycles, DMASYNC should always be High"; p.566 "After two clock cycles of DMASYNC High, the MMU assumes that the CPU has control of the bus"; p.564 TRNS names no DMA exemption; p.572 draws DMASYNC High for one CLK rise | SPEC + INFERRED | DMA follows TRNS (clear: {SN, offset} unchecked); the cycle ends at its /DS rise or at the second DMASYNC-High sample (the address sample is the first), which releases /SUP; A23:8 stay driven to the /DS rise. INFERRED: a DMASYNC-Low sample with /AS High stops the cycle holding off the /AS latch (A23:8 and /SUP still to the /DS rise). Not built: p.566 "A Low DMASYNC inhibits the MMU from using an indeterminate segment number" (`sn_clk` loads at every CLK rise). TestDMASYNC_*, tb_mmu_dmasync. OPEN: DMASYNC High at more than one rise inside a DMA cycle (outside p.572; /SUP ends at the second); a DMA master driving /AS (p.572) floats A23:8 at its /AS fall |
| 15 | reset state | p.570: reset clears Mode, VTR and DSC; MSEN = 1 if /CS Low; "All other registers are undefined"; AD/PA 3-stated; /SUP, /SEGT not driven; MSEN = 0 -> no response to addresses, commands still work | SPEC + OPEN | the F records of TestReset, TestPassThroughMSENonlyAfterCSLowReset and TestCmd_AccessWithMSENClear hold zeros for the undefined SAR and status registers and the pre-reset contents for descriptors: this implementation's choice, not a silicon claim. Reset also clears the DMA, command and acknowledge latches |
| 16 | MSEN = 0 / TRNS = 0 | p.564: MSEN clear -> address lines 3-stated; TRNS clear -> {0, SN[6:0], offset} without checks; URS/MST gating still applies | SPEC | TestPassThroughMSENonlyAfterCSLowReset, TestCmd_AccessWithMSENClear |
| 17 | /SUP on violations | p.571 "asserted during the current bus cycle when any access violation except write warning occurs"; p.564 write warning "no Suppress signal"; FATL: "Suppress signals are generated on this and subsequent CPU violations" | SPEC | TestWriteWarningNoSuppress, TestMMU_FATL_* |
| 18 | VTR layout and flag rules | Fig.8 p.564 (FATL SWW PWW EXCV CPUIV SLV SYSV RDV); p.564-565 | SPEC | layout, capture once, FATL/SWW rules and inhibits |
| 19 | VTR priority with several conditions at once | p.564 defines each flag independently | OPEN | one flag per access, order CPUI > SLV > RD > SYS > EXC; parallel comparators in silicon may set every applicable flag. No vector has a multi-flag access |
| 20 | VSN width | Fig.8 p.564: 0 + 7-bit segment number | SPEC | VSN = SN[6:0]; TestCmd_ReadStatusRegisters reads 0x62 |
| 21 | BCSR layout | Fig.8 p.564: bits 3:0 status, bit 4 R/W, bit 5 N/S, bits 7:6 = 0 | SPEC | reads 0x28 for a normal-mode write with ST = 1000 |
| 22 | ISN/IOFF capture | p.564 "address of the last instruction fetched before the first accessing violation" | SPEC | captured on ST = 1101 first-word fetches, frozen with the captured violation, resumed after 0x11. "Instruction fetched" is read as the first word only |
| 23 | command table (22 opcodes) | p.566 tables; UM010401 Table 3-6 (0x0D = Limit, 0x0E = Attribute) | SPEC | read side, 0x11/0x13-0x16, SAR increment "at the end of the field", DSC order base high, base low, limit, attribute |
| 24 | SAR write (0x01) resets DSC | p.566 "first the high-order byte is selected and then the low-order byte" | OPEN | DSC reset on a SAR write; TestMMU_SARWrite_ResetsDSC_BaseField's F DSC/DESC rows encode it |
| 25 | read of a write-only or unlisted opcode | p.566 lists write-only 0x11/0x13-0x16 and read-only 0x02-0x07 | OPEN | drives nothing; no vector reads one |
| 26 | multi-MMU URS, MST+NMS, /CS | p.564-565; p.565 acknowledge: every enabled MMU drives its own line 8+ID | SPEC | TestMultipleMMU_SN6Select, TestDualMMUWithMST, TestMMU_URS_SingleMMU, TestSegTrapAcknowledge_NotOurs. /CS decode is board logic |
| 27 | command data lane | p.559/566: AD8-AD15 only | SPEC | data on AD15:8 |

## Known gaps

* Rows 6, 14 (long DMASYNC High), 15 (undefined reset values), 19, 24, 25:
  OPEN; row 1 INFERRED.
* Not vectorized: all 256 command codes x read/write x random descriptors;
  open-drain wire-OR of two chips (the tb drives one; `.000`/`.001` replay
  each chip separately); multi-flag violations (row 19).
