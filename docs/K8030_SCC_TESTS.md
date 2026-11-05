# k8030_scc (Z8030 SCC) -- vectors, replay harness, and the test ladder

Golden model: Go `sim/scc` (pin seam `pins.go`: `TickPins(Inputs) Outputs`),
recorder `sim/scc/vecdump_test.go`, self-check `hdl/gen/cmd/sccvecverify`.
RTL: `rtl/k8030_scc/z8030_scc.sv` + `z8030_scc_channel.sv`. Harness:
`tb/k8030_scc/tb_scc.cpp` + `scc_access.h`. Vectors: `vectors/k8030_scc/*.vec`.

```
make vectors-scc          record vectors/k8030_scc from the Go suite + sccvecverify self-check
make lint-scc             verilator -Wall on rtl/k8030_scc (zero suppressions)
make build-scc            obj_dir/tb_scc/tb_scc
make test-scc             replay every vector: PASS/FAIL/SKIP + shortest failing first
make ladder-scc           every vector, shortest first, with status
make scc ONLY=TestPins_TX_8N1_x16 [VCD=1] [CONTEXT=20]   one vector, full context
```

## 1. Vector format (`K8000VEC 1 scc`)

One file per Go test x chip instance: `<TestName>.<NNN>.vec`. ASCII, one
record per line, `#` comments, `END` terminates.

```
K8000VEC 1 scc
test TestPins_TX_8N1_x16 0     Go test function, chip instance index
base 0100                      Go New(baseAddr) -- port-decode facade only, informational
P A_WR5 68                     poke: the test changed this register OUTSIDE the pin seam
T 2A7F00 00 03F00 00           one TickPins(Inputs) Outputs call
...
F IntVector A0                 final register inventory (every field, see 1.3)
F ...
F TICKS 1234                   number of T records -- informational
F POKES 0                      number of P records -- informational (0 = pure pin-seam vector)
END
```

`X unsupported <reason>` before the first `T` means SKIP; the SCC recorder
never emits it (see 1.3).

### 1.1 `T` record

`T <in:6hex> <in_AD:2hex> <out:5hex> <out_AD:2hex>`

`in` bit order (bit 21 = MSB): `PCLK AS_n DS_n R_W CS0_n CS1 INTACK_n IEI
RxD_A RxD_B CTS_n_A CTS_n_B DCD_n_A DCD_n_B TRxCIn_A TRxCIn_B TxCIn_A TxCIn_B
RxCIn_A RxCIn_B SYNCIn_A SYNCIn_B`

`out` bit order (bit 16 = MSB): `ADDrive INT_n IEO TxD_A TxD_B RTS_n_A
RTS_n_B DTR_n_A DTR_n_B TRxCOut_A TRxCOut_B TRxCDrive_A TRxCDrive_B
SYNCOut_A SYNCOut_B SYNCDrive_A SYNCDrive_B`

Every TickPins call is recorded verbatim (`vecInBits`/`vecOutBits` in the
recorder; `sccvecverify` has the same tables and must stay in step).

### 1.2 Clocking / what one record means

One TickPins call has two time bases:

* ASYNC, every call: strobe edge capture (/AS, /DS, /INTACK against the
  previous call; AD/R_W/CS/INTACK sampled while /AS is Low and frozen at
  the /AS rise; AD/IEI latched at the /DS fall), the /AS+/DS hardware
  reset, the /AS-rise copy of the interrupt condition onto the /INT latch
  (ledger item 9), and the combinational outputs (INT_n, IEO, AD float on
  /DS High);
* PCLK rise, only when PCLK went 0->1 since the previous call: bus-cycle
  service (read mux, write, INTACK vector), sampling RxD/DCD/CTS/RTxC/TRxC,
  and advancePins (BRG, TX/RX FSMs, deferred WR0 command, ext/status).

The Go tests (`pclkStep`) call TickPins twice per PCLK, but nothing forces
that ratio: `TestINTACKVectorFloatsAtDSRise` adds a call with PCLK unchanged
to prove the /DS-rise float is combinational.

