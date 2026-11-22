// Fit wrapper: registers every input and output so each timed path is flop
// to flop. Ports are virtual pins. The execute unit with its register file
// and ALU: the operand-read, ALU pass and write-back paths. Every execute
// port is connected, so a new one fails lint until it is added here.

module z8000_execute_measure (
  input  logic         clk,
  input  logic [341:0] in_i,
  output logic [220:0] out_o
);

  logic [341:0] in_q;
  logic [220:0] res;

  always_ff @(posedge clk) begin
    in_q  <= in_i;
    out_o <= res;
  end

  logic        rf_we, rf_rbyte_b;
  logic [1:0]  rf_wwidth, rf_rwidth;
  logic [3:0]  rf_wsel, rf_rsel, rf_rsel_b;
  logic [15:0] rf_wdata, rf_rdata_b;
  logic [63:0] rf_rdata;
  logic [15:0][1:0] nz;

  z8000_regfile u_regfile (
    .clk     (clk),
    .clk_en  (1'b1),
    .we      (rf_we),
    .wwidth  (rf_wwidth),
    .wsel    (rf_wsel),
    .wdata   ({48'd0, rf_wdata}),
    .rwidth  (rf_rwidth),
    .rsel    (rf_rsel),
    .rdata   (rf_rdata),
    .rbyte_b (rf_rbyte_b),
    .rsel_b  (rf_rsel_b),
    .rdata_b (rf_rdata_b),
    .nz      (nz)
  );

  z8000_execute dut (
    .clk         (clk),
    .clk_en      (1'b1),
    .reset_n     (in_q[340]),
    .w0          (in_q[339:328]),
    .ctrl_nx     (in_q[327:259]),
    .w0_nx       (in_q[258:247]),
    .alu_op      (in_q[246:242]),
    .width       (in_q[241:240]),
    .src2        (in_q[239:235]),
    .count       (in_q[234:230]),
    .dst         (in_q[229:226]),
    .src1_nib    (in_q[225:224]),
    .src2_nib    (in_q[223:222]),
    .dst_nib     (in_q[221:220]),
    .w1          (in_q[219:204]),
    .w2          (in_q[203:188]),
    .io_wr       (in_q[187]),
    .io_spec     (in_q[186]),
    .block_decr  (in_q[185]),
    .blk_more    (res[219]),
    .cc_held     (in_q[183]),
    .cnt_dec     (in_q[182]),
    .cnt_val     (res[218:203]),
    .fcw_op      (in_q[181:179]),
    .fcw_mask    (in_q[178:163]),
    .first       (in_q[162]),
    .last2       (in_q[161]),
    .to_last     (in_q[160]),
    .last        (in_q[159]),
    .last2_nx    (in_q[158]),
    .last_nx     (in_q[157]),
    .seg_mode    (in_q[156]),
    .pc_seg      (in_q[155:149]),
    .pc_b15      (in_q[341]),
    .pc_off      (in_q[148:133]),
    .cyc_end3    (in_q[132]),
    .ea_word     (in_q[131:109]),
    .ea_long     (in_q[108]),
    .mem_take    (in_q[107]),
    .int_take    (in_q[106]),
    .opnd_take   (in_q[105]),
    .ph_hold     (in_q[104]),
    .imm_in      (in_q[103]),
    .rdata       (in_q[102:87]),
    .mem_addr    (res[202:180]),
    .mem_st      (res[179:176]),
    .mem_byte    (res[175]),
    .mem_wdata   (res[174:159]),
    .bus_lock_nx (res[158]),
    .rf_rwidth   (rf_rwidth),
    .rf_rsel     (rf_rsel),
    .rf_rdata    (rf_rdata[31:0]),
    .rf_rbyte_b  (rf_rbyte_b),
    .rf_rsel_b   (rf_rsel_b),
    .rf_rdata_b  (rf_rdata_b),
    .rf_we       (rf_we),
    .rf_wwidth   (rf_wwidth),
    .rf_wsel     (rf_wsel),
    .rf_wdata    (rf_wdata),
    .pc_we       (res[157]),
    .pc_d        (res[156:134]),
    .pc_b15_d    (res[220]),
    .fcw         (in_q[86:71]),
    .exc         (in_q[70]),
    .af_done     (in_q[69]),
    .exc_vec     (in_q[68:64]),
    .psap        (in_q[63:41]),
    .id_word     (in_q[40:25]),
    .exc_pcoff   (in_q[24:16]),
    .fcw_we      (res[133]),
    .fcw_d       (res[132:117]),
    .ctl_rsel    (res[116:114]),
    .ctl_rdata   (in_q[15:0]),
    .ctl_we      (res[113]),
    .ctl_wd      (res[112:97]),
    .flags_we    (res[96]),
    .flags       (res[95:80]),
    .flags_mask  (res[79:64])
  );

  assign res[63:0] = {nz, rf_rdata[63:32]};

endmodule
