`default_nettype none
// z8010_mmu -- Zilog Z8010 Memory Management Unit, top level.
//
// Pins: z8010_mmu.pdf (Z8010 Product Specification) p.559 Fig 2 and the
// p.571 Pin Description. Lockstep contract: tb/k8010_mmu/tb_mmu.cpp replays
// vectors/k8010_mmu/*.vec (docs/K8010_MMU_TESTS.md).
//
// Clocking: every flop runs on the board master clock `clk`. `clk_in` is the
// CLK pin as the board's rising-edge pulse (High for the one master clock in
// which CLK rises; it may be High every master clock). /AS and /DS are
// strobes: their edges are seen on the master clock, independently of CLK.
//
// Which edge each input is taken on (AC Characteristics p.573, waveforms
// p.572; 4 MHz column):
//   AD15-AD8 (offset)  latched at the /AS rise. p.571: "The rising edge of AS
//                      indicates that AD0-AD15, ST0-ST3, R/W and N/S are
//                      valid"; #13 TsOFF(AS) 45 ns setup / #14 ThAS(OFFn)
//                      60 ns hold around the /AS rise. Modelled as a latch
//                      that follows the pins while /AS is Low and holds from
//                      the first master clock that sees /AS High.
//   ST3-ST0, R/W, N/S  the same latch (p.571; #21 TdSTNR(AS) valid 50 ns
//                      before the /AS rise; #23 TsST(C) and #24 TdDS(STn)
//                      keep them valid through the next CLK rise to the /DS
//                      rise, so the /AS-rise value is the one the chip uses).
//   /CS                the same latch (#34 TsCS(AS) / #35 ThAS(CSn)).
//   SN6-SN0            taken at every CLK rise (#18 TsSN(C) setup to the CLK
//                      rise of T1, #19 ThC(SNn) held past the CLK rise of
//                      T2); a cycle uses the value from the last CLK rise
//                      before its /AS rise is seen.
//   DMASYNC            at the CLK rise (#20 TdDMAS(C), #22 TdC(DMA)).
//   /RESET             asynchronous on the chip (p.570); here a synchronous
//                      reset, sampled every master clock, that also floats
//                      the pins combinationally. The board synchronises it
//                      to clk. /CS is taken with it: the last value before
//                      the /RESET rise sets MSEN (#37 TsCS(RST) / #38).
//   write data         command write: AD15-AD8 while /DS is Low.
//
// Outputs:
//   A23-A8   driven from the /AS fall (#28 TdAS(Ad)), valid at the latest
//            one CLK after the T1 rise (#29 TdC(Av) 255 ns from the CLK rise
//            under /AS, #25 TdOFF(Av) from the offset, #26 TdST(Ad) from
//            status). While /AS is Low, PA and its drive follow the pins
//            through the open latch, SN from the latest CLK rise (one in the
//            same master clock included); the master clock that sees the /AS
//            rise decides again, and PA holds from then on, so a CPU sharing
//            CLK reads a valid PA at its next CLK rise even at one master
//            clock per CLK. Floats at the /DS rise (#27 TdDS(Af)).
//   /SEGT    asserted from the /AS rise of the violating access (#30
//            TdAS(SEGT)), in the master clock that sees it; released at the
//            third CLK rise from the /AS rise of the trap-acknowledge cycle
//            (the T2 rise is the first; INFERRED from Fig.12 p.570, which
//            draws it rising from the CLK edge that opens the second wait
//            state; #31 TdC(SEGT) is CLK-referenced).
//   /SUP     asserted from the /AS rise (#32 TdAS(SUP)), in the master clock
//            that sees it; released at the /DS rise (#33 TdDS(SUP)).
//   AD15-AD8 command read data / trap-ack identifier from the /DS fall, in
//            the master clock that sees it (#8 TdDSR(RDv), #6 TdDSA(RDv));
//            float at the /DS rise (#9, #7).
//
// Behaviour: one descriptor lookup shared by
// translation and the command port; A23..A8 = base + offset[15:8], or
// {0, SN, offset[15:8]} with TRNS clear (p.562 Fig 4, p.564); the 22-entry
// command table (0x0D = Limit+incSAR, 0x0E = Attr+incSAR, UM010401 Table
// 3-6); violation capture (first wins, later ones OR into VTR); suppress
// until the end of the instruction; trap acknowledge: every enabled MMU
// drives AD line 8+ID; DMA: DMASYNC High after >= 2 Low samples presents a
// DMA address, suppress only, no SEGT / capture. Reset with /CS Low powers
// the mode register up with MSEN set. /SEGT and /SUP are open drain,
// presented as the resolved level (0 = this chip drives Low).
//
// Descriptor storage: base, limit and six attribute bits live in four 64-word
// RAMs with an asynchronous read (MLAB on Cyclone V), so the lookup stays
// combinational in the master clock that sees the /AS rise, exactly as with
// registers. A synchronous (M10K) read would need its address one master
// clock earlier, and a DMA address (DMASYNC at a CLK rise) is translated
// from the pins in the master clock that samples them. The CPU-Inhibit and
// DMA-Inhibit bits stay in flops: commands 15 and 16 set them in all 64
// descriptors at once. /RESET leaves descriptors as they are (p.570: only
// Mode, Violation Type and DSC are cleared; the rest is undefined), zero
// from power-up. One write port: a command write and a REF/CHG update
// in the same master clock (a command whose /DS falls after the next cycle's
// /AS rise, which a Z-Bus CPU never produces) keeps the command write.
// Confirmed on MLAB in the Quartus fit (unit.map.rpt altdpram x4).
//
// Harness contract (tb/k8010_mmu/mmu_access.h peeks/pokes these by
// hierarchical name; keep the names or update mmu_access.h in the same change):
//   mode_reg sar dsc viol_type viol_sn viol_off isn ioffset
//   bcsr trap_pending viol_captured addr_latched latched_st ack_pending
//   desc_bh[64] desc_bl[64] desc_lm[64] desc_at[64] desc_cpui desc_dmai

module z8010_mmu (
  input  logic        clk,        // board master clock; every flop runs on it
  input  logic        clk_in,     // CLK pin as its rising-edge pulse (one master clock)
  input  logic        reset_n,    // /RESET, synchronised to clk by the board

  input  logic [7:0]  ad,         // AD15..AD8 (the chip has no AD7..AD0)
  input  logic [6:0]  sn,         // SN6..SN0
  input  logic [3:0]  st,         // ST3..ST0
  input  logic        as_n,
  input  logic        ds_n,
  input  logic        r_w,        // 1 = read
  input  logic        n_s,        // 1 = normal mode
  input  logic        cs_n,       // chip select for command (special I/O) access
  input  logic        dmasync,    // DMA segment number valid (active high)

  // PA and Data as value+drive pairs, no tri-state
  output logic [15:0] pa,         // A23..A8
  output logic        pa_drive,
  output logic        segt_n,     // open drain, resolved level
  output logic        sup_n,      // open drain, resolved level
  output logic [7:0]  data,       // AD15..AD8, driven during command reads / SEGT ack
  output logic [7:0]  data_drive  // per-line drive of AD15:8 (bit n = AD line 8+n)
);

  // ---- register inventory --------------------------------------------------
  // Descriptor RAMs (attribute 7=REF 6=CHG 5=DIRW 4=DMAI 3=EXC 2=CPUI 1=SYS
  // 0=RD; desc_at holds {REF, CHG, DIRW, EXC, SYS, RD}).
  (* ramstyle = "MLAB, no_rw_check" *) logic [7:0] desc_bh [64];   // base high
  (* ramstyle = "MLAB, no_rw_check" *) logic [7:0] desc_bl [64];   // base low
  (* ramstyle = "MLAB, no_rw_check" *) logic [7:0] desc_lm [64];   // limit
  (* ramstyle = "MLAB, no_rw_check" *) logic [5:0] desc_at [64];   // attribute less CPUI, DMAI
  // Justification: (reg-a) CPU-Inhibit / DMA-Inhibit, set in all 64 by one command.
  logic [63:0] desc_cpui;
  logic [63:0] desc_dmai;
  logic [7:0]  mode_reg;          // 7=MSEN 6=TRNS 5=URS 4=MST 3=NMS 2:0=ID
  logic [5:0]  sar;
  logic [1:0]  dsc;
  logic [7:0]  viol_type;         // 7=FATL 6=SWW 5=PWW 4=EXCV 3=CPUIV 2=SLV 1=SYSV 0=RDV
  logic [6:0]  viol_sn;
  logic [7:0]  viol_off;          // offset AD15..AD8 of the violating access
  logic [6:0]  isn;
  logic [7:0]  ioffset;
  logic [7:0]  bcsr;
  logic        trap_pending;
  logic        viol_captured;
  logic        addr_latched;      // an /AS cycle is open: /AS fell, its /DS has not risen
  logic        ack_pending;       // our trap is the one being acknowledged (identifier phase)
  logic [1:0]  ack_wait;          // CLK rises left before the acknowledge releases /SEGT; 0 = none
  logic        sup_held;          // SUP for this cycle, released at the /DS rise
  logic        sup_instr_hold;    // SUP every memory cycle until the next first-word fetch

  // ---- strobes, seen on the master clock --------------------------------------
  // Justification: (reg-a) /AS and /DS were Low at the last master clock.
  logic        as_low_q;
  logic        ds_low_q;
  logic as_fall;
  logic as_rise;
  logic ds_rise;
  assign as_fall = ~as_low_q & ~as_n;
  assign as_rise = as_low_q & as_n;
  assign ds_rise = ds_low_q & ds_n;

  // These have no reset: each is loaded (while /AS is Low, on a CLK rise, or
  // when an address is driven) before anything reads it.
  // ---- the /AS latch: follows the pins while /AS is Low, holds after its rise --
  logic [7:0]  latched_ad;
  logic [3:0]  latched_st;
  logic        latched_rw;
  logic        latched_ns;
  logic        latched_cs_n;
  // Justification: (reg-a) SN as of the last CLK rise.
  logic [6:0]  sn_clk;
  logic [15:0] pa_q;
  logic        pa_drive_q;

  // DMA: DMASYNC rising after two or more Low samples presents a DMA address.
  // The DMA cycle holds off the /AS latch until its /DS rise, a DMASYNC-Low
  // sample with /AS High, or two more DMASYNC-High samples.
  logic [1:0]  dma_low;
  logic        dma_active;
  logic        dma_high;
  logic dma_go;
  logic dma_blk;
  assign dma_go  = clk_in & dmasync & dma_low[1];
  assign dma_blk = (dma_active & ~ds_rise) | dma_go;

  // A DMA address is translated in the sample it arrives, straight off the
  // pins; while /AS is Low the pins flow through the open latch, and SN
  // through its CLK-rise register.
  logic       as_open;
  logic       x_pins;
  logic [6:0] x_sn;
  logic [7:0] x_ad;
  logic [3:0] x_st;
  logic       x_rw;
  logic       x_ns;
  assign as_open = ~as_n & ~dma_blk;
  assign x_pins  = dma_go | as_open;
  assign x_sn    = (dma_go | (as_open & clk_in)) ? sn : sn_clk;
  assign x_ad    = x_pins ? ad   : latched_ad;
  assign x_st    = x_pins ? st   : latched_st;
  assign x_rw    = x_pins ? r_w  : latched_rw;
  assign x_ns    = x_pins ? n_s  : latched_ns;

  // ---- translate: one lookup, one adder, one comparator tree ------------------
  // Translation and command access never overlap, so they share one lookup.
  logic [5:0]  seg;
  logic [5:0]  d_idx;
  logic [5:0]  r_at;
  logic [15:0] t_base;
  logic [7:0]  t_lim;
  logic [7:0]  t_attr;
  logic [7:0]  page;
  logic        if1;
  logic        fetch;
  assign seg    = x_sn[5:0];
  assign d_idx  = (x_st == 4'h3) ? sar : seg;
  assign r_at   = desc_at[d_idx];
  assign t_base = {desc_bh[d_idx], desc_bl[d_idx]};
  assign t_lim  = desc_lm[d_idx];
  assign t_attr = {r_at[5:3], desc_dmai[d_idx], r_at[2], desc_cpui[d_idx], r_at[1:0]};
  assign page   = x_ad;
  assign if1    = (latched_st == 4'hD);   // first-word fetch
  assign fetch  = (latched_st == 4'hC) | if1;

  logic mem_cycle;
  logic responds;
  logic translating;
  assign mem_cycle   = (x_st >= 4'h8) & (x_st <= 4'hD);
  assign responds    = mode_reg[7] & (x_sn[6] == mode_reg[5]) & mem_cycle
                     & (~mode_reg[4] | (x_ns == mode_reg[3]));
  assign translating = mode_reg[6];

  // Stack segments grow down: Limit is the lowest valid page.
  logic slv;
  logic viol;
  assign slv  = t_attr[5] ? (page < t_lim) : (page > t_lim);
  assign viol = t_attr[2] | slv | (t_attr[0] & ~latched_rw) | (t_attr[1] & latched_ns)
              | (t_attr[3] & ~fetch);
  // The first-word fetch before a trap acknowledge is ignored: no checks,
  // no REF/CHG. Word fetches of the violating instruction are still checked.
  logic checked;
  assign checked = ~(trap_pending & if1);

  // A7..A0 bypass the chip: the base's low byte is zero, so no carry.
  logic [15:0] phys;
  logic [15:0] pass;
  logic [15:0] x_pa;
  assign phys = t_base + {8'h00, x_ad};
  assign pass = {1'b0, x_sn, x_ad};
  assign x_pa = translating ? phys : pass;

  logic as_cyc;
  logic drive_pa;
  logic drive_low;
  logic ack_start;
  assign as_cyc    = as_rise & addr_latched & ~dma_blk;
  assign drive_pa  = as_cyc & responds;
  assign drive_low = as_open & responds;
  assign ack_start = as_cyc & (latched_st == 4'h4) & mode_reg[7];
  // Trap acknowledge identifier phase: every enabled MMU drives its own line.
  logic       id_now;
  logic [7:0] id_line;
  assign id_now  = addr_latched & (latched_st == 4'h4) & ~ds_n & mode_reg[7];
  assign id_line = 8'h01 << mode_reg[2:0];
  // A memory cycle after a violation, before the next first-word fetch.
  logic sup_rep;
  assign sup_rep = as_cyc & sup_instr_hold & ~if1
                 & (latched_st >= 4'h8) & (latched_st <= 4'hD);
  localparam logic [1:0] ACK_RELEASE_RISE = 2'd3;
  logic [1:0] ack_cnt;
  assign ack_cnt = ack_start ? ACK_RELEASE_RISE : ack_wait;

  // DMA checks: DMA Inhibit in place of CPU Inhibit, and DMA never fetches.
  logic dma_drive;
  logic dma_viol;
  assign dma_drive = dma_go & responds;
  assign dma_viol  = t_attr[4] | slv | (t_attr[0] & ~x_rw) | (t_attr[1] & x_ns) | t_attr[3];

  // ---- violation: first one wins the capture, later ones OR into VTR -----------
  logic       wr;
  logic       pww;
  logic       trap;
  logic [7:0] vbit;
  logic       stack;
  assign wr    = ~latched_rw;
  assign pww   = ~viol & t_attr[5] & wr & (page == t_lim);
  assign trap  = drive_pa & translating & checked & (viol | pww);
  assign vbit  = t_attr[2]               ? 8'h08 :
                 slv                     ? 8'h04 :
                 (t_attr[0] & wr)        ? 8'h01 :
                 (t_attr[1] & latched_ns) ? 8'h02 :
                 t_attr[3] & ~fetch      ? 8'h10 : 8'h20;
  assign stack = (latched_st == 4'h9) | (latched_st == 4'hB);
  // FATL: a violation (or a normal-mode warning) with VTR already holding one.
  logic fatl;
  assign fatl = viol_captured & (viol | latched_ns);
  // SWW: a system stack push into the warning page while a flag is set.
  logic sww;
  assign sww = ~viol & ~latched_ns & stack & (|viol_type[5:0]) & ~fatl;
  // Once FATL or SWW is set no further trap requests are made.
  logic       req;
  logic [7:0] vt_next;
  assign req     = ~viol_type[7] & ~viol_type[6] & ~fatl;
  assign vt_next = (viol_captured ? (viol_type | vbit) : vbit) | {fatl, sww, 6'b0};

  // ---- command port: opcode and /CS at the /AS rise, data while /DS is Low -----
  logic [7:0] cmd;
  logic       cmd_start;
  assign cmd       = latched_ad;
  assign cmd_start = as_cyc & (latched_st == 4'h3) & ~latched_cs_n;
  logic      cmd_pending;
  logic       cmd_exec;
  logic [7:0] din;
  assign cmd_exec = (cmd_pending | cmd_start) & ~ds_n;
  assign din      = ad;

  // Descriptor commands 08-0F: bit 2 = increment SAR at the end of the field,
  // bits 1:0 = base / limit / attribute / whole descriptor.
  logic is_desc;
  assign is_desc = (cmd[7:3] == 5'b00001);
  logic [1:0] fld;        // 0 base high, 1 base low, 2 limit, 3 attribute
  logic [1:0] dsc_next;
  logic       last_byte;
  always_comb begin
    fld = 2'd0; dsc_next = dsc; last_byte = 1'b1;
    unique case (cmd[1:0])
      2'd0: begin fld = (dsc == 2'd0) ? 2'd0 : 2'd1; dsc_next = (dsc == 2'd0) ? 2'd1 : 2'd0;
                  last_byte = (dsc != 2'd0); end
      2'd1: begin fld = 2'd2; dsc_next = dsc;         last_byte = 1'b1; end
      2'd2: begin fld = 2'd3; dsc_next = dsc;         last_byte = 1'b1; end
      2'd3: begin fld = dsc;  dsc_next = dsc + 2'd1;  last_byte = (dsc == 2'd3); end
      default: ;
    endcase
  end

  logic [7:0] rd_byte;
  logic       rd_ok;
  always_comb begin
    rd_ok = 1'b1;
    rd_byte = 8'h00;
    unique case (fld)
      2'd0: rd_byte = t_base[15:8];
      2'd1: rd_byte = t_base[7:0];
      2'd2: rd_byte = t_lim;
      2'd3: rd_byte = t_attr;
      default: ;
    endcase
    if (!is_desc) begin
      case (cmd)
        8'h00:   rd_byte = mode_reg;
        8'h01:   rd_byte = {2'b00, sar};
        8'h20:   rd_byte = {6'b0, dsc};
        8'h02:   rd_byte = viol_type;
        8'h03:   rd_byte = {1'b0, viol_sn};
        8'h04:   rd_byte = viol_off;
        8'h05:   rd_byte = bcsr;
        8'h06:   rd_byte = {1'b0, isn};
        8'h07:   rd_byte = ioffset;
        default: begin rd_byte = 8'h00; rd_ok = 1'b0; end
      endcase
    end
  end

  // ---- descriptor RAM write port --------------------------------------------
  // A command write puts one byte in its field at SAR. A clean access sets
  // REF (and CHG on a write) in the looked-up descriptor (p.566), here a
  // read-modify-write of desc_at through the asynchronous read; d_idx is
  // that descriptor (seg, the DMA pins' SN in a DMA sample).
  logic       cmd_wr;
  logic       ref_cpu;
  logic       ref_dma;
  logic       ref_wr;
  logic       ref_chg;
  logic [5:0] d_wa;
  assign cmd_wr  = reset_n & cmd_exec & ~latched_rw & is_desc;
  assign ref_cpu = drive_pa & translating & checked & ~viol;
  assign ref_dma = dma_drive & translating & ~dma_viol;
  assign ref_wr  = reset_n & ~cmd_wr & (ref_cpu | ref_dma);
  assign ref_chg = ref_dma ? ~r_w : ~latched_rw;
  assign d_wa    = cmd_wr ? sar : d_idx;
  logic [3:0] f_we;       // base high, base low, limit, attribute
  logic [7:0] w_byte;
  logic [5:0] w_at;
  always_comb begin
    f_we   = 4'b0000;
    w_byte = din;
    w_at   = {din[7:5], din[3], din[1:0]};
    if (cmd_wr) begin
      unique case (fld)
        2'd0: f_we = 4'b1000;
        2'd1: f_we = 4'b0100;
        2'd2: f_we = 4'b0010;
        2'd3: f_we = 4'b0001;
        default: ;
      endcase
    end else if (ref_wr) begin
      f_we = 4'b0001;
      w_at = {1'b1, r_at[4] | ref_chg, r_at[3:0]};
    end
  end
  always_ff @(posedge clk) begin
    if (f_we[3]) desc_bh[d_wa] <= w_byte;
    if (f_we[2]) desc_bl[d_wa] <= w_byte;
    if (f_we[1]) desc_lm[d_wa] <= w_byte;
    if (f_we[0]) desc_at[d_wa] <= w_at;
  end

  logic [7:0]  data_q;
  logic [7:0]  data_drive_q;

  // ---- one state block: /RESET first, then the strobe and CLK events -----------
  always_ff @(posedge clk) begin
    if (!reset_n) begin
      sar           <= 6'd0;
      dsc           <= 2'd0;
      viol_type     <= 8'h00;
      viol_sn       <= 7'd0;
      viol_off      <= 8'h00;
      isn           <= 7'd0;
      ioffset       <= 8'h00;
      bcsr          <= 8'h00;
      trap_pending  <= 1'b0;
      viol_captured <= 1'b0;
      addr_latched  <= 1'b0;
      latched_st    <= 4'd0;
      ack_pending   <= 1'b0;
      ack_wait      <= 2'd0;
      sup_held      <= 1'b0;
      sup_instr_hold <= 1'b0;
      mode_reg      <= {~cs_n, 7'b0};
      as_low_q      <= 1'b0;
      ds_low_q      <= 1'b0;
      pa_drive_q    <= 1'b0;
      cmd_pending   <= 1'b0;
      data_q        <= 8'h00;
      data_drive_q  <= 8'h00;
      dma_low       <= 2'd0;
      dma_active    <= 1'b0;
      dma_high      <= 1'b0;
    end else begin
      as_low_q <= ~as_n;
      ds_low_q <= ~ds_n;
      if (clk_in)
        sn_clk <= sn;

      // End of cycle first: a new cycle may start in the same sample.
      // A command that never saw its data phase is dropped.
      if (ds_rise) begin
        pa_drive_q   <= 1'b0;
        data_drive_q <= 8'h00;
        cmd_pending  <= 1'b0;
        ack_pending  <= 1'b0;
        ack_wait     <= 2'd0;
        if (ack_wait != 2'd0)
          trap_pending <= 1'b0;
        sup_held     <= 1'b0;
        dma_active   <= 1'b0;
      end

      if (clk_in) begin
        dma_low  <= dmasync ? 2'd0 : (dma_low[1] ? 2'd2 : dma_low + 2'd1);
        dma_high <= dmasync & dma_active & ~dma_go;
        // The DMA cycle ends, and its suppress with it (p.565: "asserted
        // during that cycle only").
        if (dmasync && dma_active && dma_high) begin
          dma_active <= 1'b0;
          sup_held   <= 1'b0;
        end
        // DMASYNC Low with /AS High: the next /AS is a new cycle. PA and
        // /SUP hold to /DS.
        if (!dmasync && as_n)
          dma_active <= 1'b0;
      end
      if (dma_go) begin
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
          pa_q       <= x_pa;
          pa_drive_q <= 1'b1;
          if (translating && dma_viol)
            sup_held <= 1'b1;
        end
      end

      // Trap acknowledge identifier: every enabled MMU drives its own line.
      if (id_now) begin
        data_q       <= ack_pending ? id_line : 8'h00;
        data_drive_q <= id_line;
      end

      // The previous cycle's PA drive ends at the /AS fall.
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
            data_q       <= rd_byte;
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
              trap_pending  <= 1'b0;
              sup_held      <= 1'b0;
              sup_instr_hold <= 1'b0;
            end
            8'h13: viol_type[6] <= 1'b0;
            8'h14: viol_type[7] <= 1'b0;
            8'h15: desc_cpui <= '1;
            8'h16: desc_dmai <= '1;
            default: ;
          endcase
          if (is_desc && fld == 2'd3) begin
            desc_cpui[sar] <= din[2];
            desc_dmai[sar] <= din[4];
          end
        end
        if (is_desc) begin
          dsc <= dsc_next;
          if (cmd[2] && last_byte)
            sar <= sar + 6'd1;
        end
      end

      // The /AS latch is open while /AS is Low.
      if (!as_n && !dma_blk) begin
        latched_ad   <= ad;
        latched_st   <= st;
        latched_rw   <= r_w;
        latched_ns   <= n_s;
        latched_cs_n <= cs_n;
      end
      if (as_fall && !dma_blk)
        addr_latched <= 1'b1;
      else if (ds_rise)
        addr_latched <= 1'b0;

      // A first-word fetch starts the next instruction and ends the hold.
      if (as_cyc && if1) begin
        sup_instr_hold <= 1'b0;
        if (!viol_captured) begin
          isn     <= sn_clk;
          ioffset <= latched_ad;
        end
      end
      if (sup_rep)
        sup_held <= 1'b1;

      if (drive_pa) begin
        pa_q       <= x_pa;
        pa_drive_q <= 1'b1;
      end

      // Trap acknowledge: /SEGT is released at the third CLK rise from the
      // acknowledge's /AS rise (INFERRED, ACK_RELEASE_RISE; the T2 rise is
      // the first), a /DS rise that comes first releases it there.
      if (ack_start) begin
        ack_pending <= trap_pending;
        ack_wait    <= ACK_RELEASE_RISE;
      end
      if (ack_cnt != 2'd0 && clk_in) begin
        ack_wait <= ack_cnt - 2'd1;
        if (ack_cnt == 2'd1)
          trap_pending <= 1'b0;
      end

      if (trap) begin
        viol_type <= vt_next;
        if (!viol_captured) begin
          viol_sn       <= sn_clk;
          viol_off      <= latched_ad;
          bcsr          <= {2'b00, latched_ns, latched_rw, latched_st};
          viol_captured <= 1'b1;
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

  // ---- pins: each output follows its strobe edge in the same master clock
  // (PA the /AS fall and rise, /SEGT, /SUP the /AS rise; command data and the identifier the /DS
  // fall), then holds from its register; all are released while /RESET is Low.
  logic sup_now;
  logic segt_now;
  logic rd_now;
  assign sup_now  = (trap & viol) | sup_rep;
  assign segt_now = trap & req;
  assign rd_now   = cmd_exec & latched_rw & rd_ok;
  always_comb begin
    pa         = (drive_pa | drive_low) ? x_pa : pa_q;
    pa_drive   = ((pa_drive_q & ~as_open) | drive_pa | drive_low) & reset_n;
    segt_n     = ~((trap_pending | segt_now) & reset_n);
    sup_n      = ~((sup_held | sup_now) & reset_n);
    data       = rd_now ? rd_byte : id_now ? (ack_pending ? id_line : 8'h00) : data_q;
    data_drive = (data_drive_q | {8{rd_now}} | (id_now ? id_line : 8'h00)) & {8{reset_n}};
  end

endmodule

`default_nettype wire
