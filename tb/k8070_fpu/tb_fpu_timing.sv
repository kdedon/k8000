// tb_fpu_timing -- Z8070 pin-protocol conformance, from the Preliminary
// Product Specification (1985 Data Book, printed pp.531-558).
//
// Not a vector replay: the bench drives the pins as a Z8000 system would
// and checks what the specification says the chip must do. One posedge of
// `clk` is one master clock; CLK.I and CLK.D pulse every other one.
//
// Run: make test-fpu-timing

`default_nettype none

module tb_fpu_timing;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic        clki_rise = 1'b0, clki_fall = 1'b0, clkd_rise = 1'b0;
  logic        reset_n   = 1'b1;
  logic [15:0] ad_in     = 16'h0000;
  logic        as_n      = 1'b1;
  logic        ds_n      = 1'b1;
  logic        r_w       = 1'b1;
  logic        b_w       = 1'b0;
  logic        n_s       = 1'b0;
  logic [3:0]  st        = 4'h0;
  logic [6:0]  sn        = 7'h00;
  logic        busack_n  = 1'b1;
  logic        abort_n   = 1'b1;
  logic        iei       = 1'b1;
  logic [1:0]  id        = 2'd0;
  logic [1:0]  opt       = 2'b11;

  logic [15:0] ad_out;
  logic        ad_drive, bsy_n, int_n, ieo;

  z8070_fpu dut (
    .clk(clk), .clki_rise(clki_rise), .clki_fall(clki_fall), .clkd_rise(clkd_rise),
    .reset_n(reset_n),
    .ad_in(ad_in), .ad_out(ad_out), .ad_drive(ad_drive),
    .as_n(as_n), .ds_n(ds_n), .r_w(r_w), .b_w(b_w), .n_s(n_s), .st(st), .sn(sn),
    .busack_n(busack_n), .abort_n(abort_n),
    .bsy_n(bsy_n), .int_n(int_n), .iei(iei), .ieo(ieo),
    .id(id), .opt(opt)
  );

  // Fast-clock probes: a promotion in the done clock seen, the Data
  // Processor starts counted, /ABORT Low for the clock the promoted start
  // waits in (ab_at 1) or is given in (ab_at 2).
  int unsigned npwait, pw0;
  int unsigned nstart, ns0;
  int ab_at = 0;
  always @(negedge clk) begin
    if (ab_at == 1)      abort_n = !dut.u_ip.pwait_q;
    else if (ab_at == 2) abort_n = !dut.u_ip.pstart_q;
    #1;
    if (dut.u_ip.pwait_q) npwait = npwait + 1;
    if (dut.u_ip.dp_start) nstart = nstart + 1;
  end

  int unsigned checks, fails;
  task automatic ck(input bit ok, input string name, input string cite, input string detail);
    checks = checks + 1;
    if (ok) $display("  PASS  %s", name);
    else begin
      fails = fails + 1;
      $display("  FAIL  %s", name);
      $display("          %s", detail);
      $display("          spec: %s", cite);
    end
  endtask

  // One CLK.I period: rise, then fall; CLK.D tied to CLK.I. bsy_fall is
  // /BSY in the master clock of the fall, where the CPU samples STOP.
  // fast: one master clock with every pulse High, as a board that clocks
  // CLK.I and CLK.D at the master clock.
  logic bsy_fall;
  bit   fast = 1'b0;
  task automatic clk_cycle();
    if (fast) begin
      clki_rise = 1'b1; clki_fall = 1'b1; clkd_rise = 1'b1; @(posedge clk); #1 bsy_fall = bsy_n;
      return;
    end
    clki_rise = 1'b1; clkd_rise = 1'b1; @(posedge clk);
    clki_rise = 1'b0; clkd_rise = 1'b0; @(posedge clk);
    clki_fall = 1'b1;                   @(posedge clk); #1 bsy_fall = bsy_n;
    clki_fall = 1'b0;                   @(posedge clk);
  endtask

  // One bus cycle as the CPU runs it: /AS for one CLK.I period with the
  // status, then /DS Low for two with `data` on AD. `late`, when not
  // equal to `data`, replaces AD after the CLK.I fall inside /DS and before
  // the /DS rise. int_seen records /INT Low at any point while /DS is Low.
  bit int_seen;
  task automatic bus_cycle(input logic [3:0] status, input logic [15:0] data,
                           input logic [15:0] late);
    int_seen = 1'b0;
    st = status; r_w = 1'b1; ad_in = 16'h0000; as_n = 1'b0;
    clk_cycle();
    as_n = 1'b1;
    clk_cycle();
    ad_in = data; ds_n = 1'b0;
    clk_cycle(); #1; if (!int_n) int_seen = 1'b1;
    clk_cycle(); #1; if (!int_n) int_seen = 1'b1;
    ad_in = late;                     // no CLK.I edge until /DS rises
    repeat (2) @(posedge clk);
    #1; if (!int_n) int_seen = 1'b1;
    ds_n = 1'b1;
    clk_cycle(); #1;
  endtask

  // One master clock at a time, sampled just after each edge, for the
  // drive and /BSY checks. Phases: 0 /AS Low, 1 /AS High before /DS,
  // 2 /DS Low, 3 after the /DS rise.
  bit          drv[4], drv_all[4], bsy_lo_all[4], bsy_hi_all[4], ieo_lo[4], ieo_hi[4];
  logic [15:0] ad_seen;

  task automatic sample_clk(input int ph, input bit rise, input bit fall);
    clki_rise = rise; clkd_rise = rise; clki_fall = fall;
    @(posedge clk); #1;
    if (ad_drive) begin drv[ph] = 1'b1; ad_seen = ad_out; end
    else drv_all[ph] = 1'b0;
    if (bsy_n) bsy_lo_all[ph] = 1'b0; else bsy_hi_all[ph] = 1'b0;
    if (ieo) ieo_hi[ph] = 1'b1; else ieo_lo[ph] = 1'b1;
  endtask

  task automatic sample_cycle(input int ph);
    sample_clk(ph, 1'b1, 1'b0);
    sample_clk(ph, 1'b0, 1'b0);
    sample_clk(ph, 1'b0, 1'b1);
    sample_clk(ph, 1'b0, 1'b0);
    clki_fall = 1'b0;
  endtask

  task automatic sample_reset();
    for (int p = 0; p < 4; p++) begin
      drv[p] = 1'b0; drv_all[p] = 1'b1; bsy_lo_all[p] = 1'b1; bsy_hi_all[p] = 1'b1;
      ieo_lo[p] = 1'b0; ieo_hi[p] = 1'b0;
    end
    ad_seen = 16'hxxxx;
  endtask

  // A data cycle: write = 1 is an EPU write (R/W Low), the FPU's word out
  // for 1010; for 1110 the CPU reads with R/W High.
  task automatic data_cycle(input logic [3:0] status, input bit write);
    sample_reset();
    st = status; r_w = ~write; ad_in = 16'h0000; as_n = 1'b0;
    sample_cycle(0);
    as_n = 1'b1;
    sample_cycle(1);
    ds_n = 1'b0;
    sample_cycle(2); sample_cycle(2);
    ds_n = 1'b1;
    sample_cycle(3);
    r_w = 1'b1;
  endtask

  bit bsy_all_hi, bsy_all_lo;
  task automatic watch_bsy(input int cycles);
    bsy_all_hi = 1'b1; bsy_all_lo = 1'b1;
    repeat (cycles) begin
      clk_cycle(); #1;
      if (!bsy_n) bsy_all_hi = 1'b0; else bsy_all_lo = 1'b0;
    end
    sample_reset();
  endtask

  task automatic poke_fflags(input logic [31:0] v);
    force dut.u_ip.fflags_q = v;
    @(posedge clk);
    release dut.u_ip.fflags_q;
    #1;
  endtask

  task automatic reset_with_sc(input logic [31:0] sc);
    reset_n = 1'b0; clk_cycle();
    reset_n = 1'b1; clk_cycle();
    force dut.u_ip.sc_q = sc;
    @(posedge clk);
    release dut.u_ip.sc_q;
    clk_cycle(); #1;
  endtask

  localparam logic [3:0]  ST_RFSH = 4'h1, ST_DMEM = 4'h8, ST_PROG = 4'hC, ST_IF1 = 4'hD;
  localparam logic [3:0]  ST_EDATA = 4'hA, ST_EPUX = 4'hE;
  localparam logic [3:0]  ST_NMIA = 4'h5, ST_NVIA = 4'h6, ST_VIA = 4'h7;
  localparam logic [31:0] SC_ACK_VI = 32'h0003_0000, SC_SV = 32'h0000_0200;
  localparam logic [31:0] SC_NV = 32'h0000_0800, SC_DLC = 32'h0000_1000;
  localparam logic [31:0] SC_MIE  = 32'h0000_8000;
  localparam logic [31:0] SC_EPUIDS1 = 32'h2000_0000;  // ID 1 invalid
  localparam logic [15:0] IF1_ID0 = 16'h8E04;          // internal, EPU 0
  localparam logic [15:0] IF1_ID1 = 16'h8E05;          // internal, EPU 1
  localparam logic [15:0] W2_NONE = 16'hC0F0;          // code 3F: no row
  localparam logic [15:0] W2_FADD = 16'h4080;          // FADD F0,F0
  localparam logic [31:0] SC_INTERMEDIATE = 32'h0008_0000;
  localparam logic [15:0] IF1_STORE = 16'h0F0C;        // memory <- EPU, EPU 0
  localparam logic [15:0] IF1_INT   = 16'h8E04;        // internal, EPU 0
  localparam logic [15:0] IF1_CTL_SC_OUT = 16'h8F00;   // CPU <- EPU, select 0 (SC)
  localparam logic [15:0] IF1_FLDCTLB_G4 = 16'h8E40;   // FCW <- EPU, group 4
  localparam logic [15:0] W2_CTL_FFLAGS_MEM = 16'hC401; // FLDCTL, select 4, 2 words
  localparam logic [15:0] W2_CTL_SC_CPU = 16'hC001;    // FLDCTL, 2 words
  localparam logic [15:0] W2_FLDCTLB = 16'hC110;       // FLDCTLB
  localparam logic [15:0] W2_FSETFLG_01 = 16'hC130;    // FSETFLG, list 01
  localparam logic [15:0] W2_FLD_F5_MEM = 16'h8501;    // FLD F5, 2 words (single)
  localparam logic [15:0] IF1_LD_F2_MEM = 16'h0F04;    // EPU <- memory, EPU 0
  localparam logic [15:0] W2_FLD_F2_MEM = 16'h8201;    // FLD F2, 2 words (single)
  localparam logic [15:0] W2_FDIV_F0_F1 = 16'h41A0;    // FDIV F0,F1
  localparam logic [79:0] ONE   = 80'h3FFF_8000_0000_0000_0000;
  localparam logic [79:0] THREE = 80'h4000_C000_0000_0000_0000;
  localparam logic [79:0] FIVE  = 80'h4001_A000_0000_0000_0000;

  bit idle_ok;
  task automatic watch_idle(input int cycles);
    idle_ok = 1'b1;
    repeat (cycles) begin
      clk_cycle();
      #1;
      if (ad_drive || !bsy_n || !int_n || ieo != iei) idle_ok = 1'b0;
    end
  endtask

  initial begin
    checks = 0; fails = 0;
    $display("tb_fpu_timing -- Z8070 pin protocol");
    $display("");

    $display("[1] reset: idle pins, SC.ID from the ID pins");
    id = 2'd2; reset_n = 1'b0;
    watch_idle(4);
    ck(idle_ok, "pins idle while /RESET is Low",
       "p.542 RESET forces the power-on condition; p.544 AD 3-state",
       "ad_drive, /BSY Low, /INT Low or IEO != IEI during reset");
    reset_n = 1'b1;
    watch_idle(4);
    ck(idle_ok, "pins idle after reset with the bus quiet",
       "p.542 BSY, INT; p.544 AD supplied by the CPU",
       "ad_drive, /BSY Low, /INT Low or IEO != IEI after reset");
    ck(dut.u_ip.sc_q == {4'h0, 2'd2, 26'd0}, "SC is 0 but SC.ID = ID pins (ID = 2)",
       "p.542 note: after a reset all bits in USER, FFLAG and SYS are 0 except the ID bits in SYS, which store the ID pins",
       $sformatf("SC = %08h", dut.u_ip.sc_q));
    ck(dut.u_ip.user_q == 32'd0 && dut.u_ip.fflags_q == 32'd0, "USER and FFLAGS are 0",
       "p.542 note",
       $sformatf("USER = %08h, FFLAGS = %08h", dut.u_ip.user_q, dut.u_ip.fflags_q));

    id = 2'd1;
    clk_cycle(); #1;
    ck(dut.u_ip.sc_q[27:26] == 2'd2, "SC.ID holds when the ID pins change after reset",
       "p.542 ID0-ID1 establish the EPU ID during reset",
       $sformatf("SC.ID = %0d, want 2", dut.u_ip.sc_q[27:26]));
    reset_n = 1'b0; clk_cycle(); reset_n = 1'b1; clk_cycle(); #1;
    ck(dut.u_ip.sc_q[27:26] == 2'd1, "a second reset takes the new ID (ID = 1)",
       "p.542 ID0-ID1 establish the EPU ID during reset",
       $sformatf("SC.ID = %0d, want 1", dut.u_ip.sc_q[27:26]));

    iei = 1'b0; #1;
    ck(!ieo, "IEO Low with IEI Low", "p.542 IEO is High only if IEI is High",
       $sformatf("ieo = %0b", ieo));
    iei = 1'b1; #1;
    ck(ieo, "IEO High with IEI High and nothing under service",
       "p.542 IEO", $sformatf("ieo = %0b", ieo));

    $display("");
    $display("[2] snoop: IF1 taken in /DS, word 2 the next 1100, /BUSACK ignored");
    id = 2'd0;
    reset_with_sc(SC_MIE | SC_EPUIDS1);
    bus_cycle(ST_IF1, IF1_ID1, IF1_ID1);
    ck(!int_seen && !int_n, "IF1 for a flagged ID: /INT Low after the /DS rise, not before",
       "p.534 EPUIDS: an instruction specifying an ID whose bit is 1 causes an Invalid EPU ID interrupt; p.545 the Z8070 captures the IF1 word",
       $sformatf("/INT Low during /DS = %0b, after = %0b", int_seen, !int_n));
    ck(dut.u_ip.sc_q[25:24] == 2'd2 && dut.u_ip.sc_q[14], "SC.IR = 10 (Invalid EPU ID), SC.IP set",
       "p.534 SC IR 10 Invalid EPU id, IP", $sformatf("SC = %08h", dut.u_ip.sc_q));

    reset_with_sc(SC_MIE | SC_EPUIDS1);
    bus_cycle(ST_IF1, IF1_ID1, 16'h0000);
    ck(!int_n, "IF1 word is AD at the CLK.I fall in /DS: a later change is not seen",
       "p.546 memory supplies the data before the falling edge of the clock in the middle of T3 (the same edge for IF1: interpretation)",
       "AD 8E05 at the fall, 0000 before the /DS rise: no Invalid EPU ID request");
    reset_with_sc(SC_MIE | SC_EPUIDS1);
    bus_cycle(ST_IF1, 16'h0000, IF1_ID1);
    ck(int_n, "AD changed after the CLK.I fall is not the IF1 word",
       "p.546", "AD 0000 at the fall, 8E05 before the /DS rise: request raised");

    reset_with_sc(SC_MIE);
    bus_cycle(ST_IF1, IF1_ID0, IF1_ID0);
    bus_cycle(ST_RFSH, W2_NONE, W2_NONE);
    bus_cycle(ST_DMEM, W2_NONE, W2_NONE);
    ck(int_n, "refresh and memory cycles after IF1 are not word 2",
       "p.545 the CPU's next non-refresh transaction fetches the second word with ST 1100",
       "a 0001 or 1000 cycle carrying an invalid code raised the request");
    bus_cycle(ST_PROG, W2_NONE, W2_NONE);
    ck(!int_seen && !int_n, "the next 1100 is word 2: invalid code raises /INT at its /DS rise",
       "p.534 IR 01 Invalid opcode; p.545 word 2 determines the operation",
       $sformatf("/INT Low during /DS = %0b, after = %0b", int_seen, !int_n));
    ck(dut.u_ip.sc_q[25:24] == 2'd1, "SC.IR = 01 (Invalid opcode)", "p.534 SC IR",
       $sformatf("SC = %08h", dut.u_ip.sc_q));

    reset_with_sc(SC_MIE);
    bus_cycle(ST_IF1, IF1_ID0, IF1_ID0);
    bus_cycle(ST_PROG, W2_FADD, W2_FADD);
    ck(int_n && dut.u_ip.sc_q[23], "a valid word 2 raises nothing and sets SC.U",
       "p.534 SC U", $sformatf("SC = %08h, /INT = %0b", dut.u_ip.sc_q, int_n));

    reset_with_sc(SC_MIE);
    bus_cycle(ST_IF1, IF1_ID1, IF1_ID1);
    bus_cycle(ST_PROG, W2_NONE, W2_NONE);
    ck(int_n, "another EPU's instruction: its word 2 is not decoded",
       "p.545 the EPU whose ID bits match captures word 2",
       "an invalid word 2 after IF1 for ID 1 raised the request on EPU 0");

    reset_with_sc(SC_MIE | SC_EPUIDS1);
    busack_n = 1'b0;
    bus_cycle(ST_IF1, IF1_ID1, IF1_ID1);
    ck(int_n, "/BUSACK Low: a flagged-ID IF1 is not seen",
       "p.545 BUSACK Low: the EPU 3-states AD until it goes High (cycles ignored: interpretation)", "Invalid EPU ID raised");
    bus_cycle(ST_IF1, IF1_ID0, IF1_ID0);
    bus_cycle(ST_PROG, W2_NONE, W2_NONE);
    ck(int_n, "/BUSACK Low: IF1 and word 2 are not seen",
       "p.545", "Invalid opcode raised");
    busack_n = 1'b1;
    bus_cycle(ST_PROG, W2_NONE, W2_NONE);
    ck(int_n, "the IF1 under /BUSACK started nothing",
       "p.545", "a 1100 after /BUSACK rose was decoded as word 2");
    bus_cycle(ST_IF1, IF1_ID0, IF1_ID0);
    bus_cycle(ST_PROG, W2_NONE, W2_NONE);
    ck(!int_n, "/BUSACK High again: IF1 and word 2 are seen",
       "p.545", "no Invalid opcode request");

    $display("");
    $display("[3] drive windows, the flag byte, the /BSY store wait");
    reset_with_sc(SC_MIE);
    poke_fflags(32'h1234_5678);
    bus_cycle(ST_IF1, IF1_STORE, IF1_STORE);
    bus_cycle(ST_PROG, W2_CTL_FFLAGS_MEM, W2_CTL_FFLAGS_MEM);
    data_cycle(ST_EDATA, 1'b1);
    ck(!drv[0] && drv_all[1] && drv_all[2] && !drv[3] && ad_seen == 16'h1234,
       "memory write: AD driven from the /AS rise to the /DS rise, word 1 first",
       "p.546 for a write the Z8070 places the data on the bus when AS rises",
       $sformatf("driven /AS Low %0b, /AS-/DS all %0b, /DS all %0b, after /DS %0b, AD %04h",
                 drv[0], drv_all[1], drv_all[2], drv[3], ad_seen));
    busack_n = 1'b0;
    data_cycle(ST_EDATA, 1'b1);
    ck(!drv[0] && !drv[1] && !drv[2] && !drv[3], "/BUSACK Low: a 1010 write is not driven",
       "p.545 BUSACK Low: the EPU 3-states AD until it goes High",
       "AD driven in another master's cycle");
    busack_n = 1'b1;
    data_cycle(ST_EDATA, 1'b1);
    ck(drv_all[1] && drv_all[2] && !drv[3] && ad_seen == 16'h5678,
       "/BUSACK High again: the second word follows, unconsumed by the foreign cycle",
       "p.545", $sformatf("AD %04h, driven %0b", ad_seen, drv_all[2]));
    data_cycle(ST_EDATA, 1'b1);
    ck(!drv[1] && !drv[2], "the last word ends the transfer",
       "p.546 the CPU runs n data cycles", "AD driven in a third 1010 write");

    bus_cycle(ST_IF1, IF1_CTL_SC_OUT, IF1_CTL_SC_OUT);
    bus_cycle(ST_PROG, W2_CTL_SC_CPU, W2_CTL_SC_CPU);
    data_cycle(ST_EPUX, 1'b0);
    ck(!drv[0] && !drv[1] && drv_all[2] && !drv[3] && ad_seen == 16'h0080,
       "1110 read: AD driven while /DS is Low only (SC 31:16, SC.U set)",
       "p.548 Fig 17 CPU-EPU transfer: I/O timing, the data while DS is Low",
       $sformatf("driven /AS Low %0b, /AS-/DS %0b, /DS all %0b, after /DS %0b, AD %04h",
                 drv[0], drv[1], drv_all[2], drv[3], ad_seen));
    data_cycle(ST_EPUX, 1'b0);
    ck(drv_all[2] && ad_seen == 16'h8000, "second 1110 read: SC 15:0",
       "p.534 SC", $sformatf("AD %04h", ad_seen));

    poke_fflags(32'h0084_0000);   // compare flags FC and FH
    bus_cycle(ST_IF1, IF1_FLDCTLB_G4, IF1_FLDCTLB_G4);
    bus_cycle(ST_PROG, W2_FLDCTLB, W2_FLDCTLB);
    data_cycle(ST_EPUX, 1'b0);
    ck(drv_all[2] && !drv[1] && !drv[3] && ad_seen == 16'h0084,
       "flag byte on AD7-0 in FCW order (C ... H in bits 7:2), 00 on AD15-8",
       "p.1004 FC FZ FS FV FD FH correspond to the FCW's C Z S P/V D H; AD15-8 00 assumed",
       $sformatf("AD %04h", ad_seen));

    bus_cycle(ST_IF1, IF1_INT, IF1_INT);
    bus_cycle(ST_PROG, W2_FSETFLG_01, W2_FSETFLG_01);
    ck(dut.u_ip.fflags_q[7:0] == 8'h01, "after the transfers the IP is idle: the next IF1 runs",
       "p.545 each extended instruction starts with its IF1",
       $sformatf("FFLAGS = %08h", dut.u_ip.fflags_q));

    reset_with_sc(SC_MIE);
    bus_cycle(ST_IF1, IF1_STORE, IF1_STORE);
    bus_cycle(ST_PROG, W2_FLD_F5_MEM, W2_FLD_F5_MEM);
    #1;
    ck(!bsy_n, "No Overlap: /BSY Low from word 2 while the Data Processor converts",
       "p.535 No Overlap: BSY is asserted while the Z8070 executes", $sformatf("/BSY = %0b", bsy_n));

    reset_with_sc(SC_MIE | SC_INTERMEDIATE);
    bus_cycle(ST_IF1, IF1_STORE, IF1_STORE);
    bus_cycle(ST_PROG, W2_FLD_F5_MEM, W2_FLD_F5_MEM);
    watch_bsy(3);
    ck(bsy_all_lo, "Intermediate: a store holds /BSY Low from word 2",
       "patent US 4,648,034 FIG. 7: a decoded store forces the busy term", "/BSY High before the data cycle");
    st = ST_EDATA; r_w = 1'b0; as_n = 1'b0;
    sample_cycle(0);
    as_n = 1'b1;
    sample_cycle(1);
    ds_n = 1'b0;
    sample_cycle(2); sample_cycle(2);
    ck(bsy_lo_all[0] && bsy_lo_all[1] && bsy_lo_all[2] && !drv[1] && !drv[2],
       "store wait: /BSY Low through the store's data cycle, AD not driven",
       "p.542 BSY is used as a Wait signal during stores; p.546 WAIT extends the transfer (to /WAIT: assumed)",
       $sformatf("/BSY Low in /AS %0b, after /AS rise %0b, in /DS %0b, driven %0b",
                 bsy_lo_all[0], bsy_lo_all[1], bsy_lo_all[2], drv[1] | drv[2]));
    // CLK.I periods, one master clock at a time, until the Data
    // Processor's rounding is done; the word's value is not checked.
    for (int m = 0; !bsy_n && m < 400; m++) begin
      clki_rise = (m % 4 == 0); clkd_rise = (m % 4 == 0); clki_fall = (m % 4 == 2);
      @(posedge clk); #1;
    end
    clki_rise = 1'b0; clkd_rise = 1'b0; clki_fall = 1'b0;
    sample_reset();
    ck(bsy_n && ad_drive, "word ready: /BSY High and AD driven in the next master clock",
       "p.542", $sformatf("/BSY = %0b, drive = %0b", bsy_n, ad_drive));
    sample_cycle(2);
    ds_n = 1'b1;
    sample_cycle(3);
    ck(drv_all[2] && !drv[3] && bsy_hi_all[3], "the waited word ends at the /DS rise",
       "p.546", $sformatf("driven to /DS rise %0b, after %0b", drv_all[2], drv[3]));
    data_cycle(ST_EDATA, 1'b1);
    ck(drv_all[1] && drv_all[2] && bsy_hi_all[1] && bsy_hi_all[2],
       "second store word: no wait, driven from the /AS rise",
       "p.546", $sformatf("driven %0b %0b, /BSY High %0b %0b", drv_all[1], drv_all[2],
                          bsy_hi_all[1], bsy_hi_all[2]));
    bus_cycle(ST_IF1, IF1_INT, IF1_INT);
    bus_cycle(ST_PROG, W2_FSETFLG_01, W2_FSETFLG_01);
    ck(dut.u_ip.fflags_q[7:0] == 8'h01, "after the store the IP is idle: the next IF1 runs",
       "p.545", $sformatf("FFLAGS = %08h", dut.u_ip.fflags_q));

    $display("");
    $display("[4] /BSY at the STOP samples: the CLK.I fall before IF1 and before word 2");
    // bus_cycle ends with one CLK.I period after the /DS rise: bsy_fall is
    // /BSY at the fall the CPU samples before its next cycle.
    reset_with_sc(32'h0);
    dut.u_dp.f_mem[0] = ONE; dut.u_dp.f_mem[1] = THREE;
    bus_cycle(ST_IF1, IF1_STORE, IF1_STORE);
    ck(bsy_fall, "No Overlap: /BSY High at the sample before a store's word 2",
       "TM p.9-15 STOP sampled before word 2; p.535 nothing executing", "/BSY Low");
    bus_cycle(ST_PROG, W2_FLD_F5_MEM, W2_FLD_F5_MEM);
    ck(!bsy_fall, "No Overlap: /BSY Low at the sample after a store's word 2",
       "p.535 No Overlap stops the CPU while the Z8070 processes", "/BSY High");
    while (!bsy_n) clk_cycle();
    data_cycle(ST_EDATA, 1'b1); data_cycle(ST_EDATA, 1'b1);
    bus_cycle(ST_IF1, IF1_INT, IF1_INT);
    bus_cycle(ST_PROG, W2_FDIV_F0_F1, W2_FDIV_F0_F1);
    ck(!bsy_fall, "No Overlap: /BSY Low at the sample before the next IF1 while FDIV runs",
       "p.535", "/BSY High");
    while (!bsy_n) clk_cycle();
    clk_cycle();
    ck(bsy_fall && !dut.dp_busy, "No Overlap: /BSY High at the first sample after done", "p.535",
       "/BSY Low");

    reset_with_sc(SC_INTERMEDIATE);
    bus_cycle(ST_IF1, IF1_INT, IF1_INT);
    bus_cycle(ST_PROG, W2_FDIV_F0_F1, W2_FDIV_F0_F1);
    ck(bsy_fall, "Intermediate: /BSY High at the sample after word 2, nothing queued",
       "p.535 the CPU continues while an operation proceeds", "/BSY Low");
    bus_cycle(ST_IF1, IF1_LD_F2_MEM, IF1_LD_F2_MEM);
    ck(bsy_fall && dut.u_ip.pend_q == 2'd1, "Intermediate: /BSY High at the sample before the queued word 2",
       "patent FIG. 7: /BSY = V1, set once the instruction and its data are queued", "/BSY Low");
    bus_cycle(ST_PROG, W2_FLD_F2_MEM, W2_FLD_F2_MEM);
    ck(bsy_fall, "Intermediate: /BSY High after the queued word 2, operands still due", "patent FIG. 7",
       "/BSY Low");
    bus_cycle(ST_EDATA, 16'h40A0, 16'h40A0);
    ck(bsy_fall, "Intermediate: /BSY High with one of two queued operand words in", "patent FIG. 7",
       "/BSY Low");
    bus_cycle(ST_EDATA, 16'h0000, 16'h0000);
    ck(!bsy_fall && dut.dp_busy, "Intermediate: /BSY Low at the sample before the next IF1, queue complete",
       "p.535 stops the CPU after a second instruction is transferred; patent V1", "/BSY High");
    while (!bsy_n) clk_cycle();
    clk_cycle();
    ck(bsy_fall && dut.u_ip.pend_q == 2'd0, "Intermediate: /BSY High at the first sample after the queued load starts",
       "patent: V1 clears when the Data Processor takes the entry", "/BSY Low");
    repeat (20) clk_cycle();
    #1;
    ck(dut.u_dp.f_mem[2] == FIVE, "the queued load wrote F2", "p.535 instruction 2 queued",
       $sformatf("F2 %020h", dut.u_dp.f_mem[2]));

    // CLK.I and CLK.D every master clock: a queued instruction starts in
    // its predecessor's done clock and its Data Processor reads in the next.
    reset_with_sc(SC_INTERMEDIATE);
    fast = 1'b1;
    dut.u_dp.f_mem[1] = 80'h4000_8000_0000_0000_0000;  // 2.0
    dut.u_dp.f_mem[2] = ONE;
    bus_cycle(ST_IF1, 16'h8E14, 16'h8E14);              // FMUL F1,F1
    bus_cycle(ST_PROG, 16'h41B0, 16'h41B0);
    bus_cycle(ST_IF1, 16'h8E24, 16'h8E24);              // FADD F2,F1, queued
    bus_cycle(ST_PROG, 16'h4180, 16'h4180);
    repeat (200) clk_cycle();
    ck(dut.u_dp.f_mem[2] == FIVE, "fast clocks: the queued FADD reads F2, then the F1 FMUL wrote",
       "p.535 execution appears linear", $sformatf("F2 %020h", dut.u_dp.f_mem[2]));
    reset_with_sc(SC_INTERMEDIATE);
    dut.u_dp.f_mem[3] = 80'h0;
    bus_cycle(ST_IF1, IF1_LD_F2_MEM, IF1_LD_F2_MEM);    // FLD F3, double 1.0
    bus_cycle(ST_PROG, 16'h8303, 16'h8303);
    bus_cycle(ST_EDATA, 16'h3FF0, 16'h3FF0);
    repeat (3) bus_cycle(ST_EDATA, 16'h0000, 16'h0000);
    bus_cycle(ST_IF1, IF1_LD_F2_MEM, IF1_LD_F2_MEM);    // FLD F4, double 3.0, queued
    bus_cycle(ST_PROG, 16'h8403, 16'h8403);
    bus_cycle(ST_EDATA, 16'h4008, 16'h4008);
    repeat (3) bus_cycle(ST_EDATA, 16'h0000, 16'h0000);
    bus_cycle(ST_IF1, 16'h8E34, 16'h8E34);              // FDIV F3,F4, queued
    bus_cycle(ST_PROG, 16'h44A0, 16'h44A0);
    repeat (200) clk_cycle();
    ck(dut.u_dp.f_mem[3] == 80'h3FFD_AAAA_AAAA_AAAA_AAAB,
       "fast clocks: the queued FDIV reads F3, then the F4 the queued load wrote",
       "p.535 execution appears linear", $sformatf("F3 %020h", dut.u_dp.f_mem[3]));
    reset_with_sc(SC_INTERMEDIATE);
    dut.u_dp.f_mem[1] = 80'h4000_8000_0000_0000_0000;  // 2.0
    dut.u_dp.f_mem[2] = ONE;
    bus_cycle(ST_IF1, 16'h8E14, 16'h8E14);              // FMUL F1,F1
    bus_cycle(ST_PROG, 16'h41B0, 16'h41B0);
    bus_cycle(ST_IF1, IF1_LD_F2_MEM, IF1_LD_F2_MEM);    // FLD F2, single 5.0, queued
    bus_cycle(ST_PROG, W2_FLD_F2_MEM, W2_FLD_F2_MEM);
    bus_cycle(ST_EDATA, 16'h40A0, 16'h40A0);
    pw0 = npwait;
    bus_cycle(ST_EDATA, 16'h0000, 16'h0000);
    repeat (200) clk_cycle();
    ck(npwait != pw0 && dut.u_dp.f_mem[2] == FIVE && dut.u_dp.f_mem[1] == 80'h4001_8000_0000_0000_0000,
       "fast clocks: a queued load started in the done clock writes F2",
       "p.535 instruction 2 queued", $sformatf("promoted at done %0b, F2 %020h, F1 %020h", npwait != pw0,
       dut.u_dp.f_mem[2], dut.u_dp.f_mem[1]));
    reset_with_sc(SC_INTERMEDIATE);
    dut.u_dp.f_mem[1] = 80'h4000_8000_0000_0000_0000;
    pw0 = npwait;
    bus_cycle(ST_IF1, 16'h8E14, 16'h8E14);              // FMUL F1,F1
    bus_cycle(ST_PROG, 16'h41B0, 16'h41B0);
    bus_cycle(ST_IF1, IF1_STORE, IF1_STORE);            // FST F1 double, queued
    bus_cycle(ST_PROG, 16'h8103, 16'h8103);
    for (int i = 0; i < 200 && dut.u_ip.state_q != 3'd4; i++) clk_cycle();
    ck(npwait != pw0 && dut.u_ip.state_q == 3'd4 && dut.u_ip.img[79:16] == 64'h4010_0000_0000_0000,
       "fast clocks: a queued store started in the done clock sources the F1 FMUL wrote",
       "p.535 execution appears linear", $sformatf("promoted at done %0b, state %0d, words %016h",
       npwait != pw0, dut.u_ip.state_q, dut.u_ip.img[79:16]));
    for (int a = 1; a <= 2; a++) begin
      reset_with_sc(SC_INTERMEDIATE);
      dut.u_dp.f_mem[1] = 80'h4000_8000_0000_0000_0000;
      dut.u_dp.f_mem[2] = ONE;
      bus_cycle(ST_IF1, 16'h8E14, 16'h8E14);            // FMUL F1,F1
      bus_cycle(ST_PROG, 16'h41B0, 16'h41B0);
      bus_cycle(ST_IF1, 16'h8E24, 16'h8E24);            // FADD F2,F1, queued
      bus_cycle(ST_PROG, 16'h4180, 16'h4180);
      ns0 = nstart; pw0 = npwait; ab_at = a;
      repeat (200) clk_cycle();
      ab_at = 0; abort_n = 1'b1;
      ck(npwait != pw0 && nstart == ns0 && dut.u_dp.f_mem[2] == ONE && dut.u_ip.state_q == 3'd0,
         a == 1 ? "fast clocks: /ABORT in the read clock drops the queued FADD unstarted" :
                  "fast clocks: /ABORT in the start clock drops the queued FADD unstarted",
         "p.544 /ABORT causes an instruction abort", $sformatf("starts %0d, F2 %020h, state %0d", nstart - ns0, dut.u_dp.f_mem[2],
         dut.u_ip.state_q));
    end
    // FRDIV and FRVSUB unpack the source first, then Fd.
    for (int q = 0; q < 2; q++)
      for (int m = 0; m < 2; m++) begin
        reset_with_sc(SC_INTERMEDIATE);
        dut.u_dp.f_mem[1] = 80'h4000_8000_0000_0000_0000;
        dut.u_dp.f_mem[3] = ONE;
        dut.u_dp.f_mem[4] = THREE;
        pw0 = npwait;
        if (q == 1) begin
          bus_cycle(ST_IF1, 16'h8E14, 16'h8E14);        // FMUL F1,F1
          bus_cycle(ST_PROG, 16'h41B0, 16'h41B0);
        end
        if (m == 0) begin
          bus_cycle(ST_IF1, 16'h8E34, 16'h8E34);        // FRDIV / FRVSUB F3,F4
          bus_cycle(ST_PROG, q ? 16'h0490 : 16'h04A0, q ? 16'h0490 : 16'h04A0);
        end else begin
          bus_cycle(ST_IF1, IF1_LD_F2_MEM, IF1_LD_F2_MEM);  // F3 by memory double 3.0
          bus_cycle(ST_PROG, q ? 16'h0393 : 16'h03A3, q ? 16'h0393 : 16'h03A3);
          bus_cycle(ST_EDATA, 16'h4008, 16'h4008);
          repeat (3) bus_cycle(ST_EDATA, 16'h0000, 16'h0000);
        end
        repeat (200) clk_cycle();
        ck((q == 0 || npwait != pw0) &&
           dut.u_dp.f_mem[3] == (q ? 80'h4000_8000_0000_0000_0000 : THREE),
           {"fast clocks: ", q ? "queued FRVSUB" : "direct FRDIV", " F3 by ",
            m ? "memory" : "F4", " reads Fd for its second operand"},
           "p.535 execution appears linear",
           $sformatf("promoted at done %0b, F3 %020h", npwait != pw0, dut.u_dp.f_mem[3]));
      end
    // FCPF and FCPFX unpack Fd, then Fs, and send the compare flags.
    for (int c = 0; c < 3; c++) begin
      reset_with_sc(SC_INTERMEDIATE);
      bus_cycle(ST_IF1, IF1_LD_F2_MEM, IF1_LD_F2_MEM);  // FLD F1, double 2.0
      bus_cycle(ST_PROG, 16'h8103, 16'h8103);
      bus_cycle(ST_EDATA, 16'h4000, 16'h4000);
      repeat (3) bus_cycle(ST_EDATA, 16'h0000, 16'h0000);
      bus_cycle(ST_IF1, IF1_LD_F2_MEM, IF1_LD_F2_MEM);  // FLD F2, double 0.75
      bus_cycle(ST_PROG, 16'h8203, 16'h8203);
      bus_cycle(ST_EDATA, 16'h3FE8, 16'h3FE8);
      repeat (3) bus_cycle(ST_EDATA, 16'h0000, 16'h0000);
      repeat (100) clk_cycle();
      unique case (c)
        0: begin bus_cycle(ST_IF1, 16'h8E10, 16'h8E10); bus_cycle(ST_PROG, 16'h4210, 16'h4210); end
        1: begin bus_cycle(ST_IF1, 16'h8E20, 16'h8E20); bus_cycle(ST_PROG, 16'h4120, 16'h4120); end
        default: begin bus_cycle(ST_IF1, 16'h8E10, 16'h8E10); bus_cycle(ST_PROG, 16'h4110, 16'h4110); end
      endcase
      for (int i = 0; i < 200 && dut.u_ip.state_q != 3'd4; i++) clk_cycle();
      ck(dut.u_ip.state_q == 3'd4 && dut.u_ip.cmp_byte == (c == 0 ? 8'h28 : c == 1 ? 8'h88 : 8'h40),
         c == 0 ? "fast clocks: FCPF F1,F2 (2.0 vs 0.75) sends 28" :
         c == 1 ? "fast clocks: FCPFX F2,F1 (0.75 vs 2.0) sends 88" :
                  "fast clocks: FCPF F1,F1 (2.0 vs 2.0) sends 40",
         "p.535 execution appears linear", $sformatf("state %0d, flags %02h", dut.u_ip.state_q,
         dut.u_ip.cmp_byte));
    end
    fast = 1'b0;
    clki_rise = 1'b0; clki_fall = 1'b0; clkd_rise = 1'b0;

    $display("");
    $display("[5] acknowledge: the IEO rule, the vector drive window, NV");
    reset_with_sc(SC_MIE | SC_ACK_VI | 32'h40);
    bus_cycle(ST_IF1, IF1_ID0, IF1_ID0);
    bus_cycle(ST_PROG, W2_NONE, W2_NONE);
    ck(!int_n && ieo, "requesting outside an acknowledge: /INT Low, IEO High",
       "p.542 IEO: not requesting (Interrupt Acknowledge cycle only)",
       $sformatf("/INT %0b IEO %0b", int_n, ieo));
    data_cycle(ST_NVIA, 1'b0);
    ck(!(drv[0] | drv[1] | drv[2] | drv[3]) && !ieo_lo[1] && !ieo_lo[2] && !int_n &&
       !dut.u_ip.sc_q[13], "INTACK 11: a non-vectored acknowledge is not answered",
       "p.534 INTACK 11 = Vectored",
       $sformatf("drive %0b%0b%0b%0b IEO Low %0b%0b /INT %0b", drv[0], drv[1], drv[2], drv[3],
                 ieo_lo[1], ieo_lo[2], int_n));
    iei = 1'b0;
    data_cycle(ST_VIA, 1'b0);
    iei = 1'b1;
    ck(!(drv[0] | drv[1] | drv[2] | drv[3]) && !int_n && !dut.u_ip.sc_q[13],
       "IEI Low: the acknowledge is not taken, the request stays",
       "p.542 IEI High: no higher device is requesting or under service",
       $sformatf("drive %0b%0b%0b%0b /INT %0b IUS %0b", drv[0], drv[1], drv[2], drv[3], int_n,
                 dut.u_ip.sc_q[13]));
    data_cycle(ST_VIA, 1'b0);
    ck(!ieo_lo[0] && !ieo_hi[1] && !ieo_hi[2] && !ieo_hi[3],
       "IEO High with /AS Low, Low from the /AS rise and after (IUS)",
       "p.542 IEO; p.534 IUS",
       $sformatf("IEO Low %0b%0b%0b%0b", ieo_lo[0], ieo_lo[1], ieo_lo[2], ieo_lo[3]));
    ck(!drv[0] && !drv[1] && drv_all[2] && !drv[3] && ad_seen == 16'h0040,
       "vector on AD7-0 while /DS is Low, AD15-8 00",
       "p.534 vector 0-7; p.556 vector placed while RD is Low",
       $sformatf("drive %0b%0b%0b%0b AD %04h", drv[0], drv[1], drv[2], drv[3], ad_seen));
    ck(int_n && dut.u_ip.sc_q[13] && !dut.u_ip.sc_q[14],
       "after the /DS rise: IUS set, IP clear, /INT High",
       "p.534 IUS, IP; p.556 sets the Interrupt-Under-Service latch",
       $sformatf("/INT %0b IUS %0b IP %0b", int_n, dut.u_ip.sc_q[13], dut.u_ip.sc_q[14]));
    force dut.u_ip.sc_q = SC_MIE | SC_ACK_VI;
    @(posedge clk); release dut.u_ip.sc_q; #1;
    ck(ieo, "IUS cleared: IEO High", "p.542 IEO", $sformatf("IEO %0b", ieo));
    force dut.u_ip.sc_q = SC_MIE | SC_ACK_VI | SC_DLC;
    @(posedge clk); release dut.u_ip.sc_q; #1;
    ck(!ieo, "DLC set: IEO Low", "p.534 DLC disables lower devices", $sformatf("IEO %0b", ieo));

    reset_with_sc(SC_MIE | SC_ACK_VI | SC_SV | 32'h41);
    bus_cycle(ST_IF1, IF1_ID0, IF1_ID0);
    bus_cycle(ST_PROG, W2_NONE, W2_NONE);
    data_cycle(ST_VIA, 1'b0);
    ck(drv[2] && ad_seen == 16'h0082, "SV: the vector shifted left, LSB 0",
       "p.534 SV", $sformatf("AD %04h", ad_seen));

    reset_with_sc(SC_MIE | SC_NV | 32'h40);
    bus_cycle(ST_IF1, IF1_ID0, IF1_ID0);
    bus_cycle(ST_PROG, W2_NONE, W2_NONE);
    data_cycle(ST_NMIA, 1'b0);
    ck(!(drv[0] | drv[1] | drv[2] | drv[3]) && !ieo_hi[1] && !ieo_hi[2] &&
       dut.u_ip.sc_q[13] && int_n,
       "NV, INTACK 00: nonmaskable acknowledge taken, AD floats",
       "p.534 NV leaves the lines 3-stated; INTACK 0X = Non-maskable",
       $sformatf("drive %0b%0b%0b%0b IEO High %0b%0b IUS %0b", drv[0], drv[1], drv[2], drv[3],
                 ieo_hi[1], ieo_hi[2], dut.u_ip.sc_q[13]));

    $display("");
    $display("Interface Processor state recovery");
    for (int code = 5; code < 8; code++) begin
      force dut.u_ip.state_q = type(dut.u_ip.state_q)'(3'(code));
      @(posedge clk); #1;
      release dut.u_ip.state_q;
      @(posedge clk); #1;
      ck(dut.u_ip.state_q == 3'd0, $sformatf("unused state code %0d returns to idle", code),
         "design rule", $sformatf("state %0d", dut.u_ip.state_q));
    end

    // A store whose words are all taken before the result is ready: the
    // lost-word count stops at 7 and nothing is driven afterwards.
    reset_with_sc(SC_MIE | SC_INTERMEDIATE);
    bus_cycle(ST_IF1, IF1_STORE, IF1_STORE);
    bus_cycle(ST_PROG, W2_FLD_F5_MEM, W2_FLD_F5_MEM);
    force dut.u_ip.cnt_q = 3'd7;
    @(posedge clk); #1;
    release dut.u_ip.cnt_q;
    data_cycle(ST_EDATA, 1'b1);
    ck(dut.u_ip.cnt_q == 3'd7, "lost-word count saturates at 7",
       "assumed: a 3-bit count that saturates", $sformatf("count %0d", dut.u_ip.cnt_q));
    while (dut.dp_busy) clk_cycle();
    data_cycle(ST_EDATA, 1'b1);
    ck(!drv[0] && !drv[1] && !drv[2] && !drv[3] && dut.u_ip.state_q == 3'd0,
       "result after every word was lost: idle, AD not driven",
       "assumed: drive only while words remain",
       $sformatf("driven %0b%0b%0b%0b, state %0d", drv[0], drv[1], drv[2], drv[3], dut.u_ip.state_q));

    $display("");
    if (fails == 0) $display("RESULT PASS  tb_fpu_timing  %0d checks", checks);
    else            $display("RESULT FAIL  tb_fpu_timing  %0d/%0d checks failed", fails, checks);
    $finish;
  end
endmodule

`default_nettype wire
