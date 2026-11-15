#!/usr/bin/env python3
"""Z8070 Data Processor microprogram ROM from rtl/k8070_fpu/z8070_dp_ucode.txt.

Writes rtl/k8070_fpu/gen/z8070_dp_rom_pkg.sv (actions, sequencer codes,
microword type) and rtl/k8070_fpu/gen/z8070_dp_rom.sv (one word per
address in file order, and the entry and body dispatch tables).

usage: gen_dp_rom.py [OUT_ROOT]   (default: the repo root)
"""

import os
import sys

from genlib import Fail, bits_for, repo_root, write_outputs

SRC = "rtl/k8070_fpu/z8070_dp_ucode.txt"
PKG = "rtl/k8070_fpu/gen/z8070_dp_rom_pkg.sv"
ROM = "rtl/k8070_fpu/gen/z8070_dp_rom.sv"
HEADER = "// Generated from z8070_dp_ucode.txt by make gen; do not hand-edit.\n"
SEQ = {"NEXT": 0, "JMP": 1, "JCOND": 2, "RET": 3}


def parse(path):
    acts, words, entries, routines = [], [], [], []
    cur = None
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            fl = line.split("#", 1)[0].split()
            if not fl:
                continue
            rec = fl[0]
            if rec == "act":
                if len(fl) < 3:
                    raise Fail(f"line {n}: act needs a name and a description")
                acts.append((fl[1], " ".join(fl[2:])))
            elif rec == "routine":
                if len(fl) < 3 or fl[2] not in ("published", "guess"):
                    raise Fail(f"line {n}: routine <name> <published|guess> <note>")
                cur = fl[1]
                routines.append((fl[1], fl[2], " ".join(fl[3:])))
            elif rec == "word":
                if cur is None:
                    raise Fail(f"line {n}: word outside a routine")
                if len(fl) < 4:
                    raise Fail(f"line {n}: word <label> <ACT> <seq> [target] [end]")
                w = {"label": fl[1], "act": fl[2], "seq": fl[3], "tgt": "",
                     "end": False, "routine": cur, "line": n}
                rest = fl[4:]
                if w["seq"] in ("JMP", "JCOND"):
                    if not rest:
                        raise Fail(f"line {n}: {w['seq']} needs a target")
                    w["tgt"], rest = rest[0], rest[1:]
                elif w["seq"] not in ("NEXT", "RET"):
                    raise Fail(f"line {n}: unknown seq {w['seq']!r}")
                for r in rest:
                    if r != "end":
                        raise Fail(f"line {n}: unexpected {r!r}")
                    w["end"] = True
                words.append(w)
            elif rec == "entry":
                if len(fl) < 5:
                    raise Fail(f"line {n}: entry <kind> <entry> <body> <name>")
                try:
                    k = int(fl[1], 16)
                except ValueError:
                    k = -1
                if not 0 <= k <= 63:
                    raise Fail(f"line {n}: bad kind {fl[1]!r}")
                entries.append((k, fl[2], fl[3], fl[4]))
            else:
                raise Fail(f"line {n}: unknown record {rec!r}")
    return acts, words, entries, routines


