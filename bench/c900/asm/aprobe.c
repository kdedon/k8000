/* aprobe.c -- companion to probe.s.  See probe.s. */
#include <stdio.h>

main()
{
	int v;

	v = k_probe();
	printf("PROBE %d\n", v);
	printf("PROBE_OK %d\n", v == 12345 ? 1 : 0);
	if (v != 12345)
		printf("# wrong return register, or the call did not reach the routine;\n"
		       "# edit probe.s (note 3) and report which register worked.\n");
	return 0;
}
