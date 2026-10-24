#!/usr/bin/env python3
"""Cité Néon — la ville en contrebas : immeubles voisins plus bas que notre toit (fenêtres et enseignes en
shader), toits encombrés, avenues lumineuses au fond (circulation animée), tout noyé de brume rose.

Écrit assets/decor/neon/shell/city.glb (un maillage, shaders/neon_city.gdshader).
Sommets : COLOR.r graine, COLOR.g teinte (0..1 dans la palette), COLOR.b réservé, COLOR.a classe
(0 façade à fenêtres, 1/3 toit, 2/3 avenue, 1 enseigne lumineuse) ; UV en mètres (façade : u le long du mur,
v = hauteur ; avenue : u le long de la voie, v en travers 0..1) ; UV2.x animation (0,5 clignote), UV2.y phase.
Lancement : python3 tools/decor/neon_shell_city.py
"""
import math
import os

import numpy as np

from neon_shell_common import H, MB, OUT, W, ZN, write_glb

R = np.random.default_rng(5150)
STREET_Y = -48.0
WALLC, ROOF, ROAD, SIGN = 0.0, 1 / 3, 2 / 3, 1.0
# avenues : (axe, position, de, à, largeur)
ROADS = [("z", -17.0, -60.0, 80.0, 10.0), ("z", W + 17.0, -60.0, 80.0, 10.0), ("x", H + 15.0, -70.0, W + 70.0, 10.0),
         ("x", -34.0, -70.0, W + 70.0, 10.0), ("z", -52.0, -60.0, 80.0, 9.0), ("z", W + 52.0, -60.0, 80.0, 9.0)]
# emprises interdites : notre tour, la tour voisine
KEEP_OUT = [(-0.5, ZN - 0.5, W + 0.5, H + 0.5), (-11.5, -29.0, W + 11.5, 0.5)]


def on_road(x0, z0, x1, z1):
    for (ax, p, a, b, w) in ROADS:
        if ax == "z":
            if x1 > p - w * 0.5 - 1.5 and x0 < p + w * 0.5 + 1.5 and z1 > a and z0 < b:
                return True
        else:
            if z1 > p - w * 0.5 - 1.5 and z0 < p + w * 0.5 + 1.5 and x1 > a and x0 < b:
                return True
    return False


def blocked(x0, z0, x1, z1, placed):
    for (a, b, c, d) in KEEP_OUT + placed:
        if x1 > a and x0 < c and z1 > b and z0 < d:
            return True
    return False


def wall(mb, p0, p1, y0, y1, n, seed, tint):
    """Mur vertical de p0 à p1 (xz), uv en mètres."""
    p0, p1 = np.array(p0, float), np.array(p1, float)
    L = np.linalg.norm(p1 - p0)
    c = (p0 + p1) * 0.5
    r = (p1 - p0) / L
    mb.quad((c[0], (y0 + y1) * 0.5, c[1]), (r[0], 0, r[1]), (0, 1, 0), L * 0.5, (y1 - y0) * 0.5,
            (0.0, y1, L, y0), (seed, tint, 0.0), WALLC, normal=(n[0], 0, n[1]))


