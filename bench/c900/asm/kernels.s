! kernels.s -- step 3b.  Per-instruction cycle-count kernels for the C900.
!
! Each routine runs KLOOPS (1000) iterations of a body holding TEN copies
! of the instruction under test, plus one DEC + one JR of loop control.
! It takes no arguments and returns nothing, so only the CALL/RET half of
! the C calling convention has to be right (probe.s proves that half), and
! every register it touches is saved and restored -- no assumption about
! which registers the compiler expects to survive a call.
!
! Predicted clocks per call are in ../expected/expected.txt, generated from
! the same Go golden model the k8000 RTL is verified against -- and it
! carries TWO predictions per kernel: the decode-ROM constant and what the
! model's CPU actually executes.  They agree for most of these kernels and
! differ for the bit-serial ones (MULT, DIV, shifts, block moves), where a
! static constant cannot describe an instruction whose cost depends on its
! operand.  Measure against the EXECUTED figure; the difference between the
! two columns is where hardware is most worth asking.
!
! ---------------------------------------------------------------------
! NONSEGMENTED FORM.  This file assumes Coherent runs user code in the
! Z8000 nonsegmented mode: 16-bit pointers, SP == R15, indirect == @Rn.
! probe.c settles it -- if it prints SIZEOF_PTR 4, user code is segmented
! and this file needs the segmented forms:
!
!	sed -e 's/@r15/@rr14/g' -e 's/@r4/@rr4/g' -e 's/@r6/@rr6/g' \
!	    -e 's/\bld\t\(r[0-9]*\),_b/ldl\trr\1,_b/' kernels.s > kseg.s
!
! and the pointer globals in adriver.c become 32-bit.  Say which form you
! used when you send the numbers back; the predictions differ.
!
! DATA SYMBOLS.  Three objects are defined in adriver.c and referenced
! here as _bsrc, _bdst and _gword.  If the link fails with "_bsrc
! undefined", this compiler does not decorate names -- strip the
! underscores from those three references:
!
!	sed -e 's/_bsrc/bsrc/' -e 's/_bdst/bdst/' -e 's/_gword/gword/' \
!	    kernels.s > k2.s
!
! SYNTAX.  Zilog standard mnemonics, '!' comments, '#' immediates, .globl
! and .text directives.  If the assembler objects, the fix is almost always
! mechanical (';' for '!', 'global' for '.globl').  Every instruction has
! its opcode words in the comment, so a disagreement can be checked by
! hand against the encoding rather than argued about.
! ---------------------------------------------------------------------

! Every entry point is defined twice, with and without the leading
! underscore, so the file links whichever decoration the C compiler emits.
! If the assembler rejects one of the two forms, delete that form.
	.globl	_k_ldrr, _k_addrr, _k_ldimm, _k_nop
	.globl	_k_ldind, _k_stind, _k_ldda, _k_sla1
	.globl	_k_sla8, _k_sla8w1, _k_mult1, _k_multff
	.globl	_k_multl3, _k_multl5, _k_div, _k_divl
	.globl	_k_ldir4, _k_ldir64, _k_pushpop, _k_callret
	.globl	_k_jrtaken, _k_neglc
	.globl	k_ldrr, k_addrr, k_ldimm, k_nop
	.globl	k_ldind, k_stind, k_ldda, k_sla1
	.globl	k_sla8, k_sla8w1, k_mult1, k_multff
	.globl	k_multl3, k_multl5, k_div, k_divl
	.globl	k_ldir4, k_ldir64, k_pushpop, k_callret
	.globl	k_jrtaken, k_neglc

	.text

! --------------------------------------------------------------- LD R2,R1
! A112, 3 clocks.  The floor: one word fetched, nothing else on the bus.
k_ldrr:
_k_ldrr:
	push	@r15,r1
	push	@r15,r2
	push	@r15,r6
	ld	r1,#1
	ld	r6,#1000
