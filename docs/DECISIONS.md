# Decisions

RTL design choices resting on the model or on inference rather than an explicit source. Machine-cycle timing conflicts are recorded with the Go model's machine-cycle doc. TM: Z8000 CPU Technical Manual (Mar81, Jan83); DB: Zilog 1988 Data Book.

| decision | evidence | tag |
|---|---|---|
| A REFRESH write with RE set reloads the prescaler count; the divide-by-4 phase runs on. /RESET leaves count and phase alone. | Model only. Manual silent: Mar81 TM §8.3 (printed 8-1); 1988 DB (printed 37) says only "presettable prescaler". | guess |
| REFRESH bit 0 is stored as written. | Mar81 TM (printed 6-70): LDCTL loads REFRESH(1:15). Matches the model. | interpretation |
| Z8001 nonsegmented data addresses use the PC's segment. | Jan83 TM 3.4.2 (printed 3-3). | explicit |
| `ad_in` comes straight from a register (the read-data capture). | The decode and program ROM look-ahead uses the whole data-arrival clock. | constraint |
| Multiply/divide zero and overflow paths, the register shift count, the block count, MULTL extra adds, MREQ's handshake and HALT's exit are tied off. | Held at the values the sequencer used before; no datapath source yet. | guess |

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
