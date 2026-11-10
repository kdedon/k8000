// tb_fpu_dp -- replay of recorded Data Processor operations (`fpudp`
// D records) into the Verilated z8070_dp alone.
//
//   tb_fpu_dp [--only g1,g2,...] [--mclk P] [--show N] [--quiet] file.vec...
//
// Each record: the operation, precision and rounding mode on the start
// pulse, the destination and source operands on the operand bus as the DP
// names them, then CLK.D rises until done. Integer to float: the integer
// is the source operand's significand. Float to integer: op_prec is the
// width (opts bit 0), a truncate (opts bit 1) passes rm 01, and the
// result is {0000, rint}. Compared: result (20 hex),
// flags, invalid reason, rounded-up bit, compare code and the CLK.D count
// (done's rise counted). Every other record starts on the first CLK.D
// rise instead of the master clock before it. CLK.D's High and Low phases
// take the next counts of master clocks from P (comma list, cycled;
// default K8000_MCLK or "1,2,1,3").
//
// Groups by operation: add (FADD FSUB FRVSUB), load, sign (FABS FNEG
// FCLR), cmp (FCP FCPX FCPZ FCPZX), mul (FMUL FPWR2), div (FDIV FRDIV),
// sqrt, fint, rem (FREM FREMSTEP), conv (integer), bcd. One line per
// group run; the first N failures of each are shown (default 3).
//
// Exit codes: 0 every selected record passes, 1 a failure, 4 usage or
// parse error.

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <map>
#include <fstream>
#include <sstream>

#include "verilated.h"
#include "Vz8070_dp.h"

struct Rec {
    unsigned kind, prec, rm;
    uint16_t dse, sse, rse;
    uint64_t dsig, ssig, rsig, iv, rint;
    unsigned opts;
    unsigned flags, reason, rup, cmp, cycles;
    std::string where;
};

static const char* groupOf(unsigned k) {
    switch (k) {
    case 0x00: case 0x01: case 0x02: return "add";
    case 0x08: return "load";
    case 0x09: case 0x0A: case 0x0B: return "sign";
    case 0x0D: case 0x0E: case 0x0F: case 0x10: return "cmp";
    case 0x03: case 0x06: return "mul";
    case 0x04: case 0x05: return "div";
    case 0x07: return "sqrt";
    case 0x0C: return "fint";
    case 0x11: case 0x12: return "rem";
    case 0x20: case 0x21: return "conv";
    case 0x22: case 0x23: return "bcd";
    }
    return "other";
}
static const char* const kGroups[] = {"add", "load", "sign", "cmp", "mul", "div", "sqrt",
                                      "fint", "rem", "conv", "bcd", "other"};

static bool parseX80(const std::string& s, uint16_t& se, uint64_t& sig) {
    if (s.size() != 20) return false;
    se = (uint16_t)strtoul(s.substr(0, 4).c_str(), nullptr, 16);
    sig = strtoull(s.substr(4).c_str(), nullptr, 16);
    return true;
}

static std::vector<unsigned> parseList(const char* s) {
    std::vector<unsigned> v;
    std::stringstream ss(s);
    std::string t;
    while (std::getline(ss, t, ','))
        if (!t.empty()) v.push_back((unsigned)atoi(t.c_str()));
    return v;
}

struct Bench {
    Vz8070_dp* t;
    std::vector<unsigned> mclk;
    size_t mi = 0;
    uint16_t dse = 0, sse = 0;
    uint64_t dsig = 0, ssig = 0;

