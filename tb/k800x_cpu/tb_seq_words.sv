// tb_seq_words -- instruction-word capture for address-bearing forms.
//
// Runs one instruction per case on a Z8001 with the sequencer forced to walk
// its program, and checks, on the edge its last word is taken, the address
// register and the other words. Memory operands are not run yet, so no pin
// vector reaches these registers.
//
// Run: make test-seq-words

module tb_seq_words;
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

  z8000_cpu #(.SEGMENTED(1'b1), .VMPU(1'b0)) dut (
    .clk(clk), .reset_n(reset_n),
    .ad_in(ad_in), .stop_n(1'b1), .wait_n(1'b1), .busreq_n(1'b1),
    .nmi_n(1'b1), .nvi_n(1'b1), .vi_n(1'b1), .segt_n(1'b1),
    .abort_n(1'b1), .mi_n(1'b1),
    .ad_out(ad_out), .ad_drive(ad_drive), .sn(sn),
    .as_n(as_n), .ds_n(ds_n), .mreq_n(mreq_n),
    .r_w(r_w), .b_w(b_w), .n_s(n_s), .st(st),
    .busack_n(busack_n), .mo_n(mo_n)
  );

  // Program memory in segment 0; the latched offset selects the word.
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
  logic [15:0] pc_seg = 16'h0000;           // PSA PC segment word

  task automatic run(input string name, input logic [15:0] fcw, input int n,
                     input logic [15:0] w0, w1, w2, w3,
                     input logic [22:0] ea, input logic [15:0] ir1, ir2);
    int i;
    for (i = 0; i < 256; i++) mem[i] = 16'h0000;
    mem[1] = fcw;
    mem[2] = pc_seg;
    mem[3] = PROG;
    mem[(PROG >> 1) + 0] = w0;
    mem[(PROG >> 1) + 1] = w1;
    mem[(PROG >> 1) + 2] = w2;
    mem[(PROG >> 1) + 3] = w3;
    reset_n = 1'b0;
    repeat (4) @(posedge clk);
    reset_n = 1'b1;
    for (i = 0; i < 200; i++) begin
      @(posedge clk);
      #1;
      if (dut.pc[15:0] == PROG + 16'(2 * n)) break;
    end
    if (i == 200 || dut.u_sequencer.ir0_q != w0 || dut.u_sequencer.ea_q != ea ||
        dut.u_sequencer.ir1_q != ir1 || dut.u_sequencer.ir2_q != ir2) begin
      failed++;
      $display("FAIL  %s: ea %h ir1 %h ir2 %h, want ea %h ir1 %h ir2 %h%s",
               name, dut.u_sequencer.ea_q, dut.u_sequencer.ir1_q, dut.u_sequencer.ir2_q,
               ea, ir1, ir2, i == 200 ? "  (words not all taken)" : "");
    end else begin
      passed++;
    end
  endtask

  localparam logic [15:0] SEG = 16'hC000;   // system, segmented
  localparam logic [15:0] NS  = 16'h4000;   // system, nonsegmented

  initial begin
    reset_n = 1'b0;
    as_q = 1'b1;
    lat_addr = 16'h0000;
    force dut.u_sequencer.run_ok = 1'b1;

    // Four words: segmented long address with an immediate or a second word.
    run("CP DA,#imm SL",   SEG, 4, 16'h4D01, 16'h8500, 16'h1234, 16'hBEEF, 23'h051234, 16'hBEEF, 16'h0000);
    run("LD X,#imm SL",    SEG, 4, 16'h4D25, 16'h8500, 16'h1234, 16'hBEEF, 23'h051234, 16'hBEEF, 16'h0000);
    run("LDB X,#imm SL",   SEG, 4, 16'h4C25, 16'hFF00, 16'hFFFE, 16'hABAB, 23'h7FFFFE, 16'hABAB, 16'h0000);
    run("CPB DA,#imm SL",  SEG, 4, 16'h4C01, 16'h8100, 16'h0002, 16'h5A5A, 23'h010002, 16'h5A5A, 16'h0000);
    run("LDM R,DA SL",     SEG, 4, 16'h5C01, 16'h0302, 16'h8700, 16'h4567, 23'h074567, 16'h0302, 16'h0000);
    run("LDM X,R SL",      SEG, 4, 16'h5C19, 16'h0302, 16'h8700, 16'h4567, 23'h074567, 16'h0302, 16'h0000);
    run("EPU DA SL",       SEG, 4, 16'h4E00, 16'hABCD, 16'h8100, 16'h2222, 23'h012222, 16'hABCD, 16'h0000);
    run("EPU X to mem SL", SEG, 4, 16'h4E18, 16'hABCD, 16'h8100, 16'h2222, 23'h012222, 16'hABCD, 16'h0000);
    // Short offset: segment and offset in one word.
    run("CP DA,#imm SS",   SEG, 3, 16'h4D01, 16'h0512, 16'hBEEF, 16'h0000, 23'h050012, 16'hBEEF, 16'h0000);
    run("LDM R,DA SS",     SEG, 3, 16'h5C01, 16'h0302, 16'h0745, 16'h0000, 23'h070045, 16'h0302, 16'h0000);
    run("LD R,DA SS",      SEG, 2, 16'h6101, 16'h7FFF, 16'h0000, 16'h0000, 23'h7F00FF, 16'h0000, 16'h0000);
    run("LD R,DA SL",      SEG, 3, 16'h6101, 16'hFF00, 16'h89AB, 16'h0000, 23'h7F89AB, 16'h0000, 16'h0000);
    // Nonsegmented: one address word.
    run("CP DA,#imm NS",   NS,  3, 16'h4D01, 16'h1234, 16'hBEEF, 16'h0000, 23'h001234, 16'hBEEF, 16'h0000);
    run("LDM R,DA NS",     NS,  3, 16'h5C01, 16'h0302, 16'h4567, 16'h0000, 23'h004567, 16'h0302, 16'h0000);
    run("EPU DA NS",       NS,  3, 16'h4E00, 16'hABCD, 16'hFEDC, 16'h0000, 23'h00FEDC, 16'hABCD, 16'h0000);
    pc_seg = 16'h0300;                       // the address takes the PC's segment
    run("CP DA,#imm NS seg 3", NS, 3, 16'h4D01, 16'h1234, 16'hBEEF, 16'h0000, 23'h031234, 16'hBEEF, 16'h0000);
    pc_seg = 16'h0000;
    // No address: immediates fill words 1 and 2.
    run("LDL RR,#imm32",   SEG, 3, 16'h1402, 16'h1111, 16'h2222, 16'h0000, 23'h000000, 16'h1111, 16'h2222);

    if (failed == 0) $display("RESULT PASS  tb_seq_words  %0d cases", passed);
    else             $display("RESULT FAIL  tb_seq_words  %0d of %0d cases", failed, passed + failed);
    $finish;
  end
endmodule
