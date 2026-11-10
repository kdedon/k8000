# k8036_cio (Z8036 CIO) -- tests

## Scope

RTL `rtl/k8036_cio/z8036_cio.sv`; replay harness `tb/k8036_cio/tb_cio.cpp`;
vectors `vectors/k8036_cio/*.vec` (134 files from 124 tests, 53 partial);
make fragment `mk/k8036_cio.mk`.

Ports: `ad_in as_n ds_n r_w cs0_n cs1 intack_n iei pclk_fall pa_in pb_in
pc_in` in, `ad_out ad_drive int_n ieo pa_out pa_oe pb_out pb_oe pc_out
pc_oe` out, plus `clk` (board master clock). `pclk_fall` is the PCLK
falling edge as a one-master-clock pulse. There is no reset port: the chip
has no reset pin. The Z8036 has no WAIT input: WAIT/REQUEST is an output on
PC1 (Port A) / PC3 (Port B), Table 1 p.678, and every handshake line is a
Port C pin.

Sources: z8036_cio.pdf (1985 data book pp.673-698, book folios below),
cross-checked with the 1988 Z8000 Family Data Book pp.282-305 ("1988 DB").

## How to run

```
make lint-cio         # verilator -Wall on z8036_cio.sv (zero suppressions)
make build-cio        # obj_dir/tb_cio/tb_cio
make test-cio         # replay every vector, pass/fail + shortest failing
make cio ONLY=TestName [VCD=1] [CONTEXT=N] [FCLK=N]   # one vector, full context
make ladder-cio       # every vector, shortest first, with status
make test-cio-timing  # datasheet strobe bench (18 checks; docs/TIMING_TESTS.md)
make test-cio-iack    # two chips on one daisy chain, acknowledge (10 checks)
make vectors-cio      # maintainer only: re-record the vectors with the vector generator
```

### Vector format (`K8000VEC 1 cio`)

```
K8000VEC 1 cio
test TestTickPinsRegisterRead 0        test name, chip instance index
T 27 00 00 00 0 0F 00 00 00 00 00 0 0  one pin sample
...
X partial <reason>                     optional: records stop here
F REGS 00 00 ... (48 bytes)            informational: registers at the end
F TICKS 20                             number of T records
F REAL 8                               ... of which pin samples the test drove
F MIRRORED 12                          ... of which bus cycles written for the test's register accesses
F COINCIDENT 0                         records with a strobe edge AND a PCLK fall (always 0)
END
```

`X unsupported <reason>` before any `T` means SKIP (no file has one).

```
T <in_bits:2hex> <AD_in:2hex> <PA_in:2hex> <PB_in:2hex> <PC_in:1hex>
  <out_bits:2hex> <AD_out:2hex> <PA_out:2hex> <PA_oe:2hex> <PB_out:2hex> <PB_oe:2hex> <PC_out:1hex> <PC_oe:1hex>
```

* `in_bits` (bit 7 = MSB): `PCLK AS_n DS_n R_W CS0_n CS1 INTACK_n IEI`
* `out_bits` (bit 4 = MSB): `ADDrive INT_n IEO PortAReq_n PortBReq_n`.
  The two Req_n bits mirror a Port C level; they are not pins and are not
  compared (the Port C pins are).

Where a test set the chip up through register accesses rather than pins,
the generator writes each as Z-Bus cycles: an access is three records (/AS
fall with address and selects; /AS rise and /DS fall with data; /DS rise),
an acknowledge three (with IEI High), a PCLK step two (one falling edge,
port pins as the test set them). Every record is checked against a chip
driven only by the records; the first state difference the pins cannot
produce writes `X partial` and ends the file, so every record before it is
faithful.

### Two clock domains

Only the timer-mode counters, the deskew timers and REQUEST/WAIT run on
PCLK (p.695 Note 1). The port input register, 1's catchers, pattern match,
handshakes and the /INT latch run on **/AS** ("The AS functions as the
clock to the 8036. If AS strobe stops, then data does not get clocked
through the device", 1988 DB p.301 Note 7; AC rows 22-25 in /AS-cycle
units):

* register `as_n` with `clk`; `as_rise = ~as_q & as_n`;
* on `as_rise`: sample `pa_in`/`pb_in`/`pc_in`, update the 1's catchers,
  step the handshakes (not their deskew count), run the pattern compare and
  its two-stage synchroniser, load the /INT latch from the priority
  encoder; `int_n` is that latch inverted;
* on `pclk_fall`: the counter/timers (PCLK/2 prescaler), the deskew
  counters, REQUEST/WAIT;
