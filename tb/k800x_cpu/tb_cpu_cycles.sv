// tb_cpu_cycles -- CYCLE-ACCURACY conformance for the CPU.
//
// Cycle counts are datasheet facts: Z8000 CPU Technical Manual Mar81 sec 6.7
// "Instruction Execution Times".  The Go golden model reproduces them
// structurally (~/git/z8000/docs/CYCLE_ACCURACY_PLAN.md: every figure emerges from
// cyclesPLA(ctrl) driving a sequencer that does real work each clock -- no
// stored totals, no calibration padding), and vectors/k800x_cpu/cycles/cycles.vec is
// generated from it by ~/git/z8000/hdl/gen/cmd/cyclevec.
//
// Each record is a small program plus two PCs.  The bench runs the program on
// the RTL and measures the clocks between the IF1 (ST=1101) /AS fall at the
// first PC and the next IF1 /AS fall, which must land on the second PC.  That
// interval is the only pin-observable definition of "how long did this
// instruction take", and for repeatable instructions the generator takes it in
// pipeline steady state (the Z8000 prefetches: a first execution after a
// different instruction borrows fetch clocks from its predecessor).
//
// Records are tagged `exact` when that measured interval equals the Mar81 /
// cyclesPLA figure (29 of the 33 curated cases) and `approx` when it does not
// -- single-shot branch/stack cases, and shifts whose n_rec is base + per-step
// clocks while the decode-time PLA figure is only the base.  Both are asserted
// against the measured golden number; the tag tells you whether the datasheet
// figure and the pin-observable interval coincide for that instruction.
//
// Run: make test-cpu-cycles

module tb_cpu_cycles
  import z8000_zbus_pkg::*;
