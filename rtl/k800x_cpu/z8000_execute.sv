// z8000_execute -- register and immediate operands through the ALU.
//
// The instruction is decoded from its words for as long as it runs. This
// unit says whether it runs it (`handles`); the machine-cycle program says
// when. The work lands on the program's last clocks: a byte or word op is
// one ALU pass on the last clock, a long op a low-word pass on the second
// last and a high-word pass on the last. Results are written at the end of
// the pass's clock.
//
// A long op's low pass keeps its C and Z for the high pass, which writes
// FCW once, with Z = Z_low & Z_high.

module z8000_execute
  import z8000_ctrl_pkg::*;
(
  input  logic        clk,
  input  logic        reset_n,

  // the running instruction
  input  logic [11:0] w0,           // register nibbles and the low byte
  input  logic        valid,
  input  logic [4:0]  exec,
  input  logic [4:0]  alu_op,
  input  logic [1:0]  width,
  input  logic [4:0]  src2,
  input  logic [3:0]  dst,
  input  logic [1:0]  src1_nib,
  input  logic [1:0]  src2_nib,
  input  logic [1:0]  dst_nib,
  input  logic [15:0] w1,           // instruction words 1 and 2
  input  logic [15:0] w2,
  output logic        handles,
  input  logic        last2,        // the program's second last clock
  input  logic        last,         // the program's last clock

  // register file
  output logic [1:0]  rf_rwidth,
  output logic [3:0]  rf_rsel,
  input  logic [15:0] rf_rdata,
  output logic        rf_rbyte_b,
  output logic [3:0]  rf_rsel_b,
  input  logic [15:0] rf_rdata_b,
  output logic        rf_we,
  output logic [1:0]  rf_wwidth,
  output logic [3:0]  rf_wsel,
  output logic [15:0] rf_wdata,

  // flags
  input  logic        fcw_c,
  output logic        flags_we,
  output logic [15:0] flags,        // FCW bit positions
  output logic [15:0] flags_mask
);

  localparam logic [1:0] RF_BYTE = 2'd0;
  localparam logic [1:0] RF_WORD = 2'd1;

  // ---- which instructions ---------------------------------------------------------
  logic src_mem, dst_mem;

  always_comb begin
    unique case (src2)
      SRC_IR, SRC_DA, SRC_X, SRC_PCREL, SRC_BASED, SRC_BX: src_mem = 1'b1;
      default:                                             src_mem = 1'b0;
    endcase
    dst_mem = !(dst == DST_REG || dst == DST_NONE || dst == DST_FLAGS_ONLY);
  end

  assign handles = valid && exec == CLS_UNIFIED && !src_mem && !dst_mem;

  // ---- passes ---------------------------------------------------------------------------
  logic is_long, is_byte, pass_lo, pass;
  logic high;      // the high pass of a long op
  assign is_long = width == WIDTH_LONG;
  assign is_byte = width == WIDTH_BYTE;
  assign pass_lo = handles && (is_long ? last2 : last);
  assign pass    = pass_lo || high;

  // The high pass is the clock after the low pass.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) high <= 1'b0;
    else          high <= pass_lo && is_long;
  end

  // ---- operands -------------------------------------------------------------------
  function automatic logic [3:0] nib(input logic [11:0] w, input logic [1:0] sel);
    unique case (sel)
      REG_NIB2: return w[7:4];
      REG_NIB1: return w[11:8];
      default:  return w[3:0];
    endcase
  endfunction

  logic [3:0]  ra, rb, rd;
  assign ra = nib(w0, src1_nib);
  assign rb = nib(w0, src2_nib);
  assign rd = nib(w0, dst_nib);

  logic [4:0]  op;
  logic [15:0] a, b;
  logic        cin;
  logic [15:0] value, alu_flags, alu_mask;
  logic        c_lo_q, z_lo_q;

  // A long's register operands are word pairs: high word even, low word odd.
  assign rf_rwidth  = is_byte ? RF_BYTE : RF_WORD;
  assign rf_rsel    = is_long ? {ra[3:1], ~high} : ra;
  assign rf_rbyte_b = is_byte;
  assign rf_rsel_b  = is_long ? {rb[3:1], ~high} : rb;
  assign a          = rf_rdata;

  always_comb begin
    unique case (src2)
      SRC_REG:            b = rf_rdata_b;
      SRC_IMM:            b = is_long ? (high ? w1 : w2) : (is_byte ? {8'h00, w1[15:8]} : w1);
      SRC_ONE:            b = 16'd1;
      SRC_TWO:            b = 16'd2;
      SRC_NIB3_BIT:       b = {12'h000, w0[3:0]};
      SRC_NIB3_CNT_PLUS1: b = {11'h000, {1'b0, w0[3:0]} + 5'd1};
      SRC_OP_LO_BYTE:     b = {8'h00, w0[7:0]};
      default:            b = 16'h0000;
    endcase
  end

  // A long's high pass carries from the low pass; CP's low pass runs as SUB.
  always_comb begin
    op  = alu_op;
    cin = fcw_c;
    if (is_long && !high && alu_op == OP_CP) op = OP_SUB;
    if (high) begin
      cin = c_lo_q;
      unique case (alu_op)
        OP_ADD, OP_ADC:        op = OP_ADC;
        OP_SUB, OP_SBC, OP_CP: op = OP_SBC;
        default:               ;
      endcase
    end
  end

  z8000_alu u_alu (
    .op         (op),
    .width      (is_byte ? WIDTH_BYTE : WIDTH_WORD),
    .a          (a),
    .b          (b),
    .cin        (cin),
    .value      (value),
    .flags      (alu_flags),
    .flags_mask (alu_mask)
  );

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      c_lo_q <= 1'b0;
      z_lo_q <= 1'b0;
    end else if (pass_lo && is_long) begin
      c_lo_q <= alu_flags[7];
      z_lo_q <= alu_flags[6];
    end
  end

  // ---- results ----------------------------------------------------------------------
  assign rf_we     = pass && dst == DST_REG;
  assign rf_wwidth = is_byte ? RF_BYTE : RF_WORD;
  assign rf_wsel   = is_long ? {rd[3:1], ~high} : rd;
  assign rf_wdata  = value;

  always_comb begin
    flags_we   = (pass_lo && !is_long) || high;
    flags      = alu_flags;
    flags_mask = alu_mask;
    if (high) flags[6] = alu_flags[6] & z_lo_q;
  end

endmodule
