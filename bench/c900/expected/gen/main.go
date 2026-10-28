// c900expected -- predicted clock counts for bench/c900/asm/kernels.s.
//
// MAINTAINER TOOL, like `make refresh-rtl`: it is the ONE thing in
// bench/c900 that reads outside this repository.  It needs the Z8000 Go
// golden model at ../../../../../z8000/sim -- the same model the k8000 RTL
// is verified against -- and emits ../expected.txt, which IS committed.
//
//	go run .            (from this directory) > ../expected.txt
//
// TWO NUMBERS PER KERNEL, and the difference between them matters:
//
//	pla       cpu.Decode(...).Cycles -- the DECODE-TIME figure, the static
//	          per-instruction constant carried in the decode ROM and taken
//	          from Mar81 sec 6.7.  For the bit-serial classes (MULT, DIV,
//	          shifts, block moves) Mar81 publishes one operand-independent
//	          number and the ROM stores it as a peak; it is metadata, not
//	          a prediction of what the machine does.
//
//	exec      what the model's CPU actually does: the program below is
//	          assembled, run in a flat-RAM Z8002 system with no wait
//	          states, and the clocks between successive instruction
//	          fetches at the loop head are measured in pipeline steady
//	          state.  This is the number the C900 should reproduce, and
//	          the only one with a pin-observable definition.
//
// Where the two disagree the disagreement is printed, because that is
// where hardware is worth asking.  The known ones today: word DIV (ROM
// says 744, a stale mirror of DIVL's peak -- the FSM executes 107, which
// is the Reference Manual p.90 figure), shifts (ROM stores the base, the
// sequencer bills 3 clocks per position), and block moves (ROM stores one
// step).
//
// The kernel bodies below MUST mirror asm/kernels.s.  They are word
// streams rather than parsed from the .s because there is no Z8000
// assembler in this repository; when a kernel changes, change both.
package main

import (
	"fmt"
	"os"
	"sort"

	"z8000/cpu"
	"z8000/system"
	"z8000/zbus"
)

const (
	progAddr = 0x0100 // where every generated program is loaded
	dataAddr = 0x0800 // the block-move / indirect buffers
	stackTop = 0x0700
	kloops   = 1000 // the loop count inside every kernel in kernels.s
	simLoops = 12   // loop count used for the simulated measurement
)

// insn is one instruction: its words, and how many copies the kernel holds.
type insn struct {
	words []uint16
	n     int
}

type kernel struct {
	name    string
	note    string
	save    []insn // PUSH/POP pairs in kernels.s: fixed cost, once per call
	setup   []insn // register loads before the loop
	group   []insn // ONE repetition of the loop body, in program order
	copies  int    // how many times the body repeats it (kernels.s unrolls)
	counter uint16 // register holding the loop count
	perIter int    // copies of the instruction under test per iteration
	// extraSpec: instructions the iteration EXECUTES but that are not laid
	// out inside the loop -- the leaf RET a CALL reaches.  They belong in
	// the published-cycle total; they are not part of the program image.
	extraSpec []insn
	// specOver: published figures that depend on the OPERAND, not just the
	// opcode -- MULTL's 282+7n and LDIR's 11+9n differ between two kernels
	// running the same instruction.  Consulted before the global table.
	specOver map[string]spec
	// specNA: the published figure cannot describe this kernel, so the
	// model-versus-spec difference is not reported as a divergence.
	specNA bool
	caveat string
}

func ldImm(r, v uint16) insn { return insn{[]uint16{0x2100 | r, v}, 1} }
func ldDA(r, a uint16) insn  { return insn{[]uint16{0x6100 | r, a}, 1} }
func pushR(r uint16) insn    { return insn{[]uint16{0x93F0 | r}, 1} }
func popR(r uint16) insn     { return insn{[]uint16{0x97F0 | r}, 1} }
func one(w ...uint16) insn   { return insn{w, 1} }

// saves builds the PUSH/POP block for a register list.
func saves(regs ...uint16) []insn {
	var out []insn
	for _, r := range regs {
		out = append(out, pushR(r))
	}
	for i := len(regs) - 1; i >= 0; i-- {
		out = append(out, popR(regs[i]))
	}
	out = append(out, insn{[]uint16{0x9E08}, 1}) // RET
	return out
}

