# bench/c900 -- CPU performance tests for a REAL Commodore 900.
#
# Deliberately old-fashioned: explicit rules only, no pattern rules, no
# macros the Coherent make of 1985 will not understand.
#
#	make probe   && ./probe   > probe.out
#	make bench   && ./bench   > bench.out
#	make aprobe  && ./aprobe            (assembly tier: check it links)
#	make abench  && ./abench  > abench.out
#
# If probe reports TICKSRC BAD, add -DTB_FTIME (or -DTB_TIME) to CFLAGS
# and rebuild everything.

CC = cc
CFLAGS = -O

all: probe bench

probe: probe.c tb.c tb.h
	$(CC) $(CFLAGS) -o probe probe.c tb.c

bench: bench.c tb.c tb.h
	$(CC) $(CFLAGS) -o bench bench.c tb.c

# Keep the generated assembly: it is what turns a bench.out number into a
# statement about the CPU.  Send it back with the results.
bench.s: bench.c
	$(CC) $(CFLAGS) -S bench.c

aprobe: asm/aprobe.c asm/probe.s
	$(CC) $(CFLAGS) -o aprobe asm/aprobe.c asm/probe.s

abench: asm/adriver.c asm/kernels.s tb.c tb.h
	$(CC) $(CFLAGS) -I. -o abench asm/adriver.c tb.c asm/kernels.s

clean:
	rm -f probe bench aprobe abench *.o bench.s

# Maintainer-side only: prove the C still compiles on the development host
# before it is shipped to someone with the real machine.  gnu89 is the
# closest a modern compiler gets to Coherent's K&R cc.
dryrun:
	gcc -std=gnu89 -w -o /tmp/c900probe probe.c tb.c
	gcc -std=gnu89 -w -o /tmp/c900bench bench.c tb.c
	gcc -std=gnu89 -w -fsyntax-only asm/adriver.c -I.
	@echo "dryrun ok (the .s files are not checked -- no Z8000 assembler here)"
