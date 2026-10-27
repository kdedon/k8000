/*
 * tb.c -- timing base.  See tb.h.
 *
 * Three clock sources are tried, most precise first:
 *
 *   TB_TIMES  times(2) -- process user+system time in HZ ticks.  This is
 *             the one we want: it excludes time the machine spent in other
 *             processes, so a busy system only lengthens the run, it does
 *             not corrupt the measurement.
 *   TB_FTIME  ftime(2) -- wall clock in milliseconds.
 *   (fallback) time(2) -- wall clock in whole seconds.
 *
 * Select with -DTB_TIMES (default), -DTB_FTIME or -DTB_TIME.  probe.c
 * reports which one works on the machine under test; if the default is
 * wrong, rebuild everything with the flag probe recommends.
 */

#include <stdio.h>
#include "tb.h"

#if !defined(TB_TIMES) && !defined(TB_FTIME) && !defined(TB_TIME)
#define TB_TIMES 1
#endif

#ifdef TB_TIMES
/* struct tms is declared locally so this file needs no system header that
 * a given Coherent release may or may not ship.  The V7/SysV layout is
 * four longs and has never varied. */
struct tb_tms {
	long tms_utime;
	long tms_stime;
	long tms_cutime;
	long tms_cstime;
};

long
tb_ticks()
{
	struct tb_tms t;

	t.tms_utime = 0;
	t.tms_stime = 0;
	times(&t);
	return t.tms_utime + t.tms_stime;
}
#endif

#ifdef TB_FTIME
struct tb_timeb {
	long time;
	unsigned short millitm;
	short timezone;
	short dstflag;
};

long
tb_ticks()
{
	struct tb_timeb tb;
	static long base = -1;

	ftime(&tb);
	if (base < 0)
		base = tb.time;
	return (tb.time - base) * 1000L + (long) tb.millitm;
}
#endif

#ifdef TB_TIME
long
tb_ticks()
{
	long t;
	static long base = -1;

	time(&t);
	if (base < 0)
		base = t;
	return t - base;
}
#endif

/*
 * tb_hz -- measure the tick rate against time(2).
 *
 * Nothing here assumes 100: the rate is derived by spinning until the wall
 * clock has advanced TB_HZ_SECONDS whole seconds and dividing the tick
 * delta by that.  The spin is a plain loop so it also proves the tick
 * counter advances at all.
 */
#define TB_HZ_SECONDS 3L

static long hz_cache = 0;

long
tb_hz()
{
	long t0, t1, w0, w1, k;

	if (hz_cache)
		return hz_cache;
	time(&w0);
	do
		time(&w1);
	while (w1 == w0);		/* align to a second boundary */
	t0 = tb_ticks();
	w0 = w1;
	k = 0;
	do {
		k++;			/* keep the CPU busy: times() counts CPU, not wall */
		time(&w1);
	} while (w1 - w0 < TB_HZ_SECONDS);
	t1 = tb_ticks();
	hz_cache = (t1 - t0) / TB_HZ_SECONDS;
	if (hz_cache <= 0)
		hz_cache = -1;
	return hz_cache;
}

/* tb_percall -- Z8001 clocks in one tick.  60000 on a 6 MHz / HZ=100 C900. */
long
tb_percall()
{
	long hz;

	hz = tb_hz();
	if (hz <= 0)
		return 0;
	return TB_NOMINAL_CPU_HZ / hz;
}
