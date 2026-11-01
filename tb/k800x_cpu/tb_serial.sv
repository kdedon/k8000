// tb_serial -- the serial unit's MULT / DIV / SHIFT routines vs the Go golden
// MultState / DivState / ShiftState (sim/cpu/alu/alu.go).
//
// Replays vectors/k800x_cpu/serial/random.vec. Per record the contract is: the
// operand-load protocol, the EXACT tick count to done (cycle counts must
// EMERGE from the FSM), the Remaining() lower bound after each tick (the
// CPU's internal-op bus dressing consults it), and the result/flag fields.
// Protocol (see rtl/k800x_cpu/z8000_serial.sv header): start pulse at edge E0 (Go
// Start), ticks are the following edges, a long's high word (x_hi) the edge
// before its low word, src_valid during the edge of tick
// (delay+1) (Go SetMultiplier/SetDivisor before that Tick).
//   obj_dir/tb_serial/tb_serial +vec=vectors/k800x_cpu/serial/random.vec [+only=M|D|S]

module tb_serial
  import z8000_ctrl_pkg::*;
;
  logic clk = 0, reset_n = 0;
  always #5 clk <= ~clk;

  // One unit; `kind` says which driver set feeds it: 1 multiply, 2 divide, 0 shift.
  int          kind = 0;
  logic        x_done, x_fin, x_hi = 0;   // x_hi: a long's high word is given
  logic [63:0] x_words;
  // ---- mult ----
  logic        m_start, m_width32, m_src_valid, m_done, m_fin;
  logic [31:0] m_dst, m_src;
  logic [63:0] m_product;
  logic        m_more;   // CPU hookup only
  logic        m_flag_c, m_flag_z;
  // ---- div ----
  logic        d_start, d_n32, d_src_valid, d_done, d_fin, d_dbz, d_ovf, d_wide, d_qneg, d_qzero;
  logic [63:0] d_dividend;
  logic [31:0] d_divisor, d_quot, d_rem;
  // ---- shift ----
  logic        s_start, s_done;
  logic [1:0]  s_width;
  logic [ALUOP_W-1:0] s_op;
  logic [31:0] s_val, s_result;
  logic [5:0]  s_count;
  logic [15:0] s_flags, s_mask;
  logic        x_end3, x_end2, x_last;   // CPU hookup only
  z8000_serial u_serial (.clk(clk), .reset_n(reset_n), .tick(1'b1), .start(m_start || d_start || s_start),
                         .mul(kind == 1), .div(kind == 2), .wide(kind == 1 ? m_width32 : d_n32),
                         .dst(kind == 1 ? {32'd0, m_dst} : kind == 2 ? d_dividend : {32'd0, s_val}),
                         .src_hi(x_hi), .src_valid(m_src_valid || d_src_valid),
                         .src(x_hi ? x_src32[31:16] : x_src32[15:0]),
                         .width(s_width), .op(s_op), .count(s_count),
                         .done(x_done), .fin(x_fin), .words(x_words), .flag_c(m_flag_c), .flag_z(m_flag_z),
                         .more(m_more), .div_by_zero(d_dbz), .overflow(d_ovf),
                         .wide_quot(d_wide), .quot_neg(d_qneg), .quot_zero(d_qzero),
                         .sh_flags(s_flags), .sh_mask(s_mask), .end3(x_end3), .end2(x_end2), .last(x_last));
  logic [31:0] x_src32;
  assign x_src32   = kind == 1 ? m_src : d_divisor;
  assign m_done    = x_done;
  assign m_fin     = x_fin;
  assign m_product = m_width32 ? x_words : {32'd0, x_words[63:32]};
  assign d_done    = x_done;
  assign d_fin     = x_fin;
  assign d_quot    = d_n32 ? x_words[31:0] : {16'h0000, x_words[47:32]};
  assign d_rem     = d_n32 ? x_words[63:32] : {16'h0000, x_words[63:48]};
  assign s_done    = x_done;
  assign s_result  = x_words[31:0];

  string vecfile, only, tok;
  int fd, n, total, bad, shown, ticks, delay, exp_ticks, remv, k;
  int r_width, r_delay, r_ticks, r_dbz, r_ovf, r_wide, r_qneg, r_qzero, r_op, r_count;
  logic [63:0] r_dst, r_src, r_product, r_dividend, r_divisor, r_quot, r_rem, r_val, r_result;
  logic [15:0] r_flags, r_mask;
  bit fail_this;
  // fin: the results are final on the clock before done.
  int fin_at, fin_late;
  logic [63:0] fin_res;
  logic [4:0]  fin_flg;
  task automatic fin_check(input string what, input bit may_skip, input logic [63:0] res, input logic [4:0] flg);
    if (fin_at < 0) begin
      if (!may_skip) mismatch($sformatf("%s: no fin before done", what));
      else fin_late++;
    end else begin
      if (fin_at != exp_ticks - 2) mismatch($sformatf("%s: fin at tick %0d (exp %0d)", what, fin_at + 1, exp_ticks - 1));
      if (fin_res !== res || fin_flg !== flg) mismatch($sformatf("%s: results at fin differ from done", what));
    end
  endtask

  // Multiplier arrival as the CPU gives it, as a tick after the start
  // edge: register, IM, IR, DA/X.
  int m_arr_w[4] = '{0, 1, 2, 3};
  int m_arr_l[4] = '{0, 4, 5, 6};
  function automatic logic [15:0] m_abs16(input logic [15:0] v);
    return v[15] ? 16'h0000 - v : v;
  endfunction

  task automatic report(input string what);
    total++;
    if (fail_this) begin
      bad++;
      shown++;
    end
  endtask

  task automatic mismatch(input string what);
    if (!fail_this && shown < 20) $display("  MISMATCH %s", what);
    fail_this = 1;
  endtask

  // Drive one tick; returns after the posedge settled.
  task automatic tick();
    @(posedge clk); #1;
  endtask

  task automatic reset_dut();
    reset_n = 0; m_start = 0; d_start = 0; s_start = 0; m_src_valid = 0; d_src_valid = 0;
    @(negedge clk); reset_n = 1; @(negedge clk);
  endtask

  // ---- directed protocol cases ----------------------------------------------
  // Each check compares a run against a reference run of the same operation
  // from reset: ticks to done, remaining after every tick, results and flags.
  // MAXT caps a run's ticks; passed as a delay, the operand never arrives.
  localparam int MAXT = 1024;
  int          run_ticks, ref_ticks;
  int          run_rem[MAXT], ref_rem[MAXT];
  logic [63:0] run_res, ref_res;
  logic [15:0] run_flg, ref_flg;
  bit          run_done, ref_done;

  task automatic save_ref();
    ref_ticks = run_ticks; ref_rem = run_rem; ref_res = run_res; ref_flg = run_flg; ref_done = run_done;
  endtask

  task automatic compare(input string what, input bit chk_res);
    fail_this = 0;
    if (!ref_done) mismatch($sformatf("%s: reference not done", what));
    if (!run_done) mismatch($sformatf("%s: not done after %0d ticks", what, run_ticks));
    if (run_ticks != ref_ticks) mismatch($sformatf("%s: ticks exp=%0d got=%0d", what, ref_ticks, run_ticks));
    for (int i = 0; i < run_ticks && i < ref_ticks; i++)
      if (run_rem[i] != ref_rem[i]) begin
        mismatch($sformatf("%s tick %0d: remaining exp=%0d got=%0d", what, i + 1, ref_rem[i], run_rem[i]));
        break;
      end
    if (run_flg !== ref_flg) mismatch($sformatf("%s: flags exp=%h got=%h", what, ref_flg, run_flg));
    if (chk_res && run_res !== ref_res) mismatch($sformatf("%s: result exp=%h got=%h", what, ref_res, run_res));
    report(what);
  endtask

  // Div quotient and remainder are undefined after divide by zero or overflow.
  function automatic bit res_defined();
    return !ref_flg[4] && !ref_flg[3];
  endfunction

  // delay < 0: src_valid with start (a word only: a long's two words cannot
  // arrive on the start edge through one 16-bit port). delay2: tick of a
  // second pulse carrying src2.
  // Stops after limit ticks, or at done.
  task automatic run_m(input bit fresh, input bit w32, input logic [31:0] dst, src, input int dly,
                       input logic [31:0] src2, input int delay2, input int limit);
    if (fresh) reset_dut();
    @(negedge clk);
    // A long is given a word at a time, its high word first.
    m_width32 = w32; m_dst = dst; m_src = src;
    kind = 1; m_start = 1; m_src_valid = (dly < 0); x_hi = w32 && dly == 0;
    tick(); m_start = 0; m_src_valid = 0; x_hi = 0;
    run_ticks = 0;
    while (!m_done && run_ticks < limit) begin
      @(negedge clk);
      m_src_valid = (run_ticks == dly) || (run_ticks == delay2);
      m_src = (run_ticks == delay2) ? src2 : src;
      x_hi  = w32 && run_ticks == dly - 1;
      tick(); m_src_valid = 0; x_hi = 0;
      run_rem[run_ticks] = 0; run_ticks++;
    end
    run_done = m_done; run_res = m_product; run_flg = 0;
  endtask

  task automatic run_d(input bit fresh, input bit l, input logic [63:0] dvd, input logic [31:0] dvr, input int dly,
                       input logic [31:0] dvr2, input int delay2, input int limit);
    if (fresh) reset_dut();
    @(negedge clk);
    d_n32 = l; d_dividend = dvd; d_divisor = dvr;
    kind = 2; d_start = 1; d_src_valid = (dly < 0); x_hi = l && dly == 0;
    tick(); d_start = 0; d_src_valid = 0; x_hi = 0;
    run_ticks = 0;
    while (!d_done && run_ticks < limit) begin
      @(negedge clk);
      d_src_valid = (run_ticks == dly) || (run_ticks == delay2);
      d_divisor = (run_ticks == delay2) ? dvr2 : dvr;
      x_hi = l && run_ticks == dly - 1;
      tick(); d_src_valid = 0; x_hi = 0;
      run_rem[run_ticks] = 0; run_ticks++;
    end
    run_done = d_done; run_res = {d_quot, d_rem}; run_flg = {11'd0, d_dbz, d_ovf, d_wide, d_qneg, d_qzero};
  endtask

  task automatic mult_case(input bit w32, input logic [31:0] dst, src, src2, dst_b, src_b);
    string id = $sformatf("M w=%0d dst=%h src=%h", w32 ? 32 : 16, dst, src);
    // 1. arrival with start == delay 0
    run_m(1, w32, dst, src, 0, 0, -1, MAXT); save_ref();
    if (!w32) begin run_m(1, w32, dst, src, -1, 0, -1, MAXT); compare({id, " with start"}, 1); end
    // back to back: start from done, without reset
    run_m(1, w32, dst_b, src_b, 0, 0, -1, MAXT);
    run_m(0, w32, dst, src, 0, 0, -1, MAXT); compare({id, " after another op"}, 1);
    // 2. Later pulses are ignored: a unit takes one operand per start, and the
    // CPU never sends a second.
    if (!w32) begin run_m(1, w32, dst, src, -1, src2, 0, MAXT); compare({id, " with start, 2nd pulse +1"}, 1); end
    run_m(1, w32, dst, src, 0, src2, 1, MAXT); compare({id, " 2nd pulse +1"}, 1);
    run_m(1, w32, dst, src, 0, src2, 6, MAXT); compare({id, " 2nd pulse +6"}, 1);
    run_m(1, w32, dst, src, 5, 0, -1, MAXT); save_ref();
    run_m(1, w32, dst, src, 5, src2, 6, MAXT); compare({id, " late, 2nd pulse +1"}, 1);
    // 3. start while busy restarts
    id = $sformatf("M w=%0d dst=%h src=%h", w32 ? 32 : 16, dst_b, src_b);
    run_m(1, w32, dst_b, src_b, 0, 0, -1, MAXT); save_ref();
    run_m(1, w32, dst, src, 0, 0, -1, 12);
    run_m(0, w32, dst_b, src_b, 0, 0, -1, MAXT); compare({id, " restart mid-iteration"}, 1);
    run_m(1, w32, dst, src, 0, 0, -1, 12);
    if (!w32) begin run_m(0, w32, dst_b, src_b, -1, 0, -1, MAXT); compare({id, " with start, restart mid-iteration"}, 1); end
    run_m(1, w32, dst, src, MAXT, 0, -1, 6);
    run_m(0, w32, dst_b, src_b, 0, 0, -1, MAXT); compare({id, " restart while waiting"}, 1);
    run_m(1, w32, dst, src, 0, 0, -1, MAXT);
    run_m(0, w32, dst_b, src_b, 0, 0, -1, MAXT); compare({id, " after another op"}, 1);
  endtask

  task automatic div_case(input bit l, input logic [63:0] dvd, input logic [31:0] dvr, dvr2,
                          input logic [63:0] dvd_b, input logic [31:0] dvr_b);
    string id = $sformatf("D n=%0d dvd=%h dvr=%h", l ? 32 : 16, dvd, dvr);
    run_d(1, l, dvd, dvr, 0, 0, -1, MAXT); save_ref();
    if (!l) begin run_d(1, l, dvd, dvr, -1, 0, -1, MAXT); compare({id, " with start"}, res_defined()); end
    run_d(1, l, dvd_b, dvr_b, 0, 0, -1, MAXT);
    run_d(0, l, dvd, dvr, 0, 0, -1, MAXT); compare({id, " after another op"}, res_defined());
    if (!l) begin run_d(1, l, dvd, dvr, -1, dvr2, 0, MAXT); compare({id, " with start, 2nd pulse +1"}, res_defined()); end
    run_d(1, l, dvd, dvr, 0, dvr2, 1, MAXT); compare({id, " 2nd pulse +1"}, res_defined());
    run_d(1, l, dvd, dvr, 0, dvr2, 6, MAXT); compare({id, " 2nd pulse +6"}, res_defined());
    run_d(1, l, dvd, dvr, 30, 0, -1, MAXT); save_ref();
    run_d(1, l, dvd, dvr, 30, dvr2, 31, MAXT); compare({id, " late, 2nd pulse +1"}, res_defined());
    id = $sformatf("D n=%0d dvd=%h dvr=%h", l ? 32 : 16, dvd_b, dvr_b);
    run_d(1, l, dvd_b, dvr_b, 0, 0, -1, MAXT); save_ref();
    run_d(1, l, dvd, dvr, 0, 0, -1, 60);
    run_d(0, l, dvd_b, dvr_b, 0, 0, -1, MAXT); compare({id, " restart mid-iteration"}, res_defined());
    run_d(1, l, dvd, dvr, 0, 0, -1, 60);
    if (!l) begin run_d(0, l, dvd_b, dvr_b, -1, 0, -1, MAXT); compare({id, " with start, restart mid-iteration"}, res_defined()); end
    run_d(1, l, dvd, dvr, MAXT, 0, -1, 40);
    run_d(0, l, dvd_b, dvr_b, 0, 0, -1, MAXT); compare({id, " restart while waiting"}, res_defined());
    run_d(1, l, dvd, dvr, 0, 0, -1, MAXT);
    run_d(0, l, dvd_b, dvr_b, 0, 0, -1, MAXT); compare({id, " after another op"}, res_defined());
  endtask

  task automatic run_s(input bit fresh, input logic [1:0] w, input logic [ALUOP_W-1:0] op, input logic [31:0] val,
                       input logic [5:0] cnt);
    if (fresh) reset_dut();
    @(negedge clk);
    s_width = w; s_op = op; s_val = val; s_count = cnt;
    kind = 0; s_start = 1; tick(); s_start = 0;
    run_ticks = 0;
    while (!s_done && run_ticks < MAXT) begin
      tick(); run_rem[run_ticks] = 0; run_ticks++;
    end
    run_done = s_done; run_res = {16'd0, s_mask, s_result}; run_flg = s_flags & s_mask;
  endtask

  // Op 2 started from op 1's done matches op 2 from reset.
  task automatic shift_b2b(input logic [1:0] w1, input logic [ALUOP_W-1:0] op1, input logic [31:0] val1,
                           input logic [5:0] cnt1, input logic [1:0] w2, input logic [ALUOP_W-1:0] op2,
                           input logic [31:0] val2, input logic [5:0] cnt2);
    string id = $sformatf("S w=%0d op=%0d val=%h n=%0d after w=%0d op=%0d val=%h n=%0d",
                          w2, op2, val2, cnt2, w1, op1, val1, cnt1);
    run_s(1, w2, op2, val2, cnt2); save_ref();
    run_s(1, w1, op1, val1, cnt1);
    run_s(0, w2, op2, val2, cnt2); compare(id, 1);
  endtask

  // 4. flags after done hold while the next start presents another width.
  task automatic shift_case(input logic [1:0] w, input logic [ALUOP_W-1:0] op, input logic [31:0] val,
                            input logic [5:0] cnt, input logic [1:0] w_next);
    string id = $sformatf("S w=%0d op=%0d val=%h n=%0d, next width %0d", w, op, val, cnt, w_next);
    logic [15:0] f, fm;
    fail_this = 0;
    reset_dut();
    @(negedge clk);
    s_width = w; s_op = op; s_val = val; s_count = cnt;
    kind = 0; s_start = 1; tick(); s_start = 0;
    for (int i = 0; i < 200 && !s_done; i++) tick();
    if (!s_done) mismatch({id, ": not done"});
    f = s_flags; fm = s_mask;
    @(negedge clk);
    s_width = w_next; s_op = OP_SRL; s_val = ~val; s_count = 6'd3; kind = 0; s_start = 1;
    #4;  // just before the start edge
    if (s_flags !== f || s_mask !== fm)
      mismatch($sformatf("%s: flags/mask %04X/%04X became %04X/%04X", id, f, fm, s_flags, s_mask));
    tick(); s_start = 0;
    report(id);
  endtask

  initial begin
    if (!$value$plusargs("vec=%s", vecfile)) vecfile = "vectors/k800x_cpu/serial/random.vec";
    if (!$value$plusargs("only=%s", only)) only = "";
    fd = $fopen(vecfile, "r");
    if (fd == 0) begin $display("RESULT FAIL tb_serial %s: cannot open", vecfile); $finish; end
    total = 0; bad = 0; shown = 0;
    m_width32 = 0; m_dst = 0; m_src = 0; d_n32 = 0; d_dividend = 0; d_divisor = 0;
    s_width = 0; s_op = 0; s_val = 0; s_count = 0;
    reset_dut();
    while ($fscanf(fd, "%s", tok) == 1) begin
      if (tok == "K8000VEC") begin n = $fscanf(fd, "%s %s", tok, tok); continue; end
      if (tok == "END") break;
      fail_this = 0;
      if (tok == "M") begin
        // The Go record's own operand delay and Remaining() run are not the
        // CPU's; the unit is run with the multiplier arriving where the CPU
        // gives it (register, IM, IR, DA/X), the clocks to done must be the
        // CPU's (Jan83 6-99 less the program's 3), and the result is final
        // on the clock before done.
        n = $fscanf(fd, "%d %h %h %d %d %h", r_width, r_dst, r_src, r_delay, r_ticks, r_product);
        for (k = 0; k < r_ticks; k++) n = $fscanf(fd, "%d", remv);
        r_delay = (r_width == 32) ? m_arr_l[total % 4] : m_arr_w[total % 4];
        if (r_width == 32) exp_ticks = (r_src[31:0] == 0) ? 27 : 279 + 7 * $countones(m_abs16(r_dst[15:0]));
        else               exp_ticks = (r_src[15:0] == 0) ? 15 : 67;
        reset_dut();
        @(negedge clk);
        m_width32 = (r_width == 32); m_dst = r_dst[31:0]; m_src = r_src[31:0];
        kind = 1; m_start = 1; x_hi = m_width32 && r_delay == 0;
        tick(); m_start = 0; x_hi = 0;                                    // E0: load
        ticks = 0; fin_at = -1;
        for (k = 0; k < exp_ticks; k++) begin
          @(negedge clk);
          m_src_valid = (k == r_delay);
          x_hi = m_width32 && k == r_delay - 1;
          tick(); m_src_valid = 0; x_hi = 0; ticks++;
          if (only == "" || only == "M") begin
            if (m_fin) begin fin_at = k; fin_res = m_product; fin_flg = 0; end
            if (m_done && k != exp_ticks - 1)
              mismatch($sformatf("M w=%0d dst=%h src=%h delay=%0d: done early at tick %0d (exp %0d)", r_width, r_dst, r_src, r_delay, ticks, exp_ticks));
          end
        end
        if (only == "" || only == "M") begin
          if (!m_done) mismatch($sformatf("M w=%0d dst=%h src=%h delay=%0d: not done after %0d ticks", r_width, r_dst, r_src, r_delay, exp_ticks));
          if ((r_width == 16 ? m_product[31:0] : m_product) !== (r_width == 16 ? r_product[31:0] : r_product))
            mismatch($sformatf("M w=%0d dst=%h src=%h: product exp=%h got=%h", r_width, r_dst, r_src, r_product, m_product));
          if (r_width == 32 && (m_flag_c !== (r_product[63:31] != {33{r_product[63]}}) || m_flag_z !== (r_product == 0)))
            mismatch($sformatf("M w=32 dst=%h src=%h: C/Z got %b%b", r_dst, r_src, m_flag_c, m_flag_z));
          fin_check($sformatf("M w=%0d dst=%h src=%h delay=%0d", r_width, r_dst, r_src, r_delay), 0, m_product, 0);
          report("M");
        end
      end else if (tok == "D") begin
        n = $fscanf(fd, "%d %h %h %d %d %d %d %d %d %d %h %h", r_width, r_dividend, r_divisor, r_delay, r_ticks,
                    r_dbz, r_ovf, r_wide, r_qneg, r_qzero, r_quot, r_rem);
        // As for M: the divisor arrives where the CPU gives it, and the
        // clocks to done are the CPU's (Jan83 6-47/6-48 less the program's 3).
        for (k = 0; k < r_ticks; k++) n = $fscanf(fd, "%d", remv);
        r_delay = (r_width == 32) ? m_arr_l[total % 4] : m_arr_w[total % 4];
        if (r_dbz[0])                exp_ticks = (r_width == 32) ? 27 : 10;
        else if (r_ovf[0])           exp_ticks = (r_width == 32) ? 48 : 22;
        else                         exp_ticks = (r_width == 32) ? 741 : 104;
        reset_dut();
        @(negedge clk);
        d_n32 = (r_width == 32); d_dividend = r_dividend; d_divisor = r_divisor[31:0];
        kind = 2; d_start = 1; x_hi = d_n32 && r_delay == 0;
        tick(); d_start = 0; x_hi = 0;
        ticks = 0; fin_at = -1;
        for (k = 0; k < exp_ticks; k++) begin
          @(negedge clk);
          d_src_valid = (k == r_delay);
          x_hi = d_n32 && k == r_delay - 1;
          tick(); d_src_valid = 0; x_hi = 0; ticks++;
          if (only == "" || only == "D") begin
            if (d_fin) begin
              fin_at = k; fin_res = {d_quot, d_rem}; fin_flg = {d_dbz, d_ovf, d_wide, d_qneg, d_qzero};
            end
            if (d_done && k != exp_ticks - 1)
              mismatch($sformatf("D n=%0d dvd=%h dvr=%h delay=%0d: done early at tick %0d (exp %0d)", r_width, r_dividend, r_divisor, r_delay, ticks, exp_ticks));
          end
        end
        if (only == "" || only == "D") begin
          if (!d_done) mismatch($sformatf("D n=%0d dvd=%h dvr=%h delay=%0d: not done after %0d ticks", r_width, r_dividend, r_divisor, r_delay, exp_ticks));
          if (d_dbz != r_dbz[0] || d_ovf != r_ovf[0] || d_wide != r_wide[0] || d_qneg != r_qneg[0] || d_qzero != r_qzero[0])
            mismatch($sformatf("D n=%0d dvd=%h dvr=%h: flags dbz/ovf/wide/qneg/qzero exp=%0d%0d%0d%0d%0d got=%0d%0d%0d%0d%0d",
                     r_width, r_dividend, r_divisor, r_dbz, r_ovf, r_wide, r_qneg, r_qzero, d_dbz, d_ovf, d_wide, d_qneg, d_qzero));
          // Divide by zero hands the dividend back unchanged.
          if (r_dbz[0]) begin
            if (r_width == 16 ? {d_rem[15:0], d_quot[15:0]} !== r_dividend[31:0] : {d_rem, d_quot} !== r_dividend[63:0])
              mismatch($sformatf("D n=%0d dvd=%h dvr=%h: dividend back exp=%h got=%h:%h", r_width, r_dividend, r_divisor, r_dividend, d_rem, d_quot));
          end
          if (!r_dbz[0] && !r_ovf[0]) begin
            if ((r_width == 16 ? 32'(d_quot[15:0]) : d_quot) !== (r_width == 16 ? 32'(r_quot[15:0]) : r_quot[31:0]))
              mismatch($sformatf("D n=%0d dvd=%h dvr=%h: quotient exp=%h got=%h", r_width, r_dividend, r_divisor, r_quot, d_quot));
            if ((r_width == 16 ? 32'(d_rem[15:0]) : d_rem) !== (r_width == 16 ? 32'(r_rem[15:0]) : r_rem[31:0]))
              mismatch($sformatf("D n=%0d dvd=%h dvr=%h: remainder exp=%h got=%h", r_width, r_dividend, r_divisor, r_rem, d_rem));
          end
          fin_check($sformatf("D n=%0d dvd=%h dvr=%h delay=%0d", r_width, r_dividend, r_divisor, r_delay),
                    0, {d_quot, d_rem}, {d_dbz, d_ovf, d_wide, d_qneg, d_qzero});
          report("D");
        end
      end else if (tok == "S") begin
        n = $fscanf(fd, "%d %h %h %d %d %h %h %h", r_width, r_op, r_val, r_count, r_ticks, r_result, r_flags, r_mask);
        exp_ticks = r_ticks;
        reset_dut();
        @(negedge clk);
        s_width = (r_width == 8) ? WIDTH_BYTE : (r_width == 16) ? WIDTH_WORD : WIDTH_LONG;
        s_op = r_op[ALUOP_W-1:0]; s_val = r_val[31:0]; s_count = r_count[5:0];
        kind = 0; s_start = 1; tick(); s_start = 0;
        ticks = 0;
        for (k = 0; k < exp_ticks; k++) begin
          @(negedge clk); tick(); ticks++;
          if ((only == "" || only == "S") && s_done && k != exp_ticks - 1)
            mismatch($sformatf("S w=%0d op=%0d val=%h n=%0d: done early at tick %0d (exp %0d)", r_width, r_op, r_val, r_count, ticks, exp_ticks));
        end
        if (only == "" || only == "S") begin
          if (!s_done) mismatch($sformatf("S w=%0d op=%0d val=%h n=%0d: not done after %0d ticks", r_width, r_op, r_val, r_count, exp_ticks));
          if (s_result !== r_result[31:0] || s_mask !== r_mask || (s_flags & r_mask) !== (r_flags & r_mask))
            mismatch($sformatf("S w=%0d op=%0d val=%h n=%0d: result exp=%h got=%h flags exp=%04X got=%04X mask exp=%04X got=%04X",
                     r_width, r_op, r_val, r_count, r_result, s_result, r_flags & r_mask, s_flags & r_mask, r_mask, s_mask));
          report("S");
        end
      end else begin
        $display("RESULT FAIL tb_serial %s: unexpected token %s", vecfile, tok);
        $finish;
      end
    end
    $fclose(fd);
    if (only == "" || only == "M") begin
      mult_case(0, 32'h0000_1234, 32'h0000_8765, 32'h0000_0003, 32'h0000_FFFF, 32'h0000_7FFF);
      mult_case(0, 32'h0000_8001, 32'h0000_0000, 32'h0000_1111, 32'h0000_0037, 32'h0000_8000);
      mult_case(1, 32'h8000_0001, 32'h7FFF_FFFF, 32'h0000_0001, 32'h1234_5678, 32'hFEDC_BA98);
    end
    if (only == "" || only == "D") begin
      div_case(0, 64'h0001_2345, 32'h0000_0123, 32'h0000_0007, 64'hFFFF_8000, 32'hFFFF_FFF9);
      div_case(0, 64'h0000_9C40, 32'h0000_0001, 32'h0000_0003, 64'h0000_0000, 32'h0000_0000);
      div_case(1, 64'h0000_0123_4567_89AB, 32'h0012_3456, 32'h0000_0005, 64'hFFFF_FFFF_8000_0000, 32'hFFFF_FFF9);
    end
    if (only == "" || only == "S") begin
      shift_case(WIDTH_BYTE, OP_SLL, 32'h0000_0040, 6'd1, WIDTH_WORD);
      shift_case(WIDTH_WORD, OP_SLA, 32'h0000_4001, 6'd1, WIDTH_BYTE);
      shift_case(WIDTH_LONG, OP_SRA, 32'h8000_0000, 6'd4, WIDTH_BYTE);
      shift_case(WIDTH_BYTE, OP_SRL, 32'h0000_0081, 6'd0, WIDTH_LONG);
      shift_b2b(WIDTH_WORD, OP_SLA, 32'h0000_4001, 6'd1, WIDTH_WORD, OP_SLA, 32'h0000_0001, 6'd1);
      shift_b2b(WIDTH_BYTE, OP_SLL, 32'h0000_0081, 6'd3, WIDTH_LONG, OP_SRA, 32'h8000_0001, 6'd0);
    end
    $display("  %0d operations end on done alone (operand late)", fin_late);
    if (bad == 0) $display("RESULT PASS tb_serial %s: %0d operations", vecfile, total);
    else          $display("RESULT FAIL tb_serial %s: %0d of %0d operations mismatched", vecfile, bad, total);
    $finish;
  end
endmodule
