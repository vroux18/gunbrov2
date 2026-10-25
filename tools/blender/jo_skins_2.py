"""Apparences de Jo, deuxième lot : six tenues complètes (voir l'en-tête de tools/blender/jo_skins.py pour le
pipeline et le contrat des parts). Elles sont ajoutées à BUILDS de jo_skins.py :

    /opt/bpyenv/bin/python tools/blender/jo_skins.py jo_pirate      (cargo, commune)
    jo_polaire (glacier, commune), jo_mecano (ardoise, commune), jo_jardiniere (menthe, commune),
    jo_princesse (corail, rare), jo_plongeuse (lagon, rare)

Brique en plus : revo() — surface de révolution dont le profil change avec l'angle (bords de chapeau relevés en
tricorne, chapeau de paille ondulé, volants de jupe, bords de capuche), avec une épaisseur et une doublure.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from jo import *  # noqa


def revo(c, profile, thick, cols, inner=None, seg=36, ax=1.0, bz=1.0, a0=0.0, a1=360.0):
    """Surface de révolution épaisse autour de l'axe vertical passant par c.
    profile(theta_deg) -> [(r, y), ...] : le profil (rayon, hauteur absolue) pour cet angle (0 = +X, 90 = +Z devant,
    270 = dos), même nombre de points pour tous les angles. cols : couleur par bande du profil (liste) ou fonction
    (theta, k) -> couleur. inner : couleur de la face intérieure / du dessous (même forme). ax, bz : ellipse.
    La face « extérieure » est celle de la normale (-dy, dr) du profil : le dessus d'un bord, l'extérieur d'une jupe."""
    g = Geo()
    c = V(c)
    full = abs(a1 - a0) >= 359.9
    cnt = seg if full else seg + 1
    outer, inn = [], []
    npf = None
    for i in range(cnt):
        th = a0 + (a1 - a0) * i / seg
        d = Vector((math.cos(math.radians(th)) * ax, 0.0, math.sin(math.radians(th)) * bz))
        pf = profile(th % 360.0)
        npf = len(pf)
        ro, ri = [], []
        for k, (r, y) in enumerate(pf):
            k0, k1 = max(0, k - 1), min(npf - 1, k + 1)
            dr = pf[k1][0] - pf[k0][0]
            dy = pf[k1][1] - pf[k0][1]
            ln = math.hypot(dr, dy) or 1.0
            nr, ny = -dy / ln, dr / ln
            p = Vector((c.x + d.x * r, y, c.z + d.z * r))
            off = Vector((d.x * nr, ny, d.z * nr)) * thick * 0.5
            g.v.append(p + off)
            ro.append(len(g.v) - 1)
            g.v.append(p - off)
            ri.append(len(g.v) - 1)
        outer.append(ro)
        inn.append(ri)

    def colo(th, k):
        if callable(cols):
            return hexcol(cols(th, k))
        return hexcol(cols[min(k, len(cols) - 1)])

    def coli(th, k):
        if inner is None:
            return colo(th, k)
        if callable(inner):
            return hexcol(inner(th, k))
        if isinstance(inner, (list, tuple)):
            return hexcol(inner[min(k, len(inner) - 1)])
        return hexcol(inner)

    rng = range(cnt) if full else range(cnt - 1)
    for i in rng:
        j = (i + 1) % cnt
        th = (a0 + (a1 - a0) * (i + 0.5) / seg) % 360.0
        for k in range(npf - 1):
            g.f.append((outer[i][k], outer[i][k + 1], outer[j][k + 1], outer[j][k]))
            g.col.append(colo(th, k))
            g.f.append((inn[j][k], inn[j][k + 1], inn[i][k + 1], inn[i][k]))
            g.col.append(coli(th, k))
        for k, cc in ((0, colo(th, 0)), (npf - 1, colo(th, npf - 2))):
            g.f.append((outer[i][k], outer[j][k], inn[j][k], inn[i][k]))
            g.col.append(cc)
    if not full:
        for i in (0, cnt - 1):
            th = a0 if i == 0 else a1
            for k in range(npf - 1):
                g.f.append((outer[i][k], inn[i][k], inn[i][k + 1], outer[i][k + 1]))
                g.col.append(colo(th % 360.0, k))
    return g


def corner(th, corners, width):
    """0 sur un coin (angles en degrés), 1 à `width` degrés ou plus du coin le plus proche (lissé)."""
    dmin = min(abs((th - a + 180.0) % 360.0 - 180.0) for a in corners)
    t = min(1.0, dmin / width)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def boot(part, sx, col, sole, top_y=0.29, cuff=None, cuff_col=None, toe=0.15, w=1.0, heel=False):
    """Botte : pied arrondi, tige jusqu'à top_y, revers évasé `cuff` (hauteur) de couleur cuff_col."""
    x = sx * 0.077
    part.add(loft(smooth([S((x, 0.045, -0.058), 0.034 * w, 0.03), S((x, 0.05, -0.03), 0.042 * w, 0.044),
                          S((x, 0.046, 0.04), 0.044 * w, 0.034), S((x, 0.034, toe - 0.03), 0.036 * w, 0.024),
                          S((x, 0.03, toe), 0.016 * w, 0.014)], 2), col, nc=2, ref=(1, 0, 0)))
    part.add(loft([S((x, 0.012, z), a * w + 0.002, 0.012, 0.004) for z, a in ((-0.064, 0.032), (-0.03, 0.042), (0.05, 0.046), (toe - 0.01, 0.026))],
                  sole, nc=1))
    part.add(loft(smooth([S((x, 0.05, -0.012), 0.04 * w, 0.044), S((x, 0.12, -0.008), 0.039 * w, 0.042),
                          S((x, 0.2, -0.004), 0.043 * w, 0.046), S((x, top_y, 0.0), 0.046 * w, 0.05)], 2), col, nc=2))
    if cuff:
        part.add(shell([{"c": (x, top_y - cuff, 0.0), "a": 0.047 * w, "b": 0.051, "a0": 0, "a1": 360},
                        {"c": (x, top_y + 0.02, 0.004), "a": 0.066 * w, "b": 0.07, "a0": 0, "a1": 360}], 0.01,
                       cuff_col, inner=col, seg=20))


# ------------------------------------------------------------------ Pirate de l'espace (cargo, commune)
P_COAT = "#B3243A"
P_COAT_D = "#7A1426"
P_GOLD = "#F2B33D"
P_HAT = "#1C1A24"
P_CREAM = "#EFE3C4"
P_BOOT = "#24202A"
P_LEATHER = "#8A5A34"
P_HAIR = "#3A2418"
P_GLOW = "#7AF2FF"