Replay rule: **one `T` record == one posedge of the fabric clock `clk`,
then N-1 more master clocks with the inputs held** (N cycles through the
comma list `--mclk P` / env `K8000_MCLK`, default `1,2,1,3`; `1` = 1:1).
The clock pins are one-master-clock EDGE PULSES from the board divider:
`pclk_rise`, `rxc_rise/rxc_fall`, `trxc_rise/trxc_fall` ([1:0] per channel).
The tb fires a pulse on the first master clock after the record that
changed the recorded level, for exactly one clock. Nothing assumes a gap
between pulses. The RTL no longer derives `pclk_rise`; the port is it.
/RTxC and /TRxC rebuild their level per channel (set by `_rise`, cleared by
`_fall`, a pulse on the current clock counts at once) and sample it only at
PCLK rises against the level at the previous PCLK rise, exactly the Go
`prev*` model, so an edge between PCLK rises is seen as before. Strobe
edges stay `<x>_q & ~<x>_n` (registered previous level vs the CURRENT
input), so a strobe transition in the same record as a PCLK rise is
serviced in that record, async part first, as in Go. Transitions between
PCLK rises wait in pending flags (Go `pinPending*`).

Per record the tb runs `clk=0; eval; drive inputs + pulses; clk=1; eval;
clear pulses; eval; extra clocks; compare`. Pokes (`P`) are applied between
records and settled with an `eval()`.

### 1.3 `P` pokes and `F` final state (register inventory)

Field names are the Go `Snapshot` names (reflection in `sim/scc/vecfields.go`):
chip-level bare (`IntVector IntPending ShiftRight IUSMask`), per channel
prefixed `A_`/`B_`, arrays suffixed with the index (`A_WR5`, `B_RxFIFOData2`).
Excluded: `Version`, `BaseAddr`/`AddrMask` (chip select is a pin), sim-only
`TXData`, legacy `RxBuf/RxAvail/RxErr`. `scc_access.h` maps every name to an
RTL register; an unknown name SKIPs the vector (poke) or fails it (F).

Pokes, not `X unsupported`: 11 of the 16 older TickPins tests set the chip up
through the functional facade (`ioWrite`, `rxPush`, `updateIntPending`,
`GetTXData`) before or between pin ticks. The recorder snapshots the
inventory around every call and emits the diff as pokes; pin records stay
verbatim. `F POKES 0` marks a pure pin-seam vector (the `TestPins_*` suite
plus 5 older tests).

Inventory `RxD`/`TxD` are the PCLK-sampled RxD register and the TxD output
register. Live `DCD`/`CTS` levels are not in the snapshot: they are
re-sampled from the pins every PCLK rise before use.

## 2. What is compared, when

| pin group | rule |
|---|---|
| ADDrive, INT_n, IEO, TxD[A/B], RTS_n[A/B], DTR_n[A/B], TRxCDrive[A/B], SYNCDrive[A/B] | every record |
| AD | only when both the Go model and the RTL drive it (`ADDrive && ad_drive`); a drive mismatch is reported as ADDrive |
| TRxCOut[A/B] | only while the Go model drives it (TRxCDrive) |
| SYNCOut[A/B] | only while the Go model drives it (never: SYNC output is unmodeled) |
| register inventory | `F` records after the last `T` (all fields; `TICKS`/`POKES` informational) |

Sim-only constructs never reach a vector: `TXCallback`, `Diag*` counters,
`TXData`/`GetTXData`, `advance()`'s virtual clock, `resetChannel`'s TXData
drain, all of `feed.go`. `sccvecverify` (run by `make vectors-scc`) replays
every vector into a fresh Go `New(base)` (pokes via `Snapshot.SetVecField` +
`LoadState`) and requires bit-exact outputs, AD included while floating, and
the exact final inventory.

The Z8030 has no reset pin (hardware reset = /AS+/DS Low) and the RTL has
no reset port. tb_scc.cpp idles two PCLKs, holds /AS and /DS Low across three
PCLK rises (the RTL needs two), then idles six PCLKs; that leaves the Go
`New()` state. A board resets the chip the same way, through the pins.