l_ldrr:
	ld	r2,r1		! A112
	ld	r2,r1
	ld	r2,r1
	ld	r2,r1
	ld	r2,r1
	ld	r2,r1
	ld	r2,r1
	ld	r2,r1
	ld	r2,r1
	ld	r2,r1
	dec	r6,#1		! AB60
	jr	nz,l_ldrr	! EExx
	pop	r6,@r15
	pop	r2,@r15
	pop	r1,@r15
	ret

! ------------------------------------------------------------- ADD R2,R1
! 8112, 4 clocks.
k_addrr:
_k_addrr:
	push	@r15,r1
	push	@r15,r2
	push	@r15,r6
	ld	r1,#1
	ld	r2,#0
	ld	r6,#1000
l_addrr:
	add	r2,r1		! 8112
	add	r2,r1
	add	r2,r1
	add	r2,r1
	add	r2,r1
	add	r2,r1
	add	r2,r1
	add	r2,r1
	add	r2,r1
	add	r2,r1
	dec	r6,#1
	jr	nz,l_addrr
	pop	r6,@r15
	pop	r2,@r15
	pop	r1,@r15
	ret

! -------------------------------------------------------- LD R1,#0x1234
! 2101 1234, 7 clocks.  Two words fetched: the second fetch is the delta
! against k_ldrr, so this pair alone gives the cost of an instruction word.
k_ldimm:
_k_ldimm:
	push	@r15,r1
	push	@r15,r6
	ld	r6,#1000
l_ldimm:
	ld	r1,#0x1234	! 2101 1234
	ld	r1,#0x1234
	ld	r1,#0x1234
	ld	r1,#0x1234
	ld	r1,#0x1234
	ld	r1,#0x1234
	ld	r1,#0x1234
	ld	r1,#0x1234
	ld	r1,#0x1234
	ld	r1,#0x1234
	dec	r6,#1
	jr	nz,l_ldimm
	pop	r6,@r15
	pop	r1,@r15
	ret

! ------------------------------------------------------------------- NOP
! 8D07, 7 clocks per the model.  A 7-clock instruction that touches no
! memory and no register: the cleanest test of the fetch path alone.
k_nop:
_k_nop:
	push	@r15,r6
	ld	r6,#1000
l_nop:
	nop			! 8D07
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	dec	r6,#1
	jr	nz,l_nop
	pop	r6,@r15
	ret

! ------------------------------------ NEG R2; LD R1,#0x1234; COM R2
! 8D22, 2101 1234, 8D20: 7 clocks each.  The LD follows NEG, whose
! internal clocks overlap the LD's first fetch.  Three trios per
! iteration: 73 clocks if the published figures are throughput, as the
! model reads them; 64 if a word fetched ahead were not billed again.
k_neglc:
_k_neglc:
	push	@r15,r1
	push	@r15,r2
	push	@r15,r6
	ld	r6,#1000
l_neglc:
	neg	r2		! 8D22
	ld	r1,#0x1234	! 2101 1234
	com	r2		! 8D20
	neg	r2
	ld	r1,#0x1234
	com	r2
	neg	r2
	ld	r1,#0x1234
	com	r2
	dec	r6,#1
	jr	nz,l_neglc
	pop	r6,@r15
	pop	r2,@r15
	pop	r1,@r15
	ret

! ------------------------------------------------------------ LD R2,@R4
! 2142, 7 clocks.  One instruction fetch + one data read: k_ldind minus
! k_ldrr is what a memory READ costs on this board, wait states included.
k_ldind:
_k_ldind:
	push	@r15,r2
	push	@r15,r4
	push	@r15,r6
	ld	r4,_bsrc
	ld	r6,#1000
l_ldind:
	ld	r2,@r4		! 2142
	ld	r2,@r4
	ld	r2,@r4
	ld	r2,@r4
	ld	r2,@r4
	ld	r2,@r4
	ld	r2,@r4
	ld	r2,@r4
	ld	r2,@r4
	ld	r2,@r4
	dec	r6,#1
	jr	nz,l_ldind
	pop	r6,@r15
	pop	r4,@r15
	pop	r2,@r15
	ret

