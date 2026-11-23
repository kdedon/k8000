// z8000_sequencer -- CPU control: the reset sequence, then instruction flow.
//
// After /RESET rises the CPU waits two clocks; the third edge opens T1 of
// the first Program Status Area read. The reads run back to back with
// ST=1100 in system mode and segment 0: FCW from 0002, then the PC (Z8001:
// segment word from 0004 and offset from 0006; Z8002: 0004). Each read's
// data is loaded at its T3 edge.
//
// Then every instruction runs its machine-cycle program from the program
// ROM: the IF1, whose word selects the program, then each further cycle in
// order. The bus unit times a cycle (transaction and tail, or internal
// operation); this unit says what the next cycle is and, during a
// transaction's T3 clock, how long its tail is. The next IF1 follows the
// program's last cycle. Words are taken at their T3 edge: the first into
// the instruction register, address words into the address register,
// others into words 1 and 2. In segmented mode a long address word (bit 15
// set) moves the program to its SL column at that edge.
//
// A trap replaces the next IF1 with the entry program: the aborted IF1
// (the fetch at the PC, its word ignored), the status pushes and the
// Program Status Area reads, all from the trapping instruction's word,
// which is the identifier pushed. SC traps after its program; a
// privileged instruction in normal mode, or an EPU instruction with FCW
// EPA clear, after its IF1 machine cycle, its work suppressed. The execute unit runs the entry's cycles.
//
// An interrupt sampled at the instruction's last cycle (its T3, or the
// third clock of an internal operation) runs the external entry program
// at the boundary: the aborted IF1, the acknowledge, whose word is the
// identifier pushed, then the pushes and reads as a trap's. A Vectored
// Interrupt reads its PC from the identifier's entry of the PSA table. A
// repeat form samples at the last cycle of an element another follows;
// a request then ends the instruction there, the PC stepped back to its
// first word (the repeat forms are two words) for the aborted IF1 and
// the push.
//
// On a Z8003/Z8004 an /ABORT sampled in a memory transaction of the
// instruction ends it as that cycle's T3 ends, with no tail: the read word
// is dropped, the instruction's work stops, and the next IF1 or an entry
// for a request sampled at that T3 follows. A word fetched counts as taken.
//
// Refresh goes in between whole machine cycles, after an IF1 (aborted
// too), an internal operation or a block element, at most once per gap.
// Refreshes skipped while the bus was granted or waited go after any
// cycle, back to back.
// STOP Low before an IF1, or an EPU instruction's second word, runs
// refreshes after its T3 until STOP is High again.
//
// The datapath picks a program's path and says whether its repeated part
// runs again (`more`). The first word's condition (`cc_met`, for the word
// as of the next edge) picks the taken or not-taken program at the IF1's
// T3 edge; a multiplier picks its path on the edge it is taken
// (`md_take`). A unit-ended internal cycle (IU) repeats while `more`, or
// until the serial unit's last cycle, which ends the program from any
// internal cycle (`unit_last`).
//
// The execute unit is told the IF1's T3 clock (the first with the word
// decoded), and the program's last clock and the one before, a clock
// ahead, as flops.
//
// Requests are a function of state; `bus_cyc_end` and `bus_done` arrive
// combinationally and are acted on at the same edge.

