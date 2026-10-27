// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_shift_measure (
  input  logic        clk,
  input  logic [46:0] in_i,
  output logic [64:0] out_o
);

  logic [46:0] in_q;
  logic [64:0] res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8000_shift dut (
    .clk        (clk),
    .reset_n    (in_q[46]),
    .start      (in_q[45]),
    .width      (in_q[44:43]),
    .op         (in_q[42:38]),
    .val        (in_q[37:6]),
    .count      (in_q[5:0]),
    .done       (res[64]),
    .result     (res[63:32]),
    .flags      (res[31:16]),
    .flags_mask (res[15:0])
  );

endmodule