## 3. Coverage: which Go tests became vectors

`sim/scc` has 68 older tests plus 22 `TestPins_*` in `k8000_pins_test.go`.
Of 92 Go tests, 39 record 81 vectors; 53 record nothing (section 4).

Pure pin-seam vectors (`F POKES 0`, 27 files):

| vector | ticks | exercises |
|---|---|---|
| TestTickPinsCSGatesBus | 8 | deselected cycle writes nothing |
| TestTickPinsReadRR0 | 8 | RR0 read, AD driven at /DS fall |
| TestPins_ReadFloatsAtDSRise | 11 | AD floats at /DS rise with no PCLK edge |
| TestPins_CSGatesBothHalves | 24 | /CS0 AND CS1 |
| TestTickPinsDirectWrite | 24 | WR5/WR0/WR1 direct writes, no register pointer |
| TestPins_AddressLatchedAtASRise | 24 | AD and /CS0 taken at /AS rise (last value while /AS Low), not at the fall |
| TestPins_ShiftRightAddressing | 64 | Shift Right/Left, A//B on AD0 vs AD5, B-only |
| TestPins_WR9Resets | 72 | WR9 channel reset per the reset table (WR3 D0 only, WR11 kept, WR15=F8, WR2/WR9 kept); hardware reset keeps VIS and WR2 |
| TestPins_HardwareResetViaASDS | 100 | /AS+/DS reset (2 PCLK wide >= TwRES, 6 idle PCLK after): reset-table WR3/WR5/WR11/WR15/WR4, RR0=44, RR1=07, RR15=F8, WR2 kept, RTS/DTR deassert |
| TestPins_TxInterrupt | 120 | Tx IP on TBR->TSR, INT_n only after an /AS strobe, RR3, Reset Tx IP (INT_n holds until the next /AS) |
| TestPins_ExtStatusDCD | 128 | DCD sample + latch + Reset Ext/Status; CTS with WR15 D5 clear; INT_n via /AS strobes |
| TestPins_Break | 248 | break set/release ext/status, RR0 D7 latch |
| TestPins_RxInterruptINTACKAndIUS | 248 | INT_n (after /AS), RR2 A/B, RR3, INTACK vector, IEO, Reset Highest IUS |
| TestPins_TX_7E2_x1_Underrun | 264 | 7 bits, even parity, 2 stop, x1; Tx Underrun/EOM latch + WR0 D7:6 reset |
| TestPins_AutoEnablesCTS | 360 | /CTS High: TxD marks, byte HELD in the TBR (RR0 D2 clear, All Sent clear); sent intact once /CTS asserts |
| TestPins_RxIntFirstCharOneShot | 380 | Rx int mode 01 one-shot + WR0 cmd 4 re-arm |
| TestPins_TxDisableCompletesCharacter | 424 | WR5 D3 cleared mid-frame: frame completes, queued TBR byte waits, sent after re-enable |
| TestTickPinsTXShiftsOut | 448 | full firmware-style TX programming, x1 BRG |
| TestPins_RX_FIFOOverrunLatchesAtTop | 480 | 4 frames, overrun on the newest, latch at FIFO top |
| TestPins_RX_ParityAndFramingErrors | 544 | 7-bit odd parity RX at x1; RR1 D4 sticky, D6 follows head, Error Reset (WR15 written 0 first) |
| TestPins_AutoEnablesRTSHold | 1586 | WR5 D1 cleared mid-frame with Auto Enables: /RTS stays Low until All Sent; without Auto Enables it follows the bit |
| TestPins_TX_8N1_x16 | 2424 | TxD waveform 8N1 x16, bit width, RR1 All Sent |
| TestPins_BRGTimeConstant (2) | 1616 / 3920 | start-bit width = 16*2*(TC+2) for TC=0,3 |
| TestPins_LoopbackTxToRx | 3184 | TxD_B -> RxD_B loopback, two bytes at x16 |
| TestPins_TX_BackToBack | 3184 | two contiguous frames, TBR frees on PCLK |
| TestPins_RX_8N1_x16 | 4088 | three RX frames at x16, RR8 pop order |