! ------------------------------------------------------------ LD @R4,R2
! 2F42, 8 clocks.  Same, for a WRITE.
k_stind:
_k_stind:
	push	@r15,r2
	push	@r15,r4
	push	@r15,r6
	ld	r4,_bdst
	ld	r2,#0x55AA
	ld	r6,#1000
l_stind:
	ld	@r4,r2		! 2F42
	ld	@r4,r2
	ld	@r4,r2
	ld	@r4,r2
	ld	@r4,r2
	ld	@r4,r2
	ld	@r4,r2
	ld	@r4,r2
	ld	@r4,r2
	ld	@r4,r2
	dec	r6,#1
	jr	nz,l_stind
	pop	r6,@r15
	pop	r4,@r15
	pop	r2,@r15
	ret

! --------------------------------------------------------- LD R2,_gword
! 6102 addr, 9 clocks nonsegmented.  Direct address: three fetched words
! and one data read, versus the two-word indirect form above.
k_ldda:
_k_ldda:
	push	@r15,r2
	push	@r15,r6
	ld	r6,#1000
l_ldda:
	ld	r2,_gword	! 6102 <addr>
	ld	r2,_gword
	ld	r2,_gword
	ld	r2,_gword
	ld	r2,_gword
	ld	r2,_gword
	ld	r2,_gword
	ld	r2,_gword
	ld	r2,_gword
	ld	r2,_gword
	dec	r6,#1
	jr	nz,l_ldda
	pop	r6,@r15
	pop	r2,@r15
	ret

! ---------------------------------------------------------- SLA R1,#1/#8
! B319 0001 and B319 0008.  THE OPEN QUESTION, and it is a sharp one.
!
! Zilog publishes SLA as 13 + 3n -- the 1988 data book's ROTATE AND SHIFT
! table prints the formula in the cell, "(13 + 3 n)" -- so in isolation a
! shift by 1 costs 16 and a shift by 8 costs 37.  Our CPU produces exactly
! that when the instruction is timed alone.
!
! Back to back it produces 13 and 34.  The three missing clocks are the
! successor's second-word fetch hiding inside the shift's internal burn;
! static shifts are the only instructions that are BOTH multi-word and
! have a long internal phase, which is why nothing else in the suite shows
! the effect.  Whether that overlap is real silicon or an optimistic
! prefetch model is what this pair asks the hardware.
!
! Nine of the ten shifts in an iteration overlap; the tenth follows the
! loop's JR and finds the queue flushed, so it pays the full figure:
!
!   sla1   9x13 + 16 + 10 = 143 if the overlap is real, 170 if not
!   sla8   9x34 + 37 + 10 = 353 if the overlap is real, 380 if not
!
! A 27-clock discrimination on a 1000-iteration loop is 27,000 clocks --
! 4.5 ms of C900 time per call, far above the noise.
k_sla1:
_k_sla1:
	push	@r15,r1
	push	@r15,r6
	ld	r1,#1
	ld	r6,#1000
l_sla1:
	sla	r1,#1		! B319 0001
	sla	r1,#1
	sla	r1,#1
	sla	r1,#1
	sla	r1,#1
	sla	r1,#1
	sla	r1,#1
	sla	r1,#1
	sla	r1,#1
	sla	r1,#1
	dec	r6,#1
	jr	nz,l_sla1
	pop	r6,@r15
	pop	r1,@r15
	ret

k_sla8:
_k_sla8:
	push	@r15,r1
	push	@r15,r6
	ld	r1,#1
	ld	r6,#1000
l_sla8:
	sla	r1,#8		! B319 0008
	sla	r1,#8
	sla	r1,#8
	sla	r1,#8
	sla	r1,#8
	sla	r1,#8
	sla	r1,#8
	sla	r1,#8
	sla	r1,#8
	sla	r1,#8
	dec	r6,#1
	jr	nz,l_sla8
	pop	r6,@r15
	pop	r1,@r15
	ret

