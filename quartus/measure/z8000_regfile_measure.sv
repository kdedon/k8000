// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_regfile_measure (
  input  logic        clk,
  input  logic [81:0] in_i,
  output logic [111:0] out_o
);

  logic [81:0] in_q;
  logic [63:0] rdata;
  logic [15:0] rdata_b;
  logic [15:0][1:0] nz;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= {nz, rdata_b, rdata};
  end

  z8000_regfile dut (
    .clk    (clk),
    .we     (in_q[81]),
    .rbyte_b(in_q[80]),
    .rsel_b (in_q[79:76]),
    .wwidth (in_q[75:74]),
    .wsel   (in_q[73:70]),
    .wdata  (in_q[69:6]),
    .rwidth (in_q[5:4]),
    .rsel   (in_q[3:0]),
    .rdata  (rdata),
    .rdata_b(rdata_b),
    .nz     (nz)
  );

endmodule
