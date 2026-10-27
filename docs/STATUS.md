# Status

`make test`, 2026-10-26. Update when a bench moves.

| bench | command | result |
|---|---|---|
| decode ROM | `make test-decode` | PASS, 135552 checks |
| decode ROM vs table | `make test-decode-table` | PASS, 1048576 checks |
| register file | `make test-regfile` | PASS, 4056 checks |
| ALU | `make test-alu` | PASS, 215 of 215 vector files |
| MULT/DIV/SHIFT | `make test-serial` | PASS, 2874 operations |
| CPU vectors | `make test-cpu` | 6 pass, 912 fail, 92 skip |
| CPU Z-Bus timing | `make test-cpu-timing` | 7 of 12 (monitor clean, 2 transactions) |
| CPU cycle counts | `make test-cpu-cycles` | 45 not run |
| MMU vectors | `make test-mmu` | 6 of 71 |
| MMU timing | `make test-mmu-timing` | 6 of 12 |
| CIO vectors | `make test-cio` | 1 of 110 (52 partial) |
| CIO timing | `make test-cio-timing` | 4 of 14 |
| SCC vectors | `make test-scc` | 0 of 81 |
| SCC timing | `make test-scc-timing` | 2 of 12 |

## Fit

`quartus/build.sh <unit>`, 5CSEBA6U23I7, 48 MHz target, slow corner.

| unit | ALMs | Fmax |
|---|---|---|
| register file | 300 | 135 MHz |
| ALU | 1453 | 60.4 MHz |
| multiplier | 288 | 99.4 MHz |
| divider | 604 | 90.5 MHz |
| shifter | 136 | 175 MHz |

## Next

- CPU: reset pin state, bus unit and the PSA reads pass (`TestResetSequenceZ8002`,
  `TestResetPinState`, `TestResetReadStatusCodes`). Every failing vector diverges at the
  first IF1 T1 on ADDrive, AS_n and ST: tick 28 (clock 14) on Z8002/Z8004, tick 34
  (clock 17) on Z8001/Z8003. Next: rung 2 (IF1, decode hookup, HALT).
- MMU: passes are the "chip does nothing" cases (TestReset.001,
  TestMasterEnableDisabled, TestMMU_URS_SingleMMU.001/.003, TestSegTrapAcknowledge_NotOurs.001,
  TestCmd_UnlistedOpcodeWriteIsNoOp). TestReset.000 fails on one final-state field.
- CIO: passes TestG80_3_MCCRGatesCTTrigger. Shortest failures, TestAddressDecoding and
  TestResetState, diverge at tick 2 on ADDrive.
- SCC: shortest failures diverge on INT_n and IEO within 3 ticks.

## Vector inventory

| device | files | notes |
|---|---|---|
| CPU | 1010 | 92 skipped (restore Go snapshots) |
| CPU cycle counts | 45 | 34 `exact`, 11 `approx` |
| MMU | 71 | from 48 of 49 Go tests |
| CIO | 110 | 52 `X partial` |
| SCC | 81 | 27 pure pin-seam (`F POKES 0`) |
