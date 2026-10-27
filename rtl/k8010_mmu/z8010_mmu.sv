// z8010_mmu -- Zilog Z8010 Memory Management Unit, top level.
//
// Pin seam == ~/git/z8000/sim/mmu/mmu.go Inputs (mmu.go:17-36) / Outputs
// (mmu.go:39-46), one-for-one. The lockstep contract is per-edge pin
// equality against the Go model: tb/k8010_mmu/tb_mmu.cpp replays vectors/k8010_mmu/*.vec
// through these ports (docs/K8010_MMU_TESTS.md).
//
// STATUS: SCAFFOLD. Only the reset pin state is implemented (Go
// DefaultOutputs(): SEGT_n/SUP_n released, PA/Data not driven) and the
// register inventory is declared. Every vector that expects the chip to do
// anything fails until the steps below exist.
//
// Implementation order (FPGA_BIBLE Ch.3.4):
//   1. Port list (done) + Ch.2 strobe capture: sample as_n/ds_n/dmasync
//      with clk, edge-detect from the previous sample (Go prevAS_n/prevDS_n/
//      prevDMASYNC, mmu.go tick: asFallingEdge/asRisingEdge/dsRisingEdge).
//      Latch sn/ad/st/r_w/n_s at AS fall (mmu.go "asFallingEdge" block).
//      Combinational translate: physAddr = {base,8'h00} + offset, 24-bit;
//      violation checks as one always_comb comparator tree
//      (translate(), mmu.go translate / translateDMA).
//   2. Descriptor store + SAR/DSC command engine: executeCommand
//      (mmu.go, the 22-entry case table; 0x0D = Limit+incSAR, 0x0E =
//      Attr+incSAR per UM010401 Table 3-6). Command data rides ad[15:8]
//      ONLY (the Z8010 has no AD0-7 pins).
//   3. Trap/suppress FSM: segt_n asserted while trap_pending; sup_n per
//      cycle (sup_held, released at DS rise) plus until-end-of-instruction
//      hold (sup_instr_hold, cleared on the next ST=1101 AS fall);
//      SEGT-ack: at the AS-rise sample of a latched ST=0100 cycle,
//      ack_pending <= trap_pending, trap_pending <= 0 (SEGT released,
//      Fig.12 p.570); while ds_n is low drive ad line 8+ID = ack_pending
//      (every enabled MMU drives, 1 = trapped / 0 = not); at the DS-rise
//      sample ack_pending <= 0 and data_drive <= 0.
//      dummy-fetch-ignore while trap_pending (mmu.go translate top).
//      pa_drive and data_drive drop at the DS-rise sample (TdDS(Af),
//      TdDSR(RDf)); command reads drive data only while ds_n is low
//      (TdDSR(RDv)) and both reads and writes execute at the first
//      DS-low sample after the AS-rise that latched the command (cs_n is
//      sampled at that AS rise only).
//   4. DMASYNC path: >=2 low samples then a rising edge -> DMA translate,
//      suppress-only, no SEGT / no VTR capture (translateDMA).
//   5. Reset: Go reset(csN) -- everything cleared; if cs_n is LOW while
//      reset_n is low, mode_reg powers up with MSEN (bit 7) = 1
//      (pass-through). Reset acts on every Go Tick regardless of CLK
//      (asynchronous). Note the vectors always hold reset across at least
//      one posedge, so a synchronous sample of cs_n during reset is
//      observably equivalent.
//   6. Open-drain segt_n/sup_n: internally an out+oe pair (lesson
//      sv-30-open-drain). At THIS port the pin is presented as the
//      resolved level with the board pull-up (0 = this chip drives low,
//      1 = released), which is exactly the Go bool. The system top can
//      wire-OR several MMUs by AND-ing these outputs.
//
// Harness contract (tb/k8010_mmu/mmu_access.h peeks/pokes these by hierarchical name;
// keep the names or update mmu_access.h in the same change):
//   mode_reg sar dsc viol_type viol_sn viol_off viol_overflow isn ioffset
//   bcsr trap_pending viol_captured addr_latched latched_st ack_pending
//   desc_base[64] desc_limit[64] desc_attr[64]

