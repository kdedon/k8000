/*
 * bench.c -- step 2.  The C-level CPU performance suite for the C900.
 *
 *	cc -O -o bench bench.c tb.c
 *	./bench > bench.out
 *
 * WHAT THIS MEASURES.  Not instructions -- C statements.  What the Z8001
 * actually executes for "a += b" is the compiler's business, so a raw
 * number from here means nothing on its own.  It becomes a measurement of
 * the CPU when it is paired with the code the compiler generated:
 *
 *	cc -O -S bench.c		(keep bench.s -- send it back)
 *
 * With bench.s in hand every RESULT line turns into an exact claim about
 * the CPU: we disassemble the loop body, add up the datasheet cycle counts
 * the k8000 model uses, and compare that against the measured figure.  A
 * systematic gap is a cycle-count error in the model (or a wait state the
 * model does not know about); a gap on one line only is that instruction.
 *
 * HOW IT MEASURES.  Every kernel is an n-times loop over an 8-fold
 * unrolled body, so loop control is ~1/8 of the cost and the `loop_empty`
 * kernel measures what is left.  n is scaled until the run lasts long
 * enough to be worth a tick count, each kernel is run three times and the
 * SHORTEST run is kept (interference can only add time).  With times(2)
 * the figure is process CPU time, so other load lengthens the wall clock
 * but not the result.
 *
 * K&R C: no prototypes, no void, no long long, no floating point.
 */

#include <stdio.h>
#include "tb.h"

#define TARGET_TICKS 100L	/* ~1 s per run at HZ=100 */
#define START_ITERS 500L
#define MAX_ITERS 20000000L
#define RUNS 3
#define UNROLL 8

#define U8(s) s s s s s s s s

long sink;			/* every kernel feeds this: nothing is dead code */
int isink;

/* ---- the kernels ------------------------------------------------------- */
/* Each returns a checksum.  The checksums are printed: two machines (or a
 * machine and the simulator) running the same binary must agree on them. */

long
k_empty(n) long n; {
	register long i;
	register int a;
	a = 0;
	for (i = 0; i < n; i++) { U8(;) }
	return (long) a + i;
}

long
k_add16(n) long n; {
	register long i;
	register int a, b;
	a = 1; b = 3;
	for (i = 0; i < n; i++) { U8(a += b;) }
	return (long) a;
}

long
k_sub16(n) long n; {
	register long i;
	register int a, b;
	a = 1; b = 3;
	for (i = 0; i < n; i++) { U8(a -= b;) }
	return (long) a;
}

long
k_and16(n) long n; {
	register long i;
	register int a, b;
	a = -1; b = 0x5A5A;
	for (i = 0; i < n; i++) { U8(a &= b;) }
	return (long) a;
}

long
k_xor16(n) long n; {
	register long i;
	register int a, b;
	a = 0x1234; b = 0x5A5A;
	for (i = 0; i < n; i++) { U8(a ^= b;) }
	return (long) a;
}

long
k_mul16(n) long n; {
	register long i;
	register int a, b;
	a = 1; b = 3;
	for (i = 0; i < n; i++) { U8(a *= b;) }
	return (long) a;
}

long
k_div16(n) long n; {
	register long i;
	register int a, b;
	b = 3;
	for (i = 0; i < n; i++) { a = 30000; U8(a /= b;) sink += a; }
	return (long) a;
}

long
k_mod16(n) long n; {
	register long i;
	register int a, b;
	b = 7;
	for (i = 0; i < n; i++) { a = 30000; U8(a %= b; a += 30000;) }
	return (long) a;
}

long
k_add32(n) long n; {
	register long i, a, b;
	a = 1; b = 3;
	for (i = 0; i < n; i++) { U8(a += b;) }
	return a;
}

long
k_mul32(n) long n; {
	register long i, a, b;
	a = 1; b = 3;
	for (i = 0; i < n; i++) { U8(a *= b;) }
	return a;
}

long
k_div32(n) long n; {
	register long i, a, b;
	b = 3;
	for (i = 0; i < n; i++) { a = 1000000L; U8(a /= b;) sink += a; }
	return a;
}

