// tb_cpu_fpu -- closed-loop replay of a recorded CPU + Z8070 system
// vector (`K8000VEC 1 cpufpu`) against the tb_cpu_fpu board: the RTL CPU
// and FPU on real pins, with a bench memory.
//
//   tb_cpu_fpu_<variant> <file.vec> [--context N] [--vcd out.vcd] [--quiet]
//                                   [--stop-first] [--no-final] [--mclk P]
//
// Only the board inputs (/RESET, /BUSREQ, /NMI, /NVI, SEGT, /ABORT, /MI)
// come from the records; everything between the chips and the memory is
// the board's. Each C record (one CPU CLK level) gets the next count of
// master clocks from P (comma list, cycled; default K8000_MCLK or
// "1,2,1,3"); its first carries the CPU CLK pulse, which is also CLK.I and
// CLK.D. E records drive nothing.
//
// Compared: the CPU's outputs at every C record (the CPU bench's rules);
// the CPU's inputs where it samples them (STOP and /WAIT at a CLK fall,
// /VI at a rise that takes it, AD at a read's T3 rise); the FPU's outputs
// at every CLK.I=1 E record (what the CPU sees next); memory words the bus
// changed against the W records; the final CPU, FPU and memory state. A
// clash of two AD drivers is a failure, but for an EPU store's data from
// the /AS rise over the CPU's address, which is counted (store-overlap).
//
// Exit codes: 0 PASS, 1 FAIL, 2 SKIP, 3 wrong variant binary, 4 usage or
// parse error.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <deque>
#include <map>
#include <fstream>
#include <sstream>

#include "verilated.h"
#if VM_TRACE
#include "verilated_vcd_c.h"
#endif
#include "Vtb_cpu_fpu.h"
#include "cpu_fpu_access.h"

#ifndef K8000_VARIANT
#define K8000_VARIANT "Z8001"
#endif
#ifndef K8000_SEGMENTED
#define K8000_SEGMENTED 1
#endif

struct CIn {
    bool clk, reset_n, stop_n, wait_n, busreq_n, nmi_n, nvi_n, vi_n, segt_n, abort_n, mi_n;
    uint16_t ad;
};
struct COut {
    bool ad_drive, as_n, ds_n, mreq_n, r_w, b_w, n_s, busack_n, mo_n;
    uint16_t ad;
    uint8_t sn, st;
};
struct EOut {
    bool ad_drive, bsy_n, int_n, ieo;
    uint16_t ad;
};

static CIn decodeCIn(unsigned b, unsigned ad) {
    CIn i;
    i.clk = b >> 10 & 1; i.reset_n = b >> 9 & 1; i.stop_n = b >> 8 & 1;
    i.wait_n = b >> 7 & 1; i.busreq_n = b >> 6 & 1; i.nmi_n = b >> 5 & 1;
    i.nvi_n = b >> 4 & 1; i.vi_n = b >> 3 & 1; i.segt_n = b >> 2 & 1;
    i.abort_n = b >> 1 & 1; i.mi_n = b & 1; i.ad = ad;
    return i;
}
static COut decodeCOut(unsigned b, unsigned ad, unsigned sn, unsigned st) {
    COut o;
    o.ad_drive = b >> 8 & 1; o.as_n = b >> 7 & 1; o.ds_n = b >> 6 & 1;
    o.mreq_n = b >> 5 & 1; o.r_w = b >> 4 & 1; o.b_w = b >> 3 & 1;
    o.n_s = b >> 2 & 1; o.busack_n = b >> 1 & 1; o.mo_n = b & 1;
    o.ad = ad; o.sn = sn; o.st = st;
    return o;
}
static COut readCOut(Vtb_cpu_fpu* t) {
    COut o;
    o.ad_drive = t->cpu_ad_drive; o.as_n = t->as_n; o.ds_n = t->ds_n; o.mreq_n = t->mreq_n;
    o.r_w = t->r_w; o.b_w = t->b_w; o.n_s = t->n_s; o.busack_n = t->busack_n; o.mo_n = t->mo_n;
    o.ad = t->cpu_ad_out; o.sn = t->sn; o.st = t->st;
    return o;
}
static EOut readEOut(Vtb_cpu_fpu* t) {
    EOut o;
    o.ad_drive = t->fpu_ad_drive; o.bsy_n = t->bsy_n; o.int_n = t->int_n; o.ieo = t->ieo;
    o.ad = t->fpu_ad_out;
    return o;
}

