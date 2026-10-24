"""Relais — mobilier : râtelier d'armes de la Loge, établi de l'atelier (outils, moteur en réparation),
plantes en pot futuristes, projecteur d'hologramme, vaisseau des Passeurs vu par la baie.

Repère de chaque objet : posé sur y = 0, face avant vers +Z, centré en x."""
import math
import sys

import numpy as np

from relais_common import *

LEAF = "#2FC79A"
LEAF_D = "#1E8C78"
STEM = "#2C6E6A"
PLUM = "#7B5CFF"
PLUM_D = "#5A3FD0"
SOIL = "#2A2238"


def _blaster(pc_body, pc_acc, pc_dark, c, s=1.0, rifle=False):
    """Arme couchée le long de X, canon vers +X : coque, crosse, canon, poignée."""
    x, y, z = c
    L = 0.5 * s if rifle else 0.36 * s
    pc_body.add(rbox((x, y, z), (L, 0.09 * s, 0.07 * s), 0.06 * s))
    pc_body.add(ellipsoid((x - L * 0.75, y - 0.02 * s, z), (0.2 * s, 0.1 * s, 0.065 * s)), k=0.04 * s)
    pc_acc.add(rbox((x + L * 0.15, y + 0.08 * s, z), (L * 0.55, 0.035 * s, 0.075 * s), 0.03 * s))
    pc_dark.add(capsule((x + L * 0.8, y, z), (x + L * 1.35, y, z), 0.045 * s))
    pc_dark.add(rbox((x - L * 0.1, y - 0.16 * s, z), (0.05 * s, 0.11 * s, 0.05 * s), 0.035 * s, rot=(0, 0, -12)))


def rack():
    """Râtelier de la Loge : cadre blanc, panneau sombre à rainures, trois armes, casque sur l'étagère."""
    body = part("rack", res=0.015)
    fr = body.piece(HULL, tris=180)
    for sx in (-1, 1):
        fr.add(rbox((sx * 1.15, 1.32, 0), (0.1, 1.32, 0.13), 0.06))
    base = body.piece(STEEL_D, tris=93)
    base.add(rbox((0, 0.13, 0.04), (1.28, 0.13, 0.3), 0.06))
    head = body.piece(STEEL_D, tris=93)
    head.add(rbox((0, 2.6, 0.02), (1.27, 0.13, 0.2), 0.06))
    panel = body.piece(NAVY, tris=93)
    panel.add(rbox((0, 1.38, -0.07), (1.06, 1.1, 0.04), 0.03))
    ribs = body.piece(STEEL_D, tris=93)
    for y in (0.62, 1.14, 1.66, 2.18):
        ribs.add(rbox((0, y, -0.02), (1.04, 0.025, 0.025), 0.012))
    hooks = body.piece(STEEL, tris=144)
    for y in (0.78, 1.32, 1.86):
        for x in (-0.5, 0.45):
            hooks.add(capsule((x, y - 0.06, -0.03), (x, y - 0.06, 0.1), 0.025))
    # armes : fusil (haut), blaster de Jo (milieu), blaster d'élite or (bas)
    wb = body.piece(HULL, tris=324)
    wa = body.piece(ORANGE, tris=144)
    wd = body.piece(STEEL, tris=180)
    _blaster(wb, wa, wd, (-0.08, 1.9, 0.08), 1.0, rifle=True)
    _blaster(wb, wa, wd, (-0.05, 1.36, 0.08), 1.0)
    gold_b = body.piece(GOLD, tris=144)
    gold_a = body.piece(NAVY, tris=72)
    _blaster(gold_b, gold_a, wd, (-0.05, 0.82, 0.08), 1.0)
    # casque de Passeur posé sur le haut
    hel = body.piece(HULL, tris=180)
    hel.add(sphere((0.55, 2.98, 0.04), 0.25))
    hel.sub(rbox((0.55, 2.7, 0.04), (0.4, 0.06, 0.4), 0.01))
    body.piece(ORANGE, tris=60).add(ellipsoid((0.55, 3.2, 0.04), (0.06, 0.07, 0.2)))
    glow = part("rack_glow", res=0.012)
    g = glow.piece(TEAL, tris=108)
    g.add(rbox((0, 2.6, 0.22), (1.05, 0.025, 0.02), 0.01))
    g.add(ellipsoid((0.55, 2.97, 0.25), (0.17, 0.08, 0.06)))  # visière du casque
    cells = glow.piece(TEAL, tris=72)
    for y in (1.9, 1.36):
        cells.add(rbox((-0.05, y + 0.085, 0.155), (0.1, 0.018, 0.01), 0.008))
    cells.add(rbox((-0.05, 0.905, 0.155), (0.1, 0.018, 0.01), 0.008))
    return [body, glow]


