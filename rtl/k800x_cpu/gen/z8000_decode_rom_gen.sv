// DERIVED FILE, but a COMMITTED SOURCE of k8000: check it in, review its
// diffs, and build from it. Nothing in k8000's lint/build/test reads any
// other repo.
//
// Do not hand-edit: it is emitted by cmd/decoderom from the Z8000 Go golden
// model, and 'make refresh-rtl' (maintainers only, needs that model) will
// overwrite it. What proves it correct HERE is tb_decode replaying the
// committed vectors/k800x_cpu/decode/decode.vec -- no external repo needed.
//
// z8000_decode_rom_gen: reference decode ROM, f(w0[15:0], w1[3:0]) -> ctrl.
// Only bits 3:0 of the second word ever influence the control word (the
// 3A/3B/BA/BB/1C/5C sub-decoders); everything else is a function of w0.
// Structure mirrors the Go ROM: case on the high byte, then (only where the
// Go entry is a sub-decoder) on the low byte and the w1 nibble. Synthesis
// minimizes the constant tables; the tb (tb_decode) checks this module
// against vectors/decode/decode.vec, and it is the golden reference for
// any hand-structured decoder you write in rtl/z8000_decode.sv.

module z8000_decode_rom_gen
  import z8000_ctrl_pkg::*;
