// z8000_bus_monitor -- continuous Z-Bus protocol/timing checker for the CPU.
//
// This is a SPEC checker, not a golden-model comparison: every rule below is
// taken from the Zilog Z8001/Z8002 Product Specification (1988 Z8000 Family
// Data Book pp.150-160: Fig 12 memory read/write, Fig 13 input/output, Fig 14
// interrupt acknowledge, Fig 15 bus request/acknowledge, Fig 16 stop, Fig 17
// internal operation, Fig 18 memory refresh, Fig 19 reset + back-to-back, AC
// Characteristics p.159-160) and the Z8000 CPU Reference Manual sec 9.  The
// vector-replay harness (tb/k800x_cpu/tb_cpu.cpp) proves "same as the Go model"; this
// module proves "legal on the bus" -- it fires on the clock the RTL first
// misbehaves, with the citation, whatever program is running.
//
// Sampling convention: `clk` is the CPU's CLK; the monitor samples on both
// of its edges, each sample seeing the pins as the previous edge left them
// (identical to the Go model's per-Tick outputs).  Offsets are counted in
// half clocks from the sample where /AS first went Low (T1's first half =
// 0): an odd offset is the second half of a clock, after its fall.
//
// Instantiate alongside the DUT (tb_cpu_timing.sv) or `bind` it into any
// bench.  errors != 0 fails the run; every violation prints once with the
// clock number, the transaction, and the spec cite.
//
// verilator lint_off UNUSEDSIGNAL

