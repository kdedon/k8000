// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_mult_measure (
  input  logic        clk,
  input  logic [67:0] in_i,
  output logic [74:0] out_o
);

  logic [67:0] in_q;
  logic [74:0] res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8000_mult dut (
    .clk       (clk),
    .reset_n   (in_q[67]),
    .tick      (1'b1),
    .start     (in_q[66]),
    .width32   (in_q[65]),
    .dst       (in_q[64:33]),
    .src_valid (in_q[32]),
    .src       (in_q[31:0]),
    .done      (res[74]),
    .product   (res[73:10]),
    .remaining (res[9:0])
  );

endmodule
