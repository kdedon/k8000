// Generated from z8070_dp_ucode.txt by make gen; do not hand-edit.
//
// z8070_dp_rom -- the Data Processor microprogram ROM in logic: the word
// at addr, the entry address of the next operation, and the body
// address of the latched operation. Words are numeric {act, seq, tgt,
// fin}: Quartus 17.0.2 crashes extracting a ROM from enum-valued words.

`default_nettype none

module z8070_dp_rom
  import z8070_dp_rom_pkg::*;
(
  input  logic [UA_W-1:0] addr,
  input  logic [5:0]      kind,        // latched operation
  input  logic [5:0]      next_kind,   // operation to start
  output logic [14:0]     uw,          // dp_uw_t
  output logic [UA_W-1:0] entry,
  output logic [UA_W-1:0] body
);

  localparam logic [UA_W-1:0] UA_UNP_A    = 6'd0;
  localparam logic [UA_W-1:0] UA_UNP_B    = 6'd2;
  localparam logic [UA_W-1:0] UA_ADD_SP   = 6'd4;
  localparam logic [UA_W-1:0] UA_BCL_LD   = 6'd11;
  localparam logic [UA_W-1:0] UA_CMP_SP   = 6'd19;
  localparam logic [UA_W-1:0] UA_SGN_LD   = 6'd24;
  localparam logic [UA_W-1:0] UA_MUL_SP   = 6'd26;
  localparam logic [UA_W-1:0] UA_DIV_SP   = 6'd31;
  localparam logic [UA_W-1:0] UA_REM_A    = 6'd38;
  localparam logic [UA_W-1:0] UA_REM_SP   = 6'd40;
  localparam logic [UA_W-1:0] UA_SQR_SP   = 6'd47;
  localparam logic [UA_W-1:0] UA_FIN_SP   = 6'd52;
  localparam logic [UA_W-1:0] UA_I2F_LD   = 6'd55;
  localparam logic [UA_W-1:0] UA_CVI_SP   = 6'd56;
  localparam logic [UA_W-1:0] UA_TAIL     = 6'd61;

  always_comb begin
    unique case (addr)
      // unpack
      6'd0:   uw = {6'd0 , 2'd0, 6'd0 , 1'b0};  // UNP_A    UNPA  NEXT  -
      6'd1:   uw = {6'd1 , 2'd0, 6'd0 , 1'b0};  // UNP_AR   RENA  NEXT  -
      6'd2:   uw = {6'd2 , 2'd0, 6'd0 , 1'b0};  // UNP_B    UNPB  NEXT  -
      6'd3:   uw = {6'd3 , 2'd3, 6'd0 , 1'b0};  // UNP_BR   RENB  RET   -
      // add
      6'd4:   uw = {6'd4 , 2'd2, 6'd61, 1'b0};  // ADD_SP   SPEC  JCOND TAIL
      6'd5:   uw = {6'd5 , 2'd0, 6'd0 , 1'b0};  // ADD_ED   EXPD  NEXT  -
      6'd6:   uw = {6'd6 , 2'd0, 6'd0 , 1'b0};  // ADD_SW   SWAP  NEXT  -
      6'd7:   uw = {6'd7 , 2'd0, 6'd0 , 1'b0};  // ADD_AL   ALGN  NEXT  -
      6'd8:   uw = {6'd8 , 2'd0, 6'd0 , 1'b0};  // ADD_AD   ADD   NEXT  -
      6'd9:   uw = {6'd9 , 2'd0, 6'd0 , 1'b0};  // ADD_NG   NEG   NEXT  -
      6'd10:  uw = {6'd10, 2'd1, 6'd14, 1'b0};  // ADD_CY   CRY   JMP   ADD_LZ
      // bcdload
      6'd11:  uw = {6'd2 , 2'd0, 6'd0 , 1'b0};  // BCL_LD   UNPB  NEXT  -
      6'd12:  uw = {6'd49, 2'd2, 6'd61, 1'b0};  // BCL_SP   BSPC  JCOND TAIL
      6'd13:  uw = {6'd50, 2'd2, 6'd13, 1'b0};  // BCL_IT   BSTP  JCOND BCL_IT
      // round
      6'd14:  uw = {6'd11, 2'd2, 6'd61, 1'b0};  // ADD_LZ   LZC   JCOND TAIL
      6'd15:  uw = {6'd12, 2'd2, 6'd17, 1'b0};  // ADD_NM   NORM  JCOND ADD_RD
      6'd16:  uw = {6'd13, 2'd0, 6'd0 , 1'b0};  // ADD_DN   DNRM  NEXT  -
      6'd17:  uw = {6'd14, 2'd0, 6'd0 , 1'b0};  // ADD_RD   RND   NEXT  -
      6'd18:  uw = {6'd15, 2'd1, 6'd61, 1'b0};  // ADD_RG   RNG   JMP   TAIL
      // compare
      6'd19:  uw = {6'd18, 2'd0, 6'd0 , 1'b0};  // CMP_SP   SPCC  NEXT  -
      6'd20:  uw = {6'd5 , 2'd0, 6'd0 , 1'b0};  // CMP_ED   EXPD  NEXT  -
      6'd21:  uw = {6'd19, 2'd0, 6'd0 , 1'b0};  // CMP_SG   SIGC  NEXT  -
      6'd22:  uw = {6'd20, 2'd0, 6'd0 , 1'b0};  // CMP_SR   SREL  NEXT  -
      6'd23:  uw = {6'd21, 2'd1, 6'd61, 1'b0};  // CMP_CM   CMAP  JMP   TAIL
      // sign
      6'd24:  uw = {6'd2 , 2'd0, 6'd0 , 1'b0};  // SGN_LD   UNPB  NEXT  -
      6'd25:  uw = {6'd22, 2'd1, 6'd61, 1'b0};  // SGN_OP   SOP   JMP   TAIL
      // mul
      6'd26:  uw = {6'd23, 2'd2, 6'd61, 1'b0};  // MUL_SP   MSPC  JCOND TAIL
      6'd27:  uw = {6'd24, 2'd0, 6'd0 , 1'b0};  // MUL_EX   MEXP  NEXT  -
      6'd28:  uw = {6'd25, 2'd0, 6'd0 , 1'b0};  // MUL_3M   M3    NEXT  -
      6'd29:  uw = {6'd26, 2'd2, 6'd29, 1'b0};  // MUL_IT   MSTP  JCOND MUL_IT
      6'd30:  uw = {6'd27, 2'd1, 6'd10, 1'b0};  // MUL_PR   PRD   JMP   ADD_CY
      // div
      6'd31:  uw = {6'd28, 2'd2, 6'd61, 1'b0};  // DIV_SP   DSPC  JCOND TAIL
      6'd32:  uw = {6'd29, 2'd0, 6'd0 , 1'b0};  // DIV_EX   DEXP  NEXT  -
      6'd33:  uw = {6'd30, 2'd0, 6'd0 , 1'b0};  // DIV_LD   DLD   NEXT  -
      6'd34:  uw = {6'd31, 2'd2, 6'd34, 1'b0};  // DIV_IT   DSTP  JCOND DIV_IT
      6'd35:  uw = {6'd32, 2'd2, 6'd14, 1'b0};  // DIV_QS   QSEL  JCOND ADD_LZ
      // bcdstore
      6'd36:  uw = {6'd52, 2'd2, 6'd36, 1'b0};  // BCS_DG   BDIG  JCOND BCS_DG
      6'd37:  uw = {6'd53, 2'd1, 6'd61, 1'b0};  // BCS_OU   BOUT  JMP   TAIL
      // rem
      6'd38:  uw = {6'd0 , 2'd0, 6'd0 , 1'b0};  // REM_A    UNPA  NEXT  -
      6'd39:  uw = {6'd33, 2'd1, 6'd2 , 1'b0};  // REM_AR   RENS  JMP   UNP_B
      6'd40:  uw = {6'd34, 2'd2, 6'd61, 1'b0};  // REM_SP   RSPC  JCOND TAIL
      6'd41:  uw = {6'd5 , 2'd0, 6'd0 , 1'b0};  // REM_ED   EXPD  NEXT  -
      6'd42:  uw = {6'd35, 2'd0, 6'd0 , 1'b0};  // REM_LN   RLEN  NEXT  -
      6'd43:  uw = {6'd36, 2'd0, 6'd0 , 1'b0};  // REM_LD   RLD   NEXT  -
      6'd44:  uw = {6'd31, 2'd2, 6'd44, 1'b0};  // REM_IT   DSTP  JCOND REM_IT
      6'd45:  uw = {6'd37, 2'd2, 6'd61, 1'b0};  // REM_CR   CORR  JCOND TAIL
      6'd46:  uw = {6'd11, 2'd1, 6'd15, 1'b0};  // REM_LZ   LZC   JMP   ADD_NM
      // sqrt
      6'd47:  uw = {6'd38, 2'd2, 6'd61, 1'b0};  // SQR_SP   SSPC  JCOND TAIL
      6'd48:  uw = {6'd39, 2'd0, 6'd0 , 1'b0};  // SQR_EX   SEXP  NEXT  -
      6'd49:  uw = {6'd40, 2'd0, 6'd0 , 1'b0};  // SQR_LD   SLD   NEXT  -
      6'd50:  uw = {6'd41, 2'd2, 6'd50, 1'b0};  // SQR_IT   SSTP  JCOND SQR_IT
      6'd51:  uw = {6'd42, 2'd1, 6'd14, 1'b0};  // SQR_RS   SRES  JMP   ADD_LZ
      // fint
      6'd52:  uw = {6'd43, 2'd2, 6'd61, 1'b0};  // FIN_SP   FSPC  JCOND TAIL
      6'd53:  uw = {6'd44, 2'd0, 6'd0 , 1'b0};  // FIN_AL   IALN  NEXT  -
      6'd54:  uw = {6'd45, 2'd1, 6'd14, 1'b0};  // FIN_RD   IRND  JMP   ADD_LZ
      // itof
      6'd55:  uw = {6'd46, 2'd1, 6'd14, 1'b0};  // I2F_LD   ILD   JMP   ADD_LZ
      // ftoi
      6'd56:  uw = {6'd47, 2'd2, 6'd61, 1'b0};  // CVI_SP   XSPC  JCOND TAIL
      6'd57:  uw = {6'd44, 2'd0, 6'd0 , 1'b0};  // CVI_AL   IALN  NEXT  -
      6'd58:  uw = {6'd45, 2'd2, 6'd60, 1'b0};  // CVI_RD   IRND  JCOND BCS_LD
      6'd59:  uw = {6'd48, 2'd1, 6'd61, 1'b0};  // FIX_FN   IFIN  JMP   TAIL
      6'd60:  uw = {6'd51, 2'd1, 6'd34, 1'b0};  // BCS_LD   BLD   JMP   DIV_IT
      // tail
      6'd61:  uw = {6'd16, 2'd0, 6'd0 , 1'b0};  // TAIL     PACK  NEXT  -
      6'd62:  uw = {6'd17, 2'd0, 6'd0 , 1'b1};  // TAIL_WB  WB    NEXT  -       end
      default: uw = {6'd54, 2'd0, 6'd0, 1'b1};  // unused: NOJOB, end
    endcase
  end

  always_comb begin
    unique case (next_kind)
      6'h00:   entry = UA_UNP_A;  // FADD
      6'h01:   entry = UA_UNP_A;  // FSUB
      6'h02:   entry = UA_UNP_A;  // FRVSUB
      6'h03:   entry = UA_UNP_A;  // FMUL
      6'h04:   entry = UA_UNP_A;  // FDIV
      6'h05:   entry = UA_UNP_A;  // FRDIV
      6'h06:   entry = UA_UNP_A;  // FPWR2
      6'h07:   entry = UA_UNP_B;  // FSQR
      6'h08:   entry = UA_UNP_A;  // FLD
      6'h09:   entry = UA_SGN_LD;  // FABS
      6'h0A:   entry = UA_SGN_LD;  // FNEG
      6'h0B:   entry = UA_SGN_LD;  // FCLR
      6'h0C:   entry = UA_UNP_B;  // FINT
      6'h0D:   entry = UA_UNP_A;  // FCP
      6'h0E:   entry = UA_UNP_A;  // FCPX
      6'h0F:   entry = UA_UNP_A;  // FCPZ
      6'h10:   entry = UA_UNP_A;  // FCPZX
      6'h11:   entry = UA_REM_A;  // FREM
      6'h12:   entry = UA_REM_A;  // FREMSTEP
      6'h20:   entry = UA_I2F_LD;  // ITOF
      6'h21:   entry = UA_UNP_B;  // FTOI
      6'h22:   entry = UA_BCL_LD;  // BCDLD
      6'h23:   entry = UA_UNP_B;  // BCDST
      default: entry = UA_TAIL;  // no routine: the tail
    endcase
  end

  always_comb begin
    unique case (kind)
      6'h00:   body = UA_ADD_SP;  // FADD
      6'h01:   body = UA_ADD_SP;  // FSUB
      6'h02:   body = UA_ADD_SP;  // FRVSUB
      6'h03:   body = UA_MUL_SP;  // FMUL
      6'h04:   body = UA_DIV_SP;  // FDIV
      6'h05:   body = UA_DIV_SP;  // FRDIV
      6'h06:   body = UA_MUL_SP;  // FPWR2
      6'h07:   body = UA_SQR_SP;  // FSQR
      6'h08:   body = UA_ADD_SP;  // FLD
      6'h09:   body = UA_SGN_LD;  // FABS
      6'h0A:   body = UA_SGN_LD;  // FNEG
      6'h0B:   body = UA_SGN_LD;  // FCLR
      6'h0C:   body = UA_FIN_SP;  // FINT
      6'h0D:   body = UA_CMP_SP;  // FCP
      6'h0E:   body = UA_CMP_SP;  // FCPX
      6'h0F:   body = UA_CMP_SP;  // FCPZ
      6'h10:   body = UA_CMP_SP;  // FCPZX
      6'h11:   body = UA_REM_SP;  // FREM
      6'h12:   body = UA_REM_SP;  // FREMSTEP
      6'h20:   body = UA_I2F_LD;  // ITOF
      6'h21:   body = UA_CVI_SP;  // FTOI
      6'h22:   body = UA_BCL_LD;  // BCDLD
      6'h23:   body = UA_CVI_SP;  // BCDST
      default: body = UA_TAIL;  // no routine: the tail
    endcase
  end

endmodule

`default_nettype wire