! -------------------------------------- SLA R1,#8 + a ONE-WORD successor
! THE CONTROL for the sla8 experiment, and the reason this pair can say
! WHY rather than just WHAT.
!
! The 3 clocks a shift appears to save are the successor's SECOND WORD
! being fetched while the shifter is still running.  A successor with no
! second word cannot supply one, so the saving must vanish.  Measured in
! the model, it does, exactly:
!
!	SLA #8 then SLA #8      (2-word successor)   34 + 34
!	SLA #8 then LD R2,R1    (1-word successor)   37 + 3
!
! So this kernel costs 10 x (37 + 3) + 10 = 410 clocks an iteration under
! BOTH theories -- the published isolated figure and our overlapping model
! agree here.  It is therefore a pure measurement of what the BOARD adds:
! whatever it reads above 410 is refresh and wait states for a stream of
! ten shifts and ten register moves.
!
! Then k_sla8 next door, same ten shifts but a two-word successor, reads
! 353 under our model and 380 under a flat reading.  Subtract this
! kernel's board overhead from that one and the answer is unambiguous.
k_sla8w1:
_k_sla8w1:
	push	@r15,r1
	push	@r15,r2
	push	@r15,r6
	ld	r1,#1
	ld	r6,#1000
l_sla8w1:
	sla	r1,#8		! B319 0008
	ld	r2,r1		! A112 -- ONE word: nothing to overlap
	sla	r1,#8
	ld	r2,r1
	sla	r1,#8
	ld	r2,r1
	sla	r1,#8
	ld	r2,r1
	sla	r1,#8
	ld	r2,r1
	sla	r1,#8
	ld	r2,r1
	sla	r1,#8
	ld	r2,r1
	sla	r1,#8
	ld	r2,r1
	sla	r1,#8
	ld	r2,r1
	sla	r1,#8
	ld	r2,r1
	dec	r6,#1
	jr	nz,l_sla8w1
	pop	r6,@r15
	pop	r2,@r15
	pop	r1,@r15
	ret

! ------------------------------------------------- MULT RR2,R1 (a PAIR)
! 9912, 70 clocks, FLAT -- Zilog gives no per-bit term for word MULT, and a
! spurious "+17n" was once a real bug in the Go model.  These two kernels
! are structurally identical: same instructions, same word counts, same
! number of bus cycles.  ONLY the operands differ -- 0x1234 x 1 against
! 0xFFFF x 0xFFFF, the emptiest and fullest multiplicands there are.
!
! So every board effect -- refresh, wait states, whatever the MMU adds --
! is common to both and cancels in the difference.  k_multff minus k_mult1
! must be ZERO.  Anything else is a per-bit term in the real silicon, and
! it would mean the model (and the RTL built from it) is wrong for every
! multiply an application does.
k_mult1:
_k_mult1:
	push	@r15,r1
	push	@r15,r2
	push	@r15,r3
	push	@r15,r6
	ld	r1,#0x0001	! multiplier: the emptiest possible
	ld	r2,#0x0000
	ld	r6,#1000
l_mult1:
	ld	r3,#0x1234	! 2103 1234
	mult	rr2,r1		! 9912
	ld	r3,#0x1234
	mult	rr2,r1
	ld	r3,#0x1234
	mult	rr2,r1
	ld	r3,#0x1234
	mult	rr2,r1
	ld	r3,#0x1234
	mult	rr2,r1
	ld	r3,#0x1234
	mult	rr2,r1
	ld	r3,#0x1234
	mult	rr2,r1
	ld	r3,#0x1234
	mult	rr2,r1
	ld	r3,#0x1234
	mult	rr2,r1
	ld	r3,#0x1234
	mult	rr2,r1
	dec	r6,#1
	jr	nz,l_mult1
	pop	r6,@r15
	pop	r3,@r15
	pop	r2,@r15
	pop	r1,@r15
	ret