* the counter-mode count input is asynchronous, and the C/T gate and
  trigger are sampled by PCLK from the live pins (rows 11/14/16 are
  pin-to-PCLK with no /AS term).

With /AS stopped the chip does nothing in the second bullet and keeps
counting in the third (TestASIsTheChipClock, TestPins_CountersRunWithASStopped).

### Replay

One record = one fabric clock: drive the inputs, fire `pclk_fall` for the
first master clock after a record that took PCLK 1 to 0, step N posedges
(N cycles through `--mclk P` / `K8000_MCLK`, default `1,2,1,3`; `--fclk` is
an alias), compare every output. Consequences:

* register reads and the acknowledge vector are combinational from the
  live `ds_n` plus /AS-latched state, and `ad_drive` drops in the record
  `ds_n` rises;
* a two-flop strobe synchroniser needs three master clocks per record
  (`K8000_MCLK=3 make test-cio`); the chip has none;
* no record has both a strobe edge and a PCLK fall (`F COINCIDENT 0`), so
  their order is free; the datasheet leaves it undefined too (Current
  Count "is valid only if the counter is stopped", p.683; RCC exists for
  that).

Reset: before the first record the tb idles two clocks, holds /AS and /DS
Low for four, then idles four (`AS_n = DS_n = CS0_n = INTACK_n = 1, CS1 = 0,
IEI = 1, PCLK = 0`). Registers read 0 except MICR = 01; the PCLK/2
prescaler restarts Low (row 13).

### What is compared

| pin(s) | rule |
|---|---|
| ADDrive, INT_n, IEO | every record |
| AD | only while both drive it. AD is driven only during a selected read (/DS Low) and an acknowledge with MIE = 1, NV = 0: from the /DS fall, floating at the /DS rise (AC rows 13/16/17 p.692) |
| PortA/B/C OE | every record, exact |
| PortA/B/C data | bits under `exp_oe & got_oe`; `--strict-out` compares all bits |
| `F REGS` | informational; no test pokes state |

`INT_n` is active Low (open drain at the pad); REQUEST asserts High on its
Port C pin.

## What is covered

134 files from 124 tests, all PASS; 529,521 records, 524,309 of them in
TestG80_14_TCZeroIs65536 (the TC = 0, 65536-count wrap). 20 files are pure
pin samples (the TestPins_* set), 31 mix pin samples with written bus
cycles, 83 are written bus cycles only. 81 are complete; 53 are `X
partial`, nearly all because the test changed port inputs or registers
with no /AS edge to clock the /AS domain (pattern match, Port C inputs,
handshake state, the /INT latch). The pin-driven TestPins_* vectors cover
that domain at full length.

### Ladder (shortest failing first, grouped by unit)

1. **Strobe capture, register file, reset gating**: TestResetState,
   TestAddressDecoding, TestStrobeServiceWriteNoPCLK,
   TestStrobeServiceReadNoPCLK, TestAsyncStrobeCaptured*,
   TestTickPinsCSGatesBus, TestTickPinsRegisterWrite/Read,
   TestTickPinsBackToBackCycles, TestExitReset, TestRegisterReadWrite,
   TestCommandStatusWrite, TestOverlappedCycleWriteSurvivesPriorCycleAsRise,
   TestHardwareResetASDSLow, TestCS1AndRWSampledAtDS,
   TestCS0LatchHeldUntilNextAS, TestPins_UnusedRegisterAddressesReadZero,
   TestTypicalBootInitSequence. The first divergence is usually the OE
   masks at the MCCR write (0xF4 enables the ports: OE = ~Dir at once, no
   PCLK) or ADDrive at the first read.
2. **Ports A/B/C**: TestPortData, TestPortPolarity, TestPortPolarityOnOutputs,
   TestPortOpenDrainOutputs, TestPortCOutputReadsPin,
   TestCSNibbleSiliconLayout, TestG80_3_MCCRGatesPortIPAndOE,
   TestG80_12_OnesCatcher, TestG80_12_DPPInPatternPath,
   TestInputRegisterFull, TestSetPortBInputLatch, TestPins_PortInputIsASClocked,
   TestPins_EOEFollowsPortOutputPath.
3. **Interrupts and acknowledge**: TestIntACK_NoInterrupt,
   TestIntACK_MIEDisabled, TestINTACKVectorFloatsAtDSRise,
   TestStrobeServiceINTACKNoPCLK, TestNVInhibitsVectorDriveOnPins,
   TestG80_13_IEOIntackAndDLC, TestBUG_CIO_6_NVSuppressesVectorNotIUS,
   TestIEILowBlocksINT, TestCTBeforeAckDSWaitsForAS,
   TestCTDuringAckDSKeepsIEO, TestPins_INTReleasesOnASAfterAcknowledge.
