#!/usr/bin/env python3
"""Apply a CPU behaviour change, captured on a physical Z8001, to vectors
recorded before it.

  update_cpu_vectors.py RULE [--check] [--inferred] FILE...

Each RULE recomputes, from the vector's own bus cycles, the fields the
behaviour change moves, and rewrites them in place: a final register or
PSAP record, a written word (every record that drives it, and a later read
of the same word, as the board's memory would return it), and in a
cpufpu file the W and final memory records.  Every other byte stays.  A
vector the rule touches but cannot work out stops the run.  --check only
lists what would change.  trt and tr stop rather than patch a translate
with an interrupt or trap entry inside it, or with the string pointer in
R1 over two or more elements: no capture covers those; --inferred
applies the RTL's reading there.  Rules (docs/DECISIONS.md, silicon rows):

  psap    PSAP offset bits 7:0 are not stored and read back 0; PSAPSEG
          bit 15 is stored and read back.
  pcseg   bit 15 of the PC segment word is kept as last loaded (reset, a
          PSA entry, JP/CALL address word, RET, IRET, LDPS); LDAR writes
          it to bit 31 and the pushed PC segment word carries it.
  trt     TRT* with the source pointer in R1 steps the pointer, then
          writes RH1.
  tr      TR* writes the table byte to RH1, after the pointer step, and
          sets Z when it is 0.
  zeroc   a shift by zero sets C (serial vectors compare C for it).
  shiftv  SLL/SRL/SDL (byte, word, long) set V if the sign bit changed at
          any step; serial vectors compare V for them.
  blockz  block moves (LDI...LDDRB) and block I/O set Z as V: the count
          reached 0.
  comflg  COMFLG complements H, whatever its flag mask.
  rldb    RLDB/RRDB set S from bit 7 of the link byte.
  lda     segmented LDA DA/X with a short address word keeps its offset
          byte in the segment word.
  dab     DAB after a subtraction applies the addition's tests and
          subtracts the corrections (ALU vectors).
"""

import sys

SEG_VARIANTS = ('Z8001', 'Z8003')
ST_IF1, ST_IFN, ST_STACK = 0xD, 0xC, 0x9


