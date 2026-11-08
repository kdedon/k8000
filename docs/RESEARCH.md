# Research: per-clock timing of the Z8001/2 CPU

The manuals print totals (clock counts per instruction and addressing mode) and the bus-cycle shape. They do not print which clock does which step. This file records the readings reverse-engineered from the totals plus the operation, one family at a time: what each clock is taken to do, which routine it shares, what supports and what contradicts it, and whether the design adopted it. Choices already settled are in DECISIONS.md; they are pointed to by topic, not repeated.

Sources: TM = Z8000 CPU Technical Manual (Mar81, Jan83); Fawcett = the Z8000 book; DB = Zilog 1988 Data Book. Page cites are PDF pages, with printed numbers in brackets where the source gave them.

Confidence: **strong** (an identity holds across several modes or editions, or a manual states it); **plausible** (consistent with the totals and a shared routine, one or two independent supports); **guess** (fits the total, nothing else). Status: **adopted** (in the RTL and/or DECISIONS), **proposed** (a reading or small change not yet taken), **parked** (waiting for a C900 trace), **open** (no reading found).

## 0. Method and cost model

Notation: c1-c3 are the IF1's T1-T3; c4 is the first clock after it. `Fa`/`Fn` are an address/other instruction word fetch, `R`/`W` 3-clock memory cycles, `+k` the k-th tail clock, `Ik` an internal cycle of k clocks. NS/SS/SL are nonsegmented, short-segmented, long-segmented. Totals are NS unless stated.

Evidence that constrains every reading:

- One 16-bit internal bus and one ALU that does data and address work; no multiplier, divider or shifter block. Jan83 TM PDF p.20 (printed 2-1), block diagram; Fawcett PDF p.19 (printed 8), Fig 1.4.
- An internal operation is 3 clocks minimum, up to 8, shown T1 T2 T3. Jan83 TM PDF p.257 (printed 9-10), p.259 (9-12), Fig 9-7; Fawcett PDF p.77 (printed 66).
- Fawcett PDF p.78 (printed 67) narrates DIV R,R as a 5-clock IF1 then 6, 6, 7-clock internal cycles; this contradicts the 107 total and is not used.

The cost model the readings share (a clock is a micro-op, a labelled wait with its mechanism, or "no job found"; nothing is padding):

| micro-op | cost | anchor |
|---|---|---|
| XFER: one word over the bus into one destination | 1 | EX R,R 6 = 3 moves; LDL R,R 5 = 2 |
| PASS: one ALU op with its flags | 1 | ADD R,R 4; ADC/SBC/TCC/DAB R 5 = operand move + pass |
| T3 delivery: the read word into a latch or register, or one op taking the word off the bus | 0 | ADD/LD/CP IR 7 = IF1+1 and an R, nine families |
| Fast-group T3 move (R,R ALU, LD R,R, INC/DEC, BIT/SET/RES static, JR, CALR) | 0 | LD R,R 3, ADD R,R 4 |
| MERGE: long flags to the FCW, Z = Z_lo and Z_hi | 1 | ADDL minus LDL = 3 in R, IM, IR, DA, X |
| Rotate one bit | 1 | RL by 2 minus by 1 = 1, all eight rotates (Mar81 TM PDF p.171, printed 6-118) |
| BR: 2-way next address on a latched condition | 1 | DJNZ, shift position |
| Second-level dispatch on a w0[3:0] sub-op | 2 | section 6.1 |
| Segment decode of a short address word; shares a clock with an add | 1 | SS DA = NS DA + 1, SS X = NS X, SL = SS + 2 in every family |
| PARK: effective address into the MAR (destination routine) | 1 | section 6.3 |
| IM operand read through the source routine's pointer step, the PC as pointer | 1 | IM total = IR total: ALU 7, LD 7, LDL 11, ADDL 14, MULT 70, DIV 107 |
| Stack step (CALL, CALR, RET, IRET, trap): pointer on port A is the address (pop) or the adder gives SP minus k (push); the adder writes SP | 1 | CALL DA 12, X 13, IR 10, CALR 10; IRET 13 pops three words with one tail clock |
| Disabled step of a shared routine: its length, no effect | step | only with a shown identity (equal totals across forms) |

Address and PC rules:

- A1. A data cycle's address is the MAR. It loads by a move or pass naming it, by a stack step, or by the T3 bypass (the read word, only for a cycle requested in that T3). It holds until reloaded; a long's second word is MAR + 2 on the incrementer. LD DA 9 = IF1, Fa, R; INC DA 13 = Fa, R+1, W.
- A2. IF1, Fn and Fa take the PC on the fetch path: no clock, MAR untouched.
- A3. The IF1 is requested in the program's last clock from the PC as that clock opens; a conditional PC load must finish by then; a pop may hand the word to the IF1 by the bypass. JR 6, JP DA 7, RET 10.
- A4. A segmented address (PC, a register pair used as an address, the EA latch) moves segment and offset in one clock. IR forms SS = NS: LD/ADD/CP @RRs 7.
- A5. No op of the instruction's own data pass runs in a bus cycle's T1/T2 (CLR DA = IR + 3: the data stage needs its own clock). Scope: the operand's ALU passes only; pointer and count steps (section 5) are stack-class and do not violate it.

Totals for the instruction families are from Mar81 TM App. C, PDF p.276-284, unless another page is given.

## 1. Serial unit: MULT, MULTL, DIV, DIVL, shifts

Settled in DECISIONS (see "one serial unit", "multiply and divide" and "shift" rows; "case 3", "case 4", "internal cycles follow the unit"): one adder, one pair rotate, one operand latch, one count and cycle-end generator; the DIV frame order with a signed divisor; MULT/MULTL test the multiplier after the first loop decrement; case 3 as O joining the loop condition (22 / 48); the DIVL flags routine as MULT's finish routine; the unit starting on the IF1's T3 with an operand-not-in hold. Unit clock counts that reproduce every total: DIV 2 + 9 + 15 x 6 + 3 = 104, zero 10, case 3 22; MULT 2 + 16 x 4 + 1 = 67, zero 15; MULTL 4 + 32 x 8 + 19 = 279, zero 27; DIVL 4 + 21 + 33 x 21 + 21 + 2 = 741, zero 27, case 3 48. Totals: Jan83 TM PDF p.106-108 (printed 6-47 to 6-49; DIV 107, DIVL 744, Note 2 lower by 94/714 zero and 82/693 overflow), p.158 (printed 6-99; MULT 70/18, MULTL 282 + 7n / 30). The order inside the routines is not documented.

### 1.1 DIV's second loop-head clock (BR2)
- Reading: the second clock of a 2-clock call into the frame body. The frame is DEC, call (2), RLC, SUB, ADD: the unit's routine shape (call 2, three passes) with no return, because the body closes in line on the exit flag DEC latched. Frame 1's prologue (TEST, CP Rd1, CP Rd0) is itself a three-pass routine entered from the call's first clock.
- Reuse: the shape every DIVL routine (R1..R3, TRY, RST, SHF, FQ, FR), MULTL's add and Z/C routines and the pair flag routine already have: call 2, exactly three passes. DIV frame 6 = DIVL routine 7 minus the return 2 plus DEC 1.
- Corroborates: DIVL (every body three passes); MULTL's add routine (7n = call, ADD, ADC, latch, return).
- Counter-example: MULT (DEC + 1-clock BR + two inline passes) and the shift (DEC + BR + one rotate): inline bodies of fewer than three passes pay no call. Consistent, but the rule is read off two cases.
- Confidence: plausible. Status: proposed (comment and wording only; no logic change).

