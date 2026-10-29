# Status

`make test`, 2026-10-29. Update when a bench moves.

| bench | command | result |
|---|---|---|
| decode ROM | `make test-decode` | PASS, 135552 checks |
| decode ROM vs table | `make test-decode-table` | PASS, 1048576 checks |
| program ROM vs table | `make test-mc-table` | PASS, 1054835 checks (434 forms, 236 programs) |
| register file | `make test-regfile` | PASS, 4056 checks (port B on the byte and word cases) |
| ALU | `make test-alu` | PASS, 270 of 270 vector files (79862 records, 10546 long as two word passes, 39 out-of-contract skipped) |
| MULT/DIV/SHIFT | `make test-serial` | PASS, 3030 operations |
| Refresh prescaler | `make test-refresh` | PASS, 7 checks |
| Instruction word capture | `make test-seq-words` | PASS, 17 cases (address register and words 1, 2) |
| Program paths and repeats | `make test-seq-paths` | PASS, 20 cases (JP/RET cc taken and not taken, shift counts, LDM counts and lengths) |
| Condition codes | `make test-cond` | PASS, 256 checks (16 codes, every C Z S P/V) |
| CPU vectors | `make test-cpu` | 846 pass, 335 fail, 17 skip |
| CPU Z-Bus timing | `make test-cpu-timing` | 11 of 12 (monitor clean; I/O not run) |
| CPU cycle counts | `make test-cpu-cycles` | 28 of 45 pass (register, immediate, byte/word IR and DA, branch and stack rows), 17 not run |
| MMU vectors | `make test-mmu` | 6 of 71 |
| MMU timing | `make test-mmu-timing` | 6 of 12 |
| CIO vectors | `make test-cio` | 1 of 110 (52 partial) |
| CIO timing | `make test-cio-timing` | 4 of 14 |
| SCC vectors | `make test-scc` | 0 of 81 |
| SCC timing | `make test-scc-timing` | 2 of 12 |

## Fit

`quartus/build.sh <unit>`, 5CSEBA6U23I7, 48 MHz target, slow corner; worst paths in
`results/quartus/<unit>.txt`.

| unit | ALMs | Fmax |
|---|---|---|
| register file (two read ports) | 399 | 130 MHz |
| ALU | 205 | 101 MHz |
| multiplier | 261 | 97.5 MHz |
| divider | 779 | 62.4 MHz |
| shifter | 136 | 175 MHz |
| execute unit + register file + ALU | 524 | 63.5 MHz |
| CPU, Z8001 (the program ROMs drive the bus; FCW flags reach it through the condition code, so the ALU and register file stay) | 3680 | 53.9 MHz (worst: instruction word to a unified op's pass flag through the program ROMs) |

## Next

- CPU: every instruction runs its machine-cycle program from the generated program
  ROM. Decode is registered and looks ahead; address words build an address register;
  the condition code and the LDM, EPU and shift counts choose paths and repeats, and
  the sources not built yet are named tie-offs. A cycle the sequencer cannot run sets a
  sticky flag that fails the vector. Rungs 2 and 3 pass. Byte, word and long
  reads and stores with IR, DA, X, BA, BX and RA addresses run, and so does byte
  and word read-modify-write; segmented Z8001 vectors cover each. JP, JR,
  CALL, CALR, RET, DJNZ/DBJNZ and every PUSH/POP form run, segmented
  included, and so do DI/EI, the flag ops, LDCTLB, TCC, DAB, EXTS, EX, RLDB/RRDB,
  LDA and LDAR, LDCTL, LDPS, IRET, LDM and translate (single and repeat), with
  the stack pointer swap on a mode change (R14 and R15 on a Z8001). The two
  failing new vectors are round trips through SC, which is not built. Privileged instructions are not trapped
  in normal mode yet. Next: MULT/DIV, then block ops and IN/OUT. Interrupt sampling,
  abort and BUSREQ are not wired.
- MMU: passes are the "chip does nothing" cases (TestReset.001,
  TestMasterEnableDisabled, TestMMU_URS_SingleMMU.001/.003, TestSegTrapAcknowledge_NotOurs.001,
  TestCmd_UnlistedOpcodeWriteIsNoOp). TestReset.000 fails on one final-state field.
- CIO: passes TestG80_3_MCCRGatesCTTrigger. Shortest failures, TestAddressDecoding and
  TestResetState, diverge at tick 2 on ADDrive.
- SCC: shortest failures diverge on INT_n and IEO within 3 ticks.

## Vector inventory

| device | files | notes |
|---|---|---|
| CPU | 1192 | 17 skipped (restore Go snapshots, or set a refresh pending directly) |
| CPU cycle counts | 45 | 35 `exact`, 10 `approx` |
| MMU | 71 | from 48 of 49 Go tests |
| CIO | 110 | 52 `X partial` |
| SCC | 81 | 28 pure pin-seam (`F POKES 0`) |
