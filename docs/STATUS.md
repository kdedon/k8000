# Status

`make test`, 2026-11-01. Update when a bench moves.

| bench | command | result |
|---|---|---|
| decode ROM | `make test-decode` | PASS, 135552 checks |
| decode ROM vs table | `make test-decode-table` | PASS, 1048576 checks |
| program ROM vs table | `make test-mc-table` | PASS, 1053342 checks (434 forms, 206 programs) |
| register file | `make test-regfile` | PASS, 4056 checks (port B on the byte and word cases) |
| ALU | `make test-alu` | PASS, 427 of 427 vector files (84365 records, 10546 long as two word passes, 39 out-of-contract skipped) |
| Serial unit (MULT/DIV/SHIFT) | `make test-serial` | PASS, 5182 operations (2,136 divides at the case 3/4 edges) |
| Refresh prescaler | `make test-refresh` | PASS, 7 checks |
| Instruction word capture | `make test-seq-words` | PASS, 17 cases (address register and words 1, 2) |
| Program paths and repeats | `make test-seq-paths` | PASS, 20 cases (JP/RET cc taken and not taken, shift counts, LDM counts and lengths) |
| Condition codes | `make test-cond` | PASS, 256 checks (16 codes, every C Z S P/V) |
| CPU vectors | `make test-cpu` | 1833 pass, 0 fail, 17 skip (Z8001 849 of 849, Z8002 962 of 962, Z8003 7 of 7, Z8004 15 of 15) |
| CPU Z-Bus timing | `make test-cpu-timing` | PASS, 13 checks (I/O with /WAIT included) |
| CPU cycle counts | `make test-cpu-cycles` | PASS, 45 of 45 |
| MMU vectors | `make test-mmu` | 75 of 75 |
| MMU timing | `make test-mmu-timing` | 12 of 12 |
| CIO vectors | `make test-cio` | 131 of 131 (53 partial) |
| CIO timing | `make test-cio-timing` | 14 of 14 |
| SCC vectors | `make test-scc` | 169 of 169 |
| SCC timing | `make test-scc-timing` | 12 of 12 |

## Fit

`quartus/build.sh <unit>`, 5CSEBA6U23I7, 48 MHz target, slow corner; worst paths in
`results/quartus/<unit>.txt`. `SEED=<n>` picks the fitter seed (results in `<unit>_s<n>.txt`).

| unit | ALMs | Fmax |
|---|---|---|
| register file (two read ports, byte nonzero bits) | 454 | 125 MHz |
| ALU | 205 | 101 MHz |
| serial unit (multiply, divide, shifts on one adder and rotate) | 658 | 72.4 MHz |
| MMU (64 descriptors in flops) | 1,481 | 68.1 MHz |
| CIO (bus interface, register file, ports A/B/C, counter/timers, pattern match, interrupts, handshakes) | 1,635 | 53.3 MHz |
| SCC (strobe capture, /INT latch, IEO, register core, acknowledge, WR0 commands, ext/status, BRG, clock mux, transmitter, async receiver, SDLC, SDLC Loop, monosync, bisync, external sync, DPLL, NRZI/FM) | 2,067 | 51.9 MHz (1.6 ns setup slack at 48 MHz; worst: /AS into the ext/status latch) |
| CPU, Z8001 (the program ROMs drive the bus; the serial unit included; the shift and multi-micro work sits in the CPU glue on ports A and B) | 4721 | 50.5 MHz median over seeds 1-5 (setup slack at 48 MHz: 1.0 ns median, 0.7 ns worst; no single path family leads) |

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
  DIV and DIVL run in every operand form, segmented included, as microroutines on the
  program's clocks: one named pass, rotate, latch or sequencer clock per clock on
  unit-local copies of the destination, their operands read on ports A and B. One
  serial unit (one adder, one pair rotate, one microword set) runs them and the shifts.
  They start on the IF1's T3 in every form and hold while the operand is not in.
  The units end their internal cycles (unit-ended ROM entries): DIV and DIVL on
  every path, MULT, MULTL's frames and the shift positions; a divide has one
  program, which the unit's last cycle ends. MULT zero, MULTL zero and MULTL's
  finish keep counted cycles (the baseline's placement).
  DIV/DIVL case 3 run frames 1-2 (DIVL frame 1) and store the partial words,
  unchecked in the vectors; case 4 runs the normal routine (its timing pending
  a C900 measurement). IN/OUT
  and SIN/SOUT, block transfer, compare, string compare and block I/O (single and
  repeat, segmented included) run; an interrupt, a refresh or a bus request between block
  elements is taken. Refresh runs after an IF1 (aborted too), an
  internal operation or a block element, and the STOP stream runs after an IF1. NVI, VI and NMI are sampled at the
  instruction's last cycle (and by HALT, which leaves on two samples) and run the
  acknowledge entry, the VI through its vector table (the identifier doubled on both
  CPUs). Up to two skipped refreshes are owed, one issued per boundary. SLA/SLL/SDA/SDL run through the serial unit, one
  position per I3; BIT/SET/RES with a register bit number, and MSET/MRES/MBIT/MREQ
  with the /MO and /MI handshake, run, segmented included. MULT/MULTL/DIV/DIVL write registers and flags on the program's last clock
  (a unit holds for a late operand; no CPU program delivers one, and a self-check
  fails if a write lands later). A byte or word immediate op
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
  registered read needs the lookup re-pipelined).