var kernels = []kernel{
	{
		name: "ldrr", note: "LD R2,R1",
		save: saves(1, 2, 6), setup: []insn{ldImm(1, 1)},
		group: []insn{one(0xA112)}, copies: 10, counter: 6, perIter: 10,
	},
	{
		name: "addrr", note: "ADD R2,R1",
		save: saves(1, 2, 6), setup: []insn{ldImm(1, 1), ldImm(2, 0)},
		group: []insn{one(0x8112)}, copies: 10, counter: 6, perIter: 10,
	},
	{
		name: "ldimm", note: "LD R1,#0x1234",
		save: saves(1, 6), group: []insn{one(0x2101, 0x1234)}, copies: 10,
		counter: 6, perIter: 10,
	},
	{
		name: "nop", note: "NOP",
		save: saves(6), group: []insn{one(0x8D07)}, copies: 10, counter: 6, perIter: 10,
	},
	{
		name: "neglc", note: "NEG R2; LD R1,#0x1234; COM R2",
		save:   saves(1, 2, 6),
		group:  []insn{one(0x8D22), one(0x2101, 0x1234), one(0x8D20)},
		copies: 3, counter: 6, perIter: 3,
		caveat: "look-ahead check.  The published figures are back-to-back\n" +
			"#  throughput: each instruction is a run of machine cycles, each from\n" +
			"#  one bus transaction's start to the next (Fawcett pp.56-58, 67), so\n" +
			"#  a trio is 7+7+7 = 21 and an iteration 73.  If instead a word\n" +
			"#  fetched during NEG's internal clocks were not billed again, the LD\n" +
			"#  would cost 4 and an iteration 64.  ldimm is the control at 80.",
	},
	{
		name: "ldind", note: "LD R2,@R4 -- one data READ",
		save: saves(2, 4, 6), setup: []insn{ldDA(4, dataAddr)},
		group: []insn{one(0x2142)}, copies: 10, counter: 6, perIter: 10,
	},
	{
		name: "stind", note: "LD @R4,R2 -- one data WRITE",
		save: saves(2, 4, 6), setup: []insn{ldDA(4, dataAddr), ldImm(2, 0x55AA)},
		group: []insn{one(0x2F42)}, copies: 10, counter: 6, perIter: 10,
	},
	{
		name: "ldda", note: "LD R2,addr -- direct address",
		save: saves(2, 6), group: []insn{one(0x6102, dataAddr)}, copies: 10,
		counter: 6, perIter: 10,
	},
	{
		name: "sla1", note: "SLA R1,#1",
		save: saves(1, 6), setup: []insn{ldImm(1, 1)},
		group: []insn{one(0xB319, 0x0001)}, copies: 10, counter: 6, perIter: 10,
	},
	{
		name: "sla8", note: "SLA R1,#8",
		save: saves(1, 6), setup: []insn{ldImm(1, 1)},
		group: []insn{one(0xB319, 0x0008)}, copies: 10, counter: 6, perIter: 10,
		caveat: "spec is the ISOLATED cost, 13+3n = 37; exec is THROUGHPUT.  Nine\n" +
			"#  of the ten shifts in an iteration overlap their successor's\n" +
			"#  second-word fetch and cost 34; the tenth follows the loop's JR,\n" +
			"#  which flushed the queue, so it pays the full 37.  9x34 + 37 + 10\n" +
			"#  of loop control = 353, which is what the model executes.  The\n" +
			"#  same arithmetic for sla1 is 9x13 + 16 + 10 = 143.  Hardware\n" +
			"#  showing 353 confirms the overlap is real silicon behaviour;\n" +
			"#  hardware showing 380 (10x37 + 10) says the published figure is\n" +
			"#  the whole cost and our prefetch model is optimistic.",
	},
	{
		name: "sla8w1", note: "SLA R1,#8 then LD R2,R1 -- ONE-word successor",
		save: saves(1, 2, 6), setup: []insn{ldImm(1, 1)},
		group: []insn{one(0xB319, 0x0008), one(0xA112)}, copies: 10, counter: 6, perIter: 10,
		caveat: "THE CONTROL for the shift experiment.  The 3 clocks a shift seems\n" +
			"#  to save are the successor's SECOND WORD being fetched during the\n" +
			"#  shifter's burn; a one-word successor has none to give, and the\n" +
			"#  saving vanishes -- 37 + 3 here against 34 + 34 in sla8.  So spec\n" +
			"#  and exec AGREE on this kernel under both readings, and whatever\n" +
			"#  hardware reads above it is purely what the board adds.",
	},
	{
		name: "mult1", note: "MULT RR2,R1, multiplier 1 (+ reload)",
		save: saves(1, 2, 3, 6), setup: []insn{ldImm(1, 1), ldImm(2, 0)},
		group: []insn{one(0x2103, 0x1234), one(0x9912)}, copies: 10, counter: 6, perIter: 10,
		caveat: "paired with multff.  Same instructions, same bus cycles, only the\n" +
			"#  operands differ, so board overhead cancels in the difference and\n" +
			"#  multff - mult1 must be ZERO if MULT is flat at 70.",
	},
	{
		name: "multff", note: "MULT RR2,R1, 0xFFFF x 0xFFFF (+ reload)",
		save: saves(1, 2, 3, 6), setup: []insn{ldImm(1, 0xFFFF), ldImm(2, 0)},
		group: []insn{one(0x2103, 0xFFFF), one(0x9912)}, copies: 10, counter: 6, perIter: 10,
		caveat: "the fullest multiplicand there is; see mult1.  A spurious per-bit\n" +
			"#  term (a +17n) was a real bug in this model once, which is why the\n" +
			"#  flat figure is worth confirming against silicon rather than\n" +
			"#  assuming.",
	},
	{
		name: "multl3", note: "MULTL RQ0,RR4, multiplicand 0x0007 (n=3)",
		save: saves(0, 1, 2, 3, 4, 5, 6), setup: []insn{ldImm(4, 0), ldImm(5, 1)},
		group:  []insn{one(0x2102, 0x0000), one(0x2103, 0x0007), one(0x9842)},
		copies: 5, counter: 6, perIter: 5,
		specOver: map[string]spec{
			"9842": {303, 282, "RefMan p.141-143: MULTL 282+7n, n=popcount(0x0007)=3"},
		},
		caveat: "paired with multl5 to measure the SLOPE of 282+7n, which is the\n" +
			"#  part a structural model can get wrong.  multl5 - multl3 must be\n" +
			"#  5 copies x 7 x 2 = 70 clocks an iteration; board overhead cancels.",
	},
	{
		name: "multl5", note: "MULTL RQ0,RR4, multiplicand 0x001F (n=5)",
		save: saves(0, 1, 2, 3, 4, 5, 6), setup: []insn{ldImm(4, 0), ldImm(5, 1)},
		group:  []insn{one(0x2102, 0x0000), one(0x2103, 0x001F), one(0x9842)},
		copies: 5, counter: 6, perIter: 5,
		specOver: map[string]spec{
			"9842": {317, 282, "RefMan p.141-143: MULTL 282+7n, n=popcount(0x001F)=5"},
		},
	},
	{
		name: "div", note: "DIV RR2,R1 (+ CLR and a reload)",
		save: saves(1, 2, 3, 6), setup: []insn{ldImm(1, 7)},
		group:  []insn{one(0x8D28), one(0x2103, 0x1234), one(0x9B12)},
		copies: 5, counter: 6, perIter: 5,
		caveat: "THE ONE TO WATCH.  pla says 744 for word DIV -- a stale mirror of\n" +
			"#  DIVL's peak in the decode ROM (sim/cpu/cycle_pla_muldiv.go says so\n" +
			"#  in as many words).  The model's divide FSM executes it in 107,\n" +
			"#  which is the Zilog Reference Manual p.90 figure, so `exec` is the\n" +
			"#  prediction to test.  The FSM is also DATA-DEPENDENT (0x1234/7\n" +
			"#  takes 107 clocks, 0xFFFF/0xFFFF takes 25); Mar81 publishes a\n" +
			"#  single operand-independent number.  Whether a real Z8001 varies\n" +
			"#  with the operands is an open question this kernel cannot answer\n" +
			"#  on its own -- it uses one fixed operand pair -- but a measured\n" +
			"#  107 would confirm the FSM, and a measured 744 would mean the\n" +
			"#  peak is real and the FSM is wrong.",
	},
	{
		name: "divl", note: "DIVL RQ0,RR4 (+ four reloads)",
		save: saves(0, 1, 2, 3, 4, 5, 6), setup: []insn{ldImm(4, 0), ldImm(5, 7)},
		group: []insn{one(0x8D08), one(0x8D18), one(0x2102, 0x0001),
			one(0x2103, 0x2345), one(0x9A42)},
		copies: 3, counter: 6, perIter: 3,
	},
	{
		name: "ldir4", note: "LDIR of 4 words, once per iteration",
		save: saves(3, 4, 6, 7),
		group: []insn{ldDA(4, dataAddr), ldDA(6, dataAddr+512), ldImm(3, 4),
			one(0xBB61, 0x0340)},
		copies: 1, counter: 7, perIter: 1,
		specOver: map[string]spec{
			"BB61 0340": {47, 11, "Mar81 6.7 LDIR 11+9n, n=4"},
		},
		caveat: "the slope partner for ldir64: 60 elements apart, so the published\n" +
			"#  difference is 9 x 60 = 540 clocks an iteration.  On hardware the\n" +
			"#  gap is 540 PLUS 120 memory accesses' worth of wait states, which\n" +
			"#  ldind and stind measure independently -- if the three disagree,\n" +
			"#  a block move's accesses are not ordinary ones.",
	},
	{
		name: "ldir64", note: "LDIR of 64 words, once per iteration",
		save: saves(3, 4, 6, 7),
		group: []insn{ldDA(4, dataAddr), ldDA(6, dataAddr+512), ldImm(3, 64),
			one(0xBB61, 0x0340)},
		copies: 1, counter: 7, perIter: 1,
		caveat: "the published cost is 11 + 9 per element, so 587 for these 64\n" +
			"#  words; the decode ROM carries only the 11 base.  Per-word cost\n" +
			"#  from hardware is (clocks_per_iter - 25 of loads - 10 of loop)/64,\n" +
			"#  which should come out at 9 plus whatever the board adds.",
	},
	{
		name: "pushpop", note: "PUSH @R15,R2 + POP R2,@R15",
		save: saves(2, 6), setup: []insn{ldImm(2, 0x1234)},
		group: []insn{one(0x93F2), one(0x97F2)}, copies: 5, counter: 6, perIter: 5,
		caveat: "the PUSH and POP alternate in kernels.s; here they are grouped,\n" +
			"#  which costs the same but leaves the stack pointer where it began.",
	},
	{
		name: "callret", note: "CALL + RET",
		save: saves(6), group: []insn{one(0x5F00, 0x0000)}, copies: 10, counter: 6, perIter: 10,
		extraSpec: []insn{{[]uint16{0x9E08}, 10}},
		caveat: "the CALL target is patched to a bare RET placed after the loop;\n" +
			"#  the ten RETs it executes are counted in the published total even\n" +
			"#  though they are not laid out inside the loop.",
	},
	{
		name: "jrtaken", note: "JR (always taken)",
		save: saves(6), group: []insn{one(0xE800)}, copies: 10, counter: 6, perIter: 10,
		caveat: "each JR jumps to the next instruction; the displacements are\n" +
			"#  patched when the program is assembled.",
	},
}

