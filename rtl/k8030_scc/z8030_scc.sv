// z8030_scc -- Zilog Z8030 Z-SCC (Z-Bus serial communications controller),
// top level. Pin seam == ~/git/z8000/sim/scc/pins.go (Inputs/Outputs)
// one-for-one; index [0] = Channel A, [1] = Channel B (Go ChA/ChB).
//
// The lockstep contract is per-record pin equality against the Go model:
// tb/k8030_scc/tb_scc.cpp replays vectors/k8030_scc/*.vec (one T record == one TickPins
// call == one posedge of `clk`) through these ports -- see
// docs/K8030_SCC_TESTS.md for exactly what is compared when.
//
// STATUS: SCAFFOLD. Only the power-up pin state is implemented (Go New():
// AD floating, INT_n/IEO High, TxD/RTS_n/DTR_n High, TRxC/SYNC not
// driven). Every vector fails at its first bus cycle or PCLK-driven event
// until the blocks below exist. FPGA_BIBLE Ch.5.
//
// Spec-audit notes (docs/K8030_SCC_TESTS.md sec 7, 2026-08-16):
//   * /INT is NOT int_pending: the Z8030 clocks its interrupt request
//     latch with /AS (int_latch <= int_pending at every as_rise, and at the
//     INTACK ds_fall) -- SCC/ESCC UM p.21, TdAS(INT). int_n = ~int_latch.
//   * The AD/CS0/INTACK latch is transparent while /AS is Low and freezes
//     at as_rise ("latched by the rising edge of AS"); decode at as_rise.
//   * IEO uses the /AS-latched INTACK (as_intack_n) and int_latch, not the
//     raw intack_n pin.
//   * Hardware reset values are the UM reset table (see channel initial
//     block); WR9 D5:D2 clear, D1:D0 (NV, VIS) and WR2 unaffected.
//   * The /AS+/DS reset is qualified by WIDTH, not by level (p.648: row 39
//     TwRES >= 250 ns "Coincident Low for Reset", rows 37/38 name 15-30 ns
//     approaches as "Delay for No Reset"). A level detector wipes a
//     configured chip on a legal bus turnaround -- a real defect, fixed in
//     the Go model 2026-08-16. HERE, count the coincidence in FABRIC clocks
//     against 250 ns of real time (e.g. >= 13 at 50 MHz), NOT in pclk_rise
//     enables: at 6 MHz PCLK a 250 ns window straddles 1 or 2 rises and a
//     30 ns window 0 or 1, so PCLK-edge counting cannot separate the two
//     bands at the boundary. The Go model counts 2 pclk rises because that
//     is the resolution it has; the fabric clock has better. Bench check:
//     tb_scc_timing [6], which passes under either rule.
//   * A /DS fall is a data strobe ONLY after an intervening /AS rise.
//     Cycle ownership latches at as_rise and is never cleared at
//     end-of-cycle, so an unpaired ds_fall would otherwise replay a write
//     to whatever register the LAST access decoded, with whatever is on AD.
//     Gate the ds_fall capture on as_n being High (Go: the same guard, 2026-08-16).
//     Note this is the SCC's variant of the R-CIO-409 family: cycle-ownership
//     state that outlives its cycle. The CIO answer was to order the
//     teardown before the latch; the SCC answer is to qualify the strobe.
//
// Clocking decision (Bible 0.2.3 + 15.1, documented in docs/K8030_SCC_TESTS.md):
//   * `clk` is the fabric clock: one posedge per Go TickPins call.
//   * `pclk` is a LEVEL input. pclk_rise = pclk & ~pclk_q is a one-cycle
//     enable (Go pinPrevPCLK / pclkRising) -- never a derived clock.
//   * /AS //DS //INTACK are oversampled by `clk`: <x>_fall = <x>_q & ~<x>_n
//     is combinational against the registered previous level, so a strobe
//     transition seen in the SAME record as a PCLK rise is serviced in that
//     record (Go: async capture block runs before the PCLK block in the
//     same call). Pending flags carry transitions across records to the
//     next PCLK rise, exactly the Go pinPending* flags.
//   * Hardware reset = /AS and /DS both Low (no reset pin). The Go model
//     resets on any single observation; W2-22 (scc.go:412) says silicon
//     qualifies TwRES >= 250 ns -- if a width counter is added here, add
//     it to the sim in the same change (Bible 0.3).
//   * AD is an in/out/oe triplet (ad_in / ad_out / ad_drive); ad_drive
//     drops combinationally when ds_n is High (scc.go:598-604) and is
//     never asserted during INTACK when WR9 NV=1 (W2-19).
//
// Implementation order (Bible 5.2/5.5; Go file:line):
//   1. strobe capture + AS-latched AD/RW/CS/INTACK, DS-latched AD/IEI   scc.go tickPins:426-455
//   2. address decode: AD4:1 = register, A//B on AD5 (Shift Left) or AD0  scc.go decodeAddr:613
//   3. register read mux (RR0/1/2/3/8/10/12/13/15) + write core          scc.go readReg:640 writeReg:735
//      WR2/WR9 shared; WR9 D7:6 reset commands                            scc.go execWR9:887 hardwareReset:1748
//   4. INTACK: vector at DS(fall) if IEI, IUS latch, RR2 modification     scc.go intAck:1091 modifyVector:1062
//   5. INT_n = ~int_latch; IEO = ~DLC & iei & (ius==0) & ~(as_intack & int_latch)  scc.go tickPins
//   6. two channel instances (rtl/k8030_scc/z8030_scc_channel.sv)
//
// Harness contract (tb/k8030_scc/scc_access.h peeks/pokes these by hierarchical
// name; keep the names or update that one file in the same change):
//   int_vector int_pending int_latch shift_right ius_mask  u_cha.* u_chb.*

