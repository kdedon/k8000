// tb_scc -- per-record pin-equality replay of a Go-recorded Z8030 SCC vector
// file against the Verilated z8030_scc (FPGA_BIBLE 0.3 tier 1, Ch.5).
//
//   tb_scc <file.vec> [--context N] [--vcd out.vcd] [--quiet]
//                     [--stop-first] [--no-final]
//
// Exit codes: 0 PASS, 1 FAIL, 2 SKIP (unsupported vector / poke), 4
// usage/parse error.
//
// The vector is a verbatim log of every TickPins(Inputs) Outputs call a
// Go test made (see docs/K8030_SCC_TESTS.md). Replay is OPEN LOOP: the recorded
// inputs are driven regardless of what the RTL does. One T record == one
// posedge of the fabric clock `clk`; PCLK is a recorded LEVEL input and
// the RTL derives its own pclk_rise enable, exactly like the Go model's
// pinPrevPCLK. Every output pin is compared after every record.
//
// Comparison rules (docs/K8030_SCC_TESTS.md "What is compared"):
//   always:  ADDrive INT_n IEO TxD[A/B] RTS_n[A/B] DTR_n[A/B]
//            TRxCDrive[A/B] SYNCDrive[A/B]
//   AD       only while BOTH models drive it (Go ADDrive && RTL ad_drive)
//   TRxCOut  only while the Go model drives it (TRxCDrive)
//   SYNCOut  only while the Go model drives it (never, today)
// P records poke the register inventory through tb/k8030_scc/scc_access.h before
// the next record; F records compare it after the last one.

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
#include "Vz8030_scc.h"
#include "scc_access.h"

struct In {
    bool pclk, as_n, ds_n, r_w, cs0_n, cs1, intack_n, iei;
    bool rxd[2], cts_n[2], dcd_n[2], trxc[2], txc[2], rxc[2], sync[2];
    uint8_t ad;
};
struct Out {
    bool ad_drive, int_n, ieo;
    bool txd[2], rts_n[2], dtr_n[2], trxc_out[2], trxc_drive[2], sync_out[2], sync_drive[2];
    uint8_t ad;
};