// ---- assembling one kernel into a runnable program ----------------------

// bodyOf expands the loop body: `copies` repetitions of the group, in
// program order, exactly as kernels.s unrolls it.
func bodyOf(k kernel) []insn {
	var out []insn
	for i := 0; i < k.copies; i++ {
		out = append(out, k.group...)
	}
	return out
}

func flatten(is []insn) []uint16 {
	var out []uint16
	for _, in := range is {
		for i := 0; i < in.n; i++ {
			out = append(out, in.words...)
		}
	}
	return out
}

// specSum totals the PUBLISHED figures for a sequence, and collects any
// place where the model's decode ROM has drifted from them.
func specSum(is []insn, over map[string]spec) (int, []string, []string) {
	total := 0
	var detail, drift []string
	for _, in := range is {
		sp, rom, agree := specOf(in.words, over)
		total += sp.clocks * in.n
		d := decode(in.words)
		mark := ""
		if sp.clocks != sp.romBase {
			mark = fmt.Sprintf("   (base %d + operand cost)", sp.romBase)
		}
		if !agree {
			mark = fmt.Sprintf("   <-- decode ROM says %d", rom)
			drift = append(drift, fmt.Sprintf("%s: base should be %d, decode ROM carries %d  (%s)",
				key(in.words), sp.romBase, rom, sp.cite))
		}
		detail = append(detail, fmt.Sprintf("#     %-3dx %-12s %-6s %-22s %3d clocks%s",
			in.n, key(in.words)+" ", d.Mnemonic, d.Operands, sp.clocks, mark))
	}
	return total, detail, drift
}

