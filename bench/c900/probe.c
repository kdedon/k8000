/*
 * probe.c -- step 1.  Two minutes on the real machine, before anything else.
 *
 * Answers the questions the rest of the suite depends on and cannot ask
 * itself: what size is an int, does the tick counter move, how many ticks
 * are in a second, and roughly how fast is this CPU.  Everything it prints
 * is one line of "KEY value" so the whole output can be pasted back.
 *
 *	cc -o probe probe.c tb.c
 *	./probe
 *
 * If TICKSRC comes back BAD, rebuild with -DTB_FTIME (then -DTB_TIME) and
 * run again; use the same flag for bench and adriver.
 */

#include <stdio.h>
#include "tb.h"

long sink;

main()
{
	long t0, t1, hz, i, n, ticks;

	printf("# C900 CPU performance probe -- k8000/bench/c900\n");
	printf("SIZEOF_INT %d\n", sizeof(int));
	printf("SIZEOF_LONG %d\n", sizeof(long));
	printf("SIZEOF_PTR %d\n", sizeof(char *));
	printf("CHAR_SIGNED %d\n", (int) ((char) 255) < 0 ? 1 : 0);

	/* Does the tick counter advance under a pure CPU load?  The load is
	 * doubled until it does, so a fast host running the dry-run does not
	 * report a false BAD. */
	n = 50000L;
	for (;;) {
		t0 = tb_ticks();
		for (i = 0; i < n; i++)
			sink += i;
		t1 = tb_ticks();
		if (t1 - t0 > 0 || n > 20000000L)
			break;
		n = n * 4;
	}
	printf("TICK_DELTA %ld  # after %ld iterations\n", t1 - t0, n);
	printf("TICKSRC %s\n", (t1 - t0) > 0 ? "OK" : "BAD");
	if ((t1 - t0) <= 0) {
		printf("# tick counter did not move -- rebuild with -DTB_FTIME\n");
		printf("# (and if that also fails, -DTB_TIME and expect coarse results)\n");
	}

	hz = tb_hz();
	printf("TICK_HZ %ld\n", hz);
	printf("CLOCKS_PER_TICK %ld  # assuming a %ld Hz Z8001\n",
	       tb_percall(), TB_NOMINAL_CPU_HZ);

	/*
	 * A crude absolute speed number: how many long adds per second.  Its
	 * only job is to prove the machine is not being timed while swapping
	 * or sharing the CPU -- run probe twice, the two must agree closely.
	 */
	n = 500000L;
	t0 = tb_ticks();
	for (i = 0; i < n; i++)
		sink += 3;
	t1 = tb_ticks();
	ticks = t1 - t0;
	printf("LONGADD_ITERS %ld\n", n);
	printf("LONGADD_TICKS %ld\n", ticks);
	if (ticks > 0 && hz > 0)
		printf("LONGADD_PER_SEC %ld\n", n / ticks * hz);
	printf("SINK %ld\n", sink);
	printf("# probe done -- paste the whole of the above into the results file\n");
	return 0;
}
