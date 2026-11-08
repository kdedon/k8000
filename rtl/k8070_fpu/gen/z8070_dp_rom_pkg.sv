// DERIVED FILE, but a COMMITTED SOURCE of k8000: check it in, review its
// diffs, and build from it. Emitted by cmd/fpuucode from
// rtl/k8070_fpu/z8070_dp_ucode.txt; 'make gen-fpu' overwrites it. Do not
// hand-edit.
//
// z8070_dp_rom_pkg -- the Data Processor microprogram's types: 63 words,
// 23 dispatch entries (the ROM itself is z8070_dp_rom). Routines (tag):
//   unpack   guess     two operands in successive clocks over one bus, each classified then renormalized
//   add      published 18 clocks every precision (the total); the split is a guess; 7 on a special operand and 14 on an exact cancellation are guesses
//   bcdload  guess     27 clocks (24 for a zero, 4 for a non-decimal digit): the container read, the digit check, one x10 shift-add per digit (19), the shared tail without DNRM
//   round    guess     the add path's last five clocks; an integer result is never tiny and skips DNRM
//   compare  guess     11 clocks: the unpack, a magnitude compare on the adders, the relation and code
//   sign     guess     4 clocks: quiet bit operations, the operand passes unchanged but for the sign
//   mul      published 28/42/48 clocks (16 + floor(nS/2) radix-4 steps); the split is a guess; 7 on a special operand is a guess
//   div      published 29/43/49 clocks (17 + floor(nS/2), floor(nS/2) + 2 SRT digits); the split is a guess; 7 on a special operand is a guess
//   bcdstore guess     63 clocks (5 on a special operand): the conversion front end (5), h / 10^19 on the divide's 34 SRT digits and QSEL, one x10 per digit (19), the digits out, the tail
//   rem      guess     17 + floor(n/2) clocks for n quotient bits (29/43/49 a full batch), 12 + floor(n/2) on a zero remainder, 7 on a special operand
//   sqrt     guess     13 + nS clocks (37/66/77), one root bit a clock; 5 on a special operand; the shared tail: LZC's count is fixed by the precision, DNRM shifts only a single or double root of a tiny extended operand
//   fint     guess     11 clocks (8 for a zero integer, 5 on a special operand): the unpack's B half, special select, integer align and round, the shared tail without DNRM
//   itof     guess     7 clocks (4 for a zero): one adder pass reads the integer, the shared tail without DNRM
//   ftoi     guess     8 clocks (5 on a special operand): the unpack's B half, special select, integer align and round, negate and range
//   tail     guess     result latch, then the hand-over

