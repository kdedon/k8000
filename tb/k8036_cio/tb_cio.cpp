// tb_cio -- per-record pin-equality replay of a Z8036 CIO vector file
// against the Verilated z8036_cio.
//
//   tb_cio <file.vec> [--context N] [--vcd out.vcd] [--quiet] [--stop-first]
//                     [--mclk P] [--strict-out]
//
// Exit codes: 0 PASS, 1 FAIL, 2 SKIP (unsupported vector), 4 usage/parse
// error.
//
// The vector is a pin-level log, one record per pin sample; register
// accesses appear as Z-Bus cycles (docs/K8036_CIO_TESTS.md).
// Replay is OPEN LOOP: the recorded inputs are driven regardless of what
// the RTL does, then the fabric clock is stepped N posedges (N cycles through
// the comma list `--mclk P` / env K8000_MCLK, default "1,2,1,3"; --fclk is
// an alias) with the inputs held, and the outputs are compared. The PCLK
// fall reaches the chip as a pulse on `pclk_fall`, high for exactly the first
// master clock after the record that changed the level. One record ==
// N master clocks: the vectors react to
// a strobe edge and to a PCLK falling edge (the Z8036 PCLK-domain clock)
// within the same record, so the RTL gets the record's first posedge to do the
// same (a two-FF synchroniser on the strobes therefore needs --fclk 3 to
// be fair; the vectors never place a strobe edge and a PCLK fall in the
// same record -- F COINCIDENT is 0 -- so the intra-record ordering between
// the two domains never matters).
//
// Comparison (docs/K8036_CIO_TESTS.md): ADDrive, INT_n, IEO and the three
// OE masks always; PortAReq_n/PortBReq_n are not compared (they mirror
// Port C levels, which are); AD only while both sides drive it;
// PortA/B/C data bits only under the OE mask both
// sides agree on (--strict-out compares all data bits: the vectors'
// non-driven data bits mirror the output registers).
//
// `X partial <why>` ends the comparable part of a file early (state
// set next has no pin equivalent); everything before it is
// compared and the result is reported as PASS/FAIL with a (partial) tag.
// `X unsupported` (before any T) is SKIP.

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
#include "Vz8036_cio.h"

struct In {
    bool pclk, as_n, ds_n, r_w, cs0_n, cs1, intack_n, iei;
    uint8_t ad, pa, pb, pc;
};
struct Out {
    bool ad_drive, int_n, ieo, pa_req_n, pb_req_n;
    uint8_t ad, pa_out, pa_oe, pb_out, pb_oe, pc_out, pc_oe;
};

static In decodeIn(unsigned bits, unsigned ad, unsigned pa, unsigned pb, unsigned pc) {
    In i;
    i.pclk = bits >> 7 & 1; i.as_n = bits >> 6 & 1; i.ds_n = bits >> 5 & 1; i.r_w = bits >> 4 & 1;
    i.cs0_n = bits >> 3 & 1; i.cs1 = bits >> 2 & 1; i.intack_n = bits >> 1 & 1; i.iei = bits & 1;
    i.ad = ad; i.pa = pa; i.pb = pb; i.pc = pc & 0xF;
    return i;
}
static Out decodeOut(unsigned bits, unsigned ad, unsigned pao, unsigned paoe, unsigned pbo, unsigned pboe,
                     unsigned pco, unsigned pcoe) {
    Out o;
    o.ad_drive = bits >> 4 & 1; o.int_n = bits >> 3 & 1; o.ieo = bits >> 2 & 1;
    o.pa_req_n = bits >> 1 & 1; o.pb_req_n = bits & 1;
    o.ad = ad; o.pa_out = pao; o.pa_oe = paoe; o.pb_out = pbo; o.pb_oe = pboe;
    o.pc_out = pco & 0xF; o.pc_oe = pcoe & 0xF;
    return o;
}
static Out readOut(Vz8036_cio* t) {
    Out o;
    o.ad_drive = t->ad_drive; o.int_n = t->int_n; o.ieo = t->ieo;
    o.pa_req_n = o.pb_req_n = true;   // not chip pins: REQUEST/WAIT is on Port C
    o.ad = t->ad_out; o.pa_out = t->pa_out; o.pa_oe = t->pa_oe;
    o.pb_out = t->pb_out; o.pb_oe = t->pb_oe; o.pc_out = t->pc_out & 0xF; o.pc_oe = t->pc_oe & 0xF;
    return o;
}

