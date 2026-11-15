# k8030_scc (Z8030 SCC) -- tests

## Scope

RTL `rtl/k8030_scc/z8030_scc.sv` + `z8030_scc_channel.sv`; replay harness
`tb/k8030_scc/tb_scc.cpp` with `scc_access.h`; vectors
`vectors/k8030_scc/*.vec` (181 files from 104 tests); make fragment
`mk/k8030_scc.mk`.

Sources: z8030_scc.pdf (= 1985 data book pp.631-652); 1988 Z8000 Family
Data Book (Z8030/Z8530 spec, pp.253-288; "1988 DB"); Zilog SCC/ESCC User
Manual UM0109 ("UM", printed folios); Z8030 Technical Manual 00-2057-03
(1986).

## How to run

```
make lint-scc         # verilator -Wall on rtl/k8030_scc (zero suppressions)
make build-scc        # obj_dir/tb_scc/tb_scc
make test-scc         # replay every vector: PASS/FAIL/SKIP, shortest failing first
make ladder-scc       # every vector, shortest first, with status
make scc ONLY=TestPins_TX_8N1_x16 [VCD=1] [CONTEXT=20]   # one vector, full context
make test-scc-timing  # datasheet strobe bench (15 checks; docs/TIMING_TESTS.md)
make test-scc-iack    # two chips on one daisy chain, acknowledge (11 checks)
```

### Vector format (`K8000VEC 1 scc`)

One file per test x chip instance: `<TestName>.<NNN>.vec`.

```
K8000VEC 1 scc
test TestPins_TX_8N1_x16 0     test name, chip instance index
base 0100                      informational
P A_WR5 68                     poke: a register set outside the pins
T 2A7F00 00 03F00 00           one pin sample
...
F IntVector A0                 final register inventory (every field)
F TICKS 1234                   number of T records, informational
F POKES 0                      number of P records (0 = pure pin vector)
END
```

`X unsupported <reason>` before the first `T` means SKIP; no file has one.

`T <in:6hex> <in_AD:2hex> <out:5hex> <out_AD:2hex>`

* `in` (bit 21 = MSB): `PCLK AS_n DS_n R_W CS0_n CS1 INTACK_n IEI RxD_A
  RxD_B CTS_n_A CTS_n_B DCD_n_A DCD_n_B TRxCIn_A TRxCIn_B TxCIn_A TxCIn_B
  RxCIn_A RxCIn_B SYNCIn_A SYNCIn_B` (TxCIn has no chip pin and is
  ignored; RxCIn is /RTxC)
* `out` (bit 16 = MSB): `ADDrive INT_n IEO TxD_A TxD_B RTS_n_A RTS_n_B
  DTR_n_A DTR_n_B TRxCOut_A TRxCOut_B TRxCDrive_A TRxCDrive_B SYNCOut_A
  SYNCOut_B SYNCDrive_A SYNCDrive_B`

Pokes and final state use register-inventory names: chip-level bare
(`IntVector IntPending ShiftRight IUSMask`), per channel `A_`/`B_`, arrays
suffixed with the index (`A_WR5`, `B_RxFIFOData2`). `scc_access.h` maps
every name to an RTL register or marks it vector-only; an unknown name SKIPs the vector (poke) or
fails it (F). Inventory `TxD` is the TxD output register.

### Clocking

Each record has two time bases:

* every record: strobe edges (/AS, /DS, /INTACK against the previous
  record; AD, CS0 and INTACK transparent while /AS is Low and frozen at the
  /AS rise; R/W and CS1 taken at the /DS fall; AD and IEI at the /DS fall),
  the /AS+/DS reset, the /AS-rise copy of the interrupt request onto the
  /INT latch (ledger row 9), and the combinational outputs (INT_n, IEO, AD
  float on /DS High);
* PCLK rise: bus-cycle service (read mux, write, acknowledge vector),
  sampling RxD/DCD/CTS/RTxC/TRxC/SYNC, and the BRG, transmitter, receiver,
  WR0 commands and ext/status.

