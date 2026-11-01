// scc_access.h -- THE HARNESS CONTRACT between tb_scc.cpp and the SCC RTL.
//
// tb_scc replays Go-recorded vectors that poke register state between
// records (the Go test wrote registers through the functional facade --
// ioWrite/rxPush/... -- instead of the pins; the recorder emits the
// resulting register-inventory diff as `P <field> <hex>`) and always
// compares the final register inventory (`F <field> <hex>`). Field names
// are the Go Snapshot field names (sim/scc/vecfields.go): chip-level
// bare, per-channel prefixed A_ / B_, arrays suffixed with the index.
//
// The harness reaches into the Verilated model through the table below
// (built with --public-flat-rw, so every signal is visible as
// rootp->z8030_scc__DOT__<hier>__DOT__<name>). If you rename or move any
// register, update THIS FILE in the same change -- nothing else in the
// harness knows the hierarchy. A field missing here makes vectors that
// poke it SKIP (and F records for it are reported as unknown).
//
//   z8030_scc: int_vector int_pending int_latch shift_right ius_mask
//   u_cha / u_chb: wr[16] tx_buf tx_buf_empty tx_all_sent rx_fifo_data[3]
//     rx_fifo_err[3] rx_fifo_len rx_err_sticky rx_shift_err tx_underrun_eom
//     baud_counter brg_tc rxd_q rx_state rx_shift rx_bit_count rx_sub_count
//     rx_stop_bit rx_break txd_q tx_state tx_shift tx_bit_count tx_sub_count
//     tx_stop_bit tx_ip rx_int_next_char rx_int_forced rx_lock ext_ip dcd_latch
//     cts_latch dcd_sync1 cts_sync1 ext_latch_closed
//     break_latch underrun_latch pending_wr0 pending_wr0_cmd prev_rtxc
//     prev_trxc trxc_out_lvl rts_hold sd_tx_sr sd_tx_n sd_tx_kind sd_tx_ones
//     sd_tx_crc sd_tx_pipe sd_hunt sd_rx_raw sd_rx_ones sd_in_frame sd_rx_hist
//     sd_rx_nb sd_rx_cnt sd_rx_chars sd_rx_crc sd_residue sd_tx_crc_on
//     sd_rx_pend sd_crc_on sd_strip_prev sd_sync_out lp_on lp_send lp_poll lp_bit
//     lp_conv lp_drain hunt_latch sync_pin
//     dp_on dp_search dp_brg dp_fm dp_cnt dp_adj dp_seen dp_next dp_miss_n
//     dp_miss1 dp_miss2 dp_clk dp_rx_in dp_rxo dp_txo tx_line tx_raw rx_prev rx_bit

#pragma once
#include <cstdint>
#include <string>
#include "Vz8030_scc.h"
#include "Vz8030_scc___024root.h"

struct SccAccess {
    Vz8030_scc* top;
    explicit SccAccess(Vz8030_scc* t) : top(t) {}

