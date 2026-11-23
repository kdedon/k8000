# k8070_fpu (Z8070 FPU) -- tests

## Scope

The Z8070 exists only as a Preliminary Product Specification (1985 Data
Book, printed pp.531-558). The RTL follows it where it speaks; where it is
silent, this implementation's choice is listed under "Assumed" below.

RTL: `rtl/k8070_fpu/z8070_fpu.sv` (top, real pins only), `z8070_ip.sv`
(Interface Processor: snoop, transfers, SC/USER/FFLAGS/PC1/PC2, /BSY,
interrupts), `z8070_dec.sv` (its decode: IF1 template and ID, word-2 plan
through the table in `gen/z8070_enc_pkg.sv`), `z8070_dp.sv` (Data
Processor: F0-F7, FOP1/FOP2, arithmetic on CLK.D: one microword per CLK.D
rise from `gen/z8070_dp_rom.sv`, whose source is `z8070_dp_ucode.txt`,
over one 68-bit significand adder, one 17-bit exponent adder, one 68-bit
shifter and one leading-zero counter). Ports: `clk` (board master clock),
`clki_rise`, `clki_fall`, `clkd_rise`, `reset_n`, `ad_in`, `ad_out`,
`ad_drive`, `as_n`, `ds_n`, `r_w`, `b_w`, `n_s`, `st`, `sn`, `busack_n`,
`abort_n`, `bsy_n`, `int_n`, `iei`, `ieo`, `id`, `opt`: the common signals
(p.542) plus the Z8000 interface's (pp.544-545). OPT1-OPT0 are read by
nothing yet: only the Z8000 interface (11) is built.

| vectors | format | files | bench |
|---|---|---|---|
| `vectors/k8070_fpu/fpu/` | `K8000VEC 1 fpu` | 67 from 55 tests | `tb/k8070_fpu/tb_fpu.cpp` |
| `vectors/k8070_fpu/dp/` | `K8000VEC 1 fpudp` | 20 (123,209 records, 15 MB) | `tb/k8070_fpu/tb_fpu_dp.cpp` |
| `vectors/k8070_fpu/system/` | `K8000VEC 1 cpufpu` | 26 (10 tests, Z8001 and Z8002) | `tb/k8070_fpu/tb_cpu_fpu.cpp` on the `tb_cpu_fpu.sv` board |
| `vectors/k8070_fpu/enc/enc.vec` | `K8000VEC 1 fpuenc` | 1 | `tb/k8070_fpu/tb_fpu_enc.sv` |

`rtl/k8070_fpu/gen/z8070_enc_pkg.sv` (the decode table) is
hand-maintained and `vectors/k8070_fpu/enc/enc.vec` is generated;
`make gen` assembles `gen/z8070_dp_rom_pkg.sv` and `gen/z8070_dp_rom.sv`
from `z8070_dp_ucode.txt`.

## How to run

```
make lint-fpu         # verilator -Wall on z8070_dec, z8070_ip, z8070_dp, z8070_fpu (zero suppressions)
make test-fpu-enc     # the RTL decode against the digests, every input
make build-fpu        # obj_dir/tb_fpu/tb_fpu
make test-fpu         # replay every fpu vector, pass/fail + shortest failing
make fpu ONLY=TestName [VCD=1] [CONTEXT=N] [MCLK=P]   # one vector, full context table
make ladder-fpu       # every vector, shortest first, with status
make test-fpu-timing  # the specification bench (72 checks; docs/TIMING_TESTS.md)
make test-fpu-dp [ONLY=add,cmp,...] [MCLK=P]   # the Data Processor alone, every dp record
make test-cpu-fpu     # RTL CPU + FPU on one board, every system vector, Z8001 then Z8002
make cpu-fpu ONLY=TestName[.Z8001.000] [VCD=1] [CONTEXT=N] [MCLK=P]   # one system vector
make test-fpu-fastd   # every fpu and system vector with CLK.D rising every master clock (final state, memory, driven words)
make test-fpu-slowd   # the same with CLK.D at 1/8 and 1/12 of CLK.I; the bench stops the CPU on /BSY
```

