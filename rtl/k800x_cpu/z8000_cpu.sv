// z8000_cpu -- Z8001/Z8002 (Z8003/Z8004 with VMPU) CPU, top level.
//
// SEGMENTED=1: Z8001/Z8003 (SN pins, the PC segment read at reset, SEGT).
// VMPU=1: Z8003/Z8004 (ABORT pin).
//
// AD is split into ad_in / ad_out / ad_drive.
// The test harness reads and pokes u_regfile.r, fcw, pc, psap, refresh,
// nspoff, nspseg, refresh_en and halted by name.

module z8000_cpu #(
  parameter bit SEGMENTED = 1,
  parameter bit VMPU      = 0
) (
  input  logic        clk,
  input  logic        reset_n,    // asynchronous, active low

  // inputs
  input  logic [15:0] ad_in,
  input  logic        stop_n,
  input  logic        wait_n,
  input  logic        busreq_n,
  input  logic        nmi_n,
  input  logic        nvi_n,
  input  logic        vi_n,
  input  logic        segt_n,     // SEGT (Z8001) / SAT (Z8003); ignored when !SEGMENTED
  input  logic        abort_n,    // Z8003/Z8004 only; ignored when !VMPU
  input  logic        mi_n,

  // outputs
  output logic [15:0] ad_out,
  output logic        ad_drive,
  output logic [6:0]  sn,         // SN6..SN0, meaningful only when SEGMENTED
  output logic        as_n,
  output logic        ds_n,
  output logic        mreq_n,
  output logic        r_w,        // 1 = read
  output logic        b_w,        // 1 = byte
  output logic        n_s,        // 1 = normal (user) mode
  output logic [3:0]  st,         // ST3..ST0, z8000_zbus_pkg codes
  output logic        busack_n,
  output logic        mo_n
);

  // ---- architectural registers ----------------------------------------------
  logic [15:0] fcw;
  logic [31:0] pc;          // Z8002: 16-bit; Z8001: seg[22:16]:offset[15:0]
  logic [31:0] psap;
  logic [15:0] refresh;
  logic [15:0] nspoff;
  logic [15:0] nspseg;
  logic        refresh_en;
  logic        halted;

  // ---- register file --------------------------------------------------------
  logic        rf_we;
  logic [1:0]  rf_wwidth;
  logic [3:0]  rf_wsel;
  logic [63:0] rf_wdata;
  logic [1:0]  rf_rwidth;
  logic [3:0]  rf_rsel;
  logic [63:0] rf_rdata;

  z8000_regfile u_regfile (
    .clk    (clk),
    .we     (rf_we),
    .wwidth (rf_wwidth),
    .wsel   (rf_wsel),
    .wdata  (rf_wdata),
    .rwidth (rf_rwidth),
    .rsel   (rf_rsel),
    .rdata  (rf_rdata)
  );

  assign rf_we     = 1'b0;
  assign rf_wwidth = 2'd0;
  assign rf_wsel   = 4'd0;
  assign rf_wdata  = 64'd0;
  assign rf_rwidth = 2'd0;
  assign rf_rsel   = 4'd0;

  // ---- control and bus ------------------------------------------------------
  logic        fcw_we, pc_we;
  logic [15:0] fcw_d;
  logic [31:0] pc_d;
  logic        bus_req, bus_ack, bus_done;
  logic [22:0] bus_addr;
  logic [15:0] bus_wdata, bus_rdata;
  logic [3:0]  bus_st;
  logic        bus_write, bus_byte, bus_normal, bus_epu_drives;

  z8000_sequencer #(.SEGMENTED(SEGMENTED)) u_sequencer (
    .clk            (clk),
    .reset_n        (reset_n),
    .fcw_sys        (fcw[14]),
    .pc             (pc),
    .fcw_we         (fcw_we),
    .fcw_d          (fcw_d),
    .pc_we          (pc_we),
    .pc_d           (pc_d),
    .bus_req        (bus_req),
    .bus_addr       (bus_addr),
    .bus_wdata      (bus_wdata),
    .bus_st         (bus_st),
    .bus_write      (bus_write),
    .bus_byte       (bus_byte),
    .bus_normal     (bus_normal),
    .bus_epu_drives (bus_epu_drives),
    .bus_ack        (bus_ack),
    .bus_done       (bus_done),
    .bus_rdata      (bus_rdata)
  );

  z8000_bus_unit #(.SEGMENTED(SEGMENTED)) u_bus (
    .clk            (clk),
    .reset_n        (reset_n),
    .req            (bus_req),
    .req_addr       (bus_addr),
    .req_wdata      (bus_wdata),
    .req_st         (bus_st),
    .req_write      (bus_write),
    .req_byte       (bus_byte),
    .req_normal     (bus_normal),
    .req_epu_drives (bus_epu_drives),
    .ack            (bus_ack),
    .done           (bus_done),
    .rdata          (bus_rdata),
    .wait_n         (wait_n),
    .ad_in          (ad_in),
    .ad_out         (ad_out),
    .ad_drive       (ad_drive),
    .sn             (sn),
    .as_n           (as_n),
    .ds_n           (ds_n),
    .mreq_n         (mreq_n),
    .r_w            (r_w),
    .b_w            (b_w),
    .n_s            (n_s),
    .st             (st)
  );

  assign busack_n = 1'b1;
  assign mo_n     = 1'b1;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      fcw <= 16'h0000;
      pc  <= 32'h0;
    end else begin
      if (fcw_we) fcw <= fcw_d;
      if (pc_we)  pc  <= pc_d;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      psap       <= 32'h0;
      refresh    <= 16'h0;
      nspoff     <= 16'h0;
      nspseg     <= 16'h0;
      refresh_en <= 1'b0;
      halted     <= 1'b0;
    end
  end

  // Inputs and registers that later control units will consume.
  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{stop_n, busreq_n, nmi_n, nvi_n, vi_n, segt_n, abort_n, mi_n,
                       rf_rdata, fcw[15], fcw[13:0], psap, refresh, nspoff, nspseg, refresh_en,
                       halted, VMPU};
  // verilator lint_on UNUSEDSIGNAL

endmodule
