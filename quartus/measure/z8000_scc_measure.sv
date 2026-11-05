// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_scc_measure (
  input  logic        clk,
  input  logic [33:0] in_i,
  output logic [24:0] out_o
);

  logic [33:0] in_q;   // in_q[3:2] spare
  logic [24:0] res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8030_scc dut (
    .clk        (clk),
    .ad_in      (in_q[27:20]),
    .as_n       (in_q[19]),
    .ds_n       (in_q[18]),
    .r_w        (in_q[17]),
    .cs0_n      (in_q[16]),
    .cs1        (in_q[15]),
    .intack_n   (in_q[14]),
    .iei        (in_q[13]),
    .pclk_rise  (in_q[12]),
    .rxd        (in_q[11:10]),
    .cts_n      (in_q[9:8]),
    .dcd_n      (in_q[7:6]),
    .trxc_rise  (in_q[5:4]),
    .trxc_fall  (in_q[33:32]),
    .rxc_rise   (in_q[1:0]),
    .rxc_fall   (in_q[31:30]),
    .sync_in    (in_q[29:28]),
    .ad_out     (res[22:15]),
    .ad_drive   (res[14]),
    .int_n      (res[13]),
    .ieo        (res[12]),
    .txd        (res[11:10]),
    .rts_n      (res[9:8]),
    .dtr_n      (res[7:6]),
    .trxc_out   (res[5:4]),
    .trxc_drive (res[3:2]),
    .sync_out   (res[24:23]),
    .sync_drive (res[1:0])
  );

endmodule
