/*
 * adriver.c -- step 3c.  Times the assembly kernels in kernels.s.
 *
 *	cc -o abench adriver.c tb.c kernels.s	(add ../tb.c's directory:
 *	cc -I.. -o abench adriver.c ../tb.c kernels.s)
 *	./abench > abench.out
 *
 * Every kernel is one C call that runs 1000 iterations of a fixed body of
 * ten copies of the instruction under test.  The driver only counts calls
 * and ticks -- it makes no assumption about arguments or return values,
 * because the kernels take none and return none.
 *
 * Compare the clocks_per_iter column against ../expected/expected.txt.
 * The two will not be equal: real memory has wait states and the DRAM
 * refresh steals cycles, and neither is in the prediction.  What matters
 * is the SHAPE of the difference:
 *
 *   - a constant per-instruction-word offset  -> fetch wait states
 *   - an offset only on ldind/stind/ldda/ldir -> data-access wait states
 *   - a percentage on everything              -> refresh, or the clock is
 *                                                not 6.000 MHz
 *   - one kernel out on its own               -> that instruction's cycle
 *                                                count in the model is wrong
 *
 * The last one is what this exists to find.  k_div is the standing
 * suspect: the model says 744 clocks, the Zilog Reference Manual says 107.
 */

#include <stdio.h>
#include "tb.h"

#define TARGET_TICKS 100L
#define MAX_CALLS 2000000L
#define RUNS 3
#define ITERS_PER_CALL 1000L	/* the loop count inside every kernel */

/* Referenced by kernels.s.  bsrc/bdst are the block-move and indirect
 * buffers; gword is the direct-address target. */
int buf[256];
int *bsrc;
int *bdst;
int gword;

extern int k_ldrr(), k_addrr(), k_ldimm(), k_nop();
extern int k_ldind(), k_stind(), k_ldda();
extern int k_sla1(), k_sla8(), k_sla8w1();
extern int k_mult1(), k_multff(), k_multl3(), k_multl5();
extern int k_div(), k_divl();
extern int k_ldir4(), k_ldir64();
extern int k_pushpop(), k_callret(), k_jrtaken();

struct akernel {
	char *name;
	int (*fn)();
	int per_iter;		/* copies of the instruction per iteration */
	char *note;
};

struct akernel akernels[] = {
	{"ldrr",    k_ldrr,    10, "LD R2,R1        40/iter"},
	{"addrr",   k_addrr,   10, "ADD R2,R1       50/iter"},
	{"ldimm",   k_ldimm,   10, "LD R1,#imm      80/iter (one extra fetched word)"},
	{"nop",     k_nop,     10, "NOP             80/iter"},
	{"ldind",   k_ldind,   10, "LD R2,@R4       80/iter (one data read)"},
	{"stind",   k_stind,   10, "LD @R4,R2       90/iter (one data write)"},
	{"ldda",    k_ldda,    10, "LD R2,addr      100/iter (two words + a read)"},

	/* The shift experiment: sla8w1 is the control both readings agree on,
	 * sla8 is the discriminator, sla1 the same question at n=1. */
	{"sla8w1",  k_sla8w1,  10, "SLA #8 + 1-word 410/iter under BOTH readings -- CONTROL"},
	{"sla8",    k_sla8,    10, "SLA #8 + 2-word 353 if the overlap is real, 380 if not"},
	{"sla1",    k_sla1,    10, "SLA #1 + 2-word 143 if the overlap is real, 170 if not"},

	/* Pairs.  Each pair runs identical code and differs only in an
	 * operand, so the board's overhead cancels in the difference. */
	{"mult1",   k_mult1,   10, "MULT x1         780/iter"},
	{"multff",  k_multff,  10, "MULT 0xFFFF     780/iter -- must EQUAL mult1"},
	{"multl3",  k_multl3,   5, "MULTL n=3       1595/iter"},
	{"multl5",  k_multl5,   5, "MULTL n=5       1665/iter -- multl5-multl3 must be 70"},
	{"ldir4",   k_ldir4,    1, "LDIR 4 words    82/iter"},
	{"ldir64",  k_ldir64,   1, "LDIR 64 words   622/iter -- ldir64-ldir4 must be 540 + waits"},

	{"div",     k_div,      5, "DIV RR2,R1      615/iter (107 each)"},
	{"divl",    k_divl,     3, "DIVL RQ0,RR4    2326/iter (744 each)"},
	{"pushpop", k_pushpop,  5, "PUSH+POP        95/iter"},
	{"callret", k_callret, 10, "CALL + RET      230/iter"},
	{"jrtaken", k_jrtaken, 10, "JR (taken)      70/iter"},
	{0, 0, 0, 0}
};

long
safe_x1000(cycles, ops) long cycles; long ops; {
	long q, r;

	while (ops > 2000000L) {
		ops = ops / 2;
		cycles = cycles / 2;
	}
	if (ops <= 0)
		return 0;
	q = cycles / ops;
	r = cycles % ops;
	return q * 1000L + (r * 1000L) / ops;
}

runone(k, cpt) struct akernel *k; long cpt; {
	long calls, t0, t1, ticks, best, iters, cyc;
	int run;

	calls = 1;
	for (;;) {
		t0 = tb_ticks();
		for (iters = 0; iters < calls; iters++)
			(*k->fn)();
		t1 = tb_ticks();
		ticks = t1 - t0;
		if (ticks >= TARGET_TICKS || calls >= MAX_CALLS)
			break;
		if (ticks <= 0)
			calls = calls * 8;
		else
			calls = (calls / ticks) * TARGET_TICKS
				+ ((calls % ticks) * TARGET_TICKS) / ticks
				+ 1;
		if (calls > MAX_CALLS)
			calls = MAX_CALLS;
	}

	best = -1;
	for (run = 0; run < RUNS; run++) {
		t0 = tb_ticks();
		for (iters = 0; iters < calls; iters++)
			(*k->fn)();
		t1 = tb_ticks();
		ticks = t1 - t0;
		if (best < 0 || ticks < best)
			best = ticks;
	}

	cyc = best * cpt;
	printf("RESULT_ASM %-8s calls=%-8ld ticks=%-6ld clocks_per_call=%-8ld clocks_per_iter_x1000=%-8ld  # %s\n",
	       k->name, calls, best,
	       safe_x1000(cyc, calls) / 1000L,
	       safe_x1000(cyc, calls * ITERS_PER_CALL),
	       k->note);
	fflush(stdout);
	return 0;
}

main()
{
	struct akernel *k;
	long cpt;
	int i;

	for (i = 0; i < 256; i++)
		buf[i] = i;
	bdst = &buf[0];
	bsrc = &buf[128];
	gword = 0x1234;

	printf("# k8000/bench/c900 -- assembly cycle-count kernels\n");
	printf("# clocks assume a %ld Hz Z8001; each call is %ld loop iterations\n",
	       TB_NOMINAL_CPU_HZ, ITERS_PER_CALL);
	printf("TICK_HZ %ld\n", tb_hz());
	cpt = tb_percall();
	printf("CLOCKS_PER_TICK %ld\n", cpt);
	if (cpt <= 0) {
		printf("# no usable clock -- see probe.c\n");
		return 1;
	}
	for (k = akernels; k->name; k++)
		runone(k, cpt);
	printf("# done.  Compare with ../expected/expected.txt.\n");
	return 0;
}