Replay: **one `T` record = one posedge of the master clock `clk`, then
N-1 more with the inputs held** (N cycles through `--mclk P` /
`K8000_MCLK`, default `1,2,1,3`). The clock pins are one-master-clock edge
pulses from the board divider: `pclk_rise`, `rxc_rise/rxc_fall`,
`trxc_rise/trxc_fall` ([1:0] per channel), fired on the first master clock
after the record that changed the level. /RTxC and /TRxC rebuild their
level per channel and are sampled only at PCLK rises against the level at
the previous one, so an edge between PCLK rises is seen at the next.
Strobe edges are `<x>_q & ~<x>_n` (registered previous level vs the live
input), so a strobe transition in the same record as a PCLK rise is
serviced in that record, strobe part first. Pokes are applied between
records.

The Z8030 has no reset pin and the RTL no reset port. tb_scc idles two
PCLKs, holds /AS and /DS Low across three PCLK rises, then idles six: the
hardware-reset state, which is also the RTL's power-up state.

### What is compared

| pin group | rule |
|---|---|
| ADDrive, INT_n, IEO, TxD, RTS_n, DTR_n, TRxCDrive, SYNCDrive (A/B) | every record |
| AD | only while both sides drive it; a drive mismatch is reported as ADDrive |
| TRxCOut (A/B) | only while TRxCDrive |
| SYNCOut (A/B) | only while SYNCDrive |
| register inventory | `F` records after the last `T` (`TICKS`/`POKES` informational); IUSMask per priority level, SDLC_RxHist D31:D14 and SDLC_Residue D3:D1 only; WR0, RxD, RxStopBit, PendingWR0, PendingWR0Cmd and DPLL_RxBit have no RTL state and are neither poked nor compared; WR2 and WR9 read the chip's register, WR8 the transmit buffer |

## What is covered

181 files from 104 tests, all PASS. 128 are pure pin vectors (`F POKES
0`); 53 set the chip up by poke, then run on the pins (TestTickPinsStartBitIsAFullBitWide
alone is 40, one per phase offset).

| area | vectors |
|---|---|
| bus interface | TestTickPinsCSGatesBus, TestTickPinsReadRR0, TestTickPinsDirectWrite, TestTickPinsOneAccessPerAS, TestTickPinsRWAndCS1AtDSFall, TestPins_ReadFloatsAtDSRise, TestPins_CSGatesBothHalves, TestPins_AddressLatchedAtASRise, TestPins_ShiftRightAddressing, TestPins_StrayDSIgnored, TestPins_ReadRegisterImages |
| resets | TestPins_HardwareResetViaASDS, TestPins_BriefASDSOverlapIsNotReset, TestPins_WR9Resets, TestPins_WR9HardwareResetKeepsShiftRight |
| interrupts and acknowledge | TestTickPinsINTOnRxAvailable, TestTickPinsINTACKVector, TestTickPinsIEIBlocksINTACK, TestINTACKVectorFloatsAtDSRise, TestG81_12_IEOIntackAndDLC, TestW2_19_NVFloatsADDuringINTACK (2), TestTickPinsRXInterruptUnderALConfig, TestPins_TxInterrupt, TestPins_RxInterruptINTACKAndIUS, TestPins_RxIntFirstCharOneShot, TestPins_RR3RxIPFollowsInterrupt (2), TestPins_AckTakesOnlyASLatchedRequest, TestPins_IEILowHoldsINT, TestPins_RR2BStatusAfterNVAck, TestPins_RR2BPollingMIEOff |
| ext/status, modem | TestPins_ExtStatusDCD, TestPins_Break, TestPins_AutoEnablesCTS, TestPins_AutoEnablesRTSHold |
| BRG and clock mux | TestPins_BRGTimeConstant (2), TestPins_BRGTimeConstantAtReload, TestPins_BRGChannelResetKeepsCount, TestPins_BRGHardwareResetLoadClock, TestPins_BRGRestartResumesCount, TestPins_BRGStartUp, TestPins_TRxCOutBRG, TestG81_8_BRGSourceRTxC, TestG81_8_ClockMuxRouting (2) |
| async transmit | TestTickPinsTXShiftsOut, TestTickPinsTXAdvancesSerialFSM, TestPins_TX_8N1_x16, TestPins_TX_7E2_x1_Underrun, TestPins_TX_BackToBack, TestPins_TxDisableCompletesCharacter, TestPins_SendBreak, TestPins_SendBreakAtBitCells, TestPins_OneAndAHalfStopBits (3) |
| async receive | TestTickPinsRXDelivers, TestTickPinsStartBitIsAFullBitWide (40), TestPins_RX_8N1_x16, TestPins_RX_FIFOOverrunLatchesAtTop, TestPins_RX_ParityAndFramingErrors, TestPins_RX_BreakLoadsOneNull, TestPins_RX_OneStopBitChecked, TestPins_RX_ShortCharFill, TestPins_RxAllCharsNoLock, TestPins_RxLockedFIFOOverruns, TestPins_RxSpecialLocksFIFO, TestPins_LoopbackTxToRx |
| SDLC and SDLC Loop | TestSDLC* (34 files) |
| monosync, bisync, external sync | TestSync* (22 files) |
| DPLL, NRZI, FM | TestDPLL*, TestEncode* (16 files) |

