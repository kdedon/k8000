// z8000_mult -- bit-serial shift-add multiplier sequencer.
//
// Signed MULT (16x16) / MULTL (32x32). One multiplicand bit is folded per
// step, LSB first, on the step's last clock: the multiplier, shifted left one
// place per step, is added to the accumulator when the bit is set (subtracted
// for the sign bit).
//
// Phases: setup, one step per bit, then for MULTL one extra add per 1 in the
// absolute value of the multiplicand's low word (read as a signed word) and
// the finish. A zero multiplier replaces the steps with one zero phase.
//
// The multiplier may arrive (src_valid) after setup ends. The clocks waited
// count toward the phase it selects; if they cover it, that phase ends on the
// arrival clock. `remaining` is a lower bound on clocks still needed: the
// current phase's count, 1 while waiting, 0 when done.

module z8000_mult (
  input  logic        clk,
  input  logic        reset_n,
  input  logic        start,
  input  logic        width32,     // 0 = MULT (16x16), 1 = MULTL (32x32)
  input  logic [31:0] dst,         // multiplicand (low half of the destination pair/quad)
  input  logic        src_valid,
  input  logic [31:0] src,         // multiplier
  output logic        done,
  output logic [63:0] product,
  output logic [9:0]  remaining
);

  // Clocks per phase. MULT has no finish.
  localparam logic [4:0] SETUP_CLKS_W  = 5'd3;
  localparam logic [4:0] SETUP_CLKS_L  = 5'd4;
  localparam logic [4:0] STEP_CLKS_W   = 5'd4;
  localparam logic [4:0] STEP_CLKS_L   = 5'd8;
  localparam logic [4:0] ADD_CLKS      = 5'd7;
  localparam logic [4:0] FINISH_CLKS_L = 5'd19;
  localparam logic [4:0] ZERO_CLKS_W   = 5'd12;
  localparam logic [4:0] ZERO_CLKS_L   = 5'd23;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_SETUP,
    ST_WAIT,     // setup done, no multiplier yet
    ST_STEP,
    ST_ADD,
    ST_FINISH,
    ST_ZERO,
    ST_DONE
  } state_e;

  state_e      state_q, state_d;
  logic [4:0]  rem_q, rem_d;        // clocks left in the current phase
  logic [4:0]  spent_q, spent_d;    // clocks waited, saturating
  logic [4:0]  adds_q, adds_d;      // MULTL extra adds still to run
  logic        wide_q;
  logic        have_op_q, have_op_d;
  logic [31:0] cand_q, cand_d;      // multiplicand, shifted right per step
  logic [63:0] addend_q, addend_d;  // multiplier << bit
  logic [63:0] acc_q, acc_d;
  logic [5:0]  bit_q, bit_d;        // multiplicand bit of the current step
  logic        cand_neg_q;          // multiplicand bit 15
  logic        low_one_q, low_one_d; // a lower multiplicand bit was set

  // ---- operand view ---------------------------------------------------------
  // The first src_valid pulse after start (or with it) is the operand.
  logic [63:0] src_ext, mult_now;
  logic        wide_cur, arrive, op_now;

  always_comb begin
    wide_cur = start ? width32 : wide_q;
    src_ext  = wide_cur ? {{32{src[31]}}, src} : {{48{src[15]}}, src[15:0]};
    arrive   = src_valid && (start || (!have_op_q && (state_q == ST_SETUP || state_q == ST_WAIT)));
    op_now   = have_op_q || arrive;
    mult_now = arrive ? src_ext : addend_q;
  end

  // ---- one shift-add step ---------------------------------------------------
  logic [63:0] fold_acc;
  logic        fold_set, fold_last, fold_mag, fold_add;

  always_comb begin
    fold_set  = cand_q[0];
    fold_last = (bit_q == (wide_q ? 6'd31 : 6'd15));
    fold_acc  = acc_q;
    if (fold_set) fold_acc = fold_last ? acc_q - mult_now : acc_q + mult_now;
    // Bit of |low 16 of multiplicand| as a signed word, negated serially:
    // inverted above the lowest set bit.
    fold_mag  = fold_set ^ (cand_neg_q && low_one_q);
    fold_add  = fold_mag && wide_q && (bit_q[5:4] == 2'b00);
  end

  // ---- control --------------------------------------------------------------
  // Both paths' counts for a late multiplier are formed from the clocks
  // waited, before the multiplier picks one. A path the wait covers ends on
  // arrival.
  logic       ends, fold, path_zero, cov_step, cov_zero, bits_done;
  logic [4:0] rem_dec, step_clks, zero_clks, late_step, late_zero, adds_left;
  state_e     next_st;
  logic [4:0] next_clks;

  always_comb begin
    state_d   = state_q;
    rem_d     = rem_q;
    spent_d   = spent_q;
    adds_d    = adds_q;
    have_op_d = have_op_q || arrive;
    fold      = 1'b0;
    bits_done = 1'b0;
    adds_left = adds_q;
    rem_dec   = rem_q - 5'd1;
    ends      = (rem_dec == 5'd0);
    step_clks = wide_q ? STEP_CLKS_L : STEP_CLKS_W;
    zero_clks = wide_q ? ZERO_CLKS_L : ZERO_CLKS_W;
    late_step = step_clks - spent_q - 5'd1;
    late_zero = zero_clks - spent_q - 5'd1;
    cov_step  = (spent_q >= step_clks - 5'd1);
    cov_zero  = (spent_q >= zero_clks - 5'd1);
    path_zero = arrive ? (src[15:0] == 16'd0 && (!wide_cur || src[31:16] == 16'd0))
                       : (addend_q == 64'd0);

    unique case (state_q)
      ST_SETUP: begin
        rem_d = rem_dec;
        if (ends) begin
          if (!op_now) begin
            state_d = ST_WAIT;
          end else begin
            state_d = path_zero ? ST_ZERO : ST_STEP;
            rem_d   = path_zero ? zero_clks : step_clks;
          end
        end
      end
      ST_WAIT: begin
        if (!arrive) begin
          if (spent_q != 5'h1F) spent_d = spent_q + 5'd1;
        end else if (path_zero) begin
          state_d = cov_zero ? ST_DONE : ST_ZERO;
          rem_d   = cov_zero ? 5'd0 : late_zero;
        end else begin
          fold    = cov_step;
          state_d = ST_STEP;
          rem_d   = cov_step ? step_clks : late_step;
        end
      end
      ST_STEP: begin
        rem_d = rem_dec;
        if (ends) begin
          fold      = 1'b1;
          rem_d     = step_clks;
          bits_done = fold_last;
        end
      end
      ST_ADD: begin
        rem_d = rem_dec;
        if (ends) begin
          bits_done = 1'b1;
          adds_left = adds_q - 5'd1;
        end
      end
      ST_FINISH, ST_ZERO: begin
        rem_d = rem_dec;
        if (ends) begin
          state_d = ST_DONE;
          rem_d   = 5'd0;
        end
      end
      default: ;
    endcase

    if (fold) adds_left = adds_q + {4'd0, fold_add};

    // After the last bit and after each add: the next add, the finish, or done.
    if (adds_left != 5'd0) begin
      next_st   = ST_ADD;
      next_clks = ADD_CLKS;
    end else if (wide_q) begin
      next_st   = ST_FINISH;
      next_clks = FINISH_CLKS_L;
    end else begin
      next_st   = ST_DONE;
      next_clks = 5'd0;
    end
    adds_d = adds_left;
    if (bits_done) begin
      state_d = next_st;
      rem_d   = next_clks;
    end

    if (start) begin
      state_d   = ST_SETUP;
      rem_d     = width32 ? SETUP_CLKS_L : SETUP_CLKS_W;
      spent_d   = 5'd0;
      adds_d    = 5'd0;
      have_op_d = arrive;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q   <= ST_IDLE;
      rem_q     <= 5'd0;
      spent_q   <= 5'd0;
      adds_q    <= 5'd0;
      have_op_q <= 1'b0;
    end else begin
      state_q   <= state_d;
      rem_q     <= rem_d;
      spent_q   <= spent_d;
      adds_q    <= adds_d;
      have_op_q <= have_op_d;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      wide_q     <= 1'b0;
      cand_neg_q <= 1'b0;
    end else if (start) begin
      wide_q     <= width32;
      cand_neg_q <= dst[15];
    end
  end

  // ---- datapath -------------------------------------------------------------
  always_comb begin
    cand_d    = cand_q;
    addend_d  = addend_q;
    acc_d     = acc_q;
    bit_d     = bit_q;
    low_one_d = low_one_q;
    if (start) begin
      cand_d    = width32 ? dst : {16'h0000, dst[15:0]};
      addend_d  = arrive ? src_ext : 64'd0;
      acc_d     = 64'd0;
      bit_d     = 6'd0;
      low_one_d = 1'b0;
    end else if (fold) begin
      cand_d    = {1'b0, cand_q[31:1]};
      addend_d  = {mult_now[62:0], 1'b0};
      acc_d     = fold_acc;
      bit_d     = bit_q + 6'd1;
      low_one_d = low_one_q || fold_set;
    end else if (arrive) begin
      addend_d = src_ext;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      cand_q    <= 32'd0;
      addend_q  <= 64'd0;
      acc_q     <= 64'd0;
      bit_q     <= 6'd0;
      low_one_q <= 1'b0;
    end else begin
      cand_q    <= cand_d;
      addend_q  <= addend_d;
      acc_q     <= acc_d;
      bit_q     <= bit_d;
      low_one_q <= low_one_d;
    end
  end

  // ---- outputs --------------------------------------------------------------
  always_comb begin
    done      = (state_q == ST_DONE);
    product   = acc_q;
    remaining = 10'd0;
    if (state_q != ST_DONE && state_q != ST_IDLE)
      remaining = (rem_q == 5'd0) ? 10'd1 : {5'd0, rem_q};
  end

endmodule