def building(mb, x0, z0, x1, z1, top, seed, tint):
    y0 = STREET_Y
    wall(mb, (x0, z1), (x1, z1), y0, top, (0, 1), seed, tint)
    wall(mb, (x1, z0), (x0, z0), y0, top, (0, -1), seed, tint)
    wall(mb, (x0, z0), (x0, z1), y0, top, (-1, 0), seed, tint)
    wall(mb, (x1, z1), (x1, z0), y0, top, (1, 0), seed, tint)
    # toit, acrotère
    mb.quad(((x0 + x1) * 0.5, top, (z0 + z1) * 0.5), (1, 0, 0), (0, 0, -1), (x1 - x0) * 0.5, (z1 - z0) * 0.5,
            (x0, z0, x1, z1), (seed, tint, 0.0), ROOF, normal=(0, 1, 0))
    # édicules du toit : climatiseurs, réservoir d'eau, cage d'escalier
    n = int(R.integers(1, 5))
    for k in range(n):
        w, d, h = R.uniform(1.0, 3.0), R.uniform(1.0, 3.0), R.uniform(0.6, 2.4)
        if x1 - x0 < w + 1 or z1 - z0 < d + 1:
            continue
        cx = R.uniform(x0 + w * 0.5 + 0.5, x1 - w * 0.5 - 0.5)
        cz = R.uniform(z0 + d * 0.5 + 0.5, z1 - d * 0.5 - 0.5)
        if R.random() < 0.3:
            mb.cyl((cx, top, cz), (cx, top + h + 0.8, cz), min(w, d) * 0.45, (0, 0, 1, 1), (seed + 0.3, tint, 0.0), ROOF, 8, caps=True)
        else:
            mb.box((cx - w * 0.5, top, cz - d * 0.5), (cx + w * 0.5, top + h, cz + d * 0.5), (0, 0, 1, 1), (seed + 0.5, tint, 0.0), ROOF, "xXzZY")
    # feu d'obstacle rouge, enseigne de toit sur certains
    mb.box((x0 + 0.3, top, z0 + 0.3), (x0 + 0.6, top + 0.3, z0 + 0.6), (0, 0, 1, 1), (seed, 0.0, 0.0), SIGN, "xXzZY", anim=(0.5, seed))
    if R.random() < 0.45:
        ln = min(x1 - x0, z1 - z0) * R.uniform(0.4, 0.8)
        hh = R.uniform(1.2, 2.6)
        if R.random() < 0.5:
            cz = z0 + 0.4
            mb.box(((x0 + x1) * 0.5 - ln * 0.5, top + 0.3, cz - 0.08), ((x0 + x1) * 0.5 + ln * 0.5, top + 0.3 + hh, cz + 0.08),
                   (0, 0, 1, 1), (seed, R.uniform(0, 1), 1.0), SIGN, "xXzZY", anim=(0.25 if R.random() < 0.4 else 0.0, seed))
        else:
            cx = x1 - 0.4
            mb.box((cx - 0.08, top + 0.3, (z0 + z1) * 0.5 - ln * 0.5), (cx + 0.08, top + 0.3 + hh, (z0 + z1) * 0.5 + ln * 0.5),
                   (0, 0, 1, 1), (seed, R.uniform(0, 1), 1.0), SIGN, "xXzZY", anim=(0.25 if R.random() < 0.4 else 0.0, seed))
    # enseignes verticales accrochées aux façades qui regardent les avenues
    if R.random() < 0.6:
        side = int(R.integers(0, 4))
        hh = R.uniform(5.0, 12.0)
        ya = top - R.uniform(2.0, 6.0) - hh
        if side == 0:
            x = R.uniform(x0 + 1, x1 - 1)
            mb.box((x - 0.12, ya, z1), (x + 0.12, ya + hh, z1 + 1.2), (0, 0, 1, 1), (seed, R.uniform(0, 1), 1.0), SIGN, "xXZyY", anim=(0.25, seed))
        elif side == 1:
            x = R.uniform(x0 + 1, x1 - 1)
            mb.box((x - 0.12, ya, z0 - 1.2), (x + 0.12, ya + hh, z0), (0, 0, 1, 1), (seed, R.uniform(0, 1), 1.0), SIGN, "xXzyY", anim=(0.25, seed))
        elif side == 2:
            z = R.uniform(z0 + 1, z1 - 1)
            mb.box((x0 - 1.2, ya, z - 0.12), (x0, ya + hh, z + 0.12), (0, 0, 1, 1), (seed, R.uniform(0, 1), 1.0), SIGN, "xzZyY", anim=(0.25, seed))
        else:
            z = R.uniform(z0 + 1, z1 - 1)
            mb.box((x1, ya, z - 0.12), (x1 + 1.2, ya + hh, z + 0.12), (0, 0, 1, 1), (seed, R.uniform(0, 1), 1.0), SIGN, "XzZyY", anim=(0.25, seed))


