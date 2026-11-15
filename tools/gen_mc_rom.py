#!/usr/bin/env python3
"""CPU machine-cycle program ROM from rtl/k800x_cpu/z8000_mc_table.txt.

Writes rtl/k800x_cpu/gen/z8000_mc_pkg.sv (field widths, the entry
programs, the ROM types) and rtl/k800x_cpu/gen/z8000_mc_rom_gen.sv (first
word -> form -> program -> cycles and links).

usage: gen_mc_rom.py [OUT_ROOT]   (default: the repo root)
"""

import os
import sys

from genlib import Fail, bits_for, repo_root, write_outputs

SRC = "rtl/k800x_cpu/z8000_mc_table.txt"
PKG = "rtl/k800x_cpu/gen/z8000_mc_pkg.sv"
ROM = "rtl/k800x_cpu/gen/z8000_mc_rom_gen.sv"
HEADER = ("// Generated from z8000_mc_table.txt by make gen; do not hand-edit.\n"
          "// tb_mc_table proves it against rtl/k800x_cpu/z8000_mc_table.txt.\n")

KINDS = ["F1", "Fn", "Fa", "R", "W", "IO", "EPU", "AF", "I", "IA", "IU"]
KIND_SV = {k: "MC_" + k.upper() for k in KINDS}
COLS = ["NS", "SS", "SL"]
COL_SV = ["MC_COL_NS", "MC_COL_SS", "MC_COL_SL"]
PATHS = ["default", "not_taken", "zero"]
PATH_SV = ["MC_PATH_DEFAULT", "MC_PATH_NOT_TAKEN", "MC_PATH_ZERO"]


def parse(path):
    names = []
    prog_of = {}
    progs = []          # [(texts, [entry tuple])]
    sigs = [None] * 65536
    texts = []          # '#' lines since the last record
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            where = f"{SRC} line {n}"
            s = line.rstrip("\n")
            if s.startswith("# "):
                texts.append(s[2:])
                continue
            fl = s.split("//", 1)[0].split()
            if not fl or fl[0].startswith("#"):
                continue
            rec, a = fl[0], fl[1:]
            if rec == "form":
                body = s.split(None, 2)[2] if len(a) > 1 else ""
                name = body.split("  # ", 1)[0]
                if int(a[0]) != len(names) or not name:
                    raise Fail(f"{where}: forms must be numbered 0, 1, ... with a name")
                names.append(name)
            elif rec == "prog" and len(a) == 4:
                if a[1] not in COLS or a[2] not in PATHS:
                    raise Fail(f"{where}: bad column or path")
                prog_of[int(a[0]), COLS.index(a[1]), PATHS.index(a[2])] = int(a[3])
            elif rec == "cycle" and len(a) == 9:
                pi, pos = int(a[0]), int(a[1])
                if pi == len(progs) and pos == 0:
                    progs.append((texts, []))
                elif pi != len(progs) - 1 or pos != len(progs[-1][1]):
                    raise Fail(f"{where}: cycles must run in program and position order")
                if a[2] not in KINDS:
                    raise Fail(f"{where}: unknown kind {a[2]}")
                e = (a[2],) + tuple(int(x) for x in a[3:])
                if e[5] > 1 or e[6] > 1 or e[1] < 0 or e[2] < 1:
                    raise Fail(f"{where}: bad cycle fields")
                progs[-1][1].append(e)
            elif rec == "range" and len(a) == 4:
                lo, hi, form = int(a[0], 16), int(a[1], 16), int(a[3])
                nibs = range(16) if a[2] == "-" else [int(a[2], 16)]
                for w0 in range(lo, hi + 1):
                    if sigs[w0] is None:
                        sigs[w0] = [None] * 16
                    for k in nibs:
                        if sigs[w0][k] is not None:
                            raise Fail(f"{where}: {w0:04X}/{k:X} mapped twice")
                        sigs[w0][k] = form
            else:
                raise Fail(f"{where}: unknown record")
            texts = []
    nf = len(names)
    po = []
    for fi in range(nf):
        po.append([[None] * 3 for _ in range(3)])
        for c in range(3):
            for p in range(3):
                v = prog_of.get((fi, c, p))
                if v is None or not 0 <= v < len(progs):
                    raise Fail(f"{SRC}: form {fi} {COLS[c]} {PATHS[p]} has no program")
                po[fi][c][p] = v
    for pi, (_, ents) in enumerate(progs):
        for e in ents:
            if e[3] >= len(ents) or e[4] >= len(ents):
                raise Fail(f"{SRC}: program {pi} links past its last entry")
    for w0 in range(65536):
        if sigs[w0] is None or None in sigs[w0]:
            raise Fail(f"{SRC}: first word {w0:04X} has no form")
        if any(f >= nf for f in sigs[w0]):
            raise Fail(f"{SRC}: first word {w0:04X} names an unknown form")
        sigs[w0] = tuple(sigs[w0])
    return names, po, progs, sigs


