// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_regfile_measure (
  input  logic        clk,
  input  logic [76:0] in_i,
  output logic [63:0] out_o
);

  logic [76:0] in_q;
  logic [63:0] rdata;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= rdata;
  end

  z8000_regfile dut (
    .clk    (clk),
    .we     (in_q[76]),
    .wwidth (in_q[75:74]),
    .wsel   (in_q[73:70]),
    .wdata  (in_q[69:6]),
    .rwidth (in_q[5:4]),
    .rsel   (in_q[3:0]),
    .rdata  (rdata)
  );

endmodule