def main():
    mb = MB()
    placed = []
    # immeubles : plus hauts près de notre tour (parallaxe), plus bas au loin
    tries = 0
    while tries < 2600 and len(placed) < 70:
        tries += 1
        x = R.uniform(-75.0, W + 75.0)
        z = R.uniform(-55.0, H + 55.0)
        w, d = R.uniform(7.0, 16.0), R.uniform(7.0, 16.0)
        x0, z0, x1, z1 = x - w * 0.5, z - d * 0.5, x + w * 0.5, z + d * 0.5
        if on_road(x0, z0, x1, z1) or blocked(x0 - 1.0, z0 - 1.0, x1 + 1.0, z1 + 1.0, placed):
            continue
        dist = max(0.0, max(-x1, x0 - W, 0.0) + max(z0 - H, -z1, 0.0) * 0.5)
        top = -R.uniform(4.0, 14.0) - dist * R.uniform(0.15, 0.4) - (R.uniform(0, 10) if R.random() < 0.4 else 0)
        placed.append((x0, z0, x1, z1))
        building(mb, x0, z0, x1, z1, top, float(R.uniform(0.02, 0.98)), float(R.uniform(0, 1)))
    print("  immeubles :", len(placed))
    # sol de la ville et avenues
    S = 160.0
    mb.quad((W * 0.5, STREET_Y - 0.05, H * 0.5), (1, 0, 0), (0, 0, -1), S * 0.5, S * 0.5, (0, 0, S, S), (0.5, 0.0, 0.0), ROOF, normal=(0, 1, 0))
    for (ax, p, a, b, w) in ROADS:
        L = b - a
        if ax == "z":
            mb.quad((p, STREET_Y, (a + b) * 0.5), (0, 0, 1), (1, 0, 0), L * 0.5, w * 0.5, (0, 0, L, 1), (0.3, 0.0, 0.0), ROAD, normal=(0, 1, 0))
        else:
            mb.quad(((a + b) * 0.5, STREET_Y, p), (1, 0, 0), (0, 0, -1), L * 0.5, w * 0.5, (0, 0, L, 1), (0.7, 0.0, 0.0), ROAD, normal=(0, 1, 0))
    print("  triangles :", mb.count())
    write_glb(os.path.join(OUT, "city.glb"), [("city", mb.arrays())])


def taxi():
    """Drone-taxi : cabine arrondie, verrière lumineuse, quatre nacelles de rotor, phares, liseré dessous.
    COLOR.rgb couleur, COLOR.a : 0 carrosserie, 1 lumineux. Avant vers -z."""
    mb = MB()
    body = np.array([0.95, 0.75, 0.2])
    dark = np.array([0.08, 0.08, 0.1])
    uv = (0, 0, 1, 1)
    mb.box((-0.45, -0.18, -0.9), (0.45, 0.22, 0.9), uv, body, 0.0, "xXyYzZ")
    mb.box((-0.4, 0.22, -0.55), (0.4, 0.5, 0.45), uv, dark, 0.0, "xXYzZ")
    # verrière (chaude), phares, feux arrière, liseré
    mb.quad((0.0, 0.36, -0.551), (-1, 0, 0), (0, 1, 0), 0.36, 0.11, uv, (1.0, 0.75, 0.45), 1.0, normal=(0, 0, -1))
    for sx in (-1, 1):
        mb.quad((sx * 0.401, 0.36, -0.05), (0, 0, sx), (0, 1, 0), 0.4, 0.1, uv, (1.0, 0.7, 0.4), 1.0, normal=(sx, 0, 0))
        mb.quad((sx * 0.3, 0.02, -0.901), (-1, 0, 0), (0, 1, 0), 0.1, 0.05, uv, (1.0, 0.95, 0.85), 1.0, normal=(0, 0, -1))
        mb.quad((sx * 0.3, 0.02, 0.901), (1, 0, 0), (0, 1, 0), 0.1, 0.05, uv, (1.0, 0.1, 0.12), 1.0, normal=(0, 0, 1))
    mb.quad((0.0, -0.181, 0.0), (1, 0, 0), (0, 0, 1), 0.42, 0.85, uv, (0.0, 0.85, 0.8), 1.0, normal=(0, -1, 0))
    # nacelles
    for sx in (-1, 1):
        for sz in (-1, 1):
            c = np.array([sx * 0.75, 0.05, sz * 0.7])
            mb.cyl(c - (0, 0.08, 0), c + (0, 0.08, 0), 0.26, uv, dark, 0.0, 10, caps=True)
            mb.box((min(c[0], sx * 0.45), -0.02, c[2] - 0.04), (max(c[0], sx * 0.45), 0.04, c[2] + 0.04), uv, body * 0.7, 0.0, "yYzZ")
            mb.cyl(c + (0, 0.081, 0), c + (0, 0.082, 0), 0.2, uv, (0.6, 0.9, 1.0), 1.0, 10, caps=True)
    print("  taxi :", mb.count(), "triangles")
    write_glb(os.path.join(OUT, "taxi.glb"), [("taxi", mb.arrays())])


if __name__ == "__main__":
    taxi()
    main()