### 1.2 MULTL's second BR clock and DECIDE
- Reading: BR sub 1 is a half dispatch: frames 1-16 (bits of |s|, the add is a called routine) and 17-32 (bits of Ah + K, the add is the inline masked pass) are two bodies selected on the count's bit 4, one branch clock per decision. DECIDE tests r3 bit 0 into the condition latch: a call's next-address select needs its condition latched (DIV's TEST latches Z for CP Rd1's select); MULT needs no such clock because its ADD takes the bit as a pass mask. In frames 17-32 DECIDE's latch is unread (shared microword).
- Corroborates: DIV's TEST then CP Rd1; MULT's masked ADD. Counter-example: none found; the half dispatch is a naming, not a datapath (the RTL runs one body with a mask).
- Confidence: DECIDE plausible; BR sub 1 guess. Status: proposed (no logic).

### 1.3 MULTL's tail exit branch
- Reading: there is no tail branch on the normal path; its two clocks are LD r2,#0 and LD r3,#0 masked by Z at the finish routine's entry. One finish routine for both paths: call (2), LD r2 (Z), LD r3 (Z), Z routine (7), C routine (7), flags, ending in line. Normal 4 + 256 + 2 + 2 + 7 + 7 + 1 = 279; zero 4 + 3 + TEST + 2 + 2 + 7 + 7 + 1 = 27. Both paths spend 19 after their decision; today the zero path ends in line and the normal path pays an exit branch, an asymmetry with no support.
- Reuse: the masked pass (NEG by K, SBC by Z in DIVL's frame 0: a write gated by a latched flag, the clock paid either way).
- Corroborates: MULT zero (jump, clear, pair flags, ending in line); DIVL frame-0 un-negate masked by Z. Counter-example: MULT's normal path has no finish (67 = 2 + 65; flags come from the unit's finish routine on the zero path only), so MULT does not run a masked clear.
- Logic: the normal path's loop exit branches into the finish routine instead of the Z routine, the clears write only when Z, FLAGS ends in line; the finish's cycle end moves to the C routine's fifth clock (two states earlier), keeping the baseline /AS placement. Vectors unchanged.
- Confidence: plausible. Status: adopted (DECISIONS "one serial unit").

### 1.4 DIVL's unread CP in the pair flag routine
- Reading: a disabled step of a shared routine. MULT's zero finish and DIVL's flag routine are the same 7 clocks (call, CP hi against lo's sign, OR hi|lo, flags, return). The CP is MULT's C (product needs the upper half). DIVL's C is defined otherwise (Jan83 TM PDF p.106: C is V set with the quotient in the 33-bit range; case 4's stored sign is wrong), so DIVL reads only the OR (Z) and the flag pass. The unit's earlier version carried the same CP over from MULT with the routine.
- Rearrangements tried (a two-pass zero test, an explicit width compare, a two-step flag merge, three inline clocks) each only move the unused slot or recompute what is already known.
- Confidence: plausible. Status: adopted (see DECISIONS "DIVL ... flags routine").

### 1.5 DIV's CP Rd1 on the zero path
- Reading: the branch's select clock with a pass folded in. A pass latches a condition and the next microword's select takes it. TEST latches Z and Sd; CP Rd1 is that next microword and sends Z to the exit. On the normal path its pass latches low half < |D| (for the -2^16 exception); on the zero path the compare is unread but the clock is the select's. The DA/X holds pin TEST at clock 5 and the zero total pins the exit at clock 10 after TEST, a 2-clock jump and two restore passes: the select clock is the only free one.
- Confidence: strong (clock), plausible (name). Status: adopted (DECISIONS "MULT's TEST ... DIV's TEST").

### 1.6 DIV TEST versus MULT TEST (two costs)
- With "TEST decides" DIV zero would be 9; with "the next microword decides" MULT zero would be 16 (LD r1,#0 cannot be dropped: r1 still holds the multiplicand). No single rule gives both.
- Reading: DIV's TEST is the first pass of a called routine (the prologue), whose first pass cannot leave the routine; MULT's TEST is an inline microword and selects on its own Z. A routine is left from its call, its return, or a pass's select after the first; this fits DIV, DIVL (zero exit leaves from R3's return) and MULT.
- Confidence: guess. Status: proposed (replaces the "no one rule" sentence in DECISIONS).

### 1.7 Case 3 (past the width) and the -2^N boundary
- Case 3 is adopted as DECISIONS records ("case 3"). Evidence: Jan83 TM PDF p.106 (printed 6-47) case 3 text ("the destination register contains an undefined value", V set, C and Z cleared, S undefined) and case 2 ("remains unchanged"); p.108 (6-49) Note 2.
- Two things the manual does not settle:
  - Destination after case 3: whether the passes' partial words are stored (W1) or the destination is left alone (W2). The manual calls it undefined. Predicted under W1: `DIV RR0,R2` with RR0 = 0x00020000, R2 = 2 gives RR0 = 0x00020003; RR0 = 0xFFFE0000, R2 = 1 gives 0xFFFAFFFD; `DIVL RQ0,RR4` with RQ0 = 0x0000000200000000, RR4 = 2 gives RQ0 = 0x0000000000000001. Status: parked pending C900 trace.
  - The -2^N boundary: a single trial cannot tell a quotient of exactly -2^16 (-2^32) from case 3. The exact class is O = trial fits, unless the remainder is 0, the quotient negative and the low half < |D| (|D| x 2^N has no low bits). Test: `DIV RR0,R2` with RR0 = 0x00020001, R2 = 0xFFFE is case 4 (107, C = V = 1) by the manual, or 25 if the chip compares only the high half. Status: parked pending C900 trace.