def pirate():
    """Pirate de l'espace : tricorne noir à galon d'or et cocarde lumineuse, longue veste de capitaine cramoisie
    à revers d'or et basques fendues qui flottent, épaulettes à franges, ceinture à grosse boucle, culotte crème,
    bottes à revers, queue de cheval nouée."""
    m = Model("jo_pirate")
    hg = head(m, iris="#4A2A1A")
    hp = hair_bob(m, P_HAIR, long_side=False)
    pts = [(0, 1.0, -0.1), (0, 0.95, -0.115), (0, 0.88, -0.112), (0, 0.82, -0.1)]
    hp.add(loft(smooth([S(p, w, w * 0.8, w * 0.4) for p, w in zip(pts, (0.026, 0.028, 0.02, 0.004))], 2), P_HAIR, nc=1))
    hp.add(box((0, 1.0, -0.104), (0.03, 0.012, 0.012), 0.004, P_GOLD))
    # tricorne : calotte et bord relevé en trois cornes (devant, arrière gauche, arrière droit)
    c = P(m, "coiffe")
    c.add(loft(smooth([S((0, 1.1, -0.006), 0.104, 0.114), S((0, 1.16, -0.008), 0.1, 0.11), S((0, 1.215, -0.01), 0.078, 0.088),
                       S((0, 1.235, -0.01), 0.03, 0.034)], 2), P_HAT, nc=3))
    cn = (90.0, 210.0, 330.0)

    def tri(th):
        s = corner(th, cn, 60.0)
        return [(0.1, 1.11), (lerp(0.15, 0.118, s), lerp(1.12, 1.13, s)), (lerp(0.205, 0.128, s), lerp(1.148, 1.215, s)),
                (lerp(0.222, 0.13, s), lerp(1.16, 1.24, s))]
    c.add(revo((0, 0, -0.008), tri, 0.012, [P_HAT, P_HAT, P_GOLD], inner=[P_HAT, P_HAT, P_GOLD], seg=48, ax=1.0, bz=1.08))
    cg = P(m, "coiffe_glow")
    cg.add(disc((0, 1.165, 0.155), (0, 0.55, 1), 0.0, 0.024, 0.008, P_GLOW, seg=18))
    c.add(disc((0, 1.163, 0.152), (0, 0.55, 1), 0.022, 0.034, 0.008, P_GOLD, seg=18))
    # longue veste : buste cramoisi, plastron crème en V, revers d'or, boutons
    tg = jacket(m, P_COAT, 0.53, P_GOLD, P_CREAM, wide=1.1)
    P(m, "torso").geo.paint(lambda c, n: c.z > 0.03 and c.y > 0.6 and abs(c.x) < 0.014 + (c.y - 0.6) * 0.3, P_CREAM)
    t = P(m, "torso")
    for sx in (-1, 1):
        seam(t, tg, [(sx * 0.018, 0.62, 0), (sx * 0.052, 0.76, 0), (sx * 0.092, 0.87, 0)], (0, 0, -1), col=P_GOLD, w=0.008)
        for y in (0.67, 0.72, 0.77):
            p, n = surface(tg, (sx * (0.038 + (y - 0.6) * 0.3), y, 0.4), (0, 0, -1))
            t.add(ell(p + Vector((0, 0, 0.003)), 0.0075, 0.0075, 0.005, P_GOLD, n=3, nc=1))
    # large ceinture de cuir à grosse boucle d'or, baudrier en travers (épaule gauche -> hanche droite)
    t.add(loft([S((0, 0.575, 0), 0.124, 0.092), S((0, 0.63, 0), 0.12, 0.089)], P_LEATHER, nc=2))
    t.add(box((0, 0.603, 0.094), (0.036, 0.032, 0.008), 0.005, P_GOLD))
    t.add(box((0, 0.603, 0.101), (0.019, 0.016, 0.004), 0.002, P_LEATHER))
    t.add(box((0.0, 0.603, 0.104), (0.003, 0.016, 0.004), 0.001, P_GOLD))
    for zs in (-1, 1):
        t.add(loft([S((0.118, 0.9, zs * 0.03), 0.003, 0.015), S((0.03, 0.8, zs * 0.098), 0.003, 0.015),
                    S((-0.112, 0.6, zs * 0.088), 0.003, 0.015)], "#5E3A20", nc=1, ref=(0, 0, 1)))
    t.add(box((0.03, 0.8, 0.101), (0.016, 0.014, 0.004), 0.003, P_GOLD, up=(0.8, 1, 0)))
    seam(t, tg, [(0, 0.88, 0), (0, 0.63, 0)], (0, 0, 1), col=P_COAT_D, w=0.003)
    # col dressé et jabot (zone col)
    co = P(m, "col")
    co.add(shell([{"c": (0, 0.89, -0.006), "a": 0.082, "b": 0.07, "a0": 125, "a1": 415},
                  {"c": (0, 0.955, -0.02), "a": 0.09, "b": 0.078, "a0": 130, "a1": 410, "col": P_GOLD},
                  {"c": (0, 0.965, -0.022), "a": 0.091, "b": 0.079, "a0": 130, "a1": 410}], 0.01, P_COAT, inner=P_COAT_D, seg=22))
    co.add(loft([S((0, 0.905, 0.066), 0.016, 0.006, 0.003), S((0, 0.87, 0.078), 0.028, 0.008, 0.004, col="#DCD3BC"),
                 S((0, 0.86, 0.08), 0.03, 0.008, 0.004), S((0, 0.83, 0.088), 0.034, 0.008, 0.004, col="#DCD3BC"),
                 S((0, 0.82, 0.09), 0.034, 0.008, 0.004), S((0, 0.795, 0.094), 0.016, 0.006, 0.003)], WHITE, nc=1))
    # cache-œil (zone visage) à pastille lumineuse
    v = P(m, "visage")
    pe, ne = surface(hg, (-0.034, 1.05, 0.4), (0, 0, -1))
    v.add(ell(pe + Vector((0, 0, 0.004)), 0.021, 0.019, 0.007, INK, n=4, nc=2))
    seam(v, hg, [(-0.02, 1.064, 0), (-0.05, 1.085, 0), (-0.07, 1.1, 0)], (0, 0, -1), col=INK, w=0.004, lift=0.002)
    seam(v, hg, [(0, 1.1, 0.05), (0, 1.12, -0.02)], (1, 0, 0), col=INK, w=0.004, lift=0.002)
    P(m, "visage_glow").add(ell(pe + Vector((0, 0, 0.011)), 0.005, 0.005, 0.003, P_GLOW, n=3, nc=1))
    # basques fendues qui flottent (deux pans : dos_d, dos_g)
    for nm, sx, arc in (("dos_d", -1, (184, 268)), ("dos_g", 1, (272, 356))):
        pv = [(sx * 0.06, 0.62, -0.07), (sx * 0.08, 0.42, -0.1), (sx * 0.1, 0.19, -0.13)]
        segs = chain(m, nm, pv[:2], "torso")
        for i, sg in enumerate(segs):
            y0, y1 = pv[i][1], pv[i + 1][1]
            def rr(y):
                return 0.122 + (0.62 - y) * 0.24, 0.094 + (0.62 - y) * 0.22
            secs = [{"c": (0, y0, 0.0), "a": rr(y0)[0], "b": rr(y0)[1], "a0": arc[0], "a1": arc[1]}]
            if i == 1:
                secs.append({"c": (0, y1 + 0.02, 0.0), "a": rr(y1 + 0.02)[0], "b": rr(y1 + 0.02)[1], "a0": arc[0], "a1": arc[1], "col": P_GOLD})
            secs.append({"c": (0, y1, 0.0), "a": rr(y1)[0], "b": rr(y1)[1], "a0": arc[0], "a1": arc[1]})
            sg.add(shell(secs, 0.012, P_COAT, inner=P_COAT_D, seg=12))
            if i == 0:
                sg.add(ell((sx * 0.05, 0.56, -0.118), 0.008, 0.008, 0.006, P_GOLD, n=3, nc=1))
    # épaulettes d'or à franges
    for side, sx in sides():
        e = P(m, "epaule_" + side)
        e.add(revo((sx * 0.158, 0, 0.0), lambda th: [(0.0, 0.928), (0.05, 0.922), (0.066, 0.905)], 0.012, [P_GOLD, P_GOLD],
                   inner=P_COAT_D, seg=20, ax=1.0, bz=0.9))
        for k in range(9):
            a = math.radians(-70 + k * 17.5)
            px, pz = math.cos(a) * 0.064 * sx, math.sin(a) * 0.056
            e.add(box((sx * 0.158 + px * (1 if sx > 0 else 1), 0.886, pz), (0.005, 0.02, 0.005), 0.002, "#E09A2A"))
    # manches à grands parements
    arms(m, P_COAT, P_LEATHER, wide=1.1, cuff=None)
    for side, sx in sides():
        a = P(m, "arm_" + side)
        a.add(shell([{"c": (sx * 0.182, 0.645, 0.016), "a": 0.04, "b": 0.04, "a0": 0, "a1": 360},
                     {"c": (sx * 0.186, 0.6, 0.03), "a": 0.046, "b": 0.046, "a0": 0, "a1": 360, "col": P_GOLD},
                     {"c": (sx * 0.187, 0.59, 0.034), "a": 0.047, "b": 0.047, "a0": 0, "a1": 360}], 0.01, P_COAT_D, inner=P_COAT_D, seg=18))
    # culotte crème, bottes noires à revers
    legs(m, P_CREAM, None, None, None)
    for side, sx in sides():
        boot(P(m, "jambe_" + side), sx, P_BOOT, INK, top_y=0.3, cuff=0.06, cuff_col=P_LEATHER)
    blaster(m, shell_col="#D9A441", stripe=P_COAT, metal=INK, glow=P_GLOW)
    return m


def arm_at(sx, y):
    """Centre et demi-tailles de la manche de Jo (ARM de jo.py) à la hauteur y."""
    for (x0, y0, z0, a0, b0), (x1, y1, z1, a1, b1) in zip(ARM, ARM[1:]):
        if y1 <= y <= y0:
            t = (y0 - y) / (y0 - y1)
            return Vector((sx * lerp(x0, x1, t), y, lerp(z0, z1, t))), lerp(a0, a1, t), lerp(b0, b1, t)
    x, y0, z, a, b = ARM[-1] if y < ARM[-1][1] else ARM[0]
    return Vector((sx * x, y, z)), a, b


def fur(part, c, a, b, a0, a1, r, col, n=20, y_wave=0.0):
    """Bordure de fourrure synthétique : bourrelet facetté le long d'un arc d'ellipse (centre c, rayons a en X,
    b en Z), épaisseur alternée (touffes nettes, pas de boule molle)."""
    c = V(c)
    secs = []
    for i in range(n + 1):
        th = math.radians(a0 + (a1 - a0) * i / n)
        k = 1.0 if i % 2 == 0 else 0.72
        p = c + Vector((math.cos(th) * a, y_wave * math.sin(th * 2), math.sin(th) * b))
        secs.append({"c": p, "a": r * k, "b": r * k * 1.1, "r": r * k * 0.5})
    part.add(loft(secs, col, nc=1, ref=(0, 1, 0)))


def mitten(part, sx, col, cuff=None):
    """Moufle : grosse main ronde et pouce, sur le poing de Jo (manchette `cuff`)."""
    c = Vector((sx * 0.19, 0.505, 0.052))
    part.add(box(c, (0.034, 0.044, 0.038), 0.017, col, nc=2))
    part.add(box(c + Vector((-sx * 0.03, 0.012, 0.02)), (0.012, 0.022, 0.013), 0.008, col, nc=2, up=(-sx * 0.4, 1, 0)))
    if cuff:
        part.add(loft([S(c + Vector((0, 0.03, -0.004)), 0.036, 0.04), S(c + Vector((0, 0.058, -0.012)), 0.034, 0.038)], cuff, nc=2))


