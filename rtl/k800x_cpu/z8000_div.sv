// z8000_div -- bit-serial shift-subtract divide sequencer.
//
// Signed DIV (32/16) / DIVL (64/32) on magnitudes, restoring, one quotient
// bit per step MSB first, on the step's last clock. Phases: setup, then one
// of three paths picked by the divisor when setup ends: the trial and one
// step per bit, divide by zero, or overflow.
//
// The path is picked by magnitude compares, on the registered divisor or on
// the arriving one. A quotient one bit too wide (wide_quot: low N bits
// stored, C set) is formed during the overflow phase, two bits per clock
// through two cascaded subtract stages, then signed in place.
//
// The divisor may arrive (src_valid) after setup ends; as in z8000_mult the
// clocks waited count toward the path it picks, but the overflow path keeps
// the clocks that wide quotient needs after the arrival. Outputs are valid
// when done; the quotient rounds toward zero and the remainder takes the
// dividend's sign.

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
  localparam logic [6:0] SETUP_CLKS  = 7'd2;
  localparam logic [6:0] TRIAL_CLKS_W = 7'd6;
  localparam logic [6:0] TRIAL_CLKS_L = 7'd67;
  localparam logic [6:0] STEP_CLKS_W = 7'd6;
  localparam logic [6:0] STEP_CLKS_L = 7'd21;
  localparam logic [6:0] ZERO_CLKS_W = 7'd8;
  localparam logic [6:0] ZERO_CLKS_L = 7'd25;
  localparam logic [6:0] OVF_CLKS_W  = 7'd20;
  localparam logic [6:0] OVF_CLKS_L  = 7'd46;
  // Overflow clocks after a late divisor's: bit N, the N bits in pairs, signs.
  localparam logic [6:0] OVF_WORK_W  = 7'd10;
  localparam logic [6:0] OVF_WORK_L  = 7'd18;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_SETUP,
    ST_WAIT,     // setup done, no divisor yet
    ST_TRIAL,
    ST_STEP,
    ST_ZERO,
    ST_OVF,
    ST_DONE
  } state_e;

  state_e      state_q, state_d;
  logic [6:0]  rem_q, rem_d;        // clocks left in the current phase
  logic [6:0]  spent_q, spent_d;    // clocks waited, saturating
  logic        long_q;
  logic        dvd_neg_q;
  logic        have_op_q, dvr_neg_q, dbz_q;
  logic [31:0] dvr_q;               // |divisor|
  logic        ovf_q, wide_q;
  logic [31:0] prem_q, prem_d;      // partial remainder
  logic [32:0] dlo_q, dlo_d;        // dividend bits N..0, shifted left per step
  logic [32:0] quo_q, quo_d;        // quotient bits N..0
  logic [5:0]  cnt_q, cnt_d;        // quotient bits formed
  logic        stored_q;            // signs applied
  logic        qneg_q, qzero_q;

  // ---- operands ---------------------------------------------------------------
  // The first src_valid pulse after start (or with it) is the divisor.
  logic        long_cur, arrive, op_now;
  logic [63:0] dvd_abs_in;
  logic        dvd_neg_in;
  logic [31:0] dvr_ext, dvr_abs_in;
  logic        dvr_neg_in, dbz_in, res_neg;

  always_comb begin
    long_cur   = start ? n32 : long_q;
    arrive     = src_valid && (start || (!have_op_q && (state_q == ST_SETUP || state_q == ST_WAIT)));
    op_now     = have_op_q || arrive;

    dvd_neg_in = n32 ? dividend[63] : dividend[31];
    dvd_abs_in = n32 ? dividend : {32'd0, dividend[31:0]};
    if (dvd_neg_in) dvd_abs_in = n32 ? 64'd0 - dividend : {32'd0, 32'd0 - dividend[31:0]};

    dvr_ext    = long_cur ? divisor : {{16{divisor[15]}}, divisor[15:0]};
    dvr_neg_in = dvr_ext[31];
    dvr_abs_in = dvr_neg_in ? 32'd0 - dvr_ext : dvr_ext;
    dbz_in     = (dvr_ext == 32'd0);
    res_neg    = dvd_neg_q ^ dvr_neg_q;
  end

  // ---- path ---------------------------------------------------------------------
  // Case 1 needs quotient < 2^(N-1) (<= for a negative result); case 3 is
  // past -2^N..2^N-1. The added |divisor| shares no set bit with the shifted
  // one, so OR is the sum. The dividend is still unshifted here.
  logic [63:0] dvd_abs, dvr64, thr_fit, thr_wide;
  logic        cmp_neg, cmp_dbz, ovf_any, ovf_far;

  always_comb begin
    dvd_abs  = long_q ? {prem_q[30:0], dlo_q} : {32'd0, prem_q[14:0], dlo_q[32:16]};
    dvr64    = {32'd0, arrive ? dvr_abs_in : dvr_q};
    cmp_neg  = dvd_neg_q ^ (arrive ? dvr_neg_in : dvr_neg_q);
    cmp_dbz  = arrive ? dbz_in : dbz_q;
    thr_fit  = (long_q ? dvr64 << 31 : dvr64 << 15) | (cmp_neg ? dvr64 : 64'd0);
    thr_wide = (long_q ? dvr64 << 32 : dvr64 << 16) | (cmp_neg ? dvr64 : 64'd0);
    ovf_any  = (dvd_abs >= thr_fit);
    ovf_far  = (dvd_abs >= thr_wide);
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
  // Each path's count for a late divisor is formed from the clocks waited,
  // before the divisor picks one. A path the wait covers ends on arrival.
  logic       ends, pick, seed, step, step2, store, all_bits, last_bit;
  logic       cov_trial, cov_zero, cov_ovf;
  logic [6:0] rem_dec, step_clks, trial_clks, zero_clks, ovf_clks;
  logic [6:0] late_trial, late_zero, late_ovf, ovf_work;

  always_comb begin
    state_d    = state_q;
    rem_d      = rem_q;
    spent_d    = spent_q;
    pick       = 1'b0;
    seed       = 1'b0;
    step       = 1'b0;
    step2      = 1'b0;
    store      = 1'b0;
    rem_dec    = rem_q - 7'd1;
    ends       = (rem_dec == 7'd0);
    all_bits   = (cnt_q == (long_q ? 6'd33 : 6'd17));
    last_bit   = (cnt_q == (long_q ? 6'd32 : 6'd16));
    step_clks  = long_q ? STEP_CLKS_L  : STEP_CLKS_W;
    trial_clks = long_q ? TRIAL_CLKS_L : TRIAL_CLKS_W;
    zero_clks  = long_q ? ZERO_CLKS_L  : ZERO_CLKS_W;
    ovf_clks   = long_q ? OVF_CLKS_L   : OVF_CLKS_W;
    late_trial = trial_clks - spent_q - 7'd1;
    late_zero  = zero_clks  - spent_q - 7'd1;
    ovf_work   = long_q ? OVF_WORK_L   : OVF_WORK_W;
    late_ovf   = ovf_clks   - spent_q - 7'd1;
    cov_trial  = (spent_q >= trial_clks - 7'd1);
    cov_zero   = (spent_q >= zero_clks  - 7'd1);
    cov_ovf    = (spent_q >= ovf_clks   - ovf_work - 7'd1);

    unique case (state_q)
      ST_SETUP: begin
        rem_d = rem_dec;
        if (ends) begin
          pick = op_now;
          if (!op_now) begin
            state_d = ST_WAIT;
          end else if (cmp_dbz) begin
            state_d = ST_ZERO;
            rem_d   = zero_clks;
          end else if (ovf_any) begin
            state_d = ST_OVF;
            rem_d   = ovf_clks;
          end else begin
            state_d = ST_TRIAL;
            rem_d   = trial_clks;
          end
        end
      end
      ST_WAIT: begin
        pick = arrive;
        if (!arrive) begin
          if (spent_q != 7'h7F) spent_d = spent_q + 7'd1;
        end else if (cmp_dbz) begin
          state_d = cov_zero ? ST_DONE : ST_ZERO;
          rem_d   = cov_zero ? 7'd0 : late_zero;
        end else if (ovf_any) begin
          state_d = ST_OVF;
          rem_d   = cov_ovf ? ovf_work : late_ovf;
        end else begin
          seed    = cov_trial;
          state_d = cov_trial ? ST_STEP : ST_TRIAL;
          rem_d   = cov_trial ? step_clks : late_trial;
        end
      end
      // The trial ends by moving the dividend's high half into the partial
      // remainder; quotient bit N is 0 on this path.
      ST_TRIAL: begin
        rem_d = rem_dec;
        if (ends) begin
          seed    = 1'b1;
          state_d = ST_STEP;
          rem_d   = step_clks;
        end
      end
      ST_STEP: begin
        rem_d = rem_dec;
        if (ends) begin
          step    = 1'b1;
          store   = last_bit;
          state_d = last_bit ? ST_DONE : ST_STEP;
          rem_d   = last_bit ? 7'd0 : step_clks;
        end
      end
      ST_ZERO: begin
        rem_d = rem_dec;
        if (ends) begin
          state_d = ST_DONE;
          rem_d   = 7'd0;
        end
      end
      ST_OVF: begin
        rem_d = rem_dec;
        if (ends) begin
          state_d = ST_DONE;
          rem_d   = 7'd0;
        end
        // Case 4: quotient bit N, then two bits per clock, then the signs.
        if (wide_q && !stored_q) begin
          if (cnt_q == 6'd0)  step  = 1'b1;
          else if (!all_bits) step2 = 1'b1;
          else                store = 1'b1;
        end
      end
      default: ;
    endcase

    if (start) begin
      state_d = ST_SETUP;
      rem_d   = SETUP_CLKS;
      spent_d = 7'd0;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q <= ST_IDLE;
      rem_q   <= 7'd0;
      spent_q <= 7'd0;
    end else begin
      state_q <= state_d;
      rem_q   <= rem_d;
      spent_q <= spent_d;
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

  // Overflow class, captured when the path is picked.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ovf_q  <= 1'b0;
      wide_q <= 1'b0;
    end else if (start) begin
      ovf_q  <= 1'b0;
      wide_q <= 1'b0;
    end else if (pick && !cmp_dbz) begin
      ovf_q  <= ovf_far;
      wide_q <= ovf_any && !ovf_far;
    end
  end

  // ---- datapath -------------------------------------------------------------------
  logic [32:0] quo_mag;

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
    end else if (seed) begin
      prem_d = trial_a[31:0];
      dlo_d  = {dlo_q[31:0], 1'b0};
      cnt_d  = 6'd1;
    end else if (step) begin
      prem_d = prem_a;
      dlo_d  = {dlo_q[31:0], 1'b0};
      quo_d  = {quo_q[31:0], fit_a};
      cnt_d  = cnt_q + 6'd1;
    end else if (step2) begin
      prem_d = prem_b;
      dlo_d  = {dlo_q[30:0], 2'b00};
      quo_d  = {quo_q[30:0], fit_a, fit_b};
      cnt_d  = cnt_q + 6'd2;
    end
    // The signs are applied with the last step or on a clock of their own.
    quo_mag = step ? {quo_q[31:0], fit_a} : quo_q;
    if (store) begin
      prem_d = dvd_neg_q ? 32'd0 - prem_d : prem_d;
      quo_d  = res_neg ? 33'd0 - quo_mag : quo_mag;
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
      qneg_q   <= res_neg && (quo_mag != 33'd0);
      qzero_q  <= (quo_mag == 33'd0);
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
      remaining = (rem_q == 7'd0) ? 10'd1 : {3'd0, rem_q};
  end

endmodule
