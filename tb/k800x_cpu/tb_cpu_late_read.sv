// tb_cpu_late_read -- a Z8001 whose memory and I/O drive read data late in
// T3: after the CLK rise opening T3, held to the CLK fall in it.
//
// The CPU must take a read word on the CLK fall in T3 (1988 DB PDF p.47,
// #12: read data setup to the CLK fall). The board here pulses CLK from a
// master-clock divider. While /DS is Low in a read, AD carries the word only
// in the master clocks that hold no CLK pulse, and changing garbage in the
// master clocks of a pulse: a CPU taking the word at the T3 rise reads
// garbage; one taking it as CLK falls (AD in the master clock before the
// fall's pulse) reads the word.
//
// The program, from reset in segmented system mode, reads through every
// kind of read cycle: instruction fetches (first words, immediate words,
// short and long address words), memory operands (indirect, direct short,
// direct long, an ADD from memory), a word IN, a memory read the board
// holds with two wait states, a byte read, a CALL and RET across segments
// with refresh on, MREQ with /MI High then Low (the other level at the T3
// rise and fall: only the rise ending T3 may sample it), and a vectored interrupt
// whose acknowledge word picks the handler and is pushed on the stack.
// Any simulation check the CPU flags fails the run.
//
//   +half=N[,M...]  master clocks per CLK half, cycled (default 2; 2 or
//                   more for the late window)
//   +normal         the word on AD for as long as /DS is Low
//   +only=K         late for one kind of read: fetch, data, io or ack
//   +edge           the word only in the master clock before the fall's
//                   pulse (half 3 or more tells it from the one after the
//                   rise)
//   +mixed          turbo from the first read waiting for its T3 fall: an
//                   unsupported mix the CPU must flag (the run fails)
//   +unmix          turbo until a read's T3 rise, then the fall alone: the
//                   other unsupported order (the run fails)
//   +turbo          CLK rise and fall pulses in every master clock, the word
//                   on AD while /DS is Low: the T3 fall is then the end of
//                   the T3 rise's master clock
//   +trace          print the bus every master clock
//
// Run: make test-cpu-late-read

