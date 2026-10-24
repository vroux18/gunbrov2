"""Bras de chargement du quai (station, jaune de manutention) : socle boulonné, tourelle, bras, avant-bras,
poignet à pince qui tient une caisse HÉLIX FRET. Pièces articulées, animées par hangar_bay.gd (BayArm) :
  arm_base (fixe) > arm_turret (lacet, axe Y) > arm_lower (épaule, axe X) > arm_upper (coude, axe X)
  > arm_head (poignet, garde la pince à la verticale) > arm_crate.
Au repos : bras dressé, avant-bras tendu vers +Z."""
from bay_lib import *

SH = v(0, 0.55, 0)      # épaule
EL = v(0, 1.25, -0.05)  # coude
WR = v(0, 1.25, 0.85)   # poignet


def build():
    parts = []
    base = BPart("arm_base", res=0.016, seed=71.0)
    base.stain((0, 0, 0), 0.6, 0.4, "#141414")
    base.piece(GUN, tris=160, wear=0.7).add(ycyl((0, 0.08, 0), 0.42, 0.08, 0.03))
    base.piece(YELLOW, tris=80, wear=0.9).add(ycyl((0, 0.165, 0), 0.34, 0.012, 0.006))
    bolts = base.piece(STEEL, tris=100, res=0.01, wear=0.0)
    for i in range(8):
        a = i * math.pi / 4
        bolts.add(ycyl((math.cos(a) * 0.36, 0.17, math.sin(a) * 0.36), 0.025, 0.015, 0.006))
    parts.append(base)

    tur = BPart("arm_turret", pivot=(0, 0.17, 0), parent="arm_base", res=0.016, seed=72.0)
    tur.piece(YELLOW, tris=220, wear=0.8).add(ycyl((0, 0.27, 0), 0.3, 0.1, 0.04))
    yk = tur.piece(YELLOW, tris=160, wear=0.8)
    for x in (-0.17, 0.17):
        yk.add(box((x, 0.5, 0), (0.04, 0.2, 0.14), 0.03))
    tur.piece(GUN_D, tris=120, wear=0.4).add(box((0, 0.38, -0.25), (0.18, 0.12, 0.1), 0.03))
    parts.append(tur)

    low = BPart("arm_lower", pivot=SH, parent="arm_turret", res=0.014, seed=73.0)
    low.piece(GUN_D, tris=100, wear=0.3, bare=STEEL_L).add(xcyl(SH, 0.1, 0.13, 0.02))
    lb = low.piece(YELLOW, tris=220, wear=0.9)
    lb.add(capsule(SH, EL, 0.085, 0.07))
    lb.add(box((SH + EL) * 0.5 + v(0, 0, -0.02), (0.06, 0.3, 0.06), 0.03), k=0.04)
    low.piece(STEEL_L, tris=60, wear=0.0).add(capsule(SH + v(0, 0.08, 0.12), EL * 0.6 + SH * 0.4 + v(0, 0, 0.1), 0.02))
    low.piece(BLACK, tris=80, res=0.01, wear=0.0).add(capsule(SH + v(0.1, 0.1, -0.05), EL + v(0.1, -0.1, -0.06), 0.015))
    parts.append(low)

    up = BPart("arm_upper", pivot=EL, parent="arm_lower", res=0.014, seed=74.0)
    up.piece(GUN_D, tris=90, wear=0.3, bare=STEEL_L).add(xcyl(EL, 0.085, 0.11, 0.02))
    ub = up.piece(YELLOW, tris=200, wear=0.9)
    ub.add(capsule(EL, WR, 0.065, 0.05))
    ub.add(box(EL + v(0, 0.04, 0.3), (0.05, 0.05, 0.25), 0.03), k=0.03)
    parts.append(up)

    hd = BPart("arm_head", pivot=WR, parent="arm_upper", res=0.01, seed=75.0)
    hd.piece(GUN_D, tris=120, wear=0.4).add(ycyl(WR + v(0, -0.06, 0), 0.08, 0.06, 0.02))
    cl = hd.piece(GUN, tris=160, wear=0.6)
    cl.add(box(WR + v(0, -0.14, 0), (0.25, 0.03, 0.06), 0.015))
    for x in (-0.23, 0.23):
        cl.add(capsule(WR + v(x, -0.14, 0), WR + v(x * 1.02, -0.42, 0), 0.025))
    parts.append(hd)

    cr = BPart("arm_crate", pivot=WR, parent="arm_head", res=0.02, seed=76.0)
    cr.piece(HXF, tris=100, wear=0.9).add(box(WR + v(0, -0.37, 0), (0.2, 0.2, 0.2), 0.03))
    cr.piece(BLACK, tris=60, res=0.012, wear=0.0).add(box(WR + v(0, -0.37, 0), (0.04, 0.206, 0.206), 0.01))
    parts.append(cr)

    g = BPart("arm_blink", pivot=(0, 0.17, 0), parent="arm_turret", res=0.008)
    g.piece("#FFB060", tris=40).add(sphere((0.0, 0.5, -0.27), 0.04))
    parts.append(g)
    return Prop("bay_arm", parts)