class Vector:
    def __init__(self, path):
        self.path = path
        self.lines = open(path).read().split('\n')
        self.kind = self.lines[0].split()[2]
        self.variant = next((l.split()[1] for l in self.lines if l.startswith('variant ')), '')
        self.seg = self.variant in SEG_VARIANTS
        self.bus = 'T' if self.kind == 'cpu' else 'C'
        self.changes = []

    def field(self, i, k):
        return int(self.lines[i].split()[k], 16)

    def set_field(self, i, k, v, width):
        p = self.lines[i].split(' ')
        p[k] = '%0*X' % (width, v)
        self.lines[i] = ' '.join(p)

    def cycles(self):
        """Bus cycles: addr, st, sn, rw, bw, data, and the record indices
        whose AD carries the data (inputs for a read, outputs for a write)."""
        cyc, cur, prev_as = [], None, 1
        for i, l in enumerate(self.lines):
            p = l.split()
            if not p or p[0] != self.bus:
                continue
            ob = int(p[3], 16)
            as_n, ds_n, rw, drive = (ob >> 7) & 1, (ob >> 6) & 1, (ob >> 4) & 1, (ob >> 8) & 1
            if not as_n:
                if prev_as:
                    cur = {'addr': int(p[4], 16), 'sn': int(p[5], 16), 'st': int(p[6], 16),
                           'rw': rw, 'data': None, 'recs': [], 'ds': [], 'i': i}
                    cyc.append(cur)
            elif cur is not None:
                cur['recs'].append((i, drive))
                if not ds_n:
                    cur['ds'].append(i)
                    cur['rw'] = rw
                    cur['data'] = int(p[2], 16) if rw else int(p[4], 16)
            prev_as = as_n
        return cyc

    def final_regs(self):
        tag = 'F REGS ' if self.kind == 'cpu' else 'F C REGS '
        for i, l in enumerate(self.lines):
            if l.startswith(tag):
                return i, len(tag.split()) , [int(x, 16) if x != '----' else None for x in l.split()[len(tag.split()):]]
        raise SystemExit('%s: no final registers' % self.path)

    def set_reg(self, r, v):
        i, off, regs = self.final_regs()
        if regs[r] is None:
            raise SystemExit('%s: R%d is undefined in the final record' % (self.path, r))
        if regs[r] != v:
            self.changes.append('final R%d %04X -> %04X' % (r, regs[r], v))
            self.set_field(i, off + r, v, 4)

    def set_final(self, name, v, width):
        tag = ('F %s ' if self.kind == 'cpu' else 'F C %s ') % name
        for i, l in enumerate(self.lines):
            if l.startswith(tag):
                old = int(l.split()[-1], 16)
                if old != v:
                    self.changes.append('final %s %0*X -> %0*X' % (name, width, old, width, v))
                    self.set_field(i, len(tag.split()), v, width)
                return
        raise SystemExit('%s: no final %s' % (self.path, name))

    def rewrite_write(self, c, new, later):
        """A write cycle's data becomes new: its driving records, then reads of
        the same word in the cycles after it until it is written again."""
        old = c['data']
        if old == new:
            return
        self.changes.append('write %02X:%04X %04X -> %04X (record %d)' % (c['sn'], c['addr'], old, new, c['i'] + 1))
        for i, drive in c['recs']:
            if drive and self.field(i, 4) == old:
                self.set_field(i, 4, new, 4)
                # cpufpu: the FPU records of the same step see the bus
                k = i + 1
                while k < len(self.lines) and self.lines[k][:2] in ('C ', 'E '):
                    if self.lines[k].startswith('E ') and self.field(k, 2) == old:
                        self.set_field(k, 2, new, 4)
                    if self.lines[k].startswith('C ') and k not in [r for r, _ in c['recs']]:
                        break
                    k += 1
        c['data'] = new
        for d in later:
            if (d['sn'], d['addr'] & ~1) != (c['sn'], c['addr'] & ~1):
                continue
            if not d['rw']:
                break
            if d['data'] == old:
                self.changes.append('read %02X:%04X %04X -> %04X (record %d)' % (d['sn'], d['addr'], old, new, d['i'] + 1))
                for i, _ in d['recs']:
                    if self.field(i, 2) == old:
                        self.set_field(i, 2, new, 4)
                d['data'] = new
        if self.kind == 'cpufpu':
            self.fix_memory(c, old, new)

    def rewrite_addr(self, c, new):
        """A cycle's address becomes new; the data the board returned is kept."""
        old = c['addr']
        self.changes.append('address %02X:%04X -> %04X (record %d), data %04X kept' % (c['sn'], old, new, c['i'] + 1, c['data']))
        i = c['i']
        while True:
            p = self.lines[i].split()
            if p and p[0] == self.bus:
                ob = int(p[3], 16)
                on_bus = (ob >> 8) & 1 and self.field(i, 4) == old
                if (ob >> 7) & 1 and not on_bus:
                    break
                if on_bus:
                    self.set_field(i, 4, new, 4)
            i += 1
        c['addr'] = new

    def fix_memory(self, c, old, new):
        """cpufpu: the W record of that write, and the final memory."""
        addr = ((c['sn'] << 16) | c['addr']) & ~1
        mem = {}
        w_line = None
        for i, l in enumerate(self.lines):
            p = l.split()
            if not p:
                continue
            if p[0] == 'M':
                mem[int(p[1], 16)] = int(p[2], 16)
            elif p[0] == 'W' and i > c['i'] and w_line is None and int(p[1], 16) == addr:
                w_line = i
        prior = mem.get(addr, 0)   # memory before the write (test writes only)
        if w_line is not None:
            if new == prior:
                del self.lines[w_line]
            else:
                self.set_field(w_line, 2, new, 4)
        elif new != prior:
            raise SystemExit('%s: no W record for the write at %06X' % (self.path, addr))
        for i, l in enumerate(self.lines):
            p = l.split()
            if p[:2] == ['F', 'M'] and int(p[2], 16) == addr:
                if new == 0:
                    del self.lines[i]
                else:
                    self.set_field(i, 3, new, 4)
                break
        else:
            if new != 0:
                raise SystemExit('%s: no final memory record at %06X' % (self.path, addr))

    def save(self):
        open(self.path, 'w').write('\n'.join(self.lines))


