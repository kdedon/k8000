// z8030_scc_channel -- one Z8030 SCC serial channel (A or B).
//
// STATUS: SCAFFOLD (register inventory only). Every register below is a
// field of scc.Channel / scc.ChannelSnapshot in ~/git/z8000/sim/scc
// (scc.go:53-171, snapshot.go:22-96) -- FPGA_BIBLE Ch.5.2 "Structure to
// port". Nothing advances yet: the flops hold the New() power-up values
// and the transmitter marks. tb/k8030_scc/scc_access.h pokes/peeks these by
// hierarchical name (z8030_scc.u_cha.<name> / u_chb.<name>); keep the
// names or update that one file in the same change.
//
// Clocking (FPGA_BIBLE 5.2 + 0.2.3): single fabric clock `clk`; `pclk_rise`
// is a one-cycle ENABLE (Go: pclkRising) -- never a clock. Everything in
// this module commits on posedge clk when pclk_rise is high, mirroring
// the PCLK(rise) block of scc.go tickPins / advancePins.
//
// Implementation order (Bible 5.2, 5.5; Go file:line):
//   1. WR write / RR read mux            scc.go writeReg:735 readReg:640 (via top)
//   2. deferred WR0 command              scc.go execWR0:810 applyWR0Cmd:844
//   3. DCD/CTS sync + ext/status latch   scc.go advancePins:1264-1300, raiseExtStatusIP:251
//      NOTE the Go chain updates sync0 AND sync1 in the same tick
//      (sync1 = new sync0): effectively ONE stage of latency. Mirror it
//      exactly or fix the sim in the same change (Bible 0.3).
//   4. BRG counter (2*(TC+2)) + WR11 mux  scc.go brgPeriod:1115 advancePins:1300-1345
//   5. TX FSM (txIdle..txPending)        scc.go txAdvance:1528, loadTSR:1228, beginStartBit:1243
//   6. RX FSM + 3-deep FIFO + latches    scc.go rxAdvance:1373, rxPush:178, rxPop:213
//   7. TBR->TSR handoff on PCLK          scc.go advancePins:1350-1370