### The `fpu` file

```
K8000VEC 1 fpu
test TestResetLatchesID 0                 test name, chip instance index
T <in:4hex> <AD:4hex> <ST:1hex> <SN:2hex> <out:1hex> <outAD:4hex>
P <reg> <hex>                              register the test wrote between records
X unsupported poke of internal state       a poke with no P form; records stop
F F0..F7, FOP1, FOP2 <20hex>               final state (sign+exponent, significand)
F FFLAGS, SC, USER, PC1, PC2 <8hex>
F DPBUSY <0|1>
F TICKS <n>
END
```

`in` (bit 14 = MSB): `CLKI CLKD RESET_n AS_n DS_n R_W B_W N_S BUSACK_n ABORT_n IEI ID1 ID0 OPT1 OPT0`.
`out` (bit 3 = MSB): `ADDrive BSY_n INT_n IEO`.

The bench drives a record's inputs, raises `clki_rise`, `clki_fall` or
`clkd_rise` for the first master clock of a record whose CLK.I or CLK.D
changed that way, and runs N master clocks (N cycles through `--mclk P` /
`K8000_MCLK`, default `1,2,1,3`). Start state: no reset yet, both clocks
Low.

| compared | rule |
|---|---|
| ADDrive, BSY_n, INT_n, IEO | every record |
| AD | while both sides drive it (all 16 bits; byte drives put 00 on AD15-8, assumed) |
| `F` FFLAGS, SC, USER, PC1, PC2, F0-F7, FOP1, FOP2, DPBUSY | exact, through `tb/k8070_fpu/fpu_access.h` |
| `P` SC, FFLAGS, USER, PC1, PC2, F0-F7, FOP1, FOP2 | poked into the RTL |
| settle | two idle master clocks before a `P` and before the `F` records: F[Fd] and FOP2 are written one and two master clocks after done (nothing at the pins moves) |
| `X` | SKIP |

### The `fpudp` file

```
K8000VEC 1 fpudp
test TestSingleOracle
D kind prec rm dst src int opts  res flags reason rup cmp rint cycles
END
```

One `D` per Data Processor operation run to completion: `kind` the
operation or conversion, `dst`/`src`/`res` 20-hex X80, `int`/`rint` 16 hex,
`opts` bit 0 quad, bit 1 truncate, `cycles` CLK.D clocks, decimal. The
record order of TestExtendedBigOracle changes between recordings; the
record set does not.

`tb_fpu_dp` drives `z8070_dp` alone: per record, `op_kind`, `op_prec`,
`op_rm` on a `start` pulse, the destination or source operand on `opnd` as
`opnd_src` names it, then CLK.D rises (`clkd_rise`, High and Low phases
from `--mclk`, default `1,2,1,3` master clocks) until `done`. Every other
record starts on the first CLK.D rise instead of the master clock before.

| compared | rule |
|---|---|
| result | all 80 bits (zero for a compare) |
| flags, invalid reason, R bit, compare code | exact |
| CLK.D clocks | the rises up to and including the one `done` is High in |
| busy | Low after `done` |

Groups (`ONLY=`): add (FADD, FSUB, FRVSUB), load (FLD rounding), sign
(FABS, FNEG, FCLR), cmp (FCP, FCPX, FCPZ, FCPZX), mul, div, sqrt, fint,
rem, conv, bcd. A kind with no routine runs the two-clock tail and fails.
Integer to float: the integer on `opnd[63:0]` as the source. Float to
integer: `op_prec` carries the width (opts bit 0: 1 = 64 bits), a truncate
(opts bit 1) is driven as `op_rm` 01, and `res` is compared with
`{0000, rint}`. A stress file in the same format replays with
`obj_dir/tb_fpu_dp/tb_fpu_dp [--mclk 1] <file>.vec` once `make test-fpu-dp`
has built the bench.

