# k800x_cpu (Z8001/2/3/4) -- vectors and the spec conformance ledger

RTL `rtl/k800x_cpu` (one core; `SEGMENTED`/`VMPU` pick the variant);
harness `tb/k800x_cpu`; vectors `vectors/k800x_cpu`.

Review decoder changes in `rtl/k800x_cpu/z8000_decode_table.txt`: the ROM
(1660 lines of 80-bit hex; `decode.vec` 70336 more) as 479 control words
with non-default fields named (`alu_op=OP_SUB width=WIDTH_BYTE
src2=SRC_IMM ...`) over 8495 first-word ranges. Kept honest by:

* the generator re-packing every field list and failing unless it is
  bit-identical to the hex;
* `make test-decode-table`, which checks `z8000_decode_rom_gen.sv` against
  every range (1048576 checks). A `-` in the w1 column claims word 2's low
  nibble is irrelevant, so all 16 nibbles are checked.

`vectors/k800x_cpu/cpu/*.vec` are recorded from Go `sim/cpu` (recorder
`vecdump_test.go`, env `K8000_VEC_DIR`) by `make refresh-vectors` and
replayed by `tb/k800x_cpu/tb_cpu.cpp` (`make test-cpu`). Format:
docs/VECTOR_FORMAT.md; rung order: docs/LADDER.md.

This file audits the Go model's pins against the primary sources. The
target is the hardware: where the model was unambiguously wrong it was
fixed, the vectors regenerated, and a cited test added. Where the spec is
silent or the sources disagree the item is OPEN and the harness tolerant.

Sources (printed page numbers of the 1988 Z8000 Family Data Book,
`1988_Zilog_Z8000_Family_Data_Book.pdf`; PDF page = printed + 7 in the
Z8001/2 spec, also `z8001_cpu.pdf`):
Product Spec "Z8000 CPU Timing" pp.149-157 (Fig 12 memory read/write, Fig
13 I/O, Fig 14 interrupt/segment-trap acknowledge, Fig 15 bus
request/acknowledge, Fig 16 STOP, Fig 17 internal operation, Fig 18
refresh, Fig 19 reset), AC Characteristics pp.159-161; Z8000 CPU
Reference Manual 1982 (`Z8000_CPUrefMan_1982.pdf`, PDF page = printed +
9) chapter 9 pp.229-241 (Figs 9.2-9.11, Table 9-1) and 7.4/7.6.
Go requirements R-CPU-500..530 and R-CPU-930..998 (AC table) cite most of
these.

## Reading the vectors: the rising-edge convention

Model and RTL clock on the rising edge only. A `T` record's outputs are the
pins just after that edge (the CLK=0 record repeats them). Silicon moves
several strobes after the FALLING edge (AC table, all from clock fall:
TdC(MR) MREQ fall, TdC(DSW) DS(write) fall, TdC(DSf) DS(I/O) fall,
TdC(DSr)/TdC(MRr) DS/MREQ rise; setups to clock fall: TsW(C) WAIT, TsDR(C)
read data, TsSTP(C) STOP); they show at the NEXT rising edge. Per clock
(value just after the opening edge):

| clock | AS | MREQ (memory/refresh) | DS read | DS write | DS I/O | DS INTACK | AD |
|-------|----|-----------------------|---------|----------|--------|-----------|----|
| T1    | 0  | 1 | 1 | 1 | 1 | 1 | address (driven) |
| T2    | 1  | 0 | 0 | 1 | 1 | 1 | read: released; write: data |
| TWA   | 1  | - | - | - | 0 | 0 from the 4th TWA | I/O write: data |
| TW    | 1  | 0 | 0 | 0 | 0 | 0 | as T2/TWA |
| T3    | 1  | 0 | 0 | 0 | 0 | 0 | write: data still driven; read data captured at the opening edge |
| next  | (T1 of the next cycle may start here) | 1 | 1 | 1 | 1 | 1 | released / next address |

Falling-edge samples move to the next rising edge: WAIT/ABORT at the edge
that would open T3 or the next TW; identifier/read data at the T3 opening
edge; STOP at the fetch launch edge and each refresh T3 opening edge.
Sampling read data one edge later (closing T3) also passes: recorded memory
responses hold while DS is low.

## Spec conformance ledger

