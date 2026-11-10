// tb_fpu_enc -- the RTL decode equals the vector decode over every input.
//
// Replays vectors/k8070_fpu/enc/enc.vec: for each IF1 high byte, a digest of the template decode of all
// 256 words; for each template x word-1 bits 7:4 x operation code, a digest
// of the plan for all 1024 word 2s (rounding, register, n-1). Values are
// packed as the generator packs them; an invalid plan packs to 0.
//
// Run: make test-fpu-enc

`default_nettype none

module tb_fpu_enc;
  import z8070_enc_pkg::*;

  logic [15:0] if1 = 16'h0000;
  logic        if1_epa, if1_ok;
  tpl_e        if1_tpl;
  logic [1:0]  if1_id;
  tpl_e        tpl = TPL_MEM_FROM_EPU;
  logic [7:4]  w1  = 4'h0;
  logic [15:0] w2  = 16'h0000;
  logic        plan_ok;
  mn_e         mn;
  logic [2:0]  fd, fs;
  fmt_e        fmt;
  logic [1:0]  rnd;
  logic [3:0]  sel;
  logic [7:0]  list_byte;
  dir_e        dir;
  logic [3:0]  words;

  z8070_dec dut (
    .if1_op(if1[15:8]), .if1_dir_id(if1[3:0]), .if1_epa(if1_epa), .if1_ok(if1_ok), .if1_tpl(if1_tpl), .if1_id(if1_id),
    .tpl(tpl), .w1(w1), .w2(w2), .plan_ok(plan_ok), .mn(mn), .fd(fd), .fs(fs),
    .fmt(fmt), .rnd(rnd), .sel(sel), .list_byte(list_byte), .dir(dir), .words(words)
  );

  function automatic longint unsigned fnv_add(input longint unsigned h, input longint unsigned v);
    for (int i = 0; i < 8; i++) begin
      h = h ^ ((v >> (8 * i)) & 64'hFF);
      h = h * 64'h0000_0100_0000_01B3;
    end
    return h;
  endfunction

  localparam longint unsigned FNV0 = 64'hCBF2_9CE4_8422_2325;

  function automatic longint unsigned pack_plan();
    if (!plan_ok) return 64'd0;
    return (64'd1 << 39) | (64'(mn) << 33) | (64'(tpl) << 30) | (64'(fd) << 27) |
           (64'(fs) << 24) | (64'(fmt) << 20) | (64'(rnd) << 18) | (64'(sel) << 14) |
           (64'(list_byte) << 6) | (64'(dir) << 4) | 64'(words);
  endfunction

  function automatic longint unsigned pack_tpl();
    return (64'(if1_epa) << 6) | (if1_ok ? ((64'd1 << 5) | (64'(if1_tpl) << 2)) : 64'd0) |
           64'(if1_id);
  endfunction

  int fh, n, wlines, plines, fails, valid, got_valid;
  string line, tag;
  int unsigned a, b, c;
  longint unsigned want, h;

  initial begin
    fails = 0; wlines = 0; plines = 0;
    fh = $fopen("vectors/k8070_fpu/enc/enc.vec", "r");
    if (fh == 0) begin
      $display("RESULT FAIL tb_fpu_enc: cannot open vectors/k8070_fpu/enc/enc.vec");
      $finish;
    end
    while ($fgets(line, fh) > 0) begin
      if (line.len() == 0 || line[0] == "#" || line[0] == "K") continue;
      if (line[0] == "E") break;
      if (line[0] == "W") begin
        n = $sscanf(line, "%s %h %h", tag, a, want);
        h = FNV0;
        for (int lo = 0; lo < 256; lo++) begin
          if1 = {a[7:0], lo[7:0]};
          #1;
          h = fnv_add(h, pack_tpl());
        end
        wlines++;
        if (h != want) begin
          fails++;
          if (fails <= 20) $display("  FAIL IF1 %02h__: digest %016h, want %016h", a[7:0], h, want);
        end
      end else if (line[0] == "P") begin
        n = $sscanf(line, "%s %d %h %h %d %h", tag, a, b, c, valid, want);
        tpl = tpl_e'(a[2:0]);
        w1  = b[3:0];
        h = FNV0;
        got_valid = 0;
        for (int r = 0; r < 1024; r++) begin
          w2 = {c[5:4], r[9:8], r[7:4], c[3:0], r[3:0]};
          #1;
          if (plan_ok) got_valid++;
          h = fnv_add(h, pack_plan());
        end
        plines++;
        if (h != want) begin
          fails++;
          if (fails <= 20)
            $display("  FAIL template %0d, word 1 bits 7:4 = %h, code %02h: %0d valid (want %0d), digest %016h, want %016h",
                     a, b[3:0], c[5:0], got_valid, valid, h, want);
        end
      end
    end
    $fclose(fh);
    if (wlines != 256 || plines != 7 * 16 * 64) begin
      $display("RESULT FAIL tb_fpu_enc: %0d IF1 and %0d plan lines, want 256 and 7168", wlines, plines);
    end else if (fails == 0)
      $display("RESULT PASS tb_fpu_enc: IF1 65536 words, plans 7 templates x 16 x 65536 word 2s (7168 digests)");
    else
      $display("RESULT FAIL tb_fpu_enc: %0d of %0d digests differ", fails, wlines + plines);
    $finish;
  end
endmodule

`default_nettype wire
