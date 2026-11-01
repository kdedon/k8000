// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_mmu_measure (
  input  logic        clk,
  input  logic [33:0] in_i,
  output logic [50:0] out_o
);

  logic [33:0] in_q;
  logic [50:0] res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8010_mmu dut (
    .clk        (clk),
    .reset_n    (in_q[33]),
    .ad         (in_q[32:17]),
    .sn         (in_q[16:10]),
    .st         (in_q[9:6]),
    .as_n       (in_q[5]),
    .ds_n       (in_q[4]),
    .r_w        (in_q[3]),
    .n_s        (in_q[2]),
    .cs_n       (in_q[1]),
    .dmasync    (in_q[0]),
    .pa         (res[50:27]),
    .pa_drive   (res[26]),
    .segt_n     (res[25]),
    .sup_n      (res[24]),
    .data       (res[23:8]),
    .data_drive (res[7:0])
  );

endmodule