module z8030_scc_channel (
  input  logic        clk,
  input  logic        pclk_rise,     // enable: PCLK 0->1 seen this fabric cycle

  // serial / modem pins (Go Inputs.RxD/CTS_n/DCD_n[i], TRxCIn/RxCIn[i])
  input  logic        rxd,
  input  logic        cts_n,
  input  logic        dcd_n,
  input  logic        trxc_in,
  input  logic        rxc_in,
  output logic        txd,           // Go Channel.TxD
  output logic        trxc_out_level // Go Channel.trxcOutLevel
);

  // ---- register inventory (ChannelSnapshot order) ----------------------------
  logic [7:0]  wr [16];              // WR0..WR15
  logic [7:0]  tx_buf;               // TxBuf (TBR)
  logic        tx_buf_empty;         // TxBufEmpty  (RR0 D2)
  logic        tx_all_sent;          // TxAllSent   (RR1 D0)
  logic [7:0]  rx_fifo_data [3];     // RxFIFOData0..2
  logic [7:0]  rx_fifo_err  [3];     // RxFIFOErr0..2 (bit4 parity, bit5 overrun, bit6 framing)
  logic [1:0]  rx_fifo_len;          // RxFIFOLen 0..3
  logic [7:0]  rx_err_sticky;        // RxErrSticky
  logic [7:0]  rx_shift_err;         // RxShiftErr
  logic        tx_underrun_eom;      // TxUnderrunEOM (RR0 D6)
  logic [17:0] baud_counter;         // BaudCounter (max 2*(65535+2))
  logic        rxd_q;                // RxD (pin sampled at PCLK rise)
  logic [2:0]  rx_state;             // RxState: 0 idle 1 start 2 data 3 parity 4 stop
  logic [7:0]  rx_shift;             // RxShift
  logic [3:0]  rx_bit_count;         // RxBitCount
  logic [6:0]  rx_sub_count;         // RxSubCount (1..64)
  logic [1:0]  rx_stop_bit;          // RxStopBit
  logic        rx_break;             // RxBreak (RR0 D7 live)
  logic        txd_q;                // TxD
  logic [2:0]  tx_state;             // TxState: 0 idle 1 start 2 data 3 parity 4 stop 5 pending
  logic [7:0]  tx_shift;             // TxShift (TSR)
  logic [3:0]  tx_bit_count;         // TxBitCount
  logic [6:0]  tx_sub_count;         // TxSubCount
  logic [1:0]  tx_stop_bit;          // TxStopBit
  logic        tx_ip;                // TxIP
  logic        rx_int_next_char;     // RxIntNextChar
  logic        rx_int_forced;        // RxIntForced
  logic        ext_ip;               // ExtIP
  logic        dcd_latch;            // DcdLatch
  logic        cts_latch;            // CtsLatch
  logic        dcd_sync0;            // DcdSync0
  logic        dcd_sync1;            // DcdSync1
  logic        cts_sync0;            // CtsSync0
  logic        cts_sync1;            // CtsSync1
  logic        ext_latch_closed;     // ExtLatchClosed
  logic        break_latch;          // BreakLatch
  logic        underrun_latch;       // UnderrunLatch
  logic        pending_wr0;          // PendingWR0
  logic [2:0]  pending_wr0_cmd;      // PendingWR0Cmd
  logic        prev_rtxc;            // PrevRTxC
  logic        prev_trxc;            // PrevTRxC
  logic        trxc_out_lvl;         // TrxcOutLevel
  logic        rts_hold;             // RtsHold (Auto Enables /RTS hold, R-SCC-045)
  // live modem levels (Go Channel.DCD/CTS: pin sampled at PCLK rise,
  // active-high; not part of the snapshot)
  logic        dcd_live;
  logic        cts_live;

  // ---- power-up state == Go New() == hardware reset with idle pins ---------
  // The Z8030 has no reset pin (hardware reset = /AS+/DS Low, handled in
  // the top). Vendor power-up init (Bible 0.1 / lesson sv-68) reproduces
  // the Go constructor, which is the SCC/ESCC User Manual reset table
  // (UM010903 p.26-27, Hardware RESET column) applied to a zeroed chip:
  // WR4 = 04 (1 stop bit), WR11 = 08 (Tx clock from /TRxC), WR14 = 20,
  // WR15 = F8 (DCD/Sync/CTS/Underrun/Break IE set); TBR empty, all sent,
  // underrun latch set, lines marking, DCD/CTS chains and latches at the
  // idle (deasserted) pin level -- RR0 D3/D5 are X after reset and simply
  // track the pins.
  initial begin
    for (int i = 0; i < 16; i++) wr[i] = 8'h00;
    wr[4] = 8'h04; wr[11] = 8'h08; wr[14] = 8'h20; wr[15] = 8'hF8;
    tx_buf = 8'h00; tx_buf_empty = 1'b1; tx_all_sent = 1'b1;
    for (int i = 0; i < 3; i++) begin rx_fifo_data[i] = 8'h00; rx_fifo_err[i] = 8'h00; end
    rx_fifo_len = 2'd0; rx_err_sticky = 8'h00; rx_shift_err = 8'h00;
    tx_underrun_eom = 1'b1; baud_counter = 18'd0;
    rxd_q = 1'b1; rx_state = 3'd0; rx_shift = 8'h00; rx_bit_count = 4'd0;
    rx_sub_count = 7'd0; rx_stop_bit = 2'd0; rx_break = 1'b0;
    txd_q = 1'b1; tx_state = 3'd0; tx_shift = 8'h00; tx_bit_count = 4'd0;
    tx_sub_count = 7'd0; tx_stop_bit = 2'd0;
    tx_ip = 1'b0; rx_int_next_char = 1'b0; rx_int_forced = 1'b0; ext_ip = 1'b0;
    dcd_latch = 1'b0; cts_latch = 1'b0;
    dcd_sync0 = 1'b0; dcd_sync1 = 1'b0; cts_sync0 = 1'b0; cts_sync1 = 1'b0;
    ext_latch_closed = 1'b0; break_latch = 1'b0; underrun_latch = 1'b1;
    pending_wr0 = 1'b0; pending_wr0_cmd = 3'd0;
    prev_rtxc = 1'b0; prev_trxc = 1'b0; trxc_out_lvl = 1'b0; rts_hold = 1'b0;
    dcd_live = 1'b0; cts_live = 1'b0;
  end

  // TODO(scaffold): PCLK(rise) block -- sample rxd/dcd/cts into rxd_q/
  // dcd_live/cts_live (Go tickPins:540-556), then advancePins steps 2..7.
  always_ff @(posedge clk) begin
    if (pclk_rise) begin
      // TODO(scaffold): register commits go here.
    end
  end

  assign txd            = txd_q;
  assign trxc_out_level = trxc_out_lvl;

  // ---- scaffold-only lint waivers: remove as each input gains a consumer ----
  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{rxd, cts_n, dcd_n, trxc_in, rxc_in,
                       wr[0], wr[1], wr[2], wr[3], wr[4], wr[5], wr[6], wr[7],
                       wr[8], wr[9], wr[10], wr[11], wr[12], wr[13], wr[14], wr[15],
                       tx_buf, tx_buf_empty, tx_all_sent,
                       rx_fifo_data[0], rx_fifo_data[1], rx_fifo_data[2],
                       rx_fifo_err[0], rx_fifo_err[1], rx_fifo_err[2],
                       rx_fifo_len, rx_err_sticky, rx_shift_err, tx_underrun_eom,
                       baud_counter, rxd_q, rx_state, rx_shift, rx_bit_count,
                       rx_sub_count, rx_stop_bit, rx_break, tx_state, tx_shift,
                       tx_bit_count, tx_sub_count, tx_stop_bit, tx_ip,
                       rx_int_next_char, rx_int_forced, ext_ip, dcd_latch, cts_latch,
                       dcd_sync0, dcd_sync1, cts_sync0, cts_sync1, ext_latch_closed,
                       break_latch, underrun_latch, pending_wr0, pending_wr0_cmd,
                       prev_rtxc, prev_trxc, rts_hold, dcd_live, cts_live};
  // verilator lint_on UNUSEDSIGNAL

endmodule
