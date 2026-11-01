// z8030_scc_channel -- one Z8030 SCC serial channel (A or B).
//
// STATUS: register write/read, RR8 FIFO pop, resets, WR0 commands,
// DCD/CTS ext/status, BRG, WR11 clock mux, the async transmitter and
// the async receiver. Every register below is a
// field of scc.Channel / scc.ChannelSnapshot in ~/git/z8000/sim/scc
// (scc.go:53-171, snapshot.go:22-96) -- FPGA_BIBLE Ch.5.2 "Structure to
// port". tb/k8030_scc/scc_access.h pokes/peeks these by
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
  input  logic        sync_in,       // /SYNC pin level
  output logic        txd,           // Go Channel.TxD
  output logic        trxc_out_level, // Go Channel.trxcOutLevel
  output logic [7:0]  wr9,            // channel A's copy is the chip's WR9

  // register port (from the top's bus decode)
  input  logic        wr_en,         // write this channel's register wr_reg
  input  logic        rd_en,         // read strobe for rd_reg (RR8 pops the FIFO)
  input  logic [3:0]  wr_reg,
  input  logic [3:0]  rd_reg,
  input  logic [7:0]  wr_data,
  input  logic        reset_ch,      // channel reset (WR9 command or hardware)
  input  logic        reset_hw,      // ... the hardware flavour
  output logic [7:0]  rd_data,       // RR0/1/8/10/12/13/15; others read 0
  output logic [2:0]  rr3_ip,        // {Rx, Tx, Ext/Status} IP, each gated by its enable
  output logic [3:0]  int_req,       // {Rx fires, Rx is special, Tx, Ext/Status} for /INT
  output logic [7:0]  wr5,
  output logic [7:0]  wr11,
  output logic        rts_hold_o,
  output logic        sync_drive_o,  // /SYNC is an output (monosync, bisync)
  output logic        sync_low_o     // ... and is Low: a sync match
);
  /*verilator inline_module*/

  // ---- register inventory (ChannelSnapshot order) ----------------------------
  logic [7:0]  wr [16];              // WR0..WR15
  logic [7:0]  tx_buf;               // TxBuf (TBR)
  logic        tx_buf_empty;         // TxBufEmpty  (RR0 D2)
  logic        tx_all_sent;          // TxAllSent   (RR1 D0)
  logic [7:0]  rx_fifo_data [3];     // RxFIFOData0..2
  logic [7:0]  rx_fifo_err  [3];     // RxFIFOErr0..2 (bit0 parity, bit1 overrun, bit2 framing)
  logic [1:0]  rx_fifo_len;          // RxFIFOLen 0..3
  logic [7:0]  rx_err_sticky;        // RxErrSticky
  logic [7:0]  rx_shift_err;         // RxShiftErr
  logic        tx_underrun_eom;      // TxUnderrunEOM (RR0 D6)
  logic [17:0] baud_counter;         // BaudCounter (max 2*(65535+2))
  logic [15:0] brg_tc;               // BrgTC: time constant loaded into the counter
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
  logic        rx_lock;              // a special character read holds the FIFO exit
  logic        ext_ip;               // ExtIP
  logic        dcd_latch;            // DcdLatch
  logic        cts_latch;            // CtsLatch
  logic        dcd_sync1;            // DcdSync1 (the model's DcdSync0 is the same sample)
  logic        cts_sync1;            // CtsSync1 (likewise CtsSync0)
  logic        ext_latch_closed;     // ExtLatchClosed
  logic        break_latch;          // BreakLatch
  logic        underrun_latch;       // UnderrunLatch
  logic        pending_wr0;          // PendingWR0
  logic [2:0]  pending_wr0_cmd;      // PendingWR0Cmd
  logic        prev_rtxc;            // PrevRTxC
  logic        prev_trxc;            // PrevTRxC
  logic        trxc_out_lvl;         // TrxcOutLevel
  logic        rts_hold;             // RtsHold (Auto Enables /RTS hold, R-SCC-045)
  // SDLC framing (Go sdlcState)
  logic [15:0] sd_tx_sr;             // bits still to send, LSB first
  logic [4:0]  sd_tx_n;
  logic [1:0]  sd_tx_kind;           // 0 flag/mark/abort, 1 data, 2 CRC
  logic [2:0]  sd_tx_ones;
  logic [15:0] sd_tx_crc;
  logic [7:0]  sd_tx_pipe;           // zero inserter delay; TxD is D5
  logic        sd_hunt, sd_in_frame, sd_rx_chars, hunt_latch;
  logic [7:0]  sd_rx_raw;            // last 8 line bits, newest in D7
  logic [3:0]  sd_rx_ones, sd_rx_nb, sd_rx_cnt;
  logic [31:0] sd_rx_hist;           // data bits after zero deletion, newest in D31
  logic [15:0] sd_rx_crc;
  logic [7:0]  sd_residue;           // RR1 D3:D1
  // Byte sync (Go sdlcState byte-sync fields)
  logic        sd_tx_crc_on;         // WR5 D0 taken with the character
  logic [1:0]  sd_rx_pend;           // bits until the assembled character loads
  logic        sd_crc_on, sd_strip_prev, sd_sync_out, sync_pin;
  // SDLC Loop (Go sdlcState Loop fields)
  logic        lp_on, lp_send, lp_poll, lp_bit, lp_conv;
  logic [2:0]  lp_drain;
  // DPLL and line coding (Go dpllState)
  logic        dp_on, dp_search, dp_brg, dp_fm, dp_seen, dp_miss1, dp_miss2;
  logic [4:0]  dp_cnt;
  logic [1:0]  dp_adj, dp_next, dp_miss_n; // corrections: 1 add, 2 drop a count
  logic        dp_clk, dp_rx_in, dp_rxo, dp_txo, tx_line, tx_raw, rx_prev, rx_bit;
  // live modem levels (Go Channel.DCD/CTS: pin sampled at PCLK rise,
  // active-high; not part of the snapshot)
  logic        dcd_live;
  logic        cts_live;

  // No power-up values: every flop starts at 0 and the hardware reset
  // (the top holds it through the first clock) sets the Go New() state.

  // ---- status and read mux ------------------------------------------------
  logic       rx_avail, sync_mode;
  logic [7:0] rx_vis_err;
  assign rx_avail   = rx_fifo_len != 2'd0;
  assign sync_mode  = wr[4][3:2] == 2'b00;
  assign rx_vis_err = (rx_avail ? (rx_fifo_err[0] & 8'h0C) : 8'h00) | rx_err_sticky;
  logic sdlc, bsync, ext_sync;
  assign sdlc     = wr[4][5:2] == 4'b1000;
  assign bsync    = sync_mode && wr[4][5:4] != 2'b10;
  assign ext_sync = wr[4][5:2] == 4'b1100;
  assign sync_drive_o = bsync && !ext_sync;
  assign sync_low_o   = sd_sync_out;

  logic dcd_rr0, cts_rr0, brk_rr0, unr_rr0;
  assign dcd_rr0 = ext_latch_closed ? dcd_latch      : dcd_sync1;
  assign cts_rr0 = ext_latch_closed ? cts_latch      : cts_sync1;
  assign brk_rr0 = ext_latch_closed ? break_latch    : rx_break;
  assign unr_rr0 = ext_latch_closed ? underrun_latch : tx_underrun_eom;
  logic hunt_rr0;
  assign hunt_rr0 = (ext_latch_closed ? hunt_latch : (ext_sync ? sync_pin : sd_hunt)) & sync_mode;

  always_comb begin
    case (rd_reg)
      4'd0:    rd_data = {brk_rr0, unr_rr0, cts_rr0, hunt_rr0, dcd_rr0, tx_buf_empty, 1'b0, rx_avail};
      4'd1:    rd_data = {rx_vis_err[3:0], sdlc ? sd_residue[3:1] : 3'b011, tx_all_sent | sync_mode};
      4'd8:    rd_data = rx_avail ? rx_fifo_data[0] : 8'h00;
      4'd10:   rd_data = {dp_miss1, dp_miss2, 1'b0, lp_send, 2'd0, lp_on, 1'b0};
      4'd12:   rd_data = wr[12];
      4'd13:   rd_data = wr[13];
      4'd15:   rd_data = wr[15];
      default: rd_data = 8'h00;
    endcase
  end


  // Overrun and End of Frame are special, framing only async, parity
  // only with WR1 D2. The CRC error rides every sync character.
  logic rx_special, rx_fire;
  assign rx_special = rx_vis_err[1] | rx_vis_err[3] | (rx_vis_err[2] & ~sync_mode) |
                      (rx_vis_err[0] & wr[1][2]);
  always_comb begin
    case (wr[1][4:3])
      2'b01:   rx_fire = rx_special | rx_int_forced;
      2'b10:   rx_fire = 1'b1;
      2'b11:   rx_fire = rx_special;
      default: rx_fire = 1'b0;
    endcase
  end
  // RR3's Rx IP is the condition that drives the interrupt.
  assign rr3_ip  = {rx_avail & rx_fire, tx_ip & wr[1][1], ext_ip & wr[1][0]};
  assign int_req = {rr3_ip[2], rx_special, rr3_ip[1:0]};

  // ---- next state ----------------------------------------------------------
  // Bus side first (reset, register write, WR0 command), then -- on a PCLK
  // rise -- one step of the ext/status sampler, BRG, clock mux and
  // transmitter, all seeing what the bus just did.
  logic [7:0]  n_wr [16];
  logic [7:0]  n_tx_buf, n_tx_shift;
  logic        n_tx_buf_empty, n_tx_all_sent, n_tx_underrun_eom, n_tx_ip, n_txd;
  logic [2:0]  n_tx_state;
  logic [3:0]  n_tx_bit_count;
  logic [6:0]  n_tx_sub_count;
  logic [1:0]  n_tx_stop_bit;
  logic [17:0] n_baud_counter;
  logic [15:0] n_brg_tc;
  logic        n_ext_ip, n_ext_latch_closed;
  logic        n_dcd_latch, n_cts_latch, n_break_latch, n_underrun_latch;
  logic        n_dcd_sync, n_cts_sync, n_trxc_out_lvl, n_rts_hold;
  logic [7:0]  n_rx_fifo_data [3];
  logic [7:0]  n_rx_fifo_err  [3];
  logic [1:0]  n_rx_fifo_len;
  logic [7:0]  n_rx_err_sticky, n_rx_shift_err, n_rx_shift;
  logic [2:0]  n_rx_state;
  logic [3:0]  n_rx_bit_count;
  logic [6:0]  n_rx_sub_count;
  logic [1:0]  n_rx_stop_bit;
  logic        n_rx_break, n_rx_int_next_char, n_rx_int_forced, n_rx_lock, rx_pop;

  logic        dcd_now, cts_now, rtxc_rise, trxc_rise, brk_now;
  assign dcd_now   = ~dcd_n;
  assign cts_now   = ~cts_n;
  assign rtxc_rise = ~prev_rtxc & rxc_in;
  assign trxc_rise = ~prev_trxc & trxc_in;
  assign brk_now   = reset_ch ? 1'b0 : rx_break;

  logic        brg_edge, brg_lvl, tx_edge, tx_en, tx_par, tx_two_stop, tx_half_stop;
  logic [17:0] b_inc, b_per;
  logic        brg_start, b_wrap, b_half, b_inc_lt, b_cur_lt;
  logic [6:0]  cm;
  logic [3:0]  tx_bits;
  logic [7:0]  tx_mask;
  logic [2:0]  cmd;
  logic        auto_en;
  logic        rx_edge, rx_par;
  logic [3:0]  rx_bits;
  logic [6:0]  rx_mid;
  logic [7:0]  rx_err, rx_fill, rx_data;
  logic        rx_push;
  logic [15:0] n_sd_tx_sr, n_sd_tx_crc, n_sd_rx_crc;
  logic [4:0]  n_sd_tx_n;
  logic [1:0]  n_sd_tx_kind;
  logic [2:0]  n_sd_tx_ones;
  logic [7:0]  n_sd_tx_pipe, n_sd_rx_raw, n_sd_residue, sd_char, sd_err;
  logic        n_sd_hunt, n_sd_in_frame, n_sd_rx_chars, n_hunt_latch;
  logic [3:0]  n_sd_rx_ones, n_sd_rx_nb, n_sd_rx_cnt;
  logic [31:0] n_sd_rx_hist;
  logic        sd_out, sd_b, sd_del, sd_done;
  logic [15:0] crc_preset, sd_preset;
  logic        sd_mode, bs_mode, bs_ext, bs_load, n_sd_tx_crc_on, n_sd_crc_on;
  logic        n_sd_strip_prev, n_sd_sync_out, n_sync_pin;
  logic [1:0]  n_sd_rx_pend;
  logic        n_lp_on, n_lp_send, n_lp_poll, n_lp_bit, n_lp_conv, lp_loop, lp_rep, sd_cut;
  logic [2:0]  n_lp_drain;
  logic [15:0] sd_fill;
  logic [3:0]  sd_slot;
  logic [3:0]  bs_n, bs_w;
  logic [8:0]  bs_win;
  logic [7:0]  bs_err;
  logic        n_dp_on, n_dp_search, n_dp_brg, n_dp_fm, n_dp_seen, n_dp_miss1, n_dp_miss2;
  logic [4:0]  n_dp_cnt;
  logic [1:0]  n_dp_adj, n_dp_next, n_dp_miss_n, enc;
  logic        n_dp_clk, n_dp_rx_in, n_dp_rxo, n_dp_txo, n_tx_line, n_tx_raw, n_rx_prev, n_rx_bit;
  logic        dclk, d_rx, d_tx, drr, drf, dtr, dtf, brg_fall, tx_mid, rx_half, rxa;
  logic [5:0]  d_h;
  logic [1:0]  dp_srx, dp_stx;        // outputs after the next count: NRZI in D0, FM in D1
  logic [4:0]  s_cnt;
  logic        d_step, ext_mid, dcd_mid, cts_mid;
  logic        rx_dec;

  // One bit into a bit-reversed CRC register: CRC-CCITT, or CRC-16 with WR5 D2.
  function automatic logic [15:0] crc_step(input logic [15:0] c, input logic b, input logic crc16);
    crc_step = {1'b0, c[15:1]} ^ ((c[0] ^ b) ? (crc16 ? 16'hA001 : 16'h8408) : 16'h0000);
  endfunction

  // A character snapshot: the newest assembled bit lands in D(n-1),
  // later line bits above it.
  function automatic logic [7:0] sd_snap(input logic [24:14] h, input logic [3:0] n);
    case (n)
      4'd5:    sd_snap = h[24:17];
      4'd6:    sd_snap = h[23:16];
      4'd7:    sd_snap = h[22:15];
      default: sd_snap = h[21:14];
    endcase
  endfunction

  // RR0 D4: the /SYNC pin in External Sync, else Hunt.