func plaSum(is []insn) (int, []string) {
	total := 0
	var detail []string
	for _, in := range is {
		d := decode(in.words)
		total += d.Cycles * in.n
		hex := ""
		for _, w := range in.words {
			hex += fmt.Sprintf("%04X ", w)
		}
		detail = append(detail, fmt.Sprintf("#     %-3dx %-12s %-6s %-22s %3d clocks",
			in.n, hex, d.Mnemonic, d.Operands, d.Cycles))
	}
	return total, detail
}

// ---- the Zilog figures ---------------------------------------------------
//
// THE SPEC COLUMN IS THIS TABLE, not anything the model computes.  Each
// entry is the published execution time for that instruction, keyed by the
// opcode words the kernels use, with the page it was read from.  The
// generator cross-checks every entry against the model's decode ROM and
// prints a DRIFT line where they disagree -- that is a fault in the model,
// and it is reported, never silently adopted.
//
// Sources, in the k8000/z8000 working set:
//
//	Mar81   Z8000 CPU Technical Manual, sec 6.7 "Instruction Execution Times"
//	RefMan  Z8000 CPU Reference Manual 1982
//
// Both are scanned images in ~/git/z8000 with no text layer, so these
// figures are transcriptions -- from the decode ROM's own citations in
// sim/cpu/decode.go and sim/cpu/cycle_pla_muldiv.go, which were entered
// from those pages.  Anything a reader wants to re-verify goes back to the
// page named here.
type spec struct {
	clocks  int // the published cost FOR THE OPERANDS THIS KERNEL USES
	romBase int // the constant the decode ROM should carry (the base)
	cite    string
}

