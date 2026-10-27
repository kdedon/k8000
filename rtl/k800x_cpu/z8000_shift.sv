// z8000_shift -- bit-serial shifter sequencer.
//
// SLL / SLA / SRL / SRA, one bit position per 3-clock step. The start edge
// shifts position 1; each later step shifts one more. A zero count costs
// one step, shifts nothing and leaves C unaffected. done follows exactly
// 3 * max(count, 1) clocks after start.
//
// Flags (FCW positions): C = last bit out, Z, S. P/V is written by the
// arithmetic forms only, as overflow (SLA: the sign changed at any step;
// SRA: 0).

module z8000_shift
  import z8000_ctrl_pkg::*;
(
  input  logic               clk,
  input  logic               reset_n,
  input  logic               start,
  input  logic [1:0]         width,     // WIDTH_BYTE / WIDTH_WORD / WIDTH_LONG
  input  logic [ALUOP_W-1:0] op,        // OP_SLL / OP_SLA / OP_SRL / OP_SRA
  input  logic [31:0]        val,
  input  logic [5:0]         count,     // 0..32
  output logic               done,
  output logic [31:0]        result,
  output logic [15:0]        flags,
  output logic [15:0]        flags_mask
);

  localparam logic [1:0] STEP_CLKS = 2'd3;

  localparam logic [15:0] F_C = 16'h0080;
  localparam logic [15:0] F_Z = 16'h0040;
  localparam logic [15:0] F_S = 16'h0020;
  localparam logic [15:0] F_V = 16'h0010;

  typedef enum logic [1:0] {
    ST_IDLE,
    ST_RUN,
    ST_DONE
  } state_e;

  state_e      state_q, state_d;
  logic [1:0]  rem_q, rem_d;     // clocks left in the current step
  logic [5:0]  cnt_q, cnt_d;     // positions left, including the current one
  logic [1:0]  width_q;
  logic        left_q, arith_q, zero_n_q;
  logic [31:0] val_q, val_d;
  logic        c_q, c_d;
  logic        ovf_q, ovf_d;

  // ---- operation, from the inputs on the start edge -------------------------
  logic [1:0]  w_cur;
  logic        left_cur, arith_cur, zero_n_cur;
  logic [31:0] wmask, sign;

  always_comb begin
    w_cur      = start ? width : width_q;
    left_cur   = start ? (op == OP_SLL || op == OP_SLA) : left_q;
    arith_cur  = start ? (op == OP_SLA || op == OP_SRA) : arith_q;
    zero_n_cur = start ? (count == 6'd0) : zero_n_q;
    unique case (w_cur)
      WIDTH_BYTE: wmask = 32'h0000_00FF;
      WIDTH_WORD: wmask = 32'h0000_FFFF;
      default:    wmask = 32'hFFFF_FFFF;
    endcase
    sign = wmask & ~(wmask >> 1);
  end

  logic [31:0] sign_q;

  always_comb begin
    unique case (width_q)
      WIDTH_BYTE: sign_q = 32'h0000_0080;
      WIDTH_WORD: sign_q = 32'h0000_8000;
      default:    sign_q = 32'h8000_0000;
    endcase
  end

  // ---- one position ---------------------------------------------------------
  logic [31:0] sh_in, sh_out;
  logic        sh_c, sh_ovf;

  always_comb begin
    sh_in  = start ? (val & wmask) : val_q;
    sh_out = sh_in;
    sh_c   = start ? 1'b0 : c_q;
    sh_ovf = start ? 1'b0 : ovf_q;
    if (!zero_n_cur) begin
      if (left_cur) begin
        sh_c   = |(sh_in & sign);
        sh_out = {sh_in[30:0], 1'b0} & wmask;
        if (|((sh_out ^ sh_in) & sign)) sh_ovf = 1'b1;
      end else begin
        sh_c   = sh_in[0];
        sh_out = {1'b0, sh_in[31:1]} | (arith_cur ? (sh_in & sign) : 32'd0);
      end
    end
  end

  // ---- control --------------------------------------------------------------
  logic shift_now;

  always_comb begin
    state_d   = state_q;
    rem_d     = rem_q;
    cnt_d     = cnt_q;
    shift_now = 1'b0;

    unique case (state_q)
      ST_RUN: begin
        rem_d = rem_q - 2'd1;
        if (rem_q == 2'd1) begin
          cnt_d = cnt_q - 6'd1;
          if (cnt_q == 6'd1) begin
            state_d = ST_DONE;
          end else begin
            rem_d     = STEP_CLKS;
            shift_now = 1'b1;
          end
        end
      end
      default: ;
    endcase

    if (start) begin
      state_d   = ST_RUN;
      rem_d     = STEP_CLKS;
      cnt_d     = (count == 6'd0) ? 6'd1 : count;
      shift_now = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q <= ST_IDLE;
      rem_q   <= 2'd0;
      cnt_q   <= 6'd0;
    end else begin
      state_q <= state_d;
      rem_q   <= rem_d;
      cnt_q   <= cnt_d;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      width_q  <= WIDTH_NONE;
      left_q   <= 1'b0;
      arith_q  <= 1'b0;
      zero_n_q <= 1'b0;
    end else if (start) begin
      width_q  <= width;
      left_q   <= left_cur;
      arith_q  <= arith_cur;
      zero_n_q <= zero_n_cur;
    end
  end

  // ---- datapath -------------------------------------------------------------
  always_comb begin
    val_d = val_q;
    c_d   = c_q;
    ovf_d = ovf_q;
    if (shift_now) begin
      val_d = sh_out;
      c_d   = sh_c;
      ovf_d = sh_ovf;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      val_q <= 32'd0;
      c_q   <= 1'b0;
      ovf_q <= 1'b0;
    end else begin
      val_q <= val_d;
      c_q   <= c_d;
      ovf_q <= ovf_d;
    end
  end

  // ---- outputs --------------------------------------------------------------
  always_comb begin
    done       = (state_q == ST_DONE);
    result     = val_q;
    flags      = 16'h0000;
    if (val_q == 32'd0)  flags = flags | F_Z;
    if (|(val_q & sign_q)) flags = flags | F_S;
    if (c_q)             flags = flags | F_C;
    if (arith_q && left_q && ovf_q) flags = flags | F_V;
    flags_mask = F_Z | F_S;
    if (!zero_n_q) flags_mask = flags_mask | F_C;
    if (arith_q)   flags_mask = flags_mask | F_V;
  end

endmodule
