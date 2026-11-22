#!/usr/bin/env python3
"""Convert captures from a physical Z8001 into silicon vectors.

  python3 -I tools/silicon_vectors.py SUITE [OUTDIR]

SUITE is a checkout of the capture suite: its test definitions (Python
generators under tests/), golden/<set>/*.json final states, traces/<dir>/
bus traces, src/bootstrap*.bin and tests/golden_masks.json.  The suite's
generators are imported, so run this with -I.  OUTDIR defaults to
vectors/k800x_cpu/silicon.  Writes z8001.vec (non-segmented) and
z8001-seg.vec; format in docs/VECTOR_FORMAT.md.

Each test is laid out as the capture rig did it: RAM cleared, the bootstrap
image with its reset vector, the FCW at 0x0002 and 0x0030, the registers at
0x0010, the test's memory, the code at 0x0200 followed by a jump to the
dump routine at 0x00C0.  The dump routine stores R0-R15 and the FCW.

Coverage tests carry no program words: the suite assembles them.  They are
encoded here from the suite's opcode table and kept only when the encoding
equals an assembler listing line in the suite (tests/all_tests.lst, and
objdump lines quoted in tests/*.py), or when it is one of the few checked
by hand against the CPU manual's instruction formats (HAND_CHECKED); the
rest are listed as dropped.

Masked: the DIV/DIVL case 3 destination and S, where the RTL differs from
the chip, and any field the suite's mask file names.
"""

import csv
import dataclasses
import glob
import json
import os
import re
import sys
import types

CODE_BASE = 0x0200
SETS = {
    'z8001': {
        'targets': ('common', 'z8001'), 'golden': 'golden/z8001',
        'traces': ('traces/z8001', 'traces/odd_io'), 'boot': 'src/bootstrap.bin',
        'fcw0': 0x4000, 'regs': 0x0090, 'fcw': 0x00B2, 'jp': [0x5E08, 0x00C0]},
    'z8001-seg': {
        'targets': ('z8001-seg',), 'golden': 'golden/z8001-seg',
        'traces': ('traces/odd_io_seg',), 'boot': 'src/bootstrap_seg.bin',
        'fcw0': 0xC000, 'regs': 0x0140, 'fcw': 0x0162, 'jp': [0x5E08, 0x8000, 0x00C0]},
}
FLAG_BITS = {'C': 7, 'Z': 6, 'S': 5, 'V': 4, 'DA': 3, 'H': 2}
# Coverage programs checked by hand against the Z8000 CPU Reference
# Manual (1982) instruction formats: name -> words.
HAND_CHECKED = {
    # PUSHL @Rd,RRs: 10 010001 Rd RRs (PDF p.167, printed 158)
    'cov_299_pushl_r_pushl_rd_rrs': (0x9122,),
    # LDA RRd,address SS: 01 110110 0000 RRd, then 0 segment offset (PDF p.122, printed 113)
    'seg_cov_171_lda_da_lda_rd_address_short': (0x7608, 0x0180),
    # LDA RRd,addr(Rs) SS: 01 110110 Rs RRd, then 0 segment offset (PDF p.122, printed 113)
    'seg_cov_172_lda_x_lda_rd_addr_rs_short': (0x7658, 0x0170),
    # TRDB @Rd,@Rs,r: 10 111000 Rd 1000, 0000 r Rs 0000 (PDF p.204, printed 195)
    'cov_414_trdb_ir_trdb_rd_rs_r': (0xB828, 0x0410),
    'seg_cov_414_trdb_ir_trdb_rd_rs_r': (0xB8A8, 0x0480),
    # TRDRB @Rd,@Rs,r: 10 111000 Rd 1100, 0000 r Rs 0000 (PDF p.205, printed 196)
    'cov_415_trdrb_ir_trdrb_rd_rs_r': (0xB82C, 0x0410),
    'seg_cov_415_trdrb_ir_trdrb_rd_rs_r': (0xB8AC, 0x0480),
    # TRIB @Rd,@Rs,r: 10 111000 Rd 0000, 0000 r Rs 0000 (PDF p.207, printed 198)
    'cov_416_trib_ir_trib_rd_rs_r': (0xB820, 0x0410),
    'seg_cov_416_trib_ir_trib_rd_rs_r': (0xB8A0, 0x0480),
    # TRIRB @Rd,@Rs,r: 10 111000 Rd 0100, 0000 r Rs 0000 (PDF p.209, printed 200)
    'cov_417_trirb_ir_trirb_rd_rs_r': (0xB824, 0x0410),
    'seg_cov_417_trirb_ir_trirb_rd_rs_r': (0xB8A4, 0x0480),
}
# The suite's text for a segmented coverage test predates its segmented
# words; these give the operands the words encode.
HAND_HINT = {
    'seg_cov_171_lda_da_lda_rd_address_short': 'LDA RR8,<<1>>0x80',
    'seg_cov_172_lda_x_lda_rd_addr_rs_short': 'LDA RR8,<<1>>0x70(R5)',
    'seg_cov_414_trdb_ir_trdb_rd_rs_r': 'TRDB @RR10,@RR8,R4',
    'seg_cov_415_trdrb_ir_trdrb_rd_rs_r': 'TRDRB @RR10,@RR8,R4',
    'seg_cov_416_trib_ir_trib_rd_rs_r': 'TRIB @RR10,@RR8,R4',
    'seg_cov_417_trirb_ir_trirb_rd_rs_r': 'TRIRB @RR10,@RR8,R4',
}


