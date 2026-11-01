// tb_cio_timing -- Z8036 CIO bus-protocol/timing conformance, straight from
// the datasheet (z8036_cio.pdf = 1985 data book pp.673-698; folio page numbers
// below; cross-checked against the 1988 Z8000 Family Data Book pp.282-305).
//
// This bench does NOT replay vectors: it drives the Z-Bus strobe patterns the
// datasheet figures show and asserts what the chip must do.  Companion to
// tb_cio.cpp (which proves per-Tick equality with the Go golden model);
// together they cover "same as the model" and "legal per the spec".
//
// Sampling convention == the vector harness: one posedge of `clk` is one bus
// sample, pins are set before the edge.  PCLK is held Low for the whole bus
// section on purpose: the register datapath is strobe-asynchronous (AC rows
// 13 TdDS(DRV) / 14 TdDS(DR) / 30 TdDSA(DR), p.692 -- all PCLK-independent;
// p.695 Note 1: "PCLK is only used with the counter/timers ... the PCLK input
// can be held low"), so every check here must hold with no PCLK edge at all.
//
// Run: make test-cio-timing

module tb_cio_timing;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic       rst_n   = 1'b0;
  logic [7:0] ad_in   = 8'h00;
  logic       as_n    = 1'b1;
  logic       ds_n    = 1'b1;
  logic       r_w     = 1'b1;
  logic       cs0_n   = 1'b1;
  logic       cs1     = 1'b0;
  logic       intack_n= 1'b1;
  logic       iei     = 1'b1;
  logic       pclk    = 1'b0;
  logic [7:0] pa_in   = 8'h00;
  logic [7:0] pb_in   = 8'h00;
  logic [3:0] pc_in   = 4'h0;

  logic [7:0] ad_out;
  logic       ad_drive, int_n, ieo;
  logic [7:0] pa_out, pa_oe, pb_out, pb_oe;
  logic       pa_req_n, pb_req_n;
  logic [3:0] pc_out, pc_oe;

  z8036_cio dut (
    .clk(clk), .rst_n(rst_n),
    .ad_in(ad_in), .as_n(as_n), .ds_n(ds_n), .r_w(r_w),
    .cs0_n(cs0_n), .cs1(cs1), .intack_n(intack_n), .iei(iei), .pclk(pclk),
    .pa_in(pa_in), .pb_in(pb_in), .pc_in(pc_in),
    .ad_out(ad_out), .ad_drive(ad_drive), .int_n(int_n), .ieo(ieo),
    .pa_out(pa_out), .pa_oe(pa_oe), .pa_req_n(pa_req_n),
    .pb_out(pb_out), .pb_oe(pb_oe), .pb_req_n(pb_req_n),
    .pc_out(pc_out), .pc_oe(pc_oe)
  );

  // ---- Z8036 register numbers used here (cio.go RegXxx / p.680 Table 3) ----
  localparam logic [7:0] REG_MICR      = 8'h00;
  localparam logic [7:0] REG_MCCR      = 8'h01;
  localparam logic [7:0] REG_PA_DIR    = 8'h23;
  localparam logic [7:0] REG_PB_DIR    = 8'h2B;
  localparam logic [7:0] REG_PA_MODE   = 8'h20;
  localparam logic [7:0] REG_PA_PP     = 8'h25;
  localparam logic [7:0] REG_PA_PT     = 8'h26;
  localparam logic [7:0] REG_PA_PM     = 8'h27;
  localparam logic [7:0] REG_PA_CS     = 8'h08;
  localparam logic [7:0] MICR_RESET    = 8'h01;

  // The address on AD is the register number shifted into AD6:AD1 with RJA=0
  // (p.681 "Right Justified Address": with RJA=0 the register address occupies
  // AD6-AD1 and AD0 is ignored).  cio.go regAddr does (port>>1) & 0x3F.
  function automatic logic [7:0] adr(input logic [7:0] reg_no);
    return {1'b0, reg_no[5:0], 1'b1};   // AD0=1 mirrors the C900 odd-port wiring
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

  // ---- bus primitives --------------------------------------------------------
  // One sample = one posedge.  A well-formed Z-Bus cycle is
  //   T1  /AS Low, address + /CS0 + /INTACK on the pins
  //   T2  /AS High
  //   T3  /DS Low (CS1 and R/W are the LEVELS here -- rows 8/9/10/18/19)
  //   T4  /DS High
  // /AS and /DS must never be Low together: that is the hardware reset.
  // as_pulse: one deselected /AS cycle -- the strobe a CPU issues on every
  // transaction, which is the Z8036's clock (R-CIO-405).
  task automatic as_pulse();
    as_n = 1'b0; @(posedge clk);
    as_n = 1'b1; @(posedge clk);
  endtask

  task automatic bus_write(input logic [7:0] reg_no, input logic [7:0] data);
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b0; ad_in = adr(reg_no); @(posedge clk);
    as_n = 1'b1;                                                            @(posedge clk);
    ds_n = 1'b0; ad_in = data;                                              @(posedge clk);
    ds_n = 1'b1;                                                            @(posedge clk);
    cs0_n = 1'b1; cs1 = 1'b0;                                               @(posedge clk);
  endtask

  task automatic bus_read(input logic [7:0] reg_no, output logic [7:0] data,
                          output logic drove);
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b1; ad_in = adr(reg_no); @(posedge clk);
    as_n = 1'b1;                                                            @(posedge clk);
    ds_n = 1'b0;                                                            @(posedge clk);
    #1; data = ad_out; drove = ad_drive;
    ds_n = 1'b1;                                                            @(posedge clk);
    cs0_n = 1'b1; cs1 = 1'b0;                                               @(posedge clk);
  endtask

  logic [7:0] rd;
  logic       drove, drove_after;
  logic [7:0] micr_rd;
  logic       ok;

  initial begin
    checks = 0; fails = 0;
    $display("tb_cio_timing -- Z8036 Z-Bus timing conformance (PCLK held Low)");
    $display("");

    // ---- fabric reset to the Go New() / hardware-reset state ---------------
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    $display("[1] reset state and the reset-bit protocol");
    bus_read(REG_MICR, micr_rd, drove);
    ck(micr_rd == MICR_RESET && drove, "MICR reads 0x01 while the chip is in reset",
       "p.684 Programming: after a reset all registers are 0 except MICR bit 0 (Reset), which is set; only that bit can be read or written",
       $sformatf("MICR read back %02h (ad_drive=%0b), want 01", micr_rd, drove));
    bus_read(REG_PA_DIR, rd, drove);
    ck(rd == 8'h00, "every other register reads 0 while in reset",
       "p.684: all control bits are forced to 0 while the Reset bit is set",
       $sformatf("Port A Direction read back %02h, want 00", rd));
    bus_write(REG_PA_DIR, 8'h5A);
    bus_read(REG_PA_DIR, rd, drove);
    ck(rd == 8'h00, "writes other than MICR are ignored while in reset",
       "p.684: while the Reset bit is set only MICR bit 0 is writable",
       $sformatf("Port A Direction read back %02h after a write in reset, want 00", rd));

    // Leave reset the way the firmware does.
    bus_write(REG_MICR, 8'h00);
    bus_write(REG_MCCR, 8'hF4);        // enable the ports + C/Ts (G-80.3)

    $display("");
    $display("[2] register datapath timing");
    bus_write(REG_PA_DIR, 8'h5A);
    bus_read(REG_PA_DIR, rd, drove);
    ck(rd == 8'h5A && drove, "register write then read over the bus, with PCLK held Low",
       "p.692 AC rows 13 TdDS(DRV) / 14 TdDS(DR): read data is driven from the /DS fall with no PCLK term; p.695 Note 1: PCLK may be held Low",
       $sformatf("read back %02h (ad_drive=%0b), want 5A", rd, drove));

    // AD must float at the /DS rise -- referenced to /DS alone (rows 16/17).
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b1; ad_in = adr(REG_PA_DIR); @(posedge clk);
    as_n = 1'b1;                                                                @(posedge clk);
    ds_n = 1'b0;                                                                @(posedge clk);
    #1; drove = ad_drive;
    ds_n = 1'b1;                                                                @(posedge clk);
    #1; drove_after = ad_drive;
    cs0_n = 1'b1; cs1 = 1'b0;                                                   @(posedge clk);
    ck(drove && !drove_after, "AD is driven from the /DS fall and floats at the /DS rise",
       "p.648-style AC rows 16 TdDSr(DR) / 17 TdDS(DRz): the float is referenced to the /DS rise alone",
       $sformatf("ad_drive was %0b during /DS Low and %0b after the rise", drove, drove_after));

    $display("");
    $display("[3] what /AS latches vs what /DS samples (R-CIO-401/402)");
    // CS1 Low at the /AS fall, High at the /DS fall -> the access MUST happen.
    bus_write(REG_PB_DIR, 8'h00);
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b0; r_w = 1'b0; ad_in = adr(REG_PB_DIR); @(posedge clk);
    as_n = 1'b1; cs1 = 1'b1;                                                    @(posedge clk);
    ds_n = 1'b0; ad_in = 8'hA5;                                                 @(posedge clk);
    ds_n = 1'b1;                                                                @(posedge clk);
    cs0_n = 1'b1; cs1 = 1'b0;                                                   @(posedge clk);
    bus_read(REG_PB_DIR, rd, drove);
    ck(rd == 8'hA5, "CS1 is sampled at the /DS fall, not latched by /AS",
       "p.692 rows 8/19 TsCS1(DS)/ThCS1(DS) are CS1's only AC parameters; p.674 lists ONLY addresses, INTACK and CS0 as AS-sampled",
       $sformatf("Port B Direction = %02h after a cycle with CS1 Low at /AS and High at /DS, want A5", rd));

    // CS1 High at the /AS fall, Low at the /DS fall -> the access must NOT happen.
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b0; ad_in = adr(REG_PB_DIR); @(posedge clk);
    as_n = 1'b1;                                                                @(posedge clk);
    ds_n = 1'b0; cs1 = 1'b0; ad_in = 8'h3C;                                     @(posedge clk);
    ds_n = 1'b1;                                                                @(posedge clk);
    cs0_n = 1'b1;                                                               @(posedge clk);
    bus_read(REG_PB_DIR, rd, drove);
    ck(rd == 8'hA5, "CS1 Low at the /DS fall suppresses the access",
       "p.692 rows 8/19: CS1 must be valid at /DS; the chip is deselected when it is not",
       $sformatf("Port B Direction = %02h, want A5 (unchanged)", rd));

    $display("");
    $display("[4] back-to-back cycles (the /DS rise shares a sample with the next /AS fall)");
    // Product Spec Fig 19 (1988 DB p.157): the CPU releases /DS after the T3
    // falling edge and drops /AS for the next transaction at the next edge, so
    // a rising-edge-sampled model sees both in ONE sample.  The chip's
    // end-of-cycle teardown must be applied BEFORE its /AS-fall latch or the
    // second access is dropped -- R-CIO-409, the defect that left both C900
    // CIOs stuck in power-on reset.
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b0; ad_in = adr(REG_PA_DIR); @(posedge clk);
    as_n = 1'b1;                                                                @(posedge clk);
    ds_n = 1'b0; ad_in = 8'h11;                                                 @(posedge clk);
    // coincident sample: /DS rise AND the next cycle's /AS fall
    ds_n = 1'b1; as_n = 1'b0; ad_in = adr(REG_PB_DIR);                          @(posedge clk);
    as_n = 1'b1;                                                                @(posedge clk);
    ds_n = 1'b0; ad_in = 8'h22;                                                 @(posedge clk);
    ds_n = 1'b1;                                                                @(posedge clk);
    cs0_n = 1'b1; cs1 = 1'b0;                                                   @(posedge clk);
    bus_read(REG_PA_DIR, rd, drove);
    ck(rd == 8'h11, "first of two back-to-back writes lands",
       "Product Spec Fig 19 back-to-back Z-Bus cycles",
       $sformatf("Port A Direction = %02h, want 11", rd));
    bus_read(REG_PB_DIR, rd, drove);
    ck(rd == 8'h22, "second back-to-back write lands (teardown before /AS latch)",
       "R-CIO-409 / Fig 19: the /DS-rise teardown must not wipe the ownership the same sample's /AS fall just latched",
       $sformatf("Port B Direction = %02h, want 22", rd));

    $display("");
    $display("[5] hardware reset: /AS and /DS Low together");
    // p.674 footnote / p.684: the Z8036 has no reset pin; forcing /AS and /DS
    // Low at the same time resets it.  Reset Timing p.696 gives TwRES.
    as_n = 1'b0; ds_n = 1'b0;                                                   @(posedge clk);
    repeat (2) @(posedge clk);
    as_n = 1'b1; ds_n = 1'b1;                                                   @(posedge clk);
    bus_read(REG_MICR, micr_rd, drove);
    ck(micr_rd == MICR_RESET, "/AS+/DS Low forces the hardware reset (MICR reads 01)",
       "p.674 footnote + p.684: the Z8036 has no reset pin; /AS and /DS Low together reset it, setting MICR bit 0",
       $sformatf("MICR read back %02h after /AS+/DS Low, want 01", micr_rd));
    bus_read(REG_PA_DIR, rd, drove);
    ck(rd == 8'h00, "hardware reset clears the register file",
       "p.684: a reset forces all control bits to 0",
       $sformatf("Port A Direction = %02h after the hardware reset, want 00", rd));

    $display("");
    $display("[6] /AS is the chip's clock (R-CIO-405)");
    // p.695 Note 1: PCLK is used ONLY by the timer-mode counters, the
    // deskew timers and REQUEST/WAIT. Everything else -- the port input
    // register, the 1's catchers, the pattern match, the handshake FSMs
    // and the IP -> /INT latch -- is clocked by /AS: 1988 Z8000 Family
    // Data Book p.301 Note 7, "The AS functions as the clock to the 8036.
    // If AS strobe stops, then data does not get clocked through the
    // device. AS cycle functions similar to a clock cycle", and every INT
    // delay in p.692 rows 22-25 is quoted in AS cycles.
    //
    // The probe is the pattern-match IP bit, because it is STATE: a bus
    // read is itself an /AS cycle, so a probe that only looked at the data
    // register could not tell the two clocks apart.
    bus_write(REG_MICR,    8'h00);   // leave the reset of [5]
    bus_write(REG_MCCR,    8'h04);   // PAE: a disabled port does not match
    bus_write(REG_PA_DIR,  8'hFF);   // Port A all inputs
    bus_write(REG_PA_PT,   8'h00);   // level match ...
    bus_write(REG_PA_PP,   8'h3C);   // ... against 0x3C
    bus_write(REG_PA_MODE, 8'h02);   // PMS (D2:D1) = 01: AND mode
    bus_write(REG_PA_PM,   8'hFF);   // every bit participates
    bus_write(REG_PA_CS,   8'h20);   // clear IP/IUS
    bus_write(REG_PA_CS,   8'hC0);   // set IE
    bus_write(REG_MICR,    8'h80);   // MIE

    pa_in = 8'h3C;
    repeat (8) begin                 // PCLK alone must clock nothing
      pclk = 1'b1; @(posedge clk);
      pclk = 1'b0; @(posedge clk);
    end
    pa_in = 8'h00;                   // the probe cycle must not create the match itself
    bus_read(REG_PA_CS, rd, drove);
    ck((rd & 8'h20) == 8'h00, "the pattern does NOT match while /AS is stopped",
       "p.695 Note 1: PCLK drives only the timer-mode counters, the deskew timers and REQUEST/WAIT -- nothing else may depend on a PCLK edge",
       $sformatf("Port A CS = %02h after 8 PCLK cycles with /AS idle, IP must be clear", rd));

    pa_in = 8'h3C;
    as_pulse();                      // two /AS cycles: the synchroniser is
    as_pulse();                      // two stages deep (p.681)
    bus_read(REG_PA_CS, rd, drove);
    ck((rd & 8'h20) != 8'h00, "the pattern matches on the /AS clock",
       "1988 DB p.301 Note 7: the AS strobe clocks data through the device; TdPM(INT) (row 22) is 1 AS cycle + 800 ns",
       $sformatf("Port A CS = %02h after two /AS cycles, IP must be set", rd));
    #1;
    ck(!int_n, "/INT follows on the /AS clock",
       "p.692 rows 22-25: every /INT delay is quoted in AS cycles, so /INT is an /AS-clocked latch, not a combinational encoder output",
       $sformatf("int_n=%0b with IP+IE+MIE set", int_n));

    $display("");
    if (fails == 0) $display("RESULT PASS  tb_cio_timing  %0d checks", checks);
    else            $display("RESULT FAIL  tb_cio_timing  %0d/%0d checks failed", fails, checks);
    $finish;
  end
endmodule