`define SCC_HUNT (n_wr[4][5:2] == 4'b1100 ? n_sync_pin : n_sd_hunt)

  // The newest line bits against the receive sync, left-justified in WR7:WR6.
  function automatic logic sync_match(input logic [15:0] h, input logic [7:0] w7, input logic [7:0] w6,
                                      input logic bi, input logic six);
    if (bi && six)  sync_match = h[15:4] == {w7, w6[7:4]};
    else if (bi)    sync_match = h == {w7, w6};
    else if (six)   sync_match = h[15:10] == w7[7:2];
    else            sync_match = h[15:8] == w7;
  endfunction

  // Close the ext/status latch over the values of this moment.
`define SCC_EXT_RAISE begin \
    n_ext_ip = 1'b1; \
    if (!n_ext_latch_closed) begin \
      n_ext_latch_closed = 1'b1; \
      n_dcd_latch = n_dcd_sync; n_cts_latch = n_cts_sync; n_break_latch = n_rx_break; \
      n_underrun_latch = n_tx_underrun_eom; n_hunt_latch = `SCC_HUNT; \
    end \
  end

  always_comb begin
    n_sd_tx_sr = sd_tx_sr; n_sd_tx_n = sd_tx_n; n_sd_tx_kind = sd_tx_kind;
    n_sd_tx_ones = sd_tx_ones; n_sd_tx_crc = sd_tx_crc; n_sd_tx_pipe = sd_tx_pipe;
    n_sd_hunt = sd_hunt; n_sd_in_frame = sd_in_frame; n_sd_rx_chars = sd_rx_chars;
    n_hunt_latch = hunt_latch; n_sd_rx_raw = sd_rx_raw; n_sd_rx_ones = sd_rx_ones;
    n_sd_rx_nb = sd_rx_nb; n_sd_rx_cnt = sd_rx_cnt; n_sd_rx_hist = sd_rx_hist;
    n_sd_rx_crc = sd_rx_crc; n_sd_residue = sd_residue;
    n_sd_tx_crc_on = sd_tx_crc_on; n_sd_rx_pend = sd_rx_pend; n_sd_crc_on = sd_crc_on;
    n_sd_strip_prev = sd_strip_prev; n_sd_sync_out = sd_sync_out; n_sync_pin = sync_pin;
    n_lp_on = lp_on; n_lp_send = lp_send; n_lp_poll = lp_poll; n_lp_bit = lp_bit;
    n_lp_conv = lp_conv; n_lp_drain = lp_drain; lp_loop = 1'b0; lp_rep = 1'b0;
    sd_cut = 1'b0; sd_fill = 16'h0000; sd_slot = 4'd0;
    bs_mode = 1'b0; bs_ext = 1'b0; bs_load = 1'b0; bs_n = 4'd8; bs_w = 4'd8;
    bs_win = 9'h000; bs_err = 8'h00;
    sd_out = 1'b1; sd_b = 1'b1; sd_del = 1'b0; sd_done = 1'b0; sd_char = 8'h00; sd_err = 8'h00;
    crc_preset = wr[10][7] ? 16'hFFFF : 16'h0000;
    sd_mode = 1'b0; sd_preset = 16'h0000;
    for (int i = 0; i < 16; i++) n_wr[i] = wr[i];
    n_tx_buf = tx_buf; n_tx_shift = tx_shift;
    n_tx_buf_empty = tx_buf_empty; n_tx_all_sent = tx_all_sent;
    n_tx_underrun_eom = tx_underrun_eom; n_tx_ip = tx_ip; n_txd = txd_q;
    n_tx_state = tx_state; n_tx_bit_count = tx_bit_count;
    n_tx_sub_count = tx_sub_count; n_tx_stop_bit = tx_stop_bit;
    n_baud_counter = baud_counter; n_brg_tc = brg_tc;
    n_ext_ip = ext_ip; n_ext_latch_closed = ext_latch_closed;
    n_dcd_latch = dcd_latch; n_cts_latch = cts_latch;
    n_break_latch = break_latch; n_underrun_latch = underrun_latch;
    n_dcd_sync = dcd_sync1; n_cts_sync = cts_sync1;
    n_trxc_out_lvl = trxc_out_lvl; n_rts_hold = rts_hold;
    n_dp_on = dp_on; n_dp_search = dp_search; n_dp_brg = dp_brg; n_dp_fm = dp_fm;
    n_dp_seen = dp_seen; n_dp_miss1 = dp_miss1; n_dp_miss2 = dp_miss2; n_dp_cnt = dp_cnt;
    n_dp_adj = dp_adj; n_dp_next = dp_next; n_dp_miss_n = dp_miss_n; n_dp_clk = dp_clk;
    n_dp_rx_in = dp_rx_in; n_dp_rxo = dp_rxo; n_dp_txo = dp_txo; n_tx_line = tx_line;
    n_tx_raw = tx_raw; n_rx_prev = rx_prev; n_rx_bit = rx_bit;
    dclk = 1'b0; d_rx = 1'b0; d_tx = 1'b0; drr = 1'b0; drf = 1'b0; dtr = 1'b0; dtf = 1'b0;
    brg_fall = 1'b0; tx_mid = 1'b0; rx_half = 1'b0; rxa = 1'b1; d_h = 6'd0; enc = 2'd0; rx_dec = 1'b1; d_step = 1'b0; ext_mid = 1'b1; dcd_mid = 1'b1; cts_mid = 1'b1;
    for (int i = 0; i < 3; i++) begin
      n_rx_fifo_data[i] = rx_fifo_data[i]; n_rx_fifo_err[i] = rx_fifo_err[i];
    end
    n_rx_fifo_len = rx_fifo_len; n_rx_err_sticky = rx_err_sticky;
    n_rx_shift_err = rx_shift_err; n_rx_shift = rx_shift; n_rx_state = rx_state;
    n_rx_bit_count = rx_bit_count; n_rx_sub_count = rx_sub_count;
    n_rx_stop_bit = rx_stop_bit; n_rx_break = brk_now;
    n_rx_int_next_char = rx_int_next_char; n_rx_int_forced = rx_int_forced;
    n_rx_lock = rx_lock; rx_pop = 1'b0;
    rx_edge = 1'b0; rx_par = 1'b0; rx_bits = 4'd8; rx_mid = 7'd1; rx_err = 8'h00;
    rx_fill = 8'h00; rx_data = 8'h00; rx_push = 1'b0;
    tx_two_stop = 1'b0; tx_half_stop = 1'b0;
    brg_edge = 1'b0; brg_lvl = 1'b0; tx_edge = 1'b0; tx_en = 1'b0; tx_par = 1'b0;
    brg_start = 1'b0; cm = 7'd1; tx_bits = 4'd8; tx_mask = 8'hFF; auto_en = 1'b0;
    cmd = wr_data[5:3];

    if (reset_ch) begin
      n_wr[0]  = 8'h00;
      n_wr[1]  = wr[1] & 8'h24;
      n_wr[3]  = wr[3] & 8'hFE;
      n_wr[4]  = wr[4] | 8'h04;
      n_wr[5]  = wr[5] & 8'h61;
      n_wr[15] = 8'hF8;
      if (reset_hw) begin
        n_wr[9]  = wr[9] & 8'h03;
        n_wr[10] = 8'h00;
        n_wr[11] = 8'h08;
        n_wr[14] = (wr[14] & 8'hC0) | 8'h20;
      end else begin
        n_wr[10] = wr[10] & 8'h60;
        n_wr[14] = (wr[14] & 8'hC3) | 8'h20;
      end
      n_rts_hold = 1'b0;
      n_tx_buf = 8'h00; n_tx_buf_empty = 1'b1; n_tx_all_sent = 1'b1; n_tx_ip = 1'b0;
      n_tx_underrun_eom = 1'b1;
      n_ext_ip = 1'b0; n_ext_latch_closed = 1'b0;
      n_baud_counter = '0; n_brg_tc = {wr[13], wr[12]}; n_trxc_out_lvl = 1'b0; brg_start = 1'b1;
      n_txd = 1'b1; n_tx_state = 3'd0; n_tx_shift = 8'h00; n_tx_bit_count = 4'd0;
      n_tx_sub_count = 7'd0; n_tx_stop_bit = 2'd0;
      // The modem latches and synchronisers restart at the live pin level.
      n_dcd_latch = dcd_live; n_cts_latch = cts_live;
      n_break_latch = 1'b0; n_underrun_latch = 1'b1; n_hunt_latch = 1'b1;
      n_dcd_sync = dcd_live; n_cts_sync = cts_live;
      for (int i = 0; i < 3; i++) begin n_rx_fifo_data[i] = 8'h00; n_rx_fifo_err[i] = 8'h00; end
      n_rx_fifo_len = 2'd0; n_rx_err_sticky = 8'h00; n_rx_shift_err = 8'h00;
      n_rx_int_next_char = 1'b1; n_rx_int_forced = 1'b0; n_rx_lock = 1'b0;
      n_rx_state = 3'd0; n_rx_shift = 8'h00; n_rx_bit_count = 4'd0;
      n_rx_sub_count = 7'd0; n_rx_stop_bit = 2'd0;
      n_sd_tx_sr = '0; n_sd_tx_n = '0; n_sd_tx_kind = '0; n_sd_tx_ones = '0;
      n_sd_tx_crc = '0; n_sd_tx_pipe = 8'h3F; n_sd_hunt = 1'b1; n_sd_in_frame = 1'b0;
      n_sd_rx_chars = 1'b0; n_sd_rx_raw = '0; n_sd_rx_ones = '0; n_sd_rx_nb = '0;
      n_sd_rx_cnt = '0; n_sd_rx_hist = '0; n_sd_rx_crc = '0; n_sd_residue = 8'h06;
      n_sd_tx_crc_on = 1'b0; n_sd_rx_pend = '0; n_sd_crc_on = 1'b0;
      n_sd_strip_prev = 1'b0; n_sd_sync_out = 1'b0;
      n_lp_on = 1'b0; n_lp_send = 1'b0; n_lp_poll = 1'b0; n_lp_bit = 1'b1;
      n_lp_conv = 1'b0; n_lp_drain = 3'd0;
      n_dp_on = 1'b0; n_dp_search = 1'b1; n_dp_brg = 1'b0; n_dp_fm = 1'b0; n_dp_seen = 1'b0;
      n_dp_miss1 = 1'b0; n_dp_miss2 = 1'b0; n_dp_cnt = 5'd16; n_dp_adj = 2'd0; n_dp_next = 2'd0;
      n_dp_miss_n = 2'd0; n_dp_clk = 1'b0; n_dp_rx_in = 1'b1; n_dp_rxo = 1'b1; n_dp_txo = 1'b1;
      n_tx_line = 1'b1; n_tx_raw = 1'b1; n_rx_prev = 1'b1; n_rx_bit = 1'b1;
    end

    if (wr_en) begin
      n_wr[wr_reg] = wr_reg == 4'd9 ? (wr_data & 8'h3F) : wr_data;
      // BRG startup loads the time constant; the output starts High.
      if (wr_reg == 4'd14 && !wr[14][0] && wr_data[0]) begin
        n_baud_counter = '0; n_brg_tc = {wr[13], wr[12]}; brg_start = 1'b1;
      end
      // DPLL commands. Reset Missing Clock disables it as Disable does.
      if (wr_reg == 4'd14) begin
        case (wr_data[7:5])
          3'd1, 3'd2, 3'd3: begin
            n_dp_on = wr_data[7:5] == 3'd1; n_dp_search = 1'b1; n_dp_cnt = 5'd16;
            n_dp_adj = 2'd0; n_dp_seen = 1'b0; n_dp_next = 2'd0;
            n_dp_miss_n = 2'd0; n_dp_miss1 = 1'b0; n_dp_miss2 = 1'b0;
          end
          3'd4, 3'd5: n_dp_brg = !wr_data[5];
          3'd6, 3'd7: n_dp_fm  = !wr_data[5];
          default: ;
        endcase
      end
      case (wr_reg)
        4'd0: begin
          if (wr_data[7:6] == 2'b11) n_tx_underrun_eom = 1'b0;
          if (wr_data[7:6] == 2'b01) n_sd_rx_crc = crc_preset;
          if (wr_data[7:6] == 2'b10) n_sd_tx_crc = crc_preset;
          case (cmd)
            // Reset Ext/Status: reopen the latch at the live levels.
            3'd2: begin
              n_ext_latch_closed = 1'b0; n_ext_ip = 1'b0;
              n_dcd_latch = n_dcd_sync; n_cts_latch = n_cts_sync;
              n_break_latch = brk_now; n_underrun_latch = n_tx_underrun_eom; n_hunt_latch = `SCC_HUNT;
            end
            // Send Abort: eight 1s at once, the buffer cleared, EOM set.
            3'd3: if (sdlc) begin
              n_sd_tx_sr = 16'h00FF; n_sd_tx_n = 5'd8; n_sd_tx_kind = 2'd0; n_sd_tx_ones = 3'd0;
              n_tx_buf_empty = 1'b1;
              if (!n_tx_underrun_eom) begin
                n_tx_underrun_eom = 1'b1;
                if (n_wr[15][6]) `SCC_EXT_RAISE
              end
            end
            3'd4: n_rx_int_next_char = 1'b1;
            3'd5: n_tx_ip = 1'b0;
            3'd6: begin
              n_rx_err_sticky = 8'h00;
              n_rx_lock       = 1'b0;
              rx_pop          = rx_lock;
            end
            default: ;
          endcase
        end
        4'd3: if (wr_data[4] && sync_mode) begin   // Enter Hunt
          if (!n_sd_hunt) begin
            n_sd_hunt = 1'b1;
            if (n_wr[15][4] && !ext_sync) `SCC_EXT_RAISE
          end
          n_sd_in_frame = 1'b0;
        end
        // First Char or Special mode re-arms the one-shot.
        4'd1: if (wr_data[4:3] == 2'b01) begin
          n_rx_int_next_char = 1'b1;
          n_rx_int_forced    = 1'b0;
        end
        // Dropping RTS under Auto Enables holds the pin until the
        // transmitter has drained.
        4'd5: begin
          if (wr[5][1] && !wr_data[1] && wr[3][5] && !sync_mode &&
              !(tx_all_sent && tx_buf_empty))
            n_rts_hold = 1'b1;
          if (wr_data[1]) n_rts_hold = 1'b0;
        end
        4'd8: begin
          n_tx_ip        = 1'b0;
          n_tx_buf       = wr_data;
          n_tx_buf_empty = 1'b0;
        end
        default: ;
      endcase
    end

    // RR8 pops the FIFO head; the next character's parity/overrun latch.
    // In First Char or Special and Special Only modes a special
    // character stays at the exit until Error Reset, which pops it.
    if (rd_en && rd_reg == 4'd8) begin
      n_rx_int_forced = 1'b0;
      if (rx_avail && !rx_lock) begin
        if (wr[1][3] && rx_special) n_rx_lock = 1'b1;
        else                        rx_pop    = 1'b1;
      end
    end
    if (rx_pop) begin
      n_rx_fifo_data[0] = rx_fifo_data[1]; n_rx_fifo_data[1] = rx_fifo_data[2];
      n_rx_fifo_err[0]  = rx_fifo_err[1];  n_rx_fifo_err[1]  = rx_fifo_err[2];
      n_rx_fifo_len     = rx_fifo_len - 2'd1;
      if (n_rx_fifo_len != 2'd0) n_rx_err_sticky = n_rx_err_sticky | (n_rx_fifo_err[0] & 8'h03);
    end

    if (pclk_rise) begin
      // /SYNC: in External Sync both edges are ext/status transitions.
      if (n_wr[4][5:2] == 4'b1100 && n_sync_pin != sync_in && n_wr[15][4]) begin
        n_sync_pin = sync_in;
        `SCC_EXT_RAISE
      end
      n_sync_pin = sync_in;
      // DCD/CTS: one PCLK from pin to detection.
      if (((dcd_now != n_dcd_sync) && n_wr[15][3]) ||
          ((cts_now != n_cts_sync) && n_wr[15][5])) begin
        n_ext_ip = 1'b1;
        if (!n_ext_latch_closed) begin
          n_ext_latch_closed = 1'b1;
          n_dcd_latch = dcd_now; n_cts_latch = cts_now;
          n_break_latch = brk_now; n_underrun_latch = n_tx_underrun_eom; n_hunt_latch = `SCC_HUNT;
        end
      end
      n_dcd_sync = dcd_now; n_cts_sync = cts_now;
      ext_mid = n_ext_latch_closed; dcd_mid = n_dcd_latch; cts_mid = n_cts_latch;

      // BRG: 2 * (time constant + 2) source clocks per output edge. A new
      // time constant waits for the next load of the counter.
      // The compares come from the registered count; a restarted count
      // is 0 or 1, never an edge and below half.
      if (n_wr[14][0] && (n_wr[14][1] || rtxc_rise)) begin
        if (brg_start) n_baud_counter = 18'd1;
        else if (b_wrap) begin
          n_baud_counter = '0; n_brg_tc = {n_wr[13], n_wr[12]};
          brg_edge = 1'b1;
        end else begin
          n_baud_counter = b_inc; brg_fall = b_half;
        end
        brg_lvl = brg_start || b_wrap || b_inc_lt;
      end else begin
        brg_lvl = brg_start || b_cur_lt;
      end
      if (!n_wr[14][0]) brg_lvl = n_trxc_out_lvl;

      // DPLL: a 5-bit counter on its source clock's rises. An RxD edge is
      // placed by half counts (the clock is High in a count's first half)
      // against the count before this PCLK's rise.
      dclk = n_dp_brg ? brg_lvl : rxc_in;
      d_h  = {n_dp_cnt, ~dclk};
      if (n_dp_on && rxd != n_dp_rx_in) begin
        if (n_dp_search) begin
          n_dp_search = 1'b0; n_dp_cnt = 5'd16; n_dp_seen = 1'b1; n_dp_next = 2'd0; n_dp_clk = dclk;
        end else if (!n_dp_seen && (!n_dp_fm || (d_h >= 6'd25 && d_h <= 6'd38))) begin
          n_dp_seen = 1'b1;
          n_dp_next = (d_h == 6'd31 || d_h == 6'd32) ? 2'd0 : d_h > 6'd32 ? 2'd1 : 2'd2;
        end
      end
      n_dp_rx_in = rxd;
      // Outputs if the count does not move this PCLK.
      d_rx = n_dp_fm ? (n_dp_cnt[3:0] >= 4'd4 && n_dp_cnt[3:0] < 4'd12) : n_dp_cnt[4];
      d_tx = n_dp_fm ? n_dp_cnt[3] : n_dp_cnt[4];
      d_step = n_dp_on && !n_dp_search && dclk && !n_dp_clk;
      if (d_step) begin
        if (n_dp_cnt == 5'd5 && n_dp_adj == 2'd1)      n_dp_adj = 2'd0;
        else if (n_dp_cnt == 5'd4 && n_dp_adj == 2'd2) begin n_dp_cnt = 5'd6; n_dp_adj = 2'd0; end
        else                                           n_dp_cnt = n_dp_cnt + 5'd1;
        if (n_dp_fm && n_dp_cnt == 5'd20) begin
          // End of the FM window, mid 12 to mid 19.
          if (n_dp_seen) n_dp_miss_n = 2'd0;
          else begin n_dp_miss_n = n_dp_miss_n + 2'd1; n_dp_miss1 = 1'b1; end
          n_dp_adj = n_dp_next; n_dp_seen = 1'b0; n_dp_next = 2'd0;
        end else if (n_dp_fm && n_dp_cnt == 5'd2 && n_dp_miss_n == 2'd2) begin
          n_dp_miss2 = 1'b1; n_dp_search = 1'b1; n_dp_cnt = 5'd16; n_dp_miss_n = 2'd0;
        end else if (!n_dp_fm && n_dp_cnt == 5'd0) begin
          n_dp_adj = n_dp_next; n_dp_seen = 1'b0; n_dp_next = 2'd0;
        end
      end
      n_dp_clk = dclk;
      // A moving count takes the outputs worked out from the registers.
      if (d_step) begin d_rx = dp_srx[n_dp_fm]; d_tx = dp_stx[n_dp_fm]; end
      drr = d_rx & ~dp_rxo; drf = ~d_rx & dp_rxo; dtr = d_tx & ~dp_txo; dtf = ~d_tx & dp_txo;
      n_dp_rxo = d_rx; n_dp_txo = d_tx;

      // Transmit clock: a cell starts on tx_edge; tx_mid times the FM
      // centre. From the DPLL a cell starts at count 16 (and 0 in FM).
      case (n_wr[11][4:3])
        2'd0:    begin tx_edge = rtxc_rise; tx_mid = prev_rtxc & ~rxc_in;  end
        2'd1:    begin tx_edge = trxc_rise; tx_mid = prev_trxc & ~trxc_in; end
        2'd2:    begin tx_edge = brg_edge;  tx_mid = brg_fall;             end
        default: begin tx_edge = n_dp_fm ? dtf : dtr; tx_mid = n_dp_fm ? dtr : dtf; end
      endcase

      // TRxC as an output echoes the BRG square wave (High for the first
      // TC+2 counts), the transmit clock, or the DPLL's receive output.
      if (n_wr[11][2]) begin
        case (n_wr[11][1:0])
          2'd3: n_trxc_out_lvl = n_dp_rxo;
          2'd2: n_trxc_out_lvl = brg_lvl;
          2'd1: case (n_wr[11][4:3])
                  2'd0:    n_trxc_out_lvl = rxc_in;
                  2'd1:    ;
                  2'd2:    n_trxc_out_lvl = brg_lvl;
                  default: n_trxc_out_lvl = n_dp_txo;
                endcase
          default: ;
        endcase
      end

      // Auto Enables: /CTS gates the start of each character.
      auto_en = n_wr[3][5];
      tx_en   = n_wr[5][3] && !(auto_en && !cts_now);
      case (n_wr[4][7:6])
        2'd0:    cm = 7'd1;
        2'd1:    cm = 7'd16;
        2'd2:    cm = 7'd32;
        default: cm = 7'd64;
      endcase
      case (n_wr[5][6:5])
        2'd0:    tx_bits = 4'd5;
        2'd1:    tx_bits = 4'd7;
        2'd2:    tx_bits = 4'd6;
        default: tx_bits = 4'd8;
      endcase

      // 1.5 stop bits end on a half bit; x1 has no half bit and sends 1.
      tx_two_stop  = n_wr[4][3:2] == 2'b11 || (n_wr[4][3:2] == 2'b10 && cm != 7'd1);
      tx_half_stop = n_wr[4][3:2] == 2'b10 && cm != 7'd1 && n_tx_stop_bit == 2'd1;

      sd_mode = n_wr[4][5:2] == 4'b1000;
      bs_mode = n_wr[4][3:2] == 2'b00 && n_wr[4][5:4] != 2'b10;
      bs_ext  = n_wr[4][5:2] == 4'b1100;
      sd_preset = n_wr[10][7] ? 16'hFFFF : 16'h0000;

      // Loop Mode: TxD repeats RxD while the transmitter parks a flag at
      // the end of the zero inserter. Taking the loop sends one 0 (the
      // EOP's last 1), then the parked flag; a flag leaving without Go
      // Active On Poll, or a disabled transmitter, hands TxD back once
      // the inserter clears.
      // Leaving SDLC drops the loop.
      if (!sd_mode) begin
        n_lp_on = 1'b0; n_lp_send = 1'b0; n_lp_poll = 1'b0; n_lp_conv = 1'b0; n_lp_drain = 3'd0;
      end
      lp_loop = sd_mode && (n_wr[10][1] || n_lp_on);
      // The CRC's bit times while Tx Enable is clear carry the flag or
      // the sync pattern, repeated over 16 bits.
      if (sd_mode)                    sd_fill = {n_wr[7], n_wr[7]};
      else if (n_wr[4][5:4] == 2'b01) sd_fill = {n_wr[7], n_wr[6]};
      else if (n_wr[10][0])           sd_fill = {n_wr[6][3:0], n_wr[6][5:0], n_wr[6][5:0]};
      else                            sd_fill = {n_wr[6], n_wr[6]};

      // SDLC transmit: at a character boundary load buffered data, else
      // on underrun with the latch reset the CRC (or an abort, WR10 D2),
      // else the idle flag or marks. A 0 follows every five 1s of data
      // or CRC, then five bits of delay to TxD.
      if (tx_edge && sd_mode && (lp_loop && !n_lp_send || n_lp_conv || n_lp_drain == 3'd1)) begin
        n_txd = !n_lp_conv && n_lp_bit;
        if (n_lp_send && !n_lp_conv) begin n_lp_send = 1'b0; n_lp_drain = 3'd0; end
        n_lp_conv = 1'b0;
        n_sd_tx_sr = {13'd0, n_wr[7][7:5]}; n_sd_tx_n = 5'd3; n_sd_tx_kind = 2'd0; n_sd_tx_ones = 3'd0;
        n_sd_tx_pipe = {3'd0, n_wr[7][0], n_wr[7][1], n_wr[7][2], n_wr[7][3], n_wr[7][4]};
      end else if (tx_edge && sd_mode) begin
        if (n_lp_drain != 3'd0) n_lp_drain = n_lp_drain - 3'd1;
        else if (n_sd_tx_n == 5'd0) begin
          if (lp_loop && (!tx_en || n_sd_tx_kind == 2'd0 && !n_wr[10][4])) n_lp_drain = 3'd5;
          else if (!tx_en) ;
          else if (!n_tx_buf_empty) begin
            n_sd_tx_sr = {8'h00, n_tx_buf}; n_sd_tx_n = {1'b0, tx_bits}; n_sd_tx_kind = 2'd1;
            n_tx_buf_empty = 1'b1; n_tx_ip = 1'b1;
          end else if (!n_tx_underrun_eom) begin
            // No CRC without Tx CRC Enable at the underrun (WR5 D0).
            // Loop mode ignores WR10 D3:D2.
            if (n_wr[10][2] && !lp_loop || !n_wr[5][0]) begin
              n_sd_tx_sr = {8'h00, (n_wr[10][3:2] != 2'd0 && !lp_loop) ? 8'hFF : n_wr[7]};
              n_sd_tx_n = 5'd8; n_sd_tx_kind = 2'd0;
            end else begin
              n_sd_tx_sr = ~n_sd_tx_crc; n_sd_tx_n = 5'd16; n_sd_tx_kind = 2'd2;
            end
            n_tx_underrun_eom = 1'b1;
            if (n_wr[15][6]) `SCC_EXT_RAISE
          end else begin
            n_sd_tx_sr = {8'h00, n_wr[10][3] && !lp_loop ? 8'hFF : n_wr[7]}; n_sd_tx_n = 5'd8; n_sd_tx_kind = 2'd0;
          end
        end
        if (n_sd_tx_n != 5'd0) begin
          if (n_sd_tx_ones == 3'd5) begin
            sd_out = 1'b0; n_sd_tx_ones = 3'd0;
          end else begin
            sd_cut = n_sd_tx_kind == 2'd2 && !n_wr[5][3];
            sd_slot = 4'(5'd16 - n_sd_tx_n);
            sd_out = sd_cut ? sd_fill[sd_slot] : n_sd_tx_sr[0];
            n_sd_tx_sr = {1'b0, n_sd_tx_sr[15:1]};
            n_sd_tx_n = n_sd_tx_n - 5'd1;
            if (n_sd_tx_kind == 2'd0 || sd_cut || !sd_out) n_sd_tx_ones = 3'd0;
            else                                 n_sd_tx_ones = n_sd_tx_ones + 3'd1;
            if (n_sd_tx_kind == 2'd1 && n_wr[5][0])
              n_sd_tx_crc = crc_step(n_sd_tx_crc, sd_out, n_wr[5][2]);
          end
        end
        n_sd_tx_pipe = {n_sd_tx_pipe[6:0], sd_out};
        n_txd = n_sd_tx_pipe[5];
      end

      // Byte sync transmit: buffered data (and parity), else on underrun
      // with the latch reset the CRC, else the sync pattern.
      if (tx_edge && bs_mode) begin
        if (n_sd_tx_n == 5'd0) begin
          if (!tx_en) ;
          else if (!n_tx_buf_empty) begin
            n_sd_tx_sr = {8'h00, n_tx_buf & (8'hFF >> (4'd8 - tx_bits))}; n_sd_tx_n = {1'b0, tx_bits}; n_sd_tx_kind = 2'd1;
            if (n_wr[4][0]) begin
              n_sd_tx_sr[tx_bits] = ^(n_tx_buf & (8'hFF >> (4'd8 - tx_bits))) ^ ~n_wr[4][1];
              n_sd_tx_n = n_sd_tx_n + 5'd1;
            end
            n_sd_tx_crc_on = n_wr[5][0];
            n_tx_buf_empty = 1'b1; n_tx_ip = 1'b1;
          end else if (!n_tx_underrun_eom && n_wr[5][0]) begin
            n_sd_tx_sr = n_sd_tx_crc; n_sd_tx_n = 5'd16; n_sd_tx_kind = 2'd2;
            n_tx_underrun_eom = 1'b1;
            if (n_wr[15][6]) `SCC_EXT_RAISE
          end else begin
            // Sync idle; bisync keeps its 16-bit sync with WR10 D0.
            if (!n_tx_underrun_eom) begin
              n_tx_underrun_eom = 1'b1;
              if (n_wr[15][6]) `SCC_EXT_RAISE
            end
            if (n_wr[4][5:4] == 2'b01) begin
              n_sd_tx_sr = {n_wr[7], n_wr[6]}; n_sd_tx_n = 5'd16;
            end else if (n_wr[10][0]) begin
              n_sd_tx_sr = {10'd0, n_wr[6][5:0]}; n_sd_tx_n = 5'd6;
            end else begin
              n_sd_tx_sr = {8'h00, n_wr[6]}; n_sd_tx_n = 5'd8;
            end
            n_sd_tx_kind = 2'd0;
          end
        end
        if (n_sd_tx_n != 5'd0) begin
          sd_slot = 4'(5'd16 - n_sd_tx_n);
          sd_out = n_sd_tx_kind == 2'd2 && !n_wr[5][3] ? sd_fill[sd_slot] : n_sd_tx_sr[0];
          n_sd_tx_sr = {1'b0, n_sd_tx_sr[15:1]};
          n_sd_tx_n = n_sd_tx_n - 5'd1;
          if (n_sd_tx_kind == 2'd1 && n_sd_tx_crc_on)
            n_sd_tx_crc = crc_step(n_sd_tx_crc, sd_out, n_wr[5][2]);
        end
        n_txd = sd_out;
      end

      if (tx_edge && !sd_mode && !bs_mode) begin
        if (!tx_en && (n_tx_state == 3'd0 || n_tx_state == 3'd5)) begin
          if (n_tx_state == 3'd0) n_tx_all_sent = n_tx_buf_empty;
        end else begin
          case (n_tx_state)
            3'd0: n_tx_all_sent = n_tx_buf_empty;
            3'd5: begin
              n_tx_bit_count = 4'd0; n_tx_sub_count = 7'd0; n_tx_state = 3'd1;
            end
            3'd1: begin
              n_tx_sub_count = n_tx_sub_count + 7'd1;
              if (n_tx_sub_count >= cm) begin
                n_tx_state = 3'd2; n_tx_sub_count = 7'd0; n_tx_bit_count = 4'd0;
              end
            end
            3'd2: begin
              n_tx_sub_count = n_tx_sub_count + 7'd1;
              if (n_tx_sub_count >= cm) begin
                n_tx_sub_count = 7'd0;
                n_tx_bit_count = n_tx_bit_count + 4'd1;
                if (n_tx_bit_count == tx_bits) begin
                  n_tx_state = n_wr[4][0] ? 3'd3 : 3'd4;
                  if (!n_wr[4][0]) n_tx_stop_bit = 2'd0;
                end
              end
            end
            3'd3: begin
              n_tx_sub_count = n_tx_sub_count + 7'd1;
              if (n_tx_sub_count >= cm) begin
                n_tx_sub_count = 7'd0; n_tx_state = 3'd4; n_tx_stop_bit = 2'd0;
              end
            end
            3'd4: begin
              n_tx_sub_count = n_tx_sub_count + 7'd1;
              if (n_tx_sub_count >= (tx_half_stop ? {1'b0, cm[6:1]} : cm)) begin
                n_tx_sub_count = 7'd0;
                n_tx_stop_bit = n_tx_stop_bit + 2'd1;
                if (n_tx_stop_bit >= (tx_two_stop ? 2'd2 : 2'd1)) begin
                  if (!n_tx_buf_empty && tx_en) begin
                    // Back to back: the next start bit begins on this edge.
                    n_tx_shift = n_tx_buf; n_tx_buf_empty = 1'b1; n_tx_all_sent = 1'b0;
                    n_tx_ip = 1'b1; n_tx_bit_count = 4'd0; n_tx_sub_count = 7'd0;
                    n_tx_state = 3'd1;
                  end else if (!n_tx_buf_empty) begin
                    n_tx_state = 3'd0;
                  end else begin
                    n_tx_state = 3'd0;
                    n_tx_all_sent = 1'b1;
                    // Ran dry: Tx Underrun/EOM sets, an ext/status source.
                    if (!n_tx_underrun_eom) begin
                      n_tx_underrun_eom = 1'b1;
                      if (n_wr[15][6]) begin
                        n_ext_ip = 1'b1;
                        if (!n_ext_latch_closed) begin
                          n_ext_latch_closed = 1'b1;
                          n_dcd_latch = n_dcd_sync; n_cts_latch = n_cts_sync;
                          n_break_latch = brk_now; n_underrun_latch = 1'b1; n_hunt_latch = `SCC_HUNT;
                        end
                      end
                    end
                  end
                end
              end
            end
            default: ;
          endcase
        end

        tx_mask = 8'hFF >> (4'd8 - tx_bits);
        tx_par  = ^(n_tx_shift & tx_mask) ^ ~n_wr[4][1];
        case (n_tx_state)
          3'd1:    n_txd = 1'b0;
          3'd2:    n_txd = n_tx_shift[n_tx_bit_count[2:0]];
          3'd3:    n_txd = tx_par;
          default: n_txd = 1'b1;
        endcase
      end

      // The TBR moves to the TSR on PCLK, not on the transmit clock.
      if (!sd_mode && !bs_mode && n_tx_state == 3'd0 && !n_tx_buf_empty && tx_en) begin
        n_tx_shift = n_tx_buf; n_tx_buf_empty = 1'b1; n_tx_all_sent = 1'b0;
        n_tx_ip = 1'b1; n_tx_bit_count = 4'd0; n_tx_sub_count = 7'd0;
        n_tx_state = 3'd5;
      end

      if (n_rts_hold && n_tx_all_sent && n_tx_buf_empty) n_rts_hold = 1'b0;

      // Receive clock: RTxC, TRxC, or the BRG.
      // From the DPLL the receiver samples on its output's fall.
      case (n_wr[11][6:5])
        2'd0:    begin rx_edge = rtxc_rise; rx_half = prev_rtxc & ~rxc_in;  end
        2'd1:    begin rx_edge = trxc_rise; rx_half = prev_trxc & ~trxc_in; end
        2'd2:    begin rx_edge = brg_edge;  rx_half = brg_fall;             end
        default: begin rx_edge = drf;       rx_half = drr;                  end
      endcase

      // Line coding in any x1 mode: NRZ, NRZI, FM1, FM0 (WR10 D6:D5). FM
      // takes its first-half sample on rx_half and decodes on rx_edge.
      enc = n_wr[10][6:5];
      // The bit a receive edge would decode: the first-half sample never
      // lands on the same PCLK as a receive edge.
      case (enc)
        2'd0:    rx_dec = rxd;
        2'd1:    rx_dec = rxd == rx_prev;
        default: rx_dec = (rxd != rx_prev) == (enc == 2'd2);
      endcase
      // The repeated line bypasses the encoder.
      lp_rep = sd_mode && (n_wr[10][1] || n_lp_on) && !n_lp_send;
      if (sd_mode || bs_mode || cm == 7'd1) begin
        if (tx_edge && lp_rep) n_tx_line = n_txd;
        else if (tx_edge) begin
          case (enc)
            2'd0:    n_tx_line = n_txd;
            2'd1:    n_tx_line = n_tx_line == n_txd;
            default: begin n_tx_line = ~n_tx_line; n_tx_raw = n_txd; end
          endcase
        end else if (tx_mid && !lp_rep && enc[1] && n_tx_raw == (enc == 2'd2)) begin
          n_tx_line = ~n_tx_line;
        end
        if (rx_half && enc[1]) n_rx_prev = rxd;
        if (rx_edge) begin
          n_rx_bit = rx_dec;
          if (enc == 2'd1) n_rx_prev = rxd;
        end
      end
      rxa = (enc != 2'd0 && cm == 7'd1) ? rx_dec : rxd;
      case (n_wr[3][7:6])
        2'd0:    rx_bits = 4'd5;
        2'd1:    rx_bits = 4'd7;
        2'd2:    rx_bits = 4'd6;
        default: rx_bits = 4'd8;
      endcase
      rx_mid = (cm + 7'd1) >> 1;
      // Bits above the character and its parity bit read as 1s.
      rx_fill = 8'hFF << (rx_bits + {3'd0, n_wr[4][0]});

      // SDLC receive: flags and aborts on the line bits; data bits after
      // zero deletion feed the CRC checker 8 bits late and the character
      // assembler 10 bits late.
      if (rx_edge && sd_mode) begin
        n_lp_bit = rxd;
        if (!n_wr[3][0] || (auto_en && !dcd_now)) begin
          if (!n_sd_hunt) begin
            n_sd_hunt = 1'b1;
            if (n_wr[15][4]) `SCC_EXT_RAISE
          end
          n_sd_in_frame = 1'b0; n_sd_rx_ones = 4'd0; n_sd_rx_raw = 8'h00;
        end else begin
          sd_b = rx_dec;
          n_sd_rx_raw = {sd_b, n_sd_rx_raw[7:1]};
          sd_del = !sd_b && n_sd_rx_ones == 4'd5;
          if (!sd_b)                       n_sd_rx_ones = 4'd0;
          else if (n_sd_rx_ones < 4'd8)    n_sd_rx_ones = n_sd_rx_ones + 4'd1;
          if (!sd_b && n_rx_break) begin
            n_rx_break = 1'b0;
            if (n_wr[15][7]) `SCC_EXT_RAISE
          end
          if (n_sd_rx_ones == 4'd7) begin
            n_rx_break = 1'b1;
            if (n_wr[15][7]) `SCC_EXT_RAISE
            if (!n_sd_hunt) begin
              n_sd_hunt = 1'b1;
              if (n_wr[15][4]) `SCC_EXT_RAISE
            end
            n_sd_in_frame = 1'b0;
          end
          if (n_sd_hunt) n_sd_rx_crc = sd_preset;
          // Loop: Go Active On Poll and an EOP (the seventh 1) go on loop;
          // on loop a flag then an EOP with it set take the loop. With Loop
          // Mode cleared the channel leaves at an EOP, or at once in one.
          if (n_wr[10][1] || n_lp_on) begin
            if (n_lp_send) ;
            else if (!n_wr[10][1] && n_sd_rx_ones >= 4'd7) begin
              n_lp_on = 1'b0; n_lp_poll = 1'b0;
            end else if (n_sd_rx_ones == 4'd7 && !n_lp_on) n_lp_on = n_wr[10][4];
            else if (n_sd_rx_ones == 4'd7) begin
              n_lp_send = n_lp_poll && n_wr[10][4]; n_lp_conv = n_lp_send; n_lp_poll = 1'b0;
            end else if (n_lp_on && n_sd_rx_raw == n_wr[7]) n_lp_poll = 1'b1;
          end
          if (n_sd_in_frame && !sd_del) begin
            n_sd_rx_hist = {sd_b, n_sd_rx_hist[31:1]};
            if (n_sd_rx_nb < 4'd11) n_sd_rx_nb = n_sd_rx_nb + 4'd1;
            if (n_sd_rx_nb > 4'd8) n_sd_rx_crc = crc_step(n_sd_rx_crc, n_sd_rx_hist[23], n_wr[5][2]);
            if (n_sd_rx_nb > 4'd10) begin
              n_sd_rx_cnt = n_sd_rx_cnt + 4'd1;
              if (n_sd_rx_cnt == rx_bits) begin
                sd_done = 1'b1; sd_char = sd_snap(n_sd_rx_hist[24:14], rx_bits); n_sd_rx_cnt = 4'd0;
              end
            end
          end
          sd_err = n_sd_rx_crc != 16'hF0B8 ? 8'h04 : 8'h00;
          if (n_sd_rx_raw == n_wr[7]) begin
            if (n_sd_hunt) begin
              n_sd_hunt = 1'b0;
              if (n_wr[15][4]) `SCC_EXT_RAISE
            end else if (n_sd_in_frame && n_sd_rx_nb > 4'd10 && (n_sd_rx_chars || !n_wr[3][2])) begin
              // End of Frame; RR1 D3..D1 hold the residue count bit-reversed.
              if (!sd_done) sd_char = sd_snap(n_sd_rx_hist[24:14], rx_bits);
              n_sd_residue = {4'd0, n_sd_rx_cnt[0], n_sd_rx_cnt[1], n_sd_rx_cnt[2], 1'b0};
              rx_push = 1'b1; rx_data = sd_char; rx_err = sd_err | 8'h08;
            end
            n_sd_in_frame = 1'b1; n_sd_rx_nb = 4'd0; n_sd_rx_cnt = 4'd0;
            n_sd_rx_chars = 1'b0; n_sd_rx_crc = sd_preset;
          end else if (sd_done) begin
            // Address search: WR6 (high nibble with WR3 D1) or all 1s.
            if (!n_sd_rx_chars && n_wr[3][2] && sd_char != 8'hFF &&
                ((sd_char ^ n_wr[6]) & (n_wr[3][1] ? 8'hF0 : 8'hFF)) != 8'h00)
              n_sd_in_frame = 1'b0;
            else begin
              n_sd_rx_chars = 1'b1;
              rx_push = 1'b1; rx_data = sd_char; rx_err = sd_err;
            end
          end
        end
      end

      // Byte sync receive: hunt for the sync on the line bits; a character
      // loads once the 8 bits from its first are in (more with parity on 8
      // bits). The CRC checker runs 16 bits behind the line, its enable
      // taken at each load for the character before.
      if (rx_edge && bs_mode) begin
        if (!n_wr[3][0] || (auto_en && !dcd_now)) begin
          if (!n_sd_hunt) begin
            n_sd_hunt = 1'b1;
            if (n_wr[15][4] && !bs_ext) `SCC_EXT_RAISE
          end
          n_sd_sync_out = 1'b0;
        end else begin
          n_sd_rx_hist = {rx_dec, n_sd_rx_hist[31:1]};
          n_sd_sync_out = !bs_ext && sync_match(n_sd_rx_hist[31:16], n_wr[7], n_wr[6], n_wr[4][4], n_wr[10][0]);
          if (n_sd_hunt) begin
            n_sd_rx_crc = sd_preset; n_sd_rx_cnt = 4'd0; n_sd_rx_pend = 2'd0; n_sd_strip_prev = 1'b1;
            if (bs_ext && !n_sync_pin) begin
              // The bit before /SYNC fell was the first of the character.
              n_sd_rx_cnt = 4'd2; n_sd_hunt = 1'b0;
            end else if (n_sd_sync_out) begin
              n_sd_hunt = 1'b0;
              if (n_wr[15][4]) `SCC_EXT_RAISE
            end
          end else begin
            if (n_sd_crc_on) n_sd_rx_crc = crc_step(n_sd_rx_crc, n_sd_rx_hist[15], n_wr[5][2]);
            bs_n = rx_bits + {3'd0, n_wr[4][0]};
            bs_w = bs_n > 4'd8 ? bs_n : 4'd8;
            if (n_sd_rx_pend != 2'd0) begin
              n_sd_rx_pend = n_sd_rx_pend - 2'd1;
              bs_load = n_sd_rx_pend == 2'd0;
            end
            n_sd_rx_cnt = n_sd_rx_cnt + 4'd1;
            if (n_sd_rx_cnt >= bs_n) begin
              n_sd_rx_cnt = 4'd0;
              n_sd_rx_pend = 2'(bs_w - bs_n);
              if (n_sd_rx_pend == 2'd0) bs_load = 1'b1;
            end
            if (bs_load) begin
              bs_win = bs_w == 4'd9 ? n_sd_rx_hist[31:23] : {1'b0, n_sd_rx_hist[31:24]};
              bs_err = n_sd_rx_crc != 16'h0000 ? 8'h04 : 8'h00;
              // Parity over the data bits and the bit after them.
              if (n_wr[4][0] && (^(bs_win & ((9'h002 << (bs_n - 4'd1)) - 9'h001)) ^ n_wr[4][1]) == 1'b0)
                bs_err = bs_err | 8'h01;
              n_sd_crc_on = n_wr[3][3] && !n_sd_strip_prev;
              n_sd_strip_prev = n_wr[3][1] && bs_win[7:0] == n_wr[6] &&
                                !(n_wr[4][5:4] == 2'b01 && n_wr[10][0]);
              if (!n_sd_strip_prev) begin
                rx_push = 1'b1; rx_data = bs_win[7:0]; rx_err = bs_err;
              end
            end
          end
        end
      end

      if (rx_edge) begin
        if (!sd_mode && !bs_mode) begin
        // RxD back High ends a break, an ext/status source.
        if (n_rx_break && rxa) begin
          n_rx_break = 1'b0;
          if (n_wr[15][7]) begin
            n_ext_ip = 1'b1;
            if (!n_ext_latch_closed) begin
              n_ext_latch_closed = 1'b1;
              n_dcd_latch = n_dcd_sync; n_cts_latch = n_cts_sync;
              n_break_latch = 1'b0; n_underrun_latch = n_tx_underrun_eom; n_hunt_latch = `SCC_HUNT;
            end
          end
          // One null is left at the end of a break; odd parity flags it.
          rx_push = 1'b1; rx_data = 8'h00;
          rx_err = {7'd0, n_wr[4][0] & ~n_wr[4][1]};
        end

        // Disabled (or /DCD High under Auto Enables): held idle.
        if (!n_wr[3][0] || (auto_en && !dcd_now)) begin
          n_rx_state = 3'd0; n_rx_sub_count = 7'd0; n_rx_bit_count = 4'd0;
          n_rx_shift = 8'h00; n_rx_shift_err = 8'h00;
        end else begin
          case (n_rx_state)
            // Start bit on RxD Low; x1 samples bit 0 on the next edge.
            // A break holds the receiver until RxD returns High.
            3'd0: if (!rxa && !n_rx_break) begin
              n_rx_shift = 8'h00; n_rx_bit_count = 4'd0;
              n_rx_state     = cm == 7'd1 ? 3'd2 : 3'd1;
              n_rx_sub_count = cm == 7'd1 ? 7'd0 : 7'd1;
            end
            // A start bit gone High by mid-bit was a glitch.
            3'd1: begin
              n_rx_sub_count = n_rx_sub_count + 7'd1;
              if (n_rx_sub_count == rx_mid && rxa) begin
                n_rx_state = 3'd0; n_rx_sub_count = 7'd0;
              end else if (n_rx_sub_count >= cm) begin
                n_rx_state = 3'd2; n_rx_sub_count = 7'd0;
              end
            end
            3'd2: begin
              n_rx_sub_count = n_rx_sub_count + 7'd1;
              if (n_rx_sub_count == rx_mid && rxa)
                n_rx_shift[n_rx_bit_count[2:0]] = 1'b1;
              if (n_rx_sub_count >= cm) begin
                n_rx_sub_count = 7'd0;
                n_rx_bit_count = n_rx_bit_count + 4'd1;
                if (n_rx_bit_count == rx_bits) begin
                  n_rx_state = n_wr[4][0] ? 3'd3 : 3'd4;
                  if (!n_wr[4][0]) n_rx_stop_bit = 2'd0;
                end
              end
            end
            3'd3: begin
              n_rx_sub_count = n_rx_sub_count + 7'd1;
              rx_par = ^n_rx_shift ^ ~n_wr[4][1];
              if (n_rx_sub_count == rx_mid && rxa != rx_par)
                n_rx_shift_err = n_rx_shift_err | 8'h01;
              // The parity bit is loaded above the data when it fits.
              if (n_rx_sub_count == rx_mid && rxa && rx_bits != 4'd8)
                n_rx_shift[rx_bits[2:0]] = 1'b1;
              if (n_rx_sub_count >= cm) begin
                n_rx_sub_count = 7'd0; n_rx_state = 3'd4; n_rx_stop_bit = 2'd0;
              end
            end
            3'd4: begin
              n_rx_sub_count = n_rx_sub_count + 7'd1;
              if (n_rx_sub_count == rx_mid && !rxa)
                n_rx_shift_err = n_rx_shift_err | 8'h04;
              if (n_rx_sub_count >= cm) begin
                n_rx_sub_count = 7'd0;
                n_rx_stop_bit = n_rx_stop_bit + 2'd1;
                // One stop bit is checked whatever WR4 D3:D2 select.
                // The break character itself is not loaded.
                if (n_rx_shift_err[2] && n_rx_shift == 8'h00 && !n_rx_break) begin
                  n_rx_break = 1'b1;
                  if (n_wr[15][7]) begin
                    n_ext_ip = 1'b1;
                    if (!n_ext_latch_closed) begin
                      n_ext_latch_closed = 1'b1;
                      n_dcd_latch = n_dcd_sync; n_cts_latch = n_cts_sync;
                      n_break_latch = 1'b1; n_underrun_latch = n_tx_underrun_eom; n_hunt_latch = `SCC_HUNT;
                    end
                  end
                end else begin
                  rx_push = 1'b1; rx_data = n_rx_shift; rx_err = n_rx_shift_err;
                end
                n_rx_shift_err = 8'h00;
                n_rx_state = 3'd0; n_rx_sub_count = 7'd0;
              end
            end
            default: ;
          endcase
        end

        end

        // Into the FIFO; a full FIFO loses its newest entry to this
        // character, tagged with overrun.
        if (rx_push) begin
          if (!sd_mode) rx_data = rx_data | rx_fill;
          if (n_rx_fifo_len == 2'd3) begin
            n_rx_fifo_data[2] = rx_data;
            n_rx_fifo_err[2]  = rx_err | 8'h02;
          end else begin
            n_rx_fifo_data[n_rx_fifo_len] = rx_data;
            n_rx_fifo_err[n_rx_fifo_len]  = rx_err;
            n_rx_fifo_len = n_rx_fifo_len + 2'd1;
          end
          n_rx_err_sticky = n_rx_err_sticky | (n_rx_fifo_err[0] & 8'h03);
          if (n_rx_int_next_char) begin
            n_rx_int_forced = 1'b1; n_rx_int_next_char = 1'b0;
          end
        end
      end

      // A latch closed from here on holds this PCLK's DCD and CTS.
      if (!ext_mid && n_ext_latch_closed) begin
        n_dcd_latch = dcd_now; n_cts_latch = cts_now;
      end else begin
        n_dcd_latch = dcd_mid; n_cts_latch = cts_mid;
      end
    end
  end

  // BRG compares on the registered count and time constant.
  always_comb begin
    b_per    = {brg_tc, 1'b0} + 18'd4;
    b_inc    = baud_counter + 18'd1;
    b_wrap   = b_inc >= b_per;
    b_half   = b_inc == {1'b0, b_per[17:1]};
    b_inc_lt = b_inc < {1'b0, b_per[17:1]};
    b_cur_lt = baud_counter < {1'b0, b_per[17:1]};
  end

  // The DPLL's outputs after its next count, straight from the
  // registers: a counting PCLK never also has a command or a search exit.
  always_comb begin
    if (dp_cnt == 5'd5 && dp_adj == 2'd1)      s_cnt = 5'd5;
    else if (dp_cnt == 5'd4 && dp_adj == 2'd2) s_cnt = 5'd6;
    else                                       s_cnt = dp_cnt + 5'd1;
    dp_srx[0] = s_cnt[4]; dp_stx[0] = s_cnt[4];
    // FM's second miss enters search at 16, where both outputs are Low.
    if (s_cnt == 5'd2 && dp_miss_n == 2'd2) begin
      dp_srx[1] = 1'b0; dp_stx[1] = 1'b0;
    end else begin
      dp_srx[1] = s_cnt[3:0] >= 4'd4 && s_cnt[3:0] < 4'd12; dp_stx[1] = s_cnt[3];
    end
  end

  always_ff @(posedge clk) begin
    for (int i = 0; i < 16; i++) wr[i] <= n_wr[i];
    tx_buf <= n_tx_buf; tx_shift <= n_tx_shift;
    tx_buf_empty <= n_tx_buf_empty; tx_all_sent <= n_tx_all_sent;
    tx_underrun_eom <= n_tx_underrun_eom; tx_ip <= n_tx_ip; txd_q <= n_txd;
    tx_state <= n_tx_state; tx_bit_count <= n_tx_bit_count;
    tx_sub_count <= n_tx_sub_count; tx_stop_bit <= n_tx_stop_bit;
    baud_counter <= n_baud_counter; brg_tc <= n_brg_tc;
    ext_ip <= n_ext_ip; ext_latch_closed <= n_ext_latch_closed;
    dcd_latch <= n_dcd_latch; cts_latch <= n_cts_latch;
    break_latch <= n_break_latch; underrun_latch <= n_underrun_latch;
    dcd_sync1 <= n_dcd_sync;
    cts_sync1 <= n_cts_sync;
    trxc_out_lvl <= n_trxc_out_lvl; rts_hold <= n_rts_hold;

    for (int i = 0; i < 3; i++) begin
      rx_fifo_data[i] <= n_rx_fifo_data[i]; rx_fifo_err[i] <= n_rx_fifo_err[i];
    end
    rx_fifo_len <= n_rx_fifo_len; rx_err_sticky <= n_rx_err_sticky;
    rx_shift_err <= n_rx_shift_err; rx_shift <= n_rx_shift; rx_state <= n_rx_state;
    rx_bit_count <= n_rx_bit_count; rx_sub_count <= n_rx_sub_count;
    rx_stop_bit <= n_rx_stop_bit; rx_break <= n_rx_break;
    rx_int_next_char <= n_rx_int_next_char; rx_int_forced <= n_rx_int_forced;
    rx_lock <= n_rx_lock;
    sd_tx_sr <= n_sd_tx_sr; sd_tx_n <= n_sd_tx_n; sd_tx_kind <= n_sd_tx_kind;
    sd_tx_ones <= n_sd_tx_ones; sd_tx_crc <= n_sd_tx_crc; sd_tx_pipe <= n_sd_tx_pipe;
    sd_hunt <= n_sd_hunt; sd_in_frame <= n_sd_in_frame; sd_rx_chars <= n_sd_rx_chars;
    hunt_latch <= n_hunt_latch; sd_rx_raw <= n_sd_rx_raw; sd_rx_ones <= n_sd_rx_ones;
    sd_rx_nb <= n_sd_rx_nb; sd_rx_cnt <= n_sd_rx_cnt; sd_rx_hist <= n_sd_rx_hist;
    sd_rx_crc <= n_sd_rx_crc; sd_residue <= n_sd_residue;
    sd_tx_crc_on <= n_sd_tx_crc_on; sd_rx_pend <= n_sd_rx_pend; sd_crc_on <= n_sd_crc_on;
    sd_strip_prev <= n_sd_strip_prev; sd_sync_out <= n_sd_sync_out; sync_pin <= n_sync_pin;
    lp_on <= n_lp_on; lp_send <= n_lp_send; lp_poll <= n_lp_poll; lp_bit <= n_lp_bit;
    lp_conv <= n_lp_conv; lp_drain <= n_lp_drain;
    dp_on <= n_dp_on; dp_search <= n_dp_search; dp_brg <= n_dp_brg; dp_fm <= n_dp_fm;
    dp_seen <= n_dp_seen; dp_miss1 <= n_dp_miss1; dp_miss2 <= n_dp_miss2; dp_cnt <= n_dp_cnt;
    dp_adj <= n_dp_adj; dp_next <= n_dp_next; dp_miss_n <= n_dp_miss_n; dp_clk <= n_dp_clk;
    dp_rx_in <= n_dp_rx_in; dp_rxo <= n_dp_rxo; dp_txo <= n_dp_txo; tx_line <= n_tx_line;
    tx_raw <= n_tx_raw; rx_prev <= n_rx_prev; rx_bit <= n_rx_bit;

    if (reset_ch) begin
      pending_wr0 <= 1'b0; pending_wr0_cmd <= 3'd0;
      rxd_q <= 1'b1;
    end

    if (wr_en && wr_reg == 4'd0 && wr_data[5:3] >= 3'd2) pending_wr0_cmd <= wr_data[5:3];

    // Pins sampled at every PCLK rise.
    if (pclk_rise) begin
      rxd_q     <= rxd;
      dcd_live  <= dcd_now;
      cts_live  <= cts_now;
      prev_rtxc <= rxc_in;
      prev_trxc <= trxc_in;
    end
  end

  // NRZI and FM drive the coded line in any x1 mode; Send Break holds TxD Low.
  // Loop Mode off loop passes RxD straight through.
  assign txd = ((sdlc && wr[10][1] && !lp_on) ? rxd :
                (wr[10][6:5] != 2'd0 && (wr[4][3:2] == 2'b00 || wr[4][7:6] == 2'b00)) ? tx_line : txd_q)
               & ~wr[5][4];
  assign trxc_out_level = trxc_out_lvl;
  assign wr9            = wr[9];
  assign wr5            = wr[5];
  assign wr11           = wr[11];
  assign rts_hold_o     = rts_hold;

  // ---- lint waivers: unused register bits; rxd_q is the RxD pin as the
  // bench reads it, the receiver samples rxd itself ----
  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{wr[2], wr[8], sd_residue[7:4], sd_residue[0], rx_vis_err[7:4],
                       pending_wr0, pending_wr0_cmd, rxd_q};
  // verilator lint_on UNUSEDSIGNAL

endmodule
