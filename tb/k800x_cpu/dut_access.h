// dut_access.h -- THE HARNESS CONTRACT between tb_cpu.cpp and your RTL.
//
// tb_cpu replays vectors that sometimes poke architectural state
// between clocks (registers written directly) and always compare
// the final architectural state. It reaches into the Verilated model through
// the accessors below (built with --public-flat-rw, so every signal is
// visible as rootp->z8000_cpu__DOT__<hier>__DOT__<name>).
//
// If you rename or move any of these registers, update THIS FILE in the same
// change -- nothing else in the harness knows the hierarchy.
//
//   u_regfile.r[16]  fcw  pc  psap  refresh (bit 15 RE)  nspoff  nspseg  halted
//   u_refresh.owed_q count_q
//   u_execute.sp_we_q/sp_sel_q/sp_d_q
//   u_execute.tset_rmw/wr_next_q  mem_take  bus_done   (TSET bus lock)

#pragma once
#include <cstdint>
#include "Vz8000_cpu.h"
#include "Vz8000_cpu___024root.h"

struct DutAccess {
    Vz8000_cpu* top;
    explicit DutAccess(Vz8000_cpu* t) : top(t) {}

    // The stack pointer's write lands a clock after its cycle is taken; a
    // vector may end on that take, so a pending write counts.
    uint16_t reg(int i) const {
        auto* r = top->rootp;
        if (r->z8000_cpu__DOT__u_execute__DOT__sp_we_q && r->z8000_cpu__DOT__u_execute__DOT__sp_sel_q == i)
            return r->z8000_cpu__DOT__u_execute__DOT__sp_d_q;
        return r->z8000_cpu__DOT__u_regfile__DOT__r[i];
    }
    void     set_reg(int i, uint16_t v)  { top->rootp->z8000_cpu__DOT__u_regfile__DOT__r[i] = v; }

    uint16_t fcw() const                 { return top->rootp->z8000_cpu__DOT__fcw; }
    void     set_fcw(uint16_t v)         { top->rootp->z8000_cpu__DOT__fcw = v; }

    uint32_t pc() const                  { return top->rootp->z8000_cpu__DOT__pc; }
    void     set_pc(uint32_t v)          { top->rootp->z8000_cpu__DOT__pc = v & 0x7FFFFF; }

    uint32_t psap() const                { return top->rootp->z8000_cpu__DOT__psap; }
    void     set_psap(uint32_t v)        { top->rootp->z8000_cpu__DOT__psap = v & 0x7FFFFF; }

    uint16_t refresh() const             { return top->rootp->z8000_cpu__DOT__refresh; }
    // RATE and ROW; RE is set by its bit 15 or kept from REFRESH_EN, in
    // either order. With RE set the prescaler loads RATE, as a write does.
    void     set_refresh(uint16_t v)     { auto& r = top->rootp->z8000_cpu__DOT__refresh; r = (v & 0xFFFE) | (r & 0x8000); load_prescaler(); }

    uint16_t nspoff() const              { return top->rootp->z8000_cpu__DOT__nspoff; }
    void     set_nspoff(uint16_t v)      { top->rootp->z8000_cpu__DOT__nspoff = v; }

    uint16_t nspseg() const              { return top->rootp->z8000_cpu__DOT__nspseg; }
    void     set_nspseg(uint16_t v)      { top->rootp->z8000_cpu__DOT__nspseg = v; }

    bool     refresh_en() const          { return top->rootp->z8000_cpu__DOT__refresh >> 15; }
    void     set_refresh_en(bool v)      { auto& r = top->rootp->z8000_cpu__DOT__refresh; r = (r & 0x7FFF) | (v ? 0x8000 : 0); load_prescaler(); }
    void     load_prescaler()            { auto* r = top->rootp; if (r->z8000_cpu__DOT__refresh >> 15) r->z8000_cpu__DOT__u_refresh__DOT__count_q = (r->z8000_cpu__DOT__refresh >> 9) & 0x3F; }

    // A refresh owed, as the prescaler's underflow leaves one.
    void     set_rfsh_pend(bool v)       { top->rootp->z8000_cpu__DOT__u_refresh__DOT__owed_q = v ? 1 : 0; }

    bool     halted() const              { return top->rootp->z8000_cpu__DOT__halted; }

    // TSET's lock, from its read's word to its write's take (no pin carries it).
    bool     rmw_lock() const            { auto* r = top->rootp; return r->z8000_cpu__DOT__u_execute__DOT__tset_rmw && r->z8000_cpu__DOT__u_execute__DOT__wr_next_q; }
    bool     mem_take() const            { return top->rootp->z8000_cpu__DOT__mem_take; }
    bool     bus_done() const            { return top->rootp->z8000_cpu__DOT__bus_done; }

    // A simulation-only execute check failed.
    bool     execute_check() const       { return top->rootp->z8000_cpu__DOT__u_execute__DOT__check_q || top->rootp->z8000_cpu__DOT__u_sequencer__DOT__check_q || top->rootp->z8000_cpu__DOT__check_q; }
};
