// tb_alu -- combinational ALU vs the ALU vectors.
//
// Replays one "A" vector file (vectors/k800x_cpu/alu/*.vec = directed
// tests + constrained random; vectors/k800x_cpu/alu_from_cpu/*.vec = every Execute
// call the CPU tests made) through z8000_alu. Checks value exactly and
// flags under the affected-flag mask; the mask itself must match exactly.
//
// Records the CPU never issues to the ALU (multi-bit shifts, EXTS, long
// forms other than ADD/ADC/SUB/SBC/CP/TEST/LD, rotate counts other than 1-2,
// bit numbers above 15) are skipped and counted. A long record runs as two
// word passes composed the way the sequencer does it (see the ALU header).
// Prints the first 20 mismatches with the op decoded, then RESULT.
//   obj_dir/tb_alu/tb_alu +vec=vectors/k800x_cpu/alu/random.vec

module tb_alu
  import z8000_ctrl_pkg::*;
;
  logic [ALUOP_W-1:0] op;
  logic [1:0]         width;
  logic [15:0]        a, b;
  logic               cin;
  logic [15:0]        value;
  logic [15:0]        flags, flags_mask;

  z8000_alu dut (.op(op), .width(width), .a(a), .b(b), .cin(cin),
                 .value(value), .flags(flags), .flags_mask(flags_mask));

  string vecfile, line;
  int fd, n, total, bad, shown, skipped, twopass;
  logic [7:0]  r_op, r_w;
  logic [63:0] r_a, r_b, r_val, got_val;
  int          r_cin;
  logic [15:0] r_flags, r_mask, got_f, got_m, lo_f;
  logic [ALUOP_W-1:0] r_aluop;

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

  // The vector width is 1/2/4 bytes; the RTL code is 1/2/3.
  function automatic logic [1:0] wcode(input logic [7:0] gw);
    case (gw)
      8'd1: return WIDTH_BYTE; 8'd2: return WIDTH_WORD; 8'd4: return WIDTH_LONG; default: return WIDTH_NONE;
    endcase
  endfunction

  // The (op, width, operand) combinations the CPU issues to the ALU.
  function automatic logic in_contract(input logic [ALUOP_W-1:0] o, input logic [7:0] gw,
                                       input logic [63:0] bb);
    logic lng;
    lng = (gw == 8'd4);
    if (gw != 8'd1 && gw != 8'd2 && gw != 8'd4) return 1'b0;
    case (o)
      OP_ADD, OP_ADC, OP_SUB, OP_SBC, OP_CP, OP_TEST, OP_LD: return 1'b1;
      OP_AND, OP_OR, OP_XOR, OP_COM, OP_NEG, OP_TSET:        return !lng;
      OP_INC, OP_DEC:                return !lng && bb >= 64'd1 && bb <= 64'd16;
      OP_RL, OP_RR, OP_RLC, OP_RRC:  return !lng && (bb == 64'd1 || bb == 64'd2);
      OP_BIT, OP_SET, OP_RES:        return !lng && bb < 64'd16;
      OP_DAB:                        return gw == 8'd1;
      default:                       return 1'b0;
    endcase
  endfunction

  // Opcode of the high pass of a long op.
  function automatic logic [ALUOP_W-1:0] hi_op(input logic [ALUOP_W-1:0] o);
    case (o)
      OP_ADD, OP_ADC:        return OP_ADC;
      OP_SUB, OP_SBC, OP_CP: return OP_SBC;
      default:               return o;
    endcase
  endfunction

  initial begin
    if (!$value$plusargs("vec=%s", vecfile)) vecfile = "vectors/k800x_cpu/alu/random.vec";
    fd = $fopen(vecfile, "r");
    if (fd == 0) begin
      $display("RESULT FAIL tb_alu %s: cannot open", vecfile);
      $finish;
    end
    total = 0; bad = 0; shown = 0; skipped = 0; twopass = 0;
    while ($fgets(line, fd) != 0) begin
      if (line.len() < 2 || line.substr(0, 1) != "A ") continue;
      n = $sscanf(line, "A %h %h %h %d %h %h %h %h", r_op, r_a, r_b, r_cin, r_w, r_val, r_flags, r_mask);
      if (n != 8) begin
        $display("RESULT FAIL tb_alu %s: bad line: %s", vecfile, line);
        $finish;
      end
      r_aluop = r_op[ALUOP_W-1:0];
      if (!in_contract(r_aluop, r_w, r_b)) begin
        skipped++;
        continue;
      end
      total++;
      if (r_w == 8'd4) begin
        twopass++;
        op    = (r_aluop == OP_CP) ? OP_SUB : r_aluop;
        width = WIDTH_WORD;
        a = r_a[15:0]; b = r_b[15:0]; cin = (r_cin != 0);
        #1;
        got_val = {48'd0, value};
        lo_f    = flags;
        op = hi_op(r_aluop);
        a  = r_a[31:16]; b = r_b[31:16];
        if (op == OP_ADC || op == OP_SBC) cin = lo_f[7];
        #1;
        got_val = {32'd0, value, got_val[15:0]};
        got_f   = (flags & ~16'h0040) | (flags & lo_f & 16'h0040);
        got_m   = flags_mask;
      end else begin
        op    = r_aluop;
        width = wcode(r_w);
        a = r_a[15:0]; b = r_b[15:0]; cin = (r_cin != 0);
        #1;
        got_val = {48'd0, value};
        got_f   = flags;
        got_m   = flags_mask;
      end
      if (got_val !== r_val || got_m !== r_mask || (got_f & r_mask) !== (r_flags & r_mask)) begin
        bad++;
        if (shown < 20) begin
          shown++;
          $display("  MISMATCH %s.%s a=%h b=%h cin=%0d: value exp=%h got=%h | flags exp=%04X got=%04X (mask exp=%04X got=%04X)",
                   opname(r_aluop), wname(wcode(r_w)), r_a, r_b, r_cin, r_val, got_val,
                   r_flags & r_mask, got_f & r_mask, r_mask, got_m);
        end
      end
    end
    $fclose(fd);
    if (bad == 0) $display("RESULT PASS tb_alu %s: %0d checks (%0d two-pass), %0d out-of-contract skipped",
                           vecfile, total, twopass, skipped);
    else          $display("RESULT FAIL tb_alu %s: %0d of %0d checks mismatched (%0d two-pass), %0d out-of-contract skipped",
                           vecfile, bad, total, twopass, skipped);
    $finish;
  end
endmodule
