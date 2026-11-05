// tb_mmu -- per-edge pin-equality replay of a Go-recorded Z8010 MMU vector
// file against the Verilated z8010_mmu (FPGA_BIBLE 0.3 tier 1, Ch.3.6).
//
//   tb_mmu <file.vec> [--context N] [--vcd out.vcd] [--quiet]
//                     [--stop-first] [--no-final] [--mclk P]
//
// The MMU runs on the board master clock `clk`; the CLK pin `clk_in` is the
// board's rising-edge pulse, High for the first master clock of a record
// whose CLK level rose. Each record gets the next count of master clocks
// from the pattern P (comma list, cycled; default K8000_MCLK or "1,2,1,3").
//
// The chip's pins are AD15..AD8 and A23..A8: the recorded 16-bit AD, 24-bit
// PA and 16-bit Data are compared on those bits only, and so is the
// violation offset (the chip keeps only its high byte).
//
// Exit codes: 0 PASS, 1 FAIL, 2 SKIP (unsupported vector), 4 usage/parse
// error. (3 = wrong-variant is reserved for parity with tb_cpu; the MMU has
// no variants.)
//
// The vector is a verbatim log of every Tick(Inputs) Outputs call a Go test
// made (see docs/K8010_MMU_TESTS.md). Replay is OPEN LOOP: the recorded inputs are
// driven regardless of what the RTL does, and every output pin is compared
// after every Tick -- low sample (before the edge) and high sample (after
// it) alike, exactly the two-calls-per-clock convention. The first
// divergence names the tick, the clock, and the pin, and prints the
// surrounding ticks (expected | actual). It then keeps counting so you also
// learn how bad it is.
//
// Comparison rules (why they are fair -- docs/K8010_MMU_TESTS.md "Comparison"):
//   * One Go Tick == one sample of the pins == one record. Both models act
//     on an /AS or /DS edge in the record that shows it and on CLK rises
//     for SN, DMASYNC and the trap-acknowledge /SEGT release (p.570-573);
//     the RTL sees the record's edges at its first master clock, so every
//     output is comparable after every record, exactly.
//   * /RESET is a level in both.
//   * All Go outputs are registered (m.out persists between Ticks), so PA
//     is compared only while PADrive=1 and Data only while DataDrive=1
//     (DataMask always) --
//     the held-but-undriven values are not pins.
//   * SEGT_n/SUP_n are the resolved open-drain levels (0 = driving low).

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
#include "Vz8010_mmu.h"
#include "mmu_access.h"

struct In {
    bool clk, reset_n, as_n, ds_n, r_w, n_s, cs_n, dmasync;
    uint16_t ad;
    uint8_t sn, st;
};
struct Out {
    bool pa_drive, segt_n, sup_n, data_drive;
    uint32_t pa;
    uint16_t data;
    uint8_t mask;
};

