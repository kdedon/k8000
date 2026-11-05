# Status

`make test`, 2026-11-05. Update when a bench moves.

| bench | command | result |
|---|---|---|
| decode ROM | `make test-decode` | PASS, 135552 checks |
| decode ROM vs table | `make test-decode-table` | PASS, 1048576 checks |
| program ROM vs table | `make test-mc-table` | PASS, 1053342 checks (434 forms, 206 programs) |
| register file | `make test-regfile` | PASS, 4056 checks (port B on the byte and word cases) |
| ALU | `make test-alu` | PASS, 431 of 431 vector files (86297 records, 10549 long as two word passes, 39 out-of-contract skipped) |
| Serial unit (MULT/DIV/SHIFT) | `make test-serial` | PASS, 5182 operations (2,136 divides at the case 3/4 edges) |
| Refresh prescaler | `make test-refresh` | PASS, 7 checks |
| Instruction word capture | `make test-seq-words` | PASS, 17 cases (address register and words 1, 2) |
| Program paths and repeats | `make test-seq-paths` | PASS, 20 cases (JP/RET cc taken and not taken, shift counts, LDM counts and lengths) |
| Condition codes | `make test-cond` | PASS, 256 checks (16 codes, every C Z S P/V) |
| CPU vectors | `make test-cpu` | 2668 pass, 0 fail, 78 skip (Z8001 1130, Z8002 1516, Z8003 7, Z8004 15) |
| CPU vectors, CLK rise and fall in one master clock | `make test-cpu-combined` | 2668 pass, 0 fail, 78 skip |
| CPU Z-Bus timing | `make test-cpu-timing` | PASS, 13 checks (I/O with /WAIT included) |
| CPU cycle counts | `make test-cpu-cycles` | PASS, 45 of 45 |
| MMU vectors | `make test-mmu` | 77 of 77, every record exact |
| MMU timing | `make test-mmu-timing` | 16 of 16 |
| CPU and MMU on one CLK | `make test-cpu-mmu-clk` | PASS at master:CLK 2:1, 3:1, 4:1, 5:1, 7:1 and 2,3,2,4 (49 PA checks each), and 1:1 with both CLK pulses every master clock (94) |
| CIO vectors | `make test-cio` | 132 of 132 (53 partial) |
| CIO timing | `make test-cio-timing` | 14 of 14 |
| SCC vectors | `make test-scc` | 172 of 172 |
| SCC timing | `make test-scc-timing` | 12 of 12 |

## Fit

`quartus/build.sh <unit>`, 2026-11-02, 5CSEBA6U23I7, 48 MHz target, slow corner; worst paths in
`results/quartus/<unit>.txt`. `SEED=<n>` picks the fitter seed (results in `<unit>_s<n>.txt`).

| unit | ALMs | Fmax |
|---|---|---|
| register file (two read ports, byte nonzero bits) | 451 | 123 MHz |
| ALU | 205 | 101 MHz |
| serial unit (multiply, divide, shifts on one adder and rotate) | 658 | 72.4 MHz |
| MMU (64 descriptors in four MLAB RAMs, 1,920 bits; A23:8, offset latched at the /AS rise) | 551 | 69.2 MHz |
| CIO (bus interface, register file, ports A/B/C, counter/timers, pattern match, interrupts, handshakes) | 1,611 | 55.6 MHz |
| SCC (strobe capture, /INT latch, IEO, register core, acknowledge, WR0 commands, ext/status, BRG, clock mux, transmitter, async receiver, SDLC, SDLC Loop, monosync, bisync, external sync, DPLL, NRZI/FM) | 1,990 | 51.6 MHz (1.5 ns setup slack at 48 MHz; worst: /AS into the hunt latch) |
| CPU, Z8001 (the program ROMs drive the bus; the serial unit included; the shift and multi-micro work sits in the CPU glue on ports A and B) | 4,735 | 50.5 MHz, median of seeds 1-3 (setup slack at 48 MHz: 1.03 ns; worst path: a sequencer flop through the register read select and the address adder into the register file) |

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
  the stack pointer swap on a mode change (R15 on S/N; on a Z8001, R14 into
  or out of segmented system mode). SC and the
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
  and SIN/SOUT (a byte written on both halves of AD, read from the half the
  port's A0 picks), block transfer, compare, string compare and block I/O (single and
  repeat, segmented included) run; an interrupt, a refresh or a bus request between block
  elements is taken. Refresh runs after an IF1 (aborted too), an
  internal operation or a block element, and the STOP stream runs after an IF1. NVI, VI and NMI are sampled at the
  instruction's last cycle (and by HALT, which leaves on two samples) and run the
  acknowledge entry, the VI through its vector table (the identifier doubled on both
  CPUs). Up to two refreshes are owed; those that came due with the bus granted or in a wait state go out back to back as soon as the bus is back or the waited cycle ends, ahead of any cycle. SLA/SLL/SDA/SDL run through the serial unit, one
  position per I3; BIT/SET/RES with a register bit number, and MSET/MRES/MBIT/MREQ
  with the /MO and /MI handshake, run, segmented included. MULT/MULTL/DIV/DIVL write registers and flags on the program's last clock
  (a unit holds for a late operand; no CPU program delivers one, and a self-check
  fails if a write lands later). A byte or word immediate op
  writes its register and flags as its word's T3 opens. /BUSREQ is sampled at each machine cycle's T1 and the bus given up
  right after that cycle's T3 (/BUSACK, AD released, `bus_drive` Low for the other outputs);
  the cycle's later clocks run on, the next cycle waits, and the bus comes back two clocks
  after /BUSREQ rises; TSET grants none between its read and write,
  and the lock holds through the write's T3 (no pin carries it; tb_cpu mirrors it from internal nets and checks no grant falls inside it). On a Z8003/Z8004 /ABORT,
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
- Pins and clocks: every chip module has only its real pins. One board master
  clock runs every flop; each chip's clock pin is a one-master-clock pulse for the
  edge it acts on (CPU and MMU CLK rise, SCC PCLK rise, CIO PCLK fall, SCC /RTxC
  and /TRxC as rise and fall pulses). The SCC and CIO have no reset port: /AS and
  /DS Low together reset them. Vector replays run 1, 2, 4 and uneven master clocks
  per record; the TSET bus lock is internal and tb_cpu checks it from the hierarchy.