module z8000_bus_monitor #(
  parameter bit SEGMENTED = 1,
  parameter int MAX_REPORT = 20
) (
  input  logic        clk,
  input  logic        enable,     // gate the checks (drop during reset / bus grant)
  input  logic [15:0] ad_out,
  input  logic        ad_drive,
  input  logic [6:0]  sn,
  input  logic        as_n,
  input  logic        ds_n,
  input  logic        mreq_n,
  input  logic        r_w,
  input  logic        b_w,
  input  logic        n_s,
  input  logic [3:0]  st,
  input  logic        busack_n,
  input  logic        mo_n,
  input  logic        wait_n
);
  import z8000_zbus_pkg::*;

  // ---- expected strobe offsets, in half clocks from the /AS fall (no waits)
  // From the AC table (1988 DB PDF p.47-48) and Figs 12/13/14.
  //
  //   every cycle : /AS falls on T1's rise (#24) and rises on its fall (#26):
  //                 Low for one half (1).
  //   memory read : /MREQ falls on T1's fall (#18, offset 1); /DS(read) on
  //                 T2's rise (#37, 2); both rise on T3's fall (#23, #34, 5).
  //   memory write: /DS(write) falls on T2's fall (#39, 3), rises at 5.
  //   I/O         : /MREQ never asserts.  One automatic wait: T1, T2, TWA, T3.
  //                 /DS falls on T2's fall (#42, 3) and rises on T3's (7).
  //   INTACK      : /MREQ never asserts.  Five automatic waits; /DS falls on
  //                 the rise opening the fourth (#45, 10) and rises on T3's
  //                 fall (15).
  //   refresh     : /AS + /MREQ only, /DS NEVER falls (Fig 18; Tech Manual
  //                 9-4: refresh and internal-operation cycles never activate
  //                 /DS -- only /AS + /MREQ frame the row address).
  //   internal op : ST=0000, /AS pulse only, no /MREQ, no /DS (Fig 17).
  // /WAIT is sampled on T2's fall (TWA's for I/O) and each Tw's (#62); a Tw
  // adds two halves.
  localparam int OFF_AS_UP      = 1;
  localparam int OFF_MEM_RD_DS  = 2;
  localparam int OFF_MEM_WR_DS  = 3;
  localparam int OFF_MEM_DS_UP  = 5;
  localparam int OFF_IO_DS      = 3;
  localparam int OFF_IO_DS_UP   = 7;
  localparam int OFF_IACK_DS    = 10;
  localparam int OFF_IACK_DS_UP = 15;
  localparam int OFF_MREQ       = 1;

  int unsigned errors;
  int unsigned transactions;
  int unsigned clk_no;
  int          reported;

  // ---- previous-sample pin state -------------------------------------------
  logic        as_q, ds_q, mreq_q, busack_q;
  logic [15:0] ad_q;
  logic [3:0]  st_q;

  // ---- in-flight transaction ------------------------------------------------
  logic        t_live;
  int          t_off;        // half clocks since the /AS fall sample
  int          t_tw;         // Tw clocks inserted (/WAIT Low at a sample point)
  int          t_tw_pre;     // of those, the ones before /DS fell
  logic [3:0]  t_st;
  logic        t_rw, t_bw, t_ns;
  logic [15:0] t_addr;
  logic [6:0]  t_sn;
  int          t_ds_fall, t_ds_rise, t_mreq_fall;
  logic        t_ad_drive_seen_low;   // read: AD released while /DS Low
  logic        t_ad_drive_all_high;   // write: AD held for the whole /DS Low
  logic        t_prev_rw, t_prev_bw, t_prev_ns;  // for the refresh "unchanged" rule
  logic        t_have_prev;

  function automatic bit is_mem(input logic [3:0] s);
    return s[3];                                     // 1000..1111
  endfunction
  function automatic bit is_io(input logic [3:0] s);
    return s == ST_IO || s == ST_SPECIAL_IO;
  endfunction
  function automatic bit is_ack(input logic [3:0] s);
    return s == ST_SEGMENT_TRAP || s == ST_NMI_ACK ||
           s == ST_NVI_ACK      || s == ST_VI_ACK;
  endfunction

  task automatic viol(input string rule, input string cite, input string detail);
    errors = errors + 1;
    if (reported < MAX_REPORT) begin
      reported = reported + 1;
      $display("  BUS VIOLATION @clk %0d  [%s]", clk_no, rule);
      $display("      %s", detail);
      $display("      spec: %s", cite);
    end else if (reported == MAX_REPORT) begin
      reported = reported + 1;
      $display("  ... further violations suppressed (MAX_REPORT=%0d)", MAX_REPORT);
    end
  endtask

  function automatic string cyc_name();
    if (is_io(t_st))  return "I/O";
    if (is_ack(t_st)) return "acknowledge";
    if (t_st == ST_REFRESH) return "refresh";
    if (t_st == ST_INTERNAL_OP) return "internal-op";
    if (is_mem(t_st)) return t_rw ? "memory read" : "memory write";
    return "unknown";
  endfunction

  // ---- checks ---------------------------------------------------------------
  task automatic check_end_of_cycle(input int ds_rise_at);
    int ds_f, ds_r;
    ds_f = t_ds_fall  - 2 * t_tw_pre;  // discount externally-inserted TW clocks
    ds_r = ds_rise_at - 2 * t_tw;

    if (is_mem(t_st)) begin
      if (t_mreq_fall != OFF_MREQ)
        viol("MREQ position",
             "Fig 12 / AC #18 TdC(MR): /MREQ falls on T1's falling edge",
             $sformatf("%s: /MREQ fell at T1+%0d, want T1+%0d", cyc_name(), t_mreq_fall, OFF_MREQ));
      if (t_rw) begin
        if (ds_f != OFF_MEM_RD_DS)
          viol("DS(read) position",
               "Fig 12 / AC #37 TdC(DSR): /DS falls on T2's rising edge on a read",
               $sformatf("memory read: /DS fell at T1+%0d (waits removed), want T1+%0d", ds_f, OFF_MEM_RD_DS));
        if (!t_ad_drive_seen_low)
          viol("AD not released on a read",
               "Fig 12: the CPU 3-states AD after T1 so the addressed slave can drive it",
               "memory read: ad_drive stayed High through the /DS Low window");
      end else begin
        if (ds_f != OFF_MEM_WR_DS)
          viol("DS(write) position",
               "Fig 12 / AC #39 TdC(DSW): /DS(write) falls on T2's falling edge, half a clock after a read's",
               $sformatf("memory write: /DS fell at T1+%0d (waits removed), want T1+%0d", ds_f, OFF_MEM_WR_DS));
        if (!t_ad_drive_all_high)
          viol("write data not held",
               "Fig 12 / AC ThDS(DO): write data is valid on AD until the end of T3",
               "memory write: ad_drive dropped while /DS was Low");
      end
      if (ds_r != OFF_MEM_DS_UP)
        viol("DS release",
             "Fig 12 / AC #23, #34: /DS and /MREQ rise on T3's falling edge",
             $sformatf("%s: /DS rose at T1+%0d (waits removed), want T1+%0d", cyc_name(), ds_r, OFF_MEM_DS_UP));
    end else if (is_io(t_st)) begin
      if (t_mreq_fall >= 0)
        viol("MREQ on an I/O cycle",
             "Fig 13 / Ref Manual 9.4.3: /MREQ is not activated for I/O references",
             $sformatf("I/O: /MREQ fell at T1+%0d", t_mreq_fall));
      if (ds_f != OFF_IO_DS)
        viol("DS(I/O) position",
             "Fig 13 / AC #42 TdC(DSf): /DS(I/O) falls on T2's falling edge; one automatic wait (TWA) follows",
             $sformatf("I/O: /DS fell at T1+%0d (waits removed), want T1+%0d", ds_f, OFF_IO_DS));
      if (ds_r != OFF_IO_DS_UP)
        viol("I/O cycle length",
             "Fig 13: an I/O reference is T1, T2, TWA, T3 -- four clocks minimum",
             $sformatf("I/O: /DS rose at T1+%0d (waits removed), want T1+%0d", ds_r, OFF_IO_DS_UP));
    end else if (is_ack(t_st)) begin
      if (t_mreq_fall >= 0)
        viol("MREQ on an acknowledge cycle",
             "Fig 14: /MREQ stays High through an interrupt/segment-trap acknowledge",
             $sformatf("acknowledge: /MREQ fell at T1+%0d", t_mreq_fall));
      if (ds_f != OFF_IACK_DS)
        viol("DS(acknowledge) position",
             "Fig 14 / AC #45 TdC(DSA): five automatic waits; /DS falls on the rise opening the fourth so the IEI/IEO chain has settled",
             $sformatf("acknowledge: /DS fell at T1+%0d (waits removed), want T1+%0d", ds_f, OFF_IACK_DS));
      if (ds_r != OFF_IACK_DS_UP)
        viol("acknowledge cycle length",
             "Fig 14: the acknowledge is 8+ T-states (T1, T2, five TWA, T3)",
             $sformatf("acknowledge: /DS rose at T1+%0d (waits removed), want T1+%0d", ds_r, OFF_IACK_DS_UP));
    end else if (t_st == ST_REFRESH) begin
      if (t_ds_fall >= 0)
        viol("DS on a refresh cycle",
             "Fig 18 / Tech Manual 9-4: refresh cycles never activate /DS -- /AS + /MREQ alone frame the row address",
             $sformatf("refresh: /DS fell at T1+%0d", t_ds_fall));
      if (t_mreq_fall != OFF_MREQ)
        viol("MREQ on a refresh cycle",
             "Fig 18: a refresh cycle drives the row address with /AS and /MREQ",
             $sformatf("refresh: /MREQ fell at T1+%0d, want T1+%0d", t_mreq_fall, OFF_MREQ));
      if (t_have_prev && (t_rw != t_prev_rw || t_bw != t_prev_bw || t_ns != t_prev_ns))
        viol("refresh changed R/W, B/W or N/S",
             "Fig 18 / Ref Manual 9.4.6: during refresh these are the same as for the immediately preceding transaction",
             $sformatf("refresh: R/W=%0b B/W=%0b N/S=%0b, previous transaction had %0b %0b %0b",
                       t_rw, t_bw, t_ns, t_prev_rw, t_prev_bw, t_prev_ns));
    end else if (t_st == ST_INTERNAL_OP) begin
      if (t_ds_fall >= 0)
        viol("DS on an internal operation",
             "Fig 17 / Tech Manual 9-4: internal-operation cycles never activate /DS (the address is undefined)",
             $sformatf("internal op: /DS fell at T1+%0d", t_ds_fall));
      if (t_mreq_fall >= 0)
        viol("MREQ on an internal operation",
             "Fig 17: an internal operation is an /AS pulse with no memory request",
             $sformatf("internal op: /MREQ fell at T1+%0d", t_mreq_fall));
    end

    // Byte memory writes duplicate the byte on both halves of AD.
    if (is_mem(t_st) && !t_rw && t_bw && t_ds_fall >= 0 &&
        ad_q[15:8] != ad_q[7:0])
      viol("byte write not duplicated",
           "Ref Manual 9.4.2 p.234 (R-CPU-513): on a byte write the CPU places the same byte on BOTH halves of the bus",
           $sformatf("byte write data AD=%04h (AD15:8=%02h AD7:0=%02h)", ad_q, ad_q[15:8], ad_q[7:0]));

    transactions = transactions + 1;
  endtask

  // Plain `always` (not always_ff): this is a checker, and the violation
  // counters are read back by the check tasks in the same evaluation.
  always @(posedge clk or negedge clk) begin
    clk_no <= clk_no + 1;

    if (!enable) begin
      t_live <= 1'b0;
    end else begin
      // --- rules that hold on EVERY sample ----------------------------------
      // R1: /AS and /DS are never both Low.  That combination is the Z-Bus
      // "force hardware reset" condition of the Z8036/Z8030 peripherals
      // (z8036_cio.pdf p.674, z8030_scc.pdf) -- a CPU that ever produces it
      // resets every peripheral on the board.
      if (!as_n && !ds_n)
        viol("/AS and /DS both Low",
             "z8036_cio.pdf p.674 / z8030_scc.pdf: simultaneous /AS+/DS Low is the peripherals' hardware-reset condition, never a transaction",
             "CPU drove as_n=0 and ds_n=0 in the same clock");

      // R2: /AS Low never spans an address or status change -- that is two T1s
      // with one falling edge, and every AS-edge latcher keeps the FIRST
      // address for the SECOND transaction.
      if (!as_n && !as_q && ad_drive && (ad_out != ad_q || st != st_q))
        viol("/AS held Low across an address/status change",
             "Fig 12: the address and status are valid while /AS is Low and /AS rises on T1's fall; the rising edge is the external latch point",
             $sformatf("AD %04h->%04h ST %0h->%0h with /AS still Low", ad_q, ad_out, st_q, st));

      // R3: while /AS is Low the CPU must be driving the address.
      if (!as_n && !ad_drive)
        viol("address not driven during /AS",
             "Fig 12: AD carries the address during T1, latched by external logic on the /AS rise",
             "as_n=0 with ad_drive=0");

      // R4: /MREQ and /DS must be released while the bus is granted away.
      // R5: a Z8002/Z8004 has no segment pins; SN must read as zero.
      if (!SEGMENTED && sn != 7'h00)
        viol("SN driven on a non-segmented part",
             "Product Spec p.150: SN6-SN0 exist only on the Z8001/Z8003",
             $sformatf("SEGMENTED=0 but sn=%02h", sn));

      if (!busack_n && (!as_n || !ds_n || !mreq_n || ad_drive))
        viol("bus not floated during /BUSACK",
             "Fig 15: when the CPU acknowledges a bus request it 3-states AD, /AS, /DS, /MREQ, ST, B/W, R/W and N/S",
             $sformatf("busack_n=0 with as_n=%0b ds_n=%0b mreq_n=%0b ad_drive=%0b", as_n, ds_n, mreq_n, ad_drive));

      // --- transaction tracking ---------------------------------------------
      if (as_q && !as_n) begin
        // /AS fall == T1 of a new transaction.  A /DS rise may share this very
        // sample (Fig 19 back-to-back): the OLD cycle ended, this is the new
        // one -- so the previous transaction is closed out first, below.
        if (t_live && t_ds_fall >= 0 && t_ds_rise < 0) begin
          check_end_of_cycle(t_off + 1);   // released on this same edge
        end
        t_have_prev <= t_live;
        if (t_live) begin
          t_prev_rw <= t_rw;
          t_prev_bw <= t_bw;
          t_prev_ns <= t_ns;
        end
        t_live      <= 1'b1;
        t_off       <= 0;
        t_tw        <= 0;
        t_tw_pre    <= 0;
        t_st        <= st;
        t_rw        <= r_w;
        t_bw        <= b_w;
        t_ns        <= n_s;
        t_addr      <= ad_out;
        t_sn        <= sn;
        t_ds_fall   <= -1;
        t_ds_rise   <= -1;
        t_mreq_fall <= -1;
        t_ad_drive_seen_low <= 1'b0;
        t_ad_drive_all_high <= 1'b1;
      end else if (t_live) begin
        t_off <= t_off + 1;
        // /WAIT is sampled on T2's fall and each Tw's; for I/O from TWA's
        // (Fig 9-5). The sample before that fall shows its level.
        if (!wait_n && t_ds_rise < 0 && t_off + 1 == (is_io(t_st) ? 4 : 2) + 2 * t_tw)
          t_tw <= t_tw + 1;
        if (!as_q && as_n && t_off + 1 != OFF_AS_UP)
          viol("AS width",
               "AC #24, #26, #29: /AS falls on T1's rise and rises on its fall",
               $sformatf("%s: /AS rose at T1+%0d halves, want %0d", cyc_name(), t_off + 1, OFF_AS_UP));
        if (ds_q && !ds_n) begin
          t_ds_fall <= t_off + 1;
          t_tw_pre  <= t_tw;
        end
        if (mreq_q && !mreq_n) t_mreq_fall <= t_off + 1;
        if (!ds_n) begin
          if (!ad_drive) t_ad_drive_seen_low <= 1'b1;
          else if (t_rw) begin end
          if (!t_rw && !ad_drive) t_ad_drive_all_high <= 1'b0;
        end
        if (!ds_q && ds_n && t_ds_rise < 0) begin
          t_ds_rise <= t_off + 1;
          check_end_of_cycle(t_off + 1);
          t_live <= 1'b0;
        end
        // A cycle with no data strobe at all (refresh / internal op) closes
        // three clocks after /AS falls -- long enough for its T3. An
        // acknowledge /DS can fall later, after waits.
        else if (t_off + 1 >= 5 && t_ds_fall < 0 && t_ds_rise < 0 &&
                 !is_ack(t_st)) begin
          check_end_of_cycle(t_ds_rise);
          t_live <= 1'b0;
        end
      end
    end

    as_q     <= as_n;
    ds_q     <= ds_n;
    mreq_q   <= mreq_n;
    busack_q <= busack_n;
    ad_q     <= ad_out;
    st_q     <= st;
  end

  initial begin
    errors = 0; transactions = 0; clk_no = 0; reported = 0;
    as_q = 1'b1; ds_q = 1'b1; mreq_q = 1'b1; busack_q = 1'b1;
    ad_q = 16'h0; st_q = 4'h0;
    t_live = 1'b0; t_off = 0; t_tw = 0; t_tw_pre = 0; t_st = 4'h0;
    t_rw = 1'b1; t_bw = 1'b0; t_ns = 1'b0; t_addr = 16'h0; t_sn = 7'h0;
    t_ds_fall = -1; t_ds_rise = -1; t_mreq_fall = -1;
    t_ad_drive_seen_low = 1'b0; t_ad_drive_all_high = 1'b1;
    t_prev_rw = 1'b1; t_prev_bw = 1'b0; t_prev_ns = 1'b0; t_have_prev = 1'b0;
  end
endmodule