// Input bit order (MSB first): CLK RESET_n AS_n DS_n RW NS CS_n DMASYNC
static In decodeIn(unsigned bits, unsigned ad, unsigned sn, unsigned st) {
    In i;
    i.clk = bits >> 7 & 1; i.reset_n = bits >> 6 & 1; i.as_n = bits >> 5 & 1; i.ds_n = bits >> 4 & 1;
    i.r_w = bits >> 3 & 1; i.n_s = bits >> 2 & 1; i.cs_n = bits >> 1 & 1; i.dmasync = bits & 1;
    i.ad = ad; i.sn = sn; i.st = st;
    return i;
}
// Output bit order (MSB first): PADrive SEGT_n SUP_n DataDrive
static Out decodeOut(unsigned bits, unsigned pa, unsigned data, unsigned mask) {
    Out o;
    o.pa_drive = bits >> 3 & 1; o.segt_n = bits >> 2 & 1; o.sup_n = bits >> 1 & 1; o.data_drive = bits & 1;
    o.pa = pa; o.data = data; o.mask = mask;
    return o;
}
static Out readOut(Vz8010_mmu* t) {
    Out o;
    o.pa_drive = t->pa_drive; o.segt_n = t->segt_n; o.sup_n = t->sup_n; o.data_drive = t->data_drive != 0;
    o.pa = (uint32_t)t->pa << 8; o.data = (uint16_t)(t->data << 8); o.mask = t->data_drive;
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
             "%7ld %6ld  %d %d %c%c %c %c %c %c %04X %02X %-4s | %d %d %d %d %06X %04X %02X | %d %d %d %d %06X %04X %02X  %s",
             tick, clock, in.clk, in.reset_n,
             in.as_n ? '-' : 'A', in.ds_n ? '-' : 'D', in.r_w ? 'R' : 'W', in.n_s ? 'N' : 'S',
             in.cs_n ? '-' : 'C', in.dmasync ? 'Y' : '-', in.ad, in.sn, stName(in.st),
             e.pa_drive, e.segt_n, e.sup_n, e.data_drive, e.pa, e.data, e.mask,
             a.pa_drive, a.segt_n, a.sup_n, a.data_drive, a.pa, a.data, a.mask,
             marks.c_str());
    return buf;
}

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
    if (vecPath.empty()) { fprintf(stderr, "usage: tb_mmu <file.vec> [--context N] [--vcd f] [--quiet] [--stop-first] [--no-final]\n"); return 4; }

    std::ifstream f(vecPath);
    if (!f) { printf("RESULT FAIL %s: cannot open\n", vecPath.c_str()); return 4; }

    Vz8010_mmu* top = new Vz8010_mmu;
    MmuAccess dut(top);
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

    std::vector<int> mclkSeq;
    for (size_t p0 = 0; p0 < mclkPat.size();) {
        size_t p1 = mclkPat.find(',', p0); if (p1 == std::string::npos) p1 = mclkPat.size();
        int n = atoi(mclkPat.substr(p0, p1 - p0).c_str());
        if (n < 1) { fprintf(stderr, "--mclk: counts must be >= 1\n"); return 4; }
        mclkSeq.push_back(n); p0 = p1 + 1;
    }
    if (mclkSeq.empty()) { fprintf(stderr, "--mclk: empty pattern\n"); return 4; }
    size_t mclkIdx = 0;
    auto mtick = [&]() { top->clk = 0; top->eval(); dump(); top->clk = 1; top->eval(); dump(); };

    // Quiescent start == Go New(): no reset yet, strobes inactive, CLK low
    // (a fresh Z8010 has prevCLK=false, so the first CLK=1 Tick IS an edge).
    top->clk = 0; top->clk_in = 0; top->reset_n = 1; top->ad = 0; top->sn = 0; top->st = 0;
    top->as_n = 1; top->ds_n = 1; top->r_w = 1; top->n_s = 0; top->cs_n = 1; top->dmasync = 0;
    for (int k = 0; k < 2; k++) mtick();

    std::string line, testName;
    long tick = 0, clock = 0;
    bool prevClk = false;
    long mismTicks = 0, firstTick = -1, firstClock = -1;
    std::string firstPins;
    std::deque<std::string> ctx;      // rows before the divergence
    std::vector<std::string> after;   // rows after it
    long finalFails = 0;
    std::string finalMsg;
    bool sawEnd = false;

    // Pokes are applied to the model, then settled with an eval() at the
    // current clock level (the Go test wrote state between two Ticks).
    auto poke = [&](std::istringstream& ss, const std::string& what) -> bool {
        std::string h1, h2, h3, h4;
        if (what == "MODE") { ss >> h1; dut.set_mode_reg((uint8_t)strtoul(h1.c_str(), nullptr, 16)); }
        else if (what == "SAR") { ss >> h1; dut.set_sar((uint8_t)strtoul(h1.c_str(), nullptr, 16)); }
        else if (what == "DSC") { ss >> h1; dut.set_dsc((uint8_t)strtoul(h1.c_str(), nullptr, 16)); }
        else if (what == "DESC") {
            ss >> h1 >> h2 >> h3 >> h4;
            dut.set_desc((int)(strtoul(h1.c_str(), nullptr, 16) & 63), (uint16_t)strtoul(h2.c_str(), nullptr, 16),
                         (uint8_t)strtoul(h3.c_str(), nullptr, 16), (uint8_t)strtoul(h4.c_str(), nullptr, 16));
        }
        else if (what == "VTR") { ss >> h1; dut.set_viol_type((uint8_t)strtoul(h1.c_str(), nullptr, 16)); }
        else if (what == "ACK") dut.ack();
        else if (what == "LATCHED_ST") { ss >> h1; dut.set_latched_st((uint8_t)strtoul(h1.c_str(), nullptr, 16)); }
        else if (what == "ADDR_LATCHED") { ss >> h1; dut.set_addr_latched(h1 == "1"); }
        else return false;
        top->eval();
        return true;
    };

    while (std::getline(f, line)) {
        if (line.empty()) continue;
        if (line[0] == '#') continue;
        std::istringstream ss(line);
        std::string tag; ss >> tag;
        if (tag == "K8000VEC") {
            int ver; std::string kind; ss >> ver >> kind;
            if (ver != 1 || kind != "mmu") { printf("RESULT FAIL %s: not a v1 mmu vector\n", vecPath.c_str()); return 4; }
        } else if (tag == "test") {
            std::string n; int idx; ss >> n >> idx; testName = n;
        } else if (tag == "X") {
            std::string why; std::getline(ss, why);
            printf("RESULT SKIP %s:%s\n", vecPath.c_str(), why.c_str());
            return 2;
        } else if (tag == "P") {
            std::string what; ss >> what;
            if (!poke(ss, what)) { printf("RESULT SKIP %s: unsupported poke %s\n", vecPath.c_str(), what.c_str()); return 2; }
        } else if (tag == "T") {
            std::string sInB, sAD, sSN, sST, sOutB, sPA, sData, sMask;
            ss >> sInB >> sAD >> sSN >> sST >> sOutB >> sPA >> sData >> sMask;
            In in = decodeIn(strtoul(sInB.c_str(), nullptr, 16), strtoul(sAD.c_str(), nullptr, 16),
                             strtoul(sSN.c_str(), nullptr, 16), strtoul(sST.c_str(), nullptr, 16));
            Out exp = decodeOut(strtoul(sOutB.c_str(), nullptr, 16), strtoul(sPA.c_str(), nullptr, 16),
                                strtoul(sData.c_str(), nullptr, 16), strtoul(sMask.c_str(), nullptr, 16));
            tick++;
            // drive inputs
            top->reset_n = in.reset_n; top->ad = in.ad >> 8; top->sn = in.sn; top->st = in.st;
            top->as_n = in.as_n; top->ds_n = in.ds_n; top->r_w = in.r_w; top->n_s = in.n_s;
            top->cs_n = in.cs_n; top->dmasync = in.dmasync;
            bool rising = in.clk && !prevClk;
            prevClk = in.clk;
            top->clk_in = rising;   // the edge pulse, first master clock of the record only
            top->eval();          // the new inputs settle before the master clock samples them
            for (int k = mclkSeq[mclkIdx]; k > 0; k--) { mtick(); top->clk_in = 0; }
            mclkIdx = (mclkIdx + 1) % mclkSeq.size();
            if (rising) clock++;
            Out got = readOut(top);
            bool ok[7];
            ok[0] = exp.pa_drive == got.pa_drive;
            ok[1] = exp.segt_n == got.segt_n;
            ok[2] = exp.sup_n == got.sup_n;
            ok[3] = exp.data_drive == got.data_drive;
            ok[4] = exp.mask == got.mask;
            ok[5] = !(exp.pa_drive && got.pa_drive) || (exp.pa & 0xFFFF00) == got.pa;
            ok[6] = !(exp.data_drive && got.data_drive) || (exp.data & 0xFF00) == got.data;
            std::string marks;
            static const char* pinName[7] = {"PADrive", "SEGT_n", "SUP_n", "DataDrive", "DataMask", "PA", "Data"};
            for (int k = 0; k < 7; k++)
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
            std::string what; ss >> what;
            auto fail = [&](const std::string& m) { finalFails++; if (finalFails <= 20) finalMsg += "  final " + m + "\n"; };
            if (what == "DESC") {
                std::string hi, hb, hl, ha; ss >> hi >> hb >> hl >> ha;
                int i = (int)(strtoul(hi.c_str(), nullptr, 16) & 63);
                uint16_t eb = strtoul(hb.c_str(), nullptr, 16); uint8_t el = strtoul(hl.c_str(), nullptr, 16), ea = strtoul(ha.c_str(), nullptr, 16);
                uint16_t gb = dut.desc_base(i); uint8_t gl = dut.desc_limit(i), ga = dut.desc_attr(i);
                if (eb != gb || el != gl || ea != ga) {
                    char b[128]; snprintf(b, sizeof b, "DESC[%02X] exp=%04X %02X %02X got=%04X %02X %02X", i, eb, el, ea, gb, gl, ga); fail(b);
                }
            } else {
                std::string h; ss >> h; uint64_t e = strtoull(h.c_str(), nullptr, 16); uint64_t g = 0; bool known = true;
                if (what == "MODE") g = dut.mode_reg();
                else if (what == "SAR") g = dut.sar();
                else if (what == "DSC") g = dut.dsc();
                else if (what == "VTR") g = dut.viol_type();
                else if (what == "VSN") g = dut.viol_sn();
                else if (what == "VOFF") { e >>= 8; g = dut.viol_off(); }
                else if (what == "VOVF") g = dut.viol_overflow();
                else if (what == "ISN") g = dut.isn();
                else if (what == "IOFF") g = dut.ioffset();
                else if (what == "BCSR") g = dut.bcsr();
                else if (what == "TRAP") g = dut.trap_pending();
                else known = false;   // TICKS is informational
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
    top->final();
    delete top;

    if (!sawEnd && !(stopFirst && firstTick >= 0)) { printf("RESULT FAIL %s: truncated vector (no END)\n", vecPath.c_str()); return 4; }

    bool pass = firstTick < 0 && finalFails == 0;
    if (pass) {
        printf("RESULT PASS %s ticks=%ld clocks=%ld\n", vecPath.c_str(), tick, clock);
        return 0;
    }
    if (firstTick >= 0)
        printf("RESULT FAIL %s first-divergence tick=%ld clock=%ld pins=%s mismatched-ticks=%ld/%ld%s\n",
               vecPath.c_str(), firstTick, firstClock, firstPins.c_str(), mismTicks, tick,
               finalFails ? " final-state-mismatch" : "");
    else
        printf("RESULT FAIL %s pins-ok final-state-mismatch (%ld fields)\n", vecPath.c_str(), finalFails);
    if (!quiet) {
        if (firstTick >= 0) {
            printf("  ---- context: inputs | expected (Go) | actual (RTL) ----\n");
            printf("   tick  clock  C R AD RW NS CS DY  AD   SN ST   | PAd SEGT SUP Dd  PA    Data | PAd SEGT SUP Dd  PA    Data\n");
            for (auto& r : ctx) printf("%s\n", r.c_str());
            for (auto& r : after) printf("%s\n", r.c_str());
            printf("  (input flags: A=AS_n low, D=DS_n low, R/W=read/write, N/S=normal/system, C=CS_n low, Y=DMASYNC high)\n");
        }
        if (finalFails) printf("%s", finalMsg.c_str());
    }
    return 1;
}
