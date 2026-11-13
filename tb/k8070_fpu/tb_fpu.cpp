// tb_fpu -- per-record pin-equality replay of a Z8070 vector
// file against the Verilated z8070_fpu.
//
//   tb_fpu <file.vec> [--context N] [--vcd out.vcd] [--quiet]
//                     [--stop-first] [--no-final] [--mclk P] [--fastd]
//
// The chip runs on the board master clock `clk`. CLK.I is two pulses,
// clki_rise and clki_fall, and CLK.D one, clkd_rise: each High for the
// first master clock of a record whose level changed that way. Each record
// gets the next count of master clocks from the pattern P (comma list,
// cycled; default K8000_MCLK or "1,2,1,3").
//
// Replay is open loop: the recorded inputs are driven whatever the RTL
// does, and after each record ADDrive, BSY_n, INT_n and IEO are compared,
// AD too while both sides drive it. The first divergence prints the
// records around it (expected | actual); counting goes on.
//
// Final F records are compared, and P records applied, after two idle
// master clocks, for the registers the RTL holds; the rest are listed as
// unchecked on the RESULT line. A P record for a register
// the RTL does not hold, or an X record, makes the vector a SKIP.
//
// --fastd: CLK.D rises every master clock, as on a board that clocks it
// at the master clock. The Data Processor then runs ahead of the vector,
// so pins are not compared; the word driven at the end of each /DS Low
// window is, in order, with the final state but PC2 (an IF1 while busy
// loads it, so it depends on the speed).
//
// Exit codes: 0 PASS, 1 FAIL, 2 SKIP, 4 usage or parse error.

#include <cstdio>
#include <cstdlib>
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
#include "Vz8070_fpu.h"
#include "fpu_access.h"

struct In {
    bool clki, clkd, reset_n, as_n, ds_n, r_w, b_w, n_s, busack_n, abort_n, iei;
    uint8_t id, opt, st, sn;
    uint16_t ad;
};
struct Out {
    bool ad_drive, bsy_n, int_n, ieo;
    uint16_t ad;
};

// Input bit order (MSB first): CLKI CLKD RESET_n AS_n DS_n R_W B_W N_S
// BUSACK_n ABORT_n IEI ID1 ID0 OPT1 OPT0
static In decodeIn(unsigned b, unsigned ad, unsigned st, unsigned sn) {
    In i;
    i.clki = b >> 14 & 1; i.clkd = b >> 13 & 1; i.reset_n = b >> 12 & 1; i.as_n = b >> 11 & 1;
    i.ds_n = b >> 10 & 1; i.r_w = b >> 9 & 1; i.b_w = b >> 8 & 1; i.n_s = b >> 7 & 1;
    i.busack_n = b >> 6 & 1; i.abort_n = b >> 5 & 1; i.iei = b >> 4 & 1;
    i.id = b >> 2 & 3; i.opt = b & 3;
    i.ad = ad; i.st = st & 15; i.sn = sn & 0x7F;
    return i;
}
// Output bit order (MSB first): ADDrive BSY_n INT_n IEO
static Out decodeOut(unsigned b, unsigned ad) {
    Out o;
    o.ad_drive = b >> 3 & 1; o.bsy_n = b >> 2 & 1; o.int_n = b >> 1 & 1; o.ieo = b & 1;
    o.ad = ad;
    return o;
}
static Out readOut(Vz8070_fpu* t) {
    Out o;
    o.ad_drive = t->ad_drive; o.bsy_n = t->bsy_n; o.int_n = t->int_n; o.ieo = t->ieo;
    o.ad = t->ad_out;
    return o;
}

static const char* stName(unsigned st) {
    static const char* n[16] = {"INT", "RFSH", "IO", "SIO", "SEGT", "NMIA", "NVIA", "VIA",
                                "DMEM", "SMEM", "DEPU", "SEPU", "PROG", "IF1", "EPUX", "LOCK"};
    return n[st & 15];
}