long
k_shl1(n) long n; {
	register long i;
	register int a;
	a = 1;
	for (i = 0; i < n; i++) { U8(a <<= 1; a |= 1;) }
	return (long) a;
}

long
k_shl8(n) long n; {
	register long i;
	register int a;
	a = 1;
	for (i = 0; i < n; i++) { U8(a <<= 8; a |= 0x55;) }
	return (long) a;
}

long
k_shr_var(n) long n; {
	register long i;
	register int a, s;
	a = -1; s = 5;
	for (i = 0; i < n; i++) { U8(a >>= s; a |= 0x4000;) }
	return (long) a;
}

long
k_shl32(n) long n; {
	register long i, a;
	a = 1;
	for (i = 0; i < n; i++) { U8(a <<= 1; a |= 1;) }
	return a;
}

/* --- memory: the interesting axis on a machine with an MMU ------------- */

#define ASIZE 4096
int warr[ASIZE];
char barr[ASIZE];
int gvar;

long
k_load_idx(n) long n; {
	register long i;
	register int a, j;
	a = 0; j = 0;
	for (i = 0; i < n; i++) { U8(a += warr[j]; j = (j + 17) & (ASIZE - 1);) }
	return (long) a;
}

long
k_store_idx(n) long n; {
	register long i;
	register int j;
	j = 0;
	for (i = 0; i < n; i++) { U8(warr[j] = j; j = (j + 17) & (ASIZE - 1);) }
	return (long) warr[3];
}

long
k_load_ptr(n) long n; {
	register long i;
	register int a;
	register int *p;
	a = 0;
	for (i = 0; i < n; i++) {
		p = warr;
		U8(a += *p++;)
	}
	return (long) a;
}

long
k_store_ptr(n) long n; {
	register long i;
	register int *p;
	for (i = 0; i < n; i++) {
		p = warr;
		U8(*p++ = 1;)
	}
	return (long) warr[0];
}

long
k_load_byte(n) long n; {
	register long i;
	register int a;
	register char *p;
	a = 0;
	for (i = 0; i < n; i++) {
		p = barr;
		U8(a += *p++;)
	}
	return (long) a;
}

long
k_global(n) long n; {
	register long i;
	for (i = 0; i < n; i++) { U8(gvar += 3;) }
	return (long) gvar;
}

long
k_localvar(n) long n; {
	long i;
	int a, b;		/* deliberately NOT register: frame accesses */
	a = 1; b = 3;
	for (i = 0; i < n; i++) { U8(a += b;) }
	return (long) a;
}

/* --- control flow ------------------------------------------------------ */

static int
leaf0() { return 1; }

static int
leaf3(a, b, c) int a, b, c; { return a + b + c; }

long
k_call0(n) long n; {
	register long i;
	register int a;
	a = 0;
	for (i = 0; i < n; i++) { U8(a += leaf0();) }
	return (long) a;
}

long
k_call3(n) long n; {
	register long i;
	register int a;
	a = 0;
	for (i = 0; i < n; i++) { U8(a += leaf3(1, 2, 3);) }
	return (long) a;
}

long
k_branch_t(n) long n; {
	register long i;
	register int a, b;
	a = 0; b = 1;
	for (i = 0; i < n; i++) { U8(if (b) a++;) }
	return (long) a;
}

long
k_branch_n(n) long n; {
	register long i;
	register int a, b;
	a = 0; b = 0;
	for (i = 0; i < n; i++) { U8(if (b) a++;) }
	return (long) a;
}

long
k_switch(n) long n; {
	register long i;
	register int a, j;
	a = 0; j = 0;
	for (i = 0; i < n; i++) {
		U8(switch (j & 7) {
		case 0: a += 1; break;
		case 1: a += 2; break;
		case 2: a += 3; break;
		case 3: a += 4; break;
		case 4: a += 5; break;
		case 5: a += 6; break;
		case 6: a += 7; break;
		default: a += 8; break;
		} j++;)
	}
	return (long) a;
}

