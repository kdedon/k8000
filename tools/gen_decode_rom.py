#!/usr/bin/env python3
"""CPU decode ROM from rtl/k800x_cpu/z8000_decode_table.txt.

Writes rtl/k800x_cpu/gen/z8000_decode_rom_gen.sv. The control word layout
and the field value names come from the hand-maintained
rtl/k800x_cpu/gen/z8000_ctrl_pkg.sv; each control word's symbolic field
line in the table must re-pack to its hex.

usage: gen_decode_rom.py [OUT_ROOT]   (default: the repo root)
"""

import os
import re
import sys

from genlib import Fail, repo_root, write_outputs

SRC = "rtl/k800x_cpu/z8000_decode_table.txt"
PKG = "rtl/k800x_cpu/gen/z8000_ctrl_pkg.sv"
OUT = "rtl/k800x_cpu/gen/z8000_decode_rom_gen.sv"
HEADER = ("// Generated from z8000_decode_table.txt by make gen; do not hand-edit.\n"
          "// tb_decode proves it against vectors/k800x_cpu/decode/decode.vec.\n")


def parse_pkg(path):
    """CTRL_W, the struct fields MSB first as (name, width, lsb), and every
    sized localparam as name -> (width, value)."""
    text = open(path, encoding="utf-8").read()
    m = re.search(r"localparam int CTRL_W = (\d+);", text)
    if not m:
        raise Fail(f"{PKG}: no CTRL_W")
    total = int(m.group(1))
    m = re.search(r"typedef struct packed \{(.*?)\} ctrl_word_t;", text, re.S)
    if not m:
        raise Fail(f"{PKG}: no ctrl_word_t")
    fields = []
    for fm in re.finditer(r"^\s*logic\s*(?:\[(\d+):0\])?\s+(\w+);", m.group(1), re.M):
        fields.append((fm.group(2), int(fm.group(1)) + 1 if fm.group(1) else 1))
    if sum(w for _, w in fields) != total:
        raise Fail(f"{PKG}: ctrl_word_t is not CTRL_W = {total} bits")
    laid, pos = [], total
    for name, w in fields:
        pos -= w
        laid.append((name, w, pos))
    consts = {}
    for cm in re.finditer(r"localparam logic \[(\d+):0\] (\w+) = \d+'([dhb])([0-9a-fA-F_]+);", text):
        base = {"d": 10, "h": 16, "b": 2}[cm.group(3)]
        consts[cm.group(2)] = (int(cm.group(1)) + 1, int(cm.group(4).replace("_", ""), base))
    return total, laid, consts


def pack_fields(text, fields, consts, where):
    """Re-pack a symbolic field list."""
    if text == "(all fields zero)":
        return 0
    by_name = {n: (w, lsb) for n, w, lsb in fields}
    v = 0
    for tok in text.split():
        name, eq, val = tok.partition("=")
        if not eq or name not in by_name:
            raise Fail(f"{where}: bad field {tok!r}")
        w, lsb = by_name[name]
        if val.isdigit():
            x = int(val)
        elif val in consts and consts[val][0] == w:
            x = consts[val][1]
        else:
            raise Fail(f"{where}: {val} is not a {w}-bit value of z8000_ctrl_pkg")
        if x >> w:
            raise Fail(f"{where}: {name}={val} overflows {w} bits")
        v |= x << lsb
    return v


def parse_table(path, total, fields, consts):
    words = {}
    tbl = [None] * 65536
    pending = None
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            where = f"{SRC} line {n}"
            if pending is not None:
                name, val = pending
                pending = None
                if not line.startswith("#    "):
                    raise Fail(f"{where}: ctrl {name} needs its '#    <fields>' line")
                if pack_fields(line[5:].strip(), fields, consts, where) != val:
                    raise Fail(f"{where}: fields of {name} do not pack to its hex")
                continue
            fl = line.split("//", 1)[0].split("#", 1)[0].split()
            if not fl:
                continue
            if fl[0] == "ctrl" and len(fl) == 3:
                val = int(fl[2], 16)
                if val >> total or fl[1] in words:
                    raise Fail(f"{where}: bad or repeated ctrl {fl[1]}")
                words[fl[1]] = val
                pending = (fl[1], val)
            elif fl[0] == "range" and len(fl) == 4:
                lo, hi = int(fl[1], 16), int(fl[2], 16)
                if fl[3] not in words:
                    raise Fail(f"{where}: unknown ctrl {fl[3]}")
                for w0 in range(lo, hi + 1):
                    if tbl[w0] is not None:
                        raise Fail(f"{where}: {w0:04X} decoded twice")
                    tbl[w0] = words[fl[3]]
            elif fl == ["END"]:
                break
            else:
                raise Fail(f"{where}: unknown record")
    if None in tbl:
        raise Fail(f"{SRC}: {tbl.index(None):04X} has no range")
    return tbl


def group(keys):
    """Distinct keys in first-seen order, stably sorted largest group first,
    with the indices of each."""
    order, members = [], {}
    for i, k in enumerate(keys):
        if k not in members:
            order.append(k)
            members[k] = []
        members[k].append(i)
    order.sort(key=lambda k: -len(members[k]))
    return order, members


def wrap_labels(labels):
    out = []
    for i, l in enumerate(labels):
        if i > 0:
            out.append(", ")
            if i % 12 == 0:
                out.append("\n          ")
        out.append(l)
    return "".join(out)


def generate(root):
    total, fields, consts = parse_pkg(os.path.join(root, PKG))
    tbl = parse_table(os.path.join(root, SRC), total, fields, consts)
    digits = (total + 3) // 4

    def lit(v):
        return f"ctrl_word_t'({total}'h{v:0{digits}x})"

    p = [HEADER]
    p.append("""//
// z8000_decode_rom_gen: reference decode ROM, f(w0[15:0]) -> ctrl.
// Case on the high byte, then (where it matters) on the low byte.
// Synthesis minimizes the constant tables.

`default_nettype none

module z8000_decode_rom_gen
  import z8000_ctrl_pkg::*;
(
  input  logic [15:0] w0,      // instruction first word
  output ctrl_word_t  ctrl
);

  localparam int W = CTRL_W;

  always_comb begin
    ctrl = ctrl_word_t'(W'(0));
    case (w0[15:8])
""")
    for hi in range(256):
        texts = [f"ctrl = {lit(tbl[hi << 8 | lo])};" for lo in range(256)]
        order, members = group(texts)
        if len(order) == 1:
            p.append(f"      8'h{hi:02X}: {order[0]}\n")
            continue
        p.append(f"      8'h{hi:02X}: begin\n        case (w0[7:0])\n")
        for t in order[1:]:
            labels = wrap_labels([f"8'h{lo:02X}" for lo in members[t]])
            p.append(f"          {labels}:\n            {t}\n")
        p.append(f"          default:\n            {order[0]}\n        endcase\n      end\n")
    p.append("      default: ctrl = ctrl_word_t'(W'(0));\n    endcase\n  end\n\n"
             "endmodule\n\n`default_nettype wire\n")
    return {OUT: "".join(p)}


if __name__ == "__main__":
    root = repo_root()
    out = sys.argv[1] if len(sys.argv) > 1 else root
    write_outputs("gen_decode_rom", lambda: generate(root), out)
