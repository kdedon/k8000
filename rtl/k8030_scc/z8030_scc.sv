// z8030_scc -- Zilog Z8030 Z-SCC (Z-Bus serial communications controller),
// top level. Index [0] = Channel A, [1] = Channel B.
//
// tb/k8030_scc/tb_scc.cpp replays vectors/k8030_scc/*.vec (one T record ==
// one posedge of `clk`) through these ports and compares every pin -- see
// docs/K8030_SCC_TESTS.md for exactly what is compared when.
//
// STATUS: strobe capture, /INT latch, IEO, address decode, register read
// and write, WR9 and /AS+/DS resets, interrupt priority and acknowledge.
// No serial logic.
//
// Spec notes:
//   * /INT is NOT int_pending: the Z8030 clocks its interrupt request
//     latch with /AS (int_latch <= int_pending & iei at every as_rise; the
//     INTACK ds_fall can only release it) -- SCC/ESCC UM p.21,
//     TdAS(INT); /INT needs IEI High (UM 2.4.5.1). int_n = ~int_latch.
//   * Only a request latched at the acknowledge's /AS takes the
//     acknowledge ("no additional interrupt requests during an Interrupt
//     Acknowledge cycle", UM): one arriving later waits for the next /AS.
//   * The AD/CS0/INTACK latch is transparent while /AS is Low and freezes
//     at as_rise ("latched by the rising edge of AS"); decode at as_rise.
//   * IEO uses the /AS-latched INTACK (as_intack_n) and int_latch, not the
//     raw intack_n pin.
//   * Hardware reset values are the UM reset table (see the channel
//     reset block); WR9 D5:D2 clear, D1:D0 (NV, VIS) and WR2 unaffected.
//   * The /AS+/DS reset is qualified by WIDTH, not by level (p.648: row 39
//     TwRES >= 250 ns "Coincident Low for Reset", rows 37/38 name 15-30 ns
//     approaches as "Delay for No Reset"). A level detector wipes a
//     configured chip on a legal bus turnaround. Counting the coincidence
//     in fabric clocks against 250 ns (e.g. >= 13 at 50 MHz) would separate
//     the bands; at 6 MHz PCLK a 250 ns window straddles 1 or 2 rises and a
//     30 ns window 0 or 1. This port counts 2 PCLK rises, as the vectors
//     do. Bench check: tb_scc_timing [5] and [6].
//   * A /DS fall is a data strobe ONLY after an intervening /AS rise.
//     Cycle ownership latches at as_rise and is never cleared at
//     end-of-cycle, so an unpaired ds_fall would otherwise replay a write
//     to whatever register the LAST access decoded, with whatever is on AD.
//     Gate the ds_fall capture on as_n being High.
//
// Clocking (documented in docs/K8030_SCC_TESTS.md):
//   * `clk` is the board master clock: one or more posedges per record.
//   * `pclk_rise` is the PCLK rising edge as a one-master-clock pulse from
//     the board divider -- never a derived clock. Pulses may fire on
//     consecutive master clocks.
//   * /RTxC and /TRxC use both edges and the level: `rxc_rise/rxc_fall` and
//     `trxc_rise/trxc_fall` ([1:0] per channel) are pulse pairs. Each channel
//     rebuilds the pin level (set by _rise, cleared by _fall; a pulse on
//     the current clock counts at once). The level is sampled only at PCLK
//     rises and compared with the level at the previous PCLK rise, so an
//     edge between PCLK rises is seen at the next one.
//   * /AS //DS //INTACK are oversampled by `clk`: <x>_fall = <x>_q & ~<x>_n
//     is combinational against the registered previous level, so a strobe
//     transition seen in the SAME record as a PCLK rise is serviced in that
//     record, before the PCLK work. Pending flags carry transitions across
//     records to the next PCLK rise.
//   * Hardware reset = /AS and /DS both Low across two PCLK rises (no
//     reset pin); see the width note above. The board applies it at
//     power-up through the same pins.
//   * Asynchronous inputs are not synchronised here, so lockstep with the
//     vectors holds: /DCD, /CTS and /SYNC take one PCLK sample, RxD is used
//     as it stands at the PCLK rise, and /RTxC and /TRxC compare the last
//     PCLK's level with the present one. The system top must put 2-flop
//     synchronisers on RxD, /RTxC, /TRxC, /SYNC, /DCD, /CTS and the bus
//     strobes.
//   * AD is an in/out/oe triplet (ad_in / ad_out / ad_drive); ad_drive
//     drops combinationally when ds_n is High and is never asserted
//     during INTACK when WR9 NV=1.
//
// Blocks:
//   1. strobe capture + AS-latched AD/RW/CS/INTACK, DS-latched AD/IEI
//   2. address decode: AD4:1 = register, A//B on AD5 (Shift Left) or AD0
//   3. register read mux (RR0/1/2/3/8/10/12/13/15) + write core
//      WR2/WR9 shared; WR9 D7:6 reset commands
//   4. INTACK: vector at DS(fall) if IEI, IUS latch, RR2 modification
//   5. INT_n = ~int_latch (IEI in the latch); IEO = ~DLC & iei & (ius==0) & ~(as_intack & int_latch)
//   6. two channel instances (rtl/k8030_scc/z8030_scc_channel.sv)
//
// Harness contract (tb/k8030_scc/scc_access.h peeks/pokes these by hierarchical
// name; keep the names or update that one file in the same change):
//   int_vector int_pending int_latch shift_right ius_mask  u_cha.* u_chb.*