(
  input  logic [15:0] w0,      // instruction first word
  input  logic [3:0]  w1_lo,   // second word bits 3:0 (0 if not yet fetched)
  output ctrl_word_t  ctrl
);

  localparam int W = CTRL_W;

  always_comb begin
    ctrl = ctrl_word_t'(W'(0));
    case (w0[15:8])
      8'h00: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h800a0800000000000048);
          default:
            ctrl = ctrl_word_t'(80'h80090c00200000000024);
        endcase
      end
      8'h01: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h80120800000000000048);
          default:
            ctrl = ctrl_word_t'(80'h80110c00200000000024);
        endcase
      end
      8'h02: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h804a0800000000000048);
          default:
            ctrl = ctrl_word_t'(80'h80490c00200000000024);
        endcase
      end
      8'h03: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h80520800000000000048);
          default:
            ctrl = ctrl_word_t'(80'h80510c00200000000024);
        endcase
      end
      8'h04: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h80aa0800000000000048);
          default:
            ctrl = ctrl_word_t'(80'h80a90c00200000000024);
        endcase
      end
      8'h05: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h80b20800000000000048);
          default:
            ctrl = ctrl_word_t'(80'h80b10c00200000000024);
        endcase
      end
      8'h06: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h808a0800000000000048);
          default:
            ctrl = ctrl_word_t'(80'h80890c00200000000024);
        endcase
      end
      8'h07: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h80920800000000000048);
          default:
            ctrl = ctrl_word_t'(80'h80910c00200000000024);
        endcase
      end
      8'h08: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h80ca0800000000000048);
          default:
            ctrl = ctrl_word_t'(80'h80c90c00200000000024);
        endcase
      end
      8'h09: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h80d20800000000000048);
          default:
            ctrl = ctrl_word_t'(80'h80d10c00200000000024);
        endcase
      end
      8'h0A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h814a0840000000000048);
          default:
            ctrl = ctrl_word_t'(80'h81490c40200000000024);
        endcase
      end
      8'h0B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h81520840000000000048);
          default:
            ctrl = ctrl_word_t'(80'h81510c40200000000024);
        endcase
      end
      8'h0C: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'h80e90cc0280000000024);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(80'h814a0c84200000000048);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(80'h81090cc0280000000024);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'h81290c80200000000024);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(80'h82ea08c0080000000048);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'h83690cc0280000000024);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'h82e924c0080000000024);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(80'h00000000000000000048);
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000024);
        endcase
      end
      8'h0D: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'h80f10cc0280000000024);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(80'h81520c84200000000048);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(80'h81110cc0280000000024);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'h81310c80200000000024);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(80'h82f208c0080000000048);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'h83710cc0280000000024);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'h82f124c0080000000024);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(80'h8c020000000000800048);
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000024);
        endcase
      end
      8'h0E: ctrl = ctrl_word_t'(80'hec020c00000000000148);
      8'h0F: ctrl = ctrl_word_t'(80'hec020c00000000000148);
      8'h10: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h815b084000000000006c);
          default:
            ctrl = ctrl_word_t'(80'h81590c40200000000024);
        endcase
      end
      8'h11: ctrl = ctrl_word_t'(80'h8c010c00000000600024);
      8'h12: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h805b080000000000006c);
          default:
            ctrl = ctrl_word_t'(80'h80590c00200000000024);
        endcase
      end
      8'h13: ctrl = ctrl_word_t'(80'h8c010c00000000400024);
      8'h14: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82fb080000000000006c);
          default:
            ctrl = ctrl_word_t'(80'h82f90c00200000000024);
        endcase
      end
      8'h15: ctrl = ctrl_word_t'(80'h8c0100c0000000700024);
      8'h16: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h801b080000000000006c);
          default:
            ctrl = ctrl_word_t'(80'h80190c00200000000024);
        endcase
      end
      8'h17: ctrl = ctrl_word_t'(80'h8c0100c0000000500024);
      8'h18: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'hd01b080000000000006c);
          default:
            ctrl = ctrl_word_t'(80'hd0190c00000000000024);
        endcase
      end
      8'h19: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'hd0120800000000000048);
          default:
            ctrl = ctrl_word_t'(80'hd0110c00000000000024);
        endcase
      end
      8'h1A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'hd41b080000000000006c);
          default:
            ctrl = ctrl_word_t'(80'hd4190c00000000000024);
        endcase
      end
      8'h1B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'hd4120800000000000048);
          default:
            ctrl = ctrl_word_t'(80'hd4110c00000000000024);
        endcase
      end
      8'h1C: begin
        case (w0[7:0])
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(80'hc8020c00000000000048);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'h81390c80200000000024);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(80'hc8020c00000000008048);
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000024);
        endcase
      end
      8'h1D: ctrl = ctrl_word_t'(80'h82f904c0080000000024);
      8'h1E: ctrl = ctrl_word_t'(80'h90010000000000020024);
      8'h1F: ctrl = ctrl_word_t'(80'h90010000000000060024);
      8'h20: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82ea0800000000000048);
          default:
            ctrl = ctrl_word_t'(80'h82e90c00200000000024);
        endcase
      end
      8'h21: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82f20800000000000048);
          default:
            ctrl = ctrl_word_t'(80'h82f10c00200000000024);
        endcase
      end
      8'h22: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'ha74a0000000000000048);
          default:
            ctrl = ctrl_word_t'(80'h83490cdc280000000024);
        endcase
      end
      8'h23: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'ha7520000000000000048);
          default:
            ctrl = ctrl_word_t'(80'h83510cdc280000000024);
        endcase
      end
      8'h24: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'ha72a0000000000000048);
          default:
            ctrl = ctrl_word_t'(80'h83290cdc280000000024);
        endcase
      end
      8'h25: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'ha7320000000000000048);
          default:
            ctrl = ctrl_word_t'(80'h83310cdc280000000024);
        endcase
      end
      8'h26: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'ha70a0000000000000048);
          default:
            ctrl = ctrl_word_t'(80'h83090c9c280000000024);
        endcase
      end
      8'h27: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'ha7120000000000000048);
          default:
            ctrl = ctrl_word_t'(80'h83110c9c280000000024);
        endcase
      end
      8'h28: ctrl = ctrl_word_t'(80'h81690cde280000000024);
      8'h29: ctrl = ctrl_word_t'(80'h81710cde280000000024);
      8'h2A: ctrl = ctrl_word_t'(80'h81890cde280000000024);
      8'h2B: ctrl = ctrl_word_t'(80'h81910cde280000000024);
      8'h2C: ctrl = ctrl_word_t'(80'h9c090c00000000000024);
      8'h2D: ctrl = ctrl_word_t'(80'h9c110c00000000000024);
      8'h2E: ctrl = ctrl_word_t'(80'h82e904c0080000000024);
      8'h2F: ctrl = ctrl_word_t'(80'h82f104c0080000000024);
      8'h30: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82ea2c00000000000048);
          default:
            ctrl = ctrl_word_t'(80'h82ea3000200000000048);
        endcase
      end
      8'h31: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82f22c00000000000048);
          default:
            ctrl = ctrl_word_t'(80'h82f23000200000000048);
        endcase
      end
      8'h32: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82ea0580000000000048);
          default:
            ctrl = ctrl_word_t'(80'h82ea05c0080000000048);
        endcase
      end
      8'h33: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82f20580000000000048);
          default:
            ctrl = ctrl_word_t'(80'h82f205c0080000000048);
        endcase
      end
      8'h34: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'ha8022c00000000000048);
          default:
            ctrl = ctrl_word_t'(80'ha8023000200000000048);
        endcase
      end
      8'h35: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82fa2c00000000000048);
          default:
            ctrl = ctrl_word_t'(80'h82fa3000200000000048);
        endcase
      end
      8'h36: ctrl = ctrl_word_t'(80'h00000000000000000048);
      8'h37: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82fa0580000000000048);
          default:
            ctrl = ctrl_word_t'(80'h82fa05c0080000000048);
        endcase
      end
      8'h38: ctrl = ctrl_word_t'(80'h00000000000000000024);
      8'h39: ctrl = ctrl_word_t'(80'hd8010c00000000000024);
      8'h3A: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc40a0000000000002048);
            default: ctrl = ctrl_word_t'(80'hc40a0000000000001048);
          endcase
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc40a0000000000006048);
            default: ctrl = ctrl_word_t'(80'hc40a0000000000005048);
          endcase
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc40a0000000000008048);
            default: ctrl = ctrl_word_t'(80'hc40a0000000000009048);
          endcase
          8'h03, 8'h13, 8'h23, 8'h33, 8'h43, 8'h53, 8'h63, 8'h73, 8'h83, 8'h93, 8'hA3, 8'hB3, 
          8'hC3, 8'hD3, 8'hE3, 8'hF3:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc40a000000000000c048);
            default: ctrl = ctrl_word_t'(80'hc40a000000000000d048);
          endcase
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'hac0a0000000000000048);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(80'hac0a0000000000004048);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'hac0a0000000000008048);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(80'hac0a000000000000c048);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc40a0000000000000048);
            default: ctrl = ctrl_word_t'(80'hc40a0000000000003048);
          endcase
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc40a0000000000004048);
            default: ctrl = ctrl_word_t'(80'hc40a0000000000007048);
          endcase
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc40a000000000000a048);
            default: ctrl = ctrl_word_t'(80'hc40a000000000000b048);
          endcase
          8'h0B, 8'h1B, 8'h2B, 8'h3B, 8'h4B, 8'h5B, 8'h6B, 8'h7B, 8'h8B, 8'h9B, 8'hAB, 8'hBB, 
          8'hCB, 8'hDB, 8'hEB, 8'hFB:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc40a000000000000e048);
            default: ctrl = ctrl_word_t'(80'hc40a000000000000f048);
          endcase
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000048);
        endcase
      end
      8'h3B: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc4120000000000002048);
            default: ctrl = ctrl_word_t'(80'hc4120000000000001048);
          endcase
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc4120000000000006048);
            default: ctrl = ctrl_word_t'(80'hc4120000000000005048);
          endcase
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc4120000000000008048);
            default: ctrl = ctrl_word_t'(80'hc4120000000000009048);
          endcase
          8'h03, 8'h13, 8'h23, 8'h33, 8'h43, 8'h53, 8'h63, 8'h73, 8'h83, 8'h93, 8'hA3, 8'hB3, 
          8'hC3, 8'hD3, 8'hE3, 8'hF3:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc412000000000000c048);
            default: ctrl = ctrl_word_t'(80'hc412000000000000d048);
          endcase
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'hac120000000000000048);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(80'hac120000000000004048);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'hac120000000000008048);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(80'hac12000000000000c048);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc4120000000000000048);
            default: ctrl = ctrl_word_t'(80'hc4120000000000003048);
          endcase
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc4120000000000004048);
            default: ctrl = ctrl_word_t'(80'hc4120000000000007048);
          endcase
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc412000000000000a048);
            default: ctrl = ctrl_word_t'(80'hc412000000000000b048);
          endcase
          8'h0B, 8'h1B, 8'h2B, 8'h3B, 8'h4B, 8'h5B, 8'h6B, 8'h7B, 8'h8B, 8'h9B, 8'hAB, 8'hBB, 
          8'hCB, 8'hDB, 8'hEB, 8'hFB:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(80'hc412000000000000e048);
            default: ctrl = ctrl_word_t'(80'hc412000000000000f048);
          endcase
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000048);
        endcase
      end
      8'h3C: ctrl = ctrl_word_t'(80'hac090c00000000000024);
      8'h3D: ctrl = ctrl_word_t'(80'hac110c00000000000024);
      8'h3E: ctrl = ctrl_word_t'(80'hac090c00000000008024);
      8'h3F: ctrl = ctrl_word_t'(80'hac110c00000000008024);
      8'h40: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h800a100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h800a140020000000004e);
        endcase
      end
      8'h41: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h8012100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h8012140020000000004e);
        endcase
      end
      8'h42: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h804a100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h804a140020000000004e);
        endcase
      end
      8'h43: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h8052100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h8052140020000000004e);
        endcase
      end
      8'h44: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h80aa100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h80aa140020000000004e);
        endcase
      end
      8'h45: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h80b2100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h80b2140020000000004e);
        endcase
      end
      8'h46: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h808a100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h808a140020000000004e);
        endcase
      end
      8'h47: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h8092100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h8092140020000000004e);
        endcase
      end
      8'h48: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h80ca100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h80ca140020000000004e);
        endcase
      end
      8'h49: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h80d2100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h80d2140020000000004e);
        endcase
      end
      8'h4A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h814a104000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h814a144020000000004e);
        endcase
      end
      8'h4B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h8152104000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h8152144020000000004e);
        endcase
      end
      8'h4C: begin
        case (w0[7:0])
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(80'h00000000000000000072);
          8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 8'hC0, 
          8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'h80ea154028000000004e);
          8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 8'hC1, 
          8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(80'h814a1494200000000072);
          8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 8'hC2, 
          8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(80'h810a154028000000004e);
          8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 8'hC4, 
          8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'h812a148020000000004e);
          8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 8'hC5, 
          8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(80'h82ea2940080000000072);
          8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 8'hC6, 
          8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'h836a154028000000004e);
          8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 8'hC8, 
          8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'h82ea254008000000004e);
          8'h00:
            ctrl = ctrl_word_t'(80'h80ea110028000000004e);
          8'h01:
            ctrl = ctrl_word_t'(80'h814a1094200000000072);
          8'h02:
            ctrl = ctrl_word_t'(80'h810a110028000000004e);
          8'h04:
            ctrl = ctrl_word_t'(80'h812a108020000000004e);
          8'h05:
            ctrl = ctrl_word_t'(80'h82ea2900080000000072);
          8'h06:
            ctrl = ctrl_word_t'(80'h836a110028000000004e);
          8'h08:
            ctrl = ctrl_word_t'(80'h82ea250008000000004e);
          default:
            ctrl = ctrl_word_t'(80'h0000000000000000004e);
        endcase
      end
      8'h4D: begin
        case (w0[7:0])
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(80'h00000000000000000072);
          8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 8'hC0, 
          8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'h80f2154028000000004e);
          8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 8'hC1, 
          8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(80'h81521494200000000072);
          8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 8'hC2, 
          8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(80'h8112154028000000004e);
          8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 8'hC4, 
          8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'h8132148020000000004e);
          8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 8'hC5, 
          8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(80'h82f22940080000000072);
          8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 8'hC6, 
          8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'h8372154028000000004e);
          8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 8'hC8, 
          8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'h82f2254008000000004e);
          8'h00:
            ctrl = ctrl_word_t'(80'h80f2110028000000004e);
          8'h01:
            ctrl = ctrl_word_t'(80'h81521094200000000072);
          8'h02:
            ctrl = ctrl_word_t'(80'h8112110028000000004e);
          8'h04:
            ctrl = ctrl_word_t'(80'h8132108020000000004e);
          8'h05:
            ctrl = ctrl_word_t'(80'h82f22900080000000072);
          8'h06:
            ctrl = ctrl_word_t'(80'h8372110028000000004e);
          8'h08:
            ctrl = ctrl_word_t'(80'h82f2250008000000004e);
          default:
            ctrl = ctrl_word_t'(80'h0000000000000000004e);
        endcase
      end
      8'h4E: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'hec031000000000000171);
          default:
            ctrl = ctrl_word_t'(80'hec031400000000000171);
        endcase
      end
      8'h4F: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'hec031000000000000171);
          default:
            ctrl = ctrl_word_t'(80'hec031400000000000171);
        endcase
      end
      8'h50: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h815a104000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h815a144020000000004e);
        endcase
      end
      8'h51: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'h8c02100000000060004e);
          default:
            ctrl = ctrl_word_t'(80'h8c02140000000060004e);
        endcase
      end
      8'h52: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h805a100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h805a140020000000004e);
        endcase
      end
      8'h53: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'h8c02100000000040004e);
          default:
            ctrl = ctrl_word_t'(80'h8c02140000000040004e);
        endcase
      end
      8'h54: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82fa100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h82fa140020000000004e);
        endcase
      end
      8'h55: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'h8c02010000000070004e);
          default:
            ctrl = ctrl_word_t'(80'h8c02014000000070004e);
        endcase
      end
      8'h56: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h801a100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h801a140020000000004e);
        endcase
      end
      8'h57: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'h8c02010000000050004e);
          default:
            ctrl = ctrl_word_t'(80'h8c02014000000050004e);
        endcase
      end
      8'h58: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'hd01a100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'hd01a140020000000004e);
        endcase
      end
      8'h59: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'hd012100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'hd012140020000000004e);
        endcase
      end
      8'h5A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'hd41a100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'hd41a140020000000004e);
        endcase
      end
      8'h5B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'hd412100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'hd412140020000000004e);
        endcase
      end
      8'h5C: begin
        case (w0[7:0])
          8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 8'hC1, 
          8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(80'hc8031400200000000071);
          8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 8'hC8, 
          8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'h813a148020000000004e);
          8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 8'hC9, 
          8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(80'hc8031400200000008071);
          8'h01:
            ctrl = ctrl_word_t'(80'hc8031000000000000071);
          8'h08:
            ctrl = ctrl_word_t'(80'h813a108000000000004e);
          8'h09:
            ctrl = ctrl_word_t'(80'hc8031000000000008071);
          default:
            ctrl = ctrl_word_t'(80'h0000000000000000004e);
        endcase
      end
      8'h5D: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82fa050000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h82fa054008000000004e);
        endcase
      end
      8'h5E: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h9002000000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h9002000000000001004e);
        endcase
      end
      8'h5F: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h9002000000000004004e);
          default:
            ctrl = ctrl_word_t'(80'h9002000000000005004e);
        endcase
      end
      8'h60: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82ea100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h82ea140020000000004e);
        endcase
      end
      8'h61: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82f2100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h82f2140020000000004e);
        endcase
      end
      8'h62: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h834a111c28000000004e);
          default:
            ctrl = ctrl_word_t'(80'h834a155c28000000004e);
        endcase
      end
      8'h63: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h8352111c28000000004e);
          default:
            ctrl = ctrl_word_t'(80'h8352155c28000000004e);
        endcase
      end
      8'h64: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h832a111c28000000004e);
          default:
            ctrl = ctrl_word_t'(80'h832a155c28000000004e);
        endcase
      end
      8'h65: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h8332111c28000000004e);
          default:
            ctrl = ctrl_word_t'(80'h8332155c28000000004e);
        endcase
      end
      8'h66: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h830a109c28000000004e);
          default:
            ctrl = ctrl_word_t'(80'h830a149c28000000004e);
        endcase
      end
      8'h67: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h8312109c28000000004e);
          default:
            ctrl = ctrl_word_t'(80'h8312149c28000000004e);
        endcase
      end
      8'h68: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h816a111e28000000004e);
          default:
            ctrl = ctrl_word_t'(80'h816a155e28000000004e);
        endcase
      end
      8'h69: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h8172111e28000000004e);
          default:
            ctrl = ctrl_word_t'(80'h8172155e28000000004e);
        endcase
      end
      8'h6A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h818a111e28000000004e);
          default:
            ctrl = ctrl_word_t'(80'h818a155e28000000004e);
        endcase
      end
      8'h6B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h8192111e28000000004e);
          default:
            ctrl = ctrl_word_t'(80'h8192155e28000000004e);
        endcase
      end
      8'h6C: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h9c0a100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h9c0a140020000000004e);
        endcase
      end
      8'h6D: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h9c12100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h9c12140020000000004e);
        endcase
      end
      8'h6E: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82ea050000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h82ea054008000000004e);
        endcase
      end
      8'h6F: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'h82f2050000000000004e);
          default:
            ctrl = ctrl_word_t'(80'h82f2054008000000004e);
        endcase
      end
      8'h70: ctrl = ctrl_word_t'(80'h82ea340020000000004e);
      8'h71: ctrl = ctrl_word_t'(80'h82f2340020000000004e);
      8'h72: ctrl = ctrl_word_t'(80'h82ea060008000000004e);
      8'h73: ctrl = ctrl_word_t'(80'h82f2060008000000004e);
      8'h74: ctrl = ctrl_word_t'(80'ha802340020000000004e);
      8'h75: ctrl = ctrl_word_t'(80'h82fa340020000000004e);
      8'h76: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(80'ha802100000000000004e);
          default:
            ctrl = ctrl_word_t'(80'ha802140020000000004e);
        endcase
      end
      8'h77: ctrl = ctrl_word_t'(80'h82fa060008000000004e);
      8'h78: ctrl = ctrl_word_t'(80'h00000000000000000024);
      8'h79: ctrl = ctrl_word_t'(80'hd802100000000000004e);
      8'h7A: ctrl = ctrl_word_t'(80'hdc010000000000000024);
      8'h7B: begin
        case (w0[7:0])
          8'h1D, 8'h2D, 8'h3D, 8'h4D, 8'h5D, 8'h6D, 8'h7D, 8'h8D, 8'h9D, 8'hAD, 8'hBD, 8'hCD, 
          8'hDD, 8'hED, 8'hFD:
            ctrl = ctrl_word_t'(80'hcc010000000000000c24);
          8'h00:
            ctrl = ctrl_word_t'(80'he4010000000000000024);
          8'h08:
            ctrl = ctrl_word_t'(80'hcc010000000000000824);
          8'h09:
            ctrl = ctrl_word_t'(80'hcc010000000000000424);
          8'h0A:
            ctrl = ctrl_word_t'(80'hcc010000000000000024);
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000024);
        endcase
      end
      8'h7C: begin
        case (w0[7:0])
          8'h01, 8'h09, 8'h11, 8'h19, 8'h21, 8'h29, 8'h31, 8'h39, 8'h41, 8'h49, 8'h51, 8'h59, 
          8'h61, 8'h69, 8'h71, 8'h79, 8'h81, 8'h89, 8'h91, 8'h99, 8'hA1, 8'hA9, 8'hB1, 8'hB9, 
          8'hC1, 8'hC9, 8'hD1, 8'hD9, 8'hE1, 8'hE9, 8'hF1, 8'hF9:
            ctrl = ctrl_word_t'(80'h84010000011000000024);
          8'h02, 8'h0A, 8'h12, 8'h1A, 8'h22, 8'h2A, 8'h32, 8'h3A, 8'h42, 8'h4A, 8'h52, 8'h5A, 
          8'h62, 8'h6A, 8'h72, 8'h7A, 8'h82, 8'h8A, 8'h92, 8'h9A, 8'hA2, 8'hAA, 8'hB2, 8'hBA, 
          8'hC2, 8'hCA, 8'hD2, 8'hDA, 8'hE2, 8'hEA, 8'hF2, 8'hFA:
            ctrl = ctrl_word_t'(80'h84010000010800000024);
          8'h03, 8'h0B, 8'h13, 8'h1B, 8'h23, 8'h2B, 8'h33, 8'h3B, 8'h43, 8'h4B, 8'h53, 8'h5B, 
          8'h63, 8'h6B, 8'h73, 8'h7B, 8'h83, 8'h8B, 8'h93, 8'h9B, 8'hA3, 8'hAB, 8'hB3, 8'hBB, 
          8'hC3, 8'hCB, 8'hD3, 8'hDB, 8'hE3, 8'hEB, 8'hF3, 8'hFB:
            ctrl = ctrl_word_t'(80'h84010000010000000024);
          8'h04, 8'h0C, 8'h14, 8'h1C, 8'h24, 8'h2C, 8'h34, 8'h3C, 8'h44, 8'h4C, 8'h54, 8'h5C, 
          8'h64, 8'h6C, 8'h74, 8'h7C, 8'h84, 8'h8C, 8'h94, 8'h9C, 8'hA4, 8'hAC, 8'hB4, 8'hBC, 
          8'hC4, 8'hCC, 8'hD4, 8'hDC, 8'hE4, 8'hEC, 8'hF4, 8'hFC:
            ctrl = ctrl_word_t'(80'h84010000001800000024);
          8'h05, 8'h0D, 8'h15, 8'h1D, 8'h25, 8'h2D, 8'h35, 8'h3D, 8'h45, 8'h4D, 8'h55, 8'h5D, 
          8'h65, 8'h6D, 8'h75, 8'h7D, 8'h85, 8'h8D, 8'h95, 8'h9D, 8'hA5, 8'hAD, 8'hB5, 8'hBD, 
          8'hC5, 8'hCD, 8'hD5, 8'hDD, 8'hE5, 8'hED, 8'hF5, 8'hFD:
            ctrl = ctrl_word_t'(80'h84010000001000000024);
          8'h06, 8'h0E, 8'h16, 8'h1E, 8'h26, 8'h2E, 8'h36, 8'h3E, 8'h46, 8'h4E, 8'h56, 8'h5E, 
          8'h66, 8'h6E, 8'h76, 8'h7E, 8'h86, 8'h8E, 8'h96, 8'h9E, 8'hA6, 8'hAE, 8'hB6, 8'hBE, 
          8'hC6, 8'hCE, 8'hD6, 8'hDE, 8'hE6, 8'hEE, 8'hF6, 8'hFE:
            ctrl = ctrl_word_t'(80'h84010000000800000024);
          8'h07, 8'h0F, 8'h17, 8'h1F, 8'h27, 8'h2F, 8'h37, 8'h3F, 8'h47, 8'h4F, 8'h57, 8'h5F, 
          8'h67, 8'h6F, 8'h77, 8'h7F, 8'h87, 8'h8F, 8'h97, 8'h9F, 8'hA7, 8'hAF, 8'hB7, 8'hBF, 
          8'hC7, 8'hCF, 8'hD7, 8'hDF, 8'hE7, 8'hEF, 8'hF7, 8'hFF:
            ctrl = ctrl_word_t'(80'h84010000000000000024);
          default:
            ctrl = ctrl_word_t'(80'h84010000011800000024);
        endcase
      end
      8'h7D: ctrl = ctrl_word_t'(80'hb0010000000000000024);
      8'h7E: ctrl = ctrl_word_t'(80'h00000000000000000024);
      8'h7F: ctrl = ctrl_word_t'(80'he0010000000000000024);
      8'h80: ctrl = ctrl_word_t'(80'h80090400200000000024);
      8'h81: ctrl = ctrl_word_t'(80'h80110400200000000024);
      8'h82: ctrl = ctrl_word_t'(80'h80490400200000000024);
      8'h83: ctrl = ctrl_word_t'(80'h80510400200000000024);
      8'h84: ctrl = ctrl_word_t'(80'h80a90400200000000024);
      8'h85: ctrl = ctrl_word_t'(80'h80b10400200000000024);
      8'h86: ctrl = ctrl_word_t'(80'h80890400200000000024);
      8'h87: ctrl = ctrl_word_t'(80'h80910400200000000024);
      8'h88: ctrl = ctrl_word_t'(80'h80c90400200000000024);
      8'h89: ctrl = ctrl_word_t'(80'h80d10400200000000024);
      8'h8A: ctrl = ctrl_word_t'(80'h81490440200000000024);
      8'h8B: ctrl = ctrl_word_t'(80'h81510440200000000024);
      8'h8C: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'h80e90000880000000024);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(80'h84010000040000000024);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(80'h81090000880000000024);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'h81290040880000000024);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'h83690000880000000024);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'h82e92400080000000024);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(80'h84010000030000000024);
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000024);
        endcase
      end
      8'h8D: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'h80f10000880000000024);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(80'h81110000880000000024);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'h81310040880000000024);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'h83710000880000000024);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(80'h82f12440000000000024);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'h82f12400080000000024);
          8'h01:
            ctrl = ctrl_word_t'(80'h84010000000000000024);
          8'h03:
            ctrl = ctrl_word_t'(80'h84010000010000000024);
          8'h05:
            ctrl = ctrl_word_t'(80'h84010000020000000024);
          8'h11:
            ctrl = ctrl_word_t'(80'h84010000000010000024);
          8'h13:
            ctrl = ctrl_word_t'(80'h84010000010010000024);
          8'h15:
            ctrl = ctrl_word_t'(80'h84010000020010000024);
          8'h21:
            ctrl = ctrl_word_t'(80'h84010000000020000024);
          8'h23:
            ctrl = ctrl_word_t'(80'h84010000010020000024);
          8'h25:
            ctrl = ctrl_word_t'(80'h84010000020020000024);
          8'h31:
            ctrl = ctrl_word_t'(80'h84010000000030000024);
          8'h33:
            ctrl = ctrl_word_t'(80'h84010000010030000024);
          8'h35:
            ctrl = ctrl_word_t'(80'h84010000020030000024);
          8'h41:
            ctrl = ctrl_word_t'(80'h84010000000040000024);
          8'h43:
            ctrl = ctrl_word_t'(80'h84010000010040000024);
          8'h45:
            ctrl = ctrl_word_t'(80'h84010000020040000024);
          8'h51:
            ctrl = ctrl_word_t'(80'h84010000000050000024);
          8'h53:
            ctrl = ctrl_word_t'(80'h84010000010050000024);
          8'h55:
            ctrl = ctrl_word_t'(80'h84010000020050000024);
          8'h61:
            ctrl = ctrl_word_t'(80'h84010000000060000024);
          8'h63:
            ctrl = ctrl_word_t'(80'h84010000010060000024);
          8'h65:
            ctrl = ctrl_word_t'(80'h84010000020060000024);
          8'h71:
            ctrl = ctrl_word_t'(80'h84010000000070000024);
          8'h73:
            ctrl = ctrl_word_t'(80'h84010000010070000024);
          8'h75:
            ctrl = ctrl_word_t'(80'h84010000020070000024);
          8'h81:
            ctrl = ctrl_word_t'(80'h84010000000080000024);
          8'h83:
            ctrl = ctrl_word_t'(80'h84010000010080000024);
          8'h85:
            ctrl = ctrl_word_t'(80'h84010000020080000024);
          8'h91:
            ctrl = ctrl_word_t'(80'h84010000000090000024);
          8'h93:
            ctrl = ctrl_word_t'(80'h84010000010090000024);
          8'h95:
            ctrl = ctrl_word_t'(80'h84010000020090000024);
          8'hA1:
            ctrl = ctrl_word_t'(80'h840100000000a0000024);
          8'hA3:
            ctrl = ctrl_word_t'(80'h840100000100a0000024);
          8'hA5:
            ctrl = ctrl_word_t'(80'h840100000200a0000024);
          8'hB1:
            ctrl = ctrl_word_t'(80'h840100000000b0000024);
          8'hB3:
            ctrl = ctrl_word_t'(80'h840100000100b0000024);
          8'hB5:
            ctrl = ctrl_word_t'(80'h840100000200b0000024);
          8'hC1:
            ctrl = ctrl_word_t'(80'h840100000000c0000024);
          8'hC3:
            ctrl = ctrl_word_t'(80'h840100000100c0000024);
          8'hC5:
            ctrl = ctrl_word_t'(80'h840100000200c0000024);
          8'hD1:
            ctrl = ctrl_word_t'(80'h840100000000d0000024);
          8'hD3:
            ctrl = ctrl_word_t'(80'h840100000100d0000024);
          8'hD5:
            ctrl = ctrl_word_t'(80'h840100000200d0000024);
          8'hE1:
            ctrl = ctrl_word_t'(80'h840100000000e0000024);
          8'hE3:
            ctrl = ctrl_word_t'(80'h840100000100e0000024);
          8'hE5:
            ctrl = ctrl_word_t'(80'h840100000200e0000024);
          8'hF1:
            ctrl = ctrl_word_t'(80'h840100000000f0000024);
          8'hF3:
            ctrl = ctrl_word_t'(80'h840100000100f0000024);
          8'hF5:
            ctrl = ctrl_word_t'(80'h840100000200f0000024);
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000024);
        endcase
      end
      8'h8E: ctrl = ctrl_word_t'(80'hec020000000000000348);
      8'h8F: ctrl = ctrl_word_t'(80'hec020000000000000248);
      8'h90: ctrl = ctrl_word_t'(80'h81590440200000000024);
      8'h91: ctrl = ctrl_word_t'(80'h8c010000000000200024);
      8'h92: ctrl = ctrl_word_t'(80'h80590400200000000024);
      8'h93: ctrl = ctrl_word_t'(80'h8c010000000000000024);
      8'h94: ctrl = ctrl_word_t'(80'h82f90400200000000024);
      8'h95: ctrl = ctrl_word_t'(80'h8c010000000000300024);
      8'h96: ctrl = ctrl_word_t'(80'h80190400200000000024);
      8'h97: ctrl = ctrl_word_t'(80'h8c010000000000100024);
      8'h98: ctrl = ctrl_word_t'(80'hd0190400000000000024);
      8'h99: ctrl = ctrl_word_t'(80'hd0110400000000000024);
      8'h9A: ctrl = ctrl_word_t'(80'hd4190400000000000024);
      8'h9B: ctrl = ctrl_word_t'(80'hd4110400000000000024);
      8'h9C: begin
        case (w0[7:0])
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'h81390040800000000024);
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000024);
        endcase
      end
      8'h9D: ctrl = ctrl_word_t'(80'h00000000000000000024);
      8'h9E: ctrl = ctrl_word_t'(80'h90010000000000090024);
      8'h9F: ctrl = ctrl_word_t'(80'h00000000000000000024);
      8'hA0: ctrl = ctrl_word_t'(80'h82e90400200000000024);
      8'hA1: ctrl = ctrl_word_t'(80'h82f10400200000000024);
      8'hA2: ctrl = ctrl_word_t'(80'h83493800880000000024);
      8'hA3: ctrl = ctrl_word_t'(80'h83513800880000000024);
      8'hA4: ctrl = ctrl_word_t'(80'h83293800880000000024);
      8'hA5: ctrl = ctrl_word_t'(80'h83313800880000000024);
      8'hA6: ctrl = ctrl_word_t'(80'h83093840880000000024);
      8'hA7: ctrl = ctrl_word_t'(80'h83113840880000000024);
      8'hA8: ctrl = ctrl_word_t'(80'h81693c00880000000024);
      8'hA9: ctrl = ctrl_word_t'(80'h81713c00880000000024);
      8'hAA: ctrl = ctrl_word_t'(80'h81893c00880000000024);
      8'hAB: ctrl = ctrl_word_t'(80'h81913c00880000000024);
      8'hAC: ctrl = ctrl_word_t'(80'h9c090000000000000024);
      8'hAD: ctrl = ctrl_word_t'(80'h9c110000000000000024);
      8'hAE: ctrl = ctrl_word_t'(80'h94090000000000000024);
      8'hAF: ctrl = ctrl_word_t'(80'h94110000000000000024);
      8'hB0: ctrl = ctrl_word_t'(80'h98010000000000000024);
      8'hB1: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'h88090000000000000024);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(80'h88190000000000000024);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(80'h88110000000000000024);
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000024);
        endcase
      end
      8'hB2: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'h82291800880000000024);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(80'hb5ea0004000000000048);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(80'h82291c00880000000024);
          8'h03, 8'h13, 8'h23, 8'h33, 8'h43, 8'h53, 8'h63, 8'h73, 8'h83, 8'h93, 8'hA3, 8'hB3, 
          8'hC3, 8'hD3, 8'hE3, 8'hF3:
            ctrl = ctrl_word_t'(80'hb5ea0002000000000048);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'h82491800880000000024);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'h82491c00880000000024);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'h82691800880000000024);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(80'hb5aa0004000000000048);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(80'h82691c00880000000024);
          8'h0B, 8'h1B, 8'h2B, 8'h3B, 8'h4B, 8'h5B, 8'h6B, 8'h7B, 8'h8B, 8'h9B, 8'hAB, 8'hBB, 
          8'hCB, 8'hDB, 8'hEB, 8'hFB:
            ctrl = ctrl_word_t'(80'hb5aa0002000000000048);
          8'h0C, 8'h1C, 8'h2C, 8'h3C, 8'h4C, 8'h5C, 8'h6C, 8'h7C, 8'h8C, 8'h9C, 8'hAC, 8'hBC, 
          8'hCC, 8'hDC, 8'hEC, 8'hFC:
            ctrl = ctrl_word_t'(80'h82891800880000000024);
          8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h4E, 8'h5E, 8'h6E, 8'h7E, 8'h8E, 8'h9E, 8'hAE, 8'hBE, 
          8'hCE, 8'hDE, 8'hEE, 8'hFE:
            ctrl = ctrl_word_t'(80'h82891c00880000000024);
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000048);
        endcase
      end
      8'hB3: begin
        case (w0[7:0])
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(80'hb5f20004000000000048);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(80'h82311c00880000000024);
          8'h03, 8'h13, 8'h23, 8'h33, 8'h43, 8'h53, 8'h63, 8'h73, 8'h83, 8'h93, 8'hA3, 8'hB3, 
          8'hC3, 8'hD3, 8'hE3, 8'hF3:
            ctrl = ctrl_word_t'(80'hb5f20002000000000048);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'h82511800880000000024);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(80'hb5fa0004000000000048);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'h82511c00880000000024);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(80'hb5fa0002000000000048);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'h82711800880000000024);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(80'hb5b20004000000000048);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(80'h82711c00880000000024);
          8'h0B, 8'h1B, 8'h2B, 8'h3B, 8'h4B, 8'h5B, 8'h6B, 8'h7B, 8'h8B, 8'h9B, 8'hAB, 8'hBB, 
          8'hCB, 8'hDB, 8'hEB, 8'hFB:
            ctrl = ctrl_word_t'(80'hb5b20002000000000048);
          8'h0C, 8'h1C, 8'h2C, 8'h3C, 8'h4C, 8'h5C, 8'h6C, 8'h7C, 8'h8C, 8'h9C, 8'hAC, 8'hBC, 
          8'hCC, 8'hDC, 8'hEC, 8'hFC:
            ctrl = ctrl_word_t'(80'h82911800880000000024);
          8'h0D, 8'h1D, 8'h2D, 8'h3D, 8'h4D, 8'h5D, 8'h6D, 8'h7D, 8'h8D, 8'h9D, 8'hAD, 8'hBD, 
          8'hCD, 8'hDD, 8'hED, 8'hFD:
            ctrl = ctrl_word_t'(80'hb5ba0004000000000048);
          8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h4E, 8'h5E, 8'h6E, 8'h7E, 8'h8E, 8'h9E, 8'hAE, 8'hBE, 
          8'hCE, 8'hDE, 8'hEE, 8'hFE:
            ctrl = ctrl_word_t'(80'h82911c00880000000024);
          8'h0F, 8'h1F, 8'h2F, 8'h3F, 8'h4F, 8'h5F, 8'h6F, 8'h7F, 8'h8F, 8'h9F, 8'hAF, 8'hBF, 
          8'hCF, 8'hDF, 8'hEF, 8'hFF:
            ctrl = ctrl_word_t'(80'hb5ba0002000000000048);
          default:
            ctrl = ctrl_word_t'(80'h82311800880000000024);
        endcase
      end
      8'hB4: ctrl = ctrl_word_t'(80'h80290400200000000024);
      8'hB5: ctrl = ctrl_word_t'(80'h80310400200000000024);
      8'hB6: ctrl = ctrl_word_t'(80'h80690400200000000024);
      8'hB7: ctrl = ctrl_word_t'(80'h80710400200000000024);
      8'hB8: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'he8020000000000008048);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(80'he8020000000000000048);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'he8020000000000009048);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'he8020000000000001048);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'he802000000000000a048);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(80'he8020000000000002048);
          8'h0C, 8'h1C, 8'h2C, 8'h3C, 8'h4C, 8'h5C, 8'h6C, 8'h7C, 8'h8C, 8'h9C, 8'hAC, 8'hBC, 
          8'hCC, 8'hDC, 8'hEC, 8'hFC:
            ctrl = ctrl_word_t'(80'he802000000000000b048);
          8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h4E, 8'h5E, 8'h6E, 8'h7E, 8'h8E, 8'h9E, 8'hAE, 8'hBE, 
          8'hCE, 8'hDE, 8'hEE, 8'hFE:
            ctrl = ctrl_word_t'(80'he8020000000000003048);
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000048);
        endcase
      end
      8'hB9: ctrl = ctrl_word_t'(80'h00000000000000000024);
      8'hBA: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'hbc0a0000000000000048);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            case (w1_lo)
            4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hE, 4'hF: ctrl = ctrl_word_t'(80'hb80a0000000000000048);
            default: ctrl = ctrl_word_t'(80'hb80a0000000000001048);
          endcase
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(80'hc00a0000000000000048);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'hbc0a0000000000001048);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'hc00a0000000000001048);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'hbc0a0000000000002048);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            case (w1_lo)
            4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hE, 4'hF: ctrl = ctrl_word_t'(80'hb80a0000000000002048);
            default: ctrl = ctrl_word_t'(80'hb80a0000000000003048);
          endcase
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(80'hc00a0000000000002048);
          8'h0C, 8'h1C, 8'h2C, 8'h3C, 8'h4C, 8'h5C, 8'h6C, 8'h7C, 8'h8C, 8'h9C, 8'hAC, 8'hBC, 
          8'hCC, 8'hDC, 8'hEC, 8'hFC:
            ctrl = ctrl_word_t'(80'hbc0a0000000000003048);
          8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h4E, 8'h5E, 8'h6E, 8'h7E, 8'h8E, 8'h9E, 8'hAE, 8'hBE, 
          8'hCE, 8'hDE, 8'hEE, 8'hFE:
            ctrl = ctrl_word_t'(80'hc00a0000000000003048);
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000048);
        endcase
      end
      8'hBB: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(80'hbc120000000000000048);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            case (w1_lo)
            4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hE, 4'hF: ctrl = ctrl_word_t'(80'hb8120000000000000048);
            default: ctrl = ctrl_word_t'(80'hb8120000000000001048);
          endcase
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(80'hc0120000000000000048);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(80'hbc120000000000001048);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(80'hc0120000000000001048);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(80'hbc120000000000002048);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            case (w1_lo)
            4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hE, 4'hF: ctrl = ctrl_word_t'(80'hb8120000000000002048);
            default: ctrl = ctrl_word_t'(80'hb8120000000000003048);
          endcase
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(80'hc0120000000000002048);
          8'h0C, 8'h1C, 8'h2C, 8'h3C, 8'h4C, 8'h5C, 8'h6C, 8'h7C, 8'h8C, 8'h9C, 8'hAC, 8'hBC, 
          8'hCC, 8'hDC, 8'hEC, 8'hFC:
            ctrl = ctrl_word_t'(80'hbc120000000000003048);
          8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h4E, 8'h5E, 8'h6E, 8'h7E, 8'h8E, 8'h9E, 8'hAE, 8'hBE, 
          8'hCE, 8'hDE, 8'hEE, 8'hFE:
            ctrl = ctrl_word_t'(80'hc0120000000000003048);
          default:
            ctrl = ctrl_word_t'(80'h00000000000000000048);
        endcase
      end
      8'hBC: ctrl = ctrl_word_t'(80'ha2410000000000000024);
      8'hBD: ctrl = ctrl_word_t'(80'h82f13800080000000024);
      8'hBE: ctrl = ctrl_word_t'(80'ha2210000000000000024);
      8'hBF: ctrl = ctrl_word_t'(80'h00000000000000000024);
      8'hC0: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hC1: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hC2: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hC3: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hC4: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hC5: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hC6: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hC7: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hC8: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hC9: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hCA: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hCB: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hCC: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hCD: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hCE: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hCF: ctrl = ctrl_word_t'(80'h82e94000100000000024);
      8'hD0: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hD1: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hD2: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hD3: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hD4: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hD5: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hD6: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hD7: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hD8: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hD9: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hDA: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hDB: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hDC: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hDD: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hDE: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hDF: ctrl = ctrl_word_t'(80'h90010000000000080024);
      8'hE0: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hE1: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hE2: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hE3: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hE4: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hE5: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hE6: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hE7: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hE8: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hE9: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hEA: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hEB: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hEC: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hED: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hEE: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hEF: ctrl = ctrl_word_t'(80'h90010000000000030024);
      8'hF0: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hF1: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hF2: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hF3: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hF4: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hF5: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hF6: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hF7: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hF8: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hF9: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hFA: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hFB: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hFC: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hFD: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hFE: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      8'hFF: ctrl = ctrl_word_t'(80'h900100000000000a0024);
      default: ctrl = ctrl_word_t'(W'(0));
    endcase
  end

endmodule