Vectors with pokes (53 files): TestTickPinsINTOnRxAvailable, TestG81_12_
IEOIntackAndDLC, TestW2_19_NVFloatsADDuringINTACK (2), TestTickPins
IEIBlocksINTACK, TestTickPinsINTACKVector, TestINTACKVectorFloatsAtDSRise,
TestTickPinsRXDelivers, TestTickPinsTXAdvancesSerialFSM, TestG81_8_
BRGSourceRTxC, TestG81_8_ClockMuxRouting (2), TestTickPinsRXInterrupt
UnderALConfig, TestTickPinsStartBitIsAFullBitWide (40 -- one per phase
offset). Pin records are verbatim; only setup arrives as pokes.

## 4. NOT vectorizable (52 tests) -- and why

These never call `TickPins`, so there is nothing to record. The last column
names the pin-seam test covering the same behaviour.

| test | reason | pin-seam counterpart |
|---|---|---|
| bitlevel_test.go: TestRX_BitLevel_X1, TestRX_BitLevel_X16, TestRX_Break, TestTX_BitLevel_X1, TestTX_RX_Loopback | `setRxD`+`advance()` (virtual clock, feed.go class) | TestPins_RX_8N1_x16, _Break, TestPins_TX_*, _LoopbackTxToRx |
| intack_test.go: TestSCC_IntACK_RXAvailable, TestSCC_IntACK_NoInterrupt | `intAck()` function call, `FeedByteRX` | TestPins_RxInterruptINTACKAndIUS |
| scc_g81_test.go: TestG81_3_RxFIFODepth, TestG81_4_ErrorFIFOAndLatch | `FeedByteRX*` + `ioRead` | TestPins_RX_FIFOOverrunLatchesAtTop, _RX_ParityAndFramingErrors |
| scc_g81_test.go: TestG81_5_RR0FollowsPinsUntilLatched | `setModem` + `advance()` | TestPins_ExtStatusDCD |
| scc_g81_test.go: TestG81_6_IntAckNVAndVIS, TestG81_6_WR9ResetRetainsControlBits, TestG81_9_ChannelResetArmsFirstChar | `ioWrite` + `intAck()` / direct field peeks | TestW2_19 (pokes), TestPins_WR9Resets |
| scc_g81_test.go: TestG81_10_WR8ClearsTxIPAndBuffersWhileDisabled, TestG81_11_TxUnderrunEOMLatch | `ioWrite` + `advance()` + `GetTXData` | TestPins_TxInterrupt, TestPins_TX_7E2_x1_Underrun |
| scc_test.go: TestDirectRegisterRead, TestWR0LowBitsDoNotRedirect, TestShiftRightMode, TestSCCInitSequence, TestAddressDecoding, TestMasterReset | `ioRead`/`ioWrite` port facade (AddrMask decode is not a chip function) | TestTickPinsDirectWrite, TestPins_ShiftRightAddressing, _HardwareResetViaASDS |
| scc_test.go: TestTXData, TestTXDirectWR8, TestTXEnableGate, TestTXInterruptPending, TestTXInterruptChannelB | `advance()` + `GetTXData`/`TXCallback` (sim-only observers) | TestPins_TX_*, TestPins_TxInterrupt |
| scc_test.go: TestRXData, TestRXEnableGate, TestRXInterruptPending, TestRXInterruptChannelB, TestFeedByteRX_DirectWR, TestEnableInterruptOnNextRX | `FeedByteRX` (feed.go) | TestPins_RX_*, _RxIntFirstCharOneShot |
| scc_test.go: TestRR0Bits, TestRR1ErrorBits, TestModemInputsAndExtInterrupt | `setModem`/`FeedByteRXWithError` + `advance()` | TestPins_ExtStatusDCD, _RX_ParityAndFramingErrors |
| scc_test.go: TestInterruptVector, TestSpecialReceiveConditionVector, TestBUG_SCC_1/2/3/5/6a/6b/6c/7/8/9, TestG81_2_TxOutranksExtStatus | `intAck()`/`intSource` + facade | TestPins_RxInterruptINTACKAndIUS (partial); priority/IUS fence and special-condition vectors still Go-only |
| snapshot_roundtrip_test.go: TestSnapshotRoundTripIUSMask, TestSnapshotRoundTripExtLatchBits | gob snapshot round trip, no chip activity | n/a |
| w2_scc_test.go: TestW2_20_StickyErrorLatchesAtFIFOTop, TestW2_21_ExtLatchFreezesBreakAndUnderrun | `FeedByteRX*` / `setModem` + `advance()` | TestPins_RX_FIFOOverrunLatchesAtTop, _Break, _ExtStatusDCD |

