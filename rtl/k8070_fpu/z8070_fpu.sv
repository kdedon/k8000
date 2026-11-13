// z8070_fpu -- Zilog Z8070 Floating-Point Unit, Z8000 interface, top level.
//
// Pins: the Z8070 Preliminary Product Specification (1985 Data Book,
// printed pp.541-545): the signals common to every interface plus the
// Z8000 interface's, nothing else. AD is split into in, out and drive.
//
// Clocking: every flop runs on the board master clock `clk`. CLK.I is
// seen as a rise pulse and a fall pulse, CLK.D as a rise pulse, each High
// for one master clock. The strobes are seen on the master clock.
//
// Two halves, as on the chip: the Interface Processor watches the bus,
// moves data and holds the control registers; the Data Processor holds
// F0-F7 and computes on CLK.D.
//
// Implemented so far: /RESET (control registers cleared but SC.ID, which
// takes the ID pins), idle pins, the bus snoop and instruction decode, the
// operand and result transfers, FLDCTL, FLDCTLB, the list instructions,
// the Invalid opcode, Invalid EPU ID, Privilege and trap requests on /INT,
// /BSY in both overlap modes and as the store wait, the Intermediate
// queue with PC2, the exception flush and /ABORT, the F0-F7 file with
// FOP1/FOP2, and every Data Processor operation started from the pins.

`default_nettype none

module z8070_fpu (
  input  logic        clk,        // board master clock
  input  logic        clki_rise,  // CLK.I rising edge, one master clock
  input  logic        clki_fall,  // CLK.I falling edge, one master clock
  input  logic        clkd_rise,  // CLK.D rising edge, one master clock
  input  logic        reset_n,    // /RESET, level

  input  logic [15:0] ad_in,
  output logic [15:0] ad_out,
  output logic        ad_drive,
  input  logic        as_n,
  input  logic        ds_n,
  input  logic        r_w,        // 1 = read
  input  logic        b_w,        // 1 = byte
  input  logic        n_s,        // 1 = normal mode
  input  logic [3:0]  st,
  input  logic [6:0]  sn,
  input  logic        busack_n,
  input  logic        abort_n,

  output logic        bsy_n,
  output logic        int_n,      // open drain at the pad; 0 = asserted
  input  logic        iei,
  output logic        ieo,

  input  logic [1:0]  id,         // ID1-ID0
  input  logic [1:0]  opt         // OPT1-OPT0; 11 = Z8000
);

  logic        dp_busy, dp_start, dp_done, dp_opnd_src, dp_opnd_rd, dp_opnd_nxt, dp_rup;
  logic [5:0]  dp_kind;
  logic [1:0]  dp_prec, dp_rm;
  logic [79:0] dp_opnd, f_rdata, f_wdata, dp_res;
  logic [7:0]  dp_flags;
  logic [2:0]  dp_reason;
  logic [5:0]  dp_cmp;
  logic        f_we, f_re, dp_out;
  logic [3:0]  f_waddr, f_raddr;

  z8070_ip u_ip (
    .clk       (clk),
    .clki_rise (clki_rise),
    .clki_fall (clki_fall),
    .reset_n   (reset_n),
    .ad_in     (ad_in),
    .ad_out    (ad_out),
    .ad_drive  (ad_drive),
    .as_n      (as_n),
    .ds_n      (ds_n),
    .r_w       (r_w),
    .b_w       (b_w),
    .n_s       (n_s),
    .st        (st),
    .sn        (sn),
    .busack_n  (busack_n),
    .abort_n   (abort_n),
    .bsy_n     (bsy_n),
    .int_n     (int_n),
    .iei       (iei),
    .ieo       (ieo),
    .id        (id),
    .opt       (opt),
    .dp_busy   (dp_busy),
    .dp_start  (dp_start),
    .dp_kind   (dp_kind),
    .dp_prec   (dp_prec),
    .dp_rm     (dp_rm),
    .dp_opnd   (dp_opnd),
    .dp_opnd_src(dp_opnd_src),
    .dp_opnd_rd(dp_opnd_rd),
    .dp_opnd_nxt(dp_opnd_nxt),
    .dp_done   (dp_done),
    .dp_res    (dp_res),
    .dp_flags  (dp_flags),
    .dp_reason (dp_reason),
    .dp_rup    (dp_rup),
    .dp_cmp    (dp_cmp),
    .dp_out    (dp_out),
    .f_we      (f_we),
    .f_waddr   (f_waddr),
    .f_wdata   (f_wdata),
    .f_raddr   (f_raddr),
    .f_re      (f_re),
    .f_rdata   (f_rdata)
  );

  z8070_dp u_dp (
    .clk       (clk),
    .clkd_rise (clkd_rise),
    .reset_n   (reset_n),
    .busy      (dp_busy),
    .start     (dp_start),
    .op_kind   (dp_kind),
    .op_prec   (dp_prec),
    .op_rm     (dp_rm),
    .op_out    (dp_out),
    .opnd      (dp_opnd),
    .opnd_src  (dp_opnd_src),
    .opnd_rd   (dp_opnd_rd),
    .opnd_nxt  (dp_opnd_nxt),
    .done      (dp_done),
    .res       (dp_res),
    .res_flags (dp_flags),
    .res_reason(dp_reason),
    .res_rup   (dp_rup),
    .res_cmp   (dp_cmp),
    .f_we      (f_we),
    .f_waddr   (f_waddr),
    .f_wdata   (f_wdata),
    .f_raddr   (f_raddr),
    .f_re      (f_re),
    .f_rdata   (f_rdata)
  );

endmodule

`default_nettype wire
