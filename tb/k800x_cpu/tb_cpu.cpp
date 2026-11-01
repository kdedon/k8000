// tb_cpu -- per-edge pin-equality replay of a Go-recorded CPU vector file
// against the Verilated z8000_cpu (FPGA_BIBLE 0.3 tier 1, lesson sv-46).
//
//   tb_cpu_<variant> <file.vec> [--context N] [--vcd out.vcd] [--quiet]
//                               [--stop-first] [--no-final]
//
// Exit codes: 0 PASS, 1 FAIL, 2 SKIP (unsupported vector), 3 wrong variant
// binary, 4 usage/parse error.
//
// The vector is a verbatim log of every Tick(Inputs) Outputs call a Go test
// made (see docs/VECTOR_FORMAT.md). Replay is OPEN LOOP: the recorded
// inputs are driven regardless of what the RTL does, and every output pin
// is compared after every Tick -- low sample (before the edge) and high
// sample (after it) alike, exactly the two-calls-per-clock convention.
// The first divergence names the tick, the clock, and the pin, and prints
// the surrounding ticks (expected | actual). It then keeps counting so you
// also learn how bad it is.
//
// AD is compared only when the Go model drives it (ADDrive=1) and the
// Product Spec defines it; SN only for SEGMENTED builds and only while /AS
// is low. Everything else always. See the tolerance windows in the compare
// block and docs/K800X_CPU_TESTS.md.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <deque>
#include <fstream>
#include <sstream>

#include "verilated.h"
#if VM_TRACE
#include "verilated_vcd_c.h"
#endif
#include "Vz8000_cpu.h"
#include "dut_access.h"

#ifndef K8000_VARIANT
#define K8000_VARIANT "Z8001"
#endif
#ifndef K8000_SEGMENTED
#define K8000_SEGMENTED 1
#endif

struct In {
    bool clk, reset_n, stop_n, wait_n, busreq_n, nmi_n, nvi_n, vi_n, segt_n, abort_n, mi_n;
    uint16_t ad;
};
struct Out {
    bool ad_drive, as_n, ds_n, mreq_n, r_w, b_w, n_s, busack_n, mo_n, bus_drive, bus_lock;
    uint16_t ad;
    uint8_t sn, st;
};

static In decodeIn(unsigned bits, unsigned ad) {
    In i;
    i.clk = bits >> 10 & 1; i.reset_n = bits >> 9 & 1; i.stop_n = bits >> 8 & 1;
    i.wait_n = bits >> 7 & 1; i.busreq_n = bits >> 6 & 1; i.nmi_n = bits >> 5 & 1;
    i.nvi_n = bits >> 4 & 1; i.vi_n = bits >> 3 & 1; i.segt_n = bits >> 2 & 1;
    i.abort_n = bits >> 1 & 1; i.mi_n = bits & 1; i.ad = ad;
    return i;
}
static Out decodeOut(unsigned bits, unsigned ad, unsigned sn, unsigned st) {
    Out o;
    o.ad_drive = bits >> 8 & 1; o.as_n = bits >> 7 & 1; o.ds_n = bits >> 6 & 1;
    o.mreq_n = bits >> 5 & 1; o.r_w = bits >> 4 & 1; o.b_w = bits >> 3 & 1;
    o.n_s = bits >> 2 & 1; o.busack_n = bits >> 1 & 1; o.mo_n = bits & 1;
    o.bus_drive = o.busack_n; // the strobes are driven whenever the bus is not granted
    o.bus_lock = false;
    o.ad = ad; o.sn = sn; o.st = st;
    return o;
}
static Out readOut(Vz8000_cpu* t) {
    Out o;
    o.ad_drive = t->ad_drive; o.as_n = t->as_n; o.ds_n = t->ds_n; o.mreq_n = t->mreq_n;
    o.r_w = t->r_w; o.b_w = t->b_w; o.n_s = t->n_s; o.busack_n = t->busack_n; o.mo_n = t->mo_n;
    o.bus_drive = t->bus_drive; o.bus_lock = t->bus_lock;
    o.ad = t->ad_out; o.sn = t->sn; o.st = t->st;
    return o;
}

static const char* stName(unsigned st) {
    static const char* n[16] = {"INT", "RFSH", "IO", "SIO", "SEGT", "NMIA", "NVIA", "VIA",
                                "DMEM", "SMEM", "DEPU", "SEPU", "PROG", "IF1", "EPUX", "LOCK"};
    return n[st & 15];
}

