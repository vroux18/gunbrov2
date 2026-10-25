"""Tenues de Jo, lot B (voir l'en-tête de tools/blender/jo_skins.py : contrat des parts, pipeline).

Cow-girl (agrume), Méca (sentinelle), Idole pop (lavande), Pompière (braise), Fée des aurores (aurore),
Astronaute cosmique (prisme). Construites avec les briques de jo.py / jo_lib.py, plus `sheet` (nappe épaisse
définie par une fonction : bord de chapeau relevé, ailes, pétales, visière).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from jo import *  # noqa


# ------------------------------------------------------------------ briques du lot
def sheet(fn, nu, nv, thick, col, closed=False, colf=None, under=None):
    """Nappe d'épaisseur `thick` : fn(u, v) -> point (u, v dans [0, 1]) ; `closed` : v boucle (bord de chapeau).
    colf(u, v) -> couleur ou None (bande) ; `under` : couleur de la face de dessous."""
    g = Geo()
    us = [i / nu for i in range(nu + 1)]
    vs = [j / nv for j in range(nv if closed else nv + 1)]
    nV = len(vs)
    e = 1e-3

    def nrm(u, v):
        du = V(fn(min(u + e, 1.0), v)) - V(fn(max(u - e, 0.0), v))
        if closed:
            dv = V(fn(u, v + e)) - V(fn(u, v - e))
        else:
            dv = V(fn(u, min(v + e, 1.0))) - V(fn(u, max(v - e, 0.0)))
        n = du.cross(dv)
        return n.normalized() if n.length > 1e-12 else Vector((0, 1, 0))

    T, B = [], []
    for u in us:
        tr, br = [], []
        for v in vs:
            p, n = V(fn(u, v)), nrm(u, v)
            g.v.append(p + n * thick * 0.5)
            tr.append(len(g.v) - 1)
            g.v.append(p - n * thick * 0.5)
            br.append(len(g.v) - 1)
        T.append(tr)
        B.append(br)
    base = hexcol(col)
    und = hexcol(under) if under else base
    jr = range(nV) if closed else range(nV - 1)
    for i in range(nu):
        for j in jr:
            j2 = (j + 1) % nV
            vm = (vs[j] + (vs[j2] if j2 else 1.0)) * 0.5
            c = colf((us[i] + us[i + 1]) * 0.5, vm) if colf else None
            c = hexcol(c) if c else base
            g.f.append((T[i][j], T[i + 1][j], T[i + 1][j2], T[i][j2]))
            g.col.append(c)
            g.f.append((B[i][j2], B[i + 1][j2], B[i + 1][j], B[i][j]))
            g.col.append(und if not colf else c if under is None else und)
    for i, flip in ((0, False), (nu, True)):
        for j in jr:
            j2 = (j + 1) % nV
            q = (T[i][j], T[i][j2], B[i][j2], B[i][j])
            g.f.append(tuple(reversed(q)) if flip else q)
            g.col.append(base)
    if not closed:
        for j, flip in ((0, True), (nV - 1, False)):
            for i in range(nu):
                q = (T[i][j], T[i + 1][j], B[i + 1][j], B[i][j])
                g.f.append(tuple(reversed(q)) if flip else q)
                g.col.append(base)
    return g


def seg(a, b, w, d, col, nc=1, ref=(1, 0, 0)):
    """Barre de a à b (demi-largeur w selon ref, demi-épaisseur d)."""
    return loft([S(a, w, d, min(w, d) * 0.5), S(b, w, d, min(w, d) * 0.5)], col, nc=nc, ref=ref)


def ring_y(y, a, b, z=0.0, col=INK, w=0.008, t=0.006, seg_n=24):
    """Anneau horizontal (ceinture, bracelet, bague de combinaison) : coque fermée basse."""
    return shell([{"c": (0, y - w, z), "a": a, "b": b, "a0": 0, "a1": 360},
                  {"c": (0, y + w, z), "a": a, "b": b, "a0": 0, "a1": 360}], t, col, seg=seg_n)


def limb_ring(c, axis, a, b, h, col, t=0.006, seg_n=16):
    """Bague autour d'un membre (centre c, axe du membre) : tube court."""
    c, ax = V(c), V(axis).normalized()
    return loft([S(c - ax * h, a, b, min(a, b) * 0.9, t=ax, nc=3), S(c + ax * h, a, b, min(a, b) * 0.9, t=ax, nc=3)], col, nc=3)


def boot(part, sx, col, sole=INK, top=0.27, top_col=None, toe=None, heel=0.0, point=0.0, wide=1.0, shaft_col=None,
         flare=0.0):
    """Botte : pied (tube le long de Z), talon `heel` (hauteur), bout pointu `point`, tige jusqu'à `top`."""
    x = sx * 0.077
    hy = heel
    fz = [(-0.062, 0.03, 0.038, 0.05 + hy * 0.6), (-0.045, 0.04, 0.046, 0.052 + hy * 0.55), (0.0, 0.043, 0.044, 0.05 + hy * 0.4),
          (0.06, 0.044, 0.03, 0.036 + hy * 0.15), (0.11, 0.036 - point * 0.3, 0.022, 0.03), (0.14 + point, 0.022 - point * 0.4, 0.014, 0.026)]
    ss = []
    for i, (z, a, b, yc) in enumerate(fz):
        s = S((x, yc, z), a * wide, b, min(a * wide, b) * 0.6)
        if toe and i >= 3:
            s["col"] = toe
        ss.append(s)
    part.add(loft(smooth(ss, 2), col, nc=2))
    # semelle
    sz = [(-0.064, 0.03), (-0.04, 0.042), (0.06, 0.046), (0.12, 0.036 - point * 0.3), (0.15 + point, 0.016)]
    part.add(loft([S((x, 0.008 + (hy if z < -0.02 else hy * max(0.0, (0.02 - z) / 0.06)), z), a * wide + 0.002, 0.008, 0.004)
                   for z, a in sz], sole, nc=1, ref=(1, 0, 0)))
    if hy > 0:
        part.add(box((x, hy * 0.5 + 0.004, -0.046), (0.026 * wide, hy * 0.5 + 0.004, 0.022), 0.004, sole))
    # tige
    ys = [0.06 + hy * 0.6, (0.06 + top) * 0.5, top]
    sc = shaft_col or col
    part.add(loft([S((x, ys[0], -0.012), 0.042 * wide, 0.048, 0.02), S((x, ys[1], -0.008), (0.041 + flare * 0.3) * wide, 0.045 + flare * 0.3, 0.02),
                   S((x, ys[2], -0.004), (0.043 + flare) * wide, 0.046 + flare, 0.02, col=top_col or sc),
                   S((x, ys[2] + 0.014, -0.004), (0.044 + flare) * wide, 0.047 + flare, 0.02)], sc, nc=2))


GOLD = "#F2B33D"
GOLD_D = "#C9861E"


# ------------------------------------------------------------------ Cow-girl
HAT = "#D27E2C"
HAT_D = "#93511A"
HAT_BAND = "#3E2112"
SHIRT = "#FFB619"
VEST = "#7A3F1E"
FRINGE = "#F0D39A"
JEANS = "#3E62B0"
JEANS_D = "#2C4887"
BOOT = "#5E321A"
BANDANA = "#E8352B"
AUBURN = "#A8461A"