### Ladder (suggested order, shortest first)

1. TestTickPinsINTOnRxAvailable: `int_latch <= int_pending & iei` at the
   /AS rise, `int_n = ~int_latch`.
2. TestG81_12_IEOIntackAndDLC, TestW2_19_*: IEO, acknowledge with NV (no
   AD drive), IUS.
3. TestTickPinsReadRR0, TestPins_ReadFloatsAtDSRise,
   TestPins_AddressLatchedAtASRise, TestTickPinsRWAndCS1AtDSFall: strobe
   capture, decode at the /AS rise, RR0 read, AD float on /DS High.
4. TestTickPinsCSGatesBus, TestPins_CSGatesBothHalves,
   TestTickPinsDirectWrite, TestTickPinsOneAccessPerAS,
   TestPins_StrayDSIgnored: CS0/CS1 gate, write core, one access per /AS.
5. TestPins_HardwareResetViaASDS, TestPins_BriefASDSOverlapIsNotReset,
   TestPins_WR9Resets, TestPins_WR9HardwareResetKeepsShiftRight: the UM
   reset table (row 7), RTS/DTR from WR5.
6. TestPins_ShiftRightAddressing: WR0B D1:0.
7. TestPins_TxInterrupt, TestTickPinsINTACKVector,
   TestINTACKVectorFloatsAtDSRise, TestPins_RxInterruptINTACKAndIUS,
   TestPins_AckTakesOnlyASLatchedRequest, TestPins_IEILowHoldsINT: Tx IP,
   RR3, vector modification, Reset Highest IUS, the acknowledge latch.
8. TestPins_ExtStatusDCD, TestPins_Break: one-PCLK sample (row 1),
   ext/status latch, WR15 gating.
9. Async transmit, BRG and the /RTS hold.
10. Async receive: midpoint sampling, glitch filter, 3-deep FIFO, error
    FIFO, sticky latch, special receive, one-shot.
11. TestG81_8_*: /RTxC and /TRxC as bit clock and BRG source.
12. TestPins_LoopbackTxToRx.
13. SDLC, byte sync, DPLL and encodings.

### Behaviour the vectors encode

1. **DCD/CTS take one PCLK sample**: a transition is seen one PCLK after
   the pin changes (row 1).
2. **Power-up = hardware reset with idle pins** (WR4 = 04, WR11 = 08,
   WR14 = 20, WR15 = F8, ...; DCD/CTS deasserted), so the first PCLK is not
   a modem transition.
3. **WR0 commands run in the PCLK step that services the /DS-fall
   write** (row 4).
4. **RR0 D7 Break/Abort follows the line** while the ext/status latch is
   open; with the reset WR15 = F8 the break transition itself closes the
   latch unless software wrote WR15 first.
5. **/INT moves only on /AS**: the request reaches the pin latch at an /AS
   rise and is released by the acknowledge /DS fall (row 9). A Z8001
   issues one /AS per transaction, so /INT lags by up to one bus cycle.

### Spec conformance ledger

Verdicts: SPEC = the source settles it and the vectors follow it;
INFERRED = read from the sources, unverified on silicon; OPEN = the
source is silent; the reading taken is stated.