`default_nettype none

package z8070_dp_rom_pkg;

  localparam int UA_W = 6;

  typedef enum logic [5:0] {
    DA_UNPA   = 6'd0, // operand bus to A, classify (exponent field, integer and quiet bits)
    DA_RENA   = 6'd1, // A: leading-zero count, left shift, exponent minus count; DE; zero significand to zero
    DA_UNPB   = 6'd2, // operand bus or a made zero to B, classify, sign flip for a subtract (FABS/FNEG/FCLR: the operand as it is)
    DA_RENB   = 6'd3, // B: as RENA
    DA_SPEC   = 6'd4, // add special operands (NaN, infinity, both zero) resolved into S with flags
    DA_EXPD   = 6'd5, // exponent adder: ea - eb
    DA_SWAP   = 6'd6, // larger exponent to A (a zero operand loses), exponent adder: -d if swapped; effective subtract
    DA_ALGN   = 6'd7, // shifter: B significand right by min(d, 67) into S, sticky collected
    DA_ADD    = 6'd8, // adder: A significand plus or minus S
    DA_NEG    = 6'd9, // adder: 0 - S and sign flip if the subtract went negative
    DA_CRY    = 6'd10, // shifter: S right one with sticky on a carry out; exponent adder: +1
    DA_LZC    = 6'd11, // leading-zero count of S; a zero sum becomes the signed zero of the rounding mode
    DA_NORM   = 6'd12, // shifter: S left by the count; exponent adder: minus the count; the denormalize amount (subnormal scale - exponent)
    DA_DNRM   = 6'd13, // tininess; shifter: denormalize a tiny result by the amount formed at NORM
    DA_RND    = 6'd14, // precision fold into guard and sticky, round decision, adder: increment at the precision LSB
    DA_RNG    = 6'd15, // zero, overflow (infinity or largest finite) and storage form; INX, UN, FOV
    DA_PACK   = 6'd16, // shifter: significand left for storage; result latch loaded
    DA_WB     = 6'd17, // result handed to the register file and the Interface Processor
    DA_SPCC   = 6'd18, // compare: NaN operand to unordered, signaling NaN to NAN
    DA_SIGC   = 6'd19, // adder: A significand - B significand; magnitude relation: exponent, else the borrow and zero
    DA_SREL   = 6'd20, // signed relation: zeros equal, signs, both negative reversed
    DA_CMAP   = 6'd21, // compare code (Table 1); unordered on an X compare: INV, reason 4
    DA_SOP    = 6'd22, // sign unit: B to S with the sign cleared (FABS) or flipped (FNEG), or Normal Zero (FCLR)
    DA_MSPC   = 6'd23, // multiply special operands (NaN, zero times infinity, infinity, zero) resolved into S with flags
    DA_MEXP   = 6'd24, // exponent adder: ea + eb; product sign; shifter: multiplicand left one into S (the accumulator offset)
    DA_M3     = 6'd25, // adder: 2M + M into X (3M, shifted left one); shifter: B right to its top n bits, the rest to sticky; exponent adder: minus the bias; S cleared; step count
    DA_MSTP   = 6'd26, // radix-4 step: S plus 0, M, 2M or 3M by B[1:0], shifted right two, the two low bits into B shifted right two
    DA_PRD    = 6'd27, // product into S: adder adds M for the double's integer bit; guard, round and sticky from B
    DA_DSPC   = 6'd28, // divide special operands (NaN, 0/0, inf/inf, infinity, zero divisor) resolved into S with flags
    DA_DEXP   = 6'd29, // exponent adder: ea - eb; quotient sign
    DA_DLD    = 6'd30, // exponent adder: plus the bias and the precision offset; shifter: dividend right two (double) or three into S; X, QM cleared; step count
    DA_DSTP   = 6'd31, // SRT step: digit from S[67:62] and D[62:60]; adder: 4w minus or plus D or 2D; X takes a positive digit, QM a negative one
    DA_QSEL   = 6'd32, // adder: quotient X - QM, less one on a negative remainder, into S; the remainder's sticky below it (BCD store: the fraction alone, IX on a quotient of one or more)
    DA_RENS   = 6'd33, // remainder: A renormalized into S; A kept as stored
    DA_RSPC   = 6'd34, // remainder special operands (NaN, infinite dividend or zero divisor, infinite divisor, zero dividend) with flags
    DA_RLEN   = 6'd35, // batch length: n - 1, n odd, complete, step count
    DA_RLD    = 6'd36, // exponent adder: e - (n - 1); shifter: dividend right two or three; D to A; X, QM cleared
    DA_CORR   = 6'd37, // remainder: zero ends with a signed zero; negative: adder w + D; remainder flags
    DA_SSPC   = 6'd38, // square root special operands (NaN, zero, negative, infinity) with flags
    DA_SEXP   = 6'd39, // exponent adder: (eb + bias + twice the precision offset) / 2, parity
    DA_SLD    = 6'd40, // shifter: radicand fraction into A; first root bit: root 1, remainder 0 or 1 + f1; step count
    DA_SSTP   = 6'd41, // root step: adder 4 rem + pair - (4 root + 1), or + (4 root + 3) after a negative remainder, root bit into B; shifter: radicand left two
    DA_SRES   = 6'd42, // root into S (shifter: B right one), the extended's leading bit, sticky from the remainder (a negative one exact at -(2 root + 1)) and the radicand left
    DA_FSPC   = 6'd43, // FINT special operands (NaN, infinity, zero) with flags; exponent adder: shift count bias + 63 - eb
    DA_IALN   = 6'd44, // shifter: B right to the integer point into S, sticky collected (none when already an integer: FINT keeps the scale, a conversion overflows)
    DA_IRND   = 6'd45, // round S at its LSB (the integer point): the round clock with the extended fold
    DA_ILD    = 6'd46, // operand bus integer through the adder: 0 - v when negative into S, the sign, exponent bias + 63
    DA_XSPC   = 6'd47, // conversion special operands: NaN (INV, reason 7), infinity (IX), zero; the indefinite integer or the zero container
    DA_IFIN   = 6'd48, // adder: 0 - S when negative; range by width; the indefinite on overflow; IX or INX
    DA_BSPC   = 6'd49, // BCD digit check (a non-decimal digit: QNaN, INV, reason 6); exponent bias + 63; the sign; digit count
    DA_BSTP   = 6'd50, // BCD digit: adder 8 acc + 2 acc + digit (low bits and carry-in) into S; shifter: the digits left four in B
    DA_BLD    = 6'd51, // shifter: integer right three into S (the dividend / 8); B the divisor 10^19; X, QM cleared; step count
    DA_BDIG   = 6'd52, // decimal digit: adder 8 g + 2 g, the integer part a digit; shifter: digits left four in B, the digit in
    DA_BOUT   = 6'd53, // digits (B) to S with the sign; IX or INX
    DA_NOJOB  = 6'd54  // unused address: no work, the operation ends
  } dp_act_e;

  typedef enum logic [1:0] {
    SQ_NEXT  = 2'd0,
    SQ_JMP   = 2'd1,
    SQ_JCOND = 2'd2,
    SQ_RET   = 2'd3
  } dp_seq_e;

  typedef struct packed {
    dp_act_e         act;
    dp_seq_e         seq;
    logic [UA_W-1:0] tgt;
    logic            fin;
  } dp_uw_t;

endpackage

`default_nettype wire
