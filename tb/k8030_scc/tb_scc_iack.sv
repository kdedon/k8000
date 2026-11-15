// tb_scc_iack -- two SCCs on one daisy chain, the first's IEO into the
// second's IEI, both /INT lines wired into /VI.
//
// The first is acknowledged and left under service (IEO Low). The second
// then gets a DCD ext/status IP: with IEI Low it must keep /INT High
// (UM0109 2.4.5.1 "no higher-priority interrupt is being serviced (IEI is
// High)"), or the CPU starts an acknowledge nobody answers and AD floats.
// IEI enters at the /AS latch: the AC table times /INT only from the /AS
// rise (TdAS(INT)), with no IEI-to-/INT row.
//
// Last, a request arriving after an acknowledge's /AS must not take that
// acknowledge ("no additional interrupt requests during an Interrupt
// Acknowledge cycle", UM0109).
//
// Run: make test-scc-iack

`default_nettype none

module tb_scc_iack;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic [7:0] ad_in     = 8'h00;
  logic       as_n      = 1'b1;
  logic       ds_n      = 1'b1;
  logic       r_w       = 1'b1;
  logic [1:0] cs0_n     = 2'b11;
  logic       cs1       = 1'b0;
  logic       intack_n  = 1'b1;
  logic       pclk_rise = 1'b0;
  logic [1:0] dcd_up    = 2'b11;
  logic [1:0] dcd_dn    = 2'b11;

  logic [7:0] ad_out [2];
  logic [1:0] ad_drive, int_n, ieo, iei;
  logic       vi_n;
  assign vi_n = &int_n;
  assign iei  = {ieo[0], 1'b1};

  for (genvar i = 0; i < 2; i++) begin : g
    logic [1:0] txd, rts_n, dtr_n, trxc_out, trxc_drive, sync_out, sync_drive;
    z8030_scc u (
      .clk(clk), .ad_in(ad_in), .as_n(as_n), .ds_n(ds_n), .r_w(r_w),
      .cs0_n(cs0_n[i]), .cs1(cs1), .intack_n(intack_n), .iei(iei[i]), .pclk_rise(pclk_rise),
      .rxd(2'b11), .cts_n(2'b11), .dcd_n(i == 0 ? dcd_up : dcd_dn),
      .trxc_rise(2'b00), .trxc_fall(2'b00), .rxc_rise(2'b00), .rxc_fall(2'b00), .sync_in(2'b11),
      .ad_out(ad_out[i]), .ad_drive(ad_drive[i]), .int_n(int_n[i]), .ieo(ieo[i]),
      .txd(txd), .rts_n(rts_n), .dtr_n(dtr_n), .trxc_out(trxc_out), .trxc_drive(trxc_drive),
      .sync_out(sync_out), .sync_drive(sync_drive));
  end

  // AD as the CPU reads it: the driving SCC, else the pull-ups.
  function automatic logic [7:0] bus();
    return ad_drive[0] ? ad_out[0] : ad_drive[1] ? ad_out[1] : 8'hFF;
  endfunction

  task automatic phase();
    pclk_rise = 1'b0; @(posedge clk); #1;
    pclk_rise = 1'b1; @(posedge clk); #1;
    pclk_rise = 1'b0;
  endtask

  task automatic wr(input int chip, input int reg_no, input logic [7:0] val);
    as_n = 1'b0; cs0_n[chip] = 1'b0; cs1 = 1'b1; r_w = 1'b0; ad_in = 8'(8'h20 | (reg_no << 1)); phase();
    as_n = 1'b1;                                                                               phase();
    ds_n = 1'b0; ad_in = val;                                                                  phase();
    ds_n = 1'b1;                                                                               phase();
    cs0_n = 2'b11; cs1 = 1'b0;                                                                 phase();
  endtask

  // A cycle that selects nobody: /INT is clocked by every /AS.
  task automatic other_cycle();
    as_n = 1'b0; phase(); as_n = 1'b1; phase();
    ds_n = 1'b0; phase(); ds_n = 1'b1; phase();
  endtask

  task automatic ack_as();
    as_n = 1'b0; intack_n = 1'b0; phase();
    as_n = 1'b1;                  phase(); phase();
  endtask

  // The data phase of an acknowledge: the vector is read at /DS.
  task automatic ack_ds(output logic [7:0] v, output logic [1:0] drv);
    ds_n = 1'b0;     phase(); phase();
    #1; v = bus(); drv = ad_drive;
    ds_n = 1'b1;     phase();
    intack_n = 1'b1; phase();
  endtask

  int checks = 0, fails = 0;
  task automatic ck(input bit ok, input string what);
    checks++;
    $display("  %s  %s", ok ? "PASS" : "FAIL", what);
    if (!ok) fails++;
  endtask

  logic [7:0] v;
  logic [1:0] drv;

  initial begin
    // /AS and /DS Low together: hardware reset of both chips.
    as_n = 1'b0; ds_n = 1'b0; phase(); phase(); phase();
    as_n = 1'b1; ds_n = 1'b1; repeat (6) phase();

    // Vector, ext/status IE (WR15 resets to DCD IE), MIE.
    wr(0, 2, 8'h40); wr(0, 1, 8'h01); wr(0, 9, 8'h08);
    wr(1, 2, 8'h80); wr(1, 1, 8'h01); wr(1, 9, 8'h08);

    $display("[1] upstream DCD IP, acknowledged and left under service");
    dcd_up[0] = 1'b0; repeat (4) phase(); other_cycle();
    ack_as(); ack_ds(v, drv);
    ck(v == 8'h40 && drv == 2'b01, $sformatf("upstream acknowledge reads %02h from the upstream SCC", v));
    other_cycle();
    ck(!ieo[0], "upstream IEO Low while its IUS is set");

    $display("[2] downstream DCD IP with IEI Low");
    dcd_dn[0] = 1'b0; repeat (4) phase(); other_cycle();
    ck(int_n[1] && vi_n, "downstream /INT High while IEI is Low; /VI High");

    $display("[3] upstream service ends: Reset Ext/Status, Reset Highest IUS");
    wr(0, 0, 8'h10); wr(0, 0, 8'h38);
    ck(ieo[0] && int_n[1], "IEI High: downstream /INT waits for an /AS");
    other_cycle();
    ck(!int_n[1], "downstream /INT Low at the next /AS");
    ack_as(); ack_ds(v, drv);
    ck(v == 8'h80 && drv == 2'b10, $sformatf("downstream acknowledge reads %02h from the downstream SCC", v));
    wr(1, 0, 8'h10); wr(1, 0, 8'h38);

    $display("[4] a request after the acknowledge's /AS waits for the next /AS");
    dcd_up[0] = 1'b1; repeat (4) phase(); other_cycle();
    wr(0, 0, 8'h10); other_cycle();
    ck(&int_n, "no request before the acknowledge");
    ack_as();
    dcd_up[0] = 1'b0; repeat (4) phase();
    ack_ds(v, drv);
    ck(drv == 2'b00 && g[0].u.ius == 6'h00, $sformatf("no SCC answers: drivers %02b, upstream IUS %02h",
       drv, g[0].u.ius));
    ck(int_n[0], "upstream /INT still High after the acknowledge");
    other_cycle();
    ck(!int_n[0], "upstream /INT Low at the next /AS");
    ack_as(); ack_ds(v, drv);
    ck(v == 8'h40 && drv == 2'b01, $sformatf("next acknowledge reads %02h from the upstream SCC", v));

    $display("");
    if (fails == 0) $display("RESULT PASS  tb_scc_iack  %0d checks", checks);
    else            $display("RESULT FAIL  tb_scc_iack  %0d/%0d checks failed", fails, checks);
    $finish;
  end
endmodule
