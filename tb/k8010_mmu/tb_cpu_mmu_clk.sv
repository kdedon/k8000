// tb_cpu_mmu_clk -- a Z8001 (z8000_cpu) and a Z8010 (z8010_mmu) on ONE CLK net.
//
// Both chips run on the master clock `mclk` and see the same CLK
// rising-edge pulse, made by a board divider flop in the master domain; the
// CPU also takes the falling-edge pulse. The CPU raises /AS on T1's CLK
// fall and takes read data as CLK falls in T3; the MMU latches
// the offset at the /AS rise (z8010_mmu.pdf p.571, p.573 #13/#14) and
// drives A23-A8 from it, so that CLK rise must already see the right
// physical address.
//
// A board address latch (A7-A0 follow AD7-AD0 while /AS is Low) and a word
// memory sit on {A23..A8, A7..A0}. The program, from the reset vector:
//   pass-through (MSEN set at reset by /CS Low): first fetch at 00:0038,
//   then SOUTB to the MMU (port low byte F0): SAR=0, descriptor 0 = base
//   0000 limit FF; SAR=5, descriptor 5 = base 1200 limit FF; Mode = C0
//   (MSEN|TRNS); then LD R1,@RR2 at 05:1234 (-> 12:1234), SINB RH1 from the
//   MMU's Mode register, LD @RR2,R1 at 05:1236 (-> 12:1236), JR to itself.
// Checks, at every CLK rise while /DS is Low in a memory cycle: PA is driven
// and {A23..A8, A7..A0} equals the bench's own translation of the CPU's
// logical address. Plus: the first IF1 is at 00:0038, the translated read
// and write hit 12:1234 / 12:1236, and the word written is C0EF (EF from
// 12:1234, C0 read back from the MMU over AD15-AD8).
// Runs master:CLK 2:1, 3:1, 4:1, 5:1, 7:1, an uneven 2,3,2,4 pattern, and 1:1
// with the rise and fall pulses in every master clock. Not a mix of 1 and
// more: SN, driven in a T1-opening master clock, misses the MMU's sample at
// that rise when /AS then rises on a later fall.
//
// Run: make test-cpu-mmu-clk

