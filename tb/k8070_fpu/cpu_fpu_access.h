// cpu_fpu_access.h -- the harness contract between tb_cpu_fpu.cpp and the
// two chips under the tb_cpu_fpu board (built with --public-flat-rw).
//
//   u_cpu: u_regfile.r[16] fcw pc psap nspoff nspseg halted,
//          u_execute.sp_we_q/sp_sel_q/sp_d_q, u_int.smp/smp_halt/halt_on
//   u_fpu: u_ip sc_q user_q fflags_q pc1_q pc2_q, u_dp f_mem (F0-F7, FOP1 8,
//          FOP2 9), dp_busy
//
// Rename one of these in the RTL and update this file in the same change.

#pragma once
#include <cstdint>
#include <cstdio>
#include <string>
#include "Vtb_cpu_fpu.h"
#include "Vtb_cpu_fpu___024root.h"

#define CPU_(n) tb_cpu_fpu__DOT__u_cpu__DOT__##n
#define FPU_(n) tb_cpu_fpu__DOT__u_fpu__DOT__##n

// An 80-bit value: hi = bits 79:64, lo = bits 63:0.
struct V80 {
    uint64_t hi = 0, lo = 0;
    bool operator==(const V80& o) const { return hi == o.hi && lo == o.lo; }
    bool operator!=(const V80& o) const { return !(*this == o); }
    static V80 parse(const std::string& h) {
        V80 v;
        size_t n = h.size();
        if (n > 16) {
            v.hi = strtoull(h.substr(0, n - 16).c_str(), nullptr, 16);
            v.lo = strtoull(h.substr(n - 16).c_str(), nullptr, 16);
        } else {
            v.lo = strtoull(h.c_str(), nullptr, 16);
        }
        return v;
    }
    std::string str() const {
        char b[40];
        if (hi) snprintf(b, sizeof b, "%llX%016llX", (unsigned long long)hi, (unsigned long long)lo);
        else snprintf(b, sizeof b, "%llX", (unsigned long long)lo);
        return b;
    }
};

struct BoardAccess {
    Vtb_cpu_fpu* top;
    explicit BoardAccess(Vtb_cpu_fpu* t) : top(t) {}

    // CPU. The stack pointer's write lands a clock after its cycle is
    // taken; a pending write counts.
    uint16_t reg(int i) const {
        auto* r = top->rootp;
        if (r->CPU_(u_execute__DOT__sp_we_q) && r->CPU_(u_execute__DOT__sp_sel_q) == i)
            return r->CPU_(u_execute__DOT__sp_d_q);
        return r->CPU_(u_regfile__DOT__r)[i];
    }
    bool cpuPoke(const std::string& n, uint64_t v) {
        auto* r = top->rootp;
        if (n.size() >= 2 && n[0] == 'R' && isdigit((unsigned char)n[1])) r->CPU_(u_regfile__DOT__r)[atoi(n.c_str() + 1)] = (uint16_t)v;
        else if (n == "FCW") r->CPU_(fcw) = (uint16_t)v;
        else if (n == "PC") r->CPU_(pc) = (uint32_t)v;
        else if (n == "PSAP") r->CPU_(psap) = (uint32_t)v;
        else if (n == "NSPOFF") r->CPU_(nspoff) = (uint16_t)v;
        else if (n == "NSPSEG") r->CPU_(nspseg) = (uint16_t)v;
        else return false;
        return true;
    }
    bool cpuGet(const std::string& n, uint64_t& v) const {
        auto* r = top->rootp;
        if (n == "FCW") v = r->CPU_(fcw);
        else if (n == "PC") v = r->CPU_(pc);
        else if (n == "PSAP") v = r->CPU_(psap);
        else if (n == "NSPOFF") v = r->CPU_(nspoff);
        else if (n == "NSPSEG") v = r->CPU_(nspseg);
        else if (n == "HALTED") v = r->CPU_(halted);
        else return false;
        return true;
    }

    // /VI is taken on this CLK rise: the instruction's sample or HALT's.
    bool viSampled() const {
        auto* r = top->rootp;
        return r->CPU_(u_int__DOT__smp) || (r->CPU_(u_int__DOT__smp_halt) && r->CPU_(u_int__DOT__halt_on));
    }

    // FPU.
    uint32_t* reg32(const std::string& n) const {
        auto* r = top->rootp;
        if (n == "SC")     return &r->FPU_(u_ip__DOT__sc_q);
        if (n == "USER")   return &r->FPU_(u_ip__DOT__user_q);
        if (n == "FFLAGS") return &r->FPU_(u_ip__DOT__fflags_q);
        if (n == "PC1")    return &r->FPU_(u_ip__DOT__pc1_q);
        if (n == "PC2")    return &r->FPU_(u_ip__DOT__pc2_q);
        return nullptr;
    }
    VlWide<3>* reg80(const std::string& n) const {
        auto* r = top->rootp;
        if (n.size() == 2 && n[0] == 'F' && n[1] >= '0' && n[1] <= '7') return &r->FPU_(u_dp__DOT__f_mem)[n[1] - '0'];
        if (n == "FOP1") return &r->FPU_(u_dp__DOT__f_mem)[8];
        if (n == "FOP2") return &r->FPU_(u_dp__DOT__f_mem)[9];
        return nullptr;
    }
    bool fpuGet(const std::string& n, V80& v) const {
        v = V80();
        if (n == "DPBUSY") { v.lo = top->rootp->FPU_(dp_busy); return true; }
        if (VlWide<3>* p = reg80(n)) {
            v.lo = (uint64_t)(*p)[1] << 32 | (*p)[0];
            v.hi = (*p)[2] & 0xFFFF;
            return true;
        }
        if (uint32_t* p = reg32(n)) { v.lo = *p; return true; }
        return false;
    }
    bool fpuPoke(const std::string& n, const V80& v) {
        if (VlWide<3>* p = reg80(n)) {
            (*p)[0] = (uint32_t)v.lo;
            (*p)[1] = (uint32_t)(v.lo >> 32);
            (*p)[2] = (uint32_t)(v.hi & 0xFFFF);
            return true;
        }
        if (uint32_t* p = reg32(n)) { *p = (uint32_t)v.lo; return true; }
        return false;
    }
};