# ------------------------------------------------------------------ Exploratrice polaire (glacier, commune)
I_PARKA = "#F2531C"
I_PARKA_D = "#C23A0E"
I_FUR = "#F4F1EA"
I_FUR_D = "#D8D2C6"
I_KNIT = "#2F7BFF"
I_KNIT_D = "#1E55C8"
I_PANTS = "#3A4766"
I_BOOT = "#4C5468"
I_LENS = "#9FE8FF"


def polaire():
    """Exploratrice polaire : grosse parka orange matelassée (bandes bombées), capuche rabattue bordée de fourrure
    blanche, bonnet bleu à revers rayé et gros pompon, lunettes de glacier rondes à œillères, moufles bleues,
    pantalon de neige, bottes de neige à revers de fourrure."""
    m = Model("jo_polaire")
    hg = head(m, iris="#2A5AA8")
    bangs(m, "#3A2418")
    # bonnet : calotte tricotée, revers rayé, pompon facetté
    c = P(m, "coiffe")
    kn = loft(smooth([S((0, 1.075, -0.008), 0.098, 0.108), S((0, 1.14, -0.01), 0.096, 0.106), S((0, 1.2, -0.014), 0.078, 0.088),
                      S((0, 1.235, -0.016), 0.04, 0.046), S((0, 1.245, -0.016), 0.01, 0.012)], 2), I_KNIT, nc=3)
    kn.paint(lambda c, n: c.y > 1.1 and (math.degrees(math.atan2(c.z + 0.012, c.x)) % 36.0) < 10.0, I_KNIT_D)  # côtes
    c.add(kn)
    c.add(loft([S((0, 1.058, -0.008), 0.106, 0.116, col=I_KNIT_D), S((0, 1.075, -0.008), 0.107, 0.117, col=WHITE),
                S((0, 1.09, -0.008), 0.107, 0.117, col=I_KNIT_D), S((0, 1.112, -0.008), 0.106, 0.116)], I_KNIT_D, nc=3))
    c.add(ell((0, 1.29, -0.018), 0.048, 0.044, 0.048, I_FUR, n=5, nc=1))
    c.add(ell((0, 1.29, -0.018), 0.036, 0.052, 0.036, I_FUR_D, n=4, nc=1, up=(0.6, 0.2, 0.7)))
    # lunettes de glacier (zone visage) : verres ronds, œillères de cuir, bride
    v = P(m, "visage")
    for sx in (-1, 1):
        p, n = surface(hg, (sx * 0.034, 1.05, 0.4), (0, 0, -1))
        v.add(torus(p + n * 0.007, n, 0.026, 0.007, "#2A2F3A", seg=16, rs=4))
        v.add(disc(p + n * 0.007, n, 0.0, 0.023, 0.005, "#1E3550", seg=16))
        P(m, "visage_glow").add(disc(p + n * 0.011 + Vector((sx * -0.007, 0.007, 0)), n, 0.0, 0.007, 0.002, I_LENS, seg=8))
        q, nq = surface(hg, (sx * 0.4, 1.05, 0.045), (-sx, 0, 0))
        v.add(box(q + nq * 0.004, (0.004, 0.018, 0.02), 0.003, "#5E3A20"))
    v.add(box((0, 1.054, 0.088), (0.012, 0.004, 0.005), 0.002, "#2A2F3A"))
    v.add(shell([{"c": (0, 1.045, -0.004), "a": 0.085, "b": 0.096, "a0": -15, "a1": 195},
                 {"c": (0, 1.055, -0.004), "a": 0.085, "b": 0.096, "a0": -15, "a1": 195}], 0.005, "#2A2F3A", seg=24))
    # parka matelassée : bandes bombées, pincées aux coutures
    secs = []
    bands = [0.42, 0.5, 0.58, 0.66, 0.74, 0.82]
    for i, y in enumerate(bands):
        k = (y - 0.42) / 0.4
        a = lerp(0.155, 0.142, k)
        b = lerp(0.13, 0.104, k)
        secs.append((y, a * 0.93, b * 0.93, 0.0, I_PARKA_D if i == 0 else None))
        if i < len(bands) - 1:
            secs.append((y + 0.012, a, b, 0.0, None))
            secs.append((y + 0.068, a, b, 0.0, None))
    secs += [(0.86, 0.152, 0.104, 0.0, None), (0.895, 0.142, 0.09, 0.0, None), (0.922, 0.09, 0.066, -0.004, None),
             (0.938, 0.045, 0.045, -0.004, None)]
    tg = torso(m, secs, I_PARKA, k=1)
    P(m, "torso").geo.paint(lambda c, n: c.y < 0.43, I_PARKA_D)
    t = P(m, "torso")
    seam(t, tg, [(0, 0.9, 0), (0, 0.43, 0)], (0, 0, -1), col="#2A2F3A", w=0.005)
    for sx in (-1, 1):
        t.add(box((sx * 0.075, 0.55, 0.122), (0.04, 0.035, 0.008), 0.006, I_PARKA_D, up=(0, 1, -0.15)))
        t.add(box((sx * 0.075, 0.585, 0.126), (0.042, 0.008, 0.008), 0.004, "#2A2F3A", up=(0, 1, -0.15)))
    lg = P(m, "dos")
    back_logo(lg, tg, 0.72, 0.07, WHITE)
    # capuche rabattue sur la nuque, bordée de fourrure (zone col)
    co = P(m, "col")
    co.add(shell([{"c": (0, 0.89, -0.01), "a": 0.096, "b": 0.084, "a0": 115, "a1": 425},
                  {"c": (0, 0.93, -0.04), "a": 0.124, "b": 0.11, "a0": 125, "a1": 415},
                  {"c": (0, 0.96, -0.07), "a": 0.124, "b": 0.096, "a0": 140, "a1": 400}], 0.014, I_PARKA, inner=I_PARKA_D, seg=24))
    fur(co, (0, 0.965, -0.07), 0.124, 0.096, 140, 400, 0.024, I_FUR, n=22)
    fur(co, (0, 0.9, -0.004), 0.1, 0.088, 60, 120, 0.02, I_FUR, n=6)
    # manches bouffantes matelassées, manchette de fourrure, moufles
    arms(m, I_PARKA, I_KNIT, wide=1.3, cuff=None)
    for side, sx in sides():
        a = P(m, "arm_" + side)
        for y in (0.79, 0.7):
            pc, aa, bb = arm_at(sx, y)
            a.add(loft([S(pc + Vector((0, 0.006, 0)), aa * 1.24, bb * 1.24), S(pc - Vector((0, 0.006, 0)), aa * 1.24, bb * 1.24)],
                       I_PARKA_D, nc=2))
        pc, aa, bb = arm_at(sx, 0.57)
        fur(a, pc, 0.034, 0.034, 0, 360, 0.014, I_FUR, n=14)
        mitten(a, sx, I_KNIT)
        a.add(box(Vector((sx * 0.19, 0.505, 0.052)) + Vector((0, 0.0, 0.0)), (0.031, 0.006, 0.035), 0.003, WHITE))
    # pantalon de neige, bottes de neige à revers de fourrure
    legs(m, I_PANTS, None, None, None, wide=1.12)
    for side, sx in sides():
        b = P(m, "jambe_" + side)
        boot(b, sx, I_BOOT, "#23262E", top_y=0.2, w=1.22, toe=0.14)
        fur(b, (sx * 0.077, 0.205, 0.0), 0.052, 0.058, 0, 360, 0.02, I_FUR, n=16)
        b.add(loft([S((sx * 0.077, 0.08, z), a, 0.006, 0.003) for z, a in ((0.02, 0.05), (0.09, 0.04))], I_PARKA, nc=1))
    blaster(m, shell_col=WHITE, stripe=I_PARKA, metal="#2A2F3A", glow=I_LENS)
    return m


def on_surf(geo, x, y, z_side, lift=0.004):
    """Point de la surface de geo devant (z_side = 1) ou derrière (z_side = -1) à (x, y), décollé de lift."""
    p, n = surface(geo, (x, y, z_side * 0.5), (0, 0, -z_side))
    return p + Vector((0, 0, z_side * lift))


# ------------------------------------------------------------------ Mécano (ardoise, commune)
K_OVER = "#EBA21C"
K_OVER_D = "#B87810"
K_TEE = "#3A4152"
K_CAP = "#E8452C"
K_CAP_D = "#B32A18"
K_GLOVE = "#E8452C"
K_BELT = "#5E3A20"
K_STEEL = "#C7CDD8"
K_STEEL_D = "#8A93A3"
K_BOOT = "#6B4423"