// One line of the context table.
static std::string fmtRow(long tick, long clock, const In& in, const Out& e, const Out& a,
                          const std::string& marks) {
    char buf[512];
    snprintf(buf, sizeof buf,
             "%7ld %6ld  %d %d %04X %c%c%c%c%c%c%c%c%c | %d %d %d %d %d %d %d %-4s %04X %02X | %d %d %d %d %d %d %d %-4s %04X %02X  %s",
             tick, clock, in.clk, in.reset_n, in.ad,
             in.stop_n ? '-' : 'S', in.wait_n ? '-' : 'W', in.busreq_n ? '-' : 'B', in.nmi_n ? '-' : 'N',
             in.nvi_n ? '-' : 'n', in.vi_n ? '-' : 'v', in.segt_n ? '-' : 'T', in.abort_n ? '-' : 'A', in.mi_n ? '-' : 'M',
             e.ad_drive, e.as_n, e.ds_n, e.mreq_n, e.r_w, e.b_w, e.n_s, stName(e.st), e.ad, e.sn,
             a.ad_drive, a.as_n, a.ds_n, a.mreq_n, a.r_w, a.b_w, a.n_s, stName(a.st), a.ad, a.sn,
             marks.c_str());
    return buf;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::string vecPath, vcdPath;
    int context = 12;
    bool quiet = false, stopFirst = false, checkFinal = true;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--context" && i + 1 < argc) context = atoi(argv[++i]);
        else if (a == "--vcd" && i + 1 < argc) vcdPath = argv[++i];
        else if (a == "--quiet") quiet = true;
        else if (a == "--stop-first") stopFirst = true;
        else if (a == "--no-final") checkFinal = false;
        else if (a[0] == '-' && a[1] == '-') { fprintf(stderr, "unknown option %s\n", a.c_str()); return 4; }
        else vecPath = a;
    }
    if (vecPath.empty()) { fprintf(stderr, "usage: tb_cpu <file.vec> [--context N] [--vcd f] [--quiet] [--stop-first] [--no-final]\n"); return 4; }

    std::ifstream f(vecPath);
    if (!f) { printf("RESULT FAIL %s: cannot open\n", vecPath.c_str()); return 4; }

    Vz8000_cpu* top = new Vz8000_cpu;
    DutAccess dut(top);
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

    // Quiescent start: DefaultInputs (all active-low high, CLK high), no reset yet.
    top->clk = 1; top->reset_n = 1; top->ad_in = 0; top->stop_n = 1; top->wait_n = 1; top->busreq_n = 1;
    top->nmi_n = 1; top->nvi_n = 1; top->vi_n = 1; top->segt_n = 1; top->abort_n = 1; top->mi_n = 1;
    top->eval();
    dump();

    std::string line, variant, testName, hint;
    long tick = 0, clock = 0;
    bool prevClk = true;
    long mismTicks = 0, firstTick = -1, firstClock = -1;
    std::string firstPins;
    std::deque<std::string> ctx;      // rows before the divergence
    std::vector<std::string> after;   // rows after it
    long finalFails = 0;
    std::string finalMsg;
    bool sawEnd = false;

    // Pokes are applied to the model, then settled with an eval() at the
    // current clock level (the Go test wrote state between two Ticks).
    auto poke = [&](const std::string& what, uint64_t v) -> bool {
        if (what.size() >= 2 && what[0] == 'R' && isdigit((unsigned char)what[1])) { dut.set_reg(atoi(what.c_str() + 1), (uint16_t)v); }
        else if (what == "FCW") dut.set_fcw((uint16_t)v);
        else if (what == "PC") dut.set_pc((uint32_t)v);
        else if (what == "PSAP") dut.set_psap((uint32_t)v);
        else if (what == "REFRESH") dut.set_refresh((uint16_t)v);
        else if (what == "NSPOFF") dut.set_nspoff((uint16_t)v);
        else if (what == "NSPSEG") dut.set_nspseg((uint16_t)v);
        else if (what == "REFRESH_EN") dut.set_refresh_en(v != 0);
        else return false;
        top->eval();
        return true;
    };

    while (std::getline(f, line)) {
        if (line.empty()) continue;
        if (line[0] == '#') {
            if (line.rfind("# hint:", 0) == 0) hint = line.substr(8);
            continue;
        }
        std::istringstream ss(line);
        std::string tag; ss >> tag;
        if (tag == "K8000VEC") {
            int ver; std::string kind; ss >> ver >> kind;
            if (ver != 1 || kind != "cpu") { printf("RESULT FAIL %s: not a v1 cpu vector\n", vecPath.c_str()); return 4; }
        } else if (tag == "variant") {
            ss >> variant;
            if (variant != K8000_VARIANT) {
                printf("RESULT WRONGVARIANT %s: vector is %s, this binary is %s\n", vecPath.c_str(), variant.c_str(), K8000_VARIANT);
                return 3;
            }
        } else if (tag == "test") {
            std::string n; int idx; ss >> n >> idx; testName = n;
        } else if (tag == "X") {
            std::string why; std::getline(ss, why);
            printf("RESULT SKIP %s:%s\n", vecPath.c_str(), why.c_str());
            return 2;
        } else if (tag == "P") {
            std::string what, hex; ss >> what >> hex;
            uint64_t v = strtoull(hex.c_str(), nullptr, 16);
            if (!poke(what, v)) { printf("RESULT SKIP %s: unsupported poke %s\n", vecPath.c_str(), what.c_str()); return 2; }
        } else if (tag == "T") {
            std::string sInB, sInAD, sOutB, sOutAD, sSN, sST;
            ss >> sInB >> sInAD >> sOutB >> sOutAD >> sSN >> sST;
            In in = decodeIn(strtoul(sInB.c_str(), nullptr, 16), strtoul(sInAD.c_str(), nullptr, 16));
            Out exp = decodeOut(strtoul(sOutB.c_str(), nullptr, 16), strtoul(sOutAD.c_str(), nullptr, 16),
                                strtoul(sSN.c_str(), nullptr, 16), strtoul(sST.c_str(), nullptr, 16));
            tick++;
            // drive inputs
            top->reset_n = in.reset_n; top->ad_in = in.ad; top->stop_n = in.stop_n; top->wait_n = in.wait_n;
            top->busreq_n = in.busreq_n; top->nmi_n = in.nmi_n; top->nvi_n = in.nvi_n; top->vi_n = in.vi_n;
            top->segt_n = in.segt_n; top->abort_n = in.abort_n; top->mi_n = in.mi_n;
            bool rising = in.clk && !prevClk;
            prevClk = in.clk;
            top->clk = in.clk;
            top->eval();          // one Tick == inputs applied, (maybe) one posedge, outputs settled
            dump();
            if (rising) clock++;
            Out got = readOut(top);
            // compare
            std::string marks;
            auto cmp = [&](bool ok, const char* pin) { if (!ok) { if (!marks.empty()) marks += ","; marks += pin; } };
            // Spec-tolerance windows (docs/K800X_CPU_TESTS.md "Spec conformance
            // ledger"): pins the Product Spec leaves undefined are not
            // compared there, so an RTL that differs from the Go model's
            // deterministic stand-in value is not penalised.
            //   ST=0000 internal operation (Fig 17): AD undefined, B/W
            //     undefined.
            //   ST=0001 refresh (Fig 18): AD9-15 undefined (row on AD0-8).
            //   ST=0100..0111 acknowledge, ST=1110 EPU transfer: no address
            //     is generated -- AD is not compared while /AS is low.
            //   SN (Fig 12): valid from ~one clock before the address until
            //     early T2, so it is compared only while /AS is low; the
            //     silicon (and an RTL) may drive it a clock earlier than the
            //     Go model does.
            const bool internalOp = exp.st == 0x0;
            const bool refresh = exp.st == 0x1;
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
            cmp(exp.bus_drive == got.bus_drive, "BusDrive");
            cmp(!(got.bus_lock && !got.busack_n), "BusLock"); // no grant while locked
            cmp(exp.mo_n == got.mo_n, "MO_n");
            if (exp.ad_drive && got.ad_drive) {
                if (internalOp) { /* undefined */ }
                else if (refresh) cmp((exp.ad & 0x01FF) == (got.ad & 0x01FF), "AD[8:0]");
                else if (addressless && !exp.as_n) { /* no address generated */ }
                else cmp(exp.ad == got.ad, "AD");
            }
            if (K8000_SEGMENTED && !exp.as_n && !internalOp && !refresh && !addressless) cmp(exp.sn == got.sn, "SN");
            std::string row = fmtRow(tick, clock, in, exp, got, marks.empty() ? "" : "<-- " + marks);
            if (!marks.empty()) {
                mismTicks++;
                if (firstTick < 0) { firstTick = tick; firstClock = clock; firstPins = marks; }
            }
            if (firstTick < 0) {
                ctx.push_back(row);
                if ((int)ctx.size() > context) ctx.pop_front();
            } else if ((int)after.size() < context + 1) {
                after.push_back(row);
            }
            if (stopFirst && firstTick >= 0) break;
        } else if (tag == "F") {
            if (!checkFinal) continue;
            std::string what; ss >> what;
            auto fail = [&](const std::string& m) { finalFails++; if (finalFails <= 20) finalMsg += "  final " + m + "\n"; };
            if (what == "REGS") {
                for (int i = 0; i < 16; i++) {
                    std::string h; ss >> h;
                    if (h == "----") continue;   // left undefined
                    uint16_t e = strtoul(h.c_str(), nullptr, 16), g = dut.reg(i);
                    if (e != g) { char b[96]; snprintf(b, sizeof b, "R%d exp=%04X got=%04X", i, e, g); fail(b); }
                }
            } else {
                std::string h; ss >> h; uint64_t e = strtoull(h.c_str(), nullptr, 16); uint64_t g = 0; bool known = true;
                if (what == "FCW") g = dut.fcw();
                else if (what == "PC") g = dut.pc();
                else if (what == "PSAP") g = dut.psap();
                else if (what == "REFRESH") g = dut.refresh();
                else if (what == "NSPOFF") g = dut.nspoff();
                else if (what == "NSPSEG") g = dut.nspseg();
                else if (what == "HALTED") { e = strtoull(h.c_str(), nullptr, 10); g = dut.halted(); }
                else known = false;   // CYCLES / TICKS are informational
                if (known && e != g) { char b[96]; snprintf(b, sizeof b, "%s exp=%llX got=%llX", what.c_str(), (unsigned long long)e, (unsigned long long)g); fail(b); }
            }
        } else if (tag == "END") {
            sawEnd = true;
            break;
        }
    }