Not covered by any vector (all pin-drivable): interrupt priority fence across sources
(BUG_SCC_5), special-receive-condition vectors and WR1 D2 parity-special
(BUG_SCC_6*), Status High vector modification on the pins (BUG_SCC_8),
Tx-outranks-ext-status (G81_2), x32/x64 clock modes, 5/6-bit characters,
1.5 stop bits, TRxC-as-output (WR11 D2) levels, DLC.

## 5. Ladder (suggested order, shortest first)

1. `TestTickPinsINTOnRxAvailable` (6 ticks, pokes) -- `int_latch <= int_pending` at /AS rise, `int_n = ~int_latch`.
2. `TestG81_12_IEOIntackAndDLC`, `TestW2_19_*` -- IEO equation, INTACK
   with NV (no AD drive), IUS latch.
3. `TestTickPinsReadRR0`, `TestPins_ReadFloatsAtDSRise`,
   `TestPins_AddressLatchedAtASRise` -- strobe capture, /AS-rise-latched
   decode (transparent while Low), RR0 read mux, AD triplet + /DS-High float.
4. `TestTickPinsCSGatesBus`, `TestPins_CSGatesBothHalves`,
   `TestTickPinsDirectWrite` -- CS0/CS1 gate, write core, WR0 not a pointer
   (final-state checks).
5. `TestPins_HardwareResetViaASDS`, `TestPins_WR9Resets` -- reset paths
   per the UM reset table (section 7 item 7), RTS/DTR from WR5, RR1/RR2/RR15.
6. `TestPins_ShiftRightAddressing` -- WR0B D1:0.
7. `TestPins_TxInterrupt`, `TestTickPinsINTACKVector`,
   `TestINTACKVectorFloatsAtDSRise`, `TestPins_RxInterruptINTACKAndIUS`
   -- TBR->TSR on PCLK, Tx IP, RR3, vector modification, Reset Highest IUS.
8. `TestPins_ExtStatusDCD`, `TestPins_Break` -- sync chain (see 6.1!),
   ext/status latch bank, WR15 gating.
9. `TestPins_TX_7E2_x1_Underrun`, `TestTickPinsTXShiftsOut`,
   `TestPins_TX_8N1_x16`, `TestPins_BRGTimeConstant`, `TestPins_TX_BackToBack`,
   `TestPins_AutoEnablesCTS`, `TestPins_TxDisableCompletesCharacter`,
   `TestPins_AutoEnablesRTSHold` -- BRG, WR11 mux, TX FSM incl. txPending,
   parity, stop bits, underrun, the transmitter-enable rules and the /RTS hold.
10. `TestPins_RX_*`, `TestPins_RxIntFirstCharOneShot`, `TestTickPinsRXDelivers`,
    `TestTickPinsStartBitIsAFullBitWide` (40) -- RX FSM, midpoint sampling,
    glitch filter, 3-deep FIFO + error FIFO + sticky latch, one-shot.
11. `TestG81_8_*` -- external clocks RTxC/TRxC as bit clock and BRG source
    (modelled in TickPins).
