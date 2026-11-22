// tb_silicon -- replays silicon vectors (K8000VEC 1 silicon) on a Z8001:
// programs captured on a physical Z8001, judged by the final state it
// dumped and, where recorded, its bus trace and instruction clock count.
//
// The board is the capture rig's: 8 KiB of RAM indexed by {SN0, AD[11:0]}
// (AD[15:12] and SN[6:1] alias), I/O ports 0x0100-0x010F as twelve 16-bit
// registers (standard I/O registers 0-5 at AD[3:1], special I/O 6-11),
// 0xFFFF for any other I/O read, no wait states.  The I/O registers persist
// from test to test, as on the rig.  The rig's instrumentation is copied
// too: the trace records every completed data-strobe cycle while the last
// first-word fetch was at an offset of 0x0200 or above (the gate is updated
// after the cycle is recorded); the instruction count is CLK rises while
// the gate is open.  A test ends at the data-strobe rise of the fetch of
// HALT (0x7A00).
//
// Run: make test-cpu-silicon; +vec=FILE, +limit=N (CLK rises per test),
// +verbose (one line per test).

module tb_silicon
  import z8000_zbus_pkg::*;
#(parameter bit SEGMENTED = 1'b1);
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic mclk = 1'b0;
  initial begin #0.5; forever #1 mclk = ~mclk; end
  logic clk_pq = 1'b0;
  always @(posedge mclk) clk_pq <= clk;
  wire  clk_rise = clk & ~clk_pq;
  wire  clk_fall = ~clk & clk_pq;

  logic        reset_n = 1'b0;
  logic [15:0] ad_in;
  logic [15:0] ad_out;
  logic        ad_drive, bus_drive;
  logic [6:0]  sn;
  logic        as_n, ds_n, mreq_n, r_w, b_w, n_s;
  logic [3:0]  st;
  logic        busack_n, mo_n;

  z8000_cpu #(.SEGMENTED(SEGMENTED), .VMPU(1'b0)) dut (
    .clk(mclk), .clk_rise(clk_rise), .clk_fall(clk_fall), .reset_n(reset_n),
    .ad_in(ad_in), .stop_n(1'b1), .wait_n(1'b1), .busreq_n(1'b1),
    .nmi_n(1'b1), .nvi_n(1'b1), .vi_n(1'b1), .segt_n(1'b1),
    .abort_n(1'b1), .mi_n(1'b1),
    .ad_out(ad_out), .ad_drive(ad_drive), .bus_drive(bus_drive), .sn(sn),
    .as_n(as_n), .ds_n(ds_n), .mreq_n(mreq_n),
    .r_w(r_w), .b_w(b_w), .n_s(n_s), .st(st),
    .busack_n(busack_n), .mo_n(mo_n)
  );

  // ---- the rig ---------------------------------------------------------------
  localparam int TMAX = 1024;
  logic [15:0] mem [0:4095];
  logic [15:0] base [0:4095];
  logic [15:0] ioreg [0:15];
  logic [15:0] ioseq [0:15][0:3];
  int          seq_n [0:15];
  int          seq_pos [0:15];

  logic [15:0] a_addr, c_addr, c_wdata;
  logic [3:0]  c_st;
  logic        c_sn, c_rw, c_bw, c_mreq;
  logic        as_q = 1'b1, ds_q = 1'b1;
  logic        running = 1'b0, halt_seen = 1'b0, gate = 1'b0;
  int unsigned n_icc;

  // the observed trace: addr, data, rw, bw, io, seg, st
  logic [15:0] ot_addr [0:TMAX-1];
  logic [15:0] ot_data [0:TMAX-1];
  logic [3:0]  ot_bits [0:TMAX-1];   // {seg, io, bw, rw}
  logic [3:0]  ot_st   [0:TMAX-1];
  int          n_ot;

  function automatic bit io_space(input logic [3:0] s);
    return s == ST_IO || s == ST_SPECIAL_IO;
  endfunction
  function automatic logic [3:0] io_index(input logic [15:0] a, input logic [3:0] s);
    return {1'b0, a[3:1]} + ((s == ST_SPECIAL_IO) ? 4'd6 : 4'd0);
  endfunction
  function automatic bit io_match(input logic [15:0] a, input logic [3:0] s);
    return io_space(s) && a[15:4] == 12'h010;
  endfunction

  logic [15:0] rdata;
  always_comb begin
    logic [3:0] ix;
    ix = io_index(c_addr, c_st);
    if (!c_mreq && !io_space(c_st))  rdata = mem[{c_sn, c_addr[11:1]}];
    else if (io_match(c_addr, c_st)) rdata = (seq_n[ix] != 0) ? ioseq[ix][(seq_pos[ix] >= seq_n[ix]) ? seq_n[ix] - 1 : seq_pos[ix]]
                                                              : ioreg[ix];
    else                             rdata = 16'hFFFF;
  end
  assign ad_in = rdata;

  // Sampled on the master clock's fall, half a master clock after the pins move.
  always @(negedge mclk) begin
    logic [3:0] ix;
    if (!as_n && ad_drive) a_addr <= ad_out;
    if (!as_q && as_n) begin
      c_addr <= a_addr;
      c_st   <= st;
      c_sn   <= sn[0];
      c_rw   <= r_w;
      c_bw   <= b_w;
    end
    if (!ds_n) begin
      c_wdata <= ad_out;
      c_mreq  <= mreq_n;
    end
    if (!ds_q && ds_n && running) begin
      ix = io_index(c_addr, c_st);
      if (gate && n_ot < TMAX) begin
        ot_addr[n_ot] <= c_addr;
        ot_data[n_ot] <= c_rw ? rdata : c_wdata;
        ot_bits[n_ot] <= {c_sn, io_space(c_st), c_bw, c_rw};
        ot_st[n_ot]   <= c_st;
      end
      if (gate) n_ot <= n_ot + 1;
      if (c_st == ST_INSTR_FETCH_FIRST) begin
        gate <= c_addr >= 16'h0200;
        if (c_rw && rdata == 16'h7A00) halt_seen <= 1'b1;
      end
      if (!c_rw && !c_mreq && !io_space(c_st)) begin
        if (!c_bw || !c_addr[0]) mem[{c_sn, c_addr[11:1]}][15:8] <= c_wdata[15:8];
        if (!c_bw ||  c_addr[0]) mem[{c_sn, c_addr[11:1]}][7:0]  <= c_wdata[7:0];
      end
      if (io_match(c_addr, c_st) && !c_rw && ix < 4'd12) begin
        if (!c_bw || !c_addr[0]) ioreg[ix][15:8] <= c_wdata[15:8];
        if (!c_bw ||  c_addr[0]) ioreg[ix][7:0]  <= c_wdata[7:0];
      end
      if (io_match(c_addr, c_st) && c_rw && seq_n[ix] != 0 && seq_pos[ix] < seq_n[ix])
        seq_pos[ix] <= seq_pos[ix] + 1;
    end
    as_q <= as_n;
    ds_q <= ds_n;
  end

  always @(posedge mclk)
    if (clk_rise && running && gate) n_icc <= n_icc + 1;

  // ---- the vectors -------------------------------------------------------------
  string vec, line, name, s_rw, s_bw, s_io, s_seg, s_st, s_v, s_m, field;
  int fd, code, i, limit, n_test, n_pass, n_fail, n_end, n_bad, lineno;
  int unsigned a, v, m, dump_regs, dump_fcw, exp_icc;
  bit verbose, in_test, have_icc;
  // expectations
  logic [15:0] x_reg [0:15];
  logic [15:0] x_regm [0:15];
  logic [15:0] x_fcw, x_fcwm;
  bit          have_fcw;
  logic [15:0] x_maddr [0:4095];
  logic [15:0] x_mval  [0:4095];
  int          n_xm;
  int          x_io [0:15];
  logic [15:0] x_iov [0:15];
  int          n_xio;
  logic [15:0] xt_addr [0:TMAX-1];
  logic [15:0] xt_data [0:TMAX-1];
  int          xt_f [0:TMAX-1][0:4];      // rw bw io seg st; -1 = not recorded
  int          n_xt;

  task automatic note(input string msg);
    if (n_bad < 8) $display("FAIL %s  %s", name, msg);
    n_bad++;
  endtask

  task automatic run_test();
    logic [15:0] got;
    string f;
    reset_n = 1'b0;
    running = 1'b0; halt_seen = 1'b0; gate = 1'b0; n_icc = 0; n_ot = 0;
    repeat (8) @(posedge clk);
    @(negedge clk);
    reset_n = 1'b1;
    running = 1'b1;
    for (int k = 0; k < limit && !halt_seen; k++) @(posedge clk);
    repeat (2) @(posedge mclk);
    running = 1'b0;
    reset_n = 1'b0;
    n_bad = 0;
    if (!halt_seen) note($sformatf("no HALT within %0d clocks", limit));
    if (dut.check_q || dut.u_execute.check_q || dut.u_sequencer.check_q || dut.u_bus.check_q)
      note("an RTL self-check fired");
    for (int r = 0; r < 16; r++) begin
      got = mem[(dump_regs[12:0] + 2 * r) >> 1];
      if (((got ^ x_reg[r]) & x_regm[r]) != 0)
        note($sformatf("R%0d want %04h got %04h", r, x_reg[r] & x_regm[r], got & x_regm[r]));
    end
    if (have_fcw) begin
      got = mem[dump_fcw[12:1]];
      if (((got ^ x_fcw) & x_fcwm) != 0)
        note($sformatf("FCW want %04h got %04h (mask %04h)", x_fcw, got & x_fcwm, x_fcwm));
    end
    for (int k = 0; k < n_xm; k++)
      if (mem[x_maddr[k][12:1]] != x_mval[k])
        note($sformatf("MEM %04h want %04h got %04h", x_maddr[k], x_mval[k], mem[x_maddr[k][12:1]]));
    for (int k = 0; k < n_xio; k++)
      if (ioreg[x_io[k]] != x_iov[k])
        note($sformatf("IO %0h want %04h got %04h", x_io[k], x_iov[k], ioreg[x_io[k]]));
    if (n_xt != 0) begin
      if (n_ot != n_xt) note($sformatf("trace length want %0d got %0d", n_xt, n_ot));
      for (int k = 0; k < n_xt && k < n_ot && k < TMAX; k++) begin
        f = "";
        if (ot_addr[k] != xt_addr[k] || ot_data[k] != xt_data[k]
            || xt_f[k][0] != int'(ot_bits[k][0]) || xt_f[k][1] != int'(ot_bits[k][1])
            || xt_f[k][2] != int'(ot_bits[k][2])
            || (xt_f[k][3] >= 0 && xt_f[k][3] != int'(ot_bits[k][3]))
            || (xt_f[k][4] >= 0 && xt_f[k][4] != int'(ot_st[k]))) begin
          note($sformatf("trace #%0d want %04h %04h rw=%0d bw=%0d io=%0d seg=%0d st=%0d got %04h %04h rw=%0d bw=%0d io=%0d seg=%0d st=%0d",
                         k, xt_addr[k], xt_data[k], xt_f[k][0], xt_f[k][1], xt_f[k][2], xt_f[k][3], xt_f[k][4],
                         ot_addr[k], ot_data[k], ot_bits[k][0], ot_bits[k][1], ot_bits[k][2], ot_bits[k][3], ot_st[k]));
          break;
        end
      end
    end
    if (have_icc && n_icc != exp_icc) note($sformatf("ICC want %0d got %0d", exp_icc, n_icc));
    n_test++;
    if (n_bad == 0) begin n_pass++; if (verbose) $display("PASS %s", name); end
    else n_fail++;
  endtask

  initial begin
    for (i = 0; i < 16; i++) begin
      ioreg[i] = 16'h0000; seq_n[i] = 0; seq_pos[i] = 0;
      for (int j = 0; j < 4; j++) ioseq[i][j] = 16'h0000;
    end
    for (i = 0; i < 4096; i++) begin base[i] = 16'h0000; mem[i] = 16'h0000; end
    c_addr = 16'h0; c_st = 4'h0; c_sn = 1'b0; c_rw = 1'b1; c_bw = 1'b0; c_mreq = 1'b1;
    a_addr = 16'h0; c_wdata = 16'h0; n_icc = 0; n_ot = 0;
    if (!$value$plusargs("vec=%s", vec)) begin $display("RESULT FAIL  tb_silicon  no +vec"); $finish; end
    if (!$value$plusargs("limit=%d", limit)) limit = 200000;
    verbose = $test$plusargs("verbose");
    fd = $fopen(vec, "r");
    if (fd == 0) begin $display("RESULT FAIL  tb_silicon  cannot open %s", vec); $finish; end
    n_test = 0; n_pass = 0; n_fail = 0; n_end = -1; in_test = 0; lineno = 0;
    dump_regs = 0; dump_fcw = 0;
    code = $fgets(line, fd);
    if (line != "K8000VEC 1 silicon\n") begin $display("RESULT FAIL  tb_silicon  %s: not a silicon vector", vec); $finish; end
    while (!$feof(fd)) begin
      code = $fgets(line, fd);
      lineno++;
      if (code == 0 || line.len() < 2 || line[0] == "#") continue;
      case (line[0])
        "v": ;
        "d": code = $sscanf(line, "dump %h %h", dump_regs, dump_fcw);
        "t": begin
          code = $sscanf(line, "test %s", name);
          for (i = 0; i < 4096; i++) mem[i] = base[i];
          for (i = 0; i < 16; i++) begin
            seq_n[i] = 0; seq_pos[i] = 0; x_reg[i] = 16'h0; x_regm[i] = 16'h0;
          end
          n_xm = 0; n_xio = 0; n_xt = 0; have_fcw = 0; have_icc = 0; in_test = 1;
        end
        "M": begin
          code = $sscanf(line, "M %h %h", a, v);
          if (in_test) mem[a[12:1]] = v[15:0]; else base[a[12:1]] = v[15:0];
        end
        "P": begin code = $sscanf(line, "P %h %h", a, v); ioreg[a[3:0]] = v[15:0]; end
        "Q": begin
          code = $sscanf(line, "Q %h %h", a, v);
          ioseq[a[3:0]][seq_n[a[3:0]]] = v[15:0];
          seq_n[a[3:0]] = seq_n[a[3:0]] + 1;
        end
        "F": begin
          code = $sscanf(line, "F %s %s %s", field, s_v, s_m);
          if (field == "FCW") begin
            code = $sscanf(line, "F FCW %h %h", v, m);
            x_fcw = v[15:0]; x_fcwm = m[15:0]; have_fcw = 1;
          end else if (field == "MEM") begin
            code = $sscanf(line, "F MEM %h %h", a, v);
            x_maddr[n_xm] = a[15:0]; x_mval[n_xm] = v[15:0]; n_xm++;
          end else if (field == "IO") begin
            code = $sscanf(line, "F IO %h %h", a, v);
            x_io[n_xio] = a; x_iov[n_xio] = v[15:0]; n_xio++;
          end else if (field == "ICC") begin
            code = $sscanf(line, "F ICC %d", exp_icc); have_icc = 1;
          end else if (field[0] == "R") begin
            code = $sscanf(field.substr(1, field.len() - 1), "%d", a);
            if (s_v == "----") x_regm[a] = 16'h0000;
            else begin
              code = $sscanf(line, "F %s %h %h", field, v, m);
              x_reg[a] = v[15:0];
              x_regm[a] = (code == 3) ? m[15:0] : 16'hFFFF;
            end
          end else begin
            $display("RESULT FAIL  tb_silicon  %s:%0d: unknown F field %s", vec, lineno + 1, field); $finish;
          end
        end
        "B": begin
          if (n_xt < TMAX) begin
            code = $sscanf(line, "B %h %h %s %s %s %s %s", a, v, s_rw, s_bw, s_io, s_seg, s_st);
            xt_addr[n_xt] = a[15:0]; xt_data[n_xt] = v[15:0];
            xt_f[n_xt][0] = (s_rw == "R") ? 1 : 0;
            xt_f[n_xt][1] = (s_bw == "B") ? 1 : 0;
            xt_f[n_xt][2] = (s_io == "I") ? 1 : 0;
            xt_f[n_xt][3] = (s_seg == "-") ? -1 : (s_seg == "1") ? 1 : 0;
            if (s_st == "-") xt_f[n_xt][4] = -1;
            else begin code = $sscanf(s_st, "%h", v); xt_f[n_xt][4] = int'(v); end
          end
          n_xt++;
        end
        "E": begin
          if (line.substr(0, 2) == "END") code = $sscanf(line, "END %d", n_end);
          else begin
            run_test();
            in_test = 0;
          end
        end
        default: begin $display("RESULT FAIL  tb_silicon  %s:%0d: bad record", vec, lineno + 1); $finish; end
      endcase
    end
    $fclose(fd);
    if (n_end != n_test)
      $display("RESULT FAIL  tb_silicon  %s: END says %0d tests, %0d run", vec, n_end, n_test);
    else if (n_fail != 0)
      $display("RESULT FAIL  tb_silicon  %s: %0d of %0d pass, %0d fail", vec, n_pass, n_test, n_fail);
    else
      $display("RESULT PASS  tb_silicon  %s: %0d of %0d pass", vec, n_pass, n_test);
    $finish;
  end
endmodule