Contract the Interface Processor uses: `start` latches the operation; a
CLK.D rise in the same master clock is its first clock. `done` is High in
the master clock of the last clock's CLK.D rise, from registered state,
with the result latch already loaded, so /BSY and the first result word
can move in that master clock. `start` in the same master clock as `done`
is not allowed (a queued operation starts the master clock after `done`).

### The `cpufpu` file and the system bench

```
K8000VEC 1 cpufpu
variant Z8001                       Z8001 | Z8002
test TestFPUSystemFADD 0
board bsywait 1 fpuid 0             /BSY to /WAIT as well as STOP; the ID pins
mem 000000 10000                    mapped memory: base, size
M <addr> <word>                     memory the test wrote
P C <reg> <hex> / P E <reg> <hex>   CPU / FPU register the test wrote
C <cpu T record fields>             one CPU record
E <fpu T record fields>             one FPU record
W <addr> <word>                     a word a bus write changed in that step
F C ..., F E ..., F M <addr> <word> final CPU, FPU, nonzero memory
END
```

Per system step: C (CLK 0), C (CLK 1), E (CLK.I 0), E (CLK.I 1). Test
writes come before both chips' records of the step they land in.

`tb_cpu_fpu.sv` wires the two RTL chips on their pins: one master clock,
CPU CLK = CLK.I = CLK.D, /BSY to STOP and, with `bsywait`, to /WAIT while
the status latched on /AS is 1010, 1011 or 1110 (to the /DS rise), /INT to
/VI, IEI High, OPT 11, one /RESET. The C++ memory follows {SN, AD} while /AS
is Low, drives read data while /DS is Low on a memory status (not 1110) and
writes at the /DS rise what was driven while /DS was Low; an undriven write
(a store word the FPU did not have) leaves memory as it was. Only the board
inputs come from the records.

| compared | rule |
|---|---|
| CPU outputs | every C record, the CPU bench's rules |
| STOP, /WAIT | at each CLK fall, as the CPU took them |
| /VI | at a CLK rise that takes it (an instruction's or HALT's sample) |
| AD in | at a read's T3 rise record: AD as CLK falls in T3, where the CPU takes it |
| FPU ADDrive, BSY_n, INT_n, IEO, AD | at each CLK.I = 1 E record: what the CPU sees next |
| memory | changed words in order against W; final memory, CPU and FPU registers |
| AD drivers | two at once fails, but for an EPU store's data from the /AS rise over the CPU's address until it floats at T2 (spec p.546 drive edge), counted as `store-overlap` |

### The `fpuenc` file

```
K8000VEC 1 fpuenc
W <IF1 bits 15:8> <digest>                               256 lines, each over 256 IF1 words: {first-byte flag, template found, template, ID}
P <template> <word 1 bits 7:4> <code> <valid> <digest>   7168 lines, each over 1024 word 2s: rounding, register, n-1
END
```

Digests are FNV-1a 64 over each packed value, low byte first; the plan
packs {valid, mnemonic, template, Fd, Fs, format, rounding, select, list
byte, direction, words}, 0 when invalid. Together the lines cover every
IF1 word and every input the plan decode reads; a mismatch names the
template, word 1 nibble and operation code.

## What is covered

* `make test-fpu`: 1382 files, 1381 PASS, 1 SKIP (TestSnapshotMidOperation.001:
  a poke of internal state).
* `make test-cpu-fpu`: 457 of 457 on the Z8001 and 17 of 17 on the Z8002.
* `make test-fpu-fastd`, at `--mclk 1` and `1,2,1,3` each: fpu 1379 PASS, 3
  SKIP; system 468 PASS, 6 SKIP. Skipped: TestSnapshotMidOperation.001 (a poke
  of internal state) and eight files whose outcome depends on the Data
  Processor's speed, each failing at `1,2,1,3`: TestLostStoreWord,
  TestQueueAbortAtStart, TestFPUSystemInterrupt (2), TestFPUSystemStoreWithoutWait
  (2), TestFPUSystemQueueHoldTrap (2). PC2 is not compared there (only an IF1 while busy loads it). At 5 or
  more master clocks a level TestQueueAbort and TestSnapshotMidOperation.000
  depend on the speed too.