| # | item | source | verdict | behaviour / vectors |
|---|---|---|---|---|
| 1 | DCD/CTS synchroniser depth | z8030 p.633 pin descriptions (Schmitt, pulse detect); p.647 row 21 TwEXT 200 ns; 1988 DB p.280 row 10b TdEXT(INT) = 2..3 /AS units | OPEN | one PCLK from pin to detect |
| 2 | Auto Enables with /CTS High | z8030 p.633 "a Low on the inputs enables the respective transmitters"; UM p.95/p.110 "/CTS High, the transmitter is disabled"; UM p.102, p.153 WR5 D3: a disabled transmitter completes the character in progress | SPEC | the TBR-to-TSR handoff and a character start wait for /CTS; TxD marks; a frame in progress completes; All Sent needs the TBR empty. TestPins_AutoEnablesCTS, TestPins_TxDisableCompletesCharacter |
| 3 | DCD/CTS state after reset | UM p.26-27 reset table: RR0 D3/D5 = X | SPEC | latches and sync at the pin level |
| 4 | WR0 command timing | z8030 p.645 recovery time 6 TcPC + 200 ns; UM p.28 | SPEC | runs in the PCLK step that services the write; no pin effect before the next access |
| 5 | /AS+/DS reset width | z8030 p.648 rows 37-39: no reset <= 30 ns, TwRES >= 250 ns; UM p.26: stretched 4-5 PCLK, accesses ignored | OPEN between 30 and 250 ns | TestPins_HardwareResetViaASDS holds the coincidence two PCLK and idles six before the next access; see row 17 |
| 6 | external clock pins | z8030 p.633 RTxC/TRxC; WR11 p.644 | SPEC | TestG81_8_* drive /RTxC and /TRxC |
| 7 | reset register values | UM p.26-27 reset table and bit text (WR15 p.173, WR14 D4 p.171, WR11 p.74/80, RR1 p.179) | SPEC | WR0 = 0, WR1 &= 24, WR3 &= FE, WR4 \|= 04, WR5 &= 61, WR10 (hardware 0 / channel &= 60), WR11 (hardware 08 / channel kept), WR14 (hardware 20 / channel D5 = 1, D4:2 = 0), WR15 = F8, WR9 D5:2 clear, D1:0 kept, WR2 kept, IUS clear, Shift Left; RR1 D3:1 = 011 in Async. WR14 D4: the table prints 1, the bit text says reset to 0; 0 is taken. TestPins_HardwareResetViaASDS, TestPins_WR9Resets |
| 8 | address, CS0, INTACK latch | z8030 p.645 "latched by the rising edge of AS"; p.633; UM p.21 | SPEC | transparent while /AS is Low, frozen at the rise; decode at the rise. TestPins_AddressLatchedAtASRise |
| 9 | /INT timing | UM p.21 "the IP bits in the Z80X30 are updated by /AS ... may delay interrupt requests if the processor does not supply /AS strobes"; "/INT ... goes inactive in response to the falling edge of /DS"; z8030 p.648 row 28 TdAS(INT); 1988 DB p.280 rows 4b/8b/10b in /AS units | SPEC | the request copied to the /INT latch at every /AS rise; released at the acknowledge /DS fall |
| 10 | IEO and /INTACK | z8030 p.633 "INTACK is latched by the rising edge of AS"; p.648 row 35 TdAS(IEO) | SPEC | IEO uses the /AS-latched INTACK and the /INT latch. TestG81_12_IEOIntackAndDLC |
| 11 | /RTS with Auto Enables | z8030 p.633 RTS: "When the RTS bit is reset in the Asynchronous mode and Auto Enable is on, the signal goes High after the transmitter is empty"; UM p.95, p.154 | SPEC | a 1-to-0 write of WR5 D1 in Async with Auto Enables holds /RTS Low until TSR and TBR are empty. A bit that was never set does not assert the pin. TestPins_AutoEnablesRTSHold |
| 12 | RR1 D0 All Sent | z8030 p.643 WR4 D3:2 = 00 sync modes; UM p.187 "always set in synchronous and SDLC modes" | SPEC | sync case is WR4 D3:2 = 00. TestPins_AutoEnablesCTS |
| 13 | acknowledge vector drive and float | z8030 p.646 Fig 14, p.648 rows 30-31 TdDSA(DR), row 23 TdDS(DRz); UM p.21 IUS set at the /DS fall if IEI High | SPEC | TestINTACKVectorFloatsAtDSRise, TestW2_19_NVFloatsADDuringINTACK |
| 14 | IEI/IEO settle | z8030 p.648 rows 32-35, note 5 | SPEC | settles between the /AS rise and the /DS fall; IEI sampled at the /DS fall |
| 15 | /INT latency vs spec minimum | 1988 DB p.280 row 10b TdEXT(INT) min 2 /AS units, TdRXC(INT) 8 TcPC + 2 /AS | OPEN | the vectors encode one PCLK plus the next /AS, at or below the minimum; no tolerance window |
| 16 | reset stretch (4-5 PCLK, accesses ignored) | UM p.26 | OPEN | not built; no vector accesses inside the window |
| 17 | /AS+/DS reset qualified by width | z8030 p.648 row 39 TwRES "AS and DS Coincident Low for Reset" >= 250 ns vs rows 37/38 "Delay for No Reset" (15-30 ns) | SPEC | reset after two PCLK rises with both strobes Low, so a bus turnaround overlap does not wipe the chip. The threshold is a choice: at 6 MHz PCLK, 250 ns spans one or two rises and 30 ns zero or one. Counting master clocks against 250 ns would separate the bands. TestPins_BriefASDSOverlapIsNotReset, tb_scc_timing [5], [6] |
| 18 | a /DS fall is a data strobe only after an /AS rise | z8030 p.645 read/write timing (address phase ends at the /AS rise, data phase from the /DS fall after it); rows 37/38 | SPEC | the /DS capture is gated on /AS High |
| 19 | R/W and CS1 | 1988 DB p.225 CS1 "must remain active throughout the transaction"; p.237; p.246 rows 5-6 TsCS1(DS)/ThCS1(DS), 9-11 TsRWR(DS)/ThRW(DS)/TsRWW(DS) | SPEC | taken at the /DS fall; an access needs CS1 High there. TestTickPinsRWAndCS1AtDSFall |
| 20 | one access per /AS | Technical Manual 3.1.2 ("the coincidence of CS1 HIGH and DS LOW latches the write data") reads as per /DS; 3.1.3 asks for "only one DS per acknowledge cycle" | INFERRED | the first /DS rise after an /AS spends the select; a further /DS without a new /AS does nothing. TestTickPinsOneAccessPerAS, TestPins_StrayDSIgnored |
| 21 | /INT needs IEI High; acknowledge takes only the /AS-latched request | UM 2.4.5.1, Technical Manual 4.2: /INT Low "only if ... no higher-priority interrupt is being serviced (IEI is High)"; UM: "no additional interrupt requests during an Interrupt Acknowledge cycle" | SPEC | `int_latch <= int_pending & iei` at the /AS rise; a request arising later waits for the next /AS. TestPins_IEILowHoldsINT, TestPins_AckTakesOnlyASLatchedRequest, `make test-scc-iack` |
| 22 | WR9 Force Hardware Reset and Shift Right/Left | UM p.160, p.21 | SPEC | WR9 keeps the Shift Right/Left bit; only the /AS+/DS reset forces Shift Left. TestPins_WR9HardwareResetKeepsShiftRight |

## Known gaps

* Rows 1, 5, 15, 16 OPEN; row 20 INFERRED.
* Not built: SDLC Loop in FM, the sync-mode loop (WR10 D1 outside SDLC),
  /SYNC as an output in SDLC and as an input in async, parity in SDLC,
  Zero Count, the DTR/REQ request and the /W//REQ pins.
* Not audited against the sources: SDLC, byte sync and the DPLL (the
  vectors exist and pass; no ledger rows yet).
* The RTL takes asynchronous inputs in-domain to keep lockstep; a system
  top must put 2-flop synchronisers on RxD, /RTxC, /TRxC, /SYNC, /DCD,
  /CTS and the bus strobes.
