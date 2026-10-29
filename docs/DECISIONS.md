# Decisions

RTL design choices resting on the model or on inference rather than an explicit source. Machine-cycle timing conflicts are recorded with the Go model's machine-cycle doc. TM: Z8000 CPU Technical Manual (Mar81, Jan83); DB: Zilog 1988 Data Book.

| decision | evidence | tag |
|---|---|---|
| A REFRESH write with RE set reloads the prescaler count; the divide-by-4 phase runs on. /RESET leaves count and phase alone. | Model only. Manual silent: Mar81 TM §8.3 (printed 8-1); 1988 DB (printed 37) says only "presettable prescaler". | guess |
| REFRESH bit 0 is stored as written. | Mar81 TM (printed 6-70): LDCTL loads REFRESH(1:15). Matches the model. | interpretation |
| Z8001 nonsegmented data addresses use the PC's segment. | Jan83 TM 3.4.2 (printed 3-3). | explicit |
| `ad_in` comes straight from a register (the read-data capture). | The decode and program ROM look-ahead uses the whole data-arrival clock. | constraint |
| An X address adds the index to the address word's offset on its own 16-bit adder, not the ALU, while the operand cycle is requested; the segment takes no carry. | Model only; the shape note below leaves the adder open. | guess |
| A read-modify-write's R tail clock carries the latched result to the write data; the W takes it from the write-data latch and the R's address from an address latch, not a second pointer read. | Fawcett p.62 as quoted below (not re-read): a memory cycle's extra clocks route data inside the CPU. | guess |
| TSET's write data is all ones, ready before the read, so its W (no R tail) needs no latch. | TSET's programs: `R/0 W/0`. | interpretation |
| On a Z8003/Z8004 TSET's read has status 1111. | Jan83 TM p.317 (PDF): "During the read phase of the TSET instruction on the Z8003/4 VMPU, the status lines ST0-ST3 are all set to 1s." Table 2-1 p.23 (PDF): "1111 Test and Set Data Access (Z8003 and Z8004 only)". | explicit |
| TSET's write on a Z8003/Z8004 is data memory (1000). | No source states it; p.317 names only the read phase. | interpretation |
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
| Register EX, RLDB and RRDB swap through the write-data latch: in the second last clock w0[7:4] is written and the other result latched, in the last the latch goes to w0[3:0]. RLDB/RRDB set Z from the link (w0[3:0]); S likewise. | Z: Mar81 TM RLDB (PDF p.173, printed 6-120), RRDB (p.177, 6-124). S is undefined there; the model's choice. Clocks: model only; programs F1+3 (EX), F1+2 · I4 (RLDB/RRDB). | explicit (Z) / guess (S, clocks) |
| Memory EX swaps in its read's first tail clock: the read word goes to the register, the register's old value to the write-data latch; the W sends the latch to the read's address. EXB's read is a word cycle, its write a byte. | Vector pins (B/W) for the cycle widths; the rest model only, as the read-modify-write row above. | guess |
| LDA and LDAR take the address the operand path forms (the adder, the base or index latch, the address word) and write it in the program's last clock; segmented, the segment word (segment in bits 14:8) in the second last clock and the offset in the last. | Model only; programs F1+4 · Fn+2 · I3 (RA, BA, BX), F1+4 · Fa+2 (DA, X; Fa+3 and Fn segmented). | guess |
| Multiply/divide zero and overflow paths, the register shift count, the block count, MULTL extra adds, MREQ's handshake and HALT's exit are tied off. | Held at the values the sequencer used before; no datapath source yet. | guess |
| A PUSH whose source is the stack pointer's offset register (R15; R15 of RR14 segmented) pushes the decremented value. | Mar81 TM PUSH (PDF p.165, printed 6-112): "The contents of the destination register (a stack pointer) are decremented ... Then the source operand is loaded". | interpretation |
| A CALL through or indexed by R15 (RR14 segmented) branches to the value before its push. | Mar81 TM CALL (PDF p.71, printed 6-18) orders SP ← SP - 2 (4 segmented); @SP ← PC; PC ← dst. Read as dst evaluated before the push; matches the model. | interpretation |
| A segmented push, pop, call or return writes only R15; R14 is left as it is. The model rewrites R14 as seg<<8 on each step, so they differ only when R14 is malformed. | Jan83 TM Figure 3-3 (PDF p.36): a segmented address in a register pair has bit 15 and bits 7-0 of the segment word 0. | interpretation |
| LDCTL moves a control register word in the program's last clock (F1+4). LDCTL FCW,Rs loads FCW bits 15:11 and 7:2 in the second last, so the next fetch has the new N/S; bits 10:8 and 1:0 are reserved and keep their value. A change of S/N swaps R15 with the NSP offset in that clock and, on a Z8001, R14 with the NSP segment in the last clock, whatever SEG. Tail 1 decodes w0's direction and control register number, tail 2 reads Rs or the control register onto the ALU path; here both are combinational from the held w0 and the register ports, so those clocks add no logic. | Mask: Mar81 TM PDF p.123 (6-70). Banking: PDF p.23 (2.6), the Z8001 has a two-word stack pointer per mode (R14'/R15' or R14/R15). Clocks: RTL choice; N/S of the next IF1 in the vectors. | explicit (mask) / interpretation (banking) / guess (clocks) |
| On a Z8001, R14 is banked with R15 in every mode, so any S/N change swaps both, whatever SEG. Another emulator swaps R14 only when segmented; the model followed it until this change. | For: Mar81 TM PDF p.23 (2.6), a two-word stack pointer per mode (R14'/R15' or R14/R15). Against: PDF p.124 (6-71), "In segmented mode, the NSPSEG register is the normal mode R14". Chosen because 2.6 is the architecture statement and p.124 names the LDCTL register. | interpretation |
| LDCTL reads the PSAP segment as 0sssssss 00000000 and control registers 0 and 1 as zero; a Z8002 still holds the PSAP and NSP segment words. LDCTL is not yet trapped in normal mode. | Field: Mar81 TM PDF p.124 (6-71), PSAPSEG(8:14). Zero fill and registers 0 and 1: model only. | explicit (field) / guess (fill) |
| LDPS reads FCW then PC (segmented: from the address + 2, then the PC segment word and offset; a Z8001 nonsegmented keeps its PC segment); IRET pops the identifier, FCW and PC the same way from R15 (RR14), stack status, + 2 per pop. The read FCW is held until the edge opening the program's last clock, which loads FCW and PC (the last word from the read latch, or straight from the read as it is taken) and does LDCTL FCW's swaps (R15 then, R14 in the last clock). | Layout per mode, PC segment: Mar81 TM PDF p.139 (6-86). Pop order, SP + 4 / + 6: PDF p.112 (6-59), which leaves Z8001 nonsegmented IRET undefined. Clocks: RTL choice. | explicit (layout, order) / guess (clocks) |
| LDPS reads with data status whatever its pointer. Its X index is read on port B before the first read and held, + 2 when segmented, so the first address takes one add. LDPS and IRET are not yet trapped in normal mode. | Status: model only. Index: RTL choice. | guess |
| LDM's address is formed once, as for a word operand, and each later word goes to the previous address + 2 (the segment takes no carry), so loading the pointer register does not move the block. Registers run from w1[11:8] modulo 16 (R0 follows R15); every cycle has data status. A store's register is read on port B as its cycle is requested; a load's word is written the clock after its T3. | Wrap: Mar81 TM PDF p.137 (6-84). The rest: model only. | explicit (wrap) / guess |
| Translate per byte: read the string byte at @Rd (w0[7:4]), read the table at Rs (w1[7:4]) + that byte (offset add, no segment carry), then write the translated byte back to @Rd's old address (TR) or run the internal operation (TRT); every cycle data status. Per-clock work: Translate clocks below. | Fields: Mar81 TM PDF p.205 (6-152), p.214 (6-161); the Coherent assembler encodes `trib (rr4),(rr6),r3` as B840 0360. Order, V, TRT Z, TR Z undefined: PDF p.205, p.209 (6-156). A nonrepeating TR's Z tests the whole table word, as the model does. Clocks: guess. | explicit (fields, order, flags) / guess (clocks) |
| A new FCW from LDCTL, LDPS or IRET takes effect at the next instruction: the instruction's own cycles keep the old status, and the FCW loads no later than the edge opening the next IF1. | Mar81 TM PDF p.139 (6-86), p.112 (6-59). | explicit |

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
| I4 c3 | end-of-instruction sampling point | no interrupts yet; the between-element exit is not wired |
| I4 c4 | next IF1 address set-up | the fetch unit's PC |

TR leaves RH1 as it is: the manual makes it undefined and the model does not touch it.
