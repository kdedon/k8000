/*
 * tb.h -- timing base for the C900 CPU performance tests.
 *
 * K&R C only: no prototypes, no void, no const, no // comments, no
 * long long, no floating point.  Coherent's cc (Mark Williams C) is the
 * target; it must also build with "gcc -std=gnu89 -w" on a modern host so
 * the suite can be dry-run before it is shipped.
 *
 * Everything is measured in CLOCK TICKS of the process CPU-time counter
 * (Coherent HZ == 100 on the C900: kernel timer = Z8036 CT, (PCLK/2)/30000
 * with PCLK 6 MHz -- see C900 planning/BOOT_TIMING_BASELINE.md).  The tick
 * rate is never assumed: tb_hz() measures it against time(2).
 */

#define TB_NOMINAL_CPU_HZ 6000000L	/* Z8001 on the C900 CPU board */

long tb_ticks();		/* process CPU time in ticks, -1 if unavailable */
long tb_hz();			/* measured ticks per second */
long tb_percall();		/* cycles per tick == CPU_HZ / HZ */
