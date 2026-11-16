# Status

`make test`, 2026-11-14. Update when a bench moves.

| bench | command | result |
|---|---|---|
| decode ROM | `make test-decode` | PASS, 135552 checks |
| decode ROM vs table | `make test-decode-table` | PASS, 1048576 checks |
| program ROM vs table | `make test-mc-table` | PASS, 1053342 checks (434 forms, 206 programs) |
| register file | `make test-regfile` | PASS, 4056 checks (port B on the byte and word cases) |
| ALU | `make test-alu` | PASS, 450 of 450 vector files (89267 records, 16739 in two passes: longs as two words, rotates by 2 as two by 1; 39 out-of-contract skipped) |
| Serial unit (MULT/DIV/SHIFT) | `make test-serial` | PASS, 5182 operations (2,136 divides at the case 3/4 edges) |
| Refresh prescaler | `make test-refresh` | PASS, 7 checks |
| Instruction word capture | `make test-seq-words` | PASS, 17 cases (address register and words 1, 2) |
| Program paths and repeats | `make test-seq-paths` | PASS, 20 cases on Z8002 and segmented Z8001 (JP/RET cc taken and not taken, shift counts, LDM counts and lengths) |
| Condition codes | `make test-cond` | PASS, 256 checks (16 codes, every C Z S P/V) |
| CPU vectors | `make test-cpu` | 3078 pass, 0 fail, 0 skip (Z8001 1298, Z8002 1758, Z8003 7, Z8004 15) |
| CPU vectors, CLK rise and fall in one master clock | `make test-cpu-combined` | 3078 pass, 0 fail, 0 skip |
| CPU Z-Bus timing | `make test-cpu-timing` | PASS, 13 checks on Z8002, 14 on segmented Z8001 in segments 05 and 12 (I/O with /WAIT included, SN timing) |
| CPU cycle counts | `make test-cpu-cycles` | PASS, Z8002 45 of 45, segmented Z8001 38 of 38 (SS and SL direct and indexed addresses, CALL, RET, long words) |
| MMU vectors | `make test-mmu` | 77 of 77, every record exact |
| MMU timing | `make test-mmu-timing` | 22 of 22 |
| CPU and MMU on one CLK | `make test-cpu-mmu-clk` | PASS at master:CLK 2:1, 3:1, 4:1, 5:1, 7:1 and 2,3,2,4 (49 PA checks each, plus PA checks in every /AS-Low master clock), and 1:1 with both CLK pulses every master clock (94) |
| CIO vectors | `make test-cio` | 138 of 138 (53 partial) |
| CIO timing | `make test-cio-timing` | 19 of 19 |
| CIO daisy-chain acknowledge | `make test-cio-iack` | 10 of 10 |
| SCC vectors | `make test-scc` | 181 of 181 |
| SCC timing | `make test-scc-timing` | 15 of 15 |
| SCC daisy-chain acknowledge | `make test-scc-iack` | 11 of 11 |
| SCC async receive, sender off rate | `make test-scc-async-rx` | 14 of 14 (-3% to +3%, one and two stop bits; +/-10% fails as it must) |
| FPU vectors | `make test-fpu` | 1381 pass, 1 skip (`X`) |
| FPU timing | `make test-fpu-timing` | 72 of 72 (reset, snoop, drive windows, the store wait, /BSY at the STOP samples in both overlap modes, queued operations, FRDIV, FRVSUB, FCPF and FCPFX, and /ABORT with CLK.I and CLK.D at the master clock, the acknowledge: IEO, vector window, SV, NV, DLC; the lost-word count) |
| FPU decode table | `make test-fpu-enc` | PASS, every IF1 word and every template x word 1 bits 7:4 x word 2 |
| FPU Data Processor | `make test-fpu-dp` | add 61487 of 61487, load 11 of 11, sign 18 of 18, cmp 3087 of 3087, mul 24541 of 24541, div 32867 of 32867, sqrt 457 of 457, rem 345 of 345, fint 255 of 255, conv 77 of 77, bcd 64 of 64 (results, flags, reason, R bit, compare code, CLK.D count) |
| FPU and CPU+FPU, CLK.D every master clock | `make test-fpu-fastd` | at `--mclk 1` and `1,2,1,3`: fpu 1379 pass, 3 skip; system 468 pass, 6 skip (final state but PC2, memory, driven words; skips: one internal-state poke, eight files with speed-dependent outcomes) |
| FPU and CPU+FPU, CLK.D at 1/8 and 1/12 of CLK.I | `make test-fpu-slowd` | at `--mclk 1` and `1,2,1,3`: fpu 1380 pass, 2 skip; system 474 pass |
| CPU and FPU on one board | `make test-cpu-fpu` | Z8001 457 of 457, Z8002 17 of 17 (CPU pins, CPU inputs where sampled, FPU outputs, memory writes; final CPU, FPU and memory) |
| Vectors at other master-clock patterns | `make test-mclk` | MMU, SCC, CIO, FPU and CPU+FPU as above at `--mclk 1`, `2`, `1,3`, `3,1,2`; FPU and CPU+FPU also at `3` and `4` |

Every ladder in `docs/LADDER.md` is complete: datapath A1-A3, CPU rungs
0-10, MMU M1-M5, CIO C1-C5, SCC S1-S4, FPU F0-F11.

## Fit

`quartus/build.sh <unit>`, Quartus 17.0.2, 5CSEBA6U23I7, 48 MHz target,
slow corner; worst paths in `results/quartus/<unit>.txt`. `SEED=<n>` picks
the fitter seed (results in `<unit>_s<n>.txt`). ALMs are the fitter's logic
utilization in those files, boundary flops included.