12. `TestPins_LoopbackTxToRx` -- everything together.

## 6. Things worth knowing about the Go model

1. **DCD/CTS sampling is one PCLK stage.** `advancePins` does
   `sync0 = live; sync1 = sync0` with Go blocking semantics, so `sync1` is
   this PCLK's sample and a transition is seen one PCLK after the pin
   changes. Non-blocking RTL would give two stages: write
   `dcd_sync1 <= dcd_live`, or change the model too. Zilog does not specify
   the stage count (ledger item 1); the vectors encode one.
2. **Power-up == hardware reset with idle pins.** `New()` applies the reset
   table (WR4=04, WR11=08, WR14=20, WR15=F8, ...) to a zeroed chip with
   DCD/CTS deasserted, matching `defaultInputs()`, so the first PCLK is
   not a modem transition. The RTL `initial` values are these.
3. **Deferred WR0 commands execute on the PCLK rise that services the
   /DS-fall write** (writeReg sets `pendingWR0`; `advancePins` applies it
   in the same rise). The pins cannot tell before the next access (item 4).
4. **Hardware reset (Go) resets on any sample of /AS+/DS Low.** Silicon:
   >= 250 ns (TwRES) resets, <= 30 ns must not, in between unspecified. The
   reset vector holds the coincidence two PCLK and idles six PCLK before
   the next access (the UM stretches reset 4-5 PCLK and ignores accesses
   meanwhile), so a width-qualified RTL replays it identically (item 5).
5. **RR0 D7 Break/Abort follows the line** while the ext/status latch is
   open; with the reset value WR15 = F8 the break transition itself
   closes the latch (Break/Abort IE) unless software wrote WR15 first.
6. **External clock pins ARE modeled** in TickPins (RxCIn as RTxC, TRxCIn;
   `TestG81_8_*` vectors drive them). TxCIn/SYNCIn are accepted and
   ignored (item 6).
7. `TRxCOut` is the raw `trxcOutLevel` even when WR11 D2 is clear; the tb
   compares it only while TRxCDrive is set.
8. **/INT is clocked by /AS.** `IntPending` (PCLK side) is copied to the
   pin latch only at an /AS rise (any cycle) and at the INTACK /DS fall;
   `INT_n = !intLatch`. Tests use `k8Strobe` (an unselected /AS pulse) in
   place of the CPU's next bus cycle (item 9). `IEO` uses the /AS-latched
   INTACK and the pin latch (item 10).

## 7. Spec conformance ledger

The target is the hardware: the Go model was fixed where the primary
sources are unambiguous and the vectors re-recorded. Sources: z8030_scc.pdf
(= 1985 data book pp.631-652); 1988 Z8000 Family Data Book (Z8030/Z8530
spec, pp.253-288); Zilog SCC/ESCC User Manual UM010903 (printed folios).
Each Go fix carries the datasheet-cited regression test named in the last
column.