def cowgirl():
    """Cow-girl : grand chapeau caramel à bord relevé sur les côtés, calotte pincée, bande sombre et étoile d'or ;
    tresse auburn qui flotte ; foulard rouge noué ; chemise jaune, gilet de cuir à franges ; ceinturon à grosse
    boucle, lasso à la hanche ; jean, bottes pointues à talon et éperons étoilés ; blaster crosse de bois."""
    m = Model("jo_cowgirl")
    head(m, iris="#4A6A2A")
    hair_bob(m, AUBURN, long_side=False)
    # tresse dans le dos : trois maillons qui flottent
    pv = [(0, 1.0, -0.1), (0, 0.88, -0.125), (0, 0.76, -0.135), (0, 0.66, -0.13)]
    segs = chain(m, "tresse", pv[:3], "head")
    hp = P(m, "hair")
    hp.add(loft([S((0, 1.08, -0.085), 0.03, 0.022), S(pv[0], 0.026, 0.02)], AUBURN, nc=2))
    for i, sg in enumerate(segs):
        a, b = Vector(pv[i]), Vector(pv[i + 1])
        n = 3
        for k in range(n):
            p = a + (b - a) * ((k + 0.5) / n)
            w = 0.026 - 0.004 * i - 0.0015 * k
            sg.add(ell(p + Vector(((-1) ** k * 0.005, 0, 0)), w, (b - a).length / n * 0.62, w * 0.8, AUBURN, n=4, nc=1,
                       up=(b - a).normalized()))
        if i == 2:
            sg.add(loft([S(b + Vector((0, 0.012, 0)), 0.016, 0.014, t=(0, 1, 0)), S(b - Vector((0, 0.004, 0)), 0.016, 0.014, t=(0, 1, 0))],
                        BANDANA, nc=1))
            sg.add(loft([S(b - Vector((0, 0.004, 0)), 0.014, 0.012), S(b - Vector((0, 0.05, -0.004)), 0.003, 0.003)], AUBURN, nc=1))
    # chapeau
    c = P(m, "coiffe")

    def brim(u, v):
        th = v * 2 * math.pi
        cx, sz = math.cos(th), math.sin(th)
        ra, rb = 0.104 + 0.118 * u, 0.116 + 0.124 * u
        y = 1.112 + 0.07 * (abs(cx) ** 2.2) * (u ** 1.6) - 0.012 * (sz ** 2) * u
        return (cx * ra, y, sz * rb - 0.01)
    c.add(sheet(brim, 5, 40, 0.012, HAT, closed=True, under=HAT_D,
                colf=lambda u, v: HAT_BAND if u > 0.86 else None))
    crown = [S((0, 1.1, -0.01), 0.104, 0.116), S((0, 1.16, -0.012), 0.101, 0.112, col=HAT_BAND), S((0, 1.188, -0.013), 0.098, 0.109),
             S((0, 1.24, -0.016), 0.088, 0.1), S((0, 1.272, -0.018), 0.074, 0.088)]
    cg = loft(smooth(crown, 2), HAT, nc=3)

    def pinch(p):
        p = Vector(p)
        if p.y > 1.2:
            k = (p.y - 1.2) / 0.072
            p.y -= 0.032 * max(0.0, 1.0 - (p.x / 0.06) ** 2) * k  # creux en long sur le dessus
            if p.z > 0:
                p.x *= 1.0 - 0.32 * k * min(1.0, p.z / 0.08)  # pincé devant
        return p
    cg.xform(pinch)
    c.add(cg)
    c.add(star((0, 1.172, 0.112), (0, 0, 1), 0.017, 0.007, 0.006, GOLD))
    # foulard rouge noué (zone col)
    col = P(m, "col")
    col.add(shell([{"c": (0, 0.885, -0.004), "a": 0.078, "b": 0.068, "a0": 0, "a1": 360},
                   {"c": (0, 0.93, -0.006), "a": 0.056, "b": 0.05, "a0": 0, "a1": 360}], 0.012, BANDANA, seg=24))
    col.add(loft([S((0, 0.905, 0.058), 0.05, 0.008, 0.004), S((0, 0.84, 0.086), 0.024, 0.007, 0.003), S((0, 0.8, 0.094), 0.002, 0.004, 0.001)],
                 BANDANA, nc=1))
    col.add(box((0.0, 0.9, 0.066), (0.016, 0.014, 0.012), 0.005, "#B81F1A"))
    for sx in (-1, 1):
        col.add(loft([S((sx * 0.01, 0.9, 0.07), 0.009, 0.005), S((sx * 0.03, 0.86, 0.08), 0.006, 0.004)], BANDANA, nc=1))
    for sx, y in ((-0.02, 0.86), (0.015, 0.83), (0.0, 0.88)):
        col.add(ell((sx, y, 0.088 - (0.9 - y) * 0.1), 0.004, 0.004, 0.003, "#FFF2D8", n=3, nc=1))
    # chemise jaune et gilet de cuir ouvert devant
    tg = torso(m, [
        (0.5, 0.06, 0.05, 0.0, None), (0.525, 0.1, 0.07, 0.0, None), (0.57, 0.108, 0.074, 0.0, None),
        (0.64, 0.096, 0.066, 0.002, None), (0.72, 0.102, 0.07, 0.006, None), (0.8, 0.122, 0.078, 0.01, None),
        (0.855, 0.136, 0.076, 0.004, None), (0.888, 0.13, 0.068, 0.0, None), (0.912, 0.085, 0.056, -0.004, None),
        (0.93, 0.04, 0.04, -0.004, None)], SHIRT)
    t = P(m, "torso")
    tg.paint(lambda c, n: c.y < 0.6, JEANS)
    seam(t, tg, [(0, 0.88, 0), (0, 0.66, 0)], (0, 0, -1), col="#C98A0E", w=0.0025)
    for y in (0.84, 0.78, 0.72, 0.67):
        p, n = surface(tg, (0, y, 0.5), (0, 0, -1))
        t.add(ell(p + Vector((0.008, 0, 0.002)), 0.004, 0.004, 0.003, "#FFF2D8", n=3, nc=1))
    vest = [{"c": (0, 0.6, 0.0), "a": 0.118, "b": 0.084}, {"c": (0, 0.65, 0.002), "a": 0.108, "b": 0.078},
            {"c": (0, 0.72, 0.006), "a": 0.114, "b": 0.082}, {"c": (0, 0.8, 0.01), "a": 0.134, "b": 0.09},
            {"c": (0, 0.855, 0.004), "a": 0.147, "b": 0.088}, {"c": (0, 0.895, 0.0), "a": 0.134, "b": 0.078}]
    for k, s in enumerate(vest):
        o = 16 if s["c"][1] < 0.7 else 16 + (s["c"][1] - 0.7) * 100
        s["a0"], s["a1"] = 90 + o, 450 - o
    vg = shell(smooth(vest, 2), 0.01, VEST, inner="#4E2612", seg=30)
    t.add(vg)
    # franges : sous l'ourlet du gilet et sur l'empiècement du dos
    for k in range(26):
        th = math.radians(90 + 32 + k * (296 / 25))
        cx, sz = math.cos(th), math.sin(th)
        a = Vector((cx * 0.116, 0.598, sz * 0.082))
        L = 0.06 + 0.012 * ((k % 3) == 1)
        ribbon(t, a, a + Vector((cx * 0.008, -L, sz * 0.008)), 0.0075, 0.005, 0.003, FRINGE, side=(-sz, 0, cx))
    for k in range(13):
        th = math.radians(200 + k * (140 / 12))
        cx, sz = math.cos(th), math.sin(th)
        y0 = 0.82 - 0.03 * (1 - abs(cx) / 0.95)
        rr = (0.128, 0.088)
        a = Vector((cx * rr[0], y0, sz * rr[1] - 0.004))
        ribbon(t, a, a + Vector((cx * 0.006, -0.05, sz * 0.012 - 0.004)), 0.007, 0.005, 0.003, FRINGE, side=(-sz, 0, cx))
    t.add(shell([{"c": (0, 0.818, 0.006), "a": 0.131, "b": 0.09, "a0": 200, "a1": 340},
                 {"c": (0, 0.83, 0.006), "a": 0.133, "b": 0.09, "a0": 200, "a1": 340}], 0.006, FRINGE, seg=14))
    # ceinturon, grosse boucle, étui
    t.add(loft([S((0, 0.555, 0.0), 0.112, 0.078), S((0, 0.585, 0.0), 0.11, 0.077)], VEST, nc=2))
    t.add(box((0, 0.57, 0.08), (0.03, 0.022, 0.006), 0.005, GOLD))
    t.add(box((0, 0.57, 0.087), (0.018, 0.012, 0.003), 0.002, GOLD_D))
    t.add(box((0.125, 0.5, 0.01), (0.02, 0.05, 0.03), 0.008, VEST, up=(0.25, 1, 0)))
    # lasso à la hanche gauche (zone dos)
    d = P(m, "dos")
    for k in range(3):
        d.add(torus((0.122 + 0.006 * k, 0.53, -0.055), (1, 0, -0.35), 0.056 - 0.004 * k, 0.0055, "#E9C77A", seg=22, rs=4))
    d.add(box((0.124, 0.585, -0.05), (0.012, 0.012, 0.016), 0.004, VEST))
    # bras : manches jaunes, gants de cuir à crispin
    arms(m, SHIRT, BOOT, cuff=FRINGE, cuff_y=0.62, wide=1.08)
    for side, sx in sides():
        a = P(m, "arm_" + side)
        a.add(shell([{"c": (sx * 0.183, 0.62, 0.022), "a": 0.034, "b": 0.034, "a0": 0, "a1": 360},
                     {"c": (sx * 0.187, 0.565, 0.04), "a": 0.03, "b": 0.03, "a0": 0, "a1": 360}], 0.008, BOOT, seg=16))
        for k in range(5):
            th = math.radians(-70 + k * 35) if sx > 0 else math.radians(250 - k * 35)
            o = Vector((sx * 0.183 + math.cos(th) * 0.04, 0.625, 0.022 + math.sin(th) * 0.04))
            ribbon(a, o, o + Vector((math.cos(th) * 0.004, -0.03, math.sin(th) * 0.004)), 0.007, 0.004, 0.003, FRINGE,
                   side=(-math.sin(th), 0, math.cos(th)))
    # jean, bottes pointues à talon et éperons
    legs(m, JEANS, None, None, None)
    for side, sx in sides():
        s = P(m, "shin_" + side)
        s.add(box((sx * 0.075, 0.33, 0.036), (0.026, 0.03, 0.006), 0.006, JEANS_D))
        b = P(m, "jambe_" + side)
        boot(b, sx, BOOT, sole="#2A160C", top=0.28, top_col="#8C5530", heel=0.02, point=0.03)
        x = sx * 0.077
        for k in range(3):
            b.add(box((x + sx * 0.0425, 0.13 + k * 0.035, -0.01), (0.002, 0.012, 0.012), 0.002, GOLD, up=(0, 1, 0.2 * k - 0.2)))
        # éperon : sangle d'or, tige, molette étoilée
        b.add(loft([S((x, 0.075, -0.07), 0.046, 0.004, 0.002, t=(0, 1, 0)), S((x, 0.085, -0.07), 0.046, 0.004, 0.002, t=(0, 1, 0))],
                   GOLD_D, nc=1))
        b.add(seg((x, 0.072, -0.074), (x, 0.066, -0.11), 0.004, 0.004, GOLD))
        b.add(star((x, 0.066, -0.118), (1, 0, 0), 0.02, 0.008, 0.004, GOLD, n=6))
    blaster(m, shell_col="#8C5530", stripe=GOLD, metal="#3A2414", glow="#B8FF6A")
    return m


# ------------------------------------------------------------------ Méca
ARMOR = "#EEF2F7"
ARMOR_D = "#B9C2D2"
ORANGE = "#FF7A1A"
ORANGE_D = "#C9530C"
UNDER = "#2C3350"
JOINT = "#191C2C"
CYANG = "#6FF3FF"