/* --- block operations: does the compiler reach for LDIR / CPIR? -------- */

long
k_copy_word(n) long n; {
	register long i;
	register int j;
	for (i = 0; i < n; i++)
		for (j = 0; j < 64; j++)
			warr[j] = warr[j + 64];
	return (long) warr[0];
}

long
k_copy_byte(n) long n; {
	register long i;
	register int j;
	for (i = 0; i < n; i++)
		for (j = 0; j < 64; j++)
			barr[j] = barr[j + 64];
	return (long) barr[0];
}

long
k_strlen(n) long n; {
	register long i;
	register long a;
	a = 0;
	for (i = 0; i < n; i++)
		a += strlen(barr + 128);
	return a;
}

long
k_strcmp(n) long n; {
	register long i;
	register long a;
	a = 0;
	for (i = 0; i < n; i++)
		a += strcmp(barr + 128, barr + 192);
	return a;
}

/* ---- the runner -------------------------------------------------------- */

struct bench {
	char *name;
	long (*fn)();
	int unroll;		/* operations per loop iteration */
	char *note;
};

struct bench benches[] = {
	{"loop_empty",  k_empty,     UNROLL, "loop control only -- the baseline"},
	{"add16",       k_add16,     UNROLL, "int += int"},
	{"sub16",       k_sub16,     UNROLL, "int -= int"},
	{"and16",       k_and16,     UNROLL, "int &= int"},
	{"xor16",       k_xor16,     UNROLL, "int ^= int"},
	{"mul16",       k_mul16,     UNROLL, "int *= int -- MULT, 70 clocks claimed"},
	{"div16",       k_div16,     UNROLL, "int /= int -- DIV, 107 vs 744 open"},
	{"mod16",       k_mod16,     UNROLL, "int %= int -- DIV remainder"},
	{"add32",       k_add32,     UNROLL, "long += long"},
	{"mul32",       k_mul32,     UNROLL, "long *= long -- MULTL, 282 claimed"},
	{"div32",       k_div32,     UNROLL, "long /= long -- DIVL, 744 claimed"},
	{"shl1",        k_shl1,      UNROLL, "int <<= 1 (+ or)"},
	{"shl8",        k_shl8,      UNROLL, "int <<= 8 (+ or) -- per-step shifter cost"},
	{"shr_var",     k_shr_var,   UNROLL, "int >>= variable (+ or) -- SDA path"},
	{"shl32",       k_shl32,     UNROLL, "long <<= 1 (+ or)"},
	{"load_idx",    k_load_idx,  UNROLL, "int from array[i] -- indexed EA"},
	{"store_idx",   k_store_idx, UNROLL, "int to array[i]"},
	{"load_ptr",    k_load_ptr,  UNROLL, "int via *p++ -- indirect EA"},
	{"store_ptr",   k_store_ptr, UNROLL, "int to *p++"},
	{"load_byte",   k_load_byte, UNROLL, "char via *p++ -- byte bus cycle"},
	{"global",      k_global,    UNROLL, "global int += 3 -- direct address"},
	{"localvar",    k_localvar,  UNROLL, "stack local += stack local"},
	{"call0",       k_call0,     UNROLL, "call/return, no arguments"},
	{"call3",       k_call3,     UNROLL, "call/return, three arguments"},
	{"branch_t",    k_branch_t,  UNROLL, "conditional branch, taken"},
	{"branch_n",    k_branch_n,  UNROLL, "conditional branch, not taken"},
	{"switch8",     k_switch,    UNROLL, "8-way switch"},
	{"copy_word",   k_copy_word, 64,     "64 int copies -- LDIR candidate"},
	{"copy_byte",   k_copy_byte, 64,     "64 char copies -- LDIRB candidate"},
	{"strlen32",    k_strlen,    32,     "strlen of a 32-char string"},
	{"strcmp32",    k_strcmp,    32,     "strcmp of two 32-char strings"},
	{0, 0, 0, 0}
};

