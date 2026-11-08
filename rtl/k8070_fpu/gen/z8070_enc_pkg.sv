// DERIVED FILE, but a COMMITTED SOURCE of k8000: check it in, review its
// diffs, and build from it. Emitted by cmd/fpuenc from the Z8070 Go model
// (isa.go); 'make gen-fpu' overwrites it. Do not hand-edit.
//
// z8070_enc_pkg -- the Z8070 operation-field table: one line per row, in
// row order, first match on (code, template) wins. code = {w2[15:14],
// w2[7:4]}. Each row keeps its source tag: software (the CP/M-8000
// assembler table and emulator) or assumed (no source).

`default_nettype none

package z8070_enc_pkg;

  typedef enum logic [2:0] {
    TPL_MEM_FROM_EPU   = 3'd0,
    TPL_EPU_FROM_MEM   = 3'd1,
    TPL_CPU_FROM_EPU   = 3'd2,
    TPL_EPU_FROM_CPU   = 3'd3,
    TPL_FCW_FROM_EPU   = 3'd4,
    TPL_EPU_FROM_FCW   = 3'd5,
    TPL_INTERNAL       = 3'd6
  } tpl_e;

  typedef enum logic [5:0] {
    MN_INVALID   = 6'd0,
    MN_FADD      = 6'd1,
    MN_FSUB      = 6'd2,
    MN_FRVSUB    = 6'd3,
    MN_FMUL      = 6'd4,
    MN_FDIV      = 6'd5,
    MN_FRDIV     = 6'd6,
    MN_FSQR      = 6'd7,
    MN_FREMSNF   = 6'd8,
    MN_FREMSTEP  = 6'd9,
    MN_FPWR2     = 6'd10,
    MN_FABS      = 6'd11,
    MN_FNEG      = 6'd12,
    MN_FCLR      = 6'd13,
    MN_FINT      = 6'd14,
    MN_FLD       = 6'd15,
    MN_FLDNF     = 6'd16,
    MN_FLDBCD    = 6'd17,
    MN_FLDIL     = 6'd18,
    MN_FLDIQ     = 6'd19,
    MN_FLDTL     = 6'd20,
    MN_FLDTQ     = 6'd21,
    MN_FCP       = 6'd22,
    MN_FCPF      = 6'd23,
    MN_FCPFX     = 6'd24,
    MN_FCPX      = 6'd25,
    MN_FCPZ      = 6'd26,
    MN_FCPZFX    = 6'd27,
    MN_FCPZNF    = 6'd28,
    MN_FCPZXNF   = 6'd29,
    MN_FLDCTL    = 6'd30,
    MN_FLDCTLB   = 6'd31,
    MN_FSETFLG   = 6'd32,
    MN_FRESFLG   = 6'd33,
    MN_FSETTRAP  = 6'd34,
    MN_FRESTRAP  = 6'd35,
    MN_FSETMODE  = 6'd36
  } mn_e;

  typedef enum logic [3:0] {
    FMT_SINGLE   = 4'd0,
    FMT_DOUBLE   = 4'd1,
    FMT_EXTENDED = 4'd2,
    FMT_INT32    = 4'd3,
    FMT_INT64    = 4'd4,
    FMT_BCD      = 4'd5,
    FMT_CTL      = 4'd6,
    FMT_BYTE     = 4'd7,
    FMT_NONE     = 4'd8
  } fmt_e;

  typedef enum logic [1:0] {
    DIR_NONE = 2'd0,
    DIR_IN   = 2'd1,
    DIR_OUT  = 2'd2
  } dir_e;

  typedef enum logic [2:0] {
    SZ_NONE  = 3'd0,
    SZ_FLOAT = 3'd1,
    SZ_INT   = 3'd2,
    SZ_BCD   = 3'd3,
    SZ_CTL   = 3'd4,
    SZ_BYTE  = 3'd5
  } size_e;

  // List-op targets (the plan's select field).
  typedef enum logic [3:0] {
    LIST_STICKY  = 4'd0,
    LIST_COMPARE = 4'd1,
    LIST_TRAP    = 4'd2
  } list_e;

  typedef struct packed {
    logic  hit;
    mn_e   mn;
    size_e size;
  } enc_row_t;

  function automatic enc_row_t enc_lookup(input tpl_e tpl, input logic [5:0] code);
    logic [6:0] t;
    enc_row_t   r;
    t = 7'b000_0001 << tpl;
    r = '{hit: 1'b0, mn: MN_INVALID, size: SZ_NONE};
    case (code)
      6'h00: if (|(t & 7'b1000000)) r = '{hit: 1'b1, mn: MN_FCLR, size: SZ_NONE}; // software
      6'h01: if (|(t & 7'b0010000)) r = '{hit: 1'b1, mn: MN_FCPZ, size: SZ_BYTE}; // software
             else if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FCPZNF, size: SZ_FLOAT}; // assumed
      6'h02: if (|(t & 7'b0010000)) r = '{hit: 1'b1, mn: MN_FCPZFX, size: SZ_BYTE}; // software
             else if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FCPZXNF, size: SZ_FLOAT}; // assumed
      6'h09: if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FRVSUB, size: SZ_FLOAT}; // software
      6'h0A: if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FRDIV, size: SZ_FLOAT}; // software
      6'h11: if (|(t & 7'b0010000)) r = '{hit: 1'b1, mn: MN_FCPF, size: SZ_BYTE}; // software
             else if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FCP, size: SZ_FLOAT}; // software
      6'h12: if (|(t & 7'b0010000)) r = '{hit: 1'b1, mn: MN_FCPFX, size: SZ_BYTE}; // software
             else if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FCPX, size: SZ_FLOAT}; // software
      6'h18: if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FADD, size: SZ_FLOAT}; // software
      6'h19: if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FSUB, size: SZ_FLOAT}; // software
      6'h1A: if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FDIV, size: SZ_FLOAT}; // software
      6'h1B: if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FMUL, size: SZ_FLOAT}; // software
      6'h1C: if (|(t & 7'b0010000)) r = '{hit: 1'b1, mn: MN_FREMSTEP, size: SZ_BYTE}; // software
             else if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FREMSNF, size: SZ_FLOAT}; // software
      6'h20: if (|(t & 7'b1001111)) r = '{hit: 1'b1, mn: MN_FLD, size: SZ_FLOAT}; // software
      6'h21: if (|(t & 7'b0001111)) r = '{hit: 1'b1, mn: MN_FLDBCD, size: SZ_BCD}; // software
      6'h22: if (|(t & 7'b0001111)) r = '{hit: 1'b1, mn: MN_FLDIL, size: SZ_INT}; // software
      6'h23: if (|(t & 7'b1001111)) r = '{hit: 1'b1, mn: MN_FLDNF, size: SZ_FLOAT}; // software
      6'h24: if (|(t & 7'b0000101)) r = '{hit: 1'b1, mn: MN_FLDTL, size: SZ_INT}; // software
      6'h28: if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FABS, size: SZ_FLOAT}; // software
      6'h29: if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FNEG, size: SZ_FLOAT}; // software
      6'h2B: if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FPWR2, size: SZ_FLOAT}; // software
      6'h2C: if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FSQR, size: SZ_FLOAT}; // software
      6'h2D: if (|(t & 7'b1001010)) r = '{hit: 1'b1, mn: MN_FINT, size: SZ_FLOAT}; // software
      6'h30: if (|(t & 7'b0001111)) r = '{hit: 1'b1, mn: MN_FLDCTL, size: SZ_CTL}; // software
      6'h31: if (|(t & 7'b0010000)) r = '{hit: 1'b1, mn: MN_FLDCTLB, size: SZ_BYTE}; // software
             else if (|(t & 7'b0100000)) r = '{hit: 1'b1, mn: MN_FLDCTLB, size: SZ_BYTE}; // assumed
      6'h32: if (|(t & 7'b1000000)) r = '{hit: 1'b1, mn: MN_FRESFLG, size: SZ_NONE}; // software
      6'h33: if (|(t & 7'b1000000)) r = '{hit: 1'b1, mn: MN_FSETFLG, size: SZ_NONE}; // software
      6'h34: if (|(t & 7'b1000000)) r = '{hit: 1'b1, mn: MN_FSETMODE, size: SZ_NONE}; // software
      default: ;
    endcase
    return r;
  endfunction

  // FLDCTL select -> words moved; ok = 0 for a select with no register.
  function automatic logic [3:0] ctl_words(input logic [3:0] sel);
    // {ok, words[2:0]}
    case (sel)
      4'd0 : return {1'b1, 3'd2};
      4'd1 : return {1'b1, 3'd2};
      4'd2 : return {1'b1, 3'd2};
      4'd4 : return {1'b1, 3'd2};
      4'd5 : return {1'b1, 3'd1};
      4'd6 : return {1'b1, 3'd5};
      4'd7 : return {1'b1, 3'd5};
      default: return 4'b0000;
    endcase
  endfunction

endpackage

`default_nettype wire
