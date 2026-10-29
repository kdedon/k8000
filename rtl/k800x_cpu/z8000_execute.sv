// z8000_execute -- register, immediate and memory operands through the ALU.
//
// The instruction is decoded from its words for as long as it runs. This
// unit says whether it runs it (`handles`); the machine-cycle program says
// when. The work lands on the program's last clocks: a byte or word op is
// one ALU pass on the last clock, a long op a low-word pass on the second
// last and a high-word pass on the last. Results are written at the end of
// the pass's clock.
//
// A memory operand (IR, DA, X, BA, BX, RA) has its address formed while
// its cycle is requested: port A reads the pointer, base or index in every
// clock but the pass's, and the address is latched when the cycle is taken.
// A displacement or index adds to the offset alone. A BX index comes from
// port B a clock ahead, so a store's request clock can read its data there. A
// read word goes to the operand latch at its T3 edge (a byte from the upper
// half at an even address, else the lower), and the pass uses it. A store
// gives its data when the write is taken; it has no pass.
//
// A read-modify-write (the same IR, DA or X operand read then written) has
// its pass in the read's T3 clock: the result goes to the write-data latch
// and the flags at that clock's end, and the write reuses the read's
// address. TSET writes all ones, so its write needs no latch.
//
// A long op's low pass keeps its C and Z for the high pass, which writes
// FCW once, with Z = Z_low & Z_high.
//
// Branches load the PC on the edge that opens the program's last clock, so
// the next IF1 is requested from it in the last; RET from the popped word
// as it is taken there. The target comes from the address words, port A,
// or the PC offset plus a doubled displacement on the address adder.
// DJNZ decrements in its internal operation's first clock into the
// write-data latch, and writes the count back as the PC is loaded.
//
// Stack cycles address the stack pointer register (R15, RR14 segmented,
// or a PUSH/POP's own pointer) with stack status. The pointer is read on
// port A while the cycle is requested; the adder forms the pushed address
// or the popped one + 2 (4 for a long), written back to the pointer's
// offset word when the cycle is taken. A long's second word goes to the
// first's address + 2. CALL pushes the PC offset, then segmented its
// segment word.
//
// A long memory operand is two word cycles, at the address and at the
// address + 2 (the segment takes no carry). The first read word is kept in
// a high-word latch. A long load writes its high word in the clock after
// the first read's T3 and its low word on the program's last clock. A long
// store gives the high register first.

module z8000_execute
  import z8000_ctrl_pkg::*, z8000_zbus_pkg::*;
