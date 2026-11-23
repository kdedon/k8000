// Generated from z8000_decode_table.txt by make gen; do not hand-edit.
// tb_decode proves it against vectors/k800x_cpu/decode/decode.vec.
//
// z8000_decode_rom_gen: reference decode ROM, f(w0[15:0]) -> ctrl.
// Case on the high byte, then (where it matters) on the low byte.
// Synthesis minimizes the constant tables.

`default_nettype none

module z8000_decode_rom_gen
  import z8000_ctrl_pkg::*;
(
  input  logic [15:0] w0,      // instruction first word
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
            ctrl = ctrl_word_t'(68'h80084000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80086001000000000);
        endcase
      end
      8'h01: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80104000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80106001000000000);
        endcase
      end
      8'h02: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80484000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80486001000000000);
        endcase
      end
      8'h03: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80504000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80506001000000000);
        endcase
      end
      8'h04: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80a84000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80a86001000000000);
        endcase
      end
      8'h05: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80b04000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80b06001000000000);
        endcase
      end
      8'h06: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80884000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80886001000000000);
        endcase
      end
      8'h07: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80904000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80906001000000000);
        endcase
      end
      8'h08: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80c84000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80c86001000000000);
        endcase
      end
      8'h09: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80d04000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80d06001000000000);
        endcase
      end
      8'h0A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h81484200000000000);
          default:
            ctrl = ctrl_word_t'(68'h81486201000000000);
        endcase
      end
      8'h0B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h81504200000000000);
          default:
            ctrl = ctrl_word_t'(68'h81506201000000000);
        endcase
      end
      8'h0C: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'h80e86601400000000);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'h81486421000000000);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(68'h81086601400000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(68'h81286401000000000);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(68'h82e84600400000000);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(68'h83686601400000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(68'h82e92600400000000);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'h0D: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'h80f06601400000000);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'h81506421000000000);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(68'h81106601400000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(68'h81306401000000000);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(68'h82f04600400000000);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(68'h83706601400000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(68'h82f12600400000000);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(68'h8c000000000004000);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'h0E: ctrl = ctrl_word_t'(68'hec006000000000001);
      8'h0F: ctrl = ctrl_word_t'(68'hec006000000000001);
      8'h10: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h81584200000000000);
          default:
            ctrl = ctrl_word_t'(68'h81586201000000000);
        endcase
      end
      8'h11: ctrl = ctrl_word_t'(68'h8c006000000003000);
      8'h12: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80584000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80586001000000000);
        endcase
      end
      8'h13: ctrl = ctrl_word_t'(68'h8c006000000002000);
      8'h14: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82f84000000000000);
          default:
            ctrl = ctrl_word_t'(68'h82f86001000000000);
        endcase
      end
      8'h15: ctrl = ctrl_word_t'(68'h8c000600000003800);
      8'h16: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80184000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80186001000000000);
        endcase
      end
      8'h17: ctrl = ctrl_word_t'(68'h8c000600000002800);
      8'h18: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'hd0184000000000000);
          default:
            ctrl = ctrl_word_t'(68'hd0186001000000000);
        endcase
      end
      8'h19: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'hd0104000000000000);
          default:
            ctrl = ctrl_word_t'(68'hd0106001000000000);
        endcase
      end
      8'h1A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'hd4184000000000000);
          default:
            ctrl = ctrl_word_t'(68'hd4186001000000000);
        endcase
      end
      8'h1B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'hd4104000000000000);
          default:
            ctrl = ctrl_word_t'(68'hd4106001000000000);
        endcase
      end
      8'h1C: begin
        case (w0[7:0])
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'hc8006000000000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(68'h81386401000000000);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(68'hc8006000000000040);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'h1D: ctrl = ctrl_word_t'(68'h82f82600400000000);
      8'h1E: ctrl = ctrl_word_t'(68'h90000000000000100);
      8'h1F: ctrl = ctrl_word_t'(68'h90000000000000300);
      8'h20: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82e84000000000000);
          default:
            ctrl = ctrl_word_t'(68'h82e86001000000000);
        endcase
      end
      8'h21: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82f04000000000000);
          default:
            ctrl = ctrl_word_t'(68'h82f06001000000000);
        endcase
      end
      8'h22: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'ha7480000000000000);
          default:
            ctrl = ctrl_word_t'(68'h834866e1400000000);
        endcase
      end
      8'h23: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'ha7500000000000000);
          default:
            ctrl = ctrl_word_t'(68'h835066e1400000000);
        endcase
      end
      8'h24: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'ha7280000000000000);
          default:
            ctrl = ctrl_word_t'(68'h832866e1400000000);
        endcase
      end
      8'h25: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'ha7300000000000000);
          default:
            ctrl = ctrl_word_t'(68'h833066e1400000000);
        endcase
      end
      8'h26: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'ha7080000000000000);
          default:
            ctrl = ctrl_word_t'(68'h830864e1400000000);
        endcase
      end
      8'h27: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'ha7100000000000000);
          default:
            ctrl = ctrl_word_t'(68'h831064e1400000000);
        endcase
      end
      8'h28: ctrl = ctrl_word_t'(68'h816866f1400000000);
      8'h29: ctrl = ctrl_word_t'(68'h817066f1400000000);
      8'h2A: ctrl = ctrl_word_t'(68'h818866f1400000000);
      8'h2B: ctrl = ctrl_word_t'(68'h819066f1400000000);
      8'h2C: ctrl = ctrl_word_t'(68'h9c086000000000000);
      8'h2D: ctrl = ctrl_word_t'(68'h9c106000000000000);
      8'h2E: ctrl = ctrl_word_t'(68'h82e82600400000000);
      8'h2F: ctrl = ctrl_word_t'(68'h82f02600400000000);
      8'h30: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82e96000000000000);
          default:
            ctrl = ctrl_word_t'(68'h82e98001000000000);
        endcase
      end
      8'h31: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82f16000000000000);
          default:
            ctrl = ctrl_word_t'(68'h82f18001000000000);
        endcase
      end
      8'h32: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82e82c00000000000);
          default:
            ctrl = ctrl_word_t'(68'h82e82e00400000000);
        endcase
      end
      8'h33: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82f02c00000000000);
          default:
            ctrl = ctrl_word_t'(68'h82f02e00400000000);
        endcase
      end
      8'h34: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'ha8016000000000000);
          default:
            ctrl = ctrl_word_t'(68'ha8018001000000000);
        endcase
      end
      8'h35: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82f96000000000000);
          default:
            ctrl = ctrl_word_t'(68'h82f98001000000000);
        endcase
      end
      8'h36: ctrl = ctrl_word_t'(68'h00000000000000000);
      8'h37: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82f82c00000000000);
          default:
            ctrl = ctrl_word_t'(68'h82f82e00400000000);
        endcase
      end
      8'h38: ctrl = ctrl_word_t'(68'h00000000000000000);
      8'h39: ctrl = ctrl_word_t'(68'hd8046000000000000);
      8'h3A: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'hc40c0000000000000);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'hc40c0000000000020);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(68'hc40c0000000000040);
          8'h03, 8'h13, 8'h23, 8'h33, 8'h43, 8'h53, 8'h63, 8'h73, 8'h83, 8'h93, 8'hA3, 8'hB3, 
          8'hC3, 8'hD3, 8'hE3, 8'hF3:
            ctrl = ctrl_word_t'(68'hc40c0000000000060);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(68'hac0c0000000000000);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(68'hac0c0000000000020);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(68'hac0c0000000000040);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(68'hac0c0000000000060);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(68'hc40c0000000000010);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(68'hc40c0000000000030);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(68'hc40c0000000000050);
          8'h0B, 8'h1B, 8'h2B, 8'h3B, 8'h4B, 8'h5B, 8'h6B, 8'h7B, 8'h8B, 8'h9B, 8'hAB, 8'hBB, 
          8'hCB, 8'hDB, 8'hEB, 8'hFB:
            ctrl = ctrl_word_t'(68'hc40c0000000000070);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'h3B: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'hc4140000000000000);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'hc4140000000000020);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(68'hc4140000000000040);
          8'h03, 8'h13, 8'h23, 8'h33, 8'h43, 8'h53, 8'h63, 8'h73, 8'h83, 8'h93, 8'hA3, 8'hB3, 
          8'hC3, 8'hD3, 8'hE3, 8'hF3:
            ctrl = ctrl_word_t'(68'hc4140000000000060);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(68'hac140000000000000);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(68'hac140000000000020);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(68'hac140000000000040);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(68'hac140000000000060);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(68'hc4140000000000010);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(68'hc4140000000000030);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(68'hc4140000000000050);
          8'h0B, 8'h1B, 8'h2B, 8'h3B, 8'h4B, 8'h5B, 8'h6B, 8'h7B, 8'h8B, 8'h9B, 8'hAB, 8'hBB, 
          8'hCB, 8'hDB, 8'hEB, 8'hFB:
            ctrl = ctrl_word_t'(68'hc4140000000000070);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'h3C: ctrl = ctrl_word_t'(68'hac0c6000000000000);
      8'h3D: ctrl = ctrl_word_t'(68'hac146000000000000);
      8'h3E: ctrl = ctrl_word_t'(68'hac0c6000000000040);
      8'h3F: ctrl = ctrl_word_t'(68'hac146000000000040);
      8'h40: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80088000000000000);
          default:
            ctrl = ctrl_word_t'(68'h8008a001000000000);
        endcase
      end
      8'h41: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80108000000000000);
          default:
            ctrl = ctrl_word_t'(68'h8010a001000000000);
        endcase
      end
      8'h42: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80488000000000000);
          default:
            ctrl = ctrl_word_t'(68'h8048a001000000000);
        endcase
      end
      8'h43: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80508000000000000);
          default:
            ctrl = ctrl_word_t'(68'h8050a001000000000);
        endcase
      end
      8'h44: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80a88000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80a8a001000000000);
        endcase
      end
      8'h45: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80b08000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80b0a001000000000);
        endcase
      end
      8'h46: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80888000000000000);
          default:
            ctrl = ctrl_word_t'(68'h8088a001000000000);
        endcase
      end
      8'h47: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80908000000000000);
          default:
            ctrl = ctrl_word_t'(68'h8090a001000000000);
        endcase
      end
      8'h48: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80c88000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80c8a001000000000);
        endcase
      end
      8'h49: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80d08000000000000);
          default:
            ctrl = ctrl_word_t'(68'h80d0a001000000000);
        endcase
      end
      8'h4A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h81488200000000000);
          default:
            ctrl = ctrl_word_t'(68'h8148a201000000000);
        endcase
      end
      8'h4B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h81508200000000000);
          default:
            ctrl = ctrl_word_t'(68'h8150a201000000000);
        endcase
      end
      8'h4C: begin
        case (w0[7:0])
          8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 8'hC0, 
          8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'h80e8aa01400000000);
          8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 8'hC1, 
          8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'h8148a4a1000000000);
          8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 8'hC2, 
          8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(68'h8108aa01400000000);
          8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 8'hC4, 
          8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(68'h8128a401000000000);
          8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 8'hC5, 
          8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(68'h82e94a00400000000);
          8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 8'hC6, 
          8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(68'h8368aa01400000000);
          8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 8'hC8, 
          8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(68'h82e92a00400000000);
          8'h00:
            ctrl = ctrl_word_t'(68'h80e88801400000000);
          8'h01:
            ctrl = ctrl_word_t'(68'h814884a1000000000);
          8'h02:
            ctrl = ctrl_word_t'(68'h81088801400000000);
          8'h04:
            ctrl = ctrl_word_t'(68'h81288401000000000);
          8'h05:
            ctrl = ctrl_word_t'(68'h82e94800400000000);
          8'h06:
            ctrl = ctrl_word_t'(68'h83688801400000000);
          8'h08:
            ctrl = ctrl_word_t'(68'h82e92800400000000);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'h4D: begin
        case (w0[7:0])
          8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 8'hC0, 
          8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'h80f0aa01400000000);
          8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 8'hC1, 
          8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'h8150a4a1000000000);
          8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 8'hC2, 
          8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(68'h8110aa01400000000);
          8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 8'hC4, 
          8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(68'h8130a401000000000);
          8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 8'hC5, 
          8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(68'h82f14a00400000000);
          8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 8'hC6, 
          8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(68'h8370aa01400000000);
          8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 8'hC8, 
          8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(68'h82f12a00400000000);
          8'h00:
            ctrl = ctrl_word_t'(68'h80f08801400000000);
          8'h01:
            ctrl = ctrl_word_t'(68'h815084a1000000000);
          8'h02:
            ctrl = ctrl_word_t'(68'h81108801400000000);
          8'h04:
            ctrl = ctrl_word_t'(68'h81308401000000000);
          8'h05:
            ctrl = ctrl_word_t'(68'h82f14800400000000);
          8'h06:
            ctrl = ctrl_word_t'(68'h83708801400000000);
          8'h08:
            ctrl = ctrl_word_t'(68'h82f12800400000000);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'h4E: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'hec008000000000001);
          default:
            ctrl = ctrl_word_t'(68'hec00a000000000001);
        endcase
      end
      8'h4F: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'hec008000000000001);
          default:
            ctrl = ctrl_word_t'(68'hec00a000000000001);
        endcase
      end
      8'h50: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h81588200000000000);
          default:
            ctrl = ctrl_word_t'(68'h8158a201000000000);
        endcase
      end
      8'h51: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'h8c008000000003000);
          default:
            ctrl = ctrl_word_t'(68'h8c00a000000003000);
        endcase
      end
      8'h52: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80588000000000000);
          default:
            ctrl = ctrl_word_t'(68'h8058a001000000000);
        endcase
      end
      8'h53: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'h8c008000000002000);
          default:
            ctrl = ctrl_word_t'(68'h8c00a000000002000);
        endcase
      end
      8'h54: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82f88000000000000);
          default:
            ctrl = ctrl_word_t'(68'h82f8a001000000000);
        endcase
      end
      8'h55: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'h8c000800000003800);
          default:
            ctrl = ctrl_word_t'(68'h8c000a00000003800);
        endcase
      end
      8'h56: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h80188000000000000);
          default:
            ctrl = ctrl_word_t'(68'h8018a001000000000);
        endcase
      end
      8'h57: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'h8c000800000002800);
          default:
            ctrl = ctrl_word_t'(68'h8c000a00000002800);
        endcase
      end
      8'h58: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'hd0188000000000000);
          default:
            ctrl = ctrl_word_t'(68'hd018a001000000000);
        endcase
      end
      8'h59: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'hd0108000000000000);
          default:
            ctrl = ctrl_word_t'(68'hd010a001000000000);
        endcase
      end
      8'h5A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'hd4188000000000000);
          default:
            ctrl = ctrl_word_t'(68'hd418a001000000000);
        endcase
      end
      8'h5B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'hd4108000000000000);
          default:
            ctrl = ctrl_word_t'(68'hd410a001000000000);
        endcase
      end
      8'h5C: begin
        case (w0[7:0])
          8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 8'hC1, 
          8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'hc800a001000000000);
          8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 8'hC8, 
          8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(68'h8138a401000000000);
          8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 8'hC9, 
          8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(68'hc800a001000000040);
          8'h01:
            ctrl = ctrl_word_t'(68'hc8008000000000000);
          8'h08:
            ctrl = ctrl_word_t'(68'h81388400000000000);
          8'h09:
            ctrl = ctrl_word_t'(68'hc8008000000000040);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'h5D: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82f82800000000000);
          default:
            ctrl = ctrl_word_t'(68'h82f82a00400000000);
        endcase
      end
      8'h5E: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h90000000000000000);
          default:
            ctrl = ctrl_word_t'(68'h90000000000000080);
        endcase
      end
      8'h5F: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h90000000000000200);
          default:
            ctrl = ctrl_word_t'(68'h90000000000000280);
        endcase
      end
      8'h60: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82e88000000000000);
          default:
            ctrl = ctrl_word_t'(68'h82e8a001000000000);
        endcase
      end
      8'h61: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82f08000000000000);
          default:
            ctrl = ctrl_word_t'(68'h82f0a001000000000);
        endcase
      end
      8'h62: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h834888e1400000000);
          default:
            ctrl = ctrl_word_t'(68'h8348aae1400000000);
        endcase
      end
      8'h63: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h835088e1400000000);
          default:
            ctrl = ctrl_word_t'(68'h8350aae1400000000);
        endcase
      end
      8'h64: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h832888e1400000000);
          default:
            ctrl = ctrl_word_t'(68'h8328aae1400000000);
        endcase
      end
      8'h65: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h833088e1400000000);
          default:
            ctrl = ctrl_word_t'(68'h8330aae1400000000);
        endcase
      end
      8'h66: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h830884e1400000000);
          default:
            ctrl = ctrl_word_t'(68'h8308a4e1400000000);
        endcase
      end
      8'h67: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h831084e1400000000);
          default:
            ctrl = ctrl_word_t'(68'h8310a4e1400000000);
        endcase
      end
      8'h68: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h816888f1400000000);
          default:
            ctrl = ctrl_word_t'(68'h8168aaf1400000000);
        endcase
      end
      8'h69: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h817088f1400000000);
          default:
            ctrl = ctrl_word_t'(68'h8170aaf1400000000);
        endcase
      end
      8'h6A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h818888f1400000000);
          default:
            ctrl = ctrl_word_t'(68'h8188aaf1400000000);
        endcase
      end
      8'h6B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h819088f1400000000);
          default:
            ctrl = ctrl_word_t'(68'h8190aaf1400000000);
        endcase
      end
      8'h6C: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h9c088000000000000);
          default:
            ctrl = ctrl_word_t'(68'h9c08a001000000000);
        endcase
      end
      8'h6D: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h9c108000000000000);
          default:
            ctrl = ctrl_word_t'(68'h9c10a001000000000);
        endcase
      end
      8'h6E: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82e82800000000000);
          default:
            ctrl = ctrl_word_t'(68'h82e82a00400000000);
        endcase
      end
      8'h6F: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'h82f02800000000000);
          default:
            ctrl = ctrl_word_t'(68'h82f02a00400000000);
        endcase
      end
      8'h70: ctrl = ctrl_word_t'(68'h82e9a001000000000);
      8'h71: ctrl = ctrl_word_t'(68'h82f1a001000000000);
      8'h72: ctrl = ctrl_word_t'(68'h82e83000400000000);
      8'h73: ctrl = ctrl_word_t'(68'h82f03000400000000);
      8'h74: ctrl = ctrl_word_t'(68'ha801a001000000000);
      8'h75: ctrl = ctrl_word_t'(68'h82f9a001000000000);
      8'h76: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(68'ha8008000000000000);
          default:
            ctrl = ctrl_word_t'(68'ha800a001000000000);
        endcase
      end
      8'h77: ctrl = ctrl_word_t'(68'h82f83000400000000);
      8'h78: ctrl = ctrl_word_t'(68'h00000000000000000);
      8'h79: ctrl = ctrl_word_t'(68'hd8048000000000000);
      8'h7A: ctrl = ctrl_word_t'(68'hdc040000000000000);
      8'h7B: begin
        case (w0[7:0])
          8'h0D, 8'h1D, 8'h2D, 8'h3D, 8'h4D, 8'h5D, 8'h6D, 8'h7D, 8'h8D, 8'h9D, 8'hAD, 8'hBD, 
          8'hCD, 8'hDD, 8'hED, 8'hFD:
            ctrl = ctrl_word_t'(68'hcc04000000000000c);
          8'h00:
            ctrl = ctrl_word_t'(68'he4040000000000000);
          8'h08:
            ctrl = ctrl_word_t'(68'hcc040000000000008);
          8'h09:
            ctrl = ctrl_word_t'(68'hcc040000000000004);
          8'h0A:
            ctrl = ctrl_word_t'(68'hcc040000000000000);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'h7C: begin
        case (w0[7:0])
          8'h01, 8'h09, 8'h11, 8'h19, 8'h21, 8'h29, 8'h31, 8'h39, 8'h41, 8'h49, 8'h51, 8'h59, 
          8'h61, 8'h69, 8'h71, 8'h79, 8'h81, 8'h89, 8'h91, 8'h99, 8'hA1, 8'hA9, 8'hB1, 8'hB9, 
          8'hC1, 8'hC9, 8'hD1, 8'hD9, 8'hE1, 8'hE9, 8'hF1, 8'hF9:
            ctrl = ctrl_word_t'(68'h84040000088000000);
          8'h02, 8'h0A, 8'h12, 8'h1A, 8'h22, 8'h2A, 8'h32, 8'h3A, 8'h42, 8'h4A, 8'h52, 8'h5A, 
          8'h62, 8'h6A, 8'h72, 8'h7A, 8'h82, 8'h8A, 8'h92, 8'h9A, 8'hA2, 8'hAA, 8'hB2, 8'hBA, 
          8'hC2, 8'hCA, 8'hD2, 8'hDA, 8'hE2, 8'hEA, 8'hF2, 8'hFA:
            ctrl = ctrl_word_t'(68'h84040000084000000);
          8'h03, 8'h0B, 8'h13, 8'h1B, 8'h23, 8'h2B, 8'h33, 8'h3B, 8'h43, 8'h4B, 8'h53, 8'h5B, 
          8'h63, 8'h6B, 8'h73, 8'h7B, 8'h83, 8'h8B, 8'h93, 8'h9B, 8'hA3, 8'hAB, 8'hB3, 8'hBB, 
          8'hC3, 8'hCB, 8'hD3, 8'hDB, 8'hE3, 8'hEB, 8'hF3, 8'hFB:
            ctrl = ctrl_word_t'(68'h84040000080000000);
          8'h04, 8'h0C, 8'h14, 8'h1C, 8'h24, 8'h2C, 8'h34, 8'h3C, 8'h44, 8'h4C, 8'h54, 8'h5C, 
          8'h64, 8'h6C, 8'h74, 8'h7C, 8'h84, 8'h8C, 8'h94, 8'h9C, 8'hA4, 8'hAC, 8'hB4, 8'hBC, 
          8'hC4, 8'hCC, 8'hD4, 8'hDC, 8'hE4, 8'hEC, 8'hF4, 8'hFC:
            ctrl = ctrl_word_t'(68'h8404000000c000000);
          8'h05, 8'h0D, 8'h15, 8'h1D, 8'h25, 8'h2D, 8'h35, 8'h3D, 8'h45, 8'h4D, 8'h55, 8'h5D, 
          8'h65, 8'h6D, 8'h75, 8'h7D, 8'h85, 8'h8D, 8'h95, 8'h9D, 8'hA5, 8'hAD, 8'hB5, 8'hBD, 
          8'hC5, 8'hCD, 8'hD5, 8'hDD, 8'hE5, 8'hED, 8'hF5, 8'hFD:
            ctrl = ctrl_word_t'(68'h84040000008000000);
          8'h06, 8'h0E, 8'h16, 8'h1E, 8'h26, 8'h2E, 8'h36, 8'h3E, 8'h46, 8'h4E, 8'h56, 8'h5E, 
          8'h66, 8'h6E, 8'h76, 8'h7E, 8'h86, 8'h8E, 8'h96, 8'h9E, 8'hA6, 8'hAE, 8'hB6, 8'hBE, 
          8'hC6, 8'hCE, 8'hD6, 8'hDE, 8'hE6, 8'hEE, 8'hF6, 8'hFE:
            ctrl = ctrl_word_t'(68'h84040000004000000);
          8'h07, 8'h0F, 8'h17, 8'h1F, 8'h27, 8'h2F, 8'h37, 8'h3F, 8'h47, 8'h4F, 8'h57, 8'h5F, 
          8'h67, 8'h6F, 8'h77, 8'h7F, 8'h87, 8'h8F, 8'h97, 8'h9F, 8'hA7, 8'hAF, 8'hB7, 8'hBF, 
          8'hC7, 8'hCF, 8'hD7, 8'hDF, 8'hE7, 8'hEF, 8'hF7, 8'hFF:
            ctrl = ctrl_word_t'(68'h84040000000000000);
          default:
            ctrl = ctrl_word_t'(68'h8404000008c000000);
        endcase
      end
      8'h7D: ctrl = ctrl_word_t'(68'hb0040000000000000);
      8'h7E: ctrl = ctrl_word_t'(68'h00000000000000000);
      8'h7F: ctrl = ctrl_word_t'(68'he0000000000000000);
      8'h80: ctrl = ctrl_word_t'(68'h80082001000000000);
      8'h81: ctrl = ctrl_word_t'(68'h80102001000000000);
      8'h82: ctrl = ctrl_word_t'(68'h80482001000000000);
      8'h83: ctrl = ctrl_word_t'(68'h80502001000000000);
      8'h84: ctrl = ctrl_word_t'(68'h80a82001000000000);
      8'h85: ctrl = ctrl_word_t'(68'h80b02001000000000);
      8'h86: ctrl = ctrl_word_t'(68'h80882001000000000);
      8'h87: ctrl = ctrl_word_t'(68'h80902001000000000);
      8'h88: ctrl = ctrl_word_t'(68'h80c82001000000000);
      8'h89: ctrl = ctrl_word_t'(68'h80d02001000000000);
      8'h8A: ctrl = ctrl_word_t'(68'h81482201000000000);
      8'h8B: ctrl = ctrl_word_t'(68'h81502201000000000);
      8'h8C: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'h80e80004400000000);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'h84000000200000000);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(68'h81080004400000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(68'h81280204400000000);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(68'h83680004400000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(68'h82e92000400000000);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(68'h84000000180000000);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'h8D: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'h80f00004400000000);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(68'h81100004400000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(68'h81300204400000000);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(68'h83700004400000000);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(68'h82f12200000000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(68'h82f12000400000000);
          8'h01:
            ctrl = ctrl_word_t'(68'h84000000000000000);
          8'h03:
            ctrl = ctrl_word_t'(68'h84000000080000000);
          8'h05:
            ctrl = ctrl_word_t'(68'h84000000100000000);
          8'h11:
            ctrl = ctrl_word_t'(68'h84000000000080000);
          8'h13:
            ctrl = ctrl_word_t'(68'h84000000080080000);
          8'h15:
            ctrl = ctrl_word_t'(68'h84000000100080000);
          8'h21:
            ctrl = ctrl_word_t'(68'h84000000000100000);
          8'h23:
            ctrl = ctrl_word_t'(68'h84000000080100000);
          8'h25:
            ctrl = ctrl_word_t'(68'h84000000100100000);
          8'h31:
            ctrl = ctrl_word_t'(68'h84000000000180000);
          8'h33:
            ctrl = ctrl_word_t'(68'h84000000080180000);
          8'h35:
            ctrl = ctrl_word_t'(68'h84000000100180000);
          8'h41:
            ctrl = ctrl_word_t'(68'h84000000000200000);
          8'h43:
            ctrl = ctrl_word_t'(68'h84000000080200000);
          8'h45:
            ctrl = ctrl_word_t'(68'h84000000100200000);
          8'h51:
            ctrl = ctrl_word_t'(68'h84000000000280000);
          8'h53:
            ctrl = ctrl_word_t'(68'h84000000080280000);
          8'h55:
            ctrl = ctrl_word_t'(68'h84000000100280000);
          8'h61:
            ctrl = ctrl_word_t'(68'h84000000000300000);
          8'h63:
            ctrl = ctrl_word_t'(68'h84000000080300000);
          8'h65:
            ctrl = ctrl_word_t'(68'h84000000100300000);
          8'h71:
            ctrl = ctrl_word_t'(68'h84000000000380000);
          8'h73:
            ctrl = ctrl_word_t'(68'h84000000080380000);
          8'h75:
            ctrl = ctrl_word_t'(68'h84000000100380000);
          8'h81:
            ctrl = ctrl_word_t'(68'h84000000000400000);
          8'h83:
            ctrl = ctrl_word_t'(68'h84000000080400000);
          8'h85:
            ctrl = ctrl_word_t'(68'h84000000100400000);
          8'h91:
            ctrl = ctrl_word_t'(68'h84000000000480000);
          8'h93:
            ctrl = ctrl_word_t'(68'h84000000080480000);
          8'h95:
            ctrl = ctrl_word_t'(68'h84000000100480000);
          8'hA1:
            ctrl = ctrl_word_t'(68'h84000000000500000);
          8'hA3:
            ctrl = ctrl_word_t'(68'h84000000080500000);
          8'hA5:
            ctrl = ctrl_word_t'(68'h84000000100500000);
          8'hB1:
            ctrl = ctrl_word_t'(68'h84000000000580000);
          8'hB3:
            ctrl = ctrl_word_t'(68'h84000000080580000);
          8'hB5:
            ctrl = ctrl_word_t'(68'h84000000100580000);
          8'hC1:
            ctrl = ctrl_word_t'(68'h84000000000600000);
          8'hC3:
            ctrl = ctrl_word_t'(68'h84000000080600000);
          8'hC5:
            ctrl = ctrl_word_t'(68'h84000000100600000);
          8'hD1:
            ctrl = ctrl_word_t'(68'h84000000000680000);
          8'hD3:
            ctrl = ctrl_word_t'(68'h84000000080680000);
          8'hD5:
            ctrl = ctrl_word_t'(68'h84000000100680000);
          8'hE1:
            ctrl = ctrl_word_t'(68'h84000000000700000);
          8'hE3:
            ctrl = ctrl_word_t'(68'h84000000080700000);
          8'hE5:
            ctrl = ctrl_word_t'(68'h84000000100700000);
          8'hF1:
            ctrl = ctrl_word_t'(68'h84000000000780000);
          8'hF3:
            ctrl = ctrl_word_t'(68'h84000000080780000);
          8'hF5:
            ctrl = ctrl_word_t'(68'h84000000100780000);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'h8E: ctrl = ctrl_word_t'(68'hec000000000000003);
      8'h8F: ctrl = ctrl_word_t'(68'hec000000000000002);
      8'h90: ctrl = ctrl_word_t'(68'h81582201000000000);
      8'h91: ctrl = ctrl_word_t'(68'h8c000000000001000);
      8'h92: ctrl = ctrl_word_t'(68'h80582001000000000);
      8'h93: ctrl = ctrl_word_t'(68'h8c000000000000000);
      8'h94: ctrl = ctrl_word_t'(68'h82f82001000000000);
      8'h95: ctrl = ctrl_word_t'(68'h8c000000000001800);
      8'h96: ctrl = ctrl_word_t'(68'h80182001000000000);
      8'h97: ctrl = ctrl_word_t'(68'h8c000000000000800);
      8'h98: ctrl = ctrl_word_t'(68'hd0182001000000000);
      8'h99: ctrl = ctrl_word_t'(68'hd0102001000000000);
      8'h9A: ctrl = ctrl_word_t'(68'hd4182001000000000);
      8'h9B: ctrl = ctrl_word_t'(68'hd4102001000000000);
      8'h9C: ctrl = ctrl_word_t'(68'h81380204000000000);
      8'h9D: ctrl = ctrl_word_t'(68'h00000000000000000);
      8'h9E: ctrl = ctrl_word_t'(68'h90000000000000480);
      8'h9F: ctrl = ctrl_word_t'(68'h00000000000000000);
      8'hA0: ctrl = ctrl_word_t'(68'h82e82001000000000);
      8'hA1: ctrl = ctrl_word_t'(68'h82f02001000000000);
      8'hA2: ctrl = ctrl_word_t'(68'h8349c004400000000);
      8'hA3: ctrl = ctrl_word_t'(68'h8351c004400000000);
      8'hA4: ctrl = ctrl_word_t'(68'h8329c004400000000);
      8'hA5: ctrl = ctrl_word_t'(68'h8331c004400000000);
      8'hA6: ctrl = ctrl_word_t'(68'h8309c204400000000);
      8'hA7: ctrl = ctrl_word_t'(68'h8311c204400000000);
      8'hA8: ctrl = ctrl_word_t'(68'h8169e004400000000);
      8'hA9: ctrl = ctrl_word_t'(68'h8171e004400000000);
      8'hAA: ctrl = ctrl_word_t'(68'h8189e004400000000);
      8'hAB: ctrl = ctrl_word_t'(68'h8191e004400000000);
      8'hAC: ctrl = ctrl_word_t'(68'h9c080000000000000);
      8'hAD: ctrl = ctrl_word_t'(68'h9c100000000000000);
      8'hAE: ctrl = ctrl_word_t'(68'h94080000000000000);
      8'hAF: ctrl = ctrl_word_t'(68'h94100000000000000);
      8'hB0: ctrl = ctrl_word_t'(68'h98000000000000000);
      8'hB1: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'h88080000000000000);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(68'h88180000000000000);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(68'h88100000000000000);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'hB2: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(68'h8228c004400000000);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'hb5e80020000000000);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(68'h8228e004400000000);
          8'h03, 8'h13, 8'h23, 8'h33, 8'h43, 8'h53, 8'h63, 8'h73, 8'h83, 8'h93, 8'hA3, 8'hB3, 
          8'hC3, 8'hD3, 8'hE3, 8'hF3:
            ctrl = ctrl_word_t'(68'hb5e80010000000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(68'h8248c004400000000);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(68'h8248e004400000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(68'h8268c004400000000);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(68'hb5a80020000000000);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(68'h8268e004400000000);
          8'h0B, 8'h1B, 8'h2B, 8'h3B, 8'h4B, 8'h5B, 8'h6B, 8'h7B, 8'h8B, 8'h9B, 8'hAB, 8'hBB, 
          8'hCB, 8'hDB, 8'hEB, 8'hFB:
            ctrl = ctrl_word_t'(68'hb5a80010000000000);
          8'h0C, 8'h1C, 8'h2C, 8'h3C, 8'h4C, 8'h5C, 8'h6C, 8'h7C, 8'h8C, 8'h9C, 8'hAC, 8'hBC, 
          8'hCC, 8'hDC, 8'hEC, 8'hFC:
            ctrl = ctrl_word_t'(68'h8288c004400000000);
          8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h4E, 8'h5E, 8'h6E, 8'h7E, 8'h8E, 8'h9E, 8'hAE, 8'hBE, 
          8'hCE, 8'hDE, 8'hEE, 8'hFE:
            ctrl = ctrl_word_t'(68'h8288e004400000000);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'hB3: begin
        case (w0[7:0])
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'hb5f00020000000000);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(68'h8230e004400000000);
          8'h03, 8'h13, 8'h23, 8'h33, 8'h43, 8'h53, 8'h63, 8'h73, 8'h83, 8'h93, 8'hA3, 8'hB3, 
          8'hC3, 8'hD3, 8'hE3, 8'hF3:
            ctrl = ctrl_word_t'(68'hb5f00010000000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(68'h8250c004400000000);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(68'hb5f80020000000000);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(68'h8250e004400000000);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(68'hb5f80010000000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(68'h8270c004400000000);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(68'hb5b00020000000000);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(68'h8270e004400000000);
          8'h0B, 8'h1B, 8'h2B, 8'h3B, 8'h4B, 8'h5B, 8'h6B, 8'h7B, 8'h8B, 8'h9B, 8'hAB, 8'hBB, 
          8'hCB, 8'hDB, 8'hEB, 8'hFB:
            ctrl = ctrl_word_t'(68'hb5b00010000000000);
          8'h0C, 8'h1C, 8'h2C, 8'h3C, 8'h4C, 8'h5C, 8'h6C, 8'h7C, 8'h8C, 8'h9C, 8'hAC, 8'hBC, 
          8'hCC, 8'hDC, 8'hEC, 8'hFC:
            ctrl = ctrl_word_t'(68'h8290c004400000000);
          8'h0D, 8'h1D, 8'h2D, 8'h3D, 8'h4D, 8'h5D, 8'h6D, 8'h7D, 8'h8D, 8'h9D, 8'hAD, 8'hBD, 
          8'hCD, 8'hDD, 8'hED, 8'hFD:
            ctrl = ctrl_word_t'(68'hb5b80020000000000);
          8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h4E, 8'h5E, 8'h6E, 8'h7E, 8'h8E, 8'h9E, 8'hAE, 8'hBE, 
          8'hCE, 8'hDE, 8'hEE, 8'hFE:
            ctrl = ctrl_word_t'(68'h8290e004400000000);
          8'h0F, 8'h1F, 8'h2F, 8'h3F, 8'h4F, 8'h5F, 8'h6F, 8'h7F, 8'h8F, 8'h9F, 8'hAF, 8'hBF, 
          8'hCF, 8'hDF, 8'hEF, 8'hFF:
            ctrl = ctrl_word_t'(68'hb5b80010000000000);
          default:
            ctrl = ctrl_word_t'(68'h8230c004400000000);
        endcase
      end
      8'hB4: ctrl = ctrl_word_t'(68'h80282001000000000);
      8'hB5: ctrl = ctrl_word_t'(68'h80302001000000000);
      8'hB6: ctrl = ctrl_word_t'(68'h80682001000000000);
      8'hB7: ctrl = ctrl_word_t'(68'h80702001000000000);
      8'hB8: begin
        case (w0[7:0])
          8'h00, 8'h04, 8'h10, 8'h14, 8'h20, 8'h24, 8'h30, 8'h34, 8'h40, 8'h44, 8'h50, 8'h54, 
          8'h60, 8'h64, 8'h70, 8'h74, 8'h80, 8'h84, 8'h90, 8'h94, 8'hA0, 8'hA4, 8'hB0, 8'hB4, 
          8'hC0, 8'hC4, 8'hD0, 8'hD4, 8'hE0, 8'hE4, 8'hF0, 8'hF4:
            ctrl = ctrl_word_t'(68'he8000000000000040);
          8'h02, 8'h06, 8'h12, 8'h16, 8'h22, 8'h26, 8'h32, 8'h36, 8'h42, 8'h46, 8'h52, 8'h56, 
          8'h62, 8'h66, 8'h72, 8'h76, 8'h82, 8'h86, 8'h92, 8'h96, 8'hA2, 8'hA6, 8'hB2, 8'hB6, 
          8'hC2, 8'hC6, 8'hD2, 8'hD6, 8'hE2, 8'hE6, 8'hF2, 8'hF6:
            ctrl = ctrl_word_t'(68'he8000000000000000);
          8'h08, 8'h0C, 8'h18, 8'h1C, 8'h28, 8'h2C, 8'h38, 8'h3C, 8'h48, 8'h4C, 8'h58, 8'h5C, 
          8'h68, 8'h6C, 8'h78, 8'h7C, 8'h88, 8'h8C, 8'h98, 8'h9C, 8'hA8, 8'hAC, 8'hB8, 8'hBC, 
          8'hC8, 8'hCC, 8'hD8, 8'hDC, 8'hE8, 8'hEC, 8'hF8, 8'hFC:
            ctrl = ctrl_word_t'(68'he8000000000000050);
          8'h0A, 8'h0E, 8'h1A, 8'h1E, 8'h2A, 8'h2E, 8'h3A, 8'h3E, 8'h4A, 8'h4E, 8'h5A, 8'h5E, 
          8'h6A, 8'h6E, 8'h7A, 8'h7E, 8'h8A, 8'h8E, 8'h9A, 8'h9E, 8'hAA, 8'hAE, 8'hBA, 8'hBE, 
          8'hCA, 8'hCE, 8'hDA, 8'hDE, 8'hEA, 8'hEE, 8'hFA, 8'hFE:
            ctrl = ctrl_word_t'(68'he8000000000000010);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'hB9: ctrl = ctrl_word_t'(68'h00000000000000000);
      8'hBA: begin
        case (w0[7:0])
          8'h00, 8'h04, 8'h10, 8'h14, 8'h20, 8'h24, 8'h30, 8'h34, 8'h40, 8'h44, 8'h50, 8'h54, 
          8'h60, 8'h64, 8'h70, 8'h74, 8'h80, 8'h84, 8'h90, 8'h94, 8'hA0, 8'hA4, 8'hB0, 8'hB4, 
          8'hC0, 8'hC4, 8'hD0, 8'hD4, 8'hE0, 8'hE4, 8'hF0, 8'hF4:
            ctrl = ctrl_word_t'(68'hbc080000000000000);
          8'h02, 8'h06, 8'h12, 8'h16, 8'h22, 8'h26, 8'h32, 8'h36, 8'h42, 8'h46, 8'h52, 8'h56, 
          8'h62, 8'h66, 8'h72, 8'h76, 8'h82, 8'h86, 8'h92, 8'h96, 8'hA2, 8'hA6, 8'hB2, 8'hB6, 
          8'hC2, 8'hC6, 8'hD2, 8'hD6, 8'hE2, 8'hE6, 8'hF2, 8'hF6:
            ctrl = ctrl_word_t'(68'hc0080000000000000);
          8'h08, 8'h0C, 8'h18, 8'h1C, 8'h28, 8'h2C, 8'h38, 8'h3C, 8'h48, 8'h4C, 8'h58, 8'h5C, 
          8'h68, 8'h6C, 8'h78, 8'h7C, 8'h88, 8'h8C, 8'h98, 8'h9C, 8'hA8, 8'hAC, 8'hB8, 8'hBC, 
          8'hC8, 8'hCC, 8'hD8, 8'hDC, 8'hE8, 8'hEC, 8'hF8, 8'hFC:
            ctrl = ctrl_word_t'(68'hbc080000000000010);
          8'h0A, 8'h0E, 8'h1A, 8'h1E, 8'h2A, 8'h2E, 8'h3A, 8'h3E, 8'h4A, 8'h4E, 8'h5A, 8'h5E, 
          8'h6A, 8'h6E, 8'h7A, 8'h7E, 8'h8A, 8'h8E, 8'h9A, 8'h9E, 8'hAA, 8'hAE, 8'hBA, 8'hBE, 
          8'hCA, 8'hCE, 8'hDA, 8'hDE, 8'hEA, 8'hEE, 8'hFA, 8'hFE:
            ctrl = ctrl_word_t'(68'hc0080000000000010);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'hb8080000000000000);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(68'hb8080000000000010);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'hBB: begin
        case (w0[7:0])
          8'h00, 8'h04, 8'h10, 8'h14, 8'h20, 8'h24, 8'h30, 8'h34, 8'h40, 8'h44, 8'h50, 8'h54, 
          8'h60, 8'h64, 8'h70, 8'h74, 8'h80, 8'h84, 8'h90, 8'h94, 8'hA0, 8'hA4, 8'hB0, 8'hB4, 
          8'hC0, 8'hC4, 8'hD0, 8'hD4, 8'hE0, 8'hE4, 8'hF0, 8'hF4:
            ctrl = ctrl_word_t'(68'hbc100000000000000);
          8'h02, 8'h06, 8'h12, 8'h16, 8'h22, 8'h26, 8'h32, 8'h36, 8'h42, 8'h46, 8'h52, 8'h56, 
          8'h62, 8'h66, 8'h72, 8'h76, 8'h82, 8'h86, 8'h92, 8'h96, 8'hA2, 8'hA6, 8'hB2, 8'hB6, 
          8'hC2, 8'hC6, 8'hD2, 8'hD6, 8'hE2, 8'hE6, 8'hF2, 8'hF6:
            ctrl = ctrl_word_t'(68'hc0100000000000000);
          8'h08, 8'h0C, 8'h18, 8'h1C, 8'h28, 8'h2C, 8'h38, 8'h3C, 8'h48, 8'h4C, 8'h58, 8'h5C, 
          8'h68, 8'h6C, 8'h78, 8'h7C, 8'h88, 8'h8C, 8'h98, 8'h9C, 8'hA8, 8'hAC, 8'hB8, 8'hBC, 
          8'hC8, 8'hCC, 8'hD8, 8'hDC, 8'hE8, 8'hEC, 8'hF8, 8'hFC:
            ctrl = ctrl_word_t'(68'hbc100000000000010);
          8'h0A, 8'h0E, 8'h1A, 8'h1E, 8'h2A, 8'h2E, 8'h3A, 8'h3E, 8'h4A, 8'h4E, 8'h5A, 8'h5E, 
          8'h6A, 8'h6E, 8'h7A, 8'h7E, 8'h8A, 8'h8E, 8'h9A, 8'h9E, 8'hAA, 8'hAE, 8'hBA, 8'hBE, 
          8'hCA, 8'hCE, 8'hDA, 8'hDE, 8'hEA, 8'hEE, 8'hFA, 8'hFE:
            ctrl = ctrl_word_t'(68'hc0100000000000010);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(68'hb8100000000000000);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(68'hb8100000000000010);
          default:
            ctrl = ctrl_word_t'(68'h00000000000000000);
        endcase
      end
      8'hBC: ctrl = ctrl_word_t'(68'ha2400000000000000);
      8'hBD: ctrl = ctrl_word_t'(68'h82f1c000400000000);
      8'hBE: ctrl = ctrl_word_t'(68'ha2200000000000000);
      8'hBF: ctrl = ctrl_word_t'(68'h00000000000000000);
      8'hC0: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hC1: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hC2: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hC3: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hC4: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hC5: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hC6: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hC7: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hC8: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hC9: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hCA: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hCB: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hCC: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hCD: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hCE: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hCF: ctrl = ctrl_word_t'(68'h82ea0000800000000);
      8'hD0: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hD1: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hD2: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hD3: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hD4: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hD5: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hD6: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hD7: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hD8: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hD9: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hDA: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hDB: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hDC: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hDD: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hDE: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hDF: ctrl = ctrl_word_t'(68'h90000000000000400);
      8'hE0: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hE1: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hE2: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hE3: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hE4: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hE5: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hE6: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hE7: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hE8: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hE9: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hEA: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hEB: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hEC: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hED: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hEE: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hEF: ctrl = ctrl_word_t'(68'h90000000000000180);
      8'hF0: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hF1: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hF2: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hF3: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hF4: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hF5: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hF6: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hF7: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hF8: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hF9: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hFA: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hFB: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hFC: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hFD: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hFE: ctrl = ctrl_word_t'(68'h90000000000000500);
      8'hFF: ctrl = ctrl_word_t'(68'h90000000000000500);
      default: ctrl = ctrl_word_t'(W'(0));
    endcase
  end

endmodule

`default_nettype wire
