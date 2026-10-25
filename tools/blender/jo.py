"""Jo, la Passeuse — modèle et tenues, sculptés dans Blender (sans interface) par parts rigides.

/opt/bpyenv/bin/python tools/blender/jo.py jo [concept_toits ...]   -> assets/chars3d/<nom>.glb

Direction : coureuse urbaine stylisée (Mirror's Edge, Spider-Verse) : ~5 têtes, jambes longues, formes nettes à
chanfreins, aplats francs, blanc / gris clair dominants et un accent rouge vif. Rendu « BD » par le shader de Jo
(shaders/jo_comic.gdshader + contour d'encre shaders/jo_ink.gdshader).

Contrat du rig (scripts/rig3d.gd) — noms et pivots des parts (repère du jeu, Jo regarde vers +Z, droite en -X) :
  torso (hanches)  head (cou)  hair (enfant de head)  arm_r / arm_l (épaules)  gun (main droite, enfant de arm_r)
  leg_r / leg_l (hanches)  shin_r / shin_l (genoux, enfants des cuisses)  *_glow : lumineux (enfant de sa part)
Les pièces que l'équipement porté peut remplacer sont des parts à part, nommées par zone (voir scripts/rig3d.gd,
OUTFIT_ZONES) : coiffe (capuche, chapeau, heaume), visage (masque, visière), col, dos (cape, sac, logo),
epaule_r / epaule_l, jambe_r / jambe_l (bottes, jambières). Une part de zone est enfant de la part qui la porte.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from jo_lib import *  # noqa

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

PIV = {
    "torso": (0, 0.57, 0), "head": (0, 0.93, 0), "hair": (0, 0.93, 0),
    "arm_r": (-0.152, 0.882, 0), "arm_l": (0.152, 0.882, 0), "gun": (-0.19, 0.5, 0.05),
    "leg_r": (-0.07, 0.57, 0), "leg_l": (0.07, 0.57, 0), "shin_r": (-0.074, 0.335, 0.004), "shin_l": (0.074, 0.335, 0.004),
}
PARENT = {"torso": None, "head": "torso", "hair": "head", "arm_r": "torso", "arm_l": "torso", "gun": "arm_r",
          "leg_r": "torso", "leg_l": "torso", "shin_r": "leg_r", "shin_l": "leg_l"}
# zones de tenue -> part qui les porte
ZONE_HOST = {"coiffe": "head", "visage": "head", "col": "torso", "dos": "torso", "epaule_r": "arm_r",
             "epaule_l": "arm_l", "jambe_r": "shin_r", "jambe_l": "shin_l"}

SKIN = "#E3A47C"
SKIN_D = "#C98663"
INK = "#15161C"
WHITE = "#F4F4F1"
LGRAY = "#C9CED6"
MGRAY = "#8E96A3"
DGRAY = "#3A3F4B"
RED = "#F0262E"
RED_D = "#B5141E"
GLOW = "#9FF6FF"


def P(m, name):
    """Part du contrat (ou part de zone) avec son pivot et son parent."""
    if name in PIV:
        return m.part(name, PIV[name], PARENT[name])
    base = name[:-5] if name.endswith("_glow") else name
    if base in PIV:
        return m.part(name, PIV[base], base)
    zone = base if base in ZONE_HOST else base.split("_")[0]
    host = ZONE_HOST[zone]
    if name.endswith("_glow"):
        P(m, base)
        return m.part(name, PIV[host], base)
    return m.part(name, PIV[host], host)


def sides():
    return (("r", -1.0), ("l", 1.0))


def extra(m, name, host, parent=None):
    """Part libre (ni du contrat ni de zone) portée par `host` : même pivot, enfant de `parent` (host par défaut)."""
    return m.part(name, PIV[host], parent or host)


def chain(m, prefix, pivots, parent):
    """Pièces qui flottent (pans d'écharpe, cape, plumet, pointe de chapeau) : prefix_f1 enfant de `parent`,
    prefix_f2 enfant de prefix_f1... Le rig (scripts/rig3d.gd, _jo_flow) les fait suivre le mouvement.
    `prefix` commence par une zone (coiffe_, dos_) pour que l'équipement porté les masque avec leur zone."""
    out = []
    for i, pv in enumerate(pivots):
        nm = "%s_f%d" % (prefix, i + 1)
        out.append(m.part(nm, pv, parent if i == 0 else "%s_f%d" % (prefix, i)))
    return out


def ribbon(part, a, b, w0, w1, thick, col, side=(1, 0, 0)):
    """Ruban plat de a à b (largeur w0 -> w1) : pan d'écharpe, de cape, de bandeau."""
    part.add(loft([S(a, w0 * 0.5, thick * 0.5, thick * 0.4), S(b, w1 * 0.5, thick * 0.5, thick * 0.4)], col, nc=1, ref=side))


def S(c, a, b, r=None, **kw):
    d = {"c": c, "a": a, "b": b, "r": r if r is not None else min(a, b) * 0.7}
    d.update(kw)
    return d


def seam(part, host, pts, direction, col=INK, w=0.0028, lift=0.0015):
    """Trait d'encre posé sur une surface (pli, couture, bord de poche) : pts projetés sur `host` selon direction."""
    on = []
    d = V(direction).normalized()
    for p in pts:
        q, n = surface(host, V(p) - d * 0.4, d)
        on.append(q - d * lift)
    part.add(loft([{"c": q, "a": w, "b": w, "r": w * 0.5} for q in on], col, nc=1))


# ------------------------------------------------------------------ tête et visage
HEAD_SECS = [  # y, a, b, z
    (0.95, 0.016, 0.02, 0.04),
    (0.966, 0.038, 0.044, 0.032),
    (0.995, 0.06, 0.07, 0.016),
    (1.035, 0.075, 0.085, 0.006),
    (1.085, 0.081, 0.092, -0.002),
    (1.135, 0.077, 0.09, -0.009),
    (1.172, 0.06, 0.074, -0.012),
    (1.196, 0.03, 0.04, -0.013),
]


def head(m, eyes=INK, brows="#2A2230", mark=None, mouth="#7A2E36", iris="#3B2A26"):
    h = P(m, "head")
    secs = [S((0, y, z), a, b, min(a, b) * 0.7) for (y, a, b, z) in HEAD_SECS]
    hg = loft(smooth(secs, 2), SKIN, nc=3)
    h.add(hg)
    # cou long et fin
    h.add(loft([S((0, 0.885, -0.006), 0.028, 0.03), S((0, 0.98, -0.004), 0.027, 0.029)], SKIN, nc=2))
    for sx in (-1, 1):
        h.add(ell((sx * 0.08, 1.058, -0.008), 0.01, 0.019, 0.014, SKIN_D, n=4))
    def on(x, y, out=0.0):
        p, n = surface(hg, (x, y, 0.4), (0, 0, -1))
        return p + Vector((0, 0, out))
    for sx in (-1, 1):
        e = on(sx * 0.034, 1.05)
        g = ell(e + Vector((0, 0, -0.0015)), 0.017, 0.0105, 0.006, eyes, n=4, nc=2)
        rot(g, e, (0, 0, 1), sx * -9)
        h.add(g)
        h.add(ell(e + Vector((sx * 0.003, -0.002, 0.003)), 0.0075, 0.0085, 0.003, iris, n=3, nc=2))
        h.add(ell(e + Vector((sx * -0.004, 0.004, 0.0048)), 0.0035, 0.0035, 0.002, "#FFFFFF", n=3, nc=1))
        b = on(sx * 0.037, 1.078)
        bg = box(b + Vector((0, 0, 0.0015)), (0.018, 0.0032, 0.004), 0.0015, brows)
        rot(bg, b, (0, 0, 1), sx * 12)
        h.add(bg)
    n = on(0, 1.018)
    h.add(ell(n + Vector((0, -0.002, 0.001)), 0.007, 0.011, 0.007, SKIN_D, n=3, nc=1))
    mo = on(0, 0.984)
    mg = box(mo + Vector((0, 0, 0.0008)), (0.011, 0.0022, 0.003), 0.0012, mouth)
    rot(mg, mo, (0, 0, 1), -6)
    h.add(mg)
    if mark:  # trait graphique sous l'œil droit (Mirror's Edge)
        pts = [on(-0.058, 1.044, 0.0015), on(-0.05, 1.03, 0.0015), on(-0.035, 1.022, 0.0015)]
        h.add(loft([S(p, 0.0032, 0.0032) for p in pts], mark, nc=1))
    return hg


# ------------------------------------------------------------------ cheveux
def hair_bob(m, col, hi=None, ponytail=False, long_side=True):
    """Carré net (coque) + frange en mèches pointues, mèche longue à droite ; queue de cheval en option."""
    hp = P(m, "hair")
    secs = [
        {"c": (0, 0.99, -0.022), "a": 0.088, "b": 0.096, "a0": 152, "a1": 388},
        {"c": (0, 1.04, -0.014), "a": 0.093, "b": 0.101, "a0": 150, "a1": 390},
        {"c": (0, 1.1, -0.008), "a": 0.092, "b": 0.102, "a0": 128, "a1": 412},
        {"c": (0, 1.155, -0.012), "a": 0.08, "b": 0.092, "a0": 100, "a1": 440},
        {"c": (0, 1.195, -0.014), "a": 0.054, "b": 0.065, "a0": 90, "a1": 450},
        {"c": (0, 1.215, -0.016), "a": 0.016, "b": 0.02, "a0": 90, "a1": 450},
    ]
    hp.add(shell(secs, 0.016, col, seg=24))
    # frange : mèches en lames, pointes vers le bas et la droite
    for x0, x1, y1, w in ((-0.062, -0.08, 1.04, 0.036), (-0.028, -0.05, 1.07, 0.042), (0.008, -0.012, 1.085, 0.042),
                          (0.044, 0.03, 1.08, 0.04), (0.072, 0.07, 1.05, 0.03)):
        pts = [(x0 * 0.5, 1.2, 0.045), (x0 * 0.9, 1.17, 0.082), (x0 * 0.5 + x1 * 0.5, 1.12, 0.098), (x1, y1, 0.098)]
        hp.add(loft([S(pts[0], w * 0.5, 0.011, 0.004), S(pts[1], w * 0.5, 0.011, 0.004),
                     S(pts[2], w * 0.38, 0.008, 0.003), S(pts[3], w * 0.06, 0.004, 0.001)], col, nc=1))
    if long_side:
        pts = [(-0.088, 1.1, 0.04), (-0.098, 1.03, 0.05), (-0.09, 0.97, 0.052), (-0.08, 0.93, 0.05)]
        hp.add(loft([S(pts[0], 0.012, 0.022, 0.005), S(pts[1], 0.011, 0.02, 0.005), S(pts[2], 0.008, 0.012, 0.003),
                     S(pts[3], 0.002, 0.003, 0.001)], col, nc=1))
    if hi:
        hp.geo.paint(lambda c, n: c.y > 1.11 and -0.06 < c.x < -0.02, hi)
    if ponytail:
        pts = [(0, 1.15, -0.1), (0, 1.135, -0.14), (0, 1.07, -0.17), (0, 0.99, -0.175), (0, 0.92, -0.16), (0, 0.87, -0.14)]
        ws = [0.026, 0.03, 0.03, 0.024, 0.014, 0.003]
        hp.add(loft(smooth([S(p, w, w * 0.75, w * 0.4) for p, w in zip(pts, ws)], 2), col, nc=1))
        hp.add(torus((0, 1.142, -0.118), (0, 0.35, -1), 0.024, 0.007, RED, seg=14, rs=4))
    return hp


# ------------------------------------------------------------------ torse
def torso(m, secs, col, nc=3, k=2):
    """secs : (y, a, b, z, couleur de la bande ou None). Renvoie la géométrie (pour poser motifs et coutures)."""
    t = P(m, "torso")
    ss = []
    for (y, a, b, z, c) in secs:
        s = S((0, y, z), a, b, min(a, b) * 0.62)
        if c:
            s["col"] = c
        ss.append(s)
    g = loft(smooth(ss, k), col, nc=nc)
    t.add(g)
    return g


FITTED = [  # veste ajustée : hanches, taille marquée, poitrine, épaules nettes
    (0.5, 0.06, 0.05, 0.0, None), (0.525, 0.1, 0.07, 0.0, None), (0.57, 0.108, 0.074, 0.0, None),
    (0.64, 0.096, 0.066, 0.002, None), (0.72, 0.1, 0.07, 0.006, None), (0.8, 0.12, 0.078, 0.01, None),
    (0.855, 0.134, 0.076, 0.004, None), (0.888, 0.13, 0.068, 0.0, None), (0.912, 0.085, 0.056, -0.004, None),
    (0.93, 0.04, 0.04, -0.004, None)]


def jacket(m, col, hem_y, hem_col, pants_col, wide=1.0, length=0.0):
    """Veste sur le modèle FITTED : la bande sous l'ourlet prend la couleur du pantalon."""
    secs = []
    for (y, a, b, z, c) in FITTED:
        k = wide if y > 0.56 else 1.0
        if y < hem_y - length:
            c = pants_col
        secs.append((y, a * k, b * k, z, c))
    # ourlet : petit rebord net
    secs.append((hem_y - length, 0.104 * wide + 0.006, 0.072 * wide + 0.006, 0.0, hem_col))
    secs.append((hem_y - length + 0.025, 0.1 * wide + 0.006, 0.07 * wide + 0.006, 0.0, None))
    secs.sort(key=lambda s: s[0])
    return torso(m, secs, col)


def back_logo(part, host_geo, y, R, col, depth=0.005, x=0.0):
    """Logo des Passeurs : anneau-portail ouvert traversé d'une flèche, posé sur le dos (vers -Z)."""
    p, n = surface(host_geo, (x, y, -0.5), (0, 0, 1))
    c = p + Vector((0, 0, -depth * 0.3))
    part.add(disc(c, (0, 0, -1), R * 0.68, R, depth, col, seg=40, arc=(70.0, 340.0)))
    # flèche diagonale qui traverse l'anneau et sort par l'ouverture (en haut à droite, vue de dos)
    tip = c + Vector((-R * 0.78, R * 0.78, -0.001))
    tail = c + Vector((R * 0.3, -R * 0.3, -0.001))
    w = R * 0.15
    part.add(loft([S(tail, depth * 0.5, w, depth * 0.2), S(tip, depth * 0.5, w, depth * 0.2)], col, nc=1, ref=(0, 0, 1)))
    for dx, dy in ((1, 0), (0, -1)):
        e = tip + Vector((dx * R * 0.46, dy * R * 0.46, 0))
        part.add(loft([S(e, depth * 0.5, w * 0.95, depth * 0.2), S(tip + Vector((dx * -w * 0.25, dy * -w * 0.25, 0)), depth * 0.5, w * 0.95, depth * 0.2)],
                      col, nc=1, ref=(0, 0, 1)))
    return c


# ------------------------------------------------------------------ bras
ARM = [  # x (côté), y, z, a, b : épaule -> poignet, coude un peu fléchi vers l'avant
    (0.138, 0.905, -0.002, 0.034, 0.038), (0.155, 0.88, 0.0, 0.041, 0.043), (0.165, 0.825, -0.004, 0.037, 0.039),
    (0.172, 0.76, -0.008, 0.032, 0.034), (0.176, 0.705, -0.006, 0.029, 0.031), (0.18, 0.645, 0.012, 0.03, 0.03),
    (0.185, 0.585, 0.032, 0.026, 0.025), (0.188, 0.548, 0.044, 0.023, 0.022)]


def arms(m, sleeve, glove, sleeve_l=None, wide=1.0, cuff=None, cuff_y=0.56, stripe=None, glove_l=None,
         roll=None):
    """Manches longues sur le bras ; `wide` : manche ample ; `cuff` : poignet de couleur ; `stripe` : bande
    sur le dessus de la manche ; `roll` : manche retroussée à cette hauteur (avant-bras nu en dessous)."""
    for side, sx in sides():
        a = P(m, "arm_" + side)
        sc = sleeve_l if (sleeve_l and side == "l") else sleeve
        ss = []
        for (x, y, z, aa, bb) in ARM:
            k = wide if y > cuff_y else 1.0 + (wide - 1.0) * 0.6
            s = S((sx * x, y, z), aa * k, bb * k)
            if roll and y < roll:
                s = S((sx * x, y, z), aa * 0.88, bb * 0.88, col=SKIN)
            ss.append(s)
        if cuff:
            ss.append(S((sx * 0.187, cuff_y + 0.006, 0.04), 0.03 * wide, 0.029 * wide, col=cuff))
            ss.sort(key=lambda s: -s["c"][1])
        if roll:
            ss.append(S((sx * 0.18, roll + 0.01, 0.01), 0.036 * wide, 0.035 * wide, col=sc))
            ss.append(S((sx * 0.181, roll - 0.012, 0.014), 0.035 * wide, 0.034 * wide, col=SKIN))
            ss.sort(key=lambda s: -s["c"][1])
        g = loft(smooth(ss, 2), sc, nc=3, ref=(1, 0, 0))
        if stripe:
            g.paint(lambda c, n, sx=sx: n.x * sx > 0.45 and c.y > 0.6, stripe)
        a.add(g)
        a.add(ell((sx * 0.146, 0.884, -0.002), 0.046, 0.042, 0.046, sc, n=5, nc=3))
        fist(a, sx, glove_l if (glove_l and side == "l") else glove)


def fist(part, sx, col):
    c = Vector((sx * 0.19, 0.51, 0.052))
    part.add(box(c, (0.02, 0.028, 0.026), 0.011, col, nc=2))
    part.add(ell(c + Vector((-sx * 0.016, 0.012, 0.02)), 0.009, 0.016, 0.009, col, n=4))  # pouce
    part.add(box(c + Vector((0, -0.026, 0.004)), (0.018, 0.006, 0.022), 0.004, col, nc=1))  # jointures


# ------------------------------------------------------------------ jambes
THIGH = [(0.066, 0.62, 0.0, 0.058, 0.062), (0.068, 0.55, 0.004, 0.056, 0.06), (0.071, 0.47, 0.006, 0.049, 0.052),
         (0.073, 0.4, 0.006, 0.042, 0.045), (0.074, 0.34, 0.006, 0.037, 0.04)]
SHIN = [(0.074, 0.36, 0.006, 0.037, 0.04), (0.075, 0.3, -0.002, 0.038, 0.042), (0.075, 0.24, -0.006, 0.035, 0.038),
        (0.076, 0.17, -0.006, 0.028, 0.03), (0.076, 0.11, -0.006, 0.024, 0.026)]


def legs(m, pants, shoe, sole, toe, short=None, knee=None, cuff=None, shoe_stripe=None, high=False, wide=1.0,
         lace=INK):
    """Pantalon (ou legging sous un short `short`), genouillère `knee`, revers `cuff`, baskets épaisses."""
    for side, sx in sides():
        l = P(m, "leg_" + side)
        ss = [S((sx * x, y, z), a * wide, b * wide) for (x, y, z, a, b) in THIGH]
        if short:
            ss = [S((sx * x, y, z), a * 1.22, b * 1.2, col=short) if y > 0.46 else S((sx * x, y, z), a, b) for (x, y, z, a, b) in THIGH]
            ss.insert(3, S((sx * 0.072, 0.448, 0.006), 0.06, 0.063, col=short))
            ss.insert(4, S((sx * 0.072, 0.445, 0.006), 0.047, 0.05))
        l.add(loft(smooth(ss, 2) if not short else ss, pants, nc=3))
        s = P(m, "shin_" + side)
        k = wide
        ss = [S((sx * x, y, z), a * k, b * k) for (x, y, z, a, b) in SHIN]
        if cuff:
            ss[-1] = S((sx * 0.076, 0.135, -0.006), 0.034 * k, 0.036 * k, col=cuff)
            ss.append(S((sx * 0.076, 0.105, -0.006), 0.033 * k, 0.035 * k))
        s.add(loft(smooth(ss, 2), pants, nc=3))
        if knee:
            s.add(box((sx * 0.075, 0.335, 0.036), (0.034, 0.038, 0.012), 0.01, knee, nc=2))
        if shoe:  # chaussures : part de zone « jambe_* » (des bottes portées les remplacent)
            sneaker(P(m, "jambe_" + side), sx, shoe, sole, toe, shoe_stripe, high, lace)


def sneaker(part, sx, upper, sole, toe, stripe=None, high=False, lace=INK):
    x = sx * 0.077
    # semelle épaisse : tube le long de Z (largeur en X, demi-hauteur en Y)
    sz = [(-0.065, 0.03, 0.016), (-0.052, 0.042, 0.02), (0.0, 0.046, 0.02), (0.07, 0.05, 0.02), (0.12, 0.045, 0.018),
          (0.148, 0.03, 0.013)]
    part.add(loft([S((x, 0.02, z), a, b, min(a, b) * 0.7) for z, a, b in sz], sole, nc=2, ref=(1, 0, 0)))
    part.add(loft([S((x, 0.04, z), a + 0.002, 0.003, 0.002) for z, a, b in sz[1:-1]], toe if toe != upper else RED, nc=1))
    uz = [(-0.058, 0.03, 0.04, 0.078), (-0.046, 0.04, 0.05, 0.085), (0.0, 0.043, 0.05, 0.085), (0.06, 0.044, 0.034, 0.07),
          (0.112, 0.038, 0.022, 0.058), (0.138, 0.024, 0.012, 0.05)]
    ss = []
    for i, (z, a, b, yc) in enumerate(uz):
        s = S((x, yc, z), a, b, min(a, b) * 0.6)
        if i >= 3:
            s["col"] = toe
        ss.append(s)
    g = loft(smooth(ss, 2), upper, nc=2)
    if stripe:
        g.paint(lambda c, n: abs(n.x) > 0.55 and 0.055 < c.y < 0.1 and -0.035 < c.z < 0.075, stripe)
    part.add(g)
    if high:
        part.add(loft([S((x, 0.1, -0.012), 0.04, 0.046), S((x, 0.165, -0.01), 0.036, 0.04), S((x, 0.18, -0.01), 0.038, 0.042)], upper, nc=2))
    tg = box((x, 0.112 if not high else 0.13, 0.03), (0.02, 0.034, 0.007), 0.004, upper, up=(0, 0.75, 0.66))
    part.add(tg)
    for i in range(3):
        part.add(box((x, 0.096 - i * 0.012 + (0.018 if high else 0.0), 0.043 + i * 0.013), (0.022, 0.003, 0.004), 0.0015, lace))


# ------------------------------------------------------------------ blaster (repère compatible : MUZZLE de rig3d.gd)
def blaster(m, shell_col=WHITE, stripe=RED, metal=DGRAY, glow=GLOW):
    """Bout du canon à (0, -0.225, 0.058) du pivot de la main (MUZZLE[""] de scripts/rig3d.gd)."""
    g = P(m, "gun")
    o = Vector(PIV["gun"])
    def L(x, y, z):
        return o + Vector((x, y, z))
    g.add(box(L(0, -0.075, 0.052), (0.03, 0.085, 0.04), 0.012, shell_col, nc=2))
    g.add(box(L(0, -0.06, 0.093), (0.02, 0.066, 0.008), 0.004, stripe))
    g.add(box(L(0, -0.005, 0.014), (0.019, 0.026, 0.024), 0.007, metal))  # poignée
    g.add(loft([S(L(0, -0.155, 0.058), 0.022, 0.022), S(L(0, -0.205, 0.058), 0.02, 0.02)], metal, nc=2))
    g.add(loft([S(L(0, -0.2, 0.058), 0.027, 0.027), S(L(0, -0.222, 0.058), 0.027, 0.027)], stripe, nc=2))
    gg = P(m, "gun_glow")
    gg.add(disc(L(0, -0.223, 0.058), (0, -1, 0), 0.0, 0.016, 0.004, glow, seg=16))
    gg.add(box(L(0.0312, -0.075, 0.052), (0.002, 0.05, 0.011), 0.001, glow))
    gg.add(box(L(-0.0312, -0.075, 0.052), (0.002, 0.05, 0.011), 0.001, glow))


# ------------------------------------------------------------------ concepts
def concept_toits():
    """A « Toits » : coureuse de toits. Carré noir à mèche rouge, veste technique blanche courte à manche droite
    rouge et col montant, anneau rouge dans le dos, jogging gris clair, genouillères, baskets rouges."""
    m = Model("concept_toits")
    head(m, mark=RED)
    hair_bob(m, "#1D1B24", hi=RED, ponytail=True)
    tg = jacket(m, WHITE, 0.6, LGRAY, MGRAY)
    t = P(m, "torso")
    t.add(shell([{"c": (0, 0.895, -0.004), "a": 0.07, "b": 0.06, "a0": 0, "a1": 360},
                 {"c": (0, 0.965, -0.008), "a": 0.05, "b": 0.045, "a0": 0, "a1": 360}], 0.008, WHITE))
    seam(t, tg, [(0.0, 0.89, 0), (0.0, 0.62, 0)], (0, 0, -1), col=LGRAY, w=0.003)
    d = P(m, "dos")
    back_logo(d, tg, 0.775, 0.066, RED)
    d.add(box((0.098, 0.56, -0.06), (0.03, 0.03, 0.05), 0.012, RED))  # sac banane
    arms(m, RED, INK, sleeve_l=WHITE, cuff=INK, cuff_y=0.565)
    legs(m, LGRAY, RED, WHITE, RED, knee=DGRAY, cuff=MGRAY, shoe_stripe=WHITE)
    blaster(m)
    return m


def concept_capuche():
    """B « Capuche » : sweat à capuche blanc ample, capuche relevée doublée de rouge et bande rouge sur le dessus,
    anneau rouge dans le dos, short noir sur legging gris, baskets montantes, sacoche noire en bandoulière."""
    m = Model("concept_capuche")
    head(m)
    hp = P(m, "hair")
    for x0, x1, y1, w in ((-0.05, -0.068, 1.045, 0.036), (-0.015, -0.03, 1.07, 0.04), (0.02, 0.008, 1.075, 0.04), (0.055, 0.05, 1.055, 0.032)):
        pts = [(x0 * 0.6, 1.17, 0.06), (x0, 1.13, 0.09), (x1, y1, 0.098)]
        hp.add(loft([S(pts[0], w * 0.5, 0.011, 0.004), S(pts[1], w * 0.42, 0.01, 0.004), S(pts[2], w * 0.06, 0.004, 0.001)], "#2A1E2A", nc=1))
    hp.add(shell([{"c": (0, 1.03, -0.012), "a": 0.087, "b": 0.096, "a0": 150, "a1": 390},
                  {"c": (0, 1.15, -0.014), "a": 0.08, "b": 0.092, "a0": 120, "a1": 420}], 0.01, "#2A1E2A"))
    c = P(m, "coiffe")
    hood = [  # centre, a, b, demi-ouverture devant (degrés)
        ((0, 0.92, -0.03), 0.108, 0.098, 40), ((0, 0.975, -0.024), 0.112, 0.11, 58), ((0, 1.04, -0.02), 0.108, 0.116, 66),
        ((0, 1.11, -0.024), 0.1, 0.116, 64), ((0, 1.17, -0.034), 0.084, 0.108, 56), ((0, 1.215, -0.05), 0.058, 0.09, 44),
        ((0, 1.245, -0.075), 0.03, 0.058, 30), ((0, 1.255, -0.11), 0.008, 0.02, 10)]
    hg = shell([{"c": cc, "a": a, "b": b, "a0": 90 + o, "a1": 450 - o} for cc, a, b, o in hood], 0.014, WHITE, inner=RED, seg=30)
    hg.paint(lambda c, n: abs(c.x) < 0.022 and c.y > 1.0 and c.z < 0.1, RED)
    c.add(hg)
    tg = jacket(m, WHITE, 0.545, LGRAY, INK, wide=1.16)
    t = P(m, "torso")
    t.add(box((0, 0.615, 0.082), (0.072, 0.04, 0.008), 0.006, "#E4E5E8"))  # poche kangourou
    seam(t, tg, [(-0.07, 0.65, 0), (0.07, 0.65, 0)], (0, 0, -1), col=LGRAY, w=0.0025)
    for sx in (-1, 1):
        t.add(loft([S((sx * 0.026, 0.9, 0.062), 0.004, 0.004), S((sx * 0.03, 0.82, 0.088), 0.004, 0.004),
                    S((sx * 0.031, 0.79, 0.092), 0.006, 0.006)], RED, nc=1))
    d = P(m, "dos")
    back_logo(d, tg, 0.76, 0.074, RED)
    d.add(loft([S((0.118, 0.895, -0.05), 0.003, 0.014), S((0.0, 0.79, -0.094), 0.003, 0.014),
                S((-0.11, 0.62, -0.08), 0.003, 0.014)], INK, nc=1, ref=(0, 0, 1)))
    d.add(box((-0.13, 0.59, -0.03), (0.026, 0.045, 0.06), 0.012, INK))
    arms(m, WHITE, INK, wide=1.22, cuff=LGRAY, cuff_y=0.56)
    legs(m, LGRAY, WHITE, WHITE, RED, short=INK, shoe_stripe=RED, high=True)
    blaster(m)
    return m


def concept_masque():
    """C « Masque » : bombers rouge à manches blanches (dos rouge, anneau blanc), cheveux platine en vague avec
    queue haute, loup noir sur les yeux, legging noir, baskets blanches à semelle rouge."""
    m = Model("concept_masque")
    head(m)
    plat = "#F1EBD6"
    hair_bob(m, plat, hi="#FF8A9A", ponytail=True, long_side=False)
    hp = P(m, "hair")
    pts = [(0.02, 1.215, 0.04), (0.075, 1.185, 0.085), (0.104, 1.12, 0.07), (0.1, 1.05, 0.05), (0.09, 1.0, 0.04)]
    hp.add(loft(smooth([S(p, w, w * 0.45, w * 0.3) for p, w in zip(pts, (0.035, 0.042, 0.034, 0.02, 0.004))], 2), plat, nc=1, ref=(0, 0, 1)))
    v = P(m, "visage")
    v.add(shell([{"c": (0, 1.035, 0.004), "a": 0.085, "b": 0.093, "a0": 18, "a1": 162},
                 {"c": (0, 1.068, 0.0), "a": 0.087, "b": 0.096, "a0": 18, "a1": 162}], 0.007, INK))
    tg = jacket(m, RED, 0.585, INK, INK, wide=1.06)
    t = P(m, "torso")
    t.add(shell([{"c": (0, 0.895, -0.004), "a": 0.074, "b": 0.064, "a0": 0, "a1": 360},
                 {"c": (0, 0.94, -0.008), "a": 0.062, "b": 0.054, "a0": 0, "a1": 360}], 0.01, INK))
    seam(t, tg, [(0.0, 0.89, 0), (0.0, 0.6, 0)], (0, 0, -1), col=WHITE, w=0.003)
    d = P(m, "dos")
    back_logo(d, tg, 0.77, 0.078, WHITE)
    arms(m, WHITE, WHITE, cuff=INK, cuff_y=0.565, stripe=RED, wide=1.08)
    legs(m, INK, WHITE, RED, WHITE, shoe_stripe=RED)
    blaster(m)
    return m


# ------------------------------------------------------------------ Jo (modèle de base : concept B « Capuche »)
HAIR = "#2A1E2A"
LEGGING = "#4B515E"


def bangs(m, col=HAIR):
    """Frange en lames sous la capuche, et calotte (visible quand un casque remplace la capuche)."""
    hp = P(m, "hair")
    for x0, x1, y1, w in ((-0.052, -0.072, 1.04, 0.036), (-0.018, -0.036, 1.066, 0.04), (0.018, 0.004, 1.074, 0.04),
                          (0.052, 0.046, 1.056, 0.034)):
        pts = [(x0 * 0.6, 1.17, 0.06), (x0, 1.13, 0.09), (x1, y1, 0.098)]
        hp.add(loft([S(pts[0], w * 0.5, 0.011, 0.004), S(pts[1], w * 0.42, 0.01, 0.004), S(pts[2], w * 0.06, 0.004, 0.001)], col, nc=1))
    hp.add(shell([{"c": (0, 1.0, -0.016), "a": 0.086, "b": 0.094, "a0": 152, "a1": 388},
                  {"c": (0, 1.06, -0.012), "a": 0.09, "b": 0.099, "a0": 150, "a1": 390},
                  {"c": (0, 1.15, -0.014), "a": 0.08, "b": 0.092, "a0": 120, "a1": 420},
                  {"c": (0, 1.205, -0.016), "a": 0.04, "b": 0.05, "a0": 90, "a1": 450}], 0.012, col))
    return hp


HOOD = [  # centre, a, b, demi-ouverture devant (degrés) : capuche ronde et basse, qui retombe sur la nuque
    ((0, 0.915, -0.034), 0.112, 0.1, 38), ((0, 0.97, -0.026), 0.114, 0.112, 56), ((0, 1.04, -0.02), 0.11, 0.117, 66),
    ((0, 1.11, -0.022), 0.104, 0.115, 64), ((0, 1.165, -0.026), 0.09, 0.104, 56), ((0, 1.205, -0.03), 0.065, 0.08, 44),
    ((0, 1.228, -0.033), 0.033, 0.045, 26), ((0, 1.236, -0.035), 0.008, 0.012, 10)]


def hood(m, col=WHITE, lining=RED, band=RED, tails=True):
    """Capuche relevée, doublée de rouge, ceinte d'un bandeau rouge (d'en haut : l'anneau des Passeurs) noué
    derrière, deux pans qui flottent (coiffe_f1..f3)."""
    c = P(m, "coiffe")
    hg = shell([{"c": cc, "a": a, "b": b, "a0": 90 + o, "a1": 450 - o} for cc, a, b, o in HOOD], 0.014, col, inner=lining, seg=32)
    c.add(hg)
    if band:
        c.add(shell([{"c": (0, 1.088, -0.021), "a": 0.11, "b": 0.121, "a0": 90 + 68, "a1": 450 - 68},
                     {"c": (0, 1.128, -0.026), "a": 0.104, "b": 0.12, "a0": 90 + 65, "a1": 450 - 65}], 0.012, band, seg=32))
        c.add(box((0, 1.108, -0.15), (0.024, 0.022, 0.016), 0.008, band, nc=2))
    if tails:
        pv = [(0, 1.106, -0.158), (0, 1.045, -0.2), (0, 0.98, -0.232), (0, 0.915, -0.25)]
        segs = chain(m, "coiffe", pv[:3], "coiffe")
        for k, sx in ((1.0, 1), (0.85, -1)):
            for i, sg in enumerate(segs):
                a = Vector(pv[i]) + Vector((sx * (0.008 + 0.013 * i), 0, 0))
                b = Vector(pv[i]) + (Vector(pv[i + 1]) - Vector(pv[i])) * k + Vector((sx * (0.008 + 0.013 * (i + 1)), 0, 0))
                ribbon(sg, a, b, 0.024 - 0.002 * i, 0.022 - 0.002 * i - (0.012 if i == 2 else 0.0), 0.005, band)
    return hg


def hoodie(m, col=WHITE, rib=LGRAY, logo=RED, strings=RED, short=INK):
    """Sweat ample : ourlet côtelé, poche kangourou, cordons, logo des Passeurs en grand dans le dos."""
    tg = jacket(m, col, 0.545, rib, short, wide=1.16)
    t = P(m, "torso")
    t.add(box((0, 0.615, 0.083), (0.072, 0.04, 0.008), 0.006, "#E4E5E8"))
    seam(t, tg, [(-0.075, 0.655, 0), (0.075, 0.655, 0)], (0, 0, -1), col=MGRAY, w=0.0022)
    seam(t, tg, [(-0.11, 0.86, 0.0), (-0.12, 0.75, 0.0)], (1, 0, 0), col=LGRAY, w=0.002)
    seam(t, tg, [(0.11, 0.86, 0.0), (0.12, 0.75, 0.0)], (-1, 0, 0), col=LGRAY, w=0.002)
    for sx in (-1, 1):
        t.add(loft([S((sx * 0.026, 0.9, 0.062), 0.004, 0.004), S((sx * 0.03, 0.82, 0.088), 0.004, 0.004),
                    S((sx * 0.031, 0.79, 0.092), 0.0055, 0.0055)], strings, nc=1))
    if logo:
        back_logo(t, tg, 0.76, 0.074, logo)
    return tg


def sling(m, col=INK, accent=RED):
    """Sacoche noire en bandoulière (zone « dos ») : sangle épaule gauche -> hanche droite, devant et derrière."""
    d = P(m, "dos")
    d.add(loft([S((0.118, 0.895, -0.05), 0.003, 0.013), S((0.03, 0.82, -0.098), 0.003, 0.013),
                S((-0.11, 0.63, -0.084), 0.003, 0.013)], col, nc=1, ref=(0, 0, 1)))
    d.add(loft([S((0.118, 0.895, 0.03), 0.003, 0.013), S((0.03, 0.82, 0.092), 0.003, 0.013),
                S((-0.11, 0.63, 0.082), 0.003, 0.013)], col, nc=1, ref=(0, 0, 1)))
    d.add(box((-0.135, 0.6, -0.025), (0.026, 0.046, 0.062), 0.012, col, nc=2))
    d.add(box((-0.162, 0.6, -0.025), (0.003, 0.03, 0.04), 0.002, accent))
    dg = P(m, "dos_glow")
    dg.add(box((-0.1625, 0.62, -0.025), (0.0025, 0.004, 0.024), 0.001, GLOW))


def jo():
    """Jo, la Passeuse : sweat à capuche blanc ample, capuche relevée doublée de rouge et ceinte d'un bandeau
    rouge noué dont les pans flottent, anneau des Passeurs dans le dos, sacoche noire, short noir sur legging
    gris anthracite, baskets montantes blanches et rouges, gants noirs, blaster blanc à bande rouge."""
    m = Model("jo")
    head(m, mark=RED)
    bangs(m)
    hood(m)
    hoodie(m)
    sling(m)
    arms(m, WHITE, INK, wide=1.22, cuff=LGRAY, cuff_y=0.56)
    legs(m, LEGGING, WHITE, WHITE, RED, short=INK, shoe_stripe=RED, high=True)
    blaster(m)
    return m


BUILDS = {"jo": jo, "concept_toits": concept_toits, "concept_capuche": concept_capuche, "concept_masque": concept_masque}


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("-")]
    for nm in names:
        mdl = BUILDS[nm]()
        mdl.export(os.path.join(ROOT, "assets", "chars3d", nm + ".glb"))
