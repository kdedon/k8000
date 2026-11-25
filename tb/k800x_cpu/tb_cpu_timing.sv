// tb_cpu_timing -- Z-Bus TIMING conformance for the CPU, straight from the
// Zilog spec (no vectors involved).
//
// Two layers:
//   1. Directed checks the CPU must satisfy with no program at all:
//      the reset pin state (Product Spec "Reset" + Fig 19, 1988 DB p.157;
//      Ref Manual sec 7.4) and the reset PSA fetch sequence.
//   2. A behavioural memory + I/O slave runs a short program that exercises
//      every bus-cycle class (instruction fetch, memory word read/write,
//      memory BYTE write, standard I/O in/out, /WAIT-stretched I/O, HALT),
//      with z8000_bus_monitor watching every clock.  The monitor holds the
//      Figs 12/13/14/17/18/19 rules; anything it flags is a spec violation
//      with the citation printed.
//
// SEGMENTED=0 runs a Z8002, SEGMENTED=1 a Z8001 in segmented mode with
// pointers in register pairs.  Run:
//   make test-cpu-timing        (or obj_dir/tb_cpu_timing/tb_cpu_timing)

module tb_cpu_timing
  import z8000_zbus_pkg::*;
#(parameter bit SEGMENTED = 1'b0);
  // ---- clock / reset ---------------------------------------------------------
  logic clk = 1'b0;
  always #5 clk = ~clk;
  // Master clock: 5 per CLK, off CLK's edges.
  logic mclk = 1'b0;
  initial begin #0.5; forever #1 mclk = ~mclk; end
  // The board's CLK edge pulses: High for the master clock in which CLK is
  // first seen High, or Low.
  logic clk_pq = 1'b0;
  always @(posedge mclk) clk_pq <= clk;
  wire  clk_rise = clk & ~clk_pq;
  wire  clk_fall = ~clk & clk_pq;

  logic reset_n = 1'b0;

  // ---- CPU pins ---------------------------------------------------------------
  logic [15:0] ad_in;
  logic        stop_n  = 1'b1;
  logic        wait_n;
  logic        busreq_n= 1'b1;
  logic        nmi_n   = 1'b1;
  logic        nvi_n   = 1'b1;
  logic        vi_n    = 1'b1;
  logic        segt_n  = 1'b1;
  logic        abort_n = 1'b1;
  logic        mi_n    = 1'b1;

  logic [15:0] ad_out;
  logic        ad_drive, bus_drive;
  logic [6:0]  sn;
  logic        as_n, ds_n, mreq_n, r_w, b_w, n_s;
  logic [3:0]  st;
  logic        busack_n, mo_n;

  z8000_cpu #(.SEGMENTED(SEGMENTED), .VMPU(1'b0)) dut (
    .clk(mclk), .clk_rise(clk_rise), .clk_fall(clk_fall), .reset_n(reset_n),
    .ad_in(ad_in), .stop_n(stop_n), .wait_n(wait_n), .busreq_n(busreq_n),
    .nmi_n(nmi_n), .nvi_n(nvi_n), .vi_n(vi_n), .segt_n(segt_n),
    .abort_n(abort_n), .mi_n(mi_n),
    .ad_out(ad_out), .ad_drive(ad_drive), .bus_drive(bus_drive), .sn(sn),
    .as_n(as_n), .ds_n(ds_n), .mreq_n(mreq_n),
    .r_w(r_w), .b_w(b_w), .n_s(n_s), .st(st),
    .busack_n(busack_n), .mo_n(mo_n)
  );

  logic mon_en = 1'b0;
  z8000_bus_monitor #(.SEGMENTED(SEGMENTED)) mon (
    .clk(clk), .enable(mon_en),
    .ad_out(ad_out), .ad_drive(ad_drive), .sn(sn),
    .as_n(as_n), .ds_n(ds_n), .mreq_n(mreq_n),
    .r_w(r_w), .b_w(b_w), .n_s(n_s), .st(st),
    .busack_n(busack_n), .mo_n(mo_n), .wait_n(wait_n)
  );

  // ---- behavioural memory + I/O slave -----------------------------------------
  // 64 KiB of byte-addressed memory as 32768 words; the CPU's AD carries a byte
  // address, A0 selects the byte lane on byte transfers (Ref Manual 9.4.2:
  // even address -> AD15:8, odd -> AD7:0).
  logic [15:0] mem [0:32767];
  localparam logic [6:0] CODE_SEG = 7'h05;
  localparam logic [6:0] DATA_SEG = 7'h12;

  logic [15:0] lat_addr;
  logic [3:0]  lat_st;
  logic        lat_rw, lat_bw;
  logic        lat_valid = 1'b0;
  logic        as_q = 1'b1, ds_q = 1'b1;

  // Observation counters for the directed checks.
  int unsigned n_psa_read, n_fetch, n_mem_rd, n_mem_wr, n_bytewr, n_io_rd, n_io_wr;
  int unsigned n_code_seg, n_data_seg;
  logic [15:0] io_last_write, io_last_port;
  logic [15:0] wr_seen_addr, wr_seen_data;

  // I/O slave: /WAIT Low for six half clocks from the one after /AS (T2,
  // TWA, first Tw). Fig 9-5: /DS falls on T2's fall regardless, /WAIT is
  // sampled mid-TWA and each Tw, so the CPU adds two Tw: T1 T2 TWA TW TW T3,
  // /DS Low from T2's fall through T3's.
  int io_wait_left;
  logic io_track = 1'b0;
  int   io_off, io_fall;
  int unsigned n_io_shape, n_io_shape_bad;

  // The slave is a board chip: it acts at the master clocks that see a CLK
  // edge, the same ones the CPU acts at.
  logic clk_seen = 1'b0;
  always @(posedge mclk) clk_seen <= clk;
  always @(posedge mclk) if (clk != clk_seen) begin
    if (!ds_q && ds_n) lat_valid <= 1'b0;
    // Address latch at the /AS fall (the external latch point is the /AS rise;
    // the address is stable for the whole of T1 either way).
    if (as_q && !as_n && ad_drive) begin
      lat_addr  <= ad_out;
      lat_st    <= st;
      lat_rw    <= r_w;
      lat_bw    <= b_w;
      lat_valid <= 1'b1;
      if (st == ST_IO || st == ST_SPECIAL_IO) begin
        io_wait_left <= 6;
        io_track     <= 1'b1;
        io_off       <= 1;
        io_fall      <= -1;
      end
      if (st == ST_INSTR_FETCH_FIRST) n_fetch <= n_fetch + 1;
      if (st == ST_INSTR_FETCH_FIRST && sn == CODE_SEG) n_code_seg <= n_code_seg + 1;
      if (st == ST_DATA_MEM && sn == DATA_SEG) n_data_seg <= n_data_seg + 1;
      if (st[3] && ad_out < 16'h0008) n_psa_read <= n_psa_read + 1;
    end
    // Write data is captured at the /DS fall (Fig 12: data is valid on AD from
    // T2 and held through T3).
    if (ds_q && !ds_n && lat_valid && !lat_rw) begin
      if (lat_st[3]) begin
        if (lat_bw) begin
          n_bytewr <= n_bytewr + 1;
          if (lat_addr[0]) mem[lat_addr[15:1]][7:0]  <= ad_out[7:0];
          else             mem[lat_addr[15:1]][15:8] <= ad_out[15:8];
        end else begin
          n_mem_wr <= n_mem_wr + 1;
          mem[lat_addr[15:1]] <= ad_out;
        end
        wr_seen_addr <= lat_addr;
        wr_seen_data <= ad_out;
      end else if (lat_st == ST_IO || lat_st == ST_SPECIAL_IO) begin
        n_io_wr       <= n_io_wr + 1;
        io_last_port  <= lat_addr;
        io_last_write <= ad_out;
      end
    end
    if (ds_q && !ds_n && lat_valid && lat_rw && !lat_st[3] &&
        (lat_st == ST_IO || lat_st == ST_SPECIAL_IO))
      n_io_rd <= n_io_rd + 1;
    if (ds_q && !ds_n && lat_valid && lat_rw && lat_st[3] &&
        lat_st != ST_INSTR_FETCH_FIRST && lat_st != ST_PROG_SPACE)
      n_mem_rd <= n_mem_rd + 1;

    if (io_wait_left > 0 && !wait_n) io_wait_left <= io_wait_left - 1;

    // I/O /DS shape, in half clocks from the /AS fall (T1 = 0).
    if (io_track && !(as_q && !as_n)) io_off <= io_off + 1;
    if (io_track) begin
      if (ds_q && !ds_n) io_fall <= io_off;
      if (!ds_q && ds_n) begin
        // a back-to-back I/O /AS on this edge re-arms below
        io_track   <= as_q && !as_n && ad_drive && (st == ST_IO || st == ST_SPECIAL_IO);
        n_io_shape <= n_io_shape + 1;
        if (io_fall != 3 || io_off != 11) begin
          n_io_shape_bad <= n_io_shape_bad + 1;
          $display("  I/O /DS fell at %0d, rose at %0d (want 3, 11)", io_fall, io_off);
        end
      end
    end

    as_q <= as_n;
    ds_q <= ds_n;
  end

  // Read data: driven whenever the latched cycle is a read.  Memory returns the
  // word; I/O returns a fixed pattern.  Open bus is 0xFFFF.
  always_comb begin
    if (lat_valid && lat_rw) begin
      if (lat_st[3])                                    ad_in = mem[lat_addr[15:1]];
      else if (lat_st == ST_IO || lat_st == ST_SPECIAL_IO) ad_in = 16'h00A5;
      else                                              ad_in = 16'hFFFF;
    end else begin
      ad_in = 16'hFFFF;
    end
  end

  // /WAIT from the slow I/O slave.
  always_comb wait_n = !(io_wait_left > 0 && lat_valid &&
                         (lat_st == ST_IO || lat_st == ST_SPECIAL_IO));

  // ---- pass/fail bookkeeping ---------------------------------------------------
  int unsigned checks, fails;
  task automatic ck(input bit ok, input string name, input string cite, input string detail);
    checks = checks + 1;
    if (ok) begin
      $display("  PASS  %s", name);
    end else begin
      fails = fails + 1;
      $display("  FAIL  %s", name);
      $display("          %s", detail);
      $display("          spec: %s", cite);
    end
  endtask

  // ---- the program -------------------------------------------------------------
  // Z8002 (non-segmented).  PSA at 0: word 1 = FCW, word 2 = PC.
  localparam logic [15:0] PROG = 16'h0100;
  localparam logic [15:0] DATA = 16'h0200;

  task automatic load_program();
    int i;
    for (i = 0; i < 32768; i++) mem[i] = 16'h0000;
    // Reset PSA (Ref Manual 7.4): the Z8002 fetches FCW then PC, the Z8001
    // FCW, PC segment, PC offset. The Z8001 runs segmented: it jumps to
    // segment CODE_SEG, its pointer in RR4 = segment DATA_SEG, offset DATA.
    // The slave decodes the offset only.
    if (SEGMENTED) begin
      mem[16'h0002 >> 1] = 16'hC000;  // FCW: segmented, system mode, ints off
      mem[16'h0004 >> 1] = 16'h0000;  // PC segment
      mem[16'h0006 >> 1] = PROG;      // PC offset
      // 0100  5E08 8500 0106   JP   <<05>>0106
      mem[(PROG + 16'h0000) >> 1] = 16'h5E08;
      mem[(PROG + 16'h0002) >> 1] = {1'b1, CODE_SEG, 8'h00};
      mem[(PROG + 16'h0004) >> 1] = PROG + 16'h0006;
      // 0106  1404 1200 0200   LDL  RR4,#<<12>>DATA
      mem[(PROG + 16'h0006) >> 1] = 16'h1404;
      mem[(PROG + 16'h0008) >> 1] = {1'b0, DATA_SEG, 8'h00};
      mem[(PROG + 16'h000A) >> 1] = DATA;
      // 010C  2102 5A5A   LD   R2,#0x5A5A
      mem[(PROG + 16'h000C) >> 1] = 16'h2102;
      mem[(PROG + 16'h000E) >> 1] = 16'h5A5A;
      // 0110  2F42 2143 2E4A   LD @RR4,R2; LD R3,@RR4; LDB @RR4,RL2
      mem[(PROG + 16'h0010) >> 1] = 16'h2F42;
      mem[(PROG + 16'h0012) >> 1] = 16'h2143;
      mem[(PROG + 16'h0014) >> 1] = 16'h2E4A;
      // 0116  OUTB, INB, HALT as below
      mem[(PROG + 16'h0016) >> 1] = 16'h3AA6;
      mem[(PROG + 16'h0018) >> 1] = 16'h0010;
      mem[(PROG + 16'h001A) >> 1] = 16'h3AB4;
      mem[(PROG + 16'h001C) >> 1] = 16'h0010;
      mem[(PROG + 16'h001E) >> 1] = 16'h7A00;
      return;
    end
    mem[16'h0002 >> 1] = 16'hC000;    // FCW: segmented=0, system mode, ints off
    mem[16'h0004 >> 1] = PROG;        // PC
    // 0100  2101 0200   LD   R1,#DATA          (immediate: 2 extra fetch words)
    mem[(PROG + 16'h0000) >> 1] = 16'h2101;
    mem[(PROG + 16'h0002) >> 1] = DATA;
    // 0104  2102 5A5A   LD   R2,#0x5A5A
    mem[(PROG + 16'h0004) >> 1] = 16'h2102;
    mem[(PROG + 16'h0006) >> 1] = 16'h5A5A;
    // 0108  2F12        LD   @R1,R2            memory WORD write
    mem[(PROG + 16'h0008) >> 1] = 16'h2F12;
    // 010A  2113        LD   R3,@R1            memory WORD read
    mem[(PROG + 16'h000A) >> 1] = 16'h2113;
    // 010C  2E1A        LDB  @R1,RL2           memory BYTE write (lane duplication)
    mem[(PROG + 16'h000C) >> 1] = 16'h2E1A;
    // 010E  3AA6 0010   OUTB 0x0010,RL2        standard I/O write (+2 /WAIT clocks)
    mem[(PROG + 16'h000E) >> 1] = 16'h3AA6;
    mem[(PROG + 16'h0010) >> 1] = 16'h0010;
    // 0112  3AB4 0010   INB  RL3,0x0010        standard I/O read
    mem[(PROG + 16'h0012) >> 1] = 16'h3AB4;
    mem[(PROG + 16'h0014) >> 1] = 16'h0010;
    // 0116  7A00        HALT
    mem[(PROG + 16'h0016) >> 1] = 16'h7A00;
  endtask

  // ---- run ----------------------------------------------------------------------
  int unsigned i;
  logic reset_st_ok, reset_strobe_ok, reset_sn_ok, reset_addr_ok;
  logic rel_p_ok, rel_e_ok, rel_hold_ok, rel_t1_ok, rel_re_ok;
  string rel_hold_msg;
  logic [3:0] gnt_st;
  logic [6:0] gnt_sn;
  logic gnt_rw, gnt_bw, gnt_ns;

  initial begin
    checks = 0; fails = 0;
    n_psa_read = 0; n_fetch = 0; n_mem_rd = 0; n_mem_wr = 0;
    n_bytewr = 0; n_io_rd = 0; n_io_wr = 0; n_io_shape = 0; n_io_shape_bad = 0;
    n_code_seg = 0; n_data_seg = 0;
    io_wait_left = 0;
    lat_addr = 16'h0; lat_st = 4'h0; lat_rw = 1'b1; lat_bw = 1'b0;
    wr_seen_addr = 16'h0; wr_seen_data = 16'h0;
    io_last_port = 16'h0; io_last_write = 16'h0;
    load_program();

    $display("tb_cpu_timing -- Z-Bus spec timing conformance (%s variant)", SEGMENTED ? "Z8001" : "Z8002");
    $display("");
    $display("[1] reset pin state");

    // ---- reset held Low for well over the five clocks the spec allows -------
    reset_n = 1'b0;
    reset_st_ok = 1'b1; reset_strobe_ok = 1'b1; reset_sn_ok = 1'b1; reset_addr_ok = 1'b1;
    for (i = 0; i < 12; i++) begin
      @(posedge clk);
      #1;
      if (i >= 5) begin
        if (st !== 4'b1111)                     reset_st_ok = 1'b0;
        if (!(as_n && ds_n && mreq_n && busack_n && mo_n)) reset_strobe_ok = 1'b0;
        if (sn !== 7'h00)                       reset_sn_ok = 1'b0;
        if (ad_drive !== 1'b0)                  reset_addr_ok = 1'b0;
      end
    end
    ck(reset_st_ok, "ST3-ST0 forced High while /RESET is Low",
       "Product Spec Reset (1988 DB p.157, Fig 19) / Ref Manual 7.4: ST0-ST3 are forced High within five clocks of /RESET going Low",
       $sformatf("st=%04b", st));
    ck(reset_strobe_ok, "/AS /DS /MREQ /BUSACK /MO High while /RESET is Low",
       "Product Spec Reset: AS, DS, MREQ, BUSACK and MO are forced High within five clocks",
       $sformatf("as_n=%0b ds_n=%0b mreq_n=%0b busack_n=%0b mo_n=%0b", as_n, ds_n, mreq_n, busack_n, mo_n));
    ck(reset_sn_ok, "SN6-SN0 forced Low while /RESET is Low",
       "Product Spec Reset: SN0-SN6 are forced Low",
       $sformatf("sn=%02h", sn));
    ck(reset_addr_ok, "AD 3-stated while /RESET is Low",
       "Product Spec Reset: AD0-AD15 are 3-stated within five clocks",
       $sformatf("ad_drive=%0b", ad_drive));

    // ---- release reset; the monitor now polices every clock ------------------
    $display("");
    $display("[2] program run with the Z-Bus monitor armed");
    @(posedge clk); #1;
    reset_n = 1'b1;
    mon_en  = 1'b1;

    for (i = 0; i < 4000; i++) @(posedge clk);
    #1;
    mon_en = 1'b0;

    ck(n_psa_read >= (SEGMENTED ? 3 : 2), "reset PSA fetch runs (FCW + PC, the Z8001 PC in two words)",
       "Ref Manual 7.4: after /RESET rises the CPU reads the FCW and the PC from the Program Status Area",
       $sformatf("saw %0d PSA reads below address 0x0008", n_psa_read));
    ck(n_fetch > 0, "instruction fetches issued with ST=1101",
       "Fig 12 / zbus: the first word of every instruction is fetched with status 1101 (IF1)",
       $sformatf("saw %0d IF1 cycles", n_fetch));
    if (SEGMENTED)
      ck(n_code_seg > 0 && n_data_seg >= 3, "fetches and data cycles carry their segments on SN",
         "Product Spec p.150 (1988 DB): SN6-SN0 carry the 7-bit segment number of the address",
         $sformatf("%0d IF1 in segment %02h, %0d data cycles in segment %02h", n_code_seg, CODE_SEG, n_data_seg, DATA_SEG));
    ck(n_mem_wr > 0, "memory word write performed",
       "Fig 12 memory write cycle",
       $sformatf("saw %0d word writes", n_mem_wr));
    ck(n_mem_rd > 0, "memory word read (data) performed",
       "Fig 12 memory read cycle",
       $sformatf("saw %0d data reads", n_mem_rd));
    ck(n_bytewr > 0, "memory byte write performed",
       "Ref Manual 9.4.2: byte transfers use B/W Low and A0 to pick the lane",
       $sformatf("saw %0d byte writes", n_bytewr));
    ck(n_io_wr > 0 && n_io_rd > 0, "standard I/O read and write performed",
       "Fig 13 input/output cycle (one automatic wait)",
       $sformatf("saw %0d I/O writes, %0d I/O reads", n_io_wr, n_io_rd));
    ck(n_io_shape > 0 && n_io_shape_bad == 0, "I/O /DS Low from T2's fall through two Tw and T3",
       "Tech Manual Fig 9-5, AC #42: /DS falls on T2's fall, /WAIT sampled mid-TWA, waits added between TWA and T3",
       $sformatf("%0d of %0d I/O cycles off-shape", n_io_shape_bad, n_io_shape));
    ck(mem[DATA >> 1] == 16'h5A5A || n_mem_wr == 0, "word write landed at the addressed word",
       "Fig 12: the address latched at /AS is the destination of the data strobed at /DS",
       $sformatf("mem[%04h]=%04h, want 5A5A", DATA, mem[DATA >> 1]));

    $display("");
    $display("[3] Z-Bus monitor result");
    ck(mon.errors == 0 && mon.transactions > 0, "no Z-Bus protocol/timing violations",
       "see the per-violation citations printed above (a run with zero transactions proves nothing)",
       $sformatf("%0d violation(s) over %0d transactions", mon.errors, mon.transactions));
    $display("      transactions observed: %0d", mon.transactions);

    // ---- bus request release (Fig 15): /BUSREQ seen High at rise P, /BUSACK
    // High at P+1 = E, the held pins re-driven and AD floating through E and
    // E+1, the next T1 at E+2. The halted CPU runs internal operations, so a
    // cycle is always ready to open.
    $display("");
    $display("[4] bus request release");
    @(negedge clk); busreq_n = 1'b0;
    for (i = 0; i < 40 && busack_n; i++) @(posedge clk);
    repeat (4) @(posedge clk);
    #2;
    gnt_st = st; gnt_rw = r_w; gnt_bw = b_w; gnt_ns = n_s; gnt_sn = sn;
    @(negedge clk); busreq_n = 1'b1;
    @(posedge clk); #2;                       // P
    rel_p_ok = !busack_n;
    @(posedge clk); #2;                       // E
    rel_e_ok = busack_n;
    rel_hold_ok = 1'b1;
    rel_hold_msg = "";
    // E, its fall, E+1, its fall. SN may go out for the next T1 on E+1's fall.
    for (i = 0; i < 4; i++) begin
      if (rel_hold_ok &&
          !(as_n && ds_n && mreq_n && !ad_drive && bus_drive && st == gnt_st && r_w == gnt_rw &&
            b_w == gnt_bw && n_s == gnt_ns && (!SEGMENTED || i == 3 || sn == gnt_sn))) begin
        rel_hold_ok = 1'b0;
        rel_hold_msg = $sformatf("sample %0d: as_n=%0b ds_n=%0b mreq_n=%0b ad_drive=%0b bus_drive=%0b st=%04b r_w=%0b b_w=%0b n_s=%0b sn=%02h (held st=%04b r_w=%0b b_w=%0b n_s=%0b sn=%02h)",
                                 i, as_n, ds_n, mreq_n, ad_drive, bus_drive, st, r_w, b_w, n_s, sn,
                                 gnt_st, gnt_rw, gnt_bw, gnt_ns, gnt_sn);
      end
      if (i[0]) @(posedge clk); else @(negedge clk);
      #2;
    end
    rel_t1_ok = !as_n;                        // E+2
    ck(rel_p_ok && rel_e_ok, "/BUSACK rises one clock after /BUSREQ is seen High",
       "1988 DB p.34 (Fig 15): when BUSREQ is released ... the BUSACK output goes High one clock period later",
       $sformatf("busack_n at P=%0b, at P+1=%0b", !rel_p_ok, rel_e_ok));
    ck(rel_hold_ok, "two clocks of held pins after /BUSACK rises, AD floating",
       "1988 DB Fig 15 / Jan83 TM Fig 9-9: MREQ, DS, ST, B/W, R/W, N/S \"same as previous cycle\" for two clocks; AD 3-stated",
       rel_hold_msg);
    ck(rel_t1_ok, "the next T1 opens two clocks after /BUSACK rises",
       "Jan83 TM 9.6.2: the CPU regains control of the bus two clock cycles after BUSREQ rises; Fig 9-9",
       $sformatf("as_n=%0b at E+2", as_n));

    // /BUSREQ Low again on E's fall: sampled at the T1 at E+2, so the bus is
    // given again only as that cycle's T3 ends (E+5). TM 9.6.2 tells a
    // requester to wait two cycles after releasing /BUSREQ, so this case is
    // outside the manual; the check pins the RTL's choice.
    @(negedge clk); busreq_n = 1'b0;
    for (i = 0; i < 40 && busack_n; i++) begin @(posedge clk); #2; end
    repeat (2) @(posedge clk);
    @(negedge clk); busreq_n = 1'b1;
    for (i = 0; i < 4 && !busack_n; i++) begin @(posedge clk); #2; end   // E
    @(negedge clk); busreq_n = 1'b0;
    @(posedge clk); #2;                       // E+1
    rel_re_ok = busack_n && as_n;
    @(posedge clk); #2;                       // E+2
    rel_re_ok = rel_re_ok && busack_n && !as_n;
    for (i = 0; i < 20 && busack_n; i++) begin @(posedge clk); #2; end
    rel_re_ok = rel_re_ok && !busack_n && i == 3;   // E+5
    @(negedge clk); busreq_n = 1'b1;
    ck(rel_re_ok, "/BUSREQ again in the two clocks: T1 at E+2, the next grant as its T3 ends",
       "1988 DB p.34: BUSREQ is synchronized at the beginning of any machine cycle; Fig 15",
       $sformatf("busack_n=%0b, %0d clocks after E+2 (want Low at 3)", busack_n, i));

    $display("");
    if (fails == 0) $display("RESULT PASS  tb_cpu_timing  %0d checks", checks);
    else            $display("RESULT FAIL  tb_cpu_timing  %0d/%0d checks failed", fails, checks);
    $finish;
  end
endmodule
