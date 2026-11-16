// tb_scc_async_rx -- asynchronous receive against a sender whose bit rate
// differs from the receiver's.
//
// Channel A receives 8N1 at x16 from /RTxC; a behavioural sender drives
// RxD with random characters back to back, its bit time scaled by the rate
// offset. A good stop bit ends the character at its centre sample, so the
// next start edge is found however early it comes within the sampling
// margin; a framing error adds half a bit so the bad stop bit is not taken
// for a start bit (UM0109 RR1 D6). Each offset within a few percent must
// deliver every character with no framing or overrun error, with one and
// two stop bits sent; +/-10% must fail.
//
// Run: make test-scc-async-rx

`default_nettype none

module tb_scc_async_rx;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  localparam int RXC_CLKS = 8;               // /RTxC period in master clocks
  localparam int BIT_CLKS = 16 * RXC_CLKS;   // receiver bit time at x16
  localparam int N_CHARS  = 200;

  logic [7:0] ad_in    = 8'h00;
  logic       as_n     = 1'b1;
  logic       ds_n     = 1'b1;
  logic       r_w      = 1'b1;
  logic       cs0_n    = 1'b1;
  logic       cs1      = 1'b0;
  logic       pclk_rise = 1'b0;
  logic [1:0] rxd      = 2'b11;
  logic [1:0] rxc_rise = 2'b00;
  logic [1:0] rxc_fall = 2'b00;

  logic [7:0] ad_out;
  logic       ad_drive, int_n, ieo;
  logic [1:0] txd, rts_n, dtr_n, trxc_out, trxc_drive, sync_out, sync_drive;

  z8030_scc dut (
    .clk(clk), .ad_in(ad_in), .as_n(as_n), .ds_n(ds_n), .r_w(r_w),
    .cs0_n(cs0_n), .cs1(cs1), .intack_n(1'b1), .iei(1'b1), .pclk_rise(pclk_rise),
    .rxd(rxd), .cts_n(2'b11), .dcd_n(2'b11),
    .trxc_rise(2'b00), .trxc_fall(2'b00), .rxc_rise(rxc_rise), .rxc_fall(rxc_fall), .sync_in(2'b11),
    .ad_out(ad_out), .ad_drive(ad_drive), .int_n(int_n), .ieo(ieo),
    .txd(txd), .rts_n(rts_n), .dtr_n(dtr_n), .trxc_out(trxc_out), .trxc_drive(trxc_drive),
    .sync_out(sync_out), .sync_drive(sync_drive));

  // PCLK at half the master clock; /RTxC High for the first half of its period.
  longint cyc = 0;
  always @(posedge clk) begin
    cyc       <= cyc + 1;
    pclk_rise <= cyc[0];
    rxc_rise  <= {1'b0, cyc % RXC_CLKS == 0};
    rxc_fall  <= {1'b0, cyc % RXC_CLKS == RXC_CLKS / 2};
  end

  task automatic phase();
    repeat (2) @(posedge clk);
    #1;
  endtask

  // Shift Left addressing: AD4:AD1 = register, AD5 High = channel A.
  task automatic wr(input int reg_no, input logic [7:0] val);
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b0; ad_in = 8'(8'h20 | (reg_no << 1)); phase();
    as_n = 1'b1;                                                                       phase();
    ds_n = 1'b0; ad_in = val;                                                          phase();
    ds_n = 1'b1;                                                                       phase();
    cs0_n = 1'b1; cs1 = 1'b0;                                                          phase();
  endtask

  task automatic rd(input int reg_no, output logic [7:0] val);
    as_n = 1'b0; cs0_n = 1'b0; cs1 = 1'b1; r_w = 1'b1; ad_in = 8'(8'h20 | (reg_no << 1)); phase();
    as_n = 1'b1;                                                                       phase();
    ds_n = 1'b0;                                                                       phase();
    val = ad_out;
    ds_n = 1'b1;                                                                       phase();
    cs0_n = 1'b1; cs1 = 1'b0;                                                          phase();
  endtask

  task automatic wait_until(input real t);
    while (real'(cyc) < t) @(posedge clk);
    #1;
  endtask

  logic [7:0] sent [$];
  bit         sending;
  int unsigned seed = 32'h1234_5678;

  function automatic logic [7:0] rnd();
    seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5;
    return seed[7:0];
  endfunction

  // Characters back to back, each bit ending at its scaled time.
  task automatic send(input real pct, input int stops);
    real bt, t;
    logic [10:0] frame;
    bt = real'(BIT_CLKS) / (1.0 + pct / 100.0);
    t  = real'(cyc);
    for (int i = 0; i < N_CHARS; i++) begin
      logic [7:0] c;
      c = rnd();
      sent.push_back(c);
      frame = {2'b11, c, 1'b0};
      for (int b = 0; b < 9 + stops; b++) begin
        rxd[0] = frame[b];
        t += bt;
        wait_until(t);
      end
    end
    rxd[0] = 1'b1;
    sending = 1'b0;
  endtask

  // Polls RR0 and reads RR1 before each character.
  int got, bad;
  task automatic receive();
    logic [7:0] rr0, rr1, d;
    int idle;
    idle = 0;
    while (sending || idle < 3 * 10 * BIT_CLKS) begin
      rd(0, rr0);
      if (rr0[0]) begin
        rd(1, rr1); rd(8, d);
        got++;
        if (sent.size() == 0 || d != sent[0] || rr1[6:4] != 3'b000) begin
          if (bad < 3)
            $display("    char %0d: got %02h RR1 %02h, expected %02h", got, d, rr1,
                     sent.size() ? sent[0] : 8'h00);
          bad++;
        end
        if (sent.size()) void'(sent.pop_front());
        idle = 0;
      end else if (!sending) begin
        idle += 10;
      end
    end
  endtask

  int checks = 0, fails = 0;

  task automatic run(input real pct, input int stops, input bit expect_ok);
    bit ok;
    sent.delete(); got = 0; bad = 0; sending = 1'b1;
    wr(0, 8'h30);                                // Error Reset
    wr(4, stops == 1 ? 8'h44 : 8'h4C);           // x16, async, stop bits as sent
    wr(3, 8'hC1);                                // 8 bits, Rx enable
    fork
      send(pct, stops);
      receive();
    join
    ok = expect_ok ? (bad == 0 && got == N_CHARS && sent.size() == 0)
                   : (bad != 0 || got != N_CHARS);
    checks++;
    if (!ok) fails++;
    $display("  %s  sender %5.1f%%, %0d stop: %0d of %0d received, %0d bad%s", ok ? "PASS" : "FAIL",
             pct, stops, got, N_CHARS, bad, expect_ok ? string'("") : string'(" (must fail)"));
    wr(3, 8'hC0);                                // Rx off between runs
  endtask

  initial begin
    // /AS and /DS Low together across PCLK rises: hardware reset.
    as_n = 1'b0; ds_n = 1'b0; repeat (3) phase();
    as_n = 1'b1; ds_n = 1'b1; repeat (6) phase();
    wr(11, 8'h08);                               // receive clock from /RTxC

    for (int stops = 1; stops <= 2; stops++) begin
      run(-3.0, stops, 1'b1);
      run(-1.0, stops, 1'b1);
      run( 0.0, stops, 1'b1);
      run( 0.1, stops, 1'b1);
      run( 1.0, stops, 1'b1);
      run( 3.0, stops, 1'b1);
    end
    run(-10.0, 1, 1'b0);
    run( 10.0, 1, 1'b0);

    $display("");
    if (fails == 0) $display("RESULT PASS  tb_scc_async_rx  %0d checks", checks);
    else            $display("RESULT FAIL  tb_scc_async_rx  %0d/%0d checks failed", fails, checks);
    $finish;
  end
endmodule
