// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_cio_measure (
  input  logic        clk,
  input  logic [36:0] in_i,
  output logic [52:0] out_o
);

  logic [36:0] in_q;   // in_q[36] spare
  logic [52:0] res;
  assign res[25] = 1'b0;   // spare
  assign res[8]  = 1'b0;   // spare

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8036_cio dut (
    .clk      (clk),
    .ad_in    (in_q[35:28]),
    .as_n     (in_q[27]),
    .ds_n     (in_q[26]),
    .r_w      (in_q[25]),
    .cs0_n    (in_q[24]),
    .cs1      (in_q[23]),
    .intack_n (in_q[22]),
    .iei      (in_q[21]),
    .pclk_fall(in_q[20]),
    .pa_in    (in_q[19:12]),
    .pb_in    (in_q[11:4]),
    .pc_in    (in_q[3:0]),
    .ad_out   (res[52:45]),
    .ad_drive (res[44]),
    .int_n    (res[43]),
    .ieo      (res[42]),
    .pa_out   (res[41:34]),
    .pa_oe    (res[33:26]),
    .pb_out   (res[24:17]),
    .pb_oe    (res[16:9]),
    .pc_out   (res[7:4]),
    .pc_oe    (res[3:0])
  );

endmodule
