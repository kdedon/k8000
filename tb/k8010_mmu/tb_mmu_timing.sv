// tb_mmu_timing -- Z8010 MMU bus-protocol/timing conformance from the
// product specification (z8010_mmu.pdf 00-2046-03, pp.559-575; identical text
// in the 1988 Z8000 Family Data Book pp.163-177).  Figure and AC-row numbers
// below are that document's.
//
// Spec checks, not vector replay: tb_mmu.cpp proves per-record equality with
// the vectors; this bench proves the strobe protocol -- when the
// command is latched, when the command data is taken, when PA and the command
// read data are driven and floated, and that a back-to-back CPU cycle's
// address survives the previous cycle's /DS rise, and that the offset is
// latched at the /AS rise with PA following it before the next CLK rise.
//
// Clocking convention == the vectors: one bus phase is two
// fabric samples (CLK Low then CLK High), so `phase()` is two posedges.
//
// Run: make test-mmu-timing

module tb_mmu_timing;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  // Master clock: 5 per CLK, off CLK's edges.
  logic mclk = 1'b0;
  initial begin #0.5; forever #1 mclk = ~mclk; end
  // The board's CLK rising-edge pulse: High for the master clock in which
  // CLK is first seen High.
  logic clk_pq = 1'b0;
  always @(posedge mclk) clk_pq <= clk;
  wire  clk_rise = clk & ~clk_pq;

  logic        reset_n = 1'b0;
  logic [15:0] ad      = 16'h0000;
  logic [6:0]  sn      = 7'h00;
  logic [3:0]  st      = 4'h0;
  logic        as_n    = 1'b1;
  logic        ds_n    = 1'b1;
  logic        r_w     = 1'b1;
  logic        n_s     = 1'b0;
  logic        cs_n    = 1'b1;
  logic        dmasync = 1'b1;   // "must always be High during CPU cycles" (p.571)

  logic [15:0] pa;
  logic        pa_drive, segt_n, sup_n;
  logic [7:0]  data;
  logic [7:0]  data_drive;

  z8010_mmu dut (
    .clk(mclk), .clk_in(clk_rise), .reset_n(reset_n),
    .ad(ad[15:8]), .sn(sn), .st(st), .as_n(as_n), .ds_n(ds_n),
    .r_w(r_w), .n_s(n_s), .cs_n(cs_n), .dmasync(dmasync),
    .pa(pa), .pa_drive(pa_drive), .segt_n(segt_n), .sup_n(sup_n),
    .data(data), .data_drive(data_drive)
  );

  localparam logic [3:0] ST_SPECIAL_IO = 4'b0011;
  localparam logic [3:0] ST_DATA_MEM   = 4'b1000;

  localparam logic [7:0] CMD_MODE  = 8'h00;
  localparam logic [7:0] CMD_SAR   = 8'h01;
  localparam logic [7:0] CMD_BASE  = 8'h08;   // base high then low, DSC-sequenced
  localparam logic [7:0] CMD_LIMIT = 8'h09;
  localparam logic [7:0] CMD_ATTR  = 8'h0A;

  localparam logic [7:0] MODE_MSEN = 8'h80;
  localparam logic [7:0] MODE_TRNS = 8'h40;
  localparam logic [7:0] MODE_NMS  = 8'h08;
  localparam logic [7:0] ATTR_REF  = 8'h80;

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

  task automatic phase();
    @(posedge clk);
    @(posedge clk);
  endtask

  task automatic idle_bus();
    as_n = 1'b1; ds_n = 1'b1; cs_n = 1'b1; dmasync = 1'b1; ad = 16'h0000;
    st = 4'h0; r_w = 1'b1; n_s = 1'b0; sn = 7'h00;
    phase();
  endtask

  // Special I/O WRITE (Fig.11 p.569 "OUTPUT" half): T1 /AS Low with the
  // command in AD15:8 and /CS asserted; T2 /AS rises (the command code and
  // /CS are latched there -- AC #34/#35 TsCS(AS)/ThAS(CSn) are the only /CS
  // parameters); T3 /DS Low with the data byte on AD15:8 (the Z8010 has no
  // AD0-7 pins; special-I/O byte data rides the high lane, Ref Manual 9.4.3).
  task automatic sio_write(input logic [7:0] cmd, input logic [7:0] val);
    idle_bus();
    ad = {cmd, 8'h00}; st = ST_SPECIAL_IO; as_n = 1'b0; ds_n = 1'b1;
    r_w = 1'b0; cs_n = 1'b0;                                     phase();
    as_n = 1'b1;                                                 phase();
    ad = {val, 8'h00}; ds_n = 1'b0;                              phase();
    idle_bus();
  endtask

  // Special I/O READ (Fig.11 "INPUT" half).  Reports whether the chip drove
  // the data before /DS fell (it must not), while /DS was Low (it must) and
  // after the /DS rise (it must not).
  task automatic sio_read(input logic [7:0] cmd, output logic [7:0] val,
                          output logic early, output logic during, output logic late);
    idle_bus();
    ad = {cmd, 8'h00}; st = ST_SPECIAL_IO; as_n = 1'b0; ds_n = 1'b1;
    r_w = 1'b1; cs_n = 1'b0;                                     phase();
    as_n = 1'b1;                                                 phase();
    #1; early = |data_drive;
    ad = 16'h0000; ds_n = 1'b0; cs_n = 1'b1;                     phase();
    #1; during = |data_drive; val = data;
    ds_n = 1'b1;                                                 phase();
    #1; late = |data_drive;
    idle_bus();
  endtask

  logic [7:0] rd;
  logic       early, during, late;
  logic [15:0] pa_seen, pa_low;
  logic        pa_drv_live, pa_drv_after, pa_drv_low, pa_drv_io;
  logic [7:0]  data_low_seen;

  initial begin
    checks = 0; fails = 0;
    $display("tb_mmu_timing -- Z8010 Z-Bus timing conformance");
    $display("");

    // ---- reset ---------------------------------------------------------
    reset_n = 1'b0;
    repeat (4) @(posedge clk);
    #1;
    ck(!pa_drive && data_drive == 8'h00 && segt_n && sup_n, "reset releases PA, Data, /SEGT and /SUP",
       "p.562 Outputs: /SEGT and /SUP are open-drain and released when inactive; the PA drivers are enabled by the Mode Register MSEN bit, which a reset clears (with /CS High)",
       $sformatf("pa_drive=%0b data_drive=%0b segt_n=%0b sup_n=%0b", pa_drive, data_drive, segt_n, sup_n));
    reset_n = 1'b1;
    idle_bus();

    // ---- command interface timing ---------------------------------------
    $display("");
    $display("[1] Special I/O command timing (Fig.11 p.569)");
    sio_write(CMD_MODE, MODE_MSEN | MODE_TRNS | MODE_NMS);
    sio_read(CMD_MODE, rd, early, during, late);
    ck(rd == (MODE_MSEN | MODE_TRNS | MODE_NMS), "Mode Register written then read back over the command port",
       "p.566: three commands read and write the control registers (Mode, SAR, DSC)",
       $sformatf("Mode read back %02h, want %02h", rd, MODE_MSEN | MODE_TRNS | MODE_NMS));
    ck(!early, "command read data is NOT driven before /DS falls",
       "AC #8 TdDSR(RDv): the read data delay is measured from the /DS fall",
       $sformatf("data_drive=%0b with /AS High and /DS still High", early));
    ck(during, "command read data is driven while /DS is Low",
       "p.566: the data 'is placed on AD8-AD15 while Data Strobe is Low'",
       $sformatf("data_drive=%0b while /DS Low", during));
    ck(!late, "command read data floats at the /DS rise",
       "AC #9 TdDSR(RDf): the float delay is measured from the /DS rise",
       $sformatf("data_drive=%0b after the /DS rise", late));

    sio_read(CMD_MODE, rd, early, during, late);
    data_low_seen = data;
    ck($bits(data) == 8 && $bits(ad) == 16, "command read data rides AD15:8 only",
       "p.571 Pin Description: the Z8010 has AD8-AD15 only -- there are no AD0-AD7 pins",
       $sformatf("data port is %0d bits (data=%02h)", $bits(data), data_low_seen));

    // /CS is released before /DS falls in the middle of sio_read above; the
    // command still completed, which is the AC #34/#35 rule.
    ck(rd == (MODE_MSEN | MODE_TRNS | MODE_NMS), "a command completes with /CS released before /DS",
       "AC #34/#35 TsCS(AS)/ThAS(CSn): /CS is specified only against the /AS rise; Fig.11 shows /CS High again before /DS falls",
       $sformatf("Mode read back %02h with /CS released at /DS", rd));

    // ---- translation timing ----------------------------------------------
    $display("");
    $display("[2] translation and PA timing");
    sio_write(CMD_SAR,   8'h05);          // select descriptor 5 (also re-anchors DSC)
    sio_write(CMD_BASE,  8'h01);          // base high
    sio_write(CMD_BASE,  8'h00);          // base low  -> base = 0x0100
    sio_write(CMD_LIMIT, 8'hFF);
    sio_write(CMD_ATTR,  ATTR_REF);

    idle_bus();
    sn = 7'h05; ad = 16'h1234; st = ST_DATA_MEM; r_w = 1'b1; n_s = 1'b0;
    as_n = 1'b0; ds_n = 1'b1; cs_n = 1'b1;
    @(posedge clk); #3; pa_low = pa; pa_drv_low = pa_drive;      // /AS Low, after the T1 CLK rise
    @(posedge clk);
    as_n = 1'b1; ds_n = 1'b0;                                    phase();
    #1; pa_seen = pa; pa_drv_live = pa_drive;
    ds_n = 1'b1;                                                 phase();
    #1; pa_drv_after = pa_drive;
    idle_bus();
    st = 4'b0010; ad = 16'h1234; sn = 7'h05; as_n = 1'b0;          // I/O cycle
    @(posedge clk); #3; pa_drv_io = pa_drive;
    @(posedge clk); as_n = 1'b1;                                 phase();
    idle_bus();

    ck(pa_drv_low && pa_low == 16'h0112, "PA is driven, translated, while /AS is Low",
       "AC #28 TdAS(Ad): A23-A8 driven from the /AS fall; #25/#29: valid from the offset and the T1 CLK rise",
       $sformatf("pa=%04h drive=%0b with /AS Low, want 0112", pa_low, pa_drv_low));
    ck(!pa_drv_io, "PA floats while /AS is Low for a non-memory cycle",
       "p.571: the MMU translates memory cycles only; #26 TdST(Ad): the drive follows the status",
       $sformatf("pa_drive=%0b with /AS Low in an I/O cycle", pa_drv_io));

    ck(pa_drv_live, "PA is driven for a translated CPU cycle",
       "p.565: the MMU drives the 24-bit physical address after the segment number and offset are latched by /AS",
       $sformatf("pa_drive=%0b during the cycle", pa_drv_live));
    ck(pa_seen == 16'h0112, "PA = (base << 8) + offset",
       "p.564 Segmented Addressing: the 16-bit base is the upper 16 bits of the 24-bit physical address; the 16-bit offset is added",
       $sformatf("pa=%04h, want 0112 (A23..A8)", pa_seen));
    ck(segt_n && sup_n, "no violation for an in-bounds referenced read",
       "p.567 Violation Types: /SEGT and /SUP are asserted only on a violation",
       $sformatf("segt_n=%0b sup_n=%0b", segt_n, sup_n));
    ck(!pa_drv_after, "PA floats at the /DS rise",
       "AC #6 TdDS(Af): the address float delay is measured from the /DS rise",
       $sformatf("pa_drive=%0b after the /DS rise", pa_drv_after));

    // ---- back-to-back CPU cycles ------------------------------------------
    $display("");
    $display("[3] back-to-back cycles: the /DS rise shares a sample with the next /AS fall");
    // Product Spec Fig 19 (Z8001/2, 1988 DB p.157): the CPU releases /DS after
    // the T3 falling edge and drops /AS for the next transaction at the very
    // next edge.  A rising-edge-sampled model sees both in one sample; the
    // address just latched belongs to the NEW cycle and must survive the old
    // cycle's teardown (AC #16 TdDS(AS) min 30 ns).
    sio_write(CMD_SAR,   8'h06);
    sio_write(CMD_BASE,  8'h02);
    sio_write(CMD_BASE,  8'h00);          // base = 0x0200
    sio_write(CMD_LIMIT, 8'hFF);
    sio_write(CMD_ATTR,  ATTR_REF);

    idle_bus();
    // cycle 1: segment 5, offset 0x1234
    sn = 7'h05; ad = 16'h1234; st = ST_DATA_MEM; r_w = 1'b1; as_n = 1'b0;    phase();
    as_n = 1'b1; ds_n = 1'b0;                                                phase();
    // coincident sample: /DS rise of cycle 1 AND /AS fall of cycle 2
    ds_n = 1'b1; as_n = 1'b0; sn = 7'h06; ad = 16'h0010;                     phase();
    as_n = 1'b1; ds_n = 1'b0;                                                phase();
    #1; pa_seen = pa; pa_drv_live = pa_drive;
    ds_n = 1'b1;                                                             phase();
    idle_bus();
    ck(pa_drv_live && pa_seen == 16'h0200, "the back-to-back cycle translates its OWN address",
       "Fig 19 back-to-back Z-Bus cycles + AC #16 TdDS(AS): the /AS-fall latch must win over the coincident /DS-rise teardown",
       $sformatf("pa=%04h (drive=%0b), want 0200 (A23..A8)", pa_seen, pa_drv_live));

    // ---- the /AS rise latches the offset; PA follows it before any CLK rise --
    $display("");
    $display("[4] offset latched at the /AS rise, PA driven from it (AC #13/#14)");
    idle_bus();
    sn = 7'h05; ad = 16'h9900; st = ST_DATA_MEM; r_w = 1'b1; n_s = 1'b0;
    as_n = 1'b0; ds_n = 1'b1; cs_n = 1'b1;                       phase();
    // The offset becomes valid late in the /AS-Low window, between CLK edges.
    ad = 16'h1234;
    #2; as_n = 1'b1;
    #2; pa_seen = pa; pa_drv_live = pa_drive;      // 2 ns later: no CLK edge since
    ad = 16'hABCD;                                 // AD moves on after the hold time
    @(posedge clk); #1;
    ck(pa_drv_live && pa_seen == 16'h0112, "PA is driven from the /AS rise, before the next CLK rise",
       "AC #13/#14: offset set up and held at the AS rise; p.571: the AS rise indicates AD0-AD15 valid",
       $sformatf("pa=%04h drive=%0b 2 ns after the /AS rise, want 0112", pa_seen, pa_drv_live));
    ck(pa_drive && pa == 16'h0112, "the offset is the value at the /AS rise, held after it",
       "AC #13 TsOFF(AS) / #14 ThAS(OFFn): offset setup and hold around the AS rise",
       $sformatf("pa=%04h drive=%0b after AD changed, want 0112", pa, pa_drive));
    ds_n = 1'b0;                                                 phase();
    ds_n = 1'b1;                                                 phase();
    idle_bus();

    // ---- a violation: /SEGT and /SUP from the /AS rise ------------------------
    $display("");
    $display("[5] /SEGT and /SUP asserted from the /AS rise (AC #30, #32)");
    sio_write(CMD_SAR,   8'h07);
    sio_write(CMD_LIMIT, 8'h00);          // pages above 00 are out of bounds
    sio_write(CMD_ATTR,  8'h00);
    idle_bus();
    sn = 7'h07; ad = 16'h1234; st = ST_DATA_MEM; r_w = 1'b1; n_s = 1'b0;
    as_n = 1'b0; ds_n = 1'b1; cs_n = 1'b1;                       phase();
    #2; as_n = 1'b1;
    #2; pa_drv_live = segt_n; pa_drv_after = sup_n;  // 2 ns later: no CLK edge since
    ck(!pa_drv_live && !pa_drv_after, "a segment-length violation asserts /SEGT and /SUP before the next CLK rise",
       "AC #30 TdAS(SEGT) / #32 TdAS(SUP): measured from the AS rise; p.568: asserted in T2",
       $sformatf("segt_n=%0b sup_n=%0b 2 ns after the /AS rise", pa_drv_live, pa_drv_after));
    ds_n = 1'b0;                                                 phase();
    ds_n = 1'b1;                                                 phase();
    #1;
    ck(sup_n && !segt_n, "/SUP releases at the /DS rise, /SEGT stays until the acknowledge",
       "AC #33 TdDS(SUP); p.565: SEGT is reset during the segment trap acknowledge cycle",
       $sformatf("segt_n=%0b sup_n=%0b after the /DS rise", segt_n, sup_n));
    idle_bus();

    // ---- the acknowledge releases /SEGT at a CLK rise (INFERRED edge) --------
    $display("");
    $display("[6] /SEGT released at the third CLK rise from the acknowledge /AS rise (Fig.12, AC #31; INFERRED)");
    st = 4'h4; r_w = 1'b1; as_n = 1'b0; ds_n = 1'b1;             @(posedge clk);
    as_n = 1'b1;                                                 // T2: first CLK rise
    #4;
    ck(!segt_n, "/SEGT still Low after the first CLK rise (T2)",
       "Fig.12 p.570 draws /SEGT High only from the CLK edge opening the second wait state",
       $sformatf("segt_n=%0b", segt_n));
    @(posedge clk); #4;                                          // TWA1: second
    ck(!segt_n, "/SEGT still Low after the second CLK rise (first wait state)",
       "Fig.12 p.570",
       $sformatf("segt_n=%0b", segt_n));
    @(posedge clk); #4;                                          // TWA2: third
    ck(segt_n, "/SEGT released at the third CLK rise (second wait state)",
       "Fig.12 p.570; AC #31 TdC(SEGT) is CLK-referenced; the edge is an inference, see docs/K8010_MMU_TESTS.md row 1",
       $sformatf("segt_n=%0b", segt_n));
    @(posedge clk);                                              // TWA3
    @(posedge clk); ds_n = 1'b0;                                 // TWA4: /DS Low
    @(posedge clk); #4;
    ck(data_drive == (8'h01 << 0) && data[0] === 1'b1 && segt_n, "the identifier is driven with the trap reported while /DS is Low",
       "p.565: an MMU that generated the trap outputs a 1 on AD line 8+ID (ID 0 here)",
       $sformatf("data_drive=%02h data=%02h segt_n=%0b", data_drive, data, segt_n));
    ds_n = 1'b1;                                                 phase();
    idle_bus();

    $display("");
    if (fails == 0) $display("RESULT PASS  tb_mmu_timing  %0d checks", checks);
    else            $display("RESULT FAIL  tb_mmu_timing  %0d/%0d checks failed", fails, checks);
    $finish;
  end
endmodule