def meca():
    """Méca : Jo dans une armure robotique blanche et orange. Casque fermé sur le crâne, ouvert sur le visage,
    visière lumineuse relevée sur le front, modules latéraux à anneau lumineux et antenne ; plastron à évents
    lumineux, épaulières carrées orange, gantelets massifs, cuissards, genouillères, jambières et sabots ;
    petit réacteur dorsal à deux tuyères lumineuses."""
    m = Model("jo_meca")
    head(m, iris="#2A6A8A")
    bangs(m, "#2A1E2A")
    c = P(m, "coiffe")
    hs = [((0, 0.94, -0.016), 0.098, 0.106, 58), ((0, 0.99, -0.014), 0.106, 0.116, 56), ((0, 1.05, -0.012), 0.109, 0.12, 56),
          ((0, 1.1, -0.012), 0.108, 0.12, 50), ((0, 1.135, -0.013), 0.104, 0.116, 32), ((0, 1.175, -0.015), 0.094, 0.106, 1),
          ((0, 1.215, -0.016), 0.07, 0.082, 1), ((0, 1.242, -0.016), 0.036, 0.044, 1), ((0, 1.252, -0.016), 0.006, 0.008, 1)]
    hg = shell(smooth([{"c": cc, "a": a, "b": b, "a0": 90 + o, "a1": 450 - o} for cc, a, b, o in hs], 2), 0.014, ARMOR,
               inner=UNDER, seg=32)
    hg.paint(lambda c, n: abs(c.x) < 0.036 and c.y > 1.13 and c.z < 0.1, ORANGE)
    hg.paint(lambda c, n: c.y < 0.975, ARMOR_D)
    c.add(hg)
    # crête et arête du casque
    c.add(loft([S((0, 1.2, 0.09), 0.006, 0.01), S((0, 1.255, 0.02), 0.008, 0.012), S((0, 1.25, -0.07), 0.008, 0.012),
                S((0, 1.2, -0.13), 0.006, 0.01)], ORANGE_D, nc=1))
    # modules latéraux et antenne
    for sx in (-1, 1):
        c.add(loft([S((sx * 0.112, 1.06, -0.012), 0.038, 0.038, 0.012, t=(1, 0, 0)), S((sx * 0.134, 1.06, -0.012), 0.034, 0.034, 0.01, t=(1, 0, 0))],
                   ARMOR, nc=2))
        c.add(disc((sx * 0.136, 1.06, -0.012), (sx, 0, 0), 0.0, 0.026, 0.006, UNDER, seg=20))
        P(m, "coiffe_glow").add(disc((sx * 0.1395, 1.06, -0.012), (sx, 0, 0), 0.014, 0.021, 0.003, CYANG, seg=20))
    c.add(seg((0.13, 1.08, -0.03), (0.15, 1.24, -0.08), 0.004, 0.004, JOINT))
    P(m, "coiffe_glow").add(ell((0.151, 1.245, -0.082), 0.009, 0.009, 0.009, "#FF9A3D", n=4, nc=1))
    # visière lumineuse relevée sur le front
    cg = P(m, "coiffe_glow")
    cg.add(shell([{"c": (0, 1.124, -0.012), "a": 0.124, "b": 0.138, "a0": 30, "a1": 150},
                  {"c": (0, 1.172, -0.02), "a": 0.11, "b": 0.126, "a0": 34, "a1": 146}], 0.008, CYANG, seg=18))
    c.add(shell([{"c": (0, 1.116, -0.012), "a": 0.123, "b": 0.135, "a0": 28, "a1": 152},
                 {"c": (0, 1.124, -0.012), "a": 0.124, "b": 0.136, "a0": 28, "a1": 152}], 0.01, UNDER, seg=18))
    # joues blindées orange, ailerons sur la nuque
    for sx in (-1, 1):
        c.add(box((sx * 0.088, 1.0, 0.07), (0.012, 0.05, 0.03), 0.006, ORANGE, up=(sx * -0.15, 1, 0.25), ref=(1, 0, -sx * 0.6)))
    # mentonnière (zone visage)
    v = P(m, "visage")
    v.add(shell([{"c": (0, 0.925, -0.004), "a": 0.09, "b": 0.098, "a0": 0, "a1": 360},
                 {"c": (0, 0.952, -0.004), "a": 0.094, "b": 0.104, "a0": 0, "a1": 360, "col": ORANGE},
                 {"c": (0, 0.958, -0.004), "a": 0.094, "b": 0.104, "a0": 0, "a1": 360}], 0.012, ARMOR, inner=UNDER, seg=28))
    # gorgerin
    P(m, "col").add(shell([{"c": (0, 0.87, -0.004), "a": 0.09, "b": 0.074, "a0": 0, "a1": 360},
                           {"c": (0, 0.925, -0.006), "a": 0.07, "b": 0.06, "a0": 0, "a1": 360}], 0.012, UNDER, seg=24))
    # combinaison et plastron
    tg = torso(m, [
        (0.5, 0.06, 0.05, 0.0, JOINT), (0.525, 0.1, 0.07, 0.0, None), (0.57, 0.108, 0.074, 0.0, None),
        (0.64, 0.096, 0.066, 0.002, None), (0.72, 0.1, 0.07, 0.006, None), (0.8, 0.12, 0.078, 0.01, None),
        (0.855, 0.134, 0.076, 0.004, None), (0.888, 0.13, 0.068, 0.0, None), (0.912, 0.085, 0.056, -0.004, None),
        (0.93, 0.04, 0.04, -0.004, None)], UNDER)
    t = P(m, "torso")
    plate = [S((0, 0.69, 0.008), 0.112, 0.082, 0.02), S((0, 0.74, 0.012), 0.128, 0.09, 0.022), S((0, 0.82, 0.014), 0.142, 0.096, 0.024),
             S((0, 0.87, 0.006), 0.146, 0.09, 0.024, col=ORANGE), S((0, 0.885, 0.004), 0.142, 0.086, 0.022), S((0, 0.905, 0.0), 0.11, 0.07, 0.02)]
    pg = loft(plate, ARMOR, nc=2)
    t.add(pg)
    tl = extra(m, "torso_glow", "torso")
    for sx in (-1, 1):
        for k in range(3):
            p, n = surface(pg, (sx * 0.05, 0.8 - k * 0.022, 0.5), (0, 0, -1))
            t.add(box(p + Vector((0, 0, 0.001)), (0.034, 0.007, 0.004), 0.002, JOINT))
            tl.add(box(p + Vector((0, 0, 0.004)), (0.028, 0.0035, 0.002), 0.001, CYANG))
    p, n = surface(pg, (0, 0.76, 0.5), (0, 0, -1))
    t.add(box(p + Vector((0, 0, 0.002)), (0.012, 0.05, 0.004), 0.003, ORANGE))
    # abdomen en segments, ceinture et tassettes
    for k in range(3):
        t.add(loft([S((0, 0.63 + k * 0.022, 0.002), 0.1 + 0.002 * k, 0.072, 0.02), S((0, 0.646 + k * 0.022, 0.002), 0.098 + 0.002 * k, 0.07, 0.02)],
                   ARMOR_D if k % 2 else ARMOR, nc=2))
    t.add(loft([S((0, 0.565, 0.0), 0.116, 0.082, 0.02), S((0, 0.61, 0.0), 0.112, 0.08, 0.02)], JOINT, nc=2))
    t.add(box((0, 0.588, 0.083), (0.03, 0.018, 0.006), 0.004, ORANGE))
    for sx, z in ((0, 1), (0, -1)):
        t.add(box((0, 0.535, z * 0.08), (0.07, 0.04, 0.008), 0.006, ARMOR, up=(0, 1, z * 0.25)))
    for sx in (-1, 1):
        t.add(box((sx * 0.112, 0.53, 0.0), (0.008, 0.045, 0.05), 0.005, ARMOR, up=(sx * 0.3, 1, 0)))
    # épaulières carrées
    for side, sx in sides():
        e = P(m, "epaule_" + side)
        e.add(box((sx * 0.198, 0.91, -0.004), (0.074, 0.028, 0.086), 0.012, ORANGE, up=(sx * 0.3, 1, 0), nc=2))
        e.add(box((sx * 0.215, 0.862, -0.004), (0.058, 0.032, 0.076), 0.01, ARMOR, up=(sx * 0.45, 1, 0), nc=2))
        e.add(box((sx * 0.172, 0.93, -0.004), (0.03, 0.006, 0.05), 0.004, ORANGE_D, up=(sx * 0.3, 1, 0)))
        P(m, "epaule_%s_glow" % side).add(box((sx * 0.266, 0.86, -0.004), (0.003, 0.006, 0.054), 0.001, CYANG, up=(sx * 0.45, 1, 0)))
    # bras : sous-combinaison, brassards, gantelets massifs
    arms(m, UNDER, ARMOR, wide=1.0)
    for side, sx in sides():
        a = P(m, "arm_" + side)
        a.add(box((sx * 0.168, 0.78, -0.006), (0.04, 0.05, 0.044), 0.012, ARMOR, up=(sx * 0.12, 1, 0), nc=2))
        a.add(ell((sx * 0.177, 0.705, -0.01), 0.032, 0.026, 0.03, JOINT, n=4))
        a.add(loft([S((sx * 0.18, 0.672, 0.008), 0.042, 0.042, 0.012), S((sx * 0.184, 0.62, 0.022), 0.046, 0.046, 0.012),
                    S((sx * 0.188, 0.565, 0.04), 0.044, 0.044, 0.012, col=ORANGE), S((sx * 0.188, 0.55, 0.044), 0.044, 0.044, 0.012)],
                   ARMOR, nc=2))
        a.add(box((sx * 0.19, 0.505, 0.054), (0.028, 0.032, 0.032), 0.012, ARMOR, nc=2))
        a.add(box((sx * 0.19, 0.478, 0.058), (0.026, 0.008, 0.03), 0.004, JOINT))
        P(m, "arm_%s_glow" % side).add(box((sx * 0.231, 0.62, 0.022), (0.002, 0.03, 0.012), 0.001, CYANG, up=(0, 1, 0.25)))
    # jambes : cuissards, genouillères, jambières, sabots
    legs(m, UNDER, None, None, None)
    for side, sx in sides():
        l = P(m, "leg_" + side)
        l.add(loft([S((sx * 0.07, 0.55, 0.014), 0.06, 0.062, 0.016), S((sx * 0.073, 0.46, 0.016), 0.054, 0.056, 0.016),
                    S((sx * 0.075, 0.39, 0.012), 0.046, 0.05, 0.014)], ARMOR, nc=2))
        s = P(m, "shin_" + side)
        s.add(box((sx * 0.075, 0.335, 0.04), (0.04, 0.034, 0.016), 0.012, ORANGE, nc=2))
        s.add(loft([S((sx * 0.075, 0.3, 0.008), 0.048, 0.052, 0.014), S((sx * 0.076, 0.2, 0.004), 0.05, 0.054, 0.014),
                    S((sx * 0.076, 0.13, 0.0), 0.046, 0.05, 0.014)], ARMOR, nc=2))
        s.add(box((sx * 0.076, 0.24, 0.055), (0.012, 0.04, 0.006), 0.004, ORANGE))
        b = P(m, "jambe_" + side)
        x = sx * 0.077
        b.add(loft([S((x, 0.07, -0.07), 0.046, 0.04, 0.012, t=(0, 0, 1)), S((x, 0.075, -0.02), 0.054, 0.05, 0.014, t=(0, 0, 1)),
                    S((x, 0.06, 0.08), 0.054, 0.04, 0.014, t=(0, 0, 1), col=ORANGE), S((x, 0.05, 0.135), 0.046, 0.03, 0.012, t=(0, 0, 1)),
                    S((x, 0.045, 0.16), 0.03, 0.02, 0.01, t=(0, 0, 1))], ARMOR, nc=2, ref=(1, 0, 0)))
        b.add(loft([S((x, 0.012, z), a, 0.012, 0.006, t=(0, 0, 1)) for z, a in ((-0.075, 0.046), (0.0, 0.056), (0.14, 0.048), (0.165, 0.03))],
                   JOINT, nc=1, ref=(1, 0, 0)))
        b.add(loft([S((x, 0.1, -0.01), 0.05, 0.054, 0.014), S((x, 0.15, -0.005), 0.05, 0.054, 0.014)], ARMOR_D, nc=2))
    # réacteur dorsal
    d = P(m, "dos")
    d.add(box((0, 0.79, -0.122), (0.084, 0.095, 0.042), 0.016, ARMOR, nc=2))
    d.add(box((0, 0.875, -0.124), (0.07, 0.014, 0.036), 0.008, ORANGE))
    d.add(box((0, 0.79, -0.166), (0.03, 0.06, 0.004), 0.003, UNDER))
    for sx in (-1, 1):
        # ailerons stabilisateurs (lisibles de dessus)
        d.add(box((sx * 0.13, 0.855, -0.15), (0.06, 0.01, 0.034), 0.005, ORANGE, up=(sx * -0.35, 1, 0), ref=(1, 0, 0.3 * sx)))
        d.add(box((sx * 0.186, 0.835, -0.152), (0.006, 0.016, 0.036), 0.003, ARMOR, up=(sx * -0.35, 1, 0)))
        d.add(loft([S((sx * 0.05, 0.71, -0.135), 0.026, 0.026, 0.012), S((sx * 0.05, 0.66, -0.14), 0.03, 0.03, 0.012),
                    S((sx * 0.05, 0.645, -0.142), 0.033, 0.033, 0.012)], JOINT, nc=2))
    dg = P(m, "dos_glow")
    dg.add(box((0, 0.79, -0.171), (0.012, 0.045, 0.003), 0.001, CYANG))
    for sx in (-1, 1):
        dg.add(disc((sx * 0.05, 0.643, -0.142), (0, -1, 0), 0.0, 0.024, 0.004, CYANG, seg=16))
        dg.add(loft([S((sx * 0.05, 0.64, -0.142), 0.018, 0.018, 0.008), S((sx * 0.05, 0.58, -0.146), 0.002, 0.002, 0.001)], "#C9FBFF", nc=2))
    blaster(m, shell_col=ARMOR, stripe=ORANGE, metal=UNDER, glow=CYANG)
    return m


