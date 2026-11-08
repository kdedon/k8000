// z8070_dp -- the Z8070's Data Processor: F0-F7, FOP1, FOP2 and the
// arithmetic, stepped on CLK.D.
//
// F0-F7 and FOP1, FOP2 (rows 8, 9; the trap operand and default result,
// spec p.534): one 16 x 80 RAM, {sign, exponent 15 bits, significand 64
// bits}, one write port and one registered read port (f_re holds it), an
// MLAB on Cyclone V, written and read by the Interface Processor; row 10
// keeps a bus operand for it. Not cleared by /RESET (a
// RAM cannot be in one clock); it powers up 0.
//
// Arithmetic: a vertical microprogram (the generated ROM, z8070_dp_rom),
// one word per CLK.D rise, over one datapath: a
// 68-bit significand adder, a 17-bit exponent adder, one bidirectional
// 68-bit barrel shifter with sticky collect and one leading-zero counter,
// shared by every routine. Exponents stay biased (16383) throughout; the
// working significand S is {carry, 64 bits, guard, round, sticky}.
//
// Multiply: radix 4, two multiplier bits a clock; S accumulates, B takes
// the product's low word as the multiplier shifts out, X holds 3M.
// Divide and remainder: radix-4 SRT on an exact remainder in S, the digit
// from a small table; X and QM collect the positive and the negative
// digits, and the adder takes their difference at the end.
// Square root: one root bit a clock, restoring, root in B, radicand in A.
// FINT and the integer conversions: B right to the integer point, a round
// there, then the shared tail or one negate and range pass. BCD load: one
// 10 acc + digit adder pass a digit. BCD store: the divide's SRT steps
// make h / 10^19, then one 10 g adder pass a digit takes its integer part.
//
// Interface: start latches the operation; a CLK.D rise in the same master
// clock is its first clock. The operand bus opnd carries the operand
// opnd_src names (0 destination, 1 source) and is sampled by the two
// unpack clocks (an integer to convert: its 64-bit two's complement on
// opnd[63:0]). opnd_rd is High while the running word samples opnd, so
// the caller can address a registered RAM a master clock ahead. For a
// conversion to an integer op_prec 1 selects 64 bits,
// 0 32; the result is the integer sign-extended in res[63:0], res[79:64]
// zero. BCD: the Fig 12 container on opnd or in res. done is High in the
// master clock of the last clock's CLK.D rise, from registered state; the
// result latch was loaded the clock before and holds until the next
// operation's last-but-one clock. start must not share a master clock
// with done.
//
// Implemented so far: add, subtract, reverse subtract, load (round to a
// precision), compare (four forms), FABS, FNEG, FCLR, multiply, FPWR2,
// divide, reverse divide, remainder (both forms), square root, FINT,
// integer to float and back, BCD load and store. Other operations run the
// tail only and end in two clocks.
//
// op_out (latched at start): a single or double store. The result keeps
// the denormalized form of a tiny value (the subnormal's exponent,
// integer bit 0) instead of renormalizing it for F, so the memory image
// is its fields.
//
// Harness contract: the replay bench reads and pokes f_mem by name.