k_multff:
_k_multff:
	push	@r15,r1
	push	@r15,r2
	push	@r15,r3
	push	@r15,r6
	ld	r1,#0xFFFF	! multiplier: every bit set
	ld	r2,#0x0000
	ld	r6,#1000
l_multff:
	ld	r3,#0xFFFF	! 2103 FFFF
	mult	rr2,r1		! 9912
	ld	r3,#0xFFFF
	mult	rr2,r1
	ld	r3,#0xFFFF
	mult	rr2,r1
	ld	r3,#0xFFFF
	mult	rr2,r1
	ld	r3,#0xFFFF
	mult	rr2,r1
	ld	r3,#0xFFFF
	mult	rr2,r1
	ld	r3,#0xFFFF
	mult	rr2,r1
	ld	r3,#0xFFFF
	mult	rr2,r1
	ld	r3,#0xFFFF
	mult	rr2,r1
	ld	r3,#0xFFFF
	mult	rr2,r1
	dec	r6,#1
	jr	nz,l_multff
	pop	r6,@r15
	pop	r3,@r15
	pop	r2,@r15
	pop	r1,@r15
	ret

! ------------------------------------------------ MULTL RQ0,RR4 (a PAIR)
! 9842.  Zilog gives MULTL as 282 + 7n, n = the number of set bits in the
! low 16 of the multiplicand (RefMan p.141-143).  A single measurement can
! only confirm one point on that line; a PAIR measures its SLOPE, and the
! slope is the part a structural model can get wrong.
!
! Multiplicand 0x0007 has three bits set, 0x001F has five.  The two kernels
! are otherwise identical, so board overhead cancels exactly:
!
!	k_multl5 - k_multl3 = 5 copies x 7 x (5-3) = 70 clocks per iteration
!
! 70,000 clocks per call, about 12 ms of C900 time.  If that difference
! comes back as 0 the cost is flat and the +7n is our invention; if it
! comes back as 70 the slope is real silicon.
k_multl3:
_k_multl3:
	push	@r15,r0
	push	@r15,r1
	push	@r15,r2
	push	@r15,r3
	push	@r15,r4
	push	@r15,r5
	push	@r15,r6
	ld	r4,#0x0000	! RR4 = 1, the multiplier
	ld	r5,#0x0001
	ld	r6,#1000
l_multl3:
	ld	r2,#0x0000	! multiplicand high
	ld	r3,#0x0007	! multiplicand low -- THE variable
	multl	rq0,rr4	! 9842
	ld	r2,#0x0000	! multiplicand high
	ld	r3,#0x0007	! multiplicand low -- THE variable
	multl	rq0,rr4	! 9842
	ld	r2,#0x0000	! multiplicand high
	ld	r3,#0x0007	! multiplicand low -- THE variable
	multl	rq0,rr4	! 9842
	ld	r2,#0x0000	! multiplicand high
	ld	r3,#0x0007	! multiplicand low -- THE variable
	multl	rq0,rr4	! 9842
	ld	r2,#0x0000	! multiplicand high
	ld	r3,#0x0007	! multiplicand low -- THE variable
	multl	rq0,rr4	! 9842
	dec	r6,#1
	jr	nz,l_multl3
	pop	r6,@r15
	pop	r5,@r15
	pop	r4,@r15
	pop	r3,@r15
	pop	r2,@r15
	pop	r1,@r15
	pop	r0,@r15
	ret

k_multl5:
_k_multl5:
	push	@r15,r0
	push	@r15,r1
	push	@r15,r2
	push	@r15,r3
	push	@r15,r4
	push	@r15,r5
	push	@r15,r6
	ld	r4,#0x0000	! RR4 = 1, the multiplier
	ld	r5,#0x0001
	ld	r6,#1000