# ------------------------------------------------------------------ Idole pop
IDOL = "#6B3BE6"
IDOL_D = "#4422A8"
IDOL_W = "#F6F2FF"
PINKH = "#FF8FD2"
PINKH_D = "#E0569F"
BOW = "#36DDF0"
STARY = "#FFE27A"


def _tail(m, name, sx):
    """Couette : racine fixe (cheveux) qui tombe le long de la tête, puis deux maillons qui flottent (ils restent
    sous la tête vue de face : pas de pointes dressées) ; étoile lumineuse à la racine."""
    pv = [(sx * 0.1, 1.15, -0.03), (sx * 0.165, 1.02, -0.07), (sx * 0.19, 0.87, -0.085), (sx * 0.18, 0.68, -0.07)]
    hp = P(m, "hair")
    segs = [hp] + chain(m, name, pv[1:3], "head")
    ws = [(0.04, 0.046), (0.046, 0.034), (0.034, 0.004)]
    for i, sg in enumerate(segs):
        a, b = Vector(pv[i]), Vector(pv[i + 1])
        w0, w1 = ws[i]
        mid = (a + b) * 0.5 + Vector((sx * 0.012, 0, -0.006))
        sg.add(loft(smooth([S(a, w0, w0 * 0.72), S(mid, (w0 + w1) * 0.56, (w0 + w1) * 0.4), S(b, w1, w1 * 0.72)], 2), PINKH, nc=2,
                    ref=(0, 0, 1)))
        if i == 2:  # pointes en mèches
            for k in (-1, 1):
                sg.add(loft([S(mid, 0.012, 0.01), S(b + Vector((k * 0.03, 0.02, k * 0.012)), 0.002, 0.002)], PINKH_D, nc=1))
    hp.add(torus(Vector(pv[0]) + Vector((sx * 0.006, -0.012, 0)), (sx * 0.5, -0.8, -0.3), 0.034, 0.008, IDOL, seg=16, rs=4))
    P(m, "hair_glow").add(star(Vector(pv[0]) + Vector((sx * 0.01, 0.022, 0.02)), (sx * 0.4, 0.5, 0.75), 0.034, 0.014, 0.008, STARY))


def idole():
    """Idole pop : longues couettes roses qui volent, étoiles lumineuses en barrettes, micro-casque ; tenue de
    scène violette à col marin blanc et nœud cyan, manches bouffantes, gants longs, jupe plissée à deux étages
    semée d'étoiles, grand nœud cyan dans le dos dont les pans flottent, bottes hautes blanches."""
    m = Model("jo_idole")
    head(m, iris="#7A3AC8")
    hp = hair_bob(m, PINKH, hi="#FFC2E6", long_side=False)
    for sx in (-1, 1):
        _tail(m, "couette_" + ("r" if sx < 0 else "l"), sx)
    # micro-casque (serre-tête, écouteurs) et micro (zone visage)
    c = P(m, "coiffe")
    band = []
    for k in range(13):
        th = math.radians(180 * k / 12)
        band.append(S((math.cos(th) * 0.1, 1.05 + math.sin(th) * 0.172, -0.016), 0.006, 0.012, 0.004))
    c.add(loft(band, IDOL_W, nc=1, ref=(0, 0, 1)))
    for sx in (-1, 1):
        c.add(loft([S((sx * 0.092, 1.05, -0.006), 0.03, 0.03, 0.012, t=(1, 0, 0)), S((sx * 0.112, 1.05, -0.006), 0.028, 0.028, 0.01, t=(1, 0, 0))],
                   IDOL, nc=2))
        c.add(disc((sx * 0.1135, 1.05, -0.006), (sx, 0, 0), 0.0, 0.02, 0.004, IDOL_W, seg=16))
    v = P(m, "visage")
    v.add(loft(smooth([S((0.11, 1.03, 0.0), 0.004, 0.004), S((0.1, 0.99, 0.05), 0.004, 0.004), S((0.05, 0.975, 0.088), 0.004, 0.004)], 2),
               IDOL_W, nc=1))
    v.add(ell((0.042, 0.976, 0.09), 0.009, 0.007, 0.007, IDOL_D, n=3, nc=1))
    # bustier violet, col marin blanc, nœud cyan
    tg = torso(m, [
        (0.5, 0.06, 0.05, 0.0, None), (0.525, 0.1, 0.07, 0.0, None), (0.57, 0.108, 0.074, 0.0, None),
        (0.6, 0.1, 0.07, 0.002, IDOL_W), (0.625, 0.097, 0.067, 0.002, None), (0.72, 0.1, 0.07, 0.006, None),
        (0.8, 0.12, 0.078, 0.01, None), (0.855, 0.132, 0.076, 0.004, None), (0.888, 0.128, 0.068, 0.0, None),
        (0.912, 0.085, 0.056, -0.004, None), (0.93, 0.04, 0.04, -0.004, SKIN)], IDOL)
    t = P(m, "torso")
    for sx in (-0.05, 0.0, 0.05):
        seam(t, tg, [(sx, 0.79, 0), (sx * 1.1, 0.64, 0)], (0, 0, -1), col=IDOL_D, w=0.0024)
    col = P(m, "col")
    col.add(shell([{"c": (0, 0.885, -0.004), "a": 0.124, "b": 0.08, "a0": 120, "a1": 420},
                   {"c": (0, 0.9, -0.006), "a": 0.1, "b": 0.066, "a0": 118, "a1": 422},
                   {"c": (0, 0.925, -0.006), "a": 0.06, "b": 0.05, "a0": 110, "a1": 430}], 0.01, IDOL_W, seg=24))
    col.add(shell([{"c": (0, 0.84, -0.012), "a": 0.124, "b": 0.08, "a0": 215, "a1": 325},
                   {"c": (0, 0.89, -0.006), "a": 0.126, "b": 0.078, "a0": 205, "a1": 335}], 0.008, IDOL_W, inner=IDOL_W, seg=12))
    col.add(loft([S((-0.06, 0.848, -0.088), 0.003, 0.003), S((0.06, 0.848, -0.088), 0.003, 0.003)], IDOL, nc=1))
    for sx in (-1, 1):
        col.add(loft([S((0, 0.835, 0.088), 0.008, 0.012, 0.004, t=(sx, 0, 0)), S((sx * 0.04, 0.85, 0.084), 0.004, 0.026, 0.004, t=(sx, 0, 0))],
                     BOW, nc=1))
        col.add(loft([S((sx * 0.006, 0.83, 0.088), 0.008, 0.004), S((sx * 0.02, 0.77, 0.092), 0.012, 0.003)], BOW, nc=1, ref=(1, 0, 0)))
    col.add(box((0, 0.835, 0.09), (0.009, 0.01, 0.008), 0.004, "#1FB4C8"))
    P(m, "col_glow").add(star((0, 0.735, 0.084), (0, 0.15, 1), 0.026, 0.011, 0.006, STARY))
    # jupe plissée à deux étages, jupon blanc
    t.add(shell([{"c": (0, 0.6, 0.0), "a": 0.112, "b": 0.08, "a0": 0, "a1": 360, "wave": (0.0, 28)},
                 {"c": (0, 0.5, 0.0), "a": 0.172, "b": 0.14, "a0": 0, "a1": 360, "wave": (0.05, 28)},
                 {"c": (0, 0.43, 0.0), "a": 0.214, "b": 0.18, "a0": 0, "a1": 360, "wave": (0.06, 28)}], 0.008, IDOL_W, seg=56))
    t.add(shell([{"c": (0, 0.615, 0.0), "a": 0.11, "b": 0.078, "a0": 0, "a1": 360, "wave": (0.0, 24)},
                 {"c": (0, 0.52, 0.0), "a": 0.168, "b": 0.136, "a0": 0, "a1": 360, "wave": (0.07, 24)},
                 {"c": (0, 0.47, 0.0), "a": 0.2, "b": 0.168, "a0": 0, "a1": 360, "wave": (0.08, 24), "col": IDOL_W},
                 {"c": (0, 0.455, 0.0), "a": 0.208, "b": 0.176, "a0": 0, "a1": 360, "wave": (0.08, 24)}], 0.01, IDOL, inner=IDOL_D, seg=48))
    t.add(loft([S((0, 0.598, 0.0), 0.106, 0.075), S((0, 0.625, 0.0), 0.102, 0.072)], IDOL_W, nc=2))
    sg = extra(m, "jupe_glow", "torso")
    for i in range(10):
        a = math.radians(i * 36 + 18)
        y = 0.5 if i % 2 else 0.54
        k = (0.615 - y) / (0.615 - 0.47)
        ra, rb = 0.11 + (0.2 - 0.11) * k + 0.012, 0.078 + (0.168 - 0.078) * k + 0.012
        nrm = Vector((math.cos(a) / ra, 0.5, math.sin(a) / rb)).normalized()
        sg.add(star(Vector((math.cos(a) * ra, y, math.sin(a) * rb)) + nrm * 0.004, nrm, 0.018, 0.0075, 0.004,
                    STARY if i % 2 else "#9FF6FF", spin=i * 23))
    # manches bouffantes (épaules), gants longs blancs
    for side, sx in sides():
        e = P(m, "epaule_" + side)
        e.add(ell((sx * 0.158, 0.865, -0.002), 0.06, 0.05, 0.062, IDOL_W, n=6, nc=3))
        e.add(loft([S((sx * 0.168, 0.825, -0.004), 0.05, 0.05, 0.02), S((sx * 0.17, 0.81, -0.004), 0.046, 0.046, 0.02)], IDOL, nc=2))
        P(m, "epaule_%s_glow" % side).add(star((sx * 0.2, 0.89, 0.0), (sx, 0.6, 0.2), 0.02, 0.008, 0.004, BOW))
    arms(m, SKIN, IDOL_W, wide=0.92)
    for side, sx in sides():
        a = P(m, "arm_" + side)
        a.geo.paint(lambda c, n: c.y < 0.72, IDOL_W)
        a.add(loft([S((sx * 0.176, 0.73, -0.006), 0.034, 0.035), S((sx * 0.176, 0.712, -0.006), 0.034, 0.035)], IDOL, nc=2))
    # jambes, bottes hautes
    legs(m, SKIN, None, None, None, short=IDOL_D)
    for side, sx in sides():
        b = P(m, "jambe_" + side)
        boot(b, sx, IDOL_W, sole=IDOL_D, top=0.37, top_col=IDOL, heel=0.03, wide=1.0, flare=0.006)
        P(m, "jambe_%s_glow" % side).add(star((sx * 0.077, 0.3, 0.055), (0, 0.1, 1), 0.016, 0.007, 0.004, STARY))
    # grand nœud cyan dans le dos, pans qui flottent
    d = P(m, "dos")
    for sx in (-1, 1):
        d.add(loft(smooth([S((sx * 0.012, 0.62, -0.09), 0.012, 0.02, 0.006, t=(sx, 0, 0)), S((sx * 0.07, 0.66, -0.1), 0.006, 0.05, 0.006, t=(sx, 0.4, 0)),
                           S((sx * 0.105, 0.64, -0.1), 0.006, 0.042, 0.006, t=(sx, -0.4, 0))], 2), BOW, nc=2, ref=(0, 0, 1)))
    d.add(box((0, 0.622, -0.094), (0.016, 0.02, 0.012), 0.006, "#1FB4C8"))
    pv = [(0, 0.61, -0.1), (0, 0.5, -0.125), (0, 0.4, -0.14), (0, 0.31, -0.15)]
    segs = chain(m, "dos", pv[:3], "torso")
    for k, sx in ((1.0, 1), (0.9, -1)):
        for i, sgm in enumerate(segs):
            a = Vector(pv[i]) + Vector((sx * (0.012 + 0.016 * i), 0, 0))
            bb = Vector(pv[i]) + (Vector(pv[i + 1]) - Vector(pv[i])) * k + Vector((sx * (0.012 + 0.016 * (i + 1)), 0, 0))
            ribbon(sgm, a, bb, 0.034, 0.032 - (0.02 if i == 2 else 0.0), 0.005, BOW)
    blaster(m, shell_col=IDOL_W, stripe=IDOL, metal=IDOL_D, glow=BOW)
    P(m, "gun_glow").add(star(Vector(PIV["gun"]) + Vector((0, -0.07, 0.1)), (0, 0, 1), 0.016, 0.007, 0.004, STARY))
    return m


