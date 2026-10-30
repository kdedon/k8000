// z8000_cpu -- Z8001/Z8002 (Z8003/Z8004 with VMPU) CPU, top level.
//
// SEGMENTED=1: Z8001/Z8003 (SN pins, the PC segment read at reset, SEGT).
// VMPU=1: Z8003/Z8004 (ABORT pin).
//
// AD is split into ad_in / ad_out / ad_drive. ad_in must come straight from
// a register (the read-data capture): its decode look-ahead takes the clock.
// The test harness reads and pokes u_regfile.r, fcw, pc, psap, refresh,
// nspoff, nspseg, refresh_en and halted by name.

module z8000_cpu
  import z8000_ctrl_pkg::*, z8000_mc_pkg::*;
#(
  parameter bit SEGMENTED = 1,
  parameter bit VMPU      = 0
) (
  input  logic        clk,
  input  logic        reset_n,    // asynchronous, active low

  // inputs
  input  logic [15:0] ad_in,
  input  logic        stop_n,
  input  logic        wait_n,
  input  logic        busreq_n,
  input  logic        nmi_n,
  input  logic        nvi_n,
  input  logic        vi_n,
  input  logic        segt_n,     // SEGT (Z8001) / SAT (Z8003); ignored when !SEGMENTED
  input  logic        abort_n,    // Z8003/Z8004 only; ignored when !VMPU
  input  logic        mi_n,

  // outputs
  output logic [15:0] ad_out,
  output logic        ad_drive,
  output logic [6:0]  sn,         // SN6..SN0, meaningful only when SEGMENTED
  output logic        as_n,
  output logic        ds_n,
  output logic        mreq_n,
  output logic        r_w,        // 1 = read
  output logic        b_w,        // 1 = byte
  output logic        n_s,        // 1 = normal (user) mode
  output logic [3:0]  st,         // ST3..ST0, z8000_zbus_pkg codes
  output logic        busack_n,
  output logic        mo_n
);

  // ---- architectural registers ----------------------------------------------
  logic [15:0] fcw;
  logic [31:0] pc;          // Z8002: 16-bit; Z8001: seg[22:16]:offset[15:0]
  logic [31:0] psap;
  logic [15:0] refresh;
  logic [15:0] nspoff;
  logic [15:0] nspseg;
  logic        refresh_en;
  logic        halted;

  // ---- register file --------------------------------------------------------
  logic        rf_we;
  logic [1:0]  rf_wwidth;
  logic [3:0]  rf_wsel;
  logic [63:0] rf_wdata;
  logic [1:0]  rf_rwidth;
  logic [3:0]  rf_rsel;
  logic [63:0] rf_rdata;
  logic        rf_rbyte_b;
  logic [3:0]  rf_rsel_b;
  logic [15:0] rf_rdata_b, ex_wdata;
  logic        ex_rf_we;
  logic [1:0]  ex_rf_wwidth;
  logic [3:0]  ex_rf_wsel;
  logic [1:0]  ex_rf_rwidth_a;
  logic [3:0]  ex_rf_rsel, ex_rf_rsel_b;
  logic        ex_rf_rbyte_b;

  z8000_regfile u_regfile (
    .clk     (clk),
    .we      (rf_we),
    .wwidth  (rf_wwidth),
    .wsel    (rf_wsel),
    .wdata   (rf_wdata),
    .rwidth  (rf_rwidth),
    .rsel    (rf_rsel),
    .rdata   (rf_rdata),
    .rbyte_b (rf_rbyte_b),
    .rsel_b  (rf_rsel_b),
    .rdata_b (rf_rdata_b)
  );

  // ---- control and bus ------------------------------------------------------
  logic        fcw_we, pc_we, ex_fcw_we, ctl_we, ref_we;
  logic [15:0] ex_fcw_d, ctl_rdata, ctl_wd;
  logic [2:0]  ctl_rsel, ctl_sel;
  logic [15:0] fcw_d;
  logic [31:0] pc_d;
  logic [15:0] dec_w0;
  logic [3:0]  dec_w1_lo;
  ctrl_word_t  ctrl, ctrl_q;
  logic        ex_handles, ex_first, ex_last, ex_last2, ex_last_nx, ex_last2_nx, ex_to_last, ex_flags_we, ex_pc_we;
  logic [22:0] ex_pc_d;
  logic [15:0] ir_w0, ir_w1, ir_w2;
  logic [22:0] ir_ea;
  logic [15:0] ex_flags, ex_flags_mask;
  logic        rf_pending, rf_take;
  logic [8:0]  rf_row_next, rf_cyc_row;
  logic [22:0] rf_addr;
  logic        bus_mem, bus_write, mem_take, int_take, opnd_take, ex_mem_byte;
  logic [22:0] ex_mem_addr;
  logic [3:0]  ex_mem_st;
  logic [15:0] ex_mem_wdata;
  logic        bus_req, bus_internal, bus_normal, bus_cyc_end, bus_cyc_end3, bus_done;
  logic [22:0] bus_addr;
  logic [3:0]  bus_st, bus_len;
  logic [2:0]  bus_tail;
  logic [15:0] bus_rdata;
  logic        cc_met, more;
  logic [5:0]  iter;

  z8000_decode u_decode (
    .w0    (dec_w0),
    .w1_lo (dec_w1_lo),
    .ctrl  (ctrl)
  );

  // Decoded from the words as of the next edge: ctrl_q decodes the words in.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) ctrl_q <= '0;
    else          ctrl_q <= ctrl;
  end

  // Sources not wired yet, tied to what the sequencer assumed before.
  logic        md_take, blk_more, mult_more, mreq_more, halt_exit, ex_word;
  mc_path_e    md_path;
  logic [15:0] rf_count;
  assign halt_exit = 1'b0;             // HALT's exit on an interrupt

  // ---- multiply and divide --------------------------------------------------
  // The units move on the program's clocks (not a wait or a refresh) and
  // end with its last one, so the work starts as many clocks before the
  // end as it takes: on the IF1's T3 for a register, immediate or IR source;
  // later by the DA/X address cycles' clocks. The destination quad is read
  // on port A as the unit starts. A register source is read on port B: a
  // word the clock after the start, a long's high word as it starts and its
  // low word the clock after; it is given and picks the program's path
  // there. A memory or immediate source is given on the edge its last word
  // arrives. The result and flags go in from the units' registers the
  // clock after the last.
  logic        imm_take, seq_in_rf, seq_rf_due, bus_twait;
  mc_col_e     col_nx;
  logic        md_mul, md_div, md_on, md_long, md_reg, md_imm, md_x, md_dax, md_tick;
  logic        md_start, md_lda, md_data, md_arrive, md_src_valid, md_pick_q, md_seen_q;
  logic        md_pend_q, md_mul_q, md_long_q, md_wb, md_rf_we;
  logic [3:0]  md_clk_q, md_dst_q, md_flags;
  logic        md_at_ns, md_at_ss, md_at_sl, md_at_hit;
  logic [15:0] md_hi_q;
  logic [31:0] md_dst_w, md_src;
  logic [63:0] md_wdata, m_product;
  logic [31:0] d_quot, d_rem;
  logic        m_done, m_zero, d_done, d_dbz, d_ovf, d_wide, d_qneg, d_qzero, d_zero, d_ovf_now;

  assign md_mul  = ctrl_q.valid && ctrl_q.exec == CLS_MUL;
  assign md_div  = ctrl_q.valid && ctrl_q.exec == CLS_DIV;
  assign md_on   = md_mul || md_div;
  assign md_long = ctrl_q.width == WIDTH_LONG;
  assign md_reg  = ctrl_q.src2 == SRC_REG;
  assign md_imm  = ctrl_q.src2 == SRC_IMM;
  assign md_x    = ctrl_q.src2 == SRC_X;
  assign md_dax  = md_x || ctrl_q.src2 == SRC_DA;
  assign md_tick = !seq_in_rf && !bus_twait;

  localparam logic [1:0] RF_BYTE = 2'd0, RF_WORD = 2'd1, RF_LONG = 2'd2, RF_QUAD = 2'd3;   // register file widths

  // Program clocks: the IF1's T3 is clock 2.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)                            md_clk_q <= 4'd0;
    else if (ex_first)                       md_clk_q <= 4'd3;
    else if (md_tick && md_clk_q != 4'hF)    md_clk_q <= md_clk_q + 4'd1;
  end

  // DA/X: the clock before the R cycle's T1 less two; the address cycles
  // are Fa (+1 for X or SS), with a long offset Fn and Fa. Each column's
  // compare is from flops; the column as of the next edge picks late.
  assign md_at_ns  = md_clk_q == 4'd3 + {3'd0, md_x};
  assign md_at_ss  = md_clk_q == 4'd4;
  assign md_at_sl  = md_clk_q == 4'd6 + {3'd0, md_x};
  assign md_at_hit = col_nx == MC_COL_SL ? md_at_sl : col_nx == MC_COL_SS ? md_at_ss : md_at_ns;
  assign md_lda    = md_on && (md_dax ? !ex_first && md_at_hit : ex_first);
  assign md_start = md_lda && md_tick;

  // Port A reads the destination quad as the unit starts.
  assign rf_rwidth = md_lda ? RF_QUAD : sh_on ? sh_rwidth : bd_on ? bd_rwidth : mq_on ? RF_WORD : ex_rf_rwidth_a;
  assign rf_rsel   = md_lda ? {ir_w0[3:2], 2'b00} : sh_on || mq_on ? ir_w0[7:4] : bd_on ? ir_w1[11:8] : ex_rf_rsel;

  // Operand words: immediate words, or the memory reads; a long's first
  // is its high word.
  assign md_data      = md_on && (md_imm ? imm_take : opnd_take && !md_reg);
  assign md_arrive    = md_data && (!md_long || md_seen_q);
  assign md_src_valid = md_reg ? md_pick_q : md_arrive;
  assign md_src = {md_long ? md_hi_q : 16'h0000, md_reg ? rf_rdata_b : bus_rdata};

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      md_pick_q <= 1'b0;
      md_seen_q <= 1'b0;
      md_hi_q   <= 16'h0000;
    end else begin
      md_pick_q <= md_start && md_reg;
      if (ex_first)     md_seen_q <= 1'b0;
      else if (md_data) md_seen_q <= 1'b1;
      if (md_start && md_reg) md_hi_q <= rf_rdata_b;
      else if (md_data)       md_hi_q <= bus_rdata;
    end
  end

  // A register source's pick lands in the IF1's tail (clock 3), where no
  // refresh or wait runs, and no cycle starts on its edge.
  assign md_take = md_pick_q || md_arrive;
  always_comb begin
    md_path = MC_PATH_DEFAULT;
    if (md_mul ? m_zero : d_zero) md_path = MC_PATH_ZERO;
    // A quotient one bit too wide is also an overflow compare: it takes
    // the overflow program, which forms its bits.
    else if (md_div && d_ovf_now) md_path = MC_PATH_OVERFLOW;
  end

  // MULT: Rd+1 (RQ's low long for MULTL). DIV: RRd (RQd for DIVL).
  always_comb begin
    if (md_mul) md_dst_w = md_long ? rf_rdata[31:0] : {16'h0000, ir_w0[1] ? rf_rdata[15:0] : rf_rdata[47:32]};
    else        md_dst_w = ir_w0[1] ? rf_rdata[31:0] : rf_rdata[63:32];
  end

  z8000_mult u_mult (
    .clk       (clk),
    .reset_n   (reset_n),
    .tick      (md_tick),
    .start     (md_start && md_mul),
    .width32   (md_long),
    .dst       (md_dst_w),
    .src_valid (md_src_valid && md_mul),
    .src       (md_src),
    .done      (m_done),
    .product   (m_product),
    /* verilator lint_off PINCONNECTEMPTY */
    .remaining (),
    /* verilator lint_on PINCONNECTEMPTY */
    .pick_zero (m_zero),
    .adds_more (mult_more)
  );

  z8000_div u_div (
    .clk         (clk),
    .reset_n     (reset_n),
    .tick        (md_tick),
    .start       (md_start && md_div),
    .n32         (md_long),
    .dividend    (md_long ? rf_rdata : {32'd0, md_dst_w}),
    .src_valid   (md_src_valid && md_div),
    .divisor     (md_src),
    .done        (d_done),
    .div_by_zero (d_dbz),
    .overflow    (d_ovf),
    .wide_quot   (d_wide),
    .quot_neg    (d_qneg),
    .quot_zero   (d_qzero),
    .quotient    (d_quot),
    .remainder   (d_rem),
    /* verilator lint_off PINCONNECTEMPTY */
    .remaining   (),
    /* verilator lint_on PINCONNECTEMPTY */
    .pick_zero   (d_zero),
    .pick_ovf    (d_ovf_now)
  );

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      md_pend_q <= 1'b0;
      md_mul_q  <= 1'b0;
      md_long_q <= 1'b0;
      md_dst_q  <= 4'd0;
    end else if (md_start) begin
      md_pend_q <= 1'b1;
      md_mul_q  <= md_mul;
      md_long_q <= md_long;
      md_dst_q  <= ir_w0[3:0];
    end else if (md_wb) begin
      md_pend_q <= 1'b0;
    end
  end

  // Divide by zero and overflow leave the destination.
  assign md_wb    = md_pend_q && (md_mul_q ? m_done : d_done);
  assign md_rf_we = md_wb && (md_mul_q || !(d_dbz || d_ovf));
  always_comb begin
    if (md_mul_q) begin
      md_wdata = m_product;
      if (md_long_q) md_flags = {m_product[63:31] != {33{m_product[63]}}, m_product == 64'd0, m_product[63], 1'b0};
      else           md_flags = {m_product[31:15] != {17{m_product[31]}}, m_product[31:0] == 32'd0, m_product[31], 1'b0};
    end else begin
      md_wdata = md_long_q ? {d_rem, d_quot} : {32'd0, d_rem[15:0], d_quot[15:0]};
      if (d_dbz)      md_flags = 4'b0101;
      else if (d_ovf) md_flags = 4'b0001;
      else            md_flags = {d_wide, d_qzero, d_qneg, d_wide};
    end
  end

  // ---- shifts ----------------------------------------------------------------
  // SLA/SLL and SDA/SDL, byte, word and long: one position per 3-clock
  // internal cycle, the unit starting as the first of them is taken. Port A
  // reads the destination throughout. A register count is read on port B
  // as the I3 before the positions is taken; that I3 forms its magnitude
  // and direction. The last position is in as the last I3 opens, so the
  // result and flags go in on the program's last clock. Each step waits
  // for the end of a cycle that is not followed by a refresh: the Fn (the
  // count word), then the count I3 for a register count.
  logic        sh_on, sh_reg, sh_start, sh_arm_q, sh_step, sh_cnt_ok_q, sh_pend_q, sh_done, sh_wb;
  logic [1:0]  sh_rwidth, sh_wwidth_q;
  logic [3:0]  sh_dst_q;
  logic [15:0] sh_cnt_q, sh_flags, sh_fmask;
  logic [31:0] sh_result;
  logic [ALUOP_W-1:0] sh_op;

  assign sh_on     = ctrl_q.valid && ctrl_q.exec == CLS_SHIFT;
  assign sh_reg    = ctrl_q.count == SRC_REG;
  assign sh_rwidth = ctrl_q.width == WIDTH_BYTE ? RF_BYTE : ctrl_q.width == WIDTH_WORD ? RF_WORD : RF_LONG;
  assign rf_count  = sh_cnt_q;
  assign sh_step   = sh_on && sh_arm_q && bus_cyc_end && !seq_rf_due;
  assign sh_start  = sh_step && (!sh_reg || sh_cnt_ok_q);

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      sh_arm_q    <= 1'b0;
      sh_cnt_q    <= 16'h0000;
      sh_cnt_ok_q <= 1'b0;
    end else if (ex_first) begin
      sh_arm_q    <= 1'b0;
      sh_cnt_ok_q <= 1'b0;
    end else begin
      if (sh_on && imm_take) sh_arm_q <= 1'b1;
      else if (sh_start)     sh_arm_q <= 1'b0;
      if (sh_step && sh_reg && !sh_cnt_ok_q) begin
        sh_cnt_q    <= rf_rdata_b;
        sh_cnt_ok_q <= 1'b1;
      end
    end
  end

  logic [15:0] sh_cnt;
  logic [5:0]  sh_n;
  assign sh_cnt = sh_reg ? rf_count : ir_w1;
  // Legal counts are at most 32 (long), so six bits.
  assign sh_n   = sh_cnt[15] ? 6'd0 - sh_cnt[5:0] : sh_cnt[5:0];

  // A negative count shifts right.
  always_comb begin
    if (ctrl_q.alu_op == OP_SLA) sh_op = sh_cnt[15] ? OP_SRA : OP_SLA;
    else                         sh_op = sh_cnt[15] ? OP_SRL : OP_SLL;
  end

  z8000_shift u_shift (
    .clk        (clk),
    .reset_n    (reset_n),
    .start      (sh_start),
    .width      (ctrl_q.width),
    .op         (sh_op),
    .val        (rf_rdata[31:0]),
    .count      (sh_n),
    .done       (sh_done),
    .result     (sh_result),
    .flags      (sh_flags),
    .flags_mask (sh_fmask)
  );

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      sh_pend_q   <= 1'b0;
      sh_dst_q    <= 4'd0;
      sh_wwidth_q <= RF_BYTE;
    end else if (sh_start) begin
      sh_pend_q   <= 1'b1;
      sh_dst_q    <= ir_w0[7:4];
      sh_wwidth_q <= sh_rwidth;
    end else if (sh_wb) begin
      sh_pend_q   <= 1'b0;
    end
  end
  assign sh_wb = sh_pend_q && ex_last;

  // ---- BIT, SET and RES with the bit number in a register -------------------
  // F1+1 · Fn+3: the bit register (w0[3:0]) is read on port B and its mask
  // latched on the second last clock; port A reads the target (w1[11:8]),
  // and the last clock tests it (Z) or writes it back with the bit changed.
  logic        bd_on, bd_wb;
  logic [1:0]  bd_rwidth;
  logic [15:0] bd_mask_q, bd_val;

  assign bd_on     = ctrl_q.valid && ctrl_q.exec == CLS_BIT_DYNAMIC;
  assign bd_rwidth = ctrl_q.width == WIDTH_BYTE ? RF_BYTE : RF_WORD;
  assign bd_val    = rf_rdata[15:0];
  assign bd_wb     = bd_on && ex_last && ctrl_q.alu_op != OP_BIT;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)                bd_mask_q <= 16'h0000;
    else if (bd_on && ex_last2)  bd_mask_q <= 16'h0001 << (ctrl_q.width == WIDTH_BYTE ? {1'b0, rf_rdata_b[2:0]} : rf_rdata_b[3:0]);
  end

  // ---- multi-micro: MSET, MRES, MBIT, MREQ -------------------------------------
  // MSET/MRES drive /MO and MBIT sets S if /MI is High as the last clock
  // opens. MREQ (F1+2 · n x I7 · I7) samples /MI as its word is taken: High
  // drives /MO Low and counts Rd down, one I7 each: Rd is read on port A in
  // the T3 clock into a count register, which each I7's first clock writes
  // back less one. Low clears S and Z and skips the count. As the last clock
  // opens /MI is sampled again: Low grants (S set), High withdraws (S clear,
  // /MO High); Z is set.
  logic        mp_on, mq_on, mq_go, mo_q, mq_req_q, mq_more_q, mq_dec_q, mq_wb, mq_end;
  logic [15:0] mq_cnt_q;    // the next value Rd takes

  assign mp_on     = ctrl_q.valid && ctrl_q.exec == CLS_MULTI_PROC;
  assign mq_on     = mp_on && ctrl_q.mp_op == MPREQ;
  assign mreq_more = mq_more_q;
  assign mq_wb     = mq_on && mq_dec_q;
  assign mq_end    = mp_on && ex_to_last;
  assign mq_go     = ex_word && fcw[14] && ctrl.valid && ctrl.exec == CLS_MULTI_PROC && ctrl.mp_op == MPREQ;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      mo_q      <= 1'b1;
      mq_req_q  <= 1'b0;
      mq_more_q <= 1'b0;
      mq_dec_q  <= 1'b0;
      mq_cnt_q  <= 16'h0000;
    end else begin
      mq_dec_q <= mq_on && int_take && more;
      // Only a word that runs: in normal mode MREQ traps and /MO holds.
      if (mq_go) begin
        mq_req_q <= mi_n;
        mo_q     <= !mi_n;
      end else if (mq_end) begin
        unique case (ctrl_q.mp_op)
          MPSET:   mo_q <= 1'b0;
          MPRES:   mo_q <= 1'b1;
          MPREQ:   if (mq_req_q && mi_n) mo_q <= 1'b1;
          default: ;
        endcase
      end
      if (mq_on && ex_first) begin
        mq_more_q <= mq_req_q && rf_rdata[15:0] != 16'h0000;
        mq_cnt_q  <= rf_rdata[15:0] - 16'd1;
      end else if (mq_wb) begin
        mq_more_q <= mq_cnt_q != 16'h0000;
        mq_cnt_q  <= mq_cnt_q - 16'd1;
      end
    end
  end

  // Port B reads a shift's count register or the bit register, else the
  // execute unit's pick.
  assign rf_rsel_b  = sh_on && sh_reg ? ir_w1[11:8] : bd_on ? ir_w0[3:0] : ex_rf_rsel_b;
  assign rf_rbyte_b = (sh_on && sh_reg) || bd_on ? 1'b0 : ex_rf_rbyte_b;

  assign rf_we     = md_rf_we || sh_wb || bd_wb || mq_wb || ex_rf_we;
  assign rf_wwidth = md_rf_we ? (md_long_q ? RF_QUAD : RF_LONG) : sh_wb ? sh_wwidth_q : bd_wb ? bd_rwidth
                   : mq_wb ? RF_WORD : ex_rf_wwidth;
  assign rf_wsel   = md_rf_we ? md_dst_q : sh_wb ? sh_dst_q : bd_wb ? ir_w1[11:8] : mq_wb ? ir_w0[7:4] : ex_rf_wsel;
  assign rf_wdata  = md_rf_we ? md_wdata : sh_wb ? {32'd0, sh_result}
                   : bd_wb ? {48'd0, ctrl_q.alu_op == OP_SET ? bd_val | bd_mask_q : bd_val & ~bd_mask_q}
                   : mq_wb ? {48'd0, mq_cnt_q}
                   : {48'd0, ex_wdata};

  z8000_sequencer #(.SEGMENTED(SEGMENTED)) u_sequencer (
    .clk          (clk),
    .reset_n      (reset_n),
    .fcw_sys      (fcw[14]),
    .fcw_seg      (fcw[15]),
    .pc           (pc),
    .fcw_we       (fcw_we),
    .fcw_d        (fcw_d),
    .pc_we        (pc_we),
    .pc_d         (pc_d),
    .halted       (halted),
    .dec_w0       (dec_w0),
    .dec_w1_lo    (dec_w1_lo),
    .dec_valid    (ctrl_q.valid),
    .dec_exec     (ctrl_q.exec),
    .cc_met       (cc_met),
    .md_take      (md_take),
    .md_zero      (md_arrive && bus_rdata == 16'h0000 && (!md_long || md_hi_q == 16'h0000)),
    .md_path      (md_path),
    .more         (more),
    .iter         (iter),
    .ex_handles   (ex_handles || sh_on || bd_on || mp_on),
    .io_write     (ctrl_q.io_write),
    .ex_first     (ex_first),
    .ex_word      (ex_word),
    .ex_to_last   (ex_to_last),
    .ex_last2     (ex_last2),
    .ex_last      (ex_last),
    .ex_last2_nx  (ex_last2_nx),
    .ex_last_nx   (ex_last_nx),
    .ir_w0        (ir_w0),
    .ir_w1        (ir_w1),
    .ir_w2        (ir_w2),
    .ir_ea        (ir_ea),
    .mem_addr     (ex_mem_addr),
    .mem_st       (ex_mem_st),
    .mem_take     (mem_take),
    .int_take     (int_take),
    .opnd_take    (opnd_take),
    .imm_take     (imm_take),
    .in_rf        (seq_in_rf),
    .rf_due       (seq_rf_due),
    .col_nx       (col_nx),
    .rf_pending   (rf_pending),
    .rf_addr      (rf_addr),
    .rf_take      (rf_take),
    .bus_req      (bus_req),
    .bus_internal (bus_internal),
    .bus_addr     (bus_addr),
    .bus_st       (bus_st),
    .bus_normal   (bus_normal),
    .bus_mem      (bus_mem),
    .bus_write    (bus_write),
    .bus_len      (bus_len),
    .bus_tail     (bus_tail),
    .bus_cyc_end  (bus_cyc_end),
    .bus_cyc_end3 (bus_cyc_end3),
    .bus_done     (bus_done),
    .bus_rdata    (bus_rdata)
  );

  // The condition of the first word as of the next edge.
  z8000_cond u_cond (
    .cc  (dec_w0[3:0]),
    .c   (fcw[7]),
    .z   (fcw[6]),
    .s   (fcw[5]),
    .v   (fcw[4]),
    .met (cc_met)
  );

  // Whether the repeated part runs again after `iter` repetitions. A shift
  // runs |count| positions, at least one; LDM and EPU transfers take their
  // count from word 1.
  always_comb begin
    more = 1'b0;
    unique case (ctrl_q.exec)
      CLS_LDM:        more = iter <= {2'b00, ir_w1[3:0]};
      CLS_EPU:        more = iter <= (ctrl_q.epu_kind == EPU_CPU ? {3'b000, ir_w1[2:0]}
                                                                 : {2'b00, ir_w1[3:0]});
      CLS_SHIFT:      more = iter == 6'd0 || iter < sh_n;
      CLS_BLOCK_TRANSFER, CLS_BLOCK_COMPARE, CLS_BLOCK_STRING, CLS_TRANSLATE, CLS_BLOCK_IO:
                      more = iter == 6'd0 || blk_more;
      CLS_MUL:        more = mult_more;
      CLS_MULTI_PROC: more = mreq_more;
      CLS_HALT:       more = !halt_exit;
      default:        ;
    endcase
  end

  z8000_execute #(.SEGMENTED(SEGMENTED), .VMPU(VMPU)) u_execute (
    .clk        (clk),
    .reset_n    (reset_n),
    .w0         (ir_w0[11:0]),
    .ctrl_nx    (ctrl),
    .w0_nx      (dec_w0[11:0]),
    .alu_op     (ctrl_q.alu_op),
    .width      (ctrl_q.width),
    .src2       (ctrl_q.src2),
    .count      (ctrl_q.count),
    .dst        (ctrl_q.dst),
    .src1_nib   (ctrl_q.src1_nib),
    .src2_nib   (ctrl_q.src2_nib),
    .dst_nib    (ctrl_q.dst_nib),
    .w1         (ir_w1),
    .w2         (ir_w2),
    .handles    (ex_handles),
    .block_decr (ctrl_q.block_decr),
    .block_rept (ctrl_q.block_rept),
    .blk_more   (blk_more),
    .fcw_op     (ctrl_q.fcw_op),
    .fcw_mask   (ctrl_q.fcw_mask),
    .first      (ex_first),
    .to_last    (ex_to_last),
    .last2      (ex_last2),
    .last       (ex_last),
    .last2_nx   (ex_last2_nx),
    .last_nx    (ex_last_nx),
    .seg_mode   (SEGMENTED && fcw[15]),
    .pc_seg     (SEGMENTED ? pc[22:16] : 7'd0),
    .pc_off     (pc[15:0]),
    .cyc_end    (bus_cyc_end),
    .ea_word    (ir_ea),
    .mem_take   (mem_take),
    .int_take   (int_take),
    .opnd_take  (opnd_take),
    .rdata      (bus_rdata),
    .mem_addr   (ex_mem_addr),
    .mem_st     (ex_mem_st),
    .mem_byte   (ex_mem_byte),
    .mem_wdata  (ex_mem_wdata),
    .rf_rwidth  (ex_rf_rwidth_a),
    .rf_rsel    (ex_rf_rsel),
    .rf_rdata   (rf_rdata[31:0]),
    .rf_rbyte_b (ex_rf_rbyte_b),
    .rf_rsel_b  (ex_rf_rsel_b),
    .rf_rdata_b (rf_rdata_b),
    .rf_we      (ex_rf_we),
    .rf_wwidth  (ex_rf_wwidth),
    .rf_wsel    (ex_rf_wsel),
    .rf_wdata   (ex_wdata),
    .pc_we      (ex_pc_we),
    .pc_d       (ex_pc_d),
    .fcw_c      (fcw[7]),
    .fcw_zsv    ({fcw[6], fcw[5], fcw[4]}),
    .fcw_lo     (fcw[10:0]),
    .fcw_sn     (fcw[14]),
    .fcw_we     (ex_fcw_we),
    .fcw_d      (ex_fcw_d),
    .ctl_rsel   (ctl_rsel),
    .ctl_rdata  (ctl_rdata),
    .ctl_we     (ctl_we),
    .ctl_sel    (ctl_sel),
    .ctl_wd     (ctl_wd),
    .flags_we   (ex_flags_we),
    .flags      (ex_flags),
    .flags_mask (ex_flags_mask)
  );

  // Control registers by LDCTL number: 2 FCW, 3 REFRESH, 4 PSAP segment,
  // 5 PSAP offset, 6 NSP segment, 7 NSP offset.
  always_comb begin
    unique case (ctl_rsel)
      3'd2:    ctl_rdata = fcw;
      3'd3:    ctl_rdata = refresh;
      3'd4:    ctl_rdata = {1'b0, psap[22:16], 8'h00};
      3'd5:    ctl_rdata = psap[15:0];
      3'd6:    ctl_rdata = nspseg;
      3'd7:    ctl_rdata = nspoff;
      default: ctl_rdata = 16'h0000;
    endcase
  end

  assign ref_we = ctl_we && ctl_sel == 3'd3;

  z8000_refresh u_refresh (
    .clk      (clk),
    .reset_n  (reset_n),
    .enable   (refresh_en),
    .rate     (refresh[14:9]),
    .row      (refresh[8:0]),
    .load     (ref_we && ctl_wd[15]),
    .load_rate(ctl_wd[14:9]),
    .take     (rf_take),
    .pending  (rf_pending),
    .row_next (rf_row_next),
    .cyc_row  (rf_cyc_row)
  );

  // Refresh addresses take the PC segment in nonsegmented mode.
  assign rf_addr = {(SEGMENTED && !fcw[15]) ? pc[22:16] : 7'd0, 7'd0, rf_cyc_row};

  // EPU transfers have no requester yet.
  z8000_bus_unit #(.SEGMENTED(SEGMENTED)) u_bus (
    .clk            (clk),
    .reset_n        (reset_n),
    .req            (bus_req),
    .req_internal   (bus_internal),
    .req_addr       (bus_addr),
    .req_wdata      (ex_mem_wdata),
    .req_st         (bus_st),
    .req_write      (bus_write),
    .req_byte       (bus_mem && ex_mem_byte),
    .req_odd        (ex_mem_addr[0]),
    .req_epu_drives (1'b0),
    .req_normal     (bus_normal),
    .req_len        (bus_len),
    .tail           (bus_tail),
    .cyc_end        (bus_cyc_end),
    .cyc_end3       (bus_cyc_end3),
    .twait          (bus_twait),
    .done           (bus_done),
    .rdata          (bus_rdata),
    .wait_n         (wait_n),
    .ad_in          (ad_in),
    .ad_out         (ad_out),
    .ad_drive       (ad_drive),
    .sn             (sn),
    .as_n           (as_n),
    .ds_n           (ds_n),
    .mreq_n         (mreq_n),
    .r_w            (r_w),
    .b_w            (b_w),
    .n_s            (n_s),
    .st             (st)
  );

  assign busack_n = 1'b1;
  assign mo_n     = mo_q;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      fcw <= 16'h0000;
      pc  <= 32'h0;
    end else begin
      if (fcw_we)           fcw <= fcw_d;
      else if (ex_fcw_we)   fcw <= ex_fcw_d;
      else if (ex_flags_we) fcw <= (fcw & ~ex_flags_mask) | (ex_flags & ex_flags_mask);
      else if (md_wb)       fcw <= {fcw[15:8], md_flags, fcw[3:0]};
      else if (sh_wb)       fcw <= (fcw & ~sh_fmask) | (sh_flags & sh_fmask);
      else if (bd_on && ex_last && ctrl_q.alu_op == OP_BIT) fcw[6] <= (bd_val & bd_mask_q) == 16'h0000;
      else if (mq_end && ctrl_q.mp_op == MPBIT) fcw[5] <= mi_n;
      else if (mq_end && ctrl_q.mp_op == MPREQ) begin
        fcw[6] <= mq_req_q;
        fcw[5] <= mq_req_q && !mi_n;
      end
      if (ex_pc_we)         pc  <= {9'd0, ex_pc_d};
      else if (pc_we)       pc  <= pc_d;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      refresh <= 16'h0;
    end else if (ref_we) begin
      refresh <= ctl_wd;
    end else if (rf_take) begin
      refresh <= {refresh[15:9], rf_row_next};
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      psap       <= 32'h0;
      nspoff     <= 16'h0;
      nspseg     <= 16'h0;
      refresh_en <= 1'b0;
    end else if (ctl_we) begin
      unique case (ctl_sel)
        3'd3:    refresh_en <= ctl_wd[15];
        3'd4:    psap[31:16] <= {9'd0, ctl_wd[14:8]};
        3'd5:    psap[15:0]  <= ctl_wd;
        3'd6:    nspseg      <= ctl_wd;
        3'd7:    nspoff      <= ctl_wd;
        default: ;
      endcase
    end
  end

  // Inputs and registers that later control units will consume.
  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{stop_n, busreq_n, nmi_n, nvi_n, vi_n, segt_n, abort_n, mi_n,
                       rf_rdata[63:32], fcw[13:8], fcw[3:0], psap, refresh[15], nspoff, nspseg,
                       halted, ir_w0[15:12], sh_cnt[14:6],
                       ctrl_q.priv, ctrl_q.fcw_op, ctrl_q.fcw_mask, ctrl_q.stk_mode,
                       ctrl_q.br_mode, ctrl_q.io_spec, ctrl_q.mp_op};
  // verilator lint_on UNUSEDSIGNAL

  // synthesis translate_off
  // Unit and program in step; read by the testbench.
  // verilator lint_off UNUSEDSIGNAL
  logic check_q = 1'b0;
  // verilator lint_on UNUSEDSIGNAL
  logic [31:0] chk_src_q;
  logic        last_d1_q = 1'b0, sh_run_q = 1'b0, sh_prev_q = 1'b0;
  logic [3:0] md_at;
  assign md_at = 4'd3 + {3'd0, md_x || col_nx == MC_COL_SS} + (col_nx == MC_COL_SL ? 4'd3 : 4'd0);
  always_ff @(posedge clk) begin
    if (md_on && md_dax && md_at_hit != (md_clk_q == md_at)) begin
      $display("%%Error: %m: multiply/divide start clock differs");
      check_q <= 1'b1;
    end
    if (md_start && md_pend_q) begin
      $display("%%Error: %m: multiply/divide started twice");
      check_q <= 1'b1;
    end
    // The operands read through ports A and B are the registers as the
    // unit starts.
    if (md_start) begin
      chk_src_q <= md_long ? {u_regfile.r[{ir_w0[7:5], 1'b0}], u_regfile.r[{ir_w0[7:5], 1'b1}]}
                           : {16'h0000, u_regfile.r[ir_w0[7:4]]};
      if (rf_rdata != {u_regfile.r[{ir_w0[3:2], 2'b00}], u_regfile.r[{ir_w0[3:2], 2'b01}],
                       u_regfile.r[{ir_w0[3:2], 2'b10}], u_regfile.r[{ir_w0[3:2], 2'b11}]}) begin
        $display("%%Error: %m: multiply/divide destination read differs");
        check_q <= 1'b1;
      end
    end
    if (md_pick_q && !md_tick) begin
      $display("%%Error: %m: register source pick on a held clock");
      check_q <= 1'b1;
    end
    // The units end with the program: the write is the clock after its last.
    if (md_wb != (md_pend_q && last_d1_q)) begin
      $display("%%Error: %m: multiply/divide unit and program out of step");
      check_q <= 1'b1;
    end
    // The shifter's last step ends with the program.
    sh_run_q <= sh_start || (sh_run_q && !sh_done);
    if ((sh_run_q && sh_done) != (last_d1_q && sh_prev_q)) begin
      $display("%%Error: %m: shift unit and program out of step");
      check_q <= 1'b1;
    end
    sh_prev_q <= sh_wb;
    last_d1_q <= ex_last;
    if (md_pick_q && md_src != chk_src_q) begin
      $display("%%Error: %m: multiply/divide register source read differs");
      check_q <= 1'b1;
    end
  end
  // synthesis translate_on

endmodule
