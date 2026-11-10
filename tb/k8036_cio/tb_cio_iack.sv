// tb_cio_iack -- two CIOs on one daisy chain, the first's IEO into the
// second's IEI.
//
// The second requests (C/T 1) and is acknowledged. While its vector is on
// AD, the first's C/T 1 reaches terminal count. The first's IEO must stay
// High: the AC table times IEO in an acknowledge from the /AS rise
// (TdAS(IEO)) and from IEI (TdIEI(IEO)) only, and UM0109 allows "no
// additional interrupt requests during an Interrupt Acknowledge cycle". A
// falling IEO would take IEI from the device driving its vector, and AD
// would float. The new request reaches /INT at the next /AS.
//
// Then a request arriving between an acknowledge's /AS and its /DS must
// not take that acknowledge.
//
// Each chip has its own PCLK so one counts while the other holds.
//
// Run: make test-cio-iack

`default_nettype none

module tb_cio_iack;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic [7:0] ad_in     = 8'h00;
  logic       as_n      = 1'b1;
  logic       ds_n      = 1'b1;
  logic       r_w       = 1'b1;
  logic [1:0] cs0_n     = 2'b11;
  logic       cs1       = 1'b0;
  logic       intack_n  = 1'b1;
  logic [1:0] pclk_fall = 2'b00;

  logic [7:0] ad_out [2];
  logic [1:0] ad_drive, int_n, ieo, iei;
  assign iei = {ieo[0], 1'b1};

  for (genvar i = 0; i < 2; i++) begin : g
    logic [7:0] pa_out, pa_oe, pb_out, pb_oe;
    logic [3:0] pc_out, pc_oe;
    z8036_cio u (
      .clk(clk), .ad_in(ad_in), .as_n(as_n), .ds_n(ds_n), .r_w(r_w),
      .cs0_n(cs0_n[i]), .cs1(cs1), .intack_n(intack_n), .iei(iei[i]), .pclk_fall(pclk_fall[i]),
      .pa_in(8'hFF), .pb_in(8'hFF), .pc_in(4'hF),
      .ad_out(ad_out[i]), .ad_drive(ad_drive[i]), .int_n(int_n[i]), .ieo(ieo[i]),
      .pa_out(pa_out), .pa_oe(pa_oe), .pb_out(pb_out), .pb_oe(pb_oe), .pc_out(pc_out), .pc_oe(pc_oe));
  end

  localparam logic [5:0] REG_MICR  = 6'h00;
  localparam logic [5:0] REG_MCCR  = 6'h01;
  localparam logic [5:0] REG_CTVEC = 6'h04;
  localparam logic [5:0] REG_CT1CS = 6'h0A;
  localparam logic [5:0] REG_TCMSB = 6'h16;
  localparam logic [5:0] REG_TCLSB = 6'h17;
  localparam logic [5:0] REG_CT1MS = 6'h1C;
  localparam int         CS_IUS    = 7;
  localparam int         CS_IP     = 5;

  // AD as the CPU reads it: the driving CIO, else the pull-ups.
  function automatic logic [7:0] bus();
    return ad_drive[0] ? ad_out[0] : ad_drive[1] ? ad_out[1] : 8'hFF;
  endfunction

  function automatic logic [7:0] adr(input logic [5:0] reg_no);
    return {1'b0, reg_no, 1'b1};
  endfunction

  task automatic wr(input int chip, input logic [5:0] reg_no, input logic [7:0] data);
    as_n = 1'b0; cs0_n[chip] = 1'b0; cs1 = 1'b1; r_w = 1'b0; ad_in = adr(reg_no); @(posedge clk);
    as_n = 1'b1;                                                                  @(posedge clk);
    ds_n = 1'b0; ad_in = data;                                                    @(posedge clk);
    ds_n = 1'b1;                                                                  @(posedge clk);
    cs0_n = 2'b11; cs1 = 1'b0;                                                    @(posedge clk);
  endtask

  task automatic other_cycle();
    #1; as_n = 1'b0; @(posedge clk); #1; as_n = 1'b1; repeat (2) @(posedge clk); #1;
  endtask

  // C/T 1 in continuous timer mode with time constant tc, IE set, MIE on.
  task automatic arm(input int chip, input logic [7:0] tc, input logic [7:0] vec);
    wr(chip, REG_MICR, 8'h00);
    wr(chip, REG_CT1MS, 8'h80);
    wr(chip, REG_TCMSB, 8'h00); wr(chip, REG_TCLSB, tc);
    wr(chip, REG_CTVEC, vec);
    wr(chip, REG_MCCR, 8'h40);
    wr(chip, REG_CT1CS, 8'hC6);
    wr(chip, REG_MICR, 8'h80);
  endtask

  // PCLK falls on one chip until its C/T 1 IP sets.
  task automatic count_to_ip(input int chip, output int n);
    for (n = 0; n < 64 && !(chip == 0 ? g[0].u.regs[REG_CT1CS][CS_IP] : g[1].u.regs[REG_CT1CS][CS_IP]); n++) begin
      pclk_fall[chip] = 1'b1; @(posedge clk); pclk_fall[chip] = 1'b0; @(posedge clk);
    end
    #1;
  endtask

  int checks = 0, fails = 0;
  task automatic ck(input bit ok, input string what);
    checks++;
    $display("  %s  %s", ok ? "PASS" : "FAIL", what);
    if (!ok) fails++;
  endtask

  logic [7:0] at_fall, at_rise;
  int n;

  initial begin
    repeat (2) @(posedge clk);
    as_n = 1'b0; ds_n = 1'b0; repeat (4) @(posedge clk);
    as_n = 1'b1; ds_n = 1'b1; repeat (2) @(posedge clk);
    arm(1, 8'h02, 8'h80);
    arm(0, 8'h04, 8'h40);

    $display("[1] a C/T request upstream while the downstream vector is on AD");
    count_to_ip(1, n);
    other_cycle();
    ck(int_n == 2'b01 && ieo[0], "downstream /INT Low, upstream idle with IEO High");
    #1; as_n = 1'b0; intack_n = 1'b0; @(posedge clk);
    #1; as_n = 1'b1; repeat (2) @(posedge clk);
    #1; ds_n = 1'b0; repeat (2) @(posedge clk);
    #1; at_fall = bus();
    ck(ad_drive == 2'b10 && at_fall == 8'h80, $sformatf("after /DS fall the downstream CIO drives %02h", at_fall));
    count_to_ip(0, n);
    at_rise = bus();
    ck(ieo[0], $sformatf("upstream IEO stays High after its TC (%0d PCLK falls)", n));
    ck(ad_drive == 2'b10 && at_rise == 8'h80, $sformatf("at /DS rise AD=%02h from the downstream CIO", at_rise));
    ds_n = 1'b1; @(posedge clk); intack_n = 1'b1; @(posedge clk);
    ck(!g[0].u.regs[REG_CT1CS][CS_IUS], "upstream IUS clear");
    other_cycle();
    ck(!int_n[0], "upstream /INT Low after the next /AS");
    wr(1, REG_CT1CS, 8'h60);      // clear downstream IUS

    $display("[2] a request between the acknowledge's /AS and /DS waits for the next /AS");
    wr(0, REG_CT1CS, 8'h24);      // clear upstream IP and IUS, gate kept
    wr(1, REG_CT1CS, 8'h20);      // clear downstream IP and IUS, gate off
    other_cycle();
    ck(int_n == 2'b11, "no request before the acknowledge");
    #1; as_n = 1'b0; intack_n = 1'b0; @(posedge clk);
    #1; as_n = 1'b1; @(posedge clk);
    count_to_ip(0, n);
    ds_n = 1'b0; repeat (2) @(posedge clk);
    #1;
    ck(ad_drive == 2'b00 && ieo[0], $sformatf("at /DS: drivers %02b, upstream IEO %0b", ad_drive, ieo[0]));
    ds_n = 1'b1; @(posedge clk); intack_n = 1'b1; @(posedge clk);
    ck(!g[0].u.regs[REG_CT1CS][CS_IUS], "upstream IUS clear");
    other_cycle();
    ck(!int_n[0], "upstream /INT Low after the next /AS");

    $display("");
    if (fails == 0) $display("RESULT PASS  tb_cio_iack  %0d checks", checks);
    else            $display("RESULT FAIL  tb_cio_iack  %0d/%0d checks failed", fails, checks);
    $finish;
  end
endmodule