# ------------------------------------------------------------------ Pompière
FIRE = "#E4261A"
FIRE_D = "#9E140E"
TAN = "#C8923A"
TAN_D = "#8E6224"
LIME = "#E8FF5A"
SILVER = "#D7DDE6"
TANK = "#E3E8EF"
RUBBER = "#1C1D22"


def _band_ring(part, y, a, b, z=0.0, h=0.012, t=0.006, a0=0, a1=360, seg_n=28):
    part.add(shell([{"c": (0, y - h, z), "a": a, "b": b, "a0": a0, "a1": a1},
                    {"c": (0, y + h, z), "a": a, "b": b, "a0": a0, "a1": a1}], t, LIME, seg=seg_n))


def pompiere():
    """Pompière : casque rouge à longue nuque, crêtes, écusson d'or dressé devant, grande visière dorée relevée,
    lampe ; couvre-nuque qui flotte ; veste de feu sable à col montant et bandes réfléchissantes lumineuses
    (torse, bras, jambes) ; bouteille d'air jaune sur harnais, lance rouge enroulée à la hanche, lance à la main
    (blaster rouge et laiton) ; bottes de caoutchouc."""
    m = Model("jo_pompiere")
    head(m, iris="#5A3A1A")
    bangs(m, "#3A1A12")
    c = P(m, "coiffe")
    crown = [S((0, 1.075, -0.012), 0.108, 0.122), S((0, 1.15, -0.014), 0.106, 0.12), S((0, 1.2, -0.016), 0.096, 0.11),
             S((0, 1.245, -0.018), 0.072, 0.086), S((0, 1.27, -0.02), 0.036, 0.046), S((0, 1.276, -0.02), 0.006, 0.008)]
    c.add(loft(smooth(crown, 2), FIRE, nc=3))

    def brim(u, v):
        th = v * 2 * math.pi
        cx, sz = math.cos(th), math.sin(th)
        back = max(0.0, -sz) ** 1.4
        ext = 0.022 + 0.03 * abs(cx) + 0.12 * back
        ra, rb = 0.106 + ext * u, 0.12 + ext * u
        y = 1.09 - 0.05 * back * u ** 1.3 + 0.012 * max(0.0, sz) * u
        return (cx * ra, y, sz * rb - 0.012)
    c.add(sheet(brim, 4, 44, 0.012, FIRE, closed=True, under=FIRE_D,
                colf=lambda u, v: FIRE_D if u > 0.8 else None))
    # crêtes
    for dx in (-0.045, 0.0, 0.045):
        pts = []
        for i in range(8):
            a = math.radians(-50 + 150 * i / 7)
            r = 1.0 - abs(dx) * 2.4
            pts.append(S((dx * (1.0 + 0.3 * math.sin(a)), 1.075 + 0.2 * math.cos(a) * r, 0.118 * math.sin(a) - 0.014), 0.007, 0.012, 0.004))
        c.add(loft(pts[1:], FIRE_D if dx else FIRE, nc=1))
    # écusson dressé devant
    sh = [S((0, 1.13, 0.124), 0.03, 0.006, 0.003, t=(0, 1, -0.35)), S((0, 1.17, 0.11), 0.05, 0.006, 0.003, t=(0, 1, -0.35)),
          S((0, 1.215, 0.094), 0.05, 0.006, 0.003, t=(0, 1, -0.35)), S((0, 1.235, 0.087), 0.036, 0.006, 0.003, t=(0, 1, -0.35))]
    c.add(loft(sh, GOLD, nc=1, ref=(1, 0, 0)))
    c.add(box((0, 1.18, 0.112), (0.028, 0.032, 0.004), 0.003, FIRE_D, up=(0, 1, -0.35)))
    c.add(star((0, 1.18, 0.116), (0, 0.33, 1), 0.02, 0.009, 0.004, GOLD))
    # grande visière dorée relevée
    c.add(shell([{"c": (0, 1.072, -0.008), "a": 0.122, "b": 0.142, "a0": 28, "a1": 152},
                 {"c": (0, 1.092, -0.012), "a": 0.116, "b": 0.134, "a0": 30, "a1": 150}], 0.008, "#F5B52E", inner="#F5B52E", seg=20))
    for sx in (-1, 1):
        c.add(box((sx * 0.112, 1.085, 0.03), (0.008, 0.02, 0.018), 0.004, RUBBER))
    cg = P(m, "coiffe_glow")
    cg.add(shell([{"c": (0, 1.067, -0.008), "a": 0.123, "b": 0.143, "a0": 28, "a1": 152},
                  {"c": (0, 1.072, -0.008), "a": 0.123, "b": 0.143, "a0": 28, "a1": 152}], 0.009, "#FFE9A0", seg=20))
    # lampe sur le côté
    c.add(box((0.118, 1.165, 0.03), (0.016, 0.018, 0.026), 0.006, RUBBER, up=(1, 0.25, 0)))
    cg.add(disc((0.122, 1.165, 0.058), (0.1, 0, 1), 0.0, 0.012, 0.004, "#FFF6C8", seg=14))
    # couvre-nuque qui flotte
    pv = [(0, 1.06, -0.115), (0, 0.98, -0.135), (0, 0.9, -0.148)]
    segs = chain(m, "coiffe", pv[:2], "coiffe")
    for i, sg in enumerate(segs):
        a, b = Vector(pv[i]), Vector(pv[i + 1])
        sg.add(shell([{"c": (0, a.y, a.z + 0.11), "a": 0.11 + 0.01 * i, "b": 0.11 + 0.008 * i, "a0": 200, "a1": 340},
                      {"c": (0, b.y, b.z + 0.11 + 0.004), "a": 0.12 + 0.01 * i, "b": 0.118 + 0.008 * i, "a0": 198, "a1": 342}],
                     0.008, TAN_D, inner="#7A5520", seg=14))
    m.part("coiffe_f2_glow", pv[1], "coiffe_f2").add(
        shell([{"c": (0, 0.915, -0.148 + 0.114), "a": 0.129, "b": 0.126, "a0": 199, "a1": 341},
               {"c": (0, 0.93, -0.146 + 0.114), "a": 0.128, "b": 0.125, "a0": 199, "a1": 341}], 0.01, LIME, seg=14))
    # veste de feu
    tg = jacket(m, TAN, 0.5, TAN_D, TAN, wide=1.12)
    t = P(m, "torso")
    p, n = surface(tg, (0, 0.72, 0.5), (0, 0, -1))
    t.add(box(p + Vector((0, 0, 0.002)), (0.012, 0.19, 0.004), 0.003, TAN_D))
    for y in (0.84, 0.76, 0.68, 0.58):
        p, n = surface(tg, (0, y, 0.5), (0, 0, -1))
        t.add(box(p + Vector((0.0, 0, 0.005)), (0.016, 0.008, 0.004), 0.003, RUBBER))
    tg2 = extra(m, "torso_glow", "torso")
    _band_ring(tg2, 0.555, 0.124, 0.09)
    _band_ring(tg2, 0.665, 0.112, 0.08, z=0.002)
    t.add(box((-0.07, 0.6, 0.087), (0.03, 0.024, 0.006), 0.004, TAN_D))
    t.add(box((0.07, 0.6, 0.087), (0.03, 0.024, 0.006), 0.004, TAN_D))
    # col montant
    P(m, "col").add(shell([{"c": (0, 0.88, -0.006), "a": 0.098, "b": 0.08, "a0": 108, "a1": 432},
                           {"c": (0, 0.95, -0.012), "a": 0.074, "b": 0.064, "a0": 104, "a1": 436, "col": TAN_D},
                           {"c": (0, 0.955, -0.012), "a": 0.074, "b": 0.064, "a0": 104, "a1": 436}], 0.012, TAN, inner="#3A2A1A", seg=24))
    # bras : manches sable, bandes, gants de cuir noir
    arms(m, TAN, RUBBER, wide=1.18, cuff=TAN_D, cuff_y=0.575)
    for side, sx in sides():
        ag = P(m, "arm_%s_glow" % side)
        for y, x, z, a in ((0.76, 0.172, -0.008, 0.039), (0.63, 0.182, 0.018, 0.037)):
            ag.add(loft([S((sx * x, y + 0.012, z), a, a + 0.002, a * 0.6), S((sx * x, y - 0.012, z + 0.006), a, a + 0.002, a * 0.6)], LIME, nc=2))
        P(m, "arm_" + side).add(loft([S((sx * 0.186, 0.6, 0.028), 0.033, 0.033), S((sx * 0.188, 0.548, 0.044), 0.03, 0.03)], RUBBER, nc=2))
    # pantalon, bandes, bottes de caoutchouc
    legs(m, TAN, None, None, None, wide=1.14)
    for side, sx in sides():
        sgl = P(m, "shin_%s_glow" % side)
        for y in (0.24, 0.29):
            sgl.add(loft([S((sx * 0.075, y + 0.009, -0.002), 0.044, 0.048, 0.024), S((sx * 0.075, y - 0.009, -0.002), 0.044, 0.048, 0.024)],
                         LIME if y < 0.27 else SILVER, nc=2))
        P(m, "leg_" + side).add(box((sx * 0.128, 0.46, 0.0), (0.008, 0.05, 0.04), 0.005, TAN_D, up=(0, 1, 0)))
        b = P(m, "jambe_" + side)
        boot(b, sx, RUBBER, sole="#0E0E12", top=0.2, top_col=TANK, toe=RUBBER, wide=1.06, flare=0.004)
    # bouteille d'air, harnais, lance enroulée
    d = P(m, "dos")
    d.add(box((0, 0.76, -0.105), (0.07, 0.15, 0.018), 0.008, RUBBER))
    d.add(loft(smooth([S((0, 0.6, -0.16), 0.004, 0.004), S((0, 0.61, -0.16), 0.046, 0.046, 0.04), S((0, 0.66, -0.16), 0.054, 0.054, 0.05),
                       S((0, 0.86, -0.16), 0.054, 0.054, 0.05), S((0, 0.92, -0.16), 0.04, 0.04, 0.036), S((0, 0.94, -0.16), 0.016, 0.016)], 2),
               TANK, nc=4))
    d.add(loft([S((0, 0.84, -0.16), 0.0555, 0.0555, 0.05), S((0, 0.87, -0.16), 0.0555, 0.0555, 0.05)], FIRE, nc=4))
    d.add(loft([S((0, 0.68, -0.16), 0.0555, 0.0555, 0.05), S((0, 0.7, -0.16), 0.0555, 0.0555, 0.05)], RUBBER, nc=4))
    d.add(loft([S((0, 0.94, -0.16), 0.014, 0.014), S((0, 0.97, -0.16), 0.014, 0.014)], SILVER, nc=2))
    d.add(box((0, 0.975, -0.16), (0.03, 0.008, 0.01), 0.004, FIRE))
    d.add(loft(smooth([S((0.012, 0.6, -0.15), 0.008, 0.008), S((0.09, 0.62, -0.1), 0.008, 0.008), S((0.12, 0.72, -0.02), 0.008, 0.008),
                       S((0.09, 0.82, 0.07), 0.008, 0.008)], 2), RUBBER, nc=1))
    for sx in (-1, 1):  # bretelles du harnais
        d.add(loft(smooth([S((sx * 0.06, 0.62, -0.09), 0.014, 0.004), S((sx * 0.07, 0.9, -0.07), 0.014, 0.004),
                           S((sx * 0.08, 0.915, 0.0), 0.014, 0.004), S((sx * 0.07, 0.86, 0.075), 0.014, 0.004),
                           S((sx * 0.066, 0.66, 0.086), 0.014, 0.004)], 2), RUBBER, nc=1, ref=(1, 0, 0)))
    for k in range(3):
        d.add(torus((-0.128 - 0.006 * k, 0.52, -0.06), (-1, 0, -0.3), 0.062 - 0.008 * k, 0.012, FIRE if k % 2 == 0 else "#C21E14", seg=24, rs=5))
    d.add(loft([S((-0.13, 0.57, -0.02), 0.012, 0.012), S((-0.15, 0.63, 0.02), 0.012, 0.012), S((-0.155, 0.66, 0.035), 0.016, 0.016),
                S((-0.158, 0.69, 0.05), 0.008, 0.008)], GOLD_D, nc=2))
    P(m, "dos_glow").add(shell([{"c": (0, 0.79, -0.16), "a": 0.0565, "b": 0.0565, "a0": 0, "a1": 360},
                                {"c": (0, 0.81, -0.16), "a": 0.0565, "b": 0.0565, "a0": 0, "a1": 360}], 0.004, LIME, seg=24))
    blaster(m, shell_col=FIRE, stripe=GOLD, metal=RUBBER, glow="#FFD34D")
    return m