    // Generic accessor: returns false when the field name is unknown.
    // set==true writes v into the register, else reads it into v.
    bool access(const std::string& name, uint64_t& v, bool set) {
        auto* r = top->rootp;
#define FIELD(nm, ref)  if (name == nm) { if (set) (ref) = (decltype(ref))v; else v = (uint64_t)(ref); return true; }
        // -- chip level --
        FIELD("IntVector",  r->z8030_scc__DOT__int_vector)
        FIELD("IntPending", r->z8030_scc__DOT__int_pending)
        FIELD("IntLatch",   r->z8030_scc__DOT__int_latch)
        FIELD("ShiftRight", r->z8030_scc__DOT__shift_right)
        FIELD("IUSMask",    r->z8030_scc__DOT__ius_mask)
        // -- channels --
#define CHANNEL(P, H) \
        for (int i = 0; i < 16; i++) FIELD(std::string(P "WR") + std::to_string(i), r->H##wr[i]) \
        for (int i = 0; i < 3; i++) FIELD(std::string(P "RxFIFOData") + std::to_string(i), r->H##rx_fifo_data[i]) \
        for (int i = 0; i < 3; i++) FIELD(std::string(P "RxFIFOErr") + std::to_string(i), r->H##rx_fifo_err[i]) \
        FIELD(P "TxBuf",          r->H##tx_buf) \
        FIELD(P "TxBufEmpty",     r->H##tx_buf_empty) \
        FIELD(P "TxAllSent",      r->H##tx_all_sent) \
        FIELD(P "RxFIFOLen",      r->H##rx_fifo_len) \
        FIELD(P "RxErrSticky",    r->H##rx_err_sticky) \
        FIELD(P "RxShiftErr",     r->H##rx_shift_err) \
        FIELD(P "TxUnderrunEOM",  r->H##tx_underrun_eom) \
        FIELD(P "BaudCounter",    r->H##baud_counter) \
        FIELD(P "BrgTC",          r->H##brg_tc) \
        FIELD(P "RxD",            r->H##rxd_q) \
        FIELD(P "RxState",        r->H##rx_state) \
        FIELD(P "RxShift",        r->H##rx_shift) \
        FIELD(P "RxBitCount",     r->H##rx_bit_count) \
        FIELD(P "RxSubCount",     r->H##rx_sub_count) \
        FIELD(P "RxStopBit",      r->H##rx_stop_bit) \
        FIELD(P "RxBreak",        r->H##rx_break) \
        FIELD(P "TxD",            r->H##txd_q) \
        FIELD(P "TxState",        r->H##tx_state) \
        FIELD(P "TxShift",        r->H##tx_shift) \
        FIELD(P "TxBitCount",     r->H##tx_bit_count) \
        FIELD(P "TxSubCount",     r->H##tx_sub_count) \
        FIELD(P "TxStopBit",      r->H##tx_stop_bit) \
        FIELD(P "TxIP",           r->H##tx_ip) \
        FIELD(P "RxIntNextChar",  r->H##rx_int_next_char) \
        FIELD(P "RxIntForced",    r->H##rx_int_forced) \
        FIELD(P "RxLocked",       r->H##rx_lock) \
        FIELD(P "ExtIP",          r->H##ext_ip) \
        FIELD(P "DcdLatch",       r->H##dcd_latch) \
        FIELD(P "CtsLatch",       r->H##cts_latch) \
        FIELD(P "DcdSync0",       r->H##dcd_sync1) \
        FIELD(P "DcdSync1",       r->H##dcd_sync1) \
        FIELD(P "CtsSync0",       r->H##cts_sync1) \
        FIELD(P "CtsSync1",       r->H##cts_sync1) \
        FIELD(P "ExtLatchClosed", r->H##ext_latch_closed) \
        FIELD(P "BreakLatch",     r->H##break_latch) \
        FIELD(P "UnderrunLatch",  r->H##underrun_latch) \
        FIELD(P "PendingWR0",     r->H##pending_wr0) \
        FIELD(P "PendingWR0Cmd",  r->H##pending_wr0_cmd) \
        FIELD(P "PrevRTxC",       r->H##prev_rtxc) \
        FIELD(P "PrevTRxC",       r->H##prev_trxc) \
        FIELD(P "TrxcOutLevel",   r->H##trxc_out_lvl) \
        FIELD(P "RtsHold",        r->H##rts_hold) \
        FIELD(P "SDLC_TxSR",      r->H##sd_tx_sr) \
        FIELD(P "SDLC_TxN",       r->H##sd_tx_n) \
        FIELD(P "SDLC_TxKind",    r->H##sd_tx_kind) \
        FIELD(P "SDLC_TxOnes",    r->H##sd_tx_ones) \
        FIELD(P "SDLC_TxCRC",     r->H##sd_tx_crc) \
        FIELD(P "SDLC_TxPipe",    r->H##sd_tx_pipe) \
        FIELD(P "SDLC_Hunt",      r->H##sd_hunt) \
        FIELD(P "SDLC_RxRaw",     r->H##sd_rx_raw) \
        FIELD(P "SDLC_RxOnes",    r->H##sd_rx_ones) \
        FIELD(P "SDLC_InFrame",   r->H##sd_in_frame) \
        FIELD(P "SDLC_RxHist",    r->H##sd_rx_hist) \
        FIELD(P "SDLC_RxNB",      r->H##sd_rx_nb) \
        FIELD(P "SDLC_RxCnt",     r->H##sd_rx_cnt) \
        FIELD(P "SDLC_RxChars",   r->H##sd_rx_chars) \
        FIELD(P "SDLC_RxCRC",     r->H##sd_rx_crc) \
        FIELD(P "SDLC_Residue",   r->H##sd_residue) \
        FIELD(P "SDLC_TxCRCOn",   r->H##sd_tx_crc_on) \
        FIELD(P "SDLC_RxPend",    r->H##sd_rx_pend) \
        FIELD(P "SDLC_CRCOn",     r->H##sd_crc_on) \
        FIELD(P "SDLC_StripPrev", r->H##sd_strip_prev) \
        FIELD(P "SDLC_SyncOut",   r->H##sd_sync_out) \
        FIELD(P "SDLC_LoopOn",    r->H##lp_on) \
        FIELD(P "SDLC_LoopSend",  r->H##lp_send) \
        FIELD(P "SDLC_LoopPoll",  r->H##lp_poll) \
        FIELD(P "SDLC_LoopBit",   r->H##lp_bit) \
        FIELD(P "SDLC_LoopConv",  r->H##lp_conv) \
        FIELD(P "SDLC_LoopDrain", r->H##lp_drain) \
        FIELD(P "HuntLatch",      r->H##hunt_latch) \
        FIELD(P "SyncPin",        r->H##sync_pin) \
        FIELD(P "DPLL_On",             r->H##dp_on) \
        FIELD(P "DPLL_Search",         r->H##dp_search) \
        FIELD(P "DPLL_BRG",            r->H##dp_brg) \
        FIELD(P "DPLL_FM",             r->H##dp_fm) \
        FIELD(P "DPLL_Cnt",            r->H##dp_cnt) \
        FIELD(P "DPLL_Adj",            r->H##dp_adj) \
        FIELD(P "DPLL_Seen",           r->H##dp_seen) \
        FIELD(P "DPLL_Next",           r->H##dp_next) \
        FIELD(P "DPLL_MissN",          r->H##dp_miss_n) \
        FIELD(P "DPLL_Miss1",          r->H##dp_miss1) \
        FIELD(P "DPLL_Miss2",          r->H##dp_miss2) \
        FIELD(P "DPLL_Clk",            r->H##dp_clk) \
        FIELD(P "DPLL_RxIn",           r->H##dp_rx_in) \
        FIELD(P "DPLL_RxO",            r->H##dp_rxo) \
        FIELD(P "DPLL_TxO",            r->H##dp_txo) \
        FIELD(P "DPLL_TxLine",         r->H##tx_line) \
        FIELD(P "DPLL_TxRaw",          r->H##tx_raw) \
        FIELD(P "DPLL_RxPrev",         r->H##rx_prev) \
        FIELD(P "DPLL_RxBit",          r->H##rx_bit)
        CHANNEL("A_", z8030_scc__DOT__u_cha__DOT__)
        CHANNEL("B_", z8030_scc__DOT__u_chb__DOT__)
#undef CHANNEL
#undef FIELD
        return false;
    }
    bool poke(const std::string& name, uint64_t v)  { return access(name, v, true); }
    bool peek(const std::string& name, uint64_t& v) { return access(name, v, false); }
};