`default_nettype none

module z8000_sequencer
  import z8000_zbus_pkg::*, z8000_ctrl_pkg::*, z8000_mc_pkg::*;
#(
  parameter bit SEGMENTED = 1
) (
  input  logic        clk,
  input  logic        clk_en,   // CLK rising edge seen this clock
  input  logic        reset_n,

  // architectural state
  input  logic        fcw_sys,     // FCW bit 14: system mode
  input  logic        fcw_seg,     // FCW bit 15: segmented mode
  input  logic [22:0] pc,
  output logic        fcw_we,
  output logic [15:0] fcw_d,
  output logic        pc_we,
  output logic [22:0] pc_d,
  output logic        pc_seg_ld,   // pc_d takes the PC segment word (rdata bit 15 kept)
  output logic        halted,

  // decoder: fed the words as of the next edge, its result registered
  output logic [15:0] dec_w0,
  output logic [3:0]  dec_w1_lo,
  input  logic        dec_valid,
  input  logic [4:0]  dec_exec,
  input  logic        dec_blk,      // a block or translate class
  input  logic        trap_if1,     // the IF1 word taken on this edge traps
  input  logic        trap_epa,     // ... as an EPU instruction with FCW EPA clear
  input  logic        abt_hit,      // /ABORT Low at a sample of this cycle
  output logic        kill_nx,      // the word's work is suppressed as of the next edge
  output logic        exc,          // the entry program runs
  output logic        af_done,      // the aborted IF1's T3 opens on this edge
  output logic [4:0]  exc_vec,      // the entry's PSA offset, nonsegmented bytes
  output logic [15:0] exc_id,       // the identifier pushed
  output logic [8:0]  exc_pcoff,    // added to the PSA PC entry's address

  // interrupts
  input  logic        irq,          // an entry starts at this boundary
  input  logic        irq_now,      // an enabled request as of the sample on this edge
  input  logic [3:0]  irq_st,
  output logic        smp_end,      // the instruction's sample is on this edge
  output logic        smp_elem,     // a between-element sample is on this edge
  output logic        smp_iop,      // an internal operation's third clock opens
  output logic        irq_take,     // an external entry starts on this edge
  output logic        bound,        // an instruction boundary is on this edge

  // datapath decisions
  input  logic        cc_met,
  input  logic        md_take,
  input  logic        md_zero,      // a memory or immediate operand arrives as zero
  input  mc_path_e    md_path,
  input  logic        more,
  input  logic        unit_last,    // the serial unit's internal cycle in flight is its last
  input  logic        bus_iop,      // the bus is in an internal operation
  input  logic        bus_away,     // the bus is granted, or given up as this clock ends
  output logic [4:0]  iter,         // repetitions started

  // execute unit
  input  logic        io_write,     // the instruction's I/O or EPU transfer cycle is a write
  output logic        ex_first,     // the IF1's T3 clock: the word decoded
  output logic        ex_word,      // the IF1's word is taken on this edge
  output logic        ex_last2,     // the program's second last clock
  output logic        ex_last,      // the program's last clock
  output logic        ex_last2_nx,  // ex_last2 and ex_last as of the next edge
  output logic        ex_last_nx,
  output logic        ex_to_last,   // the next edge opens the last clock
  output logic [15:0] ir_w0,        // instruction words 0, 1 and 2
  output logic [15:0] ir_w1,
  output logic [15:0] ir_w2,
  output logic [22:0] ir_ea,        // the instruction's address: segment, offset
  output logic        ir_ea_long,   // ... from a long address (segment word bit 15)
  input  logic [22:0] mem_addr,     // operand cycle address and status
  input  logic [3:0]  mem_st,
  output logic        mem_take,     // an operand cycle is taken on this edge
  output logic        int_take,     // an internal operation is taken on this edge
  output logic        opnd_take,    // a read operand is in on this edge
  output logic        imm_take,     // an Fn word is in on this edge
  output logic        imm_in,       // ... and the cycle is not aborted
  output logic        in_rf,        // a refresh is in flight
  output logic        rf_due,       // the cycle in flight is followed by a refresh

  // refresh
  input  logic        rf_pending,
  input  logic        rf_now,      // ... one skipped: after any cycle, back to back
  input  logic [22:0] rf_addr,
  output logic        rf_take,     // a refresh starts on this edge
  output logic        rf_keep,     // ... a STOP refresh, leaving the prescaler's pending
  input  logic        stop_n,

  // bus unit
  output logic        bus_req,
  output logic        bus_internal,
  output logic [22:0] bus_addr,
  output logic [3:0]  bus_st,
  output logic        bus_normal,
  output logic        bus_mem,      // the request is an operand cycle
  output logic        bus_nodata,   // the transaction takes no data
  output logic        bus_write,
  output logic [3:0]  bus_len,
  output logic        bus_unit,     // the internal operation is ended by the serial unit
  output logic [2:0]  bus_tail,
  output logic        bus_pc,       // the request is at the PC
  input  logic        bus_cyc_end,
  input  logic        bus_cyc_end3,
  input  logic        bus_done,
  input  logic [15:0] bus_rdata
);

  typedef enum logic [2:0] {
    SEQ_RESET,      // clocks after /RESET rises
    SEQ_PSA_REQ,    // request the next PSA read
    SEQ_PSA_WAIT,   // read in flight
    SEQ_FETCH,      // request the first IF1
    SEQ_IF1,        // IF1 in flight, its word not yet in
    SEQ_PROG        // the instruction's program runs
  } seq_state_e;

  typedef enum logic [1:0] {
    PSA_FCW,
    PSA_PC_SEG,
    PSA_PC_OFF
  } psa_word_e;

  seq_state_e  state_q, state_d;
  psa_word_e   word_q, word_d;
  logic        wait_q, wait_d;       // second clock after /RESET rises
  logic [15:0] ir0_q, ir0_d, ir1_q, ir1_d, ir2_q, ir2_d;  // instruction words
  logic [1:0]  nwords_q, nwords_d;   // instruction words in, address words aside
  logic [22:0] ea_q, ea_d;           // instruction address
  mc_col_e     col_q, col_d;
  logic [MC_POS_W-1:0]  pos_q;       // program position of the cycle in flight
  logic [MC_REPS_W-1:0] rep_q;       // its repetitions before this one
  logic [4:0]  iter_q;               // repetitions of the repeated part started
  mc_path_e    path_q, path_d;
  logic        in_rf_q;              // the cycle in flight is a refresh
  logic        rf_ok_q;              // a refresh may follow the cycle in flight
  logic        stop_q, stp_t1_q;     // STOP as of the last edge; a STOP sample's T1 clock
  logic        stop_go_q;            // a STOP refresh follows the cycle in flight
  logic        stop_rf_q;            // the refresh in flight is a STOP refresh
  logic        prog_on;
  logic        trap_q, exc_q;        // a trap after the IF1; the entry runs
  logic [4:0]  vec_q;
  // Program Status Area entries, as nonsegmented byte offsets.
  localparam logic [4:0] PSA_EPA = 5'h04, PSA_PRIV = 5'h08, PSA_SC = 5'h0C, PSA_SEGT = 5'h10,
                         PSA_NMI = 5'h14, PSA_NVI = 5'h18, PSA_VI = 5'h1C;
  logic [8:0]  poff_q;
  logic        ext_q;                // the entry is for an interrupt
  logic        eirq_q;               // a request ends the repeat at this element
  logic        abt_q;                // an abort ends the instruction at this cycle
  logic        epa_q;                // the trap is the extended-instruction trap
  logic [3:0]  ia_st_q;
  logic [15:0] ia_q;                 // the acknowledge word
  logic        i1_q, i2_q;           // an internal operation's second and third clocks
  logic        take_af, trap_go;

  // ---- program ROM ------------------------------------------------------------------
  logic [MC_FORM_W-1:0] form_s;
  logic [MC_PROG_W-1:0] prog_d, prog_q, prog_s, prog_m;
  logic [MC_POS_W-1:0]  npos;
  mc_cycle_t            cur_q, cur_d, cur_s, nxt;
  mc_link_t             link_q, link_d, link_s;

  // The program and its entry at the position in flight (cycle and link)
  // are registered. The program changes as a word arrives (`_s`, looked up
  // as if the word in flight is in; bus_done picks after the ROMs) or as a
  // multiply takes its path (`_m`). A zero operand from the bus also
  // steers the in-flight lookup, as its cycle's tail may differ on the
  // zero path; the other paths share the arriving cycle.
  logic [15:0] w0_s;
  logic [3:0]  w1_s;
  mc_col_e     col_s;
  mc_path_e    path_s;
  always_comb begin
    w0_s   = ir0_q;
    w1_s   = ir1_q[3:0];
    col_s  = col_q;
    path_s = path_q;
    if (state_q == SEQ_IF1) begin
      w0_s   = bus_rdata;
      w1_s   = 4'h0;
      col_s  = (SEGMENTED && fcw_seg) ? MC_COL_SS : MC_COL_NS;
      path_s = cc_met ? MC_PATH_DEFAULT : MC_PATH_NOT_TAKEN;
    end else if (prog_on && cur_q.kind == MC_FN && nwords_q == 2'd1) begin
      w1_s   = bus_rdata[3:0];
    end else if (prog_on && cur_q.kind == MC_FA && col_q == MC_COL_SS && bus_rdata[15]) begin
      col_s  = MC_COL_SL;
    end
    if (md_zero) path_s = MC_PATH_ZERO;
  end

  z8000_mc_index_gen u_index_s(.w0(w0_s), .w1_lo(w1_s), .form(form_s));
  z8000_mc_prog_gen  u_prog_s (.form(form_s), .col(col_s), .path(path_s), .prog(prog_s));
  z8000_mc_cycle_gen u_cur_s  (.prog(prog_s), .pos(pos_q), .cyc(cur_s));
  z8000_mc_link_gen  u_link_s (.prog(prog_s), .pos(pos_q), .link(link_s));
  z8000_mc_prog_gen  u_prog_m (.form(form_s), .col(col_s), .path(md_path), .prog(prog_m));
  // The entry program: one per part, the words not looked at.
  // An interrupt's adds the acknowledge.
  localparam logic [MC_PROG_W-1:0] EXC_PROG = MC_PROG_W'(SEGMENTED ? MC_PROG_TRAP_SEG : MC_PROG_TRAP_NS);
  localparam logic [MC_PROG_W-1:0] INT_PROG = MC_PROG_W'(SEGMENTED ? MC_PROG_INT_SEG : MC_PROG_INT_NS);
  mc_cycle_t af_cyc, cur_next;
  mc_link_t  af_link_t, af_link_i, link_next;
  logic [2:0] tail_q;
  z8000_mc_cycle_gen u_af     (.prog(EXC_PROG), .pos(MC_POS_W'(0)), .cyc(af_cyc));
  z8000_mc_link_gen  u_af_t   (.prog(EXC_PROG), .pos(MC_POS_W'(0)), .link(af_link_t));
  z8000_mc_link_gen  u_af_i   (.prog(INT_PROG), .pos(MC_POS_W'(0)), .link(af_link_i));
  logic exc_d, ext_d;
  assign ext_d  = take_af ? !trap_go : ext_q;
  assign prog_d = exc_d ? (ext_d ? INT_PROG : EXC_PROG) : md_take ? prog_m : bus_done ? prog_s : prog_q;
  // An entry's program holds, and so does its entry at the position.
  assign cur_d  = bus_done && !exc_q ? cur_s  : cur_q;
  assign link_d = bus_done && !exc_q ? link_s : link_q;
  // The next entry: at the position a finished repetition count moves
  // to, else the one in flight.
  mc_cycle_t           cyc_step;
  mc_link_t            link_step;
  logic                rep_end;
  logic [MC_POS_W-1:0] pos_step;
  assign pos_step = more ? link_q.next_more : link_q.next_done;
  z8000_mc_cycle_gen u_nxt_s  (.prog(prog_q), .pos(pos_step), .cyc(cyc_step));
  z8000_mc_link_gen  u_lnk_s  (.prog(prog_q), .pos(pos_step), .link(link_step));
  assign nxt = rep_end ? cyc_step : cur_q;

  // ---- program position ---------------------------------------------------------------
  // The serial unit's last internal cycle ends the program: a unit-ended
  // cycle repeats until it. Through a refresh or bus hold after an
  // internal cycle the unit already stands in the next, so its last is
  // taken while the cycle is in flight and held to the next IF1.
  logic at_last, u_end, u_end_d, u_ended_q;
  assign u_end   = u_ended_q || (unit_last && bus_iop);
  assign u_end_d = u_ended_q || (unit_last && prog_on && (cur_d.kind == MC_I || cur_d.kind == MC_IU));
  assign rep_end = rep_q + MC_REPS_W'(1) == link_q.reps;
  assign at_last = trap_q || eirq_q || abt_q || u_end || (rep_end && (more ? link_q.fin_more : link_q.fin_done));
  assign npos    = !rep_end ? pos_q : pos_step;

  // A program cycle is in flight.
  assign prog_on = state_q == SEQ_PROG && !in_rf_q;

  // A clock ahead. No cycle starts on an edge two clocks or less before a
  // cycle's end, so position and repetition hold; the program may change
  // with a word or path taken on this edge. `more` holds through a cycle:
  // with no repetition started it asks for the first, while word 1 may
  // still change; no program's first entry ends differently by it. Last
  // follows last2 except after a T3 clock with no tail.
  logic at_last_d, cyc_on, end_on, last_q, last2_q, last_d, last2_d;
  assign at_last_d = u_end_d || (rep_q + MC_REPS_W'(1) == link_d.reps &&
                                 (more ? link_d.fin_more : link_d.fin_done));
  // The last refresh of a STOP stream carries the IF1's tail.
  assign cyc_on    = (state_q == SEQ_PROG && (!in_rf_q || (stop_rf_q && !stop_go_q))) ||
                     state_q == SEQ_IF1;
  // A cycle STOP holds ends its program after the stream, not at its T3.
  assign end_on    = cyc_on && !stop_go_q;

  assign last_d  = last2_q || (end_on && at_last_d && bus_done &&
                               cur_d.clocks == MC_CLOCKS_W'(0));
  assign last2_d = end_on && at_last_d &&
                   (bus_cyc_end3 || (bus_done && cur_d.clocks == MC_CLOCKS_W'(1)));

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      last_q  <= 1'b0;
      last2_q <= 1'b0;
    end else if (clk_en) begin
      last_q  <= last_d;
      last2_q <= last2_d;
    end
  end

  // An aborted instruction has no last clocks.
  assign ex_last  = last_q && !abt_q;
  assign ex_last2 = last2_q && !abt_q;
  assign ex_last_nx  = last_d;
  assign ex_last2_nx = last2_d;
  // As last's next value, from the registered program: no branch or stack
  // program ends on its IF1 or as a word arrives.
  assign ex_to_last = !abt_q && (last2_q || (end_on && state_q == SEQ_PROG && at_last && bus_done &&
                                             cur_q.clocks == MC_CLOCKS_W'(0)));

  // ---- next machine cycle -------------------------------------------------------------
  typedef enum logic [3:0] {
    NEXT_NONE,
    NEXT_PSA,
    NEXT_REFRESH,
    NEXT_IF1,
    NEXT_AF,        // the aborted IF1 opening a trap entry
    NEXT_FETCH,     // a later instruction word
    NEXT_INTERNAL,
    NEXT_MEM,       // an operand read or write
    NEXT_ACK        // the interrupt acknowledge
  } next_e;

  // The bus unit reads the request's data only with req, so the data mux
  // stays off the decode path.
  next_e next;
  logic  exc_go, rf_go;
  assign rf_go   = (rf_ok_q || rf_now) && rf_pending;
  assign trap_go = trap_q || (!exc_q && dec_valid && dec_exec == CLS_SYS_CALL);
  assign exc_go  = trap_go || irq || eirq_q;
  always_comb begin
    next = NEXT_NONE;
    unique case (state_q)
      SEQ_PSA_REQ: next = NEXT_PSA;
      // The first IF1 is asked for during the last read, for its early SN.
      SEQ_PSA_WAIT: if (word_q == PSA_PC_OFF) next = NEXT_IF1;
      SEQ_FETCH:   next = NEXT_IF1;
      SEQ_PROG: begin
        if (rf_go || stop_go_q)     next = NEXT_REFRESH;
        else if (at_last)           next = exc_go ? NEXT_AF : NEXT_IF1;
        else if (nxt.kind == MC_FN || nxt.kind == MC_FA) next = NEXT_FETCH;
        else if (nxt.kind == MC_I || nxt.kind == MC_IU) next = NEXT_INTERNAL;
        else if (nxt.kind == MC_R || nxt.kind == MC_W || nxt.kind == MC_IO || nxt.kind == MC_EPU)
                                    next = NEXT_MEM;
        else if (nxt.kind == MC_IA) next = NEXT_ACK;
      end
      default: ;
    endcase
  end

  // ---- PSA word address -----------------------------------------------------
  // Always segment 0, even once the loaded FCW selects nonsegmented mode.
  // The reset entry: FCW at 0002, the PC (segment word then offset on a
  // Z8001) after it.
  localparam logic [15:0] RST_FCW = 16'h0002, RST_PC_SEG = 16'h0004,
                          RST_PC_OFF = SEGMENTED ? 16'h0006 : 16'h0004;
  logic [15:0] psa_off;
  always_comb begin
    unique case (word_q)
      PSA_FCW:    psa_off = RST_FCW;
      PSA_PC_SEG: psa_off = RST_PC_SEG;
      PSA_PC_OFF: psa_off = RST_PC_OFF;
      default:    psa_off = RST_FCW;
    endcase
  end

  always_comb begin
    bus_req      = next != NEXT_NONE;
    bus_internal = next == NEXT_INTERNAL;
    bus_addr     = pc;
    bus_st       = ST_PROG_SPACE;
    bus_len      = nxt.clocks;
    bus_unit     = nxt.kind == MC_IU;
    unique case (next)
      NEXT_PSA:      bus_addr = {7'd0, psa_off};
      NEXT_REFRESH: begin
        bus_addr = rf_addr;
        bus_st   = ST_REFRESH;
      end
      NEXT_IF1, NEXT_AF: bus_st = ST_INSTR_FETCH_FIRST;
      NEXT_INTERNAL: bus_st   = ST_INTERNAL_OP;
      NEXT_MEM: begin
        bus_addr = mem_addr;
        bus_st   = mem_st;
      end
      NEXT_ACK: begin
        bus_addr = 23'd0;
        bus_st   = ia_st_q;
      end
      default: ;
    endcase
  end

  assign bus_mem    = next == NEXT_MEM;
  assign bus_pc     = next == NEXT_IF1 || next == NEXT_AF || next == NEXT_FETCH;
  assign bus_nodata = next == NEXT_AF;
  assign bus_write = bus_mem && (nxt.kind == MC_W || ((nxt.kind == MC_IO || nxt.kind == MC_EPU) && io_write));

  // The reset reads run in system mode whatever FCW they load.
  assign bus_normal = state_q != SEQ_PSA_REQ && !fcw_sys;

  // A transaction's tail, read by the bus unit in its T3 clock; registered
  // from the next cycle. The acknowledge's T4 and T5, which take the
  // identifier, are its tail.
  assign bus_tail = tail_q;

  logic take, take_rf, take_if1, take_prog;
  assign take      = bus_req && bus_cyc_end;
  assign take_rf   = take && next == NEXT_REFRESH;
  assign take_if1  = take && next == NEXT_IF1;
  assign take_af   = take && next == NEXT_AF;
  assign take_prog = take && (next == NEXT_FETCH || next == NEXT_INTERNAL || next == NEXT_MEM || next == NEXT_ACK);
  assign mem_take  = take && next == NEXT_MEM;
  assign int_take  = take && next == NEXT_INTERNAL;
  assign opnd_take = prog_on && bus_done && !abt_q && (cur_q.kind == MC_R ||
                     ((cur_q.kind == MC_IO || cur_q.kind == MC_EPU) && !io_write));
  assign rf_take   = take_rf;
  assign rf_keep   = stop_go_q;

  // A repetition of the repeated part starts on this edge.
  logic rep_start;
  assign rep_start = take_prog && rep_end && more && link_q.next_more != link_q.next_done;

  // ---- state ------------------------------------------------------------------
  logic psa_last;
  assign psa_last = state_q == SEQ_PSA_WAIT && bus_done && word_q == PSA_PC_OFF;

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      SEQ_RESET:    if (wait_q)   state_d = SEQ_PSA_REQ;
      SEQ_PSA_REQ:  if (take)     state_d = SEQ_PSA_WAIT;
      SEQ_PSA_WAIT: if (bus_done) state_d = (word_q == PSA_PC_OFF) ? SEQ_FETCH : SEQ_PSA_REQ;
      SEQ_FETCH:    if (take)     state_d = SEQ_IF1;
      SEQ_IF1:      if (bus_done) state_d = SEQ_PROG;
      SEQ_PROG:     if (take_if1) state_d = SEQ_IF1;
      default:      state_d = SEQ_RESET;
    endcase
  end

  // Reset sequence.
  always_comb begin
    wait_d = wait_q || state_q == SEQ_RESET;
    word_d = word_q;
    if (state_q == SEQ_PSA_WAIT && bus_done) begin
      unique case (word_q)
        PSA_FCW:    word_d = SEGMENTED ? PSA_PC_SEG : PSA_PC_OFF;
        PSA_PC_SEG: word_d = PSA_PC_OFF;
        default:    ;
      endcase
    end
  end

  // Instruction words in on this edge.
  logic word_if1, word_more, word_addr;
  assign word_if1  = state_q == SEQ_IF1 && bus_done;
  assign word_more = prog_on && bus_done && (cur_q.kind == MC_FN || cur_q.kind == MC_FA);
  assign imm_take  = word_more && cur_q.kind == MC_FN;
  assign imm_in    = imm_take && !abt_q;
  assign word_addr = word_more && cur_q.kind == MC_FA;

  // FCW and PC writes: the PSA loads, then +2 per instruction word taken.
  always_comb begin
    fcw_we = state_q == SEQ_PSA_WAIT && bus_done && word_q == PSA_FCW;
    fcw_d  = bus_rdata;
    pc_we  = 1'b0;
    pc_d   = pc;
    pc_seg_ld = 1'b0;
    if (state_q == SEQ_PSA_WAIT && bus_done && word_q == PSA_PC_SEG) begin
      pc_we = 1'b1;
      pc_seg_ld = 1'b1;
      pc_d  = {bus_rdata[14:8], 16'h0000};
    end else if (psa_last) begin
      pc_we = 1'b1;
      pc_d  = SEGMENTED ? {pc[22:16], bus_rdata} : {7'd0, bus_rdata};
    end else if ((smp_elem && irq_now) || word_if1 || word_more) begin
      // An interrupted element backs the PC up to its instruction.
      pc_we = 1'b1;
      pc_d  = {pc[22:16], pc[15:0] + (smp_elem && irq_now ? 16'hFFFC : 16'h0002)};
    end
  end

  // Column: segmented mode starts on SS; a long address word moves to SL.
  always_comb begin
    col_d = col_q;
    if (word_if1)
      col_d = (SEGMENTED && fcw_seg) ? MC_COL_SS : MC_COL_NS;
    else if (word_more && cur_q.kind == MC_FA && col_q == MC_COL_SS && bus_rdata[15])
      col_d = MC_COL_SL;
  end

  // ---- registers --------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q <= SEQ_RESET;
      word_q  <= PSA_FCW;
      wait_q  <= 1'b0;
      col_q   <= MC_COL_NS;
    end else if (clk_en) begin
      state_q <= state_d;
      word_q  <= word_d;
      wait_q  <= wait_d;
      col_q   <= col_d;
    end
  end

  // Instruction words; word 1 reads 0 until it is in.
  always_comb begin
    ir0_d    = ir0_q;
    ir1_d    = ir1_q;
    ir2_d    = ir2_q;
    nwords_d = nwords_q;
    if (word_if1) begin
      ir0_d    = bus_rdata;
      ir1_d    = 16'h0000;
      ir2_d    = 16'h0000;
      nwords_d = 2'd1;
    end else if (word_more && !word_addr) begin
      if (nwords_q == 2'd1) ir1_d = bus_rdata;
      if (nwords_q == 2'd2) ir2_d = bus_rdata;
      if (nwords_q != 2'd3) nwords_d = nwords_q + 2'd1;
    end
  end

  always_comb begin
    path_d = path_q;
    if (word_if1)     path_d = cc_met ? MC_PATH_DEFAULT : MC_PATH_NOT_TAKEN;
    else if (md_take) path_d = md_path;
  end

  // Address words: nonsegmented, the address in the PC's segment; segmented,
  // the segment word (with a short offset in its low byte), then a long offset.
  // Nonsegmented, the segment follows the PC before the word too, so the
  // SN sent out ahead of its read is right.
  always_comb begin
    ea_d = ea_q;
    if (word_addr) begin
      unique case (col_q)
        MC_COL_SS: ea_d = {bus_rdata[14:8], 8'h00, bus_rdata[7:0]};
        MC_COL_SL: ea_d = {ea_q[22:16], bus_rdata};
        default:   ea_d = {SEGMENTED ? pc[22:16] : 7'd0, bus_rdata};
      endcase
    end else if (col_q == MC_COL_NS) begin
      ea_d[22:16] = SEGMENTED ? pc[22:16] : 7'd0;
    end
  end

  // The trap and the entry. Execute ignores the words from the trapping
  // IF1 to the next IF1.
  logic trap_d;
  assign trap_d  = word_if1 ? trap_if1 && !abt_q : trap_q && !take_af;
  assign exc_d   = take_af || (exc_q && !take_if1);
  // The clock after the aborted IF1 is taken still sees SC's own decode,
  // which does nothing there; the kill stays off the take path.
  assign kill_nx = (word_if1 ? trap_if1 : trap_q) || exc_q || abt_q;
  assign af_done = prog_on && bus_done && cur_q.kind == MC_AF;
  logic ia_done;
  assign ia_done = prog_on && bus_done && cur_q.kind == MC_IA;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      trap_q  <= 1'b0;
      exc_q   <= 1'b0;
      vec_q   <= 5'd0;
      ext_q   <= 1'b0;
      eirq_q  <= 1'b0;
      abt_q   <= 1'b0;
      epa_q   <= 1'b0;
      ia_st_q <= ST_NVI_ACK;
      ia_q    <= 16'h0000;
      poff_q  <= 9'd0;
      i1_q    <= 1'b0;
      i2_q    <= 1'b0;
      u_ended_q <= 1'b0;
    end else if (clk_en) begin
      trap_q <= trap_d;
      exc_q  <= exc_d;
      ext_q  <= ext_d;
      // A trap's PC entry is fixed; only a VI's acknowledge sets an offset.
      if (take_af) begin
        ia_st_q <= irq_st;
        poff_q  <= 9'd0;
        if (trap_q)                  vec_q <= epa_q ? PSA_EPA : PSA_PRIV;
        else if (trap_go)            vec_q <= PSA_SC;
        else if (irq_st == ST_NMI_ACK) vec_q <= PSA_NMI;
        else if (irq_st == ST_SEGMENT_TRAP) vec_q <= PSA_SEGT;
        else if (irq_st == ST_VI_ACK)  vec_q <= PSA_VI;
        else                         vec_q <= PSA_NVI;
      end
      if (ia_done) begin
        ia_q  <= bus_rdata;
        poff_q <= ia_st_q != ST_VI_ACK ? 9'd0 : {bus_rdata[7:0], 1'b0};
      end
      i1_q   <= int_take;
      i2_q   <= i1_q;
      u_ended_q <= !(take_if1 || take_af) && u_end;
      eirq_q <= smp_elem ? irq_now : eirq_q && !take_af;
      if (word_if1) epa_q <= trap_epa;
      if (take_if1 || take_af)
        abt_q <= 1'b0;
      else if (abt_hit && (state_q == SEQ_IF1 || prog_on) && !exc_q)
        abt_q <= 1'b1;
    end
  end
  assign exc       = exc_q;
  assign exc_vec   = vec_q;
  assign exc_id    = ext_q ? ia_q : ir0_q;
  assign exc_pcoff = poff_q;
  assign irq_take  = take_af && !trap_go;
  assign bound     = take_if1 || take_af;

  // Interrupt samples. An entry samples at its end, so a request its new
  // FCW enables follows at once; none in an instruction that traps after
  // its IF1.
  // A block element ends here (its repeated part's last cycle).
  logic smp_ok, elem_end;
  assign smp_ok   = !trap_q;
  assign elem_end = prog_on && dec_valid && dec_blk && (bus_done || i2_q) &&
                    rep_end && link_q.next_more <= pos_q;
  assign smp_iop  = prog_on && i2_q;
  assign smp_end  = smp_ok && ((cyc_on && bus_done && (at_last_d || abt_q)) || (smp_iop && at_last));
  assign smp_elem = smp_ok && elem_end && more;

  logic first_q;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) first_q <= 1'b0;
    else if (clk_en)          first_q <= word_if1;
  end
  assign ex_first = first_q;
  assign ex_word  = word_if1;

  assign cur_next  = take_af ? af_cyc : take_prog ? nxt : cur_d;
  assign link_next = take_af ? (trap_go ? af_link_t : af_link_i) :
                     take_prog ? (rep_end ? link_step : link_q) : link_d;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ir0_q    <= 16'h0000;
      ir1_q    <= 16'h0000;
      ir2_q    <= 16'h0000;
      nwords_q <= 2'd0;
      ea_q     <= 23'd0;
      path_q   <= MC_PATH_DEFAULT;
      prog_q   <= MC_PROG_W'(0);
      cur_q    <= mc_cycle_t'(0);
      link_q   <= mc_link_t'(0);
      tail_q   <= 3'd0;
    end else if (clk_en) begin
      ir0_q    <= ir0_d;
      ir1_q    <= ir1_d;
      ir2_q    <= ir2_d;
      nwords_q <= nwords_d;
      ea_q     <= ea_d;
      path_q   <= path_d;
      prog_q   <= prog_d;
      cur_q    <= cur_next;   // stale while an IF1 runs
      link_q   <= link_next;
      // A STOP stream runs the sampled cycle's tail after its last refresh.
      if (stop_go_q || abt_q)
        tail_q <= 3'd0;
      else if (in_rf_q && stop_rf_q)
        tail_q <= cur_q.clocks[2:0];
      else
        tail_q <= (state_d != SEQ_PROG || (take ? take_rf : in_rf_q)) ? 3'd0 :
                  cur_next.kind == MC_IA ? 3'd2 : cur_next.clocks[2:0];
    end
  end

  // Program position: the IF1 is position 0; each cycle taken moves on.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      pos_q <= MC_POS_W'(0);
      rep_q <= MC_REPS_W'(0);
      iter_q <= 5'd0;
    end else if (clk_en) if (take_if1 || take_af) begin
      pos_q <= MC_POS_W'(0);
      rep_q <= MC_REPS_W'(0);
      iter_q <= 5'd0;
    end else if (take_prog) begin
      pos_q <= npos;
      rep_q <= rep_end ? MC_REPS_W'(0) : rep_q + MC_REPS_W'(1);
      if (rep_start && iter_q != 5'd31) iter_q <= iter_q + 5'd1;  // saturates
    end
  end

  // Refresh bookkeeping: allowed after an IF1, aborted IF1 or internal
  // cycle, or a block element not ending the program, once.
  logic elem_rf;
  assign elem_rf = elem_end && !at_last;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      in_rf_q <= 1'b0;
      rf_ok_q <= 1'b0;
    end else if (clk_en) if (take) begin
      in_rf_q <= take_rf;
      rf_ok_q <= take_if1 || take_af || (take_prog && next == NEXT_INTERNAL) ||
                 (take_rf && stop_go_q);
    end else if (elem_rf) begin
      rf_ok_q <= 1'b1;
    end
  end

  // STOP (sampled on each CLK fall, `stop_n`) Low before an IF1's T1, or
  // before an EPU instruction's second word, puts a stream of refreshes
  // after its T3. STOP is sampled again on each T3's fall; once High, one
  // more refresh runs, then the cycle's tail. The T3-fall sample is taken
  // on the edge ending T3 and kept while the bus is away.
  logic stp_take, t3_q, stop_t3_q, stop_t3;
  assign stp_take = take_if1 || (take && next == NEXT_FETCH && nxt.kind == MC_FN &&
                                 nwords_q == 2'd1 && dec_exec == CLS_EPU);
  assign stop_t3  = t3_q ? stop_n : stop_t3_q;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      stop_q    <= 1'b1;
      stp_t1_q  <= 1'b0;
      stop_go_q <= 1'b0;
      stop_rf_q <= 1'b0;
      t3_q      <= 1'b0;
      stop_t3_q <= 1'b1;
    end else if (clk_en) begin
      if (!bus_away) stop_q <= stop_n;
      t3_q      <= bus_done;
      stop_t3_q <= stop_t3;
      stp_t1_q  <= stp_take;
      if (stp_t1_q)
        stop_go_q <= !stop_q;
      else if (take)
        stop_go_q <= take_rf && stop_go_q && !stop_t3;
      if (take)
        stop_rf_q <= take_rf && stop_go_q;
    end
  end

  assign dec_w0    = ir0_d;
  assign dec_w1_lo = ir1_d[3:0];
  assign ir_w0     = ir0_q;
  assign ir_w1     = ir1_q;
  assign ir_w2     = ir2_q;
  assign ir_ea     = ea_q;
  assign ir_ea_long = col_q == MC_COL_SL;
  assign iter      = iter_q;
  assign in_rf     = in_rf_q;
  assign rf_due    = rf_go;
  assign halted    = state_q == SEQ_PROG && dec_exec == CLS_HALT;

  // synthesis translate_off
  // A word's or a path's lookup as it lands matches the one from the
  // next-edge words, an entry's split first cycle matches its program's,
  // and the registered entry is the held program's. Read by the testbench.
  // verilator lint_off UNUSEDSIGNAL
  logic [MC_FORM_W-1:0] form_o;
  logic [MC_PROG_W-1:0] prog_o;
  mc_cycle_t            cur_o, cur_h, cur_e;
  mc_link_t             link_o, link_h, link_e;
  logic                 check_q = 1'b0;
  // verilator lint_on UNUSEDSIGNAL
  z8000_mc_index_gen u_index_o(.w0(ir0_d), .w1_lo(ir1_d[3:0]), .form(form_o));
  z8000_mc_prog_gen  u_prog_o (.form(form_o), .col(col_d), .path(path_d), .prog(prog_o));
  z8000_mc_cycle_gen u_cur_o  (.prog(prog_o), .pos(pos_q), .cyc(cur_o));
  z8000_mc_link_gen  u_link_o (.prog(prog_o), .pos(pos_q), .link(link_o));
  z8000_mc_cycle_gen u_cur_h  (.prog(prog_q), .pos(pos_q), .cyc(cur_h));
  z8000_mc_link_gen  u_link_h (.prog(prog_q), .pos(pos_q), .link(link_h));
  z8000_mc_cycle_gen u_cur_e  (.prog(prog_d), .pos(MC_POS_W'(0)), .cyc(cur_e));
  z8000_mc_link_gen  u_link_e (.prog(prog_d), .pos(MC_POS_W'(0)), .link(link_e));
  always_ff @(posedge clk) if (clk_en) begin
    if (!exc_q && (bus_done || md_take) && (state_q == SEQ_IF1 || prog_on) &&
        (prog_o != prog_d || link_o != link_d || cur_o != cur_d)) begin
      $display("%%Error: %m: split program lookup differs");
      check_q <= 1'b1;
    end
    if (take_af && (cur_e != cur_next || link_e != link_next)) begin
      $display("%%Error: %m: entry program lookup differs");
      check_q <= 1'b1;
    end
    if (prog_on && (cur_h != cur_q || link_h != link_q)) begin
      $display("%%Error: %m: held program entry differs");
      check_q <= 1'b1;
    end
    // A path taken as a cycle starts would start it from the old program.
    if (md_take && take) begin
      $display("%%Error: %m: path taken as a cycle starts");
      check_q <= 1'b1;
    end
  end
  // synthesis translate_on

endmodule

`default_nettype wire
