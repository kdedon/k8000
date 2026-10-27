// z8000_alu -- combinational ALU.
//
// One adder serves ADD/ADC/SUB/SBC/CP/INC/DEC/NEG: subtraction is
// a + ~b + 1 (or + ~C for SBC), so C is the inverted carry-out. Carries the
// flags need are recovered from operand and sum bits:
//   carry into bit k = a[k] ^ b[k] ^ sum[k]   (H uses k = 4)
//   V = ~(a[msb] ^ b[msb]) & (a[msb] ^ sum[msb])
//
// Flag bit positions == FCW: C=bit7 Z=6 S=5 P/V=4 D=3 H=2. flags_mask is the
// set of flags the op writes; flags outside it are don't-care. Width/op pairs
// the CPU never issues (long rotates, INCL/DECL, ...) return all zeros.

module z8000_alu
  import z8000_ctrl_pkg::*;
(
  input  logic [ALUOP_W-1:0] op,
  input  logic [1:0]         width,   // WIDTH_BYTE / WIDTH_WORD / WIDTH_LONG
  input  logic [63:0]        a,       // destination / first operand
  input  logic [63:0]        b,       // source / second operand (count, bit number, ...)
  input  logic               cin,     // incoming C flag (ADC/SBC/RLC/RRC/DAB)
  output logic [63:0]        value,
  output logic [15:0]        flags,
  output logic [15:0]        flags_mask
);

  localparam logic [15:0] F_C = 16'h0080;
  localparam logic [15:0] F_Z = 16'h0040;
  localparam logic [15:0] F_S = 16'h0020;
  localparam logic [15:0] F_V = 16'h0010;
  localparam logic [15:0] F_D = 16'h0008;
  localparam logic [15:0] F_H = 16'h0004;

  // ---- width ----------------------------------------------------------------
  logic [31:0] wmask, sign;
  logic [6:0]  nbits;
  logic        is_byte, is_short, w_ok;

  always_comb begin
    unique case (width)
      WIDTH_BYTE: begin wmask = 32'h0000_00FF; nbits = 7'd8;  end
      WIDTH_WORD: begin wmask = 32'h0000_FFFF; nbits = 7'd16; end
      WIDTH_LONG: begin wmask = 32'hFFFF_FFFF; nbits = 7'd32; end
      default:    begin wmask = 32'h0;         nbits = 7'd0;  end
    endcase
    sign     = wmask & ~(wmask >> 1);
    is_byte  = (width == WIDTH_BYTE);
    is_short = (width == WIDTH_BYTE) || (width == WIDTH_WORD);
    w_ok     = (width != WIDTH_NONE);
  end

  // m selects the sign bit.
  function automatic logic msb(input logic [31:0] v, input logic [31:0] m);
    return |(v & m);
  endfunction

  // Z and S of a masked result; P is the parity of its low byte.
  function automatic logic [15:0] zsp(input logic [31:0] v, input logic [31:0] m);
    return ((v == 32'd0) ? F_Z : 16'h0) | (msb(v, m) ? F_S : 16'h0)
         | ((~^v[7:0]) ? F_V : 16'h0);
  endfunction

  logic [31:0] x;
  assign x = a[31:0] & wmask;

  // ---- adder ----------------------------------------------------------------
  logic        sub_op;
  logic [31:0] add_a, add_b, sum_v;
  logic        add_cin;
  logic [32:0] sum;
  logic        cout, half, ovf;

  always_comb begin
    sub_op  = (op == OP_SUB) || (op == OP_SBC) || (op == OP_CP) || (op == OP_DEC) || (op == OP_NEG);
    add_a   = (op == OP_NEG) ? 32'd0 : x;
    add_b   = ((op == OP_NEG) ? ~a[31:0] : sub_op ? ~b[31:0] : b[31:0]) & wmask;
    unique case (op)
      OP_ADC:  add_cin = cin;
      OP_SBC:  add_cin = ~cin;
      default: add_cin = sub_op;
    endcase
    sum   = {1'b0, add_a} + {1'b0, add_b} + {32'd0, add_cin};
    sum_v = sum[31:0] & wmask;
    unique case (width)
      WIDTH_BYTE: cout = sum[8];
      WIDTH_WORD: cout = sum[16];
      default:    cout = sum[32];
    endcase
    half = add_a[4] ^ add_b[4] ^ sum[4];
    ovf  = ~(msb(add_a, sign) ^ msb(add_b, sign)) & (msb(add_a, sign) ^ msb(sum_v, sign));
  end

  // ---- shifts (count 0-63) --------------------------------------------------
  // C is the last bit shifted out, which lands just beyond the result:
  // shl[N] for left shifts, bit 0 of the right shifters (x enters at bit 1).
  logic [5:0]         n;
  logic [32:0]        shl, shr;
  logic [31:0]        x_sx;
  logic signed [32:0] sar;
  logic [31:0]        shl_v, shr_v, sar_v;
  logic               shl_c, sla_v;

  always_comb begin
    n   = b[5:0];
    shl = {1'b0, x} << n;
    shr = {x, 1'b0} >> n;
    unique case (width)
      WIDTH_BYTE: x_sx = {{24{x[7]}},  x[7:0]};
      WIDTH_WORD: x_sx = {{16{x[15]}}, x[15:0]};
      default:    x_sx = x;
    endcase
    sar   = $signed({x_sx, 1'b0}) >>> n;
    shl_v = shl[31:0] & wmask;
    shr_v = shr[32:1];
    sar_v = sar[32:1] & wmask;
    unique case (width)
      WIDTH_BYTE: shl_c = shl[8];
      WIDTH_WORD: shl_c = shl[16];
      default:    shl_c = shl[32];
    endcase
    // SLA overflows if any bit that passes through the sign position differs
    // from the original sign: bits [N-2 : N-1-n] of x, then zeros once n >= N.
    sla_v = |((x ^ {32{msb(x, sign)}}) & (wmask >> 1) & ~((wmask >> 1) >> n))
          | ({1'b0, n} >= nbits && msb(x, sign));
  end

  // ---- rotates (byte/word, count 0 means 1) ---------------------------------
  // RLC/RRC rotate the N+1-bit ring {C, x}.
  logic [5:0]  n1;
  logic [4:0]  k, kc;
  logic [31:0] ring, ring_mask, rl_v, rr_v, rlc_r, rrc_r;

  always_comb begin
    n1        = (n == 6'd0) ? 6'd1 : n;
    k         = is_byte ? {2'b0, n1[2:0]} : {1'b0, n1[3:0]};
    kc        = is_byte ? 5'(n1 % 6'd9) : 5'(n1 % 6'd17);
    ring      = x | (cin ? (32'd1 << nbits) : 32'd0);
    ring_mask = {wmask[30:0], 1'b1};
    rl_v      = ((x << k) | (x >> (nbits - 7'(k)))) & wmask;
    rr_v      = ((x >> k) | (x << (nbits - 7'(k)))) & wmask;
    rlc_r     = ((ring << kc) | (ring >> (nbits + 7'd1 - 7'(kc)))) & ring_mask;
    rrc_r     = ((ring >> kc) | (ring << (nbits + 7'd1 - 7'(kc)))) & ring_mask;
  end

  // ---- DAB ------------------------------------------------------------------
  // b[0] = H and b[1] = D from the preceding op; table per Ref Manual p.85.
  logic [7:0] dab_v;
  logic       dab_c, add06, add60;

  always_comb begin
    add06 = (a[3:0] > 4'd9) || b[0];
    add60 = cin || (a[7:4] > 4'd9) || (a[7:4] == 4'd9 && a[3:0] > 4'd9);
    if (b[1]) begin
      unique case ({cin, b[0]})
        2'b00:   dab_v = a[7:0];
        2'b01:   dab_v = a[7:0] + 8'hFA;
        2'b10:   dab_v = a[7:0] + 8'hA0;
        default: dab_v = a[7:0] + 8'h9A;
      endcase
      dab_c = cin;
    end else begin
      dab_v = a[7:0] + (add06 ? 8'h06 : 8'h00) + (add60 ? 8'h60 : 8'h00);
      dab_c = add60;
    end
  end

  // ---- bit ops --------------------------------------------------------------
  logic [63:0] bitm;
  assign bitm = (b[63:6] == 58'd0) ? (64'd1 << b[5:0]) : 64'd0;

  // ---- result select --------------------------------------------------------
  logic [31:0] lv;
  logic [15:0] arith_f;

  always_comb begin
    value      = 64'd0;
    flags      = 16'h0000;
    flags_mask = 16'h0000;
    lv         = 32'd0;
    arith_f    = (zsp(sum_v, sign) & ~F_V) | (ovf ? F_V : 16'h0)
               | ((cout ^ sub_op) ? F_C : 16'h0) | ((half ^ sub_op) ? F_H : 16'h0)
               | (sub_op ? F_D : 16'h0);

    unique case (op)
      OP_ADD, OP_ADC, OP_SUB, OP_SBC: if (w_ok) begin
        value      = {32'd0, sum_v};
        flags      = arith_f;
        flags_mask = F_C | F_Z | F_S | F_V | (is_byte ? (F_D | F_H) : 16'h0);
      end
      OP_CP: if (w_ok) begin
        value      = {32'd0, sum_v};
        flags      = arith_f & ~(F_D | F_H);
        flags_mask = F_C | F_Z | F_S | F_V;
      end
      OP_NEG: if (w_ok) begin
        value      = {32'd0, sum_v};
        flags      = arith_f;
        flags_mask = F_C | F_Z | F_S | F_V;
      end
      OP_INC, OP_DEC: if (is_short) begin
        value      = {32'd0, sum_v};
        flags      = arith_f;
        flags_mask = F_Z | F_S | F_V;
      end
      OP_AND, OP_OR, OP_XOR, OP_COM, OP_TEST: if (w_ok) begin
        unique case (op)
          OP_AND:  lv = x & b[31:0];
          OP_OR:   lv = x | (b[31:0] & wmask);
          OP_XOR:  lv = x ^ (b[31:0] & wmask);
          OP_COM:  lv = ~x & wmask;
          default: lv = x;
        endcase
        value      = {32'd0, lv};
        flags      = zsp(lv, sign);
        flags_mask = F_Z | F_S | (is_byte ? F_V : 16'h0);
      end
      OP_SLA, OP_SLL: if (w_ok) begin
        value      = {32'd0, shl_v};
        flags      = (zsp(shl_v, sign) & ~F_V) | (shl_c ? F_C : 16'h0)
                   | ((op == OP_SLA && sla_v) ? F_V : 16'h0);
        flags_mask = F_Z | F_S | ((n != 6'd0) ? F_C : 16'h0) | ((op == OP_SLA) ? F_V : 16'h0);
      end
      OP_SRA: if (w_ok) begin
        value      = {32'd0, sar_v};
        flags      = (zsp(sar_v, sign) & ~F_V) | (sar[0] ? F_C : 16'h0);
        flags_mask = F_Z | F_S | F_V | ((n != 6'd0) ? F_C : 16'h0);
      end
      OP_SRL: if (w_ok) begin
        value      = {32'd0, shr_v};
        flags      = zsp(shr_v, sign) | (shr[0] ? F_C : 16'h0);
        flags_mask = F_Z | F_S | ((n != 6'd0) ? F_C : 16'h0);
      end
      OP_RL, OP_RR, OP_RLC, OP_RRC: if (is_short) begin
        unique case (op)
          OP_RL:   begin lv = rl_v;            flags = rl_v[0] ? F_C : 16'h0; end
          OP_RR:   begin lv = rr_v;            flags = msb(rr_v, sign) ? F_C : 16'h0; end
          OP_RLC:  begin lv = rlc_r & wmask;   flags = rlc_r[nbits[4:0]] ? F_C : 16'h0; end
          default: begin lv = rrc_r & wmask;   flags = rrc_r[nbits[4:0]] ? F_C : 16'h0; end
        endcase
        value      = {32'd0, lv};
        flags      = flags | (zsp(lv, sign) & ~F_V) | (msb(lv ^ x, sign) ? F_V : 16'h0);
        flags_mask = F_C | F_Z | F_S | F_V;
      end
      OP_DAB: begin
        value      = {56'd0, dab_v};
        flags      = (zsp({24'd0, dab_v}, 32'h0000_0080) & ~F_V) | (dab_c ? F_C : 16'h0);
        flags_mask = F_C | F_Z | F_S;
      end
      OP_EXTS: begin
        unique case (width)
          WIDTH_BYTE: begin value = {48'd0, {8{a[7]}}, a[7:0]};  flags = zsp(value[31:0], 32'h0000_8000); end
          WIDTH_WORD: begin value = {32'd0, {16{a[15]}}, a[15:0]}; flags = zsp(value[31:0], 32'h8000_0000); end
          default: ;
        endcase
        flags = flags & (F_Z | F_S);
      end
      OP_LD:   value = b;
      OP_BIT: begin
        value      = a;
        flags      = ((a & bitm) == 64'd0) ? F_Z : 16'h0;
        flags_mask = F_Z;
      end
      OP_SET:  value = a | bitm;
      OP_RES:  value = a & ~bitm;
      OP_TSET: begin
        value = is_byte ? 64'h00FF : 64'hFFFF;
        flags = (is_byte ? a[7] : a[15]) ? F_S : 16'h0;
        flags_mask = F_S;
      end
      default: ;
    endcase
  end

endmodule