def instructions(cyc):
    """Group the cycles by instruction: (words fetched, the other cycles)."""
    out, cur = [], None
    for k, c in enumerate(cyc):
        if c['st'] == ST_IF1:
            cur = {'if1': c, 'k': k, 'words': [c['data']], 'ops': []}
            out.append(cur)
        elif cur is None:
            continue
        elif c['st'] == ST_IFN and c['addr'] == cur['if1']['addr'] + 2 * len(cur['words']) \
                and all(o['st'] in (0, 1) for o in cur['ops']):        # past refresh and internal cycles
            cur['words'].append(c['data'])
        else:
            cur['ops'].append(c)
    return out


# ---- psap ---------------------------------------------------------------------------

def rule_psap(v):
    cyc = v.cycles()
    regs, psap = {}, {4: None, 5: None}
    touched = False
    for ins in instructions(cyc):
        w = ins['words']
        w0 = w[0]
        if w0 is None:
            continue
        if (w0 & 0xFFF0) == 0x2100 and len(w) > 1:          # LD Rd,#imm
            regs[w0 & 15] = w[1]
        elif (w0 & 0xFF00) == 0xBD00:                       # LDK Rd,#n
            regs[(w0 >> 4) & 15] = w0 & 15
        elif (w0 & 0xFF00) == 0x7D00 and (w0 & 7) in (4, 5):
            c, r = w0 & 7, (w0 >> 4) & 15
            if w0 & 8:                                       # LDCTL PSAPxxx,Rs
                if r not in regs:
                    raise SystemExit('%s: LDCTL from an untracked register' % v.path)
                psap[c] = regs[r]
            else:                                            # LDCTL Rd,PSAPxxx
                if psap[c] is None:
                    raise SystemExit('%s: PSAP read before it is written' % v.path)
                regs[r] = psap[c] & 0xFF00
                v.set_reg(r, regs[r])
            touched = True
        elif (w0 & 0xFF00) == 0x7D00 and not (w0 & 8):
            regs.pop((w0 >> 4) & 15, None)
    if touched and psap[5] is not None:
        i = next(i for i, l in enumerate(v.lines) if l.startswith(('F PSAP ', 'F C PSAP ')))
        old = int(v.lines[i].split()[-1], 16)
        v.set_final('PSAP', old & 0x7FFF00, 8)


# ---- pcseg --------------------------------------------------------------------------

