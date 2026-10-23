"""Équipement visible de Jo (loot). Un GLB par objet : assets/chars3d/gear_<id>.glb.
Chaque part s'appelle « <cible>__<id> » : le rig la range dans la part cible de Jo (head, torso, arm_l,
leg_r, leg_l, gun) avec le même pivot, donc les coordonnées ci-dessous sont celles du modèle de Jo.
Les parts « *_glow » sont blanches : le jeu les teinte à la couleur de rareté."""
from sculpt import *

PIV = {"torso": (0, 0.36, 0), "head": (0, 0.62, 0), "arm_l": (0.19, 0.57, 0), "arm_r": (-0.19, 0.57, 0),
       "leg_r": (-0.08, 0.34, 0), "leg_l": (0.08, 0.34, 0), "gun": (-0.215, 0.33, 0.014)}
W = "#FFFFFF"
NAVY = "#1E2A4A"
STEEL = "#8A94A8"
LIGHT = "#E8ECF2"
ORANGE = "#FF7A2F"
GUNC = "#3A4258"
GUNL = "#5A6478"
DARK = "#262C40"


def part(target, gid, glow=False, res=0.005):
    return Part(target + "__" + gid + ("_glow" if glow else ""), pivot=PIV[target], res=res)


def visiere():
    # visée de pilote : bras depuis l'oreille droite, lentille devant l'œil droit
    a = part("head", "visiere")
    a.piece(DARK, tris=300).add(capsule((-0.262, 0.84, 0.02), (-0.2, 0.86, 0.17), 0.014))
    a.piece(STEEL, tris=300).add(cyl((-0.1, 0.845, 0.215), 0.06, 0.016, 0.008, rot=(90, 0, 0)))
    g = part("head", "visiere", glow=True, res=0.004)
    g.piece(W, tris=200).add(cyl((-0.1, 0.845, 0.226), 0.046, 0.006, 0.003, rot=(90, 0, 0)))
    return [a, g]


def casque_garde():
    a = part("head", "casque_garde", res=0.006)
    dome = a.piece(LIGHT, tris=1500)
    dome.add(ellipsoid((0, 0.905, -0.03), (0.258, 0.222, 0.25)))
    dome.sub(rbox((0, 0.765, 0.21), (0.19, 0.13, 0.14), 0.07), k=0.02)
    dome.sub(ellipsoid((0, 0.88, -0.03), (0.236, 0.2, 0.228)))
    a.piece(NAVY, tris=300).add(rbox((0, 1.11, -0.02), (0.035, 0.04, 0.17), 0.03))
    g = part("head", "casque_garde", glow=True)
    g.piece(W, tris=300).add(torus((0, 0.905, 0.16), 0.13, 0.012, rot=(90, 0, 0)))
    return [a, g]


def plastron():
    a = part("torso", "plastron")
    a.piece(STEEL, tris=600).add(rbox((0, 0.495, 0.112), (0.13, 0.085, 0.036), 0.03))
    a.piece(DARK, tris=200).add(rbox((0, 0.44, 0.146), (0.05, 0.02, 0.008), 0.008))
    g = part("torso", "plastron", glow=True)
    gg = g.piece(W, tris=200)
    gg.add(rbox((0, 0.548, 0.146), (0.11, 0.008, 0.006), 0.004))
    return [a, g]


def veste():
    a = part("torso", "veste")
    a.piece(ORANGE, tris=600).add(torus((0, 0.585, 0.0), 0.13, 0.035))
    a.piece(ORANGE, tris=300).add(rbox((0.1, 0.47, 0.115), (0.025, 0.09, 0.03), 0.02))
    g = part("torso", "veste", glow=True)
    g.piece(W, tris=200).add(rbox((0.1, 0.47, 0.146), (0.008, 0.07, 0.004), 0.003))
    return [a, g]


def legs(gid, col, y_band):
    out = []
    for side, sx in (("r", -1.0), ("l", 1.0)):
        a = part("leg_" + side, gid)
        g = part("leg_" + side, gid, glow=True)
        if gid == "bottes":
            a.piece(col, tris=600).add(rbox((sx * 0.085, 0.075, 0.03), (0.078, 0.07, 0.11), 0.05))
            g.piece(W, tris=200).add(cyl((sx * 0.085, y_band, 0.03), 0.082, 0.012, 0.005))
        else:
            a.piece(col, tris=500).add(ellipsoid((sx * 0.085, 0.2, 0.045), (0.055, 0.075, 0.035)))
            g.piece(W, tris=150).add(sphere((sx * 0.085, 0.215, 0.08), 0.014))
        out += [a, g]
    return out


