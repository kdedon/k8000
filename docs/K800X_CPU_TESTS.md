# k800x_cpu (Z8001/2/3/4) -- vectors and the spec conformance ledger

RTL `rtl/k800x_cpu` (one core; `SEGMENTED`/`VMPU` pick the variant);
harness `tb/k800x_cpu`; vectors `vectors/k800x_cpu`.

Review decoder changes in `rtl/k800x_cpu/z8000_decode_table.txt`: the ROM
(1657 lines of 69-bit hex; `decode.vec` 70336 more) as 476 control words
with non-default fields named (`alu_op=OP_SUB width=WIDTH_BYTE
src2=SRC_IMM ...`) over 8446 first-word ranges. Kept honest by:

* the generator re-packing every field list and failing unless it is
  bit-identical to the hex;
* `make test-decode-table`, which checks `z8000_decode_rom_gen.sv` against
  every range (1048576 checks). A `-` in the w1 column claims word 2's low
  nibble is irrelevant, so all 16 nibbles are checked.

The decoder gives no instruction length: each instruction's machine-cycle
program does. Review program changes in `rtl/k800x_cpu/z8000_mc_table.txt`
(emitted with `gen/z8000_mc_rom_gen.sv` by `hdl/gen/cmd/mcrom` from Go
`sim/cpu` `cycle_program.go`): 434 forms (first word, a block form's second
word), 236 programs over the NS/SS/SL columns and the not-taken, zero and
overflow paths, each program's model text above its entries. The
generator replays every encoded program against the model's;
`make test-mc-table` checks the ROM against every table record.

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
9) chapter 9 pp.229-241 (Figs 9.2-9.11, Table 9-1) and 7.4/7.6; TM = Z8000
CPU Technical Manual (`Z8000Tech.pdf`); Fawcett, "Z8000 Microprocessor: A
Design Handbook" (1982).
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
ambiguous or unspecified, harness tolerant; OPEN-hardware = the model
follows one reading, only a real CPU can settle it. The last column names the Go
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
| 11 | INTACK length: 10 clocks, T4 and T5 after T3 inside the acknowledge cycle. Fawcett p.91: "T4 and T5 clock periods are appended to this transaction ... the interrupt acknowledge machine cycle is always at least 10 clock cycles long"; Table 6.3: "Interrupt acknowledge cycle 10"; TM Mar81 Fig 9-6 and 1988 DB Fig 14 label T3, T4, T5 inside the acknowledge cycle | Fawcett p.91, p.93 (PDF 102, 104); TM Mar81 9-8 Fig 9-6 (PDF 243); 1988 DB p.152 Fig 14 (PDF 159) | FIXED (was: 8) | `TestMachineCycleEntry`, `TestMachineCycleEntryZ8002`. Conflict: TM Mar81 9-8 and RM 9.4.5 p.236 text: "eight clock cycles long at a minimum". Model follows Fawcett and the figures. |
| 12 | Aborted IF1 before INTACK runs in the interrupted program's mode; the mode switch happens after it. It is 7 clocks of /AS and IF1 status only: /DS and /MREQ stay High, AD is released after T1, nothing is read. Fawcett p.90: "All of the proper address and status information for the next instruction fetch will appear in T1, and the AS is pulsed. However, no active DS signal is generated, the instruction is never read from memory, and the PC is not updated. The CPU spends seven clock periods in this abandoned instruction fetch cycle". Fawcett Fig 6.9, 1988 DB Fig 14, TM Mar81 Fig 9-6 and 1985 DB Z8003/4 Fig 15 draw only /AS, R/W, B/W and ST in it. Internal traps (privileged instruction, extended instruction, SC) run the same cycle with the mode switch after it: Fawcett p.92, internal traps take "10 fewer clocks; the timing is similar except that the interrupt acknowledge cycle is not included", and 10 is the acknowledge | PS p.152 ("the subsequent IF1 cycle is exercised, but ignored. The internal state of the CPU is not altered ... After the acknowledge cycle, the N/S output indicates the automatic change to system mode"); Fawcett p.89 Fig 6.9, p.90, p.92 (PDF 100, 101, 103); TM Mar81 9-8 Fig 9-6 (PDF 243); 1985 DB p.455 Fig 15 (PDF 464) | FIXED (was: switched to system before the ignored IF1; /DS and /MREQ Low and the word read; traps had no aborted IF1). Maintainer decision; traps: inference, default, unverified on silicon | `TestBusSpec_AbortedIF1RunsInProgramMode`, `TestAbortedIF1NoData`, `TestMachineCycleTrapZ8001Nonseg`, `TestSC_SetsIrqSyscall`; matters for the C900's user/system MMU pair. Conflict: Fawcett Fig 6.13 (p.95, PDF 106) draws /MREQ and /DS falling in the IF1 that follows a HALT wake sample |
| 13 | N/S during the acknowledge cycle | RM 9.4.5 "The N/S line indicates system mode (Low)" vs PS p.152 "after the acknowledge cycle" | OPEN, model = Low (RM explicit; R-CPU-460/462) | vectors encode Low |
| 14 | Refresh: ST=0001, AS pulse, MREQ low T2-T3, DS never low, ROW on AD0-8 (AD0=0), AD9-15 undefined; R/W, B/W, N/S same as the previous transaction | Fig 18 p.156; RM 9.4.6 p.237 | FIXED (R/W,B/W,N/S were forced read/word/FCW mode); MREQ width via item 3 | `TestBusSpec_RefreshKeepsRWBWNS`; tb compares only AD[8:0] on refresh |
| 15 | Internal operation: ST=0000, AS pulse opening each cycle, MREQ/DS high, AD undefined, B/W undefined, N/S same as previous; 3 to 8 clocks ("An internal operation can extend up to a maximum of eight clock periods", Fawcett p.66; "three to eight clock cycles long", 1988 DB p.155). Internal cycles appear only where an instruction's machine-cycle program names them | Fig 17 p.155; RM 9.4.6; Fawcett p.66 (PDF 77); 1988 DB p.155 (PDF 162) | FIXED (was: an internal cycle opened whenever 3 or more internal clocks remained) / tolerance | `TestMachineCyclePins`; tb does not compare AD or B/W while ST=0000 (model drives PC+2 / word as stand-ins) |
| 16 | HALT: 5-clock IF1, then 3-clock internal operations interspersed with refresh; interrupts sampled at the beginning of every T3; after two consecutive active samples the 7-clock aborted IF1, then the 10-clock acknowledge | Fawcett p.96 (PDF 107): "a five-clock instruction fetch cycle, followed by successive three-clock-period internal cycles", Fig 6.13 p.95 (PDF 106); PS "HALT" p.155 ("If an input is found active during two consecutive samples, the subsequent IF1 cycle is exercised, but ignored, and the normal interrupt acknowledge cycle is started"); Fawcett p.93 Table 6.3 (PDF 104) | FIXED (was: idle pins, exit on any tick) | `TestBusSpec_HaltInternalOpsAndTwoSampleExit`, `TestMachineCycleHalt`, `TestG78_8_RefreshContinuesDuringHalt` |
| 17 | STOP sampled on the falling edge before an IF1 / before an EPA second word; the fetch runs, then a refresh stream after its T3, STOP re-sampled at each refresh T3; when found High the next refresh completes and the CPU continues; ROW += 2 per cycle, prescaler bypassed | Fig 16 p.154 + text; RM 9.6.4 p.240-241; R-CPU-527..530 | FIXED (was: refresh stream BEFORE the fetch, no IF1 while STOP low) | `TestSTOPStallsAndResumes`, `TestSTOPStreamShape`, `TestSTOPBeforeEPAWord2`; system FPU tests (BSY) |
| 18 | STOP: the refresh stream goes in after the IF1's T3 and the IF1's remaining clocks follow the last stream refresh. TM 9.6.4: "a stream of memory refresh cycles is inserted after the third clock cycle in the instruction fetch"; Fig 9-10 shows the IF1's T4, T5 after the stream. The only refresh placed between T3 and a tail (item 35) | TM Mar81 9-12 Fig 9-10 (PDF 247); Fig 16 | FIXED (was: treated as the normal post-fetch clocks) | `TestMachineCycleRefresh`, `TestSTOPStreamShape` |
| 19 | BUSREQ synchronized at the beginning of a machine cycle; BUSACK Low (all bus outputs floated) after that machine cycle completes, tail included: "the internal BUSREQ will cause the bus acknowledge line (BUSACK) to be asserted after the current machine cycle is completed". TSET does not grant between its read and its write on every variant: "BUSRQ is not honored in the time between loading the destination from memory and storing the destination to memory" | PS p.153 + Fig 15; RM 9.6.2; TM Mar81 9-11/9-12 (PDF 246-247), 6-163 (PDF 216); R-CPU-523 | FIXED (was: granted at any idle edge, and inside a tail) | `TestBusSpec_BusRequestTiming`, `TestBusRequestGrant`, `TestMachineCycleBusRequest`, `TestTSETBusReqNotGranted`. Conflict: Fawcett p.66: "serviced at the end of the current bus transaction". Model follows TM. |
| 20 | BUSREQ release: sampled High at edge P, BUSACK High at P+1, CPU regains the bus two clocks after BUSREQ rises (P+2) | PS p.153; RM 9.6.2 p.240; R-CPU-525 | FIXED (was: BUSACK High and resume at P) | `TestBusSpec_BusRequestTiming`. Fig 15's AD row hints at a T1 at P+3, its AS row shows none; the text's "two clock cycles" is encoded (OPEN by one clock). |
| 21 | SN valid about one clock before the address (TdC(SNv) 130 ns after a clock rise), may change from TdC(SNn) after the T2 rise | PS p.150; AC 6/7; R-CPU-509 | OPEN: model drives SN with the address at T1 | tb compares SN only while AS is low, so driving SN a clock early passes |
| 22 | Status/B/W/N/S valid early in T1 and stable through T3 (TdC(S), TdDS(S)); "same as previous cycle" between transactions and after a bus grant | Fig 12/15 | CONFIRMED | model holds the last values between transactions |
| 23 | Interrupt request sampling while running: VI/NVI/SEGT levels and the NMI latch sampled at T3 of the last machine cycle of the instruction (the third clock of an internal cycle); the aborted IF1 starts after that whole cycle, tail included. Fawcett p.90: "sampled at the beginning of T3 of the last machine cycle"; 1988 DB p.152: "at the end of T2 in the last machine cycle", the same instant | Fawcett p.77, p.90 (PDF 88, 101); 1988 DB p.152 (PDF 159); TM Mar81 9-11 (PDF 246) | FIXED (was: the level latched at the dispatch edge, +-1 clock). Maintainer decision; default, unverified on silicon | `TestMachineCycleInterruptSample`. Conflict: TM Mar81 9.6.1: "At the beginning of the last clock cycle in the last machine cycle"; they differ only when that cycle has a tail. |
| 24 | Data sample point: silicon T3 falling edge; model T3 rising (opening) edge; read data must be valid one clock after DS falls (silicon: TdDSR(DR) = TcC+TwCh-150 ns) | Fig 12; AC 12/33 | OPEN (quantization) | harness memories respond while DS is low, so either T3 edge matches |
| 25 | Chained T3/T1: a transaction's T1 never shares a clock with the previous T3 (3-clock cycles back-to-back) | Fig 19; RM 9.4.2 | FIXED for two paths (STOP stream / VMPU abort re-fetch chained before) | all back-to-back vectors |
| 26 | Z8003/4 ABORT sampled at T2 and each Tw with WAIT | 1985 DB p.448 Fig 7 | CONFIRMED (moved with item 8) | `TestAbort*` |
| 27 | Refresh prescaler CLK/4, row +2, RE bit; refresh after the whole IF1 or internal machine cycle (tail included), and in HALT | PS Fig 4 p.133, p.149, p.155, p.156; Fawcett p.66 (PDF 77) | FIXED (was: refresh before the IF1, then on the clock after the IF1's T3); prescaler, row and RE confirmed | `TestRefresh*`, `TestMachineCycleRefresh`; items 35, 36, 43 |
| 28 | INTACK/EPU-transfer cycles are addressless: AD undefined in T1 | Fig 14 (AD blob then float); RM 9.4.4/9.4.5 | tolerance | tb does not compare AD while AS is low on ST 0100-0111 and 1110 (model drives 0) |
| 29 | Flags listed as Unaffected keep their value: word ADD/ADC/SUB/SBC/CP/CPL, CPB and INC/DEC leave D, H; word AND/OR/XOR/COM/TEST leave P/V | RM p.57, 58, 60, 67, 69, 87, 98, 146, 172, 190, 193, 211 | FIXED (was: every width wrote the byte form's flags) | `TestFlagsUnaffected` |
| 30 | CPSI/CPSD and repeats compare dst - src; block compares leave D, H | RM p.72-83, example p.78 | FIXED (was: src - dst) | `TestCompareStringOperandOrder`. Conflict: Data Manual 1980 CPSD p.112, CPSDR p.114, CPSI p.116, CPSIR p.118 (PDF 116, 118, 120, 122) give "C: Undefined" and "S: Undefined"; RM CPSD p.78, CPSDR p.79 (PDF 87, 88) and TM Jan83 CPSDR 6-37, CPSI 6-39 (PDF 96, 98) define them: "C: Cleared if there is a carry from the most significant bit of the result of the comparison; set otherwise, indicating a \"borrow\"", "S: Set if the result of the comparison is negative; cleared otherwise". Model follows RM and TM. |
| 31 | DIV/DIVL quotient of exactly -2^16 / -2^32 is case 4 (low half stored, C, V, S set) | RM p.89 | FIXED (was: case 3) | `TestArithmeticSpecGap` |
| 32 | MULTL +7n: n counts the ones in the absolute value of the multiplicand's low 16 bits, read as a signed word: "n = number of bits equal to one in the absolute value of the low-order 16 bits of the destination operand" | RM p.141 (PDF 150); TM Jan83 6-99 (PDF 158); TM Mar81 6-95 (PDF 148), C-5 (PDF 280); 1988 DB p.138 (PDF 145); Fawcett p.129 (PDF 140) | FIXED (was: low 16 bits of the 32-bit multiplicand's absolute value) | `TestArithmeticSpecGap`. Conflict: 1988 DB and Fawcett say "Plus seven cycles for each 1 in the multiplicand" (no absolute value); TM Mar81 6-95 prints "the low-order table 32 bits of the destination operand", its C-5 "the absolute value of the low order 16 bits of the multiplicand". Model follows RM. |
| 33 | DIV case 4 time: Note 2 shortens "overflow conditions" (-82 word, -693 long), and overflow (V set, C clear) is case 3; case 4 sets V and C | Jan83 p.6-47, p.6-49 (PDF p.106, p.108) | FIXED (was: overflow time) | model and RTL run case 4 as a normal divide, 107 / 744; `TestArithmeticSpecGap`, `TestMulDivPath_Wide` |
| 34 | Z8001 reset reads FCW, PC segment and PC offset from segment 0, even when the loaded FCW has SEG=0. TM Jan83: "the first cycle reads the FCW from Location 0002 in segment number 0. The second cycle reads the PC segment number value from locations 0004 and the third cycle reads the PC offset value from location 0006 in segment number 0"; Fawcett: "the starting FCW is fetched from segment 0, location 2, the segment number for the initial PC value is fetched from segment 0, location 4, and the PC's offset is fetched from segment 0, location 6"; Data Manual 1980: "a 4-word program status is fetched from segment 0, offset 0 for the segmented Z8000". RM 7.4 forces SN0-SN6 Low while RESET is Low | TM Jan83 7-3 (PDF 240); Fawcett p.98 (PDF 109); Data Manual 1980 1.6.6 p.44 (PDF 48); RM 7.4 p.220 (PDF 229) | FIXED (was: the 0006 read took the PC segment just loaded from 0004; the 0004 read relied on reset clearing the PC) | `TestResetReadsSegmentZero`. Conflict: RM 7.4 p.220 says the Z8001's first cycle reads the FCW from 0002 and "the next reads the PC from location 0004", with no separate segment word; 1988 DB p.156 (PDF 163) and TM Jan83 7-3 read the segment number from 0004 and the offset from 0006. Model follows the DB and TM. |
| 35 | Refresh placement: a pending refresh goes in after the whole IF1 or internal machine cycle, tail included, never between T3 and a tail (STOP excepted, item 18). Fawcett p.66: "immediately after the next IF1 machine cycle ... or the next internal operational cycle, whichever comes first"; 1988 DB p.155: "refresh cycles can be inserted at the end of any internal machine cycle". Block and repeat forms take one after an element (1988 DB p.149 lists "all Block Move instructions") | PS p.149, p.155, p.156; Fawcett p.66 (PDF 77); 1988 DB p.149, p.155 (PDF 156, 162) | FIXED (was: on the clock after the IF1's T3, ahead of its tail). Maintainer decision (item 43) | `TestMachineCycleRefresh`, `TestRefreshDeferredToInstructionBoundary`, `TestMachineCycleBlock` |
| 36 | Refresh cost: three T-states wherever it goes in (after an IF1 or internal cycle, after a block element, in HALT); it sits between two machine cycles and leaves the instruction's cycles unchanged | PS p.155, p.156 | FIXED (was: two -- the instruction ran on the refresh's T3) | `TestRefreshCostsThreeClocks` |
| 37 | Refresh after the aborted IF1 of an interrupt, trap or HALT wake: a refresh pending by its T3 goes in after that whole 7-clock cycle, three clocks, ahead of the acknowledge or the status pushes. TM sec 8.3: "If the CPU receives a trap or an interrupt simultaneously with a Periodic Refresh request, the refresh operation is performed first."; 1988 DB p.149: "can be inserted just after the completion of any first instruction fetch (IF1) cycle" | TM Mar81 8-1 (PDF 232); TM Jan83 8-1 (PDF 246); 1988 DB p.149 (PDF 156); Fawcett p.92 (PDF 103) | FIXED (was: OPEN for traps, which had no aborted IF1) | `TestRefreshAtIgnoredIF1BeforeINTACK`, `TestMachineCycleEntry` |
| 38 | Refresh pending while a STOP stream runs: the stream does not satisfy it, so one more refresh follows release | 1988 DB p.156 | OPEN | spec silent; cost is still three clocks |
| 39 | WAIT stretches a refresh cycle at its T3 sample; p.149 lists only memory, I/O and acknowledge cycles as WAIT-extendable | 1988 DB p.149, Fig 18 | OPEN | model and RTL agree |
| 40 | WAIT on an IF1: the wait clocks lengthen the IF1 machine cycle and so the instruction; its internal clocks are unchanged | PS Fig 12; Fawcett p.58, p.125 (counts assume no wait states) | FIXED (was: wait clocks taken from the instruction's execute clocks) | `TestWaitOnIF1LengthensInstruction`; its vectors pass on the RTL |
| 41 | Cycle tables are back-to-back throughput reached by the instruction's own machine cycles: a machine cycle runs "from the start of one bus transaction to the start of the next" and "all instructions are executed with combinations of these four basic machine cycles" (Fawcett p.58); the times "are calculated assuming that there are no externally-generated wait states" (Fawcett p.125). Every clock of a total sits in a tail or an internal cycle of that instruction; a wait lengthens the cycle it lands in | Fawcett p.58, p.125 (PDF 69, 136) | Maintainer decision; default, unverified on silicon | `TestCycleTotalsMatchModel`, `TestCycleAudit*`, `make test-cpu-cycles`. Fawcett's DIV R example (5 + 6 + 6 + 7 = 24) does not reach the table's 107 |
| 42 | No look-ahead: each instruction fetches only its own words, and the next IF1 starts after its last machine cycle. Fawcett p.56: "the execution of an instruction is overlapped with the fetch of the next instruction whenever possible ... While these internal operations are being executed, the CPU will start to fetch the next instruction's opcode (Fig. 5.1)". The model takes that overlap only where an instruction ends in register work after its last read: that work needs no tail and completes during the next fetch | Fawcett p.56-57 (PDF 67-68); TM Fig 4-3 | Maintainer decision (was: a 2-deep look-ahead queue); OPEN-hardware | time a NOP loop and a NEG; LD R,#imm; COM loop on a real C900 with `bench/c900` (kernels `nop`, `neglc`, control `ldimm`) |
| 43 | Refresh placement texts disagree. TM Mar81 8.2: "may be inserted immediately after the last clock cycle of any transaction", 8.3: "This usually means after the last clock cycle of the current transaction"; TM Jan83 8.2: "will be inserted immediately after the last clock cycle of the current bus transaction", 8.3: "usually, after the last clock cycle of the current transaction". 1988 DB p.156: "started as soon as possible (that is, after the next IF1 cycle or Internal Operation cycle)"; Fawcett p.66: "insert the refresh cycle immediately after the next IF1 machine cycle (the fetch of the first word of the next instruction) or the next internal operational cycle, whichever comes first" | TM Mar81 8-1 (PDF 232); TM Jan83 8-1 (PDF 246); 1988 DB p.156 (PDF 163); Fawcett p.66 (PDF 77) | Maintainer decision: 1988 DB and Fawcett, the machine cycle taken whole (items 35, 37); OPEN-hardware | the TM reading would put a refresh between a transaction's T3 and its tail |
| 44 | Cycle table, NS / SS / SL: IN, INB, SIN, SINB Rd,port 12 / 12 / 12; LD, LDB, CP, CPB address,#data 14 / 15 / 17 and addr(Rd),#data 15 / 15 / 18; PUSH @Rd,addr(Rs) 14 / 14 / 17; PUSHL @Rd,addr(Rs) 21 / 21 / 24; POP addr(Rd),@Rs 16 / 16 / 19; POPL addr(Rd),@Rs 23 / 23 / 26; LDM address 14+3n / 15+3n / 17+3n, addr(Rs) 15+3n / 15+3n / 18+3n. RM, TM Mar81 instruction pages, TM Mar81 Appendix C and 1988 DB agree on every figure | RM p.71, 97, 111-112, 130-131, 157, 159 (PDF 80, 106, 120-121, 139-140, 166, 168); TM Mar81 6-25, 6-51, 6-65/66, 6-84/85, 6-111, 6-113 (PDF 78, 104, 118-119, 137-138, 164, 166), C-1, C-3..C-7 (PDF 276, 278-282); 1988 DB p.136, 137, 143, 144 (PDF 143, 144, 150, 151) | FIXED (was: 1-3 clocks short or long) | `TestCycleTableMemoryForms`; every form meets its total through its machine-cycle program |
| 45 | PUSH, PUSHL @Rd,address and POP, POPL address,@Rs segmented: 1988 DB p.137 gives PUSH 14 / 14 / 16, PUSHL 21 / 21 / 23, POP 16 / 16 / 18, POPL 23 / 23 / 25; RM p.156/158 and TM Mar81 C-6 agree on PUSH and POP; TM Mar81 6-110/6-112 print SL 19 and 17 (and PUSHL address SS 13, C-6 PUSHL address NS 16) | RM p.156, 158 (PDF 165, 167); TM Mar81 6-110, 6-112 (PDF 163, 165), C-6 (PDF 281); 1988 DB p.137 (PDF 144) | FIXED (was: PUSH 14 / 15 / 17, POP 16 / 17 / 19). The tables are used; OPEN-hardware | `TestCycleTotalsMatchModel` |
| 46 | A tail is at most 4 clocks: a memory machine cycle "can be one to four clock cycles longer than the bus transaction time. These extra cycles are added after T3, but before the start of the next bus transaction" (Fawcett p.62); longer work runs in internal cycles (item 15). Through a tail /AS, /DS, /MREQ stay High, AD is released, ST, N/S, R/W, B/W hold | Fawcett p.62, p.66 (PDF 73, 77); 1988 DB p.149 (PDF 156); TM Mar81 2-4 (PDF 21) | Maintainer decision; default, unverified on silicon | `TestMachineCyclePins`. Conflict: 1988 DB p.149: "one to five clock cycles are added"; TM Mar81 2-4: a machine cycle "can extend beyond the end of a transaction by an unlimited number of clock cycles" |
| 47 | A privileged instruction in normal mode, an undefined opcode and an extended instruction with FCW EPA clear run their IF1 machine cycle, tail included, then the trap (aborted IF1, item 12); no later word is fetched. Saved PC: the next instruction, or the second word of a multiple-word privileged instruction (Fawcett Table 6.1); traps are recognised at T3 of the last machine cycle (Fawcett p.77) | Fawcett p.77, p.80 (PDF 88, 91) | FIXED (was: the whole instruction fetched first). Timing inferred; default, unverified on silicon | `TestPrivilegedTrapAtDecode`, `TestEPATrapWhenDisabled` |
| 48 | Block, string, translate and block I/O forms: 7 of the base 11 clocks run before the first element (`F1 Fn+1`), 4 after the last (`I4`, no named work); an interrupt accepted between elements ends the instruction with its own address saved, and the resumed instruction runs the 7 again: "Seven cycles should be added to this instruction's execution time for each interrupt request that is accepted" (TM 6-78, and every repeat page). Single forms take the same split. A refresh or bus request may follow any element (1988 DB p.149) | TM Mar81 6-78 (PDF 131); 1988 DB p.149 (PDF 156) | Default, unverified on silicon | `TestMachineCycleBlock`, `TestMachineCycleBlockCompare`; `make test-cpu-cycles` rows `ldir_n4` 47, `ldir_n64` 587, `lddr_n4` 47, `cpir_n3` 38, `cpir_n8` 83 |
| 49 | MULT, MULTL, DIV, DIVL with an immediate or memory operand: the table gives IM = IR = R (70, 282, 107, 744) in all three columns, and over R only DA +1 / +2 / +4 and X +2 / +2 / +5 (NS / SS / SL, the same for all four), though those forms add 3 to 9 bus clocks. The setup (MD) and the first steps (MO) run during the operand transactions, as far as the total requires; a step is never shortened | 1988 DB p.138 (PDF 145) | Default, unverified on silicon: the totals imply it, no source describes it | `TestArithmeticSpecGapMemOperand`, `TestSequencerStepsOnCycleBoundaries`; a `bench/c900` MULT/DIV memory-operand kernel would settle it |
| 50 | Sequencer cadence: one step per internal cycle, the step's work on its last clock. MULT: setup 3, 16 steps of 4; MULTL: setup 4, 32 steps of 8, one 7-clock add per 1 bit (item 32), finish 19; DIV: setup 2, trial 6, 16 steps of 6; DIVL: setup 2, trial 67, 32 steps of 21; shifts by count: one 3-clock internal cycle per position, a count of 0 as 1 (TM 6-130). The totals (MULT 70, MULTL 282+7n, DIV 107, DIVL 744, shifts 13+3n / 15+3n) are cited; the step lengths are not | 1988 DB p.138 (PDF 145) | Default, unverified on silicon | `TestMachineCycleSequenced`, `TestSequencerStepsOnCycleBoundaries`; serial vectors (`make test-serial`) |
| 51 | CALL @Rd segmented: 15. TM Mar81 6-18 prints one segmented figure, 15; Fawcett Table 8.9: IR "10 - 15"; 1988 DB p.139: 10 / 15 / 15. TM Mar81 C-1's 10 / 10 / 15 differs only in which column carries it | TM Mar81 6-18 (PDF 71), C-1 (PDF 276); Fawcett p.138 Table 8.9 (PDF 149); 1988 DB p.139 (PDF 146) | CONFIRMED (was: OPEN-hardware) | `TestCycleTotalsMatchModel` |
| 52 | Extended-instruction templates: bit 3 of the first word's direction field (bits 3:2) selects a CPU write cycle in every template: memory 01 = EPU <- memory, 11 = memory <- EPU; registers 00 = CPU <- EPU, 10 = EPU <- CPU; flags 00 = FCW <- EPU, 10 = EPU <- FCW, 01 = internal | TM Mar81 6-167..6-170 (PDF 220-223) | CONFIRMED for the listed encodings. Memory 00/10 and flags 11 are unlisted: the model applies the same bit (flags 11 as internal), an interpretation (maintainer decision) | `TestEPADirections` |

## Go model behaviour to mirror in RTL

- T3 falls through: read data is captured at the T3 opening edge, the
  sequencer's post-transaction step runs on that edge, and the strobes
  trail (busTrail) to the next edge, which may be the next T1 (Fig 19).
  RTL: bus_done at the T3 opening edge, strobes released one edge later
  unless a new T1 overrides.
- Every instruction runs its machine-cycle program (`mcTick`; generated
  by `cycle_program.go`, spec in the Go model's docs/MACHINE_CYCLES.md):
  one /AS per machine cycle, tails hold the bus outputs, internal cycles
  per item 15.
- BUSREQ and refresh go in only between whole machine cycles
  (`mcMidCycle` is true through a tail and through TSET's read-to-write).
- STOP: `stopArmed` at the fetch launch; `stopStream` runs the refresh
  stream after the IF1's T3, and the IF1's tail follows it (item 18).
- HALT: `F1+2`, then 3-clock internal cycles; interrupt T3 samples count
  in `haltIntSamples`.
- Refresh transactions keep R/W, B/W and N/S from the previous
  transaction (`driveT1Outputs` skips them for ST=0001). SN is driven:
  segment 0 in segmented mode, the PC segment in nonsegmented mode on
  the Z8001/Z8003 (`adjustAddrNonSeg`).
- Refresh insertion: a pending refresh opens on the clock after the
  current machine cycle ends, tail included, and takes three clocks; the
  instruction's next machine cycle follows it.