module z8030_scc (
  input  logic        clk,          // fabric clock (one posedge per Go TickPins)

  // Inputs (pins.go Inputs)
  input  logic [7:0]  ad_in,        // AD7:0 (the chip's only bus pins)
  input  logic        as_n,         // address strobe; AD/CS0/INTACK latched at its RISE (transparent while Low)
  input  logic        ds_n,         // data strobe
  input  logic        r_w,          // 1 = read
  input  logic        cs0_n,        // /CS0 (active Low) ...
  input  logic        cs1,          // ... AND CS1 (active High), sampled while /AS Low
  input  logic        intack_n,
  input  logic        iei,
  input  logic        pclk,         // peripheral clock LEVEL (Bible 5.2: clock enable, not a clock)
  input  logic [1:0]  rxd,          // [0]=A [1]=B, idle High
  input  logic [1:0]  cts_n,
  input  logic [1:0]  dcd_n,
  input  logic [1:0]  trxc_in,      // external clocks (G-81.8: modeled in TickPins)
  input  logic [1:0]  txc_in,       // unmodeled in the Go seam (present for completeness)
  input  logic [1:0]  rxc_in,
  input  logic [1:0]  sync_in,      // unmodeled

  // Outputs (pins.go Outputs)
  output logic [7:0]  ad_out,
  output logic        ad_drive,     // 1 while the SCC sources AD
  output logic        int_n,        // open-drain, 0 = asserted
  output logic        ieo,
  output logic [1:0]  txd,
  output logic [1:0]  rts_n,        // open-drain, follow WR5 D1
  output logic [1:0]  dtr_n,        // open-drain, follow WR5 D7
  output logic [1:0]  trxc_out,
  output logic [1:0]  trxc_drive,   // WR11 D2
  output logic [1:0]  sync_out,     // never driven by the Go model
  output logic [1:0]  sync_drive
);

  // ---- chip-level registers (Snapshot: IntVector IntPending IntLatch ShiftRight IUSMask)
  logic [7:0] int_vector;
  logic       int_pending;          // PCLK-side request condition
  logic       int_latch;            // /AS-clocked /INT pin latch (Go intLatch)
  logic       shift_right;          // 0 = Shift Left (A//B on AD5, the C900 mode)
  logic [7:0] ius_mask;             // one bit per 3-bit source code

  // ---- pin-side state (Go: asyncPrev*, pinPending*, pinAsLatched*, pinDsLatched*, pinBus*, pinOut)
  logic       pclk_q, as_q, ds_q, intack_q;
  logic       pend_as_fall, pend_as_rise, pend_ds_fall, pend_ds_rise, pend_intack_rise;
  logic [7:0] as_ad;                // AD sampled while /AS Low, frozen at the rise (channel + register)
  logic       as_rw, as_cs_n, as_intack_n;
  logic [7:0] ds_ad;                // AD at /DS fall (write data)
  logic       ds_iei;               // IEI at /DS fall
  logic       bus_active, bus_ch, bus_rw;
  logic [3:0] bus_reg;
  logic [7:0] ad_out_q;
  logic       ad_drive_q;

  // ---- edge detects against the registered previous level (Bible 0.2.3)
  logic pclk_rise, as_fall, as_rise, ds_fall, ds_rise, intack_rise, hw_reset;
  assign pclk_rise   = pclk & ~pclk_q;
  assign as_fall     = as_q & ~as_n;
  assign as_rise     = ~as_q & as_n;
  assign ds_fall     = ds_q & ~ds_n;
  assign ds_rise     = ~ds_q & ds_n;
  assign intack_rise = ~intack_q & intack_n;
  assign hw_reset    = ~as_n & ~ds_n;   // TODO(scaffold): TwRES qualification (W2-22)

  // ---- power-up state == Go New() (scc.go:338-393); no reset pin ------------
  initial begin
    int_vector = 8'h00; int_pending = 1'b0; int_latch = 1'b0; shift_right = 1'b0; ius_mask = 8'h00;
    pclk_q = 1'b0; as_q = 1'b1; ds_q = 1'b1; intack_q = 1'b1;
    pend_as_fall = 1'b0; pend_as_rise = 1'b0; pend_ds_fall = 1'b0; pend_ds_rise = 1'b0;
    pend_intack_rise = 1'b0;
    as_ad = 8'h00; as_rw = 1'b0; as_cs_n = 1'b1; as_intack_n = 1'b1;
    ds_ad = 8'h00; ds_iei = 1'b0;
    bus_active = 1'b0; bus_ch = 1'b0; bus_rw = 1'b0; bus_reg = 4'd0;
    ad_out_q = 8'h00; ad_drive_q = 1'b0;
  end

  // TODO(scaffold): strobe capture / PCLK-rise bus service (steps 1-5).
  always_ff @(posedge clk) begin
    pclk_q   <= pclk;
    as_q     <= as_n;
    ds_q     <= ds_n;
    intack_q <= intack_n;
    // TODO(scaffold): if (hw_reset) hardware reset; pending flags; bus cycle.
  end

  // ---- channels ------------------------------------------------------------
  logic [1:0] ch_txd, ch_trxc_lvl;
  z8030_scc_channel u_cha (
    .clk(clk), .pclk_rise(pclk_rise),
    .rxd(rxd[0]), .cts_n(cts_n[0]), .dcd_n(dcd_n[0]), .trxc_in(trxc_in[0]), .rxc_in(rxc_in[0]),
    .txd(ch_txd[0]), .trxc_out_level(ch_trxc_lvl[0])
  );
  z8030_scc_channel u_chb (
    .clk(clk), .pclk_rise(pclk_rise),
    .rxd(rxd[1]), .cts_n(cts_n[1]), .dcd_n(dcd_n[1]), .trxc_in(trxc_in[1]), .rxc_in(rxc_in[1]),
    .txd(ch_txd[1]), .trxc_out_level(ch_trxc_lvl[1])
  );

  // ---- outputs: power-up pin state -----------------------------------------
  // TODO(scaffold): int_n = ~int_latch; ieo per scc.go tickPins; rts_n from
  // WR5 D1 | rts_hold, dtr_n from WR5 D7; trxc_drive from WR11 D2;
  // ad_drive_q & ~ds_n.
  always_comb begin
    ad_out     = ad_out_q;
    ad_drive   = ad_drive_q & ~ds_n;   // Go: release on /DS High is combinational
    int_n      = 1'b1;
    ieo        = 1'b1;
    txd        = ch_txd;
    rts_n      = 2'b11;
    dtr_n      = 2'b11;
    trxc_out   = ch_trxc_lvl;
    trxc_drive = 2'b00;
    sync_out   = 2'b00;
    sync_drive = 2'b00;
  end

  // ---- scaffold-only lint waivers: remove as each input gains a consumer ----
  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{ad_in, r_w, cs0_n, cs1, iei, txc_in, sync_in,
                       int_vector, int_pending, int_latch, shift_right, ius_mask,
                       pend_as_fall, pend_as_rise, pend_ds_fall, pend_ds_rise, pend_intack_rise,
                       as_ad, as_rw, as_cs_n, as_intack_n, ds_ad, ds_iei,
                       bus_active, bus_ch, bus_rw, bus_reg,
                       as_fall, as_rise, ds_fall, ds_rise, intack_rise, hw_reset};
  // verilator lint_on UNUSEDSIGNAL

endmodule