def group_by(keys):
    order, members = [], {}
    for i, k in enumerate(keys):
        if k not in members:
            order.append(k)
            members[k] = []
        members[k].append(i)
    return order, members


def hex_list(vals, width, digits, ind):
    parts = [f"{width}'h{v:0{digits}X}" for v in vals]
    lines = [", ".join(parts[i:i + 12]) for i in range(0, len(parts), 12)]
    return (",\n" + ind).join(lines)


def depends_on_w1(s):
    return any(v != s[0] for v in s)


def generate(root):
    names, po, progs, sigs = parse(os.path.join(root, SRC))

    def entry_prog(name, col):
        if name not in names:
            raise Fail(f"{SRC}: no form {name}")
        return po[names.index(name)][col][0]

    max_ents = max(len(e) for _, e in progs)
    max_reps = max(x[2] for _, e in progs for x in e)
    max_clocks = max(x[1] for _, e in progs for x in e)
    fw, pw = bits_for(len(names)), bits_for(len(progs))
    posw, repsw, clkw = bits_for(max_ents), bits_for(max_reps + 1), bits_for(max_clocks + 1)

    pkg = HEADER + f"""//
// z8000_mc_pkg: machine-cycle program ROM types. A program is a list of
// entries. An entry is one machine cycle (mc_cycle_t), and how the program
// goes on after it (mc_link_t): how many times the cycle runs in a row,
// the position that follows when the datapath asks for another repetition
// (next_more) and when it does not (next_done), and whether the program
// ends after it (fin_more, fin_done).

package z8000_mc_pkg;

  localparam int MC_FORM_W   = {fw};
  localparam int MC_PROG_W   = {pw};
  localparam int MC_POS_W    = {posw};
  localparam int MC_REPS_W   = {repsw};
  localparam int MC_CLOCKS_W = {clkw};

  // The trap and interrupt entry programs, nonsegmented and segmented.
  localparam int MC_PROG_TRAP_NS  = {entry_prog("(trap entry)", 0)};
  localparam int MC_PROG_TRAP_SEG = {entry_prog("(trap entry)", 1)};
  localparam int MC_PROG_INT_NS   = {entry_prog("(interrupt entry)", 0)};
  localparam int MC_PROG_INT_SEG  = {entry_prog("(interrupt entry)", 1)};

  // F1 first instruction word, FN later word, FA address word, R/W memory
  // read/write, IO, EPU transfer, AF aborted fetch, I internal operation,
  // IA interrupt acknowledge, IU internal operations ended by the serial
  // unit, repeated until its last.
  typedef enum logic [3:0] {{
    {", ".join(KIND_SV[k] for k in KINDS)}
  }} mc_kind_e;

  typedef enum logic [1:0] {{
    {", ".join(COL_SV)}
  }} mc_col_e;

  typedef enum logic [1:0] {{
    {", ".join(PATH_SV)}
  }} mc_path_e;

  typedef struct packed {{
    mc_kind_e               kind;
    logic [MC_CLOCKS_W-1:0] clocks;     // bus cycle: tail; internal: length
  }} mc_cycle_t;

  typedef struct packed {{
    logic [MC_REPS_W-1:0]   reps;
    logic [MC_POS_W-1:0]    next_more;
    logic [MC_POS_W-1:0]    next_done;
    logic                   fin_more;
    logic                   fin_done;
  }} mc_link_t;

endpackage
"""

    w = [HEADER]
    w.append("""//
// The machine-cycle program ROM: which program a first word runs, and its
// cycles. Readable form, with every form's programs: z8000_mc_table.txt.

`default_nettype none

// z8000_mc_index_gen: (w0, w1[3:0]) -> form. Only a block form depends on
// the second word (single or repeat); 0 before that word is in.
module z8000_mc_index_gen
  import z8000_mc_pkg::*;
(
  input  logic [15:0]          w0,
  input  logic [3:0]           w1_lo,
  output logic [MC_FORM_W-1:0] form
);

  always_comb begin
    form = MC_FORM_W'(0);
    unique case (w0[15:8])
""")

    def form_lit(f):
        return f"{fw}'d{f}"

    def w1case(s, ind):
        order, m = group_by(s)
        w.append(f"{ind}unique case (w1_lo)\n")
        for i, f in enumerate(order):
            if i == len(order) - 1:
                w.append(f"{ind}  default: form = {form_lit(f)};\n")
            else:
                w.append(f"{ind}  {hex_list(m[f], 4, 1, ind + '  ')}: form = {form_lit(f)};\n")
        w.append(f"{ind}endcase\n")

    def lo_arm(k):
        if depends_on_w1(k):
            w.append("\n")
            w1case(k, "            ")
        else:
            w.append(f" form = {form_lit(k[0])};\n")

    for hi in range(256):
        order, m = group_by(sigs[hi << 8:(hi + 1) << 8])
        if len(order) == 1 and not depends_on_w1(order[0]):
            if order[0][0] != 0:
                w.append(f"      8'h{hi:02X}: form = {form_lit(order[0][0])};\n")
            continue
        w.append(f"      8'h{hi:02X}: begin\n        unique case (w0[7:0])\n")
        big = 0
        for i, k in enumerate(order):
            if len(m[k]) > len(m[order[big]]):
                big = i
        for i, k in enumerate(order):
            if i != big:
                w.append(f"          {hex_list(m[k], 8, 2, '          ')}:")
                lo_arm(k)
        w.append("          default:")
        lo_arm(order[big])
        w.append("        endcase\n      end\n")

    w.append("""      default: ;
    endcase
  end

endmodule

// z8000_mc_prog_gen: (form, column, path) -> program. A path a form does
// not take gives its default program.
module z8000_mc_prog_gen
  import z8000_mc_pkg::*;
(
  input  logic [MC_FORM_W-1:0] form,
  input  mc_col_e              col,
  input  mc_path_e             path,
  output logic [MC_PROG_W-1:0] prog
);

  always_comb begin
    prog = MC_PROG_W'(0);
    unique case (form)
""")

    def prog_lit(p):
        return f"{pw}'d{p}"

    for fi, f in enumerate(po):
        if all(f[c][p] == f[0][0] for c in range(3) for p in range(3)):
            if f[0][0] != 0:
                w.append(f"      {form_lit(fi)}: prog = {prog_lit(f[0][0])};  // {names[fi]}\n")
            continue
        w.append(f"      {form_lit(fi)}: begin  // {names[fi]}\n        unique case (col)\n")
        ind = "            "
        for c in (1, 2, 0):
            w.append(f"          {COL_SV[c]}:" if c else "          default:")
            if f[c][1] == f[c][0] and f[c][2] == f[c][0]:
                w.append(f" prog = {prog_lit(f[c][0])};\n")
                continue
            w.append(f"\n{ind}unique case (path)\n")
            for p in (1, 2):
                w.append(f"{ind}  {PATH_SV[p]}: prog = {prog_lit(f[c][p])};\n")
            w.append(f"{ind}  default: prog = {prog_lit(f[c][0])};\n{ind}endcase\n")
        w.append("        endcase\n      end\n")

    w.append("""      default: ;
    endcase
  end

endmodule

// z8000_mc_cycle_gen: (program, position) -> cycle.
module z8000_mc_cycle_gen
  import z8000_mc_pkg::*;
(
  input  logic [MC_PROG_W-1:0] prog,
  input  logic [MC_POS_W-1:0]  pos,
  output mc_cycle_t            cyc
);

  always_comb begin
    cyc = mc_cycle_t'(0);
    unique case (prog)
""")

    def entries(body):
        for pi, (texts, ents) in enumerate(progs):
            w.append(f"      {prog_lit(pi)}: begin  // {' / '.join(texts)}\n        unique case (pos)\n")
            for ei, e in enumerate(ents):
                w.append(f"          {posw}'d{ei}: {body(e)};\n")
            w.append("          default: ;\n        endcase\n      end\n")
        w.append("      default: ;\n    endcase\n  end\n\nendmodule\n")

    entries(lambda e: f"cyc = '{{kind: {KIND_SV[e[0]]}, clocks: {clkw}'d{e[1]}}}")
    w.append("""
// z8000_mc_link_gen: (program, position) -> how the program goes on.
module z8000_mc_link_gen
  import z8000_mc_pkg::*;
(
  input  logic [MC_PROG_W-1:0] prog,
  input  logic [MC_POS_W-1:0]  pos,
  output mc_link_t             link
);

  always_comb begin
    link = mc_link_t'(0);
    unique case (prog)
""")
    entries(lambda e: f"link = '{{reps: {repsw}'d{e[2]}, next_more: {posw}'d{e[3]}, "
                      f"next_done: {posw}'d{e[4]}, fin_more: 1'b{e[5]}, fin_done: 1'b{e[6]}}}")
    w.append("\n`default_nettype wire\n")
    return {PKG: pkg, ROM: "".join(w)}


if __name__ == "__main__":
    root = repo_root()
    out = sys.argv[1] if len(sys.argv) > 1 else root
    write_outputs("gen_mc_rom", lambda: generate(root), out)
