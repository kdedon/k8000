// z8000_bus_unit -- Z-Bus machine cycles and the bus pins.
//
// A machine cycle is one transaction plus its tail, or one internal
// operation. The pins are registers: each rising edge updates them as below
// (values just after the edge).
//
//   T1   /AS Low, address and status driven; /DS /MREQ High
//   T2   /AS High; /MREQ Low (memory, refresh); read: /DS Low, AD
//        released; write: data on AD
//   TAW  automatic waits: one for I/O (/DS falls), five for an
//        acknowledge (/DS falls at the fourth)
//   T3   /WAIT sampled; Low holds the cycle here as a TW. A write's /DS
//        falls on the first post-T2 edge. Read data is taken at this edge
//        and `done` is raised in the same clock.
//   next /DS /MREQ (and write data) released: the strobe trail. If the
//        next machine cycle opens on this edge its T1 overrides the release.
//   tail `tail` more clocks after the T3 clock, given by the requester
//        during that clock. /AS /DS /MREQ High, AD released; ST, N/S, R/W,
//        B/W and SN hold.
//
// An internal operation (ST=0000) is `len` clocks, 3 to 8: an /AS pulse
// with `req_addr` on AD, then AD released. /DS and /MREQ stay High, /WAIT
// is ignored, N/S and SN hold.
//
// /WAIT is specified at the T2 falling edge; with outputs changing only on
// rising edges, that sample is the edge that would open T3.
//
// One requester. A request is taken on the edge that ends the machine
// cycle in flight (`cyc_end`), or on any edge while idle; it holds until
// then. A refresh (ST=0001) keeps R/W, B/W and N/S from the previous
// cycle. `done`, `rdata`, `cyc_end` and `cyc_end3` are combinational.

module z8000_bus_unit
  import z8000_zbus_pkg::*;
