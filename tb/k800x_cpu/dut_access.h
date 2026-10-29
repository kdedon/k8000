// dut_access.h -- THE HARNESS CONTRACT between tb_cpu.cpp and your RTL.
//
// tb_cpu replays Go-recorded vectors that sometimes poke architectural state
// between clocks (the Go tests wrote registers directly) and always compare
// the final architectural state. It reaches into the Verilated model through
// the accessors below (built with --public-flat-rw, so every signal is
// visible as rootp->z8000_cpu__DOT__<hier>__DOT__<name>).
//
// If you rename or move any of these registers, update THIS FILE in the same
// change -- nothing else in the harness knows the hierarchy.
//
//   u_regfile.r[16]  fcw  pc  psap  refresh  nspoff  nspseg  refresh_en  halted
//   u_sequencer.unhandled_q  u_execute.sp_we_q/sp_sel_q/sp_d_q

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
    void     set_pc(uint32_t v)          { top->rootp->z8000_cpu__DOT__pc = v; }

    uint32_t psap() const                { return top->rootp->z8000_cpu__DOT__psap; }
    void     set_psap(uint32_t v)        { top->rootp->z8000_cpu__DOT__psap = v; }

    uint16_t refresh() const             { return top->rootp->z8000_cpu__DOT__refresh; }
    void     set_refresh(uint16_t v)     { top->rootp->z8000_cpu__DOT__refresh = v; }

    uint16_t nspoff() const              { return top->rootp->z8000_cpu__DOT__nspoff; }
    void     set_nspoff(uint16_t v)      { top->rootp->z8000_cpu__DOT__nspoff = v; }

    uint16_t nspseg() const              { return top->rootp->z8000_cpu__DOT__nspseg; }
    void     set_nspseg(uint16_t v)      { top->rootp->z8000_cpu__DOT__nspseg = v; }

    bool     refresh_en() const          { return top->rootp->z8000_cpu__DOT__refresh_en; }
    void     set_refresh_en(bool v)      { top->rootp->z8000_cpu__DOT__refresh_en = v; }

    bool     halted() const              { return top->rootp->z8000_cpu__DOT__halted; }

    // A program reached a machine-cycle kind the CPU does not run yet.
    bool     unhandled_cycle() const     { return top->rootp->z8000_cpu__DOT__u_sequencer__DOT__unhandled_q; }

    // A simulation-only execute check failed.
    bool     execute_check() const       { return top->rootp->z8000_cpu__DOT__u_execute__DOT__check_q || top->rootp->z8000_cpu__DOT__u_sequencer__DOT__check_q; }
};