# ---- the suite's test definitions --------------------------------------------

def load_module(root, path, name):
    """Import a generator with its exclusion filters removed: the excluded
    tests are captured silicon measurements too."""
    src = open(path).read()
    src = re.sub(r'^(\s*)tests = \[t for t in tests if t\.name not in _DISABLED\w*\]\s*$',
                 r'\1pass', src, flags=re.M)
    m = types.ModuleType(name)
    m.__file__ = path
    m.__package__ = 'tests'
    sys.modules[name] = m
    exec(compile(src, path, 'exec'), m.__dict__)
    return m


def test_defs(root, enc):
    """Every test the suite defines, by name: (definition, source tag)."""
    sys.path.insert(0, root)
    import tests  # noqa: E402  (the suite's package)
    defs = {}

    def add(t, rename):
        d = dataclasses.asdict(t)
        d['name'] = rename(t.name)
        old = dict(defs.get(d['name']) or {})
        word = old.pop('_word', None)
        if old and old != d:
            raise SystemExit('two definitions of %s' % d['name'])
        if word:
            d['_word'] = word
        defs[d['name']] = d

    mods = {}
    for path in sorted(glob.glob(os.path.join(root, 'tests', 'gen_*.py'))):
        name = 'tests.' + os.path.basename(path)[:-3]
        mods[name] = load_module(root, path, name)
    for name, m in mods.items():
        if hasattr(m, '_assemble'):
            m._assemble = enc.assemble
    for name, m in mods.items():
        base = name.split('.')[-1]
        # A "<x>_fixes" generator names its tests after x; they become fix_*.
        word = base[len('gen_'):-len('_fixes')] if base.endswith('_fixes') else None

        def rename(n, word=word):
            if word:
                n = re.sub(r'(^|_)%s_' % re.escape(word), r'\1fix_', n, count=1)
            return n
        for fn_name, fn in sorted(vars(m).items()):
            if fn_name.startswith('generate_') and callable(fn) and getattr(fn, '__module__', '') == name:
                for t in fn():
                    add(t, rename)
                    if word:
                        defs[rename(t.name)]['_word'] = word
    for t in tests.collect_all_tests():
        add(t, lambda n: n)
    return defs


# ---- the coverage encoder -----------------------------------------------------