# ------------------------------------------------------------------ Fée des aurores
FAIRY_P = "#FF6FC4"
FAIRY_P2 = "#FFB3E2"
FAIRY_M = "#5FE6C0"
FAIRY_W = "#FFF4FB"
FAIRY_H = "#FFB08A"
FAIRY_L = "#D9C2FF"
# couleurs des parts lumineuses (multipliées par l'énergie du rig, ~1,7 : rester en tons moyens)
AUR_PINK = "#A02C72"
AUR_VIO = "#6238B0"
AUR_CYAN = "#1F86AA"
AUR_MINT = "#23A070"
AUR_EDGE = "#A8EEFF"


def petal(base, along, across, nrm, L, W, cup, col, colf=None, nu=4, nv=4, thick=0.006, bend=0.0):
    """Pétale : nappe en amande de la base vers la pointe (along), largeur W, bords relevés de `cup`."""
    base, al, ac, nr = V(base), V(along).normalized(), V(across).normalized(), V(nrm).normalized()

    def fn(u, v):
        s = (v - 0.5) * 2.0
        w = W * math.sin(math.pi * (0.22 + 0.77 * u)) ** 0.7
        return base + al * (L * u) + ac * (s * w) + nr * (cup * s * s * (w / W) + bend * u * u)
    return sheet(fn, nu, nv, thick, col, colf=colf)


def _wing(part, root, d1, d2, L, col_in, col_mid, col_out, lobe=0.62, n=14, peak=0.5):
    """Aile de lumière : éventail de la racine entre les directions d1 et d2, longueur L ; la pointe est à la
    fraction `peak` de l'éventail, `lobe` > 1 l'effile."""
    root, d1, d2 = V(root), V(d1).normalized(), V(d2).normalized()

    def fn(u, v):
        d = (d1 * (1 - v) + d2 * v).normalized()
        q = 0.5 * v / peak if v < peak else 0.5 + 0.5 * (v - peak) / (1 - peak)
        r = L * (0.12 + 0.88 * (math.sin(math.pi * (0.06 + 0.88 * q)) ** lobe)) * (0.04 + 0.96 * u)
        return root + d * r

    def colf(u, v):
        if u > 0.86:
            return AUR_EDGE
        return col_in if u < 0.36 else col_mid if u < 0.66 else col_out
    part.add(sheet(fn, 6, n, 0.004, col_mid, colf=colf))


