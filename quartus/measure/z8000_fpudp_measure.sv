// Fit wrapper: registers every DUT input and output so each timed path is
// flop to flop. Ports are virtual pins.

module z8000_fpudp_measure (
  input  logic         clk,
  input  logic [179:0] in_i,
  output logic [180:0] out_o
);

  logic [179:0] in_q;
  logic [180:0] res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  z8070_dp dut (
    .clk       (clk),
    .clkd_rise (in_q[179]),
    .reset_n   (in_q[178]),
    .busy      (res[180]),
    .start     (in_q[177]),
    .op_kind   (in_q[176:171]),
    .op_prec   (in_q[170:169]),
    .op_rm     (in_q[168:167]),
    .op_out    (1'b0),
    .opnd      (in_q[166:87]),
    .opnd_src  (res[179]),
    .opnd_rd   (),
    .done      (res[178]),
    .res       (res[177:98]),
    .res_flags (res[97:90]),
    .res_reason(res[89:87]),
    .res_rup   (res[86]),
    .res_cmp   (res[85:80]),
    .f_we      (in_q[86]),
    .f_waddr   ({1'b0, in_q[85:83]}),
    .f_wdata   (in_q[82:3]),
    .f_raddr   ({1'b0, in_q[2:0]}),
    .f_rdata   (res[79:0])
  );

endmodule
