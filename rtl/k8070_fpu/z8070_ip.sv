// z8070_ip -- the Z8070's Interface Processor: bus snoop, transfers,
// control registers, /BSY and the interrupt daisy chain.
//
// /RESET is a level, taken on every master clock: SC, USER and FFLAGS
// clear except SC.ID, which follows the ID pins while /RESET is Low
// (spec p.542 note). PC1 and PC2 clear with them. The pins are idle during
// reset whatever the registers hold.
//
// Bus snoop (spec p.545; Jan83 TM templates). The strobes are seen on the
// master clock, as edges against their last level. {SN, AD} follows the
// bus while /AS is Low and holds at its rise, when status, R/W and N/S are
// latched. AD is taken on the CLK.I fall while /DS is Low; the cycle is
// acted on at the /DS rise:
//   1101 (IF1) with an extended-instruction first byte: no template is an
//     Invalid opcode; another EPU's ID is an Invalid EPU ID if its SC.EPUIDS
//     bit is set, else ignored; this EPU's ID, idle, keeps word 1 and the
//     address (PC1) and waits for word 2; busy, queues it (PC2) unless an
//     instruction is queued already.
//   1100 while waiting: the next one is word 2, decoded through the table;
//     no row, or a word count the operand cannot have, is an Invalid opcode.
//   1010, 1011 (memory) and 1110 (CPU) data cycles move the operand words,
//     one per cycle, first word first.
//   Every other cycle, refresh (0001) among them, passes unseen.
// /BUSACK Low at the /DS rise: another master's cycle, ignored.
//
// An instruction runs in one of three ways once word 2 is decoded:
//   inbound: the words are collected in a five-word buffer; the last one
//     completes FLDCTL (control register written) and the EPU<-FCW form
//     (FCW flags into the compare flags), or starts the Data Processor.
//   outbound: FLDCTL and FLDCTLB copy their register into the buffer at
//     once and source it; every other form starts the Data Processor and
//     sources the words of its held result.
//   none: the flag, trap and mode list instructions change FFLAGS or USER
//     at the word 2 /DS rise; the rest start the Data Processor.
// The last word, or the Data Processor's done, returns the IP to idle.
//
// Queue (spec p.535): one instruction, its word 2 and operand words taken
// while the executing one runs. It starts on the first CLK.I rise with the
// IP idle and the Data Processor done, in that master clock (PC1 takes
// PC2); a Data Processor operation gets its start the next master clock.
// An arithmetic trap flushes it, complete or in transfer (p.535, p.558).
// /ABORT, a level, drops the executing and the queued instruction before
// the cycle is seen; an operation already running finishes unseen.
//
// Data Processor hand-over, with no added clock: start in the /DS rise's
// master clock (a CLK.D rise in it is the first clock); at done, F[Fd]
// takes the result (not for the compares or outbound forms but FREMSTEP),
// FFLAGS folds the flags (not for FLDNF), FOP1/FOP2 take the input operand
// and default result when a flag is set, and an enabled trap requests
// (SC.IR 00). The RAM's one write port takes F[Fd] in the done clock,
// FOP1 the next (the read register holds the operand through done) and
// FOP2 once the Data Processor is not reading. The operand bus is F
// through the RAM's registered read port, addressed a master clock ahead,
// or the bus operand (row 10 keeps it once a queued instruction's words
// are due in the buffer). Single
// and double operands and results move field by field: a subnormal goes
// in unnormalized (the Data Processor's unpack normalizes it) and comes
// out in its denormalized form.
//
// Drive (spec p.546): a memory write word from the /AS rise to the /DS
// rise, a 1110 read word while /DS is Low; never with /BUSACK Low. Byte
// forms put the byte on AD7-0 and 00 on AD15-8 (assumed).
//
// SC is privileged: an FLDCTL SC write whose last transfer has N/S High
// (Normal mode) is dropped and raises Privilege violation (p.534).
//
// /BSY (p.535, p.542; patent US 4,648,034 FIG. 7): No Overlap, Low while
// the Data Processor runs; Intermediate, Low while the queued instruction
// and its operand words are complete. In both modes a store holds it Low
// from its word 2 until its word is ready, the store wait (assumed: the
// board takes /BSY to /WAIT as well).
//
// Interrupt request: an Invalid opcode, Invalid EPU ID or Privilege
// violation sets SC.IR and SC.IP and requests; /INT is Low while
// requesting and SC.MIE is 1.
//
// Acknowledge (spec p.534 SC, p.542 IEO): a cycle with the status SC.INTACK
// selects (0X 0101, 10 0110, 11 0111). While requesting with IEI High, the
// vector (SC 7:0, shifted left by SV) is driven on AD7-0 while /DS is Low
// unless NV is set; the /DS rise sets IUS and clears IP and the request.
// IEO is High only if IEI is High, no Z8070 interrupt is under service and,
// from the /AS rise to the /DS rise of an acknowledge, none is requested;
// DLC holds it Low.
//
// Harness contract: the replay bench reads and pokes sc_q, user_q,
// fflags_q, pc1_q and pc2_q by name.

