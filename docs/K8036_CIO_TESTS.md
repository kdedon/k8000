# k8036_cio (Z8036 CIO) -- vectors, comparison rules, coverage, ladder

Produced from Go `sim/cio`, never hand-written:

| what                    | producer                                              | consumer                    |
|-------------------------|-------------------------------------------------------|-----------------------------|
| `vectors/k8036_cio/*.vec`     | `sim/cio/vecdump_test.go` (env `K8000_VEC_DIR`)       | `tb/k8036_cio/tb_cio.cpp`             |
| Go self-check           | `hdl/gen/cmd/ciovecverify` (run by `make vectors-cio`)| --                          |

```
make vectors-cio     # record 110 files from the 106 cio tests + Go replay self-check
make lint-cio        # verilator -Wall rtl/k8036_cio/z8036_cio.sv (zero suppressions)
make build-cio       # obj_dir/tb_cio/tb_cio
make test-cio        # replay everything, print pass/fail + shortest failing vectors
make cio ONLY=TestName [VCD=1] [CONTEXT=N] [FCLK=N]   # one vector, full context table
make ladder-cio      # every vector, shortest first, with status
```

RTL top `rtl/k8036_cio/z8036_cio.sv`: ports are `sim/cio/pins.go`
one-for-one (`Inputs` -> `ad_in as_n ds_n r_w cs0_n cs1 intack_n iei pclk_fall
(PCLK as a falling-edge pulse) pa_in pb_in pc_in`; `Outputs` -> `ad_out ad_drive int_n ieo pa_out pa_oe
pb_out pb_oe pc_out pc_oe`) plus `clk` (board master clock). There is no
reset port (the silicon has no reset pin, see the reset note below).
The Z8036 has no WAIT input: WAIT/REQUEST is an OUTPUT on PC1 (Port A) /
PC3 (Port B), Table 1 p.678, and every handshake line is a Port C pin.
The Go seam's `PortAReq_n`/`PortBReq_n` are active-low mirrors of that Port C
level, not silicon pins: the RTL has no such ports and tb_cio.cpp does not
compare them (the Port C pins are compared).

## The file (`K8000VEC 1 cio`)

```
K8000VEC 1 cio
test TestTickPinsRegisterRead 0        Go test function name, chip instance index
T 27 00 00 00 0 0F 00 00 00 00 00 0 0  one TickPins(Inputs) Outputs
...
X partial <reason>                     optional: the Go test then did something with
                                       no pin equivalent; records stop here
F REGS 00 00 ... (48 bytes)            informational: the shadow chip's regs[] at the end
F TICKS 20                             number of T records
F REAL 8                               ... of which verbatim TickPins calls
F MIRRORED 12                          ... of which transliterated functional-API calls
F COINCIDENT 0                         records with a strobe edge AND a PCLK fall (always 0)
END
```

`X unsupported <reason>` before any `T` means SKIP (never happens).

### `T` record

```
T <in_bits:2hex> <AD_in:2hex> <PA_in:2hex> <PB_in:2hex> <PC_in:1hex>
  <out_bits:2hex> <AD_out:2hex> <PA_out:2hex> <PA_oe:2hex> <PB_out:2hex> <PB_oe:2hex> <PC_out:1hex> <PC_oe:1hex>
```

`in_bits` (bit 7 = MSB): `PCLK AS_n DS_n R_W CS0_n CS1 INTACK_n IEI`
`out_bits` (bit 4 = MSB): `ADDrive INT_n IEO PortAReq_n PortBReq_n`

Every record is one `TickPins` call. On every call, regardless of PCLK, the
model reacts to /AS and /DS edges (previous call vs this one): AD, /CS0 and
/INTACK latch at AS(fall), CS1 and R/W are the levels at DS(fall)
(R-CIO-401/402). It also watches the counter-mode inputs PB5/PB1/PC1 on
every call (R-CIO-404), and advances its PCLK domain when PCLK goes 1->0
(falling edge, R-CIO-403). /AS and /DS both Low in one record is the
hardware reset; there is no reset pin.

