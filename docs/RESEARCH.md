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