`default_nettype none

module z8070_dp
  import z8070_dp_rom_pkg::*;
(
  input  logic        clk,
  input  logic        clkd_rise,
  input  logic        reset_n,
  output logic        busy,
  input  logic        start,
  input  logic [5:0]  op_kind,    // the operation code of the Go model
  input  logic [1:0]  op_prec,    // 0 single, 1 double, 2 extended
  input  logic [1:0]  op_rm,      // USER RM
  input  logic        op_out,
  input  logic [79:0] opnd,
  output logic        opnd_src,
  output logic        opnd_rd,
  output logic        done,
  output logic [79:0] res,
  output logic [7:0]  res_flags,  // INV FOV UN DZ INX DE NAN IX, bit 0 first
  output logic [2:0]  res_reason,
  output logic        res_rup,
  output logic [5:0]  res_cmp,    // FH FD FV FS FZ FC, bit 0 first

  input  logic        f_we,
  input  logic [3:0]  f_waddr,
  input  logic [79:0] f_wdata,
  input  logic [3:0]  f_raddr,
  input  logic        f_re,
  output logic [79:0] f_rdata
);

  // ---- F0-F7, FOP1, FOP2 -----------------------------------------------
  // Justification: (reg-a) F0-F7, FOP1, FOP2.
  (* ramstyle = "MLAB, no_rw_check" *) logic [79:0] f_mem [0:15];

  always_ff @(posedge clk) begin
    if (f_we) f_mem[f_waddr] <= f_wdata;
  end

  always_ff @(posedge clk) begin
    if (f_re) f_rdata <= f_mem[f_raddr];
  end


  // ---- operation codes and constants -----------------------------------
  localparam logic [5:0] K_SUB = 6'h01, K_RVSUB = 6'h02,
                         K_RDIV = 6'h05, K_PWR2 = 6'h06,
                         K_LOAD = 6'h08, K_ABS = 6'h09, K_NEG = 6'h0A, K_CLR = 6'h0B,
                         K_CMPX = 6'h0E, K_CMPZ = 6'h0F, K_CMPZX = 6'h10,
                         K_REM = 6'h11, K_REMSTEP = 6'h12, K_FINT = 6'h0C,
                         K_ITOF = 6'h20, K_BCDL = 6'h22, K_BCDS = 6'h23;

  typedef enum logic [2:0] {
    CL_ZERO = 3'd0,
    CL_SUB  = 3'd1,
    CL_NORM = 3'd2,
    CL_INF  = 3'd3,
    CL_QNAN = 3'd4,
    CL_SNAN = 3'd5
  } cls_e;

  // Flags (bit numbers) and compare codes.
  localparam int FL_INV = 0, FL_FOV = 1, FL_UN = 2, FL_DZ = 3, FL_INX = 4, FL_DE = 5, FL_NAN = 6,
                 FL_IX = 7;
  localparam logic [5:0] CC_LT = 6'h22, CC_GT = 6'h0A, CC_EQ = 6'h10, CC_UN = 6'h04;
  localparam int CF_FH = 0, CF_FD = 1, CF_FS = 3, CF_FZ = 4;
  localparam logic [2:0] RS_INF_INF = 3'd0, RS_ZERO_INF = 3'd1, RS_ZERO_ZERO = 3'd2,
                         RS_REM = 3'd3, RS_UNORDERED = 3'd4, RS_SQRT_NEG = 3'd5,
                         RS_BCD = 3'd6, RS_NAN_CVT = 3'd7;

  // Relations.
  localparam logic [1:0] REL_EQ = 2'd0, REL_GT = 2'd1, REL_LT = 2'd2;

  localparam logic [16:0] EXP_MAX = 17'h07FFF;  // infinity and NaN exponent field
  localparam logic [63:0] QNAN_SIG  = 64'hC000_0000_0000_0000;  // the default NaN
  localparam logic [16:0] EXP_INT   = 17'd16446;  // bias + 63: an integer at S[66:3]
  localparam logic [63:0] P19       = 64'h8AC7_2304_89E8_0000;  // 10^19, normalized as it is

  // Per precision, biased: smallest normal exponent, subnormal scale,
  // largest exponent, significand bits dropped below extended.
  function automatic logic [16:0] emin_of(input logic [1:0] p);
    emin_of = (p == 2'd0) ? 17'd16257 : (p == 2'd1) ? 17'd15361 : 17'd1;
  endfunction

  function automatic logic [16:0] subexp_of(input logic [1:0] p);
    subexp_of = (p == 2'd0) ? 17'd16257 : (p == 2'd1) ? 17'd15361 : 17'd0;
  endfunction

  function automatic logic [16:0] emax_of(input logic [1:0] p);
    emax_of = (p == 2'd0) ? 17'd16510 : (p == 2'd1) ? 17'd17406 : 17'd32766;
  endfunction

  // Significand bits below a precision's LSB (64 - nS): the exponent
  // offset of a result developed LSB-aligned, and the multiplier shift.
  function automatic logic [6:0] drop_of(input logic [1:0] p);
    drop_of = (p == 2'd0) ? 7'd40 : (p == 2'd1) ? 7'd11 : 7'd0;
  endfunction

  // nS - 1: the last quotient bit of a full remainder batch, and the root
  // steps after the first.
  function automatic logic [6:0] nsm1_of(input logic [1:0] p);
    nsm1_of = (p == 2'd0) ? 7'd23 : (p == 2'd1) ? 7'd52 : 7'd63;
  endfunction

  // Radix-4 steps: floor(nS / 2).
  function automatic logic [6:0] half_of(input logic [1:0] p);
    half_of = (p == 2'd0) ? 7'd12 : (p == 2'd1) ? 7'd26 : 7'd32;
  endfunction

  // Significand bits kept by a precision (largest finite, fold mask).
  function automatic logic [63:0] keep_of(input logic [1:0] p);
    keep_of = (p == 2'd0) ? 64'hFFFF_FF00_0000_0000 : (p == 2'd1) ? 64'hFFFF_FFFF_FFFF_F800 : 64'hFFFF_FFFF_FFFF_FFFF;
  endfunction

  // ---- sequencer -------------------------------------------------------
  // Justification: (reg-a) the microprogram counter, the run flag and the
  // operation latched at start.
  logic            run_q;
  logic [UA_W-1:0] upc_q;
  logic [5:0]      kind_q;
  logic [1:0]      prec_q, rm_q;
  logic            out_q;

  logic            step, cond;
  logic [UA_W-1:0] upc, upc_next, entry, body;
  logic [5:0]      kind;
  logic [1:0]      prec, rm;
  logic [$bits(dp_uw_t)-1:0] uw_rom, uw_first;
  dp_uw_t          uw;

  z8070_dp_rom u_rom (
    .addr       (upc_q),
    .kind       (kind_q),
    .start_kind (op_kind),
    .uw         (uw_rom),
    .uw_first   (uw_first),
    .entry      (entry),
    .body       (body)
  );

  // A start on a CLK.D rise runs its first word in that clock; that word
  // comes from its own table, not through the ROM address.
  assign uw   = dp_uw_t'(start ? uw_first : uw_rom);
  assign upc  = start ? entry : upc_q;
  assign kind = start ? op_kind : kind_q;
  assign prec = start ? op_prec : prec_q;
  assign rm   = start ? op_rm   : rm_q;
  assign step = clkd_rise & (run_q | start);
  assign done = step & uw.fin;
  assign busy = run_q;

  always_comb begin
    unique case (uw.seq)
      SQ_JMP:   upc_next = uw.tgt;
      SQ_JCOND: upc_next = cond ? uw.tgt : upc + 1'b1;
      SQ_RET:   upc_next = body;
      default:  upc_next = upc + 1'b1;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!reset_n)                run_q <= 1'b0;
    else if (step && uw.fin)     run_q <= 1'b0;
    else if (start)              run_q <= 1'b1;
  end

  always_ff @(posedge clk) begin
    if (step)       upc_q <= upc_next;
    else if (start) upc_q <= upc;
  end

  always_ff @(posedge clk) begin
    if (start) begin
      kind_q <= op_kind;
      prec_q <= op_prec;
      rm_q   <= op_rm;
      out_q  <= op_out;
    end
  end

  // ---- datapath registers ----------------------------------------------
  // Justification: (reg-a) operands A and B, unpacked.
  logic        a_sign, b_sign;
  logic [16:0] a_exp, b_exp;
  logic [63:0] a_sig, b_sig;
  cls_e        a_cls, b_cls;
  // Justification: (reg-a) the working value S: {carry, significand,
  // guard, round, sticky}, its exponent and sign.
  logic        s_sign;
  logic [16:0] s_exp;
  logic [67:0] s_sig;
  // Justification: (reg-a) step results read by a later clock: exponent
  // difference, shift count (normalize, then storage), effective
  // subtract, tininess, inexact, unordered, denormalize flag and amount
  // (formed at NORM so DNRM shifts by a register), the magnitude then
  // signed relation, flags, reason, rounded up, compare code.
  logic [16:0] d_q;
  logic [6:0]  cnt_q;
  logic        esub_q, tiny_q, inex_q, unord_q, dnrm_q, rup_q;
  logic [6:0]  dnrm_amt_q;
  logic [1:0]  rel_q;
  logic [7:0]  fl_q;
  logic [2:0]  rsn_q;
  logic [5:0]  cmp_q;
  // Justification: (reg-a) X: 3M for the multiply, the positive quotient
  // digits for the divide; QM: the negative digits. The quotient is X - QM
  // at the end, exact modulo 2^66 (it is < 2^66).
  logic [65:0] x_q, qm_q;
  // Justification: (reg-a) multiplier bits dropped below the precision
  // (sticky); exponent parity (root) or an odd quotient-bit count
  // (remainder); a complete remainder.
  logic        stin_q, par_q, cmpl_q;
  // Justification: (reg-a) an integer conversion out of range: selects the
  // indefinite, drops INX and the R bit.
  logic        ixo_q;

  logic        stin_d, par_d, cmpl_d, ixo_d;

  logic        a_sign_d, b_sign_d, s_sign_d;
  logic [16:0] a_exp_d, b_exp_d, s_exp_d, d_d;
  logic [63:0] a_sig_d, b_sig_d;
  cls_e        a_cls_d, b_cls_d;
  logic [67:0] s_sig_d;
  logic        a_we, b_we, s_we;
  logic [6:0]  cnt_d;
  logic        esub_d, tiny_d, inex_d, unord_d, dnrm_d, rup_d;
  logic [6:0]  dnrm_amt_d;
  logic [1:0]  rel_d;
  logic [7:0]  fl_d;
  logic [2:0]  rsn_d;
  logic [5:0]  cmp_d;
  logic        res_ld;

  // ---- shared units ----------------------------------------------------
  // Exponent adder: ex_x + ex_y, or ex_x - ex_y.
  logic [16:0] ex_x, ex_y, ex_sum;
  logic        ex_sub;
  assign ex_sum = ex_x + (ex_sub ? ~ex_y : ex_y) + {16'd0, ex_sub};

  // Significand adder, 68 bits.
  logic [68:0] ad_x, ad_y, ad_sum;
  logic        ad_sub, ad_ci;
  assign ad_sum = ad_x + (ad_sub ? ~ad_y : ad_y) + {68'd0, ad_sub | ad_ci};

  // Leading-zero counter over 66 bits (66 when all zero): a tree of
  // (all-zero, count) pairs over the input padded to 128 with a stop bit.
  logic [65:0] lz_in;
  logic [6:0]  lz_out;

  function automatic logic [6:0] lzc66(input logic [65:0] v);
    logic [127:0] w;
    logic         z [0:7][0:127];
    logic [6:0]   c [0:7][0:127];
    w = {v, 1'b1, 61'd0};
    for (int i = 0; i < 128; i++) begin
      z[0][i] = ~w[127 - i];
      c[0][i] = 7'd0;
    end
    for (int l = 1; l < 8; l++) begin
      for (int i = 0; i < 128; i++) begin
        if (i < (128 >> l)) begin
          z[l][i] = z[l-1][2*i] & z[l-1][2*i+1];
          c[l][i] = z[l-1][2*i] ? (c[l-1][2*i+1] | 7'(1 << (l - 1))) : c[l-1][2*i];
        end else begin
          z[l][i] = 1'b0;
          c[l][i] = 7'd0;
        end
      end
    end
    lzc66 = c[7][0];
  endfunction

  assign lz_out = lzc66(lz_in);

  // Barrel shifter, 68 bits: right with the lost bits ORed into bit 0, or
  // left (the right shifter between two bit reversals). Amount <= 67.
  logic [67:0] sh_in, sh_out;
  logic [6:0]  sh_amt;
  logic        sh_left;

  function automatic logic [67:0] rev68(input logic [67:0] v);
    for (int i = 0; i < 68; i++) rev68[i] = v[67 - i];
  endfunction

  always_comb begin
    logic [67:0] x, y, lost;
    x      = sh_left ? rev68(sh_in) : sh_in;
    y      = x >> sh_amt;
    lost   = x & ~({68{1'b1}} << sh_amt);
    sh_out = sh_left ? rev68(y) : {y[67:1], y[0] | (|lost)};
  end

  // Shift amount clamp: past 67 every bit is sticky.
  function automatic logic [6:0] clamp67(input logic [16:0] k);
    clamp67 = ((|k[16:7]) || (k[6:0] > 7'd67)) ? 7'd67 : k[6:0];
  endfunction

  // ---- classify --------------------------------------------------------
  function automatic cls_e classify(input logic [14:0] e, input logic [63:0] sig);
    if (e == 15'h7FFF) begin
      if (sig[62:0] == 63'd0) classify = CL_INF;
      else if (sig[62])       classify = CL_QNAN;
      else                    classify = CL_SNAN;
    end else if (e == 15'd0) begin
      classify = (sig == 64'd0) ? CL_ZERO : CL_SUB;
    end else begin
      classify = CL_NORM;
    end
  endfunction

  function automatic logic is_nan(input cls_e c);
    is_nan = (c == CL_QNAN) || (c == CL_SNAN);
  endfunction

  function automatic logic is_fin(input cls_e c);
    is_fin = (c == CL_SUB) || (c == CL_NORM);
  endfunction

  // Round decision (USER RM): increment the kept significand?
  function automatic logic round_up(input logic [1:0] m, input logic sign, input logic lsb,
                                    input logic g, input logic stk);
    round_up = (m == 2'd0) ? (g & (stk | lsb)) :
               (m == 2'd1) ? 1'b0 :
               (m == 2'd2) ? (~sign & (g | stk)) : (sign & (g | stk));
  endfunction

  // ---- the clock's action ----------------------------------------------
  logic        opnd_cmpz, opnd_load, opnd_rev, opnd_sw, is_rem, is_fint, is_bcs, int_res;
  logic [63:0] rnd_sig, rnd_lsb;
  logic        rnd_g, rnd_st, rnd_up;

  // An unnormal (exponent nonzero, integer bit 0) is a denormalized
  // number too: a single or double subnormal arrives so from the bus.
  logic a_unn, b_unn;

  assign a_unn = a_cls == CL_NORM && !a_sig[63] && a_sig != 64'd0;
  assign b_unn = b_cls == CL_NORM && !b_sig[63] && b_sig != 64'd0;

  assign opnd_rev  = kind == K_RVSUB;
  assign opnd_load = kind == K_LOAD;
  assign opnd_cmpz = (kind == K_CMPZ) || (kind == K_CMPZX);
  assign opnd_sw   = opnd_rev || (kind == K_RDIV);  // A from the source, B from the destination
  assign is_rem    = (kind == K_REM) || (kind == K_REMSTEP);
  assign is_fint   = kind == K_FINT;
  assign is_bcs    = kind == K_BCDS;
  assign int_res   = is_fint || (kind == K_ITOF) || (kind == K_BCDL);  // never tiny

  always_comb begin
    opnd_rd = 1'b1;
    unique case (uw.act)
      DA_UNPA: opnd_src = opnd_sw | opnd_load | (kind == K_PWR2);
      DA_UNPB: opnd_src = ~opnd_sw;
      DA_ILD:  opnd_src = 1'b1;
      default: begin opnd_src = 1'b0; opnd_rd = 1'b0; end
    endcase
  end

  // Precision fold for the round clock: the guard is the first dropped
  // bit, the sticky everything below it.
  // IRND rounds at the integer point: the extended fold.
  always_comb begin
    logic [63:0] sig, keep;
    logic [1:0]  rp;
    rp   = (uw.act == DA_IRND) ? 2'd2 : prec;
    sig  = s_sig[66:3];
    keep = keep_of(rp);
    unique case (rp)
      2'd0:    begin rnd_g = sig[39]; rnd_st = s_sig[2] | (|s_sig[1:0]) | (|sig[38:0]);
                     rnd_lsb = 64'h0000_0100_0000_0000; end
      2'd1:    begin rnd_g = sig[10]; rnd_st = s_sig[2] | (|s_sig[1:0]) | (|sig[9:0]);
                     rnd_lsb = 64'h0000_0000_0000_0800; end
      default: begin rnd_g = s_sig[2]; rnd_st = |s_sig[1:0];
                     rnd_lsb = 64'h0000_0000_0000_0001; end
    endcase
    rnd_sig = sig & keep;
    rnd_up  = round_up(rm, s_sign, |(rnd_sig & rnd_lsb), rnd_g, rnd_st);
  end

  // A BCD container digit above 9.
  logic bcd_bad;

  always_comb begin
    logic [75:0] c;
    c       = {b_exp[11:0], b_sig};
    bcd_bad = 1'b0;
    for (int i = 0; i < 19; i++) bcd_bad = bcd_bad | (c[4*i+3] & (c[4*i+2] | c[4*i+1]));
  end

  // The indefinite integer: -2^63, or -2^31 sign-extended.
  logic [67:0] ind_sig;
  assign ind_sig = {1'b0, prec[0] ? 64'h8000_0000_0000_0000 : 64'hFFFF_FFFF_8000_0000, 3'd0};

  // Special operands, one select for every operation: the result into S,
  // flags, reason and remainder flags. A NaN operand wins (A before B; the
  // square root and FINT have only B). The significand is A or B through
  // the idle shifter (a NaN is quieted on the way), the default NaN, zero,
  // or the indefinite integer.
  typedef enum logic [1:0] {XS_ZERO = 2'd0, XS_QNAN = 2'd1, XS_A = 2'd2, XS_B = 2'd3} xs_src_e;
  logic        xs_hit, xs_sign, xs_quiet, xs_ind;
  logic [16:0] xs_exp;
  xs_src_e     xs_src;
  logic [7:0]  xs_fl;
  logic [2:0]  xs_rsn;
  logic [5:0]  xs_cmp;

  always_comb begin
    logic sq, a_z, b_z, a_i, b_i, sgn;
    sq  = (uw.act == DA_SSPC) || (uw.act == DA_FSPC);
    a_z = a_cls == CL_ZERO; b_z = b_cls == CL_ZERO;
    a_i = a_cls == CL_INF;  b_i = b_cls == CL_INF;
    sgn = a_sign ^ b_sign;
    xs_hit = 1'b1; xs_sign = 1'b0; xs_exp = EXP_MAX; xs_src = XS_ZERO; xs_quiet = 1'b0;
    xs_ind = 1'b0; xs_fl = 8'd0; xs_rsn = 3'd0; xs_cmp = 6'd0;
    if (uw.act == DA_BSPC) begin
      xs_hit = bcd_bad; xs_src = XS_QNAN; xs_fl[FL_INV] = 1'b1; xs_rsn = RS_BCD;
    end else if (uw.act == DA_XSPC) begin  // to an integer or a container
      xs_exp = 17'd0;
      xs_ind = ~is_bcs;
      if (is_nan(b_cls)) begin
        xs_fl[FL_INV] = 1'b1; xs_fl[FL_NAN] = b_cls == CL_SNAN; xs_rsn = RS_NAN_CVT;
      end else if (b_i) xs_fl[FL_IX] = 1'b1;
      else if (b_z) begin
        xs_ind = 1'b0; xs_sign = is_bcs & b_sign;
      end else xs_hit = 1'b0;
    end else if (!sq && (a_cls == CL_SNAN)) begin
      xs_sign = a_sign; xs_src = XS_A; xs_quiet = 1'b1; xs_fl[FL_NAN] = 1'b1;
    end else if (b_cls == CL_SNAN) begin
      xs_sign = b_sign; xs_src = XS_B; xs_quiet = 1'b1; xs_fl[FL_NAN] = 1'b1;
    end else if (!sq && (a_cls == CL_QNAN)) begin
      xs_sign = a_sign; xs_src = XS_A;
    end else if (b_cls == CL_QNAN) begin
      xs_sign = b_sign; xs_src = XS_B;
    end else begin
      unique case (uw.act)
        DA_SPEC: begin  // add: anything but two finite or one zero
          if (a_i && b_i && (a_sign != b_sign)) begin
            xs_src = XS_QNAN; xs_fl[FL_INV] = 1'b1; xs_rsn = RS_INF_INF;
          end else if (a_i) xs_sign = a_sign;
          else if (b_i)     xs_sign = b_sign;
          else if (a_z && b_z) begin
            xs_exp  = 17'd0;
            xs_sign = (a_sign == b_sign) ? a_sign : (rm == 2'd3);
          end else xs_hit = 1'b0;
        end
        DA_MSPC: begin
          xs_sign = sgn;
          if ((a_z && b_i) || (a_i && b_z)) begin
            xs_sign = 1'b0; xs_src = XS_QNAN; xs_fl[FL_INV] = 1'b1; xs_rsn = RS_ZERO_INF;
          end else if (a_z || b_z) xs_exp = 17'd0;
          else if (!(a_i || b_i))   xs_hit = 1'b0;
        end
        DA_DSPC: begin
          xs_sign = sgn;
          if ((a_z && b_z) || (a_i && b_i)) begin
            xs_sign = 1'b0; xs_src = XS_QNAN; xs_fl[FL_INV] = 1'b1; xs_rsn = RS_ZERO_ZERO;
          end else if (b_i && !a_i) xs_exp = 17'd0;
          else if (a_i)      xs_exp = EXP_MAX;
          else if (b_z)      xs_fl[FL_DZ] = 1'b1;
          else if (a_z)      xs_exp = 17'd0;
          else               xs_hit = 1'b0;
        end
        DA_FSPC: begin
          xs_sign = b_sign;
          if (b_z)       xs_exp = 17'd0;
          else if (!b_i) xs_hit = 1'b0;
        end
        DA_SSPC: begin
          if (b_z) begin
            xs_sign = b_sign; xs_exp = 17'd0;
          end else if (b_sign) begin
            xs_src = XS_QNAN; xs_fl[FL_INV] = 1'b1; xs_rsn = RS_SQRT_NEG;
          end else if (!b_i) xs_hit = 1'b0;
        end
        DA_RSPC: begin
          xs_cmp[CF_FD] = 1'b1;
          if (a_i || b_z) begin
            xs_src = XS_QNAN; xs_fl[FL_INV] = 1'b1; xs_rsn = RS_REM; xs_cmp = 6'd0;
          end else if (b_i) begin  // the destination as stored
            xs_sign = a_sign; xs_exp = a_exp; xs_src = XS_A;
            xs_cmp[CF_FZ] = a_z;
            xs_cmp[CF_FS] = a_sign & ~a_z;
          end else if (a_z) begin
            xs_sign = a_sign; xs_exp = 17'd0; xs_cmp[CF_FZ] = 1'b1;
          end else xs_hit = 1'b0;
        end
        default: xs_hit = 1'b0;
      endcase
    end
  end

  // Radix-4 SRT digit in {-2..2} from 4w truncated to quarters (S[67:62],
  // signed) and the divisor's three fraction bits. The exact remainder
  // makes two fraction bits enough; each divisor column is two thresholds
  // and their negatives.
  function automatic logic [2:0] srt_digit(input logic [5:0] y, input logic [2:0] dcol);
    logic signed [5:0] v, m2, m1;
    v = $signed(y);
    unique case (dcol)
      3'd0:    begin m2 = 6'sd6;  m1 = 6'sd2; end
      3'd1:    begin m2 = 6'sd7;  m1 = 6'sd3; end
      3'd2:    begin m2 = 6'sd8;  m1 = 6'sd3; end
      3'd3:    begin m2 = 6'sd9;  m1 = 6'sd3; end
      3'd4:    begin m2 = 6'sd10; m1 = 6'sd4; end
      3'd5:    begin m2 = 6'sd10; m1 = 6'sd4; end
      3'd6:    begin m2 = 6'sd11; m1 = 6'sd4; end
      default: begin m2 = 6'sd12; m1 = 6'sd5; end
    endcase
    if (v >= m2)       srt_digit = 3'd2;
    else if (v >= m1)  srt_digit = 3'd1;
    else if (v >= -m1) srt_digit = 3'd0;
    else if (v >= -m2) srt_digit = 3'b111;
    else               srt_digit = 3'b110;
  endfunction

  logic [2:0]  dgt;
  logic [1:0]  dgt_neg;
  logic [1:0]  pair;
  logic        root_q;
  assign dgt     = srt_digit(s_sig[67:62], b_sig[62:60]);
  assign dgt_neg = 2'd0 - dgt[1:0];
  assign pair    = a_sig[63:62];  // the next two radicand bits
  assign root_q  = ~ad_sum[67];

  // Operands of the shared units, by action.
  always_comb begin
    ex_x = s_exp; ex_y = 17'd0; ex_sub = 1'b0;
    unique case (uw.act)
      DA_RENA: begin ex_x = a_exp; ex_y = {10'd0, lz_out}; ex_sub = 1'b1; end
      DA_RENB: begin ex_x = b_exp; ex_y = {10'd0, lz_out}; ex_sub = 1'b1; end
      DA_RENS: begin ex_x = a_exp; ex_y = {10'd0, lz_out}; ex_sub = 1'b1; end
      DA_EXPD: begin ex_x = is_rem ? s_exp : a_exp; ex_y = b_exp; ex_sub = 1'b1; end
      DA_SWAP: begin ex_x = 17'd0; ex_y = d_q; ex_sub = 1'b1; end
      DA_MEXP: begin ex_x = a_exp; ex_y = b_exp; end
      DA_M3:   begin ex_y = (prec == 2'd1) ? 17'd16383 : 17'd16382; ex_sub = 1'b1; end
      DA_DEXP: begin ex_x = a_exp; ex_y = b_exp; ex_sub = 1'b1; end
      DA_DLD:  ex_y = 17'd16383 + {10'd0, drop_of(prec)};
      DA_RLD:  begin ex_y = d_q; ex_sub = 1'b1; end
      DA_SEXP: begin ex_x = b_exp; ex_y = 17'd16383 + {9'd0, drop_of(prec), 1'b0}; end
      DA_FSPC, DA_XSPC: begin ex_x = EXP_INT; ex_y = b_exp; ex_sub = 1'b1; end
      DA_CRY:  ex_y = 17'd1;
      DA_NORM: begin ex_y = {10'd0, cnt_q}; ex_sub = 1'b1; end
      DA_RND, DA_IRND: ex_y = 17'd1;
      DA_RNG:  begin ex_y = {10'd0, lz_out}; ex_sub = 1'b1; end
      default: ;
    endcase
  end

  // 4w; the BCD store adds a 1 below each 4w, a third of an ulp on the
  // dividend.
  logic [68:0] ad_x4;
  assign ad_x4 = {1'b0, s_sig[65:1], (uw.act == DA_SSTP) ? pair : {s_sig[0], 1'b0},
                  (uw.act == DA_DSTP) & is_bcs};

  // Significand adder operands, 69 bits: the multiply's accumulator and
  // its multiples at offset 3 (the sum of the accumulator and 3M needs bit
  // 68). Divide: w with weight 1 at S[66], D at offset 3. Root: twice the
  // remainder, units at bit 1. BCD load: 10 acc + d, the digit in the
  // free low bits (x[5:3] <= 7, y[3]) and the carry-in through x[2:0] = 111.
  // BCD store: 10 g with the fraction g at S[65:1], the digit above it.
  always_comb begin
    logic [3:0] d;
    logic       c;
    d    = b_exp[11:8];
    c    = d[3] & d[0];
    ad_x = {2'd0, a_sig, 3'd0}; ad_y = {1'b0, s_sig}; ad_sub = 1'b0; ad_ci = 1'b0;
    unique case (uw.act)
      DA_ADD:  ad_sub = esub_q;
      DA_NEG:  begin ad_x = 69'd0; ad_sub = 1'b1; end
      DA_IFIN: begin ad_x = 69'd0; ad_sub = b_sign; end
      DA_ILD:  begin ad_x = 69'd0; ad_y = {{2{opnd[63]}}, opnd[63:0], 3'd0}; ad_sub = opnd[63]; end
      DA_BSTP: begin
        ad_x  = {2'd0, s_sig[63:3], d[2:0] | {3{d[3]}}, {3{c}}};
        ad_y  = {2'd0, s_sig[65:3], d[3], 3'd0};
        ad_ci = c;
      end
      DA_BDIG: ad_x = ad_x4;  // 8 g + 2 g: S[66] and S[0] are 0 from QSEL on
      DA_RND, DA_IRND: begin ad_x = {2'd0, rnd_sig, 3'd0}; ad_y = rnd_up ? {2'd0, rnd_lsb, 3'd0} : 69'd0; end
      DA_SIGC: begin ad_y = {2'd0, b_sig, 3'd0}; ad_sub = 1'b1; end
      DA_MSTP: begin
        unique case (b_sig[1:0])
          2'd0:    ad_x = 69'd0;
          2'd1:    ad_x = {2'd0, a_sig, 3'd0};
          2'd2:    ad_x = {1'b0, a_sig, 4'd0};
          default: ad_x = {x_q, 3'd0};
        endcase
      end
      DA_PRD:  if (prec != 2'd1) ad_x = 69'd0;  // double: + M for the integer bit
      DA_DSTP, DA_SSTP: begin  // 4w, or 4 (2 rem) + 2 pair
        ad_x   = ad_x4;
        // Root: - (4 root + 1), or + (4 root + 3) after a negative remainder.
        ad_y   = (uw.act == DA_SSTP)  ? {2'd0, b_sig, s_sig[67], 2'b10} :
                 (dgt[1:0] == 2'd0)   ? 69'd0 :
                 (dgt[1] & ~dgt[0])   ? {1'b0, b_sig, 4'd0} : {2'd0, b_sig, 3'd0};
        ad_sub = (uw.act == DA_SSTP)  ? ~s_sig[67] : ~dgt[2] & (dgt[1:0] != 2'd0);
      end
      DA_QSEL: begin  // 8 X - (8 QM + 4 neg): the quotient less neg above a bit that is neg
        ad_x   = {x_q, 3'd0};
        ad_y   = {qm_q, s_sig[67], 2'd0};
        ad_sub = 1'b1;
      end
      default: ;  // M3: M + 2M; CORR: D + w
    endcase
  end

  always_comb begin
    unique case (uw.act)
      DA_RENB: lz_in = {b_sig, 2'd0};
      DA_LZC:  lz_in = s_sig[66:1];
      DA_RNG:  lz_in = {s_sig[66:3], 2'd0};
      default: lz_in = {a_sig, 2'd0};
    endcase
  end

  always_comb begin
    sh_in = s_sig; sh_amt = 7'd0; sh_left = 1'b0;
    unique case (uw.act)
      DA_SPEC, DA_MSPC, DA_DSPC, DA_SSPC, DA_RSPC, DA_FSPC: if (xs_src == XS_B) sh_in = {1'b0, b_sig, 3'd0};
                                                   else sh_in = {1'b0, a_sig, 3'd0};
      DA_RENA, DA_RENS: begin sh_in = {1'b0, a_sig, 3'd0}; sh_amt = lz_out; sh_left = 1'b1; end
      DA_RENB: begin sh_in = {1'b0, b_sig, 3'd0}; sh_amt = lz_out; sh_left = 1'b1; end
      DA_ALGN: begin sh_in = {1'b0, b_sig, 3'd0}; sh_amt = clamp67(d_q); end
      DA_CRY:  sh_amt = 7'd1;
      DA_NORM: begin sh_amt = cnt_q; sh_left = 1'b1; end
      DA_DNRM: sh_amt = dnrm_amt_q;
      DA_PACK: begin sh_in = {1'b0, s_sig[66:3], 3'd0}; sh_amt = cnt_q; sh_left = 1'b1; end
      DA_MEXP: begin sh_in = {1'b0, a_sig, 3'd0}; sh_amt = 7'd1; sh_left = 1'b1; end
      DA_MSTP: begin sh_in = {1'b0, b_sig, 3'd0}; sh_amt = 7'd2; end
      DA_M3:   begin sh_in = {1'b0, b_sig, 3'd0}; sh_amt = drop_of(prec); end
      DA_DLD:  begin sh_in = {1'b0, a_sig, 3'd0}; sh_amt = (prec == 2'd1) ? 7'd2 : 7'd3; end
      DA_RLD:  sh_amt = par_q ? 7'd2 : 7'd3;
      DA_SLD:  begin sh_in = {1'b0, b_sig, 3'd0}; sh_amt = par_q ? 7'd2 : 7'd1; sh_left = 1'b1; end
      DA_SSTP: begin sh_in = {1'b0, a_sig, 3'd0}; sh_amt = 7'd2; sh_left = 1'b1; end
      DA_SRES: begin sh_in = {1'b0, b_sig, 3'd0}; sh_amt = 7'd1; end
      DA_IALN: begin sh_in = {1'b0, b_sig, 3'd0}; sh_amt = clamp67(d_q) & {7{~d_q[16]}}; end
      DA_BSTP, DA_BDIG: begin sh_in = {1'b0, b_sig, 3'd0}; sh_amt = 7'd4; sh_left = 1'b1; end
      DA_BLD:  sh_amt = 7'd3;
      default: ;
    endcase
  end

  // Test for JCOND, from registered state.
  always_comb begin
    unique case (uw.act)
      DA_SPEC, DA_MSPC, DA_DSPC, DA_SSPC, DA_RSPC, DA_FSPC, DA_XSPC, DA_BSPC: cond = xs_hit;
      DA_LZC, DA_CORR: cond = s_sig == 68'd0;
      DA_MSTP, DA_DSTP, DA_SSTP, DA_BSTP, DA_BDIG: cond = cnt_q != 7'd0;
      DA_NORM: cond = int_res;
      DA_IRND: cond = is_bcs;
      DA_QSEL: cond = ~is_bcs;
      default: cond = 1'b0;
    endcase
  end

  // The clock's register updates.
  always_comb begin
    logic        swap, to_inf, rng_ok;
    logic [63:0] sig;
    logic [16:0] k;

    // Hold, or clear the working state on a start.
    // A, B and S significands load only when written (a_we, b_we, s_we);
    // their next value is otherwise unused.
    a_sign_d = a_sign; a_exp_d = a_exp; a_sig_d = sh_out[66:3]; a_cls_d = a_cls; a_we = 1'b0;
    b_sign_d = b_sign; b_exp_d = b_exp; b_sig_d = sh_out[66:3]; b_cls_d = b_cls; b_we = 1'b0;
    d_d = d_q; esub_d = esub_q & ~start; tiny_d = tiny_q & ~start; inex_d = inex_q & ~start;
    unord_d = unord_q; dnrm_d = dnrm_q; dnrm_amt_d = dnrm_amt_q; rel_d = rel_q;
    stin_d = stin_q; par_d = par_q; cmpl_d = cmpl_q; ixo_d = ixo_q & ~start;
    if (start) begin
      s_sign_d = 1'b0; s_exp_d = 17'd0; s_sig_d = 68'd0; s_we = 1'b1; cnt_d = 7'd0;
      fl_d = 8'd0; rsn_d = 3'd0; rup_d = 1'b0; cmp_d = 6'd0;
    end else begin
      s_sign_d = s_sign; s_exp_d = s_exp; s_sig_d = sh_out; s_we = 1'b0; cnt_d = cnt_q;
      fl_d = fl_q; rsn_d = rsn_q; rup_d = rup_q; cmp_d = cmp_q;
    end
    res_ld = 1'b0;
    swap = 1'b0; to_inf = 1'b0; sig = 64'd0; rng_ok = 1'b0;
    // Denormalize amount: subnormal scale minus the normalized exponent.
    k = subexp_of(prec) - ex_sum;

    if (step) begin
      unique case (uw.act)
        DA_UNPA: begin
          a_sign_d = opnd[79];
          a_exp_d  = {2'd0, opnd[78:64]};
          a_sig_d  = opnd[63:0]; a_we = 1'b1;
          a_cls_d  = classify(opnd[78:64], opnd[63:0]);
        end

        DA_RENA: begin
          if (a_cls == CL_SUB || a_unn) fl_d[FL_DE] = 1'b1;
          if (is_fin(a_cls)) begin
            if (a_sig == 64'd0) begin  // a pseudo-zero
              a_cls_d = CL_ZERO;
              a_exp_d = 17'd0;
            end else begin
              a_sig_d = sh_out[66:3]; a_we = 1'b1;
              a_exp_d = ex_sum;
            end
          end
        end

        DA_RENB: begin
          if (b_cls == CL_SUB || b_unn) fl_d[FL_DE] = 1'b1;
          if (is_fin(b_cls)) begin
            if (b_sig == 64'd0) begin
              b_cls_d = CL_ZERO;
              b_exp_d = 17'd0;
            end else begin
              b_sig_d = sh_out[66:3]; b_we = 1'b1;
              b_exp_d = ex_sum;
            end
          end
        end

        DA_UNPB: begin
          if (opnd_cmpz || opnd_load) begin
            b_sign_d = opnd_load & a_sign;
            b_exp_d  = 17'd0;
            b_sig_d  = 64'd0; b_we = 1'b1;
            b_cls_d  = CL_ZERO;
          end else begin
            b_sign_d = opnd[79] ^ ((kind == K_SUB) || (kind == K_RVSUB));
            b_exp_d  = {2'd0, opnd[78:64]};
            b_sig_d  = opnd[63:0]; b_we = 1'b1;
            b_cls_d  = classify(opnd[78:64], opnd[63:0]);
          end
        end

        DA_EXPD: d_d = ex_sum;

        DA_SWAP: begin
          swap   = (b_cls == CL_ZERO) ? 1'b0 : (a_cls == CL_ZERO) ? 1'b1 : d_q[16];
          esub_d = a_sign ^ b_sign;
          if (swap) begin
            a_sign_d = b_sign; a_exp_d = b_exp; a_sig_d = b_sig; a_cls_d = b_cls; a_we = 1'b1;
            b_sign_d = a_sign; b_exp_d = a_exp; b_sig_d = a_sig; b_cls_d = a_cls; b_we = 1'b1;
            d_d      = ex_sum;
          end
        end

        DA_ALGN: begin
          s_sig_d  = sh_out; s_we = 1'b1;
          s_exp_d  = a_exp;
          s_sign_d = a_sign;
        end

        DA_ADD: begin s_sig_d = ad_sum[67:0]; s_we = 1'b1; end

        DA_NEG: begin
          if (esub_q && s_sig[67]) begin
            s_sig_d  = ad_sum[67:0]; s_we = 1'b1;
            s_sign_d = ~s_sign;
          end
        end

        DA_CRY: begin
          if (!esub_q && s_sig[67]) begin
            s_sig_d = sh_out; s_we = 1'b1;
            s_exp_d = ex_sum;
          end
        end

        DA_LZC: begin
          cnt_d = lz_out;
          if (s_sig == 68'd0) begin  // an exact cancellation, or an integer rounded to zero
            s_sign_d = int_res ? s_sign : (rm == 2'd3);
            s_exp_d  = 17'd0;
            if (inex_q) fl_d[FL_INX] = 1'b1;
          end
        end

        DA_NORM: begin
          s_sig_d    = sh_out; s_we = 1'b1;
          s_exp_d    = ex_sum;
          dnrm_d     = !k[16] && (k != 17'd0);
          dnrm_amt_d = clamp67(k);
        end

        DA_DNRM: begin
          tiny_d = $signed(s_exp) < $signed(emin_of(prec));
          if (dnrm_q) begin
            s_sig_d = sh_out; s_we = 1'b1;
            s_exp_d = subexp_of(prec);
          end
        end

        DA_RND, DA_IRND: begin  // FINT rounds twice: inexact and R accumulate
          inex_d = inex_q | rnd_g | rnd_st;
          rup_d  = rup_q | (rnd_up & ~is_rem);  // a remainder reports no R bit
          if (ad_sum[67]) begin  // carry out of the integer bit
            s_sig_d = {2'b01, 66'd0}; s_we = 1'b1;
            s_exp_d = ex_sum;
          end else begin
            s_sig_d = {1'b0, ad_sum[66:3], 3'd0}; s_we = 1'b1;
          end
        end

        DA_RNG: begin
          sig   = s_sig[66:3];
          cnt_d = 7'd0;
          if (inex_q)           fl_d[FL_INX] = 1'b1;
          if (tiny_q && inex_q) fl_d[FL_UN]  = 1'b1;
          if (sig == 64'd0) begin
            s_exp_d = 17'd0;
          end else if ($signed(s_exp) > $signed(emax_of(prec))) begin
            fl_d[FL_FOV] = 1'b1;
            fl_d[FL_INX] = 1'b1;
            unique case (rm)
              2'd0:    to_inf = 1'b1;
              2'd1:    to_inf = 1'b0;
              2'd2:    to_inf = ~s_sign;
              default: to_inf = s_sign;
            endcase
            if (to_inf) begin
              s_exp_d = EXP_MAX;
              s_sig_d = 68'd0; s_we = 1'b1;
            end else begin
              s_exp_d = emax_of(prec);
              s_sig_d = {1'b0, keep_of(prec), 3'd0}; s_we = 1'b1;
            end
          end else if (out_q) begin  // a store keeps the denormalized form
            s_exp_d = s_exp;
          end else if ($signed(ex_sum) >= $signed(17'd1)) begin
            s_exp_d = ex_sum;
            cnt_d   = lz_out;
          end else begin  // extended subnormal: the e = 0 form
            s_exp_d = 17'd0;
            cnt_d   = s_exp[6:0];
          end
        end

        DA_PACK: res_ld = 1'b1;

        DA_SPCC: begin
          if ((a_cls == CL_SNAN) || (b_cls == CL_SNAN)) fl_d[FL_NAN] = 1'b1;
          unord_d = is_nan(a_cls) || is_nan(b_cls);
        end

        DA_SIGC: begin
          if (d_q != 17'd0)                                rel_d = d_q[16] ? REL_LT : REL_GT;
          else if ((a_cls == CL_INF) || (ad_sum[67:0] == 68'd0)) rel_d = REL_EQ;
          else                                             rel_d = ad_sum[67] ? REL_LT : REL_GT;
        end

        DA_SREL: begin
          if ((a_cls == CL_ZERO) && (b_cls == CL_ZERO)) rel_d = REL_EQ;
          else if (a_cls == CL_ZERO)                     rel_d = b_sign ? REL_GT : REL_LT;
          else if (b_cls == CL_ZERO)                     rel_d = a_sign ? REL_LT : REL_GT;
          else if (a_sign != b_sign)                     rel_d = a_sign ? REL_LT : REL_GT;
          else if (a_sign)                               rel_d = (rel_q == REL_GT) ? REL_LT :
                                                                 (rel_q == REL_LT) ? REL_GT : REL_EQ;
          else                                           rel_d = rel_q;
        end

        DA_CMAP: begin
          if (unord_q) begin
            cmp_d = CC_UN;
            if ((kind == K_CMPX) || (kind == K_CMPZX)) begin
              fl_d[FL_INV] = 1'b1;
              rsn_d        = RS_UNORDERED;
            end
          end else begin
            unique case (rel_q)
              REL_LT:  cmp_d = CC_LT;
              REL_GT:  cmp_d = CC_GT;
              default: cmp_d = CC_EQ;
            endcase
          end
        end

        DA_RENS: begin
          if (a_cls == CL_SUB || a_unn) fl_d[FL_DE] = 1'b1;
          s_sign_d = a_sign;
          if (is_fin(a_cls)) begin
            if (a_sig == 64'd0) begin
              a_cls_d = CL_ZERO;
            end else begin
              s_sig_d = sh_out; s_we = 1'b1;
              s_exp_d = ex_sum;
            end
          end
        end

        DA_SPEC, DA_MSPC, DA_DSPC, DA_SSPC, DA_RSPC, DA_FSPC, DA_XSPC, DA_BSPC: begin
          if ((uw.act == DA_FSPC) || (uw.act == DA_XSPC)) d_d = ex_sum;  // the integer-point shift
          if ((uw.act == DA_BSPC) && !xs_hit) begin
            s_exp_d  = EXP_INT;
            s_sign_d = b_sign;
            cnt_d    = 7'd18;
          end
          if (xs_hit) begin
            s_sign_d = xs_sign;
            s_exp_d  = xs_exp;
            unique case (xs_src)
              XS_A, XS_B: begin s_sig_d = sh_out | {2'd0, xs_quiet, 65'd0}; s_we = 1'b1; end
              XS_QNAN:    begin s_sig_d = {1'b0, QNAN_SIG, 3'd0}; s_we = 1'b1; end
              default:    begin s_sig_d = xs_ind ? ind_sig : 68'd0; s_we = 1'b1; end
            endcase
            fl_d     = fl_q | xs_fl;
            rsn_d    = xs_rsn;
            cmp_d    = xs_cmp;
          end
        end

        DA_MEXP: begin
          s_exp_d  = ex_sum;
          s_sign_d = a_sign ^ b_sign;
          s_sig_d  = sh_out; s_we = 1'b1;
        end

        DA_M3: begin
          b_sig_d = sh_out[66:3] & ~((prec == 2'd1) ? 64'h0010_0000_0000_0000 : 64'd0); b_we = 1'b1;
          stin_d  = |sh_out[2:0];
          s_exp_d = ex_sum;
          s_sig_d = 68'd0; s_we = 1'b1;
          cnt_d   = half_of(prec) - 7'd1;
        end

        DA_MSTP: begin
          s_sig_d = {1'b0, ad_sum[68:5], 3'd0}; s_we = 1'b1;
          b_sig_d = {ad_sum[4:3], sh_out[64:3]}; b_we = 1'b1;
          cnt_d   = cnt_q - 7'd1;
        end

        DA_PRD: begin s_sig_d = {ad_sum[67:3], b_sig[63], b_sig[62], stin_q | (|b_sig[61:0])}; s_we = 1'b1; end

        DA_DEXP: begin
          s_exp_d  = ex_sum;
          s_sign_d = a_sign ^ b_sign;
        end

        DA_DLD: begin
          s_exp_d = ex_sum;
          s_sig_d = sh_out; s_we = 1'b1;
          cnt_d   = half_of(prec) + 7'd1;
        end

        DA_DSTP: begin
          s_sig_d = ad_sum[67:0]; s_we = 1'b1;
          cnt_d   = cnt_q - 7'd1;
        end

        DA_QSEL: begin  // cnt: the BCD store's digits (the divide's LZC replaces it)
          s_sig_d = {1'b0, ad_sum[68:3], s_sig != 68'd0}; s_we = 1'b1;
          cnt_d   = 7'd18;
          if (is_bcs) begin  // the fraction alone; a quotient of one or more is h >= 10^19
            s_sig_d = {2'd0, ad_sum[67:3], 1'b0};
            if (ad_sum[68]) begin
              ixo_d       = 1'b1;
              fl_d[FL_IX] = 1'b1;
            end
          end
        end

        DA_RLEN: begin
          // n quotient bits: d + 1 (complete), nS, or none below zero.
          if (d_q[16]) begin
            d_d = 17'h1FFFF; par_d = 1'b0; cmpl_d = 1'b1; cnt_d = 7'd0;
          end else if (d_q <= {10'd0, nsm1_of(prec)}) begin
            par_d = ~d_q[0]; cmpl_d = 1'b1; cnt_d = (d_q[6:0] + 7'd1) >> 1;
          end else begin
            d_d = {10'd0, nsm1_of(prec)}; par_d = prec == 2'd1; cmpl_d = 1'b0; cnt_d = half_of(prec);
          end
        end

        DA_RLD: begin
          s_exp_d = ex_sum;
          s_sig_d = sh_out; s_we = 1'b1;
          a_sig_d = b_sig; a_we = 1'b1;
        end

        DA_CORR: begin
          cmp_d         = 6'd0;
          cmp_d[CF_FD]  = cmpl_q;
          if (s_sig == 68'd0) begin
            s_exp_d       = 17'd0;
            cmp_d[CF_FZ]  = 1'b1;
            cmp_d[CF_FH]  = x_q[0] ^ qm_q[0];
          end else begin
            cmp_d[CF_FS]  = s_sign;
            cmp_d[CF_FH]  = x_q[0] ^ qm_q[0] ^ s_sig[67];
            if (s_sig[67]) begin s_sig_d = ad_sum[67:0]; s_we = 1'b1; end
          end
        end

        DA_SEXP: begin
          s_exp_d  = {ex_sum[16], ex_sum[16:1]};
          par_d    = ex_sum[0];
          s_sign_d = 1'b0;
        end

        DA_SLD: begin
          a_sig_d = sh_out[66:3]; a_we = 1'b1;
          b_sig_d = 64'd1; b_we = 1'b1;
          s_sig_d = par_q ? {65'd0, b_sig[62], ~b_sig[62], 1'b0} : 68'd0; s_we = 1'b1;
          cnt_d   = nsm1_of(prec);
        end

        DA_SSTP: begin
          s_sig_d = ad_sum[67:0]; s_we = 1'b1;
          b_sig_d = {b_sig[62:0], root_q}; b_we = 1'b1;
          a_sig_d = sh_out[66:3]; a_we = 1'b1;
          cnt_d   = cnt_q - 7'd1;
        end

        DA_SRES: begin
          s_sig_d     = sh_out; s_we = 1'b1;
          s_sig_d[66] = prec == 2'd2;
          // A negative remainder is exact at -(2 root + 1), stored as ~(4 root + 1).
          s_sig_d[0]  = ((s_sig ^ ({68{s_sig[67]}} & {1'b1, prec != 2'd2, ~b_sig, 2'b10})) != 68'd0) ||
                        (a_sig != 64'd0);
        end

        DA_SOP: begin
          s_sign_d = (kind == K_NEG) ? ~b_sign : (kind == K_ABS) ? 1'b0 : b_sign;
          s_exp_d  = b_exp;
          s_sig_d  = {1'b0, b_sig, 3'd0}; s_we = 1'b1;
          if (kind == K_CLR) begin
            s_sign_d = 1'b0;
            s_exp_d  = 17'd0;
            s_sig_d  = 68'd0; s_we = 1'b1;
          end
        end

        DA_IALN: begin
          s_sig_d  = sh_out; s_we = 1'b1;
          s_sign_d = b_sign;
          s_exp_d  = (is_fint && d_q[16]) ? b_exp : EXP_INT;
          if (!is_fint && d_q[16]) begin  // 2^64 or more
            ixo_d        = 1'b1;
            fl_d[FL_IX]  = 1'b1;
          end
        end

        DA_ILD: begin
          s_sig_d  = ad_sum[67:0]; s_we = 1'b1;
          s_sign_d = opnd[63];
          s_exp_d  = EXP_INT;
        end

        DA_IFIN: begin
          rng_ok   = prec[0] ? (ad_sum[67] == ad_sum[66]) : ((&ad_sum[67:34]) || !(|ad_sum[67:34]));
          s_sign_d = 1'b0;
          s_exp_d  = 17'd0;
          if (ixo_q || !rng_ok) begin
            s_sig_d     = ind_sig; s_we = 1'b1;
            fl_d[FL_IX] = 1'b1;
            rup_d       = 1'b0;
          end else begin
            s_sig_d = {ad_sum[67:3], 3'd0}; s_we = 1'b1;
            if (inex_q) fl_d[FL_INX] = 1'b1;
          end
        end

        DA_BSTP: begin
          s_sig_d = ad_sum[67:0]; s_we = 1'b1;
          b_sig_d = sh_out[66:3]; b_we = 1'b1;
          b_exp_d = {5'd0, b_exp[7:0], b_sig[63:60]};
          cnt_d   = cnt_q - 7'd1;
        end

        DA_BLD: begin
          s_sig_d = sh_out; s_we = 1'b1;
          b_sig_d = P19; b_we = 1'b1;
          cnt_d   = 7'd33;
        end

        DA_BDIG: begin
          s_sig_d = {2'd0, ad_sum[64:0], 1'b0}; s_we = 1'b1;
          b_sig_d = sh_out[66:3] | {60'd0, ad_sum[68:65]}; b_we = 1'b1;
          b_exp_d = {5'd0, b_exp[7:0], b_sig[63:60]};
          cnt_d   = cnt_q - 7'd1;
        end

        DA_BOUT: begin
          s_sign_d = b_sign;
          s_exp_d  = b_exp;
          s_sig_d  = {1'b0, b_sig, 3'd0}; s_we = 1'b1;
          cnt_d    = 7'd0;
          if (ixo_q)       rup_d = 1'b0;
          else if (inex_q) fl_d[FL_INX] = 1'b1;
        end

        default: ;  // WB, NOJOB
      endcase
    end
  end

  always_ff @(posedge clk) begin
    a_sign <= a_sign_d; a_exp <= a_exp_d; a_cls <= a_cls_d;
    b_sign <= b_sign_d; b_exp <= b_exp_d; b_cls <= b_cls_d;
    if (a_we) a_sig <= a_sig_d;
    if (b_we) b_sig <= b_sig_d;
  end

  always_ff @(posedge clk) begin
    s_sign <= s_sign_d; s_exp <= s_exp_d;
    if (s_we) s_sig <= s_sig_d;
  end

  always_ff @(posedge clk) begin
    d_q <= d_d; cnt_q <= cnt_d; esub_q <= esub_d; tiny_q <= tiny_d; inex_q <= inex_d;
    unord_q <= unord_d; dnrm_q <= dnrm_d; dnrm_amt_q <= dnrm_amt_d; rel_q <= rel_d; rup_q <= rup_d;
    stin_q <= stin_d; par_q <= par_d; cmpl_q <= cmpl_d; ixo_q <= ixo_d;
    fl_q <= fl_d; rsn_q <= rsn_d; cmp_q <= cmp_d;
  end

  // X and QM: cleared by a divide or remainder load, X loaded with 3M,
  // both shifted left two with a digit by an SRT step.
  logic xq_clr, x_ld, xq_sh;
  assign xq_clr = step && ((uw.act == DA_DLD) || (uw.act == DA_RLD) || (uw.act == DA_BLD));
  assign x_ld   = step && (uw.act == DA_M3);
  assign xq_sh  = step && (uw.act == DA_DSTP);

  always_ff @(posedge clk) begin
    if (xq_clr) begin
      x_q  <= 66'd0;
      qm_q <= 66'd0;
    end else if (x_ld) begin
      x_q  <= ad_sum[68:3];
    end else if (xq_sh) begin
      x_q  <= {x_q[63:0], dgt[2] ? 2'd0 : dgt[1:0]};
      qm_q <= {qm_q[63:0], dgt[2] ? dgt_neg : 2'd0};
    end
  end

  // ---- result latch ----------------------------------------------------
  // Justification: (reg-a) the result the Interface Processor takes, held
  // from the last clock until the next operation's PACK.
  logic [79:0] res_q;
  logic [7:0]  res_fl_q;
  logic [2:0]  res_rsn_q;
  logic        res_rup_q;
  logic [5:0]  res_cmp_q;

  always_ff @(posedge clk) begin
    if (res_ld) begin
      res_q     <= {s_sign, s_exp[14:0], sh_out[66:3]};
      res_fl_q  <= fl_q;
      res_rsn_q <= rsn_q;
      res_rup_q <= rup_q;
      res_cmp_q <= cmp_q;
    end
  end

  assign res        = res_q;
  assign res_flags  = res_fl_q;
  assign res_reason = res_rsn_q;
  assign res_rup    = res_rup_q;
  assign res_cmp    = res_cmp_q;

endmodule

`default_nettype wire