static const char* stName(unsigned st) {
    static const char* n[16] = {"INT", "RFSH", "IO", "SIO", "SEGT", "NMIA", "NVIA", "VIA",
                                "DMEM", "SMEM", "DEPU", "SEPU", "PROG", "IF1", "EPUX", "LOCK"};
    return n[st & 15];
}

static std::string cRow(long tick, const CIn& in, const CIn& seen, const COut& e, const COut& a,
                        const std::string& marks) {
    char buf[512];
    snprintf(buf, sizeof buf,
             "%7ld C %d %d %04X %c%c%c | %c%c%c | %d %d %d %d %d %d %-4s %04X %02X | %d %d %d %d %d %d %-4s %04X %02X  %s",
             tick, in.clk, in.reset_n, in.ad,
             in.stop_n ? '-' : 'S', in.wait_n ? '-' : 'W', in.vi_n ? '-' : 'v',
             seen.stop_n ? '-' : 'S', seen.wait_n ? '-' : 'W', seen.vi_n ? '-' : 'v',
             e.ad_drive, e.as_n, e.ds_n, e.mreq_n, e.r_w, e.b_w, stName(e.st), e.ad, e.sn,
             a.ad_drive, a.as_n, a.ds_n, a.mreq_n, a.r_w, a.b_w, stName(a.st), a.ad, a.sn,
             marks.c_str());
    return buf;
}
static std::string eRow(long tick, const EOut& e, const EOut& a, const std::string& marks) {
    char buf[256];
    snprintf(buf, sizeof buf, "%7ld E   fpu: Dr BSY INT IEO AD | %d %d %d %d %04X | %d %d %d %d %04X  %s",
             tick, e.ad_drive, e.bsy_n, e.int_n, e.ieo, e.ad,
             a.ad_drive, a.bsy_n, a.int_n, a.ieo, a.ad, marks.c_str());
    return buf;
}

// A memory status: data, stack, EPU-memory, program, IF1 (not 1110).
static bool memStatus(unsigned st) { return st >= 8 && st != 0xE; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::string vecPath, vcdPath;
    int context = 12;
    bool quiet = false, stopFirst = false, checkFinal = true;
    std::string mclkPat = getenv("K8000_MCLK") ? getenv("K8000_MCLK") : "1,2,1,3";
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--context" && i + 1 < argc) context = atoi(argv[++i]);
        else if (a == "--vcd" && i + 1 < argc) vcdPath = argv[++i];
        else if (a == "--quiet") quiet = true;
        else if (a == "--stop-first") stopFirst = true;
        else if (a == "--no-final") checkFinal = false;
        else if (a == "--mclk" && i + 1 < argc) mclkPat = argv[++i];
        else if (a.size() > 1 && a[0] == '-' && a[1] == '-') { fprintf(stderr, "unknown option %s\n", a.c_str()); return 4; }
        else vecPath = a;
    }
    if (vecPath.empty()) { fprintf(stderr, "usage: tb_cpu_fpu <file.vec> [--context N] [--vcd f] [--quiet] [--stop-first] [--no-final] [--mclk P]\n"); return 4; }

    std::ifstream f(vecPath);
    if (!f) { printf("RESULT FAIL %s: cannot open\n", vecPath.c_str()); return 4; }

    std::vector<int> mclkSeq;
    for (size_t p0 = 0; p0 < mclkPat.size();) {
        size_t p1 = mclkPat.find(',', p0); if (p1 == std::string::npos) p1 = mclkPat.size();
        int n = atoi(mclkPat.substr(p0, p1 - p0).c_str());
        if (n < 1) { fprintf(stderr, "--mclk: counts must be >= 1\n"); return 4; }
        mclkSeq.push_back(n); p0 = p1 + 1;
    }
    if (mclkSeq.empty()) { fprintf(stderr, "--mclk: empty pattern\n"); return 4; }
    size_t mclkIdx = 0;

    Vtb_cpu_fpu* top = new Vtb_cpu_fpu;
    BoardAccess dut(top);
#if VM_TRACE
    VerilatedVcdC* tfp = nullptr;
    if (!vcdPath.empty()) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open(vcdPath.c_str());
    }
    vluint64_t simTime = 0;
    auto dump = [&]() { if (tfp) { tfp->dump(simTime); simTime += 5; } };