def rule_pcseg(v):
    if not v.seg:
        return
    cyc = v.cycles()
    ins = instructions(cyc)
    if not ins:
        return
    # Reset: FCW, PC segment word, PC offset.
    boot = cyc[:ins[0]['k']]
    if len([c for c in boot if c['rw']]) < 3:
        raise SystemExit('%s: no reset PC segment word' % v.path)
    b15 = (boot[1]['data'] >> 15) & 1
    segm = (boot[0]['data'] >> 15) & 1

    def later(c):
        return cyc[cyc.index(c) + 1:]

    for n, x in enumerate(ins):
        w0 = x['words'][0]
        nxt = ins[n + 1]['if1'] if n + 1 < len(ins) else None
        pushes = [c for c in x['ops'] if c['st'] == ST_STACK and not c['rw']]
        pops = [c for c in x['ops'] if c['st'] == ST_STACK and c['rw']]
        reads = [c for c in x['ops'] if c['rw'] and c['st'] != ST_STACK]
        call = w0 is not None and ((w0 & 0xFF0F) == 0x5F00 or (w0 & 0xFF0F) == 0x1F00 or (w0 & 0xF000) == 0xD000)
        # Trap and interrupt frames: four stack writes, the second the PC
        # segment word; then the PSA's FCW, (segmented) PC segment word and
        # offset.
        frame, run, k = False, [], 0
        ops = x['ops']
        while k < len(ops):
            c = ops[k]
            if c['st'] == ST_STACK and not c['rw']:
                run.append(c)
                k += 1
                if len(run) == 4:
                    frame = True
                    if b15 is None:
                        raise SystemExit('%s: PC segment bit 15 unknown at a trap' % v.path)
                    v.rewrite_write(run[1], (run[1]['data'] & 0x7FFF) | (b15 << 15), later(run[1]))
                    psa = []
                    while k < len(ops) and ops[k]['rw'] and ops[k]['st'] != ST_STACK and len(psa) < 3:
                        psa.append(ops[k])
                        k += 1
                    if psa:
                        segm = (psa[0]['data'] >> 15) & 1
                    if len(psa) == 3:
                        b15 = (psa[1]['data'] >> 15) & 1
                    run = []
                continue
            run = []
            k += 1
        # A segmented CALL/CALR pushes the offset, then the segment word.
        if not frame and call and segm and len(pushes) == 2:
            if b15 is None:
                raise SystemExit('%s: PC segment bit 15 unknown at a call' % v.path)
            v.rewrite_write(pushes[1], (pushes[1]['data'] & 0x7FFF) | (b15 << 15), later(pushes[1]))
        if w0 is None:
            continue
        sequential = nxt is not None and nxt['addr'] == x['if1']['addr'] + 2 * len(x['words'])
        if frame:
            pass                                         # the PSA reads set it above
        elif (w0 & 0xFF00) in (0x5E00, 0x5F00) and segm:   # JP cc / CALL, DA or X
            if (w0 & 0xFF00) == 0x5F00 or not sequential:
                b15 = (x['words'][1] >> 15) & 1
        elif (w0 & 0xFF00) in (0x1E00, 0x1F00) and segm:   # JP cc / CALL @RR
            if (w0 & 0xFF00) == 0x1F00 or not sequential:
                b15 = None
        elif (w0 & 0xFFF0) == 0x9E00 and pops and segm:    # RET cc
            b15 = (pops[0]['data'] >> 15) & 1
        elif w0 == 0x7B00:                                 # IRET
            if segm and len(pops) >= 4:
                b15 = (pops[2]['data'] >> 15) & 1
            if len(pops) >= 2:
                segm = (pops[1]['data'] >> 15) & 1
        elif (w0 & 0xFF0F) == 0x3900 or (w0 & 0xFF0F) == 0x7900:   # LDPS
            if segm and len(reads) >= 3:
                b15 = (reads[1]['data'] >> 15) & 1
            if reads:
                segm = (reads[0]['data'] >> 15) & 1
        elif (w0 & 0xFF0F) == 0x7D0A:                      # LDCTL FCW,Rs
            segm = None
        elif (w0 & 0xFFF0) == 0x3400 and segm:             # LDAR RRd,addr
            if b15 is None:
                raise SystemExit('%s: PC segment bit 15 unknown at LDAR' % v.path)
            if nxt is None or nxt['data'] != 0x7A00:
                raise SystemExit('%s: LDAR is not the last instruction' % v.path)
            r = w0 & 15
            _, _, regs = v.final_regs()
            v.set_reg(r, (regs[r] & 0x7FFF) | (b15 << 15))
        if segm is None and (call or (w0 & 0xFF00) in (0x5E00, 0x1E00)):
            raise SystemExit('%s: mode unknown at a branch' % v.path)


# ---- trt ----------------------------------------------------------------------------

INFERRED = False      # --inferred: also patch translate cases no capture covers


def refuse_inferred(v, risky):
    """Stop on a translate change that rests on inferred behaviour only."""
    if v.changes and risky and not INFERRED:
        raise SystemExit('%s: %s; not patched (--inferred to apply)' % (v.path, '; '.join(sorted(set(risky)))))


