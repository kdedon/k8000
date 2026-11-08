// fpu_access.h -- the harness contract between tb_fpu.cpp and the Z8070 RTL.
//
// tb_fpu reads the final register state and applies pokes through these
// accessors (built with --public-flat-rw). Rename a register in the RTL and
// update this file in the same change; nothing else in the harness knows
// the hierarchy.
//
//   Interface Processor: sc_q user_q fflags_q pc1_q pc2_q
//   Data Processor: f_mem (F0-F7 rows 0-7, FOP1 8, FOP2 9; 80 bits: {SE, significand})
//   top: dp_busy
//
// Values move as hex text, up to 80 bits. A register the RTL does not hold
// yet returns false from has(); its F record is reported as unchecked and
// a P record for it skips the vector.

#pragma once
#include <cstdint>
#include <cstdio>
#include <string>
#include "Vz8070_fpu.h"
#include "Vz8070_fpu___024root.h"

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

struct FpuAccess {
    Vz8070_fpu* top;
    explicit FpuAccess(Vz8070_fpu* t) : top(t) {}

    uint32_t* reg32(const std::string& n) const {
        auto* r = top->rootp;
        if (n == "SC")     return &r->z8070_fpu__DOT__u_ip__DOT__sc_q;
        if (n == "USER")   return &r->z8070_fpu__DOT__u_ip__DOT__user_q;
        if (n == "FFLAGS") return &r->z8070_fpu__DOT__u_ip__DOT__fflags_q;
        if (n == "PC1")    return &r->z8070_fpu__DOT__u_ip__DOT__pc1_q;
        if (n == "PC2")    return &r->z8070_fpu__DOT__u_ip__DOT__pc2_q;
        return nullptr;
    }

    // F0-F7 index, or -1.
    static int freg(const std::string& n) {
        if (n.size() == 2 && n[0] == 'F' && n[1] >= '0' && n[1] <= '7') return n[1] - '0';
        return -1;
    }

    // An 80-bit register: F0-F7, FOP1, FOP2.
    VlWide<3>* reg80(const std::string& n) const {
        auto* r = top->rootp;
        int f = freg(n);
        if (f >= 0) return &r->z8070_fpu__DOT__u_dp__DOT__f_mem[f];
        if (n == "FOP1") return &r->z8070_fpu__DOT__u_dp__DOT__f_mem[8];
        if (n == "FOP2") return &r->z8070_fpu__DOT__u_dp__DOT__f_mem[9];
        return nullptr;
    }

    bool has(const std::string& n) const {
        return reg32(n) != nullptr || reg80(n) != nullptr || n == "DPBUSY";
    }

    bool get(const std::string& n, V80& v) const {
        auto* r = top->rootp;
        v = V80();
        if (n == "DPBUSY") { v.lo = r->z8070_fpu__DOT__dp_busy; return true; }
        if (VlWide<3>* p80 = reg80(n)) {
            auto& w = *p80;
            v.lo = (uint64_t)w[1] << 32 | w[0];
            v.hi = w[2] & 0xFFFF;
            return true;
        }
        uint32_t* p = reg32(n);
        if (!p) return false;
        v.lo = *p;
        return true;
    }

    bool set(const std::string& n, const V80& v) {
        if (VlWide<3>* p80 = reg80(n)) {
            auto& w = *p80;
            w[0] = (uint32_t)v.lo;
            w[1] = (uint32_t)(v.lo >> 32);
            w[2] = (uint32_t)(v.hi & 0xFFFF);
            return true;
        }
        uint32_t* p = reg32(n);
        if (!p) return false;
        *p = (uint32_t)v.lo;
        return true;
    }
};