#else
    auto dump = [&]() {};
#endif

    // Bench memory: mapped windows from `mem` lines, FFFF elsewhere.
    std::vector<uint8_t> mem(1u << 24, 0);
    std::vector<std::pair<uint32_t, uint32_t>> maps;
    auto mapped = [&](uint32_t a) {
        for (auto& m : maps) if (a >= m.first && a < m.first + m.second) return true;
        return false;
    };
    uint32_t latAddr = 0; unsigned latSt = 0; bool latRead = true, latByte = false;
    bool prevDsLow = false, wdriven = false; uint16_t wdata = 0;
    std::vector<std::pair<uint32_t, uint16_t>> gotW;   // words the bus changed
    long clashes = 0, overlaps = 0;
    auto memWrite = [&](uint32_t a, uint16_t d, bool byte) {
        if (!mapped(a)) return;
        uint32_t w = a & 0xFFFFFE;
        uint16_t was = (uint16_t)(mem[w] << 8 | mem[w + 1]);
        if (byte) mem[a] = (a & 1) ? (uint8_t)d : (uint8_t)(d >> 8);
        else { mem[w] = (uint8_t)(d >> 8); mem[w + 1] = (uint8_t)d; }
        uint16_t now = (uint16_t)(mem[w] << 8 | mem[w + 1]);
        if (now != was) gotW.push_back({w, now});
    };
    // Follow the bus on the settled pins; drive read data while /DS is Low.
    auto memBus = [&]() {
        if (!top->as_n) {
            latAddr = (K8000_SEGMENTED ? (uint32_t)top->sn << 16 : 0) | top->ad;
            latSt = top->st; latRead = top->r_w; latByte = top->b_w;
        }
        bool dsLow = !top->ds_n;
        if (dsLow && !prevDsLow) wdriven = false;
        if (dsLow && !latRead && (top->cpu_ad_drive || top->fpu_ad_drive)) { wdata = top->ad; wdriven = true; }
        // An undriven write (a store word the FPU did not have) leaves memory as it was.
        if (!dsLow && prevDsLow && !latRead && memStatus(latSt) && wdriven) memWrite(latAddr, wdata, latByte);
        prevDsLow = dsLow;
        uint32_t w = latAddr & 0xFFFFFE;
        bool drive = dsLow && latRead && memStatus(latSt) && top->busack_n && !top->cpu_ad_drive;
        top->mem_drive = drive;
        top->mem_data = drive ? (mapped(w) ? (uint16_t)(mem[w] << 8 | mem[w + 1]) : 0xFFFF) : 0;
    };
    // Seen by the chips at a pulse's master clock edge.
    CIn seen{};
    uint16_t seenAD = 0;
    bool viTaken = false;
    auto mtick = [&](bool sample) {
        top->clk = 0; top->eval();
        memBus(); top->eval();
        if (top->ad_clash) {
            // The FPU drives store data from the /AS rise while the CPU
            // still holds the address (the spec's drive edge).
            if (top->cpu_ad_drive && top->fpu_ad_drive && !top->mem_drive && top->as_n &&
                (latSt == 0xA || latSt == 0xB) && !latRead) overlaps++;
            else clashes++;
        }
        if (sample) {
            seen.stop_n = top->stop_n; seen.wait_n = top->wait_n; seen.vi_n = top->vi_n; seenAD = top->ad;
            viTaken = dut.viSampled();
        }
        dump();
        top->clk = 1; top->eval(); dump();
    };

    // Quiescent start, as the CPU bench: board inputs idle, one CLK edge.
    top->clk = 0; top->clk_rise = 1; top->clk_fall = 0; top->reset_n = 1;
    top->busreq_n = 1; top->nmi_n = 1; top->nvi_n = 1; top->segt_n = 1; top->abort_n = 1; top->mi_n = 1;
    top->fpu_id = 0; top->bsy_wait = 1; top->mem_data = 0; top->mem_drive = 0;
    mtick(false);
    top->clk_rise = 0;
    mtick(false);

    std::string line, variant;
    long tick = 0;
    bool prevClk = true;
    long mismTicks = 0, firstTick = -1;
    std::string firstPins;
    std::deque<std::string> ctx;
    std::vector<std::string> after;
    long finalFails = 0;
    std::string finalMsg;
    bool sawEnd = false, settled = false;
    std::vector<std::pair<uint32_t, uint16_t>> expW;
    std::map<uint32_t, uint16_t> expMem;
    bool sawFinalMem = false;
    // The last CLK=1 record, for the AD the CPU took at a read's T3 rise.
    struct { bool valid; CIn in; COut exp; uint16_t ad; } lastRise{};
    COut prevExp{}; bool havePrev = false;

    auto addRow = [&](const std::string& row, bool bad, const std::string& marks) {
        if (bad) {
            mismTicks++;
            if (firstTick < 0) { firstTick = tick; firstPins = marks; }
        }
        if (firstTick < 0) {
            ctx.push_back(row);
            if ((int)ctx.size() > context) ctx.pop_front();
        } else if ((int)after.size() < context + 1) {
            after.push_back(row);
        }
    };
    auto finalFail = [&](const std::string& m) { finalFails++; if (finalFails <= 20) finalMsg += "  final " + m + "\n"; };
    auto settle = [&]() { if (!settled) { for (int k = 0; k < 2; k++) mtick(false); settled = true; } };

    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ss(line);
        std::string tag; ss >> tag;
        if (tag == "K8000VEC") {
            int ver; std::string kind; ss >> ver >> kind;
            if (ver != 1 || kind != "cpufpu") { printf("RESULT FAIL %s: not a v1 cpufpu vector\n", vecPath.c_str()); return 4; }
        } else if (tag == "variant") {
            ss >> variant;
            if (variant != K8000_VARIANT) {
                printf("RESULT WRONGVARIANT %s: vector is %s, this binary is %s\n", vecPath.c_str(), variant.c_str(), K8000_VARIANT);
                return 3;
            }
        } else if (tag == "test") {
            continue;
        } else if (tag == "board") {
            std::string k; int v;
            while (ss >> k >> v) {
                if (k == "bsywait") top->bsy_wait = v != 0;
                else if (k == "fpuid") top->fpu_id = v & 3;
            }
            top->eval();
        } else if (tag == "mem") {
            std::string b, s; ss >> b >> s;
            maps.push_back({(uint32_t)strtoul(b.c_str(), nullptr, 16), (uint32_t)strtoul(s.c_str(), nullptr, 16)});
        } else if (tag == "X") {
            std::string why; std::getline(ss, why);
            printf("RESULT SKIP %s:%s\n", vecPath.c_str(), why.c_str());
            return 2;
        } else if (tag == "M") {
            std::string a, w; ss >> a >> w;
            uint32_t ad = strtoul(a.c_str(), nullptr, 16) & 0xFFFFFE; uint16_t v = strtoul(w.c_str(), nullptr, 16);
            mem[ad] = (uint8_t)(v >> 8); mem[ad + 1] = (uint8_t)v;
        } else if (tag == "W") {
            std::string a, w; ss >> a >> w;
            expW.push_back({(uint32_t)strtoul(a.c_str(), nullptr, 16), (uint16_t)strtoul(w.c_str(), nullptr, 16)});
        } else if (tag == "P") {
            std::string chip, what, h; ss >> chip >> what >> h;
            bool ok = chip == "C" ? dut.cpuPoke(what, strtoull(h.c_str(), nullptr, 16))
                    : chip == "E" ? dut.fpuPoke(what, V80::parse(h)) : false;
            if (!ok) { printf("RESULT SKIP %s: unsupported poke %s %s\n", vecPath.c_str(), chip.c_str(), what.c_str()); return 2; }
            top->eval();
        } else if (tag == "C") {
            std::string sInB, sInAD, sOutB, sOutAD, sSN, sST;
            ss >> sInB >> sInAD >> sOutB >> sOutAD >> sSN >> sST;
            CIn in = decodeCIn(strtoul(sInB.c_str(), nullptr, 16), strtoul(sInAD.c_str(), nullptr, 16));
            COut exp = decodeCOut(strtoul(sOutB.c_str(), nullptr, 16), strtoul(sOutAD.c_str(), nullptr, 16),
                                  strtoul(sSN.c_str(), nullptr, 16), strtoul(sST.c_str(), nullptr, 16));
            tick++;
            top->reset_n = in.reset_n; top->busreq_n = in.busreq_n; top->nmi_n = in.nmi_n; top->nvi_n = in.nvi_n;
            top->segt_n = in.segt_n; top->abort_n = in.abort_n; top->mi_n = in.mi_n;
            bool rising = in.clk && !prevClk, falling = !in.clk && prevClk;
            prevClk = in.clk;
            top->clk_rise = rising; top->clk_fall = falling;
            seen = in;
            for (int k = mclkSeq[mclkIdx]; k > 0; k--) {
                mtick(k == mclkSeq[mclkIdx]);
                top->clk_rise = 0; top->clk_fall = 0;
            }
            mclkIdx = (mclkIdx + 1) % mclkSeq.size();
            COut got = readCOut(top);
            std::string marks;
            auto cmp = [&](bool ok, const char* pin) { if (!ok) { if (!marks.empty()) marks += ","; marks += pin; } };
            const bool internalOp = exp.st == 0x0, refresh = exp.st == 0x1;
            const bool addressless = (exp.st >= 0x4 && exp.st <= 0x7) || exp.st == 0xE;
            cmp(exp.ad_drive == got.ad_drive, "ADDrive");
            cmp(exp.as_n == got.as_n, "AS_n");
            cmp(exp.ds_n == got.ds_n, "DS_n");
            cmp(exp.mreq_n == got.mreq_n, "MREQ_n");
            cmp(exp.r_w == got.r_w, "R_W");
            if (!internalOp) cmp(exp.b_w == got.b_w, "B_W");
            cmp(exp.n_s == got.n_s, "N_S");
            cmp(exp.st == got.st, "ST");
            cmp(exp.busack_n == got.busack_n, "BUSACK_n");
            cmp(exp.mo_n == got.mo_n, "MO_n");
            if (exp.ad_drive && got.ad_drive) {
                if (internalOp) { }
                else if (refresh) cmp((exp.ad & 0x01FF) == (got.ad & 0x01FF), "AD[8:0]");
                else if (addressless && !exp.as_n) { }
                else cmp(exp.ad == got.ad, "AD");
            }
            if (K8000_SEGMENTED && !exp.as_n && !internalOp && !refresh && !addressless) cmp(exp.sn == got.sn, "SN");
            if (in.reset_n) {
                if (falling) { cmp(seen.stop_n == in.stop_n, "STOP_n"); cmp(seen.wait_n == in.wait_n, "WAIT_n"); }
                if (rising && viTaken) cmp(seen.vi_n == in.vi_n, "VI_n");
                // A read's /DS rises on this fall: the rise before was T3.
                if (falling && havePrev && !prevExp.ds_n && exp.ds_n && prevExp.r_w && !prevExp.ad_drive && lastRise.valid)
                    cmp(lastRise.ad == lastRise.in.ad, "AD_in(T3)");
            }
            if (clashes) { cmp(false, "AD clash"); clashes = 0; }
            if (rising) lastRise = {true, in, exp, seenAD};
            prevExp = exp; havePrev = true;
            CIn seenRow = seen;
            addRow(cRow(tick, in, seenRow, exp, got, marks.empty() ? "" : "<-- " + marks), !marks.empty(), marks);
            if (stopFirst && firstTick >= 0) break;
        } else if (tag == "E") {
            std::string sIn, sAD, sST, sSN, sOut, sOAD;
            ss >> sIn >> sAD >> sST >> sSN >> sOut >> sOAD;
            unsigned ib = strtoul(sIn.c_str(), nullptr, 16), ob = strtoul(sOut.c_str(), nullptr, 16);
            if (!(ib >> 14 & 1) || !(ib >> 12 & 1)) continue;   // CLK.I=0 call, or /RESET Low
            EOut exp{(bool)(ob >> 3 & 1), (bool)(ob >> 2 & 1), (bool)(ob >> 1 & 1), (bool)(ob & 1),
                     (uint16_t)strtoul(sOAD.c_str(), nullptr, 16)};
            EOut got = readEOut(top);
            std::string marks;
            auto cmp = [&](bool ok, const char* pin) { if (!ok) { if (!marks.empty()) marks += ","; marks += pin; } };
            cmp(exp.ad_drive == got.ad_drive, "FPU ADDrive");
            cmp(exp.bsy_n == got.bsy_n, "BSY_n");
            cmp(exp.int_n == got.int_n, "INT_n");
            cmp(exp.ieo == got.ieo, "IEO");
            if (exp.ad_drive && got.ad_drive) cmp(exp.ad == got.ad, "FPU AD");
            addRow(eRow(tick, exp, got, marks.empty() ? "" : "<-- " + marks), !marks.empty(), marks);
            if (stopFirst && firstTick >= 0) break;
        } else if (tag == "F") {
            if (!checkFinal) continue;
            settle();
            std::string chip, what; ss >> chip;
            if (chip == "TICKS") continue;
            ss >> what;
            if (chip == "C" && what == "REGS") {
                for (int i = 0; i < 16; i++) {
                    std::string h; ss >> h;
                    if (h == "----") continue;
                    uint16_t e = strtoul(h.c_str(), nullptr, 16), g = dut.reg(i);
                    if (e != g) { char b[96]; snprintf(b, sizeof b, "CPU R%d exp=%04X got=%04X", i, e, g); finalFail(b); }
                }
            } else if (chip == "C") {
                std::string h; ss >> h; uint64_t e = strtoull(h.c_str(), nullptr, what == "HALTED" ? 10 : 16), g = 0;
                if (dut.cpuGet(what, g) && e != g) {
                    char b[96]; snprintf(b, sizeof b, "CPU %s exp=%llX got=%llX", what.c_str(), (unsigned long long)e, (unsigned long long)g);
                    finalFail(b);
                }
            } else if (chip == "E") {
                std::string h; ss >> h; V80 e = V80::parse(h), g;
                if (dut.fpuGet(what, g) && e != g) finalFail("FPU " + what + " exp=" + e.str() + " got=" + g.str());
            } else if (chip == "M") {
                std::string h; ss >> h;
                expMem[strtoul(what.c_str(), nullptr, 16) & 0xFFFFFE] = strtoul(h.c_str(), nullptr, 16);
                sawFinalMem = true;
            }
        } else if (tag == "END") {
            sawEnd = true;
            break;
        }
    }