/* safe_x1000 -- cycles*1000/ops without overflowing a 32-bit long. */
long
safe_x1000(cycles, ops) long cycles; long ops; {
	long q, r;

	while (ops > 2000000L) {	/* keep r*1000 in range */
		ops = ops / 2;
		cycles = cycles / 2;
	}
	if (ops <= 0)
		return 0;
	q = cycles / ops;
	r = cycles % ops;
	return q * 1000L + (r * 1000L) / ops;
}

runone(b, clocks_per_tick) struct bench *b; long clocks_per_tick; {
	long iters, t0, t1, best, ticks, chk, ops, cyc;
	int run;

	/* Scale to TARGET_TICKS.  Once a run is long enough to have produced
	 * any ticks at all the next size is PREDICTED from it, so a kernel
	 * whose operation costs 744 clocks does not overshoot into minutes
	 * the way repeated quadrupling would. */
	iters = START_ITERS;
	for (;;) {
		t0 = tb_ticks();
		chk = (*b->fn)(iters);
		t1 = tb_ticks();
		ticks = t1 - t0;
		if (ticks >= TARGET_TICKS || iters >= MAX_ITERS)
			break;
		if (ticks <= 0) {
			iters = iters * 8;
		} else {
			/* iters * TARGET / ticks, in two steps: no overflow */
			iters = (iters / ticks) * TARGET_TICKS
				+ ((iters % ticks) * TARGET_TICKS) / ticks;
			iters = iters + iters / 8 + 1;	/* 12% margin */
		}
		if (iters > MAX_ITERS)
			iters = MAX_ITERS;
	}

	best = -1;
	for (run = 0; run < RUNS; run++) {
		t0 = tb_ticks();
		chk = (*b->fn)(iters);
		t1 = tb_ticks();
		ticks = t1 - t0;
		if (best < 0 || ticks < best)
			best = ticks;
	}

	ops = iters * (long) b->unroll;
	cyc = best * clocks_per_tick;
	printf("RESULT %-10s iters=%-9ld unroll=%-3d ticks=%-6ld clocks_per_op_x1000=%-8ld chk=%ld\n",
	       b->name, iters, b->unroll, best,
	       safe_x1000(cyc, ops), chk);
	fflush(stdout);
	return 0;
}

selftest()
{
	int a;
	long l;
	int bad;

	bad = 0;
	a = 30000; a /= 3; if (a != 10000) bad++;
	a = 30000; a %= 7; if (a != 30000 % 7) bad++;
	a = 0x1234; a ^= 0x5A5A; if (a != (0x1234 ^ 0x5A5A)) bad++;
	l = 1000000L; l /= 3; if (l != 333333L) bad++;
	l = 65536L * 100L; if (l != 6553600L) bad++;
	a = -1; a >>= 5; if (a != -1) bad++;	/* arithmetic shift expected */
	printf("SELFTEST %s  # %d failures\n", bad ? "BAD" : "OK", bad);
	return bad;
}

main(argc, argv) int argc; char **argv; {
	long hz, cpt;
	struct bench *b;
	int i;

	for (i = 0; i < ASIZE; i++) {
		warr[i] = i;
		barr[i] = (char) (i | 1);
	}
	for (i = 0; i < 32; i++) {
		barr[128 + i] = 'a';
		barr[192 + i] = 'a';
	}
	barr[128 + 32] = 0;
	barr[192 + 32] = 0;

	printf("# k8000/bench/c900 -- C-level CPU performance suite\n");
	printf("# clocks_per_op_x1000 is nominal Z8001 clocks per C operation,\n");
	printf("# times 1000, assuming a %ld Hz CPU.  Divide by 1000.\n",
	       TB_NOMINAL_CPU_HZ);
	selftest();
	hz = tb_hz();
	cpt = tb_percall();
	printf("TICK_HZ %ld\n", hz);
	printf("CLOCKS_PER_TICK %ld\n", cpt);
	if (hz <= 0) {
		printf("# no usable clock -- see probe.c, rebuild with -DTB_FTIME\n");
		return 1;
	}
	for (b = benches; b->name; b++)
		runone(b, cpt);
	printf("# done.  Send back this output AND the bench.s from cc -O -S.\n");
	return 0;
}