class Encoder:
    """GAS-syntax encoder for the coverage forms, from the opcode table."""
    CC = {'f': 0, 'lt': 1, 'le': 2, 'ule': 3, 'ov': 4, 'pe': 4, 'mi': 5, 'z': 6, 'eq': 6,
          'c': 7, 'ult': 7, 't': 8, 'ge': 9, 'gt': 10, 'ugt': 11, 'nov': 12, 'po': 12,
          'pl': 13, 'nz': 14, 'ne': 14, 'nc': 15, 'uge': 15}
    SYM = re.compile(r'RQd|RRd|RRs|Rbd|Rbs|Rbl|Rb|Rs1|Rs2|Rd|Rs|Rx|R|r|address|addr|port|#data|'
                     r'#disp|#src|#n|#b|cc|flags|int|FCW|FLAGS|REFRESH|PSAPSEG|PSAPOFF|PSAP|'
                     r'NSPSEG|NSPOFF|NSP')
    VAL = re.compile(r'rq\d+|rr\d+|rh\d|rl\d|r\d+|#?-?0x[0-9a-f]+|#?-?\d+|[a-z/]+')
    CTL = ('FCW', 'FLAGS', 'REFRESH', 'PSAPSEG', 'PSAPOFF', 'PSAP', 'NSPSEG', 'NSPOFF', 'NSP')

    def __init__(self, csv_path):
        self.rows = list(csv.DictReader(open(csv_path, newline='')))

    @staticmethod
    def val(tok):
        t = tok.lstrip('#')
        m = re.fullmatch(r'r([hl])(\d)', t)
        if m:
            return int(m.group(2)) + (8 if m.group(1) == 'l' else 0)
        m = re.fullmatch(r'r[rq]?(\d+)', t)
        if m:
            return int(m.group(1))
        if re.fullmatch(r'-?0x[0-9a-f]+|-?\d+', t):
            return int(t, 0)
        return t

    @staticmethod
    def ops(s):
        return [x.strip() for x in s.split(',')] if s.strip() else []

    def bind(self, template, asm):
        tm, am = template.split(' ', 1), asm.split(' ', 1)
        tops = self.ops(tm[1]) if len(tm) > 1 else []
        aops = self.ops(am[1]) if len(am) > 1 else []
        f = {}
        if tops and tops[-1] in ('flags', 'int'):
            f[tops[-1]] = aops[len(tops) - 1:]
            aops, tops = aops[:len(tops) - 1], tops[:-1]
        if len(tops) != len(aops):
            return None
        for t, a in zip(tops, aops):
            if re.fullmatch(r'#\d+', t):
                if self.val(a) != int(t[1:]):
                    return None
                continue
            if t in self.CTL:
                if a.lower() not in (t.lower(), {'PSAPOFF': 'psap', 'NSPOFF': 'nsp'}.get(t, '?')):
                    return None
                continue
            ts, av = self.SYM.findall(t), self.VAL.findall(a)
            if len(ts) != len(av) or t.startswith('@') != a.startswith('@') or ('(' in t and '(' not in a):
                return None
            if t.startswith('#') != a.startswith('#') and t != 'port':
                return None
            for s, v in zip(ts, av):
                x = self.val(v)
                pair_ok = (t.startswith('@') or '(' in t or (s == 'Rd' and template.startswith('LDA '))) \
                    and re.fullmatch(r'rr\d+', v)
                if s in ('Rd', 'Rs', 'Rx', 'R', 'r', 'Rs1', 'Rs2') and not re.fullmatch(r'r\d+', v) and not pair_ok:
                    return None
                if s in ('Rbd', 'Rbs', 'Rb', 'Rbl') and not re.fullmatch(r'r[hl]\d', v):
                    return None
                if s in ('RRd', 'RRs') and not re.fullmatch(r'rr\d+', v):
                    return None
                if s == 'RQd' and not re.fullmatch(r'rq\d+', v):
                    return None
                if s in ('address', 'addr', 'port', '#data', '#disp', '#src', '#n', '#b') and \
                        (not isinstance(x, int) or v.startswith('r')):
                    return None
                if s == 'cc' and x not in self.CC:
                    return None
                f[s] = x
        return f

    def encode_row(self, row, asm):
        f = self.bind(row['syntax'], asm)
        if f is None:
            return None
        mn = row['instruction']
        d = next((f[k] for k in ('Rd', 'Rbd', 'RRd', 'RQd', 'Rbl') if k in f), None)
        s = next((f[k] for k in ('Rs', 'Rbs', 'RRs') if k in f), None)
        r = f.get('r', f.get('R', f.get('Rb')))
        byte_op = mn.endswith('B') and mn not in ('DJNZ', 'SUB', 'CPSB') and any(k in f for k in ('Rbd', 'Rbs'))
        words = []
        parts = [p.strip() for p in row['encoding'].split(' + ')]
        for part in parts:
            if part in ('#data', '#data | #data'):
                v = f['#data'] & 0xFFFF
                if byte_op or part == '#data | #data':
                    v = (v & 0xFF) * 0x101
                words.append(v)
                continue
            if part == '#data (high)':
                words.append((f['#data'] >> 16) & 0xFFFF)
                continue
            if part == '#data (low)':
                words.append(f['#data'] & 0xFFFF)
                continue
            if part in ('address', '#address'):
                a = f.get('address', f.get('addr', f.get('port')))
                if a is None:
                    return None
                words.append(a & 0xFFFF)
                continue
            if part == 'displacement':
                # an unlinked object at address 0: the field is the target
                words.append((f['address'] if row['addressing_mode'] == 'RA' else f['#disp']) & 0xFFFF)
                continue
            if part == 'bbbbbbbb':
                b = -f['#b'] if mn in ('SRL', 'SRA', 'SRLL', 'SRAL') else f['#b']
                words.append(b & 0xFFFF)
                continue
            if part == '0000_bbbb':
                b = -f['#b'] if mn in ('SRLB', 'SRAB') else f['#b']
                words.append(b & 0xFF)
                continue
            bits = ''
            for tok in part.split('_'):
                if re.fullmatch(r'[01]+', tok):
                    bits += tok
                    continue
                m = re.fullmatch(r'([01]*)(.*)', tok)
                pre, name = m.group(1), m.group(2)
                bits += pre
                v = self.field(name, mn, f, d, s, r, len(bits))
                if v is None:
                    return None
                bits += format(v & ((1 << len(name)) - 1), '0%db' % len(name))
            if len(bits) % 16:
                return None
            if 'port' in f and part == parts[-1] and row['addressing_mode'] == 'DA' and \
                    mn.lstrip('S').rstrip('B') in ('IN', 'OUT'):
                bits += format(f['port'] & 0xFFFF, '016b')
            words += [int(bits[i:i + 16], 2) for i in range(0, len(bits), 16)]
        return words

    def field(self, name, mn, f, d, s, r, nbits):
        if name in ('Rsnz', 'Rsss', 'Rbss', 'RRss'):
            return s
        if name in ('Rdnz', 'Rddd', 'Rbdd', 'RRdd', 'RQdd'):
            return d
        if name == 'Rrrr':
            return r
        if name == 'Rxxx':
            return f.get('Rx')
        if name == 'R1nz':
            return f.get('Rs1')
        if name == 'R2nz':
            return f.get('Rs2')
        if name == 'cccc':
            return self.CC[f['cc']] if 'cc' in f else None
        if name == 'nnnn':
            return f['#n'] - 1
        if name in ('bbbb', 'bbb'):
            return f['#b'] & 15
        if name in ('CZSV', 'CZSP'):
            v = 0
            for x in f['flags']:
                v |= {'c': 8, 'z': 4, 's': 2, 'p': 1, 'v': 1}[x.strip()]
            return v
        if name in ('VN', '00VN', '01VN'):
            v = 3
            for x in f['int']:
                v &= ~{'vi': 2, 'nvi': 1}[x.strip()]
            return v
        if name == 'dddd' and mn == 'LDK':
            return f['#data'] & 15
        if name == 'dddddddd' and mn == 'LDB':
            return f['#data'] & 0xFF
        if re.fullmatch(r'd+', name) and mn == 'JR':
            v = (f['address'] >> 1) & 0xFF
            if len(name) == 4:
                v = v >> 4 if nbits == 8 else v & 15
            return v
        if re.fullmatch(r'd+', name) and mn in ('DJNZ', 'DBJNZ'):
            v = ((-f['address']) >> 1) & 0x7F
            return v >> 4 if len(name) == 3 else v & 15
        return None

    def assemble(self, asm, z8001=False):
        mn = asm.split(' ', 1)[0].upper()
        c = [w for row in self.rows if row['instruction'] == mn
             for w in [self.encode_row(row, asm)] if w is not None]
        if not c:
            return None
        return list(min(c, key=len))   # the assembler picks the shortest