#if VM_TRACE
    if (tfp) { tfp->close(); delete tfp; }
#endif
    top->final();

    if (!sawEnd && !(stopFirst && firstTick >= 0)) { printf("RESULT FAIL %s: truncated vector (no END)\n", vecPath.c_str()); return 4; }
    if (checkFinal && sawEnd) {
        if (sawFinalMem) {
            for (auto& m : maps)
                for (uint32_t a = m.first & 0xFFFFFE; a + 1 < m.first + m.second; a += 2) {
                    auto it = expMem.find(a);
                    uint16_t e = it == expMem.end() ? 0 : it->second, g = (uint16_t)(mem[a] << 8 | mem[a + 1]);
                    if (e != g) { char b[96]; snprintf(b, sizeof b, "MEM %06X exp=%04X got=%04X", a, e, g); finalFail(b); }
                }
        }
        if (gotW != expW) {
            char b[160];
            size_t i = 0;
            while (i < gotW.size() && i < expW.size() && gotW[i] == expW[i]) i++;
            snprintf(b, sizeof b, "memory writes: %zu expected, %zu seen, first difference at write %zu", expW.size(), gotW.size(), i);
            finalFail(b);
        }
    }
    delete top;

    if (firstTick < 0 && finalFails == 0) {
        printf("RESULT PASS %s %s ticks=%ld writes=%zu store-overlap=%ld\n", vecPath.c_str(), variant.c_str(), tick, gotW.size(), overlaps);
        return 0;
    }
    if (firstTick >= 0)
        printf("RESULT FAIL %s %s first-divergence tick=%ld pins=%s mismatched-records=%ld%s\n",
               vecPath.c_str(), variant.c_str(), firstTick, firstPins.c_str(), mismTicks,
               finalFails ? " final-state-mismatch" : "");
    else
        printf("RESULT FAIL %s %s pins-ok final-state-mismatch (%ld fields)\n", vecPath.c_str(), variant.c_str(), finalFails);
    if (!quiet) {
        if (firstTick >= 0) {
            printf("  ---- context: C rows: CLK RESET AD_in, inputs recorded | as seen, outputs expected | actual (RTL); E rows: FPU outputs expected | actual ----\n");
            printf("   tick   C R AD   SWv | SWv | Dr AS DS MRQ RW BW ST   AD   SN | Dr AS DS MRQ RW BW ST   AD   SN\n");
            for (auto& r : ctx) printf("%s\n", r.c_str());
            for (auto& r : after) printf("%s\n", r.c_str());
            printf("  (S=STOP W=WAIT v=VI Low)\n");
        }
        if (finalFails) printf("%s", finalMsg.c_str());
    }
    return 1;
}
