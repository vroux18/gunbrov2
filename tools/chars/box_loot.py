"""Box de butin (écran COFFRES) : quatre raretés, Bronze, Argent, Or, Légendaire.

Coffre trapu et arrondi, lisible de loin : caisse à pieds aux panneaux en creux, couvercle en tonneau,
deux sangles qui passent par-dessus, coins renforcés, grosse serrure à emblème lumineux. Le couvercle est
une part à part, articulée à la charnière arrière (il s'ouvre en code, scripts/ui/boxes_stage.gd). Dans la
caisse, une nappe lumineuse (body_glow) : cachée par le couvercle, elle éclaire tout quand il saute.
L'Argent a des rivets, l'Or des clous d'or et un gros joyau, la Légendaire des cristaux sur le couvercle.

Regarde vers +Z ; posé sur y = 0 ; largeur 1.

Usage : python3 tools/chars/box_loot.py [rareté...]   (écrit assets/loot/box_<rareté>.glb)
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import numpy as np  # noqa: E402
from sculpt import *  # noqa: E402,F401,F403
import sculpt  # noqa: E402

# corps, sangles et coins, métal sombre (serrure, pieds, dessous du couvercle), clous, lumière
PALETTES = {
    "bronze": {"body": "#C67A3C", "band": "#6A3E22", "metal": "#3A2620", "stud": "#E7A86A", "glow": "#FFB45E"},
    "argent": {"body": "#D6E2F0", "band": "#46608E", "metal": "#222E4A", "stud": "#F4F8FF", "glow": "#5CF0FF"},
    "or": {"body": "#FFBE2E", "band": "#D0571A", "metal": "#5A2410", "stud": "#FFF0B0", "glow": "#FFF2A0"},
    "legendaire": {"body": "#8A4FF2", "band": "#FFBE2E", "metal": "#2A1458", "stud": "#FFF0B0", "glow": "#FF8AF2"},
}
CRYSTAL = "#7AE7FF"
GEM = {"or": "#FF4A3A", "legendaire": "#FF8AF2"}

HX, HZ = 0.48, 0.36  # demi-largeur, demi-profondeur de la caisse
TOP = 0.54  # dessus de la caisse = charnière du couvercle
LID_DROP = 0.16  # axe du tonneau sous le bord : couvercle bombé sans être un demi-cylindre
LID_R = math.hypot(HZ + 0.01, LID_DROP)


def inter(a, b):
    """Intersection de deux formes (sangle qui épouse le couvercle)."""
    return sculpt.Shape(lambda P: np.maximum(a(P), b(P)), np.maximum(a.lo, b.lo), np.minimum(a.hi, b.hi))


def barrel(grow=0.0, half_x=HX + 0.01):
    """Couvercle en tonneau : cylindre d'axe X dont l'axe passe sous le bord de la caisse."""
    return cyl((0, TOP - LID_DROP, 0), LID_R + grow, half_x, 0.07, rot=(0, 0, 90))


def build_box(rarity):
    c = PALETTES[rarity]
    legend = rarity == "legendaire"
    parts = []
    # ---------------- caisse (pivot au sol)
    body = Part("body", pivot=(0, 0, 0), res=0.011)
    shell = body.piece(c["body"], tris=1500)
    shell.add(rbox((0, (TOP + 0.04) * 0.5, 0), (HX, (TOP - 0.04) * 0.5, HZ), 0.09))
    # panneaux en creux (face, dos, flancs)
    for z in (HZ, -HZ):
        shell.sub(rbox((0, 0.29, z), (0.15, 0.13, 0.03), 0.03), k=0.012)
    for x in (HX, -HX):
        shell.sub(rbox((x, 0.29, 0), (0.03, 0.13, 0.2), 0.03), k=0.012)
    band = body.piece(c["band"], tris=900)
    for sx in (-1, 1):
        band.add(rbox((sx * 0.29, 0.3, 0), (0.06, 0.25, HZ + 0.024), 0.035))
    band.add(rbox((0, 0.075, 0), (HX + 0.024, 0.055, HZ + 0.024), 0.045))  # socle
    # coins renforcés en haut de la caisse
    for sx in (-1, 1):
        for sz in (-1, 1):
            band.add(rbox((sx * (HX - 0.03), TOP - 0.06, sz * (HZ - 0.03)), (0.065, 0.06, 0.065), 0.035))
    metal = body.piece(c["metal"], tris=500)
    for sx in (-1, 1):
        for sz in (-1, 1):
            metal.add(cyl((sx * (HX - 0.08), 0.022, sz * (HZ - 0.08)), 0.07, 0.025, 0.018))  # pieds
    metal.add(rbox((0, TOP - 0.1, HZ + 0.025), (0.12, 0.1, 0.035), 0.04))  # serrure, moitié basse
    studs = body.piece(c["stud"], tris=400, res=0.007)
    for sx in (-1, 1):
        for y in (0.15, 0.4):
            for sz in (-1, 1):
                studs.add(sphere((sx * 0.29, y, sz * (HZ + 0.03)), 0.02))
    if rarity in ("argent", "or", "legendaire"):
        for sx in (-1, 1):
            for sz in (-1, 1):
                studs.add(sphere((sx * (HX + 0.035), TOP - 0.06, sz * (HZ - 0.03)), 0.024))
    parts.append(body)
    glow = Part("body_glow", pivot=(0, 0, 0), parent="body", res=0.008)
    g = glow.piece(c["glow"], tris=300)
    g.add(rbox((0, TOP - 0.004, 0), (HX - 0.08, 0.012, HZ - 0.08), 0.01))  # nappe de lumière (sous le couvercle)
    g.add(rbox((0, TOP - 0.115, HZ + 0.062), (0.026, 0.04, 0.006), 0.005))  # trou de serrure
    parts.append(glow)
    # ---------------- couvercle (pivot à la charnière arrière)
    lid = Part("lid", pivot=(0, TOP, -HZ), parent="body", res=0.011)
    cut = rbox((0, TOP - 0.3, 0), (0.8, 0.3, 0.8), 0.0)
    lshell = lid.piece(c["body"], tris=1500)
    lshell.add(barrel())
    lshell.add(rbox((0, TOP + 0.04, 0), (HX + 0.01, 0.04, HZ + 0.01), 0.04), k=0.03)
    lshell.sub(cut)
    lband = lid.piece(c["band"], tris=900)
    for sx in (-1, 1):
        lband.add(inter(barrel(0.022, HX + 0.1), rbox((sx * 0.29, TOP + 0.2, 0), (0.06, 0.3, 0.6), 0.03)))
    lband.add(rbox((0, TOP + 0.03, HZ - 0.01), (HX + 0.025, 0.03, 0.035), 0.025))  # bord avant
    lband.sub(cut)
    lmetal = lid.piece(c["metal"], tris=500)
    lmetal.add(rbox((0, TOP + 0.05, HZ + 0.04), (0.13, 0.09, 0.045), 0.045))  # serrure, moitié haute
    lmetal.add(rbox((0, TOP - 0.006, 0), (HX - 0.04, 0.01, HZ - 0.04), 0.008))  # dessous sombre (vu ouvert)
    for sx in (-1, 1):
        lmetal.add(cyl((sx * 0.29, TOP + 0.005, -HZ - 0.03), 0.04, 0.075, 0.015, rot=(0, 0, 90)))  # charnières
    if rarity in GEM:
        lid.piece(GEM[rarity], tris=300, res=0.006).add(ellipsoid((0, TOP + 0.075, HZ + 0.088), (0.05, 0.05, 0.03)))
    parts.append(lid)
    lglow = Part("lid_glow", pivot=(0, TOP, -HZ), parent="lid", res=0.006)
    lg = lglow.piece(c["glow"], tris=400)
    if rarity not in GEM:
        # emblème : losange lumineux sur la serrure
        lg.add(rbox((0, TOP + 0.075, HZ + 0.086), (0.04, 0.04, 0.01), 0.01, rot=(0, 0, 45)))
    else:
        lg.add(torus((0, TOP + 0.075, HZ + 0.086), 0.062, 0.009, rot=(90, 0, 0)))  # sertissure du joyau
    lg.add(rbox((0, TOP - LID_DROP + LID_R + 0.022, 0), (0.07, 0.008, 0.07), 0.006, rot=(0, 45, 0)))  # sommet
    parts.append(lglow)
    if legend:
        cr = Part("crystal", pivot=(0, TOP, -HZ), parent="lid", res=0.006)
        k = cr.piece(CRYSTAL, tris=500)
        y0 = TOP - LID_DROP + LID_R - 0.02
        k.add(capsule((0, y0, -0.04), (0, y0 + 0.3, -0.07), 0.075, 0.008))
        k.add(capsule((0.13, y0 - 0.03, -0.02), (0.22, y0 + 0.16, 0.0), 0.05, 0.006))
        k.add(capsule((-0.13, y0 - 0.03, -0.06), (-0.23, y0 + 0.18, -0.1), 0.055, 0.006))
        parts.append(cr)
    return Character("box_" + rarity, parts)


if __name__ == "__main__":
    out = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "loot"))
    names = sys.argv[1:] or list(PALETTES.keys())
    for r in names:
        build_box(r).export(os.path.join(out, "box_%s.glb" % r))
