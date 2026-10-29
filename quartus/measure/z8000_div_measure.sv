// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_div_measure (
  input  logic        clk,
  input  logic [99:0] in_i,
  output logic [79:0] out_o
);

  logic [99:0] in_q;
  logic [79:0] res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8000_div dut (
    .clk         (clk),
    .reset_n     (in_q[99]),
    .tick        (1'b1),
    .start       (in_q[98]),
    .n32         (in_q[97]),
    .dividend    (in_q[96:33]),
    .src_valid   (in_q[32]),
    .divisor     (in_q[31:0]),
    .done        (res[79]),
    .div_by_zero (res[78]),
    .overflow    (res[77]),
    .wide_quot   (res[76]),
    .quot_neg    (res[75]),
    .quot_zero   (res[74]),
    .quotient    (res[73:42]),
    .remainder   (res[41:10]),
    .remaining   (res[9:0])
  );

endmodule