;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic        reset_n;
  logic [15:0] ad_in;
  logic        stop_n   = 1'b1;
  logic        wait_n   = 1'b1;
  logic        busreq_n = 1'b1;
  logic        nmi_n    = 1'b1;
  logic        nvi_n    = 1'b1;
  logic        vi_n     = 1'b1;
  logic        segt_n   = 1'b1;
  logic        abort_n  = 1'b1;
  logic        mi_n     = 1'b1;

  logic [15:0] ad_out;
  logic        ad_drive;
  logic [6:0]  sn;
  logic        as_n, ds_n, mreq_n, r_w, b_w, n_s;
  logic [3:0]  st;
  logic        busack_n, mo_n;

  z8000_cpu #(.SEGMENTED(1'b0), .VMPU(1'b0)) dut (
    .clk(clk), .reset_n(reset_n),
    .ad_in(ad_in), .stop_n(stop_n), .wait_n(wait_n), .busreq_n(busreq_n),
    .nmi_n(nmi_n), .nvi_n(nvi_n), .vi_n(vi_n), .segt_n(segt_n),
    .abort_n(abort_n), .mi_n(mi_n),
    .ad_out(ad_out), .ad_drive(ad_drive), .sn(sn),
    .as_n(as_n), .ds_n(ds_n), .mreq_n(mreq_n),
    .r_w(r_w), .b_w(b_w), .n_s(n_s), .st(st),
    .busack_n(busack_n), .mo_n(mo_n)
  );

  // ---- flat RAM slave (the generator's system: one 64 KiB chip) -------------
  localparam logic [15:0] PROG = 16'h0100;

  logic [15:0] mem [0:32767];
  logic [15:0] lat_addr;
  logic [3:0]  lat_st;
  logic        lat_rw, lat_bw, lat_valid;
  logic        as_q, ds_q;

  // The /DS-rise teardown goes first: a back-to-back /AS fall on the same
  // edge must win.
  always @(posedge clk) begin
    if (!ds_q && ds_n) lat_valid <= 1'b0;
    if (as_q && !as_n && ad_drive) begin
      lat_addr  <= ad_out;
      lat_st    <= st;
      lat_rw    <= r_w;
      lat_bw    <= b_w;
      lat_valid <= 1'b1;
    end
    if (ds_q && !ds_n && lat_valid && !lat_rw && lat_st[3]) begin
      if (lat_bw) begin
        if (lat_addr[0]) mem[lat_addr[15:1]][7:0]  <= ad_out[7:0];
        else             mem[lat_addr[15:1]][15:8] <= ad_out[15:8];
      end else begin
        mem[lat_addr[15:1]] <= ad_out;
      end
    end
    as_q <= as_n;
    ds_q <= ds_n;
  end

  always_comb begin
    if (lat_valid && lat_rw && lat_st[3]) ad_in = mem[lat_addr[15:1]];
    else if (lat_valid && lat_rw)         ad_in = 16'h00A5;   // I/O slave
    else                                  ad_in = 16'hFFFF;
  end

  // ---- IF1 observation --------------------------------------------------------
  int unsigned clk_no;
  logic        if1_now = 1'b0;
  logic [15:0] if1_pc  = 16'h0000;
  always @(posedge clk) begin
    clk_no <= clk_no + 1;
    if1_now <= 1'b0;
    if (as_q && !as_n && ad_drive && st == ST_INSTR_FETCH_FIRST) begin
      if1_now <= 1'b1;
      if1_pc  <= ad_out;
    end
  end

  // ---- vector file ------------------------------------------------------------
  string vecfile;
  int fd, code;
  string line, tok, name, kind;
  int unsigned n_rec, passed, failed, notrun, n_total;

  logic [15:0] prog_words [0:255];
  int          n_words;
  logic [15:0] from_pc, to_pc;
  int          want_clocks, pla_clocks;

  function automatic bit has_approx(input string s);
    int i;
    for (i = 0; i + 6 <= s.len(); i++)
      if (s.substr(i, i + 5) == "approx") return 1'b1;
    return 1'b0;
  endfunction

  task automatic load_and_reset();
    int i;
    for (i = 0; i < 32768; i++) mem[i] = 16'h0000;
    mem[16'h0002 >> 1] = 16'h4000;                  // FCW: system, non-segmented
    mem[16'h0004 >> 1] = PROG;                      // PC
    for (i = 0; i < n_words; i++) mem[(PROG >> 1) + i] = prog_words[i];
    reset_n = 1'b0;
    repeat (8) @(posedge clk);
    reset_n = 1'b1;
  endtask

  // Run the loaded program, measuring the IF1-to-IF1 interval.  Returns -1 if
  // the anchor IF1 never appeared, -2 if the following IF1 was at the wrong PC.
  task automatic measure(output int got, output logic [15:0] landed);
    int budget;
    logic armed;
    int t0;
    armed = 1'b0;
    got   = -1;
    landed = 16'h0000;
    for (budget = 0; budget < 4000; budget++) begin
      @(posedge clk);
      #1;
      if (if1_now) begin
        if (!armed && if1_pc == from_pc) begin
          armed = 1'b1;
          t0 = clk_no;
        end else if (armed) begin
          got    = clk_no - t0;
          landed = if1_pc;
          return;
        end
      end
    end
  endtask

  int got;
  logic [15:0] landed;
  int scan;

  initial begin
    n_rec = 0; passed = 0; failed = 0; notrun = 0; n_total = 0;
    clk_no = 0; lat_valid = 1'b0; as_q = 1'b1; ds_q = 1'b1;
    lat_addr = 16'h0; lat_st = 4'h0; lat_rw = 1'b1; lat_bw = 1'b0;
    reset_n = 1'b0;

    if (!$value$plusargs("vec=%s", vecfile)) vecfile = "vectors/k800x_cpu/cycles/cycles.vec";
    fd = $fopen(vecfile, "r");
    if (fd == 0) begin
      $display("RESULT FAIL  tb_cpu_cycles  cannot open %s", vecfile);
      $finish;
    end

    $display("tb_cpu_cycles -- instruction cycle counts (Mar81 sec 6.7 via vectors/k800x_cpu/cycles)");
    $display("");

    n_words = 0;
    while (!$feof(fd)) begin
      code = $fgets(line, fd);
      if (code == 0) continue;
      if (line.len() < 1) continue;
      case (line[0])
        "N": begin
          name = line.substr(2, line.len() - 2);
          while (name.len() > 0 && (name[name.len()-1] == "\n" || name[name.len()-1] == " "))
            name = name.substr(0, name.len() - 2);
          n_words = 0;
        end
        "W": begin
          scan = 2;
          n_words = 0;
          while (scan < line.len() - 1) begin
            logic [15:0] v;
            string sub;
            sub = line.substr(scan, scan + 3);
            if (sub.len() == 4) begin
              v = sub.atohex();
              prog_words[n_words] = v;
              n_words = n_words + 1;
            end
            scan = scan + 5;
          end
        end
        "T": begin
          // NOTE: no %s here.  Verilator's $sscanf with a trailing %s into a
          // string corrupts the next declared variable, which silently zeroed
          // the record counter -- the tag is recovered by a substring scan.
          code = $sscanf(line, "T %h %h %d %d", from_pc, to_pc, want_clocks, pla_clocks);
          kind = has_approx(line) ? "approx" : "exact";
          n_rec = n_rec + 1;
          load_and_reset();
          measure(got, landed);
          if (got < 0) begin
            notrun = notrun + 1;
            $display("  [%2d] NOTRUN %-14s  never fetched IF1 at %04h (want %0d clocks)",
                     n_rec, name, from_pc, want_clocks);
          end else if (landed != to_pc) begin
            failed = failed + 1;
            $display("  [%2d] FAIL   %-14s  next IF1 at %04h, want %04h (control flow diverged)",
                     n_rec, name, landed, to_pc);
          end else if (got != want_clocks) begin
            failed = failed + 1;
            $display("  [%2d] FAIL   %-14s  %0d clocks, want %0d   (%04h -> %04h, Mar81/PLA %0d, %0s)",
                     n_rec, name, got, want_clocks, from_pc, to_pc, pla_clocks, kind);
          end else begin
            passed = passed + 1;
            $display("  [%2d] PASS   %-14s  %0d clocks  (%0s)", n_rec, name, got, kind);
          end
        end
        default: ;   // W-continuation, comments, E
      endcase
    end
    $fclose(fd);
    // Snapshot for the summary.  Keep the per-record $display above reading
    // n_rec as well: with Verilator 5.020 a counter incremented inside a
    // time-consuming loop and read ONLY after that loop comes out stale (0).
    n_total = n_rec;

    $display("");
    if (failed == 0 && notrun == 0 && n_total > 0)
      $display("RESULT PASS  tb_cpu_cycles  %0d/%0d records", passed, n_total);
    else
      $display("RESULT FAIL  tb_cpu_cycles  %0d pass, %0d fail, %0d not run, of %0d",
               passed, failed, notrun, n_total);
    $finish;
  end
endmodule
