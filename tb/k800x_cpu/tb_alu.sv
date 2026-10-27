// tb_alu -- combinational ALU vs the Go golden ALU (sim/cpu/alu).
//
// Replays one "A" vector file (vectors/k800x_cpu/alu/*.vec = the alu package's own
// tests + constrained random; vectors/k800x_cpu/alu_from_cpu/*.vec = every Execute
// call the CPU tests made) through z8000_alu. Checks value exactly and
// flags under the affected-flag mask; the mask itself must match exactly.
// Prints the first 20 mismatches with the op decoded, then RESULT.
//   obj_dir/tb_alu/tb_alu +vec=vectors/k800x_cpu/alu/random.vec

module tb_alu
  import z8000_ctrl_pkg::*;
;
  logic [ALUOP_W-1:0] op;
  logic [1:0]         width;
  logic [63:0]        a, b;
  logic               cin;
  logic [63:0]        value;
  logic [15:0]        flags, flags_mask;

  z8000_alu dut (.op(op), .width(width), .a(a), .b(b), .cin(cin),
                 .value(value), .flags(flags), .flags_mask(flags_mask));

  string vecfile, line;
  int fd, n, total, bad, shown;
  logic [7:0]  r_op, r_w;
  logic [63:0] r_a, r_b, r_val;
  int          r_cin;
  logic [15:0] r_flags, r_mask;

  function automatic string opname(input logic [ALUOP_W-1:0] o);
    case (o)
      OP_ADD: return "ADD";   OP_ADC: return "ADC";   OP_SUB: return "SUB";   OP_SBC: return "SBC";
      OP_AND: return "AND";   OP_OR:  return "OR";    OP_XOR: return "XOR";   OP_COM: return "COM";
      OP_NEG: return "NEG";   OP_TEST: return "TEST"; OP_CP:  return "CP";    OP_INC: return "INC";
      OP_DEC: return "DEC";   OP_SLA: return "SLA";   OP_SRA: return "SRA";   OP_SLL: return "SLL";
      OP_SRL: return "SRL";   OP_RL:  return "RL";    OP_RR:  return "RR";    OP_RLC: return "RLC";
      OP_RRC: return "RRC";   OP_DAB: return "DAB";   OP_EXTS: return "EXTS"; OP_LD:  return "LD";
      OP_BIT: return "BIT";   OP_SET: return "SET";   OP_RES: return "RES";   OP_TSET: return "TSET";
      default: return "OP?";
    endcase
  endfunction

  function automatic string wname(input logic [1:0] w);
    case (w)
      WIDTH_BYTE: return "B"; WIDTH_WORD: return "W"; WIDTH_LONG: return "L"; default: return "?";
    endcase
  endfunction

  // Go alu.Width is 1/2/4; the RTL code is 1/2/3.
  function automatic logic [1:0] wcode(input logic [7:0] gw);
    case (gw)
      8'd1: return WIDTH_BYTE; 8'd2: return WIDTH_WORD; 8'd4: return WIDTH_LONG; default: return WIDTH_NONE;
    endcase
  endfunction

  initial begin
    if (!$value$plusargs("vec=%s", vecfile)) vecfile = "vectors/k800x_cpu/alu/random.vec";
    fd = $fopen(vecfile, "r");
    if (fd == 0) begin
      $display("RESULT FAIL tb_alu %s: cannot open", vecfile);
      $finish;
    end
    total = 0; bad = 0; shown = 0;
    while ($fgets(line, fd) != 0) begin
      if (line.len() < 2 || line.substr(0, 1) != "A ") continue;
      n = $sscanf(line, "A %h %h %h %d %h %h %h %h", r_op, r_a, r_b, r_cin, r_w, r_val, r_flags, r_mask);
      if (n != 8) begin
        $display("RESULT FAIL tb_alu %s: bad line: %s", vecfile, line);
        $finish;
      end
      op = r_op[ALUOP_W-1:0];
      width = wcode(r_w);
      a = r_a; b = r_b; cin = (r_cin != 0);
      #1;
      total++;
      if (value !== r_val || flags_mask !== r_mask || (flags & r_mask) !== (r_flags & r_mask)) begin
        bad++;
        if (shown < 20) begin
          shown++;
          $display("  MISMATCH %s.%s a=%h b=%h cin=%0d: value exp=%h got=%h | flags exp=%04X got=%04X (mask exp=%04X got=%04X)",
                   opname(op), wname(width), a, b, cin, r_val, value, r_flags & r_mask, flags & r_mask, r_mask, flags_mask);
        end
      end
    end
    $fclose(fd);
    if (bad == 0) $display("RESULT PASS tb_alu %s: %0d checks", vecfile, total);
    else          $display("RESULT FAIL tb_alu %s: %0d of %0d checks mismatched", vecfile, bad, total);
    $finish;
  end
endmodule