def bench():
    """Établi de l'atelier (le mécano travaille derrière, face à la caméra) : plateau clair à chant orange,
    caisson à tiroirs, outils posés, caisse à outils, étau, lampe articulée et moteur ouvert en réparation
    (cœur lumineux qui pulse). Plateau à y = 1,0."""
    body = part("bench", res=0.015)
    top = body.piece(HULL_D, tris=165)
    top.add(rbox((0, 1.0, 0), (1.05, 0.06, 0.46), 0.04))
    body.piece(ORANGE, tris=90).add(rbox((0, 0.955, 0.44), (1.05, 0.03, 0.035), 0.015))
    cab = body.piece(STEEL, tris=225)
    cab.add(rbox((-0.64, 0.47, -0.02), (0.36, 0.47, 0.4), 0.05))
    cab.add(rbox((0.9, 0.47, -0.02), (0.08, 0.47, 0.36), 0.04))
    cab.add(rbox((0.15, 0.14, -0.2), (0.8, 0.04, 0.04), 0.02))
    dr = body.piece(STEEL_D, tris=150)
    for y in (0.72, 0.42, 0.14):
        dr.add(rbox((-0.64, y, 0.38), (0.31, 0.12, 0.03), 0.02))
    hd = body.piece(HULL, tris=120)
    for y in (0.75, 0.45, 0.17):
        hd.add(capsule((-0.74, y, 0.43), (-0.54, y, 0.43), 0.022))
    tools = body.piece(STEEL, tris=270, res=0.01)
    # clé plate et marteau posés à plat sur le plateau
    tools.add(capsule((0.48, 1.075, 0.2), (0.86, 1.075, 0.06), 0.026))
    tools.add(torus((0.9, 1.075, 0.045), 0.055, 0.02))
    tools.add(capsule((-0.25, 1.08, 0.3), (0.2, 1.08, 0.34), 0.024))
    tools.add(rbox((0.24, 1.1, 0.34), (0.05, 0.05, 0.11), 0.02, rot=(0, 10, 0)))
    hand = body.piece(ORANGE, tris=150, res=0.01)
    for z in (-0.25, -0.12):
        tools.add(capsule((0.5, 1.075, z), (0.68, 1.075, z), 0.011))
        hand.add(capsule((0.72, 1.08, z), (0.86, 1.08, z), 0.03))
    # caisse à outils orange
    tb = body.piece(ORANGE, tris=180)
    tb.add(rbox((-0.68, 1.2, -0.15), (0.26, 0.14, 0.16), 0.04))
    body.piece(STEEL_D, tris=90).add(rbox((-0.68, 1.27, -0.15), (0.27, 0.025, 0.17), 0.015))
    body.piece(STEEL_D, tris=90).add(torus((-0.68, 1.37, -0.15), 0.1, 0.02, rot=(90, 0, 0)))
    # lampe articulée (pied, deux bras, abat-jour)
    lamp = body.piece(STEEL_D, tris=195, res=0.01)
    lamp.add(cyl((0.88, 1.08, -0.3), 0.09, 0.02, 0.01))
    lamp.add(capsule((0.88, 1.08, -0.3), (0.8, 1.5, -0.32), 0.018))
    lamp.add(capsule((0.8, 1.5, -0.32), (0.55, 1.62, -0.1), 0.016))
    body.piece(HULL, tris=120).add(ellipsoid((0.5, 1.58, -0.06), (0.11, 0.07, 0.11), rot=(30, 0, 20)))
    # moteur ouvert en réparation, au milieu du plateau
    eng = body.piece(STEEL, tris=240)
    eng.add(cyl((0.05, 1.24, 0.0), 0.24, 0.18, 0.06, rot=(0, 0, 90)))
    eng.sub(rbox((0.05, 1.42, 0.06), (0.15, 0.12, 0.2), 0.03), k=0.02)
    rim = body.piece(HULL, tris=150)
    rim.add(torus((-0.15, 1.24, 0.0), 0.24, 0.035, rot=(0, 0, 90)))
    rim.add(torus((0.25, 1.24, 0.0), 0.2, 0.03, rot=(0, 0, 90)))
    glow = part("bench_glow", res=0.01)
    glow.piece("#FFE8C8", tris=60).add(ellipsoid((0.5, 1.54, -0.05), (0.08, 0.03, 0.08), rot=(30, 0, 20)))
    core = part("bench_pulse_glow", res=0.01)
    core.piece(TEAL, tris=120).add(sphere((0.05, 1.3, 0.03), 0.12))
    return [body, glow, core]


