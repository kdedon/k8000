// tb_cond -- the condition-code evaluator against the Z8000 CPU Reference
// Manual (1982) condition-code table, p.56: every code under every C, Z, S,
// P/V combination.
//
// Run: make test-cond

module tb_cond;
  logic [3:0] cc;
  logic       c, z, s, v, met;

  z8000_cond dut (.cc(cc), .c(c), .z(z), .s(s), .v(v), .met(met));

  // The table's flag settings, row by row.
  function automatic logic want(input logic [3:0] code, input logic fc, fz, fs, fv);
    unique case (code)
      4'b0000: return 1'b0;                     // F    always false
      4'b1000: return 1'b1;                     //      always true
      4'b0110: return fz;                       // Z/EQ   Z = 1
      4'b1110: return !fz;                      // NZ/NE  Z = 0
      4'b0111: return fc;                       // C/ULT  C = 1
      4'b1111: return !fc;                      // NC/UGE C = 0
      4'b1101: return !fs;                      // PL     S = 0
      4'b0101: return fs;                       // MI     S = 1
      4'b0100: return fv;                       // OV/PE  V = 1
      4'b1100: return !fv;                      // NOV/PO V = 0
      4'b1001: return (fs ^ fv) == 1'b0;        // GE  (S XOR V) = 0
      4'b0001: return (fs ^ fv) == 1'b1;        // LT  (S XOR V) = 1
      4'b1010: return (fz | (fs ^ fv)) == 1'b0; // GT  (Z OR (S XOR V)) = 0
      4'b0010: return (fz | (fs ^ fv)) == 1'b1; // LE  (Z OR (S XOR V)) = 1
      4'b1011: return !fc && !fz;               // UGT ((C = 0) AND (Z = 0)) = 1
      4'b0011: return fc | fz;                  // ULE (C OR Z) = 1
      default: return 1'bx;
    endcase
  endfunction

  int unsigned failed = 0, passed = 0;

  initial begin
    for (int i = 0; i < 256; i++) begin
      cc = i[7:4];
      {c, z, s, v} = i[3:0];
      #1;
      if (met !== want(cc, c, z, s, v)) begin
        failed++;
        $display("FAIL  cc %b C%0d Z%0d S%0d V%0d: %b, want %b", cc, c, z, s, v, met,
                 want(cc, c, z, s, v));
      end else begin
        passed++;
      end
    end
    if (failed == 0) $display("RESULT PASS  tb_cond  %0d checks", passed);
    else             $display("RESULT FAIL  tb_cond  %0d of %0d checks", failed, passed + failed);
    $finish;
  end
endmodule
