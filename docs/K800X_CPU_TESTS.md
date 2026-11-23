# k800x_cpu (Z8001/2/3/4) -- tests

## Scope

RTL `rtl/k800x_cpu` (one core; `SEGMENTED`/`VMPU` pick the variant);
harnesses `tb/k800x_cpu`; vectors `vectors/k800x_cpu`; vector format
docs/VECTOR_FORMAT.md.

| vectors | files | bench |
|---|---|---|
| `cpu/` | 3078 (1298 Z8001, 1758 Z8002, 7 Z8003, 15 Z8004; 264 named `Unknown`) | `tb/k800x_cpu/tb_cpu.cpp` |
| `alu/`, `alu_from_cpu/` | 17, 433 | `tb_alu.sv` |
| `decode/decode.vec` | 1 | `tb_decode.sv` |
| `serial/random.vec` | 1 | `tb_serial.sv` |
| `cycles/cycles.vec`, `cycles/cycles_z8001.vec` | 2 (Z8002; Z8001 segmented) | `tb_cpu_cycles.sv` |
| `silicon/z8001.vec`, `silicon/z8001-seg.vec` | 2 (1202 and 1072 programs captured on a Z8001, non-segmented and segmented) | `tb_silicon.sv` |

Sources (printed page numbers of the 1988 Z8000 Family Data Book,
`1988_Zilog_Z8000_Family_Data_Book.pdf`; PDF page = printed + 7 in the
Z8001/2 spec, also `z8001_cpu.pdf`): Product Spec "Z8000 CPU Timing"
pp.149-157 (Fig 12 memory read/write, Fig 13 I/O, Fig 14 interrupt and
segment-trap acknowledge, Fig 15 bus request/acknowledge, Fig 16 STOP, Fig
17 internal operation, Fig 18 refresh, Fig 19 reset), AC Characteristics
pp.159-161; Z8000 CPU Reference Manual 1982 (`Z8000_CPUrefMan_1982.pdf`,
PDF page = printed + 9) chapter 9 pp.229-241 (Figs 9.2-9.11, Table 9-1)
and 7.4/7.6; TM = Z8000 CPU Technical Manual (`Z8000Tech.pdf`, Mar81 and
Jan83 editions); Data Manual 1980; Fawcett, "Z8000 Microprocessor: A
Design Handbook" (1982).

## How to run

```
make lint               # verilator -Wall on every RTL module
make test-cpu           # replay every cpu/ vector on its variant's build
make test-cpu-combined  # the same, CLK rise and fall in one master clock; pairs of 1, 2 and 1,2,1,3 master clocks
make cpu ONLY=TestNOP [VCD=1]   # one vector with full divergence context
make ladder             # cpu/ vectors shortest-first with PASS/FAIL
make test-cpu-timing    # Z-Bus monitor against the AC table (docs/TIMING_TESTS.md)
make test-cpu-cycles    # instruction cycle counts against TM Mar81 sec 6.7
make test-cpu-late-read # memory and I/O drive read data only between T3's rise and fall
make test-decode        # the decode ROM against decode.vec
make test-decode-table  # the decode ROM against z8000_decode_table.txt
make test-mc-table      # the machine-cycle ROM against z8000_mc_table.txt
make test-alu | test-regfile | test-serial | test-refresh | test-seq-words | test-seq-paths | test-cond
make test-cpu-silicon   # programs captured on a physical Z8001
```

`tb_cpu` takes `--mclk P` / `K8000_MCLK` (comma list of master clocks per
record, cycled; default `1,2,1,3`) and `--combined` / `K8000_COMBINED=1`.
Results land in `results/cpu.txt` and `results/cpu_combined.txt`
(`cpu_combined_mclkP.txt` for the other combined patterns).

### Reviewing the ROM tables

Decoder changes are made in `rtl/k800x_cpu/z8000_decode_table.txt`, then
`make gen`: the ROM (`gen/z8000_decode_rom_gen.sv`, 1649 lines of 69-bit hex) as 478
control words with non-default fields named (`alu_op=OP_SUB
width=WIDTH_BYTE src2=SRC_IMM ...`) over 8417 range records. Kept
honest by:

* `make test-decode-table`, which checks the ROM against every range
  (1048576 checks). A `-` in the w1 column claims word 2's low nibble is
  irrelevant, so all 16 nibbles are checked.

