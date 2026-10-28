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
// Refresh goes in between whole machine cycles, after an IF1 or an
// internal operation, at most once per gap. Instructions the execute unit
// does not run yet (and HALT in normal mode) stop the sequencer after
// their IF1 machine cycle.
//
// The datapath picks a program's path and says whether its repeated part
// runs again (`more`). The first word's condition (`cc_met`, for the word
// as of the next edge) picks the taken or not-taken program at the IF1's
// T3 edge; a multiply or divide operand picks its path on the edge it is
// taken (`md_take`).
//
// The execute unit is told the program's last clock and the one before,
// a clock ahead, as flops.
//
// Requests are a function of state; `bus_cyc_end` and `bus_done` arrive
// combinationally and are acted on at the same edge.

module z8000_sequencer
  import z8000_zbus_pkg::*, z8000_ctrl_pkg::*, z8000_mc_pkg::*;
#(
  parameter bit SEGMENTED = 1
) (
  input  logic        clk,
  input  logic        reset_n,

  // architectural state
  input  logic        fcw_sys,     // FCW bit 14: system mode
  input  logic        fcw_seg,     // FCW bit 15: segmented mode
  input  logic [31:0] pc,
  output logic        fcw_we,
  output logic [15:0] fcw_d,
  output logic        pc_we,
  output logic [31:0] pc_d,
  output logic        halted,

  // decoder: fed the words as of the next edge, its result registered
  output logic [15:0] dec_w0,
  output logic [3:0]  dec_w1_lo,
  input  logic        dec_valid,
  input  logic [4:0]  dec_exec,

  // datapath decisions
  input  logic        cc_met,
  input  logic        md_take,
  input  mc_path_e    md_path,
  input  logic        more,
  output logic [5:0]  iter,         // repetitions started

  // execute unit
  input  logic        ex_handles,
  output logic        ex_last2,     // the program's second last clock
  output logic        ex_last,      // the program's last clock
  output logic [15:0] ir_w0,        // instruction words 0, 1 and 2
  output logic [15:0] ir_w1,
  output logic [15:0] ir_w2,
  output logic [22:0] ir_ea,        // the instruction's address: segment, offset

  // refresh
  input  logic        rf_pending,
  input  logic [22:0] rf_addr,
  output logic        rf_take,     // a refresh starts on this edge

  // bus unit
  output logic        bus_req,
  output logic        bus_internal,
  output logic [22:0] bus_addr,
  output logic [3:0]  bus_st,
  output logic        bus_normal,
  output logic [3:0]  bus_len,
  output logic [2:0]  bus_tail,
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
    SEQ_PROG,       // the instruction's program runs
    SEQ_STOP        // an instruction not run yet
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
  logic [5:0]  iter_q;               // repetitions of the repeated part started
  mc_path_e    path_q, path_d;
  logic        in_rf_q;              // the cycle in flight is a refresh
  logic        rf_ok_q;              // a refresh may follow the cycle in flight

  // ---- program ROM ------------------------------------------------------------------
  logic [MC_FORM_W-1:0] form;
  logic [MC_PROG_W-1:0] prog_d, prog_q;
  logic [MC_POS_W-1:0]  npos;
  mc_cycle_t            cur_q, cur_d, nxt;
  mc_link_t             link, link_d;

  // The program is looked up from the words as they arrive and held. The
  // cycle in flight is registered; `_d` lookups see a word taken this edge.
  z8000_mc_index_gen u_index  (.w0(ir0_d), .w1_lo(ir1_d[3:0]), .form(form));
  z8000_mc_prog_gen  u_prog   (.form(form), .col(col_d), .path(path_d),
                               .prog(prog_d));
  z8000_mc_cycle_gen u_cur    (.prog(prog_d), .pos(pos_q), .cyc(cur_d));
  z8000_mc_link_gen  u_link   (.prog(prog_q), .pos(pos_q), .link(link));
  z8000_mc_link_gen  u_link_d (.prog(prog_d), .pos(pos_q), .link(link_d));
  z8000_mc_cycle_gen u_nxt    (.prog(prog_q), .pos(npos), .cyc(nxt));

  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{link_d.next_more, link_d.next_done};
  // verilator lint_on UNUSEDSIGNAL

  // ---- program position ---------------------------------------------------------------
  logic rep_end, at_last, run_ok;
  assign rep_end = rep_q + MC_REPS_W'(1) == link.reps;
  assign at_last = rep_end && (more ? link.fin_more : link.fin_done);
  assign npos    = !rep_end ? pos_q : more ? link.next_more : link.next_done;
  assign run_ok  = dec_valid && (ex_handles || (dec_exec == CLS_HALT && fcw_sys));

  // A program cycle is in flight. One starts only with run_ok; a captured
  // word can drop run_ok a clock later, but no bus_done follows before
  // SEQ_STOP.
  logic prog_on;
  assign prog_on = state_q == SEQ_PROG && !in_rf_q;

  // A clock ahead. No cycle starts on an edge two clocks or less before a
  // cycle's end, so position and repetition hold; the program may change
  // with a word or path taken on this edge. `more` holds through a cycle:
  // with no repetition started it asks for the first, while word 1 may
  // still change; no program's first entry ends differently by it. Last
  // follows last2 except after a T3 clock with no tail. Execute ignores an
  // instruction the sequencer stops on.
  logic at_last_d, cyc_on, last_q, last2_q;
  assign at_last_d = rep_q + MC_REPS_W'(1) == link_d.reps &&
                     (more ? link_d.fin_more : link_d.fin_done);
  assign cyc_on    = (state_q == SEQ_PROG && !in_rf_q) || state_q == SEQ_IF1;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      last_q  <= 1'b0;
      last2_q <= 1'b0;
    end else begin
      last_q  <= last2_q || (cyc_on && at_last_d && bus_done &&
                             cur_d.clocks == MC_CLOCKS_W'(0));
      last2_q <= cyc_on && at_last_d &&
                 (bus_cyc_end3 || (bus_done && cur_d.clocks == MC_CLOCKS_W'(1)));
    end
  end

  assign ex_last  = last_q;
  assign ex_last2 = last2_q;

  // ---- next machine cycle -------------------------------------------------------------
  typedef enum logic [2:0] {
    NEXT_NONE,
    NEXT_PSA,
    NEXT_REFRESH,
    NEXT_IF1,
    NEXT_FETCH,     // a later instruction word
    NEXT_INTERNAL
  } next_e;

  next_e next;
  always_comb begin
    next = NEXT_NONE;
    unique case (state_q)
      SEQ_PSA_REQ: next = NEXT_PSA;
      SEQ_FETCH:   next = NEXT_IF1;
      SEQ_PROG: begin
        if (run_ok) begin
          if (rf_ok_q && rf_pending)  next = NEXT_REFRESH;
          else if (at_last)           next = NEXT_IF1;
          else if (nxt.kind == MC_FN || nxt.kind == MC_FA) next = NEXT_FETCH;
          else if (nxt.kind == MC_I)  next = NEXT_INTERNAL;
        end
      end
      default: ;
    endcase
  end

  // ---- PSA word address -----------------------------------------------------
  // Always segment 0, even once the loaded FCW selects nonsegmented mode.
  logic [15:0] psa_off;
  always_comb begin
    unique case (word_q)
      PSA_FCW:    psa_off = 16'h0002;
      PSA_PC_SEG: psa_off = 16'h0004;
      PSA_PC_OFF: psa_off = SEGMENTED ? 16'h0006 : 16'h0004;
      default:    psa_off = 16'h0002;
    endcase
  end

  always_comb begin
    bus_req      = next != NEXT_NONE;
    bus_internal = next == NEXT_INTERNAL;
    bus_addr     = pc[22:0];
    bus_st       = ST_PROG_SPACE;
    bus_len      = nxt.clocks;
    unique case (next)
      NEXT_PSA:      bus_addr = {7'd0, psa_off};
      NEXT_REFRESH: begin
        bus_addr = rf_addr;
        bus_st   = ST_REFRESH;
      end
      NEXT_IF1:      bus_st   = ST_INSTR_FETCH_FIRST;
      NEXT_INTERNAL: bus_st   = ST_INTERNAL_OP;
      default: ;
    endcase
  end

  // The reset reads run in system mode whatever FCW they load.
  assign bus_normal = state_q != SEQ_PSA_REQ && !fcw_sys;

  // A transaction's tail, read by the bus unit in its T3 clock.
  assign bus_tail = (state_q == SEQ_PROG && !in_rf_q) ? cur_q.clocks[2:0] : 3'd0;

  logic take, take_rf, take_if1, take_prog;
  assign take      = bus_req && bus_cyc_end;
  assign take_rf   = take && next == NEXT_REFRESH;
  assign take_if1  = take && next == NEXT_IF1;
  assign take_prog = take && (next == NEXT_FETCH || next == NEXT_INTERNAL);
  assign rf_take   = take_rf;

  // A repetition of the repeated part starts on this edge.
  logic rep_start;
  assign rep_start = take_prog && rep_end && more && link.next_more != link.next_done;

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
      SEQ_PROG: begin
        if (!run_ok)       state_d = SEQ_STOP;
        else if (take_if1) state_d = SEQ_IF1;
      end
      SEQ_STOP:     ;
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
  assign word_addr = word_more && cur_q.kind == MC_FA;

  // FCW and PC writes: the PSA loads, then +2 per instruction word taken.
  always_comb begin
    fcw_we = state_q == SEQ_PSA_WAIT && bus_done && word_q == PSA_FCW;
    fcw_d  = bus_rdata;
    pc_we  = 1'b0;
    pc_d   = pc;
    if (state_q == SEQ_PSA_WAIT && bus_done && word_q == PSA_PC_SEG) begin
      pc_we = 1'b1;
      pc_d  = {9'd0, bus_rdata[14:8], 16'h0000};
    end else if (psa_last) begin
      pc_we = 1'b1;
      pc_d  = SEGMENTED ? {pc[31:16], bus_rdata} : {16'h0000, bus_rdata};
    end else if (word_if1 || word_more) begin
      pc_we = 1'b1;
      pc_d  = {pc[31:16], pc[15:0] + 16'd2};
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
    end else begin
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
  always_comb begin
    ea_d = ea_q;
    if (word_addr) begin
      unique case (col_q)
        MC_COL_SS: ea_d = {bus_rdata[14:8], 8'h00, bus_rdata[7:0]};
        MC_COL_SL: ea_d = {ea_q[22:16], bus_rdata};
        default:   ea_d = {SEGMENTED ? pc[22:16] : 7'd0, bus_rdata};
      endcase
    end
  end

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
    end else begin
      ir0_q    <= ir0_d;
      ir1_q    <= ir1_d;
      ir2_q    <= ir2_d;
      nwords_q <= nwords_d;
      ea_q     <= ea_d;
      path_q   <= path_d;
      prog_q   <= prog_d;
      cur_q    <= take_prog ? nxt : cur_d;   // stale while an IF1 runs
    end
  end

  // Program position: the IF1 is position 0; each cycle taken moves on.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      pos_q <= MC_POS_W'(0);
      rep_q <= MC_REPS_W'(0);
      iter_q <= 6'd0;
    end else if (take_if1) begin
      pos_q <= MC_POS_W'(0);
      rep_q <= MC_REPS_W'(0);
      iter_q <= 6'd0;
    end else if (take_prog) begin
      pos_q <= npos;
      rep_q <= rep_end ? MC_REPS_W'(0) : rep_q + MC_REPS_W'(1);
      if (rep_start && iter_q != 6'd63) iter_q <= iter_q + 6'd1;  // saturates
    end
  end

  // Refresh bookkeeping: allowed after an IF1 or internal cycle, once.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      in_rf_q <= 1'b0;
      rf_ok_q <= 1'b0;
    end else if (take) begin
      in_rf_q <= take_rf;
      rf_ok_q <= take_if1 || (take_prog && next == NEXT_INTERNAL);
    end
  end

  assign dec_w0    = ir0_d;
  assign dec_w1_lo = ir1_d[3:0];
  assign ir_w0     = ir0_q;
  assign ir_w1     = ir1_q;
  assign ir_w2     = ir2_q;
  assign ir_ea     = ea_q;
  assign iter      = iter_q;
  assign halted    = state_q == SEQ_PROG && run_ok && dec_exec == CLS_HALT;

  // synthesis translate_off
  // A program cycle of a kind not run yet stalls the program: flag it once.
  logic unhandled_q;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      unhandled_q <= 1'b0;
    else if (state_q == SEQ_PROG && run_ok && next == NEXT_NONE && bus_cyc_end && !unhandled_q) begin
      unhandled_q <= 1'b1;
      $display("%%Error: %m: machine cycle %s not run yet (position %0d)", nxt.kind.name(), npos);
    end
  end
  // synthesis translate_on

endmodule
