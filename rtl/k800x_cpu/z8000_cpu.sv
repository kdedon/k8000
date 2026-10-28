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

  assign rf_wdata = {48'd0, ex_wdata};

  // ---- control and bus ------------------------------------------------------
  logic        fcw_we, pc_we;
  logic [15:0] fcw_d;
  logic [31:0] pc_d;
  logic [15:0] dec_w0;
  logic [3:0]  dec_w1_lo;
  ctrl_word_t  ctrl, ctrl_q;
  logic        ex_handles, ex_last, ex_last2, ex_flags_we;
  logic [15:0] ir_w0, ir_w1, ir_w2;
  logic [22:0] ir_ea;
  logic [15:0] ex_flags, ex_flags_mask;
  logic        rf_pending, rf_take;
  logic [8:0]  rf_row_next, rf_cyc_row;
  logic [22:0] rf_addr;
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
  logic        md_take, blk_more, mult_more, mreq_more, halt_exit;
  mc_path_e    md_path;
  logic [15:0] rf_count;
  assign md_take   = 1'b0;             // multiply/divide operand: zero, overflow
  assign md_path   = MC_PATH_DEFAULT;
  assign rf_count  = 16'h0000;         // SDA/SDL count register read
  assign blk_more  = 1'b0;             // block count register and compare
  assign mult_more = 1'b0;             // MULTL extra adds
  assign mreq_more = 1'b0;             // MREQ's MI handshake
  assign halt_exit = 1'b0;             // HALT's exit on an interrupt

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
    .md_path      (md_path),
    .more         (more),
    .iter         (iter),
    .ex_handles   (ex_handles),
    .ex_last2     (ex_last2),
    .ex_last      (ex_last),
    .ir_w0        (ir_w0),
    .ir_w1        (ir_w1),
    .ir_w2        (ir_w2),
    .ir_ea        (ir_ea),
    .rf_pending   (rf_pending),
    .rf_addr      (rf_addr),
    .rf_take      (rf_take),
    .bus_req      (bus_req),
    .bus_internal (bus_internal),
    .bus_addr     (bus_addr),
    .bus_st       (bus_st),
    .bus_normal   (bus_normal),
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
  logic [15:0] sh_cnt;
  logic [5:0]  sh_n;
  assign sh_cnt = ctrl_q.count == SRC_REG ? rf_count : ir_w1;
  // Legal counts are at most 32 (long), so six bits.
  assign sh_n   = sh_cnt[15] ? 6'd0 - sh_cnt[5:0] : sh_cnt[5:0];

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

  z8000_execute u_execute (
    .clk        (clk),
    .reset_n    (reset_n),
    .w0         (ir_w0[11:0]),
    .valid      (ctrl_q.valid),
    .exec       (ctrl_q.exec),
    .alu_op     (ctrl_q.alu_op),
    .width      (ctrl_q.width),
    .src2       (ctrl_q.src2),
    .dst        (ctrl_q.dst),
    .src1_nib   (ctrl_q.src1_nib),
    .src2_nib   (ctrl_q.src2_nib),
    .dst_nib    (ctrl_q.dst_nib),
    .w1         (ir_w1),
    .w2         (ir_w2),
    .handles    (ex_handles),
    .last2      (ex_last2),
    .last       (ex_last),
    .rf_rwidth  (rf_rwidth),
    .rf_rsel    (rf_rsel),
    .rf_rdata   (rf_rdata[15:0]),
    .rf_rbyte_b (rf_rbyte_b),
    .rf_rsel_b  (rf_rsel_b),
    .rf_rdata_b (rf_rdata_b),
    .rf_we      (rf_we),
    .rf_wwidth  (rf_wwidth),
    .rf_wsel    (rf_wsel),
    .rf_wdata   (ex_wdata),
    .fcw_c      (fcw[7]),
    .flags_we   (ex_flags_we),
    .flags      (ex_flags),
    .flags_mask (ex_flags_mask)
  );

  // Control-register loads (LDCTL and friends) have no source yet.
  logic        ctl_we;
  logic [31:0] ctl_d;
  assign ctl_we = 1'b0;
  assign ctl_d  = 32'h0;

  z8000_refresh u_refresh (
    .clk      (clk),
    .reset_n  (reset_n),
    .enable   (refresh_en),
    .rate     (refresh[14:9]),
    .row      (refresh[8:0]),
    .load     (ctl_we && ctl_d[15]),
    .load_rate(ctl_d[14:9]),
    .take     (rf_take),
    .pending  (rf_pending),
    .row_next (rf_row_next),
    .cyc_row  (rf_cyc_row)
  );

  // Refresh addresses take the PC segment in nonsegmented mode.
  assign rf_addr = {(SEGMENTED && !fcw[15]) ? pc[22:16] : 7'd0, 7'd0, rf_cyc_row};

  // Memory data and EPU transfers have no requester yet.
  z8000_bus_unit #(.SEGMENTED(SEGMENTED)) u_bus (
    .clk            (clk),
    .reset_n        (reset_n),
    .req            (bus_req),
    .req_internal   (bus_internal),
    .req_addr       (bus_addr),
    .req_wdata      (16'h0000),
    .req_st         (bus_st),
    .req_write      (1'b0),
    .req_byte       (1'b0),
    .req_epu_drives (1'b0),
    .req_normal     (bus_normal),
    .req_len        (bus_len),
    .tail           (bus_tail),
    .cyc_end        (bus_cyc_end),
    .cyc_end3       (bus_cyc_end3),
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
  assign mo_n     = 1'b1;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      fcw <= 16'h0000;
      pc  <= 32'h0;
    end else begin
      if (fcw_we)           fcw <= fcw_d;
      else if (ex_flags_we) fcw <= (fcw & ~ex_flags_mask) | (ex_flags & ex_flags_mask);
      if (pc_we)            pc  <= pc_d;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      refresh <= 16'h0;
    end else if (ctl_we) begin
      refresh <= ctl_d[15:0];
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
      psap       <= ctl_d;
      nspoff     <= ctl_d[15:0];
      nspseg     <= ctl_d[31:16];
      refresh_en <= ctl_d[15];
    end
  end

  // Inputs and registers that later control units will consume.
  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{stop_n, busreq_n, nmi_n, nvi_n, vi_n, segt_n, abort_n, mi_n,
                       rf_rdata[63:16], fcw[13:8], fcw[3:0], psap, refresh[15], nspoff, nspseg,
                       halted, VMPU, ir_w0[15:12], ir_ea, sh_cnt[14:6],
                       ctrl_q.priv, ctrl_q.fcw_op, ctrl_q.fcw_mask, ctrl_q.stk_mode,
                       ctrl_q.br_mode, ctrl_q.io_write, ctrl_q.io_spec, ctrl_q.block_decr,
                       ctrl_q.block_rept, ctrl_q.mp_op};
  // verilator lint_on UNUSEDSIGNAL

endmodule