- MMU: translates. Its pins are AD15:8 in, A23:8 out. Offset, status and /CS are
  latched while /AS is Low and held from its rise; A23:8 (base + offset[15:8], or
  pass-through with TRNS clear) drive from the master clock that sees the /AS rise and
  float at the /DS rise;
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
  Open: the chip starts driving A23:8 at the /AS fall (AC #28), the RTL at the rise.
  The Go model acts on the same strobe edges (fixed 2026-11-02); tb_mmu compares
  every record exactly. The 64 descriptors are four MLAB RAMs (asynchronous
  read) plus 192 flops (written-since-reset, CPU-Inhibit, DMA-Inhibit).
- CIO: /AS latches AD, /CS0 and /INTACK while Low and holds them until the next /AS;
  CS1 and R/W are taken at each /DS fall, where registers are read and written, so a
  /DS with no new /AS reaches the last addressed register; AD floats at the /DS rise,
  before a new /AS in the same sample latches. /AS and /DS Low together reset
  the chip. RJA selects AD5:AD0 or AD6:AD1. Command/status registers take the
  IUS/IE/IP commands; port data registers drive the outputs, enabled per port by MCCR
  and per bit by direction through the Data Path Polarity inverters; Special I/O makes an
  output bit open-drain. Port pins are sampled at each /AS rise, and every Port C bit
  reads its pin; Special I/O input bits carry 1's catchers, cleared by
  writing 0. Ports A and B run the interlocked, strobed and 3-wire handshakes on
  their Port C lines with REQUEST and /WAIT; the pulsed handshake puts C/T 3
  in the ACKIN path of an input port and the DAV path of an output port.
- SCC: strobe capture, /INT latch, IEO, address decode, register core, resets, the acknowledge (request condition, priority, IUS, vector, RR2 modification, Reset Highest IUS), the WR0 commands, DCD/CTS ext/status, BRG (a re-enable resumes the held count), WR11 clock mux, the async transmitter (Send Break on bit cell edges, 1.5 stop bits) and the async receiver (one stop bit checked, FIFO, parity bit and 1s above short characters, parity/framing/overrun, special receive, the FIFO lock on a special condition, Break with one null at its end) and SDLC at x1 (flag or mark idle, zero insertion and deletion, CRC-CCITT/CRC-16 with the WR10 preset, Tx Underrun/EOM with CRC or abort, Send Abort, hunt, abort detect, address search, residue codes, End of Frame with the CRC check) and monosync, bisync and external sync at x1 (6, 8 and 16-bit transmit sync idle, CRC on underrun, hunt on 6, 8, 12 and 16-bit syncs, Sync Character Load Inhibit, the receive CRC's 8-bit delay and per-character enable, /SYNC in and out, parity) and the DPLL (the WR14 commands, NRZI and FM windows with the count-5 correction, search, One/Two Clocks Missing, its clocks through WR11 and on /TRxC) with NRZ, NRZI, FM1 and FM0 coding in any x1 mode and Manchester decoding through the DPLL in FM in, SDLC Loop mode in NRZ and NRZI (Go Active On Poll, TxD through gates off loop and through the one-bit delay on loop, the EOP turned into a flag, On Loop and Loop Sending in RR10, leaving at an EOP) and a CRC cut short by Tx Enable (the flag or sync pattern fills its bit times) in SDLC and byte sync; every vector passes. There is no reset port: the hardware reset is /AS and /DS Low together, as on the chip. Asynchronous inputs are taken in-domain to keep lockstep (/DCD, /CTS and /SYNC with one PCLK sample, RxD at the PCLK rise, /RTxC and /TRxC against the last PCLK's level): a system top must pass RxD, /RTxC, /TRxC, /SYNC, /DCD, /CTS and the bus strobes through 2-flop synchronisers. SDLC Loop in FM, the sync-mode loop (WR10 D1 outside SDLC), /SYNC as an output in SDLC and its input in async, parity in SDLC, Zero Count, the DTR/REQ request and the /W//REQ pins are not built.

## Vector inventory

| device | files | notes |
|---|---|---|
| CPU | 2744 | 78 skipped (restore Go snapshots, or set a refresh pending directly) |
| CPU cycle counts | 45 | 35 `exact`, 10 `approx` |
| MMU | 77 | from 54 Go tests |
| CIO | 132 | 53 `X partial` |
| SCC | 172 | 119 pure pin-seam (`F POKES 0`) |