- CPU: an interrupt pending while EI, LDCTL FCW, LDPS or IRET enables it is taken
  at the next boundary, and a DI before the sample masks it. An SC, trap or
  interrupt entry whose new FCW enables a pending request (or with an NMI held
  through it) takes it before the handler's first instruction. Done.
- CPU: shifts with counts 0 and 1 under refresh, and a bus request held
  mid-shift, have vectors. Done.
- CPU: a refresh among a shift's internal clocks holds the shift's step, so its
  last position lands on the program's last clock. Done.
- CPU: a trap entry (SC, privileged, extended) reads its PC at the PSA's fixed
  entry; only a VI's acknowledge sets the identifier offset. Done.
- CPU: a refresh or bus hold right after a MULTL step or extra add leaves the
  next extra add or the finish as the program asked before the hold. Done.
- MMU: translates. The address latched at the /AS fall drives PA from the /AS rise
  (base x 256 + offset, or pass-through with TRNS clear) and floats at the /DS rise;
  REF and CHG set on a clean access. The command port takes its opcode at the /AS rise
  (/CS sampled there only), runs at the first /DS Low sample and drives read data on
  AD15:8 while /DS is Low; all 22 commands. Violations raise SEGT and SUP, capture
  VTR, segment, offset and BCSR (FATL, SWW and the write warning included), and SUP
  repeats until the next first-word fetch; while a trap is pending only that
  first-word fetch goes unchecked. The trap acknowledge drives AD line 8+ID alone,
  through a per-line AD15:8 drive mask, so several MMUs share the bus.
  DMASYNC rising after two Low samples translates a DMA address in that sample;
  DMA violations assert SUP only; with TRNS clear a DMA address passes through
  unchecked. A DMA cycle ends at its /DS rise or after two more DMASYNC-High
  samples. A cycle starting in the /DS-rise sample latches. A system top must use
  the per-line `data_drive[n]` as the output enable for AD line 8+n and resolve
  several MMUs per bit.
- CIO: /AS latches AD, /CS0 and /INTACK while Low; CS1 and R/W are taken at the /DS
  fall, where registers are read and written; AD floats at the /DS rise, which ends a
  cycle before a new /AS in the same sample latches. /AS and /DS Low together reset
  the chip. RJA selects AD5:AD0 or AD6:AD1. Command/status registers take the
  IUS/IE/IP commands; port data registers drive the outputs, enabled per port by MCCR
  and per bit by direction through the Data Path Polarity inverters; Special I/O makes an
  output bit open-drain. Port pins are sampled at each /AS rise, and every Port C bit
  reads its pin; Special I/O input bits carry 1's catchers, cleared by
  writing 0. Ports A and B run the interlocked, strobed and 3-wire handshakes on
  their Port C lines with REQUEST and /WAIT; the pulsed handshake puts C/T 3
  in the ACKIN path of an input port and the DAV path of an output port.
- SCC: strobe capture, /INT latch, IEO, address decode, register core, resets, the acknowledge (request condition, priority, IUS, vector, RR2 modification, Reset Highest IUS), the WR0 commands, DCD/CTS ext/status, BRG, WR11 clock mux, the async transmitter (Send Break, 1.5 stop bits) and the async receiver (one stop bit checked, FIFO, parity bit and 1s above short characters, parity/framing/overrun, special receive, the FIFO lock on a special condition, Break with one null at its end) and SDLC at x1 (flag or mark idle, zero insertion and deletion, CRC-CCITT/CRC-16 with the WR10 preset, Tx Underrun/EOM with CRC or abort, Send Abort, hunt, abort detect, address search, residue codes, End of Frame with the CRC check) and monosync, bisync and external sync at x1 (6, 8 and 16-bit transmit sync idle, CRC on underrun, hunt on 6, 8, 12 and 16-bit syncs, Sync Character Load Inhibit, the receive CRC's 8-bit delay and per-character enable, /SYNC in and out, parity) and the DPLL (the WR14 commands, NRZI and FM windows with the count-5 correction, search, One/Two Clocks Missing, its clocks through WR11 and on /TRxC) with NRZ, NRZI, FM1 and FM0 coding in any x1 mode and Manchester decoding through the DPLL in FM in, SDLC Loop mode in NRZ and NRZI (Go Active On Poll, TxD through gates off loop and through the one-bit delay on loop, the EOP turned into a flag, On Loop and Loop Sending in RR10, leaving at an EOP) and a CRC cut short by Tx Enable (the flag or sync pattern fills its bit times) in SDLC and byte sync; every vector passes. rst_n gives the fabric the hardware reset at power-up. Asynchronous inputs are taken in-domain to keep lockstep (/DCD, /CTS and /SYNC with one PCLK sample, RxD at the PCLK rise, /RTxC and /TRxC against the last PCLK's level): a system top must pass RxD, /RTxC, /TRxC, /SYNC, /DCD, /CTS and the bus strobes through 2-flop synchronisers. SDLC Loop in FM, the sync-mode loop (WR10 D1 outside SDLC), /SYNC as an output in SDLC and its input in async, parity in SDLC, Zero Count and the DTR/REQ request are not built.

## Vector inventory

| device | files | notes |
|---|---|---|
| CPU | 1568 | 17 skipped (restore Go snapshots, or set a refresh pending directly) |
| CPU cycle counts | 45 | 35 `exact`, 10 `approx` |
| MMU | 75 | from 52 of 53 Go tests |
| CIO | 131 | 53 `X partial` |
| SCC | 169 | 116 pure pin-seam (`F POKES 0`) |
