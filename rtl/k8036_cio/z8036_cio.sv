// z8036_cio -- Zilog Z8036 Z-CIO counter/timer + parallel I/O unit.
//
// Pin seam == ~/git/z8000/sim/cio/pins.go (Inputs/Outputs) one-for-one,
// plus `clk` (the fabric clock, FPGA_BIBLE 0.1: one clock + enables) and
// `rst_n` (a fabric reset the silicon does not have -- the Z8036 resets
// on /AS+/DS both Low; the harness pulses rst_n once before replay to
// reach the state Go New() starts in, which is observably identical to the
// AS+DS hardware-reset state: cio.go tickPins reset block vs New()).
//
// The lockstep contract is per-Tick pin equality against the Go model:
// tb/k8036_cio/tb_cio.cpp replays vectors/k8036_cio/*.vec through these ports, one fabric
// posedge per Go TickPins call (docs/K8036_CIO_TESTS.md).
//
// STATUS: SCAFFOLD. Only the reset pin state is implemented. Every vector
// fails at the first record whose outputs leave the reset state (the
// shortest failing vector is the next rung; `make test-cio`).
//
// Implementation order (FPGA_BIBLE Ch.4.3, mirroring cio.go):
//   1. Strobe capture (Ch.2 block): register as_n/ds_n/intack_n with clk,
//      latch ad_in/cs0_n/intack_n while AS is Low (cio.go tickPins:
//      pinAsLatched*, pinBusActive; RJA address decode regAddr); cs1 and
//      r_w are the LEVELS at DS fall, not AS-latched (R-CIO-401/402).
//      /AS+/DS both Low = hardware reset, never a cycle.
//   2. Register file regs[0:47] + reset gating (readReg cio.go:1444,
//      writeReg cio.go:1582: in reset reads are 0 except MICR=1, only
//      MICR bit 0 writable). W2-7: read data on ad_out and ad_drive from
//      the DS-low level + latched cycle, NO PCLK enable in the path; AD
//      floats at DS rise alone (W2-8, cio.go:961-964).
//   3. Ports A/B/C: mode/dir/polarity, OE masks, input sampling, 1's
//      catchers (updateCatchers), effectiveInput -- all on the /AS RISE
//      enable (`as_rise = ~as_q & as_n`), not PCLK. R-CIO-405: /AS is the
//      chip's clock for the ports, the pattern match, the handshake FSMs
//      and the IP -> /INT latch (p.695 Note 1; 1988 DB p.301 Note 7 "The
//      AS functions as the clock to the 8036"). The model does this too
//      since 2026-08-16 -- see docs/K8036_CIO_TESTS.md "Two clock domains".
//   4. Counter/timers: PCLK/2 prescaler (toggles on PCLK FALLING edges,
//      R-CIO-403), TC->reload gap, TC=0 = 65536, advancePCLK()
//      compute-then-commit, C/T gate/trigger sampled by PCLK from the LIVE
//      pins (rows 11/14/16 are pin-to-PCLK setup/hold, so NOT through the
//      /AS input register) and the asynchronous counter input (every clk,
//      R-CIO-404), EOE waveforms. The deskew timers count here too.
//   5. Pattern match (cio.go:1028-1160), LPM latch, deferred ERR.
//   6. Handshake unit (cio_handshake.go), REQUEST/WAIT on Port C
//      (cio.go:882-943), Port C DPP on driven lines.
//   7. Interrupts: priority encoder (cio.go findPendingSource), INT_n =
//      NOT the /AS-clocked request latch (cio.go intLatch, loaded in
//      advanceAS -- rows 22-25 are all "N AS cycles + t", so /INT asserts
//      one AS cycle after a terminal count and releases an AS cycle after
//      the acknowledge sets IUS), IEO = !DLC && IEI && !anyIUS &&
//      !pendingDuringIntack, INTACK vector drive at DS fall.
//
// Implementation-defined choices copied from the sim (R-CIO-238/239/253/
// 254, FPGA_BIBLE 4.7): document them here as each lands.
//
// Reset state to preserve (Go New()): all registers 0, in-reset, PCLK
// previous-level tracker LOW, strobe trackers HIGH, INT_n/IEO/Req_n
// released, the /AS-clocked INT latch clear, no port drives.

module z8036_cio (
  input  logic        clk,        // fabric clock (not in the Go seam)
  input  logic        rst_n,      // fabric reset (not in the Go seam) == Go New()

  // Inputs (pins.go Inputs)
  input  logic [7:0]  ad_in,      // AD7:0 -- the chip's only bus pins
  input  logic        as_n,
  input  logic        ds_n,
  input  logic        r_w,        // 1 = read
  input  logic        cs0_n,      // /CS0 (active low)  -- select = !cs0_n && cs1
  input  logic        cs1,        //  CS1 (active high)
  input  logic        intack_n,
  input  logic        iei,
  input  logic        pclk,       // peripheral clock as a DATA input; PCLK-domain
                                  // logic uses the FALLING-edge ENABLE (!pclk & pclk_q):
                                  // z8036_cio.pdf p.695, R-CIO-403
  input  logic [7:0]  pa_in,
  input  logic [7:0]  pb_in,
  input  logic [3:0]  pc_in,      // handshake/REQUEST/WAIT lines are Port C pins (Table 1)

  // Outputs (pins.go Outputs) -- AD and the ports as out/oe pairs, no tri-state
  output logic [7:0]  ad_out,
  output logic        ad_drive,
  output logic        int_n,      // open-drain at the pad; 0 = asserted
  output logic        ieo,
  output logic [7:0]  pa_out,
  output logic [7:0]  pa_oe,      // per-bit 1 = driving
  output logic        pa_req_n,   // REQUEST/WAIT mirror, active low
  output logic [7:0]  pb_out,
  output logic [7:0]  pb_oe,
  output logic        pb_req_n,
  output logic [3:0]  pc_out,
  output logic [3:0]  pc_oe
);

  // ---- strobe / PCLK level trackers (Go asyncPrev*, pinPrevPCLK) ------------
  // TODO(scaffold): these become the Ch.2 strobe-capture block. Reset values
  // == Go New(): strobes idle High, PCLK tracker Low.
  logic as_q, ds_q, intack_q, pclk_q;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      as_q     <= 1'b1;
      ds_q     <= 1'b1;
      intack_q <= 1'b1;
      pclk_q   <= 1'b0;
    end else begin
      as_q     <= as_n;
      ds_q     <= ds_n;
      intack_q <= intack_n;
      pclk_q   <= pclk;
    end
  end

  // ---- reset pin state (Go New() / hardware reset) --------------------------
  // TODO(scaffold): replace with the register file, ports, C/Ts, pattern
  // match, handshake and interrupt units listed in the header.
  always_comb begin
    ad_out   = 8'h00;
    ad_drive = 1'b0;
    int_n    = 1'b1;
    ieo      = iei;        // DLC=0, no IUS, nothing pending: IEO follows IEI
    pa_out   = 8'h00;
    pa_oe    = 8'h00;
    pa_req_n = 1'b1;
    pb_out   = 8'h00;
    pb_oe    = 8'h00;
    pb_req_n = 1'b1;
    pc_out   = 4'h0;
    pc_oe    = 4'h0;
  end

  // ---- scaffold-only lint waivers: remove as each input gains a consumer ----
  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{ad_in, as_n, ds_n, r_w, cs0_n, cs1, intack_n, pclk,
                       pa_in, pb_in, pc_in,
                       as_q, ds_q, intack_q, pclk_q};
  // verilator lint_on UNUSEDSIGNAL

endmodule
