// tb_scc_timing -- Z8030 SCC bus-protocol/timing conformance from the
// datasheet (z8030_scc.pdf = 1985 data book pp.631-651; AC Characteristics
// p.648) and the SCC/ESCC User Manual UM010903.
//
// Spec checks, not vector replay: the companion tb_scc.cpp proves per-record
// equality with the Go golden model, this bench proves the strobe protocol.
//
// Clocking convention == docs/K8030_SCC_TESTS.md sec 1.2: one posedge of `clk` is
// one Go TickPins call, the PCLK rise is a one-master-clock pulse on
// `pclk_rise`, and one bus phase is (no pulse, pulse) -- so `phase()` below is
// two posedges.  The Z8030's bus-cycle service runs on the PCLK rise (ledger
// sec 1.2); the AD float at /DS rise is combinational and is checked with NO
// PCLK edge, which is what p.648 row 23 TdDS(DRz) requires.
//
// Run: make test-scc-timing

module tb_scc_timing;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic [7:0] ad_in    = 8'h00;
  logic       as_n     = 1'b1;
  logic       ds_n     = 1'b1;
  logic       r_w      = 1'b1;
  logic       cs0_n    = 1'b1;
  logic       cs1      = 1'b0;
  logic       intack_n = 1'b1;
  logic       iei      = 1'b1;
  logic       pclk_rise = 1'b0;
  logic [1:0] rxd      = 2'b11;
  logic [1:0] cts_n    = 2'b11;
  logic [1:0] dcd_n    = 2'b11;
  logic [1:0] trxc_rise = 2'b00;
  logic [1:0] trxc_fall = 2'b00;
  logic [1:0] rxc_rise  = 2'b00;
  logic [1:0] rxc_fall  = 2'b00;
  logic [1:0] sync_in  = 2'b11;

  logic [7:0] ad_out;
  logic       ad_drive, int_n, ieo;
  logic [1:0] txd, rts_n, dtr_n, trxc_out, trxc_drive, sync_out, sync_drive;

  z8030_scc dut (
    .clk(clk),
    .ad_in(ad_in), .as_n(as_n), .ds_n(ds_n), .r_w(r_w),
    .cs0_n(cs0_n), .cs1(cs1), .intack_n(intack_n), .iei(iei), .pclk_rise(pclk_rise),
    .rxd(rxd), .cts_n(cts_n), .dcd_n(dcd_n),
    .trxc_rise(trxc_rise), .trxc_fall(trxc_fall), .rxc_rise(rxc_rise), .rxc_fall(rxc_fall), .sync_in(sync_in),
    .ad_out(ad_out), .ad_drive(ad_drive), .int_n(int_n), .ieo(ieo),
    .txd(txd), .rts_n(rts_n), .dtr_n(dtr_n),
    .trxc_out(trxc_out), .trxc_drive(trxc_drive),
    .sync_out(sync_out), .sync_drive(sync_drive)
  );

  localparam int CH_A = 0;
  localparam int CH_B = 1;

  // Z8030 Z-Bus direct addressing, Shift Left mode (p.641): AD4:AD1 = the
  // register number, A//B on AD5 (1 = channel A), AD0 ignored.
  function automatic logic [7:0] adr(input int ch, input int reg_no);
    return 8'((reg_no << 1) | (ch == CH_A ? 8'h20 : 8'h00));
  endfunction

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

  // One bus phase = PCLK Low sample then PCLK High sample.
  // Inputs change 1 ns after the edge, so the chip samples them at the next
  // posedge whatever earlier #1 waits have done to the alignment.
  task automatic phase();
    pclk_rise = 1'b0; @(posedge clk); #1;
    pclk_rise = 1'b1; @(posedge clk); #1;
    pclk_rise = 1'b0;
  endtask
  // One extra sample with no PCLK rise pulse: used to prove that
  // a behaviour is combinational on the strobe, not clocked.
  task automatic hold();
    @(posedge clk); #1;
  endtask

  task automatic scc_write(input int ch, input int reg_no, input logic [7:0] val);
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b0; ad_in = adr(ch, reg_no); phase();
    as_n = 1'b1;                                                                phase();
    ds_n = 1'b0; ad_in = val;                                                   phase();
    ds_n = 1'b1;                                                                phase();
    cs0_n = 1'b1; cs1 = 1'b0;                                                    phase();
  endtask

  task automatic scc_read(input int ch, input int reg_no,
                          output logic [7:0] val, output logic drove);
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b1; ad_in = adr(ch, reg_no); phase();
    as_n = 1'b1;                                                                phase();
    ds_n = 1'b0;                                                                phase();
    #1; val = ad_out; drove = ad_drive;
    ds_n = 1'b1;                                                                phase();
    cs0_n = 1'b1; cs1 = 1'b0;                                                    phase();
  endtask

  logic [7:0] rd;
  logic       drove, drove_after;

  initial begin
    checks = 0; fails = 0;
    $display("tb_scc_timing -- Z8030 Z-Bus timing conformance");
    $display("");

    // The Z8030 has NO reset pin (p.633 pin list): the only reset is /AS and
    // /DS Low together.  Start from it so the bench begins in the datasheet's
    // reset state, then honour the internal 4-5 PCLK stretch (UM010903 p.26).
    @(posedge clk);
    #1;
    as_n = 1'b0; ds_n = 1'b0;                                                 phase();
                                                                              phase();
    as_n = 1'b1; ds_n = 1'b1;                                                 phase();
    repeat (6) phase();

    $display("[1] register datapath over the Z-Bus");
    scc_write(CH_A, 12, 8'h2E);
    scc_write(CH_A, 13, 8'h01);
    scc_read (CH_A, 12, rd, drove);
    ck(rd == 8'h2E && drove, "WR12 written over the bus reads back through RR12",
       "p.641 Z-Bus direct addressing + p.646 register map: RR12/RR13 return the BRG time constant written to WR12/WR13",
       $sformatf("RR12=%02h (ad_drive=%0b), want 2E", rd, drove));
    scc_read (CH_A, 13, rd, drove);
    ck(rd == 8'h01, "WR13 reads back through RR13",
       "p.646 register map",
       $sformatf("RR13=%02h, want 01", rd));
    // A//B is an ADDRESS bit (AD5 in Shift Left mode): the two channels have
    // independent register files.
    scc_write(CH_B, 12, 8'h99);
    scc_read (CH_B, 12, rd, drove);
    ck(rd == 8'h99, "channel B WR12 is addressed by AD5 = 0",
       "p.641: in Shift Left mode AD4:AD1 select the register and AD5 is the A//B channel select",
       $sformatf("RR12B=%02h, want 99", rd));
    scc_read (CH_A, 12, rd, drove);
    ck(rd == 8'h2E, "channel A WR12 is unaffected by the channel B write",
       "p.641: the channels have separate register files selected by A//B",
       $sformatf("RR12A=%02h, want 2E", rd));

    $display("");
    $display("[2] /AS latches the register address (transparent while Low, frozen at the rise)");
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b0; ad_in = adr(CH_A, 12); phase();
    as_n = 1'b1;                                                              phase();
    // AD now carries write DATA, not the address: the chip must already have
    // frozen the register number at the /AS rise.
    ds_n = 1'b0; ad_in = 8'h7F;                                               phase();
    ds_n = 1'b1;                                                              phase();
    cs0_n = 1'b1; cs1 = 1'b0;                                                  phase();
    scc_read(CH_A, 12, rd, drove);
    ck(rd == 8'h7F, "the address latched at /AS survives AD changing to data",
       "p.633 pin description: 'INTACK is latched by the rising edge of AS'; addresses and /CS0 are sampled while /AS is Low (p.641)",
       $sformatf("RR12=%02h, want 7F", rd));

    $display("");
    $display("[3] AD float is referenced to the /DS rise alone");
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b1; ad_in = adr(CH_A, 12); phase();
    as_n = 1'b1;                                                              phase();
    ds_n = 1'b0;                                                              phase();
    #1; drove = ad_drive;
    ds_n = 1'b1;                                                              hold();   // NO PCLK rise
    #1; drove_after = ad_drive;
    phase();
    cs0_n = 1'b1; cs1 = 1'b0;                                                  phase();
    ck(drove && !drove_after, "AD floats at the /DS rise with no PCLK edge",
       "p.648 rows 20 TdDSr(DR) / 23 TdDS(DRz): the data-float delay is measured from the /DS rise; the p.648 INTACK figure shows the vector floating at /DS rise while /INTACK is still Low (the W2-18 bus-fight hazard)",
       $sformatf("ad_drive during /DS Low = %0b, after the /DS rise = %0b", drove, drove_after));

    $display("");
    $display("[4] a deselected /AS pulse must not disturb the chip");
    // The CPU strobes /AS on every transaction on the board; a cycle that does
    // not select the SCC must leave its registers alone.
    as_n = 1'b0; cs0_n = 1'b1; cs1 = 1'b0; ad_in = adr(CH_A, 12);             phase();
    as_n = 1'b1;                                                              phase();
    ds_n = 1'b0; ad_in = 8'h00;                                               phase();
    ds_n = 1'b1;                                                              phase();
    scc_read(CH_A, 12, rd, drove);
    ck(rd == 8'h7F, "a cycle with /CS0 High leaves the registers untouched",
       "p.633: /CS0 is latched by /AS and gates the whole cycle",
       $sformatf("RR12=%02h after a deselected cycle, want 7F", rd));

    $display("");
    $display("[5] hardware reset: /AS and /DS Low together");
    scc_write(CH_A, 5, 8'hEA);       // DTR + TxEN + RTS
    #1;
    ck(!rts_n[CH_A] && !dtr_n[CH_A], "WR5 D1/D7 assert /RTS and /DTR",
       "p.643 WR5: D1 = RTS, D7 = DTR, both open-drain outputs",
       $sformatf("rts_n=%0b dtr_n=%0b", rts_n[CH_A], dtr_n[CH_A]));
    // Two full PCLK cycles Low together: >= TwRES (250 ns, p.648 row 39) at
    // any legal PCLK, so this is a reset by the spec and not only by model
    // convention.
    as_n = 1'b0; ds_n = 1'b0;                                                 phase();
                                                                              phase();
    as_n = 1'b1; ds_n = 1'b1;                                                 phase();
    #1;
    ck(rts_n[CH_A] && dtr_n[CH_A], "the /AS+/DS reset deasserts /RTS and /DTR",
       "UM010903 p.26-27 reset table: WR5 D7 (DTR) and D1 (RTS) clear",
       $sformatf("rts_n=%0b dtr_n=%0b after the reset", rts_n[CH_A], dtr_n[CH_A]));
    // "The reset condition is stretched internally for an additional four to
    // five PCLK cycles. During this time, any attempt to access is ignored"
    // (UM010903 p.26).
    repeat (6) phase();
    scc_read(CH_A, 15, rd, drove);
    ck(rd == 8'hF8, "RR15 holds its reset value after the /AS+/DS reset",
       "UM010903 p.26-27 reset table: WR15 (read back as RR15) resets to 0xF8",
       $sformatf("RR15=%02h, want F8", rd));
    scc_read(CH_A, 12, rd, drove);
    ck(rd == 8'h7F, "the reset leaves the BRG time constant alone",
       "UM010903 p.26-27 reset table: WR12/WR13 are X (not affected) under both resets",
       $sformatf("RR12=%02h after the reset, want 7F", rd));

    $display("");
    $display("[6] a BRIEF /AS+/DS overlap is a bus turnaround, not a reset");
    // p.648 rows 37/38 name 15-30 ns AS-to-DS and DS-to-AS delays as
    // "Delay for No Reset", while row 39 TwRES requires the two strobes
    // coincident Low for >= 250 ns before a reset happens.  The spec
    // separates the two conditions BY DURATION, so a level detector is
    // wrong: it turns every legal turnaround into a chip wipe.  Program a
    // register, glitch the strobes together for less than one PCLK, and
    // require the programming to survive.
    // Exactly ONE PCLK rising edge with the strobes coincident -- the most a
    // real turnaround glitch can straddle, and the boundary the Go model's
    // TestPins_BriefASDSOverlapIsNotReset pins.  Two would be a reset.
    scc_write(CH_A, 12, 8'h5A);
    as_n = 1'b0; ds_n = 1'b0;   phase();
    as_n = 1'b1; ds_n = 1'b1;   phase();
    repeat (4) phase();
    scc_read(CH_A, 12, rd, drove);
    ck(rd == 8'h5A, "a sub-TwRES /AS+/DS overlap does not reset the chip",
       "p.648 rows 37/38 'Delay for No Reset' (15-30 ns) vs row 39 TwRES (>= 250 ns): reset is qualified by WIDTH, so RTL must count the coincidence, not level-detect it",
       $sformatf("WR12 read back %02h after a brief overlap, want 5A", rd));

    $display("");
    $display("[7] one access per /AS: a further /DS without /AS is ignored (INFERRED)");
    // A DMA master with no /AS strobes /DS after the CPU's last cycle; the
    // data book does not say what the chip does.  Model: the select is
    // spent at the first /DS rise.
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b0; ad_in = adr(CH_A, 12); phase();
    as_n = 1'b1;                                                              phase();
    ds_n = 1'b0; ad_in = 8'h11;                                               phase();
    ds_n = 1'b1;                                                              phase();
    ds_n = 1'b0; ad_in = 8'h22;                                               phase();
    ds_n = 1'b1;                                                              phase();
    cs0_n = 1'b1; cs1 = 1'b0;                                                  phase();
    scc_read(CH_A, 12, rd, drove);
    ck(rd == 8'h11, "a second /DS write without /AS is ignored",
       "INFERRED (user 2026-11-07): one access per /AS",
       $sformatf("WR12=%02h, want 11", rd));

    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b1; ad_in = adr(CH_A, 12); phase();
    as_n = 1'b1;                                                              phase();
    ds_n = 1'b0;                                                              phase();
    #1; drove = ad_drive;
    ds_n = 1'b1;                                                              phase();
    ds_n = 1'b0;                                                              phase();
    #1; drove_after = ad_drive;
    ds_n = 1'b1;                                                              phase();
    cs0_n = 1'b1; cs1 = 1'b0;                                                  phase();
    ck(drove && !drove_after, "a second /DS read without /AS is ignored",
       "INFERRED (user 2026-11-07): one access per /AS",
       $sformatf("ad_drive first /DS = %0b, second = %0b", drove, drove_after));

    // Interrupt acknowledge: WR2 vector, MIE, DCD external/status source.
    scc_write(CH_A, 2, 8'h40);
    scc_write(CH_A, 15, 8'h08);   // DCD IE
    scc_write(CH_A, 1, 8'h01);    // Ext Int Enable
    scc_write(CH_A, 9, 8'h08);    // MIE, NV = 0, VIS = 0
    dcd_n[CH_A] = 1'b0;
    repeat (4) phase();
    as_n = 1'b0; intack_n = 1'b0;                                              phase();
    as_n = 1'b1;                                                              phase();
    ds_n = 1'b0;                                                              phase();
    #1; rd = ad_out; drove = ad_drive;
    ds_n = 1'b1;                                                              phase();
    ds_n = 1'b0;                                                              phase();
    #1; drove_after = ad_drive;
    ds_n = 1'b1; intack_n = 1'b1;                                              phase();
    ck(rd == 8'h40 && drove && !drove_after, "acknowledge drives the vector at the first /DS only",
       "INFERRED (user 2026-11-07): one access per /AS",
       $sformatf("vector %02h drive %0b, second /DS drive %0b", rd, drove, drove_after));

    $display("");
    if (fails == 0) $display("RESULT PASS  tb_scc_timing  %0d checks", checks);
    else            $display("RESULT FAIL  tb_scc_timing  %0d/%0d checks failed", fails, checks);
    $finish;
  end
endmodule