// Bit orders == sim/scc/vecdump_test.go vecInBits / vecOutBits.
static In decodeIn(unsigned bits, unsigned ad) {
    In i;
    i.pclk = bits >> 21 & 1; i.as_n = bits >> 20 & 1; i.ds_n = bits >> 19 & 1; i.r_w = bits >> 18 & 1;
    i.cs0_n = bits >> 17 & 1; i.cs1 = bits >> 16 & 1; i.intack_n = bits >> 15 & 1; i.iei = bits >> 14 & 1;
    i.rxd[0] = bits >> 13 & 1; i.rxd[1] = bits >> 12 & 1;
    i.cts_n[0] = bits >> 11 & 1; i.cts_n[1] = bits >> 10 & 1;
    i.dcd_n[0] = bits >> 9 & 1; i.dcd_n[1] = bits >> 8 & 1;
    i.trxc[0] = bits >> 7 & 1; i.trxc[1] = bits >> 6 & 1;
    i.txc[0] = bits >> 5 & 1; i.txc[1] = bits >> 4 & 1;
    i.rxc[0] = bits >> 3 & 1; i.rxc[1] = bits >> 2 & 1;
    i.sync[0] = bits >> 1 & 1; i.sync[1] = bits & 1;
    i.ad = (uint8_t)ad;
    return i;
}
static Out decodeOut(unsigned bits, unsigned ad) {
    Out o;
    o.ad_drive = bits >> 16 & 1; o.int_n = bits >> 15 & 1; o.ieo = bits >> 14 & 1;
    o.txd[0] = bits >> 13 & 1; o.txd[1] = bits >> 12 & 1;
    o.rts_n[0] = bits >> 11 & 1; o.rts_n[1] = bits >> 10 & 1;
    o.dtr_n[0] = bits >> 9 & 1; o.dtr_n[1] = bits >> 8 & 1;
    o.trxc_out[0] = bits >> 7 & 1; o.trxc_out[1] = bits >> 6 & 1;
    o.trxc_drive[0] = bits >> 5 & 1; o.trxc_drive[1] = bits >> 4 & 1;
    o.sync_out[0] = bits >> 3 & 1; o.sync_out[1] = bits >> 2 & 1;
    o.sync_drive[0] = bits >> 1 & 1; o.sync_drive[1] = bits & 1;
    o.ad = (uint8_t)ad;
    return o;
}
static Out readOut(Vz8030_scc* t) {
    Out o;
    o.ad_drive = t->ad_drive; o.int_n = t->int_n; o.ieo = t->ieo; o.ad = t->ad_out;
    for (int c = 0; c < 2; c++) {
        o.txd[c] = t->txd >> c & 1; o.rts_n[c] = t->rts_n >> c & 1; o.dtr_n[c] = t->dtr_n >> c & 1;
        o.trxc_out[c] = t->trxc_out >> c & 1; o.trxc_drive[c] = t->trxc_drive >> c & 1;
        o.sync_out[c] = t->sync_out >> c & 1; o.sync_drive[c] = t->sync_drive >> c & 1;
    }
    return o;
}
static void driveIn(Vz8030_scc* t, const In& i) {
    t->pclk = i.pclk; t->as_n = i.as_n; t->ds_n = i.ds_n; t->r_w = i.r_w; t->cs0_n = i.cs0_n; t->cs1 = i.cs1;
    t->intack_n = i.intack_n; t->iei = i.iei; t->ad_in = i.ad;
    t->rxd = (i.rxd[1] << 1) | i.rxd[0]; t->cts_n = (i.cts_n[1] << 1) | i.cts_n[0];
    t->dcd_n = (i.dcd_n[1] << 1) | i.dcd_n[0]; t->trxc_in = (i.trxc[1] << 1) | i.trxc[0];
    t->txc_in = (i.txc[1] << 1) | i.txc[0]; t->rxc_in = (i.rxc[1] << 1) | i.rxc[0];
    t->sync_in = (i.sync[1] << 1) | i.sync[0];
}

