"""Catalogo delle configurazioni serie-parallelo (AND/OR), ogni barra al piu' una volta.
Ordine: per numero di barre usate k, poi per stringa della formula. Numerazione da 1.
Lettere A..F = ingressi hit[0]..hit[5] della FPGA (A = bit 0)."""
from functools import lru_cache

def key(t):                      # chiave canonica per ordinare i figli
    return (nleaves(t), render_raw(t))

def nleaves(t):
    return 1 if t == 'x' else sum(nleaves(c) for c in t[1:])

def render_raw(t):
    return 'x' if t == 'x' else t[0] + '(' + ','.join(render_raw(c) for c in t[1:]) + ')'

@lru_cache(None)
def formule(n, op):              # n foglie, radice op in {'A','O'}
    other = 'O' if op == 'A' else 'A'
    items = []
    for m in range(1, n):
        items += [(m, 'x')] if m == 1 else [(m, c) for c in formule(m, other)]
    items.sort(key=lambda mc: key(mc[1]))
    out = set()
    def rec(i, left, ch):
        if left == 0:
            if len(ch) >= 2:
                out.add((op,) + tuple(sorted(ch, key=key)))
            return
        for j in range(i, len(items)):
            m, c = items[j]
            if m <= left:
                rec(j, left - m, ch + [c])
    rec(0, n, [])
    return tuple(sorted(out, key=key))

def tutte(k):
    return ['x'] if k == 1 else list(formule(k, 'A')) + list(formule(k, 'O'))

def render(t, it, top=True):     # assegna le lettere in ordine di apparizione
    if t == 'x':
        return next(it)
    sep = '*' if t[0] == 'A' else '+'
    s = sep.join(render(c, it, False) for c in t[1:])
    return s if top or t[0] == 'A' and False else ('(' + s + ')')

def valuta(t, bits):
    it = iter(bits)
    def ev(g):
        if g == 'x': return next(it)
        v = [ev(c) for c in g[1:]]
        return all(v) if g[0] == 'A' else any(v)
    return ev(t)

catalogo = []
for k in range(1, 7):
    righe = []
    for f in tutte(k):
        s = render(f, iter('ABCDEF'))
        tt = 0
        for i in range(64):
            bits = [(i >> b) & 1 for b in range(6)]
            if valuta(f, bits):
                tt |= 1 << i
        righe.append((k, s, tt))
    catalogo += sorted(righe, key=lambda r: r[1])

assert len(catalogo) == 107 and len({r[2] for r in catalogo}) == 107

with open('catalogo.txt', 'w') as fh:
    for n, (k, s, tt) in enumerate(catalogo, 1):
        fh.write(f"{n:3d}  k={k}  {s:<22} 0x{tt:016X}\n")
with open('catalogo.mem', 'w') as fh:       # $readmemh: indice 0 = config 1
    for k, s, tt in catalogo:
        fh.write(f"{tt:016X}\n")
