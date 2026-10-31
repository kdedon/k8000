# Decisions

RTL design choices resting on the model or on inference rather than an explicit source. Machine-cycle timing conflicts are recorded with the Go model's machine-cycle doc. TM: Z8000 CPU Technical Manual (Mar81, Jan83); DB: Zilog 1988 Data Book.

| decision | evidence | tag |
|---|---|---|
| A REFRESH write with RE set reloads the prescaler count; the divide-by-4 phase runs on. /RESET leaves count and phase alone. | Model only. Manual silent: Mar81 TM §8.3 (printed 8-1); 1988 DB (printed 37) says only "presettable prescaler". | guess |
| REFRESH bit 0 is stored as written. | Mar81 TM (printed 6-70): LDCTL loads REFRESH(1:15). Matches the model. | interpretation |
| A refresh can start in the clock the prescaler underflows in: the sequencer sees the next clock's underflow, read from the prescaler's registers, and a refresh taken on it swallows it. | Model only: it steps the prescaler and dispatches the refresh in the same clock. | guess |
| Up to two refreshes are owed at once (a third underflow is lost); one goes out per boundary, the second at the next. | Jan83 TM PDF p.247 (8-2), 8.3: "The internal circuitry can record up to two skipped refresh operations." One per boundary: interpretation. Resolved conflict: the model kept one (no recorded reason) and was fixed. | explicit / interpretation (one per boundary) |
| STOP Low in an IF1's T1 clock puts a stream of refreshes after its T3, STOP sampled again in each T3 clock; once High, one more refresh, then the IF1's remaining clocks. Stream refreshes step the row but leave the prescaler and its pending alone. | 1988 DB PDF p.42 (printed 35), STOP and Fig 16. | explicit |
| The IF1's remaining clocks after a STOP stream hold the last refresh's pins, as a tail; a prescaler refresh still pending may follow them. | Model only. | guess |
| Z8001 nonsegmented data addresses use the PC's segment. | Jan83 TM 3.4.2 (printed 3-3). | explicit |
| `ad_in` comes straight from a register (the read-data capture). | The decode and program ROM look-ahead uses the whole data-arrival clock. | constraint |
| An X address adds the index to the address word's offset on its own 16-bit adder, not the ALU, while the operand cycle is requested; the segment takes no carry. | Model only; the shape note below leaves the adder open. | guess |
| A read-modify-write's R tail clock carries the latched result to the write data; the W takes it from the write-data latch and the R's address from an address latch, not a second pointer read. | Fawcett p.62 as quoted below (not re-read): a memory cycle's extra clocks route data inside the CPU. | guess |
| TSET's write data is all ones, ready before the read, so its W (no R tail) needs no latch. | TSET's programs: `R/0 W/0`. | interpretation |
| On a Z8003/Z8004 TSET's read has status 1111. | Jan83 TM p.317 (PDF): "During the read phase of the TSET instruction on the Z8003/4 VMPU, the status lines ST0-ST3 are all set to 1s." Table 2-1 p.23 (PDF): "1111 Test and Set Data Access (Z8003 and Z8004 only)". | explicit |
| TSET's write on a Z8003/Z8004 is data memory (1000). | No source states it; p.317 names only the read phase. | interpretation |
| /BUSREQ is granted at a machine-cycle boundary in place of the next cycle, if it was Low on the edge before; a tail belongs to its cycle. | Jan83 TM p.262 (PDF, printed 9-15): "If the external BUSREQ is Low at the beginning of any machine cycle, the internal BUSREQ will cause ... BUSACK to be asserted after the current machine cycle is completed." The one-edge sample is the model's synchronizer. | interpretation |
| /BUSACK rises on the second edge that sees /BUSREQ High; the next cycle's T1 is the edge after. That clock does no work. | Jan83 TM p.262 (PDF, printed 9-15): "The CPU regains control of the bus two clock cycles after BUSREQ rises." | explicit |
| While granted, AD is released and `bus_drive` is Low (registered, High again with /BUSACK for the release clock); a system top floats /AS, /DS, /MREQ, ST, R/W, B/W, N/S and SN with it. The pins themselves stay High or hold, as the model's vectors record. | Jan83 TM p.262 (PDF, printed 9-15): all outputs but BUSACK and MO are 3-stated; the CPU regains the bus two clocks after BUSREQ rises. The held pin values: model. | explicit / interpretation (held values) |
| TSET grants no bus request between its read and its write, on every CPU type. `bus_lock` rises as the read's word is in and falls as the write's T3 ends: no re-arbitration while High, so an arbiter sees the read and write as one tenure. | Jan83 TM p.228 (PDF, printed 6-167): "BUSREQ is not honored in the time between loading the destination from memory and storing the destination to memory." | explicit |
| A long memory operand's second cycle is at the first's latched address + 2 on the offset alone; the first read word waits in a high-word latch. | High word at the lower address. The segment taking no carry is model only. | interpretation |
| A long load writes its high word at the end of the clock after the first read's T3 (the second read's T1), and its low word on the program's last clock: for DA and X the clock after the second read's T3, for IR the second read's tail. | The DA and X programs give the second read no tail, so its word is in only from T3. | guess |
| A long store reads the high register on port B for the first write, the low one for the second. | High word at the lower address. | interpretation |
| A BA, BX or RA address is formed in the request clock on the X offset adder: base (port A; an RR pair when segmented) or updated PC, plus the displacement word or index. The segment is the base pair's, or the PC's for RA. | Model only; the Fn's 4-clock tail leaves the clock open. | guess |
| A BA or BX operand whose base is R15 (RR14 segmented) has stack memory status, as an IR operand through it does; RA and other bases are data memory. | Mar81 TM 5.2 (printed 5-5): "An operand specified by BA mode will be in stack memory space if the base register is the stack pointer (R15) and in data memory space otherwise." Likewise BX (5-6), segmented BA and BX with RR14 (5-9, 5-10), IR (5-3, 5-7). | explicit |
| A BX index is read on port B and latched in every clock before the request, whose port B is a store's data. | A store's data is taken with its write request. | guess |
| A taken branch loads the PC on the edge that opens its program's last clock, so the next IF1 is requested from it in that clock; RET loads it from the last popped word as it is taken (the T3-opening edge). | The IF1 address and segment are needed in the clock before its T1 (Fawcett p.59 as quoted below, not re-read). | interpretation |
| JR, CALR and DJNZ targets are the updated PC offset plus the doubled displacement (CALR and DJNZ subtract) on the address adder; JP/CALL X add the index to the address word's offset. The segment is the PC's, or the address word's or register pair's. | Arithmetic: Mar81 TM CALR (PDF p.72, printed 6-19), DJNZ (PDF p.99, 6-46), JR (PDF p.114, 6-61). Adder: model only. | explicit (arithmetic) / guess (adder) |
| A stack cycle reads the pointer on port A while it is requested; the adder gives the push address (pointer - 2, - 4 for a long) or the popped + 2 (+ 4), written to the pointer's offset word (R15 of RR14 segmented) the clock after the cycle is taken (its next reader is a later stack cycle's request). A long's second word is at the first's address + 2. | Steps: Mar81 TM PUSH (PDF p.165, printed 6-112), POP (p.163, 6-110), CALL (p.71, 6-18), RET (p.170, 6-117). Write clock: model writes the pointer as the cycle starts (a vector's final state checks it, counting the pending write); it also rewrites the segment word, which the RTL leaves. | explicit (steps) / guess (write clock) |
| A PUSH/POP stack cycle has stack status whatever its pointer register; its other operand follows the IR rule. | Model only; manual not read for PUSH @Rd with Rd not R15. | guess |
| Segmented CALL pushes the PC offset, then the segment word (bit 15 set), each a word step; RET pops the segment word, then the offset. | Layout: Mar81 TM CALL (PDF p.71, printed 6-18) and RET (p.170, 6-117), SP - 4 and @SP <- PC, segment word at the lower address. Bus order: model only. | explicit (layout) / guess (bus order) |
| DJNZ decrements in its internal operation's first clock into the write-data latch and writes the count with the PC load. | Model writes it at the instruction's end (a vector's final state checks it); program F1+2 · I6, 11 clocks. | guess |
| DI, EI, SETFLG, RESFLG, COMFLG and LDCTLB write the FCW (LDCTLB FLAGS,Rb bits 2:7, bits 0:1 unaffected; LDCTLB Rb,FLAGS the register, bits 0:1 zero) in the program's last clock. | Bits: Mar81 TM LDCTLB (PDF p.128, printed 6-75). Clock: model only; program F1+4 for DI/EI and the flag ops. | explicit (bits) / guess (clock) |
| TCC, DAB and EXTS read their register and write it in the program's last clock, EXTSL's two words in the last two; DAB runs on the ALU with the D and H flags. | DAB arithmetic: Mar81 TM (PDF p.92, printed 6-39). EXTS operation: (p.102, 6-49). Clocks: model only; programs F1+2 (TCC, DAB), F1+2 · I6 (EXTS). | explicit (DAB, EXTS operation) / guess (clocks) |
| Register EX, RLDB and RRDB swap through the write-data latch: in the second last clock w0[7:4] is written and the other result latched, in the last the latch goes to w0[3:0]. RLDB/RRDB set Z from the link (w0[3:0]) and leave S. | Z: Mar81 TM RLDB (PDF p.173, printed 6-120), RRDB (p.177, 6-124). S is undefined there; left unaffected, as the model (its source cites a later manual's "S: Unaffected"). Clocks: model only; programs F1+3 (EX), F1+2 · I4 (RLDB/RRDB). | explicit (Z) / guess (S, clocks) |
| Memory EX swaps in its read's first tail clock: the read word goes to the register, the register's old value to the write-data latch; the W sends the latch to the read's address. EXB's read is a word cycle, its write a byte. | Vector pins (B/W) for the cycle widths; the rest model only, as the read-modify-write row above. | guess |
| LDA and LDAR take the address the operand path forms (the adder, the base or index latch, the address word) and write it in the program's last clock; segmented, the segment word (segment in bits 14:8) in the second last clock and the offset in the last. | Model only; programs F1+4 · Fn+2 · I3 (RA, BA, BX), F1+4 · Fa+2 (DA, X; Fa+3 and Fn segmented). | guess |
| The register shift count, MREQ's handshake and HALT's exit are tied off. | Held at the values the sequencer used before; no datapath source yet. | guess |
| A PUSH whose source is the stack pointer's offset register (R15; R15 of RR14 segmented) pushes the decremented value. | Mar81 TM PUSH (PDF p.165, printed 6-112): "The contents of the destination register (a stack pointer) are decremented ... Then the source operand is loaded". | interpretation |
| A CALL through or indexed by R15 (RR14 segmented) branches to the value before its push. | Mar81 TM CALL (PDF p.71, printed 6-18) orders SP ← SP - 2 (4 segmented); @SP ← PC; PC ← dst. Read as dst evaluated before the push; matches the model. | interpretation |
| A segmented push, pop, call or return writes only R15; R14 is left as it is. The model rewrites R14 as seg<<8 on each step, so they differ only when R14 is malformed. | Jan83 TM Figure 3-3 (PDF p.36): a segmented address in a register pair has bit 15 and bits 7-0 of the segment word 0. | interpretation |
| LDCTL moves a control register word in the program's last clock (F1+4). LDCTL FCW,Rs loads FCW bits 15:11 and 7:2 in the second last, so the next fetch has the new N/S; bits 10:8 and 1:0 are reserved and keep their value. A change of S/N swaps R15 with the NSP offset in that clock and, on a Z8001, R14 with the NSP segment in the last clock, whatever SEG. Tail 1 decodes w0's direction and control register number, tail 2 reads Rs or the control register onto the ALU path; here both are combinational from the held w0 and the register ports, so those clocks add no logic. | Mask: Mar81 TM PDF p.123 (6-70). Banking: PDF p.23 (2.6), the Z8001 has a two-word stack pointer per mode (R14'/R15' or R14/R15). Clocks: RTL choice; N/S of the next IF1 in the vectors. | explicit (mask) / interpretation (banking) / guess (clocks) |
| On a Z8001, R14 is banked with R15 in every mode, so any S/N change swaps both, whatever SEG. Another emulator swaps R14 only when segmented; the model followed it until this change. | For: Mar81 TM PDF p.23 (2.6), a two-word stack pointer per mode (R14'/R15' or R14/R15). Against: PDF p.124 (6-71), "In segmented mode, the NSPSEG register is the normal mode R14". Chosen because 2.6 is the architecture statement and p.124 names the LDCTL register. | interpretation |
| LDCTL reads the PSAP segment as 0sssssss 00000000 and control registers 0 and 1 as zero; a Z8002 still holds the PSAP and NSP segment words. | Field: Mar81 TM PDF p.124 (6-71), PSAPSEG(8:14). Zero fill and registers 0 and 1: model only. | explicit (field) / guess (fill) |
| LDPS reads FCW then PC (segmented: from the address + 2, then the PC segment word and offset; a Z8001 nonsegmented keeps its PC segment); IRET pops the identifier, FCW and PC the same way from R15 (RR14), stack status, + 2 per pop. The read FCW is held until the edge opening the program's last clock, which loads FCW and PC (the last word from the read latch, or straight from the read as it is taken) and does LDCTL FCW's swaps (R15 then, R14 in the last clock). | Layout per mode, PC segment: Mar81 TM PDF p.139 (6-86). Pop order, SP + 4 / + 6: PDF p.112 (6-59), which leaves Z8001 nonsegmented IRET undefined. Clocks: RTL choice. | explicit (layout, order) / guess (clocks) |
| LDPS reads with data status whatever its pointer. Its X index is read on port B before the first read and held, + 2 when segmented, so the first address takes one add. | Status: model only. Index: RTL choice. | guess |
| LDM's address is formed once, as for a word operand, and each later word goes to the previous address + 2 (the segment takes no carry), so loading the pointer register does not move the block. Registers run from w1[11:8] modulo 16 (R0 follows R15); every cycle has data status. A store's register is read on port B as its cycle is requested; a load's word is written the clock after its T3. | Wrap: Mar81 TM PDF p.137 (6-84). The rest: model only. | explicit (wrap) / guess |
| Translate per byte: read the string byte at @Rd (w0[7:4]), read the table at Rs (w1[7:4]) + that byte (offset add, no segment carry), then write the translated byte back to @Rd's old address (TR) or run the internal operation (TRT); every cycle data status. Per-clock work: Translate clocks below. | Fields: Mar81 TM PDF p.205 (6-152), p.214 (6-161); the Coherent assembler encodes `trib (rr4),(rr6),r3` as B840 0360. Order, V, TRT Z, TR Z undefined: PDF p.205, p.209 (6-156). A nonrepeating TR's Z tests the whole table word, as the model does. Clocks: guess. | explicit (fields, order, flags) / guess (clocks) |
| A new FCW from LDCTL, LDPS or IRET takes effect at the next instruction: the instruction's own cycles keep the old status, and the FCW loads no later than the edge opening the next IF1. | Mar81 TM PDF p.139 (6-86), p.112 (6-59). | explicit |
| IN/OUT: the I/O cycle is requested in the port word's T3 clock (DA) or the IF1's last tail clock (IR), with the port from word 1 or from port A (w0[7:4], a word), segment lines 0. OUT's data comes from port B (w0[7:4] DA, w0[3:0] IR) as the cycle is requested; a byte rides AD7:0 for standard I/O and AD15:8 for special I/O, the other half 0. IN writes its register in the cycle's T3 clock, the program's last. | Lanes, N/S Low, segment lines undefined: Mar81 TM PDF p.241 (printed 9-6). Register fields, the zero half, segment 0 and the write clock: model only. Programs F1+2 · Fn · IO and F1+3 · IO from the table. | explicit (lanes) / guess (rest) |
| An I/O cycle's /DS falls at the edge opening TWA whatever /WAIT does. /WAIT is first sampled mid-TWA; its Tw clocks sit between TWA and T3 with /DS Low, so /WAIT Low only at T2 adds nothing. The interrupt acknowledge keeps its /WAIT-delayed /DS. | Mar81 TM Fig 9-5 (PDF p.242, printed 9-7) and 9.4.1 (PDF p.239, printed 9-4). The model used to hold the I/O /DS fall back while /WAIT was Low, citing Product Spec Fig 14, which shows only the acknowledge string; it now follows Fig 9-5. | explicit |
| Block I/O (INI, IND, OUTI, OUTD, their repeats, byte and special forms) leaves Z unchanged; V is set from the count only. | The instruction summary says Z is altered (Mar81 TM PDF p.59, printed 6-6); the instruction pages say Z undefined, IND's and Mar81 INIR's say unaffected. The model's requirements (R-CPU-428, R-CPU-819) record V only, and no Coherent code tests Z or V after these. | interpretation |

## Memory operands: ADD R,@Rs

The per-clock design of the simplest memory-operand form; the other shapes follow from it. Form `ADD R,src IR` runs program 2 in all three columns: `F1+1{P1} · R`, a 4-clock IF1 then a 3-clock read, 7 clocks. 1988 DB p.18 (PDF 25), ADD IR: "7 7 7" (NS SS SL). Ref Manual p.58 (PDF 67), `ADD Rd,@Rs`: 7 nonsegmented, 7 segmented. ADDB is the same with B/W High and a byte pass; the byte comes from the upper bus half if ea[0] is 0, else the lower (Fawcett p.60, PDF 71).

A clock is named by the bus state its opening edge starts; the bus unit's `state_q` reads one ahead (state `BUS_T3` is the T2 clock). The RTL drives SN at the T1 edge, not in the clock before. The RTL takes a read word on the edge that opens T3; the chip samples it at the falling edge in T3 (Fawcett p.60, PDF 71). Fawcett has no worked memory-operand example; the shape comes from these:

- p.56 (PDF 67): "Most Z8000 instructions conclude with several clock periods dedicated to internal CPU operations ... While these internal operations are being executed, the CPU will start to fetch the next instruction's opcode."
- p.62 (PDF 73): a memory machine cycle "can be one to four clock cycles longer than the bus transaction time ... used to allow extra time for the routing of data internal to the CPU."
- p.67 (PDF 78): "adding two word registers takes one memory read cycle (an IF1 cycle) that is four clock periods long."
- p.59 (PDF 70): the Z8001 segment number "is output during the clock period preceding T1, that is, during the last clock period of the previous machine cycle."
- p.120 (PDF 131): "if R15 in nonsegmented mode or RR14 in segmented mode is the register used to hold the operand's address, the operand will be in the stack memory address space (... 1001 ...)".

NS:

| clk | bus | register file | address / ALU | latches at the clock's end | tag |
|---|---|---|---|---|---|
| 1 IF1 T1 | /AS Low, AD = PC, ST 1101 | - | - | - | explicit |
| 2 IF1 T2 | /DS Low; memory access | - | - | word 0, PC + 2 | explicit |
| 3 IF1 T3 | /DS rises at the end | - | decode word 0 (the chip has it from mid-T3) | decode | interpretation |
| 4 IF1 tail | strobes High, status held | A: Rs (word) | ea = {PC segment, Rs}; `req_addr` = ea_d; ST 1001 if Rs is R15, else 1000 (explicit, p.120) | ea_q; the R request takes it | interpretation |
| 5 R T1 | /AS Low, AD = ea_q, R/W High | - | - | - | explicit |
| 6 R T2 | /DS Low; memory access, /WAIT sampled | - | - | operand word | explicit |
| 7 R T3 | /DS rises at the end | A: Rd | Rd + operand | Rd, FCW flags | interpretation |

SS and SL (identical: no address word, so SL never applies):

| clk | bus | register file | address / ALU | latches at the clock's end | tag |
|---|---|---|---|---|---|
| 1-3 | as NS | - | as NS | as NS | as NS |
| 4 IF1 tail | as NS; the R's Tn, when the chip shows the segment | A: RRs (long; port B is word-only) | ea = {RRs high [14:8], RRs low}; `req_addr` = ea_d; ST 1001 if RR14 (explicit) | ea_q; the R request takes it | interpretation |
| 5-7 | as NS (SN = ea_q segment) | as NS | as NS | as NS | as NS |

What this instance fixes (IR read, register destination):

- The address is formed in the IF1 tail: port A reads the pointer, and ea_q holds it through the R. It is the tail's work, as the ALU pass is ADD R,R's (Fawcett p.67), and the segment is ready in the clock the chip shows it (p.59).
- The pointer is read in the tail, the destination in the R's T3. Port B is idle; the memory word is the ALU's second input, from an operand latch loaded with the read.
- The ALU pass lands on the R's T3, the program's last clock, as execute already places it; Rd and the flags are written at the end of the pass's clock, the edge that opens the next IF1. The chip finishes it after its mid-T3 sample, overlapping the next fetch (p.56); the total is the same.
- No clock here is a wait: each carries bus or datapath work. A form whose total leaves a clock with none gets a labelled wait row.

General rule: the full address is ready in the last clock before the operand cycle's T1. Other shapes:

- DA/X: the address comes from the address word at the Fa's T3; X adds the index in the Fa tail on the idle ALU (guess; a dedicated adder if timing needs it).
- Stores (W): write data is captured on the edge that opens the W's T1, so the source register is read in the preceding tail on port B, the pointer on port A.
- Read-modify-write (R · W): the pass lands in the R's T3 and the result goes to a write-data latch; execute needs a pass hook per cycle, not only on the program's last clock.
- Long: a 32-bit operand latch (high word first), the second R at ea + 2 (an incrementer), and two passes, which need a tail on the second R.


## Translate clocks

TR: F1 · Fn+1 · R+2 · R+3 · W · I4; TRT has I3 for the W. The repeating forms loop R+2 · R+3 · W (I3) and run the I4 once at exit. Every row is a guess from the totals and the operation.

| clock | work | here |
|---|---|---|
| Fn tail | Rd to the address latch for the string read | port A reads Rd as the read's address |
| R+2 tail 1 | select the byte by A0, zero-extended, into the ALU operand | the operand latch takes the byte at T3 |
| R+2 tail 2 | table base offset + byte to the table address; the segment is copied | port A reads Rs, the offset adder forms the address |
| R+3 tail 1 | select the byte by A0; TRT: RH1 takes it, Z from byte == 0 | RH1 written; Z loads with V in W T2 / I3 c2 |
| R+3 tail 2 | old Rd to the address latch for the write-back | port A reads Rd as the write's address |
| R+3 tail 3 | TR: the byte to the write-data latch | write data straight from the operand latch |
| W T1 / I3 c1 | Rd offset word + or - 1 | as listed |
| W T2 / I3 c2 | r - 1; V from r == 0 (TRT and nonrepeating TR: Z) | as listed |
| W T3 / I3 c3 | repeat test: V, and Z for TRT | the decision loaded at the end of c2 is read by the sequencer |
| I4 c1 | PC fix-up | PC already past the instruction's words from fetch |
| I4 c2 | FCW flag write-back | flags already loaded in the last element's c2 |
| I4 c3 | end-of-instruction sampling point | as the third clock opens |
| I4 c4 | next IF1 address set-up | the fetch unit's PC |

TR leaves RH1 as it is: the manual makes it undefined and the model does not touch it.

## Block clocks

Block transfer, compare, string compare and I/O run translate's element shape: the clocks count from the element's data word, the pointers step in the tail, and the count decrements in the first clock of the element's last cycle, where V (and the compare flags) load and the repeat is decided; the sequencer reads it in that cycle's last clock. The pre-element clocks are F1 · Fn+1 (7) and the exit I4 runs once, as translate's. Every row is a guess from the totals and the operation. LD: F1 · Fn+1 · R+3 · W · I4 (20); the repeating forms 11 + 9n.

| clock | work | here |
|---|---|---|
| Fn tail / last element clock | Rs (a pair segmented) to the address latch for the read | port A reads Rs as the read is requested |
| R+3 tail 1 | select the byte by A0 to the write-data latch, both halves | the operand latch takes the byte at T3; write data straight from it |
| R+3 tail 2 | Rs offset ± width (no segment carry) | port A reads Rs, the shared adder steps it |
| R+3 tail 3 | Rd to the address latch for the write; Rd offset ± width | one port A read gives the address and the step |
| W T1 | r - 1; V from r == 0 | the repeat decision loads with V |
| W T2, T3 | repeat test | the sequencer reads the decision in T3; an interrupt between elements is taken here only if the repeat continues, pushing the PC of the instruction's first word |

CPI: F1 · Fn+1 · R+3 · I3 · I4 (20); CPIR 11 + 9n.

| clock | work | here |
|---|---|---|
| R+3 tail 1 | select the byte by A0 | the operand latch takes the byte at T3 |
| R+3 tail 2 | R(w1[7:4]) - operand; cc w1[3:0] tested on its C Z S V | port A reads the register into the ALU; C, S and the match latch |
| R+3 tail 3 | Rs offset ± width | as listed |
| I3 c1 | r - 1; C S from the compare, Z = match, V from r == 0 | the repeat decision loads: count not zero and no match |
| I3 c2, c3 | repeat test | read by the sequencer in c3; the between-element interrupt hook, as LD |

CPSI: F1 · Fn+1 · R · R+4 · I4 · I4 (25); CPSIR 11 + 14n. The second read's word is clock 0. Destination minus source, Z from cc, V from the count, pointers before the count: Mar81 TM PDF p.88 (printed 6-35); C and S are undefined there and come from the compare, as the model.

| clock | work | here |
|---|---|---|
| R T3 / second R T1, T2 | select the source byte by A0; Rd to the address latch | the operand latch takes the byte; port A reads Rd as the read is requested |
| R+4 tail 1 | select the destination byte by A0 | the source moves to a second latch as the destination arrives |
| R+4 tail 2 | destination - source; cc tested | C, S and the match latch |
| R+4 tail 3 | Rs offset ± width | as listed |
| R+4 tail 4 | Rd offset ± width | as listed |
| I4 c1 | r - 1; flags as CPI | the repeat decision loads |
| I4 c2 - c4 | repeat test | read by the sequencer in c4; the between-element interrupt hook, as LD |

INI: F1 · Fn+1 · IO+3 · W · I4 (21); INIR 11 + 10n. OUTI: F1 · Fn+1 · R+3 · IO · I4 (21); OTIR 11 + 10n. The port register is a word and does not step; the I/O cycle is IN/OUT's (TWA included). Z unchanged, V from the count (see the block I/O Z row).

| clock | work | here |
|---|---|---|
| IO+3 tail 1 | select the byte from its class lane (AD7:0 standard, AD15:8 special) | the operand latch takes it at T3 |
| IO+3 tail 2 | the byte to the write-data latch, both halves | write data straight from the operand latch |
| IO+3 tail 3 | Rd to the address latch; Rd offset ± width | as LD |
| W T1 | r - 1; V | as LD, with the between-element interrupt hook in W T2, T3 |
| R+3 tail 1 (out) | select the byte by A0 | the operand latch takes it at T3 |
| R+3 tail 2 (out) | Rs offset ± width | as LD |
| R+3 tail 3 (out) | the port R(w1[7:4]) to the address latch; the byte to its class lane | port A reads the port |
| IO T1 (out) | r - 1; V | the repeat decision loads; read in the I/O cycle's T3, the between-element interrupt hook there, as LD |

## Multiply and divide

The serial units keep their cadence (setup, steps, adds, finish; ledger item 50); these rows place them in the programs.

| decision | evidence | tag |
|---|---|---|
| The units move only on program clocks: not a wait state, not an inserted refresh. | Model only: it ticks its sequencer on transaction clocks but waits, tails and internal cycles. | guess |
| The work ends with the program's last clock, so it starts (total - work) clocks after the IF1's T1: clock 3 for R, IM and IR; for DA and X 4, plus 1 for X or a short segmented offset, plus 3 for a long one. The unit is loaded on the clock before. | Model only: its start clock is the program's clocks less the work's. The DA/X deltas are the table's (item 49). | guess |
| No extra register-file ports. Port A reads the destination quad as the unit starts (the IF1's T3 for R, IM and IR; the start clock for DA and X). Port B reads a register source: a word the clock after the start; a long's high word as the unit starts (held) and its low word the clock after. | Port A is free in those clocks (an IR pointer is read on it the clock after, an X index is on B); a register source must be in by the first setup clock. | guess |
| A register source is latched in the load clock and given to the unit on the first setup clock, where it picks the path (zero, overflow); a memory or immediate source on the edge its last word arrives, from that word. The held program takes the new path; a zero memory or immediate operand also sets the arriving cycle's tail, which the bus reads in its T3 clock. | Model: the operand is set before the first setup step and the path taken when it arrives. The paths differ in the arriving cycle only in its tail on the zero path (MULT DA/X: 0, else 2); a simulation check holds every path's arriving cycle and link to the lookup. No path is taken on an edge that starts a cycle, so later cycles come from the held program. A zero test on the bus word is short; the overflow compare stays off the cycle lookup. Keeps the register file and the path compare off the program-ROM lookups. | interpretation |
| Product, quotient and remainder, and C Z S V, are written from the units' registers the clock after the program's last clock. Divide by zero and overflow write flags only. | Model stores on the last clock; the next instruction reads registers from its IF1's T3 and flags from its T3 edge. Flags per the CPU Technical Manual (Mar81, PDF p.96, printed 6-43; MULT PDF p.148, printed 6-95): divide by zero sets V and Z, clears C and S, leaves the destination; overflow (quotient outside -2^16..2^16-1, or -2^32..2^32-1 for DIVL) sets V, clears C and Z, S undefined (written 0, as the model), destination undefined (left); a quotient inside that range but outside the word (long) range sets C and V, S and Z from the quotient, quotient and remainder written. MULT/MULTL: C if the product needs the upper half, Z, S from the product, V cleared. | guess |
| MULTL runs one extra add per set bit of the absolute value of the multiplicand's low 16 bits read as a signed word; the unit counts them while it steps, and the program repeats its 7-clock add while it says another follows. | The Go model's reading, followed over the other readings in the notes. | interpretation |
| Divide by zero and overflow only set flags; nothing traps. | Model has no trap. | interpretation |


## Shifts

SLA/SLL: F1+4 · Fn+3 · n x I3 (13 + 3n); SDA/SDL: F1+4 · Fn+2 · I3 · n x I3 (15 + 3n); a zero count costs one position.

| decision | evidence | tag |
|---|---|---|
| One position per I3, shifted on the edge that opens it; the shifter starts on the edge that takes the first. Result and flags go in on the program's last clock. | Mar81 TM SLA (PDF p.190, printed 6-137): 13+3b, b = 0 timed as 1; SDA (PDF p.183, 6-130): 15+3n. The per-position I3 and its placement are the model's. | explicit (counts) / guess (placement) |
| Port A reads the destination for the whole program; SDA/SDL read the count register on port B as the I3 before the positions is taken, and that I3 forms the count's magnitude and direction. | The extra I3 is the only difference from SLA's program; its work is the count read. No new ports. | interpretation |
| A refresh, wait or bus hold among a shift's internal clocks holds the position step; the shift's clocks count only ticks the program also counts, as the multiplier's do. | The model inserts the refresh mid-program at 3 clocks each and leaves the result alone; the hold keeps the last position on the program's last clock. | interpretation |
| A zero count leaves C; V is written by SLA/SDA only (SRA clears it). | Mar81 TM PDF p.189 (6-136): C undefined for a zero shift; the model leaves it. | guess (C) |

## Dynamic bit

BIT/SET/RES dst,Rs (bit number in a register): F1+1 · Fn+3 (10).

| decision | evidence | tag |
|---|---|---|
| Port B reads the bit register (w0[3:0]) and its mask is latched in the second last clock; port A reads the target (w1[11:8]); the last clock sets Z (BIT) or writes the target (SET/RES). The low four bits number the bit, three for a byte. | Mar81 TM BIT (PDF p.69): only the low four (byte: three) bits of the source are used. Clock placement is the model's program; the work split is ours. | explicit (bit number) / guess (placement) |

## Multi-micro

MSET/MRES/MBIT: F1+2. MREQ: F1+2 · n x I7 · I7 (12 + 7n; Mar81 TM PDF p.145, printed 6-92).

| decision | evidence | tag |
|---|---|---|
| MSET/MRES drive /MO, and MBIT sets S from /MI, on the edge that opens the last clock. | Model's placement; the pins match the vectors. | guess |
| MBIT sets S while /MI is High (inactive) and clears it while Low. | Mar81 TM PDF p.143 (6-90), Jan83 PDF p.153 (6-94): S <- 1 if MI high; the example loops on JR PL until the resource is free. Resolved conflict: the model set S while /MI was Low (its commit note read Low as busy, no source) and was fixed. | explicit |
| MREQ samples /MI on the edge its word is taken (the edge opening the IF1's T3): High drives /MO Low and runs the count; Low drives /MO High and skips it. Only in system mode (normal mode traps; /MO holds). Rd is read on port A in the T3 clock into a count register (zero skips the count); each counting I7 writes it less one to Rd at the end of its first clock and latches whether another follows. /MI is sampled again as the last clock opens. | Operation: Mar81 TM PDF p.144 (6-91). Edges: the model's; the latched decision keeps the register file off the program lookup. | explicit (operation) / guess (clocks) |
| MREQ clears Z when /MI is Low at the start (not signalled) and sets it on the last clock otherwise. | Mar81 TM PDF p.144 (6-91), Jan83 PDF p.154 (6-95): Z <- 0, then Z <- 1 only on the path that drives /MO Low; the flags table gives S 0, Z 0 for a request not signalled. Resolved conflict: the model set Z on both paths (no recorded reason) and was fixed. | explicit |
| A trap takes the next IF1's place with the entry program: an aborted IF1 at the PC (/AS and IF1 status, /DS and /MREQ High, the word ignored, the PC not stepped), pushes at SP - 2 each of the PC offset, the PC segment word (Z8001), the old FCW and the identifier (the trapping instruction's first word), then the FCW and PC reads from the PSA entry. System mode (and segmented on a Z8001) is entered in the aborted IF1's first tail clock, R15 then R14 swapping with the NSP registers from normal mode; the PSA FCW loads as the next edge opens the last clock, with IRET's swap. | Order, identifier, system mode before the pushes with the saved FCW unaffected: Jan83 TM PDF p.240 (7-3), 7.7.1-7.7.2; PC pushed: PDF p.241, Table 7-1. Clock totals (aborted fetch 7, pushes 4/3/4/7, reads 3 each): Fawcett PDF p.104, Table 6.3. Per clock, as reasoned from those totals: the aborted IF1's four tail clocks are the switch to system mode (FCW S/N, SEG), the stack pointer swap, the stack pointer stepped by -2 for the first push (1988 DB PDF p.159: "the system stack pointer is decremented in preparation for pushing") and the PC offset moved to the write latch; the identifier push's four are the PSA entry address (PSAP + entry), a VI's vector added to it, the stack pointer's last value written back, and the FCW read's address and status set up. The switch clock and those assignments: model; the pins match the vectors. | explicit (order, totals) / interpretation (clocks) |
| In normal mode, I/O, block I/O, IRET, HALT, LDCTL, LDPS, MSET/MRES/MBIT/MREQ, DI and EI trap after their IF1 machine cycle (its tail as in the instruction's program), their work suppressed, pushing the address of the second word. The decode ROM's priv bit marks them. | List: Jan83 TM PDF p.68 (6-9). PC: Jan83 TM PDF p.241 (7-4), Table 7-1. The IF1 tail: model. | explicit / interpretation (tail) |
| SC's program is its IF1 machine cycle; the entry follows and pushes the next instruction's address. | Jan83 TM PDF p.241 (7-4), Table 7-1. | explicit |
| TestMachineCycleTrapZ8001Nonseg and TestMachineCycleInterruptSample.005 end while the handler's immediate word is on the bus; the model's final R0 and flags already hold the ADDB result, which the RTL writes on the program's last clock. Pins match; the final state is left failing. | Vector end point, as TestMachineCycleSequenced.000-.002. | constraint |
| /VI, /NVI and an /NMI falling edge are sampled as the instruction's last cycle opens T3 (an internal operation's third clock); an enabled request starts the interrupt entry at the boundary: NMI, then VI (VIE), then NVI (NVIE), the enables taken from the FCW as the next instruction starts, so an EI or DI on the last clock counts. An NMI edge is held until a sample takes it and its request until its entry starts; the levels are copied at each sample. An entry samples at its last cycle like an instruction, so a request its new FCW enables (or an NMI edge held through it) is acknowledged at once, before the handler's first instruction; a chained entry starts its program over. No sample after a trapping IF1; an SC or privileged trap at the same boundary goes first. | Sampling at T3: 1988 DB PDF p.162 (printed 155). Accepted at the next instruction's start, the enable as set by EI, LDPS, LD FCW, SC or IRET: Jan83 TM PDF p.262 (printed 9-15), 9.6.1. NMI edge-triggered: 1988 DB PDF p.155. Priority: Jan83 TM PDF p.243, 7.8. An entry's new FCW: SC is named with EI in PDF p.262, 9.6.1 ("acknowledged after the execution of that instruction"); PDF p.243 step 3: "If any enabled exceptions remain after the new FCW is loaded, the highest-priority exception is acknowledged immediately." A refresh pending with a trap or interrupt goes first: Jan83 TM PDF p.246, 8.3. The edges and the boundary: model; the pins match the vectors. | explicit (T3) / interpretation (edges) |
| The interrupt entry is the trap entry with the acknowledge after the aborted IF1: status 0101/0110/0111, address 0, five automatic waits, then two tail clocks (ten clocks in all); the word read at T3 is the identifier pushed. A VI reads its PC from PSAP + 1E + 2 id[7:0] (Z8002) or PSAP + 3C + 2 id[7:0] (Z8001); its FCW from the fixed VI entry. | Ten clocks, identifier at T3: Jan83 TM PDF p.257, 9.4.6, Fig. 9-6 (PDF p.258); 1988 DB PDF p.159, Fig. 14. N/S Low before the acknowledge: Jan83 TM PDF p.240, 7.7.1. Vector table: Jan83 TM PDF p.242 (7-5), Fig. 7-2, the identifier doubled on both CPUs (the Z8002 table ends at 21C); 7.2.2 PDF p.238. Resolved conflict: the model added the raw byte on the Z8002 (no recorded reason) and was fixed. The two tail clocks: model. | explicit / interpretation (tail) |
| N/S goes Low (system) before the acknowledge cycle, as the model does. | Jan83 TM PDF p.240, 7.7.1: "Before the acknowledge cycle, the CPU enters its System mode. The N/S line is asserted". Conflict: 1988 DB PDF p.159 says "After the acknowledge cycle, the N/S output indicates the automatic change to system mode." Jan83 and the model followed. | explicit (conflict) |
| A repeat form samples at the last cycle of an element that another follows; a request then ends the instruction after that cycle, the PC stepped back to the first word (all repeat forms are two words) before the aborted IF1, which fetches there. | Jan83 TM PDF p.88 (LDIR): interruptible after each element, the start PC saved; PDF p.68. The step-back edge: model. | explicit / interpretation (edge) |
| HALT samples in the third clock of each internal cycle; an enabled request (or held NMI edge) at two consecutive samples makes that cycle its last and is the instruction's sample. | 1988 DB PDF p.162 (printed 155). | explicit |
| On a Z8003/Z8004 /ABORT is sampled as a memory transaction's T2 opens and with each Low /WAIT sample after it. I/O, acknowledge, refresh and EPU transfer (1110) cycles, and every cycle of a trap or interrupt entry, are not sampled. | Jan83 TM PDF p.265 (9-18), 9.7: "monitors its ABORT input during each bus transaction ... If the ABORT input is asserted during clock cycle T2 ... the ABORT input is tested during each added WAIT cycle"; Fig. 9-11, PDF p.266. The excluded cycles: model. | explicit / interpretation (exclusions) |
| An abort ends the instruction as the aborted cycle's T3 ends, with no tail: its read word is dropped and nothing after it runs. Nothing is rolled back: registers already written stay, and a word fetched counts as taken (the PC past it). The requests are sampled at that T3, and the next IF1, or the entry for a request, follows. | Jan83 TM PDF p.239 (7-2), 7.4: the Abort Instruction Function "aborts the current instruction execution"; PDF p.265, 9.7: "When the WAIT input is deasserted, the CPU will acknowledge any pending interrupt request." No rollback: PDF p.243, 7.7.5. The tail, the dropped word and the PC: model. | explicit / interpretation (clocks, PC) |
| /ABORT is not honoured during a trap or interrupt entry: its status pushes and PSA reads are not sampled. | Jan83 TM PDF p.350, Appendix D: on an abort "the CPU saves the values contained by the Flag and Control Word (FCW) and the Program Counter (PC) of the aborted instruction on the system stack", which the restart algorithm takes as done; it gives no recovery for a fault in that save or in the PSA reads, so the stack and the PSA are taken as resident. | interpretation |
| SEGT (Z8001) and SAT (Z8003) are a level, copied at each sample like /VI and /NVI, never masked; priority NMI, segment trap, VI, NVI. The acknowledge has status 0100; its word is the identifier pushed, not a vector index; FCW and PC come from PSA entry 20 (segmented). The Z8002/Z8004 have no pin. | Priority: Jan83 TM PDF p.243, 7.8. An entry's new FCW: SC is named with EI in PDF p.262, 9.6.1 ("acknowledged after the execution of that instruction"); PDF p.243 step 3: "If any enabled exceptions remain after the new FCW is loaded, the highest-priority exception is acknowledged immediately." Traps cannot be disabled; SAT, and NVI/VI/NMI in its place on the Z8004: PDF p.239 (7-2), 7.3.4-7.3.5. Entry: PDF p.242, Fig. 7-2. | explicit |
| An EPU instruction with FCW EPA clear traps after its IF1 machine cycle (its tail as in the program), its work suppressed, as a privileged trap does: PSA entry 04 (08 segmented), the second word's address pushed. | Trap: Jan83 TM PDF p.239 (7-2), 7.3.1. Entry: PDF p.242, Fig. 7-2. The IF1 cycle and tail: model. | explicit / interpretation (tail) |
| A CPU-EPU transfer (1110) has I/O timing: T1, T2, one automatic wait, T3, /DS falling at the wait for a read or a write, /WAIT sampled as for I/O. Register transfers take 11+4n clocks, the flag byte 15. EPU memory transfers (1010) keep memory timing. | Jan83 TM PDF p.255, 9.4.4: "EPU-CPU transactions have the same timing relationships as I/O transactions" (Fig. 9-5); counts 11+4n and 15 on PDF p.234-236 (6-172 to 6-174), where the Mar81 edition prints 11+3n and 14. Jan83 is taken over Mar81; the model was fixed to match. | explicit (Jan83 over Mar81) |
| The internal EPU operation stays 14 clocks (both words fetched, no transfer). | Jan83 TM PDF p.237 (6-175) prints 11+4n, with no transfer for n to count; Mar81 prints 14. | interpretation |
| An EPU memory transfer is addressed as LDM (IR, DA, X; +2 per word) with status 1010; a load's word is left to the EPU, and a store releases AD from T2 while the CPU strobes. A register transfer moves n words (1 to 16) from Rn up (R15 wraps to R0), Rn in the second word's bits 11:8 and n-1 in its bits 3:0; the flag transfer moves FCW bits 7:2 as a byte transaction (B/W High) on AD7:AD0 only. Their cycles drive address 0. | Register fields: Jan83 TM PDF p.234 (6-173), the Load CPU from EPU / Load EPU from CPU formats. Flag byte: PDF p.255 (9-8), 9.4.4. Address 0 and the rest: model. | explicit (fields, byte) / interpretation |
| STOP Low in the T1 clock of an EPU instruction's second-word fetch runs the refresh stream after that fetch's T3, its tail after the stream, as for an IF1. | Jan83 TM PDF p.262, 9.6.5: STOP "is also sampled on the falling clock edge immediately preceding the second word of an instruction fetch" when the first word is an extended instruction. The clock: as the IF1's. | explicit / interpretation (clock) |
| A byte or word immediate ALU or load op (ADDB R,#imm and the like) writes its register and flags on the edge that opens its immediate word's T3, the word as sampled there. | Model only: the Go model runs the op as that T3 opens. No manual gives the internal write clock. | interpretation |
