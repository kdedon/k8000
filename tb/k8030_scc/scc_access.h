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
//     baud_counter rxd_q rx_state rx_shift rx_bit_count rx_sub_count
//     rx_stop_bit rx_break txd_q tx_state tx_shift tx_bit_count tx_sub_count
//     tx_stop_bit tx_ip rx_int_next_char rx_int_forced ext_ip dcd_latch
//     cts_latch dcd_sync0 dcd_sync1 cts_sync0 cts_sync1 ext_latch_closed
//     break_latch underrun_latch pending_wr0 pending_wr0_cmd prev_rtxc
//     prev_trxc trxc_out_lvl rts_hold

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
        FIELD(P "ExtIP",          r->H##ext_ip) \
        FIELD(P "DcdLatch",       r->H##dcd_latch) \
        FIELD(P "CtsLatch",       r->H##cts_latch) \
        FIELD(P "DcdSync0",       r->H##dcd_sync0) \
        FIELD(P "DcdSync1",       r->H##dcd_sync1) \
        FIELD(P "CtsSync0",       r->H##cts_sync0) \
        FIELD(P "CtsSync1",       r->H##cts_sync1) \
        FIELD(P "ExtLatchClosed", r->H##ext_latch_closed) \
        FIELD(P "BreakLatch",     r->H##break_latch) \
        FIELD(P "UnderrunLatch",  r->H##underrun_latch) \
        FIELD(P "PendingWR0",     r->H##pending_wr0) \
        FIELD(P "PendingWR0Cmd",  r->H##pending_wr0_cmd) \
        FIELD(P "PrevRTxC",       r->H##prev_rtxc) \
        FIELD(P "PrevTRxC",       r->H##prev_trxc) \
        FIELD(P "TrxcOutLevel",   r->H##trxc_out_lvl) \
        FIELD(P "RtsHold",        r->H##rts_hold)
        CHANNEL("A_", z8030_scc__DOT__u_cha__DOT__)
        CHANNEL("B_", z8030_scc__DOT__u_chb__DOT__)
#undef CHANNEL
#undef FIELD
        return false;
    }
    bool poke(const std::string& name, uint64_t v)  { return access(name, v, true); }
    bool peek(const std::string& name, uint64_t& v) { return access(name, v, false); }
};
