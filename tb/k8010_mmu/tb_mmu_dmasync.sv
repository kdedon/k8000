// tb_mmu_dmasync -- Z8010 DMASYNC hand-back against the next CPU cycle.
//
// z8010_mmu.pdf (00-2046-03): DMASYNC is taken at the CLK rise (AC #20/#22
// p.573, waveform p.572); >= 2 Low samples then High presents a DMA address
// (p.566); it must be High during CPU cycles (p.571). A DMASYNC pulse seen
// on one or two CLK rises, then Low, must not keep the next /AS cycle from
// being latched and translated. A DMA cycle with DMASYNC dropped after the
// address sample keeps PA and /SUP to its /DS rise; one whose master drives
// /AS across that Low sample raises no /SEGT (p.565).
// With DMASYNC = /BUSACK, a /AS after the second DMASYNC-High rise is the
// CPU's (p.566).
//
// Every case runs at 1, 2, 3, 5 and 8 master clocks per CLK.
//
// Run: make test-mmu-dmasync

`default_nettype none
module tb_mmu_dmasync;

  logic mclk = 1'b0;
  always #5 mclk = ~mclk;

  // CLK rise pulse every `div` master clocks.
  int   div = 2;
  int   cnt = 0;
  logic clk_in = 1'b0;
  always @(posedge mclk) begin
    cnt    <= (cnt + 1 >= div) ? 0 : cnt + 1;
    clk_in <= (cnt + 1 >= div);
  end

  logic       reset_n = 1'b0;
  logic [7:0] ad = 8'h00;
  logic [6:0] sn = 7'h00;
  logic [3:0] st = 4'h0;
  logic       as_n = 1'b1, ds_n = 1'b1, r_w = 1'b1, cs_n = 1'b1;
  logic       dmasync = 1'b1;

  logic [15:0] pa;
  logic        pa_drive, segt_n, sup_n;
  logic [7:0]  data, data_drive;

  z8010_mmu dut (
    .clk(mclk), .clk_in(clk_in), .reset_n(reset_n),
    .ad(ad), .sn(sn), .st(st), .as_n(as_n), .ds_n(ds_n), .r_w(r_w), .n_s(1'b0),
    .cs_n(cs_n), .dmasync(dmasync),
    .pa(pa), .pa_drive(pa_drive), .segt_n(segt_n), .sup_n(sup_n),
    .data(data), .data_drive(data_drive)
  );

  localparam logic [3:0] ST_SIO = 4'h3;
  localparam logic [3:0] ST_MEM = 4'h8;

  localparam int DIVS [5] = '{1, 2, 3, 5, 8};

  int unsigned checks = 0, fails = 0;
  task automatic ck(input bit ok, input string name, input string detail);
    checks++;
    if (!ok) begin
      fails++;
      $display("  FAIL  div %0d  %s: %s", div, name, detail);
    end
  endtask

  task automatic rise();
    @(posedge mclk iff clk_in); #1;
  endtask

  // One Z-Bus cycle: /AS Low for T1, /DS Low for T2-T3. PA is sampled in
  // the master clock after the /AS rise and again with /DS Low. A command
  // cycle (ST 3) puts `d` on AD for its data phase.
  task automatic cycle(input logic [3:0] s, input logic [6:0] seg, input logic [7:0] a,
                       input logic rd, input logic [7:0] d,
                       output logic [15:0] pa_as, output logic drv_as,
                       output logic [15:0] pa_ds, output logic drv_ds);
    st = s; sn = seg; ad = a; r_w = rd; cs_n = (s != ST_SIO); as_n = 1'b0;
    rise(); as_n = 1'b1;
    @(posedge mclk); #1; pa_as = pa; drv_as = pa_drive;
    if (s == ST_SIO) ad = d;
    rise(); ds_n = 1'b0;
    @(posedge mclk); #1; pa_ds = pa; drv_ds = pa_drive;
    rise(); rise(); ds_n = 1'b1; cs_n = 1'b1;
    rise();
  endtask

  task automatic cmd(input logic [7:0] c, input logic [7:0] d);
    logic [15:0] p1, p2; logic v1, v2;
    rise();
    cycle(ST_SIO, 7'h00, c, 1'b0, d, p1, v1, p2, v2);
  endtask

  // A CPU read of segment `seg`, page `page`, starting at the next CLK rise
  // (or at once when `now`); PA must be `want` and driven at both samples.
  task automatic cpu_read(input bit now, input logic [6:0] seg, input logic [7:0] page,
                          input logic [15:0] want, input string what);
    logic [15:0] p1, p2; logic v1, v2;
    if (!now) rise();
    cycle(ST_MEM, seg, page, 1'b1, 8'h00, p1, v1, p2, v2);
    ck(v1 && p1 == want, {what, ", /AS rise"}, $sformatf("pa %04h drive %0b, want %04h", p1, v1, want));
    ck(v2 && p2 == want, {what, ", /DS Low"},  $sformatf("pa %04h drive %0b, want %04h", p2, v2, want));
  endtask

  // DMASYNC at its active level for `n` CLK rises with a DMA master's word
  // on AD, then back at `idle` for `gap` more rises before the CPU cycle's
  // T1 rise. With `then_as` the CPU's /AS falls right after the rise that
  // first sees DMASYNC back.
  task automatic pulse(input logic idle, input int n, input int gap, input bit then_as,
                       input logic [6:0] seg, input logic [7:0] page, input logic [15:0] want,
                       input string what);
    dmasync = idle;
    rise(); rise(); rise();
    dmasync = ~idle; ad = 8'h14; sn = 7'h00; st = ST_MEM;
    repeat (n) rise();
    dmasync = idle;
    rise();
    repeat (gap) rise();
    cpu_read(then_as, seg, page, want, what);
    cpu_read(1'b0, seg, page, want, {what, ", next cycle"});
  endtask

  // A DMA cycle with no /AS: DMASYNC High at one CLK rise with the address,
  // Low from then on (p.572), /DS Low for two rises. PA and /SUP must hold
  // to the /DS rise.
  task automatic dma_cycle(input logic [6:0] seg, input logic [7:0] page, input logic rd,
                           input logic [15:0] want, input bit viol, input string what);
    logic [15:0] p; logic v, s1, s2, s3, v3;
    dmasync = 1'b0;
    rise(); rise(); rise();
    dmasync = 1'b1; sn = seg; ad = page; st = ST_MEM; r_w = rd;
    rise(); dmasync = 1'b0;
    @(posedge mclk); #1; s1 = sup_n;
    rise(); ds_n = 1'b0;
    @(posedge mclk); #1; p = pa; v = pa_drive; s2 = sup_n;
    rise(); rise(); ds_n = 1'b1;
    @(posedge mclk); #1; s3 = sup_n; v3 = pa_drive;
    ck(v && p == want, {what, ", PA with /DS Low"}, $sformatf("pa %04h drive %0b, want %04h", p, v, want));
    ck(s1 == !viol && s2 == !viol, {what, ", /SUP to the /DS rise"},
       $sformatf("sup_n %0b %0b, want %0b", s1, s2, !viol));
    ck(s3 && !v3, {what, ", /SUP and PA released at the /DS rise"}, $sformatf("sup_n %0b drive %0b", s3, v3));
    r_w = 1'b1;
    rise(); dmasync = 1'b1;
    rise(); rise(); rise();
  endtask

  // As dma_cycle, with the DMA master's /AS Low from after the address rise
  // to one master clock after the next rise. p.565: no Segment Trap
  // Request in a DMA cycle; /SUP to the /DS rise.
  task automatic dma_as_cycle(input logic [6:0] seg, input logic [7:0] page, input logic rd,
                              input bit viol, input string what);
    logic t1, t2, s1, s2;
    dmasync = 1'b0;
    rise(); rise(); rise();
    dmasync = 1'b1; sn = seg; ad = page; st = ST_MEM; r_w = rd;
    rise(); dmasync = 1'b0; as_n = 1'b0;
    rise(); @(posedge mclk); #1; as_n = 1'b1;
    @(posedge mclk); #1; t1 = segt_n; s1 = sup_n;
    rise(); ds_n = 1'b0;
    @(posedge mclk); #1; t2 = segt_n; s2 = sup_n;
    rise(); rise(); ds_n = 1'b1;
    ck(t1 && t2, {what, ", no /SEGT"}, $sformatf("segt_n %0b %0b", t1, t2));
    ck(s1 == !viol && s2 == !viol, {what, ", /SUP to the /DS rise"},
       $sformatf("sup_n %0b %0b, want %0b", s1, s2, !viol));
    r_w = 1'b1;
    rise(); dmasync = 1'b1;
    rise(); rise(); rise();
  endtask

  initial begin
    repeat (20) @(posedge mclk);
    reset_n = 1'b1;
    cmd(8'h00, 8'hC0);                                    // MSEN, TRNS
    cmd(8'h01, 8'h00);                                    // SAR 0
    cmd(8'h0B, 8'h00); cmd(8'h0B, 8'h20);                 // base 0x0020
    cmd(8'h0B, 8'hFF); cmd(8'h0B, 8'h00);                 // limit FF, no attributes
    cmd(8'h01, 8'h01);                                    // SAR 1
    cmd(8'h0B, 8'h01); cmd(8'h0B, 8'h00);                 // base 0x0100
    cmd(8'h0B, 8'hFF); cmd(8'h0B, 8'h01);                 // limit FF, read only

    foreach (DIVS[i]) begin
      div = DIVS[i];
      repeat (4) rise();
      // DMASYNC Low between pulses
      pulse(1'b0, 1, 0, 1'b0, 7'h00, 8'hF5, 16'h0115, "one-CLK pulse");
      pulse(1'b0, 2, 0, 1'b0, 7'h00, 8'hF5, 16'h0115, "two-CLK pulse");
      pulse(1'b0, 5, 0, 1'b0, 7'h00, 8'hF5, 16'h0115, "long pulse");
      pulse(1'b0, 1, 0, 1'b1, 7'h00, 8'hF5, 16'h0115, "one-CLK pulse ending just before /AS");
      pulse(1'b0, 2, 0, 1'b1, 7'h00, 8'hF5, 16'h0115, "two-CLK pulse ending just before /AS");
      // DMASYNC = /BUSACK (p.571): High in CPU cycles, Low through the grant
      pulse(1'b1, 1, 1, 1'b0, 7'h00, 8'h34, 16'h0054, "/BUSACK one-CLK grant");
      pulse(1'b1, 4, 1, 1'b0, 7'h00, 8'h34, 16'h0054, "/BUSACK long grant");
      // /AS after the second DMASYNC-High rise (p.566)
      pulse(1'b1, 4, 0, 1'b0, 7'h00, 8'h34, 16'h0054, "/BUSACK long grant, /AS after the second High rise");
      // DMA cycles
      dma_cycle(7'h00, 8'h14, 1'b1, 16'h0034, 1'b0, "DMA read");
      dma_cycle(7'h01, 8'h22, 1'b0, 16'h0122, 1'b1, "DMA write to read-only");
      dma_as_cycle(7'h01, 8'h22, 1'b0, 1'b1, "DMA write to read-only with /AS");
      dmasync = 1'b1;
      cpu_read(1'b0, 7'h00, 8'hF5, 16'h0115, "CPU after DMA");
      $display("  div %0d done", div);
    end

    if (fails == 0) $display("RESULT PASS  tb_mmu_dmasync  %0d checks", checks);
    else            $display("RESULT FAIL  tb_mmu_dmasync  %0d/%0d checks failed", fails, checks);
    $finish;
  end
endmodule
`default_nettype wire
