"""Relais — coque de la base : travée de la grande baie (pilier à bande lumineuse, allège à rebord,
linteau, traverse) répétée en arc derrière le pont, et portail des Passeurs (cadre fixe à dix socles
d'éclats en couronne, anneau intérieur tournant, cristal d'éclat).

Repère d'une travée : x le long du mur (largeur BAY, pilier à x = -BAY/2), y vers le haut depuis le sol,
+z vers l'intérieur de la base. Portail : centre à l'origine, dans le plan XY, face vers +Z."""
import math
import sys

import numpy as np
import trimesh

from relais_common import *

BAY = 3.0
H = 7.6


def bay():
    body = part("bay", res=0.025)
    hx = -BAY * 0.5
    pil = body.piece("#A9B2CC", tris=140)
    pil.add(rbox((hx, H * 0.5, 0.0), (0.3, H * 0.5, 0.36), 0.14))
    pil.sub(rbox((hx, 3.3, 0.38), (0.09, 2.3, 0.06), 0.03), k=0.02)  # gorge de la bande lumineuse
    body.piece(STEEL_D, tris=78).add(rbox((hx, 0.32, 0.06), (0.4, 0.32, 0.44), 0.08))
    body.piece(ORANGE, tris=60).add(rbox((hx, 0.72, 0.06), (0.31, 0.04, 0.37), 0.02))
    low = body.piece(STEEL_D, tris=109)
    low.add(rbox((0, 0.62, -0.05), (BAY * 0.5, 0.62, 0.26), 0.06))
    body.piece(HULL_D, tris=78).add(rbox((0, 1.25, 0.06), (BAY * 0.5, 0.06, 0.38), 0.04))
    # panneaux d'allège en relief
    pan = body.piece(STEEL, tris=62)
    pan.add(rbox((0, 0.62, 0.2), (BAY * 0.5 - 0.5, 0.38, 0.03), 0.03))
    top = body.piece(STEEL_D, tris=93)
    top.add(rbox((0, H - 0.55, -0.05), (BAY * 0.5, 0.55, 0.32), 0.08))
    body.piece(HULL, tris=62).add(rbox((0, H - 1.12, 0.08), (BAY * 0.5, 0.07, 0.34), 0.04))
    # traverse fine de la vitre
    body.piece(STEEL, tris=60).add(capsule((-BAY * 0.5 + 0.2, 4.7, -0.12), (BAY * 0.5 - 0.2, 4.7, -0.12), 0.055))
    glow = part("bay_glow", res=0.02)
    glow.piece(TEAL, tris=60).add(rbox((hx, 3.3, 0.35), (0.05, 2.25, 0.03), 0.02))
    warm = part("bay_warm_glow", res=0.02)
    warm.piece(ORANGE, tris=60).add(rbox((0, 0.95, 0.215), (BAY * 0.5 - 0.3, 0.025, 0.02), 0.012))
    return [body, glow, warm]


# ------------------------------------------------------------------ portail
R_FRAME = 2.32
SOCKETS = [math.radians(a) for a in np.linspace(162, 18, 10)]  # angles dans le plan XY, depuis +X
R_SOCK = 2.66


def _xy(a, r, z=0.0):
    return (math.cos(a) * r, math.sin(a) * r, z)