    unsigned nextM() {
        unsigned m = mclk[mi++ % mclk.size()];
        return m ? m : 1;
    }
    void drive() {
        t->eval();
        uint16_t se = t->opnd_src ? sse : dse;
        uint64_t sig = t->opnd_src ? ssig : dsig;
        t->opnd[0] = (uint32_t)sig;
        t->opnd[1] = (uint32_t)(sig >> 32);
        t->opnd[2] = se;
        t->eval();
    }
    // One master clock; returns done as seen before the edge.
    bool clock() {
        drive();
        bool d = t->done;
        t->clk = 1; t->eval();
        t->clk = 0; t->eval();
        return d;
    }
    void reset() {
        t->reset_n = 0; t->start = 0; t->clkd_rise = 0; t->clk = 0;
        for (int i = 0; i < 4; i++) clock();
        t->reset_n = 1;
        clock();
    }
    // Runs one operation; returns the CLK.D count, 0 if done never came.
    unsigned run(const Rec& r, bool coincide) {
        dse = r.dse; dsig = r.dsig; sse = r.sse; ssig = r.ssig;
        if (r.kind == 0x20) { sse = 0; ssig = r.iv; }
        t->op_kind = r.kind; t->op_prec = r.prec; t->op_rm = r.rm;
        if (r.kind == 0x21) {
            t->op_prec = r.opts & 1;
            if (r.opts & 2) t->op_rm = 1;
        }
        unsigned rises = 0;
        if (!coincide) {
            t->start = 1; t->clkd_rise = 0;
            clock();
            t->start = 0;
            unsigned m = nextM();
            for (unsigned i = 1; i < m; i++) clock();
        }
        for (;;) {
            unsigned hi = nextM(), lo = nextM();
            t->clkd_rise = 1;
            if (coincide && rises == 0) t->start = 1;
            bool d = clock();
            t->start = 0; t->clkd_rise = 0;
            rises++;
            for (unsigned i = 1; i < hi; i++) clock();
            for (unsigned i = 0; i < lo; i++) clock();
            if (d) return rises;
            if (rises >= 400) return 0;
        }
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::vector<std::string> files;
    std::map<std::string, bool> only;
    const char* mclkArg = getenv("K8000_MCLK");
    std::string mclkStr = mclkArg ? mclkArg : "1,2,1,3";
    int show = 3;
    bool quiet = false;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--only" && i + 1 < argc) {
            std::stringstream ss(argv[++i]);
            std::string g;
            while (std::getline(ss, g, ','))
                if (!g.empty()) only[g] = true;
        } else if (a == "--mclk" && i + 1 < argc) {
            mclkStr = argv[++i];
        } else if (a == "--show" && i + 1 < argc) {
            show = atoi(argv[++i]);
        } else if (a == "--quiet") {
            quiet = true;
        } else if (a.size() > 0 && a[0] == '+') {
            // Verilator plusargs
        } else if (a.size() > 1 && a[0] == '-') {
            fprintf(stderr, "usage: tb_fpu_dp [--only g,...] [--mclk P] [--show N] [--quiet] file.vec...\n");
            return 4;
        } else {
            files.push_back(a);
        }
    }
    if (files.empty()) {
        fprintf(stderr, "tb_fpu_dp: no vector files\n");
        return 4;
    }
    for (auto& g : only) {
        bool known = false;
        for (const char* k : kGroups) known |= g.first == k;
        if (!known) {
            fprintf(stderr, "tb_fpu_dp: unknown group %s\n", g.first.c_str());
            return 4;
        }
    }

    Bench b;
    b.t = new Vz8070_dp;
    b.mclk = parseList(mclkStr.c_str());
    if (b.mclk.empty()) b.mclk.push_back(1);
    b.reset();

    std::map<std::string, unsigned> pass, fail;
    std::map<std::string, int> shown;
    unsigned long n = 0;

    for (auto& path : files) {
        std::ifstream in(path);
        if (!in) {
            fprintf(stderr, "tb_fpu_dp: cannot open %s\n", path.c_str());
            return 4;
        }
        std::string line;
        unsigned ln = 0;
        bool header = false;
        while (std::getline(in, line)) {
            ln++;
            if (ln == 1) {
                if (line.rfind("K8000VEC 1 fpudp", 0) != 0) {
                    fprintf(stderr, "%s: not a K8000VEC 1 fpudp file\n", path.c_str());
                    return 4;
                }
                header = true;
                continue;
            }
            if (line.empty() || line[0] != 'D') continue;
            std::istringstream ss(line);
            std::string tag, kind, prec, rm, dst, src, iv, opts, res, flags, reason, rup, cmp, rint;
            unsigned cycles;
            if (!(ss >> tag >> kind >> prec >> rm >> dst >> src >> iv >> opts >> res >> flags >> reason >> rup >> cmp >> rint >> cycles)) {
                fprintf(stderr, "%s:%u: bad D record\n", path.c_str(), ln);
                return 4;
            }
            Rec r;
            r.kind = strtoul(kind.c_str(), nullptr, 16);
            r.prec = strtoul(prec.c_str(), nullptr, 16);
            r.rm = strtoul(rm.c_str(), nullptr, 16);
            if (!parseX80(dst, r.dse, r.dsig) || !parseX80(src, r.sse, r.ssig) || !parseX80(res, r.rse, r.rsig)) {
                fprintf(stderr, "%s:%u: bad X80 field\n", path.c_str(), ln);
                return 4;
            }
            r.flags = strtoul(flags.c_str(), nullptr, 16);
            r.reason = strtoul(reason.c_str(), nullptr, 16);
            r.rup = strtoul(rup.c_str(), nullptr, 16);
            r.cmp = strtoul(cmp.c_str(), nullptr, 16);
            r.cycles = cycles;
            r.iv = strtoull(iv.c_str(), nullptr, 16);
            r.opts = strtoul(opts.c_str(), nullptr, 16);
            r.rint = strtoull(rint.c_str(), nullptr, 16);
            if (r.kind == 0x21) { r.rse = 0; r.rsig = r.rint; }
            std::string g = groupOf(r.kind);
            if (!only.empty() && !only.count(g)) continue;

            unsigned got = b.run(r, (n++ & 1) != 0);
            uint64_t sig = (uint64_t)b.t->res[1] << 32 | b.t->res[0];
            uint16_t se = (uint16_t)(b.t->res[2] & 0xFFFF);
            bool ok = got == r.cycles && se == r.rse && sig == r.rsig &&
                      b.t->res_flags == r.flags && b.t->res_reason == r.reason &&
                      b.t->res_rup == r.rup && b.t->res_cmp == r.cmp && !b.t->busy;
            if (ok) {
                pass[g]++;
            } else {
                fail[g]++;
                if (shown[g]++ < show) {
                    const char* base = strrchr(path.c_str(), '/');
                    base = base ? base + 1 : path.c_str();
                    printf("FAIL %s %s:%u kind %02X prec %u rm %u dst %s src %s\n", g.c_str(), base, ln,
                           r.kind, r.prec, r.rm, dst.c_str(), src.c_str());
                    printf("     want res %04X%016llX flags %02X reason %u rup %u cmp %02X clocks %u\n",
                           r.rse, (unsigned long long)r.rsig, r.flags, r.reason, r.rup, r.cmp, r.cycles);
                    printf("     got  res %04X%016llX flags %02X reason %u rup %u cmp %02X clocks %u%s\n",
                           se, (unsigned long long)sig, b.t->res_flags, b.t->res_reason, b.t->res_rup,
                           b.t->res_cmp, got, b.t->busy ? " (still busy)" : "");
                }
            }
        }
        if (!header) {
            fprintf(stderr, "%s: empty file\n", path.c_str());
            return 4;
        }
    }

    bool allOk = true;
    for (const char* g : kGroups) {
        unsigned p = pass[g], f = fail[g];
        if (p + f == 0) continue;
        if (f) allOk = false;
        if (!quiet || f)
            printf("RESULT %-5s %s %u/%u\n", g, f ? "FAIL" : "PASS", p, p + f);
    }
    delete b.t;
    return allOk ? 0 : 1;
}
