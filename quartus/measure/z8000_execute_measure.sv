// Fit wrapper: registers every input and output so each timed path is flop
// to flop. Ports are virtual pins. The execute unit with its register file
// and ALU: the operand-read, ALU pass and write-back paths.

module z8000_execute_measure (
  input  logic        clk,
  input  logic [77:0] in_i,
  output logic [57:0] out_o
);

  logic [77:0] in_q;
  logic [57:0] res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  logic        rf_we, rf_rbyte_b;
  logic [1:0]  rf_wwidth, rf_rwidth;
  logic [3:0]  rf_wsel, rf_rsel, rf_rsel_b, clocks;
  logic [15:0] rf_wdata, rf_rdata_b, flags, flags_mask;
  logic [63:0] rf_rdata;
  logic        handles, flags_we;

  z8000_regfile u_regfile (
    .clk     (clk),
    .clk_en  (1'b1),
    .we      (rf_we),
    .wwidth  (rf_wwidth),
    .wsel    (rf_wsel),
    .wdata   ({48'd0, rf_wdata}),
    .rwidth  (rf_rwidth),
    .rsel    (rf_rsel),
    .rdata   (rf_rdata),
    .rbyte_b (rf_rbyte_b),
    .rsel_b  (rf_rsel_b),
    .rdata_b (rf_rdata_b)
  );

  z8000_execute dut (
    .clk        (clk),
    .clk_en     (1'b1),
    .reset_n    (in_q[77]),
    .start      (in_q[76]),
    .w0         (in_q[75:64]),
    .exec       (in_q[63:59]),
    .alu_op     (in_q[58:54]),
    .width      (in_q[53:52]),
    .words      (in_q[51:49]),
    .src2       (in_q[48:44]),
    .dst        (in_q[43:40]),
    .src1_nib   (in_q[39:38]),
    .src2_nib   (in_q[37:36]),
    .dst_nib    (in_q[35:34]),
    .handles    (handles),
    .clocks     (clocks),
    .w1         (in_q[33:18]),
    .w2         (in_q[17:2]),
    .rf_rwidth  (rf_rwidth),
    .rf_rsel    (rf_rsel),
    .rf_rdata   (rf_rdata[15:0]),
    .rf_rbyte_b (rf_rbyte_b),
    .rf_rsel_b  (rf_rsel_b),
    .rf_rdata_b (rf_rdata_b),
    .rf_we      (rf_we),
    .rf_wwidth  (rf_wwidth),
    .rf_wsel    (rf_wsel),
    .rf_wdata   (rf_wdata),
    .fcw_c      (in_q[0]),
    .flags_we   (flags_we),
    .flags      (flags),
    .flags_mask (flags_mask)
  );

  assign res = {handles, clocks, flags_we, flags[7:2], flags_mask[7:2], rf_we, rf_wwidth, rf_wsel,
                rf_wdata, in_q[1], rf_rdata[63:48]};

endmodule