def mecano():
    """Mécano : salopette moutarde à bavette et poches partout, bretelles croisées dans le dos, t-shirt ardoise
    aux manches retroussées, casquette rouge à l'envers (visière vers l'arrière), gros gants rouges, ceinture à
    outils (pochettes, marteau, tournevis), grosse clé plate dans la poche arrière, chaussures de chantier."""
    m = Model("jo_mecano")
    hg = head(m, iris="#3B2A26", mark="#4A4F5C")
    hp = bangs(m, "#4A2A1A")
    pts = [(0, 1.06, -0.1), (0, 1.03, -0.13), (0, 0.98, -0.14), (0, 0.93, -0.13)]
    hp.add(loft(smooth([S(p, w, w * 0.8, w * 0.4) for p, w in zip(pts, (0.022, 0.026, 0.02, 0.004))], 2), "#4A2A1A", nc=1))
    # casquette à l'envers : calotte à six côtes, bouton, visière vers l'arrière
    c = P(m, "coiffe")
    cg = loft(smooth([S((0, 1.065, -0.006), 0.1, 0.11), S((0, 1.12, -0.008), 0.099, 0.109), S((0, 1.17, -0.01), 0.086, 0.096),
                      S((0, 1.2, -0.012), 0.056, 0.064), S((0, 1.212, -0.012), 0.01, 0.01)], 2), K_CAP, nc=3)
    c.add(cg)
    for k in range(6):
        a = math.radians(30 + k * 60)
        pts = [(math.cos(a) * 0.104, 1.09, math.sin(a) * 0.114 - 0.006), (math.cos(a) * 0.094, 1.16, math.sin(a) * 0.104 - 0.01),
               (math.cos(a) * 0.05, 1.205, math.sin(a) * 0.058 - 0.012), (math.cos(a) * 0.01, 1.214, math.sin(a) * 0.01 - 0.012)]
        c.add(loft([S(p, 0.0035, 0.0035, 0.0015) for p in pts], K_CAP_D, nc=1))
    c.add(ell((0, 1.215, -0.012), 0.014, 0.008, 0.014, K_CAP_D, n=3, nc=1))

    def bill(th):
        k = max(0.0, math.cos(math.radians(th - 270) * 2.4)) ** 0.45
        return [(0.1, 1.08), (lerp(0.1, 0.2, k), lerp(1.08, 1.064, k))]
    c.add(revo((0, 0, -0.006), bill, 0.012, [K_CAP], inner=K_CAP_D, seg=24, a0=232, a1=308, bz=1.08))
    c.add(revo((0, 0, -0.006), lambda th: [(0.1, 1.06), (0.1, 1.08)], 0.006, [K_CAP_D], seg=36, bz=1.1))
    c.add(box((0, 1.085, 0.104), (0.03, 0.012, 0.006), 0.004, K_TEE))  # sangle de réglage (devant)
    # t-shirt ardoise, salopette : bavette devant, dos montant, bretelles croisées
    tg = torso(m, [(0.5, 0.06, 0.05, 0.0, None), (0.525, 0.106, 0.076, 0.0, None), (0.57, 0.112, 0.08, 0.0, None),
                   (0.64, 0.1, 0.07, 0.002, None), (0.72, 0.104, 0.072, 0.006, None), (0.8, 0.124, 0.08, 0.01, None),
                   (0.855, 0.136, 0.078, 0.004, None), (0.888, 0.132, 0.07, 0.0, None), (0.912, 0.086, 0.057, -0.004, None),
                   (0.93, 0.04, 0.04, -0.004, None)], K_TEE)
    P(m, "torso").geo.paint(lambda c, n: c.y < 0.68 or (c.z > 0.03 and abs(c.x) < 0.072 and c.y < 0.845) or (c.z < -0.03 and abs(c.x) < 0.09 and c.y < 0.75), K_OVER)
    t = P(m, "torso")
    seam(t, tg, [(-0.072, 0.845, 0), (-0.072, 0.68, 0)], (0, 0, -1), col=K_OVER_D, w=0.003)
    seam(t, tg, [(0.072, 0.845, 0), (0.072, 0.68, 0)], (0, 0, -1), col=K_OVER_D, w=0.003)
    seam(t, tg, [(-0.072, 0.845, 0), (0.072, 0.845, 0)], (0, 0, -1), col=K_OVER_D, w=0.003)
    t.add(box(on_surf(tg, 0, 0.765, 1, 0.006), (0.04, 0.034, 0.006), 0.004, K_OVER_D))  # poche de bavette
    t.add(box(on_surf(tg, 0.02, 0.8, 1, 0.012), (0.004, 0.022, 0.004), 0.002, "#2F7BFF"))  # crayon
    for sx in (-1, 1):
        # bretelles : bavette -> épaule -> croisées dans le dos
        f = on_surf(tg, sx * 0.058, 0.84, 1)
        b0 = on_surf(tg, sx * 0.05, 0.86, -1)
        b1 = on_surf(tg, -sx * 0.06, 0.72, -1)
        t.add(loft([S(f, 0.012, 0.004, 0.002), S((sx * 0.075, 0.918, 0.02), 0.012, 0.004, 0.002), S((sx * 0.072, 0.918, -0.035), 0.012, 0.004, 0.002),
                    S(b0, 0.012, 0.004, 0.002), S(b1, 0.012, 0.004, 0.002)], K_OVER_D, nc=1, ref=(1, 0, 0)))
        t.add(ell(f + Vector((0, -0.006, 0.004)), 0.009, 0.009, 0.005, K_STEEL, n=3, nc=1))
        # poches de hanche
        t.add(box(on_surf(tg, sx * 0.07, 0.6, 1, 0.003), (0.03, 0.03, 0.005), 0.004, K_OVER_D, up=(0, 1, 0)))
    # ceinture à outils : ceinture, pochettes, marteau, tournevis
    t.add(loft([S((0, 0.635, 0), 0.112, 0.082), S((0, 0.665, 0), 0.108, 0.079)], K_BELT, nc=2))
    t.add(box((0, 0.65, 0.083), (0.018, 0.016, 0.006), 0.003, K_STEEL))
    for sx in (-1, 1):
        t.add(box((sx * 0.118, 0.6, 0.02), (0.022, 0.04, 0.036), 0.008, K_BELT, nc=2))
        t.add(box((sx * 0.12, 0.645, 0.02), (0.024, 0.006, 0.038), 0.003, "#7A5030"))
    t.add(loft([S((-0.122, 0.62, 0.03), 0.004, 0.004), S((-0.122, 0.68, 0.03), 0.004, 0.004)], K_STEEL, nc=1))  # tournevis
    t.add(loft([S((-0.122, 0.68, 0.03), 0.008, 0.008), S((-0.122, 0.72, 0.03), 0.009, 0.009)], "#2F7BFF", nc=2))
    t.add(loft([S((0.13, 0.66, -0.03), 0.006, 0.006), S((0.135, 0.53, -0.03), 0.007, 0.007)], "#8A5A34", nc=2))  # marteau
    t.add(box((0.135, 0.53, -0.03), (0.012, 0.014, 0.034), 0.004, DGRAY))
    # grosse clé plate dans la poche arrière (zone dos)
    d = P(m, "dos")
    pk = on_surf(tg, -0.06, 0.58, -1, 0.004)
    d.add(box(pk, (0.034, 0.034, 0.006), 0.004, K_OVER_D))
    w0 = pk + Vector((0.0, 0.0, -0.012))
    w1 = w0 + Vector((-0.06, 0.2, -0.02))
    d.add(loft([S(w0, 0.014, 0.006, 0.003), S(w1, 0.014, 0.006, 0.003)], K_STEEL, nc=1, ref=(1, 0.3, 0)))
    jaw = disc(w1 + Vector((-0.012, 0.032, 0)), (0, 0, -1), 0.018, 0.04, 0.014, K_STEEL, seg=18, arc=(130, 410))
    d.add(jaw)
    d.add(disc(w0 + Vector((0.004, -0.004, -0.001)), (0, 0, -1), 0.0, 0.018, 0.01, K_STEEL_D, seg=12))
    # manches retroussées, gros gants rouges à manchette
    arms(m, K_TEE, K_GLOVE, wide=1.06, roll=0.72, cuff=None)
    for side, sx in sides():
        a = P(m, "arm_" + side)
        c0 = Vector((sx * 0.19, 0.505, 0.052))
        a.add(box(c0, (0.032, 0.04, 0.034), 0.012, K_GLOVE, nc=2))
        a.add(box(c0 + Vector((-sx * 0.028, 0.014, 0.02)), (0.011, 0.02, 0.012), 0.007, K_GLOVE, nc=2, up=(-sx * 0.4, 1, 0)))
        a.add(shell([{"c": (sx * 0.188, 0.548, 0.046), "a": 0.036, "b": 0.036, "a0": 0, "a1": 360},
                     {"c": (sx * 0.188, 0.6, 0.032), "a": 0.046, "b": 0.046, "a0": 0, "a1": 360, "col": K_CAP_D},
                     {"c": (sx * 0.188, 0.61, 0.03), "a": 0.047, "b": 0.047, "a0": 0, "a1": 360}], 0.008, K_GLOVE, inner=K_CAP_D, seg=16))
        a.add(box(c0 + Vector((0, -0.036, 0.006)), (0.03, 0.006, 0.032), 0.003, K_CAP_D))
    # jambes de salopette, poches cargo, revers, chaussures de chantier à coque
    legs(m, K_OVER, None, None, None, wide=1.12, cuff=K_OVER_D)
    for side, sx in sides():
        l = P(m, "leg_" + side)
        l.add(box((sx * 0.128, 0.45, 0.004), (0.01, 0.045, 0.034), 0.004, K_OVER_D, up=(0, 1, 0)))
        l.add(box((sx * 0.13, 0.49, 0.004), (0.011, 0.008, 0.036), 0.003, K_OVER_D))
        s = P(m, "shin_" + side)
        s.add(box((sx * 0.084, 0.335, 0.044), (0.03, 0.03, 0.01), 0.008, K_OVER_D, nc=2))
        b = P(m, "jambe_" + side)
        boot(b, sx, K_BOOT, "#2A2018", top_y=0.13, w=1.15, toe=0.145)
        b.add(ell((sx * 0.077, 0.048, 0.1), 0.044, 0.03, 0.048, K_STEEL_D, n=4, nc=2))
    blaster(m, shell_col=K_STEEL, stripe=K_OVER, metal=K_TEE, glow="#FFE08A")
    return m