def fee():
    """Fée des aurores : grandes ailes de lumière (rose, violet, cyan, menthe) qui frémissent dans le dos,
    diadème de cristaux lumineux, voile qui flotte depuis le diadème ; robe de pétales roses et menthe à trois
    étages, corsage blanc, pétales aux épaules, bracelets lumineux ; chaussons pointus lacés."""
    m = Model("jo_fee")
    head(m, iris="#3A8A9A")
    hp = hair_bob(m, FAIRY_H, hi="#FFD9C2", long_side=True)
    for sx in (-1, 1):  # mèches longues sur les épaules
        pts = [(sx * 0.09, 1.04, -0.03), (sx * 0.1, 0.95, -0.04), (sx * 0.1, 0.86, -0.05), (sx * 0.09, 0.8, -0.05)]
        hp.add(loft([S(pts[0], 0.03, 0.03, 0.01), S(pts[1], 0.03, 0.026, 0.01), S(pts[2], 0.022, 0.018, 0.008), S(pts[3], 0.003, 0.003, 0.001)],
                    FAIRY_H, nc=2))
    # diadème de cristaux
    c = P(m, "coiffe")
    c.add(shell([{"c": (0, 1.1, -0.006), "a": 0.098, "b": 0.108, "a0": 0, "a1": 360},
                 {"c": (0, 1.114, -0.008), "a": 0.096, "b": 0.106, "a0": 0, "a1": 360}], 0.008, FAIRY_W, seg=32))
    cg = P(m, "coiffe_glow")
    for k in range(-3, 4):
        th = math.radians(90 + k * 17)
        x, z = math.cos(th) * 0.1, math.sin(th) * 0.11 - 0.008
        h = 0.07 - 0.014 * abs(k)
        col = AUR_CYAN if k % 2 else AUR_PINK
        if k == 0:
            h, col = 0.095, AUR_EDGE
        nrm = Vector((math.cos(th), 0, math.sin(th)))
        cg.add(loft([S((x, 1.112, z), 0.012 - 0.0015 * abs(k), 0.008, 0.003, t=(0, 1, 0)),
                     S(Vector((x, 1.112 + h * 0.45, z)) + nrm * 0.008, 0.014 - 0.0015 * abs(k), 0.009, 0.003, t=(0, 1, 0)),
                     S(Vector((x, 1.112 + h, z)) + nrm * 0.014, 0.001, 0.001, 0.0005, t=(0, 1, 0))], col, nc=1,
                    ref=(-math.sin(th), 0, math.cos(th))))
    cg.add(ell((0, 1.105, 0.112), 0.012, 0.014, 0.008, AUR_PINK, n=4, nc=1))
    # corsage blanc, robe de pétales
    tg = torso(m, [
        (0.5, 0.06, 0.05, 0.0, None), (0.525, 0.1, 0.07, 0.0, None), (0.57, 0.108, 0.074, 0.0, None),
        (0.62, 0.098, 0.068, 0.002, FAIRY_P), (0.645, 0.096, 0.066, 0.002, None), (0.72, 0.1, 0.07, 0.006, None),
        (0.8, 0.12, 0.078, 0.01, None), (0.85, 0.124, 0.074, 0.004, SKIN), (0.888, 0.126, 0.066, 0.0, None),
        (0.912, 0.085, 0.056, -0.004, None), (0.93, 0.04, 0.04, -0.004, None)], FAIRY_W)
    t = P(m, "torso")
    for k in range(6):  # pétales du corsage
        th = math.radians(90 + (k - 2.5) * 22)
        p, n = surface(tg, (math.cos(th) * 0.5, 0.78, math.sin(th) * 0.5), (-math.cos(th), 0, -math.sin(th)))
        t.add(petal(p + n * 0.003 + Vector((0, 0.06, 0)), (0, -1, 0.1), (-math.sin(th), 0, math.cos(th)), n, 0.1, 0.03, 0.006, FAIRY_P2))
    layers = [(0.6, 0.105, 0.075, 0.3, 0.085, 10, 0.0, FAIRY_M, AUR_EDGE), (0.61, 0.108, 0.078, 0.26, 0.08, 10, 18.0, FAIRY_P, FAIRY_P2),
              (0.62, 0.11, 0.08, 0.13, 0.06, 10, 0.0, FAIRY_W, None)]
    for (y, ra, rb, L, W, n, off, col, tip) in layers:
        for k in range(n):
            th = math.radians(off + k * 360 / n)
            cx, sz = math.cos(th), math.sin(th)
            base = (cx * ra, y, sz * rb)
            t.add(petal(base, (cx * 0.62, -1, sz * 0.62), (-sz, 0, cx), (cx, 0.35, sz), L, W, 0.012, col,
                        colf=(lambda u, v, tip=tip: tip if tip and u > 0.8 else None), bend=0.03))
    t.add(loft([S((0, 0.598, 0.0), 0.106, 0.075), S((0, 0.632, 0.0), 0.102, 0.072)], FAIRY_P, nc=2))
    # pétales aux épaules
    for side, sx in sides():
        e = P(m, "epaule_" + side)
        for k, (dz, L) in enumerate(((-0.04, 0.085), (0.0, 0.1), (0.04, 0.085))):
            e.add(petal((sx * 0.13, 0.9, dz * 0.6), (sx * 1, -0.35, dz * 2.5), (0, 0, 1) if k == 1 else (0, 0.3, 1), (0, 1, 0), L, 0.034, 0.008,
                        FAIRY_P if k == 1 else FAIRY_P2))
    arms(m, SKIN, SKIN, wide=0.92)
    for side, sx in sides():
        P(m, "arm_%s_glow" % side).add(loft([S((sx * 0.186, 0.578, 0.036), 0.03, 0.03), S((sx * 0.187, 0.565, 0.04), 0.03, 0.03)], AUR_CYAN, nc=2))
    # jambes, chaussons pointus lacés
    legs(m, SKIN, None, None, None)
    for side, sx in sides():
        b = P(m, "jambe_" + side)
        x = sx * 0.077
        b.add(loft(smooth([S((x, 0.03, -0.055), 0.03, 0.03), S((x, 0.036, 0.0), 0.038, 0.036), S((x, 0.03, 0.08), 0.03, 0.022),
                           S((x, 0.04, 0.14), 0.012, 0.012), S((x, 0.075, 0.16), 0.003, 0.003)], 2), FAIRY_P, nc=2))
        b.add(loft([S((x, 0.004, -0.055), 0.03, 0.004), S((x, 0.004, 0.08), 0.032, 0.004)], FAIRY_W, nc=1))
        s = P(m, "shin_" + side)
        for k in range(4):
            y = 0.1 + k * 0.045
            s.add(loft([S((x - 0.03, y, 0.025), 0.003, 0.003), S((x + 0.03, y + 0.03, 0.025), 0.003, 0.003)], FAIRY_P, nc=1))
        b.add(petal((x, 0.07, -0.03), (0, 0.4, -1), (1, 0, 0), (0, 1, 0), 0.05, 0.02, 0.004, FAIRY_P2))
    # ailes de lumière : deux paires étalées vers l'arrière, relevées (lisibles de dessus, dans tous les sens)
    wg = P(m, "dos_glow")
    for side, sx in sides():
        up = Vector((sx * 0.96, 0.28, 0.0))
        dn = Vector((sx * 0.96, -0.26, 0.0))
        bk = Vector((0, 0, -1))
        _wing(wg, (sx * 0.03, 0.83, -0.12), up + Vector((0, 0, 0.1)), up * 0.3 + bk, 0.56, AUR_PINK, AUR_VIO, AUR_CYAN, lobe=1.25, peak=0.3)
        _wing(wg, (sx * 0.03, 0.77, -0.12), dn + Vector((0, 0, -0.1)), dn * 0.25 + bk, 0.38, AUR_PINK, AUR_CYAN, AUR_MINT, lobe=1.1, n=12, peak=0.6)
    # voiles qui flottent, accrochés entre les ailes
    pv = [(0, 0.8, -0.13), (0, 0.66, -0.16), (0, 0.5, -0.18), (0, 0.32, -0.19)]
    segs = chain(m, "dos", pv[:3], "torso")
    for k, sx in ((1.0, 1), (0.86, -1)):
        for i, sg in enumerate(segs):
            a = Vector(pv[i]) + Vector((sx * (0.02 + 0.03 * i), 0, 0))
            b = Vector(pv[i]) + (Vector(pv[i + 1]) - Vector(pv[i])) * k + Vector((sx * (0.02 + 0.03 * (i + 1)), 0, 0))
            secs = []
            for j in range(5):
                f = j / 4.0
                p = a + (b - a) * f + Vector((sx * 0.012 * math.sin((i + f) * 3.0), 0, 0.01 * math.sin((i + f) * 4.0)))
                w = 0.026 + 0.008 * i + 0.004 * f - (0.024 * f * f if i == 2 else 0.0)
                secs.append(S(p, w, 0.002, 0.001, col=(FAIRY_P2, FAIRY_L, "#BFF4F0")[i]))
            sg.add(loft(secs, (FAIRY_P2, FAIRY_L, "#BFF4F0")[i], nc=1, ref=(1, 0, -sx * 0.3)))
    d = P(m, "dos")
    d.add(box((0, 0.8, -0.098), (0.04, 0.03, 0.01), 0.006, FAIRY_W))
    d.add(ell((0, 0.8, -0.112), 0.03, 0.03, 0.016, FAIRY_P, n=4, nc=1))
    blaster(m, shell_col=FAIRY_W, stripe=FAIRY_P, metal=FAIRY_L, glow="#8AF0FF")
    P(m, "gun_glow").add(ell(Vector(PIV["gun"]) + Vector((0, -0.06, 0.105)), 0.012, 0.02, 0.008, AUR_PINK, n=4, nc=1))
    return m


# ------------------------------------------------------------------ Astronaute cosmique
SUIT = "#F2F0EA"
SUIT_D = "#C9CCD6"
NAVY = "#1E2234"
NAVY_L = "#323A5C"
SILV = "#AEB8CA"
# arc-en-ciel des parts lumineuses (tons moyens : l'énergie du rig les éclaire)
RAINBOW = ["#C23A3A", "#C8721C", "#BFAE1E", "#3AAE48", "#2E78D0", "#7A48C8"]
GLINT = "#BFEFFF"
GLASS = "#A6D6F6"
GLASS_IN = "#6A93CC"


def _arc(c, u, w, R, a0, a1, n, rad, col):
    """Arc de cercle (centre c, plan (u, w), rayon R) de a0 à a1 degrés, tube de rayon rad."""
    c, u, w = V(c), V(u).normalized(), V(w).normalized()
    pts = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        pts.append(S(c + (u * math.cos(a) + w * math.sin(a)) * R, rad, rad, rad * 0.9))
    return loft(pts, col, nc=2)


