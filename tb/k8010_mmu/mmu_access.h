// mmu_access.h -- THE HARNESS CONTRACT between tb_mmu.cpp and rtl/k8010_mmu/z8010_mmu.sv.
//
// tb_mmu replays Go-recorded MMU vectors that poke register state between
// clocks (the Go tests write ModeReg / SAR / DSC / VTR / Desc[] directly and
// call AcknowledgeTrap(); LATCHED_ST / ADDR_LATCHED pokes are still accepted
// but no current vector uses them) and always compare the final register
// state. It reaches into the Verilated model through the
// accessors below (built with --public-flat-rw, so every signal is visible
// as rootp->z8010_mmu__DOT__<name>).
//
// If you rename or move any of these registers, update THIS FILE in the same
// change -- nothing else in the harness knows the hierarchy.
//
//   mode_reg sar dsc viol_type viol_sn viol_off viol_overflow isn ioffset
//   bcsr trap_pending viol_captured addr_latched latched_st ack_pending
//   desc_base[64] desc_limit[64] desc_attr[64]
//
// If SEGT_n is a separately registered output in your RTL (as Go's
// out.SEGT_n is) rather than derived from trap_pending, extend ack() to
// release it too: the Go invariant is SEGT_n == !trapPending at all times
// (SEGT is released at the AS-rise sample of the acknowledge cycle; the
// identifier phase then uses ack_pending, which ack() also clears).

#pragma once
#include <cstdint>
#include "Vz8010_mmu.h"
#include "Vz8010_mmu___024root.h"

struct MmuAccess {
    Vz8010_mmu* top;
    explicit MmuAccess(Vz8010_mmu* t) : top(t) {}

    uint8_t  mode_reg() const           { return top->rootp->z8010_mmu__DOT__mode_reg; }
    void     set_mode_reg(uint8_t v)    { top->rootp->z8010_mmu__DOT__mode_reg = v; }

    uint8_t  sar() const                { return top->rootp->z8010_mmu__DOT__sar; }
    void     set_sar(uint8_t v)         { top->rootp->z8010_mmu__DOT__sar = v & 0x3F; }

    uint8_t  dsc() const                { return top->rootp->z8010_mmu__DOT__dsc; }
    void     set_dsc(uint8_t v)         { top->rootp->z8010_mmu__DOT__dsc = v & 0x03; }

    uint16_t desc_base(int i) const     { return top->rootp->z8010_mmu__DOT__desc_base[i]; }
    uint8_t  desc_limit(int i) const    { return top->rootp->z8010_mmu__DOT__desc_limit[i]; }
    uint8_t  desc_attr(int i) const     { return top->rootp->z8010_mmu__DOT__desc_attr[i]; }
    void     set_desc(int i, uint16_t base, uint8_t limit, uint8_t attr) {
        top->rootp->z8010_mmu__DOT__desc_base[i]  = base;
        top->rootp->z8010_mmu__DOT__desc_limit[i] = limit;
        top->rootp->z8010_mmu__DOT__desc_attr[i]  = attr;
    }

    uint8_t  viol_type() const          { return top->rootp->z8010_mmu__DOT__viol_type; }
    void     set_viol_type(uint8_t v)   { top->rootp->z8010_mmu__DOT__viol_type = v; }
    uint8_t  viol_sn() const            { return top->rootp->z8010_mmu__DOT__viol_sn; }
    uint16_t viol_off() const           { return top->rootp->z8010_mmu__DOT__viol_off; }
    bool     viol_overflow() const      { return top->rootp->z8010_mmu__DOT__viol_overflow; }
    uint8_t  isn() const                { return top->rootp->z8010_mmu__DOT__isn; }
    uint8_t  ioffset() const            { return top->rootp->z8010_mmu__DOT__ioffset; }
    uint8_t  bcsr() const               { return top->rootp->z8010_mmu__DOT__bcsr; }
    bool     trap_pending() const       { return top->rootp->z8010_mmu__DOT__trap_pending; }

    // Go-only helpers the tests use between Ticks.
    void     set_latched_st(uint8_t v)  { top->rootp->z8010_mmu__DOT__latched_st = v & 0x0F; }
    void     set_addr_latched(bool v)   { top->rootp->z8010_mmu__DOT__addr_latched = v; }
    // AcknowledgeTrap(): mmu.go -- trapPending=0, violCaptured=0,
    // addrLatched=0, ViolType=0, ViolOverflow=0, SEGT_n released.
    void     ack() {
        top->rootp->z8010_mmu__DOT__trap_pending  = 0;
        top->rootp->z8010_mmu__DOT__viol_captured = 0;
        top->rootp->z8010_mmu__DOT__addr_latched  = 0;
        top->rootp->z8010_mmu__DOT__viol_type     = 0;
        top->rootp->z8010_mmu__DOT__viol_overflow = 0;
        top->rootp->z8010_mmu__DOT__ack_pending   = 0;
    }
};