`default_nettype none

module tb_cpu_late_read
  import z8000_zbus_pkg::*;
;
  logic mclk = 1'b0;
  always #1 mclk = ~mclk;

  // ---- board CLK divider ---------------------------------------------------
  int   halves[$];
  int   hi = 0, left = 0;
  bit   turbo = 1'b0, normal = 1'b0, run = 1'b0, trace = 1'b0, edge_only = 1'b0, mixed = 1'b0;
  bit   unmix = 1'b0;
  string only = "";            // late for one kind of read only
  logic phase = 1'b0;          // CLK High
  logic clk_rise = 1'b0, clk_fall = 1'b0;
  always @(posedge mclk) begin
    if (!run) begin
      clk_rise <= 1'b0;
      clk_fall <= 1'b0;
    end else if (turbo || (mixed && dut.t3_q)) begin
      clk_rise <= 1'b1;
      clk_fall <= 1'b1;
      if (unmix && clk_rise && dut.bu_done && dut.bu_read) begin
        clk_rise <= 1'b0;
        clk_fall <= 1'b0;
        turbo <= 1'b0;
        phase <= 1'b1;
        left  <= 2;
      end
    end else begin
      clk_rise <= 1'b0;
      clk_fall <= 1'b0;
      if (left <= 1) begin
        phase <= !phase;
        if (phase) clk_fall <= 1'b1;
        else       clk_rise <= 1'b1;
        left  <= halves[hi];
        hi    <= (hi + 1) % halves.size();
      end else begin
        left <= left - 1;
      end
    end
  end

  // ---- CPU -------------------------------------------------------------------
  logic        reset_n = 1'b0;
  logic [15:0] ad_in, ad_out;
  logic        wait_n, vi_n = 1'b1, mi_n, mi_base = 1'b1;
  logic        ad_drive, bus_drive, as_n, ds_n, mreq_n, r_w, b_w, n_s, busack_n, mo_n;
  logic [6:0]  sn;
  logic [3:0]  st;

  z8000_cpu #(.SEGMENTED(1'b1), .VMPU(1'b0)) dut (
    .clk(mclk), .clk_rise(clk_rise), .clk_fall(clk_fall), .reset_n(reset_n),
    .ad_in(ad_in), .stop_n(1'b1), .wait_n(wait_n), .busreq_n(1'b1),
    .nmi_n(1'b1), .nvi_n(1'b1), .vi_n(vi_n), .segt_n(1'b1), .abort_n(1'b1), .mi_n(mi_n),
    .ad_out(ad_out), .ad_drive(ad_drive), .bus_drive(bus_drive), .sn(sn),
    .as_n(as_n), .ds_n(ds_n), .mreq_n(mreq_n), .r_w(r_w), .b_w(b_w), .n_s(n_s), .st(st),
    .busack_n(busack_n), .mo_n(mo_n));

  // ---- memory and I/O --------------------------------------------------------
  // Segments 00 (PSA), 03 (code, stack), 12 (data), others (a subroutine
  // in 05); word addressed.
  localparam logic [6:0]  CODE = 7'h03, DATA = 7'h12;
  localparam logic [15:0] PORT_IN = 16'h0040, PORT_VI = 16'h0020, PORT_MI = 16'h0030;
  localparam logic [15:0] SLOW = 16'h0300;     // the data word read with waits
  localparam logic [15:0] VEC = 16'h0010;      // the VI identifier
  localparam logic [15:0] IO_WORD = 16'h6666;
  logic [15:0] mem [4][32768];
  function automatic int seg_ix(input logic [6:0] s);
    return s == 7'h00 ? 0 : s == CODE ? 1 : s == DATA ? 2 : 3;
  endfunction

  logic [15:0] lat_addr = 16'h0000;
  logic [6:0]  lat_sn = 7'h00;
  logic [3:0]  lat_st = 4'hF;
  logic        lat_rw = 1'b1, lat_on = 1'b0, as_q = 1'b1, ds_q = 1'b1;
  logic [15:0] noise = 16'hA5C3;
  int          wait_left = 0;
  int unsigned n_fetch = 0, n_opnd = 0, n_io = 0, n_ack = 0, n_slow = 0, n_tw = 0, n_late = 0;
  int unsigned n_mo = 0, n_rf = 0, n_mo_at = 0;
  // An MREQ's IF1: /MI is mi_base only in the master clock of the rise
  // ending T3 (`mq_hit`), the other level from /DS Low until then.
  logic        mq_on = 1'b0, mq_ds = 1'b0, mq_hit_q = 1'b0;
  int          mq_n = 0;
  logic        mo_q = 1'b1, out_on = 1'b0;   // pins valid: after reset

  logic        rd_cyc, io_cyc, ack_cyc, pulse, fall_next;
  logic [15:0] word;
  assign rd_cyc  = lat_on && lat_rw;
  assign io_cyc  = lat_st == ST_IO || lat_st == ST_SPECIAL_IO;
  assign ack_cyc = lat_st == ST_VI_ACK;
  assign pulse   = clk_rise || clk_fall;
  assign fall_next = left <= 1 && phase;
  always_comb begin
    if (lat_st[3])    word = mem[seg_ix(lat_sn)][lat_addr[15:1]];
    else if (io_cyc)  word = lat_addr == PORT_IN ? IO_WORD : 16'hFFFF;
    else if (ack_cyc) word = VEC;
    else              word = 16'hFFFF;
  end
  // The word in the master clocks between CLK pulses (turbo, normal: all of
  // /DS Low); garbage otherwise.
  logic late;
  always_comb begin
    unique case (only)
      "fetch": late = lat_st == ST_INSTR_FETCH_FIRST || lat_st == ST_PROG_SPACE;
      "data":  late = lat_st[3] && !(lat_st == ST_INSTR_FETCH_FIRST || lat_st == ST_PROG_SPACE);
      "io":    late = io_cyc;
      "ack":   late = ack_cyc;
      default: late = 1'b1;
    endcase
  end
  assign ad_in  = rd_cyc && !ds_n && (turbo || normal || !late || (!pulse && (!edge_only || fall_next))) ? word : noise;
  // Two waits on the slow word: the T2 and TW falls sample /WAIT Low.
  logic slow, as_rose;
  assign slow    = lat_on && lat_st[3] && lat_rw && lat_sn == DATA && lat_addr == SLOW;
  assign as_rose = as_n && !as_q;
  assign wait_n  = !(slow && (wait_left > 0 || as_rose));
  logic mq_live, mq_hit;
  assign mq_live = mq_on && mq_n < 2 && (mq_ds || !ds_n);
  assign mq_hit  = mq_live && clk_rise && mq_n == 1;
  assign mi_n    = mq_live ? (mq_hit ? mi_base : !mi_base) : mi_base;

  always @(posedge mclk) begin
    noise <= {noise[14:0], noise[15] ^ noise[13] ^ noise[12] ^ noise[10]} ^ 16'h0101;
    as_q  <= as_n;
    ds_q  <= ds_n;
    if (trace) $display("%0t r%0b f%0b as%0b ds%0b rw%0b st%h sn%h ado %h drv%0b adi %h w%0b mo%0b mi%0b", $time,
                        clk_rise, clk_fall, as_n, ds_n, r_w, st, sn, ad_out, ad_drive, ad_in, wait_n, mo_n, mi_n);
    if (ds_n && !ds_q) lat_on <= 1'b0;
    if (!as_n && ad_drive) begin
      lat_addr <= ad_out;
      lat_sn   <= sn;
      lat_st   <= st;
      lat_rw   <= r_w;
      lat_on   <= 1'b1;
    end
    if (!as_n)                    wait_left <= 0;
    else if (as_rose)             wait_left <= clk_fall && !wait_n ? 1 : 2;
    else if (clk_fall && !wait_n) wait_left <= wait_left - 1;
    if (clk_fall && !wait_n) n_tw <= n_tw + 1;
    if (lat_on && !lat_rw && !ds_n && lat_st[3]) mem[seg_ix(lat_sn)][lat_addr[15:1]] <= ad_out;
    if (lat_on && !lat_rw && ds_q && !ds_n && io_cyc && lat_addr == PORT_VI) vi_n <= 1'b0;
    if (!as_n && st == ST_VI_ACK) vi_n <= 1'b1;
    if (lat_on && !lat_rw && ds_q && !ds_n && io_cyc && lat_addr == PORT_MI) mi_base <= 1'b0;
    if (!as_n && ad_drive) begin
      mq_on <= st == ST_INSTR_FETCH_FIRST && (mem[seg_ix(sn)][ad_out[15:1]] & 16'hFF0F) == 16'h7B0D;
      mq_ds <= 1'b0;
      mq_n  <= 0;
    end else if (mq_on) begin
      if (!ds_n) mq_ds <= 1'b1;
      if ((mq_ds || !ds_n) && clk_rise) mq_n <= mq_n + 1;
    end
    mq_hit_q <= mq_hit;
    mo_q <= mo_n;
    if (out_on && mo_q && !mo_n) n_mo <= n_mo + 1;
    if (out_on && mo_q && !mo_n && mq_hit_q) n_mo_at <= n_mo_at + 1;
    if (as_q && !as_n && st == ST_REFRESH) n_rf <= n_rf + 1;
    if (mixed && dut.t3_q) turbo <= 1'b1;
    // A read ends: count it by kind.
    if (!ds_q && ds_n && rd_cyc) begin
      if (lat_st == ST_INSTR_FETCH_FIRST || lat_st == ST_PROG_SPACE) n_fetch <= n_fetch + 1;
      else if (lat_st[3] && lat_sn == DATA && lat_addr == SLOW)       n_slow  <= n_slow + 1;
      else if (lat_st[3] && lat_sn == DATA)                           n_opnd  <= n_opnd + 1;
      else if (io_cyc)                                                n_io    <= n_io + 1;
      else if (ack_cyc)                                               n_ack   <= n_ack + 1;
    end
    // Garbage on AD as a read's T3 opens: the late window is live.
    if (rd_cyc && !ds_n && clk_rise && ad_in != word) n_late <= n_late + 1;
  end

  // ---- the program -----------------------------------------------------------

  task automatic put(input logic [6:0] s, input logic [15:0] a, input logic [15:0] w);
    mem[seg_ix(s)][a[15:1]] = w;
  endtask

  logic [15:0] prog [$] = '{
    16'h140E, 16'h0300, 16'h0800,         // LDL  RR14,#<<03>>0800
    16'h2109, 16'h8A00,                   // LD   R9,#8A00
    16'h7D9B,                             // LDCTL REFRESH,R9 (on)
    16'h1404, 16'h1200, 16'h0200,         // LDL  RR4,#<<12>>0200
    16'h2141,                             // LD   R1,@RR4
    16'h2040,                             // LDB  RH0,@RR4
    16'h6102, 16'h9200, 16'h0202,         // LD   R2,<<12>>0202 (long)
    16'h6103, 16'h1204,                   // LD   R3,<<12>>0004 (short)
    16'h0141,                             // ADD  R1,@RR4
    16'h3B64, PORT_IN,                    // IN   R6,#0040
    16'h1408, 16'h1200, SLOW,             // LDL  RR8,#<<12>>0300
    16'h2187,                             // LD   R7,@RR8 (two waits)
    16'h5F00, 16'h8500, 16'h0000,         // CALL <<05>>0000
    16'h2105, 16'h0003,                   // LD   R5,#3
    16'h7B5D,                             // MREQ R5 (/MI High)
    16'h7DB2,                             // LDCTL R11,FCW
    16'h3B06, PORT_MI,                    // OUT  #0030,R0 (/MI Low)
    16'h7B5D,                             // MREQ R5 (/MI Low)
    16'h7DC2,                             // LDCTL R12,FCW
    16'h3B06, PORT_VI,                    // OUT  #0020,R0 (raises /VI)
    16'h8D07, 16'h8D07,                   // NOP; NOP
    16'hE8FF                              // JR   $
  };

  task automatic load();
    int i;
    logic [15:0] p;
    for (i = 0; i < 4 * 32768; i++) mem[i / 32768][i % 32768] = 16'h0000;
    put(7'h00, 16'h0002, 16'hD000);       // FCW: segmented, system, VI enabled
    put(7'h00, 16'h0004, {1'b0, CODE, 8'h00});
    put(7'h00, 16'h0006, 16'h0100);
    put(7'h00, 16'h003A, 16'hC000);       // VI: FCW, then the PC per identifier
    put(7'h00, 16'h003C + {VEC[14:0], 1'b0}, {1'b0, CODE, 8'h00});
    put(7'h00, 16'h003E + {VEC[14:0], 1'b0}, 16'h0400);
    put(DATA, 16'h0202, 16'h2468);
    put(DATA, 16'h0004, 16'h3579);
    put(DATA, SLOW,     16'h7777);
    put(DATA, 16'h0200, 16'h1111);
    p = 16'h0100;
    foreach (prog[j]) begin
      put(CODE, p, prog[j]);
      p = p + 16'd2;
    end
    put(7'h05, 16'h0000, 16'h210D);       // LD   R13,#5555
    put(7'h05, 16'h0002, 16'h5555);
    put(7'h05, 16'h0004, 16'h9E08);       // RET
    put(CODE, 16'h0400, 16'h210A);        // LD   R10,#BEEF
    put(CODE, 16'h0402, 16'hBEEF);
    put(CODE, 16'h0404, 16'h7A00);        // HALT
  endtask


  // ---- run --------------------------------------------------------------------
  int unsigned fails = 0;
  task automatic ck(input bit ok, input string what);
    if (!ok) fails++;
    $display("  %s  %s", ok ? "PASS" : "FAIL", what);
  endtask

  initial begin
    string s, mode;
    int    n, i;
    if ($value$plusargs("half=%s", s)) begin
      n = 0;
      for (i = 0; i <= s.len(); i++) begin
        if (i == s.len() || s[i] == ",") begin
          if (n < 1) $fatal(1, "+half: counts must be 1 or more");
          halves.push_back(n);
          n = 0;
        end else begin
          n = n * 10 + (s[i] - "0");
        end
      end
    end else begin
      halves.push_back(2);
    end
    turbo  = $test$plusargs("turbo");
    normal = $test$plusargs("normal");
    trace  = $test$plusargs("trace");
    edge_only = $test$plusargs("edge");
    mixed  = $test$plusargs("mixed");
    unmix  = $test$plusargs("unmix");
    if (unmix) turbo = 1'b1;
    if (!$value$plusargs("only=%s", only)) only = "";
    load();
    if (unmix)       mode = "turbo, then the T3 fall alone";
    else if (turbo)  mode = "turbo";
    else if (normal) mode = {"normal memory, half ", s};
    else             mode = {"late read data", only.len() ? {" for ", only} : "", edge_only ? " before the fall" : "",
                             mixed ? ", then turbo" : "", ", half ", s.len() ? s : "2"};
    $display("tb_cpu_late_read: %s", mode);
    run = 1'b1;
    repeat (40) @(posedge mclk);
    reset_n = 1'b1;
    out_on  = 1'b1;
    for (i = 0; i < 20000 && !dut.halted; i++) @(posedge mclk);
    repeat (20) @(posedge mclk);

    ck(!(dut.check_q || dut.u_sequencer.check_q || dut.u_execute.check_q), "no simulation check flagged in the CPU");
    ck(dut.halted, "the handler's HALT is reached");
    ck(dut.u_regfile.r[0] == 16'h1100, $sformatf("LDB RH0,@RR4: R0 = %04h (1100)", dut.u_regfile.r[0]));
    ck(dut.u_regfile.r[13] == 16'h5555, $sformatf("CALL and RET across segments: R13 = %04h (5555)", dut.u_regfile.r[13]));
    ck(dut.u_regfile.r[11][6:5] == 2'b10 && dut.u_regfile.r[12][6:5] == 2'b00 && dut.u_regfile.r[5] == 16'h0000 && n_mo == 1 && n_mo_at == 1,
       $sformatf("MREQ: Z S %02b then %02b (10, 00), R5 counted to %04h (0000), /MO fell %0d (1), %0d on the rise ending T3 (1)",
                 dut.u_regfile.r[11][6:5], dut.u_regfile.r[12][6:5], dut.u_regfile.r[5], n_mo, n_mo_at));
    ck(n_rf > 0, $sformatf("refresh on: %0d refresh cycles", n_rf));
    ck(dut.u_regfile.r[1] == 16'h2222, $sformatf("LD R1,@RR4; ADD R1,@RR4: R1 = %04h (2222)", dut.u_regfile.r[1]));
    ck(dut.u_regfile.r[2] == 16'h2468, $sformatf("LD R2, long address: R2 = %04h (2468)", dut.u_regfile.r[2]));
    ck(dut.u_regfile.r[3] == 16'h3579, $sformatf("LD R3, short address: R3 = %04h (3579)", dut.u_regfile.r[3]));
    ck(dut.u_regfile.r[6] == IO_WORD, $sformatf("IN R6: R6 = %04h (%04h)", dut.u_regfile.r[6], IO_WORD));
    ck(dut.u_regfile.r[7] == 16'h7777, $sformatf("LD R7 with waits: R7 = %04h (7777)", dut.u_regfile.r[7]));
    ck(dut.u_regfile.r[10] == 16'hBEEF, $sformatf("the identifier's handler ran: R10 = %04h (BEEF)", dut.u_regfile.r[10]));
    ck(dut.u_regfile.r[15] == 16'h07F8 && mem[1][16'h07F8 >> 1] == VEC,
       $sformatf("the identifier pushed: SP %04h (07F8), word %04h (%04h)",
                 dut.u_regfile.r[15], mem[1][16'h07F8 >> 1], VEC));
    ck(n_fetch >= 20 && n_opnd == 5 && n_io == 1 && n_ack == 1 && n_slow == 1 && n_tw == 2,
       $sformatf("reads: %0d fetch, %0d operand, %0d I/O, %0d acknowledge, %0d with %0d waits",
                 n_fetch, n_opnd, n_io, n_ack, n_slow, n_tw));
    if (!turbo && !normal)
      ck(n_late > 0, $sformatf("garbage on AD at %0d read T3 rises", n_late));
    if (fails == 0) $display("RESULT PASS tb_cpu_late_read: %s", mode);
    else            $display("RESULT FAIL tb_cpu_late_read: %s: %0d checks failed", mode, fails);
    $finish;
  end

endmodule

`default_nettype wire
