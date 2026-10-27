# CPU performance tests for a real C900

`k8000` is verified against the Go golden model, whose cycle counts come
from the datasheet (Z8000 CPU Technical Manual Mar81 sec 6.7, via
`cyclesPLA`; `docs/TIMING_TESTS.md` sec 3). None of it has been compared
against a real Z8001. These programs do that: they run on a Commodore 900
under Coherent, and their output is checked against the model.

They are ordinary user programs: no root, no device access, nothing written
outside the build directory, about ten minutes in all.

## What we are hoping to learn

The main targets are `MULT`, `MULTL`, `DIV`, `DIVL` and block moves, where a
bit-serial sequencer can be wrong by fifty clocks rather than one.

| question | which test answers it |
|---|---|
| **The one open question, with a control.** `SLA` is published as `13 + 3n`, so a shift by 8 costs 37 in isolation; our CPU runs it in 34 back-to-back, fetching the successor's *second word* while the shifter runs. With a one-word successor the saving vanishes. Is that overlap real silicon? | `sla8w1` is the control: **410 per iteration under both readings**, so it measures board overhead alone. `sla8` then reads **353 if the overlap is real, 380 if not** |
| `MULT` is a flat 70 with no per-bit term. | `multff - mult1` **must be 0**: same code, emptiest against fullest operand |
| `MULTL` is `282 + 7n`, n = set bits in the low 16 of the multiplicand. A pair measures the *slope*, the part a structural model gets wrong. | `multl5 - multl3` **must be 70** (5 copies x 7 x 2) |
| `LDIR` is `11 + 9n`. | `ldir64 - ldir4` **must be 540**, plus 120 accesses' worth of wait states that `ldind`/`stind` measure independently |
| Word `DIV` is 107 clocks (1988 data book, for R, IM and IR), as our CPU executes. Never checked on hardware. | `abench` line `div` |
| `DIVL` is 744, published and in our CPU. A control: if hardware disagrees *here*, everything above is moot. | `abench` line `divl` |
| What do DRAM refresh, wait states and the MMU add? Our model has none of them. | `ldrr` vs `ldimm` vs `ldind` vs `stind` vs `ldda` |
| Is a C900 as fast overall as our simulation of one? | `bench` + the generated `bench.s` |

## What to run, in order

Build in your own directory on the C900 (not a read-only disk), with the
machine otherwise idle. Everything writes only to stdout.

```
make probe
./probe > probe.out
```

**Stop and look at `probe.out` before continuing.** Two lines matter:

* `TICKSRC OK` -- the CPU-time clock works. If it says `BAD`, rebuild
  everything with `make CFLAGS="-O -DTB_FTIME"`, and if that fails too,
  `-DTB_TIME` (results will be coarse but still usable).
* `SIZEOF_PTR` -- 2 means nonsegmented user code and the assembly tier
  works as written; 4 means segmented, and `asm/kernels.s` needs the
  substitutions in its header comment.

Then the C tier, which always works:

```
make bench
./bench > bench.out
make bench.s          # keep this file, it is half the measurement
```

`bench` takes about three minutes. Run it twice; runs more than a percent
or two apart mean something else was using the machine.

Then, if you are willing, the assembly tier, which gives the sharp numbers:

```
make aprobe
./aprobe              # expect: PROBE 12345 / PROBE_OK 1
```

`asm/probe.s` is ten lines that test whether the assembler takes our syntax
and which register the compiler returns a value in. If it does not
assemble, **send us the error message and stop**: that message tells us how
to write the rest, and `bench.out` alone is worth having.

If `aprobe` prints `PROBE_OK 1`:

```
make abench
./abench > abench.out
```

About five minutes (21 kernels).

## What to send back

* `probe.out`, `bench.out`, `abench.out`
* `bench.s` (from `make bench.s`)
* the exact `cc` version banner, if it prints one
* which `CFLAGS` you ended up using
* any assembler or linker errors, verbatim, however trivial they look

`bench.s` matters as much as `bench.out`: it shows which instructions the
compiler emitted, which turns every `bench.out` line into a figure we can
check against the model.

## How the numbers are read

`abench` prints measured clocks per loop iteration for each kernel,
assuming a 6.000 MHz Z8001 (12 MHz crystal / 2). `expected/expected.txt`
has two predictions per kernel:

* `spec` -- **what Zilog published**: a hand-curated per-opcode table in
  the generator, each entry citing its page. The generator checks every
  entry against the model's decode ROM and prints `DRIFT` where they
  disagree; it never takes a figure from the model.
* `exec` -- what the model's CPU does, measured in a simulated flat-RAM
  Z8002 as clocks between instruction fetches at the loop head.

Nineteen of the twenty-one kernels agree on both; they are the controls
that let board overhead be measured and subtracted. `sla1` and `sla8` differ
by 27 clocks each: nine of the ten shifts per iteration overlap their
successor's fetch and save 3 clocks apiece, while the tenth follows the
loop branch, finds the queue flushed, and pays in full:
`9x13 + 16 + 10 = 143` and `9x34 + 37 + 10 = 353`.

**Read the pairs before the absolutes.** Absolute numbers include refresh
and wait states no prediction contains. Paired kernels differ only in an
operand, so that overhead cancels: `multff - mult1`, `multl5 - multl3` and
`ldir64 - ldir4` are worth more than any single figure.

The `DRIFT` section should be empty. If not, the model's decode ROM has
drifted from a published figure: a model fault, not a measurement.

Measured will always be *higher* than predicted: the prediction has no
refresh, wait states or interrupt overhead. The shape of the excess says
which:

* a fixed cost per instruction *word* -- visible as `ldimm` minus `ldrr`
  being more than the predicted 4 clocks -- is a fetch wait state;
* an extra cost only where there is a data transfer (`ldind`, `stind`,
  `ldda`, `pushpop`, `ldir64`) is a data-access wait state;
* the same percentage on everything is refresh, or a clock that is not
  6.000 MHz;
* **one kernel out of line on its own is an instruction whose cycle count
  we have wrong** -- the thing worth finding.

## Layout

```
probe.c        step 1: int size, pointer size, clock source, tick rate
tb.c tb.h      the timing base (times(2), with ftime/time fallbacks)
bench.c        step 2: 31 C-level kernels -- arithmetic, memory, control
               flow, block copy, calls
asm/probe.s    step 3a: ten lines, does the assembler take our syntax
asm/aprobe.c     and does C reach the routine
asm/kernels.s  step 3b: 21 per-instruction kernels, 1000 iterations of a
               ten-copy body each, every register saved and restored; six of
               them are three matched PAIRS whose difference cancels the
               board's overhead, plus one control
asm/adriver.c  step 3c: times them
expected/expected.txt   predicted clocks per kernel, DERIVED but COMMITTED
expected/gen/           the generator (maintainer tool: needs the Go model,
                        like `make refresh-rtl`)
RESULTS_TEMPLATE.txt    a form to paste the outputs into
```

The C is K&R (no prototypes, `void`, `long long` or floating point) so a 1985
Mark Williams compiler and a modern gcc both accept it. `make dryrun` builds
it here with `gcc -std=gnu89`; the `.s` files cannot be checked that way,
hence `asm/probe.s`.
