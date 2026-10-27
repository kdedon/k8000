// z8000_int_unit -- interrupt/trap unit (sim/cpu/interrupt.go).
//
// irqReq accumulator + priority encoder (EPU > TRAP > SYSCALL > NMI >
// SEGTRAP > VI > NVI); NMI falling-edge latch (two-FF sync + edge detect,
// lessons sv-37/38); level VI/NVI/SEGT sampled per clock; de-recursed step
// FSM (steps 0-6, 11, 12): INTACK cycle (ST = 0100..0111, DS_n falls late),
// segmented 4-byte PC push vs 2-byte, tag push, FCW push, staged FCW commit
// after the last PSA read, changeFCW SP banking (nspoff/nspseg swap).
// Formal target: NMI-over-VI priority (lesson sv-44).
//
// STATUS: SCAFFOLD (empty shell).

module z8000_int_unit #(
  parameter bit SEGMENTED = 1,
  parameter bit VMPU      = 0
) (
  input  logic clk,
  input  logic reset_n,
  input  logic nmi_n,
  input  logic nvi_n,
  input  logic vi_n,
  input  logic segt_n
);

  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{clk, reset_n, nmi_n, nvi_n, vi_n, segt_n, SEGMENTED, VMPU};
  // verilator lint_on UNUSEDSIGNAL

endmodule
