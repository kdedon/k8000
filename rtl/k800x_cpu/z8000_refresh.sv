// z8000_refresh -- DRAM refresh unit (cpu.go Tick prescaler + REFRESH reg).
//
// REFRESH register: bit15 RE, bits14:9 RATE (0 -> 64), bits8:0 ROW (bit0
// always 0; +2 per refresh, 256 distinct rows). Prescaler is fed CLK/4 and
// FREE-RUNS regardless of bus activity; underflow only LATCHES pending;
// the refresh bus cycle (ST=0001, no DS_n) issues at the next IF1 /
// internal-op / HALT boundary; mid-instruction refresh bookkeeping per
// snapshot fields RefreshInFlight/RefreshStolenMark/RefreshStolen.
//
// STATUS: SCAFFOLD (empty shell).

module z8000_refresh (
  input  logic        clk,
  input  logic        reset_n,
  input  logic        enable,        // REFRESH.RE
  input  logic [5:0]  rate,          // REFRESH[14:9]
  input  logic        row_step,      // a refresh cycle was issued: ROW += 2
  input  logic        clear_pending, // refresh cycle accepted by the bus unit
  output logic        pending,
  output logic [8:0]  row
);

  // TODO(scaffold)
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      pending <= 1'b0;
      row     <= 9'd0;
    end else begin
      if (clear_pending) pending <= 1'b0;
      if (row_step)      row     <= row + 9'd2;
    end
  end

  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{enable, rate};
  // verilator lint_on UNUSEDSIGNAL

endmodule