def norm_asm(a):
    a = re.sub(r'\s+', ' ', a.replace('\t', ' ').strip())
    return re.sub(r'\s*,\s*', ', ', a).lower()


def listing(root):
    """asm text -> set of word tuples, from the suite's assembler listings."""
    corpus = {}
    cur = None

    def put(c):
        hx = c[0]
        corpus.setdefault(norm_asm(c[1]), set()).add(tuple(int(hx[i:i + 4], 16) for i in range(0, len(hx), 4)))
    for line in open(os.path.join(root, 'tests', 'all_tests.lst')):
        m = re.match(r'^\s*\d+ [0-9a-f]{4} ([0-9A-Fa-f]+)\s+\t\t(\S.*)$', line)
        if m:
            if cur:
                put(cur)
            cur = [m.group(1), m.group(2)]
            continue
        m = re.match(r'^\s*\d+\s{6}([0-9A-Fa-f]+)\s*$', line)
        if m and cur:
            cur[0] += m.group(1)
            continue
        if cur:
            put(cur)
            cur = None
    if cur:
        put(cur)
    for path in glob.glob(os.path.join(root, 'tests', '*.py')):
        for line in open(path):
            m = re.match(r'\s*#\s+[0-9a-f]{4}:\s+((?:[0-9a-f]{4}\s)+)\s*(\S.*)$', line)
            if m:
                corpus.setdefault(norm_asm(m.group(2)), set()).add(tuple(int(w, 16) for w in m.group(1).split()))
    return corpus