def secs_at(secs, y):
    """Demi-tailles (a, b) d'une liste de sections de torse (y, a, b, z, col) à la hauteur y (linéaire)."""
    for s0, s1 in zip(secs, secs[1:]):
        if s0[0] <= y <= s1[0]:
            t = (y - s0[0]) / (s1[0] - s0[0])
            return lerp(s0[1], s1[1], t), lerp(s0[2], s1[2], t)
    s = secs[0] if y < secs[0][0] else secs[-1]
    return s[1], s[2]


# ------------------------------------------------------------------ Jardinière (menthe, commune)
J_STRAW = "#F2CE6A"
J_STRAW_D = "#C99A3A"
J_RIBBON = "#E8343C"
J_DRESS = "#3FBF88"
J_DRESS_D = "#2A9A68"
J_APRON = "#22804E"
J_APRON_D = "#155E36"
J_BOOT = "#E8343C"
J_GLOVE = "#FFD23A"
J_WICKER = "#B07A3C"
J_WICKER_D = "#7E5224"
J_HAIR = "#B5521C"


def jardiniere():
    """Jardinière : très grand chapeau de paille tressé à ruban rouge et marguerite, deux nattes rousses, robe
    menthe à manches courtes, grand tablier vert à bavette et poche (transplantoir), gants jaunes, bottes de pluie
    rouges, panier d'osier dans le dos plein de carottes et d'une salade."""
    m = Model("jo_jardiniere")
    hg = head(m, iris="#3A6A2A")
    hp = bangs(m, J_HAIR)
    for sx in (-1, 1):
        pts = [(sx * 0.082, 1.03, -0.03), (sx * 0.1, 0.96, -0.02), (sx * 0.112, 0.9, 0.02), (sx * 0.112, 0.84, 0.05), (sx * 0.11, 0.8, 0.058)]
        secs = []
        for i, p in enumerate(pts):
            w = 0.022 - i * 0.002
            secs.append(S(p, w, w, w * 0.45))
        g = loft(smooth(secs, 3), J_HAIR, nc=1)
        g.paint(lambda c, n: int((c.y - 0.8) / 0.03) % 2 == 0 and c.y < 1.0, "#9A4214")  # tresse
        hp.add(g)
        hp.add(box((sx * 0.112, 0.83, 0.054), (0.018, 0.01, 0.018), 0.005, J_RIBBON))
        hp.add(ell((sx * 0.11, 0.795, 0.06), 0.014, 0.022, 0.012, J_HAIR, n=4, nc=1))
    # chapeau de paille : calotte, ruban, très large bord ondulé, tressage en anneaux
    c = P(m, "coiffe")
    cr = loft(smooth([S((0, 1.1, -0.008), 0.106, 0.116), S((0, 1.16, -0.01), 0.104, 0.114), S((0, 1.215, -0.012), 0.094, 0.104),
                      S((0, 1.235, -0.012), 0.06, 0.066), S((0, 1.24, -0.012), 0.01, 0.01)], 2), J_STRAW, nc=3)
    cr.paint(lambda c, n: 1.115 < c.y < 1.155, J_RIBBON)
    c.add(cr)

    def brim(th):
        w = 0.008 * math.sin(math.radians(th) * 7)
        return [(0.104, 1.125), (0.15, 1.118 + w * 0.3), (0.2, 1.105 + w * 0.7), (0.25, 1.09 + w), (0.285, 1.075 + w * 1.2)]
    c.add(revo((0, 0, -0.01), brim, 0.012, [J_STRAW, J_STRAW_D, J_STRAW, J_STRAW_D], inner=J_STRAW_D, seg=56))
    for fl, nr, R in (((0.118, 1.14, 0.05), (0.35, 1, 0.25), 0.04), ((0.14, 1.132, -0.02), (0.4, 1, -0.1), 0.03)):
        fl = Vector(fl)
        c.add(star(fl, nr, R, R * 0.45, 0.006, WHITE, n=8))
        c.add(ell(fl + Vector(nr).normalized() * 0.004, R * 0.3, R * 0.3, R * 0.3, J_GLOVE, n=3, nc=1))
    c.add(box((-0.02, 1.13, -0.122), (0.03, 0.02, 0.008), 0.006, J_RIBBON))
    for sx in (-1, 1):
        ribbon(c, (sx * 0.01, 1.125, -0.125), (sx * 0.04, 1.03, -0.15), 0.022, 0.016, 0.004, J_RIBBON)
    # robe menthe jusqu'aux genoux (cloche fermée : les jambes bougent dedans)
    dress = [(0.36, 0.175, 0.155, 0.006, J_DRESS_D), (0.375, 0.172, 0.152, 0.006, None), (0.45, 0.158, 0.138, 0.004, None),
             (0.53, 0.135, 0.112, 0.002, None), (0.6, 0.106, 0.076, 0.0, None), (0.64, 0.097, 0.067, 0.002, None),
             (0.72, 0.1, 0.07, 0.006, None), (0.8, 0.12, 0.078, 0.01, None), (0.855, 0.134, 0.076, 0.004, None),
             (0.888, 0.13, 0.068, 0.0, None), (0.912, 0.085, 0.056, -0.004, None), (0.93, 0.04, 0.04, -0.004, None)]
    tg = torso(m, dress, J_DRESS, k=2)
    t = P(m, "torso")
    for i in range(16):  # pois blancs sur la robe
        a = i * 2.39996
        y = 0.4 + (i % 4) * 0.045
        ra, rb = secs_at(dress, y)
        nrm = Vector((math.cos(a) / ra, 0.3, math.sin(a) / rb)).normalized()
        t.add(disc(Vector((math.cos(a) * ra, y, math.sin(a) * rb + 0.004)) + nrm * 0.002, nrm, 0.0, 0.009, 0.003, WHITE, seg=8))
    # tablier : jupe de devant, bavette, poche, liens noués dans le dos
    ap = []
    for y in (0.385, 0.45, 0.53, 0.6):
        ra, rb = secs_at(dress, y)
        ap.append({"c": (0, y, 0.006), "a": ra + 0.008, "b": rb + 0.01, "a0": 25, "a1": 155})
    ap[0]["col"] = J_APRON_D
    ap.insert(1, dict(ap[0], c=(0, 0.4, 0.006), a=secs_at(dress, 0.4)[0] + 0.008, b=secs_at(dress, 0.4)[1] + 0.01))
    ap[1].pop("col", None)
    t.add(shell(ap, 0.008, J_APRON, inner=J_APRON_D, seg=18))
    t.add(loft([S((0, 0.595, 0.0), 0.112, 0.082), S((0, 0.625, 0.0), 0.104, 0.075)], J_APRON_D, nc=2))
    bib = [{"c": (0, y, 0.004), "a": secs_at(dress, y)[0] + 0.006, "b": secs_at(dress, y)[1] + 0.008, "a0": 58, "a1": 122}
           for y in (0.62, 0.7, 0.78, 0.84)]
    t.add(shell(bib, 0.008, J_APRON, inner=J_APRON_D, seg=8))
    for sx in (-1, 1):
        t.add(loft([S(on_surf(tg, sx * 0.05, 0.84, 1, 0.008), 0.008, 0.003, 0.0015), S((sx * 0.06, 0.93, 0.0), 0.008, 0.003, 0.0015),
                    S((0, 0.94, -0.05), 0.008, 0.003, 0.0015)], J_APRON_D, nc=1, ref=(1, 0, 0)))
    pk = Vector((0.05, 0.47, secs_at(dress, 0.47)[1] + 0.026))
    t.add(box(pk, (0.05, 0.036, 0.006), 0.005, J_APRON_D, up=(0, 1, -0.3)))
    t.add(box(pk + Vector((0.025, 0.06, -0.004)), (0.007, 0.03, 0.006), 0.003, "#8A5A34"))  # manche du transplantoir
    t.add(box(pk + Vector((-0.03, 0.05, -0.002)), (0.012, 0.03, 0.004), 0.003, K_STEEL, up=(0.3, 1, 0)))
    t.add(box((0, 0.61, -0.088), (0.022, 0.016, 0.01), 0.006, J_APRON_D))
    for sx in (-1, 1):
        ribbon(t, (sx * 0.01, 0.6, -0.094), (sx * 0.035, 0.5, -0.12), 0.02, 0.016, 0.004, J_APRON_D)
    # panier d'osier dans le dos (zone dos), bretelles, carottes et salade
    d = P(m, "dos")
    bc = Vector((0, 0.76, -0.145))
    bsecs = []
    for i, y in enumerate((0.62, 0.66, 0.7, 0.74, 0.78, 0.82, 0.86, 0.88)):
        k = (y - 0.62) / 0.26
        s = S((0, y, bc.z - 0.004 * k), lerp(0.068, 0.092, k), lerp(0.045, 0.06, k), 0.016, col=J_WICKER if i % 2 == 0 else J_WICKER_D)
        bsecs.append(s)
    d.add(loft(bsecs, J_WICKER, nc=2, caps=(True, False)))
    d.add(loft([S((0, 0.865, bc.z - 0.004), 0.084, 0.052, 0.016), S((0, 0.866, bc.z - 0.004), 0.084, 0.052, 0.016)], "#3A2A16", nc=2))  # fond
    d.add(shell([{"c": (0, 0.874, bc.z - 0.004), "a": 0.094, "b": 0.062, "a0": 0, "a1": 360},
                 {"c": (0, 0.896, bc.z - 0.004), "a": 0.096, "b": 0.064, "a0": 0, "a1": 360}], 0.012, J_WICKER_D, seg=24))  # bord
    for sx in (-1, 1):
        d.add(loft([S((sx * 0.06, 0.84, -0.11), 0.012, 0.004, 0.002), S((sx * 0.08, 0.93, -0.03), 0.012, 0.004, 0.002),
                    S((sx * 0.085, 0.9, 0.06), 0.012, 0.004, 0.002), S((sx * 0.08, 0.72, 0.085), 0.012, 0.004, 0.002),
                    S((sx * 0.07, 0.66, -0.07), 0.012, 0.004, 0.002)], J_WICKER_D, nc=1, ref=(1, 0, 0)))
    for i, (x, z, tilt) in enumerate(((-0.045, -0.13, -0.3), (-0.012, -0.165, 0.0), (0.02, -0.135, 0.25))):
        base = Vector((x, 0.86, z))
        tip = base + Vector((tilt * 0.08, 0.14, -0.03))
        d.add(loft([S(base, 0.016, 0.016, 0.006), S(base.lerp(tip, 0.7), 0.011, 0.011, 0.004), S(tip, 0.002, 0.002, 0.001)], "#FF8A1F", nc=1))
        for k in range(3):
            lf = tip + Vector(((k - 1) * 0.012, 0.035, 0.0))
            d.add(loft([S(tip, 0.004, 0.003, 0.001), S(lf, 0.008, 0.003, 0.001), S(lf + Vector(((k - 1) * 0.008, 0.03, 0)), 0.001, 0.002, 0.001)],
                       "#4CB32E", nc=1))
    d.add(ell((0.05, 0.9, -0.152), 0.042, 0.036, 0.038, "#6CCB3A", n=4, nc=1))
    d.add(ell((0.05, 0.914, -0.152), 0.028, 0.03, 0.026, "#A6E66A", n=4, nc=1, up=(0.3, 1, 0.2)))
    # manches courtes bouffantes, gants jaunes
    arms(m, J_DRESS, J_GLOVE, wide=1.12, roll=0.79, cuff=None)
    for side, sx in sides():
        a = P(m, "arm_" + side)
        a.add(ell((sx * 0.158, 0.865, -0.002), 0.054, 0.05, 0.054, J_DRESS, n=5, nc=2))
        pc, aa, bb = arm_at(sx, 0.8)
        a.add(loft([S(pc + Vector((0, 0.006, 0)), aa * 1.3, bb * 1.3), S(pc - Vector((0, 0.008, 0)), aa * 1.24, bb * 1.24)], WHITE, nc=2))
        a.add(shell([{"c": (sx * 0.188, 0.548, 0.046), "a": 0.03, "b": 0.03, "a0": 0, "a1": 360},
                     {"c": (sx * 0.186, 0.6, 0.032), "a": 0.04, "b": 0.04, "a0": 0, "a1": 360}], 0.008, J_GLOVE, inner="#D9A81E", seg=16))
    # genoux nus, bottes de pluie rouges
    legs(m, SKIN, None, None, None)
    for side, sx in sides():
        b = P(m, "jambe_" + side)
        boot(b, sx, J_BOOT, "#7A1A1E", top_y=0.3, w=1.18, toe=0.14)
        b.add(shell([{"c": (sx * 0.077, 0.29, 0.0), "a": 0.055, "b": 0.059, "a0": 0, "a1": 360},
                     {"c": (sx * 0.077, 0.31, 0.002), "a": 0.058, "b": 0.062, "a0": 0, "a1": 360}], 0.008, "#FFFFFF", inner=J_BOOT, seg=18))
    blaster(m, shell_col=WHITE, stripe=J_APRON, metal=DGRAY, glow="#B8FF6A")
    return m


