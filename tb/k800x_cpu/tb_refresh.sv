// tb_refresh -- refresh prescaler timing.
//
// Drives the unit as the CPU does: REFRESH and RE take a written value on
// the write edge, and `load` marks writes with RE set. `take` is held High,
// so `pending` pulses once per underflow. Each edge's CLK/4 step runs before
// that edge's write: a write at edge W with RATE n first underflows at
// W + 4n when the CLK/4 phase is 0. /RESET keeps the phase, so each case
// first steps it back to 0.

module tb_refresh;
  logic       clk = 0, reset_n = 0;
  logic       enable = 0, load = 0;
  logic [5:0] rate = 0, load_rate = 0;
  logic       pending;
  logic [8:0] row_next, cyc_row;

  z8000_refresh dut (.clk(clk), .reset_n(reset_n), .enable(enable), .rate(rate), .row(9'd0),
                     .load(load), .load_rate(load_rate), .take(1'b1), .pending(pending),
                     .row_next(row_next), .cyc_row(cyc_row));

  always #5 clk <= ~clk;

  int edge_n, fails = 0, checks = 0;
  int ph = 0;      // CLK/4 phase, tracked as the unit should count it
  int events[$];   // edges on which a refresh became pending

  task automatic do_reset();
    reset_n = 0; enable = 0; rate = 0; load = 0;
    repeat (2) @(posedge clk);
    @(negedge clk) reset_n = 1;
    @(posedge clk) #1;
    edge_n = 0; events.delete();
  endtask

  task automatic align();
    while (ph != 0) begin enable = 1'b1; step(1'b0, 16'h0); end
    enable = 1'b0; edge_n = 0; events.delete();
  endtask

  // One clock, with an optional REFRESH write landing on its edge.
  task automatic step(input logic wr, input logic [15:0] val);
    @(negedge clk);
    load = wr && val[15]; load_rate = val[14:9];
    #1 if (pending) events.push_back(edge_n + 1);
    @(posedge clk);
    #1 edge_n++;
    if (enable) ph = (ph + 1) % 4;
    load = 0;
    if (wr) begin rate = val[14:9]; enable = val[15]; end
  endtask

  task automatic run(input int n);
    repeat (n) step(1'b0, 16'h0);
  endtask

  function automatic logic [15:0] re_rate(input logic re, input int n);
    return {re, 6'(n), 9'd0};
  endfunction

  task automatic expect_events(input string name, input int want[$]);
    checks++;
    if (events != want) begin
      fails++;
      $display("  FAIL %s: got %p want %p", name, events, want);
    end
    events.delete();
  endtask

  int w, e;

  initial begin
    // RATE n: every 4n clocks.
    do_reset();
    step(1'b1, re_rate(1'b1, 3)); w = edge_n;
    run(40);
    expect_events("RATE 3", '{w + 12, w + 24, w + 36});

    // RATE 0: every 256 clocks.
    do_reset(); align();
    step(1'b1, re_rate(1'b1, 0)); w = edge_n;
    run(520);
    expect_events("RATE 0", '{w + 256, w + 512});

    // Load mid-count: count restarts from the new RATE, CLK/4 phase (3 after
    // W+7) carries on, so RATE 2 underflows at W+12, not W+15.
    do_reset(); align();
    step(1'b1, re_rate(1'b1, 5)); w = edge_n;
    run(6);
    step(1'b1, re_rate(1'b1, 2));
    run(23);
    expect_events("load mid-count", '{w + 12, w + 20, w + 28});

    // Load on an underflow edge keeps that edge's pending.
    do_reset(); align();
    step(1'b1, re_rate(1'b1, 2)); w = edge_n;
    run(7);
    step(1'b1, re_rate(1'b1, 3));
    run(27);
    expect_events("load on underflow", '{w + 8, w + 20, w + 32});

    // RE clear holds count (3) and phase (2); RE set again without a load
    // resumes from them: underflow at E+9, then every 16.
    do_reset(); align();
    step(1'b1, re_rate(1'b1, 4)); w = edge_n;
    run(5);
    step(1'b1, re_rate(1'b0, 4));
    run(50);
    expect_events("RE clear", '{});
    enable = 1'b1; e = edge_n + 1;
    run(30);
    expect_events("RE resume", '{e + 9, e + 25});

    // /RESET keeps the CLK/4 phase: 1 after W+1, so RATE 1 written after
    // reset underflows 3 clocks later, not 4.
    do_reset(); align();
    step(1'b1, re_rate(1'b1, 2));
    run(1);
    do_reset();
    step(1'b1, re_rate(1'b1, 1)); w = edge_n;
    run(10);
    expect_events("reset keeps phase", '{w + 3, w + 7});

    if (fails == 0) $display("RESULT PASS tb_refresh: %0d checks", checks);
    else            $display("RESULT FAIL tb_refresh: %0d of %0d checks failed", fails, checks);
    $finish;
  end
endmodule
