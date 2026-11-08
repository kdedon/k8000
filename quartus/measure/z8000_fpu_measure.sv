// Fit wrapper: registers every chip pin so each timed path is flop to
// flop. Ports are virtual pins.

module z8000_fpu_measure (
  input  logic        clk,
  input  logic [42:0] in_i,
  output logic [19:0] out_o
);

  logic [42:0] in_q;
  logic [19:0] res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8070_fpu dut (
    .clk       (clk),
    .clki_rise (in_q[42]),
    .clki_fall (in_q[41]),
    .clkd_rise (in_q[40]),
    .reset_n   (in_q[39]),
    .ad_in     (in_q[38:23]),
    .as_n      (in_q[22]),
    .ds_n      (in_q[21]),
    .r_w       (in_q[20]),
    .b_w       (in_q[19]),
    .n_s       (in_q[18]),
    .st        (in_q[17:14]),
    .sn        (in_q[13:7]),
    .busack_n  (in_q[6]),
    .abort_n   (in_q[5]),
    .iei       (in_q[4]),
    .id        (in_q[3:2]),
    .opt       (in_q[1:0]),
    .ad_out    (res[19:4]),
    .ad_drive  (res[3]),
    .bsy_n     (res[2]),
    .int_n     (res[1]),
    .ieo       (res[0])
  );

endmodule
