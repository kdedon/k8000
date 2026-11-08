// Fit wrapper: four FPUs, ID 0-3, sharing only the master clock and
// /RESET. Every chip pin is registered so each timed path is flop to
// flop. Ports are virtual pins.

module z8000_fpu4_measure (
  input  logic         clk,
  input  logic [160:0] in_i,
  output logic [79:0]  out_o
);

  logic [160:0] in_q;
  logic [79:0]  res;

  localparam logic [7:0] IDS = 8'b11_10_01_00;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  genvar i;
  generate
  for (i = 0; i < 4; i = i + 1) begin : g_fpu
    logic [39:0] p;
    assign p = in_q[40*i +: 40];

    z8070_fpu dut (
      .clk       (clk),
      .clki_rise (p[39]),
      .clki_fall (p[38]),
      .clkd_rise (p[37]),
      .reset_n   (in_q[160]),
      .ad_in     (p[36:21]),
      .as_n      (p[20]),
      .ds_n      (p[19]),
      .r_w       (p[18]),
      .b_w       (p[17]),
      .n_s       (p[16]),
      .st        (p[15:12]),
      .sn        (p[11:5]),
      .busack_n  (p[4]),
      .abort_n   (p[3]),
      .iei       (p[2]),
      .id        (IDS[2*i +: 2]),
      .opt       (p[1:0]),
      .ad_out    (res[20*i+4 +: 16]),
      .ad_drive  (res[20*i+3]),
      .bsy_n     (res[20*i+2]),
      .int_n     (res[20*i+1]),
      .ieo       (res[20*i])
    );
  end
  endgenerate

endmodule