def rule_trt(v, test_only=True):
    """Translate: the pointer (offset R1 or the pair's) steps, then RH1 takes
    the table byte; each element's string address and the final R1 follow."""
    risky = []
    cyc = v.cycles()
    ins = instructions(cyc)
    segm = v.seg and (cyc[0]['data'] >> 15) & 1
    final = None
    for n, x in enumerate(ins):
        w = x['words']
        w0 = w[0]
        if w0 is None or (w0 & 0xFF00) != 0xB800 or (w0 & 3) != (2 if test_only else 0):
            continue
        for y in ins[n + 1:]:
            if r1_kept(y['words']) or (y['words'][0] or 0) >> 8 == 0xB8:
                continue
            raise SystemExit('%s: %04X after the translate may write R1' % (v.path, y['words'][0]))
        if len(w) > 1 and (w[1] >> 8) & 15 == 1:
            raise SystemExit('%s: translate count in R1' % v.path)
        on_r1 = (w0 >> 4) & 15 == (0 if segm else 1)
        step = 0xFFFF if w0 & 8 else 0x0001
        bus = [c for c in x['ops'] if c['st'] not in (0, 1) and c['data'] is not None]   # not refresh
        reads = [c for c in bus if c['rw']]
        writes = [c for c in bus if not c['rw']]
        if any(c['st'] in (4, 5, 6, 7) or (c['st'] == ST_STACK and not c['rw']) for c in x['ops']):
            risky.append('an interrupt or trap entry within the translate')
        if on_r1 and len(reads) >= 4:
            risky.append('the string pointer in R1 over two or more elements')
        p = reads[0]['addr']
        byte = None
        for e in range(0, len(reads) - 1, 2):
            s_rd, t_rd = reads[e], reads[e + 1]
            if on_r1 and s_rd['addr'] != p:
                v.rewrite_addr(s_rd, p)
            if on_r1 and not test_only and writes[e // 2]['addr'] != p:
                v.rewrite_addr(writes[e // 2], p)
            byte = (t_rd['data'] & 0xFF) if t_rd['addr'] & 1 else (t_rd['data'] >> 8)
            p = (byte << 8) | ((p + step) & 0xFF)
        final = (p, None) if on_r1 else (None, byte)
    if final is not None:
        _, _, regs = v.final_regs()
        v.set_reg(1, final[0] if final[0] is not None else (regs[1] & 0xFF) | (final[1] << 8))
    if test_only:
        refuse_inferred(v, risky)
    return risky


def r1_kept(w):
    """The instruction leaves R1 alone: the forms these vectors run."""
    w0 = w[0]
    if w0 is None or w0 in NO_FLAGS:
        return True
    if (w0 & 0xFFF0) == 0x2100 or (w0 & 0xFF00) in (0xA900, 0xAB00):   # LD R,#; INC, DEC
        return (w0 & 0xFF00 == 0x2100 and w0 & 15 != 1) or (w0 & 0xFF00 != 0x2100 and (w0 >> 4) & 15 != 1)
    if (w0 & 0xFF00) in (0x5E00, 0x1E00) or (w0 & 0xE000) == 0xE000:   # JP, JR
        return True
    if (w0 >> 8) in (0x3A, 0x3B, 0xBA, 0xBB, 0xB8) and len(w) > 1 and w[1] is not None:   # block, translate
        return 1 not in ((w0 >> 4) & 15, (w[1] >> 8) & 15, (w[1] >> 4) & 15)
    return False


def rule_tr(v):
    """TR*: RH1 as TRT*, and Z set when the last translated byte is 0."""
    risky = rule_trt(v, test_only=False)
    x = last_flag_writer(v, lambda w: (w[0] & 0xFF03) == 0xB800)
    if x is None:
        refuse_inferred(v, risky)
        return
    t = [c for c in x['ops'] if c['rw'] and c['st'] not in (0, 1) and c['data'] is not None][-1]
    byte = (t['data'] & 0xFF) if t['addr'] & 1 else (t['data'] >> 8)
    fcw = int(v.lines[fcw_line(v)].split()[-1], 16)
    v.set_final('FCW', (fcw & ~0x40) | (0x40 if byte == 0 else 0), 4)
    refuse_inferred(v, risky)


def shift_v(val, n, bits, left, arith=False):
    """V: the sign bit changed at some step of an n-position shift."""
    mask, sign = (1 << bits) - 1, 1 << (bits - 1)
    v = 0
    for _ in range(n):
        new = ((val << 1) & mask) if left else ((val >> 1) | ((val & sign) if arith else 0))
        v |= (new ^ val) & sign
        val = new
    return 1 if v else 0, val


def signed(x, bits):
    return x - (1 << bits) if x & (1 << (bits - 1)) else x


# Instructions that leave the flags alone, as these vectors use them.
NO_FLAGS = (0x8D07, 0x7A00)


def shift_scan(v):
    """Replay the vector's shifts on registers tracked from its pokes and
    immediate loads. Returns the shift that last wrote the flags, as
    (arith, count, V by the any-step rule), or None."""
    regs = {r: 0 for r in range(16)}       # registers start at 0 unless poked
    pokes = [(i, int(p[1][1:]), int(p[2], 16)) for i, p in enumerate(l.split() for l in v.lines)
             if len(p) == 3 and p[0] == 'P' and p[1][0] == 'R' and p[1][1:].isdigit()]
    ins = instructions(v.cycles())
    last = None
    for x in ins:
        while pokes and pokes[0][0] < x['if1']['i']:
            _, r, val = pokes.pop(0)
            regs[r] = val
        w = x['words']
        w0 = w[0]
        if w0 is None:
            continue
        if (w0 & 0xFFF0) == 0x2100 and len(w) > 1:                 # LD Rd,#imm
            regs[w0 & 15] = w[1]
            continue
        if (w0 & 0xF000) == 0xC000 or ((w0 & 0xFFF0) == 0x2000 and len(w) > 1):   # LDB Rbd,#imm
            d, imm = ((w0 >> 8) & 15, w0 & 0xFF) if w0 & 0xF000 == 0xC000 else (w0 & 15, w[1] & 0xFF)
            r = d & 7
            regs[r] = (regs[r] & 0x00FF) | (imm << 8) if d < 8 else (regs[r] & 0xFF00) | imm
            continue
        if (w0 & 0xFF00) == 0xBD00:                                 # LDK Rd,#n
            regs[(w0 >> 4) & 15] = w0 & 15
            continue
        sh = (w0 & 0xFE00) == 0xB200 and (w0 & 1) and not (w0 & 0x0100 == 0 and w0 & 4)
        if not sh:
            if not flag_neutral(w):
                last = None          # a later instruction may set the flags
            continue
        if len(w) < 2:
            raise SystemExit('%s: shift at %04X without its second word' % (v.path, x['if1']['addr']))
        byte, long_, dyn, arith = not (w0 & 0x0100), bool(w0 & 4), bool(w0 & 2), bool(w0 & 8)
        d = (w0 >> 4) & 15
        bits = 8 if byte else 32 if long_ else 16
        if dyn:
            cnt = signed(regs[(w[1] >> 8) & 15], 16)
        else:
            cnt = signed(w[1] & 0xFF, 8) if byte else signed(w[1], 16)
        if byte:
            val = (regs[d & 7] >> 8) & 0xFF if d < 8 else regs[d & 7] & 0xFF
        elif long_:
            val = (regs[d] << 16) | regs[d + 1]
        else:
            val = regs[d]
        vf, res = shift_v(val, abs(cnt), bits, cnt > 0, arith)
        if byte:
            r = d & 7
            regs[r] = (regs[r] & 0x00FF) | (res << 8) if d < 8 else (regs[r] & 0xFF00) | res
        elif long_:
            regs[d], regs[d + 1] = res >> 16, res & 0xFFFF
        else:
            regs[d] = res
        last = (arith, cnt, vf)
    if last is None:
        return None
    _, _, fregs = v.final_regs()
    for r, val in regs.items():
        if fregs[r] is not None and fregs[r] != val:
            raise SystemExit('%s: R%d works out to %04X, the vector has %04X' % (v.path, r, val, fregs[r]))
    return last


def rule_shiftv(v):
    if v.kind == 'serial':
        for i, l in enumerate(v.lines):
            p = l.split()
            if not p or p[0] != 'S' or int(p[2], 16) not in (0x0F, 0x10):
                continue
            bits, val, n = int(p[1]), int(p[3], 16), int(p[4])   # count in decimal
            vf, _ = shift_v(val, n, bits, int(p[2], 16) == 0x0F)
            serial_flags(v, i, p, 0x10, vf << 4)
        return
    last = shift_scan(v)
    if last is None or last[0]:
        return
    fcw = int(v.lines[fcw_line(v)].split()[-1], 16)
    v.set_final('FCW', (fcw & ~0x10) | (last[2] << 4), 4)


def rule_zeroc(v):
    """A shift by zero sets C."""
    if v.kind == 'serial':
        for i, l in enumerate(v.lines):
            p = l.split()
            if p and p[0] == 'S' and int(p[4]) == 0:
                serial_flags(v, i, p, 0x80, 0x80)
        return
    last = shift_scan(v)
    if last is None or last[1] != 0:
        return
    fcw = int(v.lines[fcw_line(v)].split()[-1], 16)
    v.set_final('FCW', fcw | 0x80, 4)


def serial_flags(v, i, p, bit, val):
    """An S record compares the flag bit and holds val in it."""
    flags, mask = int(p[7], 16), int(p[8], 16)
    nf, nm = (flags & ~bit) | val, mask | bit
    if (nf, nm) != (flags, mask):
        v.changes.append('line %d: flags %04X/%04X -> %04X/%04X' % (i + 1, flags, mask, nf, nm))
        p[7], p[8] = '%04X' % nf, '%04X' % nm
        v.lines[i] = ' '.join(p)


# ---- blockz ---------------------------------------------------------------------------

def is_block_move(w0):
    """LDI, LDIR, LDD, LDDR and the byte forms; block I/O, normal and special."""
    hi, lo = w0 >> 8, w0 & 15
    return (hi in (0xBA, 0xBB) and lo in (1, 9)) or (hi in (0x3A, 0x3B) and lo in (0, 1, 2, 3, 8, 9, 10, 11))


def flag_neutral(w):
    w0 = w[0]
    return (w0 in NO_FLAGS or (w0 & 0xFFF0) in (0x2100, 0x2000) or (w0 & 0xF000) == 0xC000
            or (w0 & 0xFF00) in (0xBD00, 0xA100, 0xA000, 0x9400)    # LDK, LD(B/L) R,R
            or (w0 & 0xFF00) in (0x5E00, 0x1E00, 0x5F00, 0x1F00, 0x9E00)  # JP, CALL, RET
            or (w0 & 0xE000) == 0xE000 or (w0 & 0xF000) == 0xD000)   # JR, DJNZ, CALR


def last_flag_writer(v, test):
    """The instruction that last wrote the flags, if test(words) picks it."""
    ins = instructions(v.cycles())
    found, other = None, None
    for x in ins:
        w = x['words']
        if w[0] is None:
            continue
        if test(w):
            found, other = x, None
        elif found is not None and not flag_neutral(w):
            other = w[0]
    return None if other is not None else found     # a later instruction wrote them


def fcw_line(v):
    return next(i for i, l in enumerate(v.lines) if l.startswith(('F FCW ', 'F C FCW ')))


def rule_blockz(v):
    """Block moves and block I/O set Z with V: the count reached 0."""
    if last_flag_writer(v, lambda w: is_block_move(w[0])) is None:
        return
    fcw = int(v.lines[fcw_line(v)].split()[-1], 16)
    vf = (fcw >> 4) & 1
    v.set_final('FCW', (fcw & ~0x40) | (vf << 6), 4)


# ---- comflg ---------------------------------------------------------------------------

def rule_comflg(v):
    """Every COMFLG complements H: H ends as the reset FCW's, complemented
    once per COMFLG, in a program that writes H no other way."""
    cyc = v.cycles()
    n, other = 0, False
    for x in instructions(cyc):
        w0 = x['words'][0]
        if w0 is None:
            continue
        if (w0 & 0xFF0F) == 0x8D05:
            n += 1
        elif not flag_neutral(x['words']):
            other = True
    if n == 0:
        return
    if other:
        raise SystemExit('%s: an instruction besides COMFLG may write H' % v.path)
    h = (cyc[0]['data'] >> 2) & 1 ^ (n & 1)
    fcw = int(v.lines[fcw_line(v)].split()[-1], 16)
    v.set_final('FCW', (fcw & ~0x04) | (h << 2), 4)


# ---- rldb -----------------------------------------------------------------------------

def rule_rldb(v):
    """RLDB/RRDB set S from bit 7 of the link byte (w0 bits 3:0)."""
    x = last_flag_writer(v, lambda w: (w[0] >> 8) in (0xBC, 0xBE))
    if x is None:
        return
    link = x['words'][0] & 15
    _, _, regs = v.final_regs()
    r = regs[link & 7]
    byte = (r >> 8) if link < 8 else (r & 0xFF)
    fcw = int(v.lines[fcw_line(v)].split()[-1], 16)
    v.set_final('FCW', (fcw & ~0x20) | ((byte >> 7) << 5), 4)


# ---- dab ------------------------------------------------------------------------------

def dab(a, h, d, c):
    """DAB: correct the low digit if H or above 9, the high digit (C set) if C
    or the byte above 0x99; after a subtraction (D) the corrections subtract."""
    lo, hi = h or (a & 15) > 9, c or a > 0x99
    v = (a + ((0xFA if d else 0x06) if lo else 0) + ((0xA0 if d else 0x60) if hi else 0)) & 0xFF
    return v, hi


def rule_dab(v):
    if v.kind != 'alu':
        raise SystemExit('%s: dab updates ALU vectors only' % v.path)
    for i, l in enumerate(v.lines):
        p = l.split()
        if not p or p[0] != 'A' or int(p[1], 16) != 0x15:
            continue
        a, b, cin = int(p[2], 16) & 0xFF, int(p[3], 16), int(p[4])
        val, c = dab(a, b & 1, (b >> 1) & 1, cin)
        flags = int(p[7], 16) & ~0xE0
        flags |= (0x80 if c else 0) | (0x40 if val == 0 else 0) | (0x20 if val & 0x80 else 0)
        nv = '%016X' % val
        nf = '%04X' % flags
        if (nv, nf) != (p[6], p[7]):
            v.changes.append('line %d: DAB %02X H=%d D=%d C=%d: %s %s -> %s %s' % (
                i + 1, a, b & 1, (b >> 1) & 1, cin, p[6][-2:], p[7], nv[-2:], nf))
            p[6], p[7] = nv, nf
            v.lines[i] = ' '.join(p)


# ---- lda ------------------------------------------------------------------------------

def rule_lda(v):
    """Segmented LDA DA/X with a short address word keeps the word's offset
    byte in bits 7:0 of the segment word it writes."""
    if not v.seg:
        return
    cyc = v.cycles()
    ins = instructions(cyc)
    if not ins or not (cyc[0]['data'] >> 15) & 1:
        return
    for n, x in enumerate(ins):
        w = x['words']
        if w[0] is None or (w[0] & 0xFF00) != 0x7600 or len(w) < 2 or w[1] & 0x8000:
            continue
        d = w[0] & 14
        for y in ins[n + 1:]:
            u = y['words'][0]
            if u in NO_FLAGS or (u & 0xFF00) == 0x7600 and (u & 14) != d:
                continue
            if (u & 0xFFF0) == 0x2100 and (u & 15) != d:
                continue
            raise SystemExit('%s: %04X after LDA may write R%d' % (v.path, u, d))
        _, _, regs = v.final_regs()
        v.set_reg(d, (regs[d] & 0xFF00) | (w[1] & 0xFF))


RULES = {'tr': rule_tr, 'zeroc': rule_zeroc, 'lda': rule_lda, 'dab': rule_dab, 'psap': rule_psap, 'pcseg': rule_pcseg, 'trt': rule_trt, 'shiftv': rule_shiftv,
         'blockz': rule_blockz, 'comflg': rule_comflg, 'rldb': rule_rldb}


def main(argv):
    if len(argv) < 3 or argv[1] not in RULES:
        sys.stderr.write(__doc__)
        return 2
    global INFERRED
    rule = RULES[argv[1]]
    check = '--check' in argv
    INFERRED = '--inferred' in argv
    n = 0
    for path in [a for a in argv[2:] if a not in ('--check', '--inferred')]:
        v = Vector(path)
        rule(v)
        if v.changes:
            n += 1
            print('%s:' % path)
            for c in v.changes:
                print('  ' + c)
            if not check:
                v.save()
    print('%s: %d files %s' % (argv[1], n, 'would change' if check else 'changed'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
