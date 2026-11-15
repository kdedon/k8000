// mmu_access.h -- THE HARNESS CONTRACT between tb_mmu.cpp and rtl/k8010_mmu/z8010_mmu.sv.
//
// tb_mmu replays MMU vectors that poke register state between
// clocks (Mode, SAR, DSC, VTR and descriptors written directly, and a
// trap acknowledge; LATCHED_ST / ADDR_LATCHED pokes are still accepted
// but no current vector uses them) and always compare the final register
// state. It reaches into the Verilated model through the
// accessors below (built with --public-flat-rw, so every signal is visible
// as rootp->z8010_mmu__DOT__<name>).
//
// If you rename or move any of these registers, update THIS FILE in the same
// change -- nothing else in the harness knows the hierarchy.
//
//   mode_reg sar dsc viol_type viol_sn viol_off isn ioffset
//   bcsr trap_pending viol_captured addr_latched latched_st ack_pending
//   desc_bh[64] desc_bl[64] desc_lm[64] desc_at[64] desc_cpui desc_dmai
//
// If SEGT_n is a separately registered output in your RTL rather than
// derived from trap_pending, extend ack() to release it too: the vectors
// assume SEGT_n == !trap_pending at all times
// (SEGT is released at the third CLK rise after the acknowledge's /AS rise,
// or at an earlier /DS rise; the
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

    // Descriptors: four RAMs plus flops (z8010_mmu.sv "Descriptor storage").
    uint16_t desc_base(int i) const {
        return (uint16_t)(top->rootp->z8010_mmu__DOT__desc_bh[i] << 8 | top->rootp->z8010_mmu__DOT__desc_bl[i]);
    }
    uint8_t  desc_limit(int i) const    { return top->rootp->z8010_mmu__DOT__desc_lm[i]; }
    uint8_t  desc_attr(int i) const {
        uint8_t a = top->rootp->z8010_mmu__DOT__desc_at[i];   // REF CHG DIRW EXC SYS RD
        uint8_t v = (uint8_t)((a & 0x38) << 2 | (a & 0x04) << 1 | (a & 0x03));
        v |= (uint8_t)((top->rootp->z8010_mmu__DOT__desc_cpui >> i & 1) << 2);
        v |= (uint8_t)((top->rootp->z8010_mmu__DOT__desc_dmai >> i & 1) << 4);
        return v;
    }
    void     set_desc(int i, uint16_t base, uint8_t limit, uint8_t attr) {
        auto* r = top->rootp;
        r->z8010_mmu__DOT__desc_bh[i] = base >> 8;
        r->z8010_mmu__DOT__desc_bl[i] = base & 0xFF;
        r->z8010_mmu__DOT__desc_lm[i] = limit;
        r->z8010_mmu__DOT__desc_at[i] = (uint8_t)((attr >> 2 & 0x38) | (attr >> 1 & 0x04) | (attr & 0x03));
        const uint64_t bit = 1ULL << i;
        r->z8010_mmu__DOT__desc_cpui = (r->z8010_mmu__DOT__desc_cpui & ~bit) | ((attr >> 2 & 1ULL) << i);
        r->z8010_mmu__DOT__desc_dmai = (r->z8010_mmu__DOT__desc_dmai & ~bit) | ((attr >> 4 & 1ULL) << i);
    }

    uint8_t  viol_type() const          { return top->rootp->z8010_mmu__DOT__viol_type; }
    void     set_viol_type(uint8_t v)   { top->rootp->z8010_mmu__DOT__viol_type = v; }
    uint8_t  viol_sn() const            { return top->rootp->z8010_mmu__DOT__viol_sn; }
    uint16_t viol_off() const           { return top->rootp->z8010_mmu__DOT__viol_off; }
    uint8_t  isn() const                { return top->rootp->z8010_mmu__DOT__isn; }
    uint8_t  ioffset() const            { return top->rootp->z8010_mmu__DOT__ioffset; }
    uint8_t  bcsr() const               { return top->rootp->z8010_mmu__DOT__bcsr; }
    bool     trap_pending() const       { return top->rootp->z8010_mmu__DOT__trap_pending; }

    // Vector-only pokes between records.
    void     set_latched_st(uint8_t v)  { top->rootp->z8010_mmu__DOT__latched_st = v & 0x0F; }
    void     set_addr_latched(bool v)   { top->rootp->z8010_mmu__DOT__addr_latched = v; }
    // Trap acknowledge: clears the trap, the captured violation and the
    // address latch; SEGT_n released.
    void     ack() {
        top->rootp->z8010_mmu__DOT__trap_pending  = 0;
        top->rootp->z8010_mmu__DOT__viol_captured = 0;
        top->rootp->z8010_mmu__DOT__addr_latched  = 0;
        top->rootp->z8010_mmu__DOT__viol_type     = 0;
        top->rootp->z8010_mmu__DOT__ack_pending   = 0;
    }
};