#(
  parameter bit SEGMENTED = 1
) (
  input  logic        clk,
  input  logic        reset_n,

  // the next machine cycle, held until taken
  input  logic        req,
  input  logic        req_internal,   // internal operation, else a transaction
  input  logic [22:0] req_addr,       // seg[22:16]:offset[15:0]
  input  logic [15:0] req_wdata,
  input  logic [3:0]  req_st,
  input  logic        req_write,
  input  logic        req_byte,
  input  logic        req_odd,        // a byte write's address bit 0, ahead of the address select
  input  logic        req_epu_drives, // the EPU supplies the write data
  input  logic        req_normal,     // N/S for the cycle (1 = normal)
  input  logic [3:0]  req_len,        // internal operation length
  input  logic [2:0]  tail,           // read in a transaction's T3 clock

  output logic        cyc_end,        // the next edge ends the machine cycle
  output logic        cyc_end3,       // ... the third edge from now does
  output logic        done,           // T3 opens on this edge
  output logic        twait,          // this clock is a wait state
  output logic [15:0] rdata,          // read data, valid with done

  // pins
  input  logic        wait_n,
  input  logic [15:0] ad_in,
  output logic [15:0] ad_out,
  output logic        ad_drive,
  output logic [6:0]  sn,
  output logic        as_n,
  output logic        ds_n,
  output logic        mreq_n,
  output logic        r_w,
  output logic        b_w,
  output logic        n_s,
  output logic [3:0]  st
);

  // T2, TAW and T3 name the clock the next edge opens; T3CLK, HOLD and IDLE
  // the clock now running.
  typedef enum logic [2:0] {
    BUS_IDLE,
    BUS_T2,
    BUS_TAW,
    BUS_T3,
    BUS_T3CLK,        // a transaction's T3 clock
    BUS_HOLD          // a tail, or an internal operation after its T1
  } bus_state_e;

  bus_state_e  state_q, state_d;
  logic        trail_q, trail_d;     // /DS /MREQ still Low from the last T3
  logic [2:0]  taw_q, taw_d;         // automatic waits left
  logic [3:0]  rest_q, rest_d;       // HOLD clocks after this one
  logic [3:0]  cyc_st_q, cyc_st_d;   // status of the cycle in flight
  logic        cyc_write_q, cyc_write_d;
  logic        cyc_epu_q, cyc_epu_d;
  logic [15:0] cyc_wdata_q, cyc_wdata_d;

  logic [15:0] ad_out_d;
  logic        ad_drive_d, as_n_d, ds_n_d, mreq_n_d, r_w_d, b_w_d, n_s_d;
  logic [6:0]  sn_d;
  logic [3:0]  st_d;

  // ---- machine-cycle boundary -------------------------------------------------
  always_comb begin
    unique case (state_q)
      BUS_IDLE:  cyc_end = 1'b1;
      BUS_T3CLK: cyc_end = tail == 3'd0;
      BUS_HOLD:  cyc_end = rest_q == 4'd0;
      default:   cyc_end = 1'b0;
    endcase
  end

  always_comb begin
    unique case (state_q)
      BUS_T3CLK: cyc_end3 = tail == 3'd2;
      BUS_HOLD:  cyc_end3 = rest_q == 4'd2;
      default:   cyc_end3 = 1'b0;
    endcase
  end

  logic start, start_txn, start_iop;
  assign start     = req && cyc_end;
  assign start_txn = start && !req_internal;
  assign start_iop = start && req_internal;

  // ---- the transaction to start -------------------------------------------------
  logic req_io, req_refresh, cyc_io, cyc_ack, cyc_epux, cyc_refresh;
  assign req_io      = req_st == ST_IO || req_st == ST_SPECIAL_IO;
  assign req_refresh = req_st == ST_REFRESH;
  assign cyc_io      = cyc_st_q == ST_IO || cyc_st_q == ST_SPECIAL_IO;
  assign cyc_ack     = cyc_st_q[3:2] == 2'b01;
  assign cyc_epux    = cyc_st_q == ST_EPU_TRANSFER;
  assign cyc_refresh = cyc_st_q == ST_REFRESH;

  // A memory byte write carries the byte on both halves; the memory picks
  // the lane from A0. I/O byte lanes are architectural and pass through.
  logic [7:0]  wbyte;
  logic [15:0] wdata_bus;
  assign wbyte     = req_odd ? req_wdata[7:0] : req_wdata[15:8];
  assign wdata_bus = (req_write && req_byte && !req_io) ? {wbyte, wbyte} : req_wdata;

  assign done  = state_q == BUS_T3 && wait_n;
  assign twait = state_q == BUS_T3 && !wait_n;
  assign rdata = ad_in;

  logic [2:0] taw_dec;
  assign taw_dec = taw_q - 3'd1;

  // ---- cycle state ------------------------------------------------------------------
  always_comb begin
    state_d     = state_q;
    taw_d       = taw_q;
    rest_d      = rest_q;
    cyc_st_d    = cyc_st_q;
    cyc_write_d = cyc_write_q;
    cyc_epu_d   = cyc_epu_q;
    cyc_wdata_d = cyc_wdata_q;
    if (start_txn) begin
      cyc_st_d    = req_st;
      cyc_write_d = req_write;
      cyc_epu_d   = req_epu_drives;
      cyc_wdata_d = wdata_bus;
      state_d     = BUS_T2;
    end else if (start_iop) begin
      rest_d  = req_len - 4'd1;
      state_d = BUS_HOLD;
    end else begin
      unique case (state_q)
        BUS_IDLE: ;
        BUS_T2: begin
          if (cyc_ack) begin
            taw_d   = 3'd5;
            state_d = BUS_TAW;
          end else if (cyc_io) begin
            taw_d   = 3'd1;
            state_d = BUS_TAW;
          end else begin
            state_d = BUS_T3;
          end
        end
        BUS_TAW: begin
          // An external wait delays the acknowledge string. I/O samples
          // /WAIT only mid-TWA, in BUS_T3 (Fig 9-5).
          if (wait_n || !cyc_ack) begin
            taw_d = taw_dec;
            if (taw_dec == 3'd0) state_d = BUS_T3;
          end
        end
        BUS_T3:    if (wait_n) state_d = BUS_T3CLK;
        BUS_T3CLK: begin
          rest_d  = {1'b0, tail} - 4'd1;
          state_d = (tail == 3'd0) ? BUS_IDLE : BUS_HOLD;
        end
        BUS_HOLD: begin
          rest_d = rest_q - 4'd1;
          if (rest_q == 4'd0) state_d = BUS_IDLE;
        end
        default: state_d = BUS_IDLE;
      endcase
    end
  end

  // ---- pins -----------------------------------------------------------------------------
  always_comb begin
    trail_d    = trail_q;
    ad_out_d   = ad_out;
    ad_drive_d = ad_drive;
    sn_d       = sn;
    as_n_d     = as_n;
    ds_n_d     = ds_n;
    mreq_n_d   = mreq_n;
    r_w_d      = r_w;
    b_w_d      = b_w;
    n_s_d      = n_s;
    st_d       = st;

    if (trail_q) begin
      ds_n_d     = 1'b1;
      mreq_n_d   = 1'b1;
      ad_drive_d = 1'b0;
      trail_d    = 1'b0;
    end

    if (start_txn) begin
      ad_out_d   = req_addr[15:0];
      ad_drive_d = 1'b1;
      as_n_d     = 1'b0;
      ds_n_d     = 1'b1;
      mreq_n_d   = 1'b1;
      st_d       = req_st;
      sn_d       = SEGMENTED ? req_addr[22:16] : 7'd0;
      if (!req_refresh) begin
        r_w_d = !req_write;
        b_w_d = req_byte;
        n_s_d = req_normal && !req_io;
      end
    end else if (start_iop) begin
      ad_out_d   = req_addr[15:0];
      ad_drive_d = 1'b1;
      as_n_d     = 1'b0;
      ds_n_d     = 1'b1;
      mreq_n_d   = 1'b1;
      st_d       = ST_INTERNAL_OP;
      r_w_d      = 1'b1;
      b_w_d      = 1'b0;
    end else begin
      unique case (state_q)
        BUS_T2: begin
          as_n_d   = 1'b1;
          mreq_n_d = cyc_io || cyc_ack || cyc_epux;
          if (!cyc_refresh && !cyc_ack && !cyc_io && !cyc_write_q)
            ds_n_d = 1'b0;
          if (cyc_write_q && !cyc_epu_q) begin
            ad_out_d   = cyc_wdata_q;
            ad_drive_d = 1'b1;
          end else begin
            ad_drive_d = 1'b0;
          end
        end
        BUS_TAW: begin
          if (!cyc_ack || (wait_n && taw_dec <= 3'd1))
            ds_n_d = 1'b0;
        end
        BUS_T3: begin
          if (cyc_write_q && !cyc_refresh && !cyc_io)
            ds_n_d = 1'b0;
          if (wait_n) begin
            if (!cyc_write_q)
              ad_drive_d = 1'b0;
            trail_d = 1'b1;
          end
        end
        BUS_HOLD: begin
          as_n_d     = 1'b1;
          ad_drive_d = 1'b0;
        end
        default: ;
      endcase
    end
  end

  // Reset values are the reset pin state: AD floated (and High), strobes
  // High, SN Low, ST 1111, N/S system.
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q     <= BUS_IDLE;
      taw_q       <= 3'd0;
      rest_q      <= 4'd0;
      cyc_st_q    <= 4'b1111;
      cyc_write_q <= 1'b0;
      cyc_epu_q   <= 1'b0;
      cyc_wdata_q <= 16'h0000;
    end else begin
      state_q     <= state_d;
      taw_q       <= taw_d;
      rest_q      <= rest_d;
      cyc_st_q    <= cyc_st_d;
      cyc_write_q <= cyc_write_d;
      cyc_epu_q   <= cyc_epu_d;
      cyc_wdata_q <= cyc_wdata_d;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      trail_q  <= 1'b0;
      ad_out   <= 16'hFFFF;
      ad_drive <= 1'b0;
      sn       <= 7'd0;
      as_n     <= 1'b1;
      ds_n     <= 1'b1;
      mreq_n   <= 1'b1;
      r_w      <= 1'b1;
      b_w      <= 1'b0;
      n_s      <= 1'b0;
      st       <= 4'b1111;
    end else begin
      trail_q  <= trail_d;
      ad_out   <= ad_out_d;
      ad_drive <= ad_drive_d;
      sn       <= sn_d;
      as_n     <= as_n_d;
      ds_n     <= ds_n_d;
      mreq_n   <= mreq_n_d;
      r_w      <= r_w_d;
      b_w      <= b_w_d;
      n_s      <= n_s_d;
      st       <= st_d;
    end
  end

endmodule