def plant():
    """Plante en pot : pot blanc arrondi à bague lumineuse, feuilles charnues, bulbes lumineux."""
    body = part("plant", res=0.012)
    pot = body.piece(HULL, tris=250)
    pot.add(cyl((0, 0.32, 0), 0.3, 0.3, 0.12))
    pot.add(cyl((0, 0.08, 0), 0.22, 0.08, 0.05), k=0.08)
    pot.sub(cyl((0, 0.62, 0), 0.25, 0.04, 0.02), k=0.02)
    body.piece(SOIL, tris=60).add(cyl((0, 0.57, 0), 0.25, 0.02, 0.01))
    body.piece(STEEL_D, tris=100).add(ring((0, 0.4, 0), 0.305, 0.02, 0.04, 0.012))
    leaves = body.piece(LEAF, tris=450)
    rng = np.random.default_rng(5)
    tips = []
    for k in range(7):
        a = 2 * math.pi * k / 7 + rng.random() * 0.4
        tilt = 35 + rng.random() * 25
        L = 0.45 + rng.random() * 0.25
        d = np.array([math.cos(a) * math.sin(math.radians(tilt)), math.cos(math.radians(tilt)), math.sin(a) * math.sin(math.radians(tilt))])
        c = np.array([0, 0.58, 0]) + d * L * 0.55
        # feuille : capsule effilée et ventrue
        leaves.add(capsule((0, 0.58, 0), (c + d * L * 0.45).tolist(), 0.03, 0.075), k=0.04)
        tips.append((c + d * L * 0.5 + np.array([0, 0.05, 0])).tolist())
    stem = body.piece(STEM, tris=100)
    stem.add(capsule((0, 0.58, 0), (0.05, 1.35, 0.02), 0.03, 0.02))
    glow = part("plant_glow", res=0.01)
    bulbs = glow.piece(ORANGE, tris=150)
    for t in tips[::2]:
        bulbs.add(sphere(t, 0.045))
    glow.piece(TEAL, tris=60).add(sphere((0.05, 1.4, 0.02), 0.08))
    band = part("plant_pot_glow", res=0.01)
    band.piece(TEAL, tris=100).add(ring((0, 0.25, 0), 0.31, 0.012, 0.018, 0.008))
    return [body, glow, band]


def plant_tall():
    """Plante haute : tiges en boules empilées violettes, pointes lumineuses, pot bas."""
    body = part("plant_tall", res=0.012)
    pot = body.piece(HULL_D, tris=240)
    pot.add(cyl((0, 0.22, 0), 0.34, 0.22, 0.12))
    pot.sub(cyl((0, 0.44, 0), 0.29, 0.04, 0.02), k=0.02)
    body.piece(SOIL, tris=72).add(cyl((0, 0.4, 0), 0.29, 0.02, 0.01))
    stalks = body.piece(PLUM, tris=600)
    tips = []
    for k, (dx, dz, n) in enumerate(((0, 0, 5), (0.15, 0.08, 4), (-0.14, 0.06, 3), (0.02, -0.15, 4))):
        p = np.array([dx, 0.45, dz])
        for i in range(n):
            r = 0.1 - i * 0.012
            q = p + np.array([dx * 0.4, r * 1.7, dz * 0.4])
            stalks.add(ellipsoid(q.tolist(), (r, r * 1.15, r)), k=0.035)
            p = q
        tips.append((p + np.array([0, 0.12, 0])).tolist())
    glow = part("plant_tall_glow", res=0.01)
    g = glow.piece(TEAL, tris=120)
    for t in tips:
        g.add(sphere(t, 0.05))
    return [body, glow]