var zilog = map[string]spec{
	"A112":      {3, 3, "Mar81 6.7 LD R,R"},
	"8112":      {4, 4, "Mar81 6.7 ADD R,R"},
	"2101 1234": {7, 7, "Mar81 6.7 LD R,IM"},
	"2102 0000": {7, 7, "Mar81 6.7 LD R,IM"},
	"2102 0001": {7, 7, "Mar81 6.7 LD R,IM"},
	"2103 1234": {7, 7, "Mar81 6.7 LD R,IM"},
	"2103 2345": {7, 7, "Mar81 6.7 LD R,IM"},
	"2103 6789": {7, 7, "Mar81 6.7 LD R,IM"},
	"2103 0040": {7, 7, "Mar81 6.7 LD R,IM"},
	"2103 0004": {7, 7, "Mar81 6.7 LD R,IM"},
	"2103 0007": {7, 7, "Mar81 6.7 LD R,IM"},
	"2103 001F": {7, 7, "Mar81 6.7 LD R,IM"},
	"2103 FFFF": {7, 7, "Mar81 6.7 LD R,IM"},
	"8D07":      {7, 7, "Mar81 6.7 NOP"},
	"8D20":      {7, 7, "Mar81 6.7 COM R"},
	"8D22":      {7, 7, "Mar81 6.7 NEG R"},
	"8D08":      {7, 7, "Mar81 6.7 CLR R"},
	"8D18":      {7, 7, "Mar81 6.7 CLR R"},
	"8D28":      {7, 7, "Mar81 6.7 CLR R"},
	"2142":      {7, 7, "Mar81 6.7 LD R,IR"},
	"2F42":      {8, 8, "Mar81 6.7 LD IR,R"},
	"6102 0800": {9, 9, "Mar81 6.7 LD R,DA"},
	"6104 0800": {9, 9, "Mar81 6.7 LD R,DA"},
	"6106 0A00": {9, 9, "Mar81 6.7 LD R,DA"},
	// SLA is 13 + 3n, and the 13 is an INTERCEPT, not a flat cost: the 1988
	// data book's ROTATE AND SHIFT table prints the whole formula in the
	// cell, "(13 + 3 n)".  So a shift by 1 costs 16 and a shift by 8 costs
	// 37 in isolation.  The decode ROM carries the 13 intercept.
	//
	// Our CPU executes 13 and 34 -- three clocks less, each -- when the
	// shifts run back to back.  That is not a fault: the successor's
	// second-word fetch hides inside the shift's internal burn, and static
	// shifts are the only instructions that are both multi-word and have a
	// long internal phase, so they are the only place where throughput and
	// isolated cost differ.  Measured in isolation the model produces the
	// published figure exactly, and cycle_audit_test.go has been enforcing
	// that across the whole shift family all along.  See item 4 of
	// z8000/docs/CYCLE_RECONCILIATION_HANDOFF.md.
	"B319 0001": {16, 13, "1988 data book ROTATE AND SHIFT: SLA dst,n = 13+3n, n=1"},
	"B319 0008": {37, 13, "1988 data book ROTATE AND SHIFT: SLA dst,n = 13+3n, n=8"},
	"9912":      {70, 70, "Mar81 6.7 MULT R,R (p.141/142)"},
	// MULTL is NOT flat 282: Zilog gives 282 + 7n, n = the number of set bits
	// in the low 16 of the multiplicand (RefMan p.141-143; the model's own
	// TestArithmeticSpecGap asserts 303 for n=3 and 317 for n=5).  This
	// kernel's multiplicand is 0x00006789 and popcount(0x6789) = 8, so the
	// published cost for THESE operands is 282 + 56 = 338.  The decode ROM
	// correctly carries the 282 base.
	"9842": {338, 282, "Mar81 6.7 / RefMan p.141-143: MULTL 282+7n, n=popcount(0x6789)=8"},
	"9B12": {107, 107, "RefMan p.90 DIV word R -- and the model's own DA=108/X=109 agree with a 107 base"},
	"9A42": {744, 744, "Mar81 6.7 DIVL R,RR (p.87/88)"},
	// LDIR is 11 base + 9 per element (Mar81 6.7, stated in the model's
	// cycle_pla_block.go and asserted for CPIR in TestCycleAuditBlockCompare).
	// This kernel moves 64 words: 11 + 576 = 587.  The ROM carries the 11.
	"BB61 0340": {587, 11, "Mar81 6.7 LDIR 11+9n, n=64"},
	"93F2":      {9, 9, "Mar81 6.7 PUSH IR,R"},
	"97F2":      {8, 8, "Mar81 6.7 POP R,IR"},
	"5F00 0000": {12, 12, "Mar81 6.7 CALL DA"},
	"9E08":      {10, 10, "Mar81 6.7 RET"},
	"E800":      {6, 6, "Mar81 6.7 JR"},
	"AB60":      {4, 4, "Mar81 6.7 DEC R,#n"},
	"AB70":      {4, 4, "Mar81 6.7 DEC R,#n"},
}

