// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins. The CPU keeps its default
// parameters (Z8001); reset comes through a boundary flop like any input.

module z8000_cpu_measure (
  input  logic        clk,
  input  logic [27:0] in_i,
  output logic [36:0] out_o
);

  logic [27:0] in_q;
  logic [36:0] res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8000_cpu dut (
    .clk      (clk),
    .clk_rise (in_q[26]),
    .clk_fall (in_q[27]),
    .reset_n  (in_q[25]),
    .ad_in    (in_q[24:9]),
    .stop_n   (in_q[8]),
    .wait_n   (in_q[7]),
    .busreq_n (in_q[6]),
    .nmi_n    (in_q[5]),
    .nvi_n    (in_q[4]),
    .vi_n     (in_q[3]),
    .segt_n   (in_q[2]),
    .abort_n  (in_q[1]),
    .mi_n     (in_q[0]),
    .ad_out   (res[35:20]),
    .ad_drive (res[19]),
    .bus_drive(res[36]),
    .sn       (res[18:12]),
    .as_n     (res[11]),
    .ds_n     (res[10]),
    .mreq_n   (res[9]),
    .r_w      (res[8]),
    .b_w      (res[7]),
    .n_s      (res[6]),
    .st       (res[5:2]),
    .busack_n (res[1]),
    .mo_n     (res[0])
  );

endmodule
