"""Relais — deux robots de la base, sculptés comme les personnages et animés en code (scripts/decor/relais.gd).

Mécano (« mecano ») : petit robot d'atelier sur roule-boule, tête-écran à grands yeux turquoise et joues
roses, casque de chantier jaune, clé dans la main droite, chalumeau dans la gauche. Haut d'environ 1,75
(Jo en fait 2,5). Regarde vers +Z ; sa droite est en -X.
Drone d'entretien (« drone_relais ») : boule blanche à gros œil turquoise, rotor à trois pales au-dessus,
balai-scanner dessous. Centre du corps à l'origine. Regarde vers +Z."""
import math
import sys

import numpy as np

from relais_common import *

HAT = "#FFC94A"
BLUSH = "#F49088"
SCREEN = "#141A30"


def mecano():
    parts = []
    base = part("base", pivot=(0, 0, 0), res=0.01)
    base.piece(RUBBER, tris=150).add(sphere((0, 0.19, 0), 0.19))
    sk = base.piece(STEEL_D, tris=150)
    sk.add(cyl((0, 0.33, 0), 0.24, 0.06, 0.04))
    base.piece(ORANGE, tris=80).add(ring((0, 0.33, 0), 0.245, 0.02, 0.025, 0.01))
    parts.append(base)

    body = part("body", pivot=(0, 0.4, 0), parent="base", res=0.01)
    hull = body.piece(HULL, tris=450)
    hull.add(ellipsoid((0, 0.72, 0), (0.32, 0.33, 0.27)))
    hull.add(cyl((0, 0.45, 0), 0.2, 0.06, 0.04), k=0.06)
    body.piece(ORANGE, tris=150).add(rbox((0, 0.74, 0.22), (0.16, 0.12, 0.08), 0.06))
    body.piece(STEEL_D, tris=130).add(ring((0, 0.54, 0), 0.29, 0.035, 0.04, 0.02))
    pouch = body.piece(STEEL, tris=100)
    for sx in (-1, 1):
        pouch.add(rbox((sx * 0.2, 0.5, 0.2), (0.06, 0.06, 0.05), 0.025))
    body.piece(STEEL_D, tris=80).add(cyl((0, 1.03, 0), 0.1, 0.04, 0.02))
    for sx in (-1, 1):
        body.piece(STEEL_D, tris=80).add(sphere((sx * 0.33, 0.86, 0), 0.08))
    parts.append(body)

    head = part("head", pivot=(0, 1.05, 0), parent="body", res=0.008)
    hh = head.piece(HULL, tris=450)
    hh.add(rbox((0, 1.3, 0), (0.33, 0.25, 0.26), 0.17))
    head.piece(SCREEN, tris=250).add(rbox((0, 1.29, 0.19), (0.25, 0.17, 0.09), 0.1))
    hat = head.piece(HAT, tris=300)
    hat.add(ellipsoid((0, 1.5, -0.01), (0.29, 0.16, 0.27)))
    hat.sub(rbox((0, 1.38, 0), (0.5, 0.06, 0.5), 0.01))
    hat.add(ellipsoid((0, 1.455, 0.16), (0.27, 0.025, 0.2)), k=0.02)
    head.piece(ORANGE, tris=60).add(ellipsoid((0, 1.62, 0.0), (0.04, 0.035, 0.22)))
    cheeks = head.piece(BLUSH, tris=60, res=0.005)
    for sx in (-1, 1):
        cheeks.add(ellipsoid((sx * 0.175, 1.2, 0.27), (0.04, 0.022, 0.012)))
    ear = head.piece(STEEL_D, tris=100)
    for sx in (-1, 1):
        ear.add(cyl((sx * 0.33, 1.3, 0), 0.07, 0.03, 0.015, rot=(0, 0, 90)))
    parts.append(head)
    eyes = part("eyes_glow", pivot=(0, 1.3, 0.27), parent="head", res=0.005)
    e = eyes.piece(TEAL, tris=120)
    for sx in (-1, 1):
        e.add(ellipsoid((sx * 0.1, 1.31, 0.275), (0.048, 0.07, 0.02)))
    eyes.piece(WHITE, tris=60).add(sphere((-0.085, 1.34, 0.29), 0.014)).add(sphere((0.115, 1.34, 0.29), 0.014))
    parts.append(eyes)

    # bras : épaule, bras, avant-bras tendu vers l'avant, main
    for side, sx in (("r", -1.0), ("l", 1.0)):
        sh = np.array([sx * 0.36, 0.86, 0.0])
        el = np.array([sx * 0.44, 0.66, 0.1])
        wr = np.array([sx * 0.3, 0.62, 0.36])
        arm = part("arm_" + side, pivot=sh.tolist(), parent="body", res=0.008)
        a = arm.piece(STEEL, tris=150)
        a.add(capsule(sh.tolist(), el.tolist(), 0.055, 0.05))
        a.add(capsule(el.tolist(), wr.tolist(), 0.05, 0.045), k=0.02)
        arm.piece(HULL, tris=100).add(ellipsoid(el.tolist(), (0.07, 0.07, 0.07)))
        hand = arm.piece(HULL, tris=120)
        hand.add(sphere((wr + [0, 0, 0.04]).tolist(), 0.075))
        if side == "r":
            # clé à molette tenue verticalement
            w = arm.piece(HULL_D, tris=150)
            w.add(capsule((wr + [0, -0.12, 0.06]).tolist(), (wr + [0, 0.2, 0.06]).tolist(), 0.022))
            w.add(torus((wr + [0, 0.25, 0.06]).tolist(), 0.055, 0.022, rot=(0, 90, 90)))
            w.sub(rbox((wr + [0, 0.31, 0.06]).tolist(), (0.03, 0.05, 0.1), 0.01))
        else:
            # chalumeau
            t = arm.piece(STEEL_D, tris=130)
            t.add(capsule((wr + [0, -0.03, 0.02]).tolist(), (wr + [-0.02, 0.0, 0.25]).tolist(), 0.03, 0.022))
            arm.piece(ORANGE, tris=60).add(cyl((wr + [0, -0.03, 0.06]).tolist(), 0.04, 0.035, 0.01, rot=(90, 0, 0)))
        parts.append(arm)
    torch = part("torch_glow", pivot=(0.28, 0.62, 0.65), parent="arm_l", res=0.005)
    torch.piece("#9FF8FF", tris=60).add(sphere((0.28, 0.62, 0.63), 0.025))
    parts.append(torch)
    return parts