- Assumption behind 22 and 48: an inline microword's next-address select is 2-way (DIV needs RLCQ to split O from count Z), a routine's return is multi-way (DIVL's SHF return goes three ways). Consistent with R3's existing conditional return; an assumption. Confidence: guess.

### 1.8 Operand wait and DIV order
- The unit starts on the IF1's T3 in every form; the first pass that reads the source holds until it is in. First source use: MULT TEST clock 5, DIV TEST clock 5, MULTL TEST clock 8, DIVL OR B_L,B_H clock 8. Operand arrival (program clock): IM 6 word / 9 long, IR 7 / 10, DA 9 / 12, X and SS 10 / 13, SL DA 12 / 15, SL X 13 / 16. Holds of 0 / 1 / 2 / 4 / 5 reproduce every DA/X/SS/SL total (MULT 71/72/74/75, DIV 108/109/111/112, MULTL 264/265, DIVL 745/746).
- With DIV's TEST on clock 6 every DA/X form comes out one clock short; this forced the signed-divisor order (|D| is never formed). Page 6-47..6-49 prints totals only. Status: adopted (DECISIONS "unit starts on the IF1's T3", "DIV: NEG Rd1 ...").
- Confidence: strong for the hold model (all forms reproduce), plausible for the reading of DIV's order.

### 1.9 Internal-cycle placement (/AS grid)
- The Go model's MD cycle strings were written for the register form and fitted to other forms by aligning to the end of the work. No uniform event (microword, 8-clock cap, T3) reproduces them in all forms. Loops of MULT, DIV, DIVL steady state and the shifts end their cycles at the unit's cycle-end microword (a routine call's second clock, the rotate of each frame, the shift clock); the packed stretches (MULT zero, MULTL finish and zero, DIV case 3, DIVL prologue and zero) keep the baseline placement and every clock inside is a named microword. Status: adopted (DECISIONS "internal cycles follow the unit"). Open: whether to move the packed stretches to the unit's grid (changes pins, not totals).

### 1.10 Where reuse explains clocks and area
Logic-reuse readings that keep every clock's name and total:

| item | reading | status |
|---|---|---|
| Two serial adders, two register sets, two operand captures, a third copy of the operand high word | one unit | adopted |
| Shifter as a third pair rotate with its own countdown | folded into the unit: DEC count, branch, rotate pair with fill, per I3; 13 + 3n and 15 + 3n (Mar81 TM PDF p.282) | adopted |
| DIV and DIVL negate routines per call site (entry, zero-exit restore, quotient, remainder) | one masked negate-pair body; the zero exit's 2-clock branch is a jump into the entry's microwords (zero total 10 = 6 + branch 2 + the same 2 passes) | adopted |
| Trial and restore, rotates, divisor negate, branch states | DIV's SUB/ADD are the high-word halves of DIVL's TRY/RST; one rotate with a pair select; one branch step with a target field | adopted where DECISIONS' "one serial unit" lists them; otherwise proposed |
| Flag routines across units | MULT's finish, DIVL's flags; MULTL's Z routine is the OR pass three times, its C routine a CP with a CPC: one compare/OR-a-pair body with a length field | proposed (MULTL's routines) |
| DIV overflow class as a 64-bit compare beside the passes | the class from the first trial pass (section 1.7); the chip has no 64-bit comparator | adopted |
| MULT flags recomputed in glue; MREQ private count; dynamic BIT/SET/RES mask; entry PSA add; second PC adder; LDM write index; duplicated condition evaluation | use the unit's latched flags; the step adder; the ALU's bit ops; two passes of the address adder; one PC adder; one counter; register the condition | adopted (no clock changes) |
| RL/RR/RLC/RRC by 2 as two cascaded rotates in one pass | one rotate per pass, the second position on the extra clock (6 for 1, 7 for 2) | proposed |
| EA adder, step adder, `addr + 2`, index + segment merged into the ALU | rejected: adds mux depth to the worst path | not recommended |
| Whole-unit in-place operation through the register file | chip-faithful (a divide always writes back; case 3's partial words natural) but sits on the worst path | parked; revisit if the register-file write gains slack |

### 1.11 Shift heads' last two clocks
See section 6.2 (the w0[3:0] head shared with LDM and EPU).

## 2. Stack, call and return

Settled in DECISIONS (see "stack cycle reads the pointer on port A", "taken branch loads the PC", "segmented CALL pushes", "memory-destination routine" including PUSH DA/X as counter-example). Steps from Mar81 TM PUSH (PDF p.165, printed 6-112), POP (p.163, 6-110), CALL (p.71, 6-18), RET (p.170, 6-117).

### 2.1 One routine for JP cc,@Rd, CALL @Rd and RET cc
- Reading: 1E JP cc,@Rd, 1F CALL @Rd and 9E RET cc are one routine: EA step, PC to MDR, EA to PC, stack step, one stack slot. NS totals 10 / 10 / 10 taken; JP and RET 7 not taken (the routine's first four clocks, writes off). For JP the push slot is a disabled step of CALL's.
- JP clocks (NS, from CALL IR): c4 X Rd to T; c5 PC to MDR (disabled in JP); c6 X T to PC (cc-gated); c7 stack step (disabled); c8-c10 the W slot (disabled); SS adds 5.
- RET clocks: c4 SP to MAR (the EA step, real: the pointer is SP); c5 PC to MDR idle; c6 EA to PC idle (RET's PC comes from the pop's T3 bypass, A3); c7 stack step (SP + 2, cc-gated); R. Segmented: RET 13 = 7 + R R (pops back to back, MAR + 2) against CALL 15 = 7 + W, +2, W (the segment word's MDR stage between pushes); the difference is the push's data stage, which a pop has not.
- Evidence: JP @Rd = CALL @Rd in every column, 10 / 15 / 15 (Mar81 TM PDF p.276, p.278; Jan83 TM PDF p.123: JP IR 10/7 NS, 15/7 segmented). Corroborates: not-taken 7 of JP @Rd and RET. Counter-example: none in NS.
- An earlier reading gave RET's c4-c5 a cc-dispatch; rejected because JP cc,@Rd, JP cc,DA and TCC pay nothing for theirs.
- Confidence: JP = CALL strong; RET as the same routine plausible. Status: proposed (naming); DECISIONS lists RET's first three clocks as no job found.

### 2.2 CALL, CALR, JP, JR
All fit with work only (no dispatch):

| form | NS / SS / SL | clocks |
|---|---|---|
| CALL IR | 10/15/15 | c4 X Rd to T; c5 PC to MDR; c6 T to PC; c7 stack step; W. SS: c4 RRd to T, c5 PC to MDR/seg latch (A4); +1 seg latch to MDR; +2 stack; W |
| CALL DA | 12/18/20 | Fa (word to T); +1 PC to MDR; +2 T to PC; +3 stack; W. SS: + segment decode. SL: Fn, Fa+3 |
| CALL X | 13/18/21 | Fa; +1 P word + Rx to T; then as DA |
| CALR | 10/15/15 | T3 PC to A (fast move); c4 PC to MDR; c5 disp to B; c6 P A - B to PC; c7 stack; W |
| JP DA | 7/8/10 | Fa: T3 word to PC (cc-gated); +1 IF1 request (A3) |
| JP X | 8/8/11 | Fa; +1 P word + Rx to PC; +2 request |
| JR | 6 | T3 PC to A; c4 disp to B; c5 P A + B to PC (cc-gated); c6 request |

Confidence: plausible-strong (E: multi-mode support). Status: adopted as the clocks the design already runs.

### 2.3 PUSH, POP
- PUSH R 9: c4 P Rd - 2 to Rd; c5 PARK Rd to MAR; c6 Rs to MDR; W. PUSH IM 12 adds the IM read (Fn, W from the data latch). PUSH IR 13: c5 PARK is the open clock; c6 X Rs to MAR; R; +1 PARK; W.
- Reading for c5 and the +1: keep the destination-routine reading (c5 = PARK, +1 = PARK). The DA/X counter-example (a push needing one clock more than the routine as written) is answered by A1/A2: for DA/X the pointer went to the MAR in c4 directly and is held through Fa and the operand read (those take the fetch path and the T3 bypass, or the index pass to T), so the W finds Rd - 2 still in the MAR. The PARK that DA/X lack is the one they never needed. Identity: PUSH R 9 = LD @Rd,Rs 8 + the decrement pass; PUSH IR 13 = that plus R and the re-park.
- Corroborates: POP DA/X use T for the second address; LD dst,R IR 8. Counter: PUSH X holds two address holders (MAR and T) at once.
- POP R 8: c4 Rs to MAR; c5 P Rs + 2; R. POP IR 12 and POP DA/X (16/16/18, 16/16/19) fit with work only. POPL R 12 = POP R 8 + R + 1; the +1 is the long IR/IM clock (section 3.5).
- Confidence: plausible. Status: DECISIONS prefers "open clocks over contradictions" for PUSH; this reading would close them; proposed (documentation only).

### 2.4 LDPS and IRET tails
See section 3.4.

## 3. Loads, LDA, LDM, LDPS, long forms

### 3.1 LDA DA/X = LDL R,src with idle word steps
- Reading: LDA DA/X runs LDL R,src's program with the two reads replaced by two internal word steps that deliver the address latch's segment word and offset word. Totals LDA DA 12/13/15, X 13/13/16 (Mar81 TM PDF p.279) equal LDL DA 12/13/15, X 13/13/16 (ADDL minus LDL = 3 in every column): six columns identical. Clocks: IF1, Fa (+1 X, +segment decode SS, +Fn SL), step 1 T1-T2 idle, T3 segment word to R(d) (NS: nothing, the "NS segment step" is idle by the same identity), step 2 T1-T2 idle, T3 offset to R(d+1) (NS: Rd). Pin-silent.
- Confidence: strong for DA/X. Status: proposed (naming; program F1+4 Fa+2 keeps its pins).
- LDA BA/BX/RA 15 = LDL BA 17 - 2 (LD BA 14, LDL BA 17). The based forms share the based EA routine (BA = BX = RA in LD 14, LDL 17, LDA 15 in every column); their I3 is the segment steps; the two-clock gap is open. Based routine clocks: Fn (displacement or index field); BX index move; RA PC to A; P A + B to T; I3: segment to latch, segment word to R(d), T to R(d+1). Confidence: guess for BA/BX/RA NS. Status: open.

### 3.2 LDA's 4-clock head
- The head (c4-c7) has no dispatch field (the 34/74/76 opcodes carry Rd in w0[3:0]), so the second-level dispatch criterion predicts no M8 and none is claimed. A call-and-return into a shared EA routine (2 + 2) would fill it but no form shows a return cost. Confidence: guess. Status: open (DECISIONS: "LDA's 4-clock head").

### 3.3 LDM head and loop
- Settled in DECISIONS ("LDM's address is formed once", head clocks, DA = IR + Fa). Evidence: LDM IR 11, DA 14/15/17, X 15/15/18, + 3n (Mar81 TM PDF p.280); EPU memory DA 14 + 3n, X 15 + 3n (Jan83 TM PDF p.233); wrap Mar81 TM PDF p.137 (6-84).
- Unexplained: c6-c7 after the two dispatch clocks (see 6.2).

### 3.4 LDPS and IRET
- LDPS IR 12/16/16: NS c4 Rs to MAR; R (FCW to hold); R (MAR + 2, PC word to hold); +1 hold to FCW (and the S/N swaps); +2 IF1 request after the FCW load. SS: c4 RRs to T; c5 P T + 2 to MAR (the reserved word, Mar81 TM PDF p.139, printed 6-86); R R R.
- Reading for the +2: the FCW load, then the IF1 request from the new N/S (A3), with the R15/NSP swap (LDCTL FCW's op) in the load clock. IRET (13 = IF1+1, R, R, R) needs no such clock because its FCW arrives a pop before the PC and the swap rides that pop. Confidence: plausible. Status: proposed; replaces an earlier note that the two readings conflict.
- DA/X head (two clocks): X holds the index in B (+ 2 segmented) per DECISIONS "LDPS ... X index"; DA segmented holds 2; the second clock and NS DA have no job. SL DA (Fn, Fa, R) has no clock for address + 2: either the +2 rides the incrementer (then the DA head clock has no job) or SL DA is a clock short. Confidence: guess. Status: open. A proposed fallback: c4 is the IR routine's pointer step, idle (DA = IR + Fa + 1, the LDM pattern).
- Totals: LDPS IR 12 (16 segmented), DA 16/20/22, X 17/20/23 (Mar81 TM PDF p.139 and p.280).

### 3.5 Long IR/IM +1 (LDL, ADDL, CPL IR and IM; POPL R; LDPS IR first word)
- Reading: P pointer + 2 to MAR, the second word's address on the ALU. A register pointer has no incrementer; a DA/X word's +2 rides the MAR incrementer (A1), which is why DA pays nothing. IM pays it because IM runs the IR routine. POPL R 12 = POP R 8 + R + 1: same clock.
- Counter: the chip would spend it between the reads, whereas the generator places it after the second read: same total, the second read's /AS one clock later. A pin move, so this needs a trace, not a naming.
- Confidence: plausible. Status: parked pending C900 trace of LDL @Rs.

### 3.6 Long ALU on registers
ADDL/SUBL/CPL R 8 = X lo to B; P lo; X hi to B; P hi (with carry); MERGE. Memory forms: R, R, then lo, hi, MERGE (+3). Strong (ADDL minus LDL = 3 in five modes). Status: adopted as named.

## 4. EPU

Settled in DECISIONS (EPU trap with EPA clear; CPU-EPU transfer has I/O timing, one automatic wait; EPU memory addressed as LDM; "The internal EPU operation takes 15 clocks").

### 4.1 EPU memory and registers
- Transfer-loop routine: head (two clocks dispatch on direction; two with no job), Fn (w1 count and register latches), pointer step (idle in DA/X: DA = IR + Fa exactly), n transfers. EPU memory totals equal LDM's per mode (14/15/17 + 3n and 15/15/18 + 3n, Jan83 TM PDF p.232-236). Registers 11 + 4n, flags 15 (Jan83); registers 11 + 3n, flags 14 (Mar81 TM PDF p.222-223).
- Confidence: plausible (equal totals across four forms). Status: adopted as the head; c6-c7 open.

### 4.2 EPU internal: the source edition
- Finding: both editions make the internal form the register form at n = 1. Mar81: internal 14 = registers 11 + 3n at n = 1 (Mar81 TM PDF p.223). Jan83: internal 11 + 4n (Jan83 TM PDF p.236, printed 6-175; also "treats this template as a No Op"), i.e. 15 at n = 1. What Jan83 revised is the EPU transfer slot, 3 to 4 clocks, across all EPU forms (registers 11 + 3n to 11 + 4n, flags 14 to 15).
- The ROM uses Jan83's flags 15 and a 4-clock EPU cycle, so its internal 14 is Mar81's count with a 3-clock slot inside a Jan83 program: a mix. Under the edition the ROM already follows internal should be 15, being the register routine with its EPU cycle off (pointer step, then one slot with no transaction). 14 also equals EPU memory IR at n = 1; that is two formulas meeting, not an identity.
- Confidence: strong (identity in both editions). Status: adopted (section 8).

## 5. Block, string and translate

Settled in DECISIONS (translate per byte; block I/O leaves Z unchanged; "block and translate element tables"). Block repeats save the start PC for an interrupt; "seven cycles should be added ... for each interrupt request that is accepted" (Mar81 TM PDF p.131, printed 6-78).

### 5.1 Exit `I4{BR+U}` (4 clocks)
| clock | micro-op | confidence |
|---|---|---|
| c1 | BR: the repeat decision latched in the element's last cycle leaves the loop | plausible |
| c2 | PC fix-up: the PC is already past the instruction's words from fetch and is stepped back only for a between-element interrupt, so at the exit this changes nothing | guess |
| c3 | interrupt sampling point (Jan83 TM PDF p.262: "sampled during the penultimate clock cycle of each instruction") and the element flag latches (V; Z/C/S for compares, TRT) to the FCW | plausible |
| c4 | IF1 request (A3) | plausible |

An earlier reading made c2 "PC + 4 to PC"; it contradicted the rule that the PC is stepped at fetch and was dropped. The interrupt path leaves before I4; single forms run the same exit. Status: adopted in DECISIONS' wording.

### 5.2 Element T1/T2 work (A5)
- Reading: the pointer and count steps in a write's T1/T2 are stack-class ops (the step adder writing a pointer register while a cycle runs). A5 was adopted for the instruction's data pass (CLR DA's data stage) and the stack forms already step their pointer inside a cycle. Scope A5 to ALU passes of the operand.
- Confidence: plausible. Status: proposed (documentation only).

## 6. Control, dispatch and the remaining forms

### 6.1 Second-level dispatch (2 clocks) and the criterion
- Criterion: w0[3:0] picks the operation inside one program exactly where every member has the same total although their work differs. Where members' totals differ each has its own program and nothing is paid. A cc field never pays.

| opcode | members | totals | dispatch paid |
|---|---|---|---|
| 8D (8C byte) | COM, NEG, TEST, TSET, CLR, SETFLG/RESFLG/COMFLG, NOP; 8C adds LDCTLB | all 7 | yes (nine members, one total; NOP = 8D x 7 does no work) |
| 7C | DI, EI | 7 | yes |
| 7D | LDCTL to/from 7 control registers | 7 | yes |
| B2/B3 rotates | RL RR RLC RRC with n | 6 / 7 | yes, plus n |
| B1 | EXTSB, EXTS, EXTSL | 11 | yes |
| 1C/5C LDM; 0E/4E/8E/8F EPU | load/store; direction, flags/internal | equal per mode | yes (head) |
| BD LDK vs 8D d8 CLR R | the same two steps | 5 vs 7 | the 2 is the dispatch |
| 94 LDL R,R; AD EX R,R | none | 5 / 6 | no, work only |
| 7B (IRET 13, MSET 5, MRES 5, MBIT 7, MREQ 12 + 7n), 0C/0D/4C/4D memory group, AF TCC, 5E JP cc,DA | differ | - | no |
| 39 LDPS IR | w0[3:0] fixed 0 | F1+1 | no, none needed |

- LDPS's 1-clock head against 7D LDCTL's paid dispatch refines the criterion: the floor follows the field, not the kind of work. The criterion predicts no dispatch for LDA and RET, and none is claimed.
- Evidence: totals, Mar81 TM App. C PDF p.276-284 (TEST printed "dst OR 0", p.283; NOP 7, p.280; MREQ 12 + 7n p.280). Confidence: strong for 8C/8D, 7C, 7D, B1-B3, LDM; not used elsewhere. Status: adopted (DECISIONS rows for DI/EI, flag ops, LDCTL, EXTS, LDM).

### 6.2 LDM/EPU c6-c7 and the shift heads' last two clocks
- Reading: the call (2) into the loop routine, after the w0[3:0] dispatch (c4-c5). Every instruction that dispatches on w0[3:0] then runs an n-loop has the same 4-clock head before its count word: LDM (1C/5C), EPU (0E/4E/8E/8F), SLA/SLL and SDA/SDL (B2/B3). Block instructions, whose sub-op is in w1, have no head (IF1, Fn+1). Where the loop is in the serial unit (shifts) the call is the unit's own. SLA is 13 + 3n for both widths, SDA 15 + 3n (Mar81 TM PDF p.282).
- Counter: a call framing was rejected elsewhere for want of a return cost; here the loop ends in line (an instruction-ending routine costs 0).
- Confidence: guess. Status: open (DECISIONS lists these as no job found).

### 6.3 Memory-destination routine and O2 clocks
- Settled in DECISIONS ("memory-destination forms ... one destination routine"). Evidence: TEST against BIT IR 8/8, DA 11/10, X 12/11 (Mar81 TM PDF p.283, p.276); CLR/stores DA = IR + 3 while loads DA = IR + 2; INC/SET/RES DA read-modify-write skip it (p.278, p.282, p.281); the data stage appears exactly in the writing members (COM IR 12 vs TEST IR 8; CP dst,IM has none, LD dst,IM has Fn+1). PUSH IM is 0D d9 (PDF p.165, printed 6-112).
- Unresolved COM/NEG constant stage: FFFF (COM as XOR) / 0 (NEG as 0 minus dst; App. C prints NEG as "dst <- 0 - dst") to B before the read pass. An ALU with NOT/negate functions would not need it. Confidence: guess (stage), plausible (constants). Status: adopted as the working reading.
- Possible RTL move: load the address latch in the first destination clock and request from it, taking the EA mux off the request path. Judge by fit; no pin change. Status: proposed.

### 6.4 DJNZ (11)
| clock | micro-op |
|---|---|
| c4 | X Rd to A (the slow path's explicit A-side move; the 1 is a constant on the B mux) |
| c5 | P Rd - B to the write latch; zero to the decision latch, FCW untouched |
| c6 | BR on zero |
| c7 | write latch to Rd |
| c8 | w0[6:0] (doubled by placement) to B |
| c9 | PC to A (not fast group; JR and CALR get this in T3) |
| c10 | P A - B to PC; zero path: disabled |
| c11 | IF1 request (A3) |

- One total on both paths (Mar81 TM PDF p.278). c4 is the one weak clock: the alternative label is the branch's second clock (the DIV/MULTL 2-clock branch reading; MULT and the shifts use 1). Counter-example to the A-side move: EXTS's sign test reads its register on the port with no move.
- Confidence: guess (c4), plausible (rest). Status: adopted (DECISIONS DJNZ row, "clock 4 no reasoned job"); c4 naming proposed.

### 6.5 Register and implied forms
All fit with work only; strong (several totals each): LD R,R 3; ADD R,R 4; ADC/DAB/TCC R 5; LDK 5; LDL R,R 5; EX R,R 6 (c4 Rd to write latch; c5 Rs to Rd; c6 latch to Rs); COM/NEG/TEST/TSET/CLR R 7 (dispatch 2, operand stage, pass); SETFLG/RESFLG/COMFLG, DI/EI, LDCTL, LDCTLB 7 (dispatch, operand to B or write latch, pass or write); NOP 7 (dispatch; c6-c7 the routine's operand stage and pass with writes off); RL/RR/RLC/RRC 6 / 7; RLDB/RRDB 9 (four 1-bit rotates c4-c7, digit merges c8, c9); EXTSB/EXTS/EXTSL 11 (dispatch; c6 sign test; c7 BR; c8 0 to B; c9 B or NOT B to the write latch; c10 latch to R(d); c11 latch to R(d+1) for EXTSL, disabled for EXTS/EXTSB); ADDL/SUBL/CPL R 8. LDCTL FCW,Rs: tails 3-4 move the source and write the destination or do the R15/NSP swap. Status: adopted.

### 6.6 TESTL R (13)
- Reading: TESTL R runs TESTL IR's routine (IF1+1, R, R+3) with its two reads as internal 3-clock steps delivering Rd's words on port A at each step's T3. Clocks: c4 pointer step (idle); c5-c7 first "read" (Rd high at c7); c8-c10 second (Rd low at c10); c11 lo pass, c12 hi pass, c13 MERGE.
- Evidence: TESTL R = TESTL IR = 13 (Mar81 TM App. C); the identity is structural: 9C (register) and 1C (IR) each carry TESTL as the lone d8 sub-op of a 1C/5C/9C column whose other members are LDM. Two other lone register sub-ops share the memory routine: JP @Rd = CALL @Rd (1E/1F, 10/15/15) and EPU internal = EPU registers at n = 1.
- Counter-example: no other register form equals its IR form (TEST 7/8, LDL 5/11, ADDL and CPL 8/14), so the equality is one total; TEST R (8D) is not a counter-example (8C/8D is a first-level register group with its own 7-clock program). A CPL R-shaped long test would take at most 5 clocks; nothing else in TESTL's operation fills 10.
- Confidence: plausible. Status: open in DECISIONS (7 of 13 clocks no job found); this reading proposed.

### 6.7 MREQ (12 + 7n)
- Mar81 TM PDF p.144-145 (printed 6-91, 6-92); Jan83 TM PDF p.154: the loop is "a finite delay to allow for propagation ... by repeatedly decrementing the destination until its value is zero"; "The original value of the counter must be greater than 2. Then the MI pin is tested." Variants: DB 12 + n; one text 10 + 7n; the ROM uses 12 + 7n.
- Clocks: c4 BR on /MI (sampled at the T3 edge) and on Rd = 0; c5 Z cleared, /MO Low if /MI High. Counting I7: c1 Rd - 1 to Rd (step adder); c2 zero to the decision latch; c3 BR; c4-c7 a labelled wait, the propagation delay the loop exists to make (the 3 + 4 split is a guess); final I7 runs the body at zero, the same delay, then c7: /MI sampled as it opens, S and Z to the FCW, /MO High if not granted.
- An earlier call-and-return framing (reusing DJNZ's decrement body) was dropped. Not checked in the model: the counter's original value must be greater than 2.
- Confidence: strong (purpose of the delay), guess (split). Status: adopted as a labelled wait; the manual's greater-than-2 condition is parked.

### 6.8 Dispatch cost and single-cycle forms summary
Per-clock tables for the remaining tails (heads, single internal-cycle register forms, the memory-destination forms, HALT) are in DECISIONS; HALT is documented (T1-T2 halted, T3 the interrupt sample).

## 7. Open questions

- DIVL case 3 and DIV case 3 destination: partial words stored or the destination left alone (section 1.7); and the exact -2^N boundary (same section). Both need the three C900 divides listed there.
- Whether the packed internal-cycle stretches (MULT zero, MULTL finish and zero, DIV case 3, DIVL prologue and zero) should move to the unit's own cycle grid; this changes pins and requires regenerating vectors.
- DIV BR2 and MULTL's second BR: accept the shared-routine readings (1.1, 1.2) or leave them tagged unexplained.
- DIV's TEST versus MULT's TEST costs (1.6): the structural rule is a guess from three cases.
- LDPS DA/X head clocks and SL DA's missing address + 2 clock (3.4).
- LDA's 4-clock head and the NS segment steps of the based forms (3.1, 3.2); LDA BA/BX/RA 15 against LDL BA 17 minus 2.
- Long IR/IM +1: pin placement relative to the two reads (3.5).
- LDM/EPU/shift head c6-c7 (6.2); DJNZ c4 (6.4); RET c4-c6 (2.1); PUSH IR c5 and +1 (2.3); TESTL R's 7 clocks (6.6); MREQ's 3 + 4 split (6.7).
- Block exit c2 (PC fix-up changes nothing at the exit) (5.1).
- SCC CRC cut by Tx Enable: which flag or sync bit fills each remaining CRC bit time (taken as bit j of the pattern repeated, slot j kept), whether re-enabling mid-CRC resumes the CRC, and whether /CTS under Auto Enables cuts it too (DECISIONS). A C900 trace with WR5 D3 cleared mid-CRC settles the first.
- SCC SDLC Loop: whether a run of 1s already past seven when Go Active On Poll is set puts the channel on loop; how FM is repeated; what RR10 D4 and D1 mean outside Loop mode (UM010902 p.185 says both "can be polled in SDLC mode to determine when the closing flag has been sent"; both read 0 here).
- The C900 trace targets that would settle most of the above: `LDL @Rs` (3.5), the three divides (1.7), an EPU internal instruction (4.2).

## 8. Decisions

- EPU internal: 15 clocks (Jan83, 11 + 4n at n = 1, 4-clock slot), replacing Mar81's 14. Adopted 2026-11-01: the program is `F1+4 Fn+1 I4`, the slot an internal cycle.

## 9. Z8070 FPU

The Z8070 was published only as a Preliminary Product Specification (no pinout, package or AC table) and a software emulation package. Where the spec is silent the readings below say so; nothing here is adopted yet.

Sources: DB85 = Zilog 1985 Data Book, Z8070 FPU Preliminary Product Specification, April 1985, PDF p.540-567 (printed 531-558), and the Z8070 Floating-Point Emulation Package, PDF p.1012-1019 (printed 1003-1010); DB82 = Zilog 1982 Data Book, emulation product brief, PDF p.322-323 (printed 311-312); TM = Jan83 CPU Technical Manual; Fawcett PDF = printed + 11. The 1988 Data Book has no Z8070 pages; its EPA overview (PDF p.20) adds nothing. Period software, used only where the PDFs are silent: the CP/M-8000 Z8000 assembler's predefinition table (`asz8k.pd`), the CP/M-8000 floating-point emulator source (`FPE.Z8K`, change log 1980-1982) and the assembled CP/M-8000 `startup.o`. Tags: **explicit** (a PDF states it), **software** (period software shows it), **interpretation**, **guess**.

### 9.1 Pins (Z8000 interface)

| pin | dir | function | source |
|---|---|---|---|
| AD15-AD0 | bidir, 3-state | snooped; driven for EPU-to-memory and EPU-to-CPU words | DB85 PDF p.553 (printed 544) |
| /AS, /DS, R/W, B/W, N/S | in | bus strobes and status; /AS rise marks status valid | PDF p.554 (545) |
| ST3-ST0 | in | 0101/0110/0111 acknowledges, 1010/1011 EPU-memory, 1100 IF after first word, 1101 IF1, 1110 CPU-EPU | PDF p.554 |
| SN6-SN0 | in | segment number (Z8001/Z8003) | PDF p.554 |
| /BUSACK | in | Low: ignore the bus | PDF p.554; Fawcett PDF p.197 (186) |
| /ABORT | in | aborts the current instruction (Z8001/Z8003) | PDF p.553 |
| /BSY | out | wired to the CPU's STOP (Fig 14) and, assumed, its /WAIT (p.551 store wait) | PDF p.551 (542), p.555, Fig 14 PDF p.553 |
| /INT | out, open drain | to /NMI, /NVI or /VI | PDF p.551, p.552 (543) |
| IEI, IEO | in, out | daisy chain | PDF p.551 |
| ID1-ID0 | in | EPU ID, latched at reset into SC | PDF p.551 |
| OPT1-OPT0 | in | interface at reset; 11 = Z8000 | PDF p.551 |
| /RESET | in | power-on state; USER, FFLAGS, SC cleared but SC.ID | PDF p.551 |
| CLK.I | in | Interface Processor clock; for the Z8000 it is the CPU's clock (Fig 14: "from clock generator", to both) | PDF p.551, p.553; Z80,000 text PDF p.563 (554): synchronous with the CPU clock, minimal skew |
| CLK.D | in | Data Processor clock; may be asynchronous | PDF p.551, p.563 |

Fig 14 shows no /WAIT, /MREQ or /CS on the Z8070 in a Z8000 system. CE, RD, WR, A0, D31-D0, SIP and WAIT belong to the Universal interface only (PDF p.564).

Clock pins in k8000 terms (interpretation): CLK.I is a rise and a fall pulse, like the CPU's CLK, because the spec has the EPU take memory data "before the falling edge of the clock in the middle of T3" (PDF p.555, printed 546); CLK.D is a rise pulse.

### 9.2 Bus protocol

- IF1 snoop: every EPU and the CPU latch the word fetched with ST 1101; first byte 0E, 0F, 4E, 4F, 8E or 8F is extended; bits 1:0 are the ID (PDF p.554, printed 545; TM PDF p.260, printed 9-13). Explicit.
- Word 2: the next non-refresh transaction, ST 1100, captured by the EPU whose ID matches (PDF p.554; TM PDF p.260). Explicit.
- Memory transfers (0F/4F): after any address-word fetches, the next 1 to 16 non-refresh transactions are 1010 (data) or 1011 (stack), word only; the CPU 3-states AD while /DS is Low (PDF p.555, Fig 16 PDF p.556; TM PDF p.260-261; Fawcett PDF p.196). For a write the Z8070 "places the data on the bus when AS rises" (PDF p.555): explicit, but it overlaps the CPU's address drive before /DS; Fig 16 draws "FPU DATA OUT" after the address. Interpretation: drive from the /DS fall, as the CPU's own write data.
- CPU transfers (8F, 8E flag forms): 1 to 16 addressless 1110 transactions, I/O timing with TWA (Fig 17, PDF p.557, printed 548). Fawcett PDF p.197 (186) says "identical to a three-clock-cycle memory access"; the CPU side already follows the TWA reading (DECISIONS).
- Flag transfers: one byte on AD7-AD0; the CPU's R0 is undefined after FCW <- EPU (TM PDF p.235, printed 6-174; Fawcett PDF p.197).
- /BSY drives STOP, which the CPU samples on the fall before an IF1 and, with EPA set, on the fall before an extended instruction's word 2 (TM PDF p.262, printed 9-15). The spec is inconsistent on stores: PDF p.551 says /BSY "is used by the Z8070 as a Wait signal during stores" and PDF p.555 that the transfer "times can be extended by activating the CPU's WAIT line", but Fig 14 (PDF p.553) wires /BSY to STOP only. STOP alone cannot cover a store: the conversion needs word 2's operation and register, and the data cycles follow word 2 at once. Assumed: the system also wires /BSY to /WAIT, and /BSY is Low from a store's data cycle until its word is ready, in both overlap modes.
- Overlap: Z8000 systems use No Overlap or Intermediate (PDF p.554). No Overlap stops the CPU whenever the FPU is processing; Intermediate lets the CPU run during an operation and stops it after a second FPU instruction is transferred (PDF p.544, printed 535). Exactly which STOP sample (IF1 or word 2) asserts in each mode: interpretation.
- Interrupts: SC.INTACK selects the acknowledge type (0X NMI, 10 NVI, 11 VI); vector from SC bits 7:0, SV shifts it left, NV 3-states the lines, VIS adds status (format not given), DLC blocks lower devices (PDF p.543, printed 534). IEO: High only if IEI is High and the CPU is not servicing a Z8070 interrupt and none is requested, during INTACK (PDF p.551). Vector drive and IUS set: the Universal-interface text (PDF p.565, printed 556) describes it; the Z8000 timing is the standard Z-BUS acknowledge (interpretation).
- Exception flush: any instruction transferred or being transferred is flushed (PDF p.567, printed 558).
- Reset: registers 0 but SC.ID (PDF p.551).

### 9.3 Registers and formats

All explicit from DB85 PDF p.541-544 (printed 532-535) and Fig 11-13 (PDF p.546-547).

- F0-F7: 80-bit extended (sign, 15-bit exponent bias 16383, explicit integer bit, 63-bit fraction).
- PC1 (executing or control instruction's address), PC2 (queued instruction's), 32-bit, read only. The Z8070 must take them from the IF1 address (interpretation; Z8000 sends no PC).
- FFLAGS: 7:0 sticky INV FOV UN DZ INX DE NAN IX; 15:8 previous-operation, same order; 17:16 zero; 23:18 FC FZ FS FV FD FH; 25:24 FOP2E; 27:26 FOP1E; 28 R (rounded up); 31:29 invalid-op code (8 reasons listed).
- Compare results (Table 1): < sets FC FS FD; = sets FZ; > sets FD; unordered sets FV. FH is not in the table.
- FC FZ FS FV FD FH correspond to the FCW's C Z S P/V D H (DB85 PDF p.1013, printed 1004), so FFLAGS 23:18 is FCW 7:2 bit for bit. The condition-code table (PDF p.1019, printed 1010) agrees: FLT = ULT (C), FLU = LT (S xor V), FGU = UGT, FUN = OV.
- SC: 7:0 vector; 8 zero; 9 SV; 10 VIS; 11 NV; 12 DLC; 13 IUS; 14 IP; 15 MIE; 17:16 INTACK; 19:18 OVRLP (00 none, 01 reserved, 10 intermediate, 11 maximum, not for Z8000); 20 AC (synchronize when CLK.I and CLK.D differ); 21 F; 22 RPC; 23 U; 25:24 IR (00 arithmetic, 01 invalid opcode, 10 invalid EPU ID, 11 privilege); 27:26 ID (read only); 31:28 EPUIDS (an ID whose bit is 1 raises Invalid EPU ID). Privileged in systems with System/Normal.
- USER: 1:0 RM (nearest, zero, +inf, -inf); 15:8 trap enables, sticky order; bit 6 printed "J", not described; 31:16 undefined.
- FOP1 (input operand), FOP2 (default result), read only, 80-bit with the exponent's two MSBs in FFLAGS.
- Formats: single, double, extended binary; 32- and 64-bit two's-complement integers; BCD integer, sign and up to 19 digits in 80 bits.

### 9.4 Instruction set and encoding

Mnemonics, operands and operations: DB85 PDF p.548-551 (printed 539-542); the emulation package repeats them with operand forms R, RR, RQ, IR, DA, X and multiple-register FF (PDF p.1016-1018). Neither PDF gives word-2 encodings. The emulation package names a "Z8070 APU Technical Manual" (03-8226-01, PDF p.1005, printed 996), not on disk.

Template frame, explicit (TM PDF p.232-236, printed 6-171 to 6-175):

| w0 | template | word 2 the CPU reads | CPU clocks |
|---|---|---|---|
| 0F/4F, bits 3:2 = 11 | memory <- EPU, IR/DA/X | 3:0 n-1 | 11 + 3n IR |
| 0F/4F, bits 3:2 = 01 | EPU <- memory | 3:0 n-1 | 11 + 3n IR |
| 8F, bit 7 = 0, bits 3:2 = 00 | CPU <- EPU | 11:8 Rd, 3:0 n-1 | 11 + 4n |
| 8F, bit 7 = 0, bits 3:2 = 10 | EPU <- CPU | 11:8 Rs, 3:0 n-1 | 11 + 4n |
| 8E, bits 3:2 = 00 | FCW <- EPU | 11:8 and 3:0 printed 0000 | 15 |
| 8E, bits 3:2 = 10 | EPU <- FCW | 11:8 and 3:0 printed 0000 | 15 |
| 8E, bits 3:2 = 01 | internal | 3:0 n-1 | 11 + 4n |

0E and 4E have no template. TM PDF p.235 prints the segmented FCW <- EPU w0 as 10 001111, the nonsegmented as 10 001110: a misprint by the other six.

Operation field, software (the assembler table and the emulator decoder agree; the assembled CP/M-8000 startup bytes `8F58 C000` = FLDCTL USER,R0, `8F48 C001` = FLDCTL FFLAGS,RR0, `8F08 8021` ... `8F78 8021` = FLDIL F0..F7,RR0 decode by it):

- Operation code: 6 bits, {w2[15:14], w2[7:4]}.
- w2[13:12]: rounding precision (the `rnd` suffix).
- w2[3:0]: n-1, which also gives the source format: 1 single (or int32), 3 double (or int64), 4 extended (or BCD); 0 for internal ops.
- F registers: internal forms, destination in w0[7:4], source in w2[11:8]; CPU forms, F in w0[6:4], CPU register in w2[11:8]; memory forms, F in w2[11:8].
- Control register select for FLDCTL in w0[7:4]: SC 0, PC1 1, PC2 2, FFLAGS 4, USER 5, FOP1 6, FOP2 7.
- "Transfer flags to CPU" is the FCW <- EPU template (8E00) on the plain operation: FCPF = FCP's code, FREMSTEP = FREMSNF's.
- FSETFLG/FRESFLG/FSETTRAP/FRESTRAP: w2 bit 4 set or reset; w0 bit 5 selects the USER trap enables, w0 bit 4 the compare byte, neither the sticky flags. Where the 8-bit list sits is unclear: the emulator builds it from w2[15:8], whose top bits are the operation code.

| code | op | code | op | code | op |
|---|---|---|---|---|---|
| 00 | FCLR | 18 | FADD | 28 | FABS |
| 01 | FCPZ | 19 | FSUB | 29 | FNEG |
| 02 | FCPZX | 1A | FDIV | 2B | FPWR2 |
| 09 | FRVSUB | 1B | FMUL | 2C | FSQR |
| 0A | FRDIV | 1C | FREMSNF / FREMSTEP | 2D | FINT |
| 11 | FCP | 20 | FLD | 30 | FLDCTL |
| 12 | FCPX | 21 | FLDBCD | 31 | FLDCTLB |
| | | 22 | FLDIL / FLDIQ (by n) | 32 | FRESFLG / FRESTRAP |
| | | 23 | FLDM / FLDNF | 33 | FSETFLG / FSETTRAP |
| | | 24 | FLDTL / FLDTQ (by n) | 34 | FSETMODE |

The emulator also decodes 3F (FSTP, no datasheet mnemonic). FCPZNF and FCPZXNF have no row; FLDNF shares FLDM's. Internal forms are assembled with w2[3:0] = 0, so the CPU's 11 + 4n is 15 for them, as the k8000 CPU runs (section 8).

### 9.5 Timing

- Published (DB85 PDF p.541, printed 532), "Number of Cycles" (the clock is not named; the Data Processor has its own, so CLK.D is the reading): add/subtract 18/18/18, multiply 28/42/48, divide 29/43/49 for single/double/extended; 1 cycle = 40 ns at 25 MHz. Speed grades 10-25 MHz (PDF p.540). Single multiply "under three microseconds" at 10 MHz.
- Readings (interpretation): add constant across precisions implies single-pass alignment and normalization; multiply 16 + n/2 for n = 24, 52 (the hidden bit known), 64 is 2 bits per clock, matching the "multiplier array"; divide = multiply + 1 with the "quotient predictor" is radix-4 SRT on the same datapath.
- No figure for square root, remainder, compare, conversions, BCD, control or the Interface Processor. The emulator: "most operations finish in under one millisecond on a 6 MHz CPU" (PDF p.1012).
- No AC table. EPU bus timing follows the CPU's transactions (Fig 16, 17).

### 9.6 Architecture

Explicit (PDF p.541, printed 532): two processors with separate clocks. The Interface Processor fetches and aligns instructions and data, keeps the instruction queue, runs control and data-movement instructions without the Data Processor, watches status for templates. The Data Processor holds the eight data registers, multiplier array, ALU, accumulator, shifter, quotient predictor and temporaries. Internal format 80 bits. Datapath width and microcode are not stated.

### 9.7 Open questions

| question | gap |
|---|---|
| Word-2 operation field | No Zilog PDF; software only (9.4) |
| Store data drive edge (/AS rise or /DS fall) | PDF p.555 text against Fig 16 and the CPU's write timing |
| Which STOP sample /BSY asserts for, per overlap mode | PDF p.544 describes intent only |
| Clocks for every op but add, multiply, divide; Interface Processor latency | none published |
| VIS status format; USER bit 6 "J" | not described |
| PC1/PC2 capture point (IF1 address, segment) | not described for the Z8000 interface |
| Vector drive edge in a Z8000 acknowledge | only the Universal-interface timing is drawn |
| FCPZNF/FCPZXNF and FLDNF encodings; code 3F; the flag-list field | no software row; the emulator's list decode overlaps the operation code |
| Invalid EPU ID: raised only for another EPU's ID whose EPUIDS bit is set, not this EPU's own | PDF p.543 silent |

### 9.8 Patent US 4,648,034 (EPU busy interface)

Heninger (Zilog), filed 1984-08-27, granted 1987-03-03. PAT = its PDF page. It names the Z80,000 CPU and the Z8070 as the commercial embodiment and cites a September 1983 "Z8070 Z-APU" Preliminary Product Specification (PAT p.15, col 1-2). The CPU side is the Z80,000: 32-bit bus, opcode and PC in one transaction, an EPUO bit in its hardware interface control register. What carries over to the Z8000 bus is the EPU's queue and /BSY logic; the transactions do not.

- Queue (explicit, FIG. 6 PAT p.9; col 14 PAT p.21): two queuing registers, each a 32-bit instruction, 80-bit data, 32-bit logical PC and a valid bit (V1, V2); "could be a different number". The Data Processor takes the oldest with its data, freeing that register; with the queue empty an instruction goes straight to the Data Processor. Interpretation: per-entry PCs are PC1/PC2; the Z8000 sends no PC, so the IF1-address capture stays an interpretation.
- /BSY (explicit, FIG. 7 PAT p.9; col 14-15 PAT p.21-22): OR of three ANDs. OVRLP 00: DP busy. 10: V1 set ("one instruction and its data are stored in a first of the queuing registers"). 11: V2 set (queue full). A decoded EPU store forces the DP-busy term in every mode, so /BSY "is generated until that instruction has been executed, at which time the resulting data is available for storing". 01 is not decoded.
- Store (explicit, FIG. 11 steps 444-449 PAT p.10-11; col 16-17 PAT p.22-23): valid bit set and /BSY asserted at once on receipt, held while the DP is busy, released, then the data is driven (467). The Z80,000 tests /BSY before each transfer path (451-457), not as a bus wait. Supports the store-wait extent (Low until the word is ready, both modes); the Z8000 /WAIT wiring remains the DB85 p.551/555 reading.
- Modes (explicit, table col 18 PAT p.23): No Overlap 00 + EPUO 0; Simple 00 + EPUO 1; Intermediate 10 + EPUO 0, "executing an instruction and has another instruction in its queue, then the CPU waits"; Maximum 11 + EPUO 1. Interpretation: the Z8000 samples STOP at every IF1, i.e. EPUO 0, which is why DB85 allows only No Overlap and Intermediate. Supports a one-deep queue for Intermediate, with /BSY rising once the queued instruction and its data are in (steps 433, 444, 466), not at its IF1.
- SC (explicit, FIG. 8 PAT p.9): every field and bit position as DB85 (9.3), OVRLP at 19:18.
- Interface control 335: "preferably constructed of a programmable logic array" stepping the interface (col 14 PAT p.21). FIG. 9: word 1 bits 1:0 ID, word 2 bits 15:4 "EPU instruction", 3:0 data length; no operation field.
- Timing (FIGS. 12-16 PAT p.12-14, Z80,000 bus): CPU-EPU transfers are one /AS with a /DS per word; not the Z8000's one 1110 cycle per word. FIG. 15 draws EPU store data from the clock fall in mid-T2, after a gap following the address, about a clock before /DS falls: neither the /AS rise nor the /DS fall (interpretation; Z80,000 only).