def generate(root):
    acts, words, entries, routines = parse(os.path.join(root, SRC))
    addr = {}
    for i, w in enumerate(words):
        if w["label"] in addr:
            raise Fail(f"line {w['line']}: label {w['label']} twice")
        addr[w["label"]] = i
    act_idx = {a: i for i, (a, _) in enumerate(acts)}
    aw = bits_for(len(words) + 1)
    actw = bits_for(len(acts))
    for w in words:
        if w["act"] not in act_idx:
            raise Fail(f"line {w['line']}: unknown action {w['act']}")
        if w["tgt"] and w["tgt"] not in addr:
            raise Fail(f"line {w['line']}: unknown target {w['tgt']}")
        if not w["end"] and w["seq"] == "NEXT" and addr[w["label"]] == len(words) - 1:
            raise Fail(f"line {w['line']}: last word falls off the end")
    if "NOJOB" not in act_idx:
        raise Fail("no NOJOB action (the unused-address word)")
    if "TAIL" not in addr:
        raise Fail("no TAIL word")
    seen = set()
    for k, first, body, _ in entries:
        if k in seen:
            raise Fail(f"kind {k:02X} twice")
        seen.add(k)
        for l in (first, body):
            if l not in addr:
                raise Fail(f"entry {k:02X}: unknown word {l}")

    p = []
    p.append(HEADER + "//\n")
    p.append(f"// z8070_dp_rom_pkg -- the Data Processor microprogram's types: {len(words)} words,\n")
    p.append(f"// {len(entries)} dispatch entries (the ROM itself is z8070_dp_rom). Routines (tag):\n")
    for name, tag, note in routines:
        p.append(f"//   {name:<8} {tag:<9} {note}\n")
    p.append("\n`default_nettype none\n\npackage z8070_dp_rom_pkg;\n\n")
    p.append(f"  localparam int UA_W = {aw};\n\n")
    p.append(f"  typedef enum logic [{actw - 1}:0] {{\n")
    for i, (name, what) in enumerate(acts):
        sep = " " if i == len(acts) - 1 else ","
        p.append(f"    DA_{name:<6} = {actw}'d{i}{sep} // {what}\n")
    p.append("  } dp_act_e;\n\n")
    p.append("  typedef enum logic [1:0] {\n    SQ_NEXT  = 2'd0,\n    SQ_JMP   = 2'd1,\n"
             "    SQ_JCOND = 2'd2,\n    SQ_RET   = 2'd3\n  } dp_seq_e;\n\n")
    p.append("  typedef struct packed {\n    dp_act_e         act;\n    dp_seq_e         seq;\n"
             "    logic [UA_W-1:0] tgt;\n    logic            fin;\n  } dp_uw_t;\n\n")
    p.append("endpackage\n\n`default_nettype wire\n")
    pkg = "".join(p)

    # Named addresses: the dispatch tables' and the tail.
    used = {"TAIL"}
    for _, first, body, _ in entries:
        used.update((first, body))

    p = []
    p.append(HEADER + "//\n")
    p.append("// z8070_dp_rom -- the Data Processor microprogram ROM in logic: the word\n")
    p.append("// at addr, the entry address of the next operation, and the body\n")
    p.append("// address of the latched operation. Words are numeric {act, seq, tgt,\n")
    p.append("// fin}: Quartus 17.0.2 crashes extracting a ROM from enum-valued words.\n")
    p.append("\n`default_nettype none\n\nmodule z8070_dp_rom\n  import z8070_dp_rom_pkg::*;\n(\n")
    p.append("  input  logic [UA_W-1:0] addr,\n  input  logic [5:0]      kind,        // latched operation\n")
    p.append("  input  logic [5:0]      next_kind,   // operation to start\n")
    p.append(f"  output logic [{actw + 2 + aw}:0]     uw,          // dp_uw_t\n")
    p.append("  output logic [UA_W-1:0] entry,\n  output logic [UA_W-1:0] body\n);\n\n")
    for i, w in enumerate(words):
        if w["label"] in used:
            p.append(f"  localparam logic [UA_W-1:0] UA_{w['label']:<8} = {aw}'d{i};\n")
    p.append("\n  always_comb begin\n    unique case (addr)\n")
    cur = None
    for i, w in enumerate(words):
        if w["routine"] != cur:
            cur = w["routine"]
            p.append(f"      // {cur}\n")
        tgt, tname = (addr[w["tgt"]], w["tgt"]) if w["tgt"] else (0, "-")
        fin, fname = (1, " end") if w["end"] else (0, "")
        v = (f"{{{actw}'d{act_idx[w['act']]:<2}, 2'd{SEQ[w['seq']]}, "
             f"{aw}'d{tgt:<2}, 1'b{fin}}}")
        c = f"{w['label']:<8} {w['act']:<5} {w['seq']:<5} {tname:<7}{fname}"
        a = f"{aw}'d{i}:"
        p.append(f"      {a:<7} uw = {v};  // {c}".rstrip(" ") + "\n")
    p.append(f"      default: uw = {{{actw}'d{act_idx['NOJOB']}, 2'd0, {aw}'d0, 1'b1}};"
             "  // unused: NOJOB, end\n")
    p.append("    endcase\n  end\n\n")
    for out, sel, col in (("entry", "next_kind", 1), ("body", "kind", 2)):
        p.append(f"  always_comb begin\n    unique case ({sel})\n")
        for e in entries:
            p.append(f"      6'h{e[0]:02X}:   {out} = UA_{e[col]};  // {e[3]}\n")
        p.append(f"      default: {out} = UA_TAIL;  // no routine: the tail\n")
        p.append("    endcase\n  end\n\n")
    p.append("endmodule\n\n`default_nettype wire\n")
    return {PKG: pkg, ROM: "".join(p)}


if __name__ == "__main__":
    root = repo_root()
    out = sys.argv[1] if len(sys.argv) > 1 else root
    write_outputs("gen_dp_rom", lambda: generate(root), out)