# ---- masks --------------------------------------------------------------------

def div_dest(t):
    for src in (t.get('instruction', ''), t.get('description', '')):
        parts = (src or '').lower().split(None, 1)
        dst = parts[1].split(',', 1)[0] if len(parts) > 1 else ''
        m = re.search(r'\brq(\d+)\b', dst)
        if m:
            return {'R%d' % (int(m.group(1)) + i) for i in range(4)}
        m = re.search(r'\brr(\d+)\b', dst)
        if m:
            return {'R%d' % int(m.group(1)), 'R%d' % (int(m.group(1)) + 1)}
    return {'R%d' % i for i in range(16)}


def masks(t, g, named):
    """field -> mask of the bits compared (0 = not compared)."""
    m = {}
    for f in named.get(t['name'], {}).get('ignore_fields', []):
        m[f] = 0
    fcw, mn = g.get('fcw'), t['mnemonic']
    if mn in ('DIV', 'DIVL') and fcw is not None and (fcw >> 4) & 1 and not (fcw >> 7) & 1 and not (fcw >> 6) & 1:
        for f in div_dest(t) | {'flag_S'}:
            m[f] = 0
    return m


# ---- vectors --------------------------------------------------------------------

def ik(d):
    return {int(k): v for k, v in d.items()}


def hint(t):
    """The program as assembler text: the instruction, else a description
    that opens with the mnemonic, up to its ': '; else the mnemonic."""
    if t['name'] in HAND_HINT:
        return HAND_HINT[t['name']]
    h = t.get('instruction') or ''
    if not h and (t.get('description') or '').upper().startswith(t['mnemonic'] + ' '):
        h = t['description'].split(': ', 1)[0]
    h = re.sub(r'\s+', ' ', h).strip()
    return h if h and h.isascii() else t['mnemonic']