def back(gid):
    a = part("torso", gid)
    g = part("torso", gid, glow=True)
    if gid == "pile":
        a.piece(DARK, tris=400).add(cyl((0, 0.5, -0.225), 0.05, 0.11, 0.02))
        g.piece(W, tris=200).add(cyl((0, 0.5, -0.226), 0.053, 0.05, 0.01))
    else:
        a.piece(DARK, tris=400).add(cyl((0, 0.5, -0.215), 0.03, 0.03, 0.01, rot=(90, 0, 0)))
        g.piece(W, tris=400).add(torus((0, 0.5, -0.235), 0.075, 0.016, rot=(90, 0, 0)))
    return [a, g]


def shoulder(gid):
    a = part("arm_l", gid)
    g = part("arm_l", gid, glow=True)
    if gid == "module_canon":
        a.piece(GUNC, tris=500).add(rbox((0.235, 0.63, 0.02), (0.04, 0.035, 0.07), 0.025))
        a.piece(GUNL, tris=300).add(cyl((0.235, 0.63, 0.1), 0.02, 0.04, 0.006, rot=(90, 0, 0)))
        g.piece(W, tris=100).add(cyl((0.235, 0.63, 0.14), 0.014, 0.006, 0.002, rot=(90, 0, 0)))
    else:
        a.piece(GUNC, tris=300).add(cyl((0.25, 0.6, 0.0), 0.035, 0.03, 0.01, rot=(0, 0, 90)))
        g.piece(W, tris=200).add(sphere((0.275, 0.6, 0.0), 0.024))
    return [a, g]


def gun(gid):
    # même convention que le blaster de Jo : canon vers -Y au repos, poignée dans le gant
    a = part("gun", gid)
    g = part("gun", gid, glow=True, res=0.004)
    if gid == "blaster_garde":
        a.piece(GUNC, tris=600).add(rbox((-0.215, 0.26, 0.064), (0.04, 0.11, 0.055), 0.02))
        a.piece("#9AA4B6", tris=300).add(rbox((-0.215, 0.29, 0.122), (0.03, 0.05, 0.014), 0.01))
        a.piece(GUNL, tris=300).add(cyl((-0.215, 0.14, 0.074), 0.026, 0.05, 0.008))
        g.piece(W, tris=150).add(cyl((-0.215, 0.087, 0.074), 0.019, 0.008, 0.003))
        g.piece(W, tris=100).add(rbox((-0.257, 0.25, 0.064), (0.004, 0.06, 0.02), 0.003))
    else:
        a.piece(GUNC, tris=700).add(rbox((-0.215, 0.24, 0.064), (0.034, 0.14, 0.046), 0.022))
        a.piece(GUNL, tris=300).add(cyl((-0.215, 0.085, 0.07), 0.022, 0.04, 0.008))
        a.piece(ORANGE, tris=200).add(rbox((-0.215, 0.33, 0.04), (0.024, 0.03, 0.04), 0.015))
        gg = g.piece(W, tris=400)
        for y in (0.16, 0.21, 0.26):
            gg.add(torus((-0.215, y, 0.064), 0.05, 0.008))
        gg.add(cyl((-0.215, 0.042, 0.07), 0.016, 0.008, 0.003))
    return [a, g]


def build():
    items = {
        "visiere": visiere(), "casque_garde": casque_garde(), "plastron": plastron(), "veste": veste(),
        "bottes": legs("bottes", NAVY, 0.1), "jambieres": legs("jambieres", LIGHT, 0.0),
        "pile": back("pile"), "aimant": back("aimant"),
        "module_canon": shoulder("module_canon"), "cellule": shoulder("cellule"),
        "blaster_garde": gun("blaster_garde"), "fusil_impulsion": gun("fusil_impulsion"),
    }
    return [Character("gear_" + k, v) for k, v in items.items()]