// One line of the context table.
static std::string fmtOut(const Out& o) {
    char b[64];
    snprintf(b, sizeof b, "%d %d %d %d%d %d%d %d%d %d%d %02X",
             o.ad_drive, o.int_n, o.ieo, o.txd[0], o.txd[1], o.rts_n[0], o.rts_n[1],
             o.dtr_n[0], o.dtr_n[1], o.trxc_drive[0], o.trxc_drive[1], o.ad);
    return b;
}
static std::string fmtRow(long tick, long pclks, const In& in, const Out& e, const Out& a, const std::string& marks) {
    char buf[512];
    snprintf(buf, sizeof buf, "%7ld %6ld  %d %c%c%c%c%c%c%c %02X %d%d %d%d %d%d %d%d | %s | %s  %s",
             tick, pclks, in.pclk,
             in.as_n ? '-' : 'A', in.ds_n ? '-' : 'D', in.r_w ? 'R' : 'W', in.cs0_n ? '-' : 'c',
             in.cs1 ? 'C' : '-', in.intack_n ? '-' : 'I', in.iei ? 'e' : '-',
             in.ad, in.rxd[0], in.rxd[1], in.cts_n[0], in.cts_n[1], in.dcd_n[0], in.dcd_n[1],
             in.rxc[0], in.trxc[0],
             fmtOut(e).c_str(), fmtOut(a).c_str(), marks.c_str());
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
        else if (a.size() > 1 && a[0] == '-' && a[1] == '-') { fprintf(stderr, "unknown option %s\n", a.c_str()); return 4; }
        else vecPath = a;
    }
    if (vecPath.empty()) { fprintf(stderr, "usage: tb_scc <file.vec> [--context N] [--vcd f] [--quiet] [--stop-first] [--no-final]\n"); return 4; }

    std::ifstream f(vecPath);
    if (!f) { printf("RESULT FAIL %s: cannot open\n", vecPath.c_str()); return 4; }

    Vz8030_scc* top = new Vz8030_scc;
    SccAccess dut(top);
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

    // Quiescent start == Go defaultInputs(): strobes negated, deselected,
    // serial lines marking, PCLK low. No reset pin: the RTL powers up in
    // the Go New() state.
    In idle{}; idle.pclk = false; idle.as_n = idle.ds_n = idle.cs0_n = idle.intack_n = idle.iei = true;
    idle.r_w = true; idle.cs1 = false; idle.ad = 0;
    for (int c = 0; c < 2; c++) { idle.rxd[c] = idle.cts_n[c] = idle.dcd_n[c] = true; }
    driveIn(top, idle);
    top->clk = 0;
    top->eval();
    dump();

    std::string line, testName;
    long tick = 0, pclks = 0;
    bool prevPclk = false;
    long mismTicks = 0, firstTick = -1, firstPclk = -1;
    std::string firstPins;
    std::deque<std::string> ctx;
    std::vector<std::string> after;
    long finalFails = 0;
    std::string finalMsg;
    bool sawEnd = false;
    long pokes = 0;

    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ss(line);
        std::string tag; ss >> tag;
        if (tag == "K8000VEC") {
            int ver; std::string kind; ss >> ver >> kind;
            if (ver != 1 || kind != "scc") { printf("RESULT FAIL %s: not a v1 scc vector\n", vecPath.c_str()); return 4; }
        } else if (tag == "test") {
            std::string n; int idx; ss >> n >> idx; testName = n;
        } else if (tag == "base") {
            // Port-decode facade only; chip select is a pin on the seam.
        } else if (tag == "X") {
            std::string why; std::getline(ss, why);
            printf("RESULT SKIP %s:%s\n", vecPath.c_str(), why.c_str());
            return 2;
        } else if (tag == "P") {
            std::string what, hex; ss >> what >> hex;
            uint64_t v = strtoull(hex.c_str(), nullptr, 16);
            if (!dut.poke(what, v)) { printf("RESULT SKIP %s: unsupported poke %s\n", vecPath.c_str(), what.c_str()); return 2; }
            pokes++;
            top->eval();   // settle combinational outputs on the poked state
        } else if (tag == "T") {
            std::string sInB, sInAD, sOutB, sOutAD;
            ss >> sInB >> sInAD >> sOutB >> sOutAD;
            In in = decodeIn(strtoul(sInB.c_str(), nullptr, 16), strtoul(sInAD.c_str(), nullptr, 16));
            Out exp = decodeOut(strtoul(sOutB.c_str(), nullptr, 16), strtoul(sOutAD.c_str(), nullptr, 16));
            tick++;
            if (in.pclk && !prevPclk) pclks++;
            prevPclk = in.pclk;
            // One TickPins call == one fabric clock: drive the recorded
            // inputs, take a posedge, settle, compare.
            top->clk = 0; top->eval(); dump();
            driveIn(top, in);
            top->clk = 1; top->eval(); dump();
            Out got = readOut(top);
            std::string marks;
            auto cmp = [&](bool ok, const char* pin) { if (!ok) { if (!marks.empty()) marks += ","; marks += pin; } };
            cmp(exp.ad_drive == got.ad_drive, "ADDrive");
            cmp(exp.int_n == got.int_n, "INT_n");
            cmp(exp.ieo == got.ieo, "IEO");
            cmp(exp.txd[0] == got.txd[0], "TxD_A");
            cmp(exp.txd[1] == got.txd[1], "TxD_B");
            cmp(exp.rts_n[0] == got.rts_n[0], "RTS_n_A");
            cmp(exp.rts_n[1] == got.rts_n[1], "RTS_n_B");
            cmp(exp.dtr_n[0] == got.dtr_n[0], "DTR_n_A");
            cmp(exp.dtr_n[1] == got.dtr_n[1], "DTR_n_B");
            cmp(exp.trxc_drive[0] == got.trxc_drive[0], "TRxCDrive_A");
            cmp(exp.trxc_drive[1] == got.trxc_drive[1], "TRxCDrive_B");
            cmp(exp.sync_drive[0] == got.sync_drive[0], "SYNCDrive_A");
            cmp(exp.sync_drive[1] == got.sync_drive[1], "SYNCDrive_B");
            if (exp.trxc_drive[0]) cmp(exp.trxc_out[0] == got.trxc_out[0], "TRxCOut_A");
            if (exp.trxc_drive[1]) cmp(exp.trxc_out[1] == got.trxc_out[1], "TRxCOut_B");
            if (exp.sync_drive[0]) cmp(exp.sync_out[0] == got.sync_out[0], "SYNCOut_A");
            if (exp.sync_drive[1]) cmp(exp.sync_out[1] == got.sync_out[1], "SYNCOut_B");
            if (exp.ad_drive && got.ad_drive) cmp(exp.ad == got.ad, "AD");
            std::string row = fmtRow(tick, pclks, in, exp, got, marks.empty() ? "" : "<-- " + marks);
            if (!marks.empty()) {
                mismTicks++;
                if (firstTick < 0) { firstTick = tick; firstPclk = pclks; firstPins = marks; }
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
            std::string what, hex; ss >> what >> hex;
            if (what == "TICKS" || what == "POKES") continue;   // informational
            uint64_t e = strtoull(hex.c_str(), nullptr, 16), g = 0;
            auto fail = [&](const std::string& m) { finalFails++; if (finalFails <= 24) finalMsg += "  final " + m + "\n"; };
            if (!dut.peek(what, g)) { fail(what + " (unknown to scc_access.h)"); continue; }
            if (e != g) { char b[128]; snprintf(b, sizeof b, "%s exp=%llX got=%llX", what.c_str(), (unsigned long long)e, (unsigned long long)g); fail(b); }
        } else if (tag == "END") {
            sawEnd = true;
            break;
        }
    }