l_multl5:
	ld	r2,#0x0000	! multiplicand high
	ld	r3,#0x001F	! multiplicand low -- THE variable
	multl	rq0,rr4	! 9842
	ld	r2,#0x0000	! multiplicand high
	ld	r3,#0x001F	! multiplicand low -- THE variable
	multl	rq0,rr4	! 9842
	ld	r2,#0x0000	! multiplicand high
	ld	r3,#0x001F	! multiplicand low -- THE variable
	multl	rq0,rr4	! 9842
	ld	r2,#0x0000	! multiplicand high
	ld	r3,#0x001F	! multiplicand low -- THE variable
	multl	rq0,rr4	! 9842
	ld	r2,#0x0000	! multiplicand high
	ld	r3,#0x001F	! multiplicand low -- THE variable
	multl	rq0,rr4	! 9842
	dec	r6,#1
	jr	nz,l_multl5
	pop	r6,@r15
	pop	r5,@r15
	pop	r4,@r15
	pop	r3,@r15
	pop	r2,@r15
	pop	r1,@r15
	pop	r0,@r15
	ret

! ------------------------------------------------------------ DIV RR2,R1
! 9B12.  Word DIV is 107 clocks -- the 1988 data book's ARITHMETIC table
! prints 107 for the R, IM and IR forms alike -- and the model executes
! 107.  The decode ROM used to carry 744 here, a stale copy of DIVL's
! figure; that was found while building this suite and has been fixed, and
! the cycle table gained DIV, MULT, MULTL, DIVL and block-move records at
! the same time.  The RTL reports all of them NOTRUN, so this kernel is
! still the first check of the figure against anything real.  The divider
! also has documented special cases (a zero divisor costs 13), so operands
! matter; this kernel fixes them.  The dividend is reloaded each pass; the
! divisor is 7 and the quotient always fits, so no overflow, no trap.
k_div:
_k_div:
	push	@r15,r1
	push	@r15,r2
	push	@r15,r3
	push	@r15,r6
	ld	r1,#0x0007
	ld	r6,#1000
l_div:
	clr	r2		! 8D28
	ld	r3,#0x1234	! 2103 1234
	div	rr2,r1		! 9B12
	clr	r2
	ld	r3,#0x1234
	div	rr2,r1
	clr	r2
	ld	r3,#0x1234
	div	rr2,r1
	clr	r2
	ld	r3,#0x1234
	div	rr2,r1
	clr	r2
	ld	r3,#0x1234
	div	rr2,r1
	dec	r6,#1
	jr	nz,l_div
	pop	r6,@r15
	pop	r3,@r15
	pop	r2,@r15
	pop	r1,@r15
	ret

! ---------------------------------------------------------- DIVL RQ0,RR4
! 9A42, 744 clocks: ROM and executed model agree.  64/32 -> 32.  RQ0 (R0..R3) is reloaded every
! pass with 0x0000000000012345 and RR4 holds 7, so the quotient always
! fits in RR2 -- no overflow, no trap, and identical work every time.
k_divl:
_k_divl:
	push	@r15,r0
	push	@r15,r1
	push	@r15,r2
	push	@r15,r3
	push	@r15,r4
	push	@r15,r5
	push	@r15,r6
	ld	r4,#0x0000	! RR4 = 7, the divisor
	ld	r5,#0x0007
	ld	r6,#1000
l_divl:
	clr	r0		! 8D08
	clr	r1		! 8D18
	ld	r2,#0x0001	! 2102 0001
	ld	r3,#0x2345	! 2103 2345
	divl	rq0,rr4		! 9A42
	clr	r0
	clr	r1
	ld	r2,#0x0001
	ld	r3,#0x2345
	divl	rq0,rr4
	clr	r0
	clr	r1
	ld	r2,#0x0001
	ld	r3,#0x2345
	divl	rq0,rr4
	dec	r6,#1
	jr	nz,l_divl
	pop	r6,@r15
	pop	r5,@r15
	pop	r4,@r15
	pop	r3,@r15
	pop	r2,@r15
	pop	r1,@r15
	pop	r0,@r15
	ret