`default_nettype none

module tb_cpu_mmu_clk;

  logic mclk = 1'b0;
  always #1 mclk = ~mclk;

  // ---- board CLK divider: pulses on the master clocks where CLK rises, falls --
  int gaps[$];        // master clocks between CLK rises, cycled
  int gap_i = 0;
  int cur   = 0;      // master clocks in this CLK period
  int pos   = 0;      // master clock within it
  logic clk_rise = 1'b0, clk_fall = 1'b0;
  always @(posedge mclk) begin
    if (gaps.size() == 0) begin
      clk_rise <= 1'b0;
      clk_fall <= 1'b0;
    end else begin
      int c;
      c = (pos == 0) ? gaps[gap_i] : cur;
      if (pos == 0) begin
        cur   <= c;
        gap_i <= (gap_i + 1) % gaps.size();
      end
      clk_rise <= pos == 0;
      clk_fall <= pos == c / 2;
      pos      <= (pos + 1 >= c) ? 0 : pos + 1;
    end
  end

  logic reset_n = 1'b0;

  // ---- CPU ----------------------------------------------------------------------
  logic [15:0] ad_in;
  logic [15:0] ad_out;
  logic        ad_drive, bus_drive;
  logic [6:0]  sn;
  logic        as_n, ds_n, mreq_n, r_w, b_w, n_s;
  logic [3:0]  st;
  logic        busack_n, mo_n;
  logic        segt_n, sup_n;

  z8000_cpu #(.SEGMENTED(1'b1), .VMPU(1'b0)) cpu (
    .clk(mclk), .clk_rise(clk_rise), .clk_fall(clk_fall), .reset_n(reset_n),
    .ad_in(ad_in), .stop_n(1'b1), .wait_n(1'b1), .busreq_n(1'b1),
    .nmi_n(1'b1), .nvi_n(1'b1), .vi_n(1'b1), .segt_n(segt_n),
    .abort_n(1'b1), .mi_n(1'b1),
    .ad_out(ad_out), .ad_drive(ad_drive), .bus_drive(bus_drive), .sn(sn),
    .as_n(as_n), .ds_n(ds_n), .mreq_n(mreq_n),
    .r_w(r_w), .b_w(b_w), .n_s(n_s), .st(st),
    .busack_n(busack_n), .mo_n(mo_n)
  );

  // ---- MMU ----------------------------------------------------------------------
  localparam logic [3:0] ST_SIO = 4'h3;
  logic [15:0] bus;
  logic [15:0] pa;
  logic        pa_drive;
  logic [7:0]  mmu_data, mmu_data_drive;
  // /CS: special I/O to a port whose low byte is F0; held Low during reset
  // so the MMU comes up with MSEN set.
  wire cs_n = reset_n ? !(st == ST_SIO && ad_drive && ad_out[7:0] == 8'hF0) : 1'b0;

  z8010_mmu mmu (
    .clk(mclk), .clk_in(clk_rise), .reset_n(reset_n),
    .ad(bus[15:8]), .sn(sn), .st(st), .as_n(as_n), .ds_n(ds_n),
    .r_w(r_w), .n_s(n_s), .cs_n(cs_n), .dmasync(1'b1),
    .pa(pa), .pa_drive(pa_drive), .segt_n(segt_n), .sup_n(sup_n),
    .data(mmu_data), .data_drive(mmu_data_drive)
  );

  // ---- board: A7-A0 latch, physical address, memory -------------------------------
  logic [15:0] lat_ad;      // follows AD while /AS is Low
  logic [6:0]  lat_sn;
  logic [3:0]  lat_st;
  always @(posedge mclk) if (!as_n) begin
    lat_ad <= ad_out;
    lat_sn <= sn;
    lat_st <= st;
  end
  wire        mem_cyc = lat_st >= 4'h8 && lat_st <= 4'hD;
  wire [23:0] phys    = pa_drive ? {pa, lat_ad[7:0]} : 24'hFFFFFF;

  logic [15:0] mem [int unsigned];
  wire  mem_rd = !ds_n && r_w && mem_cyc;
  logic [15:0] mem_q;
  always_comb begin
    mem_q = 16'hFFFF;
    if (mem.exists(int'(phys[23:1]))) mem_q = mem[int'(phys[23:1])];
  end
  always_comb begin
    ad_in = 16'hFFFF;
    if (mem_rd) ad_in = mem_q;
    for (int i = 0; i < 8; i++) if (mmu_data_drive[i]) ad_in[8 + i] = mmu_data[i];
  end
  assign bus = ad_drive ? ad_out : ad_in;

  always @(posedge mclk) if (!ds_n && !r_w && mem_cyc && pa_drive) mem[int'(phys[23:1])] <= ad_out;

  // ---- the bench's own translation --------------------------------------------------
  logic trns = 1'b0;      // set when the CPU writes Mode with TRNS
  always @(posedge mclk) if (!reset_n) trns <= 1'b0;
    else if (!ds_n && !r_w && lat_st == ST_SIO && lat_ad == 16'h00F0) trns <= ad_out[14];
  function automatic logic [23:0] expect_phys(input logic [6:0] s, input logic [15:0] off);
    logic [15:0] base;
    if (!trns) return {1'b0, s, off};
    base = (s == 7'd5) ? 16'h1200 : 16'h0000;
    return {base + {8'h00, off[15:8]}, off[7:0]};
  endfunction

  int checks, low_checks, fails, if1_seen, rd_hit, wr_hit, loops;
  logic [23:0] first_if1;
  logic clr = 1'b0;      // the run task clears the counters through this
  always @(posedge mclk) if (clr) begin
    checks = 0; low_checks = 0; fails = 0; if1_seen = 0; rd_hit = 0; wr_hit = 0; loops = 0; first_if1 = 24'h0;
  end else if (reset_n && !as_n && st >= 4'h8 && st <= 4'hD) begin
    // A23-A8 are driven and valid from the master clock that sees /AS Low.
    logic [23:0] want;
    want = expect_phys(sn, ad_out);
    low_checks++;
    if (!pa_drive || pa != want[23:8]) begin
      fails++;
      if (fails <= 8)
        $display("    FAIL t=%0t /AS Low st=%h logical %02h:%04h: PA %s %04h, want %04h", $time, st,
                 sn, ad_out, pa_drive ? "drives" : "floats", pa, want[23:8]);
    end
  end else if (reset_n && clk_rise && !ds_n && mem_cyc) begin
    logic [23:0] want;
    want = expect_phys(lat_sn, lat_ad);
    checks++;
    if (!pa_drive || phys != want) begin
      fails++;
      if (fails <= 8)
        $display("    FAIL t=%0t st=%h logical %02h:%04h: PA %s %06h, want %06h", $time, lat_st,
                 lat_sn, lat_ad, pa_drive ? "drives" : "floats", phys, want);
    end
    if (lat_st == 4'hD && if1_seen == 0) begin first_if1 = phys; if1_seen = 1; end
    if (lat_st == 4'hD && phys == 24'h00008A) loops++;
    if (r_w  && phys == 24'h121234) rd_hit++;
    if (!r_w && phys == 24'h121236) wr_hit++;
  end

  // ---- program ------------------------------------------------------------------
  task automatic load_program();
    logic [15:0] p [$];
    mem.delete();
    mem[1] = 16'hC000;        // 0002 FCW: segmented, system
    mem[2] = 16'h0000;        // 0004 PC segment 0
    mem[3] = 16'h0038;        // 0006 PC offset
    p = '{16'hC000,                      // 0038 LDB RH0,#00
          16'h3A07, 16'h01F0,            //      SOUTB #01F0,RH0   SAR = 0
          16'h3A07, 16'h0FF0,            //      SOUTB #0FF0,RH0   base hi 00
          16'h3A07, 16'h0FF0,            //                        base lo 00
          16'hC0FF,                      //      LDB RH0,#FF
          16'h3A07, 16'h0FF0,            //                        limit FF
          16'hC000,
          16'h3A07, 16'h0FF0,            //                        attr 00
          16'hC005,
          16'h3A07, 16'h01F0,            //      SAR = 5
          16'hC012,
          16'h3A07, 16'h0FF0,            //                        base hi 12
          16'hC000,
          16'h3A07, 16'h0FF0,            //                        base lo 00
          16'hC0FF,
          16'h3A07, 16'h0FF0,            //                        limit FF
          16'hC000,
          16'h3A07, 16'h0FF0,            //                        attr 00
          16'hC0C0,
          16'h3A07, 16'h00F0,            //      Mode = C0 (MSEN|TRNS)
          16'h2102, 16'h0500,            // 0076 LD R2,#0500
          16'h2103, 16'h1234,            //      LD R3,#1234
          16'h2121,                      // 007E LD R1,@RR2        05:1234
          16'h3A15, 16'h00F0,            //      SINB RH1,#00F0    Mode -> RH1
          16'h2103, 16'h1236,            //      LD R3,#1236
          16'h2F21,                      // 0088 LD @RR2,R1        05:1236
          16'hE8FF};                     // 008A JR $
    foreach (p[i]) mem[32'h1C + i] = p[i];
    mem[32'h121234 >> 1] = 16'hBEEF;     // physical 12:1234
  endtask

  int total_fail = 0;
  task automatic run(input string name, input int pat[$]);
    gaps.delete();
    reset_n = 1'b0;
    clr = 1'b1;
    load_program();
    foreach (pat[i]) gaps.push_back(pat[i]);
    gap_i = 0; pos = 0;
    repeat (20 * 8) @(posedge mclk);
    clr = 1'b0;
    reset_n = 1'b1;
    for (int k = 0; k < 400000 && loops < 3; k++) @(posedge mclk);
    if (fails == 0 && low_checks > 0 && if1_seen && first_if1 == 24'h000038 && rd_hit > 0 && wr_hit > 0 && loops >= 3
        && mem.exists(32'h121236 >> 1) && mem[32'h121236 >> 1] == 16'hC0EF)
      $display("  PASS  %-10s %0d PA checks (%0d with /AS Low), first IF1 %h, read 12:1234, read Mode C0, wrote 12:1236 = C0EF",
               name, checks, low_checks, first_if1);
    else begin
      total_fail++;
      $display("  FAIL  %-10s checks=%0d fails=%0d first IF1 %h (seen %0d) rd=%0d wr=%0d loops=%0d word=%04h",
               name, checks, fails, first_if1, if1_seen, rd_hit, wr_hit, loops,
               mem.exists(32'h121236 >> 1) ? mem[32'h121236 >> 1] : 16'hXXXX);
    end
  endtask

  initial begin
    $display("tb_cpu_mmu_clk -- Z8001 + Z8010 on one CLK net");
    run("2:1",     '{2});
    run("3:1",     '{3});
    run("4:1",     '{4});
    run("5:1",     '{5});
    run("7:1",     '{7});
    run("2,3,2,4", '{2, 3, 2, 4});
    run("1:1",     '{1});
    if (total_fail == 0) $display("RESULT PASS  tb_cpu_mmu_clk  7 ratios");
    else                 $display("RESULT FAIL  tb_cpu_mmu_clk  %0d/7 ratios failed", total_fail);
    $finish;
  end

endmodule

`default_nettype wire
