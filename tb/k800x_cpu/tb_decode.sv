// tb_decode -- exhaustive decode-ROM equivalence.
//
// Replays vectors/k800x_cpu/decode/decode.vec through z8000_decode. A '-'
// w1 nibble means the result does not depend on word 2; both 0 and F are then applied.
// Reports every mismatch (capped) with the field-by-field diff of the
// packed control word, then PASS/FAIL. Run: make test-decode  (or
// obj_dir/tb_decode +vec=vectors/k800x_cpu/decode/decode.vec)

module tb_decode
  import z8000_ctrl_pkg::*;
;
  logic [15:0] w0;
  logic [3:0]  w1_lo;
  ctrl_word_t  ctrl;

  z8000_decode dut (.w0(w0), .w1_lo(w1_lo), .ctrl(ctrl));

  string vecfile;
  int fd, n, total, bad, shown;
  string line;
  logic [15:0] r_w0;
  logic [3:0]  r_w1v;
  string r_w1;
  logic [CTRL_W-1:0] want;

  function automatic void show_diff(input logic [CTRL_W-1:0] exp, input logic [CTRL_W-1:0] got);
    ctrl_word_t e, g;
    e = ctrl_word_t'(exp);
    g = ctrl_word_t'(got);
    if (e.valid       != g.valid)       $display("      valid       exp=%0d got=%0d", e.valid, g.valid);
    if (e.exec        != g.exec)        $display("      exec        exp=%0d got=%0d", e.exec, g.exec);
    if (e.alu_op      != g.alu_op)      $display("      alu_op      exp=%0d got=%0d", e.alu_op, g.alu_op);
    if (e.width       != g.width)       $display("      width       exp=%0d got=%0d", e.width, g.width);
    if (e.priv        != g.priv)        $display("      priv        exp=%0d got=%0d", e.priv, g.priv);
    if (e.src2        != g.src2)        $display("      src2        exp=%0d got=%0d", e.src2, g.src2);
    if (e.dst         != g.dst)         $display("      dst         exp=%0d got=%0d", e.dst, g.dst);
    if (e.count       != g.count)       $display("      count       exp=%0d got=%0d", e.count, g.count);
    if (e.src1_nib    != g.src1_nib)    $display("      src1_nib    exp=%0d got=%0d", e.src1_nib, g.src1_nib);
    if (e.src2_nib    != g.src2_nib)    $display("      src2_nib    exp=%0d got=%0d", e.src2_nib, g.src2_nib);
    if (e.dst_nib     != g.dst_nib)     $display("      dst_nib     exp=%0d got=%0d", e.dst_nib, g.dst_nib);
    if (e.fcw_op      != g.fcw_op)      $display("      fcw_op      exp=%0d got=%0d", e.fcw_op, g.fcw_op);
    if (e.fcw_mask    != g.fcw_mask)    $display("      fcw_mask    exp=%04X got=%04X", e.fcw_mask, g.fcw_mask);
    if (e.stk_mode    != g.stk_mode)    $display("      stk_mode    exp=%0d got=%0d", e.stk_mode, g.stk_mode);
    if (e.br_mode     != g.br_mode)     $display("      br_mode     exp=%0d got=%0d", e.br_mode, g.br_mode);
    if (e.io_write    != g.io_write)    $display("      io_write    exp=%0d got=%0d", e.io_write, g.io_write);
    if (e.io_spec     != g.io_spec)     $display("      io_spec     exp=%0d got=%0d", e.io_spec, g.io_spec);
    if (e.block_decr  != g.block_decr)  $display("      block_decr  exp=%0d got=%0d", e.block_decr, g.block_decr);
    if (e.block_rept  != g.block_rept)  $display("      block_rept  exp=%0d got=%0d", e.block_rept, g.block_rept);
    if (e.mp_op       != g.mp_op)       $display("      mp_op       exp=%0d got=%0d", e.mp_op, g.mp_op);
    if (e.epu_kind    != g.epu_kind)    $display("      epu_kind    exp=%0d got=%0d", e.epu_kind, g.epu_kind);
  endfunction

  task automatic check_one(input logic [15:0] tw0, input logic [3:0] tw1);
    w0 = tw0;
    w1_lo = tw1;
    #1;
    total++;
    if (ctrl !== ctrl_word_t'(want)) begin
      bad++;
      if (shown < 20) begin
        shown++;
        $display("  MISMATCH w0=%04X w1_lo=%X exp=%h got=%h", tw0, tw1, want, ctrl);
        show_diff(want, ctrl);
      end
    end
  endtask

  initial begin
    if (!$value$plusargs("vec=%s", vecfile)) vecfile = "vectors/k800x_cpu/decode/decode.vec";
    fd = $fopen(vecfile, "r");
    if (fd == 0) begin
      $display("RESULT FAIL tb_decode: cannot open %s", vecfile);
      $finish;
    end
    total = 0; bad = 0; shown = 0;
    while ($fgets(line, fd) != 0) begin
      if (line.len() < 2 || line.substr(0, 1) != "D ") continue;
      n = $sscanf(line, "D %h %s %h", r_w0, r_w1, want);
      if (n != 3) begin
        $display("RESULT FAIL tb_decode: bad line: %s", line);
        $finish;
      end
      if (r_w1 == "-") begin
        check_one(r_w0, 4'h0);
        check_one(r_w0, 4'hF);
      end else begin
        r_w1v = 4'(r_w1.atohex());
        check_one(r_w0, r_w1v);
      end
    end
    $fclose(fd);
    if (bad == 0) $display("RESULT PASS tb_decode: %0d checks", total);
    else          $display("RESULT FAIL tb_decode: %0d of %0d checks mismatched", bad, total);
    $finish;
  end
endmodule