static std::string fmtOut(const Out& o) {
    char buf[96];
    snprintf(buf, sizeof buf, "%d %02X %d %d %d %d %02X/%02X %02X/%02X %X/%X",
             o.ad_drive, o.ad, o.int_n, o.ieo, o.pa_req_n, o.pb_req_n,
             o.pa_out, o.pa_oe, o.pb_out, o.pb_oe, o.pc_out, o.pc_oe);
    return buf;
}

// One line of the context table.
static std::string fmtRow(long tick, long pclks, const In& in, const Out& e, const Out& a,
                          const std::string& marks) {
    char buf[512];
    snprintf(buf, sizeof buf,
             "%7ld %6ld  %d %c%c%c%c%c%c%c %02X %02X %02X %X | %s | %s  %s",
             tick, pclks, in.pclk,
             in.as_n ? '-' : 'A', in.ds_n ? '-' : 'D', in.r_w ? 'R' : 'W',
             in.cs0_n ? '-' : 'c', in.cs1 ? 'C' : '-', in.intack_n ? '-' : 'I',
             in.iei ? 'E' : '-',
             in.ad, in.pa, in.pb, in.pc,
             fmtOut(e).c_str(), fmtOut(a).c_str(), marks.c_str());
    return buf;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::string vecPath, vcdPath;
    int context = 12;
    std::string mclkPat = getenv("K8000_MCLK") ? getenv("K8000_MCLK") : "1,2,1,3";
    bool quiet = false, stopFirst = false, strictOut = false;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--context" && i + 1 < argc) context = atoi(argv[++i]);
        else if (a == "--vcd" && i + 1 < argc) vcdPath = argv[++i];
        else if ((a == "--mclk" || a == "--fclk") && i + 1 < argc) mclkPat = argv[++i];
        else if (a == "--quiet") quiet = true;
        else if (a == "--stop-first") stopFirst = true;
        else if (a == "--strict-out") strictOut = true;
        else if (a.size() > 1 && a[0] == '-' && a[1] == '-') { fprintf(stderr, "unknown option %s\n", a.c_str()); return 4; }
        else vecPath = a;
    }
    std::vector<int> mclkSeq;
    for (size_t p0 = 0; p0 < mclkPat.size();) {
        size_t p1 = mclkPat.find(',', p0); if (p1 == std::string::npos) p1 = mclkPat.size();
        int n = atoi(mclkPat.substr(p0, p1 - p0).c_str());
        if (n < 1) { fprintf(stderr, "--mclk: counts must be >= 1\n"); return 4; }
        mclkSeq.push_back(n); p0 = p1 + 1;
    }
    if (mclkSeq.empty()) { fprintf(stderr, "--mclk: empty pattern\n"); return 4; }
    size_t mclkIdx = 0;
    if (vecPath.empty()) {
        fprintf(stderr, "usage: tb_cio <file.vec> [--context N] [--vcd f] [--quiet] [--stop-first] [--mclk P] [--strict-out]\n");
        return 4;
    }
    std::ifstream f(vecPath);
    if (!f) { printf("RESULT FAIL %s: cannot open\n", vecPath.c_str()); return 4; }

    Vz8036_cio* top = new Vz8036_cio;
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
    auto posedge = [&]() {
        top->clk = 0; top->eval(); dump();
        top->clk = 1; top->eval(); dump();
    };

    // Idle bus, PCLK Low, in reset. The chip has
    // no reset pin: /AS and /DS Low together reset it, then the bus idles.
    top->ad_in = 0; top->as_n = 1; top->ds_n = 1; top->r_w = 0; top->cs0_n = 1; top->cs1 = 0;
    top->intack_n = 1; top->iei = 1; top->pclk_fall = 0;
    top->pa_in = 0; top->pb_in = 0; top->pc_in = 0;
    posedge(); posedge();
    top->as_n = 0; top->ds_n = 0;
    for (int k = 0; k < 4; k++) posedge();
    top->as_n = 1; top->ds_n = 1;
    for (int k = 0; k < 4; k++) posedge();
    top->eval();

    std::string line, testName, partialWhy;
    long tick = 0, pclks = 0;
    bool prevPclk = false;
    long mismTicks = 0, firstTick = -1, firstPclk = -1;
    std::string firstPins;
    std::deque<std::string> ctx;
    std::vector<std::string> after;
    bool sawEnd = false, partial = false;

    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ss(line);
        std::string tag; ss >> tag;
        if (tag == "K8000VEC") {
            int ver; std::string kind; ss >> ver >> kind;
            if (ver != 1 || kind != "cio") { printf("RESULT FAIL %s: not a v1 cio vector\n", vecPath.c_str()); return 4; }
        } else if (tag == "test") {
            std::string n; int idx; ss >> n >> idx; testName = n;
        } else if (tag == "X") {
            std::string kind; ss >> kind;
            std::string why; std::getline(ss, why);
            if (kind == "partial") { partial = true; partialWhy = why; continue; }
            printf("RESULT SKIP %s:%s\n", vecPath.c_str(), why.c_str());
            return 2;
        } else if (tag == "T") {
            if (partial) continue;   // records after X partial are not present by construction
            std::string s[13];
            for (int i = 0; i < 13; i++) ss >> s[i];
            unsigned v[13];
            for (int i = 0; i < 13; i++) v[i] = strtoul(s[i].c_str(), nullptr, 16);
            In in = decodeIn(v[0], v[1], v[2], v[3], v[4]);
            Out exp = decodeOut(v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12]);
            tick++;
            top->as_n = in.as_n; top->ds_n = in.ds_n; top->r_w = in.r_w;
            top->cs0_n = in.cs0_n; top->cs1 = in.cs1; top->intack_n = in.intack_n; top->iei = in.iei;
            top->ad_in = in.ad; top->pa_in = in.pa; top->pb_in = in.pb; top->pc_in = in.pc;
            // PCLK fall is a one-master-clock pulse on the first master clock
            // after the record that changed the level.
            top->pclk_fall = prevPclk && !in.pclk;
            int nclk = mclkSeq[mclkIdx]; mclkIdx = (mclkIdx + 1) % mclkSeq.size();
            for (int i = 0; i < nclk; i++) { posedge(); top->pclk_fall = 0; top->eval(); }
            if (in.pclk && !prevPclk) pclks++;
            prevPclk = in.pclk;
            Out got = readOut(top);
            std::string marks;
            auto cmp = [&](bool ok, const char* pin) { if (!ok) { if (!marks.empty()) marks += ","; marks += pin; } };
            cmp(exp.ad_drive == got.ad_drive, "ADDrive");
            if (exp.ad_drive && got.ad_drive) cmp(exp.ad == got.ad, "AD");
            cmp(exp.int_n == got.int_n, "INT_n");
            cmp(exp.ieo == got.ieo, "IEO");
            // PAReq_n/PBReq_n mirror a Port C level:
            // the Port C pins carry REQUEST/WAIT and are compared below.
            cmp(exp.pa_oe == got.pa_oe, "PAoe");
            cmp(exp.pb_oe == got.pb_oe, "PBoe");
            cmp(exp.pc_oe == got.pc_oe, "PCoe");
            uint8_t ma = strictOut ? 0xFF : (exp.pa_oe & got.pa_oe);
            uint8_t mb = strictOut ? 0xFF : (exp.pb_oe & got.pb_oe);
            uint8_t mc = strictOut ? 0x0F : (exp.pc_oe & got.pc_oe);
            cmp((exp.pa_out & ma) == (got.pa_out & ma), "PAout");
            cmp((exp.pb_out & mb) == (got.pb_out & mb), "PBout");
            cmp((exp.pc_out & mc) == (got.pc_out & mc), "PCout");
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
            // informational (REGS/TICKS/REAL/MIRRORED/COINCIDENT)
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
    if (tick == 0) { printf("RESULT SKIP %s: no records before X\n", vecPath.c_str()); return 2; }

    const char* ptag = partial ? " (partial)" : "";
    if (firstTick < 0) {
        printf("RESULT PASS %s ticks=%ld pclks=%ld%s\n", vecPath.c_str(), tick, pclks, ptag);
        return 0;
    }
    printf("RESULT FAIL %s first-divergence tick=%ld pclk=%ld pins=%s mismatched-ticks=%ld/%ld%s\n",
           vecPath.c_str(), firstTick, firstPclk, firstPins.c_str(), mismTicks, tick, ptag);
    if (!quiet) {
        printf("  ---- context: inputs | expected | actual (RTL) ----\n");
        printf("   tick  pclks  P ADRcCIE AD PA PB C | drv AD INT IEO rA rB PAo/oe PBo/oe PCo/oe | drv AD INT IEO rA rB PAo/oe PBo/oe PCo/oe\n");
        for (auto& r : ctx) printf("%s\n", r.c_str());
        for (auto& r : after) printf("%s\n", r.c_str());
        printf("  (input flags: A=/AS low D=/DS low R/W=read/write c=/CS0 low C=CS1 high I=/INTACK low E=IEI high)\n");
        if (partial) printf("  partial vector:%s\n", partialWhy.c_str());
    }
    return 1;
}