static std::string fmtRow(long tick, long clock, const In& in, const Out& e, const Out& a,
                          const std::string& marks) {
    char buf[512];
    snprintf(buf, sizeof buf,
             "%7ld %6ld  %d%d %d %c%c %c%c%c %c%c %d %d%d %04X %02X %-4s | %d %d %d %d %04X | %d %d %d %d %04X  %s",
             tick, clock, in.clki, in.clkd, in.reset_n,
             in.as_n ? '-' : 'A', in.ds_n ? '-' : 'D', in.r_w ? 'R' : 'W', in.b_w ? 'B' : 'W',
             in.n_s ? 'N' : 'S', in.busack_n ? '-' : 'K', in.abort_n ? '-' : 'X', in.iei,
             in.id, in.opt, in.ad, in.sn, stName(in.st),
             e.ad_drive, e.bsy_n, e.int_n, e.ieo, e.ad,
             a.ad_drive, a.bsy_n, a.int_n, a.ieo, a.ad, marks.c_str());
    return buf;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::string vecPath, vcdPath;
    int context = 12;
    bool quiet = false, stopFirst = false, checkFinal = true, fastd = false;
    std::string mclkPat = getenv("K8000_MCLK") ? getenv("K8000_MCLK") : "1,2,1,3";
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--context" && i + 1 < argc) context = atoi(argv[++i]);
        else if (a == "--vcd" && i + 1 < argc) vcdPath = argv[++i];
        else if (a == "--quiet") quiet = true;
        else if (a == "--stop-first") stopFirst = true;
        else if (a == "--no-final") checkFinal = false;
        else if (a == "--fastd") fastd = true;
        else if (a == "--mclk" && i + 1 < argc) mclkPat = argv[++i];
        else if (a.size() > 1 && a[0] == '-' && a[1] == '-') { fprintf(stderr, "unknown option %s\n", a.c_str()); return 4; }
        else vecPath = a;
    }
    if (vecPath.empty()) { fprintf(stderr, "usage: tb_fpu <file.vec> [--context N] [--vcd f] [--quiet] [--stop-first] [--no-final] [--mclk P] [--fastd]\n"); return 4; }

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

    Vz8070_fpu* top = new Vz8070_fpu;
    FpuAccess dut(top);
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
    auto mtick = [&]() { top->clk = 0; top->eval(); dump(); top->clk = 1; top->eval(); dump(); };

    // Quiescent start: no reset yet, bus idle, both
    // clocks Low, so a first record with a clock High is a rise.
    top->clk = 0; top->clki_rise = 0; top->clki_fall = 0; top->clkd_rise = 0;
    top->reset_n = 1; top->ad_in = 0; top->as_n = 1; top->ds_n = 1; top->r_w = 1; top->b_w = 0;
    top->n_s = 0; top->st = 0; top->sn = 0; top->busack_n = 1; top->abort_n = 1; top->iei = 1;
    top->id = 0; top->opt = 3;
    for (int k = 0; k < 2; k++) mtick();

    std::string line;
    long tick = 0, clock = 0;
    bool prevClki = false, prevClkd = false;
    long mismTicks = 0, firstTick = -1, firstClock = -1;
    std::string firstPins;
    std::deque<std::string> ctx;
    std::vector<std::string> after;
    long finalFails = 0;
    std::string finalMsg, unchecked;
    std::string skipWhy;   // an unsupported poke: an X record later still names the reason
    bool sawEnd = false;
    bool settled = false;
    // The RAM writes that follow a done (F, FOP2) land in the next two
    // master clocks; idle clocks move nothing else, so pokes and the final
    // compare wait for them.
    auto settle = [&]() { for (int k = 0; k < 2; k++) { top->clkd_rise = fastd; mtick(); } top->clkd_rise = 0; };
    // --fastd: the word driven last in each /DS Low window, -1 for none.
    std::vector<int> expWords, gotWords;
    bool prevDsLow = false;
    int expW = -1, gotW = -1;

    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ss(line);
        std::string tag; ss >> tag;
        if (tag == "K8000VEC") {
            int ver; std::string kind; ss >> ver >> kind;
            if (ver != 1 || kind != "fpu") { printf("RESULT FAIL %s: not a v1 fpu vector\n", vecPath.c_str()); return 4; }
        } else if (tag == "test") {
            continue;
        } else if (tag == "X") {
            std::string why; std::getline(ss, why);
            printf("RESULT SKIP %s:%s\n", vecPath.c_str(), why.c_str());
            return 2;
        } else if (tag == "P") {
            std::string what, h; ss >> what >> h;
            if (!skipWhy.empty()) continue;
            settle();
            if (!dut.set(what, V80::parse(h))) {
                skipWhy = " poke of " + what + ", not held by the RTL yet";
                continue;
            }
            top->eval();
        } else if (!skipWhy.empty()) {
            if (tag == "END") break;
        } else if (tag == "T") {
            std::string sIn, sAD, sST, sSN, sOut, sOAD;
            ss >> sIn >> sAD >> sST >> sSN >> sOut >> sOAD;
            In in = decodeIn(strtoul(sIn.c_str(), nullptr, 16), strtoul(sAD.c_str(), nullptr, 16),
                             strtoul(sST.c_str(), nullptr, 16), strtoul(sSN.c_str(), nullptr, 16));
            Out exp = decodeOut(strtoul(sOut.c_str(), nullptr, 16), strtoul(sOAD.c_str(), nullptr, 16));
            tick++;
            top->reset_n = in.reset_n; top->ad_in = in.ad; top->as_n = in.as_n; top->ds_n = in.ds_n;
            top->r_w = in.r_w; top->b_w = in.b_w; top->n_s = in.n_s; top->st = in.st; top->sn = in.sn;
            top->busack_n = in.busack_n; top->abort_n = in.abort_n; top->iei = in.iei;
            top->id = in.id; top->opt = in.opt;
            bool iRise = in.clki && !prevClki, iFall = !in.clki && prevClki;
            bool dRise = in.clkd && !prevClkd;
            prevClki = in.clki; prevClkd = in.clkd;
            top->clki_rise = iRise; top->clki_fall = iFall; top->clkd_rise = dRise || fastd;
            top->eval();
            for (int k = mclkSeq[mclkIdx]; k > 0; k--) {
                mtick();
                top->clki_rise = 0; top->clki_fall = 0; top->clkd_rise = fastd;
            }
            top->clkd_rise = 0;
            mclkIdx = (mclkIdx + 1) % mclkSeq.size();
            top->eval();
            if (iRise) clock++;
            Out got = readOut(top);
            bool ok[5];
            ok[0] = exp.ad_drive == got.ad_drive;
            ok[1] = exp.bsy_n == got.bsy_n;
            ok[2] = exp.int_n == got.int_n;
            ok[3] = exp.ieo == got.ieo;
            ok[4] = !(exp.ad_drive && got.ad_drive) || exp.ad == got.ad;
            static const char* pinName[5] = {"ADDrive", "BSY_n", "INT_n", "IEO", "AD"};
            if (fastd) {
                bool dsLow = !in.ds_n;
                if (dsLow && !prevDsLow) expW = gotW = -1;
                if (dsLow && exp.ad_drive) expW = exp.ad;
                if (dsLow && got.ad_drive) gotW = got.ad;
                if (!dsLow && prevDsLow && (expW >= 0 || gotW >= 0)) { expWords.push_back(expW); gotWords.push_back(gotW); }
                prevDsLow = dsLow;
                for (int k = 0; k < 5; k++) ok[k] = true;
            }
            std::string marks;
            for (int k = 0; k < 5; k++)
                if (!ok[k]) { if (!marks.empty()) marks += ","; marks += pinName[k]; }
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
            if (!settled) { settle(); settled = true; }
            std::string what, h; ss >> what >> h;
            if (what == "TICKS") continue;
            if (fastd && what == "PC2") continue;   // loaded only by an IF1 while busy
            if (!dut.has(what)) { unchecked += (unchecked.empty() ? "" : ",") + what; continue; }
            V80 e = V80::parse(h), g;
            dut.get(what, g);
            if (e != g) {
                finalFails++;
                char b[160];
                snprintf(b, sizeof b, "  final %s exp=%s got=%s\n", what.c_str(),
                         e.str().c_str(), g.str().c_str());
                if (finalFails <= 20) finalMsg += b;
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
    delete top;

    if (!skipWhy.empty()) { printf("RESULT SKIP %s:%s\n", vecPath.c_str(), skipWhy.c_str()); return 2; }
    if (!sawEnd && !(stopFirst && firstTick >= 0)) { printf("RESULT FAIL %s: truncated vector (no END)\n", vecPath.c_str()); return 4; }

    if (fastd && checkFinal && sawEnd && expWords != gotWords) {
        size_t i = 0;
        while (i < expWords.size() && i < gotWords.size() && expWords[i] == gotWords[i]) i++;
        char b[160];
        snprintf(b, sizeof b, "  final driven words: %zu expected, %zu seen, first difference at %zu (exp %04X got %04X)\n",
                 expWords.size(), gotWords.size(), i,
                 i < expWords.size() ? expWords[i] & 0xFFFF : 0, i < gotWords.size() ? gotWords[i] & 0xFFFF : 0);
        finalFails++; finalMsg += b;
    }
    std::string unc = unchecked.empty() ? "" : " unchecked=" + unchecked;
    if (firstTick < 0 && finalFails == 0) {
        printf("RESULT PASS %s ticks=%ld clocks=%ld%s\n", vecPath.c_str(), tick, clock, unc.c_str());
        return 0;
    }
    if (firstTick >= 0)
        printf("RESULT FAIL %s first-divergence tick=%ld clock=%ld pins=%s mismatched-ticks=%ld/%ld%s%s\n",
               vecPath.c_str(), firstTick, firstClock, firstPins.c_str(), mismTicks, tick,
               finalFails ? " final-state-mismatch" : "", unc.c_str());
    else
        printf("RESULT FAIL %s pins-ok final-state-mismatch (%ld fields)%s\n", vecPath.c_str(), finalFails, unc.c_str());
    if (!quiet) {
        if (firstTick >= 0) {
            printf("  ---- context: inputs | expected | actual (RTL) ----\n");
            printf("   tick  clock  ID R AD RWWN K X E id op AD  SN ST   | Dr BSY INT IEO AD  | Dr BSY INT IEO AD\n");
            for (auto& r : ctx) printf("%s\n", r.c_str());
            for (auto& r : after) printf("%s\n", r.c_str());
            printf("  (I D = CLK.I CLK.D levels; A/D = AS_n/DS_n Low; K = BUSACK_n Low; X = ABORT_n Low; E = IEI)\n");
        }
        if (finalFails) printf("%s", finalMsg.c_str());
    }
    return 1;
}