func key(w []uint16) string {
	s := ""
	for i, x := range w {
		if i > 0 {
			s += " "
		}
		s += fmt.Sprintf("%04X", x)
	}
	return s
}

// specOf returns the published figure, and whether the decode ROM agrees.
func specOf(w []uint16, over map[string]spec) (spec, int, bool) {
	sp, ok := over[key(w)]
	if !ok {
		sp, ok = zilog[key(w)]
	}
	if !ok {
		panic("no Zilog figure curated for " + key(w) + " -- add it, with its page")
	}
	rom := decode(w).Cycles
	return sp, rom, rom == sp.romBase
}

func decode(w []uint16) cpu.DecodedInsn {
	pad := append(append([]uint16{}, w...), 0, 0, 0)
	return cpu.Decode(pad, progAddr, false) // nonsegmented: see kernels.s header
}

// build lays out: setup, LD counter,#simLoops, LOOP: body, DEC, JR NZ,LOOP,
// NOP, RET-target.  It returns the words and the byte address of LOOP.
func build(k kernel) ([]uint16, uint16) {
	var prog []uint16
	prog = append(prog, 0x210F, stackTop) // LD R15,#stack  (kernels.s inherits one)
	prog = append(prog, flatten(k.setup)...)
	prog = append(prog, 0x2100|k.counter, simLoops)
	loopHead := progAddr + 2*len(prog)

	body := flatten(bodyOf(k))
	switch k.name {
	case "jrtaken":
		// every JR jumps to the following instruction: displacement 0
		for i := range body {
			body[i] = 0xE800
		}
	case "callret":
		// patch the CALL targets once the leaf address is known
	}
	prog = append(prog, body...)
	prog = append(prog, 0xAB00|(k.counter<<4)) // DEC Rc,#1
	// JR NZ,loopHead -- displacement in words from the word after the JR
	after := progAddr + 2*len(prog) + 2
	disp := (int(loopHead) - after) / 2
	prog = append(prog, 0xEE00|uint16(disp&0xFF))
	// HALT where the loop falls out: without it the CPU would return
	// through a stack we never set up and wander off executing whatever
	// it found, re-fetching the loop head at meaningless intervals.
	prog = append(prog, 0x7A00)
	leaf := progAddr + 2*len(prog)
	prog = append(prog, 0x9E08) // the bare RET the callret kernel calls

	if k.name == "callret" {
		for i := 0; i+1 < len(prog); i++ {
			if prog[i] == 0x5F00 && prog[i+1] == 0x0000 {
				prog[i+1] = uint16(leaf)
			}
		}
	}
	return prog, uint16(loopHead)
}