def projector():
    """Socle de projecteur d'hologramme : disque bas, lentille lumineuse."""
    body = part("projector", res=0.01)
    b = body.piece(STEEL_D, tris=260)
    b.add(cyl((0, 0.08, 0), 0.42, 0.08, 0.04))
    b.add(cyl((0, 0.2, 0), 0.26, 0.06, 0.03), k=0.04)
    body.piece(HULL, tris=200).add(ring((0, 0.17, 0), 0.4, 0.03, 0.02, 0.01))
    glow = part("projector_glow", res=0.01)
    glow.piece(TEAL, tris=160).add(cyl((0, 0.27, 0), 0.16, 0.02, 0.01))
    glow.piece(TEAL, tris=200).add(ring((0, 0.16, 0), 0.43, 0.012, 0.012, 0.006))
    return [body, glow]


def ship():
    """Le Passeur, vaisseau de Jo : navette ronde blanche à liseré orange, verrière turquoise, deux nacelles.
    Long de ~11 le long de X, nez vers +X."""
    body = part("ship", res=0.05, ao=3.0)
    hull = body.piece(HULL, tris=540)
    hull.add(ellipsoid((0, 0, 0), (5.2, 1.5, 1.9)))
    hull.add(ellipsoid((-1.2, 0.6, 0), (3.2, 1.3, 1.6)), k=0.6)
    belly = body.piece(HULL_D, tris=240)
    belly.add(ellipsoid((0.2, -0.55, 0), (4.6, 1.0, 1.7)))
    belly.sub(rbox((0, 0.4, 0), (6, 1.0, 3), 0.05))
    stripe = body.piece(ORANGE, tris=240)
    stripe.add(ellipsoid((0.3, 0.05, 0), (5.0, 0.16, 1.93)))
    for sz in (-1, 1):
        nac = body.piece(STEEL, tris=240)
        nac.add(capsule((-4.2, -0.2, sz * 2.3), (-0.4, -0.1, sz * 2.3), 0.6, 0.45))
        nac.add(ellipsoid((-1.8, -0.1, sz * 1.5), (1.6, 0.25, 0.7)), k=0.3)
        body.piece(STEEL_D, tris=120).add(cyl((-4.5, -0.2, sz * 2.3), 0.52, 0.2, 0.08, rot=(0, 0, 90)))
    fin = body.piece(HULL, tris=180)
    fin.add(ellipsoid((-3.6, 1.8, 0), (1.2, 0.9, 0.15), rot=(0, 0, -25)))
    body.piece(ORANGE, tris=96).add(ellipsoid((-3.9, 2.2, 0), (0.6, 0.35, 0.18), rot=(0, 0, -25)))
    glow = part("ship_glow", res=0.04)
    glow.piece(TEAL, tris=180).add(ellipsoid((3.2, 0.75, 0), (1.5, 0.6, 1.15)))
    eng = glow.piece(ORANGE, tris=120)
    for sz in (-1, 1):
        eng.add(cyl((-4.72, -0.2, sz * 2.3), 0.4, 0.05, 0.02, rot=(0, 0, 90)))
    nav = glow.piece(TEAL, tris=60)
    nav.add(sphere((1.0, 0.0, 2.0), 0.12))
    return [body, glow]


if __name__ == "__main__":
    run({"rack": rack, "bench": bench, "plant": plant, "plant_tall": plant_tall, "projector": projector, "ship": ship}, sys.argv)