#if VM_TRACE
    if (tfp) { tfp->close(); delete tfp; }
#endif
    const bool unhandled = dut.unhandled_cycle();
    const bool checkFail = dut.execute_check();
    top->final();
    delete top;

    if (!sawEnd && !(stopFirst && firstTick >= 0)) { printf("RESULT FAIL %s: truncated vector (no END)\n", vecPath.c_str()); return 4; }

    bool pass = firstTick < 0 && finalFails == 0 && !unhandled && !checkFail;
    if (pass) {
        printf("RESULT PASS %s ticks=%ld clocks=%ld\n", vecPath.c_str(), tick, clock);
        return 0;
    }
    if (firstTick >= 0)
        printf("RESULT FAIL %s first-divergence tick=%ld clock=%ld pins=%s mismatched-ticks=%ld/%ld%s\n",
               vecPath.c_str(), firstTick, firstClock, firstPins.c_str(), mismTicks, tick,
               finalFails ? " final-state-mismatch" : "");
    else if (finalFails)
        printf("RESULT FAIL %s pins-ok final-state-mismatch (%ld fields)\n", vecPath.c_str(), finalFails);
    else if (unhandled)
        printf("RESULT FAIL %s pins-ok unhandled-machine-cycle\n", vecPath.c_str());
    else
        printf("RESULT FAIL %s pins-ok execute-check\n", vecPath.c_str());
    if (!quiet) {
        if (!hint.empty()) printf("  program: %s\n", hint.c_str());
        if (firstTick >= 0) {
            printf("  ---- context: inputs | expected (Go) | actual (RTL) ----\n");
            printf("   tick  clock  C R AD_in SWBNnvTAM | drv AS DS MRQ RW BW NS ST   AD   SN | drv AS DS MRQ RW BW NS ST   AD   SN\n");
            for (auto& r : ctx) printf("%s\n", r.c_str());
            for (auto& r : after) printf("%s\n", r.c_str());
            printf("  (input flags: letter = asserted low: S=STOP W=WAIT B=BUSREQ N=NMI n=NVI v=VI T=SEGT A=ABORT M=MI)\n");
        }
        if (finalFails) printf("%s", finalMsg.c_str());
    }
    return 1;
}