The decoder gives no instruction length: each instruction's machine-cycle
program does. Program changes are reviewed in
`rtl/k800x_cpu/z8000_mc_table.txt` (the source of
`gen/z8000_mc_rom_gen.sv`): 434 forms (first word, a block form's second
word), 206 programs over the NS/SS/SL columns and the default, not-taken
and zero paths, each program's text above its entries. `make
test-mc-table` checks the ROM against every table record (1053342 checks).

### Reading the vectors: CLK edges

State advances on the CLK rise. The strobes the AC table times from the
CLK fall change on the CLK = 0 record (1988 DB PDF p.47-48): /AS rise
(#26), /MREQ fall and rise (#18, #23), DS(write) and DS(I/O) fall (#39,
#42), /DS rise (#34). WAIT and STOP are sampled on the fall (#60, #62) and
acted on at the next rise. Read data is taken as CLK falls in T3 (#12,
ledger 24). Per half clock (value just after the edge):

| edge | AS | MREQ (memory/refresh) | DS read | DS write | DS I/O | DS INTACK | AD |
|------|----|-----------------------|---------|----------|--------|-----------|----|
| T1 rise | 0 | 1 | 1 | 1 | 1 | 1 | address (driven) |
| T1 fall | 1 | 0 | 1 | 1 | 1 | 1 | address |
| T2 rise | 1 | 0 | 0 | 1 | 1 | 1 | read: released; write: data |
| T2 fall | 1 | 0 | 0 | 0 | 0 | 1 | as T2 rise; WAIT sampled |
| TWA / TW | 1 | 0 | 0 | 0 | 0 | 0 from the 4th TWA rise | as T2 |
| T3 rise | 1 | 0 | 0 | 0 | 0 | 0 | read data on AD |
| T3 fall | 1 | 1 | 1 | 1 | 1 | 1 | read data captured (the T3 rise record's AD); write: data still driven |
| next rise | (T1 of the next cycle may start here) | 1 | 1 | 1 | 1 | 1 | released / next address |

A record's inputs are those after its edge, so the word as CLK falls is
the T3 rise record's AD; the T3 fall record may already show memory
released. A vector that ends on the rise opening a read's T3 gets that
fall, inputs held, before its final state is read.

### Tolerances in tb_cpu

* SN compared only while /AS is Low (ledger 21).
* Refresh: only AD[8:0] compared (ledger 14).
* Internal operation (ST = 0000): AD and B/W not compared (ledger 15).
* /AS Low on ST 0100-0111 and 1110: AD not compared (ledger 28).

## What is covered

`make test-cpu`: 3078 of 3078 PASS, 0 SKIP. `make test-decode-table`,
`make test-mc-table` and `make test-cpu-cycles` pass. `make
test-cpu-silicon`: 1202 of 1202 and 1072 of 1072.

### Silicon vectors

Programs run on a physical Z8001 (Z8001APS) by the z8000_test suite
(Salvatore Paxia, MIT; `vectors/k800x_cpu/silicon/LICENSE`), converted by
`python3 -I tools/silicon_vectors.py SUITE`. `tb_silicon.sv` is the
capture rig: 8 KiB RAM on {SN0, AD11:0}, I/O ports 0x0100-0x010F as twelve
word registers kept from test to test, 0xFFFF elsewhere, no waits. Each
test loads the rig's bootstrap, its registers and memory and its code at
0x0200, runs to the HALT fetch, and checks what the bootstrap's dump
routine stored: R0-R15, the FCW, the observed memory and I/O registers.
Where the rig recorded a bus trace (177 non-segmented tests, and the
odd-port I/O tests in both modes) it also checks every /DS-completed
cycle from the test's first word to the dump routine's IF1 (address,
data, R/W, B/W, I/O, and SN0 and status where recorded) and the CLK rises
in that window (`F ICC`). Traces from the first segmented rig build are
not used: its B/W and clock counts are wrong.

One mask, a known difference: a DIV/DIVL quotient overflow (case 3)
leaves destination and S uncompared. The chip gives 0001/FFFD with S set
for 0x0001FFFE / 0xFFFF (`sys_div_rr_r_large`), the RTL 0004/FFF3 with S
clear; no reading of the RTL's divide steps yields the chip's words. The
suite's own mask file names no field. 848 coverage tests are not
converted: the suite assembles them, and no assembler listing in the
suite confirms their words; eleven more are converted on a hand check of
their words against the manual's formats (`silicon/dropped.txt`). With
all of them included every one of the 3122 tests passes.

Where silicon fills or overrides the manual, the RTL follows it
(DECISIONS rows tagged silicon). `tools/update_cpu_vectors.py` applied
each such change to the older vectors (cpu, cpu+fpu system, serial, ALU);
four translate vectors needed `--inferred`, the RTL's reading where no
capture covers a repeat with its pointer in R1.

### Bus behaviour the vectors encode

- T3 falls through: read data is captured as CLK falls in T3, the
  sequencer's post-transaction step runs then, and the strobes release on
  the next edge, which may be the next T1 (Fig 19).
- Every instruction runs its machine-cycle program: one /AS per machine
  cycle, tails hold the bus outputs, internal cycles per ledger 15.
- BUSREQ is sampled at each T1 and the bus given up after that T3, the
  tail running on; no grant inside TSET's read-to-write. Refresh goes in
  only between whole machine cycles.
- STOP: the refresh stream runs after the IF1's T3, and the IF1's tail
  follows it (ledger 18).
- HALT: a 5-clock IF1, then 3-clock internal cycles; interrupt T3 samples
  counted for the two-sample exit.
- Refresh keeps R/W, B/W and N/S from the previous transaction. SN is
  segment 0 in segmented mode and the PC segment in nonsegmented mode on
  the Z8001/Z8003.
- A pending refresh opens on the clock after the current machine cycle
  ends, tail included, and takes three clocks.
- Skipped refreshes: an underflow on a granted or wait clock marks the
  refreshes owed; they follow any machine cycle, back to back. A
  refresh's T3 leaves the read data and its byte lane alone.

### Spec conformance ledger

Verdicts: SPEC = the sources settle it and the vectors follow it;
CONFLICT = the sources disagree, the reading taken is named; INFERRED =
derived from totals or figures, unverified on silicon; OPEN = the sources
are silent, the reading taken is stated. The last column names the
vectors (`<TestName>.*.vec`) or the tb_cpu tolerance.

| # | item | source | verdict | vectors / note |
|---|---|---|---|---|
| 1 | Reset pin state: AD 3-stated; AS, DS, MREQ, ST0-3, BUSACK, MO high; SN low; R/W, B/W, N/S "not affected" | PS "Reset" p.156 + Fig 19 p.157; RM 7.4 p.220, 9.7 p.241 | SPEC | TestResetPinState. During reset N/S Low, R/W High, B/W Low (undefined in silicon) |
| 2 | Reset reads start on the 3rd rising edge after RESET rises; three (Z8001) / two (Z8002) back-to-back 3-clock reads at 0002/0004/0006 with ST = 1100 ("IFn" in Fig 19), system mode | Fig 19; PS p.156 | SPEC | TestResetSequenceZ8002, TestResetReadStatusCodes |
| 3 | Memory read: /AS Low from T1's rise to its fall; MREQ Low from T1's fall, DS from T2's rise, both through T3 and released on T3's fall (TwDSR = TcC+TwCh-80 ns, TwMRh = TcC-40 ns) | Fig 12 p.150; AC 18/19/23/24/26/34/37/38 (1988 DB PDF p.47) | SPEC | TestBusTimingMemoryRead; every read vector |
| 4 | Memory write: data driven from the T2 rise to the end of T3 (TdC(DW), TdDS(DW)); DS(write) Low from T2's fall to T3's (TdC(DSW), TwDSW = TcC-65 ns) | Fig 12; AC 14/16/21/35/39/40 | SPEC | TestBusSpec_MemoryWriteStrobes, TestBusTimingMemoryWrite |
| 5 | Byte memory writes put the same byte on both halves of AD | RM 9.4.2 p.234 | SPEC | TestBusSpec_ByteWriteDuplicatesData |
| 6 | Byte I/O as byte memory: a write puts the byte on both halves of AD; a read takes AD15:8 for an even port, AD7:0 for an odd one, in both classes and the block forms | TM Jan83 9.4.3 p.9-6; Fawcett p.53, Fig 4.3; TM Mar81 9.4.3 p.9-6 (lanes by class on the ports it allows) | SPEC | TestIOByte_*, TestBlockIOByte_* (Z8002 and segmented Z8001) |
| 7 | I/O cycle: T1, T2, TWA, T3; DS falls on T2's fall and rises on T3's (TwDS = 2TcC-90 ns); MREQ High; N/S Low; port address at T1 | Fig 13 p.151; AC 42/43; TM Jan83 Fig 9-5 | SPEC | TestBusSpec_IOCycleDS, TestIOCycleAutoWait |
| 8 | WAIT sampled on the T2 falling edge (again mid-TW), acted on at the next rise; one clock added per Low sample; no control output changes during TW | PS p.150; RM 9.4.1 p.232; AC 62/63 | SPEC | TestBusSpec_WaitSampledAtEndOfT2, TestIOWaitAfterDSFall; ABORT (Z8003/4) moves with it |
| 9 | INTACK: T1, T2, five automatic waits, T3; DS falls just after the edge opening the 4th automatic wait (TdAS(DSA) min = 4TcC+TwCl-40 ns after AS rise; TdC(DSA) from clock rise) and stays Low through T3 (identifier sampled at the T3 falling edge, TdDSA(DR)) | Fig 14 p.152; AC 44/45/46 p.160; RM 9.4.5 p.236 | SPEC | TestINTACKDSLateFall |
| 10 | INTACK WAIT sampled in two places: before the DS fall (delays it) and before the identifier read | RM 9.4.5 p.236 | SPEC | TestBusSpec_INTACKWaitPlaces |
| 11 | INTACK length: 10 clocks, T4 and T5 after T3 inside the acknowledge cycle. Fawcett p.91: "T4 and T5 clock periods are appended to this transaction ... the interrupt acknowledge machine cycle is always at least 10 clock cycles long"; Table 6.3: "Interrupt acknowledge cycle 10"; TM Mar81 Fig 9-6 and 1988 DB Fig 14 label T3, T4, T5 inside the acknowledge cycle | Fawcett p.91, p.93 (PDF 102, 104); TM Mar81 9-8 Fig 9-6 (PDF 243); 1988 DB p.152 Fig 14 (PDF 159) | CONFLICT | TestMachineCycleEntry, TestMachineCycleEntryZ8002. TM Mar81 9-8 and RM 9.4.5 p.236 text: "eight clock cycles long at a minimum". Fawcett and the figures are followed |
| 12 | Aborted IF1 before INTACK runs in the interrupted program's mode; the mode switch happens after it. It is 7 clocks of /AS and IF1 status only: /DS and /MREQ stay High, AD is released after T1, nothing is read. Fawcett p.90: "All of the proper address and status information for the next instruction fetch will appear in T1, and the AS is pulsed. However, no active DS signal is generated, the instruction is never read from memory, and the PC is not updated. The CPU spends seven clock periods in this abandoned instruction fetch cycle". Fawcett Fig 6.9, 1988 DB Fig 14, TM Mar81 Fig 9-6 and 1985 DB Z8003/4 Fig 15 draw only /AS, R/W, B/W and ST in it. Internal traps (privileged instruction, extended instruction, SC) run the same cycle with the mode switch after it: Fawcett p.92, internal traps take "10 fewer clocks; the timing is similar except that the interrupt acknowledge cycle is not included", and 10 is the acknowledge | PS p.152 ("the subsequent IF1 cycle is exercised, but ignored. The internal state of the CPU is not altered ... After the acknowledge cycle, the N/S output indicates the automatic change to system mode"); Fawcett p.89 Fig 6.9, p.90, p.92 (PDF 100, 101, 103); TM Mar81 9-8 Fig 9-6 (PDF 243); 1985 DB p.455 Fig 15 (PDF 464) | SPEC; traps INFERRED | TestBusSpec_AbortedIF1RunsInProgramMode, TestAbortedIF1NoData, TestMachineCycleTrapZ8001Nonseg, TestSC_SetsIrqSyscall. Conflict: Fawcett Fig 6.13 (p.95, PDF 106) draws /MREQ and /DS falling in the IF1 that follows a HALT wake sample |
| 13 | N/S during the acknowledge cycle | RM 9.4.5 "The N/S line indicates system mode (Low)" vs PS p.152 "after the acknowledge cycle" | OPEN | Low (RM explicit) |
| 14 | Refresh: ST = 0001, AS pulse, MREQ Low T2-T3, DS never Low, ROW on AD0-8 (AD0 = 0), AD9-15 undefined; R/W, B/W, N/S same as the previous transaction | Fig 18 p.156; RM 9.4.6 p.237 | SPEC | TestBusSpec_RefreshKeepsRWBWNS, TestBusSpec_RefreshAfterByteWrite; tb compares only AD[8:0] on refresh |
| 15 | Internal operation: ST = 0000, AS pulse opening each cycle, MREQ/DS High, AD undefined, B/W undefined, N/S same as previous; 3 to 8 clocks ("An internal operation can extend up to a maximum of eight clock periods", Fawcett p.66; "three to eight clock cycles long", 1988 DB p.155). Internal cycles appear only where an instruction's machine-cycle program names them | Fig 17 p.155; RM 9.4.6; Fawcett p.66 (PDF 77); 1988 DB p.155 (PDF 162) | SPEC | tb does not compare AD or B/W while ST = 0000 |
| 16 | HALT: 5-clock IF1, then 3-clock internal operations interspersed with refresh; interrupts sampled at the beginning of every T3; after two consecutive active samples the 7-clock aborted IF1, then the 10-clock acknowledge | Fawcett p.96 (PDF 107): "a five-clock instruction fetch cycle, followed by successive three-clock-period internal cycles", Fig 6.13 p.95 (PDF 106); PS "HALT" p.155 ("If an input is found active during two consecutive samples, the subsequent IF1 cycle is exercised, but ignored, and the normal interrupt acknowledge cycle is started"); Fawcett p.93 Table 6.3 (PDF 104) | SPEC | TestBusSpec_HaltInternalOpsAndTwoSampleExit, TestMachineCycleHalt, TestG78_8_RefreshContinuesDuringHalt |
| 17 | STOP sampled on the falling edge before an IF1 / before an EPA second word; the fetch runs, then a refresh stream after its T3, STOP re-sampled on each T3 fall (the IF1's, then each refresh's); when found High the next refresh completes and the CPU continues; ROW += 2 per cycle, prescaler bypassed | Fig 16 p.154 + text; RM 9.6.4 p.240-241 | SPEC | TestSTOPStallsAndResumes, TestSTOPStreamShape, TestSTOPSampledOnT3Fall, TestSTOPBeforeEPAWord2, TestStopAtIF1Z8001, TestStopShortReg, TestStopShortRegFlags (a three or four clock register instruction runs once, after the stream; streams of 1 and 3), TestStopShortRegEvents (with /WAIT in the IF1, a refresh owed, /BUSREQ, NMI or NVI), TestStopSerial (MULT, MULTL, DIV, DIVL from a register, immediate, address or @R, and shifts: the unit runs as without STOP, 3 clocks later per refresh); the CPU+FPU system vectors (/BSY to STOP) |
| 18 | STOP: the refresh stream goes in after the IF1's T3 and the IF1's remaining clocks follow the last stream refresh. TM 9.6.4: "a stream of memory refresh cycles is inserted after the third clock cycle in the instruction fetch"; Fig 9-10 shows the IF1's T4, T5 after the stream. The only refresh placed between T3 and a tail (item 35) | TM Mar81 9-12 Fig 9-10 (PDF 247); Fig 16 | SPEC | TestMachineCycleRefresh, TestSTOPStreamShape |
| 19 | BUSREQ sampled at the rising edge opening each machine cycle's T1; if Low, BUSACK Low (bus outputs floated) right after that cycle's T3: "the CPU will relinquish the bus at the end of the bus transaction in that cycle (in other words, immediately after T3)". The cycle's later clocks (tail, internal operation past its third clock, acknowledge T4/T5) run on during the grant; the next cycle waits for the bus. TSET does not grant between its read and its write on every variant: "BUSRQ is not honored in the time between loading the destination from memory and storing the destination to memory" | Fawcett PDF p.114 (printed 103); TM Jan83 p.262-263 Fig 9-9; DB 1988 p.41 Fig 15; TM Mar81 6-163 (PDF 216) | CONFLICT | TestBusRequestTail, TestBusRequestInternal, TestBusRequestAcknowledge, TestBusRequestRefresh, TestBusRequestTSET, TestBusRequestSampledAtT1, TestMachineCycleBusRequest, TestBusSpec_BusRequestTiming, TestTSETBusReqNotGranted. An internal operation's transaction taken as its first three clocks (TM Fig 9-7, Fawcett Fig 5.8): interpretation. TM p.262 and DB p.41 text say BUSACK after the whole machine cycle; Fawcett's worked acknowledge (8 of 10 clocks) is followed |
| 20 | BUSREQ release: sampled High at edge P, BUSACK High at P+1, CPU regains the bus two clocks after BUSREQ rises (P+2) | PS p.153; RM 9.6.2 p.240 | SPEC; OPEN by one clock | TestBusSpec_BusRequestTiming. Fig 15's AD row hints at a T1 at P+3, its AS row shows none; the text's "two clock cycles" is encoded |
| 21 | SN valid about one clock before the address (TdC(SNv) 130 ns after a clock rise), may change from TdC(SNn) after the T2 rise | PS p.150; AC 6/7 | OPEN | the vectors drive SN with the address at T1; the RTL drives it on the fall in the clock before T1, in time for the Z8010's SN sample at the T1 rise (#18). tb compares SN only while AS is Low |
| 22 | Status, B/W, N/S valid early in T1 and stable through T3 (TdC(S), TdDS(S)); "same as previous cycle" between transactions and after a bus grant | Fig 12/15 | SPEC | the last values hold between transactions |
| 23 | Interrupt request sampling while running: VI/NVI/SEGT levels and the NMI latch sampled at T3 of the last machine cycle of the instruction (the third clock of an internal cycle); the aborted IF1 starts after that whole cycle, tail included. Fawcett p.90: "sampled at the beginning of T3 of the last machine cycle"; 1988 DB p.152: "at the end of T2 in the last machine cycle", the same instant | Fawcett p.77, p.90 (PDF 88, 101); 1988 DB p.152 (PDF 159); TM Mar81 9-11 (PDF 246) | CONFLICT; INFERRED | TestMachineCycleInterruptSample. TM Mar81 9.6.1: "At the beginning of the last clock cycle in the last machine cycle"; they differ only when that cycle has a tail |
| 24 | Data sample point: the T3 CLK fall, #12 TsDR(C) "Read Data to Clock ↓ Setup time" 20/10 ns, #15 ThDR(DS) "Read Data to DS ↑ Hold Time" 0. The RTL takes AD as CLK falls in T3: AD in the master clock before the fall's pulse, the vectors' T3 rise record. With CLK rise and fall in one master clock that is the T3 rise's master clock | 1988 DB PDF p.47 (printed 40) #12, #15; Fig 12 | SPEC | tb_cpu_late_read (memory and I/O drive the word only after the T3 rise: fetches, operands, I/O, the VI acknowledge, a read with two waits) |
| 25 | Chained T3/T1: a transaction's T1 never shares a clock with the previous T3 (3-clock cycles back-to-back) | Fig 19; RM 9.4.2 | SPEC | all back-to-back vectors, including the STOP stream and the VMPU abort re-fetch |
| 26 | Z8003/4 ABORT sampled at T2 and each Tw with WAIT | 1985 DB p.448 Fig 7 | SPEC | TestAbort* |
| 27 | Refresh prescaler CLK/4, row +2, RE bit; a write loads bits 15:1 (bit 0 stays 0, AD0 Low even on the first refresh after it); refresh after the whole IF1 or internal machine cycle (tail included), and in HALT | PS Fig 4 p.133, p.149, p.155, p.156; Fawcett p.66 (PDF 77); TM 6-74, 6-76 | SPEC | TestRefresh*, TestMachineCycleRefresh; items 35, 36, 43 |
| 28 | INTACK/EPU-transfer cycles are addressless: AD undefined in T1 | Fig 14 (AD blob then float); RM 9.4.4/9.4.5 | SPEC | tb does not compare AD while AS is Low on ST 0100-0111 and 1110 |
| 29 | Flags listed as Unaffected keep their value: word ADD/ADC/SUB/SBC/CP/CPL, CPB and INC/DEC leave D, H; word AND/OR/XOR/COM/TEST leave P/V | RM p.57, 58, 60, 67, 69, 87, 98, 146, 172, 190, 193, 211 | SPEC | TestFlagsUnaffected |
| 30 | CPSI/CPSD and repeats compare dst - src; block compares leave D, H | RM p.72-83, example p.78 | CONFLICT | TestCompareStringOperandOrder, TestCPS_StringCompare. Data Manual 1980 CPSD p.112, CPSDR p.114, CPSI p.116, CPSIR p.118 (PDF 116, 118, 120, 122) give "C: Undefined" and "S: Undefined"; RM CPSD p.78, CPSDR p.79 (PDF 87, 88) and TM Jan83 CPSDR 6-37, CPSI 6-39 (PDF 96, 98) define them: "C: Cleared if there is a carry from the most significant bit of the result of the comparison; set otherwise, indicating a \"borrow\"", "S: Set if the result of the comparison is negative; cleared otherwise". RM and TM are followed |
| 31 | DIV/DIVL quotient of exactly -2^16 / -2^32 is case 4 (low half stored, C, V, S set) | RM p.89 | SPEC | TestArithmeticSpecGap |
| 32 | MULTL +7n: n counts the ones in the absolute value of the multiplicand's low 16 bits, read as a signed word: "n = number of bits equal to one in the absolute value of the low-order 16 bits of the destination operand" | RM p.141 (PDF 150); TM Jan83 6-99 (PDF 158); TM Mar81 6-95 (PDF 148), C-5 (PDF 280); 1988 DB p.138 (PDF 145); Fawcett p.129 (PDF 140) | CONFLICT | TestArithmeticSpecGap. 1988 DB and Fawcett say "Plus seven cycles for each 1 in the multiplicand" (no absolute value); TM Mar81 6-95 prints "the low-order table 32 bits of the destination operand", its C-5 "the absolute value of the low order 16 bits of the multiplicand". RM is followed |
| 33 | DIV case 4 time: Note 2 shortens "overflow conditions" (-82 word, -693 long), and overflow (V set, C clear) is case 3; case 4 sets V and C | Jan83 p.6-47, p.6-49 (PDF p.106, p.108) | SPEC | case 4 runs as a normal divide, 107 / 744; TestArithmeticSpecGap, TestMulDivPath_Wide |
| 34 | Z8001 reset reads FCW, PC segment and PC offset from segment 0, even when the loaded FCW has SEG = 0. TM Jan83: "the first cycle reads the FCW from Location 0002 in segment number 0. The second cycle reads the PC segment number value from locations 0004 and the third cycle reads the PC offset value from location 0006 in segment number 0"; Fawcett: "the starting FCW is fetched from segment 0, location 2, the segment number for the initial PC value is fetched from segment 0, location 4, and the PC's offset is fetched from segment 0, location 6"; Data Manual 1980: "a 4-word program status is fetched from segment 0, offset 0 for the segmented Z8000". RM 7.4 forces SN0-SN6 Low while RESET is Low | TM Jan83 7-3 (PDF 240); Fawcett p.98 (PDF 109); Data Manual 1980 1.6.6 p.44 (PDF 48); RM 7.4 p.220 (PDF 229) | CONFLICT | TestResetReadsSegmentZero. RM 7.4 p.220 says the Z8001's first cycle reads the FCW from 0002 and "the next reads the PC from location 0004", with no separate segment word; 1988 DB p.156 (PDF 163) and TM Jan83 7-3 read the segment number from 0004 and the offset from 0006. The DB and TM are followed |
| 35 | Refresh placement: a pending refresh goes in after the whole IF1 or internal machine cycle, tail included, never between T3 and a tail (STOP excepted, item 18). Fawcett p.66: "immediately after the next IF1 machine cycle ... or the next internal operational cycle, whichever comes first"; 1988 DB p.155: "refresh cycles can be inserted at the end of any internal machine cycle". Block and repeat forms take one after an element (1988 DB p.149 lists "all Block Move instructions") | PS p.149, p.155, p.156; Fawcett p.66 (PDF 77); 1988 DB p.149, p.155 (PDF 156, 162) | CONFLICT (item 43) | TestMachineCycleRefresh, TestRefreshDeferredToInstructionBoundary, TestMachineCycleBlock |
| 36 | Refresh cost: three T-states wherever it goes in (after an IF1 or internal cycle, after a block element, in HALT); it sits between two machine cycles and leaves the instruction's cycles unchanged | PS p.155, p.156 | SPEC | TestRefreshCostsThreeClocks |
| 37 | Refresh after the aborted IF1 of an interrupt, trap or HALT wake: a refresh pending by its T3 goes in after that whole 7-clock cycle, three clocks, ahead of the acknowledge or the status pushes. TM sec 8.3: "If the CPU receives a trap or an interrupt simultaneously with a Periodic Refresh request, the refresh operation is performed first."; 1988 DB p.149: "can be inserted just after the completion of any first instruction fetch (IF1) cycle" | TM Mar81 8-1 (PDF 232); TM Jan83 8-1 (PDF 246); 1988 DB p.149 (PDF 156); Fawcett p.92 (PDF 103) | SPEC | TestRefreshAtIgnoredIF1BeforeINTACK, TestMachineCycleEntry |
| 38 | Refresh pending while a STOP stream runs: the stream does not satisfy it, so one more refresh follows release | 1988 DB p.156 | OPEN | cost is still three clocks |
| 39 | WAIT stretches a refresh cycle at its T3 sample; p.149 lists only memory, I/O and acknowledge cycles as WAIT-extendable | 1988 DB p.149, Fig 18 | OPEN | stretched |
| 40 | WAIT on an IF1: the wait clocks lengthen the IF1 machine cycle and so the instruction; its internal clocks are unchanged | PS Fig 12; Fawcett p.58, p.125 (counts assume no wait states) | SPEC | TestWaitOnIF1LengthensInstruction |
| 41 | Cycle tables are back-to-back throughput reached by the instruction's own machine cycles: a machine cycle runs "from the start of one bus transaction to the start of the next" and "all instructions are executed with combinations of these four basic machine cycles" (Fawcett p.58); the times "are calculated assuming that there are no externally-generated wait states" (Fawcett p.125). Every clock of a total sits in a tail or an internal cycle of that instruction; a wait lengthens the cycle it lands in | Fawcett p.58, p.125 (PDF 69, 136) | INFERRED | TestCycleAudit*, `make test-cpu-cycles`. Fawcett's DIV R example (5 + 6 + 6 + 7 = 24) does not reach the table's 107 |
| 42 | No look-ahead: each instruction fetches only its own words, and the next IF1 starts after its last machine cycle. Fawcett p.56: "the execution of an instruction is overlapped with the fetch of the next instruction whenever possible ... While these internal operations are being executed, the CPU will start to fetch the next instruction's opcode (Fig. 5.1)". The overlap is taken only where an instruction ends in register work after its last read: that work needs no tail and completes during the next fetch | Fawcett p.56-57 (PDF 67-68); TM Fig 4-3 | INFERRED; needs silicon | timing a NOP loop, NEG, LD R,#imm and COM loop on a real CPU would settle it |
| 43 | Refresh placement texts disagree. TM Mar81 8.2: "may be inserted immediately after the last clock cycle of any transaction", 8.3: "This usually means after the last clock cycle of the current transaction"; TM Jan83 8.2: "will be inserted immediately after the last clock cycle of the current bus transaction", 8.3: "usually, after the last clock cycle of the current transaction". 1988 DB p.156: "started as soon as possible (that is, after the next IF1 cycle or Internal Operation cycle)"; Fawcett p.66: "insert the refresh cycle immediately after the next IF1 machine cycle (the fetch of the first word of the next instruction) or the next internal operational cycle, whichever comes first" | TM Mar81 8-1 (PDF 232); TM Jan83 8-1 (PDF 246); 1988 DB p.156 (PDF 163); Fawcett p.66 (PDF 77) | CONFLICT; needs silicon | 1988 DB and Fawcett followed, the machine cycle taken whole (items 35, 37); the TM reading would put a refresh between a transaction's T3 and its tail |
| 44 | Cycle table, NS / SS / SL: IN, INB, SIN, SINB Rd,port 12 / 12 / 12; LD, LDB, CP, CPB address,#data 14 / 15 / 17 and addr(Rd),#data 15 / 15 / 18; PUSH @Rd,addr(Rs) 14 / 14 / 17; PUSHL @Rd,addr(Rs) 21 / 21 / 24; POP addr(Rd),@Rs 16 / 16 / 19; POPL addr(Rd),@Rs 23 / 23 / 26; LDM address 14+3n / 15+3n / 17+3n, addr(Rs) 15+3n / 15+3n / 18+3n. RM, TM Mar81 instruction pages, TM Mar81 Appendix C and 1988 DB agree on every figure | RM p.71, 97, 111-112, 130-131, 157, 159 (PDF 80, 106, 120-121, 139-140, 166, 168); TM Mar81 6-25, 6-51, 6-65/66, 6-84/85, 6-111, 6-113 (PDF 78, 104, 118-119, 137-138, 164, 166), C-1, C-3..C-7 (PDF 276, 278-282); 1988 DB p.136, 137, 143, 144 (PDF 143, 144, 150, 151) | SPEC | TestCycleTableMemoryForms; every form meets its total through its machine-cycle program |
| 45 | PUSH, PUSHL @Rd,address and POP, POPL address,@Rs segmented: 1988 DB p.137 gives PUSH 14 / 14 / 16, PUSHL 21 / 21 / 23, POP 16 / 16 / 18, POPL 23 / 23 / 25; RM p.156/158 and TM Mar81 C-6 agree on PUSH and POP; TM Mar81 6-110/6-112 print SL 19 and 17 (and PUSHL address SS 13, C-6 PUSHL address NS 16) | RM p.156, 158 (PDF 165, 167); TM Mar81 6-110, 6-112 (PDF 163, 165), C-6 (PDF 281); 1988 DB p.137 (PDF 144) | CONFLICT; needs silicon | the tables are followed; `make test-cpu-cycles` |
| 46 | A tail is at most 4 clocks: a memory machine cycle "can be one to four clock cycles longer than the bus transaction time. These extra cycles are added after T3, but before the start of the next bus transaction" (Fawcett p.62); longer work runs in internal cycles (item 15). Through a tail /AS, /DS, /MREQ stay High, AD is released, ST, N/S, R/W, B/W hold | Fawcett p.62, p.66 (PDF 73, 77); 1988 DB p.149 (PDF 156); TM Mar81 2-4 (PDF 21) | CONFLICT; INFERRED | TestMachineCycleMREQ. 1988 DB p.149: "one to five clock cycles are added"; TM Mar81 2-4: a machine cycle "can extend beyond the end of a transaction by an unlimited number of clock cycles" |
| 47 | A privileged instruction in normal mode and an extended instruction with FCW EPA clear run their IF1 machine cycle, tail included, then the trap (aborted IF1, item 12); no later word is fetched. An undefined first word runs its IF1 (no tail), then the privileged trap in either mode, the word as identifier. Saved PC: the next instruction, or the second word of a multiple-word privileged instruction (Fawcett Table 6.1); traps are recognised at T3 of the last machine cycle (Fawcett p.77) | Fawcett p.77, p.80 (PDF 88, 91); undefined word: CPU RefMan 1982 PDF p.283 (printed 274), Note 3 | SPEC; timing INFERRED; undefined-word trap INFERRED (DECISIONS) | TestPrivilegedTrapAtDecode, TestPrivilegedTrapZ8001Seg, TestEPATrapWhenDisabled, TestUndefinedOpcodeTrap |
| 48 | Block, string, translate and block I/O forms: 7 of the base 11 clocks run before the first element (`F1 Fn+1`), 4 after the last (`I4`, no named work); an interrupt accepted between elements ends the instruction with its own address saved, and the resumed instruction runs the 7 again: "Seven cycles should be added to this instruction's execution time for each interrupt request that is accepted" (TM 6-78, and every repeat page). Single forms take the same split. A refresh or bus request may follow any element (1988 DB p.149) | TM Mar81 6-78 (PDF 131); 1988 DB p.149 (PDF 156) | INFERRED | TestMachineCycleBlock, TestMachineCycleBlockCompare; `make test-cpu-cycles` rows `ldir_n4` 47, `ldir_n64` 587, `lddr_n4` 47, `cpir_n3` 38, `cpir_n8` 83 |
| 49 | MULT, MULTL, DIV, DIVL with an immediate or memory operand: the table gives IM = IR = R (70, 282, 107, 744) in all three columns, and over R only DA +1 / +2 / +4 and X +2 / +2 / +5 (NS / SS / SL, the same for all four), though those forms add 3 to 9 bus clocks. The setup (MD) and the first steps (MO) run during the operand transactions, as far as the total requires; a step is never shortened | 1988 DB p.138 (PDF 145) | INFERRED: the totals imply it, no source describes it | TestArithmeticSpecGapMemOperand, TestMulDivStretch_*, TestMulDivPath_*; a timing measurement of a memory-operand MULT/DIV on a real CPU would settle it |
| 50 | Sequencer cadence: one step per internal cycle, the step's work on its last clock. MULT: setup 3, 16 steps of 4; MULTL: setup 4, 32 steps of 8, one 7-clock add per 1 bit (item 32), finish 19; DIV: setup 2, trial 6, 16 steps of 6; DIVL: setup 2, trial 67, 32 steps of 21; shifts by count: one 3-clock internal cycle per position, a count of 0 as 1 (TM 6-130). The totals (MULT 70, MULTL 282+7n, DIV 107, DIVL 744, shifts 13+3n / 15+3n) are cited; the step lengths are not | 1988 DB p.138 (PDF 145) | INFERRED | TestMachineCycleSequenced; serial vectors (`make test-serial`) |
| 51 | CALL @Rd segmented: 15. TM Mar81 6-18 prints one segmented figure, 15; Fawcett Table 8.9: IR "10 - 15"; 1988 DB p.139: 10 / 15 / 15. TM Mar81 C-1's 10 / 10 / 15 differs only in which column carries it | TM Mar81 6-18 (PDF 71), C-1 (PDF 276); Fawcett p.138 Table 8.9 (PDF 149); 1988 DB p.139 (PDF 146) | SPEC | `make test-cpu-cycles` |
| 52 | Extended-instruction templates: bit 3 of the first word's direction field (bits 3:2) selects a CPU write cycle in every template: memory 01 = EPU <- memory, 11 = memory <- EPU; registers 00 = CPU <- EPU, 10 = EPU <- CPU; flags 00 = FCW <- EPU, 10 = EPU <- FCW, 01 = internal | TM Mar81 6-167..6-170 (PDF 220-223) | SPEC; unlisted encodings OPEN | memory 00/10 and flags 11 are unlisted: the same bit is applied (flags 11 as internal) |
| 53 | Skipped refreshes: one coming due with the bus granted or in a wait state is skipped; the refreshes then owed (two at most) go out back to back from the first boundary after, the clock after /BUSACK rises or after the waited cycle (tail included), ahead of the next cycle even a data cycle of the same instruction. Jan83 TM 8.3: "When the CPU regains control of the bus, or when the WAIT line is deactivated, it immediately issues the skipped refresh cycles." | TM Jan83 8-1, 8-2 (PDF 246-247); TM Mar81 8-1 (PDF 232, WAIT sense misprinted); Fawcett p.48 (PDF 59) | SPEC; clock placement INFERRED | a refresh or bus hold between a block, compare, translate or block I/O element's cycles leaves the element's pointer, count and compare steps where they were. TestRefreshSkippedBusGrant, TestRefreshSkippedWait, TestRefreshSkippedAnyCycle, TestRefreshSkippedBlock, TestRefreshSkippedLDIR, TestRefreshTwoSkipped |
| 54 | Flag transfer lane: Load FCW from EPU takes FCW bits 7:2 from AD7:AD0 and ignores AD15:AD8; Load EPU from FCW drives them on AD7:AD0, B/W High. Register transfers are words | TM Jan83 9-8, 6-174 (PDF 255, 235) | SPEC | TestEPAFlagByteLane (the EPU drives different bytes on the two halves) |

## Known gaps

* OPEN: items 13, 20 (one clock), 21, 38, 39, 52 (unlisted encodings).
* DIV/DIVL case 3: the destination and S differ from the chip
  (`sys_div_rr_r_large`); masked.
* PUSHL with the pointer as the source pair's low word (@R3,RR2;
  segmented @RR2,RR2) pushes the decremented pointer: no capture.
* Silicon traces to recapture on the current rig: MSET in normal mode
  completes a read of the next word before the trap where the RTL runs
  the aborted IF1 (item 12; one capture, no status recorded); trap
  pushes show status 1011, the RTL drives 1001 (captured only on the rig
  build whose B/W is wrong).
* Needs a real CPU: items 42, 43, 45, 49.
* INFERRED, unverified on silicon: items 12 (traps), 23, 41, 46, 47
  (timing), 48, 49, 50, 53 (clock placement).
* 264 `cpu/` vectors carry the test name `Unknown`; their names do not
  identify the behaviour they cover.
