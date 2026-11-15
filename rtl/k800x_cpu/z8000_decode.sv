// z8000_decode -- instruction decode: (w0, w1[3:0]) -> ctrl_word_t, from
// the generated ROM. An instruction's length is its machine-cycle
// program's, not the decoder's.

`default_nettype none

module z8000_decode
  import z8000_ctrl_pkg::*;
(
  input  logic [15:0] w0,
  input  logic [3:0]  w1_lo,
  output ctrl_word_t  ctrl
);

  z8000_decode_rom_gen u_rom (
    .w0    (w0),
    .w1_lo (w1_lo),
    .ctrl  (ctrl)
  );

endmodule

`default_nettype wire
