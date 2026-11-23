// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_serial_measure (
  input  logic         clk,
  input  logic [116:0] in_i,
  output logic [93:0]  out_o
);

  logic [116:0] in_q;
  logic [93:0]  res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8000_serial dut (
    .clk         (clk),
    .clk_en      (1'b1),
    .reset_n     (in_q[116]),
    .tick        (in_q[115]),
    .start       (in_q[114]),
    .mul         (in_q[113]),
    .div         (in_q[112]),
    .wide        (in_q[29]),
    .dst         (in_q[111:48]),
    .src_hi      (in_q[47]),
    .src_valid   (in_q[46]),
    .src         (in_q[45:30]),
    .width       (in_q[28:27]),
    .op          (in_q[26:22]),
    .count       (in_q[21:16]),
    .done        (res[93]),
    .fin         (res[92]),
    .words       (res[91:28]),
    .flag_c      (res[27]),
    .flag_z      (res[26]),
    .more        (res[25]),
    .div_by_zero (res[24]),
    .overflow    (res[23]),
    .wide_quot   (res[22]),
    .quot_neg    (res[21]),
    .quot_zero   (res[20]),
    .sh_flags    (res[19:4]),
    .end3        (res[3]),
    .end2        (res[2]),
    .last        (res[1])
  );
  assign res[0] = ^in_q[15:0];

endmodule
