// z8070_dec -- the Interface Processor's instruction decode, combinational.
//
// Two lookups, used at different bus cycles:
//   IF1 word -> extended-instruction flag, template, EPU ID
//     (Jan83 TM templates: first byte 0E/0F/4E/4F/8E/8F, direction in
//     bits 3:2, ID in bits 1:0; 0E/4E and 8E direction 11 have none)
//   template + word 1 + word 2 -> the decoded plan
//     (operation code {w2[15:14], w2[7:4]} through the one table; rounding
//     w2[13:12]; n-1 in w2[3:0]; F and CPU register fields by template)
//
// The plan is meaningful only when plan_ok is 1.

`default_nettype none

module z8070_dec
  import z8070_enc_pkg::*;
(
  input  logic [15:8] if1_op,      // IF1 first byte
  input  logic [3:2]  if1_dir,     // IF1 direction
  output logic        if1_epa,     // first byte is an extended instruction's
  output logic        if1_ok,      // and it has a template
  output tpl_e        if1_tpl,

  input  tpl_e        tpl,
  input  logic [7:4]  w1,
  input  logic [15:0] w2,
  output logic        plan_ok,
  output mn_e         mn,
  output logic [2:0]  fd,
  output logic [2:0]  fs,
  output fmt_e        fmt,
  output logic [1:0]  rnd,
  output logic [3:0]  sel,
  output logic [7:0]  list_byte,
  output dir_e        dir,
  output logic [3:0]  words
);

  // ---- IF1 -------------------------------------------------------------
  always_comb begin
    if1_epa = 1'b0;
    if1_ok  = 1'b0;
    if1_tpl = TPL_MEM_FROM_EPU;
    unique case (if1_op)
      8'h0E, 8'h4E: if1_epa = 1'b1;
      8'h0F, 8'h4F: begin
        if1_epa = 1'b1;
        if1_ok  = 1'b1;
        if1_tpl = if1_dir[3] ? TPL_MEM_FROM_EPU : TPL_EPU_FROM_MEM;
      end
      8'h8F: begin
        if1_epa = 1'b1;
        if1_ok  = 1'b1;
        if1_tpl = if1_dir[3] ? TPL_EPU_FROM_CPU : TPL_CPU_FROM_EPU;
      end
      8'h8E: begin
        if1_epa = 1'b1;
        unique case (if1_dir)
          2'b00: begin if1_ok = 1'b1; if1_tpl = TPL_FCW_FROM_EPU; end
          2'b10: begin if1_ok = 1'b1; if1_tpl = TPL_EPU_FROM_FCW; end
          2'b01: begin if1_ok = 1'b1; if1_tpl = TPL_INTERNAL;     end
          default: ;
        endcase
      end
      default: ;
    endcase
  end

  // ---- word 2 ----------------------------------------------------------
  enc_row_t   row;
  logic [4:0] n;           // word count, 1-16
  logic [3:0] fsel;        // FLDCTL select or FLDCTLB group field
  logic [3:0] ctl;         // {ok, words} of the FLDCTL select
  mn_e        mn_sz;       // the row's mnemonic, FLDIQ/FLDTQ by word count
  logic       size_ok;

  assign row = enc_lookup(tpl, {w2[15:14], w2[7:4]});
  assign n   = {1'b0, w2[3:0]} + 5'd1;
  assign rnd = w2[13:12];

  always_comb begin
    fd   = 3'd0;
    fs   = 3'd0;
    fsel = 4'd0;
    unique case (tpl)
      TPL_INTERNAL, TPL_FCW_FROM_EPU, TPL_EPU_FROM_FCW: begin
        fd = w1[6:4];
        fs = w2[10:8];
      end
      TPL_CPU_FROM_EPU, TPL_EPU_FROM_CPU: begin
        fd   = w1[6:4];
        fsel = w1[7:4];
      end
      default: begin
        fd   = w2[10:8];
        fsel = w2[11:8];
      end
    endcase
  end

  assign ctl = ctl_words(fsel);

  always_comb begin
    mn_sz   = row.mn;
    fmt     = FMT_SINGLE;
    words   = 4'd0;
    size_ok = 1'b1;
    dir     = DIR_NONE;

    unique case (tpl)
      TPL_INTERNAL: fmt = FMT_NONE;
      TPL_FCW_FROM_EPU, TPL_EPU_FROM_FCW: begin
        fmt   = FMT_BYTE;
        words = 4'd1;
        dir   = (tpl == TPL_EPU_FROM_FCW) ? DIR_IN : DIR_OUT;
      end
      default: begin
        words = n[3:0];
        dir   = (tpl == TPL_MEM_FROM_EPU || tpl == TPL_CPU_FROM_EPU) ? DIR_OUT : DIR_IN;
        unique case (row.size)
          SZ_FLOAT: begin
            unique case (n)
              5'd2:    fmt = FMT_SINGLE;
              5'd4:    fmt = FMT_DOUBLE;
              5'd5:    fmt = FMT_EXTENDED;
              default: size_ok = 1'b0;
            endcase
          end
          SZ_INT: begin
            unique case (n)
              5'd2:    fmt = FMT_INT32;
              5'd4: begin
                fmt = FMT_INT64;
                mn_sz = (row.mn == MN_FLDTL) ? MN_FLDTQ : MN_FLDIQ;
              end
              default: size_ok = 1'b0;
            endcase
          end
          SZ_BCD: begin
            fmt     = FMT_BCD;
            size_ok = (n == 5'd5);
          end
          SZ_CTL: begin
            fmt     = FMT_CTL;
            size_ok = ctl[3] && ({2'b00, ctl[2:0]} == n);
          end
          default: ;
        endcase
      end
    endcase
  end

  assign plan_ok = row.hit && size_ok;

  // List and mode operands. Word 1 bit 5 (trap) is tested before bit 4
  // (compare byte), assumed.
  always_comb begin
    mn   = mn_sz;
    sel  = fsel;
    list_byte = 8'h00;
    unique case (mn_sz)
      MN_FSETFLG, MN_FRESFLG: begin
        list_byte = {w1[7:6], w2[13:8]};
        if (w1[5]) begin
          sel = LIST_TRAP;
          mn  = (mn_sz == MN_FSETFLG) ? MN_FSETTRAP : MN_FRESTRAP;
        end else if (w1[4]) begin
          sel = LIST_COMPARE;
        end else begin
          sel = LIST_STICKY;
        end
      end
      MN_FSETMODE: begin
        sel  = {2'b00, w2[11:10]};   // rounding-mode mask
        list_byte = {6'd0, w2[3:2]};      // rounding-mode value
      end
      MN_FLDCTLB: sel = w1[7:4];
      default: ;
    endcase
  end

endmodule

`default_nettype wire
