// tb_abort_mreq -- MREQ in an IF1 that /ABORT kills, on a Z8003.
//
// MREQ R5 (7B5D) in system mode with /MI High drives /MO Low on the rise
// after its word. Aborted at its IF1 the instruction must have no effect:
// /MO stays High. A run without the abort proves the bench sees /MO move.
//
// Run: make test-abort-mreq

module tb_abort_mreq;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic mclk = 1'b0;
  initial begin #0.5; forever #1 mclk = ~mclk; end
  logic clk_pq = 1'b0;
  always @(posedge mclk) clk_pq <= clk;
  wire  clk_rise = clk & ~clk_pq;
  wire  clk_fall = ~clk & clk_pq;

  logic        reset_n, abort_n;
  logic [15:0] ad_in;
  logic [15:0] ad_out;
  logic        ad_drive, bus_drive;
  logic [6:0]  sn;
  logic        as_n, ds_n, mreq_n, r_w, b_w, n_s;
  logic [3:0]  st;
  logic        busack_n, mo_n;

  z8000_cpu #(.SEGMENTED(1'b1), .VMPU(1'b1)) dut (
    .clk(mclk), .clk_rise(clk_rise), .clk_fall(clk_fall), .reset_n(reset_n),
    .ad_in(ad_in), .stop_n(1'b1), .wait_n(1'b1), .busreq_n(1'b1),
    .nmi_n(1'b1), .nvi_n(1'b1), .vi_n(1'b1), .segt_n(1'b1),
    .abort_n(abort_n), .mi_n(1'b1),
    .ad_out(ad_out), .ad_drive(ad_drive), .bus_drive(bus_drive), .sn(sn),
    .as_n(as_n), .ds_n(ds_n), .mreq_n(mreq_n),
    .r_w(r_w), .b_w(b_w), .n_s(n_s), .st(st),
    .busack_n(busack_n), .mo_n(mo_n)
  );

  localparam logic [15:0] PROG = 16'h0100;
  logic [15:0] mem [0:255];
  logic [15:0] lat_addr;
  logic        as_q, abort_on;
  always @(negedge clk) begin
    if (as_q && !as_n && ad_drive) lat_addr <= ad_out;
    as_q <= as_n;
  end
  assign ad_in = mem[lat_addr[8:1]];

  // /ABORT Low from the MREQ fetch's address until its /DS rises.
  logic in_if1, ds_q = 1'b1;
  always @(negedge clk) begin
    if (as_q && !as_n && ad_drive) in_if1 <= ad_out == PROG;
    else if (ds_n && !ds_q)        in_if1 <= 1'b0;
    ds_q <= ds_n;
  end
  assign abort_n = !(abort_on && in_if1);
  int unsigned mo_low = 0;
  always @(posedge mclk) if (!mo_n) mo_low <= mo_low + 1;
  int unsigned abt_n = 0;
  always @(posedge mclk) if (dut.u_sequencer.abt_q) abt_n <= abt_n + 1;

  int unsigned failed = 0;

  task automatic run(input bit abort, input bit want_mo);
    int i;
    int unsigned mo0, abt0;
    for (i = 0; i < 256; i++) mem[i] = 16'h8D07;   // NOP
    mem[1] = 16'hC000;                             // system, segmented
    mem[2] = 16'h0000;
    mem[3] = PROG;
    mem[PROG >> 1] = 16'h7B5D;                     // MREQ R5
    abort_on = abort;
    reset_n  = 1'b0;
    repeat (4) @(posedge clk);
    mo0      = mo_low;
    abt0     = abt_n;
    reset_n  = 1'b1;
    repeat (120) @(posedge clk);
    if ((abt_n != abt0) != abort) begin
      failed++;
      $display("FAIL  abort %0b: /ABORT sampled %0b", abort, abt_n != abt0);
    end else if ((mo_low != mo0) != want_mo) begin
      failed++;
      if (abort) $display("FAIL  aborted IF1: /MO went Low");
      else       $display("FAIL  no abort: /MO stayed High");
    end
  endtask

  initial begin
    as_q = 1'b1;
    lat_addr = 16'h0000;
    in_if1 = 1'b0;
    run(1'b0, 1'b1);
    run(1'b1, 1'b0);
    if (failed == 0) $display("RESULT PASS  tb_abort_mreq  2 cases");
    else             $display("RESULT FAIL  tb_abort_mreq  %0d of 2 cases", failed);
    $finish;
  end
endmodule
