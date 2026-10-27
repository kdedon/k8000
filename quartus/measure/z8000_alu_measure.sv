// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_alu_measure (
  input  logic         clk,
  input  logic [135:0] in_i,
  output logic [95:0]  out_o
);

  logic [135:0] in_q;
  logic [95:0]  res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8000_alu dut (
    .op         (in_q[135:131]),
    .width      (in_q[130:129]),
    .a          (in_q[128:65]),
    .b          (in_q[64:1]),
    .cin        (in_q[0]),
    .value      (res[95:32]),
    .flags      (res[31:16]),
    .flags_mask (res[15:0])
  );

endmodule
