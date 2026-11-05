// tb_regfile -- register file semantics.
//
// The 8 Go registers tests, write-enable and read-during-write checks, and a
// seeded soak against a reference model written in the Go model's style so
// it shares no index expressions with the DUT.
// Width code 0=byte 1=word 2=long 3=quad; data right-aligned.

module tb_regfile;
  logic        clk = 0;
  logic        we;
  logic [1:0]  wwidth, rwidth;
  logic [3:0]  wsel, rsel;
  logic [63:0] wdata, rdata;
  logic        rbyte_b;
  logic [3:0]  rsel_b;
  logic [15:0] rdata_b;
  logic [15:0][1:0] nz;
  logic [15:0] r_was [16];    // the registers a clock ago, which nz follows
  always @(posedge clk) r_was <= dut.r;

  z8000_regfile dut (.clk(clk), .clk_en(1'b1), .we(we), .wwidth(wwidth), .wsel(wsel), .wdata(wdata),
                     .rwidth(rwidth), .rsel(rsel), .rdata(rdata),
                     .rbyte_b(rbyte_b), .rsel_b(rsel_b), .rdata_b(rdata_b), .nz(nz));

  int fails = 0, checks = 0;

  task automatic wr_en(input logic en, input logic [1:0] w, input logic [3:0] sel, input logic [63:0] d);
    @(negedge clk);
    we = en; wwidth = w; wsel = sel; wdata = d;
    @(posedge clk);
    #1 we = 0;
  endtask

  task automatic wr(input logic [1:0] w, input logic [3:0] sel, input logic [63:0] d);
    wr_en(1'b1, w, sel, d);
  endtask

  // read then check: settle the combinational read port, compare.
  task automatic chk_rd(input string name, input logic [1:0] w, input logic [3:0] sel, input logic [63:0] want);
    rwidth = w; rsel = sel;
    rbyte_b = (w == 2'd0); rsel_b = sel;
    #1;
    checks++;
    if (rdata !== want) begin
      fails++;
      if (fails <= 20) $display("  FAIL %s: got %h want %h", name, rdata, want);
    end
    // Port B serves the byte and word views.
    if (w <= 2'd1 && rdata_b !== want[15:0]) begin
      fails++;
      if (fails <= 20) $display("  FAIL %s port B: got %h want %h", name, rdata_b, want[15:0]);
    end
    for (int i = 0; i < 16; i++)
      if (nz[i] !== {r_was[i][15:8] != 8'h00, r_was[i][7:0] != 8'h00}) begin
        fails++;
        if (fails <= 20) $display("  FAIL %s: R%0d nonzero bits %b", name, i, nz[i]);
      end
  endtask

  always #5 clk <= ~clk;

  // ---- reference model: registers.go idiom (sel-8, sel & 0xE, sel & 0xC) ----
  logic [15:0] ref_r [16];
  function automatic void ref_write(input logic [1:0] w, input logic [3:0] sel, input logic [63:0] d);
    int n;
    case (w)
      2'd0: if (sel < 8) ref_r[sel] = (16'(d[7:0]) << 8) | (ref_r[sel] & 16'h00FF);
            else         ref_r[sel - 8] = (ref_r[sel - 8] & 16'hFF00) | 16'(d[7:0]);
      2'd1: ref_r[sel] = d[15:0];
      2'd2: begin n = int'(sel) & 'hE; ref_r[n] = 16'(d >> 16); ref_r[n + 1] = 16'(d); end
      default: begin
        n = int'(sel) & 'hC;
        for (int k = 0; k < 4; k++) ref_r[n + k] = 16'(d >> (48 - 16 * k));
      end
    endcase
  endfunction
  function automatic logic [63:0] ref_read(input logic [1:0] w, input logic [3:0] sel);
    int n;
    logic [63:0] q;
    case (w)
      2'd0: return (sel < 8) ? 64'(ref_r[sel] >> 8) : 64'(ref_r[sel - 8] & 16'h00FF);
      2'd1: return 64'(ref_r[sel]);
      2'd2: begin n = int'(sel) & 'hE; return (64'(ref_r[n]) << 16) | 64'(ref_r[n + 1]); end
      default: begin
        n = int'(sel) & 'hC; q = 0;
        for (int k = 0; k < 4; k++) q = (q << 16) | 64'(ref_r[n + k]);
        return q;
      end
    endcase
  endfunction

  // A read in the write cycle sees the old value; the next cycle sees the new one.
  task automatic rdw(input string name, input logic [1:0] w, input logic [3:0] sel,
                     input logic [63:0] old, input logic [63:0] nu);
    wr(w, sel, old);
    @(negedge clk);
    we = 1; wwidth = w; wsel = sel; wdata = nu;
    chk_rd({name, " before edge"}, w, sel, old);
    @(posedge clk);
    #1 we = 0;
    chk_rd({name, " after edge"}, w, sel, nu);
  endtask

  int seed = 32'h8000;
  logic [1:0]  rw; logic [3:0] rs; logic [63:0] rdat; logic ren;
  initial begin
    we = 0; wwidth = 0; wsel = 0; wdata = 0; rwidth = 0; rsel = 0; rbyte_b = 0; rsel_b = 0;
    for (int i = 0; i < 16; i++) begin wr(2'd1, i[3:0], 64'd0); ref_r[i] = 0; end

    // TestWordReadWrite
    for (int i = 0; i < 16; i++) wr(2'd1, i[3:0], 64'h1000 + 64'(i));
    for (int i = 0; i < 16; i++) chk_rd($sformatf("word R%0d", i), 2'd1, i[3:0], 64'h1000 + 64'(i));
    // TestByteHighLow
    wr(2'd1, 4'd0, 64'hABCD);
    chk_rd("RH0", 2'd0, 4'd0, 64'hAB);
    chk_rd("RL0", 2'd0, 4'd8, 64'hCD);
    // TestByteWritePreservesOtherHalf
    wr(2'd1, 4'd3, 64'h1234);
    wr(2'd0, 4'd3, 64'hFF);   chk_rd("RH3 write -> R3", 2'd1, 4'd3, 64'hFF34);
    wr(2'd0, 4'd11, 64'hEE);  chk_rd("RL3 write -> R3", 2'd1, 4'd3, 64'hFFEE);
    // TestLongReadWrite
    wr(2'd2, 4'd2, 64'hDEADBEEF);
    chk_rd("R2 = hi(RR2)", 2'd1, 4'd2, 64'hDEAD);
    chk_rd("R3 = lo(RR2)", 2'd1, 4'd3, 64'hBEEF);
    chk_rd("RR2", 2'd2, 4'd2, 64'hDEADBEEF);
    // TestQuadReadWrite
    wr(2'd3, 4'd4, 64'h0011223344556677);
    chk_rd("R4", 2'd1, 4'd4, 64'h0011); chk_rd("R5", 2'd1, 4'd5, 64'h2233);
    chk_rd("R6", 2'd1, 4'd6, 64'h4455); chk_rd("R7", 2'd1, 4'd7, 64'h6677);
    chk_rd("RQ4", 2'd3, 4'd4, 64'h0011223344556677);
    // TestLongForcesEven
    wr(2'd2, 4'd3, 64'h12345678);
    chk_rd("WriteLong(3) -> RR2", 2'd2, 4'd2, 64'h12345678);
    // TestQuadForcesMultipleOf4
    wr(2'd3, 4'd5, 64'hAAAABBBBCCCCDDDD);
    chk_rd("WriteQuad(5) -> RQ4", 2'd3, 4'd4, 64'hAAAABBBBCCCCDDDD);
    // TestByteAccessR0ThroughR7
    for (int i = 0; i < 8; i++) wr(2'd1, i[3:0], 64'((16'(i) << 8) | 16'(i + 16'h10)));
    for (int i = 0; i < 8; i++) begin
      chk_rd($sformatf("RH%0d", i), 2'd0, i[3:0], 64'(i));
      chk_rd($sformatf("RL%0d", i), 2'd0, 4'(i + 8), 64'(i) + 64'h10);
    end

    // we Low holds every register
    wr(2'd1, 4'd5, 64'h1111);
    wr_en(1'b0, 2'd1, 4'd5, 64'h2222);
    chk_rd("we=0 word", 2'd1, 4'd5, 64'h1111);
    wr_en(1'b0, 2'd3, 4'd4, 64'hFFFFFFFFFFFFFFFF);
    chk_rd("we=0 quad", 2'd3, 4'd4, 64'h0414111106160717);
    rdw("rdw byte RL6", 2'd0, 4'd14, 64'h5A, 64'hA5);
    rdw("rdw word R9",  2'd1, 4'd9,  64'h1234, 64'hFEDC);
    rdw("rdw long RR10", 2'd2, 4'd10, 64'h01234567, 64'h89ABCDEF);
    rdw("rdw quad RQ12", 2'd3, 4'd12, 64'h0011223344556677, 64'h8899AABBCCDDEEFF);

    // ---- random soak vs the reference model ----
    for (int i = 0; i < 16; i++) begin wr(2'd1, i[3:0], 64'd0); ref_r[i] = 0; end
    for (int i = 0; i < 4000; i++) begin
      ren = ($urandom(seed) % 4) != 0;
      rw = 2'($urandom(seed)); rs = 4'($urandom(seed)); rdat = {$urandom(seed), $urandom(seed)};
      wr_en(ren, rw, rs, rdat); if (ren) ref_write(rw, rs, rdat);
      rw = 2'($urandom(seed)); rs = 4'($urandom(seed));
      chk_rd($sformatf("soak %0d w=%0d sel=%0d", i, rw, rs), rw, rs, ref_read(rw, rs));
    end

    if (fails == 0) $display("RESULT PASS tb_regfile: %0d checks", checks);
    else            $display("RESULT FAIL tb_regfile: %0d of %0d checks failed", fails, checks);
    $finish;
  end
endmodule
