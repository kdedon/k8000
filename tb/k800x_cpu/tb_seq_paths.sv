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
;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic        reset_n;
  logic [15:0] ad_in;
  logic [15:0] ad_out;
  logic        ad_drive;
  logic [6:0]  sn;
  logic        as_n, ds_n, mreq_n, r_w, b_w, n_s;
  logic [3:0]  st;
  logic        busack_n, mo_n;

  z8000_cpu #(.SEGMENTED(1'b0), .VMPU(1'b0)) dut (
    .clk(clk), .reset_n(reset_n),
    .ad_in(ad_in), .stop_n(1'b1), .wait_n(1'b1), .busreq_n(1'b1),
    .nmi_n(1'b1), .nvi_n(1'b1), .vi_n(1'b1), .segt_n(1'b1),
    .abort_n(1'b1), .mi_n(1'b1),
    .ad_out(ad_out), .ad_drive(ad_drive), .sn(sn),
    .as_n(as_n), .ds_n(ds_n), .mreq_n(mreq_n),
    .r_w(r_w), .b_w(b_w), .n_s(n_s), .st(st),
    .busack_n(busack_n), .mo_n(mo_n)
  );

  localparam logic [15:0] PROG = 16'h0100;
  logic [15:0] mem [0:255];
  logic [15:0] lat_addr;
  logic        as_q;
  always @(posedge clk) begin
    if (as_q && !as_n && ad_drive) lat_addr <= ad_out;
    as_q <= as_n;
  end
  assign ad_in = mem[lat_addr[8:1]];

  int unsigned failed = 0, passed = 0;

  // Clocks from the first IF1 T1 at PROG to the next IF1 T1.
  task automatic run(input string name, input logic [15:0] fcw,
                     input logic [15:0] w0, w1, input int want,
                     input mc_path_e path = MC_PATH_DEFAULT);
    int i, t0;
    for (i = 0; i < 256; i++) mem[i] = 16'h0000;
    mem[1] = fcw;
    mem[2] = PROG;
    mem[(PROG >> 1) + 0] = w0;
    mem[(PROG >> 1) + 1] = w1;
    reset_n = 1'b0;
    repeat (4) @(posedge clk);
    reset_n = 1'b1;
    t0 = -1;
    for (i = 0; i < 400; i++) begin
      @(posedge clk);
      #1;
      if (as_q && !as_n && st == ST_INSTR_FETCH_FIRST) begin
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
      force dut.u_sequencer.iter_q = 6'(k);
      #1;
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

  initial begin
    reset_n = 1'b0;
    as_q = 1'b1;
    lat_addr = 16'h0000;
    force dut.u_sequencer.run_ok = 1'b1;

    run("JP F,@R1",       FCW,   16'h1E10, 16'h0000, 7);
    run("JP T,@R1",       FCW,   16'h1E18, 16'h0000, 10);
    run("JP Z,@R1 Z=1",   FCW_Z, 16'h1E16, 16'h0000, 10);
    run("JP Z,@R1 Z=0",   FCW,   16'h1E16, 16'h0000, 7);
    run("JP NC,@R1 C=1",  FCW_C, 16'h1E1F, 16'h0000, 7);
    run("JP UGT,@R1 Z=1", FCW_Z, 16'h1E1B, 16'h0000, 7);
    run("JP UGT,@R1",     FCW,   16'h1E1B, 16'h0000, 10);
    run("RET F",          FCW,   16'h9E00, 16'h0000, 7);
    run("RET T",          FCW,   16'h9E08, 16'h0000, 10);
    run("RET ULE C=1",    FCW_C, 16'h9E03, 16'h0000, 10);
    ldm("LDM R3,@R2,#1",  16'h0300, 1);
    ldm("LDM R3,@R2,#3",  16'h0302, 3);
    ldm("LDM R0,@R2,#16", 16'h000F, 16);
    run("SLA R1,#5",      FCW,   16'hB319, 16'h0005, 28);
    run("SLA R1,#0",      FCW,   16'hB319, 16'h0000, 16);
    run("SRA R1,#3",      FCW,   16'hB319, 16'hFFFD, 22);
    run("SLAL RR2,#32",   FCW,   16'hB32D, 16'h0020, 109);

    if (failed == 0) $display("RESULT PASS  tb_seq_paths  %0d cases", passed);
    else             $display("RESULT FAIL  tb_seq_paths  %0d of %0d cases", failed, passed + failed);
    $finish;
  end
endmodule