#if VM_TRACE
    if (tfp) { tfp->close(); delete tfp; }
#endif
    top->final();
    delete top;

    if (!sawEnd && !(stopFirst && firstTick >= 0)) { printf("RESULT FAIL %s: truncated vector (no END)\n", vecPath.c_str()); return 4; }

    bool pass = firstTick < 0 && finalFails == 0;
    if (pass) {
        printf("RESULT PASS %s ticks=%ld pclks=%ld pokes=%ld\n", vecPath.c_str(), tick, pclks, pokes);
        return 0;
    }
    if (firstTick >= 0)
        printf("RESULT FAIL %s first-divergence tick=%ld pclk=%ld pins=%s mismatched-ticks=%ld/%ld%s\n",
               vecPath.c_str(), firstTick, firstPclk, firstPins.c_str(), mismTicks, tick,
               finalFails ? " final-state-mismatch" : "");
    else
        printf("RESULT FAIL %s pins-ok final-state-mismatch (%ld fields)\n", vecPath.c_str(), finalFails);
    if (!quiet) {
        if (firstTick >= 0) {
            printf("  ---- context: inputs | expected (Go) | actual (RTL) ----\n");
            printf("   tick   pclk  P ADRcCIe AD Rx CT DC XT | drv INT IEO TxD RTS DTR TRxC AD | drv INT IEO TxD RTS DTR TRxC AD\n");
            for (auto& r : ctx) printf("%s\n", r.c_str());
            for (auto& r : after) printf("%s\n", r.c_str());
            printf("  (inputs: A=/AS low D=/DS low R/W c=/CS0 low C=CS1 high I=/INTACK low e=IEI high;\n");
            printf("   Rx/CT/DC = RxD CTS_n DCD_n for A,B; XT = RxC_A TRxC_A; per-channel outputs listed A then B)\n");
        }
        if (finalFails) printf("%s", finalMsg.c_str());
    }
    return 1;
}
