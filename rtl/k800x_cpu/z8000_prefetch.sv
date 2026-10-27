// z8000_prefetch -- 2-deep instruction look-ahead queue + EA sequencer
// (sim/cpu/prefetch.go, ea.go; G-46 phase 2). Port THAT structure, not the
// old opcode-buffer description: three fill paths (demand / stream-ahead /
// look-ahead); one IF1 per executing instruction; PC-writers inhibit
// look-ahead; launches only at internal-op boundaries with >=3 clocks
// remaining; refresh has priority for the free slot; poisoned-word ABORT
// attribution fires on CONSUME, not arrival; fetchAlignRem 3-clock boundary
// cadence for queue-hit IF1s. Snapshot fields PfWords/PfAddrs/PfPoison/PfLA/
// PfQLen/PfInFlight/... and EaActive/EaI/EaAddr/EaSegw/EaBuildCycle are the
// register inventory.
//
// STATUS: SCAFFOLD (empty shell).

module z8000_prefetch #(
  parameter bit SEGMENTED = 1
) (
  input  logic clk,
  input  logic reset_n
);

  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{clk, reset_n, SEGMENTED};
  // verilator lint_on UNUSEDSIGNAL

endmodule
