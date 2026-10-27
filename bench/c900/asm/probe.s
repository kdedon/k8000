! probe.s -- step 3a.  Does the assembler take this file, and does the
! C compiler call it?  Ten lines, so that the syntax fight (if there is
! one) happens here and not inside kernels.s.
!
!	cc -o aprobe aprobe.c probe.s
!	./aprobe			--> expect "PROBE 12345"
!
! Three things are being checked at once:
!   1. the comment character, the directives and the operand syntax below
!      are the ones this assembler wants;
!   2. the C compiler's external-symbol decoration -- this file defines
!      BOTH _k_probe and k_probe, so it links whichever the compiler emits
!      (delete the one the assembler rejects as a duplicate);
!   3. the return-value register.  Zilog's C convention returns a word in
!      R7; if aprobe prints garbage, try R0 and R2 by editing the LD below
!      and say which one worked.

	.globl	_k_probe
	.globl	k_probe

	.text

_k_probe:
k_probe:
	ld	r7,#12345		! return value (R7 -- see note 3)
	ld	r0,r7
	ld	r2,r7
	ret
