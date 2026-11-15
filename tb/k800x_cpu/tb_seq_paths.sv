// tb_seq_paths -- program paths and repeat counts from the datapath.
//
// Runs one instruction per case on a Z8002 with the sequencer forced to walk
// its program, and checks its length in clocks, IF1 T1 to the next IF1 T1,
// against the Mar81 Technical Manual cycle counts (Appendix C): JP cc,@Rd 10
// taken / 7 not taken, RET cc 7 not taken, SLA/SRA Rd,#b 13+3b; and the
// program ROM's RET cc taken (10) and LDM Rd,@Rs,#n (11+3n), whose repeated
// part is asked for n times in all. A zero shift count costs one position.
//
// Run: make test-seq-paths

module tb_seq_paths
  import z8000_zbus_pkg::*, z8000_mc_pkg::*;
#(parameter bit SEGMENTED = 1'b0);
  logic clk = 1'b0;
  always #5 clk = ~clk;
  // Master clock: 5 per CLK, off CLK's edges.
  logic mclk = 1'b0;
  initial begin #0.5; forever #1 mclk = ~mclk; end
  // The board's CLK edge pulses: High for the master clock in which CLK is
  // first seen High, or Low.
  logic clk_pq = 1'b0;
  always @(posedge mclk) clk_pq <= clk;
  wire  clk_rise = clk & ~clk_pq;
  wire  clk_fall = ~clk & clk_pq;

  logic        reset_n;
  logic [15:0] ad_in;
  logic [15:0] ad_out;
  logic        ad_drive, bus_drive;
  logic [6:0]  sn;
  logic        as_n, ds_n, mreq_n, r_w, b_w, n_s;
  logic [3:0]  st;
  logic        busack_n, mo_n;

  z8000_cpu #(.SEGMENTED(SEGMENTED), .VMPU(1'b0)) dut (
    .clk(mclk), .clk_rise(clk_rise), .clk_fall(clk_fall), .reset_n(reset_n),
    .ad_in(ad_in), .stop_n(1'b1), .wait_n(1'b1), .busreq_n(1'b1),
    .nmi_n(1'b1), .nvi_n(1'b1), .vi_n(1'b1), .segt_n(1'b1),
    .abort_n(1'b1), .mi_n(1'b1),
    .ad_out(ad_out), .ad_drive(ad_drive), .bus_drive(bus_drive), .sn(sn),
    .as_n(as_n), .ds_n(ds_n), .mreq_n(mreq_n),
    .r_w(r_w), .b_w(b_w), .n_s(n_s), .st(st),
    .busack_n(busack_n), .mo_n(mo_n)
  );

  localparam logic [15:0] PROG = 16'h0100;
  logic [15:0] mem [0:255];
  logic [15:0] lat_addr;
  logic        as_q;
  logic        if1_now = 1'b0;   // an IF1 /AS fall in this clock
  // Sampled mid-clock: /AS is Low only in T1's first half.
  always @(negedge clk) begin
    if1_now <= as_q && !as_n && st == ST_INSTR_FETCH_FIRST;
    if (as_q && !as_n && ad_drive) lat_addr <= ad_out;
    as_q <= as_n;
  end
  assign ad_in = mem[lat_addr[8:1]];

  int unsigned failed = 0, passed = 0;
  logic        chk_seen = 1'b0;

  // A DUT self-check (the %Error lines) fails the case that first trips it.
  // Run on past the measured clocks first: the shifter's last clock comes
  // after the next IF1 T1, and the next case's reset would cut it off.
  string last_name = "";
  task automatic settle();
    repeat (8) @(posedge clk);
    dut_checks(last_name);
  endtask

  task automatic dut_checks(input string name);
    if (!chk_seen && (dut.check_q || dut.u_execute.check_q || dut.u_sequencer.check_q)) begin
      chk_seen = 1'b1;
      failed++;
      $display("FAIL  %s: DUT self-check fired", name);
    end
  endtask

  // Clocks from the first IF1 T1 at PROG to the next IF1 T1.
  task automatic run(input string name, input logic [15:0] fcw,
                     input logic [15:0] w0, w1, input int want,
                     input mc_path_e path = MC_PATH_DEFAULT);
    int i, t0;
    if (last_name != "") settle();
    last_name = name;
    for (i = 0; i < 256; i++) mem[i] = 16'h0000;
    // Z8001 PSA: FCW, PC segment, PC offset; segmented mode.
    if (SEGMENTED) begin
      mem[1] = fcw | 16'h8000;
      mem[2] = 16'h0000;
      mem[3] = PROG;
    end else begin
      mem[1] = fcw;
      mem[2] = PROG;
    end
    mem[(PROG >> 1) + 0] = w0;
    mem[(PROG >> 1) + 1] = w1;
    reset_n = 1'b0;
    repeat (4) @(posedge clk);
    reset_n = 1'b1;
    t0 = -1;
    for (i = 0; i < 400; i++) begin
      @(negedge clk);
      #1;
      if (if1_now) begin
        if (t0 >= 0) break;
        t0 = i;
      end
    end
    if (want == 0) begin
      // Stopped at a data cycle: no next IF1.
      if (i != 400 || dut.u_sequencer.path_q != path) begin
        failed++;
        $display("FAIL  %s: next IF1 %0d, path %0d", name, i, dut.u_sequencer.path_q);
      end else begin
        passed++;
      end
    end else if (i == 400 || i - t0 != want) begin
      failed++;
      $display("FAIL  %s: %0d clocks, want %0d", name, i == 400 ? -1 : i - t0, want);
    end else begin
      passed++;
    end
  endtask

  // LDM: with `iter` repetitions started, another is asked for while
  // iter < n.
  task automatic ldm(input string name, input logic [15:0] w1, input int n);
    int k, bad;
    run(name, FCW, 16'h1C21, w1, 11 + 3 * n);
    bad = 0;
    for (k = 0; k <= 17; k++) begin
      force dut.u_sequencer.iter_q = 5'(k);
      #0.01;   // all counts inside the one clock
      if (dut.more !== (k < n)) bad++;
    end
    release dut.u_sequencer.iter_q;
    if (bad != 0) begin
      failed++;
      $display("FAIL  %s: more wrong for %0d repetition counts", name, bad);
    end else begin
      passed++;
    end
  endtask

  localparam logic [15:0] FCW   = 16'h4000;   // system, nonsegmented
  localparam logic [15:0] FCW_Z = 16'h4040;   // ... Z set
  localparam logic [15:0] FCW_C = 16'h4080;   // ... C set
  // Segmented: JP cc,@RR2, taken in 15 clocks; RET taken in 13.
  localparam logic [15:0] JP_RS = SEGMENTED ? 16'h0010 : 16'h0000;
  localparam int JP_T  = SEGMENTED ? 15 : 10;
  localparam int RET_T = SEGMENTED ? 13 : 10;

  initial begin
    reset_n = 1'b0;
    as_q = 1'b1;
    lat_addr = 16'h0000;

    run("JP F,@R1",       FCW,   16'h1E10 + JP_RS, 16'h0000, 7);
    run("JP T,@R1",       FCW,   16'h1E18 + JP_RS, 16'h0000, JP_T);
    run("JP Z,@R1 Z=1",   FCW_Z, 16'h1E16 + JP_RS, 16'h0000, JP_T);
    run("JP Z,@R1 Z=0",   FCW,   16'h1E16 + JP_RS, 16'h0000, 7);
    run("JP NC,@R1 C=1",  FCW_C, 16'h1E1F + JP_RS, 16'h0000, 7);
    run("JP UGT,@R1 Z=1", FCW_Z, 16'h1E1B + JP_RS, 16'h0000, 7);
    run("JP UGT,@R1",     FCW,   16'h1E1B + JP_RS, 16'h0000, JP_T);
    run("RET F",          FCW,   16'h9E00, 16'h0000, 7);
    run("RET T",          FCW,   16'h9E08, 16'h0000, RET_T);
    run("RET ULE C=1",    FCW_C, 16'h9E03, 16'h0000, RET_T);
    ldm("LDM R3,@R2,#1",  16'h0300, 1);
    ldm("LDM R3,@R2,#3",  16'h0302, 3);
    ldm("LDM R0,@R2,#16", 16'h000F, 16);
    run("SLA R1,#5",      FCW,   16'hB319, 16'h0005, 28);
    run("SLA R1,#0",      FCW,   16'hB319, 16'h0000, 16);
    run("SRA R1,#3",      FCW,   16'hB319, 16'hFFFD, 22);
    run("SLAL RR2,#32",   FCW,   16'hB32D, 16'h0020, 109);

    settle();
    if (failed == 0) $display("RESULT PASS  tb_seq_paths  %0d cases", passed);
    else             $display("RESULT FAIL  tb_seq_paths  %0d of %0d cases", failed, passed + failed);
    $finish;
  end
endmodule
