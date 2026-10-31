# Status

`make test`, 2026-10-30. Update when a bench moves.

| bench | command | result |
|---|---|---|
| decode ROM | `make test-decode` | PASS, 135552 checks |
| decode ROM vs table | `make test-decode-table` | PASS, 1048576 checks |
| program ROM vs table | `make test-mc-table` | PASS, 1054835 checks (434 forms, 236 programs) |
| register file | `make test-regfile` | PASS, 4056 checks (port B on the byte and word cases) |
| ALU | `make test-alu` | PASS, 360 of 360 vector files (80302 records, 10546 long as two word passes, 39 out-of-contract skipped) |
| MULT/DIV/SHIFT | `make test-serial` | PASS, 3030 operations |
| Refresh prescaler | `make test-refresh` | PASS, 7 checks |
| Instruction word capture | `make test-seq-words` | PASS, 17 cases (address register and words 1, 2) |
| Program paths and repeats | `make test-seq-paths` | PASS, 20 cases (JP/RET cc taken and not taken, shift counts, LDM counts and lengths) |
| Condition codes | `make test-cond` | PASS, 256 checks (16 codes, every C Z S P/V) |
| CPU vectors | `make test-cpu` | 1284 pass, 0 fail, 17 skip (Z8001 420 of 420, Z8002 844 of 844, Z8003 5 of 5, Z8004 15 of 15) |
| CPU Z-Bus timing | `make test-cpu-timing` | PASS, 13 checks (I/O with /WAIT included) |
| CPU cycle counts | `make test-cpu-cycles` | PASS, 45 of 45 |
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
| divider | 797 | 69.9 MHz |
| shifter | 136 | 175 MHz |
| execute unit + register file + ALU | 524 | 63.5 MHz |
| CPU, Z8001 (the program ROMs drive the bus; the multiplier, divider and shifter included; the shift, dynamic bit and multi-micro work sits in the CPU glue on ports A and B) | 5582 | 48.5 MHz (49.6 at the other corner; worst: execute's operand-cycle state into the sequencer's program register) |

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
  the stack pointer swap on a mode change (R14 and R15 on a Z8001). SC and the
  privileged-instruction trap in normal mode run the trap entry (aborted IF1,
  status pushes, PSA reads), segmented included. MULT, MULTL,
  DIV and DIVL run in every operand form, segmented included, with the serial units
  stepping on the program's clocks and their operands read on ports A and B. IN/OUT
  and SIN/SOUT, block transfer, compare, string compare and block I/O (single and
  repeat, segmented included) run; an interrupt, a refresh or a bus request between block
  elements is taken. Refresh runs after an IF1 (aborted too), an
  internal operation or a block element, and the STOP stream runs after an IF1. NVI, VI and NMI are sampled at the
  instruction's last cycle (and by HALT, which leaves on two samples) and run the
  acknowledge entry, the VI through its vector table (the identifier doubled on both
  CPUs). Up to two skipped refreshes are owed, one issued per boundary. SLA/SLL/SDA/SDL run through the serial shifter, one
  position per I3; BIT/SET/RES with a register bit number, and MSET/MRES/MBIT/MREQ
  with the /MO and /MI handshake, run, segmented included. MULT/MULTL/DIV/DIVL write registers and flags on the program's last clock,
  but a clock later when the operand arrives so late that the zero path, or a wide
  quotient's work, ends on the arrival's clocks alone (no CPU program delivers an
  operand that late; only the serial bench does). A byte or word immediate op
  writes its register and flags as its word's T3 opens. A bus request is granted at any machine-cycle boundary
  (/BUSACK, AD released, `bus_drive` Low for the other outputs, the units held) and
  released two clocks after /BUSREQ rises; TSET grants none between its read and write,
  and `bus_lock` stays High through the write's T3. On a Z8003/Z8004 /ABORT,
  sampled at a memory transaction's T2 and its waits, ends the instruction as
  that cycle's T3 ends; the requests sampled there, SEGT/SAT among them, take
  the entry. An EPU instruction with EPA clear traps after its IF1; with EPA
  set its transfers run: memory (1010, a store with AD released), registers
  (1 to 16 words) and the flag byte (a byte on AD7:AD0) (1110, I/O timing
  with its automatic wait). STOP is
  sampled before an EPU instruction's second word as before an IF1. Rung 10
  is done.
- CPU rework after the last rung: the core must close 48 MHz with its ROMs in logic.
  Moving the program ROMs to M10K/MLAB is optional and must keep a logic-only build (a
  registered read needs the lookup re-pipelined). Negate the divider's operands over
  its setup clocks with a high-half compare (768 ALMs; the path is still picked on
  clock 3).
- CPU: an interrupt pending while EI, LDCTL FCW, LDPS or IRET enables it is taken
  at the next boundary, and a DI before the sample masks it. An SC, trap or
  interrupt entry whose new FCW enables a pending request (or with an NMI held
  through it) takes it before the handler's first instruction. Done.
- CPU: shifts with counts 0 and 1 under refresh, and a bus request held
  mid-shift, have vectors. Done.
- CPU: a refresh among a shift's internal clocks holds the shifter's step, so its
  last position lands on the program's last clock. Done.
- MMU: passes are the "chip does nothing" cases (TestReset.001,
  TestMasterEnableDisabled, TestMMU_URS_SingleMMU.001/.003, TestSegTrapAcknowledge_NotOurs.001,
  TestCmd_UnlistedOpcodeWriteIsNoOp). TestReset.000 fails on one final-state field.
- CIO: passes TestG80_3_MCCRGatesCTTrigger. Shortest failures, TestAddressDecoding and
  TestResetState, diverge at tick 2 on ADDrive.
- SCC: shortest failures diverge on INT_n and IEO within 3 ticks.

## Vector inventory

| device | files | notes |
|---|---|---|
| CPU | 1301 | 17 skipped (restore Go snapshots, or set a refresh pending directly) |
| CPU cycle counts | 45 | 35 `exact`, 10 `approx` |
| MMU | 71 | from 48 of 49 Go tests |
| CIO | 110 | 52 `X partial` |
| SCC | 81 | 28 pure pin-seam (`F POKES 0`) |