# ------------------------------------------------------------------ Princesse de bal (corail, rare)
R_DRESS = "#F2475E"
R_DRESS_D = "#C42A44"
R_FRILL = "#FF8C9C"
R_GOLD = "#F2B33D"
R_GOLD_D = "#C9861E"
R_BOW = "#FFE3E8"
R_BOW_D = "#F2AFC0"
R_HAIR = "#6E1F3C"
R_GEM = "#FF7AD0"


def princesse():
    """Princesse de bal : robe longue corail au jupon très bouffant, trois volants festonnés (corail, rose, corail)
    ourlés d'or, bustier à encolure dégagée, manches ballon, longs gants blancs, diadème d'or à joyau lumineux et
    chignon haut, grand nœud rose pâle dans le dos dont les deux longs pans flottent."""
    m = Model("jo_princesse")
    head(m, iris="#7A2A4A", mouth="#B0303E")
    hp = hair_bob(m, R_HAIR, long_side=False)
    hp.add(ell((0, 1.07, -0.118), 0.05, 0.046, 0.036, R_HAIR, n=5, nc=2))  # chignon bas
    hp.add(torus((0, 1.07, -0.098), (0, 0.2, -1), 0.04, 0.006, R_GOLD, seg=18, rs=4))
    for sx in (-1, 1):  # anglaises le long des joues
        pts = [(sx * 0.088, 1.06, 0.03), (sx * 0.096, 1.0, 0.036), (sx * 0.09, 0.95, 0.04)]
        hp.add(loft(smooth([S(pts[0], 0.012, 0.012), S(pts[1], 0.012, 0.012), S(pts[2], 0.003, 0.003)], 2), R_HAIR, nc=1))
    # diadème (zone coiffe) : bandeau d'or à pointes, joyau lumineux
    c = P(m, "coiffe")
    # petite couronne d'or posée sur le dessus de la tête, huit fleurons, joyaux lumineux
    cc = Vector((0, 1.19, -0.008))
    c.add(shell([{"c": cc, "a": 0.07, "b": 0.076, "a0": 0, "a1": 360},
                 {"c": cc + Vector((0, 0.032, 0)), "a": 0.078, "b": 0.084, "a0": 0, "a1": 360, "col": R_GOLD_D},
                 {"c": cc + Vector((0, 0.04, 0)), "a": 0.079, "b": 0.085, "a0": 0, "a1": 360}], 0.012, R_GOLD, inner=R_GOLD_D, seg=32))
    cg = P(m, "coiffe_glow")
    for k in range(8):
        th = math.radians(90 + k * 45)
        d_ = Vector((math.cos(th) * 0.08, 0, math.sin(th) * 0.086))
        b0 = cc + d_ + Vector((0, 0.038, 0))
        tip = cc + d_ * 1.12 + Vector((0, 0.088 if k % 2 == 0 else 0.07, 0))
        c.add(loft([S(b0, 0.017, 0.006, 0.002), S(b0.lerp(tip, 0.6), 0.01, 0.005, 0.002), S(tip, 0.002, 0.003, 0.001)], R_GOLD, nc=1,
                   ref=(-math.sin(th), 0, math.cos(th))))
        c.add(ell(tip + Vector((0, 0.004, 0)), 0.008, 0.008, 0.008, R_GOLD, n=3, nc=1))
        if k % 2 == 0:
            cg.add(ell(cc + d_ * 1.07 + Vector((0, 0.018, 0)), 0.011, 0.014, 0.011, R_GEM, n=3, nc=1, up=(math.cos(th), 0, math.sin(th))))
    c.add(shell([{"c": cc + Vector((0, 0.006, 0)), "a": 0.062, "b": 0.068, "a0": 0, "a1": 360},
                 {"c": cc + Vector((0, 0.03, 0)), "a": 0.03, "b": 0.034, "a0": 0, "a1": 360}], 0.008, R_DRESS, seg=24))  # coussin
    # bustier corail, encolure dégagée (épaules nues)
    tg = torso(m, [(0.5, 0.06, 0.05, 0.0, None), (0.525, 0.1, 0.07, 0.0, None), (0.57, 0.104, 0.072, 0.0, None),
                   (0.64, 0.092, 0.064, 0.002, None), (0.72, 0.098, 0.068, 0.006, None), (0.8, 0.118, 0.077, 0.01, None),
                   (0.855, 0.132, 0.075, 0.004, None), (0.888, 0.128, 0.067, 0.0, None), (0.912, 0.084, 0.055, -0.004, None),
                   (0.93, 0.04, 0.04, -0.004, None)], R_DRESS)
    P(m, "torso").geo.paint(lambda c, n: c.y > 0.835 + 0.02 * math.cos(c.x * 40) * (c.z > 0), SKIN)
    t = P(m, "torso")
    t.add(loft([S((0, 0.828, 0.006), 0.124, 0.078), S((0, 0.84, 0.004), 0.126, 0.077)], R_GOLD, nc=3))  # bord du bustier
    t.add(loft([S((0, 0.62, 0.0), 0.1, 0.07), S((0, 0.64, 0.0), 0.096, 0.067)], R_GOLD, nc=3))
    seam(t, tg, [(0, 0.83, 0), (0, 0.64, 0)], (0, 0, -1), col=R_DRESS_D, w=0.003)
    for sx in (-1, 1):
        seam(t, tg, [(sx * 0.05, 0.83, 0), (sx * 0.035, 0.64, 0)], (0, 0, -1), col=R_DRESS_D, w=0.003)
    P(m, "col").add(torus((0, 0.905, 0.0), (0, 1, -0.25), 0.052, 0.006, R_GOLD, seg=20, rs=4))  # collier
    P(m, "col_glow").add(ell((0, 0.88, 0.058), 0.009, 0.012, 0.005, R_GEM, n=3, nc=1))
    # jupon bouffant jusqu'au sol + trois volants festonnés
    def rsk(y):
        k = (0.6 - y) / 0.56
        return 0.1 + 0.2 * math.sqrt(max(0.0, k)) + 0.02 * k, 0.07 + 0.19 * math.sqrt(max(0.0, k)) + 0.02 * k
    sk = []
    for y in (0.62, 0.6, 0.58, 0.55, 0.5, 0.42, 0.32, 0.2, 0.1, 0.04):
        a, b = rsk(min(y, 0.6))
        sk.append(S((0, y, 0.0), a, b, min(a, b) * 0.6))
    t.add(loft(sk, R_DRESS, nc=3))
    tiers = ((0.6, 0.42, R_DRESS), (0.45, 0.25, R_FRILL), (0.28, 0.035, R_DRESS))
    for i, (y0, y1, col) in enumerate(tiers):
        def prof(th, y0=y0, y1=y1, i=i):
            w = math.sin(math.radians(th) * 12)
            a0_, _ = rsk(min(y0, 0.6))
            a1_, _ = rsk(y1)
            return [(a0_ + 0.004, y0), (lerp(a0_, a1_, 0.6) + 0.02, lerp(y0, y1, 0.6)), (a1_ + 0.034 + 0.01 * w, y1 + 0.016 + 0.008 * w),
                    (a1_ + 0.036 + 0.012 * w, y1 + 0.004 + 0.012 * w)]
        b_over_a = 0.92 - 0.04 * i
        t.add(revo((0, 0, 0.0), prof, 0.01, [col, col, R_GOLD], inner=R_DRESS_D, seg=60, bz=b_over_a))
    # manches ballon (zones épaule)
    for side, sx in sides():
        e = P(m, "epaule_" + side)
        e.add(ell((sx * 0.162, 0.855, -0.002), 0.058, 0.05, 0.058, R_FRILL, n=6, nc=1))
        e.add(torus((sx * 0.165, 0.81, 0.0), (sx * 0.3, 1, 0), 0.046, 0.006, R_GOLD, seg=18, rs=4))
    # longs gants blancs (jusqu'au-dessus du coude)
    arms(m, WHITE, WHITE, wide=0.94)
    for side, sx in sides():
        a = P(m, "arm_" + side)
        pc, aa, bb = arm_at(sx, 0.77)
        a.add(loft([S(pc + Vector((0, 0.008, 0)), aa * 1.06, bb * 1.06), S(pc - Vector((0, 0.008, 0)), aa * 1.06, bb * 1.06)], R_BOW_D, nc=2))
    # nœud dans le dos (zone dos) : deux boucles, nœud, deux longs pans flottants
    d = P(m, "dos")
    k0 = Vector((0, 0.66, -0.088))
    for sx in (-1, 1):
        d.add(loft(smooth([S(k0 + Vector((sx * 0.01, 0, -0.004)), 0.012, 0.022, 0.006),
                           S(k0 + Vector((sx * 0.06, 0.04, -0.03)), 0.014, 0.044, 0.008),
                           S(k0 + Vector((sx * 0.105, 0.022, -0.026)), 0.01, 0.036, 0.006),
                           S(k0 + Vector((sx * 0.1, -0.012, -0.016)), 0.006, 0.02, 0.004)], 2), R_BOW, nc=1, ref=(0, 1, 0)))
    d.add(box(k0 + Vector((0, 0, -0.012)), (0.018, 0.022, 0.014), 0.007, R_BOW_D, nc=2))
    pv = [(0, 0.655, -0.1), (0, 0.5, -0.17), (0, 0.33, -0.22), (0, 0.16, -0.27)]
    segs = chain(m, "dos", pv[:3], "torso")
    for k, sx in ((1.0, 1), (0.9, -1)):
        for i, sg in enumerate(segs):
            a = Vector(pv[i]) + Vector((sx * (0.012 + 0.03 * i), 0, -0.004 * i))
            b = Vector(pv[i]) + (Vector(pv[i + 1]) - Vector(pv[i])) * k + Vector((sx * (0.012 + 0.03 * (i + 1)), 0, -0.004 * (i + 1)))
            ribbon(sg, a, b, 0.06 + 0.01 * i, 0.07 + 0.01 * i, 0.008, R_BOW, side=(1, 0, 0))
            if i == 2:
                ribbon(sg, b - (b - a) * 0.14, b, 0.092, 0.092, 0.01, R_GOLD, side=(1, 0, 0))
    # escarpins d'or (zone jambe)
    legs(m, SKIN, None, None, None)
    for side, sx in sides():
        b = P(m, "jambe_" + side)
        x = sx * 0.077
        b.add(loft(smooth([S((x, 0.04, -0.05), 0.028, 0.03), S((x, 0.04, 0.0), 0.034, 0.03), S((x, 0.028, 0.08), 0.03, 0.02),
                           S((x, 0.024, 0.13), 0.012, 0.012)], 2), R_GOLD, nc=2))
        b.add(box((x, 0.02, -0.05), (0.006, 0.02, 0.006), 0.002, R_GOLD_D))
    blaster(m, shell_col=WHITE, stripe=R_DRESS, metal=R_GOLD_D, glow=R_GEM)
    return m