def portal():
    """Cadre fixe : anneau épais en deux tons, plaques, embase posée sur le pont, dix socles en couronne."""
    fr = part("portal", res=0.02)
    ring_w = fr.piece(HULL, tris=935)
    ring_w.add(torus((0, 0, 0), R_FRAME, 0.2, rot=(90, 0, 0)))
    ring_w.add(torus((0, 0, -0.08), R_FRAME + 0.04, 0.2, rot=(90, 0, 0)), k=0.05)
    lip = fr.piece(STEEL_D, tris=510)
    lip.add(torus((0, 0, 0.06), 2.07, 0.085, rot=(90, 0, 0)))
    # embase : deux jambes et un sabot sur le pont (le bas du cadre est à y = -2,6 + 0,1)
    foot = fr.piece(STEEL_D, tris=510)
    for s in (-1, 1):
        a = math.radians(-90 + s * 38)
        p = np.array(_xy(a, R_FRAME))
        foot.add(capsule(p.tolist(), (p[0] * 1.18 + s * 0.15, -2.55, -0.05), 0.2, 0.26), k=0.08)
        foot.add(rbox((p[0] * 1.18 + s * 0.15, -2.5, -0.05), (0.42, 0.1, 0.5), 0.06), k=0.1)
    foot.add(rbox((0, -2.5, -0.1), (0.9, 0.1, 0.42), 0.06), k=0.05)
    acc = fr.piece(ORANGE, tris=212)
    for s in (-1, 1):
        a = math.radians(-90 + s * 38)
        p = np.array(_xy(a, R_FRAME))
        acc.add(cyl(((p[0] * 1.18 + s * 0.15), -2.36, -0.05), 0.27, 0.035, 0.015))
    # socles des éclats : console radiale et coupelle
    sk = fr.piece(STEEL_D, tris=850, res=0.015)
    cup = fr.piece(HULL, tris=680, res=0.015)
    for a in SOCKETS:
        d = math.degrees(a)
        sk.add(rbox(_xy(a, R_FRAME + 0.24, 0.02), (0.16, 0.1, 0.15), 0.05, rot=(0, 0, d - 90)), k=0.03)
        cup.add(torus(_xy(a, R_SOCK, 0.02), 0.17, 0.05, rot=(0, 0, d - 90)))
    glow = part("portal_glow", res=0.015)
    g = glow.piece(TEAL, tris=382)
    for a in SOCKETS:
        g.add(torus(_xy(a, R_FRAME + 0.24, 0.155), 0.05, 0.014, rot=(90, 0, 0)))
    for s in (-1, 1):
        a = math.radians(-90 + s * 38)
        p = np.array(_xy(a, R_FRAME))
        g.add(rbox((p[0] * 1.18 + s * 0.15, -2.4, 0.46), (0.3, 0.025, 0.02), 0.01))
    return [fr, glow]


def portal_ring():
    """Anneau intérieur qui tourne : bague sombre à diodes, liseré lumineux."""
    r = part("ring", res=0.012)
    r.piece(NAVY, tris=700).add(torus((0, 0, 0.02), 2.0, 0.07, rot=(90, 0, 0)))
    studs = r.piece(HULL_D, tris=450)
    for k in range(12):
        a = 2 * math.pi * k / 12
        studs.add(rbox(_xy(a, 2.02, 0.07), (0.07, 0.13, 0.05), 0.025, rot=(0, 0, math.degrees(a) - 90)))
    gl = part("ring_glow", res=0.01)
    gl.piece(TEAL, tris=450).add(torus((0, 0, 0.05), 1.93, 0.03, rot=(90, 0, 0)))
    leds = gl.piece(ORANGE, tris=150)
    for k in range(0, 12, 3):
        a = 2 * math.pi * k / 12
        leds.add(ellipsoid(_xy(a, 2.02, 0.125), (0.03, 0.06, 0.02), rot=(0, 0, math.degrees(a) - 90)))
    return [r, gl]


def gem():
    """Éclat du Cœur : cristal facetté (blanc, teinté par le matériau), long de 0,5, axe Y, base à y = 0."""
    import os
    tm = crystal((0, 0.36, 0), 0.17, 0.4, sides=6, seed=4)
    # facettes de luminosités différentes : le cristal reste lisible même rendu sans ombrage (lueur)
    rng = np.random.default_rng(9)
    n = tm.face_normals
    lum = 0.62 + 0.38 * np.clip(0.5 + 0.5 * (n @ np.array([0.3, 0.8, 0.5])), 0, 1) + rng.uniform(-0.05, 0.05, len(n))
    fc = (np.clip(np.stack([lum, lum, lum, np.ones_like(lum)], axis=1), 0, 1) * 255).astype(np.uint8)
    tm.visual = trimesh.visual.ColorVisuals(tm, face_colors=fc)
    sc = trimesh.Scene()
    sc.add_geometry(tm, node_name="gem", geom_name="gem_mesh")
    path = os.path.join(OUT, "gem.glb")
    sc.export(path)
    print("gem :", len(tm.faces), "triangles ->", path)
    return None


if __name__ == "__main__":
    names = sys.argv[1:] or ["bay", "portal", "portal_ring", "gem"]
    for n in names:
        if n == "gem":
            gem()
        else:
            export(n, {"bay": bay, "portal": portal, "portal_ring": portal_ring}[n]())