def trace_records(tr):
    out = []
    for e in tr['trace']:
        out.append('B %04X %04X %s %s %s %s %s' % (
            e['addr'], e['data'], e['rw'], e['bw'], e['io'],
            '%d' % e['seg'] if 'seg' in e else '-', '%X' % e['st'] if 'st' in e else '-'))
    out.append('F ICC %d' % tr['instr_cycle_count'])
    return out


def test_records(t, g, tr, lay, named):
    rec = ['test %s' % t['name'], '# hint: %s' % hint(t)]
    mem = {0x0002: t['fcw'], 0x0030: t['fcw']}
    for r, v in ik(t['regs']).items():
        mem[0x0010 + 2 * r] = v & 0xFFFF
    for a, v in ik(t['memory']).items():
        mem[a] = v & 0xFFFF
    for i, w in enumerate(list(t['code']) + lay['jp']):
        mem[CODE_BASE + 2 * i] = w & 0xFFFF
    for a in sorted(mem):
        if a >= 0x2000:
            raise SystemExit('%s: %04X is outside the rig RAM' % (t['name'], a))
        rec.append('M %04X %04X' % (a, mem[a]))
    for r, v in sorted(ik(t['io_preloads']).items()):
        rec.append('P %X %04X' % (r, v & 0xFFFF))
    for r, vs in sorted(ik(t['io_sequences']).items()):
        if len(vs) > 4:
            raise SystemExit('%s: more than 4 scripted reads' % t['name'])
        rec += ['Q %X %04X' % (r, v & 0xFFFF) for v in vs]
    if g is not None:
        mk = masks(t, g, named)
        regs = ik(g['regs'])
        for i in range(16):
            m = mk.get('R%d' % i, 0xFFFF)
            v = (regs.get(i) or 0) & 0xFFFF
            rec.append('F R%d %s' % (i, '----' if m == 0 else '%04X' % v if m == 0xFFFF else '%04X %04X' % (v & m, m)))
        fm = 0xFFFF
        for f, b in FLAG_BITS.items():
            if mk.get('flag_' + f, 1) == 0:
                fm &= ~(1 << b)
        rec.append('F FCW %04X %04X' % (g['fcw'] & fm, fm))
        gm = ik(g.get('memory', {}))
        for a in sorted(set(gm) | set(ik(t['expected_memory'])) | set(t['observe_memory'])):
            if a >= 0x2000:
                raise SystemExit('%s: read-back of %04X is outside the rig RAM' % (t['name'], a))
            if mk.get('mem_0x%04X' % a, 1) != 0:
                rec.append('F MEM %04X %04X' % (a, (gm.get(a) or 0) & 0xFFFF))
        gi = ik(g.get('io', {}))
        for r in sorted(set(gi) | set(ik(t['expected_io'])) | set(t['observe_io'])):
            if mk.get('io_0x%02X' % r, 1) != 0:
                rec.append('F IO %X %04X' % (r, (gi.get(r) or 0) & 0xFFFF))
    if tr is not None:
        rec += trace_records(tr)
    rec.append('E')
    return rec


def words(path):
    b = open(path, 'rb').read()
    return [(b[i] << 8) | b[i + 1] for i in range(0, len(b) - 1, 2)]


