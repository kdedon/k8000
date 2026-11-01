// z8010_mmu -- Zilog Z8010 Memory Management Unit, top level.
//
// Pin seam == ~/git/z8000/sim/mmu/mmu.go Inputs (mmu.go:17-36) / Outputs
// (mmu.go:39-46), one-for-one. The lockstep contract is per-edge pin
// equality against the Go model: tb/k8010_mmu/tb_mmu.cpp replays vectors/k8010_mmu/*.vec
// through these ports (docs/K8010_MMU_TESTS.md).
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
//      sample ack_pending <= 0 and data_drive <= 0. Only line 8+ID is
//      driven on the ack, so several MMUs share AD15:8 per line.
//      dummy-fetch-ignore: the ST=1101 fetch while trap_pending.
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
  input  logic        reset_n,    // active low, sampled at clk

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
  output logic [7:0]  data_drive  // per-line drive of AD15:8 (bit n = AD line 8+n)
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
  logic        sup_held;          // SUP for this cycle, released at the /DS rise
  logic        sup_instr_hold;    // SUP every memory cycle until the next first-word fetch

  // ---- strobe samples and the address latched at the /AS fall ----------------
  logic        prev_as;           // /AS was Low last clock (0 at power-up: High)
  logic        prev_ds;
  logic [6:0]  latched_sn;
  logic [15:0] latched_ad;
  logic        latched_rw;
  logic        latched_ns;
  logic [23:0] pa_q;
  logic        pa_drive_q;

  wire as_fall = ~prev_as & ~as_n;
  wire as_rise = prev_as & as_n;
  wire ds_rise = prev_ds & ds_n;

  // DMA: DMASYNC rising after two or more Low samples presents a DMA address.
  // The DMA cycle owns the bus until its /DS rise, or until DMASYNC has been
  // High for two more samples.
  logic [1:0]  dma_low;
  logic        dma_active;
  logic        dma_high;
  wire dma_go  = dmasync & dma_low[1];
  wire dma_blk = (dma_active & ~ds_rise) | dma_go;

  // A DMA address is translated in the sample it arrives, straight off the pins.
  wire [6:0]  x_sn = dma_go ? sn   : latched_sn;
  wire [15:0] x_ad = dma_go ? ad   : latched_ad;
  wire [3:0]  x_st = dma_go ? st   : latched_st;
  wire        x_rw = dma_go ? r_w  : latched_rw;
  wire        x_ns = dma_go ? n_s  : latched_ns;

  // ---- translate: one lookup, one adder, one comparator tree ------------------
  // Translation and command access never overlap, so they share one lookup.
  wire [5:0]  seg    = x_sn[5:0];
  wire [5:0]  d_idx  = (x_st == 4'h3) ? sar : seg;
  wire [15:0] t_base = desc_base[d_idx];
  wire [7:0]  t_lim  = desc_limit[d_idx];
  wire [7:0]  t_attr = desc_attr[d_idx];
  wire [7:0]  page   = x_ad[15:8];
  wire        fetch  = (latched_st == 4'hC) | (latched_st == 4'hD);

  wire mem_cycle = (x_st >= 4'h8) & (x_st <= 4'hD);
  wire responds  = mode_reg[7] & (x_sn[6] == mode_reg[5]) & mem_cycle
                 & (~mode_reg[4] | (x_ns == mode_reg[3]));
  wire translating = mode_reg[6];

  // Stack segments grow down: Limit is the lowest valid page.
  wire slv  = t_attr[5] ? (page < t_lim) : (page > t_lim);
  wire viol = t_attr[2] | slv | (t_attr[0] & ~latched_rw) | (t_attr[1] & latched_ns)
            | (t_attr[3] & ~fetch);
  // The first-word fetch before a trap acknowledge is ignored: no checks,
  // no REF/CHG. Word fetches of the violating instruction are still checked.
  wire checked = ~(trap_pending & (latched_st == 4'hD));

  wire [23:0] phys = {t_base, 8'h00} + {8'h00, x_ad};
  wire [23:0] pass = {1'b0, x_sn, x_ad};

  wire drive_pa = as_rise & addr_latched & responds & ~dma_blk;
  wire ack_start = as_rise & addr_latched & (latched_st == 4'h4) & mode_reg[7] & ~dma_blk;

  // DMA checks: DMA Inhibit in place of CPU Inhibit, and DMA never fetches.
  wire dma_drive = dma_go & responds;
  wire dma_viol  = t_attr[4] | slv | (t_attr[0] & ~x_rw) | (t_attr[1] & x_ns) | t_attr[3];

  // ---- violation: first one wins the capture, later ones OR into VTR -----------
  wire        wr    = ~latched_rw;
  wire        pww   = ~viol & t_attr[5] & wr & (page == t_lim);
  wire        trap  = drive_pa & translating & checked & (viol | pww);
  wire [7:0]  vbit  = t_attr[2]               ? 8'h08 :
                      slv                     ? 8'h04 :
                      (t_attr[0] & wr)        ? 8'h01 :
                      (t_attr[1] & latched_ns) ? 8'h02 :
                      t_attr[3] & ~fetch      ? 8'h10 : 8'h20;
  wire        stack = (latched_st == 4'h9) | (latched_st == 4'hB);
  // FATL: a violation (or a normal-mode warning) with VTR already holding one.
  wire        fatl  = viol_captured & (viol | latched_ns);
  // SWW: a system stack push into the warning page while a flag is set.
  wire        sww   = ~viol & ~latched_ns & stack & (|viol_type[5:0]) & ~fatl;
  // Once FATL or SWW is set no further trap requests are made.
  wire        req   = ~viol_type[7] & ~viol_type[6] & ~fatl;
  wire [7:0]  vt_next = (viol_captured ? (viol_type | vbit) : vbit) | {fatl, sww, 6'b0};

  // ---- command port: opcode at the /AS rise, data byte while /DS is Low -------
  // /CS counts only at the /AS rise; it may be High again before /DS falls.
  wire [7:0] cmd       = latched_ad[15:8];
  wire       cmd_start = as_rise & addr_latched & (latched_st == 4'h3) & ~cs_n & ~dma_blk;
  logic      cmd_pending;
  wire       cmd_exec  = (cmd_pending | cmd_start) & ~ds_n;
  wire [7:0] din       = ad[15:8];

  // Descriptor commands 08-0F: bit 2 = increment SAR at the end of the field,
  // bits 1:0 = base / limit / attribute / whole descriptor.
  wire  is_desc = (cmd[7:3] == 5'b00001);
  logic [1:0] fld;        // 0 base high, 1 base low, 2 limit, 3 attribute
  logic [1:0] dsc_next;
  logic       last_byte;
  always_comb begin
    unique case (cmd[1:0])
      2'd0: begin fld = (dsc == 2'd0) ? 2'd0 : 2'd1; dsc_next = (dsc == 2'd0) ? 2'd1 : 2'd0;
                  last_byte = (dsc != 2'd0); end
      2'd1: begin fld = 2'd2; dsc_next = dsc;         last_byte = 1'b1; end
      2'd2: begin fld = 2'd3; dsc_next = dsc;         last_byte = 1'b1; end
      2'd3: begin fld = dsc;  dsc_next = dsc + 2'd1;  last_byte = (dsc == 2'd3); end
    endcase
  end

  logic [7:0] rd_byte;
  logic       rd_ok;
  always_comb begin
    rd_ok = 1'b1;
    unique case (fld)
      2'd0: rd_byte = t_base[15:8];
      2'd1: rd_byte = t_base[7:0];
      2'd2: rd_byte = t_lim;
      2'd3: rd_byte = t_attr;
    endcase
    if (!is_desc) begin
      case (cmd)
        8'h00:   rd_byte = mode_reg;
        8'h01:   rd_byte = {2'b00, sar};
        8'h20:   rd_byte = {6'b0, dsc};
        8'h02:   rd_byte = viol_type;
        8'h03:   rd_byte = {1'b0, viol_sn};
        8'h04:   rd_byte = viol_off[15:8];
        8'h05:   rd_byte = bcsr;
        8'h06:   rd_byte = {1'b0, isn};
        8'h07:   rd_byte = ioffset;
        default: begin rd_byte = 8'h00; rd_ok = 1'b0; end
      endcase
    end
  end

  logic [15:0] data_q;
  logic [7:0]  data_drive_q;

  // ---- reset (Go reset(csN)) ------------------------------------------------
  // Reset is sampled like any other pin. CS low at the last reset sample
  // powers the mode register up with MSEN set.
  always_ff @(posedge clk) begin
    if (!reset_n) begin
      for (int i = 0; i < 64; i++) begin
        desc_base[i]  <= 16'h0000;
        desc_limit[i] <= 8'h00;
        desc_attr[i]  <= 8'h00;
      end
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
      sup_held      <= 1'b0;
      sup_instr_hold <= 1'b0;
      mode_reg      <= {~cs_n, 7'b0};
      prev_as       <= 1'b0;
      prev_ds       <= 1'b0;
      pa_drive_q    <= 1'b0;
      cmd_pending   <= 1'b0;
      data_q        <= 16'h0000;
      data_drive_q  <= 8'h00;
      dma_low       <= 2'd0;
      dma_active    <= 1'b0;
      dma_high      <= 1'b0;
    end else begin
      prev_as <= ~as_n;
      prev_ds <= ~ds_n;

      // End of cycle first: a new cycle may start in the same sample.
      // A command that never saw its data phase is dropped.
      if (ds_rise) begin
        pa_drive_q   <= 1'b0;
        data_drive_q <= 8'h00;
        cmd_pending  <= 1'b0;
        ack_pending  <= 1'b0;
        sup_held     <= 1'b0;
        dma_active   <= 1'b0;
      end

      dma_low <= dmasync ? 2'd0 : (dma_low[1] ? 2'd2 : dma_low + 2'd1);
      dma_high <= dmasync & dma_active & ~dma_go;
      if (dmasync && dma_active && dma_high)
        dma_active <= 1'b0;
      if (dma_go) begin
        latched_sn   <= sn;
        latched_ad   <= ad;
        latched_st   <= st;
        latched_rw   <= r_w;
        latched_ns   <= n_s;
        addr_latched <= 1'b1;
        dma_active   <= 1'b1;
        pa_drive_q   <= 1'b0;
        data_drive_q <= 8'h00;
        // Violations only suppress this access: no trap, no capture.
        // TRNS governs DMA as it does the CPU.
        if (dma_drive) begin
          pa_q       <= translating ? phys : pass;
          pa_drive_q <= 1'b1;
          if (translating && dma_viol)
            sup_held <= 1'b1;
          else if (translating) begin
            desc_attr[seg][7] <= 1'b1;
            if (!r_w)
              desc_attr[seg][6] <= 1'b1;
          end
        end
      end

      // Trap acknowledge identifier: every enabled MMU drives its own line.
      if (addr_latched && latched_st == 4'h4 && !ds_n && mode_reg[7]) begin
        data_q       <= ack_pending ? (16'h0100 << mode_reg[2:0]) : 16'h0000;
        data_drive_q <= 8'h01 << mode_reg[2:0];
      end

      // PA floats at the start of the next cycle.
      if (as_fall) begin
        pa_drive_q   <= 1'b0;
        data_drive_q <= 8'h00;
      end
      if (cmd_start)
        cmd_pending <= 1'b1;

      if (cmd_exec) begin
        cmd_pending <= 1'b0;
        if (latched_rw) begin
          if (rd_ok) begin
            data_q       <= {rd_byte, 8'h00};
            data_drive_q <= 8'hFF;
          end
        end else begin
          case (cmd)
            8'h00: mode_reg <= din;
            8'h01: begin sar <= din[5:0]; dsc <= 2'd0; end
            8'h20: dsc <= din[1:0];
            8'h11: begin
              viol_type     <= 8'h00;
              viol_captured <= 1'b0;
              viol_overflow <= 1'b0;
              trap_pending  <= 1'b0;
              sup_held      <= 1'b0;
              sup_instr_hold <= 1'b0;
            end
            8'h13: viol_type[6] <= 1'b0;
            8'h14: viol_type[7] <= 1'b0;
            8'h15: for (int i = 0; i < 64; i++) desc_attr[i][2] <= 1'b1;
            8'h16: for (int i = 0; i < 64; i++) desc_attr[i][4] <= 1'b1;
            default: ;
          endcase
          if (is_desc) begin
            unique case (fld)
              2'd0: desc_base[sar][15:8] <= din;
              2'd1: desc_base[sar][7:0]  <= din;
              2'd2: desc_limit[sar]      <= din;
              2'd3: desc_attr[sar]       <= din;
            endcase
          end
        end
        if (is_desc) begin
          dsc <= dsc_next;
          if (cmd[2] && last_byte)
            sar <= sar + 6'd1;
        end
      end

      if (as_fall) begin
        if (!dma_blk) begin
          latched_sn   <= sn;
          latched_ad   <= ad;
          latched_st   <= st;
          latched_rw   <= r_w;
          latched_ns   <= n_s;
          addr_latched <= 1'b1;
          // A first-word fetch starts the next instruction and ends the hold.
          if (st == 4'hD)
            sup_instr_hold <= 1'b0;
          else if (sup_instr_hold && st >= 4'h8 && st <= 4'hD)
            sup_held <= 1'b1;
          if (st == 4'hD && !viol_captured) begin
            isn     <= sn;
            ioffset <= ad[15:8];
          end
        end
      end else if (ds_rise) begin
        addr_latched <= 1'b0;
      end

      if (drive_pa) begin
        pa_q       <= translating ? phys : pass;
        pa_drive_q <= 1'b1;
        if (translating && checked && !viol) begin
          desc_attr[seg][7] <= 1'b1;
          if (!latched_rw)
            desc_attr[seg][6] <= 1'b1;
        end
      end

      if (ack_start) begin
        ack_pending  <= trap_pending;
        trap_pending <= 1'b0;
      end

      if (trap) begin
        viol_type <= vt_next;
        if (!viol_captured) begin
          viol_sn       <= latched_sn;
          viol_off      <= latched_ad;
          bcsr          <= {2'b00, latched_ns, latched_rw, latched_st};
          viol_captured <= 1'b1;
        end else begin
          viol_overflow <= 1'b1;
        end
        if (req)
          trap_pending <= 1'b1;
        if (viol) begin
          sup_held       <= 1'b1;
          sup_instr_hold <= 1'b1;
        end
      end
    end
  end

  // ---- pins: released the moment reset goes Low (Go DefaultOutputs) ----------
  always_comb begin
    pa         = pa_q;
    pa_drive   = pa_drive_q & reset_n;
    segt_n     = ~(trap_pending & reset_n);
    sup_n      = ~(sup_held & reset_n);
    data       = data_q;
    data_drive = data_drive_q & {8{reset_n}};
  end

  // ---- scaffold-only lint waivers: remove as each input gains a consumer ----
  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  always_comb begin
    unused_ok = ^{viol_off[7:0], viol_overflow, t_attr[7:6]};
  end
  // verilator lint_on UNUSEDSIGNAL

endmodule