**Two clock domains (R-CIO-405):** only the timer-mode counters, the
deskew timers and REQUEST/WAIT are PCLK-clocked (p.695 Note 1). The port
input register, 1's catchers, pattern match, handshake FSMs and IP->INT
latch are clocked by **/AS** ("The AS functions as the clock to the 8036.
If AS strobe stops, then data does not get clocked through the device",
1988 data book p.301 Note 7; AC rows 22-25 in AS-cycle units). Build the
RTL the same way:

* register `as_n` with `clk` and derive `as_rise = ~as_q & as_n`;
* on `as_rise`: sample `pa_in`/`pb_in`/`pc_in` into the input register,
  update the 1's catchers, step the handshake FSMs (NOT their deskew
  count), run the pattern comparison and its two-stage synchroniser, and
  load the /INT request latch from the priority encoder. `int_n` is that
  latch inverted, not a combinational function of IP/IE;
* on the PCLK falling-edge enable: the counter/timers (PCLK/2 prescaler,
  R-CIO-403), the deskew counters, REQUEST/WAIT;
* the counter-mode count input stays asynchronous (R-CIO-404), and the
  C/T gate/trigger are sampled by PCLK from the LIVE pins (rows 11/14/16
  are pin-to-PCLK with no AS term).

With /AS stopped the chip does nothing in the second bullet and keeps
counting in the third: `TestASIsTheChipClock` and `cio/k8000_pins_test.go`.

## How the tb replays a record (per-Tick equality)

The Go seam has no fabric clock; the chip's `pclk_fall` port is the PCLK
falling edge as a one-master-clock pulse from the board divider. The tb
treats **one record == one fabric clock**: drive the recorded inputs, fire
`pclk_fall` for exactly the first master clock after the record that took
PCLK 1->0, then step N posedges in total (N cycles through the comma list
`--mclk P` / env `K8000_MCLK`, default `1,2,1,3`; `--fclk` is an alias;
`1` = a pulse on every master clock the vectors allow), compare every
output. The RTL gets what the model has: one chance per Tick to see a
strobe edge (registered `as_q/ds_q` vs the live pin) and the PCLK
falling-edge pulse. Port-line counter inputs (PB/PC) stay level-sampled
data. Consequences:

- Register reads and the INTACK vector must be COMBINATIONAL from the live
  `ds_n` level plus AS-latched state, and `ad_drive` must drop in the record
  `ds_n` rises. Waiting for a PCLK enable diverges at every read.
- A two-FF strobe synchroniser needs 3 master clocks per record
  (`K8000_MCLK=3 make test-cio`); no synchroniser is in the chip.
- In Go the strobe service runs before the PCLK-domain advance, but no
  record has both a strobe edge and a PCLK fall (`F COINCIDENT 0`:
  `pclkStep` moves strobes on the PCLK-high half), so the vectors leave that
  ordering free. The datasheet leaves it undefined too (R-CIO-408: Current
  Count "is valid only if the counter is stopped"; RCC exists for that).
- Reset: Go `New()` is in-reset (regs 0, MICR reads 1, no drives, strobe
  trackers High, PCLK tracker Low, prescaler phase 0). The tb resets the
  chip through its pins before the first record: two idle clocks, /AS and
  /DS Low for four, then four idle
  (`AS_n=DS_n=CS0_n=INTACK_n=1, CS1=0, IEI=1, PCLK=0`). The RTL reset state
  must equal `New()`, which is observably the AS+DS hardware-reset state
  (only `regs[MICR]` differs, and `readReg` masks it).
  `TestHardwareResetASDSLow` is the cited pin test of the AS+DS reset
  (registers read 0 except MICR=01, ports float, MCCR writes ignored). The
  prescaler phase after reset is unspecified (R-CIO-408); the vectors encode
  Go's "restart Low".

### What is compared, when