module z8010_mmu (
  input  logic        clk,
  input  logic        reset_n,    // asynchronous, active low (Go: acts on every Tick)

  // Inputs (mmu.go Inputs)
  input  logic [15:0] ad,         // AD15..AD0 as seen by the chip (only [15:8] exist on silicon)
  input  logic [6:0]  sn,         // SN6..SN0
  input  logic [3:0]  st,         // ST3..ST0
  input  logic        as_n,
  input  logic        ds_n,
  input  logic        r_w,        // 1 = read
  input  logic        n_s,        // 1 = normal mode
  input  logic        cs_n,       // chip select for command (special I/O) access
  input  logic        dmasync,    // DMA segment number valid (active high)

  // Outputs (mmu.go Outputs) -- PA and Data as value+drive pairs, no tri-state
  output logic [23:0] pa,
  output logic        pa_drive,
  output logic        segt_n,     // open drain, resolved level (see header note 6)
  output logic        sup_n,      // open drain, resolved level
  output logic [15:0] data,       // driven onto AD during command reads / SEGT ack
  output logic        data_drive
);

  // ---- register inventory (snapshot.go Snapshot == the register list) ------
  logic [15:0] desc_base  [64];
  logic [7:0]  desc_limit [64];
  logic [7:0]  desc_attr  [64];   // 7=REF 6=CHG 5=DIRW 4=DMAI 3=EXC 2=CPUI 1=SYS 0=RD
  logic [7:0]  mode_reg;          // 7=MSEN 6=TRNS 5=URS 4=MST 3=NMS 2:0=ID
  logic [5:0]  sar;
  logic [1:0]  dsc;
  logic [7:0]  viol_type;         // 7=FATL 6=SWW 5=PWW 4=EXCV 3=CPUIV 2=SLV 1=SYSV 0=RDV
  logic [6:0]  viol_sn;
  logic [15:0] viol_off;
  logic        viol_overflow;
  logic [6:0]  isn;
  logic [7:0]  ioffset;
  logic [7:0]  bcsr;
  logic        trap_pending;
  logic        viol_captured;
  logic        addr_latched;
  logic [3:0]  latched_st;
  logic        ack_pending;       // our trap is the one being acknowledged (identifier phase)
  // TODO(scaffold): prev_as_n, prev_ds_n, prev_dmasync, dma_low_count,
  // latched_sn/ad/rw/ns, dma_active, cmd_pending, cmd_code, sup_held,
  // sup_instr_hold (mmu.go Z8010 struct "Internal state").

  // ---- reset (Go reset(csN)) ------------------------------------------------
  // TODO(scaffold): mode_reg must power up as {~cs_n, 7'b0} (Bible 3.4 step
  // 5); the scaffold clears it. Replace with the real commit block.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      for (int i = 0; i < 64; i++) begin
        desc_base[i]  <= 16'h0000;
        desc_limit[i] <= 8'h00;
        desc_attr[i]  <= 8'h00;
      end
      mode_reg      <= 8'h00;
      sar           <= 6'd0;
      dsc           <= 2'd0;
      viol_type     <= 8'h00;
      viol_sn       <= 7'd0;
      viol_off      <= 16'h0000;
      viol_overflow <= 1'b0;
      isn           <= 7'd0;
      ioffset       <= 8'h00;
      bcsr          <= 8'h00;
      trap_pending  <= 1'b0;
      viol_captured <= 1'b0;
      addr_latched  <= 1'b0;
      latched_st    <= 4'd0;
      ack_pending   <= 1'b0;
    end else begin
      // TODO(scaffold): strobe capture, command engine, translate, trap FSM.
    end
  end

  // ---- reset pin state (Go DefaultOutputs) ------------------------------------
  always_comb begin
    pa         = 24'h000000;
    pa_drive   = 1'b0;
    segt_n     = 1'b1;
    sup_n      = 1'b1;
    data       = 16'h0000;
    data_drive = 1'b0;
  end

  // ---- scaffold-only lint waivers: remove as each input gains a consumer ----
  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  always_comb begin
    unused_ok = ^{ad, sn, st, as_n, ds_n, r_w, n_s, cs_n, dmasync,
                  mode_reg, sar, dsc, viol_type, viol_sn, viol_off, viol_overflow,
                  isn, ioffset, bcsr, trap_pending, viol_captured, addr_latched,
                  latched_st, ack_pending};
    for (int i = 0; i < 64; i++)
      unused_ok = unused_ok ^ (^{desc_base[i], desc_limit[i], desc_attr[i]});
  end
  // verilator lint_on UNUSEDSIGNAL

endmodule
