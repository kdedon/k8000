// z8000_mult -- bit-serial shift-add multiplier sequencer.
//
// Signed MULT (16x16) / MULTL (32x32). One multiplicand bit is folded per
// step, LSB first: the multiplier, shifted left one place per step, is added
// to the accumulator when the bit is set (subtracted for the sign bit).
// Phases: setup, one step per bit, finish. A zero multiplier skips the steps.
//
// The multiplier may arrive (src_valid) after start; setup stalls at its end
// until it does, and the arrival edge leaves setup. `remaining` is a lower
// bound on clocks still needed: the current phase's count, 0 when done.

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

  // Clocks per phase.
  localparam logic [4:0] SETUP_CLKS     = 5'd2;
  localparam logic [4:0] STEP_CLKS_W    = 5'd4;
  localparam logic [4:0] STEP_CLKS_L    = 5'd8;
  localparam logic [4:0] ADD_CLKS_L     = 5'd7;   // MULTL: set bit in the low 16
  localparam logic [4:0] FINISH_CLKS_W  = 5'd1;
  localparam logic [4:0] FINISH_CLKS_L  = 5'd21;
  localparam logic [4:0] ZFINISH_CLKS_W = 5'd13;
  localparam logic [4:0] ZFINISH_CLKS_L = 5'd25;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_SETUP,
    ST_ITER,
    ST_FINISH,
    ST_DONE
  } state_e;

  state_e      state_q, state_d;
  logic [4:0]  rem_q, rem_d;        // clocks left in the current phase/step
  logic        wide_q;
  logic        have_op_q, have_op_d;
  logic [31:0] cand_q, cand_d;      // multiplicand, shifted right per step
  logic [63:0] addend_q, addend_d;  // multiplier << bit
  logic [63:0] acc_q, acc_d;
  logic [5:0]  bit_q, bit_d;        // next multiplicand bit
  logic        cand_neg_q;          // multiplicand sign
  logic        low_one_q, low_one_d; // a lower multiplicand bit was set

  // ---- operand view ---------------------------------------------------------
  // The first src_valid pulse after start (or with it) is the operand.
  logic [63:0] src_ext, mult_now;
  logic        wide_cur, arrive, op_now;

  always_comb begin
    wide_cur = start ? width32 : wide_q;
    src_ext  = wide_cur ? {{32{src[31]}}, src} : {{48{src[15]}}, src[15:0]};
    arrive   = src_valid && (start || (state_q == ST_SETUP && !have_op_q));
    op_now   = have_op_q || arrive;
    mult_now = arrive ? src_ext : addend_q;
  end

  // ---- one shift-add step ---------------------------------------------------
  logic [63:0] fold_mult, fold_acc;
  logic [4:0]  fold_clks;
  logic        fold_set, fold_last, fold_mag;

  always_comb begin
    fold_mult = (state_q == ST_SETUP) ? mult_now : addend_q;
    fold_set  = cand_q[0];
    fold_last = (bit_q == (wide_q ? 6'd31 : 6'd15));
    fold_acc  = acc_q;
    if (fold_set) fold_acc = fold_last ? acc_q - fold_mult : acc_q + fold_mult;
    // Bit of |multiplicand|, negated serially: inverted above the lowest set bit.
    fold_mag  = fold_set ^ (cand_neg_q && low_one_q);
    fold_clks = wide_q ? STEP_CLKS_L : STEP_CLKS_W;
    if (fold_mag && wide_q && bit_q < 6'd16) fold_clks = fold_clks + ADD_CLKS_L;
  end

  // ---- control --------------------------------------------------------------
  logic       fold;
  logic       leave, stalled;
  logic [4:0] rem_dec;

  always_comb begin
    state_d   = state_q;
    rem_d     = rem_q;
    have_op_d = have_op_q || arrive;
    fold      = 1'b0;
    rem_dec   = rem_q - 5'd1;
    stalled   = (rem_q == 5'd0);
    leave     = 1'b0;

    unique case (state_q)
      ST_SETUP: begin
        // A stalled setup leaves on the arrival edge, which also counts as the
        // first clock of the next phase.
        leave = stalled ? arrive : (rem_dec == 5'd0) && op_now;
        if (!stalled) rem_d = rem_dec;
        if (leave) begin
          if (mult_now == 64'd0) begin
            state_d = ST_FINISH;
            rem_d   = wide_q ? ZFINISH_CLKS_L : ZFINISH_CLKS_W;
          end else begin
            state_d = ST_ITER;
            fold    = 1'b1;
            rem_d   = fold_clks;
          end
          if (stalled) rem_d = rem_d - 5'd1;
        end
      end
      ST_ITER: begin
        rem_d = rem_dec;
        if (rem_dec == 5'd0) begin
          if (bit_q == (wide_q ? 6'd32 : 6'd16)) begin
            state_d = ST_FINISH;
            rem_d   = wide_q ? FINISH_CLKS_L : FINISH_CLKS_W;
          end else begin
            fold  = 1'b1;
            rem_d = fold_clks;
          end
        end
      end
      ST_FINISH: begin
        rem_d = rem_dec;
        if (rem_dec == 5'd0) state_d = ST_DONE;
      end
      default: ;
    endcase

    if (start) begin
      state_d   = ST_SETUP;
      rem_d     = SETUP_CLKS;
      have_op_d = arrive;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q   <= ST_IDLE;
      rem_q     <= 5'd0;
      have_op_q <= 1'b0;
    end else begin
      state_q   <= state_d;
      rem_q     <= rem_d;
      have_op_q <= have_op_d;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      wide_q     <= 1'b0;
      cand_neg_q <= 1'b0;
    end else if (start) begin
      wide_q     <= width32;
      cand_neg_q <= width32 ? dst[31] : dst[15];
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
      addend_d  = {fold_mult[62:0], 1'b0};
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