`default_nettype none

module z8070_ip
  import z8070_enc_pkg::*;
(
  input  logic        clk,
  input  logic        clki_rise,
  input  logic        clki_fall,
  input  logic        reset_n,

  input  logic [15:0] ad_in,
  output logic [15:0] ad_out,
  output logic        ad_drive,
  input  logic        as_n,
  input  logic        ds_n,
  input  logic        r_w,
  input  logic        b_w,
  input  logic        n_s,
  input  logic [3:0]  st,
  input  logic [6:0]  sn,
  input  logic        busack_n,
  input  logic        abort_n,

  output logic        bsy_n,
  output logic        int_n,
  input  logic        iei,
  output logic        ieo,

  input  logic [1:0]  id,
  input  logic [1:0]  opt,

  input  logic        dp_busy,
  output logic        dp_start,   // one master clock: hand the plan over
  output logic [5:0]  dp_kind,
  output logic [1:0]  dp_prec,
  output logic [1:0]  dp_rm,
  output logic [79:0] dp_opnd,
  input  logic        dp_opnd_src,
  input  logic        dp_opnd_rd,
  input  logic        dp_done,    // one master clock: the result is ready
  input  logic [79:0] dp_res,
  input  logic [7:0]  dp_flags,
  input  logic [2:0]  dp_reason,
  input  logic        dp_rup,
  input  logic [5:0]  dp_cmp,
  output logic        dp_out,

  // F0-F7 in rows 0-7, FOP1 and FOP2 in rows 8 and 9
  output logic        f_we,
  output logic [3:0]  f_waddr,
  output logic [79:0] f_wdata,
  output logic [3:0]  f_raddr,
  output logic        f_re,
  input  logic [79:0] f_rdata
);

  localparam int SC_SV  = 9;
  localparam int SC_NV  = 11;
  localparam int SC_DLC = 12;
  localparam int SC_IUS = 13;
  localparam int SC_IP  = 14;
  localparam int SC_MIE = 15;
  localparam int SC_INTACK = 16; // bits 17:16
  localparam int SC_OVRLP = 18;  // bits 19:18
  localparam int SC_U   = 23;
  localparam int SC_IR  = 24;    // bits 25:24
  localparam int SC_ID  = 26;    // bits 27:26
  localparam int SC_EPUIDS = 28; // bits 31:28

  localparam int FF_CMP = 18;    // FFLAGS compare flags FH..FC, bits 23:18
  localparam int FF_FOPE = 24;   // FOP2, FOP1 exponent bits 14:13, bits 27:24
  localparam int FF_R   = 28;    // rounded up
  localparam int FF_RSN = 29;    // invalid reason, bits 31:29
  localparam int US_TRAP = 8;    // USER trap enables, bits 15:8

  localparam logic [1:0] OVRLP_INTERMEDIATE = 2'b10;

  localparam logic [1:0] IR_ARITH         = 2'd0;
  localparam logic [1:0] IR_INVALID_OP    = 2'd1;
  localparam logic [1:0] IR_INVALID_EPUID = 2'd2;
  localparam logic [1:0] IR_PRIVILEGE     = 2'd3;

  localparam logic [3:0] ST_DMEM = 4'hA;  // EPU memory data
  localparam logic [3:0] ST_SMEM = 4'hB;  // EPU memory stack
  localparam logic [3:0] ST_PROG = 4'hC;  // program space: word 2
  localparam logic [3:0] ST_IF1  = 4'hD;  // first instruction word
  localparam logic [3:0] ST_EPUX = 4'hE;  // CPU-EPU transfer

  // FLDCTL selects (the CP/M-8000 assembler and emulator).
  localparam logic [3:0] CTL_SC     = 4'd0;
  localparam logic [3:0] CTL_PC1    = 4'd1;
  localparam logic [3:0] CTL_PC2    = 4'd2;
  localparam logic [3:0] CTL_FFLAGS = 4'd4;
  localparam logic [3:0] CTL_USER   = 4'd5;
  localparam logic [3:0] CTL_FOP1   = 4'd6;
  localparam logic [3:0] CTL_FOP2   = 4'd7;

  // FCW flag bits on AD7-0.
  localparam logic [7:0] FCW_C = 8'h80;
  localparam logic [7:0] FCW_Z = 8'h40;
  localparam logic [7:0] FCW_S = 8'h20;
  localparam logic [7:0] FCW_V = 8'h10;

  // Sticky flag bits (FFLAGS 7:0).
  localparam int FL_INV = 0;
  localparam int FL_FOV = 1;
  localparam int FL_UN  = 2;
  localparam int FL_DZ  = 3;
  localparam int FL_INX = 4;
  localparam int FL_NAN = 6;
  localparam int FL_IX  = 7;

  typedef enum logic [2:0] {
    IP_IDLE    = 3'd0,
    IP_WORD2   = 3'd1,   // ID matched: the next 1100 is word 2
    IP_OPERAND = 3'd2,   // taking the operand words
    IP_DPWAIT  = 3'd3,   // the Data Processor runs
    IP_RESULT  = 3'd4    // sourcing the result words
  } ip_e;

  // Justification: (reg-a) architectural registers.
  logic [31:0] sc_q, sc_d;
  logic [31:0] user_q, user_d;
  logic [31:0] fflags_q, fflags_d;
  logic [31:0] pc1_q;
  logic [31:0] pc2_q;

  // ---- strobes ---------------------------------------------------------
  // Justification: (reg-a) last strobe levels, for the edges.
  logic as_q, ds_q;
  logic as_rise, ds_rise;

  always_ff @(posedge clk) begin
    as_q <= as_n;
    ds_q <= ds_n;
  end

  assign as_rise = as_n & ~as_q;
  assign ds_rise = ds_n & ~ds_q;

  // Justification: (reg-a) the cycle's address, status and controls, held
  // from the /AS rise to the next /AS.
  logic [22:0] cyc_addr_q;   // {SN6-0, AD15-0}
  logic [3:0]  cyc_st_q;
  logic        cyc_write_q;
  logic        cyc_ns_q;

  always_ff @(posedge clk) begin
    if (!as_n) cyc_addr_q <= {sn, ad_in};
  end

  always_ff @(posedge clk) begin
    if (as_rise) begin
      cyc_st_q    <= st;
      cyc_write_q <= ~r_w;
      cyc_ns_q    <= n_s;
    end
  end

  // Justification: (reg-a) /AS rise to /DS rise: the store drive window.
  logic cyc_open_q;

  always_ff @(posedge clk) begin
    if (!reset_n)     cyc_open_q <= 1'b0;
    else if (ds_rise) cyc_open_q <= 1'b0;
    else if (as_rise) cyc_open_q <= 1'b1;
  end

  // Which way the latched cycle moves a word, as seen by the EPU.
  logic cyc_mem, cyc_epu, cyc_in, cyc_out;

  assign cyc_mem = (cyc_st_q == ST_DMEM) || (cyc_st_q == ST_SMEM);
  assign cyc_epu = cyc_st_q == ST_EPUX;
  assign cyc_in  = (cyc_mem & ~cyc_write_q) | (cyc_epu & cyc_write_q);
  assign cyc_out = (cyc_mem & cyc_write_q) | (cyc_epu & ~cyc_write_q);

  // The acknowledge this EPU answers, and whether the cycle is one.
  logic [3:0] ack_st;
  // Justification: (reg-a) the interrupt request, until acknowledged.
  logic       int_req_q, int_req_d;
  logic       int_req, ack_hit, in_ack, ack_take;

  assign ack_st   = sc_q[SC_INTACK + 1] ? {3'b011, sc_q[SC_INTACK]} : 4'b0101;
  assign int_req  = int_req_q & sc_q[SC_MIE];
  assign ack_hit  = int_req & iei & (cyc_st_q == ack_st);
  assign in_ack   = ack_hit & cyc_open_q;
  assign ack_take = ack_hit & ds_rise & busack_n;

  // Justification: (reg-a) the data word, taken on the CLK.I fall in /DS.
  logic [15:0] ds_data_q, ds_data_d;

  assign ds_data_d = (clki_fall && !ds_n) ? ad_in : ds_data_q;

  always_ff @(posedge clk) begin
    ds_data_q <= ds_data_d;
  end

  // ---- decode ----------------------------------------------------------
  // The decode reads the latch's next value and is registered: the
  // register then holds the latch's decode, off the start path, and the
  // unregistered value addresses the F read a start on a CLK.D rise needs
  // one clock after the data was taken. Both, and the start's registered
  // kind, prec and rm, rely on the CLK.I fall in /DS coming at least one
  // master clock before the /DS rise.
  // Justification: (reg-a) the instruction's word 1 fields and template,
  // from IF1 to word 2.
  logic [7:4] w1_q, w1_d;
  tpl_e       tpl_q, tpl_d;

  // Justification: (reg-b) the decode of the data latch.
  logic        if1_epa, if1_ok, plan_ok, if1_epa_u, if1_ok_u, plan_ok_u;
  tpl_e        if1_tpl, if1_tpl_u;
  logic [1:0]  if1_id, if1_id_u;
  mn_e         pl_mn, pl_mn_u;
  logic [2:0]  pl_fd, pl_fs, pl_fd_u, pl_fs_u;
  fmt_e        pl_fmt, pl_fmt_u;
  logic [1:0]  pl_rnd_u;
  logic [3:0]  pl_sel, pl_sel_u;
  logic [7:0]  pl_list, pl_list_u;
  dir_e        pl_dir, pl_dir_u;
  logic [3:0]  pl_words, pl_words_u;

  z8070_dec u_dec (
    .if1_op     (ds_data_d[15:8]),
    .if1_dir_id (ds_data_d[3:0]),
    .if1_epa (if1_epa_u),
    .if1_ok  (if1_ok_u),
    .if1_tpl (if1_tpl_u),
    .if1_id  (if1_id_u),
    .tpl     (tpl_q),
    .w1      (w1_q),
    .w2      (ds_data_d),
    .plan_ok (plan_ok_u),
    .mn      (pl_mn_u),
    .fd      (pl_fd_u),
    .fs      (pl_fs_u),
    .fmt     (pl_fmt_u),
    .rnd     (pl_rnd_u),
    .sel     (pl_sel_u),
    .list_byte    (pl_list_u),
    .dir     (pl_dir_u),
    .words   (pl_words_u)
  );

  always_ff @(posedge clk) begin
    {if1_epa, if1_ok, if1_tpl, if1_id} <= {if1_epa_u, if1_ok_u, if1_tpl_u, if1_id_u};
    {plan_ok, pl_mn, pl_fd, pl_fs, pl_fmt} <= {plan_ok_u, pl_mn_u, pl_fd_u, pl_fs_u, pl_fmt_u};
    {pl_sel, pl_list, pl_dir, pl_words} <= {pl_sel_u, pl_list_u, pl_dir_u, pl_words_u};
  end

  // Justification: (reg-a) the plan fields the transfer and the Data
  // Processor still need after word 2 has left the data latch: the
  // destination and source register numbers among them.
  mn_e        mn_q;
  logic [3:0] sel_q;
  logic [7:0] list_q;
  dir_e       dir_q;
  logic [2:0] words_q;     // 1-5 once decoded
  fmt_e       fmt_q;
  logic [2:0] ra_q, rb_q;

  // Justification: (reg-a) the operand or result words, first word in 0.
  logic [4:0][15:0] buf_q, buf_d;

  // The result hand-over, formed below with the transfer buffer.
  logic       fold;        // the Data Processor's done, for this instruction
  logic       apply;       // and its flags go into FFLAGS
  logic       trap;        // a flag whose trap is enabled
  logic       fop1_bus;    // FOP1 is the bus operand, not the RAM's read
  logic [79:0] bus_x;      // the bus operand
  logic [2:0] pl_ra, pl_rb;

  // ---- sequencer -------------------------------------------------------
  // The queue holds one instruction behind the executing one (Intermediate
  // overlap; in No Overlap only an IF1 the CPU fetched before /BSY held
  // it). Its operand words use the transfer buffer, its template and word
  // 1 tpl_q and w1_q, its select, word count and list byte sel_q, words_q
  // and list_q, and its operation the start registers: the executing
  // instruction is a Data Processor operation that no longer needs them.
  typedef enum logic [1:0] {
    PQ_NONE  = 2'd0,
    PQ_W2    = 2'd1,   // IF1 queued: the next 1100 is its word 2
    PQ_CAPT  = 2'd2,   // taking its operand words
    PQ_READY = 2'd3    // complete: starts when the executing one is done
  } pq_e;

  // Justification: (reg-a) instruction state, the word count, the queue
  // state.
  ip_e        state_q, state_d;
  pq_e        pend_q, pend_d;
  logic [2:0] cnt_q, cnt_d;
  logic [31:0] pc1_d, pc2_d;

  // /ABORT acts before the cycle, as a level: the instruction and the
  // queued one are dropped; a running operation finishes unseen.
  ip_e        cur;
  pq_e        pnd;

  assign cur = abort_n ? state_q : IP_IDLE;
  assign pnd = abort_n ? pend_q : PQ_NONE;

  // Justification: (reg-a) the queued instruction's plan fields the
  // executing one still uses, and whether its first read is Fs.
  mn_e        p_mn;
  dir_e       p_dir;
  fmt_e       p_fmt;
  logic [2:0] p_ra, p_rb;
  logic       p_sf, p_lst;
  logic       p_ns;        // N/S of its last transfer

  // The same as of this master clock: its word 2, or its last operand
  // word, may come in the clock that promotes it.
  mn_e        q_mn;
  dir_e       q_dir;
  fmt_e       q_fmt;
  logic [2:0] q_ra, q_rb;
  logic       q_sf, q_lst, q_ns;

  // Events of this master clock, for the register and buffer blocks.
  logic       launch;      // word 2 decoded with a plan
  logic       p_load;      // the queued instruction's word 2 decoded
  logic       promote;     // the queued instruction starts
  logic       pstart;      // and it is a Data Processor operation
  logic       list_go;     // flag, trap or mode list, applied next clock
  logic       capture;     // an operand word into the buffer
  logic       fcw_in;      // EPU<-FCW form complete
  logic       ctl_wr;      // FLDCTL inbound complete
  logic       stg_set;     // keep the executing operation's bus operand
  logic       raise;
  logic [1:0] reason;

  logic [3:0] epuids;
  logic       last_in;
  logic       is_list;

  assign epuids  = sc_q[SC_EPUIDS +: 4];
  assign last_in = (cnt_q + 3'd1) == words_q;
  assign is_list = (pl_mn == MN_FSETFLG) || (pl_mn == MN_FRESFLG) ||
                   (pl_mn == MN_FSETTRAP) || (pl_mn == MN_FRESTRAP) ||
                   (pl_mn == MN_FSETMODE);

  always_comb begin
    state_d  = cur;
    pend_d   = pnd;
    cnt_d    = cnt_q;
    w1_d     = w1_q;
    tpl_d    = tpl_q;
    pc1_d    = pc1_q;
    pc2_d    = pc2_q;
    launch   = 1'b0;
    p_load   = 1'b0;
    promote  = 1'b0;
    pstart   = 1'b0;
    list_go  = 1'b0;
    capture  = 1'b0;
    fcw_in   = 1'b0;
    ctl_wr   = 1'b0;
    stg_set  = 1'b0;
    raise    = 1'b0;
    reason   = IR_INVALID_OP;

    if (ds_rise && busack_n) begin
      unique case (cyc_st_q)
        ST_IF1: if (if1_epa) begin
          if (!if1_ok) begin
            raise = 1'b1;
          end else if (if1_id != sc_q[SC_ID +: 2]) begin
            if (epuids[if1_id]) begin
              raise  = 1'b1;
              reason = IR_INVALID_EPUID;
            end
          end else if (cur == IP_IDLE && !dp_busy && pnd == PQ_NONE) begin
            w1_d     = ds_data_q[7:4];
            tpl_d    = if1_tpl;
            pc1_d    = {1'b0, cyc_addr_q[22:16], 8'h00, cyc_addr_q[15:0]};
            state_d  = IP_WORD2;
          end else if (pnd == PQ_NONE) begin
            w1_d     = ds_data_q[7:4];
            tpl_d    = if1_tpl;
            pc2_d    = {1'b0, cyc_addr_q[22:16], 8'h00, cyc_addr_q[15:0]};
            pend_d   = PQ_W2;
            // The executing operation's unpack (opnd_rd) is over by this
            // /DS rise; its operand is kept for FOP1 only.
            stg_set  = cur == IP_DPWAIT && dir_q == DIR_IN;
          end
        end
        ST_PROG: if (cur == IP_WORD2) begin
          if (!plan_ok) begin
            state_d = IP_IDLE;
            raise   = 1'b1;
          end else begin
            launch = 1'b1;
            cnt_d  = 3'd0;
            unique case (pl_dir)
              DIR_IN:  state_d = IP_OPERAND;
              DIR_OUT: if (pl_mn == MN_FLDCTL || pl_mn == MN_FLDCTLB) begin
                state_d = IP_RESULT;
              end else begin
                state_d  = IP_DPWAIT;
              end
              default: if (is_list) begin
                list_go = 1'b1;
                state_d = IP_IDLE;
              end else begin
                state_d  = IP_DPWAIT;
              end
            endcase
          end
        end else if (pnd == PQ_W2) begin
          if (!plan_ok) begin
            pend_d = PQ_NONE;
            raise  = 1'b1;
          end else begin
            p_load = 1'b1;
            cnt_d  = 3'd0;
            pend_d = (pl_dir == DIR_IN) ? PQ_CAPT : PQ_READY;
          end
        end
        default: begin
          if (cyc_in && cur == IP_OPERAND) begin
            capture = 1'b1;
            cnt_d   = cnt_q + 3'd1;
            if (last_in) begin
              if (tpl_q == TPL_EPU_FROM_FCW) begin
                fcw_in  = 1'b1;
                state_d = IP_IDLE;
              end else if (mn_q == MN_FLDCTL) begin
                ctl_wr  = 1'b1;
                state_d = IP_IDLE;
                if (sel_q == CTL_SC && cyc_ns_q) begin
                  raise  = 1'b1;
                  reason = IR_PRIVILEGE;
                end
              end else begin
                state_d  = IP_DPWAIT;
              end
            end
          end else if (cyc_in && pnd == PQ_CAPT) begin
            capture = 1'b1;
            cnt_d   = cnt_q + 3'd1;
            if (last_in) pend_d = PQ_READY;
          end else if (cyc_out && (cur == IP_RESULT ||
                                   (cur == IP_DPWAIT && dir_q == DIR_OUT))) begin
            // In DPWAIT the word was taken before it was ready: lost, but
            // counted, to stay in step with the CPU. The count stops at 7,
            // past every word count, so it never comes round to a word.
            cnt_d = (cnt_q == 3'd7) ? cnt_q : cnt_q + 3'd1;
            if (cur == IP_RESULT && last_in) state_d = IP_IDLE;
          end
        end
      endcase
    end

    if (fold) begin
      if (dir_q == DIR_OUT && cnt_d < words_q) state_d = IP_RESULT;
      else                                     state_d = IP_IDLE;
      if (trap) begin
        raise  = 1'b1;
        reason = IR_ARITH;
        pend_d = PQ_NONE;   // the exception flushes the queued instruction
      end
    end

    // The queued instruction starts on a CLK.I rise once the executing one
    // is done, in that clock. A Data Processor operation gets its start the
    // next master clock, before the next CLK.D rise.
    if (clki_rise && pend_d == PQ_READY && state_d == IP_IDLE && (!dp_busy || dp_done)) begin
      promote = 1'b1;
      pend_d  = PQ_NONE;
      pc1_d   = pc2_q;
      cnt_d   = 3'd0;
      unique case (q_dir)
        DIR_IN: if (tpl_q == TPL_EPU_FROM_FCW) begin
          fcw_in = 1'b1;
        end else if (q_mn == MN_FLDCTL) begin
          ctl_wr = 1'b1;
          if (sel_q == CTL_SC && q_ns) begin
            raise  = 1'b1;
            reason = IR_PRIVILEGE;
          end
        end else begin
          state_d = IP_DPWAIT;
          pstart  = 1'b1;
        end
        DIR_OUT: if (q_mn == MN_FLDCTL || q_mn == MN_FLDCTLB) begin
          state_d = IP_RESULT;
        end else begin
          state_d = IP_DPWAIT;
          pstart  = 1'b1;
        end
        default: if (q_lst) begin
          list_go = 1'b1;
        end else begin
          state_d = IP_DPWAIT;
          pstart  = 1'b1;
        end
      endcase
    end

    // An unused state code returns to idle.
    if (state_q != IP_IDLE && state_q != IP_WORD2 && state_q != IP_OPERAND &&
        state_q != IP_DPWAIT && state_q != IP_RESULT)
      state_d = IP_IDLE;

    int_req_d = (int_req_q & ~ack_take) | raise;
  end

  // Justification: (reg-a) the promoted start, the list op's clock, the
  // executing operation's bus operand kept in RAM row 10 (requested, written,
  // and readable).
  logic pstart_q, list_go_q, stg_req_q, stg_q, stg2_q, stg_now;

  always_ff @(posedge clk) begin
    if (!reset_n) begin
      state_q   <= IP_IDLE;
      pend_q    <= PQ_NONE;
      cnt_q     <= 3'd0;
      int_req_q <= 1'b0;
      pc1_q     <= 32'd0;
      pc2_q     <= 32'd0;
      pstart_q  <= 1'b0;
      list_go_q <= 1'b0;
    end else begin
      state_q   <= state_d;
      pend_q    <= pend_d;
      cnt_q     <= cnt_d;
      int_req_q <= int_req_d;
      pc1_q     <= pc1_d;
      pc2_q     <= pc2_d;
      pstart_q  <= pstart;
      list_go_q <= list_go;
    end
  end

  always_ff @(posedge clk) begin
    if (!reset_n || !abort_n || fold) begin
      stg_req_q <= 1'b0;
      stg_q     <= 1'b0;
      stg2_q    <= 1'b0;
    end else begin
      if (stg_set)      stg_req_q <= 1'b1;
      else if (stg_now) stg_req_q <= 1'b0;
      if (stg_now)      stg_q     <= 1'b1;
      stg2_q <= stg_q;
    end
  end

  always_ff @(posedge clk) begin
    w1_q  <= w1_d;
    tpl_q <= tpl_d;
  end

  // A /DS rise starts the Data Processor where the sequencer goes to
  // DPWAIT: decided a clock ahead from the decode's next value, so the
  // start is the strobe edge and a flop.
  // Justification: (reg-b) the start off the decode and sequencer paths.
  logic arm_q, arm_d, is_list_u;

  assign is_list_u = (pl_mn_u == MN_FSETFLG) || (pl_mn_u == MN_FRESFLG) ||
                     (pl_mn_u == MN_FSETTRAP) || (pl_mn_u == MN_FRESTRAP) ||
                     (pl_mn_u == MN_FSETMODE);

  always_comb begin
    unique case (cyc_st_q)
      ST_IF1:  arm_d = 1'b0;
      ST_PROG: arm_d = cur == IP_WORD2 && plan_ok_u &&
                       ((pl_dir_u == DIR_OUT && pl_mn_u != MN_FLDCTL && pl_mn_u != MN_FLDCTLB) ||
                        (pl_dir_u == DIR_NONE && !is_list_u));
      default: arm_d = cyc_in && cur == IP_OPERAND && last_in &&
                       tpl_q != TPL_EPU_FROM_FCW && mn_q != MN_FLDCTL;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!reset_n) arm_q <= 1'b0;
    else          arm_q <= arm_d;
  end

  assign dp_start = (ds_rise && busack_n && arm_q && abort_n) || pstart_q;

  logic src_first;

  always_ff @(posedge clk) begin
    if (launch) begin
      {mn_q, dir_q, fmt_q, ra_q, rb_q} <= {pl_mn, pl_dir, pl_fmt, pl_ra, pl_rb};
    end else if (promote) begin
      {mn_q, dir_q, fmt_q, ra_q, rb_q} <= {q_mn, q_dir, q_fmt, q_ra, q_rb};
    end
  end

  always_ff @(posedge clk) begin
    if (launch || p_load) begin
      sel_q   <= pl_sel;
      words_q <= pl_words[2:0];
      list_q  <= pl_list;
    end
  end

  always_ff @(posedge clk) begin
    if (p_load) {p_mn, p_dir, p_fmt, p_ra, p_rb, p_sf, p_lst} <=
                {pl_mn, pl_dir, pl_fmt, pl_ra, pl_rb, src_first, is_list};
  end

  always_ff @(posedge clk) begin
    if (pend_d == PQ_READY && pend_q != PQ_READY) p_ns <= cyc_ns_q;
  end

  assign {q_mn, q_dir, q_fmt, q_ra, q_rb, q_sf, q_lst} = p_load ?
           {pl_mn, pl_dir, pl_fmt, pl_ra, pl_rb, src_first, is_list} :
           {p_mn, p_dir, p_fmt, p_ra, p_rb, p_sf, p_lst};
  assign q_ns = (pend_q == PQ_READY) ? p_ns : cyc_ns_q;

  // ---- control registers -----------------------------------------------
  // List masks from word 1 and word 2: sticky flags, the compare byte in
  // FCW order (bits 7:2), trap enables.
  logic        list_set;
  logic [31:0] list_mask;
  logic [31:0] ctl_word;   // FLDCTL inbound, {first word, last word}

  assign list_set = (mn_q == MN_FSETFLG) || (mn_q == MN_FSETTRAP);
  assign ctl_word = {buf_d[0], buf_d[1]};

  always_comb begin
    unique case (sel_q)
      LIST_TRAP:    list_mask = {24'd0, list_q} << US_TRAP;
      LIST_COMPARE: list_mask = {26'd0, list_q[7:2]} << FF_CMP;
      default:      list_mask = {24'd0, list_q};
    endcase
  end

  always_comb begin
    sc_d     = sc_q;
    user_d   = user_q;
    fflags_d = fflags_q;

    if (launch || promote) sc_d[SC_U] = 1'b1;

    if (list_go_q) begin
      if (mn_q == MN_FSETMODE) begin
        user_d[1:0] = (user_q[1:0] & ~sel_q[1:0]) | list_q[1:0];
      end else if (sel_q == LIST_TRAP) begin
        user_d = list_set ? (user_q | list_mask) : (user_q & ~list_mask);
      end else begin
        fflags_d = list_set ? (fflags_q | list_mask) : (fflags_q & ~list_mask);
      end
    end

    if (fcw_in) fflags_d[FF_CMP +: 6] = buf_d[0][7:2];

    if (ctl_wr) begin
      unique case (sel_q)
        CTL_SC:     if (!(promote ? q_ns : cyc_ns_q)) sc_d = ctl_word;
        CTL_FFLAGS: fflags_d = ctl_word;
        CTL_USER:   user_d[15:0] = buf_d[0];
        default: ;  // PC1, PC2, FOP1, FOP2 are read only
      endcase
    end

    // The Data Processor's result, after this clock's bus work.
    if (apply) begin
      fflags_d[15:8] = dp_flags;
      fflags_d[7:0]  = fflags_d[7:0] | dp_flags;
      if (|dp_cmp)     fflags_d[FF_CMP +: 6] = dp_cmp;
      fflags_d[FF_R] = dp_rup;
      if (dp_flags[FL_INV]) fflags_d[FF_RSN +: 3] = dp_reason;
      if (|dp_flags)   fflags_d[FF_FOPE +: 4] = {fop1_bus ? bus_x[78:77] : f_rdata[78:77],
                                             dp_res[78:77]};
    end

    if (ack_take) begin
      sc_d[SC_IP]  = 1'b0;
      sc_d[SC_IUS] = 1'b1;
    end

    if (raise) begin
      sc_d[SC_IR +: 2] = reason;
      sc_d[SC_IP]      = 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (!reset_n) begin
      sc_q     <= {4'h0, id, 26'd0};
      user_q   <= 32'd0;
      fflags_q <= 32'd0;
    end else begin
      sc_q     <= sc_d;
      user_q   <= user_d;
      fflags_q <= fflags_d;
    end
  end

  // ---- transfer buffer -------------------------------------------------
  // FLDCTLB flag groups, word 1 bits 7:4, as the CP/M-8000 emulator maps
  // the sticky flags onto the FCW flags; group 4 sends the compare flags.
  logic [7:0] st_fl;
  logic [7:0] cmp_byte;
  logic [7:0] grp_byte;

  assign st_fl    = fflags_q[7:0];
  assign cmp_byte = {fflags_q[FF_CMP +: 6], 2'b00};

  always_comb begin
    grp_byte = 8'h00;
    if (sel_q == 4'd0) begin
      if (st_fl[FL_DZ])  grp_byte = grp_byte | FCW_C | FCW_S;
      if (st_fl[FL_FOV]) grp_byte = grp_byte | FCW_C | FCW_V;
      if (st_fl[FL_UN])  grp_byte = grp_byte | FCW_Z;
    end else if (sel_q[0] && sel_q[1]) begin
      grp_byte = 8'h00;
    end else if (sel_q[0]) begin
      if (st_fl[FL_INV]) grp_byte = grp_byte | FCW_C;
      if (st_fl[FL_NAN]) grp_byte = grp_byte | FCW_S;
      if (st_fl[FL_DZ])  grp_byte = grp_byte | FCW_V;
      if (st_fl[FL_INX]) grp_byte = grp_byte | FCW_Z;
    end else if (sel_q[2]) begin
      grp_byte = cmp_byte;
    end else begin
      if (st_fl[FL_DZ])  grp_byte = grp_byte | FCW_S | FCW_Z;
      if (st_fl[FL_IX])  grp_byte = grp_byte | FCW_V | FCW_Z;
      if (st_fl[FL_INX]) grp_byte = grp_byte | FCW_C;
      if (st_fl[FL_INV] || st_fl[FL_NAN]) grp_byte = grp_byte | FCW_Z;
    end
  end

  always_comb begin
    buf_d = buf_q;
    if (capture) begin
      unique case (cnt_q)
        3'd0:    buf_d[0] = ds_data_q;
        3'd1:    buf_d[1] = ds_data_q;
        3'd2:    buf_d[2] = ds_data_q;
        3'd3:    buf_d[3] = ds_data_q;
        3'd4:    buf_d[4] = ds_data_q;
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk) begin
    buf_q <= buf_d;
  end

  // ---- Data Processor hand-over ----------------------------------------
  // The plan being started: from the decode at word 2, latched after it.
  mn_e        c_mn;
  dir_e       c_dir;
  logic       at_w2;

  // Destination register, and the source: Fs, or Fd for an outbound
  // conversion (which converts the destination).
  assign pl_ra = pl_fd;
  assign pl_rb = (pl_dir == DIR_OUT && pl_fmt != FMT_BYTE) ? pl_fd : pl_fs;

  assign at_w2 = state_q == IP_WORD2;
  assign c_mn  = at_w2 ? pl_mn  : mn_q;
  assign c_dir = at_w2 ? pl_dir : dir_q;

  // Operation code (the Data Processor's kind), precision and rounding of
  // the decode's next value, registered through word 2 and held from its
  // /DS rise: a start sees them from flops.
  logic [5:0] kind_u;
  logic [1:0] prec_u, rm_u;
  logic       out_u;       // a single or double store

  always_comb begin
    unique case (pl_mn_u)
      MN_FADD:     kind_u = 6'h00;
      MN_FSUB:     kind_u = 6'h01;
      MN_FRVSUB:   kind_u = 6'h02;
      MN_FMUL:     kind_u = 6'h03;
      MN_FDIV:     kind_u = 6'h04;
      MN_FRDIV:    kind_u = 6'h05;
      MN_FPWR2:    kind_u = 6'h06;
      MN_FSQR:     kind_u = 6'h07;
      MN_FLD, MN_FLDNF: kind_u = 6'h08;
      MN_FABS:     kind_u = 6'h09;
      MN_FNEG:     kind_u = 6'h0A;
      MN_FCLR:     kind_u = 6'h0B;
      MN_FINT:     kind_u = 6'h0C;
      MN_FCP, MN_FCPF:      kind_u = 6'h0D;
      MN_FCPX, MN_FCPFX:    kind_u = 6'h0E;
      MN_FCPZ, MN_FCPZNF:   kind_u = 6'h0F;
      MN_FCPZFX, MN_FCPZXNF: kind_u = 6'h10;
      MN_FREMSNF:  kind_u = 6'h11;
      MN_FREMSTEP: kind_u = 6'h12;
      MN_FLDIL, MN_FLDIQ: kind_u = (pl_dir_u == DIR_OUT) ? 6'h21 : 6'h20;
      MN_FLDTL, MN_FLDTQ: kind_u = 6'h21;
      MN_FLDBCD:   kind_u = (pl_dir_u == DIR_OUT) ? 6'h23 : 6'h22;
      default:     kind_u = 6'h00;
    endcase
  end

  // To an integer: 1 = 64 bits. Outbound: the memory format. Else the
  // rounding field: 01 single, 11 double, else extended.
  always_comb begin
    if (kind_u == 6'h21)          prec_u = {1'b0, pl_mn_u == MN_FLDIQ || pl_mn_u == MN_FLDTQ};
    else if (kind_u == 6'h23)     prec_u = 2'd0;
    else if (pl_dir_u == DIR_OUT) prec_u = (pl_fmt_u == FMT_SINGLE) ? 2'd0 :
                                           (pl_fmt_u == FMT_DOUBLE) ? 2'd1 : 2'd2;
    else                          prec_u = (pl_rnd_u == 2'b01) ? 2'd0 : (pl_rnd_u == 2'b11) ? 2'd1 : 2'd2;
  end

  assign rm_u  = (pl_mn_u == MN_FLDTL || pl_mn_u == MN_FLDTQ) ? 2'b01 : user_q[1:0];
  assign out_u = (pl_mn_u == MN_FLD || pl_mn_u == MN_FLDNF) && pl_dir_u == DIR_OUT &&
                 (pl_fmt_u == FMT_SINGLE || pl_fmt_u == FMT_DOUBLE);

  // Justification: (reg-b) the start's operation off the decode path.
  always_ff @(posedge clk) begin
    if ((at_w2 && !launch) || (pend_q == PQ_W2 && !p_load))
      {dp_kind, dp_prec, dp_rm, dp_out} <= {kind_u, prec_u, rm_u, out_u};
  end

  // The bus operand, from the buffer as this clock's capture leaves it.
  logic [31:0] bs;
  logic [63:0] bd;
  logic [14:0] bs_e, bd_e;

  assign bs = {buf_d[0], buf_d[1]};
  assign bd = {buf_d[0], buf_d[1], buf_d[2], buf_d[3]};

  // One rebias adder for both formats.
  logic [14:0] b_sum;

  assign b_sum = (fmt_q == FMT_SINGLE) ? {7'd0, bs[30:23]} + 15'd16256 :
                                         {4'd0, bd[62:52]} + 15'd15360;

  always_comb begin
    if (&bs[30:23])       bs_e = 15'h7FFF;
    else if (~|bs[30:23]) bs_e = (|bs[22:0]) ? 15'd16257 : 15'd0;
    else                  bs_e = b_sum;
    if (&bd[62:52])       bd_e = 15'h7FFF;
    else if (~|bd[62:52]) bd_e = (|bd[51:0]) ? 15'd15361 : 15'd0;
    else                  bd_e = b_sum;
  end

  always_comb begin
    unique case (fmt_q)
      FMT_SINGLE: bus_x = {bs[31], bs_e, |bs[30:23], bs[22:0], 40'd0};
      FMT_DOUBLE: bus_x = {bd[63], bd_e, |bd[62:52], bd[51:0], 11'd0};
      FMT_INT32:  bus_x = {16'd0, {32{bs[31]}}, bs};
      FMT_INT64:  bus_x = {16'd0, bd};
      default:    bus_x = {buf_d[0], buf_d[1], buf_d[2], buf_d[3], buf_d[4]};
    endcase
  end

  // Operand bus: inbound sources come from the bus, and the inbound
  // compares with zero compare the bus operand. Outside operand words it
  // carries FOP1's operand, the source (the destination outbound), and for
  // the RAM's write port the result or FOP1.
  logic src_bus, dst_bus, op_bus, wb_now, fop_q, fop1_bus_q, fop2_pend_q, fop2_now, f_rd;

  assign src_bus = c_dir == DIR_IN;
  assign dst_bus = src_bus && (c_mn == MN_FCPZNF || c_mn == MN_FCPZXNF);
  assign op_bus  = fop_q ? fop1_bus_q : (wb_now || fop2_now) ? 1'b0 :
                   (dp_busy && !dp_opnd_rd) ? src_bus : dp_opnd_src ? src_bus : dst_bus;
  assign dp_opnd = op_bus ? bus_x : (wb_now || fop2_now) ? dp_res : f_rdata;

  // F read address, a master clock ahead of its use. Running: the operand
  // word's register, else FOP1's (the input operand; row 10 once a queued
  // instruction's words are due in the buffer) for the done clock. Before
  // word 2: the first operand of the internal form, Fs for the operations
  // whose first microword (the ROM's first-word table) reads the source,
  // else Fd (outbound forms read Fd only); a queued one's from the clock
  // that takes it, for a CLK.D rise with its start. FLDCTL of FOP1 or FOP2: its row. Taking operands: Fd.
  assign src_first = tpl_q == TPL_INTERNAL &&
                     (pl_mn_u == MN_FCLR || pl_mn_u == MN_FRVSUB || pl_mn_u == MN_FRDIV ||
                      pl_mn_u == MN_FPWR2 || pl_mn_u == MN_FSQR || pl_mn_u == MN_FINT ||
                      pl_mn_u == MN_FABS || pl_mn_u == MN_FNEG || pl_mn_u == MN_FLD ||
                      pl_mn_u == MN_FLDNF);

  always_comb begin
    if (dp_busy)       f_raddr = !dp_opnd_rd ? (stg_q ? 4'd10 : {1'b0, (dir_q == DIR_OUT) ? ra_q : rb_q}) :
                                 {1'b0, dp_opnd_src ? rb_q : ra_q};
    else if (at_w2)    f_raddr = {1'b0, src_first ? pl_fs_u : pl_fd_u};
    else if (promote)  f_raddr = {1'b0, q_sf ? q_rb : q_ra};
    else if (pstart_q) f_raddr = {1'b0, p_sf ? rb_q : ra_q};
    else if (state_q == IP_RESULT && mn_q == MN_FLDCTL)
                       f_raddr = {3'b100, sel_q == CTL_FOP2};
    else               f_raddr = {1'b0, ra_q};
  end

  assign fold  = cur == IP_DPWAIT && dp_done;
  assign apply = fold && mn_q != MN_FLDNF;
  assign trap  = apply && |(dp_flags & user_q[US_TRAP +: 8]);

  // The RAM's one write port after done: F[Fd] in the done clock, FOP1 the
  // next from the read register held through done, FOP2 in the first
  // clock after that the Data Processor does not read the operand bus (a
  // queued operation may start the clock after done and read F[Fd]). Row
  // 10 takes the bus operand in a free clock once a queued IF1 is seen.
  logic no_wb, fop;

  assign no_wb    = mn_q == MN_FCP || mn_q == MN_FCPX || mn_q == MN_FCPZNF || mn_q == MN_FCPZXNF;
  assign fop      = apply && |dp_flags;
  assign fop1_bus = src_bus && !stg2_q;
  assign wb_now   = fold && ((dir_q != DIR_OUT && !no_wb) || mn_q == MN_FREMSTEP);
  assign f_rd     = (dp_busy && dp_opnd_rd) || pstart_q;
  assign fop2_now = fop2_pend_q && !f_rd && !wb_now && !fop_q;
  assign stg_now  = stg_req_q && !f_rd && !fold && !fop_q && !fop2_pend_q;
  assign f_re     = !fold;

  // Justification: (reg-a) the write-port steps after done.
  always_ff @(posedge clk) begin
    if (!reset_n) begin
      fop_q       <= 1'b0;
      fop2_pend_q <= 1'b0;
    end else begin
      fop_q       <= fop;
      fop2_pend_q <= fop_q | (fop2_pend_q & ~fop2_now);
    end
  end

  always_ff @(posedge clk) begin
    fop1_bus_q <= fop1_bus;
  end

  // FLDCTL of FOP1 or FOP2 waits three CLK.I rises from done (that of
  // done included) for their write-back and a read after it.
  // Justification: (reg-a) CLK.I rises left.
  logic [1:0] fset_q;
  logic       fop_wait;

  always_ff @(posedge clk) begin
    if (!reset_n)                      fset_q <= 2'd0;
    else if (fop)                      fset_q <= clki_rise ? 2'd2 : 2'd3;
    else if (clki_rise && fset_q != 0) fset_q <= fset_q - 2'd1;
  end

  assign fop_wait = state_q == IP_RESULT && mn_q == MN_FLDCTL && fset_q != 2'd0 &&
                    (sel_q == CTL_FOP1 || sel_q == CTL_FOP2);

  assign f_we    = wb_now || fop_q || fop2_now || stg_now;
  assign f_waddr = wb_now ? {1'b0, ra_q} : fop_q ? 4'd8 : fop2_now ? 4'd9 : 4'd10;
  assign f_wdata = dp_opnd;

  // Result words, field by field. Single and double: the integer bit
  // tells a normal from the denormalized form; a NaN whose payload
  // truncates to 0 keeps its quiet bit.
  logic        r_spec, r_nan;
  logic [14:0] r_e;
  logic [10:0] r_dif;
  logic [7:0]  r_es;
  logic [10:0] r_ed;
  logic [22:0] r_fs;
  logic [51:0] r_fd;
  logic [31:0] ctl_v;

  assign r_e    = dp_res[78:64];
  assign r_spec = &r_e;
  assign r_nan  = r_spec && |dp_res[62:0];
  assign r_dif  = 11'(r_e - ((fmt_q == FMT_SINGLE) ? 15'd16256 : 15'd15360));
  assign r_es   = r_spec ? 8'hFF : dp_res[63] ? r_dif[7:0] : 8'h00;
  assign r_ed   = r_spec ? 11'h7FF : dp_res[63] ? r_dif[10:0] : 11'h000;
  assign r_fs   = {dp_res[62] | (r_nan & ~|dp_res[62:40]), dp_res[61:40]};
  assign r_fd   = {dp_res[62] | (r_nan & ~|dp_res[62:11]), dp_res[61:11]};

  always_comb begin
    unique case (sel_q)
      CTL_SC:     ctl_v = sc_q;
      CTL_PC1:    ctl_v = pc1_q;
      CTL_PC2:    ctl_v = pc2_q;
      CTL_FFLAGS: ctl_v = fflags_q;
      default:    ctl_v = {user_q[15:0], 16'h0000};
    endcase
  end

  // ---- pins ------------------------------------------------------------
  logic        dp_wait, store_wait, bsy_dp, drive, vec_drive;
  logic [7:0]  vec;
  logic [15:0] out_word;
  logic [79:0] img;

  assign dp_wait    = state_q == IP_DPWAIT;
  assign store_wait = (dp_wait && dir_q == DIR_OUT) || (pend_q == PQ_READY && p_dir == DIR_OUT) ||
                      fop_wait;
  assign bsy_dp     = (sc_q[SC_OVRLP +: 2] == OVRLP_INTERMEDIATE) ? pend_q == PQ_READY : dp_wait;
  assign drive      = state_q == IP_RESULT && busack_n && !fop_wait &&
                      ((cyc_mem && cyc_write_q && cyc_open_q) ||
                       (cyc_epu && !cyc_write_q && !ds_n));

  assign vec_drive  = in_ack && !ds_n && !sc_q[SC_NV];
  assign vec        = sc_q[SC_SV] ? {sc_q[6:0], 1'b0} : sc_q[7:0];

  // The words of whatever this instruction sends, first word at the top.
  always_comb begin
    if (mn_q == MN_FLDCTLB)
      img = {8'h00, grp_byte, 64'd0};
    else if (mn_q == MN_FLDCTL)
      img = (sel_q == CTL_FOP1 || sel_q == CTL_FOP2) ? f_rdata : {ctl_v, 48'd0};
    else unique case (fmt_q)
      FMT_BYTE:   img = {8'h00, cmp_byte, 64'd0};
      FMT_INT32:  img = {dp_res[31:0], 48'd0};
      FMT_INT64:  img = {dp_res[63:0], 16'd0};
      FMT_SINGLE: img = {dp_res[79], r_es, r_fs, 48'd0};
      FMT_DOUBLE: img = {dp_res[79], r_ed, r_fd, 16'd0};
      default:    img = dp_res;
    endcase
  end

  always_comb begin
    unique case (cnt_q)
      3'd0:    out_word = img[79:64];
      3'd1:    out_word = img[63:48];
      3'd2:    out_word = img[47:32];
      3'd3:    out_word = img[31:16];
      3'd4:    out_word = img[15:0];
      default: out_word = 16'h0000;
    endcase
  end

  always_comb begin
    ad_drive = reset_n & (drive | vec_drive);
    ad_out   = drive ? out_word : {8'h00, vec};
    bsy_n    = ~(reset_n & (bsy_dp | store_wait));
    int_n    = ~(reset_n & int_req);
    ieo      = iei & (~reset_n | ~(sc_q[SC_IUS] | sc_q[SC_DLC] | in_ack));
  end

  // Pins with no function on the Z8000 interface.
  logic unused_ok;
  assign unused_ok = ^{b_w, opt, pl_words[3]};

endmodule

`default_nettype wire
