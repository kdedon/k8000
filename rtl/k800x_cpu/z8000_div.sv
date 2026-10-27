// z8000_div -- bit-serial shift-subtract divide sequencer.
//
// Signed DIV (32/16) / DIVL (64/32) on magnitudes, restoring, one quotient
// bit per step MSB first. Phases: setup, overflow check, one step per bit,
// finish. Divide by zero ends at setup; overflow ends at the overflow check.
//
// The clock after the divisor arrives classifies the operands by magnitude
// compares and takes quotient bit N, the trial subtraction of the dividend's
// high half. A quotient one bit too wide (wide_quot: low N bits stored, C
// set) still finishes with the overflow check, so its remaining bits are
// formed two per clock through two cascaded subtract stages. Signs are
// applied in place once the last bit is in.
//
// Port protocol as z8000_mult. Outputs are valid when done; the quotient
// rounds toward zero and the remainder takes the dividend's sign.

module z8000_div (
  input  logic        clk,
  input  logic        reset_n,
  input  logic        start,
  input  logic        n32,         // 0 = DIV (32/16), 1 = DIVL (64/32)
  input  logic [63:0] dividend,
  input  logic        src_valid,
  input  logic [31:0] divisor,     // sign-extended to N bits by the caller
  output logic        done,
  output logic        div_by_zero,
  output logic        overflow,
  output logic        wide_quot,
  output logic        quot_neg,
  output logic        quot_zero,
  output logic [31:0] quotient,
  output logic [31:0] remainder,
  output logic [9:0]  remaining
);

  // Clocks per phase.
  localparam logic [4:0] SETUP_CLKS_W   = 5'd10;
  localparam logic [4:0] SETUP_CLKS_L   = 5'd27;
  localparam logic [4:0] OVCHECK_CLKS_W = 5'd12;
  localparam logic [4:0] OVCHECK_CLKS_L = 5'd21;
  localparam logic [4:0] STEP_CLKS_W    = 5'd5;
  localparam logic [4:0] STEP_CLKS_L    = 5'd21;
  localparam logic [4:0] FINISH_CLKS_W  = 5'd2;
  localparam logic [4:0] FINISH_CLKS_L  = 5'd21;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_SETUP,
    ST_OVCHECK,
    ST_ITER,
    ST_FINISH,
    ST_DONE
  } state_e;

  state_e      state_q, state_d;
  logic [4:0]  rem_q, rem_d;        // clocks left in the current phase/step
  logic        long_q;
  logic        dvd_neg_q;
  logic        have_op_q, dvr_neg_q, dbz_q;
  logic [31:0] dvr_q;               // |divisor|
  logic        cls_q, ovf_q, wide_q;
  logic [31:0] prem_q, prem_d;      // partial remainder
  logic [32:0] dlo_q, dlo_d;        // dividend bits N..0, shifted left per step
  logic [32:0] quo_q, quo_d;        // quotient bits N..0
  logic [5:0]  cnt_q, cnt_d;        // quotient bits formed
  logic        stored_q;            // signs applied
  logic        qneg_q, qzero_q;

  // ---- operands ---------------------------------------------------------------
  // The first src_valid pulse after start (or with it) is the divisor.
  logic        long_cur, arrive;
  logic [63:0] dvd_abs_in;
  logic        dvd_neg_in;
  logic [31:0] dvr_ext, dvr_abs_in;
  logic        dvr_neg_in, dbz_in, res_neg;

  always_comb begin
    long_cur   = start ? n32 : long_q;
    arrive     = src_valid && (start || (state_q == ST_SETUP && !have_op_q));

    dvd_neg_in = n32 ? dividend[63] : dividend[31];
    dvd_abs_in = n32 ? dividend : {32'd0, dividend[31:0]};
    if (dvd_neg_in) dvd_abs_in = n32 ? 64'd0 - dividend : {32'd0, 32'd0 - dividend[31:0]};

    dvr_ext    = long_cur ? divisor : {{16{divisor[15]}}, divisor[15:0]};
    dvr_neg_in = dvr_ext[31];
    dvr_abs_in = dvr_neg_in ? 32'd0 - dvr_ext : dvr_ext;
    dbz_in     = (dvr_ext == 32'd0);
    res_neg    = dvd_neg_q ^ dvr_neg_q;
  end

  // ---- classification -----------------------------------------------------------
  // Case 1 needs quotient < 2^(N-1) (<= for a negative result); case 3 is
  // past -2^N..2^N-1. The added |divisor| shares no set bit with the shifted
  // one, so OR is the sum.
  logic [63:0] dvd_abs, dvr64, thr_fit, thr_wide;
  logic        cls_now, ovf_any, ovf_far;

  always_comb begin
    dvd_abs  = long_q ? {prem_q[30:0], dlo_q} : {32'd0, prem_q[14:0], dlo_q[32:16]};
    dvr64    = {32'd0, dvr_q};
    thr_fit  = (long_q ? dvr64 << 31 : dvr64 << 15) | (res_neg ? dvr64 : 64'd0);
    thr_wide = (long_q ? dvr64 << 32 : dvr64 << 16) | (res_neg ? dvr64 : 64'd0);
    ovf_any  = (dvd_abs >= thr_fit);
    ovf_far  = (dvd_abs >= thr_wide);
    cls_now  = have_op_q && !cls_q && !dbz_q && !start;
  end

  // ---- two trial-subtract stages --------------------------------------------------
  // The borrow says whether the divisor fits. Bit 32 of a trial stays clear
  // while the partial remainder is below |divisor| <= 2^31; it is kept so the
  // fit test holds for any operand.
  logic [32:0] trial_a, trial_b, diff_a, diff_b;
  logic [31:0] prem_a, prem_b;
  logic        fit_a, fit_b;

  always_comb begin
    trial_a = {prem_q, dlo_q[32]};
    diff_a  = {1'b0, trial_a[31:0]} - {1'b0, dvr_q};
    fit_a   = trial_a[32] || !diff_a[32];
    prem_a  = fit_a ? diff_a[31:0] : trial_a[31:0];
    trial_b = {prem_a, dlo_q[31]};
    diff_b  = {1'b0, trial_b[31:0]} - {1'b0, dvr_q};
    fit_b   = trial_b[32] || !diff_b[32];
    prem_b  = fit_b ? diff_b[31:0] : trial_b[31:0];
  end

  // ---- control --------------------------------------------------------------------
  logic       stalled, leave, step, step2, store, all_bits;
  logic [4:0] rem_dec;

  always_comb begin
    state_d  = state_q;
    rem_d    = rem_q;
    step     = 1'b0;
    rem_dec  = rem_q - 5'd1;
    stalled  = (rem_q == 5'd0);
    leave    = 1'b0;
    all_bits = (cnt_q == (long_q ? 6'd33 : 6'd17));

    unique case (state_q)
      ST_SETUP: begin
        // A stalled setup leaves on the arrival edge, which also counts as the
        // first clock of the next phase.
        leave = stalled ? arrive : (rem_dec == 5'd0) && (have_op_q || arrive);
        if (!stalled) rem_d = rem_dec;
        if (leave) begin
          if (arrive ? dbz_in : dbz_q) begin
            state_d = ST_DONE;
          end else begin
            state_d = ST_OVCHECK;
            rem_d   = long_q ? OVCHECK_CLKS_L : OVCHECK_CLKS_W;
            if (stalled) rem_d = rem_d - 5'd1;
          end
        end
      end
      ST_OVCHECK: begin
        rem_d = rem_dec;
        if (rem_dec == 5'd0) begin
          if (ovf_q || wide_q) begin
            state_d = ST_DONE;
          end else begin
            state_d = ST_ITER;
            step    = 1'b1;
            rem_d   = long_q ? STEP_CLKS_L : STEP_CLKS_W;
          end
        end
      end
      ST_ITER: begin
        rem_d = rem_dec;
        if (rem_dec == 5'd0) begin
          if (all_bits) begin
            state_d = ST_FINISH;
            rem_d   = long_q ? FINISH_CLKS_L : FINISH_CLKS_W;
          end else begin
            step  = 1'b1;
            rem_d = long_q ? STEP_CLKS_L : STEP_CLKS_W;
          end
        end
      end
      ST_FINISH: begin
        rem_d = rem_dec;
        if (rem_dec == 5'd0) state_d = ST_DONE;
      end
      default: ;
    endcase

    step2 = wide_q && !all_bits && (state_q == ST_SETUP || state_q == ST_OVCHECK);
    store = all_bits && !stored_q && (state_q != ST_IDLE);

    if (start) begin
      state_d = ST_SETUP;
      rem_d   = n32 ? SETUP_CLKS_L : SETUP_CLKS_W;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q <= ST_IDLE;
      rem_q   <= 5'd0;
    end else begin
      state_q <= state_d;
      rem_q   <= rem_d;
    end
  end

  // Dividend sign and width, captured at start.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      long_q    <= 1'b0;
      dvd_neg_q <= 1'b0;
    end else if (start) begin
      long_q    <= n32;
      dvd_neg_q <= dvd_neg_in;
    end
  end

  // Divisor magnitude and sign, captured on arrival.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      have_op_q <= 1'b0;
      dvr_neg_q <= 1'b0;
      dbz_q     <= 1'b0;
      dvr_q     <= 32'd0;
    end else if (arrive) begin
      have_op_q <= 1'b1;
      dvr_neg_q <= dvr_neg_in;
      dbz_q     <= dbz_in;
      dvr_q     <= dvr_abs_in;
    end else if (start) begin
      have_op_q <= 1'b0;
      dvr_neg_q <= 1'b0;
      dbz_q     <= 1'b0;
      dvr_q     <= 32'd0;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      cls_q  <= 1'b0;
      ovf_q  <= 1'b0;
      wide_q <= 1'b0;
    end else if (start) begin
      cls_q  <= 1'b0;
      ovf_q  <= 1'b0;
      wide_q <= 1'b0;
    end else if (cls_now) begin
      cls_q  <= 1'b1;
      ovf_q  <= ovf_far;
      wide_q <= ovf_any && !ovf_far;
    end
  end

  // ---- datapath -------------------------------------------------------------------
  always_comb begin
    prem_d = prem_q;
    dlo_d  = dlo_q;
    quo_d  = quo_q;
    cnt_d  = cnt_q;
    if (start) begin
      prem_d = n32 ? {1'b0, dvd_abs_in[63:33]} : {17'd0, dvd_abs_in[31:17]};
      dlo_d  = n32 ? dvd_abs_in[32:0] : {dvd_abs_in[16:0], 16'h0000};
      quo_d  = 33'd0;
      cnt_d  = 6'd0;
    end else if (cls_now || step) begin
      prem_d = prem_a;
      dlo_d  = {dlo_q[31:0], 1'b0};
      quo_d  = {quo_q[31:0], fit_a};
      cnt_d  = cnt_q + 6'd1;
    end else if (step2) begin
      prem_d = prem_b;
      dlo_d  = {dlo_q[30:0], 2'b00};
      quo_d  = {quo_q[30:0], fit_a, fit_b};
      cnt_d  = cnt_q + 6'd2;
    end else if (store) begin
      prem_d = dvd_neg_q ? 32'd0 - prem_q : prem_q;
      quo_d  = res_neg ? 33'd0 - quo_q : quo_q;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      prem_q <= 32'd0;
      dlo_q  <= 33'd0;
      quo_q  <= 33'd0;
      cnt_q  <= 6'd0;
    end else begin
      prem_q <= prem_d;
      dlo_q  <= dlo_d;
      quo_q  <= quo_d;
      cnt_q  <= cnt_d;
    end
  end

  // S and Z of the full quotient, before the sign is applied.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      stored_q <= 1'b0;
      qneg_q   <= 1'b0;
      qzero_q  <= 1'b0;
    end else if (start) begin
      stored_q <= 1'b0;
      qneg_q   <= 1'b0;
      qzero_q  <= 1'b0;
    end else if (store) begin
      stored_q <= 1'b1;
      qneg_q   <= res_neg && (quo_q != 33'd0);
      qzero_q  <= (quo_q == 33'd0);
    end
  end

  // ---- outputs --------------------------------------------------------------------
  logic [31:0] nmask;

  always_comb begin
    nmask       = long_q ? 32'hFFFF_FFFF : 32'h0000_FFFF;
    done        = (state_q == ST_DONE);
    div_by_zero = dbz_q;
    overflow    = ovf_q;
    wide_quot   = wide_q;
    quot_neg    = qneg_q;
    quot_zero   = qzero_q;
    quotient    = stored_q ? quo_q[31:0] & nmask : 32'd0;
    remainder   = stored_q ? prem_q & nmask : 32'd0;
    remaining   = 10'd0;
    if (state_q != ST_DONE && state_q != ST_IDLE)
      remaining = (rem_q == 5'd0) ? 10'd1 : {5'd0, rem_q};
  end

endmodule