def main(argv):
    if len(argv) not in (2, 3):
        sys.stderr.write(__doc__)
        return 2
    if not sys.flags.isolated:
        sys.stderr.write('silicon_vectors.py imports the suite: run it with python3 -I\n')
        return 2
    root = os.path.abspath(argv[1])
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    outdir = argv[2] if len(argv) == 3 else os.path.join(here, 'vectors', 'k800x_cpu', 'silicon')
    enc = Encoder(os.path.join(root, 'tests', 'z8000_opcodes.csv'))
    defs = test_defs(root, enc)
    corpus = listing(root)
    named = json.load(open(os.path.join(root, 'tests', 'golden_masks.json'))).get('tests', {})
    gen_words = {d['_word'] for d in defs.values() if d.get('_word')}
    by_orig = {}
    for n, d in defs.items():
        if d.get('_word'):
            by_orig[re.sub(r'(^|_)fix_', r'\1%s_' % d['_word'], n, count=1)] = n
    os.makedirs(outdir, exist_ok=True)
    dropped, hand = [], []
    for set_name, lay in SETS.items():
        golden = {}
        for path in sorted(glob.glob(os.path.join(root, lay['golden'], '*.json'))):
            g = json.load(open(path))
            golden[by_orig.get(g['test'], g['test'])] = g
        traces = {}
        for d in lay['traces']:
            for path in sorted(glob.glob(os.path.join(root, d, '*.json'))):
                tr = json.load(open(path))
                traces[by_orig.get(tr['test'], tr['test'])] = tr
        names = sorted(set(golden) | set(traces))
        boot = words(os.path.join(root, lay['boot']))
        base = [0x0000, lay['fcw0'], 0x0000, 0x0040, 0, 0, 0, 0] + boot[8:]
        lines = ['K8000VEC 1 silicon', 'variant Z8001',
                 'dump %04X %04X' % (lay['regs'], lay['fcw'])]
        lines += ['M %04X %04X' % (2 * i, w) for i, w in enumerate(base) if w]
        n = 0
        for name in names:
            t = defs.get(name)
            if t is None or t['target'] not in lay['targets']:
                raise SystemExit('%s: capture %s has no test definition' % (set_name, name))
            if 'opcode_coverage' in t['tags'] and name in HAND_CHECKED:
                if tuple(t['code']) != HAND_CHECKED[name]:
                    raise SystemExit('%s: program differs from its hand check' % name)
                hand.append((set_name, name, ' '.join('%04X' % w for w in t['code'])))
            elif 'opcode_coverage' in t['tags']:
                ws = corpus.get(norm_asm(t['instruction']))
                if not t['code'] or ws is None or tuple(t['code']) not in ws:
                    dropped.append((set_name, name, t['instruction'],
                                    'not listed' if ws is None else 'listing differs'))
                    continue
            lines += test_records(t, golden.get(name), traces.get(name), lay, named)
            n += 1
        lines.append('END %d' % n)
        text = '\n'.join(lines) + '\n'
        if any(re.search(re.escape(w), text, re.I) for w in gen_words):
            raise SystemExit('%s: a generator\'s test prefix reached the vectors' % set_name)
        with open(os.path.join(outdir, set_name + '.vec'), 'w') as f:
            f.write(text)
        print('%s: %d tests (%d captures, %d traces)' % (set_name, n, len(golden), len(traces)))
    with open(os.path.join(outdir, 'dropped.txt'), 'w') as f:
        f.write('# Coverage tests converted on a hand check of their words against the CPU manual.\n')
        for s, name, asm in hand:
            f.write('#   %s %s  %s\n' % (s, name, asm))
        f.write('# Coverage tests whose encoding no assembler listing line confirms; not converted.\n')
        for s, name, asm, why in dropped:
            f.write('%s %s  %s  (%s)\n' % (s, name, asm, why))
    print('dropped %d coverage tests (dropped.txt)' % len(dropped))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