| unit | date | ALMs | Fmax |
|---|---|---|---|
| register file (two read ports, byte nonzero bits) | 2026-11-02 | 451 | 123 MHz |
| ALU | 2026-10-27 | 205 | 101 MHz |
| serial unit (multiply, divide, shifts on one adder and rotate) | 2026-11-02 | 658 | 72.4 MHz |
| MMU (64 descriptors in four MLAB RAMs, 1,920 bits; A23:8 driven from the /AS fall; slack 6.90 ns) | 2026-11-14 | 447 | 71.8 MHz |
| CIO (bus interface, register file, ports A/B/C, counter/timers, pattern match, interrupts, handshakes) | 2026-11-14 | 1,260 | 59.3 MHz |
| SCC (every mode built; seeds 1-3: 1,927-1,935) | 2026-11-14 | 1,932 | 51.38 MHz, median of seeds 1-3 (setup slack at 48 MHz: 0.87-1.87 ns, hold 0.18 ns; worst: the latched address through a WR9 reset command into the hunt latch) |
| CPU, Z8001 (the program ROMs in logic, the serial unit included; seeds 1-3: 3,997-4,011) | 2026-11-15 | 4,000 | 51.18 MHz, median of seeds 1-3 (setup slack at 48 MHz: 1.17-1.71 ns, hold 0.16 ns; worst: the arriving word's program lookup into pass_lo, last into the register file) |
| FPU Data Processor alone (`fpudp`; F0-F7 in an MLAB) | 2026-11-14 | 1,958 | 52.8 MHz (setup slack at 48 MHz: 1.89 ns; worst: the microprogram counter through the ROM into the working significand) |
| FPU, whole chip (`fpu`: F0-F7, FOP1 and FOP2 in one 16 x 80 MLAB, row 10 also holding the running operation's bus operand while a queued instruction needs the buffer; seeds 1-3: 2,733-2,758; no M10K, no DSP) | 2026-11-15 | 2,736 | 53.85 MHz, median of seeds 1-3 (setup slack at 48 MHz: 1.16-2.61 ns, hold 0.13 ns; worst: the microprogram counter through the ROM into the working significand) |

## State

- CPU (Z8001/2/3/4): every instruction, addressing mode and segmented form
  runs its machine-cycle program from the generated program ROM; traps,
  interrupts (NMI, VI, NVI, SEGT/SAT), /ABORT, refresh (two owed, issued
  back to back after a grant or wait), STOP, /BUSREQ, multi-micro and EPU
  transfers included. The serial unit runs MULT/MULTL/DIV/DIVL and the
  shifts as microroutines on the program's clocks. Closes 48 MHz with its
  ROMs in logic.
- MMU: translation, all 22 commands, violations and the segment trap
  acknowledge (one AD line per MMU, for several MMUs on one bus), DMASYNC.
  A23:8 drive from the /AS fall (AC #28). A system top resolves several MMUs
  per AD bit with `data_drive[n]`.
- CIO: bus interface (one access per /AS), ports A/B/C with the input,
  output and pulsed handshakes, Special I/O, polarity and 1's catchers, three counter/timers,
  pattern match, interrupts and the daisy chain. /AS and /DS Low together
  reset it.
- SCC: async, SDLC, SDLC Loop (NRZ, NRZI), monosync, bisync, external sync,
  BRG, DPLL, NRZ/NRZI/FM coding, interrupts and the daisy chain. /AS and
  /DS Low together reset it. A system top passes RxD, /RTxC, /TRxC, /SYNC,
  /DCD, /CTS and the bus strobes through 2-flop synchronisers.
- FPU: Interface Processor (snoop, transfers, FLDCTL and the list forms,
  one-deep queue, /BSY in No Overlap and Intermediate, traps, acknowledge)
  and a microprogrammed Data Processor (every arithmetic, compare,
  conversion and BCD operation); runs with the RTL CPU on one master clock.
- Pins and clocks: every chip module has only its real pins; one board
  master clock runs every flop, each chip clock pin a one-master-clock edge
  pulse.

## Open

- Segmented LDA bits 23:16: written 0; the manual leaves them undefined
  (DECISIONS).
- SCC: /W//REQ pins not built; also not built: SDLC Loop in FM, the
  sync-mode loop, /SYNC as an output in SDLC and its input in async,
  parity in SDLC, Zero Count, the DTR/REQ request.
- CPU undefined words: 4236 undefined first words take the privileged trap.
  9Cxy runs as TESTL RRx and 7B0D as MREQ R0; the real CPU runs the rest as
  some other instruction (CPU RefMan 1982 p.274, note 3), unknown which until
  the silicon study (RESEARCH 10).
- CPU cycle counts: 10 of 45 records are `approx` (a base plus per-step
  clocks).
- CIO: 53 vectors are `X partial`; bidirectional port mode (11) and Port
  Link Control (MCCR D3) are not built.
- FPU: 1 vector skipped (`X unsupported`, a poke of internal state).
- The FPU acknowledge sets IUS at the /DS rise; the CIO and SCC act at the
  /DS fall.

## Vector inventory

| device | files | notes |
|---|---|---|
| CPU | 3078 | none skipped: a snapshot restore replays the source CPU's records, a pending refresh is a bench poke |
| CPU cycle counts | 45 + 38 segmented | Z8002 35 `exact`, 10 `approx`; Z8001 35 `exact`, 3 `approx` |
| MMU | 77 | |
| FPU | 1382 pin + 20 Data Processor + 474 system + decode digests | 1 `X unsupported`; dp 15 MB, queue sweeps 18 MB |
| CIO | 138 | 53 `X partial` |
| SCC | 181 | 128 pure pin-seam (`F POKES 0`) |