// ---- running it ---------------------------------------------------------

type ifEvent struct {
	clk  uint64
	addr uint16
}

func run(words []uint16, clocks int) []ifEvent {
	sys := system.New(cpu.Z8002)
	ram := sys.AddChip(0, 0x10000, false)
	put := func(addr uint32, v uint16) {
		ram.Data[addr] = byte(v >> 8)
		ram.Data[addr+1] = byte(v)
	}
	put(0x0002, 0x4000) // FCW: system mode, nonsegmented, interrupts off
	put(0x0004, progAddr)
	for i, w := range words {
		put(uint32(progAddr+2*i), w)
	}
	for i := 0; i < 512; i++ { // something for the block move to copy
		put(uint32(dataAddr+2*i), uint16(i))
	}

	var events []ifEvent
	prevAS := true
	clk := uint64(0)
	cpu.TraceHook = func(c *cpu.CPU, in cpu.Inputs, out cpu.Outputs) {
		if in.CLK {
			clk++
			if prevAS && !out.AS_n && out.ADDrive && out.ST == zbus.StatusInstrFetchFirst {
				events = append(events, ifEvent{clk, out.AD})
			}
			prevAS = out.AS_n
		}
	}
	defer func() { cpu.TraceHook = nil }()
	for i := 0; i < clocks; i++ {
		sys.Tick()
	}
	return events
}

// execPerIter measures the steady-state clocks of one loop iteration.
func execPerIter(k kernel, plaIter int) (int, error) {
	prog, loopHead := build(k)
	budget := 4000 + (plaIter+400)*simLoops*4
	ev := run(prog, budget)
	var hits []uint64
	for _, e := range ev {
		if e.addr == loopHead {
			hits = append(hits, e.clk)
		}
	}
	if len(hits) < 4 {
		return 0, fmt.Errorf("%s: only %d loop-head fetches in %d clocks",
			k.name, len(hits), budget)
	}
	// Every iteration must cost the same; take the median of the
	// intervals after the first (which pays the pipeline warm-up) and
	// report a disagreement rather than averaging it away.
	var iv []int
	for i := 2; i < len(hits); i++ {
		iv = append(iv, int(hits[i]-hits[i-1]))
	}
	sort.Ints(iv)
	med := iv[len(iv)/2]
	for _, v := range iv {
		if v != med {
			return med, fmt.Errorf("%s: loop iterations are not uniform: %v", k.name, iv)
		}
	}
	return med, nil
}