* `make test-fpu-slowd`, CLK.D at every 8th and 12th CLK.I rise, at `--mclk 1`
  and `1,2,1,3` each: fpu 1380 PASS, 2 SKIP (TestSnapshotMidOperation.000 ends
  mid-operation; .001 a poke); system 474 PASS.
* Queue sweep, in the files above. An inexact FDIV, B queued complete
  behind it, C around the clock P that promotes B, then FADD F6,F7
  (inexact). B: FLD from memory, internal FADD, FSETMODE, FLDCTL USER in,
  EPU<-FCW; C: internal FDIV, FLD from memory, FLD store, FLDCTL FOP2 out,
  FSETMODE. A second set: B FADD, FSUB or FMUL from memory into F2 or F4,
  or FLDCTL SC in; C internal FINT, FNEG, FSQR, FRDIV (the first read
  Fs), FLDCTL FFLAGS out, an invalid word 2. TestQueueSweep* (1295 pin
  files; the second set with B FADD and SC): per C the four run
  one by one, then C's IF1 held with its word 2 at P-4 .. P+6 CLK
  half-periods and its operand words right behind, or its IF1 at P-1 ..
  P+4 with word 2 right behind, with CLK.D as CLK.I and inverted.
  TestFPUSystemSweep* (332 Z8001 files, both sets): the CPU runs the same instructions
  with 0-48 clocks of fill after the FDIV; per (B, C) one file for each
  class of C's IF1 and word 2 offsets from P (clamped to -4..+4 and
  -4..+8 half-periods, or no queue). TestFPUSystemQueueRandom (64 Z8001
  files, fixed seed): the FDIV, 0-48 clocks of fill, then 2 to 5
  instructions from both sets with 0-12 clocks of fill. Each is checked
  when recorded, SC (the overlap bits aside) and PC1 included: a sweep
  file against the one-by-one run, a random one against the same
  instructions run far apart (PC1 as the instruction it names). All run
  in every mode below and in `make test-mclk`.
* TestFPUSystemStopShort (44 Z8001 files): the FDIV, a fill, internal FADD,
  then INC, DEC, INCB, DECB, LD, LDB, LDK, ADD, ADDB, EX or EXB on R1, then
  FLD from memory. The fill puts the /BSY-driven STOP on that instruction's
  IF1, with streams of 1, 2, 3 and 12 refreshes; it runs once, after the
  stream. Checked when recorded against the same program run far apart,
  CPU registers included.
* `make test-fpu-enc`: 65536 IF1 words and 7 templates x 16 x 65536 word 2s
  (7168 digests).
* `make test-fpu-timing`: 72 checks.
* `make test-fpu-dp`: 123,209 of 123,209 records over the 11 groups.

### Assumed

Every choice no source settles. A later source replaces rows here and in
the code they name.

Encoding and behaviour:

