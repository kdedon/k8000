// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_alu_measure (
  input  logic        clk,
  input  logic [39:0] in_i,
  output logic [47:0] out_o
);

  logic [39:0] in_q;
  logic [47:0] res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8000_alu dut (
    .op         (in_q[39:35]),
    .width      (in_q[34:33]),
    .a          (in_q[32:17]),
    .b          (in_q[16:1]),
    .cin        (in_q[0]),
    .value      (res[47:32]),
    .flags      (res[31:16]),
    .flags_mask (res[15:0])
  );

endmodule