Verdicts: FIXED = Go model corrected; CONFIRMED = model matched; OPEN =
ambiguous or unspecified, harness tolerant. The last column names the Go
`sim/cpu` regression test or the `tb/k800x_cpu/tb_cpu.cpp` tolerance.

| # | item | source | verdict | change / note |
|---|------|--------|---------|---------------|
| 1 | Reset pin state: AD 3-stated; AS, DS, MREQ, ST0-3, BUSACK, MO high; SN low; R/W, B/W, N/S "not affected" | PS "Reset" p.156 + Fig 19 p.157; RM 7.4 p.220, 9.7 p.241 | CONFIRMED | `TestResetPinState`. During reset N/S low, R/W high, B/W low (undefined in silicon); RTL matches. |
| 2 | Reset reads start on the 3rd rising edge after RESET rises; three (Z8001) / two (Z8002) back-to-back 3-clock reads at 0002/0004/0006 with ST=1100 ("IFn" in Fig 19), system mode | Fig 19; PS p.156 | CONFIRMED | `TestResetSequence*`, `TestResetReadStatusCodes` |
| 3 | Memory read: DS low from the T2 edge THROUGH T3 (TwDSR = TcC+TwCh-80 ns), MREQ low through T3 (TwMRh = TcC-40 ns), both released at the edge after T3 | Fig 12 p.150; AC 19/34/38 p.159 | FIXED (was: DS/MREQ high at the T3 edge -- MREQ low 1 clock, high 2, the inverse of TwMRh) | `TestBusTimingMemoryRead`; every read vector |
| 4 | Memory write: data driven from the T2 edge to the end of T3 (TdC(DW), TdDS(DW)); DS(write) low only for the T3 clock (falls TdC(DSW) after the T2 falling edge, TwDSW = TcC-65 ns) | Fig 12; AC 14/16/21/35/39/40 | FIXED (was: DS low during T2, data released at the T3 edge) | `TestBusSpec_MemoryWriteStrobes` |
| 5 | Byte memory writes put the same byte on both halves of AD | RM 9.4.2 p.234; R-CPU-513 | FIXED (was: the other half zero) | `TestBusSpec_ByteWriteDuplicatesData`; `cpu_bytelane_test` unchanged (lane checks) |
| 6 | Byte I/O lanes: standard I/O on AD0-7, special I/O on AD8-15; the other half not specified | RM 9.4.3 p.234; Z8010 spec (AD8-15 only) | CONFIRMED (lanes) / OPEN (other half: model leaves it zero, not duplicated) | `cpu_io_bytelane_test` |
| 7 | I/O cycle: T1, T2, TWA, T3; DS falls after the T2 falling edge (low after the TWA and T3 edges, TwDS = 2TcC-90 ns); MREQ high; N/S low; port address at T1 | Fig 13 p.151; AC 42/43 | FIXED (was: DS low at T2 and TWA, high at T3) | `TestBusSpec_IOCycleDS`, `TestIOCycleAutoWait` |
| 8 | WAIT sampled at the T2 falling edge (again mid-TW); one clock added per Low sample; no control output changes during TW | PS p.150; RM 9.4.1 p.232 | FIXED (was: sampled at the T2 rising edge -- a WAIT driven in response to DS falling was never honored) | `TestBusSpec_WaitSampledAtEndOfT2`; ABORT (Z8003/4) moves with it (`cpu_vmpu_test` unchanged) |
| 9 | INTACK: T1, T2, five automatic waits, T3; DS falls just after the edge opening the 4th automatic wait (TdAS(DSA) min = 4TcC+TwCl-40 ns after AS rise; TdC(DSA) from clock rise) and stays low through T3 (identifier sampled at the T3 falling edge, TdDSA(DR)) | Fig 14 p.152; AC 44/45/46 p.160; RM 9.4.5 p.236 | FIXED (was: DS low for one clock, the 5th automatic wait) | `TestINTACKDSLateFall`, system `TestCIOINTACKWithLateDSFall`/`TestSCCINTACKWithLateDSFall` |
| 10 | INTACK WAIT sampled in two places: before the DS fall (delays it) and before the identifier read | RM 9.4.5 p.236 | FIXED (was: one place) | `TestBusSpec_INTACKWaitPlaces` |
| 11 | INTACK length: RM 9.4.5 "eight clock cycles long at a minimum" vs Fig 14 labelling T4, T5 after T3 inside the acknowledge cycle (10) | RM p.236; Fig 14 | OPEN | model = 8 clocks (R-CPU-458); status pushes start on the next edge. Texts disagree, unchanged. |
| 12 | Aborted IF1 before INTACK runs in the interrupted program's mode; the mode switch happens after it | PS p.152 ("the subsequent IF1 cycle is exercised, but ignored. The internal state of the CPU is not altered ... After the acknowledge cycle, the N/S output indicates the automatic change to system mode") | FIXED (was: switched to system before the ignored IF1) | `TestBusSpec_AbortedIF1RunsInProgramMode`; matters for the C900's user/system MMU pair |
| 13 | N/S during the acknowledge cycle | RM 9.4.5 "The N/S line indicates system mode (Low)" vs PS p.152 "after the acknowledge cycle" | OPEN, model = Low (RM explicit; R-CPU-460/462) | vectors encode Low |
| 14 | Refresh: ST=0001, AS pulse, MREQ low T2-T3, DS never low, ROW on AD0-8 (AD0=0), AD9-15 undefined; R/W, B/W, N/S same as the previous transaction | Fig 18 p.156; RM 9.4.6 p.237 | FIXED (R/W,B/W,N/S were forced read/word/FCW mode); MREQ width via item 3 | `TestBusSpec_RefreshKeepsRWBWNS`; tb compares only AD[8:0] on refresh |
| 15 | Internal operation: ST=0000, AS pulse opening each 3-clock cycle, MREQ/DS high, AD undefined, B/W undefined, N/S same as previous | Fig 17 p.155; RM 9.4.6 | CONFIRMED / tolerance | tb does not compare AD or B/W while ST=0000 (model drives PC / word as stand-ins) |
| 16 | HALT executes 3-cycle internal operations interspersed with refresh; interrupts sampled at the beginning of every T3; exit only after two consecutive active samples, via an ignored IF1 then INTACK | PS "HALT" p.155 | FIXED (was: idle pins, exit on any tick) | `TestBusSpec_HaltInternalOpsAndTwoSampleExit`, `TestG78_8_RefreshContinuesDuringHalt` |
| 17 | STOP sampled on the falling edge before an IF1 / before an EPA second word; the fetch runs, then a refresh stream after its T3, STOP re-sampled at each refresh T3; when found High the next refresh completes and the CPU continues; ROW += 2 per cycle, prescaler bypassed | Fig 16 p.154 + text; RM 9.6.4 p.240-241; R-CPU-527..530 | FIXED (was: refresh stream BEFORE the fetch, no IF1 while STOP low) | `TestSTOPStallsAndResumes`, `TestSTOPStreamShape`, `TestSTOPBeforeEPAWord2`; system FPU tests (BSY) |
| 18 | Fig 16 T4/T5 after the last stream refresh ("remaining T states of the IF1") | Fig 16 | OPEN | treated as the normal post-fetch clocks; vectors show fetch, N refreshes, normal continuation |
| 19 | BUSREQ synchronized at the beginning of a machine cycle; BUSACK Low (all bus outputs floated) after that machine cycle completes | PS p.153 + Fig 15; RM 9.6.2; R-CPU-523 | FIXED (was: granted at any idle edge, even one clock into a machine cycle's T1) | `TestBusSpec_BusRequestTiming`, `TestBusRequestGrant`. Boundary = transaction T1 / internal-op cycle open / idle clock, so requests never starve. |
| 20 | BUSREQ release: sampled High at edge P, BUSACK High at P+1, CPU regains the bus two clocks after BUSREQ rises (P+2) | PS p.153; RM 9.6.2 p.240; R-CPU-525 | FIXED (was: BUSACK High and resume at P) | `TestBusSpec_BusRequestTiming`. Fig 15's AD row hints at a T1 at P+3, its AS row shows none; the text's "two clock cycles" is encoded (OPEN by one clock). |
| 21 | SN valid about one clock before the address (TdC(SNv) 130 ns after a clock rise), may change from TdC(SNn) after the T2 rise | PS p.150; AC 6/7; R-CPU-509 | OPEN: model drives SN with the address at T1 | tb compares SN only while AS is low, so driving SN a clock early passes |
| 22 | Status/B/W/N/S valid early in T1 and stable through T3 (TdC(S), TdDS(S)); "same as previous cycle" between transactions and after a bus grant | Fig 12/15 | CONFIRMED | model holds the last values between transactions |
| 23 | Interrupt request sampling while running: VI/NVI/SEGT levels and the NMI latch sampled at the end of T2 of the last machine cycle of the instruction | PS p.152; RM 9.6.1; R-CPU-818 | CONFIRMED approx. | model uses the level latched at the dispatch edge (T3 opening edge when the instruction ends with a transaction); +-1 clock when it ends with internal clocks -- OPEN-minor |
| 24 | Data sample point: silicon T3 falling edge; model T3 rising (opening) edge; read data must be valid one clock after DS falls (silicon: TdDSR(DR) = TcC+TwCh-150 ns) | Fig 12; AC 12/33 | OPEN (quantization) | harness memories respond while DS is low, so either T3 edge matches |
| 25 | Chained T3/T1: a transaction's T1 never shares a clock with the previous T3 (3-clock cycles back-to-back) | Fig 19; RM 9.4.2 | FIXED for two paths (STOP stream / VMPU abort re-fetch chained before) | all back-to-back vectors |
| 26 | Z8003/4 ABORT sampled at T2 and each Tw with WAIT | 1985 DB p.448 Fig 7 | CONFIRMED (moved with item 8) | `TestAbort*` |
| 27 | Refresh prescaler CLK/4, row +2, RE bit; refresh at IF1/internal-op/HALT boundaries | PS Fig 4 p.133, p.149 | CONFIRMED | `TestRefresh*` |
| 28 | INTACK/EPU-transfer cycles are addressless: AD undefined in T1 | Fig 14 (AD blob then float); RM 9.4.4/9.4.5 | tolerance | tb does not compare AD while AS is low on ST 0100-0111 and 1110 (model drives 0) |
| 29 | Flags listed as Unaffected keep their value: word ADD/ADC/SUB/SBC/CP/CPL, CPB and INC/DEC leave D, H; word AND/OR/XOR/COM/TEST leave P/V | RM p.57, 58, 60, 67, 69, 87, 98, 146, 172, 190, 193, 211 | FIXED (was: every width wrote the byte form's flags) | `TestFlagsUnaffected` |
| 30 | CPSI/CPSD and repeats compare dst - src; block compares leave D, H | RM p.72-83, example p.78 | FIXED (was: src - dst) | `TestCompareStringOperandOrder` |
| 31 | DIV/DIVL quotient of exactly -2^16 / -2^32 is case 4 (low half stored, C, V, S set) | RM p.89 | FIXED (was: case 3) | `TestArithmeticSpecGap` |
| 32 | MULTL +7n: n counts ones in the low 16 bits of the multiplicand's absolute value | RM p.141 | FIXED (was: its raw bits) | `TestArithmeticSpecGap`. Reading: absolute value of the 32-bit multiplicand, then its low 16 bits. |
| 33 | DIV case 4 time: Note 2 shortens "overflow conditions" (-82 word, -693 long); case 4 sets V | RM p.91 | CONFIRMED (reading) | model and RTL finish case 4 in 25 / 51 clocks; the RTL forms that quotient two bits per clock |
| 34 | Z8001 reset reads FCW, PC segment and PC offset from segment 0, even when the loaded FCW has SEG=0 | RM 7.4 p.220 | FIXED (was: the 0006 read took the PC segment just loaded from 0004) | `TestResetReadsSegmentZero` |

## Go model behaviour to mirror in RTL

- T3 falls through: read data is captured at the T3 opening edge, the
  sequencer's post-transaction step runs on that edge, and the strobes
  trail (busTrail) to the next edge, which may be the next T1 (Fig 19).
  RTL: bus_done at the T3 opening edge, strobes released one edge later
  unless a new T1 overrides.
- BUSREQ is sampled at machine-cycle boundaries, idle clocks included
  (`atMachineCycleBoundary`).
- STOP: `stopArmed` at the fetch launch; `stopStream` freezes the
  sequencer (MULT/DIV/EA/prefetch ticks skipped) and charges the stolen
  clocks like a refresh.
- HALT: `advanceHalt` runs the internal-op dressing itself; interrupt
  T3 samples count in `haltIntSamples`.
- Refresh transactions do not touch R/W, B/W, N/S or SN
  (`driveT1Outputs` returns early for ST=0001).