| item | why |
|---|---|
| FCPZNF/FCPZXNF codes 01/02 on internal, memory and CPU templates | no Zilog source gives the codes; internal operand in word 1 bits 7:4 like FCPZ |
| FLDCTLB on the EPU<-FCW template writes the compare flags | no Zilog source lists an EPU<-FCW form |
| FLDM and FLDNF share code 23, run as FLDNF | no separate codes are given |
| FLDCTL select 3 is Invalid opcode | no register is named for select 3 |
| FLDBCD needs n = 5 | n = 1 forms carry an extra operand whose meaning is not given |
| list target: word 1 bit 5 (trap) tested before bit 4 (compare byte) | the order is not given; no form sets both |
| list byte: bits 5:0 in word 2 bits 13:8, bits 7:6 in word 1 bits 7:6 | the layout is not given; word 2 bits 15:8 would overlap the operation code |
| 8E with direction 11, and 0E/4E, raise Invalid opcode on the EPU their ID names | no template (TM PDF p.232-236) |
| PC1/PC2 = {0, SN6-0, 00, IF1 address}; PC1 takes PC2 when the queued instruction starts | the Z8000 interface sends no PC; format not given |
| An invalid word 2 raises Invalid opcode when its instruction would run: at once if executing, when promoted if queued or held, PC1 then its address | PC1 and PC2 are defined (p.533) but not for an invalid opcode, nor when the interrupt is raised; program order keeps an earlier SC write or trap ahead of it |
| FOP exponent MSBs: FOP1/FOP2 exponent bits 14:13 copied into FFLAGS 27:26/25:24 | the spec gives the fields, not which exponent bits |
| IEO blocked by a request from /AS rise to /DS rise of an acknowledge of the SC INTACK type | spec says only "Interrupt Acknowledge cycle" |
| the acknowledge is decided at the /DS fall (SC.IP and SC.MIE, IEI) and held to the /DS rise: the vector, IEO and the IUS set | p.556 decides it when RD falls, for the Universal interface; the Z8000 interface's text does not say |
| /INT = SC.IP and SC.MIE; IP is writable by FLDCTL SC, so clearing it withdraws the request | p.534: IP "a pending interrupt", MIE enables interrupts; SC is written whole |
| Intermediate overlap: /BSY Low while a queued instruction and its operand words are complete (V1) | US 4,648,034 FIG. 7 (OVRLP 10: V1); p.535 stops the CPU after a second instruction is transferred |
| /BSY Low from a store's word-2 decode until its word is ready, both overlap modes; the board takes /BSY to /WAIT in EPU data cycles | US 4,648,034 FIG. 7, FIG. 11 (a decoded store forces the busy term); p.542 Wait during stores, p.546 WAIT extends transfers; Fig 14 draws STOP only |
| exception flush: an arithmetic trap drops the queued instruction, complete or in transfer; PC2 keeps its address | p.535, p.558 flush on an exception; which exceptions is not said, the trapped ones are those a handler re-transfers |
| byte drives (vector, flag byte, FLDCTLB) put 00 on AD15-8 | spec names AD7-0 only |
| SC VIS ignored | status format not given |
| zero Interface Processor latency | none published |
| FLDCTL of FOP1 or FOP2 right after a flagged operation waits on /BSY three CLK.I rises from done, that of done included | FOP1/FOP2 are written back after done (F[Fd], FOP1, FOP2 share one register-file port); none published |
| a subnormal single or double bus operand reaches the Data Processor unnormalized (integer bit 0); only FABS/FNEG and FOP1 keep that form; it raises DE, as any unnormal operand does (p.535 "a denormalized number") | the Interface Processor moves fields; the Data Processor's unpack renormalizes every operand |
| FOP1 of FLDIL/FLDIQ is the integer in the significand field, of FLDBCD the container | FOP1 is the input operand (p.534); its form for a conversion is not given |
| FOP2 of an integer store is the integer in the significand field; of a tiny single or double store its denormalized form (subnormal exponent, integer bit 0) | FOP2 is the default result (p.534); the Data Processor holds a store's result in its fields |
| F0-F7 and FOP1/FOP2 cleared by /RESET | p.542 names only USER, FFLAGS and SC. The RTL keeps them in one RAM that powers up 0 and is not cleared by a later reset; no vector writes them before a second reset |
| a store word is driven from the /AS rise to the /DS rise | p.546 text: "places the data on the bus when AS rises"; Fig 16 draws it after the address |
| FLDCTL SC privilege is the N/S level at the last transfer's /AS rise | p.534 says only "privileged"; the cycle is not named |
| FLDCTL into PC1, PC2, FOP1 or FOP2 is dropped without an interrupt | p.533-534 make them read only; the effect of a write is not given |
| multiply: the multiplier's bits below the precision's top nS go only to sticky (M x the truncated multiplier, then sticky) | the multiply clocks fix nS multiplier bits; an extended operand in a single or double multiply is not covered |
| remainder flags: FD reduction complete, FZ zero remainder, FS its sign, FH the quotient's low bit; an invalid or NaN remainder writes all 0. Every compare and remainder writes the field, all 0 included | p.533 Table 1 gives the compare codes only (< FC FS FD, = FZ, > FD, unordered FV); p.539 FREMSTEP sends "the immediate result flag" to the CPU, layout not given |
| float to integer out of range, NaN or infinity: the most negative integer | not given |
| BCD store out of range (IX): the low 19 digits of the rounded integer (of the significand's 64 bits at 2^64 or more); NaN and infinity a zero container | not given |

Data Processor clocks (published: add/sub 18/18/18, mul 28/42/48, div
29/43/49, p.532):

| operation | single/double/extended | reading |
|---|---|---|
| rvsub | 18/18/18 | the add path |
| pwr2 | 28/42/48 | the multiply path |
| rdiv | 29/43/49 | the divide path |
| sqrt | 37/66/77 | 13 + significand bits: the unpack's B half (2), special select, exponent halve, load with the first root bit, one root bit a clock, root window, normalize (2), denormalize, round, range, result latch, hand-over |
| load | 18/18/18 | the add path |
| fint | 11/11/11 | the unpack's B half (2), special select with the shift count, align to the integer point, round there, normalize (2), round, range, result latch, hand-over; 8 for a zero integer, 5 on a special operand |
| add family on a NaN, infinity or two zeros | 7 | the unpack (4), the special select, result latch, hand-over |
| add family on an exact cancellation | 14 | the add path to the leading-zero count, result latch, hand-over |
| abs, neg, clr | 4/4/4 | read, sign op into the result side, result latch, hand-over |
| cmp, cmpz | 11/11/11 | the unpack (4), NaN test, exponent compare, significand compare with the magnitude relation, signed relation, code, result latch, hand-over |
| mul, div, rem on a NaN, infinity or zero operand | 7 | the unpack (4), the special select, result latch, hand-over |
| sqrt on a NaN, zero, negative or infinite operand | 5 | the unpack's B half (2), the special select, result latch, hand-over |
| rem | 29/43/49 | a full batch; n quotient bits take 17 + floor(n/2): the unpack (4), special select, exponent difference, batch length, load, floor(n/2) + 1 SRT digits, correction, normalize (2), denormalize, round, range, result latch, hand-over |
| rem with a zero remainder | 12 + floor(n/2) | the correction finds zero and goes to the result latch |
| remstep | 29/43/49 | rem; the flag transfer to the CPU is Interface Processor bus work, as FCPF runs FCP's clocks |
| int to float | 7 | one adder pass reads the integer, normalize (2), round, range, result latch, hand-over; 4 for zero |
| float to int | 8 | the unpack's B half (2), special select, align, round at the integer point, negate and range, result latch, hand-over; 5 on a special operand |
| from BCD | 27 | read, digit check, one x10 shift-add per digit (19), normalize (2), round, range, result latch, hand-over; 24 for zero, 4 for a non-decimal digit |
| to BCD | 63 | FINT's front end (5), dividend and 10^19 load, 34 SRT digits of h / 10^19, quotient, one x10 per digit (19), digits out, result latch, hand-over; 5 on a special operand |

The split of every count into clocks, published total or not, is a guess;
`rtl/k8070_fpu/z8070_dp_ucode.txt` names each clock and tags each routine.

## Known gaps

* Every "Assumed" row above, and the clock split of every Data Processor
  routine.
* OPT1-OPT0: only the Z8000 interface (11) is built.
* TestSnapshotMidOperation.001 SKIPs: its poke of internal state has no
  `P` form.
