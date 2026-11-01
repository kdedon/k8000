// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_serial_measure (
  input  logic         clk,
  input  logic [116:0] in_i,
  output logic [109:0] out_o
);

  logic [116:0] in_q;
  logic [109:0] res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8000_serial dut (
    .clk         (clk),
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
    .done        (res[109]),
    .fin         (res[108]),
    .words       (res[107:44]),
    .flag_c      (res[43]),
    .flag_z      (res[42]),
    .more        (res[41]),
    .div_by_zero (res[40]),
    .overflow    (res[39]),
    .wide_quot   (res[38]),
    .quot_neg    (res[37]),
    .quot_zero   (res[36]),
    .sh_flags    (res[35:20]),
    .sh_mask     (res[19:4]),
    .end3        (res[3]),
    .end2        (res[2]),
    .last        (res[1])
  );
  assign res[0] = ^in_q[15:0];

endmodule