| # | item | source | verdict | change / OPEN |
|---|---|---|---|---|
| 1 | DCD/CTS "two-FF" sync is one PCLK stage | z8030 p.633 pin desc (Schmitt, pulse detect); p.647 row 21 TwEXT 200 ns; 1988 DB p.280 row 10b TdEXT(INT) Z8030 = 2..3 /AS units | OPEN (unspecified internally) | no change; field comments corrected (`dcdSync0/1` in scc.go). Vectors encode 1 PCLK pin->detect. |
| 2 | Auto Enables + /CTS High dropped a byte moved into the TSR | z8030 p.633 "a Low on the inputs enables the respective transmitters"; UM p.95/p.110 "/CTS High, the transmitter is disabled"; UM p.102 + p.153 WR5 D3: a disabled transmitter completes the character in progress | Go WRONG -> FIXED | `txEnabled()` gates the TBR->TSR handoff and the start of a character; idle/pending hold with TxD marking; a frame in progress completes; All Sent needs TBR empty too. Tests `TestPins_AutoEnablesCTS`, `TestPins_TxDisableCompletesCharacter`. |
| 3 | New() latched DCD/CTS asserted vs pins deasserted | UM p.26-27 reset table: RR0 D3/D5 = X after reset | Go artifact -> FIXED | `New()` = hardware reset with idle pins (DCD/CTS deasserted, latches/sync at the pin level). Facade tests that assumed asserted lines now assert them explicitly. |
| 4 | deferred WR0 command executes on the same PCLK rise as the /DS-fall write | z8030 p.645 recovery time 6 TcPC + 200 ns is the only bound; UM p.28 "internal operation" | CONFIRMED (no pin effect) | comments corrected (no "DS rise" claim). |
| 5 | /AS+/DS reset has no width qualifier | z8030 p.648 rows 37-39: no-reset <= 30 ns, TwRES >= 250 ns; UM p.26: stretched 4-5 PCLK, accesses ignored | OPEN in the 30..250 ns window; vector made spec-safe | `TestPins_HardwareResetViaASDS` holds the coincidence 2 PCLK and idles 6 PCLK before the next access. Go still resets on any observation (legal for >= TwRES; the RTL may add a TwRES counter without a vector change). |
| 6 | external clock pins modeled | z8030 p.633 RTxC/TRxC pin descriptions; WR11 (p.644) | Go RIGHT | `TestG81_8_*` vectors drive TRxC/RTxC. |
| 7 | reset register values | UM p.26-27 reset table + per-bit text (WR15 bits p.173, WR14 D4 p.171, WR11/BRG source p.74/80, RR1 residue p.179) | Go WRONG -> FIXED | `resetChannel(ch, hw)`/`hardwareReset` apply the table: WR0=0, WR1&=24, WR3&=FE, WR4|=04, WR5&=61, WR10 (hw 0 / ch &=60), WR11 (hw 08 / ch kept), WR14 (hw 20 / ch D5=1 D4:2=0), WR15=F8, WR9 D5:2 clear with D1:0 kept, WR2 kept, IUS clear, Shift Left; RR1 D3:1 = 011 always (Async forces it). WR14 D4: table prints 1, bit text says reset -> 0 (noted). Tests `TestPins_HardwareResetViaASDS`, `TestPins_WR9Resets`, `TestMasterReset`. |
| 8 | address/CS0/INTACK latched at /AS fall | z8030 p.645 "latched by the rising edge of AS" (x3), p.633 CS0/INTACK; UM p.21 | Go WRONG (spec-shape; no legal-cycle pin effect) -> FIXED | transparent while /AS Low, frozen at the rise; decode at /AS rise. Test `TestPins_AddressLatchedAtASRise`. |
| 9 | /INT asserted on the PCLK the condition arises | UM p.21 "the IP bits in the Z80X30 are updated by /AS ... may delay interrupt requests if the processor does not supply /AS strobes" (Z85X30: by PCLK, p.30); z8030 p.648 row 28 TdAS(INT); 1988 DB p.280 rows 4b/8b/10b in /AS units | Go WRONG -> FIXED | `intLatch` copied from `IntPending` at every /AS rise and at the INTACK /DS fall (UM p.21 "/INT ... goes inactive in response to the falling edge of /DS"); `INT_n = !intLatch`. Snapshot v9 `IntLatch`. Tests: every INT_n check now follows a `k8Strobe`. |
| 10 | IEO drops at the raw /INTACK pin fall | z8030 p.633 "INTACK is latched by the rising edge of AS", p.648 row 35 TdAS(IEO) applies to a requesting SCC | Go WRONG -> FIXED | IEO uses the /AS-latched INTACK and the /INT latch. Test `TestG81_12_IEOIntackAndDLC`. |
| 11 | /RTS follows WR5 D1 strictly | z8030 p.633 RTS pin: "When the RTS bit is reset in the Asynchronous mode and Auto Enable is on, the signal goes High after the transmitter is empty"; UM p.95, p.154 "remains Low until the transmitter is completely empty and the last stop bit has left the TxD pin" | Go WRONG -> FIXED | `rtsHold` armed by a 1->0 write of WR5 D1 in Async + Auto Enables while not All Sent; released when TSR+TBR empty. Snapshot v9 `RtsHold`. Test `TestPins_AutoEnablesRTSHold`. A bit that was never set does not assert the pin (the text only describes the set->reset case). |
| 12 | RR1 D0 All Sent forced 1 in Async | z8030 p.643 WR4 D3:D2 = 00 Sync Modes Enable / 01,10,11 stop bits; UM p.187 "always set in synchronous and SDLC modes" | Go WRONG (test inverted) -> FIXED | `readRR1` uses WR4 D3:D2 == 00 for the sync case. Covered by `TestPins_AutoEnablesCTS` (All Sent clear with a byte parked). |
| 13 | INTACK vector drive/float | z8030 p.646 Fig 14 + p.648 rows 30-31 (vector after /DS fall, TdDSA(DR) 250 ns), row 23 TdDS(DRz) float at /DS rise; UM p.21 IUS set at /DS fall if IEI High | Go RIGHT | unchanged; `TestINTACKVectorFloatsAtDSRise`, `TestW2_19_*`. |
| 14 | IEI/IEO chain settle | z8030 p.648 rows 32-35 + note 5 (settles between /AS rise and /DS fall); IEI sampled at /DS fall | Go RIGHT | unchanged. |
| 15 | INT latency vs spec minimum | 1988 DB p.280 row 10b: TdEXT(INT) min 2 /AS units (Z8030), TdRXC(INT) 8 TcPC + 2 /AS | OPEN | the Go pipeline (1 PCLK + next /AS) is at or below the spec minimum; the vectors encode Go. An RTL with more latency would need an INT_n tolerance window -- not added (it would blind the compare). |
| 16 | reset stretch (4-5 PCLK, accesses ignored) | UM p.26 | OPEN (unmodeled) | vectors never access inside the window (item 5). |
| 17 | /AS+/DS reset qualified by WIDTH, not level | z8030 p.648 row 39 TwRES "AS and DS Coincident Low for Reset" >= 250 ns, vs rows 37/38 naming 15-30 ns approaches "Delay for No Reset": the spec separates reset from bus turnaround BY DURATION | Go WRONG -> FIXED | the model reset on any single sample of the coincidence, so strobe edges landing in one sample wiped a configured chip (clearing WR5 Tx Enable mid-boot; the driver then polled RR0 Tx Buffer Empty forever). Now counts PCLK rising edges with both strobes Low, threshold 2. `TestPins_BriefASDSOverlapIsNotReset`; `tb_scc_timing` [6]. **The threshold is a modelling choice**: at 6 MHz PCLK (166.7 ns) 250 ns spans 1 or 2 rising edges and 30 ns 0 or 1, so edge counting cannot separate the bands at one edge; 2 favours not wiping the chip. **RTL must count FABRIC clocks against 250 ns**, which removes the ambiguity. |
| 18 | a /DS fall is a data strobe only after an /AS rise | z8030 p.645 Read/Write Cycle Timing (the address phase ends at the /AS rise and the data phase runs from the /DS fall after it); rows 37/38 exist precisely to keep the strobes from overlapping | Go WRONG -> FIXED | cycle ownership latched at the /AS rise was never cleared, so a /DS fall with no new /AS rise replayed a write to the last decoded register with whatever was on AD (seen as a stray WR11 = 0x00). The capture is now gated on /AS High. Same family as R-CIO-409 (ownership outliving its cycle), opposite remedy: the CIO tears down before the latch, the SCC qualifies the strobe. RTL: gate the ds_fall capture on `as_n`. |

Not audited: SDLC/sync, DPLL, W/REQ, SYNC pin, ZC interrupt.

System consequences: /INT moves only on an /AS strobe; the Z8001 issues one
per transaction, so /INT lags by up to one bus cycle. After a WR9 hardware
reset WR15 = F8 (ext/status sources enabled until the driver writes WR15)
and RR2 keeps the programmed vector.