# ------------------------------------------------------------------ Plongeuse (lagon, rare)
D_NEO = "#1C2232"
D_TURQ = "#14C8E0"
D_TURQ_D = "#0A8FA8"
D_PINK = "#FF5CA8"
D_TANK = "#FFD23A"
D_TANK_D = "#D9A514"
D_GLASS = "#BFF6FF"
D_GLOW = "#7AF2FF"


def plongeuse():
    """Plongeuse : combinaison néoprène bicolore (turquoise, col, flancs et bras noirs), ceinture de
    lest, masque rose relevé sur le front et tuba qui dépasse au-dessus de la tête, grosse bouteille jaune dans
    le dos (robinet, détendeur, manomètre lumineux, tuyau jusqu'à l'épaule), ordinateur de plongée lumineux au
    poignet, bottillons et grandes palmes roses."""
    m = Model("jo_plongeuse")
    hg = head(m, iris="#1A6A80")
    hair_bob(m, "#22202E", ponytail=True, long_side=False)
    # masque relevé + tuba (zone coiffe)
    c = P(m, "coiffe")
    c.add(shell([{"c": (0, 1.118, -0.008), "a": 0.098, "b": 0.108, "a0": 0, "a1": 360},
                 {"c": (0, 1.138, -0.01), "a": 0.096, "b": 0.106, "a0": 0, "a1": 360}], 0.01, D_NEO, seg=32))  # sangle
    mc = Vector((0, 1.17, 0.07))
    mn = Vector((0, 0.75, 0.66)).normalized()
    c.add(loft([S(mc - mn * 0.012, 0.068, 0.036, 0.024), S(mc + mn * 0.014, 0.072, 0.04, 0.026), S(mc + mn * 0.024, 0.066, 0.034, 0.022)],
               D_PINK, nc=2, ref=(1, 0, 0)))
    c.add(loft([S(mc + mn * 0.022, 0.058, 0.026, 0.018), S(mc + mn * 0.028, 0.058, 0.026, 0.018)], D_GLASS, nc=2, ref=(1, 0, 0)))
    c.add(box(mc + mn * 0.03 + Vector((0.02, 0.008, 0)), (0.012, 0.004, 0.002), 0.001, WHITE, up=mn))
    c.add(loft([S(mc - mn * 0.004 + Vector((0, -0.036, 0.0)), 0.014, 0.012, 0.005), S(mc + mn * 0.02 + Vector((0, -0.044, 0.004)), 0.012, 0.01, 0.004)],
               D_PINK, nc=1))  # nez du masque
    sn = [(0.104, 1.08, 0.02), (0.112, 1.15, 0.0), (0.112, 1.24, -0.02), (0.104, 1.31, -0.03), (0.09, 1.335, -0.026)]
    c.add(loft(smooth([S(p, 0.011, 0.011, 0.005) for p in sn], 2), D_TURQ, nc=2))
    c.add(loft([S((0.091, 1.322, -0.026), 0.016, 0.016, 0.006), S((0.084, 1.345, -0.024), 0.016, 0.016, 0.006)], D_PINK, nc=2))
    c.add(box((0.1, 1.12, 0.012), (0.008, 0.012, 0.012), 0.004, D_PINK))  # attache du tuba
    # combinaison : turquoise, col et flancs noirs, fermeture rose dans le dos
    tg = torso(m, [(0.5, 0.06, 0.05, 0.0, None), (0.525, 0.1, 0.07, 0.0, None), (0.57, 0.106, 0.073, 0.0, None),
                   (0.64, 0.094, 0.065, 0.002, None), (0.72, 0.099, 0.069, 0.006, None), (0.8, 0.119, 0.077, 0.01, None),
                   (0.855, 0.132, 0.075, 0.004, None), (0.888, 0.128, 0.067, 0.0, None), (0.912, 0.084, 0.055, -0.004, None),
                   (0.95, 0.046, 0.044, -0.004, None), (0.975, 0.044, 0.042, -0.004, None)], D_TURQ)
    P(m, "torso").geo.paint(lambda c, n: (c.y > 0.82 and c.y - 0.82 > 0.06 - abs(c.x) * 0.5) or (abs(c.x) > 0.085 and 0.6 < c.y < 0.84), D_NEO)
    t = P(m, "torso")
    seam(t, tg, [(0, 0.95, 0), (0, 0.66, 0)], (0, 0, 1), col=D_PINK, w=0.005)
    seam(t, tg, [(0, 0.86, 0), (0, 0.64, 0)], (0, 0, -1), col=D_NEO, w=0.006)
    # ceinture de lest : sangle, plombs, boucle
    t.add(loft([S((0, 0.585, 0), 0.114, 0.082), S((0, 0.61, 0), 0.11, 0.079)], "#2C3448", nc=2))
    t.add(box((0, 0.598, 0.084), (0.022, 0.018, 0.008), 0.004, "#C7CDD8"))
    for a in (25, 155, 210, 330):
        th = math.radians(a)
        t.add(box((math.cos(th) * 0.112, 0.598, math.sin(th) * 0.082), (0.02, 0.02, 0.016), 0.006, "#6F7A90",
                  ref=(-math.sin(th), 0, math.cos(th))))
    # bouteille dans le dos (zone dos)
    d = P(m, "dos")
    tc = Vector((0, 0, -0.152))
    d.add(loft(smooth([S(tc + Vector((0, 0.5, 0)), 0.04, 0.04), S(tc + Vector((0, 0.51, 0)), 0.056, 0.056), S(tc + Vector((0, 0.82, 0)), 0.058, 0.058),
                       S(tc + Vector((0, 0.87, 0)), 0.046, 0.046), S(tc + Vector((0, 0.9, 0)), 0.02, 0.02)], 2), D_TANK, nc=3))
    for y in (0.6, 0.76):
        d.add(loft([S(tc + Vector((0, y - 0.012, 0)), 0.061, 0.061), S(tc + Vector((0, y + 0.012, 0)), 0.061, 0.061)], D_NEO, nc=3))
    d.add(loft([S(tc + Vector((0, 0.82, 0)), 0.0595, 0.0595), S(tc + Vector((0, 0.835, 0)), 0.0575, 0.0575)], D_TURQ, nc=3))
    d.add(loft([S(tc + Vector((0, 0.895, 0)), 0.014, 0.014), S(tc + Vector((0, 0.93, 0)), 0.014, 0.014)], "#C7CDD8", nc=2))  # robinet
    d.add(box(tc + Vector((0, 0.93, 0)), (0.03, 0.012, 0.014), 0.005, "#C7CDD8"))
    d.add(box(tc + Vector((0.036, 0.93, 0)), (0.012, 0.016, 0.016), 0.005, D_NEO))  # premier étage
    d.add(loft(smooth([S(tc + Vector((0.046, 0.93, 0)), 0.007, 0.007), S((0.11, 0.96, -0.08), 0.007, 0.007), S((0.13, 0.93, 0.0), 0.007, 0.007),
                       S((0.1, 0.86, 0.07), 0.007, 0.007)], 2), D_NEO, nc=1))  # tuyau
    d.add(box((0.098, 0.85, 0.078), (0.016, 0.016, 0.012), 0.006, D_NEO))  # détendeur de secours
    d.add(loft(smooth([S(tc + Vector((-0.04, 0.93, 0)), 0.006, 0.006), S((-0.1, 0.88, -0.12), 0.006, 0.006), S((-0.13, 0.7, -0.08), 0.006, 0.006)], 2),
               D_NEO, nc=1))
    d.add(ell((-0.134, 0.68, -0.08), 0.022, 0.022, 0.012, D_NEO, n=4, nc=1, up=(0, 0, 1)))
    P(m, "dos_glow").add(disc((-0.134, 0.68, -0.093), (0, 0, -1), 0.0, 0.016, 0.004, D_GLOW, seg=14))
    for sx in (-1, 1):  # bretelles du gilet
        d.add(loft([S((sx * 0.05, 0.9, -0.1), 0.014, 0.004, 0.002), S((sx * 0.075, 0.92, -0.02), 0.014, 0.004, 0.002),
                    S((sx * 0.074, 0.9, 0.05), 0.014, 0.004, 0.002), S(on_surf(tg, sx * 0.065, 0.75, 1, 0.004), 0.014, 0.004, 0.002),
                    S(on_surf(tg, sx * 0.07, 0.63, 1, 0.004), 0.014, 0.004, 0.002)], D_NEO, nc=1, ref=(1, 0, 0)))
    # bras : néoprène, bande turquoise, gants, ordinateur de plongée lumineux au poignet gauche
    arms(m, D_NEO, D_NEO, wide=1.02, stripe=D_TURQ, cuff=D_TURQ, cuff_y=0.565)
    for side, sx in sides():  # épaules turquoise (lisibles vues de dessus)
        P(m, "epaule_" + side).add(shell([{"c": (sx * 0.15, 0.94, -0.002), "a": 0.018, "b": 0.02, "a0": 0, "a1": 360},
                                          {"c": (sx * 0.15, 0.915, -0.002), "a": 0.046, "b": 0.05, "a0": 0, "a1": 360},
                                          {"c": (sx * 0.152, 0.86, -0.002), "a": 0.05, "b": 0.052, "a0": 0, "a1": 360}],
                                         0.008, D_TURQ, inner=D_TURQ_D, seg=20))
    a = P(m, "arm_l")
    a.add(box((0.19, 0.59, 0.07), (0.022, 0.02, 0.008), 0.005, D_NEO, up=(0, 1, 0), ref=(1, 0, 0)))
    P(m, "arm_l_glow").add(box((0.19, 0.59, 0.079), (0.016, 0.014, 0.002), 0.002, D_GLOW))
    # jambes : turquoise, bande noire sur l'extérieur, bottillons et palmes roses
    legs(m, D_TURQ, None, None, None, knee="#2C3448")
    for side, sx in sides():
        for nm in ("leg_", "shin_"):
            P(m, nm + side).geo.paint(lambda c, n, sx=sx: c.x * sx > 0.07 + 0.026 and c.y > 0.14, D_NEO)
        b = P(m, "jambe_" + side)
        x = sx * 0.077
        b.add(loft(smooth([S((x, 0.05, -0.05), 0.034, 0.03), S((x, 0.05, -0.02), 0.04, 0.042), S((x, 0.044, 0.05), 0.04, 0.03),
                           S((x, 0.034, 0.1), 0.026, 0.02)], 2), D_NEO, nc=2))
        b.add(loft([S((x, 0.05, -0.012), 0.04, 0.043), S((x, 0.14, -0.006), 0.04, 0.042)], D_NEO, nc=2))
        # palme : chausson rose, grande lame évasée à nervures turquoise
        b.add(loft(smooth([S((x, 0.036, -0.06), 0.036, 0.022), S((x, 0.04, 0.0), 0.046, 0.034), S((x, 0.03, 0.09), 0.044, 0.024),
                           S((x, 0.02, 0.13), 0.044, 0.012)], 2), D_PINK, nc=2))
        bl = [S((x, 0.018, 0.12), 0.046, 0.008, 0.003), S((x, 0.014, 0.2), 0.064, 0.006, 0.003), S((x, 0.01, 0.28), 0.08, 0.005, 0.002),
              S((x, 0.008, 0.31), 0.082, 0.004, 0.002)]
        b.add(loft(bl, D_PINK, nc=1, ref=(1, 0, 0)))
        for rx in (-1, 1):
            b.add(loft([S((x + rx * 0.042, 0.022, 0.12), 0.006, 0.008, 0.003), S((x + rx * 0.078, 0.014, 0.3), 0.005, 0.006, 0.002)], D_TURQ, nc=1))
        b.add(loft([S((x, 0.02, 0.15), 0.004, 0.004, 0.002), S((x, 0.014, 0.29), 0.004, 0.004, 0.002)], D_TURQ_D, nc=1))
    blaster(m, shell_col=D_TANK, stripe=D_NEO, metal=D_NEO, glow=D_GLOW)
    return m