4. **Counter/timers**: TestG80_3_MCCRGatesCTTrigger,
   TestPCLKDomainClocksOnFallingEdge, TestCounterModeCountsWithPCLKHeldLow,
   TestPins_CounterMode*, TestPins_CountersRunWithASStopped,
   TestTickPinsINTAssertsOnPending, TestCounterInterruptPending,
   TestCounter_*, TestG80_5_CTWaveforms.* (PB4/PB0/PC0),
   TestG80_6_ExternalTrigger.* (PB6/PB2/PC2), TestG80_7_RCCFreezesCCR,
   TestG80_8_CTDeferredError, TestG80_3_LCTriggerLink, TestTimerRetrigger,
   TestTimerExternalCount, TestTimerExternalGate, TestCounterTriggerAndCount,
   TestCounterContinuousMode, TestG80_14_TCZeroIs65536 (last).
5. **Priority, daisy chain, VIS**: TestTickPinsIEOBlocksWhenIUS,
   TestTickPinsIEIBlocksINTACK, TestTickPinsDaisyChain.000/.001,
   TestIntACK_CounterTimer, TestIntACK_Priority, TestBUG_CIO_17_PriorityOrder,
   TestBUG_CIO_18_IUS_BlocksLowerPriority, TestG80_10_Fig17*,
   TestPAVISVectorModification, TestPBVISVectorModification,
   TestORPEVVectorFrozenUntilIPClears.
6. **Pattern match**: TestPatternMatchPMSDecode.*, TestPatternMatchLevel,
   TestPatternMatchORMode, TestPatternMatchTransition,
   TestPatternAnyTransition, TestPatternIPTransitionSemantics,
   TestPatternInterruptError.*, TestPatternORPEVLevelIP,
   TestG80_9_PatternWithIMO, TestG80_9_BitPortUnchanged,
   TestPins_PatternMatchOnASClock.
7. **Handshakes**: TestW2_12_RequestActiveHigh,
   TestW2_16_PortCPolarityOnHandshakeLines, TestW2_12_WaitAccessQualified,
   TestG80_9_*Input/Output, TestW2_9_*, TestW2_10_OutputITB, TestW2_11_*,
   TestW2_13_*, TestW2_14_DeskewDTE.*, TestW2_15_StrobedOverwrite,
   TestG80_9_DoubleBuffering, TestG80_9_ITB, TestHandshakeInputIgnoresCatchers,
   TestPins_HandshakeLineOpenDrain, TestPins_InputWaitReleasesOnACKIN,
   TestPins_OutputWaitHoldsWrite, TestPins_Pulsed*, TestPins_Strobed*,
   TestPins_ThreeWireDACFallsWithDAV.

### Spec conformance ledger

Verdicts: SPEC = the source settles it and the vectors follow it;
INFERRED = read from the sources, unverified on silicon; OPEN = the
source is silent; the reading taken is stated.

**The SCC's width-qualified reset does not apply here.** The Z8030 AC
table has "Delay for No Reset" rows and TwRES (K8030_SCC_TESTS.md row 17).
The Z8036 AC table (p.692, 36 rows) has no reset parameter; p.684 says only
"reset by forcing AS and DS Low simultaneously" and the p.674 footnote
"detected Low at the same time". The CIO keeps level detection
(`tb_cio_timing` [5]); rows 7 TdAS(DS) and 20 TdDS(AS) forbid a legal
driver from overlapping the strobes.