#(
  parameter bit SEGMENTED = 0,  // Z8001/Z8003
  parameter bit VMPU = 0        // Z8003/Z8004
) (
  input  logic        clk,
  input  logic        reset_n,

  // the running instruction
  input  logic [11:0] w0,           // register nibbles and the low byte
  input  ctrl_word_t  ctrl_nx,      // the control word and w0 as of the next edge
  input  logic [11:0] w0_nx,
  input  logic [4:0]  alu_op,
  input  logic [1:0]  width,
  input  logic [4:0]  src2,
  input  logic [4:0]  count,
  input  logic [3:0]  dst,
  input  logic [1:0]  src1_nib,
  input  logic [1:0]  src2_nib,
  input  logic [1:0]  dst_nib,
  input  logic [15:0] w1,           // instruction words 1 and 2
  input  logic [15:0] w2,
  output logic        handles,
  input  logic        block_decr,
  input  logic        block_rept,
  output logic        blk_more,     // a repeated translate runs again
  input  logic [2:0]  fcw_op,
  input  logic [15:0] fcw_mask,
  input  logic        first,        // the IF1's T3 clock
  input  logic        last2,        // the program's second last clock
  input  logic        to_last,      // the next edge opens the last clock
  input  logic        last,         // the program's last clock
  input  logic        last2_nx,     // last2 and last as of the next edge
  input  logic        last_nx,

  // memory operand
  input  logic        seg_mode,     // segmented mode on a Z8001
  input  logic [6:0]  pc_seg,       // the PC's segment (0 on a Z8002)
  input  logic [15:0] pc_off,       // the PC offset, past the instruction's words
  input  logic        cyc_end,      // the next edge ends the bus cycle
  input  logic [22:0] ea_word,      // address from the address words
  input  logic        mem_take,     // the operand cycle is taken on this edge
  input  logic        int_take,     // an internal operation is taken on this edge
  input  logic        opnd_take,    // its read word is in on this edge
  input  logic [15:0] rdata,
  output logic [22:0] mem_addr,
  output logic [3:0]  mem_st,
  output logic        mem_byte,
  output logic [15:0] mem_wdata,

  // register file
  output logic [1:0]  rf_rwidth,
  output logic [3:0]  rf_rsel,
  input  logic [31:0] rf_rdata,
  output logic        rf_rbyte_b,
  output logic [3:0]  rf_rsel_b,
  input  logic [15:0] rf_rdata_b,
  output logic        rf_we,
  output logic [1:0]  rf_wwidth,
  output logic [3:0]  rf_wsel,
  output logic [15:0] rf_wdata,

  // PC load
  output logic        pc_we,
  output logic [22:0] pc_d,

  // flags
  input  logic        fcw_c,
  input  logic [2:0]  fcw_zsv,
  input  logic [10:0] fcw_lo,       // FCW bits 10:0
  input  logic        fcw_sn,       // S/N

  // FCW and control register loads
  output logic        fcw_we,
  output logic [15:0] fcw_d,
  output logic [2:0]  ctl_rsel,
  input  logic [15:0] ctl_rdata,
  output logic        ctl_we,
  output logic [2:0]  ctl_sel,
  output logic [15:0] ctl_wd,
  output logic        flags_we,
  output logic [15:0] flags,        // FCW bit positions
  output logic [15:0] flags_mask
);

  localparam logic [1:0] RF_BYTE = 2'd0;
  localparam logic [1:0] RF_WORD = 2'd1;
  localparam logic [1:0] RF_LONG = 2'd2;

  // ---- which instructions ---------------------------------------------------------

  // Decoded a clock ahead from the next control word and w0, so the
  // selects below start at flops.
  typedef struct packed {
    logic mem_read, mem_write, mem_rmw,
          op_on_a, mem_ir, mem_x, mem_ra, mem_ba, mem_bx, uni, br, br_ir, br_x, br_da,
          br_jr, br_dj, br_rel, br_call, br_ret, stk, stk_push, stk_long, stk_opnd,
          stk_imm, stk_pop_r, fop, tcc, dab, exts, sm, sm_byte, xr, xm, bcd, lea, ldctl,
          ctl_wr, ctl_fcw, ldps, iret, ps_ld, ldps_ir, ldps_x, chg_fcw, ldm, ldm_st, tr,
          tr_test, handles, is_long, is_byte, hi_first;
  } cls_t;
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic cls_t cls_of(input ctrl_word_t c, input logic [11:0] w);
    cls_t k;
    logic src_mem, dst_mem;
    unique case (c.src2)
      SRC_IR, SRC_DA, SRC_X, SRC_PCREL, SRC_BASED, SRC_BX: src_mem = 1'b1;
      default:                                             src_mem = 1'b0;
    endcase
    dst_mem = !(c.dst == DST_REG || c.dst == DST_NONE || c.dst == DST_FLAGS_ONLY);
    k.mem_read = src_mem && !dst_mem;
    k.mem_write = dst_mem && c.alu_op == OP_LD && (c.src2 == SRC_REG || c.src2 == SRC_IMM || c.src2 == SRC_IMM2 || c.src2 == SRC_ZERO);
    k.mem_rmw = src_mem && dst_mem && c.width != WIDTH_LONG;
    k.op_on_a = (k.mem_read && c.dst == DST_FLAGS_ONLY) || k.mem_rmw;
    k.mem_ir = k.mem_read ? c.src2 == SRC_IR : c.dst == DST_IR;
    k.mem_x = k.mem_read ? c.src2 == SRC_X : c.dst == DST_X;
    k.mem_ra = k.mem_read ? c.src2 == SRC_PCREL : c.dst == DST_PCREL;
    k.mem_ba = k.mem_read ? c.src2 == SRC_BASED : c.dst == DST_BASED;
    k.mem_bx = k.mem_read ? c.src2 == SRC_BX : c.dst == DST_BX;
    k.uni = c.valid && c.exec == CLS_UNIFIED && ((!src_mem && !dst_mem) || k.mem_read || k.mem_write || k.mem_rmw);
    k.br = c.valid && c.exec == CLS_BRANCH;
    k.br_ir = k.br && (c.br_mode == BRANCH_JP__IR || c.br_mode == BRANCH_CALL__IR);
    k.br_x = k.br && (c.br_mode == BRANCH_JP__X || c.br_mode == BRANCH_CALL__X);
    k.br_da = k.br && (c.br_mode == BRANCH_JP__DA || c.br_mode == BRANCH_CALL__DA);
    k.br_jr = k.br && c.br_mode == BRANCH_JR;
    k.br_dj = k.br && c.br_mode == BRANCH_DJNZ;
    k.br_rel = k.br_jr || k.br_dj || (k.br && c.br_mode == BRANCH_CALR12);
    k.br_call = k.br && (c.br_mode == BRANCH_CALL__DA || c.br_mode == BRANCH_CALL__X || c.br_mode == BRANCH_CALL__IR || c.br_mode == BRANCH_CALR12);
    k.br_ret = k.br && c.br_mode == BRANCH_RET;
    k.stk = c.valid && c.exec == CLS_STACK;
    k.stk_push = k.stk && (c.stk_mode == STACK_PUSH || c.stk_mode == STACK_PUSH_L || c.stk_mode == STACK_PUSH_SRC || c.stk_mode == STACK_PUSH_LSRC || c.stk_mode == STACK_PUSH_IMM);
    k.stk_long = k.stk && (c.stk_mode == STACK_PUSH_L || c.stk_mode == STACK_POP_L || c.stk_mode == STACK_PUSH_LSRC || c.stk_mode == STACK_POP_LDST);
    k.stk_opnd = k.stk && (c.stk_mode == STACK_PUSH_SRC || c.stk_mode == STACK_PUSH_LSRC || c.stk_mode == STACK_POP_DST || c.stk_mode == STACK_POP_LDST);
    k.stk_imm = k.stk && c.stk_mode == STACK_PUSH_IMM;
    k.stk_pop_r = k.stk && (c.stk_mode == STACK_POP || c.stk_mode == STACK_POP_L);
    k.fop = c.valid && c.exec == CLS_FCW_OP;
    k.tcc = c.valid && c.exec == CLS_TCC;
    k.dab = c.valid && c.exec == CLS_DAB;
    k.exts = c.valid && c.exec == CLS_EXTS;
    k.sm = k.fop || k.tcc || k.dab || k.exts;
    k.sm_byte = k.fop || k.dab || (k.tcc && c.width == WIDTH_BYTE);
    k.xr = c.valid && c.exec == CLS_EXCHANGE && !src_mem;
    k.xm = c.valid && c.exec == CLS_EXCHANGE && src_mem;
    k.bcd = c.valid && c.exec == CLS_BCDROTATE;
    k.lea = c.valid && c.exec == CLS_LEA;
    k.ldctl = c.valid && c.exec == CLS_LDCTL;
    k.ctl_wr = w[3];
    k.ctl_fcw = k.ldctl && k.ctl_wr && w[2:0] == 3'd2;
    k.ldps = c.valid && c.exec == CLS_LDPS;
    k.iret = c.valid && c.exec == CLS_IRET;
    k.ps_ld = k.ldps || k.iret;
    k.ldps_ir = k.ldps && c.src2 == SRC_IR;
    k.ldps_x = k.ldps && c.src2 == SRC_DA && w[7:4] != 4'd0;
    k.chg_fcw = k.ctl_fcw || k.ps_ld;
    k.ldm = c.valid && c.exec == CLS_LDM;
    k.ldm_st = k.ldm && c.io_write;
    k.tr = c.valid && c.exec == CLS_TRANSLATE;
    k.tr_test = k.tr && !c.io_write;
    k.handles = k.uni || k.br || k.stk || k.sm || k.xr || k.xm || k.bcd || k.lea || k.ldctl || k.ps_ld || k.ldm || k.tr;
    k.is_long = c.width == WIDTH_LONG;
    k.is_byte = c.width == WIDTH_BYTE || (k.br_dj && !w[7]);
    k.hi_first = k.is_long && k.mem_read && c.alu_op == OP_LD;
    return k;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  cls_t k_d, k_q;
  assign k_d = cls_of(ctrl_nx, w0_nx);
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) k_q <= '0;
    else          k_q <= k_d;
  end
  logic [1:0] mcnt_q;   // memory cycles taken so far

  // Reads: a memory source into a register or the flags. Stores: LD or CLR
  // to memory. TEST, BIT and CP-immediate take the operand on port A's side.
  logic mem_read, mem_write, mem_rmw, op_on_a;
  logic mem_ir, mem_x, mem_ra, mem_ba, mem_bx;
  assign mem_read = k_q.mem_read;
  assign mem_write = k_q.mem_write;
  assign mem_rmw = k_q.mem_rmw;
  assign op_on_a = k_q.op_on_a;
  assign mem_ir = k_q.mem_ir;
  assign mem_x = k_q.mem_x;
  assign mem_ra = k_q.mem_ra;
  assign mem_ba = k_q.mem_ba;
  assign mem_bx = k_q.mem_bx;

  logic uni;
  assign uni = k_q.uni;

  // Branches: the target's source and whether a stack cycle is next.
  logic cc_met, taken;
  logic br, br_ir, br_x, br_da, br_rel, br_call, br_ret, br_dj, br_jr;
  assign br = k_q.br;
  assign br_ir = k_q.br_ir;
  assign br_x = k_q.br_x;
  assign br_da = k_q.br_da;
  assign br_jr = k_q.br_jr;
  assign br_dj = k_q.br_dj;
  assign br_rel = k_q.br_rel;
  assign br_call = k_q.br_call;
  assign br_ret = k_q.br_ret;

  // PUSH/POP: pointer w0[7:4], register or operand pointer w0[3:0].
  logic stk, stk_push, stk_long, stk_opnd, stk_imm, stk_pop_r;
  assign stk = k_q.stk;
  assign stk_push = k_q.stk_push;
  assign stk_long = k_q.stk_long;
  assign stk_opnd = k_q.stk_opnd;
  assign stk_imm = k_q.stk_imm;
  assign stk_pop_r = k_q.stk_pop_r;

  // Register-only classes: they read and write in the program's last clocks.
  logic fop, tcc, dab, exts, sm, sm_byte;
  assign fop = k_q.fop;
  assign tcc = k_q.tcc;
  assign dab = k_q.dab;
  assign exts = k_q.exts;
  assign sm = k_q.sm;
  assign sm_byte = k_q.sm_byte;

  // EX and RLDB/RRDB swap through the write-data latch: register forms in
  // their last two clocks, memory EX in its read's tail.
  logic xr, xm, bcd, xm_pass;
  assign xr = k_q.xr;
  assign xm = k_q.xm;
  assign bcd = k_q.bcd;

  // LDA/LDAR write the operand address path's result.
  logic lea;
  assign lea = k_q.lea;

  // LDCTL: w0[3] set loads the control register w0[2:0] from w0[7:4].
  logic ldctl, ctl_wr, ctl_fcw;
  assign ldctl = k_q.ldctl;
  assign ctl_wr = k_q.ctl_wr;
  assign ctl_fcw = k_q.ctl_fcw;

  // LDPS reads FCW, then PC (segmented: from the address + 2, the PC
  // segment word, then its offset); IRET pops the identifier first.
  // LDPS's pointer or index is w0[7:4]; the X index comes from port B,
  // + 2 when segmented, ahead of the first read.
  logic ldps, iret, ps_ld, ldps_ir, ldps_x, ldps_idx, chg_fcw, sw_clk;
  assign ldps = k_q.ldps;
  assign iret = k_q.iret;
  assign ps_ld = k_q.ps_ld;
  assign ldps_ir = k_q.ldps_ir;
  assign ldps_x = k_q.ldps_x;
  assign ldps_idx = ldps_x && mcnt_q == 2'd0;
  assign chg_fcw = k_q.chg_fcw;

  // LDM moves registers w1[11:8] on (modulo 16) at the address, + 2 per
  // word, with data status. A store's register is read on port B as its
  // cycle is requested; a load's word is written the clock after its T3.
  logic       ldm, ldm_st, ldm_we_q;
  logic [3:0] ldm_k_q, ldm_wk_q;
  assign ldm = k_q.ldm;
  assign ldm_st = k_q.ldm_st;
  assign sw_clk   = iret ? to_last : last2;

  // Translate: per byte, read @Rd (pair RRd segmented, d = w1[7:4]), read
  // the table byte at Rs + that byte, then write it back to @Rd (TR) or
  // take an internal operation (TRT). Rd steps by one in the table read's
  // last tail clock; in the next the count R(w1[11:8]) decrements and V
  // (and Z) load; in the one after TRT puts the byte in RH1. A repeat runs
  // again while the count is not zero (TRT: and the byte is).
  logic       tr, tr_test, tab_take, tr_a, tr_b, tr_h, blk_q, tw_zero_q;
  logic [1:0] ec_q;     // the element's next cycle: dst read, table read, write
  logic [2:0] ph_q;     // clocks since the table read's word is in
  logic [3:0] tr_d, tr_off;
  logic [15:0] tr_val;
  assign tr = k_q.tr;
  assign tr_test = k_q.tr_test;
  assign tab_take = tr && opnd_take && ec_q == (tr_test ? 2'd0 : 2'd2);
  assign tr_a     = tr && ph_q == 3'd4;
  assign tr_b     = tr && ph_q == 3'd5;
  assign tr_h     = tr && tr_test && ph_q == 3'd1;  // RH1 <- the table byte
  assign tr_d     = w0[7:4];
  assign tr_off   = seg_mode ? {tr_d[3:1], 1'b1} : tr_d;
  assign tr_val   = rf_rdata[15:0] + ((tr_a && !block_decr) ? 16'h0001 : 16'hFFFF);
  assign blk_more = blk_q;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ec_q      <= 2'd0;
      ph_q      <= 3'd0;
      blk_q     <= 1'b0;
      tw_zero_q <= 1'b0;
    end else begin
      if (first)                ec_q <= 2'd0;
      else if (tr && mem_take)  ec_q <= ec_q == (tr_test ? 2'd1 : 2'd2) ? 2'd0 : ec_q + 2'd1;
      if (tab_take)             ph_q <= 3'd1;
      else if (ph_q != 3'd0)    ph_q <= ph_q == 3'd6 ? 3'd0 : ph_q + 3'd1;
      if (tab_take)             tw_zero_q <= rdata == 16'h0000;
      if (tr_b)                 blk_q <= tr_val != 16'h0000 && (!tr_test || opnd_q[7:0] == 8'h00);
    end
  end

  assign handles = k_q.handles;

  // A swap writes w0[7:4] and holds the other result for w0[3:0]. RLDB
  // moves digits left through the link w0[3:0], RRDB right.
  logic [7:0]  bx, by;
  logic [15:0] sw_val, sw_hold;
  assign bx = rf_rdata[7:0];
  assign by = rf_rdata_b[7:0];
  always_comb begin
    if (xr)                 {sw_val, sw_hold} = {rf_rdata_b, rf_rdata[15:0]};
    else if (alu_op == OP_RL) {sw_val, sw_hold} = {8'h00, bx[3:0], by[3:0], 8'h00, by[7:4], bx[7:4]};
    else                    {sw_val, sw_hold} = {8'h00, by[3:0], bx[7:4], 8'h00, by[7:4], bx[3:0]};
  end

  // ---- passes ---------------------------------------------------------------------------
  logic is_long, is_byte, pass_lo, pass;
  logic high;      // the second pass of a long op
  logic upper;     // this pass works on the high word
  logic hi_first;  // a long load
  logic ld_hi_q;   // a long load's high-word pass: the clock after its first read's T3
  logic nxt2_q;    // a long's first cycle is taken; the second comes next
  logic rmw_pass;  // a read-modify-write's pass: its read's T3 clock
  assign is_long = k_q.is_long;
  assign is_byte = k_q.is_byte;
  assign hi_first = k_q.hi_first;
  // A unified op's register pass: a long's low pass on the second last
  // clock (a long load's on the last), else the last.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) pass_lo <= 1'b0;
    else          pass_lo <= k_d.uni && !k_d.mem_write && !k_d.mem_rmw &&
                             (k_d.hi_first ? last_nx : k_d.is_long ? last2_nx : last_nx);
  end
  assign pass    = pass_lo || high || rmw_pass || ld_hi_q;
  assign upper   = high || ld_hi_q;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      rmw_pass <= 1'b0;
      xm_pass  <= 1'b0;
      ld_hi_q  <= 1'b0;
    end else begin
      rmw_pass <= uni && mem_rmw && opnd_take;
      xm_pass  <= xm && opnd_take;
      ld_hi_q  <= uni && hi_first && opnd_take && nxt2_q;
    end
  end

  // The high pass is the clock after the low pass.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) high <= 1'b0;
    else          high <= pass_lo && is_long && !hi_first;
  end

  // ---- branch and stack sequencing -------------------------------------------------
  // Memory cycles taken so far pick the stack cycles: a PUSH's operand reads
  // come first, a POP's operand writes last; CALL pushes and RET pops one
  // word (two segmented).
  logic       stk_cyc, stk_first, sp_seg2;
  assign sp_seg2 = seg_mode ? !mcnt_q[1] : mcnt_q == 2'd0;
  always_comb begin
    stk_cyc = 1'b0;
    if (br_call || br_ret)
      stk_cyc = sp_seg2;
    else if ((stk && !stk_opnd) || iret)
      stk_cyc = 1'b1;
    else if (stk)
      stk_cyc = stk_push ^ !(stk_long ? mcnt_q[1] : mcnt_q[0]);
  end
  assign stk_first = stk_cyc && !nxt2_q;

  logic dj_pass, nz_q, pl_hi_q;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      mcnt_q  <= 2'd0;
      dj_pass <= 1'b0;
      pl_hi_q <= 1'b0;
    end else begin
      if (first)         mcnt_q <= 2'd0;
      else if (mem_take) mcnt_q <= mcnt_q + 2'd1;
      dj_pass <= int_take && br_dj;
      pl_hi_q <= stk_pop_r && stk_long && opnd_take && nxt2_q;
    end
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
  // Outside the pass, port A reads the pointer or base (a long pair when
  // segmented) or the index.
  logic       ptr_read, seg_ir, idx_read;
  logic [3:0] ptr;
  logic [4:0] bsel;
  logic [15:0] opnd_q, opnd_hi_q, opnd_w;
  logic        ea0_q;
  assign ptr_read = (mem_read || mem_write || mem_rmw || stk_opnd) && !pass;
  assign seg_ir   = seg_mode && (mem_ir || mem_ba || mem_bx);
  assign idx_read = mem_bx && !nxt2_q && !(mem_write && cyc_end);
  assign ptr      = (xm || ldps || ldm) ? w0[7:4] : mem_write ? rd : rb;

  // The stack pointer: R15 (RR14) for a call or return, else w0[7:4].
  logic [3:0] sp, sp_off;
  assign sp     = (br || iret) ? 4'd15 : w0[7:4];
  assign sp_off = seg_mode ? {sp[3:1], 1'b1} : sp;

  // Port A: the stack pointer while a stack cycle is requested; DJNZ's
  // counter; a JP or CALL target register or index; else as above.
  always_comb begin
    // IRET's stack read gives R15 as its swap clock opens.
    if (chg_fcw && (last || (last2 && !iret))) begin
      rf_rwidth = RF_WORD;
      rf_rsel   = {3'b111, !last};
    end else if (tr) begin
      // The count, the table base, else Rd (the offset steps in tr_a).
      rf_rwidth = (tr_b || !seg_mode) ? RF_WORD : RF_LONG;
      rf_rsel   = tr_b ? w1[11:8] :
                  {ec_q == 2'd1 ? w1[7:5] : tr_d[3:1], seg_mode ? 1'b0 : (ec_q == 2'd1 ? w1[4] : tr_d[0])};
    end else if (stk_first) begin
      rf_rwidth = seg_mode ? RF_LONG : RF_WORD;
      rf_rsel   = seg_mode ? {sp[3:1], 1'b0} : sp;
    end else if (br_dj) begin
      rf_rwidth = is_byte ? RF_BYTE : RF_WORD;
      rf_rsel   = w0[11:8];
    end else if (ldctl) begin
      rf_rwidth = RF_WORD;
      rf_rsel   = w0[7:4];
    end else if (sm) begin
      // EXTS reads the word holding the sign: Rd, R(d+1) or R(d+2).
      rf_rwidth = (sm_byte && !exts) ? RF_BYTE : RF_WORD;
      rf_rsel   = !exts ? w0[7:4] : width == WIDTH_BYTE ? w0[7:4] :
                  width == WIDTH_WORD ? {w0[7:5], 1'b1} : {w0[7:6], 2'b10};
    end else if (xr || bcd) begin
      rf_rwidth = (is_byte || bcd) ? RF_BYTE : RF_WORD;
      rf_rsel   = w0[7:4];
    end else if (br_ir || br_x) begin
      rf_rwidth = (br_ir && seg_mode) ? RF_LONG : RF_WORD;
      rf_rsel   = (br_ir && seg_mode) ? {w0[7:5], 1'b0} : w0[7:4];
    end else begin
      rf_rwidth = ptr_read ? (seg_ir ? RF_LONG : RF_WORD) : (is_byte ? RF_BYTE : RF_WORD);
      rf_rsel   = ptr_read ? ptr : is_long ? {ra[3:1], ~upper} : ra;
    end
  end
  assign rf_rbyte_b = (is_byte || bcd) && !idx_read;
  always_comb begin
    if (idx_read)       rf_rsel_b = w1[11:8];
    else if (ldctl || ldps) rf_rsel_b = w0[7:4];
    else if (ldm)       rf_rsel_b = w1[11:8] + ldm_k_q;
    else if (xr || xm || bcd) rf_rsel_b = w0[3:0];
    else if (stk_long)  rf_rsel_b = {rb[3:1], nxt2_q};
    else if (!is_long)  rf_rsel_b = rb;
    else if (mem_write) rf_rsel_b = {rb[3:1], nxt2_q};
    else                rf_rsel_b = {rb[3:1], ~upper};
  end
  assign opnd_w     = high ? opnd_hi_q : opnd_q;
  assign a          = op_on_a ? opnd_w : rf_rdata[15:0];
  assign bsel       = dj_pass ? SRC_ONE : op_on_a ? count : src2;

  // DAB takes the decimal-adjust and half-carry flags as b[1:0].

  // Address words are kept apart, so an immediate after them is word 1.
  always_comb begin
    unique case (bsel)
      SRC_REG:            b = rf_rdata_b;
      SRC_IR, SRC_DA, SRC_X, SRC_PCREL, SRC_BASED, SRC_BX: b = opnd_w;
      SRC_IMM, SRC_IMM2:  b = is_long ? (high ? w1 : w2) : (is_byte ? {8'h00, w1[15:8]} : w1);
      SRC_ONE:            b = 16'd1;
      SRC_TWO:            b = 16'd2;
      SRC_NIB3_BIT:       b = {12'h000, w0[3:0]};
      SRC_NIB3_CNT_PLUS1: b = {11'h000, {1'b0, w0[3:0]} + 5'd1};
      SRC_OP_LO_BYTE:     b = {8'h00, w0[7:0]};
      default:            b = 16'h0000;
    endcase
    if (dab) b = {14'h0000, fcw_lo[3:2]};
  end

  // A long's high pass carries from the low pass; CP's low pass runs as SUB.
  always_comb begin
    op  = dj_pass ? OP_SUB : dab ? OP_DAB : alu_op;
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

  // ---- memory operand -------------------------------------------------------------
  logic [6:0] ptr_seg;
  assign ptr_seg = seg_ir ? rf_rdata[30:24] : pc_seg;

  // A read-modify-write's write reuses its read's address.
  logic [22:0] addr_q;
  logic        wr_next_q;   // the read is in; the write comes next
  logic [15:0] idx_q, off_a, off_b, off_sum, sp_step, disp;
  logic [6:0]  sp_seg;

  // A CALL through or indexed by R15 takes R15 from before its push.
  logic [15:0] sp0_q, tgt_off;
  logic        tgt_sp;
  assign tgt_sp  = br_call && (w0[7:4] == 4'd15 || (br_ir && seg_mode && w0[7:4] == 4'd14));
  assign tgt_off = tgt_sp ? sp0_q : rf_rdata[15:0];
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)                                   sp0_q <= 16'h0000;
    else if (br_call && stk_first && mcnt_q == 2'd0) sp0_q <= rf_rdata[15:0];
  end

  // Pushes step down, pops up; a long by 4. JR's displacement adds, CALR's
  // and DJNZ's subtract.
  always_comb begin
    if (br_call)                     sp_step = 16'hFFFE;
    else if (br_ret || iret)         sp_step = 16'd2;
    else if (stk_push)               sp_step = stk_long ? 16'hFFFC : 16'hFFFE;
    else                             sp_step = stk_long ? 16'd4 : 16'd2;
    if (br_jr)      disp = {{7{w0[7]}}, w0[7:0], 1'b0};
    else if (br_dj) disp = 16'd0 - {8'h00, w0[6:0], 1'b0};
    else            disp = 16'd0 - {{3{w0[11]}}, w0[11:0], 1'b0};
  end

  always_comb begin
    if (stk_first) begin
      off_a = rf_rdata[15:0];
      off_b = sp_step;
    end else if (br_rel) begin
      off_a = pc_off;
      off_b = disp;
    end else if (tr) begin
      off_a = rf_rdata[15:0];
      off_b = {8'h00, opnd_q[7:0]};
    end else if (ldps) begin
      off_a = ldps_ir ? rf_rdata[15:0] : ea_word[15:0];
      off_b = ldps_x ? idx_q : {14'd0, seg_mode, 1'b0};
    end else begin
      off_a = (mem_x || br_x) ? ea_word[15:0] : mem_ra ? pc_off : rf_rdata[15:0];
      off_b = (mem_x || br_x) ? tgt_off : mem_bx ? idx_q : w1;
    end
  end
  assign off_sum = off_a + off_b;
  assign sp_seg  = seg_mode ? rf_rdata[30:24] : pc_seg;

  always_comb begin
    if (tr)          mem_addr = {seg_mode ? rf_rdata[30:24] : pc_seg,
                                 ec_q == 2'd1 ? off_sum : rf_rdata[15:0]};
    else if (wr_next_q) mem_addr = addr_q;
    else if (nxt2_q || (ldps && mcnt_q != 2'd0) || (ldm && ldm_k_q != 4'd0))
                     mem_addr = {addr_q[22:16], addr_q[15:0] + 16'd2};
    else if (ldps)   mem_addr = {ldps_ir ? ptr_seg : ea_word[22:16], off_sum};
    else if (stk_first)
                     mem_addr = {sp_seg, (stk_push || br_call) ? off_sum : rf_rdata[15:0]};
    else if (mem_ir) mem_addr = {ptr_seg, rf_rdata[15:0]};
    else if (mem_x || mem_ra || mem_ba || mem_bx)
                     mem_addr = {mem_x ? ea_word[22:16] : ptr_seg, off_sum};
    else             mem_addr = ea_word;
  end

  // A pointer or base in R15 (RR14 segmented) addresses the stack; a
  // Z8003/Z8004 TSET reads with the bus-lock status.
  always_comb begin
    if (VMPU && mem_rmw && alu_op == OP_TSET && !wr_next_q)
      mem_st = ST_BUS_LOCK_DATA;
    else if (stk_cyc)
      mem_st = ST_STACK_MEM;
    else if (ldps || ldm || tr)
      mem_st = ST_DATA_MEM;
    else if ((mem_ir || mem_ba || mem_bx) && ptr[3:1] == 3'b111 && (seg_ir ? !ptr[0] : ptr[0]))
      mem_st = ST_STACK_MEM;
    else
      mem_st = ST_DATA_MEM;
  end
  // EXB reads its byte with a word cycle.
  assign mem_byte  = (is_byte && !(xm && !wr_next_q)) || tr;

  // A segment word's other bits are not part of the address.
  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{rf_rdata[31], rf_rdata[23:16]};
  // verilator lint_on UNUSEDSIGNAL
  logic [15:0] wdata_q, nfcw_q;
  logic [6:0]  pcs_q;
  always_comb begin
    if (br_call)      mem_wdata = mcnt_q[0] ? {1'b1, pc_seg, 8'h00} : pc_off;
    else if (stk_opnd) mem_wdata = (stk_long && !nxt2_q) ? opnd_hi_q : opnd_q;
    else if (stk_imm) mem_wdata = w1;
    else if (stk)     mem_wdata = (stk_first && rf_rsel_b == sp_off) ? off_sum : rf_rdata_b;
    else if (xm)      mem_wdata = wdata_q;
    else if (ldm)     mem_wdata = rf_rdata_b;
    else if (tr)      mem_wdata = {opnd_q[7:0], opnd_q[7:0]};
    else if (mem_rmw) mem_wdata = (alu_op == OP_TSET) ? 16'hFFFF : wdata_q;
    else if (is_byte) mem_wdata = {b[7:0], b[7:0]};
    else              mem_wdata = b;
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ea0_q     <= 1'b0;
      opnd_q    <= 16'h0000;
      addr_q    <= 23'd0;
      wr_next_q <= 1'b0;
      wdata_q   <= 16'h0000;
      opnd_hi_q <= 16'h0000;
      nxt2_q    <= 1'b0;
      idx_q     <= 16'h0000;
      nfcw_q    <= 16'h0000;
      pcs_q     <= 7'd0;
      ldm_k_q   <= 4'd0;
      ldm_wk_q  <= 4'd0;
      ldm_we_q  <= 1'b0;
    end else begin
      if (first)                 ldm_k_q <= 4'd0;
      else if (ldm && mem_take)  ldm_k_q <= ldm_k_q + 4'd1;
      if (first)                 ldm_wk_q <= 4'd0;
      else if (ldm_we_q)         ldm_wk_q <= ldm_wk_q + 4'd1;
      ldm_we_q <= ldm && !ldm_st && opnd_take;
      if (idx_read) idx_q <= rf_rdata_b;
      if (ldps_idx) idx_q <= rf_rdata_b + {14'd0, seg_mode, 1'b0};
      if (opnd_take && mcnt_q == (iret ? 2'd2 : 2'd1)) nfcw_q <= rdata;
      if (opnd_take && mcnt_q == (iret ? 2'd3 : 2'd2)) pcs_q  <= rdata[14:8];
      if (mem_take) nxt2_q <= ((uni && is_long) || stk_long) && !nxt2_q;
      if (opnd_take && nxt2_q) opnd_hi_q <= rdata;
      if (mem_take) begin
        ea0_q  <= mem_addr[0];
        addr_q <= mem_addr;
      end
      if (mem_take)                             wr_next_q <= 1'b0;
      else if ((uni && mem_rmw || xm) && opnd_take) wr_next_q <= 1'b1;
      if (rmw_pass || dj_pass) wdata_q <= is_byte ? {value[7:0], value[7:0]} : value;
      if (xm_pass)             wdata_q <= is_byte ? {rf_rdata_b[7:0], rf_rdata_b[7:0]} : rf_rdata_b;
      if ((xr || bcd) && last2) wdata_q <= sw_hold;
      if (opnd_take) opnd_q <= (is_byte || tr) ? {8'h00, ea0_q ? rdata[7:0] : rdata[15:8]} : rdata;
    end
  end

  logic pop_we, sp_we_q;

  // LDCTL FCW,Rs loads the FCW in the second last clock, so the next
  // fetch has the new N/S. A change of S/N swaps R15 with the NSP offset
  // there, and in the last clock R14 with the NSP segment (Z8001).
  // LDPS and IRET do the same from the read FCW word as the next edge
  // opens the last clock.
  logic        sw15, sw14, sw14_q, ctl_rf_we;
  logic [15:0] nfcw;
  // LDCTL FCW loads bits 15:11 and 7:2; the rest are reserved.
  assign nfcw = ctl_fcw ? {rf_rdata_b[15:11], fcw_lo[10:8], rf_rdata_b[7:2], fcw_lo[1:0]} : nfcw_q;
  assign sw15 = chg_fcw && sw_clk && (nfcw[14] ^ fcw_sn);
  assign sw14 = sw14_q && last;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) sw14_q <= 1'b0;
    else          sw14_q <= SEGMENTED && sw15;
  end
  assign ctl_rf_we = sw15 || sw14 || (ldctl && !ctl_wr && last);
  assign ctl_rsel  = sw15 ? 3'd7 : sw14 ? 3'd6 : w0[2:0];
  assign ctl_we    = sw15 || sw14 || (ldctl && ctl_wr && !ctl_fcw && last);
  assign ctl_sel   = ctl_rsel;
  assign ctl_wd    = rf_rdata[15:0];
  assign fcw_we    = chg_fcw && sw_clk;
  assign fcw_d     = {SEGMENTED && nfcw[15], nfcw[14:0]};

  // synthesis translate_off
  // The write data latch loads at the end of the read's T3; a write taken
  // on that same edge would send the old latch. A long register-result op
  // other than a load must end on its high pass. Either fails the vector.
  // Read by the testbench.
  // verilator lint_off UNUSEDSIGNAL
  logic check_q = 1'b0;
  // verilator lint_on UNUSEDSIGNAL
  always_ff @(posedge clk) begin
    if (rmw_pass && mem_take && alu_op != OP_TSET) begin
      $display("%%Error: %m: read-modify-write read has no tail");
      check_q <= 1'b1;
    end
    if (uni && is_long && !hi_first && !mem_write && !mem_rmw && last && !high) begin
      $display("%%Error: %m: long op ends without its high pass");
      check_q <= 1'b1;
    end
    if (sp_we_q && (pop_we || (br_dj && to_last) || ctl_rf_we || ldm_we_q)) begin
      $display("%%Error: %m: delayed stack pointer write dropped");
      check_q <= 1'b1;
    end
  end
  // synthesis translate_on

  // ---- results ----------------------------------------------------------------------
  // The stack pointer's offset word is written the clock after a stack
  // cycle is taken (a long's first), as the next instruction may
  // already be decoding; its next reader is the next stack
  // cycle's request, at least a cycle later. A POP's register is written at
  // the program's end (a POPL's high word as its first read's word is in);
  // DJNZ's counter with the PC.
  // TCC sets bit 0 when its condition holds; LDCTLB stores the FLAGS byte;
  // EXTS writes the sign (EXTSL's two words in the last two clocks).
  logic        sm_we, ex_sign;
  logic [15:0] sm_val;
  assign ex_sign = width == WIDTH_BYTE ? rf_rdata[7] : rf_rdata[15];
  always_comb begin
    sm_we  = last && (dab || (tcc && cc_met) || (fop && fcw_op == FCW_STORE_LO) ||
                      exts) || (exts && is_long && last2);
    sm_val = value;
    if (tcc)       sm_val = rf_rdata[15:0] | 16'h0001;
    else if (fop)  sm_val = {8'h00, fcw_lo[7:2], 2'b00};
    else if (exts) sm_val = width == WIDTH_BYTE ? {{8{ex_sign}}, rf_rdata[7:0]} : {16{ex_sign}};
  end

  logic [15:0] sp_d_q;
  logic [3:0]  sp_sel_q;
  assign pop_we = stk_pop_r && (last || pl_hi_q);

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      sp_we_q <= 1'b0;
      sp_d_q  <= 16'h0000;
      sp_sel_q <= 4'd0;
    end else begin
      sp_we_q <= mem_take && stk_first;
      if (mem_take && stk_first) begin
        sp_d_q   <= off_sum;
        sp_sel_q <= sp_off;
      end
    end
  end

  always_comb begin
    rf_we     = pass && dst == DST_REG;
    rf_wwidth = is_byte ? RF_BYTE : RF_WORD;
    rf_wsel   = is_long ? {rd[3:1], ~upper} : rd;
    rf_wdata  = value;
    if (pop_we) begin
      rf_we     = 1'b1;
      rf_wwidth = RF_WORD;
      rf_wsel   = stk_long ? {rd[3:1], !pl_hi_q} : rd;
      rf_wdata  = opnd_q;
    end else if (sp_we_q) begin
      rf_we     = 1'b1;
      rf_wwidth = RF_WORD;
      rf_wsel   = sp_sel_q;
      rf_wdata  = sp_d_q;
    end else if ((xr || bcd) && (last2 || last)) begin
      rf_we     = 1'b1;
      rf_wwidth = (is_byte || bcd) ? RF_BYTE : RF_WORD;
      rf_wsel   = last ? w0[3:0] : w0[7:4];
      rf_wdata  = last ? wdata_q : sw_val;
    end else if (xm_pass) begin
      rf_we     = 1'b1;
      rf_wwidth = is_byte ? RF_BYTE : RF_WORD;
      rf_wsel   = w0[3:0];
      rf_wdata  = opnd_q;
    end else if (lea && (last || (seg_mode && last2))) begin
      // Segmented: the segment word, then the offset.
      rf_we     = 1'b1;
      rf_wwidth = RF_WORD;
      rf_wsel   = seg_mode ? {w0[3:1], last} : w0[3:0];
      rf_wdata  = (seg_mode && !last) ? {1'b0, mem_addr[22:16], 8'h00} : mem_addr[15:0];
    end else if (tr_a || tr_b || tr_h) begin
      rf_we     = 1'b1;
      rf_wwidth = tr_h ? RF_BYTE : RF_WORD;
      rf_wsel   = tr_a ? tr_off : tr_b ? w1[11:8] : 4'd1;
      rf_wdata  = tr_h ? opnd_q : tr_val;
    end else if (ldm_we_q) begin
      rf_we     = 1'b1;
      rf_wwidth = RF_WORD;
      rf_wsel   = w1[11:8] + ldm_wk_q;
      rf_wdata  = opnd_q;
    end else if (ctl_rf_we) begin
      rf_we     = 1'b1;
      rf_wwidth = RF_WORD;
      rf_wsel   = chg_fcw ? {3'b111, !last} : w0[7:4];
      rf_wdata  = ctl_rdata;
    end else if (sm_we) begin
      rf_we     = 1'b1;
      rf_wwidth = (sm_byte && !exts) ? RF_BYTE : RF_WORD;
      rf_wsel   = (exts && is_long) ? {w0[7:6], 1'b0, last} : w0[7:4];
      rf_wdata  = sm_val;
    end else if (br_dj && to_last) begin
      // Lowest priority: to_last is late.
      rf_we    = 1'b1;
      rf_wsel  = w0[11:8];
      rf_wdata = wdata_q;
    end
  end

  // ---- branch target ----------------------------------------------------------------
  z8000_cond u_cond (
    .cc  (br_jr ? w0[11:8] : w0[3:0]),
    .c   (fcw_c),
    .z   (fcw_zsv[2]),
    .s   (fcw_zsv[1]),
    .v   (fcw_zsv[0]),
    .met (cc_met)
  );

  always_comb begin
    if (br_call)    taken = 1'b1;
    else if (br_dj) taken = nz_q;
    else            taken = cc_met;
    if (ps_ld)      pc_d = {seg_mode ? pcs_q : pc_seg, opnd_take ? rdata : opnd_q};
    else if (br_ret) pc_d = {seg_mode ? opnd_q[14:8] : pc_seg, rdata};
    else if (br_da) pc_d = ea_word;
    else if (br_ir) pc_d = {sp_seg, tgt_off};
    else if (br_x)  pc_d = {ea_word[22:16], off_sum};
    else            pc_d = {pc_seg, off_sum};
  end
  assign pc_we = ((br && taken) || ps_ld) && to_last;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)     nz_q <= 1'b0;
    else if (dj_pass) nz_q <= is_byte ? value[7:0] != 8'h00 : value != 16'h0000;
  end

  always_comb begin
    flags_we   = (pass_lo && !is_long) || high || rmw_pass || (dab && last) ||
                 (fop && last && fcw_op != FCW_STORE_LO);
    flags      = alu_flags;
    flags_mask = alu_mask;
    if (high) flags[6] = alu_flags[6] & z_lo_q;
    if (bcd) begin
      flags_we   = last;
      flags      = {9'h000, wdata_q[7:0] == 8'h00, wdata_q[7], 5'h00};
      flags_mask = 16'h0060;
    end
    if (tr_b) begin
      flags_we   = 1'b1;
      flags      = {9'h000, tr_test ? opnd_q[7:0] == 8'h00 : tw_zero_q, 1'b0, tr_val == 16'h0000, 4'h0};
      flags_mask = (tr_test || !block_rept) ? 16'h0050 : 16'h0010;
    end
    if (fop) begin
      flags_mask = fcw_op == FCW_LOAD_LO ? 16'h00FC : fcw_mask;
      unique case (fcw_op)
        FCW_SET:     flags = 16'hFFFF;
        FCW_TOGGLE:  flags = {8'h00, ~fcw_lo[7:0]};
        FCW_LOAD_LO: flags = {8'h00, rf_rdata[7:0]};
        default:     flags = 16'h0000;
      endcase
    end
  end

endmodule
