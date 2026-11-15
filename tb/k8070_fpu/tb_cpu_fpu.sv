// tb_cpu_fpu -- a board with one z8000_cpu and one z8070_fpu on real pins.
//
// One master clock. The CPU's CLK pulses are also CLK.I, and CLK.D rises
// with the CLK.I rises `clkd_en` passes, or with `clkd_fast` every master
// clock. /BSY drives STOP,
// and /WAIT through the board gate while the cycle latched at /AS is an EPU
// data cycle (1010, 1011, 1110) up to its /DS rise, when `bsy_wait` is set. /INT drives /VI. Memory sits outside:
// it drives `mem_data` onto AD with `mem_drive`.

`default_nettype none

module tb_cpu_fpu #(
  parameter bit SEGMENTED = 1
) (
  input  logic        clk,
  input  logic        clk_rise,
  input  logic        clk_fall,
  input  logic        reset_n,
  input  logic        busreq_n,
  input  logic        nmi_n,
  input  logic        nvi_n,
  input  logic        segt_n,
  input  logic        abort_n,
  input  logic        mi_n,
  input  logic [1:0]  fpu_id,
  input  logic        bsy_wait,
  input  logic        clkd_en,
  input  logic        clkd_fast,
  input  logic [15:0] mem_data,
  input  logic        mem_drive,

  output logic [15:0] ad,
  output logic        ad_clash,
  output logic        cpu_ad_drive,
  output logic [15:0] cpu_ad_out,
  output logic        bus_drive,
  output logic [6:0]  sn,
  output logic        as_n,
  output logic        ds_n,
  output logic        mreq_n,
  output logic        r_w,
  output logic        b_w,
  output logic        n_s,
  output logic [3:0]  st,
  output logic        busack_n,
  output logic        mo_n,
  output logic        fpu_ad_drive,
  output logic [15:0] fpu_ad_out,
  output logic        bsy_n,
  output logic        int_n,
  output logic        ieo,
  output logic        stop_n,
  output logic        wait_n,
  output logic        vi_n
);

  logic       ds_q, epu_cyc_q, epu_cyc;
  logic [6:0] fpu_sn;

  always_comb begin
    ad = 16'hFFFF;
    if (cpu_ad_drive)      ad = cpu_ad_out;
    else if (fpu_ad_drive) ad = fpu_ad_out;
    else if (mem_drive)    ad = mem_data;
  end
  assign ad_clash = (cpu_ad_drive && (fpu_ad_drive || mem_drive)) || (fpu_ad_drive && mem_drive);

  // The EPU data cycle the /WAIT gate covers: status through a latch open
  // while /AS is Low, held to the /DS rise.
  always_ff @(posedge clk) begin
    ds_q <= ds_n;
    if (!as_n || (ds_n && !ds_q)) epu_cyc_q <= !as_n && epu_cyc;
  end
  assign epu_cyc = !as_n ? (st == 4'b1010 || st == 4'b1011 || st == 4'b1110) : epu_cyc_q;

  assign stop_n = bsy_n;
  assign wait_n = !(bsy_wait && !bsy_n && epu_cyc);
  assign vi_n   = int_n;
  assign fpu_sn = SEGMENTED ? sn : 7'd0;

  z8000_cpu #(.SEGMENTED(SEGMENTED), .VMPU(1'b0)) u_cpu (
    .clk      (clk),
    .reset_n  (reset_n),
    .clk_rise (clk_rise),
    .clk_fall (clk_fall),
    .ad_in    (ad),
    .stop_n   (stop_n),
    .wait_n   (wait_n),
    .busreq_n (busreq_n),
    .nmi_n    (nmi_n),
    .nvi_n    (nvi_n),
    .vi_n     (vi_n),
    .segt_n   (segt_n),
    .abort_n  (abort_n),
    .mi_n     (mi_n),
    .ad_out   (cpu_ad_out),
    .ad_drive (cpu_ad_drive),
    .bus_drive(bus_drive),
    .sn       (sn),
    .as_n     (as_n),
    .ds_n     (ds_n),
    .mreq_n   (mreq_n),
    .r_w      (r_w),
    .b_w      (b_w),
    .n_s      (n_s),
    .st       (st),
    .busack_n (busack_n),
    .mo_n     (mo_n)
  );

  z8070_fpu u_fpu (
    .clk      (clk),
    .clki_rise(clk_rise),
    .clki_fall(clk_fall),
    .clkd_rise((clk_rise & clkd_en) | clkd_fast),
    .reset_n  (reset_n),
    .ad_in    (ad),
    .ad_out   (fpu_ad_out),
    .ad_drive (fpu_ad_drive),
    .as_n     (as_n),
    .ds_n     (ds_n),
    .r_w      (r_w),
    .b_w      (b_w),
    .n_s      (n_s),
    .st       (st),
    .sn       (fpu_sn),
    .busack_n (busack_n),
    .abort_n  (1'b1),
    .bsy_n    (bsy_n),
    .int_n    (int_n),
    .iei      (1'b1),
    .ieo      (ieo),
    .id       (fpu_id),
    .opt      (2'b11)
  );

endmodule

`default_nettype wire
