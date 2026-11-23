// tb_decode_table -- proves the committed decode ROM against the committed
// DECODE TABLE, using nothing outside this repo.
//
// rtl/k800x_cpu/z8000_decode_table.txt states the decoder symbolically: 446
// distinct control words, each with its fields named, over a few thousand
// first-word ranges. It is the file a human reads and reviews when the
// decoder changes. This bench makes it load-bearing rather than commentary:
// it expands every range and checks z8000_decode_rom_gen against it for all
// 65536 first words.
//
// Run: make test-decode-table
//      obj_dir/tb_decode_table/tb_decode_table +table=<path>

module tb_decode_table
  import z8000_ctrl_pkg::*;
;
  logic [15:0] w0;
  ctrl_word_t  ctrl;

  z8000_decode_rom_gen dut (.w0(w0), .ctrl(ctrl));

  string tblfile;
  int    fd, n, ncw, nrange, total, bad, shown;
  string line, nm;
  logic [CTRL_W-1:0] val, want;
  logic [15:0] lo, hi;
  int unsigned iw0;

  // NAME -> packed control word, from the "ctrl" records.
  logic [CTRL_W-1:0] byname [string];

  task automatic check_one(input logic [15:0] tw0, input logic [CTRL_W-1:0] exp,
                           input string cw);
    w0 = tw0;
    #1;
    total++;
    if (ctrl !== ctrl_word_t'(exp)) begin
      bad++;
      if (shown < 20) begin
        shown++;
        $display("  MISMATCH w0=%04X  table says %s = %h", tw0, cw, exp);
        $display("           ROM gives %h", ctrl);
      end
    end
  endtask

  initial begin
    if (!$value$plusargs("table=%s", tblfile))
      tblfile = "rtl/k800x_cpu/z8000_decode_table.txt";
    fd = $fopen(tblfile, "r");
    if (fd == 0) begin
      $display("RESULT FAIL tb_decode_table: cannot open %s", tblfile);
      $finish;
    end

    ncw = 0; nrange = 0; total = 0; bad = 0; shown = 0;
    while ($fgets(line, fd) != 0) begin
      n = $sscanf(line, "ctrl %s %h", nm, val);
      if (n == 2) begin
        if (byname.exists(nm)) begin
          $display("RESULT FAIL tb_decode_table: duplicate control word name %s", nm);
          $finish;
        end
        byname[nm] = val;
        ncw++;
        continue;
      end
      n = $sscanf(line, "range %h %h %s", lo, hi, nm);
      if (n != 3) continue;
      if (!byname.exists(nm)) begin
        $display("RESULT FAIL tb_decode_table: range names unknown control word %s", nm);
        $finish;
      end
      nrange++;
      want = byname[nm];
      for (iw0 = lo; iw0 <= hi; iw0++)
        check_one(16'(iw0), want, nm);
    end
    $fclose(fd);

    if (ncw == 0 || nrange == 0) begin
      $display("RESULT FAIL tb_decode_table: %s has %0d control words, %0d ranges",
               tblfile, ncw, nrange);
      $finish;
    end
    $display("tb_decode_table -- %0d control words, %0d range records, %0d checks",
             ncw, nrange, total);
    if (bad == 0) $display("RESULT PASS tb_decode_table: %0d checks", total);
    else          $display("RESULT FAIL tb_decode_table: %0d of %0d checks mismatched", bad, total);
    $finish;
  end
endmodule