! ------------------------------------------------- LDIR @R4,@R6,R3 (64w)
! BB61 0340.  One block move of 64 words per iteration.  The ROM carries
! 11 clocks -- that is ONE step, not a block -- so the number to extract is
! the per-word cost, (measured - the three loads and the loop control)/64.
! The model executes this loop in 622 clocks, i.e. about 9.2 clocks a word.
k_ldir64:
_k_ldir64:
	push	@r15,r3
	push	@r15,r4
	push	@r15,r6
	push	@r15,r7
	ld	r7,#1000
l_ldir64:
	ld	r4,_bdst
	ld	r6,_bsrc
	ld	r3,#64
	ldir	@r4,@r6,r3	! BB61 0340 (dst reg is word2 bits 7-4)
	dec	r7,#1
	jr	nz,l_ldir64
	pop	r7,@r15
	pop	r6,@r15
	pop	r4,@r15
	pop	r3,@r15
	ret

! ------------------------------------------------- LDIR @R4,@R6,R3 (4w)
! The slope partner for k_ldir64.  LDIR is 11 + 9n, so these two kernels
! differ by 9 x 60 = 540 clocks an iteration, and everything else about
! them -- instruction stream, register saves, loop control -- is identical.
!
! The difference is not quite as clean as the MULT and MULTL pairs, because
! the 64-word move really does perform 60 more reads and 60 more writes:
! on real hardware the gap is 540 PLUS 120 memory accesses' worth of wait
! states.  That is a feature.  k_ldind and k_stind measure the per-access
! penalty on their own, so this pair either agrees with them or says the
! block move's accesses are not ordinary ones.
k_ldir4:
_k_ldir4:
	push	@r15,r3
	push	@r15,r4
	push	@r15,r6
	push	@r15,r7
	ld	r7,#1000
l_ldir4:
	ld	r4,_bdst
	ld	r6,_bsrc
	ld	r3,#4
	ldir	@r4,@r6,r3	! BB61 0340
	dec	r7,#1
	jr	nz,l_ldir4
	pop	r7,@r15
	pop	r6,@r15
	pop	r4,@r15
	pop	r3,@r15
	ret

! ------------------------------------------------------ PUSH / POP pairs
! 93F2 / 97F2, 9 + 8 clocks claimed.  Stack traffic, and the only kernel
! that writes to the stack -- if a wait state applies to stack RAM only,
! this is where it shows.
k_pushpop:
_k_pushpop:
	push	@r15,r2
	push	@r15,r6
	ld	r2,#0x1234
	ld	r6,#1000
l_pushpop:
	push	@r15,r2		! 93F2
	pop	r2,@r15		! 97F2
	push	@r15,r2
	pop	r2,@r15
	push	@r15,r2
	pop	r2,@r15
	push	@r15,r2
	pop	r2,@r15
	push	@r15,r2
	pop	r2,@r15
	dec	r6,#1
	jr	nz,l_pushpop
	pop	r6,@r15
	pop	r2,@r15
	ret

! ------------------------------------------------------------- CALL/RET
! Ten calls to a bare RET.  The C-level call0 benchmark measures the
! compiler's prologue; this measures the instruction pair.
k_callret:
_k_callret:
	push	@r15,r6
	ld	r6,#1000
l_callret:
	call	l_leaf
	call	l_leaf
	call	l_leaf
	call	l_leaf
	call	l_leaf
	call	l_leaf
	call	l_leaf
	call	l_leaf
	call	l_leaf
	call	l_leaf
	dec	r6,#1
	jr	nz,l_callret
	pop	r6,@r15
	ret
l_leaf:
	ret

! ------------------------------------------------------- JR (always taken)
! Ten unconditional jumps to the next instruction: pure prefetch flush.
k_jrtaken:
_k_jrtaken:
	push	@r15,r6
	ld	r6,#1000
l_jrtaken:
	jr	j1
j1:	jr	j2
j2:	jr	j3
j3:	jr	j4
j4:	jr	j5
j5:	jr	j6
j6:	jr	j7
j7:	jr	j8
j8:	jr	j9
j9:	jr	j10
j10:	dec	r6,#1
	jr	nz,l_jrtaken
	pop	r6,@r15
	ret
