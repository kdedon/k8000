// z8036_cio -- Zilog Z8036 Z-CIO counter/timer and parallel I/O unit.
//
// The chip's pins, plus the board master clock `clk`. There is no reset
// pin: /AS and /DS Low together reset it; the board applies that at
// power-up.
//
// One `clk` edge is one pin sample. /AS latches AD, /CS0 and /INTACK
// while Low; CS1 and R/W are the levels at the /DS fall, where the
// register access happens with no PCLK term. AD floats at the /DS rise.
//
// PCLK is used only at its fall: the port `pclk_fall` is that edge as a
// one-master-clock pulse from the board divider (pulses may fall on
// consecutive master clocks). Counter/timer inputs on port lines are
// ordinary level-sampled port data.
//
// Port inputs (PA, PB, PC) are sampled on the master clock: the board
// synchronises any that come from outside the clk domain. Not built: the
// bidirectional port mode and Port Link Control (MCCR D3 is stored only).

`default_nettype none

module z8036_cio (
  input  logic        clk,

  input  logic [7:0]  ad_in,      // AD7:0, the chip's only bus pins
  input  logic        as_n,
  input  logic        ds_n,
  input  logic        r_w,        // 1 = read
  input  logic        cs0_n,      // selected when !cs0_n && cs1
  input  logic        cs1,
  input  logic        intack_n,
  input  logic        iei,
  input  logic        pclk_fall,  // PCLK falling edge: one-master-clock pulse; timers count on it
  input  logic [7:0]  pa_in,
  input  logic [7:0]  pb_in,
  input  logic [3:0]  pc_in,

  output logic [7:0]  ad_out,
  output logic        ad_drive,
  output logic        int_n,      // open drain at the pad; 0 = asserted
  output logic        ieo,
  output logic [7:0]  pa_out,
  output logic [7:0]  pa_oe,      // per bit, 1 = driving
  output logic [7:0]  pb_out,
  output logic [7:0]  pb_oe,
  output logic [3:0]  pc_out,
  output logic [3:0]  pc_oe
);

  localparam int         NREGS     = 48;
  localparam logic [5:0] REG_MICR  = 6'h00;
  localparam logic [5:0] REG_MCCR  = 6'h01;
  localparam logic [5:0] REG_PCPOL = 6'h05;
  localparam logic [5:0] REG_PCDIR = 6'h06;
  localparam logic [5:0] REG_PCSIO = 6'h07;
  localparam logic [5:0] REG_PACS  = 6'h08;
  localparam logic [5:0] REG_PBCS  = 6'h09;
  localparam logic [5:0] REG_CT1CS = 6'h0A;
  localparam logic [5:0] REG_CT3CS = 6'h0C;
  localparam logic [5:0] REG_PAD   = 6'h0D;
  localparam logic [5:0] REG_PBD   = 6'h0E;
  localparam logic [5:0] REG_PCD   = 6'h0F;
  localparam logic [5:0] REG_CT1CC = 6'h10;   // current counts, MSB then LSB
  localparam logic [5:0] REG_CT3CC = 6'h15;
  localparam logic [5:0] REG_CT1TC = 6'h16;   // time constants, MSB then LSB
  localparam logic [5:0] REG_CT1MD = 6'h1C;
  localparam logic [5:0] REG_CVEC  = 6'h1F;
  // Registers read from elsewhere hold no storage: port data (the output
  // registers and the pins), current counts and the current vector.
  localparam logic [NREGS-1:0] REG_STORED = ~(48'h8000_0000 | 48'h003F_0000 | 48'h0000_E000);
  localparam logic [5:0] REG_PAMOD = 6'h20;
  localparam logic [5:0] REG_PAPOL = 6'h22;
  localparam logic [5:0] REG_PADIR = 6'h23;
  localparam logic [5:0] REG_PASIO = 6'h24;
  localparam logic [5:0] REG_PBMOD = 6'h28;
  localparam logic [5:0] REG_PBPOL = 6'h2A;
  localparam logic [5:0] REG_PBDIR = 6'h2B;
  localparam logic [5:0] REG_PBSIO = 6'h2C;
  localparam int         MICR_RST  = 0;
  localparam int         MICR_RJA  = 1;
  localparam int         MCCR_PBE  = 7;
  localparam int         MCCR_CT1E = 6;
  localparam int         MCCR_CT2E = 5;
  localparam int         MCCR_PCE  = 4;
  localparam int         MCCR_PAE  = 2;

  // Command/status bits. Port: IUS IE IP ERR ORE IRF PMF IOE.
  // Counter/timer: IUS IE IP ERR RCC GCB TCB CIP.
  localparam int CS_IUS = 7, CS_IE = 6, CS_IP = 5, CS_ERR = 4;
  localparam int CS_IOE = 0, CT_RCC = 3, CT_GCB = 2, CT_TCB = 1;
  // Counter/timer mode: C/SC EOE ECE ETE EGE REB DCS1 DCS0.
  localparam int CTM_EOE = 6, CTM_ECE = 5, CTM_ETE = 4, CTM_EGE = 3;

  // D7:D5 of a command/status write: the IUS/IE/IP command.
  function automatic logic [7:0] cs_cmd(input logic [7:0] cs, input logic [2:0] cmd);
    logic [7:0] r;
    r = cs;
    case (cmd)
      3'd1: begin r[CS_IUS] = 1'b0; r[CS_IP] = 1'b0; r[CS_ERR] = 1'b0; end
      3'd2: r[CS_IUS] = 1'b1;
      3'd3: r[CS_IUS] = 1'b0;
      3'd4: r[CS_IP]  = 1'b1;
      3'd5: begin r[CS_IP] = 1'b0; r[CS_ERR] = 1'b0; end   // ERR clears with IP
      3'd6: r[CS_IE]  = 1'b1;
      3'd7: r[CS_IE]  = 1'b0;
      default: ;
    endcase
    return r;
  endfunction

  // A port's data register as read: Mode D7:D6 01 = all input, 10 = all
  // output, otherwise per bit by the direction register. Polarity last.
  function automatic logic [7:0] port_read(input logic [7:0] in, input logic [7:0] out,
                                           input logic [7:0] dir, input logic [7:0] pol,
                                           input logic [1:0] mode);
    logic [7:0] raw;
    case (mode)
      2'd1:    raw = in;
      2'd2:    raw = out;
      default: raw = (in & dir) | (out & ~dir);
    endcase
    return raw ^ pol;
  endfunction

  // ---- register storage ------------------------------------------------------
  // MICR bit 0 is the Reset bit; while it is set every other register reads
  // 0 and only that bit can be written.
  logic [7:0] regs [0:NREGS-1];
  logic       in_reset;
  assign in_reset = regs[REG_MICR][MICR_RST];

  // Port output registers. Data, not control: a reset leaves them alone.
  logic [7:0] out_a, out_b;
  logic [3:0] out_c;

  // Port pins sampled at each /AS rise, and the 1's catchers. A catcher
  // sits on each input bit with its Special I/O bit set: a 1 after the
  // polarity stage holds until software writes a 0 to that bit.
  logic [7:0] smp_a, smp_b, catch_a, catch_b;
  logic [3:0] smp_c, catch_c;

  // Inputs as the data registers and pattern logic see them: polarity
  // applied, catcher outputs on the catcher bits.
  function automatic logic [7:0] eff_in(input logic [7:0] raw, input logic [7:0] pol,
                                        input logic [7:0] sio, input logic [7:0] dir,
                                        input logic [7:0] catches);
    logic [7:0] v, en;
    v  = raw ^ pol;
    en = sio & dir;
    return (v & ~en) | ((v | catches) & en);
  endfunction

  // The /AS rise samples the pins and steps the catchers; a /DS fall in
  // the same sample already sees the new values.
  logic       as_rise;
  logic [1:0] hs_wclk;         // PCLK steps a handshake held by /WAIT
  logic [7:0] cdir_a, cdir_b;  // catcher bits: handshake data lines have none
  logic [7:0] smp_a_nx, smp_b_nx, catch_a_nx, catch_b_nx;
  logic [3:0] smp_c_nx, catch_c_nx;
  always_comb begin
    {smp_a_nx, smp_b_nx, smp_c_nx}       = {smp_a, smp_b, smp_c};
    {catch_a_nx, catch_b_nx, catch_c_nx} = {catch_a, catch_b, catch_c};
    if (as_rise || |hs_wclk) {smp_a_nx, smp_b_nx, smp_c_nx} = {pa_in, pb_in, pc_in};
    if (as_rise) begin
      if (!in_reset) begin
        catch_a_nx = catch_a | ((pa_in ^ regs[REG_PAPOL]) & regs[REG_PASIO] & cdir_a);
        catch_b_nx = catch_b | ((pb_in ^ regs[REG_PBPOL]) & regs[REG_PBSIO] & cdir_b);
        catch_c_nx = catch_c | ((pc_in ^ regs[REG_PCPOL][3:0]) & regs[REG_PCSIO][3:0]
                                & regs[REG_PCDIR][3:0]);
      end
    end
  end

  logic [7:0] in_a, in_b, in_c8;
  logic [3:0] in_c;
  assign in_a  = eff_in(smp_a_nx, regs[REG_PAPOL], regs[REG_PASIO], cdir_a, catch_a_nx);
  assign in_b  = eff_in(smp_b_nx, regs[REG_PBPOL], regs[REG_PBSIO], cdir_b, catch_b_nx);
  assign in_c8 = eff_in({4'h0, smp_c_nx}, {4'h0, regs[REG_PCPOL][3:0]}, {4'h0, regs[REG_PCSIO][3:0]},
                        {4'h0, regs[REG_PCDIR][3:0]}, {4'h0, catch_c_nx});
  assign in_c  = in_c8[3:0];

  // ---- counter/timer state ---------------------------------------------------
  // tcp: terminal count reached, reload at the next PCLK fall.
  // sq2: square wave in its second half. pclr: pulse output to drop.
  typedef struct packed {
    logic [15:0] cnt;
    logic        run, tcp, out, sq2, pclr;
  } ct_t;

  ct_t        ct [0:2];
  logic [15:0] ct_latch [0:2];  // frozen count while RCC is set
  logic [2:0] ct_perr;          // end of count while IP was set
  logic [2:0] ct_clk_q, ct_trig_q;
  logic [2:0] ct_gate_q;        // gates at the last falling count input
  logic       ct_pre;           // PCLK/2
  logic       ct_out1_q;        // C/T 1 output at the last PCLK step
  logic [2:0] ct_cip;
  assign ct_cip = {ct[2].run, ct[1].run, ct[0].run};

  // verilator lint_off UNUSEDSIGNAL
  // Load and start. A running counter only restarts with REB set.
  function automatic ct_t ct_trig(input ct_t s, input logic [7:0] md, input logic en,
                                  input logic [15:0] tc);
    ct_t r;
    r = s;
    if (en && (!s.run || md[2])) begin
      r.cnt  = tc;
      r.run  = 1'b1;
      r.tcp  = 1'b0;
      r.sq2  = 1'b0;
      r.pclr = 1'b0;
      r.out  = md[1:0] == 2'd1;   // one-shot starts High
    end
    return r;
  endfunction

  // End of count. A square wave reloads for its second half whatever C/SC
  // says; otherwise only continuous mode reloads and keeps running.
  function automatic ct_t ct_end(input ct_t s, input logic [7:0] md);
    ct_t r;
    r = s;
    r.tcp = md[7];
    r.run = md[7];
    if (md[1:0] == 2'd2) begin
      r.out = !s.sq2;
      r.sq2 = !s.sq2;
      if (!s.sq2) begin r.tcp = 1'b1; r.run = 1'b1; end
    end else if (md[1:0] == 2'd1) begin
      r.out = 1'b0;
    end else begin
      r.out  = 1'b1;               // pulse: High for one count
      r.pclr = 1'b1;
    end
    return r;
  endfunction
  // verilator lint_on UNUSEDSIGNAL

  // ---- pattern match ---------------------------------------------------------
  // Each /AS rise shifts the port's input through two stages and compares
  // the older pair: PM=0 PT=1 any transition, PM=1 PT=0 level against PP,
  // PM=1 PT=1 the edge PP names.
  logic [7:0] pm_s1 [0:1], pm_s2 [0:1], pm_bits [0:1], lpm_latch [0:1];
  logic [1:0] lpm_valid, pm_perr;

  logic [7:0] pm_bits_nx [0:1], lpm_latch_nx [0:1];
  logic [1:0] pm_frz;        // match bits held from the acknowledge until IP clears
  logic [1:0] lpm_valid_nx, pm_perr_nx, pm_pmf_nx, pm_ip_set, hs_on;
  assign cdir_a = regs[REG_PADIR] & {8{!hs_on[0]}};
  assign cdir_b = regs[REG_PBDIR] & {8{!hs_on[1]}};
  // verilator lint_off UNUSEDSIGNAL
  always_comb begin
    logic [7:0] md, cs, pp, pt, pm, m, part;
    logic       en, hit;
    for (int p = 0; p < 2; p++) begin
      md   = regs[REG_PAMOD + 6'(8*p)];
      cs   = regs[REG_PACS + 6'(p)];
      pp   = regs[REG_PAMOD + 6'(8*p+5)];
      pt   = regs[REG_PAMOD + 6'(8*p+6)];
      pm   = regs[REG_PAMOD + 6'(8*p+7)];
      en   = p == 0 ? regs[REG_MCCR][MCCR_PAE] : regs[REG_MCCR][MCCR_PBE];
      hs_on[p] = en && (md[7:6] == 2'd1 || md[7:6] == 2'd2);
      part = pm | pt;
      m    = (~pm & pt & (pm_s2[p] ^ pm_s1[p]))
           | (pm & ~pt & ~(pm_s1[p] ^ pp))
           | (pm & pt & ~(pm_s1[p] ^ pp) & (pm_s2[p] ^ pp));
      hit  = md[2:1] == 2'd1 ? (|part && &(m | ~part)) : |m;

      pm_bits_nx[p]   = pm_bits[p];
      lpm_latch_nx[p] = lpm_latch[p];
      lpm_valid_nx[p] = lpm_valid[p];
      pm_perr_nx[p]   = pm_perr[p];
      pm_pmf_nx[p]    = cs[1];
      pm_ip_set[p]    = 1'b0;
      if (as_rise && !in_reset) begin
        if (md[2:1] == 2'd0 || !en) begin
          pm_pmf_nx[p]  = 1'b0;
          pm_bits_nx[p] = 8'h00;
        end else if (!hs_on[p]) begin
          if (!pm_frz[p]) pm_bits_nx[p] = m;
          pm_pmf_nx[p]  = hit;
          // OR-priority mode raises IP on every matching sample; the
          // others on the first one, or flag an error if IP is still set.
          if (hit && (md[2:1] == 2'd3 || !cs[1])) begin
            if (md[2:1] == 2'd3 || (!cs[CS_ERR] && !cs[CS_IP]))
              pm_ip_set[p] = 1'b1;
            else if (!cs[CS_ERR] && cs[CS_IOE])
              pm_perr_nx[p] = 1'b1;
          end
          if (pm_ip_set[p] && md[0] && !lpm_valid[p]) begin
            lpm_latch_nx[p] = pm_s1[p];
            lpm_valid_nx[p] = 1'b1;
          end
        end
      end
    end
  end
  // verilator lint_on UNUSEDSIGNAL


  // ---- handshake -------------------------------------------------------------
  // Ports A and B as input or output ports: pins <-> Buffer <-> Input or
  // Output register, with the handshake lines on Port C. pmf and ip are
  // working copies of the port's status bits.
  typedef struct packed {
    logic [7:0] bf_d, inp;
    logic       bf, irf, ore, obf;  // buffer full, input full, output empty, buffer out
    logic       rd, dac, pack, aw;  // RFD or /DAV level, DAC level, last ack, await release
    logic       lv, pnd;            // ack level last clock, ack edge since the last step
    logic [7:0] ad;                 // port data at the held ack fall
    logic [4:0] dsk;                // PCLK falls left before /DAV
    logic       pmf, ip;
  } hs_t;

  localparam hs_t HS_RST = '{ore: 1'b1, rd: 1'b1, pack: 1'b1, lv: 1'b1, default: '0};

  // pmf and ip are reloaded from the status register every clock: not stored.
  localparam int HS_W = $bits(hs_t) - 2;
  logic [HS_W-1:0] hs_q [0:1];
  hs_t        hs [0:1], hs_as [0:1], hs_fin [0:1];
  assign hs[0] = hs_t'({hs_q[0], 2'b00});
  assign hs[1] = hs_t'({hs_q[1], 2'b00});
  logic [3:0] hs_drive, hs_mask, hs_drive_nx, hs_mask_nx;
  logic [1:0] hs_ipset, hs_isin, hs_tw, hs_pl;
  // Pulsed handshake: C/T3 sits in the port's ACKIN or DAV path.
  assign hs_pl = {regs[REG_PAMOD + 6'd9][7:6] == 2'd2, regs[REG_PAMOD + 6'd1][7:6] == 2'd2};
  logic [2:0] hs_rws [0:1];

  // verilator lint_off UNUSEDSIGNAL
  // Handshake ports compare whole bytes: a level pattern only.
  function automatic logic hs_cmp(input logic [7:0] md, input logic [7:0] pp, input logic [7:0] pt,
                                  input logic [7:0] pm, input logic [7:0] b);
    logic [7:0] m, part;
    part = pm | pt;
    m    = pm & ~pt & ~(b ^ pp);
    return md[2:1] == 2'd1 ? (|part && &(m | ~part)) : |m;
  endfunction

  // IP for a new byte. With ITB, only once two bytes can move, unless the
  // byte matched the pattern.
  function automatic hs_t hs_raise(input hs_t s, input logic [7:0] md, input logic pmatch);
    hs_t r;
    r = s;
    if (!md[5] || pmatch || (md[7:6] == 2'd1 ? s.irf && s.bf : s.ore && !s.obf)) r.ip = 1'b1;
    return r;
  endfunction

  // Buffer to Input register, held while PMF and IP are both set.
  function automatic hs_t hs_prop(input hs_t s, input logic [7:0] md, input logic [7:0] pp,
                                  input logic [7:0] pt, input logic [7:0] pm);
    hs_t  r;
    logic hit;
    r = s;
    if (s.bf && !s.irf && !(s.pmf && s.ip)) begin
      hit = md[2:1] == 2'd0 || hs_cmp(md, pp, pt, pm, s.bf_d);
      if (md[2:1] != 2'd0) r.pmf = hit;
      r.inp = s.bf_d;
      r.bf  = 1'b0;
      r.irf = 1'b1;
      if (!md[3] || hit) r = hs_raise(r, md, hit && md[2:1] != 2'd0);
    end
    return r;
  endfunction

  // REQUEST: a byte to read or room to write; two with ITB.
  function automatic logic hs_ready(input hs_t s, input logic [2:0] rws, input logic itb);
    case (rws)
      3'd7, 3'd3, 3'd4: return itb ? s.irf && s.bf : s.irf;
      3'd5, 3'd1:       return itb ? s.ore && !s.obf : s.ore;
      default:          return 1'b0;
    endcase
  endfunction

  // One /AS clock of each handshake, or a PCLK one while /WAIT holds it.
  always_comb begin
    logic [7:0] md, sp, pp, pt, pm, din, dout;
    logic [1:0] rdb, ackb, reqb;
    logic       ack, lack, afall, arise, il, hit, took, dg;
    hs_t        s;
    {ack, lack, afall, arise, hit, took, dg} = '0;
    hs_as       = hs;
    hs_drive_nx = hs_drive;
    hs_mask_nx  = hs_mask;
    if (as_rise && !in_reset) {hs_drive_nx, hs_mask_nx} = '0;
    for (int p = 0; p < 2; p++) begin
      md   = regs[REG_PAMOD + 6'(8*p)];
      sp   = regs[REG_PAMOD + 6'(8*p+1)];
      pp   = regs[REG_PAMOD + 6'(8*p+5)];
      pt   = regs[REG_PAMOD + 6'(8*p+6)];
      pm   = regs[REG_PAMOD + 6'(8*p+7)];
      din  = p == 0 ? in_a : in_b;
      dout = p == 0 ? out_a : out_b;
      hs_isin[p] = md[7:6] == 2'd1;
      hs_tw[p]   = sp[7:6] == 2'd3;
      hs_rws[p]  = sp[5:3];
      il   = !sp[6];                          // interlocked or pulsed
      // Table 1: Port B's two-wire lines sit on PC1/PC0/PC3.
      {rdb, ackb, reqb} = (p == 1 && !hs_tw[p]) ? {2'd1, 2'd0, 2'd3} : {2'd3, 2'd2, 2'd1};
      s     = hs[p];
      s.pmf = pm_pmf_nx[p];
      s.ip  = regs[REG_PACS + 6'(p)][CS_IP];
      hs_ipset[p] = 1'b0;
      // An ack edge between steps is held, so a short pulse still counts:
      // each step moves the ack one edge.
      lack = hs_pl[p] && hs_isin[p] ? !ct[2].out : pc_in[ackb] ^ regs[REG_PCPOL][3'(ackb)];
      if ((as_rise || hs_wclk[p]) && !in_reset && hs_on[p]) begin
        ack    = hs_pl[p] && hs_isin[p] ? !ct[2].out : in_c[ackb];
        ack    = s.pnd || ack != s.pack ? !s.pack : s.pack;
        if (s.pnd && s.pack) din = s.ad;
        s.pnd  = 1'b0;
        afall  = s.pack && !ack;
        arise  = !s.pack && ack;
        s.pack = ack;
        if (hs_isin[p]) begin
          // The strobed handshake latches on every /ACKIN fall, overrun or not.
          if (afall && (sp[7:6] == 2'd1 || (!s.bf && !(md[4] && s.irf)))) begin
            s.bf_d = din;
            s.bf   = 1'b1;
            if (sp[7:6] != 2'd1) begin
              if (il) s.aw = 1'b1;
              if (hs_tw[p]) s.dac = 1'b1;
            end
          end
          if (arise) s.aw = 1'b0;
          // 3-wire: the byte moves on as DAV rises, and DAC drops with it.
          if (!hs_tw[p] || ack) begin
            s = hs_prop(s, md, pp, pt, pm);
            s.dac = 1'b0;
          end
          if (md[5] && s.irf && s.bf) s = hs_raise(s, md, 1'b0);
          s.rd = !s.bf && !(md[4] && s.irf) && !s.aw && !s.dac;
        end else begin
          // Output register to Buffer, compared on the way.
          if (!s.ore && !s.obf && !(s.pmf && s.ip)) begin
            s.bf_d = dout;
            s.obf  = 1'b1;
            s.dsk  = md[0] ? 5'({sp[2:0], 1'b1}) + 5'd1 : 5'd0;
            hit    = md[2:1] == 2'd0 || hs_cmp(md, pp, pt, pm, dout);
            if (md[2:1] != 2'd0) s.pmf = hit;
            // Single-buffered: the register empties only when the byte is taken.
            if (!md[4]) begin
              s.ore = 1'b1;
              if (!md[3] || hit) s = hs_raise(s, md, hit && md[2:1] != 2'd0);
            end
          end
          // 3-wire waits for RFD High and DAC Low.
          dg = !hs_tw[p] || (in_c[0] && !ack);
          if (s.obf && s.dsk == 5'd0 && s.rd && !s.aw && dg) s.rd = 1'b0;
          took = hs_tw[p] ? arise : afall;
          if (took && s.obf && !s.rd) begin
            s.rd  = 1'b1;
            s.obf = 1'b0;
            if (md[4]) begin
              s.ore = 1'b1;
              hit   = md[2:1] == 2'd0 || s.pmf;
              if (!md[3] || hit) s = hs_raise(s, md, hit && md[2:1] != 2'd0);
            end
            if (il) s.aw = 1'b1;
            if (!md[4] && md[5]) s = hs_raise(s, md, 1'b0);
          end
          if (arise && !hs_tw[p]) s.aw = 1'b0;
          s.dac = 1'b0;
        end
        hs_ipset[p] = s.ip && !regs[REG_PACS + 6'(p)][CS_IP];
        hs_mask_nx[rdb]  = 1'b1;
        hs_drive_nx[rdb] = s.rd;
        if (hs_tw[p] && hs_isin[p]) begin
          hs_mask_nx[0]  = 1'b1;
          hs_drive_nx[0] = s.dac;
        end
        // /WAIT idles High; it is asserted per access at the pins.
        if (sp[5:3] == 3'd4 || sp[5:3] == 3'd5 || sp[5:3] == 3'd7) begin
          hs_mask_nx[reqb]  = 1'b1;
          hs_drive_nx[reqb] = hs_ready(s, sp[5:3], md[5]);
        end else if (sp[5:3] == 3'd1 || sp[5:3] == 3'd3) begin
          hs_mask_nx[reqb]  = 1'b1;
          hs_drive_nx[reqb] = 1'b1;
        end
      end
      if (!as_rise && !hs_wclk[p] && !in_reset && hs_on[p] && s.lv != lack) begin
        // The data is latched with the ack fall.
        if (!lack) s.ad = p == 0 ? pa_in ^ regs[REG_PAPOL] : pb_in ^ regs[REG_PBPOL];
        s.pnd = 1'b1;
      end
      s.lv = lack;
      hs_as[p] = s;
    end
  end
  // verilator lint_on UNUSEDSIGNAL
  // ---- interrupt sources -----------------------------------------------------
  // Priority, highest first: C/T 3, port A, C/T 2, port B, C/T 1. A source
  // is blocked while it or any higher one is under service.
  logic [4:0] src_ius, src_req, src_elig, src_elig_as;
  logic [2:0] src_idx;
  logic       src_any, int_latch;
  always_comb begin
    logic [7:0] s [0:4];
    s = '{regs[REG_CT3CS], regs[REG_PACS], regs[REG_CT1CS + 6'd1], regs[REG_PBCS], regs[REG_CT1CS]};
    for (int i = 0; i < 5; i++) begin
      src_ius[i] = s[i][CS_IUS];
      src_req[i] = s[i][CS_IE] && s[i][CS_IP];
    end
    for (int i = 0; i < 5; i++) begin
      src_elig[i]    = src_req[i] && !(|(src_ius & 5'((1 << (i + 1)) - 1)));
      // At the /AS rise the pattern logic's new IP counts too.
      src_elig_as[i] = (src_req[i] || (s[i][CS_IE] && (i == 1 ? pm_ip_set[0] | hs_ipset[0] : i == 3 && (pm_ip_set[1] | hs_ipset[1]))))
                       && !(|(src_ius & 5'((1 << (i + 1)) - 1)));
    end
    src_idx = 3'd0;
    for (int i = 4; i >= 0; i--) if (src_elig[i]) src_idx = 3'(i);
    src_any = |src_elig;
  end

  // A source's vector. With status included, a port puts the highest
  // matching bit (OR-priority mode), 000 for an error, or ORE/IRF/PMF on
  // D3:D1; a counter/timer puts its number, or 11 for an error, on D2:D1.
  function automatic logic [7:0] src_vec(input logic [2:0] i, input logic vis);
    logic [7:0] iv, cs, mb;
    logic [2:0] code;
    if (i == 3'd1 || i == 3'd3) begin
      iv   = regs[i == 3'd1 ? 6'h02 : 6'h03];
      cs   = regs[i == 3'd1 ? REG_PACS : REG_PBCS];
      mb   = pm_bits[i == 3'd3];
      code = 3'd0;
      if (regs[i == 3'd1 ? REG_PAMOD : REG_PBMOD][2:1] == 2'd3) begin
        for (int b = 0; b < 8; b++) if (mb[b]) code = 3'(b);
      end else if (!cs[CS_ERR]) begin
        code = {hs_on[i == 3'd3] && hs[i == 3'd3].ore, hs_on[i == 3'd3] && hs[i == 3'd3].irf, cs[1]};
      end
      return vis ? {iv[7:4], code, iv[0]} : iv;
    end else begin
      iv = regs[6'h04];
      cs = regs[i == 3'd0 ? REG_CT3CS : i == 3'd2 ? REG_CT1CS + 6'd1 : REG_CT1CS];
      code = cs[CS_ERR] ? 3'd3 : {1'b0, i[2:1]};
      return vis ? {iv[7:3], code[1:0], iv[0]} : iv;
    end
  endfunction

  logic       src_vis, mie;
  logic [7:0] ack_vec;
  assign mie     = regs[REG_MICR][7];
  assign src_vis = (src_idx == 3'd1) ? regs[REG_MICR][4]
                 : (src_idx == 3'd3) ? regs[REG_MICR][3] : regs[REG_MICR][2];
  assign ack_vec = src_vec(src_idx, src_vis && !regs[REG_MICR][5]);

  // ---- strobe capture --------------------------------------------------------
  logic       ds_q, as_q;
  logic [7:0] as_ad;          // address latched while /AS is Low
  logic       as_intack_n;
  logic       owned;          // /CS0 Low at the last /AS; CS1 gates each /DS
  logic [7:0] ad_q;
  logic       ad_drive_q;

  logic       hw_reset, ds_fall, ds_rise;
  logic       ds_spent;       // a /DS rose since the last /AS: one access per /AS
  logic [5:0] cyc_reg;
  assign hw_reset = !as_n && !ds_n;
  assign ds_fall  = ds_q && !ds_n && as_n && !ds_spent;
  assign ds_rise  = !ds_q && ds_n;
  assign as_rise  = !as_q && as_n;
  // The /INT latch as a /DS fall in the same sample as the /AS rise sees it.
  logic int_latch_now;
  assign int_latch_now = as_rise && !in_reset ? mie && iei && |src_elig_as : int_latch;
  // RJA picks AD5:AD0; otherwise AD6:AD1. AD7 is never decoded.
  assign cyc_reg  = regs[REG_MICR][MICR_RJA] ? as_ad[5:0] : as_ad[6:1];

  logic       ct_reg, cc_lsb;
  logic [1:0] ct_idx;
  assign ct_reg = cyc_reg >= REG_CT1CS && cyc_reg <= REG_CT3CS;
  assign cc_lsb = cyc_reg >= REG_CT1CC && cyc_reg <= REG_CT3CC && cyc_reg[0];
  assign ct_idx = ct_reg ? 2'(cyc_reg - REG_CT1CS) : cyc_reg[2:1];

  // Addresses 48-63 hold no register.
  logic [7:0] reg_cur, cs_new;
  assign reg_cur = (32'(cyc_reg) < NREGS) ? regs[cyc_reg] : 8'h00;
  assign cs_new  = cs_cmd(reg_cur, ad_in[7:5]);

  // ---- counter/timers --------------------------------------------------------
  // A register write this sample, and the registers as they stand after it:
  // the counters act on the new values in the same sample.
  logic bus_wr, reg_wr, ct_wr, ct_off, sw_reset;
  assign bus_wr = ds_fall && as_intack_n && cs1 && owned && !r_w;
  assign reg_wr = bus_wr && !in_reset;
  assign ct_wr  = reg_wr && ct_reg;
  assign sw_reset = reg_wr && cyc_reg == REG_MICR && ad_in[MICR_RST];
  // Reset holds the counters cleared until the Reset bit is written 0.
  assign ct_off = hw_reset || sw_reset
                  || (in_reset && !(bus_wr && cyc_reg == REG_MICR && !ad_in[MICR_RST]));

  function automatic logic [7:0] reg_post(input logic [5:0] a, input logic [7:0] cur,
                                          input logic hit, input logic [5:0] wa,
                                          input logic [7:0] wd);
    return (hit && wa == a) ? wd : cur;
  endfunction

  logic [7:0] mccr_p, pbpol_p, pbsio_p, pbdir_p, pcpol_p, pcsio_p, pcdir_p;
  logic [7:0] md_p [0:2];
  logic [15:0] tc_p [0:2];
  assign mccr_p  = reg_post(REG_MCCR,  regs[REG_MCCR],  reg_wr, cyc_reg, ad_in);
  assign pbpol_p = reg_post(REG_PBPOL, regs[REG_PBPOL], reg_wr, cyc_reg, ad_in);
  assign pbsio_p = reg_post(REG_PBSIO, regs[REG_PBSIO], reg_wr, cyc_reg, ad_in);
  assign pbdir_p = reg_post(REG_PBDIR, regs[REG_PBDIR], reg_wr, cyc_reg, ad_in);
  assign pcpol_p = reg_post(REG_PCPOL, regs[REG_PCPOL], reg_wr, cyc_reg, ad_in);
  assign pcsio_p = reg_post(REG_PCSIO, regs[REG_PCSIO], reg_wr, cyc_reg, ad_in);
  assign pcdir_p = reg_post(REG_PCDIR, regs[REG_PCDIR], reg_wr, cyc_reg, ad_in);
  genvar gi;
  generate
    for (gi = 0; gi < 3; gi++) begin : g_ct_regs
      assign md_p[gi] = reg_post(REG_CT1MD + 6'(gi), regs[REG_CT1MD + gi], reg_wr, cyc_reg, ad_in);
      assign tc_p[gi] = {reg_post(REG_CT1TC + 6'(2*gi), regs[REG_CT1TC + 2*gi], reg_wr, cyc_reg, ad_in),
                        reg_post(REG_CT1TC + 6'(2*gi+1), regs[REG_CT1TC + 2*gi+1], reg_wr, cyc_reg, ad_in)};
    end
  endgenerate

  // Port command/status write. In OR-priority mode IP holds while the
  // pattern still matches; clearing it with an error held sets IP and ERR.
  // PMF, and an IP raised by an /AS rise in this sample, survive the write
  // unless it clears IP.
  logic [7:0] port_cs_wr;
  logic       port_clr_ip;
  always_comb begin
    port_cs_wr  = cs_new;
    port_clr_ip = ad_in[7:5] == 3'd1 || ad_in[7:5] == 3'd5;
    if (port_clr_ip && regs[REG_PAMOD + 6'({cyc_reg[0], 3'b000})][2:1] == 2'd3 && reg_cur[1]) begin
      {port_cs_wr[CS_IP], port_cs_wr[CS_ERR]} = {reg_cur[CS_IP], reg_cur[CS_ERR]};
      port_clr_ip = 1'b0;
    end else if (port_clr_ip && pm_perr[cyc_reg[0]]) begin
      {port_cs_wr[CS_IP], port_cs_wr[CS_ERR]} = 2'b11;
    end
    if (!port_clr_ip && (pm_ip_set[cyc_reg[0]] || hs_ipset[cyc_reg[0]])) port_cs_wr[CS_IP] = 1'b1;
    port_cs_wr[1] = hs_on[cyc_reg[0]] ? hs_fin[cyc_reg[0]].pmf : pm_pmf_nx[cyc_reg[0]];
  end

  // Clearing IP while an end-of-count error is held sets IP and ERR again.
  logic [7:0] ct_cs_wr;
  always_comb begin
    ct_cs_wr = {cs_new[7:4], reg_cur[CT_RCC] | ad_in[CT_RCC], ad_in[CT_GCB], 2'b00};
    if (ct_perr[ct_idx] && (ad_in[7:5] == 3'd1 || ad_in[7:5] == 3'd5))
      {ct_cs_wr[CS_IP], ct_cs_wr[CS_ERR]} = 2'b11;
  end

  // Count, trigger and gate inputs come from the live pins, through
  // polarity and the 1's catchers.
  logic [7:0] pb_live, pc_live;
  logic [2:0] ct_clk_in, ct_trig_in, ct_gate_in;
  assign pb_live    = eff_in(pb_in, pbpol_p, pbsio_p, pbdir_p & {8{!hs_on[1]}}, catch_b_nx);
  assign pc_live    = eff_in({4'h0, pc_in}, {4'h0, pcpol_p[3:0]}, {4'h0, pcsio_p[3:0]},
                             {4'h0, pcdir_p[3:0]}, {4'h0, catch_c_nx});
  assign ct_clk_in  = {pc_live[1], pb_live[1], pb_live[5]};
  // A pulsed port triggers C/T3 instead of PC2: its ACKIN pin falling as
  // an input, its internal DAV falling as an output.
  logic ct3_link, ct3_ltrig;
  always_comb begin
    {ct3_link, ct3_ltrig} = '0;
    for (int p = 0; p < 2; p++)
      if (hs_on[p] && hs_pl[p]) begin
        ct3_link  = 1'b1;
        ct3_ltrig = ct3_ltrig || (hs_isin[p] ? !pc_live[p == 0 ? 2 : 0] : !hs[p].rd);
      end
  end
  assign ct_trig_in = {ct3_link ? ct3_ltrig : pc_live[2], pb_live[2], pb_live[6]};
  assign ct_gate_in = {pc_live[3], pb_live[3], pb_live[7]};

  ct_t        ct_nx [0:2];
  logic [15:0] ct_latch_nx [0:2];
  logic [2:0] ct_perr_nx, ct_ip_set, ct_en, ip_v, err_v, gcb_v;
  logic       ct_pre_nx, ct_out1_nx, ct_out0_pre, ece, cfall, crise, tick, reload, gate, out0, tc_hit;
  always_comb begin
    for (int i = 0; i < 3; i++) begin
      ct_nx[i]       = ct[i];
      ct_latch_nx[i] = ct_latch[i];
      ip_v[i]  = (ct_wr && ct_idx == 2'(i)) ? ct_cs_wr[CS_IP]  : regs[REG_CT1CS + 6'(i)][CS_IP];
      err_v[i] = (ct_wr && ct_idx == 2'(i)) ? ct_cs_wr[CS_ERR] : regs[REG_CT1CS + 6'(i)][CS_ERR];
      gcb_v[i] = (ct_wr && ct_idx == 2'(i)) ? ad_in[CT_GCB]   : regs[REG_CT1CS + 6'(i)][CT_GCB];
    end
    ct_en      = {mccr_p[MCCR_PCE], mccr_p[MCCR_CT2E], mccr_p[MCCR_CT1E]};
    ct_perr_nx = ct_perr;
    ct_ip_set  = '0;
    ct_pre_nx  = pclk_fall ? !ct_pre : ct_pre;   // timer mode counts on every other PCLK fall
    ct_out1_nx = ct_out1_q;
    {ece, cfall, crise, tick, reload, gate, out0, tc_hit} = '0;

    // Command/status write: the error is consumed, the first RCC set
    // freezes the count, TCB triggers.
    if (ct_wr) begin
      if (ad_in[7:5] == 3'd1 || ad_in[7:5] == 3'd5) ct_perr_nx[ct_idx] = 1'b0;
      if (ad_in[CT_RCC] && !reg_cur[CT_RCC]) ct_latch_nx[ct_idx] = ct[ct_idx].cnt;
      if (ad_in[CT_TCB])
        ct_nx[ct_idx] = ct_trig(ct_nx[ct_idx], md_p[ct_idx], ct_en[ct_idx], tc_p[ct_idx]);
    end

    // One step per counter. Counter mode: trigger and gate are sampled as
    // the count input falls; the count steps, reloads and ends the pulse as
    // it rises. Timer mode: trigger and reload on each PCLK fall, the rest
    // on every other one, or on C/T 1's output falling when linked.
    ct_out0_pre = ct_nx[0].out;
    for (int i = 0; i < 3; i++) begin
      ece   = md_p[i][CTM_ECE];
      cfall = ct_clk_q[i] && !ct_clk_in[i];
      crise = !ct_clk_q[i] && ct_clk_in[i];
      if ((ece ? cfall : pclk_fall) && !ct_trig_q[i] && ct_trig_in[i] && md_p[i][CTM_ETE])
        ct_nx[i] = ct_trig(ct_nx[i], md_p[i], ct_en[i], tc_p[i]);
      // C/T 2 sees C/T 1's output as its count-input step left it; the PCLK
      // step sees C/T 1's PCLK step too. It is inverted on the way.
      out0   = ece ? ct_out0_pre : ct_nx[0].out;
      reload = ece ? crise : pclk_fall;
      tick   = ece ? crise
             : pclk_fall && (i == 1 && mccr_p[1:0] == 2'd3 ? ct_out1_q && !ct_nx[0].out : ct_pre_nx);
      gate   = ece ? ct_gate_q[i] : ct_gate_in[i];
      if (tick && ct_nx[i].pclr) begin ct_nx[i].out = 1'b0; ct_nx[i].pclr = 1'b0; end
      if (reload) begin
        if (ct_nx[i].tcp) ct_nx[i].cnt = tc_p[i];
        ct_nx[i].tcp = 1'b0;
      end
      if (tick && ct_nx[i].run && gcb_v[i] && (!md_p[i][CTM_EGE] || gate)
          && !(i == 1 && mccr_p[1:0] == 2'd1 && out0)) begin
        tc_hit       = ct_nx[i].cnt == 16'd1;
        ct_nx[i].cnt = ct_nx[i].cnt - 16'd1;
        if (tc_hit) begin
          ct_nx[i] = ct_end(ct_nx[i], md_p[i]);
          if (!ip_v[i]) begin ip_v[i] = 1'b1; ct_ip_set[i] = 1'b1; end
          else if (!err_v[i]) ct_perr_nx[i] = 1'b1;
        end
      end
      if (i == 0 && ece) ct_out0_pre = ct_nx[0].out;
    end

    if (pclk_fall) begin
      if (mccr_p[1:0] == 2'd2 && ct_out1_q && !ct_nx[0].out)
        ct_nx[1] = ct_trig(ct_nx[1], md_p[1], ct_en[1], tc_p[1]);
      ct_out1_nx = ct_nx[0].out;
    end
  end


  // ---- handshake data access -------------------------------------------------
  // Reading an input port takes the Input register and moves the buffered
  // byte up; writing an output port fills the Output register. Either
  // clears IP, after the second byte with ITB. While PMF and IP are both
  // set nothing moves and a write is refused. The deskew timer counts PCLK.
  logic       hs_acc, wait_stall, wait_nx, hs_rel;
  logic [1:0] hs_wr_ok, hs_wready;
  assign hs_acc = ds_fall && as_intack_n && cs1 && owned && !in_reset;
  // While /WAIT holds the CPU no /AS comes: the stalled port's handshake
  // steps on PCLK instead, and the held access completes once it is ready.
  always_comb begin
    hs_rel = 1'b0;
    for (int p = 0; p < 2; p++) begin
      hs_wready[p] = hs_rws[p] == 3'd3 ? hs_as[p].irf : hs_as[p].ore;
      hs_wclk[p]   = pclk_fall && wait_stall && owned && !ds_n && as_intack_n && !in_reset
                     && hs_on[p] && cyc_reg == REG_PAD + 6'(p);
      if (wait_stall && owned && !ds_n && as_intack_n && !in_reset && hs_on[p]
          && cyc_reg == REG_PAD + 6'(p) && hs_wready[p]) hs_rel = 1'b1;
    end
  end
  // verilator lint_off UNUSEDSIGNAL
  always_comb begin
    logic [7:0] md;
    hs_t        s;
    wait_nx = wait_stall;
    if ((ds_fall && as_intack_n) || ds_rise) wait_nx = 1'b0;
    for (int p = 0; p < 2; p++) begin
      md = regs[REG_PAMOD + 6'(8*p)];
      s  = hs_as[p];
      hs_wr_ok[p] = 1'b1;
      if ((hs_acc || hs_rel) && hs_on[p] && cyc_reg == REG_PAD + 6'(p)) begin
        if (hs_rel) wait_nx = 1'b0;
        if (hs_acc && ((hs_rws[p] == 3'd3 && !s.irf) || (hs_rws[p] == 3'd1 && !s.ore))) begin
          wait_nx     = 1'b1;
          hs_wr_ok[p] = 1'b0;
        end else if (r_w) begin
          if (hs_isin[p] && s.irf && !(s.pmf && s.ip)) begin
            s.irf = 1'b0;
            if (!md[5] || !s.bf) s.ip = 1'b0;
            s = hs_prop(s, md, regs[REG_PAMOD + 6'(8*p+5)], regs[REG_PAMOD + 6'(8*p+6)],
                        regs[REG_PAMOD + 6'(8*p+7)]);
          end
        end else if (!hs_isin[p]) begin
          if (s.pmf && s.ip) hs_wr_ok[p] = 1'b0;
          else begin
            s.ore = 1'b0;
            if (!md[5] || s.obf) s.ip = 1'b0;
          end
        end
      end
      if (pclk_fall && !in_reset && hs_on[p] && !hs_isin[p] && s.obf && s.dsk != 5'd0)
        s.dsk = s.dsk - 5'd1;
      hs_fin[p] = s;
    end
  end
  // verilator lint_on UNUSEDSIGNAL
  // Current count as read: the frozen copy while RCC is set.
  logic [15:0] ct_rd;
  assign ct_rd = regs[REG_CT1CS + 6'(ct_idx)][CT_RCC] ? ct_latch[ct_idx] : ct[ct_idx].cnt;

  logic [7:0] rd_data;
  always_comb begin
    rd_data = 8'h00;
    if (in_reset)
      rd_data = (cyc_reg == REG_MICR) ? 8'h01 : 8'h00;
    else if (cyc_reg == REG_PACS || cyc_reg == REG_PBCS)
      // ORE and IRF: handshake only. An /AS rise in this sample has
      // already updated PMF and IP.
      rd_data = hs_on[cyc_reg[0]]
              ? {reg_cur[7:6], hs_as[cyc_reg[0]].ip, reg_cur[4], hs_as[cyc_reg[0]].ore,
                 hs_as[cyc_reg[0]].irf, hs_as[cyc_reg[0]].pmf, reg_cur[0]}
              : {reg_cur[7:6], reg_cur[CS_IP] | pm_ip_set[cyc_reg[0]], reg_cur[4], 2'b00,
                 pm_pmf_nx[cyc_reg[0]], reg_cur[0]};
    else if (ct_reg)
      rd_data = {reg_cur[7:2], 1'b0, ct_cip[ct_idx]};
    else if (cyc_reg == REG_PAD && hs_on[0])
      rd_data = hs_isin[0] ? hs_as[0].inp : out_a;
    else if (cyc_reg == REG_PBD && hs_on[1])
      rd_data = hs_isin[1] ? hs_as[1].inp : out_b;
    else if (cyc_reg == REG_PAD)
      rd_data = port_read((lpm_valid[0] && regs[REG_PACS][CS_IP] ? lpm_latch[0] : in_a)
                          ^ regs[REG_PAPOL], out_a, regs[REG_PADIR],
                          regs[REG_PAPOL], regs[REG_PAMOD][7:6]);
    else if (cyc_reg == REG_PBD)
      rd_data = port_read((lpm_valid[1] && regs[REG_PBCS][CS_IP] ? lpm_latch[1] : in_b)
                          ^ regs[REG_PBPOL], out_b, regs[REG_PBDIR],
                          regs[REG_PBPOL], regs[REG_PBMOD][7:6]);
    else if (cyc_reg == REG_PCD)                 // D7:D4 read 1
      rd_data = {4'hF, in_c};  // every bit reads its pin
    else if (cyc_reg >= REG_CT1CC && cyc_reg <= REG_CT3CC)
      rd_data = cyc_reg[0] ? ct_rd[7:0] : ct_rd[15:8];
    else if (cyc_reg == REG_CVEC)
      rd_data = mie && src_any ? (regs[REG_MICR][5] ? src_vec(src_idx, 1'b0) : ack_vec) : 8'hFF;
    // A vector register reads with its status while its source requests.
    else if (cyc_reg == 6'h02 && mie && src_req[1])
      rd_data = src_vec(3'd1, 1'b1);
    else if (cyc_reg == 6'h03 && mie && src_req[3])
      rd_data = src_vec(3'd3, 1'b1);
    else if (cyc_reg == 6'h04 && mie && |{src_req[0], src_req[2], src_req[4]})
      rd_data = src_vec(src_req[0] ? 3'd0 : src_req[2] ? 3'd2 : 3'd4, 1'b1);
    else
      rd_data = reg_cur;
  end

  always_ff @(posedge clk) begin
    // Strobe and count-input edges, the counters, the bus latch and a held
    // handshake access run through both resets.
    ds_q <= ds_n;
    as_q <= as_n;
    ct_clk_q <= ct_clk_in;
    for (int i = 0; i < 3; i++)
      if (md_p[i][CTM_ECE] ? ct_clk_q[i] && !ct_clk_in[i] : pclk_fall)
        ct_trig_q[i] <= ct_trig_in[i];
    for (int i = 0; i < 3; i++)
      if (ct_clk_q[i] && !ct_clk_in[i]) ct_gate_q[i] <= ct_gate_in[i];
    if (ct_off) begin
      for (int i = 0; i < 3; i++) begin ct[i] <= '0; ct_latch[i] <= '0; end
      {ct_perr, ct_pre, ct_out1_q} <= '0;
    end else begin
      for (int i = 0; i < 3; i++) begin ct[i] <= ct_nx[i]; ct_latch[i] <= ct_latch_nx[i]; end
      {ct_perr, ct_pre, ct_out1_q} <= {ct_perr_nx, ct_pre_nx, ct_out1_nx};
    end
    for (int p = 0; p < 2; p++) lpm_latch[p] <= lpm_latch_nx[p];
    wait_stall <= wait_nx;

    // The /DS rise floats AD before the /AS latch starts the next cycle:
    // back to back they land in the same sample. A further /DS with no
    // new /AS is ignored.
    if (ds_rise) ad_drive_q <= 1'b0;
    ds_spent <= as_n && (ds_spent || ds_rise);
    if (!as_n) begin
      as_ad       <= ad_in;
      as_intack_n <= intack_n;
      ad_drive_q  <= 1'b0;
    end
    if (hw_reset)  owned <= 1'b0;
    else if (!as_n) owned <= ds_n && !cs0_n && intack_n;

    // A held handshake access completes once its port is ready.
    if (hs_rel) begin
      if (r_w) ad_q <= rd_data;
      else if (cyc_reg == REG_PAD && hs_wr_ok[0])
        out_a <= ad_in;
      else if (cyc_reg == REG_PBD && hs_wr_ok[1])
        out_b <= ad_in;
    end

    if (hw_reset || sw_reset) begin
      for (int p = 0; p < 2; p++) begin pm_s1[p] <= '0; pm_s2[p] <= '0; pm_bits[p] <= '0; pm_frz[p] <= 1'b0; end
      {lpm_valid, pm_perr, int_latch} <= '0;
      for (int p = 0; p < 2; p++) hs_q[p] <= HS_RST[$bits(hs_t)-1:2];
      {hs_drive, hs_mask} <= '0;
      for (int i = 0; i < NREGS; i++) regs[i] <= 8'h00;
      regs[REG_MICR][MICR_RST] <= 1'b1;
      {smp_a, smp_b, smp_c}       <= '0;
      {catch_a, catch_b, catch_c} <= '0;
    end else begin
      // Port inputs: sampled at /AS rises, and on PCLK while /WAIT holds a handshake.
      {smp_a, smp_b, smp_c}       <= {smp_a_nx, smp_b_nx, smp_c_nx};
      {catch_a, catch_b, catch_c} <= {catch_a_nx, catch_b_nx, catch_c_nx};

      // Pattern logic and the /INT request latch, on the /AS clock.
      for (int p = 0; p < 2; p++) begin
        pm_bits[p] <= pm_bits_nx[p];
        if (!regs[REG_PACS + 6'(p)][CS_IP]) pm_frz[p] <= 1'b0;
        regs[REG_PACS + 6'(p)][1] <= hs_on[p] ? hs_fin[p].pmf : pm_pmf_nx[p];
        if (pm_ip_set[p]) regs[REG_PACS + 6'(p)][CS_IP] <= 1'b1;
        if (hs_on[p] && !in_reset) regs[REG_PACS + 6'(p)][CS_IP] <= hs_fin[p].ip;
        hs_q[p] <= hs_fin[p][$bits(hs_t)-1:2];
      end
      {lpm_valid, pm_perr} <= {lpm_valid_nx, pm_perr_nx};
      {hs_drive, hs_mask}  <= {hs_drive_nx, hs_mask_nx};
      if (as_rise) begin
        pm_s1[0] <= in_a;  pm_s2[0] <= pm_s1[0];
        pm_s1[1] <= in_b;  pm_s2[1] <= pm_s1[1];
        if (!in_reset) int_latch <= int_latch_now;  // Low IEI blocks the request
      end

      // Interrupt acknowledge: the highest eligible source goes under
      // service and, unless NV is set, drives its vector. Only a request
      // latched at the acknowledge's /AS takes part.
      if (ds_fall && !as_intack_n && iei && !in_reset && int_latch_now && src_any) begin
        case (src_idx)
          3'd0:    regs[REG_CT3CS][CS_IUS]        <= 1'b1;
          3'd1:    {regs[REG_PACS][CS_IUS], pm_frz[0]} <= 2'b11;
          3'd2:    regs[REG_CT1CS + 6'd1][CS_IUS] <= 1'b1;
          3'd3:    {regs[REG_PBCS][CS_IUS], pm_frz[1]} <= 2'b11;
          default: regs[REG_CT1CS][CS_IUS]        <= 1'b1;
        endcase
        if (!regs[REG_MICR][5]) begin
          ad_q       <= ack_vec;
          ad_drive_q <= 1'b1;
        end
      end

      // CS1 gates only this access.
      if (ds_fall && as_intack_n && cs1 && owned) begin
        if (r_w) begin
          ad_q       <= rd_data;
          ad_drive_q <= 1'b1;
          // Reading a current-count LSB clears that counter's RCC.
          if (!in_reset && cc_lsb) regs[REG_CT1CS + 6'(ct_idx)][CT_RCC] <= 1'b0;
        end else if (in_reset) begin
          if (cyc_reg == REG_MICR) regs[REG_MICR] <= {7'b0, ad_in[MICR_RST]};
        end else if (cyc_reg == REG_PACS || cyc_reg == REG_PBCS) begin
          regs[cyc_reg] <= {port_cs_wr[7:1], ad_in[CS_IOE]};
          if (port_clr_ip) begin
            lpm_valid[cyc_reg[0]] <= 1'b0;
            pm_perr[cyc_reg[0]]   <= 1'b0;
          end
        end else if (ct_reg) begin
          // ERR and CIP read only, TCB write only, RCC set only.
          regs[cyc_reg] <= ct_cs_wr;
        end else if (cyc_reg == REG_PAD) begin
          // A refused handshake write leaves the data register alone.
          if (hs_wr_ok[0]) begin
            out_a   <= ad_in;
            catch_a <= catch_a_nx & ~(~ad_in & regs[REG_PASIO]);
          end
        end else if (cyc_reg == REG_PBD) begin
          if (hs_wr_ok[1]) begin
            out_b   <= ad_in;
            catch_b <= catch_b_nx & ~(~ad_in & regs[REG_PBSIO]);
          end
        end else if (cyc_reg == REG_PCD) begin
          // D7:D4 write-protect D3:D0.
          out_c   <= (out_c & ad_in[7:4]) | (ad_in[3:0] & ~ad_in[7:4]);
          catch_c <= catch_c_nx & ~(~ad_in[3:0] & regs[REG_PCSIO][3:0] & ~ad_in[7:4]);
        end else if (32'(cyc_reg) < NREGS && REG_STORED[cyc_reg]) begin
          regs[cyc_reg] <= ad_in;
        end
      end

      // End of count sets IP after any write to the same register.
      for (int i = 0; i < 3; i++)
        if (!ct_off && ct_ip_set[i]) regs[REG_CT1CS + 6'(i)][CS_IP] <= 1'b1;
    end
  end

  assign ad_out   = ad_q;
  assign ad_drive = ad_drive_q;

  // IEO falls with DLC, any source under service, or a request latched at
  // an acknowledge's /AS. A source that asks later waits for the next /AS:
  // IEO in an acknowledge moves only with /AS and IEI.
  assign int_n    = !int_latch;
  assign ieo      = !regs[REG_MICR][6] && iei && !(|src_ius)
                    && !(!as_intack_n && !in_reset && int_latch);

  // /WAIT asserts only while the CPU accesses the data register of a port
  // that is not ready; REQUEST is the registered hs_drive level.
  logic [3:0] hs_drv, hs_msk;
  always_comb begin
    logic [1:0] reqb;
    logic       w;
    w      = 1'b0;
    hs_drv = hs_drive;
    hs_msk = hs_mask;
    for (int p = 0; p < 2; p++) begin
      reqb = (p == 1 && !hs_tw[p]) ? 2'd3 : 2'd1;
      if (hs_on[p] && (hs_rws[p] == 3'd1 || hs_rws[p] == 3'd3)) begin
        w = wait_stall && owned && !ds_n && cyc_reg == REG_PAD + 6'(p) && !hs_wready[p];
        hs_msk[reqb] = 1'b1;
        hs_drv[reqb] = !w;
      end
      // A pulsed output's DAV pin is the inverted C/T3 output.
      if (hs_on[p] && hs_pl[p] && !hs_isin[p]) hs_drv[p == 0 ? 3 : 1] = !ct[2].out;
    end
  end

  // A disabled port floats; an enabled one drives its output bits through
  // the polarity inverters. Special I/O makes an output bit open-drain: a
  // 1 at the pin floats.
  logic [7:0] pa_lvl, pb_lvl, pb_data;
  logic [3:0] pc_lvl, pc_data;

  // With EOE set a counter/timer output stands in for its port's output
  // bit: C/T 1 PB4, C/T 2 PB0, C/T 3 PC0.
  always_comb begin
    pb_data = out_b;
    pc_data = out_c;
    if (regs[REG_CT1MD][CTM_EOE])     pb_data[4] = ct[0].out;
    if (regs[REG_CT1MD + 1][CTM_EOE]) pb_data[0] = ct[1].out;
    if (regs[REG_CT1MD + 2][CTM_EOE]) pc_data[0] = ct[2].out;
  end

  // A handshake output port drives its Buffer register on every pin and
  // an input port drives none, whatever the direction register says. The
  // handshake's Port C lines override PCDIR but keep Port C's polarity.
  logic [7:0] pa_dir, pb_dir;
  assign pa_dir   = hs_on[0] ? {8{hs_isin[0]}} : regs[REG_PADIR];
  assign pb_dir   = hs_on[1] ? {8{hs_isin[1]}} : regs[REG_PBDIR];
  assign pa_lvl   = (hs_on[0] && !hs_isin[0] ? hs[0].bf_d : out_a) ^ regs[REG_PAPOL];
  assign pb_lvl   = (hs_on[1] && !hs_isin[1] ? hs[1].bf_d : pb_data) ^ regs[REG_PBPOL];
  assign pc_lvl   = pc_data ^ regs[REG_PCPOL][3:0];
  assign pa_out   = pa_lvl;
  assign pb_out   = pb_lvl;
  assign pc_out   = (pc_lvl & ~hs_msk) | ((hs_drv ^ regs[REG_PCPOL][3:0]) & hs_msk);
  assign pa_oe    = regs[REG_MCCR][MCCR_PAE] ? ~pa_dir & ~(regs[REG_PASIO] & pa_lvl) : 8'h00;
  assign pb_oe    = regs[REG_MCCR][MCCR_PBE] ? ~pb_dir & ~(regs[REG_PBSIO] & pb_lvl) : 8'h00;
  // Special I/O makes the handshake lines open-drain too.
  assign pc_oe    = ((regs[REG_MCCR][MCCR_PCE] ? ~regs[REG_PCDIR][3:0] : 4'h0) | hs_msk)
                    & ~(regs[REG_PCSIO][3:0] & pc_out);

  // verilator lint_off UNUSEDSIGNAL
  logic unused_ok;
  assign unused_ok = ^{as_ad[7], cs_new[0], port_cs_wr[0], in_c8[7:4], pb_live[4], pb_live[0],
                       pc_live[7:4], pc_live[0],
                       pcpol_p[7:4], pcsio_p[7:4], pcdir_p[7:4]};
  // verilator lint_on UNUSEDSIGNAL

endmodule

`default_nettype wire