def astronaute():
    """Astronaute cosmique : casque bulle en verre (collerette, arceau, reflets lumineux, Jo visible dedans),
    combinaison rétro blanche à anneaux bleu nuit, panneau de commande arc-en-ciel, gros sac de survie à
    bouteilles et antenne qui ploie, anneau d'orbite arc-en-ciel autour de la taille, trois petites planètes
    qui gravitent (pans flottants du dos), bottes lunaires."""
    m = Model("jo_astronaute")
    head(m, iris="#4A4AA8")
    hair_bob(m, "#DDE3FF", hi="#9FB8FF", long_side=False)
    # casque bulle : collerette, arceau, reflets (le verre lui-même ne se dessine pas : on voit Jo)
    c = P(m, "coiffe")
    C = Vector((0, 1.075, -0.004))
    R = 0.168
    c.add(torus((0, 0.925, -0.004), (0, 1, 0), 0.094, 0.022, SUIT, seg=28, rs=6))
    c.add(torus((0, 0.946, -0.004), (0, 1, 0), 0.084, 0.012, NAVY, seg=28, rs=5))
    # verre : bulle fermée derrière et dessus, grande ouverture sur le visage (Jo visible)
    gs = []
    for lat in (-36, -20, 0, 20, 38, 52, 64, 74, 82, 88):
        o = 64 if lat <= 38 else max(0.5, 64 * (1 - (lat - 38) / 36.0))
        la = math.radians(lat)
        gs.append({"c": (C.x, C.y + R * math.sin(la), C.z), "a": R * math.cos(la), "b": R * math.cos(la), "a0": 90 + o, "a1": 450 - o})
    c.add(shell(gs, 0.006, GLASS, inner=GLASS_IN, seg=36))
    for sx in (-1, 1):
        p = C + Vector((sx * 0.13, -0.075, -0.02))
        c.add(loft([S(p, 0.02, 0.02, 0.008, t=(sx, 0.2, 0)), S(p + Vector((sx * 0.028, 0.006, 0)), 0.018, 0.018, 0.007, t=(sx, 0.2, 0))],
                   SUIT, nc=2))
        P(m, "coiffe_glow").add(disc(p + Vector((sx * 0.0285, 0.006, 0)), (sx, 0.2, 0), 0.0, 0.012, 0.003, RAINBOW[0 if sx < 0 else 3], seg=14))
    cg = P(m, "coiffe_glow")
    cg.add(torus((0, 0.958, -0.004), (0, 1, 0), 0.082, 0.006, RAINBOW[4], seg=28, rs=4))

    def sph(lat, lon, r=R):
        la, lo = math.radians(lat), math.radians(lon)
        return C + Vector((math.cos(la) * math.sin(lo), math.sin(la), math.cos(la) * math.cos(lo))) * r
    for lats, lon, w in (((44, 76), 30, 0.0075), ((48, 66), 52, 0.006)):
        pts = [sph(lats[0] + (lats[1] - lats[0]) * i / 8, lon + 6 * math.sin(i / 8 * math.pi), R + 0.006) for i in range(9)]
        cg.add(loft([S(p, w * (0.4 + 0.6 * math.sin(math.pi * i / 8)), 0.002, 0.001) for i, p in enumerate(pts)], GLINT, nc=1,
                    ref=(1, 0, 0)))
    pts = [sph(70, -80 + 100 * i / 10, R + 0.006) for i in range(11)]
    cg.add(loft([S(p, 0.002, 0.007 * (0.4 + 0.6 * math.sin(math.pi * i / 10)), 0.001) for i, p in enumerate(pts)], GLINT, nc=1, ref=(0, 1, 0)))
    pts = [sph(10 + 40 * i / 6, -140 + 10 * math.sin(i), R + 0.006) for i in range(7)]
    cg.add(loft([S(p, 0.005 * (0.4 + 0.6 * math.sin(math.pi * i / 6)), 0.002, 0.001) for i, p in enumerate(pts)], GLINT, nc=1, ref=(1, 0, 0)))
    # combinaison
    tg = torso(m, [
        (0.5, 0.064, 0.054, 0.0, NAVY), (0.525, 0.112, 0.08, 0.0, None), (0.57, 0.122, 0.086, 0.0, None),
        (0.64, 0.116, 0.08, 0.002, None), (0.72, 0.122, 0.084, 0.006, None), (0.8, 0.138, 0.09, 0.01, None),
        (0.855, 0.146, 0.086, 0.004, None), (0.888, 0.138, 0.076, 0.0, None), (0.912, 0.09, 0.06, -0.004, None),
        (0.93, 0.045, 0.044, -0.004, None)], SUIT)
    t = P(m, "torso")
    t.add(loft([S((0, 0.585, 0.0), 0.126, 0.09, 0.03), S((0, 0.625, 0.0), 0.122, 0.088, 0.03)], NAVY, nc=2))
    t.add(box((0, 0.605, 0.091), (0.026, 0.018, 0.006), 0.005, SILV))
    p, n = surface(tg, (0, 0.75, 0.5), (0, 0, -1))
    t.add(box(p + Vector((0, 0, 0.012)), (0.058, 0.044, 0.014), 0.008, NAVY, nc=2))
    t.add(box(p + Vector((0, 0.05, 0.004)), (0.04, 0.006, 0.01), 0.003, SILV))
    tgl = extra(m, "torso_glow", "torso")
    for i, col in enumerate(RAINBOW):
        x = -0.04 + i * 0.016
        tgl.add(box(p + Vector((x, 0.014, 0.027)), (0.006, 0.006, 0.002), 0.002, col))
        tgl.add(box(p + Vector((x, -0.018, 0.027)), (0.006, 0.014 * (0.5 + 0.5 * math.sin(i * 1.7) ** 2), 0.002), 0.002, col))
    tgl.add(loft([S((0, 0.603, 0.0), 0.1275, 0.0915, 0.03), S((0, 0.607, 0.0), 0.1275, 0.0915, 0.03)], RAINBOW[2], nc=2))
    for sx in (-1, 1):
        seam(t, tg, [(sx * 0.07, 0.86, 0), (sx * 0.075, 0.64, 0)], (0, 0, -1), col=SUIT_D, w=0.003)
    # anneau d'orbite arc-en-ciel autour de la taille
    og = extra(m, "orbite_glow", "torso")
    nrm = Vector((0.18, 1, 0.12)).normalized()
    u = Vector((1, 0, 0))
    u = (u - nrm * u.dot(nrm)).normalized()
    w = nrm.cross(u)
    for k in range(12):
        a0 = k * 30 + 4
        og.add(_arc((0, 0.68, -0.01), u, w, 0.29, a0, a0 + 22, 5, 0.0075, RAINBOW[k % 6]))
    # col (zone col) : anneau de raccord sous la collerette
    P(m, "col").add(loft([S((0, 0.88, -0.004), 0.11, 0.08, 0.04), S((0, 0.91, -0.004), 0.1, 0.075, 0.04)], NAVY_L, nc=3))
    # bras bouffants à anneaux, gros gants
    arms(m, SUIT, SUIT, wide=1.24, cuff=NAVY, cuff_y=0.6)
    for side, sx in sides():
        a = P(m, "arm_" + side)
        for (x, y, z), (ax, ay, az) in (((0.168, 0.8, -0.004), (0.15, 1, 0)), ((0.176, 0.705, -0.006), (0.05, 1, -0.1)),
                                        ((0.18, 0.655, 0.01), (0.08, 1, -0.35))):
            a.add(torus((sx * x, y, z), (sx * ax, ay, az), 0.043, 0.007, NAVY, seg=18, rs=4))
        a.add(loft([S((sx * 0.186, 0.605, 0.028), 0.044, 0.044, 0.02), S((sx * 0.188, 0.565, 0.042), 0.048, 0.048, 0.02),
                    S((sx * 0.188, 0.55, 0.046), 0.046, 0.046, 0.02)], SUIT, nc=2))
        a.add(box((sx * 0.19, 0.505, 0.054), (0.026, 0.032, 0.03), 0.013, SUIT, nc=2))
        P(m, "arm_%s_glow" % side).add(box((sx * 0.232, 0.585, 0.036), (0.002, 0.012, 0.012), 0.001, RAINBOW[1 if sx < 0 else 4]))
    # épaules : plaques rondes
    for side, sx in sides():
        P(m, "epaule_" + side).add(disc((sx * 0.172, 0.905, -0.004), (sx * 0.5, 1, 0), 0.0, 0.052, 0.012, SUIT_D, seg=24))
        P(m, "epaule_%s_glow" % side).add(disc((sx * 0.175, 0.912, -0.004), (sx * 0.5, 1, 0), 0.03, 0.036, 0.008, RAINBOW[5 if sx < 0 else 0], seg=24))
    # jambes à anneaux, bottes lunaires
    legs(m, SUIT, None, None, None, wide=1.2)
    for side, sx in sides():
        l = P(m, "leg_" + side)
        l.add(torus((sx * 0.072, 0.47, 0.006), (0, 1, 0), 0.06, 0.008, NAVY, seg=18, rs=4))
        s = P(m, "shin_" + side)
        for y, r in ((0.335, 0.05), (0.3, 0.048)):
            s.add(torus((sx * 0.075, y, 0.0), (0, 1, 0), r, 0.008, NAVY, seg=18, rs=4))
        b = P(m, "jambe_" + side)
        boot(b, sx, SUIT, sole=NAVY, top=0.24, top_col=NAVY, wide=1.25, flare=0.012)
        b.add(loft([S((sx * 0.077, 0.03, -0.075), 0.054, 0.03, 0.02, t=(0, 0, 1)), S((sx * 0.077, 0.03, 0.17), 0.05, 0.03, 0.02, t=(0, 0, 1))],
                   NAVY_L, nc=2, ref=(1, 0, 0)))
    # gros sac de survie, bouteilles, antenne qui ploie
    d = P(m, "dos")
    d.add(box((0, 0.775, -0.165), (0.11, 0.15, 0.062), 0.022, SUIT, nc=2))
    d.add(box((0, 0.77, -0.229), (0.075, 0.1, 0.006), 0.005, NAVY))
    d.add(box((0, 0.905, -0.165), (0.1, 0.018, 0.056), 0.01, NAVY_L))
    for sx in (-1, 1):
        d.add(loft(smooth([S((sx * 0.12, 0.64, -0.17), 0.006, 0.006), S((sx * 0.12, 0.65, -0.17), 0.032, 0.032, 0.02),
                           S((sx * 0.12, 0.88, -0.17), 0.032, 0.032, 0.02), S((sx * 0.12, 0.9, -0.17), 0.006, 0.006)], 2), SILV, nc=3))
        d.add(torus((sx * 0.12, 0.77, -0.17), (0, 1, 0), 0.033, 0.006, NAVY, seg=14, rs=4))
    dg = P(m, "dos_glow")
    for i, col in enumerate(RAINBOW):
        dg.add(box((-0.05 + i * 0.02, 0.81, -0.2355), (0.007, 0.03, 0.002), 0.002, col))
    pv = [(0.06, 0.92, -0.19), (0.075, 1.08, -0.21), (0.09, 1.22, -0.235), (0.1, 1.3, -0.25)]
    segs = chain(m, "dos_antenne", pv[:3], "torso")
    segs[0].add(loft([S((0.06, 0.912, -0.19), 0.012, 0.012), S((0.06, 0.93, -0.19), 0.01, 0.01)], NAVY, nc=2))
    for i, sg in enumerate(segs):
        sg.add(seg(pv[i], pv[i + 1], 0.004 - 0.0008 * i, 0.004 - 0.0008 * i, SILV))
    tip = Vector(pv[3])
    ag = m.part("dos_antenne_f3_glow", pv[2], "dos_antenne_f3")
    ag.add(ell(tip, 0.016, 0.016, 0.016, RAINBOW[3], n=5, nc=2))
    ag.add(star(tip, (0, 0, -1), 0.034, 0.012, 0.005, RAINBOW[2]))
    # trois petites planètes en orbite (pans du dos : elles se balancent avec la course)
    for k, (pos, r, col, ring) in enumerate((((0.31, 1.16, -0.14), 0.044, "#F09A3A", RAINBOW[4]), ((-0.27, 1.36, -0.2), 0.032, "#3FC8B4", None),
                                             ((-0.32, 0.98, -0.16), 0.028, "#E870B8", RAINBOW[2]))):
        piv = (pos[0] * 0.25, 0.95, -0.17)
        sg = chain(m, "dos_orbite%d" % (k + 1), [piv], "torso")[0]
        pl = ell(pos, r, r, r, col, n=6, nc=3)
        pl.paint(lambda c, n, y=pos[1], r=r: abs(c.y - y) < r * 0.25, "#FFFFFF" if k == 0 else NAVY_L)
        sg.add(pl)
        gl = m.part("dos_orbite%d_f1_glow" % (k + 1), piv, "dos_orbite%d_f1" % (k + 1))
        if ring:
            gl.add(disc(pos, (0.35, 1, -0.25), r * 1.45, r * 1.85, 0.004, ring, seg=24))
        else:
            gl.add(ell(Vector(pos) + Vector((0.05, 0.03, 0)), 0.009, 0.009, 0.009, GLINT, n=4, nc=1))
    blaster(m, shell_col=SUIT, stripe=NAVY, metal=NAVY_L, glow="#FFFFFF")
    gg = P(m, "gun_glow")
    o = Vector(PIV["gun"])
    for i, col in enumerate(RAINBOW):
        gg.add(box(o + Vector((0, -0.04 - i * 0.012, 0.1025)), (0.012, 0.006, 0.002), 0.001, col))
    return m


BUILDS_B = {"jo_cowgirl": cowgirl, "jo_meca": meca, "jo_idole": idole, "jo_pompiere": pompiere, "jo_fee": fee,
            "jo_astronaute": astronaute}


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("-")] or list(BUILDS_B)
    for nm in names:
        mdl = BUILDS_B[nm]()
        n = mdl.export(os.path.join(ROOT, "assets", "chars3d", nm + ".glb"))
        if n > 24000:
            print("ATTENTION : %s dépasse 24 000 triangles (%d)" % (nm, n))
