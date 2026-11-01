// tb_mmu_timing -- Z8010 MMU bus-protocol/timing conformance from the
// product specification (z8010_mmu.pdf 00-2046-03, pp.559-575; identical text
// in the 1988 Z8000 Family Data Book pp.163-177).  Figure and AC-row numbers
// below are that document's.
//
// Spec checks, not vector replay: tb_mmu.cpp proves per-record equality with
// the Go golden model; this bench proves the strobe protocol -- when the
// command is latched, when the command data is taken, when PA and the command
// read data are driven and floated, and that a back-to-back CPU cycle's
// address survives the previous cycle's /DS rise.
//
// Clocking convention == the Go harness clkStep(): one bus phase is two
// fabric samples (CLK Low then CLK High), so `phase()` is two posedges.
//
// Run: make test-mmu-timing

module tb_mmu_timing;

  logic clk = 1'b0;
  always #5 clk = ~clk;

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

  logic [23:0] pa;
  logic        pa_drive, segt_n, sup_n;
  logic [15:0] data;
  logic [7:0]  data_drive;

  z8010_mmu dut (
    .clk(clk), .reset_n(reset_n),
    .ad(ad), .sn(sn), .st(st), .as_n(as_n), .ds_n(ds_n),
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
    #1; during = |data_drive; val = data[15:8];
    ds_n = 1'b1;                                                 phase();
    #1; late = |data_drive;
    idle_bus();
  endtask

  logic [7:0] rd;
  logic       early, during, late;
  logic [23:0] pa_seen;
  logic        pa_drv_live, pa_drv_after;
  logic [15:0] data_low_seen;

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
    ck(data_low_seen[7:0] == 8'h00, "command read data rides AD15:8 only",
       "p.571 Pin Description: the Z8010 has AD8-AD15 only -- there are no AD0-AD7 pins",
       $sformatf("data=%04h, low byte must be 0", data_low_seen));

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
    as_n = 1'b0; ds_n = 1'b1; cs_n = 1'b1;                       phase();
    as_n = 1'b1; ds_n = 1'b0;                                    phase();
    #1; pa_seen = pa; pa_drv_live = pa_drive;
    ds_n = 1'b1;                                                 phase();
    #1; pa_drv_after = pa_drive;
    idle_bus();

    ck(pa_drv_live, "PA is driven for a translated CPU cycle",
       "p.565: the MMU drives the 24-bit physical address after the segment number and offset are latched by /AS",
       $sformatf("pa_drive=%0b during the cycle", pa_drv_live));
    ck(pa_seen == 24'h011234, "PA = (base << 8) + offset",
       "p.564 Segmented Addressing: the 16-bit base is the upper 16 bits of the 24-bit physical address; the 16-bit offset is added",
       $sformatf("pa=%06h, want 011234", pa_seen));
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
    ck(pa_drv_live && pa_seen == 24'h020010, "the back-to-back cycle translates its OWN address",
       "Fig 19 back-to-back Z-Bus cycles + AC #16 TdDS(AS): the /AS-fall latch must win over the coincident /DS-rise teardown",
       $sformatf("pa=%06h (drive=%0b), want 020010", pa_seen, pa_drv_live));

    $display("");
    if (fails == 0) $display("RESULT PASS  tb_mmu_timing  %0d checks", checks);
    else            $display("RESULT FAIL  tb_mmu_timing  %0d/%0d checks failed", fails, checks);
    $finish;
  end
endmodule