| pin(s)                          | rule                                                                 |
|---------------------------------|----------------------------------------------------------------------|
| ADDrive, INT_n, IEO, PortAReq_n, PortBReq_n | every record                                             |
| AD                              | only while both drive it (exp and got ADDrive=1); otherwise Go's `pinOut.AD` is stale. AD is driven only during a read (DS Low) and an INTACK with MIE=1, NV=0 (R-CIO-267; AC rows 13/16/17: driven from DS(fall), float at DS(rise), INTACK vector too) |
| PortA/B/C OE                    | every record, exact                                                  |
| PortA/B/C data                  | bits under `exp_oe & got_oe` only; `--strict-out` compares all bits (Go's undriven bits mirror its Output* registers) |
| `F REGS`                        | informational. No `cio_access.h` exists: no test pokes state, and a final-register check would bind the harness to RTL names. Add one if wanted (pattern: `tb/k800x_cpu/dut_access.h`). |

`INT_n` and the Req_n mirrors are active-low (INT is open-drain at the pad;
REQUEST asserts HIGH on the Port C pin, `PortAReq_n` mirrors it inverted).

## Where the records come from (the shadow-chip transliteration)

Only ~25 of the 95 cio tests touch the pin seam, all using the sim-only
`ioWrite/ioRead` for setup; ~67 never call `TickPins`. The recorder keeps a
**shadow** Z8036 -- a fresh `New()` driven only through `TickPins` with the
records it writes -- and hooks the functional API (`traceAPIHook`: `ioWrite`,
`ioRead`, `intAck`, `advance`) to transliterate:

| Go call                        | records written (PCLK held; port pins held)                                   |
|--------------------------------|--------------------------------------------------------------------------------|
| `TickPins(in)`                 | 1, verbatim                                                                    |
| `ioWrite(port,d)`/`ioRead(port)`| 3: AS fall (AD=port&FF, CS0_n/CS1 = the functional decode, R/W); AS rise + DS fall (write data on AD); DS rise + bus idle. A port outside the chip's decode becomes a DESELECTED cycle (CS-gating coverage) |
| `intAck()`                     | 3: AS fall + INTACK low; AS rise + DS fall (IEI forced High); DS rise + INTACK high |
| `advance()`                    | 2: one PCLK cycle (one falling edge, ending at the previous level) with PA/PB/PC = the real chip's `Input*` fields, which is how `setPortA/B` and `c.InputX =` pokes reach the pins |
| `setPortA/B`, `c.InputX = v`   | 0; absorbed by the next `advance()`, or by one inserted PCLK cycle before a bus access |

Recorded outputs are the shadow's, so every file is self-consistent;
`ciovecverify` replays each into a fresh Go chip to prove it. Before every
event the real chip's `SaveState()` is compared with the shadow's, masking
only the pin-domain trackers, `BaseAddr/AddrMask`, `CtGate[i]` while EGE=0,
and the input synchroniser stages + PCLK/2 prescaler phase (a
`setPortA()+ioRead()` shortcut is unphysical; consequences surface in regs or
counts). The first unmaskable difference writes `X partial` and ends the
file; the ticks before it are faithful.

## Coverage

- 106 test functions; 101 produce vectors (110 files: some tests build 2-3 chips);
  4 tests exercise no chip (`TestRegisterAddressDecode`, `TestBUG_CIO_1_MICR_CTVIS_At_D2`,
  `TestBUG_CIO_11_CTMSR_BitLayout`, `TestBUG_CIO_14_TC_Zero_Deviation` -- constant/decode checks).
- 265,676 records; 262,165 in `TestG80_14_TCZeroIs65536` (the TC=0 =
  65536-count wrap; keep it).
- 36 files mix verbatim and transliterated records, 67 are fully
  transliterated, none are pure-pin (every pin test uses `ioWrite` to leave
  reset).
- 94 files are complete; 9 are `X partial`:

| vector (partial)                    | truncated because                                                        |
|-------------------------------------|--------------------------------------------------------------------------|
| `TestG80_10_Fig17CTVector`          | `c.regs[RegCT1CS] \|= ctIP` -- IP forced by poke, no pin equivalent        |
| `TestG80_13_IEOIntackAndDLC`        | same poke in the setup; only the 6 setup writes record                    |
| `TestPAVISVectorModification`       | `c.regs[RegPortACS] \|= csIP/csPMF/csERR` pokes                            |
| `TestPBVISVectorModification`       | same for Port B                                                           |
| `TestPortCData`                     | `c.OutputC = 0` poke (output register written directly, not via a bus write) |
| `TestPortCInput`                    | `c.OutputC =` / `c.InputC =` pokes before any PCLK edge                    |
| `TestPortInputWithDirection`        | `c.OutputA =` / `c.InputA =` pokes                                          |
| `TestTimerExternalCount`            | `c.externalCount(2)` -- a counter-input edge with no PCLK cycles around it |
| `TestTimerExternalGate`             | `c.setGate()` with EGE=1 -- gate poked, PB7/PB3/PC3 pins untouched         |

Not vectorizable: the 4 constant checks above, and the C900 machine-level
tests (`kbd_inject_cio_test.go`, `ct3_tickrate_test.go`), which need the
machine's clock tree and live outside this package.

## Ladder (attack order = shortest failing first, grouped by unit)

`make test-cio` prints the next rungs. Rungs follow the RTL header:

1. **Strobe capture + register file + reset gating** (9-21 ticks):
   `TestResetState`, `TestAddressDecoding` (CS-deselected cycles),
   `TestStrobeServiceWriteNoPCLK`, `TestStrobeServiceReadNoPCLK`,
   `TestAsyncStrobeCaptured*`, `TestTickPinsCSGatesBus`,
   `TestTickPinsRegisterWrite/Read`, `TestExitReset`, `TestRegisterReadWrite`,
   `TestCommandStatusWrite`, `TestOverlappedCycleWriteSurvivesPriorCycleAsRise`,
   `TestHardwareResetASDSLow` (AS+DS reset), `TestCS1AndRWSampledAtDS`
   (CS1/R_W are DS-time levels), `TestTypicalBootInitSequence`.
   The first divergence is usually `PAoe,PBoe,PCoe` at the MCCR write
   (0xF4 enables the ports: OE = ~Dir at once, no PCLK) or `ADDrive` at the
   first read.
2. **Ports A/B/C data path, polarity, direction, MCCR gating**:
   `TestPortData`, `TestPortPolarity`, `TestCSNibbleSiliconLayout`,
   `TestG80_3_MCCRGatesPortIPAndOE`, `TestG80_12_OnesCatcher`,
   `TestG80_12_DPPInPatternPath`, `TestInputRegisterFull`,
   `TestSetPortBInputLatch` (PCLK-sampled inputs).
3. **Interrupt unit + INTACK cycle** (no counters yet):
   `TestIntACK_NoInterrupt`, `TestIntACK_MIEDisabled`,
   `TestINTACKVectorFloatsAtDSRise`, `TestStrobeServiceINTACKNoPCLK`,
   `TestNVInhibitsVectorDriveOnPins` (NV=1: IUS latches, AD not driven),
   `TestG80_13_IEOIntackAndDLC` (partial), `TestBUG_CIO_6_NVSuppressesVectorNotIUS`.
4. **Counter/timers**: `TestG80_3_MCCRGatesCTTrigger` (never reads; passes with the ports disabled),
   `TestPCLKDomainClocksOnFallingEdge` (the PCLK(fall) domain edge),
   `TestCounterModeCountsWithPCLKHeldLow` (asynchronous count input),
   `TestTickPinsINTAssertsOnPending`, `TestCounterInterruptPending`,
   `TestCounter_*`, `TestG80_5_CTWaveforms.*` (EOE waveforms on PB4/PB0/PC0),
   `TestG80_6_ExternalTrigger.*` (ETE via PB6/PB2/PC2), `TestG80_7_RCCFreezesCCR`,
   `TestG80_8_CTDeferredError`, `TestG80_3_LCTriggerLink`, `TestTimerRetrigger`,
   `TestCounterTriggerAndCount`, `TestCounterContinuousMode`,
   `TestG80_14_TCZeroIs65536` (262K ticks, last).
5. **Priority encoder / daisy chain / VIS vectors**: `TestTickPinsIEOBlocksWhenIUS`,
   `TestTickPinsIEIBlocksINTACK`, `TestTickPinsDaisyChain.000/.001`,
   `TestIntACK_CounterTimer`, `TestIntACK_Priority`, `TestBUG_CIO_17_PriorityOrder`,
   `TestBUG_CIO_18_IUS_BlocksLowerPriority`, `TestG80_10_Fig17*`.
6. **Pattern match**: `TestPatternMatchPMSDecode.*`, `TestPatternMatchLevel`,
   `TestPatternMatchORMode`, `TestPatternMatchTransition`, `TestPatternAnyTransition`,
   `TestPatternIPTransitionSemantics`, `TestPatternInterruptError.*`,
   `TestPatternORPEVLevelIP`, `TestG80_9_PatternWithIMO`, `TestG80_9_BitPortUnchanged`.
7. **Handshake unit** (`cio_handshake.go`): `TestW2_12_RequestActiveHigh`,
   `TestW2_16_PortCPolarityOnHandshakeLines`, `TestW2_12_WaitAccessQualified`
   (/WAIT is strobe-domain, access-qualified), `TestG80_9_*Input/Output`,
   `TestW2_9_*`, `TestW2_10_OutputITB`, `TestW2_11_*`, `TestW2_13_*`,
   `TestW2_14_DeskewDTE.*`, `TestW2_15_StrobedOverwrite`, `TestG80_9_DoubleBuffering`,
   `TestG80_9_ITB`.

## Recording again

`make vectors-cio` wipes `vectors/k8036_cio`, reruns the Go suite with
`K8000_VEC_DIR` set, and runs `ciovecverify`. Run it after any Go change to
pin behaviour. With the variable unset the recorder does nothing.

## Spec conformance ledger

The target is the hardware. Every pin behaviour the vectors encode was
checked against `z8036_cio.pdf` (1985 data book pp.673-698, book folios
below), cross-checked with the 1988 Z8000 Family Data Book pp.282-305.
Verdicts: FIXED = model wrong, spec unambiguous, model + cited test changed,
vectors regenerated; CONFIRMED = model right (or a sim artifact with no pin
effect); OPEN = unspecified or not fixed (reason given). R-CIO-401..409 are
the Go model's requirement IDs.

**Do not port the Z8030's width-qualified reset to this chip.** The SCC's
`/AS`+`/DS` reset is width-qualified (K8030_SCC_TESTS.md item 17) because
the Z8030 AC table has rows 37/38 "Delay for No Reset" and row 39 TwRES. The
Z8036 AC table (p.692, 36 rows) has no reset parameter; p.684 says only
"reset by forcing AS and DS Low simultaneously" and the p.674 footnote
"detected Low at the same time". The model and RTL keep level detection
(`tb_cio_timing` [5]). Rows 7 TdAS(DS) (>= 40 ns at 6 MHz) and 20 TdDS(AS)
(>= 25 ns) instead forbid a legal driver from overlapping the strobes.
R-CIO-215's "TwRES minimum" for the Z8036 was imported from the Z8030 and
is corrected.

| item | source | verdict | change / note |
|------|--------|---------|---------------|
| `PortAWait_n`/`PortBWait_n` input pins (harness idled them asserted) | p.674 pin description (PC0-PC3 "provide handshake, WAIT, and REQUEST lines"); Table 1 p.678: WAIT/REQ = PC1 (A) / PC3 (B), an OUTPUT | FIXED | no such input exists; removed from `pins.go`, the vector format (`in_bits` is 8 bits), `tb_cio.cpp`, the RTL port list and `ciovecverify`. |
| `inputLatchA/B` dead state | p.679 + Fig 12 p.685: IRF exists only on the double-buffered ports with handshake; LPM latching is `lpmLatch` | FIXED (cleanup) | removed from the model and `Snapshot`. No pin effect. |
| `pinOut.AD` stale while not driven | R-CIO-267; AC rows 13 TdDS(DRV) / 16 TdDSr(DR) / 17 TdDS(DRz) p.692 | CONFIRMED | sim artifact; tb compares AD only under ADDrive. AD float rules: driven from DS(fall) of a selected read or an accepted INTACK (MIE=1, NV=0), floats at DS(rise) alone. |
| NV=1 during INTACK | p.684 "The vector output is inhibited by setting the No Vector (NV) control bit to 1"; p.689; R-CIO-048/210/267 | FIXED | Go drove the base vector with ADDrive=1. Now ADDrive=0 during the INTACK; IUS still latches (R-CIO-253). `TestNVInhibitsVectorDriveOnPins`. |
| CS1 and R/W latched at AS(fall) | p.674 "Addresses, INTACK, and CS0 are sampled while AS is Low"; 1988 p.283 "CS0 is latched by AS"; AC rows 8-10/18/19 TsCS1(DS), TsRWR/TsRWW(DS), ThRW(DS), ThCS1(DS) p.692 -- CS1/R/W have no AS-referenced parameter | FIXED | CS1 and R/W are now the levels at DS(fall); AD, /CS0, /INTACK stay AS-latched. `TestCS1AndRWSampledAtDS`. Vectors: no change in existing cycles (they hold CS1/R_W through the cycle). |
| AS latch edge (fall vs transparent-while-Low) | TsA(AS)/ThA(AS)/TsCS0(AS)/ThCS0(AS)/TsIA(AS)/ThIA(AS) all to AS rise | CONFIRMED (nuance) | Go latches at AS(fall); silicon's latch is transparent while AS Low. Identical whenever AD/CS0/INTACK are stable during AS Low (all vectors; well-formed Z-Bus). RTL should latch while `as_n` is Low. |
| IEO drops from the LIVE /INTACK pin | p.674 "INTACK is sampled while AS is Low"; row 32 TdAS(IEO) + Note 5 (chain settles from AS) | FIXED | IEO's INTACK term now uses the AS-sampled /INTACK; `TestG80_13_IEOIntackAndDLC` re-cited (INTACK Low with AS High no longer drops IEO). Mirrored INTACK cycles unchanged (AS falls in the same record). |
| Strobe edge coincident with the PCLK-domain edge (recorder item 4) | p.683 CCR "valid only if the counter is stopped" / RCC; no AC parameter relates DS to PCLK | OPEN by design (R-CIO-408) | the spec does not define the ordering; keep `F COINCIDENT 0` (helper `pclkStep` now puts strobe edges on the non-clocking PCLK rising half). Not encoded. |
| PCLK-domain clocking edge | p.695 Counter/Timer Timing figure (PCLK/2 toggles after PCLK(fall)) and rows 11/14/16/18 TsTI(PC)/TsGI(PC)/ThGI(PC)/TdPC(CO), p.696 rows 3/4 TdPC(REQ)/TdPC(WAIT), p.692 row 25 TdPC(INT): all "PCLK falling" | FIXED | Go stepped its PCLK domain on PCLK rising; now falling (`TestPCLKDomainClocksOnFallingEdge`). Timer/REQ-WAIT vectors moved half a PCLK; the C900 acceptance tests (`ct3_tickrate_test`, `kbd_inject_cio_test`) are unchanged. Residual: trigger/gate apply on the step they are seen (silicon samples them half a count-cycle earlier, rows 11/14 Note 2), documented in R-CIO-403. |
| Counter-mode count input needed a PCLK edge to be seen | p.683 "decremented on the rising edge of the counter/timer's counter input"; row 19 TdCI(CO); p.695 Note 1 "PCLK ... can be held low" | FIXED | PB5/PB1/PC1 rising edges are now watched on every TickPins call (asynchronous). `TestCounterModeCountsWithPCLKHeldLow`. |
| Port sampling / pattern match / handshake / IP->INT clock | p.695 Note 1 (PCLK is used ONLY by the timer-mode counters, deskew timers and REQUEST/WAIT); p.692 rows 22-25 in AS-cycle units + Note 6; handshake rows 9/10/21/22 = 1 AS cycle; 1988 p.301 Note 7 "The AS functions as the clock to the 8036. If AS strobe stops, then data does not get clocked through the device"; cross-check Z8536 (non-Z-Bus) gives the same rows in PCLK units, 1985 p.899 | FIXED | these ran in the PCLK domain; they are now clocked by /AS. `tickPins` samples the port pins and runs `advanceAS()` at the /AS RISE; `advancePCLK()` keeps the counter/timers and deskew timers on PCLK(fall). `/INT` is an /AS-clocked latch (`intLatch`): it asserts one AS cycle after a terminal count (row 25) and releases one AS cycle after the acknowledge sets IUS (row 23). Functional `advance()` = one PCLK cycle then one /AS cycle. Tests: `TestASIsTheChipClock`, `cio/k8000_pins_test.go`. C900: CT3's 100 Hz period is still 60000 PCLK cycles, but a harness idling the chip must supply /AS pulses, as a running CPU does. 52 vectors are partial (12-62 ticks) because a functional-API access has no /AS edge to transliterate; `k8000_pins_test.go` covers this domain at full length. |
| Hardware reset = /AS+/DS Low | p.674 footnote, p.684 Programming, Reset Timing p.696 (TwRES 250/170 ns) | CONFIRMED | Go resets on any record with both Low (no minimum-width filter: sim granularity); "DS held Low while AS pulses" also resets. `TestHardwareResetASDSLow`. |
| Register defaults after reset | p.684: "all control bits are forced to 0 ... only ... read and write the Reset bit"; R-CIO-036/214/272 | CONFIRMED | regs 0, MICR reads 01, other writes ignored while in reset (incl. the other MICR bits of the exit-reset write). Power-up state before the first reset is undefined (R-CIO-270); `New()` starts in reset. |
| Daisy chain / IUS-IE-IP | p.683-684 Interrupt Logic Operation; p.689 INTACK; R-CIO-196..210, 241..243 | CONFIRMED | INT_n = priority-encoder level (IP&IE, own IUS clear, no higher-priority IUS), IEI sampled at DS(fall) of the INTACK, IUS latched at DS(fall), IEO = !DLC & IEI & !anyIUS & !(pending during the AS-sampled INTACK). |
| Counter/timer trigger/gate vs PCLK | rows 11-17 p.695 | CONFIRMED (timer mode, sub-count residual) | see PCLK-domain item; counter-mode trigger/gate are spec-sampled by the counter input's falling edge (rows 12/15/17), the model samples them in the PCLK domain -- residual, documented in R-CIO-403. |
| Register datapath domain facts | rows 13/14/30 (register datapath from DS, no PCLK); rows 16/17 float at DS(rise) | CONFIRMED | both facts hold; the third (AS clocks the port/handshake/interrupt units) is R-CIO-405, row above. |
| PCLK/2 prescaler phase after reset | datasheet silent | OPEN (R-CIO-408) | Go restarts Low; vectors encode it; an RTL free to differ would diverge at the first count. |
| Cycle teardown vs the next cycle's /AS fall | Product Spec Fig 19 (1988 DB p.157) back-to-back cycles: /DS rises after the T3 falling edge, the next /AS falls at the following T1 -- so in a rising-edge-sampled model both land in ONE sample. Z8036 p.674: the cycle-ownership latch is set by /AS | FIXED | the /DS(rise) teardown (`ADDrive`, `pinBusActive`, `pinWaitStall`) now runs BEFORE the /AS(fall) latch in `tickPins`. Otherwise a back-to-back access is dropped: on the C900 every CIO register write was lost and both chips stayed in power-on reset (reads 0xFF; the boot ROM saw a phantom console character forever). `TestTickPinsBackToBackCycles`. RTL rule: in the `always_ff`, apply end-of-cycle clears first, then the /AS-fall latch -- never the other way round. |
