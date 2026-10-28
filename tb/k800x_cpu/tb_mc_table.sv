// tb_mc_table -- proves the committed machine-cycle program ROM against the
// committed table rtl/k800x_cpu/z8000_mc_table.txt, using nothing outside
// this repo.
//
// Every "range" record is expanded over its first words (a '-' in the w1
// column is checked against all 16 nibbles), every "prog" record checks
// the program a form runs in one column and path, and every "cycle" record
// one ROM entry. The ranges must cover every first word and second-word
// nibble once (a first word keyed on w1 needs all 16 nibbles) and the prog
// records every form, column and path once.
//
// Run: make test-mc-table
//      obj_dir/tb_mc_table/tb_mc_table +table=<path>

module tb_mc_table
  import z8000_mc_pkg::*;
;
  logic [15:0]          w0;
  logic [3:0]           w1_lo;
  logic [MC_FORM_W-1:0] form, pform;
  mc_col_e              col;
  mc_path_e             path;
  logic [MC_PROG_W-1:0] prog, cprog;
  logic [MC_POS_W-1:0]  pos;
  mc_cycle_t            cyc;
  mc_link_t             link;

  z8000_mc_index_gen u_index (.w0(w0), .w1_lo(w1_lo), .form(form));
  z8000_mc_prog_gen  u_prog  (.form(pform), .col(col), .path(path), .prog(prog));
  z8000_mc_cycle_gen u_cycle (.prog(cprog), .pos(pos), .cyc(cyc));
  z8000_mc_link_gen  u_link  (.prog(cprog), .pos(pos), .link(link));

  string tblfile, line, w1tok, colt, patht, kindt;
  int    fd, n, total, bad, shown, nforms, nprog, ncyc, nrange, nkeyed;
  int    f, p, ps, clocks, reps, nm, nd, fm, fdn, k, k0, k1;
  int unsigned lo, hi, iw;
  logic [15:0] seen_w1 [65536];   // second-word nibbles listed per first word
  bit    keyed [65536];
  bit    seen_prog [int];

  function automatic mc_kind_e kind_of(input string s);
    unique case (s)
      "F1":    return MC_F1;
      "Fn":    return MC_FN;
      "Fa":    return MC_FA;
      "R":     return MC_R;
      "W":     return MC_W;
      "IO":    return MC_IO;
      "EPU":   return MC_EPU;
      "AF":    return MC_AF;
      "I":     return MC_I;
      "IA":    return MC_IA;
      default: return MC_F1;
    endcase
  endfunction

  function automatic mc_col_e col_of(input string s);
    return (s == "SL") ? MC_COL_SL : (s == "SS") ? MC_COL_SS : MC_COL_NS;
  endfunction

  function automatic mc_path_e path_of(input string s);
    return (s == "not_taken") ? MC_PATH_NOT_TAKEN : (s == "zero") ? MC_PATH_ZERO :
           (s == "overflow") ? MC_PATH_OVERFLOW : MC_PATH_DEFAULT;
  endfunction

  task automatic fail(input string what);
    bad++;
    if (shown < 20) begin
      shown++;
      $display("  MISMATCH %s", what);
    end
  endtask

  initial begin
    if (!$value$plusargs("table=%s", tblfile))
      tblfile = "rtl/k800x_cpu/z8000_mc_table.txt";
    fd = $fopen(tblfile, "r");
    if (fd == 0) begin
      $display("RESULT FAIL tb_mc_table: cannot open %s", tblfile);
      $finish;
    end
    for (iw = 0; iw < 65536; iw++) seen_w1[iw] = 16'h0000;
    total = 0; bad = 0; shown = 0; nforms = 0; nprog = 0; ncyc = 0; nrange = 0;
    while ($fgets(line, fd) != 0) begin
      if ($sscanf(line, "form %d", f) == 1) begin
        nforms++;
        continue;
      end
      n = $sscanf(line, "prog %d %s %s %d", f, colt, patht, p);
      if (n == 4) begin
        pform = MC_FORM_W'(f);
        col   = col_of(colt);
        path  = path_of(patht);
        #1;
        total++; nprog++;
        if (seen_prog.exists(f * 16 + int'(col) * 4 + int'(path)))
          fail($sformatf("prog %0d %s %s listed twice", f, colt, patht));
        seen_prog[f * 16 + int'(col) * 4 + int'(path)] = 1'b1;
        if (prog !== MC_PROG_W'(p))
          fail($sformatf("prog %0d %s %s: table %0d, ROM %0d", f, colt, patht, p, prog));
        continue;
      end
      n = $sscanf(line, "cycle %d %d %s %d %d %d %d %d %d", p, ps, kindt, clocks, reps, nm, nd, fm, fdn);
      if (n == 9) begin
        cprog = MC_PROG_W'(p);
        pos   = MC_POS_W'(ps);
        #1;
        total++; ncyc++;
        if (cyc.kind !== kind_of(kindt) || cyc.clocks !== MC_CLOCKS_W'(clocks) ||
            link.reps !== MC_REPS_W'(reps) || link.next_more !== MC_POS_W'(nm) ||
            link.next_done !== MC_POS_W'(nd) || link.fin_more !== 1'(fm) || link.fin_done !== 1'(fdn))
          fail($sformatf("cycle %0d %0d: table %s %0d x%0d -> %0d/%0d fin %0d/%0d, ROM %0d %0d x%0d -> %0d/%0d fin %0d/%0d",
                         p, ps, kindt, clocks, reps, nm, nd, fm, fdn, cyc.kind, cyc.clocks, link.reps,
                         link.next_more, link.next_done, link.fin_more, link.fin_done));
        continue;
      end
      n = $sscanf(line, "range %h %h %s %d", lo, hi, w1tok, f);
      if (n != 4) continue;
      nrange++;
      if (w1tok == "-") begin k0 = 0; k1 = 15; end
      else begin k0 = int'(w1tok.atohex()); k1 = k0; end
      for (iw = lo; iw <= hi; iw++) begin
        for (k = k0; k <= k1; k++) begin
          if (seen_w1[iw][k]) fail($sformatf("w0=%04X w1_lo=%0X in two ranges", iw, k));
          seen_w1[iw][k] = 1'b1;
          if (w1tok != "-") keyed[iw] = 1'b1;
          w0    = 16'(iw);
          w1_lo = 4'(k);
          #1;
          total++;
          if (form !== MC_FORM_W'(f))
            fail($sformatf("w0=%04X w1_lo=%X: table form %0d, ROM %0d", iw, k, f, form));
        end
      end
    end
    $fclose(fd);

    nkeyed = 0;
    for (iw = 0; iw < 65536; iw++) begin
      if (seen_w1[iw] == 16'h0000) fail($sformatf("first word %04X in no range", iw));
      else if (seen_w1[iw] != 16'hFFFF)
        fail($sformatf("first word %04X: w1 nibbles %04X only", iw, seen_w1[iw]));
      else if (keyed[iw]) nkeyed++;
    end
    if (nprog != nforms * 12)
      fail($sformatf("%0d prog records for %0d forms", nprog, nforms));
    if (nforms == 0 || ncyc == 0 || nrange == 0)
      fail($sformatf("%0d forms, %0d cycles, %0d ranges", nforms, ncyc, nrange));

    $display("tb_mc_table -- %0d forms, %0d prog, %0d cycle, %0d range records, %0d first words keyed on w1",
             nforms, nprog, ncyc, nrange, nkeyed);
    if (bad == 0) $display("RESULT PASS tb_mc_table: %0d checks", total);
    else          $display("RESULT FAIL tb_mc_table: %0d of %0d checks mismatched", bad, total);
    $finish;
  end
endmodule