func main() {
	if len(os.Args) > 1 {
		dumpKernel(os.Args[1])
		return
	}
	out := os.Stdout
	fmt.Fprint(out, `# expected.txt -- predicted clocks for bench/c900/asm/kernels.s
#
# DERIVED but COMMITTED: regenerate with "go run ." in expected/gen, which
# needs the Z8000 Go golden model.  Two numbers per kernel, and they answer
# different questions:
#
#   spec  what ZILOG published for these instructions.  A hand-curated,
#         per-opcode table inside the generator, each entry carrying the
#         page it came from; the generator cross-checks every entry against
#         the model's decode ROM and prints a DRIFT line where they
#         disagree.  It never takes a figure from the model.
#
#   exec  what the model's CPU actually DOES: this program assembled, run
#         in a flat-RAM Z8002 with no wait states, clocks counted between
#         instruction fetches at the loop head in pipeline steady state.
#
# Where spec and exec differ, one of them is wrong about a real Z8001, and
# the C900 is the tiebreak.  That is the entire point of these kernels: the
# curated cycle table in vectors/k800x_cpu/cycles has no MULT, MULTL, DIV,
# DIVL or block-move record, so nothing in k8000 has ever checked the
# bit-serial classes against the datasheet.
#
# Both columns are IDEAL: no wait states, no DRAM refresh, no interrupts.
# Measured on hardware will exceed both.  Differences BETWEEN kernels
# cancel the per-call overhead and are the trustworthy signal.
#
# Loop count per call in kernels.s: 1000
#
`)
	fmt.Fprintf(out, "\n%-9s %-9s %-10s %-10s %-12s %-12s %s\n",
		"#kernel", "per_iter", "spec_iter", "exec_iter", "spec_call", "exec_call",
		"instruction under test")
	type row struct {
		k                   kernel
		specIter, exec, fix int
		drift               []string
	}
	var rows []row
	var allDrift []string
	for _, k := range kernels {
		specIter, _, drift := specSum(bodyOf(k), k.specOver)
		extra, _, xdrift := specSum(k.extraSpec, k.specOver)
		drift = append(drift, xdrift...)
		specIter += extra + 10 // + DEC and JR NZ, both uncontroversial
		plaIter, _ := plaSum(bodyOf(k))
		exec, err := execPerIter(k, plaIter+10)
		if err != nil {
			fmt.Fprintln(os.Stderr, "c900expected:", err)
			os.Exit(1)
		}
		fixed, _ := plaSum(k.save)
		fixed += mustSum(k.setup)
		rows = append(rows, row{k, specIter, exec, fixed, drift})
		allDrift = append(allDrift, drift...)
		mark := ""
		switch {
		case k.specNA:
			mark = " [no comparable published figure -- see note]"
		case exec != specIter:
			mark = fmt.Sprintf(" [model %+d]", exec-specIter)
		}
		fmt.Fprintf(out, "%-9s %-9d %-10d %-10d %-12d %-12d %s%s\n",
			k.name, k.perIter, specIter, exec,
			fixed+kloops*specIter, fixed+kloops*exec, k.note, mark)
	}

	if len(allDrift) > 0 {
		fmt.Fprint(out, "\n\n# ---- DRIFT: the model's decode ROM disagrees with the published\n")
		fmt.Fprint(out, "# figure for these opcodes.  The spec column above uses the\n")
		fmt.Fprint(out, "# published figure; the ROM constant is a fault to be fixed in the\n")
		fmt.Fprint(out, "# model, not a measurement.\n")
		seen := map[string]bool{}
		for _, d := range allDrift {
			if !seen[d] {
				seen[d] = true
				fmt.Fprintf(out, "#   %s\n", d)
			}
		}
	}

	fmt.Fprint(out, "\n\n# ---- per-kernel detail ---------------------------------------------\n")
	for _, r := range rows {
		k := r.k
		fmt.Fprintf(out, "\n# %s -- %s\n", k.name, k.note)
		if k.caveat != "" {
			fmt.Fprintf(out, "#  NOTE: %s\n", k.caveat)
		}
		_, bd, _ := specSum(bodyOf(k), k.specOver)
		if xd, _, _ := specSum(k.extraSpec, k.specOver); xd > 0 {
			_, xl, _ := specSum(k.extraSpec, k.specOver)
			bd = append(bd, xl...)
		}
		fmt.Fprintf(out, "#   loop body, PUBLISHED figures (%d clocks + 10 of loop control):\n",
			r.specIter-10)
		for _, l := range bd {
			fmt.Fprintln(out, l)
		}
		fmt.Fprintf(out, "#     1  x AB60         DEC    Rc,#1                    4 clocks\n")
		fmt.Fprintf(out, "#     1  x EExx         JR     NZ,loop                  6 clocks\n")
		fmt.Fprintf(out, "#   spec per iteration: %d\n", r.specIter)
		fmt.Fprintf(out, "#   exec per iteration: %d (the model, simulated, steady state)\n", r.exec)
		if r.exec != r.specIter && !k.specNA {
			fmt.Fprintf(out, "#   *** the model runs %+d clocks against the published figure ***\n",
				r.exec-r.specIter)
		}
		fmt.Fprintf(out, "#   save/restore + setup, once per call: %d\n", r.fix)
		fmt.Fprintf(out, "#   per call: spec %d, model %d\n",
			r.fix+kloops*r.specIter, r.fix+kloops*r.exec)
	}
	fmt.Fprint(out, `
# The driver's own per-call cost (the C loop and the CALL that reaches the
# kernel) is NOT included above: it is the same for every kernel and
# cancels in kernel-to-kernel differences.
`)
}

func mustSum(is []insn) int {
	n, _ := plaSum(is)
	return n
}