| # | item | source | verdict | behaviour / vectors |
|---|---|---|---|---|
| 1 | NV = 1 in an acknowledge | p.684 "The vector output is inhibited by setting the No Vector (NV) control bit to 1"; p.689 | SPEC | AD not driven; IUS still latches. TestNVInhibitsVectorDriveOnPins |
| 2 | AD, /CS0, /INTACK latch | p.674 "Addresses, INTACK, and CS0 are sampled while AS is Low"; 1988 DB p.283 "CS0 is latched by AS"; AC rows 5-6 to the /AS rise | SPEC | transparent while /AS is Low, held until the next /AS; the /DS rise only floats AD. TestCS0LatchHeldUntilNextAS |
| 3 | CS1 and R/W | AC rows 8-10/18/19 p.692 TsCS1(DS), TsRWR/TsRWW(DS), ThRW(DS), ThCS1(DS): no /AS-referenced parameter | SPEC | the levels at the /DS fall; an access needs CS1 High there. TestCS1AndRWSampledAtDS |
| 4 | one access per /AS | the data book does not decide a repeated /DS | INFERRED | the first /DS rise after an /AS spends the select; a further /DS without a new /AS does nothing (no access, no acknowledge). tb_cio_timing |
| 5 | IEO and /INTACK | p.674 "INTACK is sampled while AS is Low"; row 32 TdAS(IEO), Note 5 | SPEC | IEO uses the /AS-sampled /INTACK. TestG80_13_IEOIntackAndDLC |
| 6 | acknowledge takes only the /AS-latched request | rows 32-33: IEO in an acknowledge timed from the /AS rise and from IEI only; row 26 TdAS(INT); UM0109: "no additional interrupt requests during an Interrupt Acknowledge cycle" | SPEC | IEO in an acknowledge falls on the latched request, not a live IP; a source asking later reaches /INT at the next /AS. TestCTBeforeAckDSWaitsForAS, TestCTDuringAckDSKeepsIEO, `make test-cio-iack` |
| 7 | strobe edge and PCLK edge together | p.683 Current Count "valid only if the counter is stopped"; no AC parameter relates /DS to PCLK | OPEN | no vector has both (`F COINCIDENT 0`) |
| 8 | PCLK-domain edge | p.695 Counter/Timer Timing (PCLK/2 toggles after the PCLK fall); rows 11/14/16/18 p.695; p.696 rows 3/4 TdPC(REQ)/TdPC(WAIT); p.692 row 25 TdPC(INT): all "PCLK falling" | SPEC | counters, deskew and REQUEST/WAIT on the PCLK fall. TestPCLKDomainClocksOnFallingEdge. Trigger and gate act on the step they are seen; silicon samples them half a count cycle earlier (rows 11/14 Note 2) |
| 9 | counter-mode count input | p.683 "decremented on the rising edge of the counter/timer's counter input"; row 19 TdCI(CO); p.695 Note 1 "PCLK ... can be held low" | SPEC | PB5/PB1/PC1 rising edges are seen on every record. TestCounterModeCountsWithPCLKHeldLow |
| 10 | port sampling, pattern match, handshake, /INT clock | p.695 Note 1 (PCLK used only by timer-mode counters, deskew timers and REQUEST/WAIT); p.692 rows 22-25 in /AS-cycle units, Note 6; handshake rows 9/10/21/22 = one /AS cycle; 1988 DB p.301 Note 7 | SPEC | clocked by /AS (see Two clock domains). /INT asserts one /AS cycle after a terminal count (row 25) and releases one /AS cycle after the acknowledge sets IUS (row 23). A board idling the chip must supply /AS pulses, as a running CPU does. TestASIsTheChipClock, TestPins_* |
| 11 | hardware reset = /AS+/DS Low | p.674 footnote, p.684, Reset Timing p.696 (TwRES 250/170 ns) | SPEC | any record with both Low resets, including /DS held Low while /AS pulses. TestHardwareResetASDSLow |
| 12 | register state in reset | p.684: "all control bits are forced to 0 ... only ... read and write the Reset bit" | SPEC | registers 0, MICR reads 01, other writes ignored while in reset (including the other MICR bits of the exit-reset write). The state before the first reset is undefined; the RTL starts in reset |
| 13 | PCLK/2 prescaler phase after reset | datasheet silent | OPEN | restarts Low; an RTL free to differ diverges at the first count |
| 14 | daisy chain, IUS/IE/IP | p.683-684 Interrupt Logic Operation; p.689 | SPEC | INT_n = priority level (IP & IE, own IUS clear, no higher IUS); IEI sampled and IUS latched at the acknowledge /DS fall; IEO = !DLC & IEI & !anyIUS & !(request during the /AS-sampled INTACK) |
| 15 | counter-mode trigger and gate | rows 12/15/17 p.695: sampled by the counter input's falling edge | OPEN | sampled in the PCLK domain |
| 16 | register datapath | rows 13/14/30 (from /DS, no PCLK); rows 16/17 float at the /DS rise | SPEC | see What is compared |
| 17 | cycle teardown vs the next /AS fall | Product Spec Fig 19 (1988 DB p.157) back-to-back cycles: /DS rises after the T3 fall, the next /AS falls at the following T1, so both can land in one sample; p.674 the cycle latch is set by /AS | SPEC | end-of-cycle clears run before the /AS-fall latch, so a back-to-back access is kept. TestTickPinsBackToBackCycles |

## Known gaps

* Rows 7, 13, 15 OPEN; row 4 INFERRED; row 8's sub-count trigger residual.
* 53 partial vectors are compared only up to their `X partial` line.
* No final-register check (`F REGS` is informational): no test pokes state,
  and a register check would bind the harness to RTL names.