module z8030_scc (
  input  logic        clk,          // board master clock

  // Inputs
  input  logic [7:0]  ad_in,        // AD7:0 (the chip's only bus pins)
  input  logic        as_n,         // address strobe; AD/CS0/INTACK latched at its RISE (transparent while Low)
  input  logic        ds_n,         // data strobe
  input  logic        r_w,          // 1 = read
  input  logic        cs0_n,        // /CS0 (active Low) ...
  input  logic        cs1,          // ... AND CS1 (active High), sampled while /AS Low
  input  logic        intack_n,
  input  logic        iei,
  input  logic        pclk_rise,    // PCLK rising edge: one-master-clock pulse
  input  logic [1:0]  rxd,          // [0]=A [1]=B, idle High
  input  logic [1:0]  cts_n,
  input  logic [1:0]  dcd_n,
  input  logic [1:0]  trxc_rise,    // /TRxC rising edge pulse, [0]=A [1]=B
  input  logic [1:0]  trxc_fall,    // /TRxC falling edge pulse
  input  logic [1:0]  rxc_rise,     // /RTxC rising edge pulse
  input  logic [1:0]  rxc_fall,     // /RTxC falling edge pulse
  input  logic [1:0]  sync_in,

  // Outputs
  output logic [7:0]  ad_out,
  output logic        ad_drive,     // 1 while the SCC sources AD
  output logic        int_n,        // open-drain, 0 = asserted
  output logic        ieo,
  output logic [1:0]  txd,
  output logic [1:0]  rts_n,        // open-drain, follow WR5 D1
  output logic [1:0]  dtr_n,        // open-drain, follow WR5 D7
  output logic [1:0]  trxc_out,
  output logic [1:0]  trxc_drive,   // WR11 D2
  output logic [1:0]  sync_out,
  output logic [1:0]  sync_drive
);

  // ---- chip-level registers
  logic [7:0] int_vector;
  logic       int_pending;          // PCLK-side request condition (from the IP bits)
  logic       int_latch;            // /AS-clocked /INT pin latch
  logic       shift_right;          // 0 = Shift Left (A//B on AD5)
  logic [7:0] ius_mask;             // one bit per 3-bit source code

  // ---- pin-side state
  logic       as_q, ds_q, intack_q;
  logic       pend_as_fall, pend_as_rise, pend_ds_fall, pend_ds_rise, pend_intack_rise;
  logic [7:0] as_ad;                // AD sampled while /AS Low, frozen at the rise (channel + register)
  logic       as_cs_n, as_intack_n;  // /CS0 and /INTACK at the /AS rise
  logic [7:0] ds_ad;                // AD at /DS fall (write data)
  logic       ds_iei, ds_rw, ds_cs1; // IEI, R/W and CS1 at /DS fall
  logic       bus_active, bus_ch;
  logic [3:0] bus_reg;
  logic [7:0] ad_out_q;
  logic       ad_drive_q;

  // ---- edge detects against the registered previous level
  logic as_fall, as_rise, ds_fall, ds_rise, intack_rise, hw_reset;
  assign as_fall     = as_q & ~as_n;
  assign as_rise     = ~as_q & as_n;
  assign ds_fall     = ds_q & ~ds_n;
  assign ds_rise     = ~ds_q & ds_n;
  assign intack_rise = ~intack_q & intack_n;
  assign hw_reset    = ~as_n & ~ds_n;

  // /AS and /DS Low together resets the chip once held across two PCLK rises.
  logic [1:0] res_cnt;
  logic       pin_reset;
  assign pin_reset = hw_reset & (res_cnt[1] | (res_cnt[0] & pclk_rise));

  // The address latch is transparent while /AS is Low; the PCLK-side
  // service sees this record's value, as does IEO.
  logic as_intack_now, ds_iei_now;
  assign as_intack_now = as_n ? as_intack_n : intack_n;
  // A /DS fall is a data strobe only after /AS has risen, and only the
  // first one: the select is spent at that /DS rise until the next /AS.
  logic ds_spent;
  logic ds_strobe;
  assign ds_strobe = ds_fall & as_n & ~ds_spent;
  assign ds_iei_now = ds_strobe ? iei : ds_iei;
  logic [7:0] ad_wr;
  assign ad_wr = ds_strobe ? ad_in : ds_ad;
  // R/W and CS1 are timed to /DS, not latched by /AS.
  logic ds_rw_now, ds_cs1_now;
  assign ds_rw_now  = ds_strobe ? r_w : ds_rw;
  assign ds_cs1_now = ds_strobe ? cs1 : ds_cs1;

  // Strobe edges wait here until the next PCLK rise.
  logic as_fall_p, as_rise_p, ds_fall_p, ds_rise_p, intack_rise_p;
  assign as_fall_p     = pend_as_fall     | as_fall;
  assign as_rise_p     = pend_as_rise     | as_rise;
  assign ds_fall_p     = pend_ds_fall     | ds_strobe;
  assign ds_rise_p     = pend_ds_rise     | ds_rise;
  assign intack_rise_p = pend_intack_rise | intack_rise;

  // ---- address decode (at the /AS rise service) ----------------------------
  // AD4:AD1 = register; A//B (1 = A) on AD5 in Shift Left, AD0 in Shift Right.
  logic [7:0] as_ad_now;
  logic       as_cs_n_now, shift_right_now;
  assign as_ad_now       = as_n ? as_ad   : ad_in;
  assign as_cs_n_now     = as_n ? as_cs_n : cs0_n;
  assign shift_right_now = shift_right & ~pin_reset;

  logic       bus_active_n, bus_ch_n;
  logic [3:0] bus_reg_n;
  always_comb begin
    bus_active_n = bus_active & ~pin_reset;
    bus_ch_n     = bus_ch;
    bus_reg_n    = bus_reg;
    if (pclk_rise && as_rise_p) begin
      bus_active_n = ~as_cs_n_now & as_intack_now;
      if (bus_active_n) begin
        bus_ch_n  = ~(shift_right_now ? as_ad_now[0] : as_ad_now[5]);   // 0 = A
        bus_reg_n = as_ad_now[4:1];
      end
    end
  end

  // A register access is serviced at the PCLK rise that sees the /DS fall.
  logic bus_cycle, bus_rd, bus_wr;
  assign bus_cycle = pclk_rise & ds_fall_p & as_intack_now & bus_active_n & ds_cs1_now;
  assign bus_rd    = bus_cycle &  ds_rw_now;
  assign bus_wr    = bus_cycle & ~ds_rw_now;

  // WR2 and WR9 are shared: a write to either reaches both channels.
  logic       wr_shared;
  logic [1:0] ch_wr, ch_rd;
  assign wr_shared = bus_reg_n == 4'd2 || bus_reg_n == 4'd9;
  assign ch_wr = {bus_wr & (bus_ch_n | wr_shared), bus_wr & (~bus_ch_n | wr_shared)};
  assign ch_rd = {bus_rd & bus_ch_n, bus_rd & ~bus_ch_n};

  // WR9 D7:D6: 01 resets B, 10 resets A, 11 is a hardware reset.
  logic       wr9_hw;
  logic [1:0] ch_reset;
  assign wr9_hw   = bus_wr && bus_reg_n == 4'd9 && ad_wr[7:6] == 2'b11;
  assign ch_reset = {pin_reset | wr9_hw | (bus_wr && bus_reg_n == 4'd9 && ad_wr[7:6] == 2'b01),
                     pin_reset | wr9_hw | (bus_wr && bus_reg_n == 4'd9 && ad_wr[7:6] == 2'b10)};

  always_ff @(posedge clk) begin
    as_q     <= as_n;
    ds_q     <= ds_n;
    intack_q <= intack_n;

    if (!as_n) begin
      as_ad       <= ad_in;
      as_cs_n     <= cs0_n;
      as_intack_n <= intack_n;
    end
    ds_spent <= as_n & (ds_spent | ds_rise);
    if (ds_strobe) begin
      ds_ad  <= ad_in;
      ds_iei <= iei;
      ds_rw  <= r_w;
      ds_cs1 <= cs1;
    end

    // /INT is clocked by /AS, selected or not; a Low IEI blocks it.
    if (as_rise) int_latch <= int_latch_now;

    res_cnt <= !hw_reset ? 2'd0 : (pclk_rise && !res_cnt[1]) ? res_cnt + 2'd1 : res_cnt;
    bus_active <= bus_active_n;
    bus_ch     <= bus_ch_n;
    bus_reg    <= bus_reg_n;

    if (pclk_rise) begin
      {pend_as_fall, pend_as_rise, pend_ds_fall, pend_ds_rise, pend_intack_rise} <= '0;
      if (as_fall_p) ad_drive_q <= 1'b0;
      if (bus_rd) begin
        ad_out_q   <= rd_mux;
        ad_drive_q <= 1'b1;
      end
      if (ack) begin
        ius_mask <= ius_ack;
        if (!wr9[1]) begin
          ad_out_q   <= wr9[0] ? mod_vec : int_vector;
          ad_drive_q <= 1'b1;
        end
      end
      if (bus_wr) begin
        if (bus_reg_n == 4'd2) int_vector <= ad_wr;
        if (bus_reg_n == 4'd0 && ad_wr[5:3] == 3'd7) ius_mask <= ius_mask & ~ius_top;
        if (bus_reg_n == 4'd0 && bus_ch_n && ad_wr[1]) shift_right <= ad_wr[0];
      end
      // An acknowledge re-latches /INT from the request left after it; a
      // request newer than the acknowledge's /AS waits for the next one.
      if (ds_fall_p && !as_intack_now) int_latch <= int_latch_now & pend_ack & ds_iei_now;
      if (ds_rise_p || intack_rise_p) ad_drive_q <= 1'b0;
    end else begin
      if (as_fall)     pend_as_fall     <= 1'b1;
      if (as_rise)     pend_as_rise     <= 1'b1;
      if (ds_strobe)   pend_ds_fall     <= 1'b1;
      if (ds_rise)     pend_ds_rise     <= 1'b1;
      if (intack_rise) pend_intack_rise <= 1'b1;
    end

    if (pin_reset || wr9_hw) begin
      ius_mask    <= 8'h00;
      int_latch   <= 1'b0;
    end
    // WR9 Force Hardware Reset keeps the Shift Right/Shift Left bit.
    if (pin_reset) shift_right <= 1'b0;
  end

  // ---- channels ------------------------------------------------------------
  logic [1:0] ch_txd, ch_trxc_lvl, ch_rts_hold, ch_sync_drive, ch_sync_low;
  logic [7:0] wr9, wr9_b;           // shared WR9: channel A holds the chip copy
  logic [7:0] ch_rd_data [2];
  logic [7:0] ch_wr5 [2], ch_wr11 [2];
  logic [2:0] ch_rr3 [2];
  logic [3:0] ch_int_req [2];
  z8030_scc_channel u_cha (
    .clk(clk), .pclk_rise(pclk_rise),
    .rxd(rxd[0]), .cts_n(cts_n[0]), .dcd_n(dcd_n[0]), .trxc_rise(trxc_rise[0]), .trxc_fall(trxc_fall[0]), .rxc_rise(rxc_rise[0]), .rxc_fall(rxc_fall[0]),
    .txd(ch_txd[0]), .trxc_out_level(ch_trxc_lvl[0]), .wr9(wr9),
    .wr_en(ch_wr[0]), .rd_en(ch_rd[0]), .wr_reg(bus_reg_n), .rd_reg(bus_reg_n), .wr_data(ad_wr),
    .reset_ch(ch_reset[0]), .reset_hw(pin_reset | wr9_hw),
    .rd_data(ch_rd_data[0]), .rr3_ip(ch_rr3[0]), .int_req(ch_int_req[0]), .wr5(ch_wr5[0]), .wr11(ch_wr11[0]),
    .rts_hold_o(ch_rts_hold[0]), .sync_in(sync_in[0]),
    .sync_drive_o(ch_sync_drive[0]), .sync_low_o(ch_sync_low[0])
  );
  z8030_scc_channel u_chb (
    .clk(clk), .pclk_rise(pclk_rise),
    .rxd(rxd[1]), .cts_n(cts_n[1]), .dcd_n(dcd_n[1]), .trxc_rise(trxc_rise[1]), .trxc_fall(trxc_fall[1]), .rxc_rise(rxc_rise[1]), .rxc_fall(rxc_fall[1]),
    .txd(ch_txd[1]), .trxc_out_level(ch_trxc_lvl[1]), .wr9(wr9_b),
    .wr_en(ch_wr[1]), .rd_en(ch_rd[1]), .wr_reg(bus_reg_n), .rd_reg(bus_reg_n), .wr_data(ad_wr),
    .reset_ch(ch_reset[1]), .reset_hw(pin_reset | wr9_hw),
    .rd_data(ch_rd_data[1]), .rr3_ip(ch_rr3[1]), .int_req(ch_int_req[1]), .wr5(ch_wr5[1]), .wr11(ch_wr11[1]),
    .rts_hold_o(ch_rts_hold[1]), .sync_in(sync_in[1]),
    .sync_drive_o(ch_sync_drive[1]), .sync_low_o(ch_sync_low[1])
  );

  // ---- interrupt priority ----------------------------------------------------
  // Source codes: 7 A special, 6 A Rx, 5 A Ext, 4 A Tx, 3..0 the same for B.
  // Priority is Rx > Tx > Ext, A over B; an in-service source blocks
  // itself and everything below it.
  logic [7:0] src_req;
  always_comb begin
    src_req = 8'h00;
    for (int c = 0; c < 2; c++) begin
      src_req[{~c[0], 2'd3}] = ch_int_req[c][3] &  ch_int_req[c][2];
      src_req[{~c[0], 2'd2}] = ch_int_req[c][3] & ~ch_int_req[c][2];
      src_req[{~c[0], 2'd1}] = ch_int_req[c][0];
      src_req[{~c[0], 2'd0}] = ch_int_req[c][1];
    end
  end

  localparam logic [2:0] PRI_ORDER [8] = '{3'd7, 3'd6, 3'd4, 3'd5, 3'd3, 3'd2, 3'd0, 3'd1};
  localparam logic [2:0] SRC_LEVEL [8] = '{3'd1, 3'd0, 3'd2, 3'd2, 3'd4, 3'd3, 3'd5, 3'd5};

  // Level of the highest IUS bit plus one (0 = none), and that bit.
  function automatic logic [3:0] ius_level(input logic [7:0] ius);
    ius_level = 4'd0;
    for (int i = 0; i < 8; i++)
      if (ius[i] && {1'b0, SRC_LEVEL[i]} + 4'd1 > ius_level) ius_level = {1'b0, SRC_LEVEL[i]} + 4'd1;
  endfunction

  // The highest-priority request, and whether it may interrupt.
  function automatic logic [3:0] pick(input logic [7:0] req, input logic [7:0] ius);
    logic found;
    found = 1'b0;
    pick  = 4'd0;
    for (int i = 0; i < 8; i++)
      if (!found && req[PRI_ORDER[i]]) begin
        found = 1'b1;
        pick  = {{1'b0, SRC_LEVEL[PRI_ORDER[i]]} + 4'd1 > ius_level(ius), PRI_ORDER[i]};
      end
  endfunction

  logic [3:0] cur;
  logic [2:0] src;
  logic [7:0] ius_ack, ius_top, mod_vec;
  logic       mie, ack, pend_ack, int_latch_now;
  assign mie       = wr9[3];
  assign cur       = pick(src_req, ius_mask);
  assign src       = cur[2:0];
  assign int_pending = mie & cur[3];
  // The /INT latch as a service in the same sample as the /AS rise sees it.
  assign int_latch_now = as_rise ? int_pending & iei : int_latch;
  // An acknowledge needs IEI High at the /DS fall and the request latched
  // at its /AS.
  assign ack       = pclk_rise & ds_fall_p & ~as_intack_now & ds_iei_now & int_latch_now & int_pending;
  assign ius_ack   = ack ? ius_mask | (8'h01 << src) : ius_mask;
  assign pend_ack  = mie & |(pick(src_req, ius_ack) & 4'b1000);
  // Status High puts the code bit-reversed in V6:V4, Status Low in V3:V1.
  assign mod_vec   = wr9[4] ? {int_vector[7], src[0], src[1], src[2], int_vector[3:0]}
                            : {int_vector[7:4], src, int_vector[0]};

  // Reset Highest IUS clears the highest-priority bit; ties go to the lower code.
  always_comb begin
    ius_top = 8'h00;
    for (int i = 7; i >= 0; i--)
      if (ius_mask[i] && ({1'b0, SRC_LEVEL[i]} + 4'd1) == ius_level(ius_mask)) ius_top = 8'h01 << i;
  end

  // RR2 is the stored vector; channel B reads it modified, with status 011
  // when nothing is pending. RR3 exists in channel A only.
  logic [2:0] rr2_src;
  logic [7:0] rr2_vec, rd_mux;
  assign rr2_src = int_pending ? src : 3'b011;
  assign rr2_vec = wr9[4] ? {int_vector[7], rr2_src[0], rr2_src[1], rr2_src[2], int_vector[3:0]}
                          : {int_vector[7:4], rr2_src, int_vector[0]};
  always_comb begin
    case (bus_reg_n)
      4'd2:    rd_mux = bus_ch_n ? rr2_vec : int_vector;
      4'd3:    rd_mux = bus_ch_n ? 8'h00 : {2'b00, ch_rr3[0], ch_rr3[1]};
      default: rd_mux = ch_rd_data[bus_ch_n];
    endcase
  end

  // ---- outputs: power-up pin state -----------------------------------------
  always_comb begin
    ad_out     = ad_out_q;
    ad_drive   = ad_drive_q & ~ds_n;   // release on /DS High is combinational
    int_n      = ~int_latch;
    // A requesting SCC holds IEO Low through an acknowledge; DLC forces it Low.
    ieo        = ~wr9[2] & iei & (ius_mask == 8'h00) & ~(~as_intack_now & int_latch);
    txd        = ch_txd;
    rts_n      = {~ch_wr5[1][1] & ~ch_rts_hold[1], ~ch_wr5[0][1] & ~ch_rts_hold[0]};
    dtr_n      = {~ch_wr5[1][7], ~ch_wr5[0][7]};
    trxc_out   = ch_trxc_lvl;
    trxc_drive = {ch_wr11[1][2], ch_wr11[0][2]};
    sync_out   = ch_sync_drive & ~ch_sync_low;
    sync_drive = ch_sync_drive;
  end

  // ---- scaffold-only lint waivers: remove as each input gains a consumer ----
  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{ds_iei_now, as_ad_now[7:6], wr9_b, wr9[7:5],
                       ch_wr5[0][6:2], ch_wr5[0][0], ch_wr5[1][6:2], ch_wr5[1][0],
                       ch_wr11[0][7:3], ch_wr11[0][1:0], ch_wr11[1][7:3], ch_wr11[1][1:0]};
  // verilator lint_on UNUSEDSIGNAL

endmodule
