// z8000_sequencer -- CPU control: the reset sequence, then instruction flow.
//
// After /RESET rises the CPU waits two clocks; the third edge opens T1 of
// the first Program Status Area read. The reads run back to back with
// ST=1100 in system mode and segment 0: FCW from 0002, then the PC (Z8001:
// segment word from 0004 and offset from 0006; Z8002: 0004). Each read's
// data is loaded at its T3 edge and the next request goes out on the
// following edge.
// SEQ_FETCH is where instruction fetch begins.
//
// Bus requests are a function of state only; `bus_done` and `bus_rdata`
// arrive combinationally and are acted on at the same edge.

module z8000_sequencer
  import z8000_zbus_pkg::*;
#(
  parameter bit SEGMENTED = 1
) (
  input  logic        clk,
  input  logic        reset_n,

  // architectural state
  input  logic        fcw_sys,     // FCW bit 14: system mode
  input  logic [31:0] pc,
  output logic        fcw_we,
  output logic [15:0] fcw_d,
  output logic        pc_we,
  output logic [31:0] pc_d,

  // bus unit
  output logic        bus_req,
  output logic [22:0] bus_addr,
  output logic [15:0] bus_wdata,
  output logic [3:0]  bus_st,
  output logic        bus_write,
  output logic        bus_byte,
  output logic        bus_normal,
  output logic        bus_epu_drives,
  input  logic        bus_ack,
  input  logic        bus_done,
  input  logic [15:0] bus_rdata
);

  typedef enum logic [1:0] {
    SEQ_RESET,      // clocks after /RESET rises
    SEQ_PSA_REQ,    // request the next PSA read
    SEQ_PSA_WAIT,   // read in flight
    SEQ_FETCH
  } seq_state_e;

  typedef enum logic [1:0] {
    PSA_FCW,
    PSA_PC_SEG,
    PSA_PC_OFF
  } psa_word_e;

  seq_state_e state_q, state_d;
  psa_word_e  word_q, word_d;
  logic       wait_q, wait_d;     // second clock after /RESET rises

  // PSA word address, always segment 0, even once the loaded FCW selects
  // nonsegmented mode.
  logic [15:0] psa_off;
  always_comb begin
    unique case (word_q)
      PSA_FCW:    psa_off = 16'h0002;
      PSA_PC_SEG: psa_off = 16'h0004;
      PSA_PC_OFF: psa_off = SEGMENTED ? 16'h0006 : 16'h0004;
      default:    psa_off = 16'h0002;
    endcase
  end

  always_comb begin
    state_d        = state_q;
    word_d         = word_q;
    wait_d         = wait_q;
    fcw_we         = 1'b0;
    fcw_d          = bus_rdata;
    pc_we          = 1'b0;
    pc_d           = pc;
    bus_req        = 1'b0;
    bus_addr       = {7'd0, psa_off};
    bus_wdata      = 16'h0000;
    bus_st         = ST_PROG_SPACE;
    bus_write      = 1'b0;
    bus_byte       = 1'b0;
    // The reset reads run in system mode whatever FCW they load.
    bus_normal     = (state_q == SEQ_FETCH) && !fcw_sys;
    bus_epu_drives = 1'b0;

    unique case (state_q)
      SEQ_RESET: begin
        wait_d = 1'b1;
        if (wait_q) state_d = SEQ_PSA_REQ;
      end

      SEQ_PSA_REQ: begin
        bus_req = 1'b1;
        if (bus_ack) state_d = SEQ_PSA_WAIT;
      end

      SEQ_PSA_WAIT: begin
        if (bus_done) begin
          unique case (word_q)
            PSA_FCW: begin
              fcw_we  = 1'b1;
              word_d  = SEGMENTED ? PSA_PC_SEG : PSA_PC_OFF;
              state_d = SEQ_PSA_REQ;
            end
            PSA_PC_SEG: begin
              pc_we   = 1'b1;
              pc_d    = {9'd0, bus_rdata[14:8], 16'h0000};
              word_d  = PSA_PC_OFF;
              state_d = SEQ_PSA_REQ;
            end
            PSA_PC_OFF: begin
              pc_we   = 1'b1;
              pc_d    = SEGMENTED ? {pc[31:16], bus_rdata} : {16'h0000, bus_rdata};
              state_d = SEQ_FETCH;
            end
            default: state_d = SEQ_FETCH;
          endcase
        end
      end

      SEQ_FETCH: ;

      default: state_d = SEQ_RESET;
    endcase
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q <= SEQ_RESET;
      word_q  <= PSA_FCW;
      wait_q  <= 1'b0;
    end else begin
      state_q <= state_d;
      word_q  <= word_d;
      wait_q  <= wait_d;
    end
  end

endmodule