def drone_relais():
    parts = []
    body = part("body", pivot=(0, 0, 0), res=0.006)
    top = body.piece(HULL, tris=385)
    top.add(sphere((0, 0, 0), 0.22))
    top.sub(rbox((0, -0.2, 0), (0.3, 0.17, 0.3), 0.01))
    low = body.piece(ORANGE, tris=220)
    low.add(sphere((0, -0.005, 0), 0.215))
    low.sub(rbox((0, 0.2, 0), (0.3, 0.2, 0.3), 0.01))
    body.piece(STEEL_D, tris=165).add(ring((0, -0.005, 0), 0.215, 0.025, 0.022, 0.01))
    sock = body.piece(STEEL_D, tris=165)
    sock.add(torus((0, 0.03, 0.19), 0.085, 0.022, rot=(90, 0, 0)))
    side = body.piece(STEEL, tris=110)
    for sx in (-1, 1):
        side.add(cyl((sx * 0.22, 0.0, 0), 0.06, 0.03, 0.015, rot=(0, 0, 90)))
    body.piece(STEEL_D, tris=66).add(capsule((0, 0.2, 0), (0, 0.3, 0), 0.025))
    parts.append(body)
    eye = part("eye_glow", pivot=(0, 0.03, 0.2), parent="body", res=0.004)
    eye.piece(TEAL, tris=110).add(ellipsoid((0, 0.03, 0.2), (0.07, 0.07, 0.025)))
    eye.piece(WHITE, tris=60).add(sphere((-0.02, 0.06, 0.22), 0.014))
    parts.append(eye)
    rotor = part("rotor", pivot=(0, 0.31, 0), parent="body", res=0.006)
    rotor.piece(HULL_D, tris=66).add(cyl((0, 0.31, 0), 0.04, 0.02, 0.01))
    bl = rotor.piece(STEEL, tris=198)
    for k in range(3):
        a = 2 * math.pi * k / 3
        bl.add(ellipsoid((math.cos(a) * 0.15, 0.315, math.sin(a) * 0.15), (0.13, 0.008, 0.035), rot=(0, -math.degrees(a), 8)))
    parts.append(rotor)
    arm = part("brush", pivot=(0, -0.2, 0), parent="body", res=0.006)
    arm.piece(STEEL_D, tris=88).add(capsule((0, -0.2, 0), (0, -0.33, 0.04), 0.022))
    arm.piece(HULL, tris=88).add(cyl((0, -0.35, 0.04), 0.07, 0.02, 0.01))
    parts.append(arm)
    scan = part("brush_glow", pivot=(0, -0.37, 0.04), parent="brush", res=0.005)
    scan.piece(TEAL, tris=66).add(ring((0, -0.372, 0.04), 0.055, 0.012, 0.006, 0.004))
    parts.append(scan)
    return parts


if __name__ == "__main__":
    run({"mecano": mecano, "drone_relais": drone_relais}, sys.argv)
